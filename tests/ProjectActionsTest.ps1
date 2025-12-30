
Describe "ProjectListScreen Actions" {
    Context "Method Existence" {
        It "Should have OpenT2020 method" {
            $content = Get-Content "$PSScriptRoot/../module/Pmc.Strict/consoleui/screens/ProjectListScreen.ps1" -Raw
            $content | Should -Match "\[void\] OpenT2020"
        }

        It "Should have OpenCAA method" {
            $content = Get-Content "$PSScriptRoot/../module/Pmc.Strict/consoleui/screens/ProjectListScreen.ps1" -Raw
            $content | Should -Match "\[void\] OpenCAA"
        }

        It "Should have OpenRequest method" {
            $content = Get-Content "$PSScriptRoot/../module/Pmc.Strict/consoleui/screens/ProjectListScreen.ps1" -Raw
            $content | Should -Match "\[void\] OpenRequest"
        }

        It "Should have OpenProjectFolder method" {
            $content = Get-Content "$PSScriptRoot/../module/Pmc.Strict/consoleui/screens/ProjectListScreen.ps1" -Raw
            $content | Should -Match "\[void\] OpenProjectFolder"
        }
    }

    Context "Custom Actions Registration" {
        It "Should register 't' key for T2020" {
            $content = Get-Content "$PSScriptRoot/../module/Pmc.Strict/consoleui/screens/ProjectListScreen.ps1" -Raw
            $content | Should -Match "Key\s*=\s*'t'.*Label\s*=\s*'T2020'"
        }

        It "Should register 'c' key for CAA" {
            $content = Get-Content "$PSScriptRoot/../module/Pmc.Strict/consoleui/screens/ProjectListScreen.ps1" -Raw
            $content | Should -Match "Key\s*=\s*'c'.*Label\s*=\s*'CAA'"
        }

        It "Should register 'q' key for Request" {
            $content = Get-Content "$PSScriptRoot/../module/Pmc.Strict/consoleui/screens/ProjectListScreen.ps1" -Raw
            $content | Should -Match "Key\s*=\s*'q'.*Label\s*=\s*'Request'"
        }

        It "Should register 'o' key for Open Folder" {
            $content = Get-Content "$PSScriptRoot/../module/Pmc.Strict/consoleui/screens/ProjectListScreen.ps1" -Raw
            $content | Should -Match "Key\s*=\s*'o'.*Label\s*=\s*'Open Folder'"
        }
    }
}
