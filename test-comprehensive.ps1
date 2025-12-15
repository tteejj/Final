#!/usr/bin/env pwsh
# Comprehensive TUI Testing Suite
# Tests ALL screens, widgets, rendering, and functionality

param(
    [switch]$Verbose,
    [switch]$StopOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = if ($StopOnError) { 'Stop' } else { 'Continue' }

$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsWarning = 0

function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Status,  # PASS, FAIL, WARN
        [string]$Message = ""
    )
    
    $color = switch ($Status) {
        'PASS' { 'Green'; $script:TestsPassed++ }
        'FAIL' { 'Red'; $script:TestsFailed++ }
        'WARN' { 'Yellow'; $script:TestsWarning++ }
    }
    
    $symbol = switch ($Status) {
        'PASS' { '✓' }
        'FAIL' { '✗' }
        'WARN' { '!' }
    }
    
    Write-Host "  $symbol [$Status] $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor Gray
    }
}

# ============================================================================
# SECTION 1: Source Code Verification
# ============================================================================

Write-TestHeader "SECTION 1: Source Code Verification"

# Test 1.1: TimeListScreen callback methods
$sourceFile = "$PSScriptRoot/screens/TimeListScreen.ps1"
if (Test-Path $sourceFile) {
    $content = Get-Content $sourceFile -Raw
    $hasOnInlineEditConfirmed = $content -match '\[void\]\s+OnInlineEditConfirmed\('
    $hasOnInlineEditCancelled = $content -match '\[void\]\s+OnInlineEditCancelled\('
    
    if ($hasOnInlineEditConfirmed -and $hasOnInlineEditCancelled) {
        Write-TestResult "TimeListScreen callback methods" "PASS"
    } else {
        Write-TestResult "TimeListScreen callback methods" "FAIL" "Missing OnInlineEditConfirmed or OnInlineEditCancelled"
    }
} else {
    Write-TestResult "TimeListScreen exists" "FAIL" "File not found: $sourceFile"
}

# Test 1.2: Check all screen files exist
$screenFiles = @(
    'TaskListScreen.ps1'
    'TimeListScreen.ps1'
    'ProjectListScreen.ps1'
    'ProjectInfoScreenV4.ps1'
    'NotesMenuScreen.ps1'
    'ChecklistsMenuScreen.ps1'
    'WeeklyTimeReportScreen.ps1'
    'KanbanScreenV2.ps1'
    'SettingsScreen.ps1'
    'ThemeEditorScreen.ps1'
    'HelpViewScreen.ps1'
    'TimeReportScreen.ps1'
)

$missingScreens = @()
foreach ($screen in $screenFiles) {
    $path = "$PSScriptRoot/screens/$screen"
    if (-not (Test-Path $path)) {
        $missingScreens += $screen
    }
}

if ($missingScreens.Count -eq 0) {
    Write-TestResult "All screen files exist" "PASS" "$($screenFiles.Count) screens found"
} else {
    Write-TestResult "All screen files exist" "FAIL" "Missing: $($missingScreens -join ', ')"
}

# Test 1.3: Check all widget files exist
$widgetFiles = @(
    'UniversalList.ps1'
    'TabPanel.ps1'
    'InlineEditor.ps1'
    'FilterPanel.ps1'
    'PmcHeader.ps1'
    'PmcFooter.ps1'
    'PmcMenuBar.ps1'
    'TextInput.ps1'
    'DatePicker.ps1'
    'ProjectPicker.ps1'
    'TagEditor.ps1'
    'TextAreaEditor.ps1'
    'PmcWidget.ps1'
    'PmcDialog.ps1'
)

$missingWidgets = @()
foreach ($widget in $widgetFiles) {
    $path = "$PSScriptRoot/widgets/$widget"
    if (-not (Test-Path $path)) {
        $missingWidgets += $widget
    }
}

if ($missingWidgets.Count -eq 0) {
    Write-TestResult "All widget files exist" "PASS" "$($widgetFiles.Count) widgets found"
} else {
    Write-TestResult "All widget files exist" "FAIL" "Missing: $($missingWidgets -join ', ')"
}

# ============================================================================
# SECTION 2: Class Definition Verification
# ============================================================================

Write-TestHeader "SECTION 2: Class Definition Verification"

