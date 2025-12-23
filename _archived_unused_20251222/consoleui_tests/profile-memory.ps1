# profile-memory.ps1 - Memory profiling utility for PMC TUI
#
# Analyzes memory usage of TUI components to identify potential leaks
# and optimization opportunities.

param(
    [switch]$Detailed,
    [int]$IterationsForLeakTest = 10
)

Set-StrictMode -Version Latest

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -gt 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -gt 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -gt 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-ProcessMemory {
    $proc = Get-Process -Id $PID
    return @{
        WorkingSet = $proc.WorkingSet64
        PrivateMemory = $proc.PrivateMemorySize64
        VirtualMemory = $proc.VirtualMemorySize64
        GCTotalMemory = [GC]::GetTotalMemory($false)
    }
}

Write-Host "`n=== PMC TUI Memory Profiler ===" -ForegroundColor Cyan
Write-Host ""

# Initial memory snapshot
$initialMem = Get-ProcessMemory
Write-Host "Initial Memory State:" -ForegroundColor Yellow
Write-Host "  Working Set:    $(Format-Bytes $initialMem.WorkingSet)"
Write-Host "  Private Memory: $(Format-Bytes $initialMem.PrivateMemory)"
Write-Host "  GC Heap:        $(Format-Bytes $initialMem.GCTotalMemory)"
Write-Host ""

# Load core TUI components
$scriptDir = $PSScriptRoot
Write-Host "Loading TUI components..." -ForegroundColor Yellow

try {
    # Load helpers
    . "$scriptDir/helpers/TypeNormalization.ps1"
    . "$scriptDir/helpers/Constants.ps1"
    
    # Load ServiceContainer
    . "$scriptDir/ServiceContainer.ps1"
    
    # Mock logging to avoid file I/O
    $global:PmcTuiLogFile = $null
    function global:Write-PmcTuiLog { param([string]$Message, [string]$Level = "INFO") }
    
    $afterLoadMem = Get-ProcessMemory
    Write-Host "After loading helpers:" -ForegroundColor Yellow
    Write-Host "  Working Set:    $(Format-Bytes $afterLoadMem.WorkingSet) (+$(Format-Bytes ($afterLoadMem.WorkingSet - $initialMem.WorkingSet)))"
    Write-Host "  GC Heap:        $(Format-Bytes $afterLoadMem.GCTotalMemory) (+$(Format-Bytes ($afterLoadMem.GCTotalMemory - $initialMem.GCTotalMemory)))"
    Write-Host ""

    # Load TaskStore
    . "$scriptDir/services/TaskStore.ps1"
    
    $afterStoreMem = Get-ProcessMemory
    Write-Host "After loading TaskStore:" -ForegroundColor Yellow
    Write-Host "  Working Set:    $(Format-Bytes $afterStoreMem.WorkingSet) (+$(Format-Bytes ($afterStoreMem.WorkingSet - $afterLoadMem.WorkingSet)))"
    Write-Host "  GC Heap:        $(Format-Bytes $afterStoreMem.GCTotalMemory) (+$(Format-Bytes ($afterStoreMem.GCTotalMemory - $afterLoadMem.GCTotalMemory)))"
    Write-Host ""

    # Test for memory leaks with repeated operations
    Write-Host "Testing for leaks (${IterationsForLeakTest} iterations)..." -ForegroundColor Yellow
    
    # Create test data
    $store = [TaskStore]::GetInstance()
    $store.Initialize()
    
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $beforeLeakTest = [GC]::GetTotalMemory($true)
    
    for ($i = 0; $i -lt $IterationsForLeakTest; $i++) {
        # Create and delete tasks
        $taskId = $store.AddTask(@{ text = "Test task $i"; status = "pending" })
        $store.UpdateTask($taskId, @{ text = "Updated $i" })
        $store.DeleteTask($taskId)
        
        # Create and delete time logs
        $logId = $store.AddTimeLog(@{ date = [DateTime]::Today; minutes = 60 })
        $store.DeleteTimeLog($logId)
    }
    
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $afterLeakTest = [GC]::GetTotalMemory($true)
    
    $leakDelta = $afterLeakTest - $beforeLeakTest
    $leakPerIteration = $leakDelta / $IterationsForLeakTest
    
    Write-Host ""
    Write-Host "Leak Test Results:" -ForegroundColor $(if ($leakPerIteration -gt 10KB) { "Red" } elseif ($leakPerIteration -gt 1KB) { "Yellow" } else { "Green" })
    Write-Host "  Memory before: $(Format-Bytes $beforeLeakTest)"
    Write-Host "  Memory after:  $(Format-Bytes $afterLeakTest)"
    Write-Host "  Delta:         $(Format-Bytes $leakDelta)"
    Write-Host "  Per iteration: $(Format-Bytes $leakPerIteration)"
    
    if ($leakPerIteration -gt 10KB) {
        Write-Host "  Status: POTENTIAL MEMORY LEAK DETECTED" -ForegroundColor Red
    } elseif ($leakPerIteration -gt 1KB) {
        Write-Host "  Status: Minor memory growth (may be normal)" -ForegroundColor Yellow
    } else {
        Write-Host "  Status: No significant leaks detected" -ForegroundColor Green
    }
    
} catch {
    Write-Host "Error during profiling: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
}

Write-Host ""
Write-Host "=== Profiling Complete ===" -ForegroundColor Cyan

# Final summary
$finalMem = Get-ProcessMemory
Write-Host ""
Write-Host "Final Memory Summary:" -ForegroundColor Yellow
Write-Host "  Total Working Set: $(Format-Bytes $finalMem.WorkingSet)"
Write-Host "  Total GC Heap:     $(Format-Bytes $finalMem.GCTotalMemory)"
Write-Host "  Session Growth:    $(Format-Bytes ($finalMem.WorkingSet - $initialMem.WorkingSet))"
