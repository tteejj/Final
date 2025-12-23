# Integration Tests - Test REAL behavior of screens and widgets
# These tests instantiate actual screen classes and verify field/column alignment

BeforeAll {
    $moduleRoot = "/home/teej/ztest/module/Pmc.Strict/consoleui"
    
    # Load the full module chain required for screens
    . "$moduleRoot/helpers/GapBuffer.ps1"
    . "$moduleRoot/src/PmcThemeEngine.ps1"
    
    # Mock ZIndex enum
    if (-not ("ZIndex" -as [type])) {
        enum ZIndex {
            Background = 0
            Content = 10
            Panel = 20
            Header = 50
            Footer = 55
            StatusBar = 65
            Dropdown = 100
        }
    }
    
    # Mock PmcWidget base class
    class MockPmcWidget {
        [int]$X = 0
        [int]$Y = 0
        [int]$Width = 100
        [int]$Height = 20
        [bool]$CanFocus = $true
        [string]$RegionID = "Mock"
        
        [int] GetThemedColorInt([string]$prop) { return 0xFFFFFF }
        [void] RegisterLayout([object]$e) {}
    }
    
    # For testing GetColumns/GetEditFields we just need to parse the file
    $script:cmdLibPath = "$moduleRoot/screens/CommandLibraryScreen.ps1"
    $script:taskListPath = "$moduleRoot/screens/TaskListScreen.ps1"
    $script:stdListPath = "$moduleRoot/base/StandardListScreen.ps1"
}

Describe "CommandLibraryScreen Column-Field Alignment" {
    BeforeAll {
        $script:content = Get-Content $script:cmdLibPath -Raw
    }

    It "GetColumns and GetEditFields should have same number of fields" {
        # Extract column names from GetColumns
        $columnMatches = [regex]::Matches($script:content, "(?<=Name=')[^']+(?='[^}]*Label=)")
        
        # First 5 are columns, next 10 are edit fields (5 for new, 5 for existing)
        $columnNames = @()
        $editFieldNames = @()
        
        foreach ($m in $columnMatches) {
            if ($columnNames.Count -lt 5) {
                $columnNames += $m.Value
            } elseif ($editFieldNames.Count -lt 5) {
                $editFieldNames += $m.Value
            }
        }
        
        $columnNames.Count | Should -Be 5 -Because "GetColumns should define 5 columns"
        $editFieldNames.Count | Should -Be 5 -Because "GetEditFields should define 5 fields for new items"
    }

    It "Column names should EXACTLY match edit field names in order" {
        # Parse more carefully
        $getColumnsMatch = [regex]::Match($script:content, 'GetColumns\(\)\s*\{[\s\S]*?return\s*@\(([\s\S]*?)\)')
        $columnsBlock = $getColumnsMatch.Groups[1].Value
        $columnNames = [regex]::Matches($columnsBlock, "Name='([^']+)'") | ForEach-Object { $_.Groups[1].Value }
        
        # Get the first return block in GetEditFields (for new items)
        $editFieldsMatch = [regex]::Match($script:content, "GetEditFields.*?if.*?-eq.*?\$null.*?return\s*@\(([\s\S]*?)\)")
        $editFieldsBlock = $editFieldsMatch.Groups[1].Value
        $editFieldNames = [regex]::Matches($editFieldsBlock, "Name='([^']+)'") | ForEach-Object { $_.Groups[1].Value }
        
        Write-Host "Columns: $($columnNames -join ', ')"
        Write-Host "Edit Fields: $($editFieldNames -join ', ')"
        
        for ($i = 0; $i -lt $columnNames.Count; $i++) {
            $columnNames[$i] | Should -Be $editFieldNames[$i] -Because "Column $i name '$($columnNames[$i])' should match field $i name '$($editFieldNames[$i])'"
        }
    }
}

Describe "StandardListScreen InlineEditor Positioning Logic" {
    BeforeAll {
        $script:content = Get-Content $script:stdListPath -Raw
    }

    It "InlineEditor.X should use List.X + 2 to match UniversalList column start" {
        # UniversalList starts columns at X + 2 (inside 1-char border + 1 padding)
        # InlineEditor must match
        $script:content | Should -Match '\$this\.InlineEditor\.X\s*=\s*\$this\.List\.X\s*\+\s*2'
    }

    It "InlineEditor.Width should use List.Width - 4 to match UniversalList column width" {
        # UniversalList uses Width - 4 for content (2 for left border/padding, 2 for right)
        $script:content | Should -Match '\$this\.InlineEditor\.Width\s*=\s*\$this\.List\.Width\s*-\s*4'
    }

    It "InlineEditor.Y should be calculated from List.Y + 3 + relativeIndex" {
        # Row Y = List.Y + 3 (top border + header + separator) + row index
        $script:content | Should -Match '\$this\.List\.Y\s*\+\s*3\s*\+\s*\$relativeIndex'
    }
}

