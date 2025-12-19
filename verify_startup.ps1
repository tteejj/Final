
$ErrorActionPreference = 'Stop'

Write-Host "1. Loading PMC Module..."
Import-Module "/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1" -Force

Write-Host "2. Loading Dependencies..."
. "/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1"

Write-Host "3. Loading SpeedTUI..."
. "/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1"

Write-Host "4. Loading PraxisVT..."
. "/home/teej/ztest/module/Pmc.Strict/src/PraxisVT.ps1"

Write-Host "5. Loading Theme Engine (Was Broken)..."
. "/home/teej/ztest/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1"
Write-Host "   - PmcThemeEngine Loaded OK"

Write-Host "6. Loading Theme Manager (Was Broken)..."
. "/home/teej/ztest/module/Pmc.Strict/consoleui/theme/PmcThemeManager.ps1"
Write-Host "   - PmcThemeManager Loaded OK"

Write-Host "7. Initializing Theme System..."
Initialize-PmcThemeSystem
$manager = [PmcThemeManager]::GetInstance()
$hex = $manager.GetCurrentThemeHex()
Write-Host "   - Theme System Initialized. Current Hex: $hex"

Write-Host "8. Testing Engine Primitives..."
$engine = [PmcThemeEngine]::GetInstance()
$ansi = $engine.GetAnsiFromHex("#FFFFFF", $false)
if ([string]::IsNullOrEmpty($ansi)) { throw "Engine returned empty ANSI" }
Write-Host "   - Engine Primitive GetAnsiFromHex OK"

Write-Host "VERIFICATION SUCCESSFUL: All modules loaded and Theme System is functional."
