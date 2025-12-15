#!/usr/bin/env pwsh
# Automated TUI Testing Script
# Tests TimeListScreen callback fix and investigates rendering issues

param(
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== PMC TUI Automated Testing ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Verify TimeListScreen has required methods
Write-Host "[Test 1] Checking TimeListScreen methods..." -ForegroundColor Yellow
try {
    # Load dependencies first
    Import-Module "$PSScriptRoot/../Pmc.Strict.psd1" -Force -ErrorAction Stop
    . "$PSScriptRoot/DepsLoader.ps1"
    . "$PSScriptRoot/SpeedTUILoader.ps1"
    . "$PSScriptRoot/base/StandardListScreen.ps1"
    . "$PSScriptRoot/screens/TimeListScreen.ps1"
    
    # Create a minimal container
    . "$PSScriptRoot/ServiceContainer.ps1"
    $container = [ServiceContainer]::new()
    $container.Register('TaskStore', { [TaskStore]::GetInstance() }, $true)
    
    $screen = [TimeListScreen]::new($container)
    
    # Check if methods exist
    $hasOnInlineEditConfirmed = $screen.PSObject.Methods['OnInlineEditConfirmed'] -ne $null
    $hasOnInlineEditCancelled = $screen.PSObject.Methods['OnInlineEditCancelled'] -ne $null
    
    if ($hasOnInlineEditConfirmed -and $hasOnInlineEditCancelled) {
        Write-Host "  ✓ OnInlineEditConfirmed method exists" -ForegroundColor Green
        Write-Host "  ✓ OnInlineEditCancelled method exists" -ForegroundColor Green
        
        # Test that methods can be called without errors
        $screen.OnInlineEditConfirmed(@{test='value'})
        $screen.OnInlineEditCancelled()
        
        Write-Host "  ✓ Methods can be called without errors" -ForegroundColor Green
        Write-Host "  [PASS] TimeListScreen has required callback methods" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Missing required methods" -ForegroundColor Red
        Write-Host "  [FAIL] TimeListScreen missing callback methods" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ✗ Error: $_" -ForegroundColor Red
    if ($Verbose) {
        Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
    }
    Write-Host "  [FAIL] TimeListScreen test failed" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 2: Verify TUI starts without errors
Write-Host "[Test 2] Testing TUI startup..." -ForegroundColor Yellow
try {
    # Start TUI in background and capture output
    $logFile = "/tmp/tui-test-$([DateTime]::Now.ToString('yyyyMMddHHmmss')).log"
    
    # Create a test script that starts TUI and exits immediately
    $testScript = @"
`$ErrorActionPreference = 'Stop'
try {
    # Import the module
    Import-Module '$PSScriptRoot/../Pmc.Strict.psd1' -Force -ErrorAction Stop
    
    # Load TUI components
    . '$PSScriptRoot/Start-PmcTUI.ps1'
    
    # Try to create TimeListScreen
    `$container = [ServiceContainer]::new()
    `$container.Register('TaskStore', { [TaskStore]::GetInstance() }, `$true)
    `$screen = [TimeListScreen]::new(`$container)
    
    Write-Host "SUCCESS: TimeListScreen created without errors"
    exit 0
} catch {
    Write-Host "ERROR: `$_"
    Write-Host `$_.ScriptStackTrace
    exit 1
}
"@
    
    $testScriptPath = "/tmp/tui-startup-test.ps1"
    $testScript | Out-File -FilePath $testScriptPath -Encoding UTF8
    
    $result = & pwsh -File $testScriptPath 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($Verbose) {
        Write-Host "  Output: $result" -ForegroundColor Gray
    }
    
    if ($exitCode -eq 0 -and $result -match "SUCCESS") {
        Write-Host "  ✓ TUI components load successfully" -ForegroundColor Green
        Write-Host "  ✓ TimeListScreen instantiates without errors" -ForegroundColor Green
        Write-Host "  [PASS] TUI startup test passed" -ForegroundColor Green
    } else {
        Write-Host "  ✗ TUI startup failed" -ForegroundColor Red
        Write-Host "  Output: $result" -ForegroundColor Red
        Write-Host "  [FAIL] TUI startup test failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ✗ Error during startup test: $_" -ForegroundColor Red
    Write-Host "  [FAIL] TUI startup test failed" -ForegroundColor Red
    exit 1
} finally {
    # Cleanup
    if (Test-Path $testScriptPath) {
        Remove-Item $testScriptPath -Force
    }
}
Write-Host ""

# Test 3: Check for common rendering issues
Write-Host "[Test 3] Checking for common rendering issues..." -ForegroundColor Yellow
try {
    # Check for ANSI escape sequence issues in source files
    $renderingIssues = @()
    
    # Check key files for potential rendering problems
    $filesToCheck = @(
        "$PSScriptRoot/widgets/TabPanel.ps1"
        "$PSScriptRoot/base/TabbedScreen.ps1"
        "$PSScriptRoot/screens/ProjectInfoScreenV4.ps1"
    )
    
    foreach ($file in $filesToCheck) {
        if (Test-Path $file) {
            $content = Get-Content $file -Raw
            
            # Check for incomplete ANSI sequences
            if ($content -match '\x1b\[(?!\d+[mHJK])') {
                $renderingIssues += "Potential incomplete ANSI sequence in $(Split-Path $file -Leaf)"
            }
        }
    }
    
    if ($renderingIssues.Count -eq 0) {
        Write-Host "  ✓ No obvious ANSI escape sequence issues found" -ForegroundColor Green
        Write-Host "  [PASS] Rendering check passed" -ForegroundColor Green
    } else {
        Write-Host "  ! Found potential issues:" -ForegroundColor Yellow
        foreach ($issue in $renderingIssues) {
            Write-Host "    - $issue" -ForegroundColor Yellow
        }
        Write-Host "  [WARN] Rendering check found potential issues" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ✗ Error during rendering check: $_" -ForegroundColor Red
    Write-Host "  [FAIL] Rendering check failed" -ForegroundColor Red
}
Write-Host ""

# Test 4: Verify TabPanel exists and has required methods
Write-Host "[Test 4] Checking TabPanel widget..." -ForegroundColor Yellow
try {
    . "$PSScriptRoot/widgets/TabPanel.ps1"
    $tabPanel = [TabPanel]::new()
    
    $hasAddTab = $tabPanel.PSObject.Methods['AddTab'] -ne $null
    $hasRenderToEngine = $tabPanel.PSObject.Methods['RenderToEngine'] -ne $null
    
    if ($hasAddTab -and $hasRenderToEngine) {
        Write-Host "  ✓ TabPanel has AddTab method" -ForegroundColor Green
        Write-Host "  ✓ TabPanel has RenderToEngine method" -ForegroundColor Green
        Write-Host "  [PASS] TabPanel widget check passed" -ForegroundColor Green
    } else {
        Write-Host "  ✗ TabPanel missing required methods" -ForegroundColor Red
        Write-Host "  [FAIL] TabPanel widget check failed" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ Error loading TabPanel: $_" -ForegroundColor Red
    Write-Host "  [FAIL] TabPanel widget check failed" -ForegroundColor Red
}
Write-Host ""

# Summary
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "All critical tests passed! ✓" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps for manual testing:" -ForegroundColor Yellow
Write-Host "1. Run: pwsh $PSScriptRoot/Start-PmcTUI.ps1" -ForegroundColor White
Write-Host "2. Navigate to Time Tracking (F10 → Time → Time Tracking)" -ForegroundColor White
Write-Host "3. Press 'a' to add entry - should work without errors" -ForegroundColor White
Write-Host "4. Navigate to Projects → Project List → Select project" -ForegroundColor White
Write-Host "5. Check if tabs are visible at top of screen" -ForegroundColor White
Write-Host ""
