#!/usr/bin/env pwsh
# TestDatePicker.ps1 - Comprehensive test for DatePicker widget
#
# This script demonstrates and tests all DatePicker functionality:
# 1. Text mode smart date parsing
# 2. Calendar mode navigation
# 3. Mode switching
# 4. Event callbacks
# 5. Theme integration
# 6. Edge cases (leap years, month boundaries)

using namespace System

# Load DatePicker
. "$PSScriptRoot/DatePicker.ps1"

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Yellow
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = ""
    )

    $status = $(if ($Passed) { "[PASS]" } else { "[FAIL]" })
    $color = $(if ($Passed) { "Green" } else { "Red" })

    Write-Host "$status $TestName" -ForegroundColor $color
    if ($Details) {
        Write-Host "       $Details" -ForegroundColor Gray
    }
}

# === Test 1: Date Parsing ===
Write-TestHeader "Test 1: Smart Date Parsing"

$picker = [DatePicker]::new()

# Test cases for date parsing
$testCases = @(
    @{ Input = "today"; Expected = [DateTime]::Today; Name = "today" }
    @{ Input = "tomorrow"; Expected = [DateTime]::Today.AddDays(1); Name = "tomorrow" }
    @{ Input = "+7"; Expected = [DateTime]::Today.AddDays(7); Name = "+7 days" }
    @{ Input = "-3"; Expected = [DateTime]::Today.AddDays(-3); Name = "-3 days" }
    @{ Input = "2025-03-15"; Expected = [DateTime]::new(2025, 3, 15); Name = "ISO date 2025-03-15" }
)

foreach ($testCase in $testCases) {
    $picker._textInput = $testCase.Input
    $result = $picker._ParseTextInput()

    if ($result) {
        $passed = ($result.Date -eq $testCase.Expected.Date)
        $details = "Input: '$($testCase.Input)' -> Result: $($result.ToString('yyyy-MM-dd'))"
        Write-TestResult $testCase.Name $passed $details
    } else {
        Write-TestResult $testCase.Name $false "Failed to parse: $($testCase.Input)"
    }
}

# Test day of week parsing
Write-Host ""
Write-Host "Day of Week Parsing:" -ForegroundColor Cyan

$dayTests = @("monday", "mon", "tuesday", "tue", "friday", "fri", "next friday")
foreach ($dayTest in $dayTests) {
    $picker._textInput = $dayTest
    $result = $picker._ParseTextInput()

    if ($result) {
        Write-TestResult "Parse '$dayTest'" $true "Result: $($result.ToString('yyyy-MM-dd (ddd)'))"
    } else {
        Write-TestResult "Parse '$dayTest'" $false "Failed to parse"
    }
}

# Test month/day parsing
Write-Host ""
Write-Host "Month/Day Parsing:" -ForegroundColor Cyan

$monthTests = @("jan 15", "march 3", "dec 25")
foreach ($monthTest in $monthTests) {
    $picker._textInput = $monthTest
    $result = $picker._ParseTextInput()

    if ($result) {
        Write-TestResult "Parse '$monthTest'" $true "Result: $($result.ToString('yyyy-MM-dd'))"
    } else {
        Write-TestResult "Parse '$monthTest'" $false "Failed to parse"
    }
}

# Test end of month
Write-Host ""
$picker._textInput = "eom"
$result = $picker._ParseTextInput()
if ($result) {
    $expected = [DateTime]::new([DateTime]::Today.Year, [DateTime]::Today.Month, [DateTime]::DaysInMonth([DateTime]::Today.Year, [DateTime]::Today.Month))
    $passed = ($result.Date -eq $expected.Date)
    Write-TestResult "Parse 'eom'" $passed "Result: $($result.ToString('yyyy-MM-dd'))"
} else {
    Write-TestResult "Parse 'eom'" $false "Failed to parse"
}

# === Test 2: Invalid Input Handling ===
Write-TestHeader "Test 2: Invalid Input Handling"

$invalidInputs = @("invalid", "2025-13-45", "notadate", "xyz123")
foreach ($invalid in $invalidInputs) {
    $picker._textInput = $invalid
    $picker._errorMessage = ""
    $result = $picker._ParseTextInput()

    $passed = ($result -eq $null -and $picker._errorMessage -ne "")
    Write-TestResult "Reject '$invalid'" $passed "Error: $($picker._errorMessage)"
}

# === Test 3: Calendar Navigation ===
Write-TestHeader "Test 3: Calendar Navigation"

$picker = [DatePicker]::new()
$picker.SetDate([DateTime]::new(2025, 2, 15))  # Feb 15, 2025

# Test arrow navigation
$initialDate = $picker.GetSelectedDate()
$picker._HandleCalendarInput([ConsoleKeyInfo]::new(0, [ConsoleKey]::RightArrow, $false, $false, $false))
$newDate = $picker.GetSelectedDate()
$passed = ($newDate -eq $initialDate.AddDays(1))
Write-TestResult "Right arrow (next day)" $passed "Result: $($newDate.ToString('yyyy-MM-dd'))"

