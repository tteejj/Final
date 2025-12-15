#!/usr/bin/env pwsh
# TestTextInput.ps1 - Test suite for TextInput widget
# Tests all functionality without requiring interactive mode

param(
    [switch]$Verbose
)

Set-StrictMode -Version Latest

$ErrorActionPreference = "Stop"

# Load dependencies
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir/TextInput.ps1"

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

function Test-Constructor {
    Write-Host "`nTest: Constructor" -ForegroundColor Cyan

    $input = [TextInput]::new()

    Assert-Equal 40 $input.Width "Default width should be 40"
    Assert-Equal 3 $input.Height "Default height should be 3"
    Assert-Equal "" $input.Text "Default text should be empty"
    Assert-Equal 500 $input.MaxLength "Default max length should be 500"
    Assert-True $input.CanFocus "Should be focusable"
    Assert-Equal $false $input.IsConfirmed "Should not be confirmed initially"
    Assert-Equal $false $input.IsCancelled "Should not be cancelled initially"
}

function Test-SetText {
    Write-Host "`nTest: SetText" -ForegroundColor Cyan

    $input = [TextInput]::new()

    $input.SetText("Hello World")
    Assert-Equal "Hello World" $input.GetText() "SetText should set the text"

    # Test max length enforcement
    $input.MaxLength = 10
    $input.SetText("This is a very long string")
    Assert-Equal "This is a " $input.GetText() "SetText should truncate to MaxLength"
}

function Test-Clear {
    Write-Host "`nTest: Clear" -ForegroundColor Cyan

    $input = [TextInput]::new()
    $input.SetText("Some text")
    $input.IsConfirmed = $true

    $input.Clear($true)

    Assert-Equal "" $input.GetText() "Clear should empty the text"
    Assert-Equal $false $input.IsConfirmed "Clear should reset IsConfirmed"
    Assert-True $input.HasFocus "Clear with keepFocus=true should maintain focus"
}

function Test-Placeholder {
    Write-Host "`nTest: Placeholder" -ForegroundColor Cyan

    $input = [TextInput]::new()
    $input.Placeholder = "Enter something..."
    $input.SetPosition(0, 0)
    $input.SetSize(40, 3)

    $output = $input.Render()

    Assert-True ($output.Contains("Enter something")) "Render should include placeholder when empty"
}

function Test-Validation {
    Write-Host "`nTest: Validation" -ForegroundColor Cyan

    $input = [TextInput]::new()

    # Test simple boolean validator
    $input.Validator = { param($text) $text.Length -ge 3 }

    $input.SetText("ab")
    Assert-Equal $false $input.IsValid "Text 'ab' should fail validation (min 3 chars)"

    $input.SetText("abc")
    Assert-Equal $true $input.IsValid "Text 'abc' should pass validation"

    # Test hashtable validator with message
    $input.Validator = {
        param($text)
        if ($text.Length -lt 5) {
            return @{ Valid = $false; Message = "Too short" }
        }
        return @{ Valid = $true }
    }

    $input.SetText("abcd")
    Assert-Equal $false $input.IsValid "Text 'abcd' should fail custom validation"
}

function Test-EventCallbacks {
    Write-Host "`nTest: Event Callbacks" -ForegroundColor Cyan

    $input = [TextInput]::new()

    # Test OnTextChanged
    $script:changedText = ""
    $input.OnTextChanged = { param($text) $script:changedText = $text }

    $input.SetText("Test")
    Assert-Equal "Test" $script:changedText "OnTextChanged should be invoked with new text"

    # Test OnConfirmed
    $script:confirmedText = ""
    $input.OnConfirmed = { param($text) $script:confirmedText = $text }

    $input.Validator = { $true }
    $keyEnter = [System.ConsoleKeyInfo]::new(
        [char]13,
        [System.ConsoleKey]::Enter,
        $false, $false, $false
    )
    $input.HandleInput($keyEnter)

    Assert-Equal "Test" $script:confirmedText "OnConfirmed should be invoked on Enter"
    Assert-True $input.IsConfirmed "IsConfirmed should be true after Enter"
}

function Test-Rendering {
    Write-Host "`nTest: Rendering" -ForegroundColor Cyan

    $input = [TextInput]::new()
    $input.SetPosition(0, 0)
    $input.SetSize(40, 3)
    $input.SetText("Hello")

    $output = $input.Render()

    Assert-True ($output.Length -gt 0) "Render should produce output"
    Assert-True ($output.Contains("Hello")) "Render should include text content"
    Assert-True ($output.Contains("`e[")) "Render should include ANSI escape sequences"
}

function Test-KeyboardInput {
    Write-Host "`nTest: Keyboard Input" -ForegroundColor Cyan

    $input = [TextInput]::new()

    # Test Enter key
    $keyEnter = [System.ConsoleKeyInfo]::new(
        [char]13,
        [System.ConsoleKey]::Enter,
        $false, $false, $false
    )
    $handled = $input.HandleInput($keyEnter)
    Assert-True $handled "Enter key should be handled"
    Assert-True $input.IsConfirmed "Enter should set IsConfirmed"

    # Test Escape key
    $input2 = [TextInput]::new()
    $keyEsc = [System.ConsoleKeyInfo]::new(
        [char]27,
        [System.ConsoleKey]::Escape,
        $false, $false, $false
    )
    $handled = $input2.HandleInput($keyEsc)
    Assert-True $handled "Escape key should be handled"
    Assert-True $input2.IsCancelled "Escape should set IsCancelled"
}

function Test-MaxLength {
    Write-Host "`nTest: MaxLength Enforcement" -ForegroundColor Cyan

    $input = [TextInput]::new()
    $input.MaxLength = 5

    $input.SetText("12345")
    Assert-Equal "12345" $input.GetText() "Should accept text at max length"

    $input.SetText("1234567890")
    Assert-Equal "12345" $input.GetText() "Should truncate text exceeding max length"
}

function Test-LabelDisplay {
    Write-Host "`nTest: Label Display" -ForegroundColor Cyan

    $input = [TextInput]::new()
    $input.Label = "Task Name"
    $input.SetPosition(0, 0)
    $input.SetSize(40, 3)

    $output = $input.Render()

    Assert-True ($output.Contains("Task Name")) "Render should include label"
}

function Test-ErrorState {
    Write-Host "`nTest: Error State" -ForegroundColor Cyan

    $input = [TextInput]::new()
    $input.Validator = {
        param($text)
        if ($text.Length -lt 3) {
            return @{ Valid = $false; Message = "Too short!" }
        }
        return @{ Valid = $true }
    }

    $input.SetText("ab")
    $input.SetPosition(0, 0)
    $input.SetSize(40, 3)

    Assert-Equal $false $input.IsValid "Invalid text should set IsValid to false"

    $output = $input.Render()
    Assert-True ($output.Contains("Too short")) "Render should show validation error message"
}

# Run all tests
Write-Host "=====================================" -ForegroundColor White
Write-Host "TextInput Widget Test Suite" -ForegroundColor White
Write-Host "=====================================" -ForegroundColor White

Test-Constructor
Test-SetText
Test-Clear
Test-Placeholder
Test-Validation
Test-EventCallbacks
Test-Rendering
Test-KeyboardInput
Test-MaxLength
Test-LabelDisplay
Test-ErrorState

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