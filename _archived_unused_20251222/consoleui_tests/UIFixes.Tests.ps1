# UI Fixes Verification Tests - Simplified
# Tests that verify the code changes were applied correctly

Describe "StandardListScreen InlineEditor Positioning" {
    BeforeAll {
        $script:content = Get-Content "/home/teej/ztest/module/Pmc.Strict/consoleui/base/StandardListScreen.ps1" -Raw
    }

    It "InlineEditor X should be List.X + 2 (not +1)" {
        $script:content | Should -Match '\$this\.InlineEditor\.X = \$this\.List\.X \+ 2'
    }

    It "InlineEditor Width should be List.Width - 4 (not -2)" {
        $script:content | Should -Match '\$this\.InlineEditor\.Width = \$this\.List\.Width - 4'
    }
}

Describe "CommandLibraryScreen GetEditFields" {
    BeforeAll {
        $script:cmdContent = Get-Content "/home/teej/ztest/module/Pmc.Strict/consoleui/screens/CommandLibraryScreen.ps1" -Raw
    }

    It "Should include usage_count field" {
        $script:cmdContent | Should -Match "Name='usage_count'"
    }

    It "Should include last_used field" {
        $script:cmdContent | Should -Match "Name='last_used'"
    }

    It "Should have footer shortcuts" {
        $script:cmdContent | Should -Match "AddShortcut.*Add"
        $script:cmdContent | Should -Match "AddShortcut.*Edit"
    }
}

Describe "PmcThemeEngine Theme Keys" {
    BeforeAll {
        $script:themeContent = Get-Content "/home/teej/ztest/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1" -Raw
    }

    It "Should have Background.Widget" {
        $script:themeContent | Should -Match "Background\.Widget"
    }

    It "Should have Foreground.Primary" {
        $script:themeContent | Should -Match "Foreground\.Primary"
    }

    It "Should have Background.TabActive" {
        $script:themeContent | Should -Match "Background\.TabActive"
    }

    It "Should have Background.TabInactive" {
        $script:themeContent | Should -Match "Background\.TabInactive"
    }
}

Describe "Start-PmcTUI Theme Properties" {
    BeforeAll {
        $script:startContent = Get-Content "/home/teej/ztest/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1" -Raw
    }

    It "Should have Background.Widget" {
        $script:startContent | Should -Match "Background\.Widget"
    }

    It "Should have Foreground.Primary" {
        $script:startContent | Should -Match "Foreground\.Primary"
    }

    It "Should have Tab theme keys" {
        $script:startContent | Should -Match "Background\.TabActive"
    }
}

Describe "TabPanel No Hardcoded Colors" {
    BeforeAll {
        $script:tabContent = Get-Content "/home/teej/ztest/module/Pmc.Strict/consoleui/widgets/TabPanel.ps1" -Raw
    }

    It "Should NOT have HybridRenderEngine::_PackRGB calls" {
        $script:tabContent | Should -Not -Match "HybridRenderEngine\]::_PackRGB"
    }
}
