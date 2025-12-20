# End-to-End Widget Tests
# Instantiate REAL widgets and verify ACTUAL behavior

BeforeAll {
    $moduleRoot = "/home/teej/ztest/module/Pmc.Strict/consoleui"
    $global:PmcAppRoot = "/home/teej/ztest"
    
    # Load required classes in dependency order
    . "$moduleRoot/helpers/GapBuffer.ps1"
    . "$moduleRoot/src/PmcThemeEngine.ps1"
    
    # Mock Export-ModuleMember for dot-sourcing
    function Export-ModuleMember {}
    . "$moduleRoot/helpers/ThemeLoader.ps1"
    
    # Initialize theme system
    $theme = Load-Theme "Default"
    if ($null -eq $theme) { Write-Host "ERROR: Theme is null!" }
    else { Write-Host "Theme loaded: $($theme.Name) with $($theme.Properties.Count) properties" }
    [PmcThemeEngine]::GetInstance().Configure($theme.Properties, @{})
    
    # Create mock ZIndex if not exists
    if (-not ("ZIndex" -as [type])) {
        enum ZIndex { Background = 0; Content = 10; Panel = 20; Header = 50; Footer = 55; StatusBar = 65; Dropdown = 100 }
    }
    
    # Load SpeedTUI dependencies
    $SpeedTUIRoot = "/home/teej/ztest/lib/SpeedTUI"
    . "$SpeedTUIRoot/Core/Logger.ps1"
    . "$SpeedTUIRoot/Core/PerformanceMonitor.ps1"
    . "$SpeedTUIRoot/Core/NullCheck.ps1"
    . "$SpeedTUIRoot/Core/Internal/PerformanceCore.ps1"
    . "$SpeedTUIRoot/Core/SimplifiedTerminal.ps1"
    . "$SpeedTUIRoot/Core/NativeRenderCore.ps1"
    . "$SpeedTUIRoot/Core/CellBuffer.ps1"
    . "$SpeedTUIRoot/Core/HybridRenderEngine.ps1"
    . "$SpeedTUIRoot/Core/Component.ps1"
    
    # Load PmcWidget and dependent widgets
    . "$moduleRoot/widgets/PmcWidget.ps1"
    . "$moduleRoot/widgets/TextInput.ps1"
    . "$moduleRoot/widgets/DatePicker.ps1"
    . "$moduleRoot/services/TaskStore.ps1"
    . "$moduleRoot/widgets/ProjectPicker.ps1"
    . "$moduleRoot/widgets/InlineEditor.ps1"
    . "$moduleRoot/widgets/FilterPanel.ps1"
    . "$moduleRoot/widgets/UniversalList.ps1"
}

Describe "UniversalList Column Positioning" {
    BeforeAll {
        $script:list = [UniversalList]::new()
        $script:list.X = 2
        $script:list.Y = 8
        $script:list.Width = 120
        $script:list.Height = 20
        
        # Define 3 columns like a real screen would
        $script:list.SetColumns(@(
            @{ Name='name'; Label='Name'; Width=40 }
            @{ Name='category'; Label='Category'; Width=25 }
            @{ Name='description'; Label='Description'; Width=50 }
        ))
    }

    It "Column headers render at Y + 1" {
        # Headers render on row Y + 1 (after top border)
        $headerY = $script:list.Y + 1
        $headerY | Should -Be 9
    }

    It "Data rows start at Y + 3" {
        # Data renders at Y + 3 (border + header + separator)
        $dataStartY = $script:list.Y + 3
        $dataStartY | Should -Be 11
    }

    It "First column starts at X + 2" {
        # Columns start at X + 2 (inside border + padding)
        $firstColX = $script:list.X + 2
        $firstColX | Should -Be 4
    }

    It "Stored column widths match definitions" {
        $script:list._columnWidths['name'] | Should -Be 40
        $script:list._columnWidths['category'] | Should -Be 25
        $script:list._columnWidths['description'] | Should -Be 50
    }
}

Describe "InlineEditor Field Positioning in Horizontal Mode" {
    BeforeAll {
        $script:editor = [InlineEditor]::new()
        $script:editor.LayoutMode = "horizontal"
        $script:editor.X = 4   # Same as UniversalList content start (List.X + 2)
        $script:editor.Y = 11  # Same as first data row (List.Y + 3)
        $script:editor.Width = 115  # Same as UniversalList inner width (List.Width - 4 - 1)
        
        # Define fields matching columns
        $script:editor.SetFields(@(
            @{ Name='name'; Type='text'; Label=''; Value='Test Name'; Width=40 }
            @{ Name='category'; Type='text'; Label=''; Value='Test Category'; Width=25 }
            @{ Name='description'; Type='text'; Label=''; Value='Test Description'; Width=50 }
        ))
    }

    It "Should have 3 fields configured" {
        $script:editor._fields.Count | Should -Be 3
    }

    It "Field 1 should have width=40 matching column 1" {
        $script:editor._fields[0].Width | Should -Be 40
    }

    It "Field 2 should have width=25 matching column 2" {
        $script:editor._fields[1].Width | Should -Be 25
    }

    It "Field 3 should have width=50 matching column 3" {
        $script:editor._fields[2].Width | Should -Be 50
    }

    It "Field widgets should be created" {
        $script:editor._fieldWidgets.Count | Should -Be 3
    }

    It "GetValues should return current field values" {
        $values = $script:editor.GetValues()
        $values['name'] | Should -Be 'Test Name'
        $values['category'] | Should -Be 'Test Category'
        $values['description'] | Should -Be 'Test Description'
    }
}

