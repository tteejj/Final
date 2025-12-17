# Alignment Verification Tests
# Test the actual positioning logic and field-column matching without full widget dependency chain

BeforeAll {
    $moduleRoot = "/home/teej/ztest/module/Pmc.Strict/consoleui"
    
    # Load theme engine (minimal dependency)
    . "$moduleRoot/helpers/GapBuffer.ps1"
    . "$moduleRoot/src/PmcThemeEngine.ps1"
    
    # Load file contents for analysis
    $script:stdListContent = Get-Content "$moduleRoot/base/StandardListScreen.ps1" -Raw
    $script:inlineEditorContent = Get-Content "$moduleRoot/widgets/InlineEditor.ps1" -Raw
    $script:universalListContent = Get-Content "$moduleRoot/widgets/UniversalList.ps1" -Raw
    $script:cmdLibContent = Get-Content "$moduleRoot/screens/CommandLibraryScreen.ps1" -Raw
}

Describe "StandardListScreen Editor Positioning - THE FIX" {
    It "InlineEditor X = List.X + 2 (to match UniversalList column start)" {
        # This is the critical fix - editor X must be List.X + 2 because:
        # - UniversalList renders columns starting at X + 2 (1 for border, 1 for padding)
        # - InlineEditor must start at the same X position
        $script:stdListContent | Should -Match '\$this\.InlineEditor\.X\s*=\s*\$this\.List\.X\s*\+\s*2'
    }

    It "InlineEditor Width = List.Width - 4 (to match UniversalList column width)" {
        # Editor width must be List.Width - 4 because:
        # - UniversalList uses Width - 4 for content (2 left + 2 right for borders/padding)
        # - InlineEditor must use the same inner width
        $script:stdListContent | Should -Match '\$this\.InlineEditor\.Width\s*=\s*\$this\.List\.Width\s*-\s*4'
    }

    It "InlineEditor Y = List.Y + 3 + relativeIndex (to align with data rows)" {
        # Row Y position: List.Y + 3 (top border + header + separator) + row index
        $script:stdListContent | Should -Match '\$this\.List\.Y\s*\+\s*3\s*\+\s*\$relativeIndex'
    }
}

Describe "InlineEditor Horizontal Field Spacing - THE FIX" {
    It "No extra +6 padding between fields (was causing cumulative misalignment)" {
        # The bug was: $currentX += $fieldWidth + 6
        # This added 6 extra pixels between each field, causing cumulative drift
        $script:inlineEditorContent | Should -Not -Match '\$currentX\s*\+=\s*\$fieldWidth\s*\+\s*6'
    }

    It "Fields advance by exactly fieldWidth (no extra spacing)" {
        # The fix: $currentX += $fieldWidth
        # Fields should advance by exactly their width with no extra padding
        $matches = [regex]::Matches($script:inlineEditorContent, '\$currentX\s*\+=\s*\$fieldWidth\s*[\r\n]')
        $matches.Count | Should -BeGreaterThan 0 -Because "Should have currentX += fieldWidth without extra spacing"
    }
}

Describe "UniversalList Column Start Position" {
    It "Columns render at X + 2" {
        # UniversalList starts column content at X + 2
        # This is the reference point that InlineEditor X must match
        $script:universalListContent | Should -Match '\$this\.X\s*\+\s*2'
    }
}

Describe "CommandLibraryScreen Field-Column Matching - THE FIX" {
    BeforeAll {
        # Parse GetColumns to extract column names
        $getColumnsMatch = [regex]::Match($script:cmdLibContent, 'GetColumns\(\)\s*\{[\s\S]*?return\s*@\(([\s\S]*?)\)\s*\}')
        $columnBlock = $getColumnsMatch.Groups[1].Value
        $script:columnNames = @([regex]::Matches($columnBlock, "Name='([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        
        # Parse GetEditFields - find the return block after "if ($null -eq"
        $editSectionMatch = [regex]::Match($script:cmdLibContent, 'GetEditFields[\s\S]*?return\s*@\(([\s\S]*?)\)\s*\}\s*else')
        $fieldBlock = $editSectionMatch.Groups[1].Value
        $script:fieldNames = @([regex]::Matches($fieldBlock, "Name='([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        
        Write-Host "Columns found: $($script:columnNames -join ', ')"
        Write-Host "Fields found: $($script:fieldNames -join ', ')"
    }

    It "Should have 5 columns defined" {
        $script:columnNames.Count | Should -Be 5 -Because "CommandLibrary has 5 data columns"
    }

    It "Should have 5 edit fields defined (matching column count)" {
        $script:fieldNames.Count | Should -Be 5 -Because "Edit fields must match column count for alignment"
    }

    It "Column 1 'name' matches field 1" {
        $script:columnNames[0] | Should -Be 'name'
        $script:fieldNames[0] | Should -Be 'name'
    }

    It "Column 2 'category' matches field 2" {
        $script:columnNames[1] | Should -Be 'category'
        $script:fieldNames[1] | Should -Be 'category'
    }

    It "Column 3 'usage_count' matches field 3" {
        $script:columnNames[2] | Should -Be 'usage_count'
        $script:fieldNames[2] | Should -Be 'usage_count'
    }

    It "Column 4 'last_used' matches field 4" {
        $script:columnNames[3] | Should -Be 'last_used'
        $script:fieldNames[3] | Should -Be 'last_used'
    }

    It "Column 5 'description' matches field 5" {
        $script:columnNames[4] | Should -Be 'description'
        $script:fieldNames[4] | Should -Be 'description'
    }
}

Describe "Theme Colors for Notes Screen - THE FIX" {
    BeforeAll {
        $script:theme = [PmcThemeEngine]::new()
    }

    It "Background.Widget is defined and visible (not black/transparent)" {
        $color = $script:theme.GetBackgroundInt('Background.Widget', 80, 0)
        $color | Should -BeGreaterThan 0 -Because "Background.Widget was missing causing invisible text areas"
        
        $r = ($color -shr 16) -band 0xFF
        Write-Host "Background.Widget RGB: $r, $(($color -shr 8) -band 0xFF), $($color -band 0xFF)"
    }

    It "Foreground.Primary is defined and light (readable on dark bg)" {
        $color = $script:theme.GetForegroundInt('Foreground.Primary')
        $color | Should -BeGreaterThan 0x808080 -Because "Text must be light on dark background"
        
        $r = ($color -shr 16) -band 0xFF
        Write-Host "Foreground.Primary RGB: $r, $(($color -shr 8) -band 0xFF), $($color -band 0xFF)"
    }

    It "Tab colors are defined (active vs inactive)" {
        $active = $script:theme.GetBackgroundInt('Background.TabActive', 20, 0)
        $inactive = $script:theme.GetBackgroundInt('Background.TabInactive', 20, 0)
        
        $active | Should -Not -Be $inactive -Because "Tabs must be visually distinct"
        Write-Host "TabActive: 0x$($active.ToString('X6')), TabInactive: 0x$($inactive.ToString('X6'))"
    }
}
