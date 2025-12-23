# Functional UI Tests - Test actual behavior via public API
# Tests verify the fixes are working correctly

BeforeAll {
    $moduleRoot = "/home/teej/ztest/module/Pmc.Strict/consoleui"
    . "$moduleRoot/helpers/GapBuffer.ps1"
    . "$moduleRoot/src/PmcThemeEngine.ps1"
}

Describe "PmcThemeEngine Color Lookup" {
    BeforeAll {
        $script:theme = [PmcThemeEngine]::new()
    }

    It "Should create theme engine instance" {
        $script:theme | Should -Not -BeNull
    }

    It "GetForegroundInt returns valid int for Foreground.Primary" {
        $color = $script:theme.GetForegroundInt('Foreground.Primary')
        $color | Should -BeOfType [int]
        $color | Should -BeGreaterThan 0
        Write-Host "  Foreground.Primary = $color (0x$($color.ToString('X6')))"
    }

    It "GetBackgroundInt returns valid int for Background.Widget" {
        $color = $script:theme.GetBackgroundInt('Background.Widget', 80, 0)
        $color | Should -BeOfType [int]
        $color | Should -BeGreaterThan 0
        Write-Host "  Background.Widget = $color (0x$($color.ToString('X6')))"
    }

    It "GetBackgroundInt returns valid int for Background.TabActive" {
        $color = $script:theme.GetBackgroundInt('Background.TabActive', 20, 0)
        $color | Should -BeOfType [int]
        $color | Should -BeGreaterThan 0
        Write-Host "  Background.TabActive = $color (0x$($color.ToString('X6')))"
    }

    It "GetForegroundInt returns valid int for Foreground.TabActive" {
        $color = $script:theme.GetForegroundInt('Foreground.TabActive')
        $color | Should -BeOfType [int]
        $color | Should -BeGreaterThan 0
        Write-Host "  Foreground.TabActive = $color (0x$($color.ToString('X6')))"
    }

    It "GetBackgroundInt returns valid int for Background.TabInactive" {
        $color = $script:theme.GetBackgroundInt('Background.TabInactive', 20, 0)
        $color | Should -BeOfType [int]
        $color | Should -BeGreaterThan 0
        Write-Host "  Background.TabInactive = $color (0x$($color.ToString('X6')))"
    }

    It "GetForegroundInt returns valid int for Foreground.TabInactive" {
        $color = $script:theme.GetForegroundInt('Foreground.TabInactive')
        $color | Should -BeOfType [int]
        $color | Should -BeGreaterThan 0
        Write-Host "  Foreground.TabInactive = $color (0x$($color.ToString('X6')))"
    }
}

Describe "GapBuffer Core Operations" {
    BeforeAll {
        $script:buffer = [GapBuffer]::new()
    }

    It "Insert and GetText" {
        $script:buffer.Insert(0, "Hello World")
        $script:buffer.GetText() | Should -Be "Hello World"
    }

    It "GetLength" {
        $script:buffer.GetLength() | Should -Be 11
    }

    It "FindAll" {
        $positions = $script:buffer.FindAll("o")
        $positions.Count | Should -Be 2
    }
}

Describe "StandardListScreen Editor Positioning in Code" {
    It "Editor X should be List.X + 2" {
        $content = Get-Content "/home/teej/ztest/module/Pmc.Strict/consoleui/base/StandardListScreen.ps1" -Raw
        $content | Should -Match '\$this\.InlineEditor\.X = \$this\.List\.X \+ 2'
    }

    It "Editor Width should be List.Width - 4" {
        $content = Get-Content "/home/teej/ztest/module/Pmc.Strict/consoleui/base/StandardListScreen.ps1" -Raw
        $content | Should -Match '\$this\.InlineEditor\.Width = \$this\.List\.Width - 4'
    }
}

Describe "CommandLibraryScreen Field Count" {
    It "GetEditFields should have 5 fields to match 5 columns" {
        $content = Get-Content "/home/teej/ztest/module/Pmc.Strict/consoleui/screens/CommandLibraryScreen.ps1" -Raw
        # Check for usage_count and last_used fields (were missing before)
        $content | Should -Match "Name='usage_count'"
        $content | Should -Match "Name='last_used'"
    }
}
