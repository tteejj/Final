
$ErrorActionPreference = 'Stop'
Write-Host "=== Full Gradient Debug ==="

Import-Module "/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1" -Force
. "/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/src/PraxisVT.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/theme/PmcThemeManager.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/helpers/ThemeHelper.ps1"

$global:PmcTuiLogFile = "/tmp/pmc-debug.log"
$global:PmcApp = $null

Write-Host "1. Init theme system..."
Initialize-PmcThemeSystem

$manager = [PmcThemeManager]::GetInstance()
$engine = [PmcThemeEngine]::GetInstance()

Write-Host "2. Check current theme hex..."
Write-Host "   PmcTheme.Hex = $($manager.PmcTheme.Hex)"

Write-Host "3. Hot reload to synthwave..."
Invoke-ThemeHotReload "#ff00ff"

Write-Host "4. Check updated theme hex..."
Write-Host "   PmcTheme.Hex = $($manager.PmcTheme.Hex)"

Write-Host "5. Check if _BuildThemeProperties detects synthwave..."
# Force rebuild
$props = $manager._BuildThemeProperties()
$rowProp = $props['Foreground.Row']
Write-Host "   Foreground.Row.Type = $($rowProp.Type)"
if ($rowProp.Type -eq 'Gradient') {
    Write-Host "   Foreground.Row.Start = $($rowProp.Start)"
    Write-Host "   Foreground.Row.End = $($rowProp.End)"
} else {
    Write-Host "   Foreground.Row.Color = $($rowProp.Color)"
}

Write-Host "6. Check Engine's GetGradientInfo..."
$gradInfo = $engine.GetGradientInfo('Foreground.Row')
if ($gradInfo) {
    Write-Host "   Gradient detected!"
    Write-Host "   Start int = $($gradInfo.Start)"
    Write-Host "   End int = $($gradInfo.End)"
} else {
    Write-Host "   NO GRADIENT - returned null"
    Write-Host "   Engine properties for Foreground.Row:"
    $engProp = $engine._properties['Foreground.Row']
    Write-Host "   Type = $($engProp.Type)"
    Write-Host "   Start = $($engProp.Start)"
    Write-Host "   End = $($engProp.End)"
    Write-Host "   Color = $($engProp.Color)"
}

Write-Host "DONE"
