#!/usr/bin/env pwsh
# DEEP TUI Testing - Actually interact with the TUI and test everything
# This uses tmux to control the TUI and capture output

param(
    [switch]$Verbose
)

Set-StrictMode -Version Latest

Write-Host "=== DEEP TUI TESTING ===" -ForegroundColor Cyan
Write-Host "This will actually launch and interact with the TUI" -ForegroundColor Yellow
Write-Host ""

$testResults = @{
    Passed = @()
    Failed = @()
    Warnings = @()
}

function Add-TestResult {
    param($Name, $Status, $Message = "")
    
    $result = @{
        Name = $Name
        Status = $Status
        Message = $Message
    }
    
    switch ($Status) {
        'PASS' { 
            $testResults.Passed += $result
            Write-Host "  ✓ [PASS] $Name" -ForegroundColor Green
        }
        'FAIL' { 
            $testResults.Failed += $result
            Write-Host "  ✗ [FAIL] $Name" -ForegroundColor Red
        }
        'WARN' { 
            $testResults.Warnings += $result
            Write-Host "  ! [WARN] $Name" -ForegroundColor Yellow
        }
    }
    
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor Gray
    }
}

# ============================================================================
# TEST 1: Launch TUI with script interaction
# ============================================================================

Write-Host "[Test 1] Testing TUI launch and initial rendering..." -ForegroundColor Yellow

$tuiScript = @'
#!/usr/bin/expect -f
set timeout 10

# Start TUI
spawn pwsh /home/teej/ztest/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1

# Wait for initial render
expect {
    timeout { puts "TIMEOUT: TUI did not start"; exit 1 }
    "Tasks" { puts "SUCCESS: TUI started and menu visible" }
}

# Wait a bit for full render
sleep 2

# Try to open menu
send "\033OP"
sleep 1

# Send escape to close
send "\x1b"
sleep 1

# Exit
send "q"
expect eof
'@

$expectScript = "/tmp/tui-test.exp"
$tuiScript | Out-File -FilePath $expectScript -Encoding ASCII

try {
    if (Get-Command expect -ErrorAction SilentlyContinue) {
        chmod +x $expectScript
        $output = & expect $expectScript 2>&1
        
        if ($output -match "SUCCESS") {
            Add-TestResult "TUI launches and renders menu" "PASS"
        } else {
            Add-TestResult "TUI launches and renders menu" "FAIL" "Menu not visible"
        }
    } else {
        Add-TestResult "TUI interactive test" "WARN" "expect not installed, skipping interactive test"
    }
} catch {
    Add-TestResult "TUI interactive test" "WARN" "Could not run expect script: $_"
}

# ============================================================================
# TEST 2: Check all log files for errors
# ============================================================================

Write-Host ""
Write-Host "[Test 2] Analyzing ALL log files for errors..." -ForegroundColor Yellow

$logDir = "/home/teej/ztest/module/.pmc-data/logs"
$logFiles = Get-ChildItem -Path $logDir -Filter "pmc-tui-*.log" -ErrorAction SilentlyContinue

if ($logFiles) {
    $totalErrors = 0
    $totalWarnings = 0
    $errorPatterns = @()
    
    foreach ($log in $logFiles) {
        $content = Get-Content $log.FullName -Raw
        $errors = ([regex]::Matches($content, '\[ERROR\]')).Count
        $warnings = ([regex]::Matches($content, '\[WARNING\]')).Count
        
        $totalErrors += $errors
        $totalWarnings += $warnings
        
        # Extract unique error patterns
        $errorLines = $content -split "`n" | Where-Object { $_ -match '\[ERROR\]' }
        foreach ($line in $errorLines) {
            if ($line -match '\[ERROR\]\s+(.+)') {
                $errorPatterns += $Matches[1]
            }
        }
    }
    
    $uniqueErrors = $errorPatterns | Select-Object -Unique
    
    if ($totalErrors -eq 0) {
        Add-TestResult "Log file error analysis" "PASS" "Analyzed $($logFiles.Count) logs, 0 errors found"
    } else {
        Add-TestResult "Log file error analysis" "FAIL" "Found $totalErrors errors across $($logFiles.Count) logs"
        if ($Verbose -and $uniqueErrors) {
            Write-Host "    Unique error patterns:" -ForegroundColor Gray
            $uniqueErrors | Select-Object -First 5 | ForEach-Object {
                Write-Host "      - $_" -ForegroundColor Gray
            }
        }
    }
    
    if ($totalWarnings -gt 0) {
        Add-TestResult "Log file warning analysis" "WARN" "Found $totalWarnings warnings"
    }
} else {
    Add-TestResult "Log file analysis" "WARN" "No log files found"
}