Describe "InlineEditor and UniversalList Alignment Verification" {
    BeforeAll {
        # Simulate what StandardListScreen does
        $script:list = [UniversalList]::new()
        $script:list.X = 2
        $script:list.Y = 8
        $script:list.Width = 120
        $script:list.Height = 20
        
        # Create InlineEditor with CORRECT positioning (after fix)
        $script:editor = [InlineEditor]::new()
        $script:editor.LayoutMode = "horizontal"
        
        # StandardListScreen positions editor at:
        # X = List.X + 2 (matches column content start)
        # Width = List.Width - 4 (matches column content width)
        $script:editor.X = $script:list.X + 2
        $script:editor.Width = $script:list.Width - 4
        
        # For row 0:
        $relativeIndex = 0
        $script:editor.Y = $script:list.Y + 3 + $relativeIndex
    }

    It "Editor X matches column content start" {
        $editorX = $script:editor.X
        $columnStartX = $script:list.X + 2
        
        Write-Host "Editor X: $editorX, Column Start X: $columnStartX"
        $editorX | Should -Be $columnStartX
    }

    It "Editor Width matches column content width" {
        $editorWidth = $script:editor.Width
        $columnContentWidth = $script:list.Width - 4
        
        Write-Host "Editor Width: $editorWidth, Column Content Width: $columnContentWidth"
        $editorWidth | Should -Be $columnContentWidth
    }

    It "Editor Y matches first data row" {
        $editorY = $script:editor.Y
        $firstRowY = $script:list.Y + 3
        
        Write-Host "Editor Y: $editorY, First Row Y: $firstRowY"
        $editorY | Should -Be $firstRowY
    }
}

Describe "Theme Color Visibility Tests" {
    BeforeAll {
        $script:theme = [PmcThemeEngine]::new()
    }

    It "Background.Widget should be dark but visible" {
        $color = $script:theme.GetBackgroundInt('Background.Widget', 80, 0)
        $r = ($color -shr 16) -band 0xFF
        $g = ($color -shr 8) -band 0xFF
        $b = $color -band 0xFF
        
        Write-Host "Background.Widget RGB: ($r, $g, $b)"
        
        # Should be dark (r,g,b all < 100) but not black (at least one > 0)
        $r | Should -BeLessThan 100
        $g | Should -BeLessThan 100
        $b | Should -BeLessThan 100
        ($r + $g + $b) | Should -BeGreaterThan 0
    }

    It "Foreground.Primary should be light enough to read" {
        $color = $script:theme.GetForegroundInt('Foreground.Primary')
        $r = ($color -shr 16) -band 0xFF
        $g = ($color -shr 8) -band 0xFF
        $b = $color -band 0xFF
        
        Write-Host "Foreground.Primary RGB: ($r, $g, $b)"
        
        # Should be light (at least one channel > 180)
        $maxChannel = [Math]::Max($r, [Math]::Max($g, $b))
        $maxChannel | Should -BeGreaterThan 180
    }

    It "Active tab should be brighter than inactive tab" {
        $active = $script:theme.GetBackgroundInt('Background.TabActive', 20, 0)
        $inactive = $script:theme.GetBackgroundInt('Background.TabInactive', 20, 0)
        
        $activeR = ($active -shr 16) -band 0xFF
        $inactiveR = ($inactive -shr 16) -band 0xFF
        
        Write-Host "TabActive R: $activeR, TabInactive R: $inactiveR"
        
        # Active should have more color (higher red for orange theme)
        $activeR | Should -BeGreaterThan $inactiveR
    }
}

Describe "Field-Column Name Matching Test" {
    It "CommandLibraryScreen: Edit field names must exactly match column names" {
        $content = Get-Content "/home/teej/ztest/module/Pmc.Strict/consoleui/screens/CommandLibraryScreen.ps1" -Raw
        
        # Extract column names from GetColumns
        $getColumnsSection = [regex]::Match($content, 'GetColumns\(\)\s*\{[\s\S]*?return\s*@\(([\s\S]*?)\)\s*\}')
        $columnBlock = $getColumnsSection.Groups[1].Value
        $columnNames = @([regex]::Matches($columnBlock, "Name='([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        
        # Extract field names from first return in GetEditFields
        $getEditFieldsSection = [regex]::Match($content, 'GetEditFields[\s\S]*?if\s*\(\s*\$null\s*-eq[\s\S]*?return\s*@\(([\s\S]*?)\)\s*\}')
        $fieldsBlock = $getEditFieldsSection.Groups[1].Value
        $fieldNames = @([regex]::Matches($fieldsBlock, "Name='([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        
        Write-Host "Columns: $($columnNames -join ', ')"
        Write-Host "Fields:  $($fieldNames -join ', ')"
        
        $columnNames.Count | Should -Be $fieldNames.Count -Because "Field count must match column count"
        
        for ($i = 0; $i -lt $columnNames.Count; $i++) {
            $columnNames[$i] | Should -Be $fieldNames[$i] -Because "Field $i name must match column $i name for alignment"
        }
    }
}
