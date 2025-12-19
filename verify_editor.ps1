
$ErrorActionPreference = 'Stop'
Write-Host "Loading dependencies..."
Import-Module "/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1" -Force
. "/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/src/PraxisVT.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/theme/PmcThemeManager.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/ZIndex.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/layout/PmcLayoutManager.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/widgets/PmcWidget.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/PmcScreen.ps1"

Write-Host "Loading ThemeEditorScreen..."
try {
    . "/home/teej/ztest/module/Pmc.Strict/consoleui/screens/ThemeEditorScreen.ps1"
    Write-Host "ThemeEditorScreen loaded OK."
} catch {
    Write-Error "Failed to load ThemeEditorScreen: $_"
    exit 1
}