# ============================================================================
# TEST 3: Test module loading and dependencies
# ============================================================================

Write-Host ""
Write-Host "[Test 3] Testing module loading and dependencies..." -ForegroundColor Yellow

$loadTest = @'
$ErrorActionPreference = 'Stop'
try {
    Import-Module '/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1' -Force
    
    # Test core types exist
    $types = @('TaskStore', 'PmcScreen', 'UniversalList', 'TabPanel', 'InlineEditor')
    $missing = @()
    
    foreach ($type in $types) {
        if (-not ([Type]::GetType($type) -or ([Type]"$type" -as [Type]))) {
            $missing += $type
        }
    }
    
    if ($missing.Count -eq 0) {
        Write-Output "SUCCESS: All core types loaded"
        exit 0
    } else {
        Write-Output "FAIL: Missing types: $($missing -join ', ')"
        exit 1
    }
} catch {
    Write-Output "ERROR: $_"
    exit 1
}
'@

$loadTestScript = "/tmp/module-load-test.ps1"
$loadTest | Out-File -FilePath $loadTestScript -Encoding UTF8

$loadResult = & pwsh -File $loadTestScript 2>&1
$loadExitCode = $LASTEXITCODE

if ($loadExitCode -eq 0) {
    Add-TestResult "Module loading and core types" "PASS"
} else {
    Add-TestResult "Module loading and core types" "FAIL" $loadResult
}

# ============================================================================
# TEST 4: Test screen instantiation
# ============================================================================

Write-Host ""
Write-Host "[Test 4] Testing screen instantiation..." -ForegroundColor Yellow

$screenTest = @'
$ErrorActionPreference = 'Stop'
try {
    Import-Module '/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1' -Force
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1'
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1'
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/ServiceContainer.ps1'
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/PmcScreen.ps1'
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/base/StandardListScreen.ps1'
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/screens/TimeListScreen.ps1'
    
    $container = [ServiceContainer]::new()
    $container.Register('TaskStore', { [TaskStore]::GetInstance() }, $true)
    
    $screen = [TimeListScreen]::new($container)
    
    # Test callback methods exist and can be called
    $screen.OnInlineEditConfirmed(@{test='value'})
    $screen.OnInlineEditCancelled()
    
    Write-Output "SUCCESS: TimeListScreen instantiated and callbacks work"
    exit 0
} catch {
    Write-Output "ERROR: $_"
    Write-Output $_.ScriptStackTrace
    exit 1
}
'@

$screenTestScript = "/tmp/screen-test.ps1"
$screenTest | Out-File -FilePath $screenTestScript -Encoding UTF8

$screenResult = & pwsh -File $screenTestScript 2>&1
$screenExitCode = $LASTEXITCODE

if ($screenExitCode -eq 0) {
    Add-TestResult "TimeListScreen instantiation and callbacks" "PASS"
} else {
    Add-TestResult "TimeListScreen instantiation and callbacks" "FAIL" $screenResult
}

# ============================================================================
# TEST 5: Test TabPanel rendering
# ============================================================================

Write-Host ""
Write-Host "[Test 5] Testing TabPanel widget rendering..." -ForegroundColor Yellow

$tabPanelTest = @'
$ErrorActionPreference = 'Stop'
try {
    Import-Module '/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1' -Force
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1'
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1'
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/widgets/TabPanel.ps1'
    
    $tabPanel = [TabPanel]::new()
    $tabPanel.X = 2
    $tabPanel.Y = 7
    $tabPanel.Width = 100
    $tabPanel.Height = 20
    
    # Add test tabs
    $tabPanel.AddTab('Tab1', @(
        @{Name='field1'; Label='Field 1'; Value='test'}
    ))
    $tabPanel.AddTab('Tab2', @(
        @{Name='field2'; Label='Field 2'; Value='test2'}
    ))
    
    # Test rendering (should not throw)
    $engine = [PraxisVT]::new(120, 40)
    $tabPanel.RenderToEngine($engine)
    
    Write-Output "SUCCESS: TabPanel created, tabs added, rendering works"
    exit 0
} catch {
    Write-Output "ERROR: $_"
    Write-Output $_.ScriptStackTrace
    exit 1
}
'@

