#!/usr/bin/env pwsh
# TestTagEditor.ps1 - Test suite for TagEditor widget
# Tests all functionality without requiring interactive mode

param(
    [switch]$Verbose
)

Set-StrictMode -Version Latest

$ErrorActionPreference = "Stop"

# Load dependencies
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir/TagEditor.ps1"

# Mock Get-PmcData for testing
function Get-PmcData {
    return [PSCustomObject]@{
        tasks = @(
            [PSCustomObject]@{
                text = "Task 1"
                tags = @("work", "urgent", "bug")
            }
            [PSCustomObject]@{
                text = "Task 2"
                tags = @("personal", "urgent")
            }
            [PSCustomObject]@{
                text = "Task 3"
                tags = @("work", "feature", "backend")
            }
        )
        projects = @()
    }
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

function Assert-NotContains {
    param($Collection, $Item, $Message)

    $script:TestsTotal++

    if ($Collection -notcontains $Item) {
        $script:TestsPassed++
        if ($Verbose) {
            Write-Host "  [PASS] $Message" -ForegroundColor Green
        }
    } else {
        $script:TestsFailed++
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        Write-Host "    Collection: $($Collection -join ', ')" -ForegroundColor Yellow
        Write-Host "    Should not contain: '$Item'" -ForegroundColor Yellow
    }
}

function Test-Constructor {
    Write-Host "`nTest: Constructor" -ForegroundColor Cyan

    $editor = [TagEditor]::new()

    Assert-Equal 60 $editor.Width "Default width should be 60"
    Assert-Equal 5 $editor.Height "Default height should be 5"
    Assert-Equal 10 $editor.MaxTags "Default max tags should be 10"
    Assert-True $editor.CanFocus "Should be focusable"
    Assert-True $editor.AllowNewTags "Should allow new tags by default"
}

function Test-SetTags {
    Write-Host "`nTest: SetTags" -ForegroundColor Cyan

    $editor = [TagEditor]::new()

    $editor.SetTags(@("work", "urgent", "bug"))

    $tags = $editor.GetTags()
    Assert-Equal 3 $tags.Count "Should have 3 tags"
    Assert-Contains $tags "work" "Should contain 'work'"
    Assert-Contains $tags "urgent" "Should contain 'urgent'"
    Assert-Contains $tags "bug" "Should contain 'bug'"
}

function Test-AddTag {
    Write-Host "`nTest: AddTag" -ForegroundColor Cyan

    $editor = [TagEditor]::new()

    $result = $editor.AddTag("work")
    Assert-True $result "Should successfully add tag"

    $tags = $editor.GetTags()
    Assert-Contains $tags "work" "Tags should contain 'work'"

    # Test duplicate
    $result = $editor.AddTag("work")
    Assert-True (-not $result) "Should not add duplicate tag"
    Assert-Equal 1 $tags.Count "Should still have only 1 tag"
}

function Test-RemoveTag {
    Write-Host "`nTest: RemoveTag" -ForegroundColor Cyan

    $editor = [TagEditor]::new()
    $editor.SetTags(@("work", "urgent"))

    $result = $editor.RemoveTag("work")
    Assert-True $result "Should successfully remove tag"

    $tags = $editor.GetTags()
    Assert-NotContains $tags "work" "Tags should not contain 'work'"
    Assert-Contains $tags "urgent" "Tags should still contain 'urgent'"

    # Test removing non-existent tag
    $result = $editor.RemoveTag("nonexistent")
    Assert-True (-not $result) "Should return false for non-existent tag"
}

function Test-ClearTags {
    Write-Host "`nTest: ClearTags" -ForegroundColor Cyan

    $editor = [TagEditor]::new()
    $editor.SetTags(@("work", "urgent", "bug"))

    $editor.ClearTags()

    $tags = $editor.GetTags()
    Assert-Equal 0 $tags.Count "Should have no tags after clear"
}

function Test-MaxTagsLimit {
    Write-Host "`nTest: Max Tags Limit" -ForegroundColor Cyan

    $editor = [TagEditor]::new()
    $editor.MaxTags = 3

    $editor.AddTag("tag1")
    $editor.AddTag("tag2")
    $editor.AddTag("tag3")

    $tags = $editor.GetTags()
    Assert-Equal 3 $tags.Count "Should have 3 tags"

    $result = $editor.AddTag("tag4")
    Assert-True (-not $result) "Should not add tag beyond limit"

    $tags = $editor.GetTags()
    Assert-Equal 3 $tags.Count "Should still have only 3 tags"
}

function Test-EventCallbacks {
    Write-Host "`nTest: Event Callbacks" -ForegroundColor Cyan

    $editor = [TagEditor]::new()

    # Test OnTagsChanged
    $script:changedTags = @()
    $editor.OnTagsChanged = { param($tags) $script:changedTags = $tags }

    $editor.AddTag("work")
    Assert-Equal 1 $script:changedTags.Count "OnTagsChanged should be invoked"
    Assert-Contains $script:changedTags "work" "Changed tags should contain 'work'"

    # Test OnConfirmed
    $script:confirmedTags = @()
    $editor.OnConfirmed = { param($tags) $script:confirmedTags = $tags }

    $keyEnter = [System.ConsoleKeyInfo]::new(
        [char]13,
        [System.ConsoleKey]::Enter,
        $false, $false, $false
    )
    $editor.HandleInput($keyEnter)

    Assert-True ($script:confirmedTags.Count -gt 0) "OnConfirmed should be invoked"
    Assert-True $editor.IsConfirmed "IsConfirmed should be true"
}

function Test-Rendering {
    Write-Host "`nTest: Rendering" -ForegroundColor Cyan

    $editor = [TagEditor]::new()
    $editor.SetPosition(0, 0)
    $editor.SetSize(60, 5)
    $editor.SetTags(@("work", "urgent"))

    $output = $editor.Render()

    Assert-True ($output.Length -gt 0) "Render should produce output"
    Assert-True ($output.Contains("`e[")) "Render should include ANSI escape sequences"
    Assert-True ($output.Contains("[work]")) "Render should include tag chips"
    Assert-True ($output.Contains("[urgent]")) "Render should include tag chips"
}

function Test-EmptyState {
    Write-Host "`nTest: Empty State" -ForegroundColor Cyan

    $editor = [TagEditor]::new()
    $editor.SetPosition(0, 0)
    $editor.SetSize(60, 5)

    $output = $editor.Render()

    Assert-True ($output.Length -gt 0) "Render should work with no tags"
    Assert-True ($output.Contains("type tag")) "Should show hint when empty"
}

function Test-DuplicatePrevention {
    Write-Host "`nTest: Duplicate Prevention" -ForegroundColor Cyan

    $editor = [TagEditor]::new()

    $editor.SetTags(@("work", "work", "urgent", "work"))

    $tags = $editor.GetTags()
    # SetTags should deduplicate
    $workCount = ($tags | Where-Object { $_ -eq "work" }).Count
    Assert-Equal 1 $workCount "Should not have duplicate tags"
}

function Test-LabelCustomization {
    Write-Host "`nTest: Label Customization" -ForegroundColor Cyan

    $editor = [TagEditor]::new()
    $editor.Label = "Task Tags"
    $editor.SetPosition(0, 0)
    $editor.SetSize(60, 5)

    $output = $editor.Render()

    Assert-True ($output.Contains("Task Tags")) "Render should include custom label"
}

function Test-TagCountDisplay {
    Write-Host "`nTest: Tag Count Display" -ForegroundColor Cyan

    $editor = [TagEditor]::new()
    $editor.MaxTags = 5
    $editor.SetTags(@("work", "urgent"))
    $editor.SetPosition(0, 0)
    $editor.SetSize(60, 5)

    $output = $editor.Render()

    Assert-True ($output.Contains("(2/5)")) "Should show tag count (2/5)"
}

function Test-Cancellation {
    Write-Host "`nTest: Cancellation" -ForegroundColor Cyan

    $editor = [TagEditor]::new()

    $script:cancelled = $false
    $editor.OnCancelled = { $script:cancelled = $true }

    $keyEsc = [System.ConsoleKeyInfo]::new(
        [char]27,
        [System.ConsoleKey]::Escape,
        $false, $false, $false
    )

    $editor.HandleInput($keyEsc)

    Assert-True $script:cancelled "OnCancelled should be invoked"
    Assert-True $editor.IsCancelled "IsCancelled should be true"
}

function Test-WhitespaceHandling {
    Write-Host "`nTest: Whitespace Handling" -ForegroundColor Cyan

    $editor = [TagEditor]::new()

    # SetTags should trim whitespace
    $editor.SetTags(@("  work  ", " urgent", "bug  "))

    $tags = $editor.GetTags()
    Assert-Contains $tags "work" "Should trim leading/trailing spaces"
    Assert-Contains $tags "urgent" "Should trim leading/trailing spaces"
    Assert-Contains $tags "bug" "Should trim leading/trailing spaces"

    # Check that we don't have padded versions
    Assert-NotContains $tags "  work  " "Should not contain padded version"
}

function Test-GetTags {
    Write-Host "`nTest: GetTags" -ForegroundColor Cyan

    $editor = [TagEditor]::new()
    $editor.SetTags(@("work", "urgent", "bug"))

    $tags = $editor.GetTags()

    Assert-True ($tags -is [array]) "GetTags should return an array"
    Assert-Equal 3 $tags.Count "Should return correct count"
}

# Run all tests
Write-Host "=====================================" -ForegroundColor White
Write-Host "TagEditor Widget Test Suite" -ForegroundColor White
Write-Host "=====================================" -ForegroundColor White

Test-Constructor
Test-SetTags
Test-AddTag
Test-RemoveTag
Test-ClearTags
Test-MaxTagsLimit
Test-EventCallbacks
Test-Rendering
Test-EmptyState
Test-DuplicatePrevention
Test-LabelCustomization
Test-TagCountDisplay
Test-Cancellation
Test-WhitespaceHandling
Test-GetTags

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