$picker.SetDate([DateTime]::new(2025, 2, 15))
$picker._HandleCalendarInput([ConsoleKeyInfo]::new(0, [ConsoleKey]::LeftArrow, $false, $false, $false))
$newDate = $picker.GetSelectedDate()
$passed = ($newDate.Date -eq $initialDate.AddDays(-1).Date)
Write-TestResult "Left arrow (prev day)" $passed "Result: $($newDate.ToString('yyyy-MM-dd'))"

$picker.SetDate([DateTime]::new(2025, 2, 15))
$picker._HandleCalendarInput([ConsoleKeyInfo]::new(0, [ConsoleKey]::DownArrow, $false, $false, $false))
$newDate = $picker.GetSelectedDate()
$passed = ($newDate.Date -eq $initialDate.AddDays(7).Date)
Write-TestResult "Down arrow (next week)" $passed "Result: $($newDate.ToString('yyyy-MM-dd'))"

$picker.SetDate([DateTime]::new(2025, 2, 15))
$picker._HandleCalendarInput([ConsoleKeyInfo]::new(0, [ConsoleKey]::UpArrow, $false, $false, $false))
$newDate = $picker.GetSelectedDate()
$passed = ($newDate.Date -eq $initialDate.AddDays(-7).Date)
Write-TestResult "Up arrow (prev week)" $passed "Result: $($newDate.ToString('yyyy-MM-dd'))"

# Test Home/End
$picker.SetDate([DateTime]::new(2025, 2, 15))
$picker._HandleCalendarInput([ConsoleKeyInfo]::new(0, [ConsoleKey]::Home, $false, $false, $false))
$newDate = $picker.GetSelectedDate()
$passed = ($newDate.Date -eq [DateTime]::new(2025, 2, 1))
Write-TestResult "Home (start of month)" $passed "Result: $($newDate.ToString('yyyy-MM-dd'))"

$picker.SetDate([DateTime]::new(2025, 2, 15))
$picker._HandleCalendarInput([ConsoleKeyInfo]::new(0, [ConsoleKey]::End, $false, $false, $false))
$newDate = $picker.GetSelectedDate()
$passed = ($newDate.Date -eq [DateTime]::new(2025, 2, 28))
Write-TestResult "DoEnd (end of month)" $passed "Result: $($newDate.ToString('yyyy-MM-dd'))"

# Test PageUp/PageDown
$picker.SetDate([DateTime]::new(2025, 2, 15))
$picker._HandleCalendarInput([ConsoleKeyInfo]::new(0, [ConsoleKey]::PageDown, $false, $false, $false))
$newDate = $picker.GetSelectedDate()
$passed = ($newDate.Date -eq [DateTime]::new(2025, 3, 15))
Write-TestResult "PageDown (next month)" $passed "Result: $($newDate.ToString('yyyy-MM-dd'))"

$picker.SetDate([DateTime]::new(2025, 2, 15))
$picker._HandleCalendarInput([ConsoleKeyInfo]::new(0, [ConsoleKey]::PageUp, $false, $false, $false))
$newDate = $picker.GetSelectedDate()
$passed = ($newDate.Date -eq [DateTime]::new(2025, 1, 15))
Write-TestResult "PageUp (prev month)" $passed "Result: $($newDate.ToString('yyyy-MM-dd'))"

# === Test 4: Edge Cases ===
Write-TestHeader "Test 4: Edge Cases"

# Leap year
$picker = [DatePicker]::new()
$picker.SetDate([DateTime]::new(2024, 2, 29))  # Leap day
$passed = ($picker.GetSelectedDate().Date -eq [DateTime]::new(2024, 2, 29))
Write-TestResult "Leap year Feb 29" $passed "Date: $($picker.GetSelectedDate().ToString('yyyy-MM-dd'))"

# Month boundary navigation
$picker.SetDate([DateTime]::new(2025, 1, 31))
$picker._HandleCalendarInput([ConsoleKeyInfo]::new(0, [ConsoleKey]::RightArrow, $false, $false, $false))
$newDate = $picker.GetSelectedDate()
$passed = ($newDate.Date -eq [DateTime]::new(2025, 2, 1))
Write-TestResult "Month boundary (Jan 31 -> Feb 1)" $passed "Result: $($newDate.ToString('yyyy-MM-dd'))"

# Year boundary
$picker.SetDate([DateTime]::new(2024, 12, 31))
$picker._HandleCalendarInput([ConsoleKeyInfo]::new(0, [ConsoleKey]::RightArrow, $false, $false, $false))
$newDate = $picker.GetSelectedDate()
$passed = ($newDate.Date -eq [DateTime]::new(2025, 1, 1))
Write-TestResult "Year boundary (2024-12-31 -> 2025-01-01)" $passed "Result: $($newDate.ToString('yyyy-MM-dd'))"

# === Test 5: Event Callbacks ===
Write-TestHeader "Test 5: Event Callbacks"

$eventsFired = @{
    DateChanged = $false
    Confirmed = $false
    Cancelled = $false
}

$picker = [DatePicker]::new()
$picker.OnDateChanged = { param($date) $eventsFired.DateChanged = $true }
$picker.OnConfirmed = { param($date) $eventsFired.Confirmed = $true }
$picker.OnCancelled = { $eventsFired.Cancelled = $true }

