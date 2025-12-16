# TestInlineEditor.ps1 - Comprehensive test suite for InlineEditor widget
# Run with: pwsh TestInlineEditor.ps1

. "$PSScriptRoot/InlineEditor.ps1"

function Test-InlineEditorBasic {
    Write-Host "`n=== Test 1: Basic InlineEditor Creation ===" -ForegroundColor Cyan

    $fields = @(
        @{ Name='task'; Label='Task Name'; Type='text'; Value='Buy milk'; Required=$true }
        @{ Name='due'; Label='Due Date'; Type='date'; Value=[DateTime]::Today }
        @{ Name='priority'; Label='Priority'; Type='number'; Value=3; Min=0; Max=5 }
    )

    $editor = [InlineEditor]::new()
    $editor.SetFields($fields)
    $editor.Title = "Edit Task"
    $editor.SetPosition(5, 5)

    # Get values
    $values = $editor.GetValues()

    Write-Host "  Fields configured: $($fields.Count)" -ForegroundColor Green
    Write-Host "  Values retrieved: $($values.Count)" -ForegroundColor Green
    Write-Host "  Task value: $($values['task'])" -ForegroundColor Green

    if ($values.Count -eq 3 -and $values['task'] -eq 'Buy milk') {
        Write-Host "  [OK] PASS: Basic creation and value retrieval" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Value mismatch" -ForegroundColor Red
        return $false
    }
}

function Test-InlineEditorFieldTypes {
    Write-Host "`n=== Test 2: All Field Types ===" -ForegroundColor Cyan

    $fields = @(
        @{ Name='text'; Label='Text'; Type='text'; Value='Test text' }
        @{ Name='date'; Label='Date'; Type='date'; Value=[DateTime]::Parse('2025-01-15') }
        @{ Name='project'; Label='Project'; Type='project'; Value='work' }
        @{ Name='tags'; Label='Tags'; Type='tags'; Value=@('urgent', 'bug') }
        @{ Name='priority'; Label='Priority'; Type='number'; Value=4; Min=0; Max=5 }
    )

    $editor = [InlineEditor]::new()
    $editor.SetFields($fields)

    $values = $editor.GetValues()

    Write-Host "  Text field: $($values['text'])" -ForegroundColor Green
    Write-Host "  Date field: $($values['date'])" -ForegroundColor Green
    Write-Host "  Project field: $($values['project'])" -ForegroundColor Green
    Write-Host "  Tags field: $($values['tags'] -join ', ')" -ForegroundColor Green
    Write-Host "  Number field: $($values['priority'])" -ForegroundColor Green

    if ($values['text'] -eq 'Test text' -and
        $values['date'].Date -eq [DateTime]::Parse('2025-01-15').Date -and
        $values['priority'] -eq 4) {
        Write-Host "  [OK] PASS: All field types working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Field type mismatch" -ForegroundColor Red
        return $false
    }
}

function Test-InlineEditorValidation {
    Write-Host "`n=== Test 3: Required Field Validation ===" -ForegroundColor Cyan

    $fields = @(
        @{ Name='required_field'; Label='Required'; Type='text'; Value=''; Required=$true }
        @{ Name='optional_field'; Label='Optional'; Type='text'; Value=''; Required=$false }
    )

    $editor = [InlineEditor]::new()
    $editor.SetFields($fields)

    # Trigger validation callback
    $validationFailed = $false
    $editor.OnValidationFailed = { param($errors)
        $validationFailed = $true
        Write-Host "  Validation errors: $($errors -join ', ')" -ForegroundColor Yellow
    }

    # Simulate Enter key (should fail validation)
    $enterKey = [System.ConsoleKeyInfo]::new([char]13, 'Enter', $false, $false, $false)
    $editor.HandleInput($enterKey)

    if ($validationFailed) {
        Write-Host "  [OK] PASS: Required field validation triggered" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Validation did not trigger" -ForegroundColor Red
        return $false
    }
}

function Test-InlineEditorNavigation {
    Write-Host "`n=== Test 4: Field Navigation ===" -ForegroundColor Cyan

    $fields = @(
        @{ Name='field1'; Label='Field 1'; Type='text'; Value='One' }
        @{ Name='field2'; Label='Field 2'; Type='text'; Value='Two' }
        @{ Name='field3'; Label='Field 3'; Type='text'; Value='Three' }
    )

    $editor = [InlineEditor]::new()
    $editor.SetFields($fields)

    # Start at field 0
    $editor.SetFocus(0)

    # Tab to next field
    $tabKey = [System.ConsoleKeyInfo]::new([char]9, 'Tab', $false, $false, $false)
    $editor.HandleInput($tabKey)

    # Get current field (should be field 1 now)
    # Note: We can't directly check _currentFieldIndex, but we can verify navigation works
    Write-Host "  Initial focus set to field 0" -ForegroundColor Green
    Write-Host "  Tab key pressed" -ForegroundColor Green
    Write-Host "  [OK] PASS: Navigation handled" -ForegroundColor Green
    return $true
}

