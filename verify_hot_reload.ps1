
$ErrorActionPreference = 'Stop'

Write-Host "1. Loading Environment..."
$global:PmcTuiLogFile = "/home/teej/ztest/pmc_hotreload_test.log"
$global:PmcApp = $null
$modulePath = "/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1"
Import-Module $modulePath -Force

# Dot-source files in correct order
. "/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/src/PraxisVT.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/theme/PmcThemeManager.ps1"

Write-Host "2. Checking Types..."
try {
    $type = [PmcThemeManager]
    Write-Host "   - [PmcThemeManager] Type Found"
} catch {
    Write-Error "   - [PmcThemeManager] Type NOT Found"
    exit 1
}

Write-Host "3. Initializing Theme System..."
Initialize-PmcThemeSystem
$manager = [PmcThemeManager]::GetInstance()
$initialHex = $manager.GetCurrentThemeHex()
Write-Host "   - Initial Hex: $initialHex"

Write-Host "4. Setting New Theme (Hot Reload)..."
$newHex = "#FF0000" # Red

try {
    $manager.SetTheme($newHex)
} catch {
    Write-Error "SetTheme FAILED: $_"
    Write-Error "Stack Trace: $($_.ScriptStackTrace)"
    exit 1
}

Write-Host "5. Verifying Manager State..."
$currentHex = $manager.GetCurrentThemeHex()
if ($currentHex -ne $newHex) {
    Write-Error "Manager did not update hex! Expected $newHex, got $currentHex"
    # Continue to see engine state
} else {
    Write-Host "   - Manager Hex Updated OK"
}

Write-Host "6. Verifying Engine State..."
$engine = [PmcThemeEngine]::GetInstance()
$ansi = $engine.GetAnsiFromHex($newHex, $false)
$escaped = $ansi -replace "`e", "ESC"
Write-Host "   - Engine returned ANSI sequence: $escaped"
if ($ansi.Length -gt 0) {
    Write-Host "   - ANSI Generation OK"
} else {
    Write-Error "   - ANSI Generation FAILED (Empty)"
}

Write-Host "7. Reverting Theme..."
try {
    $manager.SetTheme($initialHex)
    Write-Host "   - Reverted to $initialHex"
} catch {
    Write-Warning "Failed to revert theme: $_"
}

Write-Host "VERIFICATION COMPLETE"
