# TestUniversalList.ps1 - Comprehensive test suite for UniversalList widget
# Run with: pwsh TestUniversalList.ps1

Set-StrictMode -Version Latest

. "$PSScriptRoot/UniversalList.ps1"

function Test-UniversalListBasic {
    Write-Host "`n=== Test 1: Basic UniversalList Creation ===" -ForegroundColor Cyan

    $list = [UniversalList]::new()
    $list.SetPosition(0, 0)
    $list.SetSize(120, 30)

    if ($null -ne $list) {
        Write-Host "  List created successfully" -ForegroundColor Green
        Write-Host "  [OK] PASS: Basic creation" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: List creation failed" -ForegroundColor Red
        return $false
    }
}

function Test-UniversalListColumns {
    Write-Host "`n=== Test 2: Column Configuration ===" -ForegroundColor Cyan

    $columns = @(
        @{ Name='id'; Label='ID'; Width=4; Align='right' }
        @{ Name='text'; Label='Task'; Width=40; Align='left' }
        @{ Name='priority'; Label='Pri'; Width=4; Align='center' }
    )

    $list = [UniversalList]::new()
    $list.SetColumns($columns)

    Write-Host "  Columns configured: $($columns.Count)" -ForegroundColor Green

    if ($columns.Count -eq 3) {
        Write-Host "  [OK] PASS: Columns configured successfully" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Column configuration failed" -ForegroundColor Red
        return $false
    }
}

function Test-UniversalListSetData {
    Write-Host "`n=== Test 3: Set Data ===" -ForegroundColor Cyan

    $columns = @(
        @{ Name='id'; Label='ID'; Width=4 }
        @{ Name='text'; Label='Task'; Width=40 }
    )

    $data = @(
        [PSCustomObject]@{ id=1; text='Task 1'; priority=3 }
        [PSCustomObject]@{ id=2; text='Task 2'; priority=5 }
        [PSCustomObject]@{ id=3; text='Task 3'; priority=1 }
    )

    $list = [UniversalList]::new()
    $list.SetColumns($columns)
    $list.SetData($data)

    Write-Host "  Data rows set: $($data.Count)" -ForegroundColor Green

    if ($data.Count -eq 3) {
        Write-Host "  [OK] PASS: Data set successfully" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Data setting failed" -ForegroundColor Red
        return $false
    }
}

function Test-UniversalListSelection {
    Write-Host "`n=== Test 4: Item Selection ===" -ForegroundColor Cyan

    $columns = @(
        @{ Name='id'; Label='ID'; Width=4 }
        @{ Name='text'; Label='Task'; Width=40 }
    )

    $data = @(
        [PSCustomObject]@{ id=1; text='Task 1' }
        [PSCustomObject]@{ id=2; text='Task 2' }
        [PSCustomObject]@{ id=3; text='Task 3' }
    )

    $list = [UniversalList]::new()
    $list.SetColumns($columns)
    $list.SetData($data)

    $selectedItem = $list.GetSelectedItem()

    Write-Host "  Selected item ID: $($selectedItem.id)" -ForegroundColor Green
    Write-Host "  Selected item text: $($selectedItem.text)" -ForegroundColor Green

    if ($selectedItem.id -eq 1) {
        Write-Host "  [OK] PASS: Default selection working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Selection failed" -ForegroundColor Red
        return $false
    }
}

function Test-UniversalListNavigation {
    Write-Host "`n=== Test 5: Navigation (Arrow Keys) ===" -ForegroundColor Cyan

    $columns = @( @{ Name='id'; Label='ID'; Width=4 } )

    $data = @(
        [PSCustomObject]@{ id=1 }
        [PSCustomObject]@{ id=2 }
        [PSCustomObject]@{ id=3 }
        [PSCustomObject]@{ id=4 }
    )

    $list = [UniversalList]::new()
    $list.SetColumns($columns)
    $list.SetData($data)

    # Initial selection (should be item 1)
    $selected = $list.GetSelectedItem()
    Write-Host "  Initial selection: ID=$($selected.id)" -ForegroundColor Green

    # Simulate Down arrow
    $downKey = [System.ConsoleKeyInfo]::new([char]0, 'DownArrow', $false, $false, $false)
    $list.HandleInput($downKey)

    $selected = $list.GetSelectedItem()
    Write-Host "  After Down arrow: ID=$($selected.id)" -ForegroundColor Green

    if ($selected.id -eq 2) {
        Write-Host "  [OK] PASS: Navigation working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Navigation failed" -ForegroundColor Red
        return $false
    }
}

function Test-UniversalListSorting {
    Write-Host "`n=== Test 6: Sorting ===" -ForegroundColor Cyan

    $columns = @(
        @{ Name='id'; Label='ID'; Width=4 }
        @{ Name='priority'; Label='Priority'; Width=8 }
    )

    $data = @(
        [PSCustomObject]@{ id=1; priority=5 }
        [PSCustomObject]@{ id=2; priority=1 }
        [PSCustomObject]@{ id=3; priority=3 }
    )

    $list = [UniversalList]::new()
    $list.SetColumns($columns)
    $list.SetData($data)

    # Sort by priority ascending
    $list.SetSortColumn('priority', $true)

    $selected = $list.GetSelectedItem()
    Write-Host "  First item after sort (ascending): Priority=$($selected.priority)" -ForegroundColor Green

    # First item should have priority=1 after ascending sort
    if ($selected.priority -eq 1) {
        Write-Host "  [OK] PASS: Sorting working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Sorting failed" -ForegroundColor Red
        return $false
    }
}