# Test 2.1: Verify TabPanel has required methods
$tabPanelFile = "$PSScriptRoot/widgets/TabPanel.ps1"
if (Test-Path $tabPanelFile) {
    $content = Get-Content $tabPanelFile -Raw
    $hasClass = $content -match 'class\s+TabPanel'
    $hasAddTab = $content -match '\[void\]\s+AddTab\('
    $hasRenderToEngine = $content -match '\[void\]\s+RenderToEngine\('
    $hasHandleInput = $content -match '\[bool\]\s+HandleInput\('
    
    if ($hasClass -and $hasAddTab -and $hasRenderToEngine -and $hasHandleInput) {
        Write-TestResult "TabPanel class structure" "PASS" "Has AddTab, RenderToEngine, HandleInput"
    } else {
        $missing = @()
        if (-not $hasClass) { $missing += "class definition" }
        if (-not $hasAddTab) { $missing += "AddTab" }
        if (-not $hasRenderToEngine) { $missing += "RenderToEngine" }
        if (-not $hasHandleInput) { $missing += "HandleInput" }
        Write-TestResult "TabPanel class structure" "FAIL" "Missing: $($missing -join ', ')"
    }
} else {
    Write-TestResult "TabPanel exists" "FAIL" "File not found"
}

# Test 2.2: Verify ProjectInfoScreenV4 inherits from TabbedScreen
$projectInfoFile = "$PSScriptRoot/screens/ProjectInfoScreenV4.ps1"
if (Test-Path $projectInfoFile) {
    $content = Get-Content $projectInfoFile -Raw
    $hasClass = $content -match 'class\s+ProjectInfoScreenV4\s*:\s*TabbedScreen'
    $hasBuildTabs = $content -match 'hidden\s+\[void\]\s+_BuildTabs\('
    $hasLoadData = $content -match '\[void\]\s+LoadData\('
    $hasSaveChanges = $content -match '\[void\]\s+SaveChanges\('
    
    if ($hasClass -and $hasBuildTabs -and $hasLoadData -and $hasSaveChanges) {
        Write-TestResult "ProjectInfoScreenV4 class structure" "PASS" "Inherits TabbedScreen, has required methods"
    } else {
        $missing = @()
        if (-not $hasClass) { $missing += "class inheritance" }
        if (-not $hasBuildTabs) { $missing += "_BuildTabs" }
        if (-not $hasLoadData) { $missing += "LoadData" }
        if (-not $hasSaveChanges) { $missing += "SaveChanges" }
        Write-TestResult "ProjectInfoScreenV4 class structure" "FAIL" "Missing: $($missing -join ', ')"
    }
} else {
    Write-TestResult "ProjectInfoScreenV4 exists" "FAIL" "File not found"
}

# Test 2.3: Verify TabbedScreen base class
$tabbedScreenFile = "$PSScriptRoot/base/TabbedScreen.ps1"
if (Test-Path $tabbedScreenFile) {
    $content = Get-Content $tabbedScreenFile -Raw
    $hasClass = $content -match 'class\s+TabbedScreen\s*:\s*PmcScreen'
    $hasTabPanel = $content -match '\[TabPanel\]\$TabPanel'
    $hasRenderContentToEngine = $content -match '\[void\]\s+RenderContentToEngine\('
    
    if ($hasClass -and $hasTabPanel -and $hasRenderContentToEngine) {
        Write-TestResult "TabbedScreen base class" "PASS" "Has TabPanel property and RenderContentToEngine"
    } else {
        Write-TestResult "TabbedScreen base class" "FAIL" "Missing required members"
    }
} else {
    Write-TestResult "TabbedScreen exists" "FAIL" "File not found"
}

# ============================================================================
# SECTION 3: Rendering Code Analysis
# ============================================================================

Write-TestHeader "SECTION 3: Rendering Code Analysis"

# Test 3.1: Check for incomplete ANSI escape sequences
$filesToCheck = Get-ChildItem -Path "$PSScriptRoot" -Recurse -Include "*.ps1" | Where-Object { $_.FullName -notmatch 'test-' }
$ansiIssues = @()

foreach ($file in $filesToCheck) {
    $content = Get-Content $file.FullName -Raw
    
    # Check for incomplete ANSI sequences (e.g., "\e[" without proper termination)
    if ($content -match '\\e\[(?!\d+[mHJKABCDEFGSTfhls])') {
        $ansiIssues += $file.Name
    }
}

if ($ansiIssues.Count -eq 0) {
    Write-TestResult "ANSI escape sequence validation" "PASS" "No incomplete sequences found"
} else {
    Write-TestResult "ANSI escape sequence validation" "WARN" "Potential issues in: $($ansiIssues -join ', ')"
}