# Test OnDateChanged
$picker.SetDate([DateTime]::new(2025, 3, 15))
Write-TestResult "OnDateChanged callback" $eventsFired.DateChanged "Event fired: $($eventsFired.DateChanged)"

# Test OnConfirmed
$eventsFired.Confirmed = $false
$picker._isCalendarMode = $true
$picker.HandleInput([ConsoleKeyInfo]::new("`r", [ConsoleKey]::Enter, $false, $false, $false))
Write-TestResult "OnConfirmed callback" $eventsFired.Confirmed "Event fired: $($eventsFired.Confirmed)"

# Test OnCancelled
$eventsFired.Cancelled = $false
$picker.HandleInput([ConsoleKeyInfo]::new("`e", [ConsoleKey]::Escape, $false, $false, $false))
Write-TestResult "OnCancelled callback" $eventsFired.Cancelled "Event fired: $($eventsFired.Cancelled)"

# === Test 6: Mode Switching ===
Write-TestHeader "Test 6: Mode Switching"

$picker = [DatePicker]::new()
$initialMode = $picker._isCalendarMode
$picker._ToggleMode()
$newMode = $picker._isCalendarMode

Write-TestResult "Toggle from text to calendar" ($initialMode -eq $false -and $newMode -eq $true) "Initial: $initialMode, After: $newMode"

$picker._ToggleMode()
$finalMode = $picker._isCalendarMode
Write-TestResult "Toggle back to text" ($finalMode -eq $false) "Final mode: $finalMode"

# === Test 7: Rendering (Visual Test) ===
Write-TestHeader "Test 7: Rendering (Visual Verification)"

Write-Host "Text Mode Render:" -ForegroundColor Cyan
$picker = [DatePicker]::new()
$picker.SetPosition(2, 2)
$picker.SetDate([DateTime]::Today)
$picker._isCalendarMode = $false
$picker._textInput = "tomorrow"

$output = $picker.Render()
Write-Host $output

Write-Host ""
Read-Host "Press Enter to see Calendar Mode"

Write-Host "`e[2J`e[H"  # Clear screen
Write-Host "Calendar Mode Render:" -ForegroundColor Cyan
$picker._isCalendarMode = $true
$picker.SetDate([DateTime]::Today)

$output = $picker.Render()
Write-Host $output

Write-Host ""
Write-Host ""

# === Summary ===
Write-TestHeader "Test Summary"

Write-Host "All automated tests completed. Review results above." -ForegroundColor Green
Write-Host ""
Write-Host "Visual tests displayed above. Verify:" -ForegroundColor Yellow
Write-Host "  1. Text mode shows input field and examples" -ForegroundColor Gray
Write-Host "  2. Calendar mode shows month grid with day names" -ForegroundColor Gray
Write-Host "  3. Selected date is highlighted in calendar" -ForegroundColor Gray
Write-Host "  4. Today's date is highlighted differently" -ForegroundColor Gray
Write-Host "  5. Borders and colors are properly rendered" -ForegroundColor Gray
Write-Host ""

# === Interactive Demo ===
Write-Host "Run Interactive Demo? (y/n): " -NoNewline -ForegroundColor Cyan
$response = Read-Host

if ($response -eq 'y' -or $response -eq 'Y') {
    Write-Host "`e[2J`e[H"  # Clear screen
    Write-Host "Interactive DatePicker Demo" -ForegroundColor Yellow
    Write-Host "Use Tab to switch modes, arrows to navigate, Enter to confirm, Esc to cancel" -ForegroundColor Gray
    Write-Host ""

    $picker = [DatePicker]::new()
    $picker.SetPosition(5, 3)
    $picker.SetDate([DateTime]::Today)
    $picker._textInput = [DateTime]::Today.ToString("yyyy-MM-dd")

    $picker.OnDateChanged = {
        param($date)
        # Silently track
    }

    $picker.OnConfirmed = {
        param($date)
        Write-Host "`e[$([Console]::WindowHeight - 1);0H" -NoNewline
        Write-Host "Confirmed: $($date.ToString('yyyy-MM-dd (dddd)'))" -ForegroundColor Green
    }

    $picker.OnCancelled = {
        Write-Host "`e[$([Console]::WindowHeight - 1);0H" -NoNewline
        Write-Host "Cancelled" -ForegroundColor Red
    }

    while (-not $picker.IsConfirmed -and -not $picker.IsCancelled) {
        # Clear screen
        Write-Host "`e[2J`e[H" -NoNewline

        # Render picker
        $output = $picker.Render()
        Write-Host $output -NoNewline

        # Read input
        $key = [Console]::ReadKey($true)
        $picker.HandleInput($key) | Out-Null
    }

    Write-Host ""
    Write-Host ""

    if ($picker.IsConfirmed) {
        $selected = $picker.GetSelectedDate()
        Write-Host "You selected: $($selected.ToString('yyyy-MM-dd (dddd)'))" -ForegroundColor Green
    } else {
        Write-Host "Cancelled" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "All tests complete!" -ForegroundColor Green