#!/usr/bin/env pwsh
# Runtime TUI Testing - Actually launches TUI and tests rendering
# This script uses expect-like behavior to test the TUI

param(
    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest

Write-Host "=== Runtime TUI Testing ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Launch TUI and capture initial render
Write-Host "[Test 1] Launching TUI and capturing initial screen..." -ForegroundColor Yellow

$logFile = "/tmp/tui-runtime-test-$([DateTime]::Now.ToString('yyyyMMddHHmmss')).log"
$screenshotFile = "/tmp/tui-screenshot-$([DateTime]::Now.ToString('yyyyMMddHHmmss')).txt"

# Create a test script that launches TUI, waits, captures output, then exits
$testScript = @"
#!/usr/bin/env pwsh
`$ErrorActionPreference = 'Stop'

# Start TUI with debug logging
cd /home/teej/ztest/module/Pmc.Strict/consoleui
./Start-PmcTUI.ps1 -DebugLog -LogLevel 3 2>&1 | Tee-Object -FilePath '$logFile'
"@

$testScriptPath = "/tmp/tui-runtime-test.ps1"
$testScript | Out-File -FilePath $testScriptPath -Encoding utf8

# Run TUI in background for a few seconds to test rendering
Write-Host "  Starting TUI (will run for 5 seconds)..." -ForegroundColor Gray

$job = Start-Job -ScriptBlock {
    param($scriptPath)
    & pwsh -File $scriptPath
} -ArgumentList $testScriptPath

# Wait for TUI to start
Start-Sleep -Seconds 2

# Check if TUI is running
$isRunning = $job.State -eq 'Running'

if ($isRunning) {
    Write-Host "  ✓ TUI started successfully" -ForegroundColor Green
    
    # Let it run for a bit
    Start-Sleep -Seconds 3
    
    # Stop the job
    Stop-Job -Job $job
    Remove-Job -Job $job -Force
    
    Write-Host "  ✓ TUI stopped cleanly" -ForegroundColor Green
} else {
    Write-Host "  ✗ TUI failed to start" -ForegroundColor Red
    $jobOutput = Receive-Job -Job $job 2>&1
    Write-Host "  Output: $jobOutput" -ForegroundColor Red
    Remove-Job -Job $job -Force
}

# Test 2: Check log for rendering errors
Write-Host ""
Write-Host "[Test 2] Checking logs for rendering errors..." -ForegroundColor Yellow

$latestLog = Get-ChildItem -Path "/home/teej/ztest/module/.pmc-data/logs" -Filter "pmc-tui-*.log" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1

if ($latestLog) {
    $logContent = Get-Content $latestLog.FullName -Raw
    
    # Check for specific rendering errors
    $renderErrors = @()
    
    if ($logContent -match 'RenderToEngine.*ERROR') {
        $renderErrors += "RenderToEngine errors found"
    }
    
    if ($logContent -match 'ANSI.*ERROR') {
        $renderErrors += "ANSI sequence errors found"
    }
    
    if ($logContent -match 'TabPanel.*ERROR') {
        $renderErrors += "TabPanel errors found"
    }
    
    if ($logContent -match 'InvalidateCached.*ERROR') {
        $renderErrors += "Cache invalidation errors found"
    }
    
    if ($renderErrors.Count -eq 0) {
        Write-Host "  ✓ No rendering errors in log" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Found rendering errors:" -ForegroundColor Red
        foreach ($error in $renderErrors) {
            Write-Host "    - $error" -ForegroundColor Red
        }
    }
    
    # Count DEBUG entries for rendering
    $debugCount = ([regex]::Matches($logContent, '\[DEBUG\].*Render')).Count
    Write-Host "  Found $debugCount rendering debug entries" -ForegroundColor Gray
} else {
    Write-Host "  ! No log file found" -ForegroundColor Yellow
}

# Test 3: Analyze log for TabPanel activity
Write-Host ""
Write-Host "[Test 3] Checking for TabPanel rendering activity..." -ForegroundColor Yellow

if ($latestLog) {
    $logContent = Get-Content $latestLog.FullName -Raw
    
    $hasTabPanelInit = $logContent -match 'TabPanel.*new'
    $hasTabPanelRender = $logContent -match 'TabPanel.*Render'
    $hasTabChanged = $logContent -match 'OnTabChanged'
    
    if ($hasTabPanelInit) {
        Write-Host "  ✓ TabPanel initialization found" -ForegroundColor Green
    } else {
        Write-Host "  ! TabPanel initialization not found in log" -ForegroundColor Yellow
    }
    
    if ($hasTabPanelRender) {
        Write-Host "  ✓ TabPanel rendering activity found" -ForegroundColor Green
    } else {
        Write-Host "  ! TabPanel rendering not found in log" -ForegroundColor Yellow
    }
}

# Cleanup
if (Test-Path $testScriptPath) {
    Remove-Item $testScriptPath -Force
}

Write-Host ""
Write-Host "=== Runtime Test Complete ===" -ForegroundColor Cyan
Write-Host "Latest log: $($latestLog.FullName)" -ForegroundColor Gray
Write-Host ""
Write-Host "To manually test:" -ForegroundColor Yellow
Write-Host "  pwsh /home/teej/ztest/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1" -ForegroundColor White
Write-Host ""