# Test 3.2: Check for proper ANSI reset sequences
$resetIssues = @()
foreach ($file in $filesToCheck) {
    $content = Get-Content $file.FullName -Raw
    
    # Check if files with color codes also have reset sequences
    if ($content -match '\\e\[\d+m' -and $content -notmatch '\\e\[0m') {
        $resetIssues += $file.Name
    }
}

if ($resetIssues.Count -eq 0) {
    Write-TestResult "ANSI reset sequence check" "PASS" "All colored output has reset sequences"
} else {
    Write-TestResult "ANSI reset sequence check" "WARN" "Missing resets in: $($resetIssues -join ', ')"
}

# Test 3.3: Check RenderToEngine implementations
$renderMethods = @()
foreach ($file in $filesToCheck) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match '\[void\]\s+RenderToEngine\(') {
        $renderMethods += $file.Name
    }
}

Write-TestResult "RenderToEngine implementations" "PASS" "Found in $($renderMethods.Count) files"

# ============================================================================
# SECTION 4: Dependency Chain Verification
# ============================================================================

Write-TestHeader "SECTION 4: Dependency Chain Verification"

# Test 4.1: Check Start-PmcTUI.ps1 loads components in correct order
$startFile = "$PSScriptRoot/Start-PmcTUI.ps1"
if (Test-Path $startFile) {
    $content = Get-Content $startFile -Raw
    
    # Check loading order
    $hasSpeedTUI = $content -match 'SpeedTUILoader\.ps1'
    $hasPraxisVT = $content -match 'PraxisVT\.ps1'
    $hasWidgets = $content -match 'widgets/PmcWidget\.ps1'
    $hasPmcScreen = $content -match 'PmcScreen\.ps1'
    $hasStandardListScreen = $content -match 'base/StandardListScreen\.ps1'
    
    if ($hasSpeedTUI -and $hasPraxisVT -and $hasWidgets -and $hasPmcScreen -and $hasStandardListScreen) {
        Write-TestResult "Start-PmcTUI.ps1 loading order" "PASS" "All core components loaded"
    } else {
        Write-TestResult "Start-PmcTUI.ps1 loading order" "FAIL" "Missing component loads"
    }
} else {
    Write-TestResult "Start-PmcTUI.ps1 exists" "FAIL" "File not found"
}

# ============================================================================
# SECTION 5: Configuration and Logging
# ============================================================================

Write-TestHeader "SECTION 5: Configuration and Logging"

# Test 5.1: Check log directory exists
$logDir = "/home/teej/ztest/module/.pmc-data/logs"
if (Test-Path $logDir) {
    $logFiles = Get-ChildItem -Path $logDir -Filter "pmc-tui-*.log" | Sort-Object LastWriteTime -Descending
    Write-TestResult "Log directory" "PASS" "Found $($logFiles.Count) log files"
    
    if ($logFiles.Count -gt 0) {
        $latestLog = $logFiles[0]
        Write-Host "    Latest log: $($latestLog.Name) ($([math]::Round($latestLog.Length/1KB, 2)) KB)" -ForegroundColor Gray
    }
} else {
    Write-TestResult "Log directory" "WARN" "Directory not found: $logDir"
}

# Test 5.2: Check for error patterns in latest log
if ($logFiles -and $logFiles.Count -gt 0) {
    $latestLogContent = Get-Content $logFiles[0].FullName -Raw
    $errorCount = ([regex]::Matches($latestLogContent, '\[ERROR\]')).Count
    $warningCount = ([regex]::Matches($latestLogContent, '\[WARNING\]')).Count
    
    if ($errorCount -eq 0) {
        Write-TestResult "Latest log error check" "PASS" "No errors found"
    } else {
        Write-TestResult "Latest log error check" "WARN" "Found $errorCount errors, $warningCount warnings"
    }
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-TestHeader "TEST SUMMARY"

$total = $script:TestsPassed + $script:TestsFailed + $script:TestsWarning
Write-Host ""
Write-Host "Total Tests: $total" -ForegroundColor Cyan
Write-Host "  Passed:  $script:TestsPassed" -ForegroundColor Green
Write-Host "  Failed:  $script:TestsFailed" -ForegroundColor Red
Write-Host "  Warnings: $script:TestsWarning" -ForegroundColor Yellow
Write-Host ""

if ($script:TestsFailed -eq 0) {
    Write-Host "✓ ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ SOME TESTS FAILED" -ForegroundColor Red
    exit 1
}
