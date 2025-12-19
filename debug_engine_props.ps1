
$ErrorActionPreference = 'Stop'
Write-Host "=== Engine Properties Debug ==="

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

Write-Host "2. Hot reload to synthwave..."
Invoke-ThemeHotReload "#ff00ff"

Write-Host "3. Check Manager's PmcTheme.Hex..."
$manager = [PmcThemeManager]::GetInstance()
Write-Host "   Manager.PmcTheme.Hex = $($manager.PmcTheme.Hex)"

Write-Host "4. Check Engine's _properties for Foreground.Row..."
$engine = [PmcThemeEngine]::GetInstance()
$prop = $engine._properties['Foreground.Row']
if ($prop) {
    Write-Host "   Type = $($prop.Type)"
    Write-Host "   Start = $($prop.Start)"
    Write-Host "   End = $($prop.End)"
    Write-Host "   Color = $($prop.Color)"
} else {
    Write-Host "   *** NO PROPERTY FOUND ***"
}

Write-Host "5. Check if singleton is stale..."
Write-Host "   Engine._properties count = $($engine._properties.Count)"

Write-Host "DONE"
