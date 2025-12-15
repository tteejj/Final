# TestFilterPanel.ps1 - Comprehensive test suite for FilterPanel widget
# Run with: pwsh TestFilterPanel.ps1

Set-StrictMode -Version Latest

. "$PSScriptRoot/FilterPanel.ps1"

function Test-FilterPanelBasic {
    Write-Host "`n=== Test 1: Basic FilterPanel Creation ===" -ForegroundColor Cyan

    $panel = [FilterPanel]::new()
    $panel.SetPosition(5, 5)

    if ($null -ne $panel) {
        Write-Host "  Panel created successfully" -ForegroundColor Green
        Write-Host "  [OK] PASS: Basic creation" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Panel creation failed" -ForegroundColor Red
        return $false
    }
}

function Test-FilterPanelAddFilter {
    Write-Host "`n=== Test 2: Add Filters ===" -ForegroundColor Cyan

    $panel = [FilterPanel]::new()

    $filter1 = @{ Type='Project'; Op='equals'; Value='work' }
    $filter2 = @{ Type='Priority'; Op='>='; Value=3 }

    $panel.AddDoFilter($filter1)
    $panel.AddDoFilter($filter2)

    $filters = $panel.GetFilters()

    Write-Host "  Filters added: $($filters.Count)" -ForegroundColor Green

    if ($filters.Count -eq 2) {
        Write-Host "  [OK] PASS: Filters added successfully" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Filter count mismatch" -ForegroundColor Red
        return $false
    }
}

function Test-FilterPanelRemoveFilter {
    Write-Host "`n=== Test 3: Remove Filters ===" -ForegroundColor Cyan

    $panel = [FilterPanel]::new()

    $panel.AddDoFilter(@{ Type='Project'; Op='equals'; Value='work' })
    $panel.AddDoFilter(@{ Type='Priority'; Op='>='; Value=3 })
    $panel.AddDoFilter(@{ Type='Status'; Op='equals'; Value='pending' })

    Write-Host "  Initial filter count: $($panel.GetFilters().Count)" -ForegroundColor Green

    $panel.RemoveDoFilter(1)  # Remove second filter

    $filters = $panel.GetFilters()
    Write-Host "  After removal: $($filters.Count)" -ForegroundColor Green

    if ($filters.Count -eq 2) {
        Write-Host "  [OK] PASS: Filter removed successfully" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Filter removal failed" -ForegroundColor Red
        return $false
    }
}

function Test-FilterPanelClearFilters {
    Write-Host "`n=== Test 4: Clear All Filters ===" -ForegroundColor Cyan

    $panel = [FilterPanel]::new()

    $panel.AddDoFilter(@{ Type='Project'; Op='equals'; Value='work' })
    $panel.AddDoFilter(@{ Type='Priority'; Op='>='; Value=3 })

    Write-Host "  Before clear: $($panel.GetFilters().Count) filters" -ForegroundColor Green

    $panel.ClearFilters()

    $filters = $panel.GetFilters()
    Write-Host "  After clear: $($filters.Count) filters" -ForegroundColor Green

    if ($filters.Count -eq 0) {
        Write-Host "  [OK] PASS: All filters cleared" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Filters not cleared" -ForegroundColor Red
        return $false
    }
}

function Test-FilterPanelApplyFilters {
    Write-Host "`n=== Test 5: Apply Filters to Data ===" -ForegroundColor Cyan

    $panel = [FilterPanel]::new()

    # Sample task data
    $tasks = @(
        [PSCustomObject]@{ id=1; text='Task 1'; project='work'; priority=5; status='pending' }
        [PSCustomObject]@{ id=2; text='Task 2'; project='personal'; priority=2; status='pending' }
        [PSCustomObject]@{ id=3; text='Task 3'; project='work'; priority=4; status='completed' }
        [PSCustomObject]@{ id=4; text='Task 4'; project='work'; priority=1; status='pending' }
    )

    # Add filter: Project = work
    $panel.AddDoFilter(@{ Type='Project'; Op='equals'; Value='work' })

    $filtered = $panel.ApplyFilters($tasks)

    Write-Host "  Original tasks: $($tasks.Count)" -ForegroundColor Green
    Write-Host "  Filtered tasks: $($filtered.Count)" -ForegroundColor Green
    Write-Host "  Filtered projects: $($filtered.project -join ', ')" -ForegroundColor Green

    if ($filtered.Count -eq 3 -and ($filtered.project | Where-Object { $_ -eq 'work' }).Count -eq 3) {
        Write-Host "  [OK] PASS: Filter applied correctly" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Filter application failed" -ForegroundColor Red
        return $false
    }
}

