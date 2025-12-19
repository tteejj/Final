#!/usr/bin/env pwsh
# Run in completely fresh session
$ErrorActionPreference = 'Stop'

Write-Host "=== Fresh Session Test ==="

# Set synthwave in config FIRST
$configPath = "/home/teej/ztest/config.json"
$cfg = Get-Content $configPath | ConvertFrom-Json
$cfg.Display.Theme.Hex = "#ff00ff"
$cfg | ConvertTo-Json -Depth 10 | Set-Content $configPath

Write-Host "1. Config set to #ff00ff"

# Now load everything fresh
Import-Module "/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1" -Force
. "/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/src/PraxisVT.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/theme/PmcThemeManager.ps1"

$global:PmcTuiLogFile = "/tmp/pmc-debug.log"

Write-Host "2. Calling Initialize-PmcThemeSystem..."
Initialize-PmcThemeSystem -Force

Write-Host "3. Getting Manager singleton..."
$manager = [PmcThemeManager]::GetInstance()
Write-Host "   PmcTheme.Hex = $($manager.PmcTheme.Hex)"

Write-Host "4. Checking Engine..."
$engine = [PmcThemeEngine]::GetInstance()
Write-Host "   Engine._properties.Count = $($engine._properties.Count)"

if ($engine._properties.Count -gt 0) {
    $rowProp = $engine._properties['Foreground.Row']
    Write-Host "   Foreground.Row.Type = $($rowProp.Type)"
    if ($rowProp.Type -eq 'Gradient') {
        Write-Host "   *** SUCCESS! Gradient detected ***"
    }
} else {
    Write-Host "   *** FAILURE: No properties ***"
}

Write-Host "DONE"
