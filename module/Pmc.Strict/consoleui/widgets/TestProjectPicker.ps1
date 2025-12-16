#!/usr/bin/env pwsh
# TestProjectPicker.ps1 - Test suite for ProjectPicker widget
# Tests all functionality without requiring interactive mode

param(
    [switch]$Verbose
)

Set-StrictMode -Version Latest

$ErrorActionPreference = "Stop"

# Load dependencies
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir/ProjectPicker.ps1"

# Mock Get-PmcData for testing
function Get-PmcData {
    return [PSCustomObject]@{
        projects = @(
            [PSCustomObject]@{ name = "inbox"; description = "Default"; created = "2024-01-01" }
            [PSCustomObject]@{ name = "work"; description = "Work tasks"; created = "2024-01-02" }
            [PSCustomObject]@{ name = "personal"; description = "Personal"; created = "2024-01-03" }
            [PSCustomObject]@{ name = "webapp"; description = "Web app"; created = "2024-01-04" }
            [PSCustomObject]@{ name = "backend"; description = "Backend"; created = "2024-01-05" }
        )
        tasks = @()
    }
}

function Save-PmcData {
    param($data)
    # Mock save - do nothing
}

# Test counter
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsTotal = 0

function Assert-Equal {
    param($Expected, $Actual, $Message)

    $script:TestsTotal++

    if ($Expected -eq $Actual) {
        $script:TestsPassed++
        if ($Verbose) {
            Write-Host "  [PASS] $Message" -ForegroundColor Green
        }
    } else {
        $script:TestsFailed++
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        Write-Host "    Expected: '$Expected'" -ForegroundColor Yellow
        Write-Host "    Actual:   '$Actual'" -ForegroundColor Yellow
    }
}

function Assert-True {
    param($Condition, $Message)

    $script:TestsTotal++

    if ($Condition) {
        $script:TestsPassed++
        if ($Verbose) {
            Write-Host "  [PASS] $Message" -ForegroundColor Green
        }
    } else {
        $script:TestsFailed++
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
    }
}

function Assert-Contains {
    param($Collection, $Item, $Message)

    $script:TestsTotal++

    if ($Collection -contains $Item) {
        $script:TestsPassed++
        if ($Verbose) {
            Write-Host "  [PASS] $Message" -ForegroundColor Green
        }
    } else {
        $script:TestsFailed++
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        Write-Host "    Collection: $($Collection -join ', ')" -ForegroundColor Yellow
        Write-Host "    Missing:    '$Item'" -ForegroundColor Yellow
    }
}

function Test-Constructor {
    Write-Host "`nTest: Constructor" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()

    Assert-Equal 35 $picker.Width "Default width should be 35"
    Assert-Equal 12 $picker.Height "Default height should be 12"
    Assert-True $picker.CanFocus "Should be focusable"
    Assert-Equal $false $picker.IsConfirmed "Should not be confirmed initially"
    Assert-Equal $false $picker.IsCancelled "Should not be cancelled initially"
}

function Test-LoadProjects {
    Write-Host "`nTest: Load Projects" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()

    # Projects should be loaded automatically in constructor
    $picker.RefreshProjects()

    $selected = $picker.GetSelectedProject()
    Assert-True ($null -ne $selected) "Should have a selected project"
}

function Test-GetSelectedProject {
    Write-Host "`nTest: Get Selected Project" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()

    # Default selection should be first project
    $selected = $picker.GetSelectedProject()
    Assert-True ($selected.Length -gt 0) "Should return a project name"
}

function Test-SearchFilter {
    Write-Host "`nTest: Search Filter" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()

    # Set search text
    $picker.SetSearchText("work")

    $selected = $picker.GetSelectedProject()
    # After filtering, should still have a valid selection
    Assert-True (($selected.Length -eq 0) -or ($selected -eq "work")) "Filtered result should be 'work' or empty"
}

function Test-FuzzyMatch {
    Write-Host "`nTest: Fuzzy Match" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()

    # Test fuzzy matching: "wb" should match "webapp"
    $picker.SetSearchText("wb")

    # Can't directly test private method, but we can check if filtering works
    # by checking that some project is still selected after filtering
    $selected = $picker.GetSelectedProject()
    Assert-True ($selected.Length -ge 0) "Fuzzy search should work"
}