function Test-FilterPanelMultipleFilters {
    Write-Host "`n=== Test 6: Multiple Filter Logic (AND) ===" -ForegroundColor Cyan

    $panel = [FilterPanel]::new()

    $tasks = @(
        [PSCustomObject]@{ id=1; text='Task 1'; project='work'; priority=5; status='pending' }
        [PSCustomObject]@{ id=2; text='Task 2'; project='work'; priority=2; status='pending' }
        [PSCustomObject]@{ id=3; text='Task 3'; project='work'; priority=4; status='completed' }
        [PSCustomObject]@{ id=4; text='Task 4'; project='personal'; priority=5; status='pending' }
    )

    # Add filters: Project=work AND Priority>=4
    $panel.AddDoFilter(@{ Type='Project'; Op='equals'; Value='work' })
    $panel.AddDoFilter(@{ Type='Priority'; Op='>='; Value=4 })

    $filtered = $panel.ApplyFilters($tasks)

    Write-Host "  Filters: Project=work AND Priority>=4" -ForegroundColor Yellow
    Write-Host "  Original tasks: $($tasks.Count)" -ForegroundColor Green
    Write-Host "  Filtered tasks: $($filtered.Count)" -ForegroundColor Green

    # Should match tasks 1 and 3
    if ($filtered.Count -eq 2) {
        Write-Host "  [OK] PASS: Multiple filters (AND logic) working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Multiple filter logic failed" -ForegroundColor Red
        return $false
    }
}

function Test-FilterPanelDateFilter {
    Write-Host "`n=== Test 7: Date Filter ===" -ForegroundColor Cyan

    $panel = [FilterPanel]::new()

    $today = [DateTime]::Today
    $tomorrow = $today.AddDays(1)
    $yesterday = $today.AddDays(-1)

    $tasks = @(
        [PSCustomObject]@{ id=1; text='Task 1'; due=$yesterday }
        [PSCustomObject]@{ id=2; text='Task 2'; due=$today }
        [PSCustomObject]@{ id=3; text='Task 3'; due=$tomorrow }
    )

    # Filter: Due date = today
    $panel.AddDoFilter(@{ Type='DueDate'; Op='equals'; Value=$today })

    $filtered = $panel.ApplyFilters($tasks)

    Write-Host "  Tasks with due date = today: $($filtered.Count)" -ForegroundColor Green

    if ($filtered.Count -eq 1 -and $filtered[0].id -eq 2) {
        Write-Host "  [OK] PASS: Date filter working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Date filter failed" -ForegroundColor Red
        return $false
    }
}

function Test-FilterPanelGetFilterString {
    Write-Host "`n=== Test 8: Filter String Generation ===" -ForegroundColor Cyan

    $panel = [FilterPanel]::new()

    $panel.AddDoFilter(@{ Type='Project'; Op='equals'; Value='work' })
    $panel.AddDoFilter(@{ Type='Priority'; Op='>='; Value=3 })

    $filterString = $panel.GetFilterString()

    Write-Host "  Filter string: $filterString" -ForegroundColor Green

    if ($filterString.Contains('Project') -and $filterString.Contains('Priority')) {
        Write-Host "  [OK] PASS: Filter string generated" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Filter string generation failed" -ForegroundColor Red
        return $false
    }
}

function Test-FilterPanelPresets {
    Write-Host "`n=== Test 9: Filter Presets ===" -ForegroundColor Cyan

    $panel = [FilterPanel]::new()

    $panel.AddDoFilter(@{ Type='Project'; Op='equals'; Value='work' })
    $panel.AddDoFilter(@{ Type='Priority'; Op='>='; Value=3 })

    # Get preset
    $preset = $panel.GetFilterPreset()

    Write-Host "  Preset created with $($preset.Filters.Count) filters" -ForegroundColor Green

    # Clear and load preset
    $panel.ClearFilters()
    Write-Host "  Filters cleared: $($panel.GetFilters().Count)" -ForegroundColor Green

    $panel.LoadFilterPreset($preset)
    Write-Host "  Preset loaded: $($panel.GetFilters().Count) filters" -ForegroundColor Green

    if ($panel.GetFilters().Count -eq 2) {
        Write-Host "  [OK] PASS: Preset save/load working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Preset functionality failed" -ForegroundColor Red
        return $false
    }
}

# Run all tests
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "    FilterPanel Test Suite" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

$results = @()
$results += Test-FilterPanelBasic
$results += Test-FilterPanelAddFilter
$results += Test-FilterPanelRemoveFilter
$results += Test-FilterPanelClearFilters
$results += Test-FilterPanelApplyFilters
$results += Test-FilterPanelMultipleFilters
$results += Test-FilterPanelDateFilter
$results += Test-FilterPanelGetFilterString
$results += Test-FilterPanelPresets

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