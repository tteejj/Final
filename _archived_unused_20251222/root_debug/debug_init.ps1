
$ErrorActionPreference = 'Stop'
Write-Host "=== Direct Manager Init Debug ==="

Import-Module "/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1" -Force
. "/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/src/PraxisVT.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/theme/PmcThemeManager.ps1"

$global:PmcTuiLogFile = "/tmp/pmc-debug.log"
$global:PmcApp = $null

Write-Host "1. Setting up synthwave in config..."
$cfg = Get-PmcConfig
$cfg.Display.Theme.Hex = "#ff00ff"
Save-PmcConfig $cfg

Write-Host "2. Calling Initialize-PmcThemeSystem..."
Initialize-PmcThemeSystem -Force

Write-Host "3. Creating PmcThemeManager singleton..."
try {
    $manager = [PmcThemeManager]::GetInstance()
    Write-Host "   Manager created"
    Write-Host "   PmcTheme.Hex = $($manager.PmcTheme.Hex)"
} catch {
    Write-Host "   *** EXCEPTION: $($_.Exception.Message)"
    Write-Host "   ScriptStackTrace: $($_.ScriptStackTrace)"
}

Write-Host "4. Checking Engine..."
try {
    $engine = [PmcThemeEngine]::GetInstance()
    Write-Host "   Engine._properties.Count = $($engine._properties.Count)"
    if ($engine._properties.Count -gt 0) {
        $rowProp = $engine._properties['Foreground.Row']
        Write-Host "   Foreground.Row.Type = $($rowProp.Type)"
    }
} catch {
    Write-Host "   *** EXCEPTION: $($_.Exception.Message)"
}

Write-Host "5. Manually calling _BuildThemeProperties..."
try {
    $props = $manager._BuildThemeProperties()
    Write-Host "   Props count = $($props.Count)"
    Write-Host "   Foreground.Row.Type = $($props['Foreground.Row'].Type)"
} catch {
    Write-Host "   *** EXCEPTION: $($_.Exception.Message)"
    Write-Host "   ScriptStackTrace: $($_.ScriptStackTrace)"
}

Write-Host "6. Manually calling Configure..."
try {
    $engine.Configure($props, $manager.ColorPalette)
    Write-Host "   Configure succeeded!"
    Write-Host "   Engine._properties.Count = $($engine._properties.Count)"
} catch {
    Write-Host "   *** EXCEPTION: $($_.Exception.Message)"
}

Write-Host "DONE"