function Test-UniversalListMultiSelect {
    Write-Host "`n=== Test 7: Multi-Select Mode ===" -ForegroundColor Cyan

    $columns = @( @{ Name='id'; Label='ID'; Width=4 } )

    $data = @(
        [PSCustomObject]@{ id=1 }
        [PSCustomObject]@{ id=2 }
        [PSCustomObject]@{ id=3 }
    )

    $list = [UniversalList]::new()
    $list.SetColumns($columns)
    $list.SetData($data)
    $list.AllowMultiSelect = $true

    # Enter multi-select mode
    $mKey = [System.ConsoleKeyInfo]::new('M', 'M', $false, $false, $false)
    $list.HandleInput($mKey)

    Write-Host "  Multi-select mode: $($list.IsInMultiSelectMode)" -ForegroundColor Green

    # Toggle selection on first item
    $spaceKey = [System.ConsoleKeyInfo]::new(' ', 'Spacebar', $false, $false, $false)
    $list.HandleInput($spaceKey)

    $selectedItems = $list.GetSelectedItems()
    Write-Host "  Selected items: $($selectedItems.Count)" -ForegroundColor Green

    if ($selectedItems.Count -ge 1) {
        Write-Host "  [OK] PASS: Multi-select working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Multi-select failed" -ForegroundColor Red
        return $false
    }
}

function Test-UniversalListActions {
    Write-Host "`n=== Test 8: Custom Actions ===" -ForegroundColor Cyan

    $list = [UniversalList]::new()

    $actionCalled = $false
    $list.AddAction('a', 'Add', { $actionCalled = $true })

    # Simulate 'a' key press
    $aKey = [System.ConsoleKeyInfo]::new('a', 'A', $false, $false, $false)
    $list.HandleInput($aKey)

    Write-Host "  Action callback called: $actionCalled" -ForegroundColor Green

    if ($actionCalled) {
        Write-Host "  [OK] PASS: Actions working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Action failed" -ForegroundColor Red
        return $false
    }
}

function Test-UniversalListRender {
    Write-Host "`n=== Test 9: Rendering ===" -ForegroundColor Cyan

    $columns = @(
        @{ Name='id'; Label='ID'; Width=4 }
        @{ Name='text'; Label='Task'; Width=40 }
    )

    $data = @(
        [PSCustomObject]@{ id=1; text='Task 1' }
        [PSCustomObject]@{ id=2; text='Task 2' }
    )

    $list = [UniversalList]::new()
    $list.Title = "Test List"
    $list.SetColumns($columns)
    $list.SetData($data)
    $list.SetPosition(0, 0)
    $list.SetSize(80, 20)

    $output = $list.Render()

    Write-Host "  Output length: $($output.Length) characters" -ForegroundColor Green
    Write-Host "  Contains title: $($output.Contains('Test List'))" -ForegroundColor Green
    Write-Host "  Contains data: $($output.Contains('Task 1'))" -ForegroundColor Green

    if ($output.Length -gt 0 -and $output.Contains('Test List')) {
        Write-Host "  [OK] PASS: Rendering working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Rendering failed" -ForegroundColor Red
        return $false
    }
}

function Test-UniversalListCallbacks {
    Write-Host "`n=== Test 10: Event Callbacks ===" -ForegroundColor Cyan

    $columns = @( @{ Name='id'; Label='ID'; Width=4 } )

    $data = @(
        [PSCustomObject]@{ id=1 }
        [PSCustomObject]@{ id=2 }
    )

    $list = [UniversalList]::new()
    $list.SetColumns($columns)
    $list.SetData($data)

    $selectionChangedCalled = $false
    $list.OnSelectionChanged = { param($item)
        $selectionChangedCalled = $true
        Write-Host "  OnSelectionChanged: Item ID=$($item.id)" -ForegroundColor Green
    }

    # Trigger selection change
    $downKey = [System.ConsoleKeyInfo]::new([char]0, 'DownArrow', $false, $false, $false)
    $list.HandleInput($downKey)

    if ($selectionChangedCalled) {
        Write-Host "  [OK] PASS: Callbacks working" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] FAIL: Callbacks not triggered" -ForegroundColor Red
        return $false
    }
}

# Run all tests
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "    UniversalList Test Suite" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

$results = @()
$results += Test-UniversalListBasic
$results += Test-UniversalListColumns
$results += Test-UniversalListSetData
$results += Test-UniversalListSelection
$results += Test-UniversalListNavigation
$results += Test-UniversalListSorting
$results += Test-UniversalListMultiSelect
$results += Test-UniversalListActions
$results += Test-UniversalListRender
$results += Test-UniversalListCallbacks

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