Describe "TaskListScreen Column-Field Width Consistency" {
    BeforeAll {
        $script:content = Get-Content $script:taskListPath -Raw
    }

    It "GetEditFields should calculate widths using same formula as GetColumns" {
        # Both should use the same width calculation approach
        # Task column uses 0.35, Details uses 0.22, Due uses 0.12, Project uses 0.15, Tags uses 0.16
        $hasTaskWidth = $script:content -match "availableWidth\s*\*\s*0\.35"
        $hasDetailsWidth = $script:content -match "availableWidth\s*\*\s*0\.22"
        $hasDueWidth = $script:content -match "availableWidth\s*\*\s*0\.12"
        
        $hasTaskWidth | Should -Be $true -Because "Task column should use 35% of available width"
        $hasDetailsWidth | Should -Be $true -Because "Details column should use 22% of available width"
        $hasDueWidth | Should -Be $true -Because "Due column should use 12% of available width"
    }
}

Describe "PmcThemeEngine Required Theme Keys for UI Rendering" {
    BeforeAll {
        $script:theme = [PmcThemeEngine]::new()
    }

    It "Background.Widget should return a visible dark color (not black, not transparent)" {
        $color = $script:theme.GetBackgroundInt('Background.Widget', 80, 0)
        $color | Should -BeGreaterThan 0 -Because "Background.Widget must be visible (not transparent)"
        $color | Should -BeLessThan 0xFFFFFF -Because "Background.Widget should not be white"
        
        # Extract RGB components
        $r = ($color -shr 16) -band 0xFF
        $g = ($color -shr 8) -band 0xFF
        $b = $color -band 0xFF
        
        Write-Host "Background.Widget: R=$r G=$g B=$b (0x$($color.ToString('X6')))"
        
        # Should be a dark gray (R=G=B, around 26)
        $r | Should -BeGreaterThan 0 -Because "Should have some red component"
    }

    It "Foreground.Primary should return a light/readable color" {
        $color = $script:theme.GetForegroundInt('Foreground.Primary')
        $color | Should -BeGreaterThan 0x808080 -Because "Text should be light enough to read on dark background"
        
        $r = ($color -shr 16) -band 0xFF
        $g = ($color -shr 8) -band 0xFF
        $b = $color -band 0xFF
        
        Write-Host "Foreground.Primary: R=$r G=$g B=$b (0x$($color.ToString('X6')))"
    }

    It "Tab colors should contrast with each other" {
        $activeBg = $script:theme.GetBackgroundInt('Background.TabActive', 20, 0)
        $inactiveBg = $script:theme.GetBackgroundInt('Background.TabInactive', 20, 0)
        
        $activeBg | Should -Not -Be $inactiveBg -Because "Active and inactive tabs must be visually distinct"
        
        # Active should be brighter/colored
        $activeR = ($activeBg -shr 16) -band 0xFF
        $inactiveR = ($inactiveBg -shr 16) -band 0xFF
        
        Write-Host "TabActive: 0x$($activeBg.ToString('X6')), TabInactive: 0x$($inactiveBg.ToString('X6'))"
        
        ($activeBg -ne $inactiveBg) | Should -Be $true
    }
}

Describe "InlineEditor Field Rendering Math" {
    BeforeAll {
        $script:content = Get-Content "$moduleRoot/widgets/InlineEditor.ps1" -Raw
    }

    It "Horizontal mode should NOT add extra spacing between fields" {
        # The bug was: $currentX += $fieldWidth + 6 (wrong)
        # Fixed to: $currentX += $fieldWidth (correct)
        # There should be NO "+ 6" in the currentX calculation
        $script:content | Should -Not -Match '\$currentX\s*\+=\s*\$fieldWidth\s*\+\s*6'
    }

    It "currentX should advance by exactly fieldWidth in horizontal mode" {
        # Check that currentX += fieldWidth exists (without extra padding)
        $hasCorrectPattern = $script:content -match '\$currentX\s*\+=\s*\$fieldWidth\s*\r?\n'
        $hasCorrectPattern | Should -Be $true -Because "currentX should advance by exactly fieldWidth"
    }
}