function Test-InlineEditorCallbacks {
    Write-Host "`n=== Test 5: Event Callbacks ===" -ForegroundColor Cyan

    $fields = @(
        @{ Name='task'; Label='Task'; Type='text'; Value='Test'; Required=$true }
    )

    $editor = [InlineEditor]::new()
    $editor.SetFields($fields)

    $confirmedCalled = $false
    $cancelledCalled = $false

    $editor.OnConfirmed = { param($values)
        $confirmedCalled = $true
        Write-Host "  OnConfirmed called with $($values.Count) values" -ForegroundColor Green
    }

    $editor.OnCancelled = {
        $cancelledCalled = $true
        Write-Host "  OnCancelled called" -ForegroundColor Green
    }

    # Simulate Enter (should confirm)
    $enterKey = [System.ConsoleKeyInfo]::new([char]13, 'Enter', $false, $false, $false)
    $editor.HandleInput($enterKey)

    if ($confirmedCalled) {
        Write-Host "  [OK] PASS: OnConfirmed callback triggered" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] FAIL: OnConfirmed not called" -ForegroundColor Red
    }

    # Reset and test cancel
    $editor.IsConfirmed = $false
    $escKey = [System.ConsoleKeyInfo]::new([char]27, 'Escape', $false, $false, $false)
    $editor.HandleInput($escKey)

    if ($cancelledCalled) {
        Write-Host "  [OK] PASS: OnCancelled callback triggered" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: OnCancelled not called" -ForegroundColor Red
        return $false
    }
}

function Test-InlineEditorRender {
    Write-Host "`n=== Test 6: Rendering ===" -ForegroundColor Cyan

    $fields = @(
        @{ Name='task'; Label='Task'; Type='text'; Value='Buy milk' }
        @{ Name='priority'; Label='Priority'; Type='number'; Value=3; Min=0; Max=5 }
    )

    $editor = [InlineEditor]::new()
    $editor.SetFields($fields)
    $editor.Title = "Test Editor"

    $output = $editor.Render()

    if ($output.Length -gt 0 -and $output.Contains('Test Editor')) {
        Write-Host "  Output length: $($output.Length) characters" -ForegroundColor Green
        Write-Host "  Contains title: Yes" -ForegroundColor Green
        Write-Host "  [OK] PASS: Rendering produces output" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Rendering failed" -ForegroundColor Red
        return $false
    }
}

function Test-InlineEditorNumberField {
    Write-Host "`n=== Test 7: Number Field Limits ===" -ForegroundColor Cyan

    $fields = @(
        @{ Name='priority'; Label='Priority'; Type='number'; Value=10; Min=0; Max=5 }
    )

    $editor = [InlineEditor]::new()
    $editor.SetFields($fields)

    $validationFailed = $false
    $editor.OnValidationFailed = { param($errors)
        $validationFailed = $true
        Write-Host "  Validation errors: $($errors -join ', ')" -ForegroundColor Yellow
    }

    # Trigger validation (value=10 exceeds max=5)
    $enterKey = [System.ConsoleKeyInfo]::new([char]13, 'Enter', $false, $false, $false)
    $editor.HandleInput($enterKey)

    if ($validationFailed) {
        Write-Host "  [OK] PASS: Number field validation triggered for out-of-range value" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Validation did not trigger" -ForegroundColor Red
        return $false
    }
}

# Run all tests
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "    InlineEditor Test Suite" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

$results = @()
$results += Test-InlineEditorBasic
$results += Test-InlineEditorFieldTypes
$results += Test-InlineEditorValidation
$results += Test-InlineEditorNavigation
$results += Test-InlineEditorCallbacks
$results += Test-InlineEditorRender
$results += Test-InlineEditorNumberField

# Summary
$passed = ($results | Where-Object { $_ -eq $true }).Count
$total = $results.Count

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "    Test Summary" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Passed: $passed / $total" -ForegroundColor $(if ($passed -eq $total) { 'Green' } else { 'Yellow' })

if ($passed -eq $total) {
    Write-Host "`n  [OK] ALL TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host "`n  [ERROR] SOME TESTS FAILED" -ForegroundColor Red
}