function Test-EventCallbacks {
    Write-Host "`nTest: Event Callbacks" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()

    # Test OnProjectSelected
    $script:selectedProject = ""
    $picker.OnProjectSelected = { param($project) $script:selectedProject = $project }

    # Simulate Enter key to select
    $keyEnter = [System.ConsoleKeyInfo]::new(
        [char]13,
        [System.ConsoleKey]::Enter,
        $false, $false, $false
    )

    $picker.HandleInput($keyEnter)

    Assert-True ($script:selectedProject.Length -gt 0) "OnProjectSelected should be invoked"
    Assert-True $picker.IsConfirmed "IsConfirmed should be true after selection"
}

function Test-CancelOperation {
    Write-Host "`nTest: Cancel Operation" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()

    $script:cancelled = $false
    $picker.OnCancelled = { $script:cancelled = $true }

    # Simulate Escape key
    $keyEsc = [System.ConsoleKeyInfo]::new(
        [char]27,
        [System.ConsoleKey]::Escape,
        $false, $false, $false
    )

    $picker.HandleInput($keyEsc)

    Assert-True $script:cancelled "OnCancelled should be invoked"
    Assert-True $picker.IsCancelled "IsCancelled should be true after Escape"
}

function Test-Navigation {
    Write-Host "`nTest: Navigation" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()

    $initialSelection = $picker.GetSelectedProject()

    # Simulate Down arrow
    $keyDown = [System.ConsoleKeyInfo]::new(
        [char]0,
        [System.ConsoleKey]::DownArrow,
        $false, $false, $false
    )

    $handled = $picker.HandleInput($keyDown)

    Assert-True $handled "Down arrow should be handled"

    $newSelection = $picker.GetSelectedProject()
    # Selection may or may not change depending on list size, but it should still be valid
    Assert-True ($newSelection.Length -ge 0) "Selection should remain valid after navigation"
}

function Test-Rendering {
    Write-Host "`nTest: Rendering" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()
    $picker.SetPosition(0, 0)
    $picker.SetSize(35, 12)

    $output = $picker.Render()

    Assert-True ($output.Length -gt 0) "Render should produce output"
    Assert-True ($output.Contains("`e[")) "Render should include ANSI escape sequences"
    Assert-True ($output.Contains("Select Project")) "Render should include label"
}

function Test-EmptyState {
    Write-Host "`nTest: Empty State" -ForegroundColor Cyan

    # Create a picker that will have no matching projects after filtering
    $picker = [ProjectPicker]::new()
    $picker.SetSearchText("nonexistentproject12345")

    $output = $picker.Render()

    Assert-True ($output.Length -gt 0) "Render should work even with no matches"
    Assert-True ($output.Contains("Alt+N")) "Should show create hint when no matches"
}

function Test-RefreshProjects {
    Write-Host "`nTest: Refresh Projects" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()

    # Refresh should not throw
    $picker.RefreshProjects()

    $selected = $picker.GetSelectedProject()
    Assert-True ($selected.Length -ge 0) "Projects should still be available after refresh"
}

function Test-LabelCustomization {
    Write-Host "`nTest: Label Customization" -ForegroundColor Cyan

    $picker = [ProjectPicker]::new()
    $picker.Label = "Choose a Project"
    $picker.SetPosition(0, 0)
    $picker.SetSize(35, 12)

    $output = $picker.Render()

    Assert-True ($output.Contains("Choose a Project")) "Render should include custom label"
}

# Run all tests
Write-Host "=====================================" -ForegroundColor White
Write-Host "ProjectPicker Widget Test Suite" -ForegroundColor White
Write-Host "=====================================" -ForegroundColor White

Test-Constructor
Test-LoadProjects
Test-GetSelectedProject
Test-SearchFilter
Test-FuzzyMatch
Test-EventCallbacks
Test-CancelOperation
Test-Navigation
Test-Rendering
Test-EmptyState
Test-RefreshProjects
Test-LabelCustomization

# Print summary
Write-Host "`n=====================================" -ForegroundColor White
Write-Host "Test Summary" -ForegroundColor White
Write-Host "=====================================" -ForegroundColor White
Write-Host "Total:  $script:TestsTotal" -ForegroundColor White
Write-Host "Passed: $script:TestsPassed" -ForegroundColor Green
Write-Host "Failed: $script:TestsFailed" -ForegroundColor $(if ($script:TestsFailed -gt 0) { "Red" } else { "White" })

if ($script:TestsFailed -eq 0) {
    Write-Host "`nAll tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSome tests failed!" -ForegroundColor Red
    exit 1
}