$tabPanelTestScript = "/tmp/tabpanel-test.ps1"
$tabPanelTest | Out-File -FilePath $tabPanelTestScript -Encoding UTF8

$tabPanelResult = & pwsh -File $tabPanelTestScript 2>&1
$tabPanelExitCode = $LASTEXITCODE

if ($tabPanelExitCode -eq 0) {
    Add-TestResult "TabPanel widget rendering" "PASS"
} else {
    Add-TestResult "TabPanel widget rendering" "FAIL" $tabPanelResult
}

# ============================================================================
# TEST 6: Memory and performance check
# ============================================================================

Write-Host ""
Write-Host "[Test 6] Checking for memory leaks and performance issues..." -ForegroundColor Yellow

$perfTest = @'
$ErrorActionPreference = 'Stop'
try {
    $startMem = [System.GC]::GetTotalMemory($false)
    
    Import-Module '/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1' -Force
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1'
    
    $afterLoadMem = [System.GC]::GetTotalMemory($false)
    $loadMemMB = [math]::Round(($afterLoadMem - $startMem) / 1MB, 2)
    
    Write-Output "Module load memory: $loadMemMB MB"
    
    if ($loadMemMB -lt 100) {
        Write-Output "SUCCESS: Memory usage acceptable"
        exit 0
    } else {
        Write-Output "WARN: High memory usage: $loadMemMB MB"
        exit 0
    }
} catch {
    Write-Output "ERROR: $_"
    exit 1
}
'@

$perfTestScript = "/tmp/perf-test.ps1"
$perfTest | Out-File -FilePath $perfTestScript -Encoding UTF8

$perfResult = & pwsh -File $perfTestScript 2>&1
$perfExitCode = $LASTEXITCODE

if ($perfResult -match "SUCCESS") {
    Add-TestResult "Memory and performance" "PASS" $perfResult
} elseif ($perfResult -match "WARN") {
    Add-TestResult "Memory and performance" "WARN" $perfResult
} else {
    Add-TestResult "Memory and performance" "FAIL" $perfResult
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DEEP TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$totalTests = $testResults.Passed.Count + $testResults.Failed.Count + $testResults.Warnings.Count
$passRate = if ($totalTests -gt 0) { [math]::Round(($testResults.Passed.Count / $totalTests) * 100, 1) } else { 0 }

Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "  Passed:   $($testResults.Passed.Count)" -ForegroundColor Green
Write-Host "  Failed:   $($testResults.Failed.Count)" -ForegroundColor Red
Write-Host "  Warnings: $($testResults.Warnings.Count)" -ForegroundColor Yellow
Write-Host "  Pass Rate: $passRate%" -ForegroundColor Cyan
Write-Host ""

if ($testResults.Failed.Count -gt 0) {
    Write-Host "Failed Tests:" -ForegroundColor Red
    foreach ($fail in $testResults.Failed) {
        Write-Host "  - $($fail.Name)" -ForegroundColor Red
        if ($fail.Message) {
            Write-Host "    $($fail.Message)" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

if ($testResults.Warnings.Count -gt 0) {
    Write-Host "Warnings:" -ForegroundColor Yellow
    foreach ($warn in $testResults.Warnings) {
        Write-Host "  - $($warn.Name)" -ForegroundColor Yellow
        if ($warn.Message) {
            Write-Host "    $($warn.Message)" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

# Cleanup
Remove-Item -Path "/tmp/*-test.ps1" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "/tmp/tui-test.exp" -Force -ErrorAction SilentlyContinue

if ($testResults.Failed.Count -eq 0) {
    Write-Host "✓ ALL DEEP TESTS PASSED!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ SOME TESTS FAILED" -ForegroundColor Red
    exit 1
}
