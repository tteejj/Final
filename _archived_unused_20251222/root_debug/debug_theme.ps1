
$ErrorActionPreference = 'Stop'
Write-Host "=== Engine Color Resolution Verification ==="

Import-Module "/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1" -Force
. "/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/src/PraxisVT.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/theme/PmcThemeManager.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/helpers/ThemeHelper.ps1"

$global:PmcTuiLogFile = "/tmp/pmc-debug.log"
$global:PmcApp = $null

Write-Host "1. Initializing..."
Initialize-PmcThemeSystem

$engine = [PmcThemeEngine]::GetInstance()

Write-Host "2. Getting Engine color BEFORE change..."
$colorBefore = $engine.GetThemeColorInt('Background.FieldFocused')
if ($colorBefore -gt 0) {
    $r = ($colorBefore -shr 16) -band 0xFF
    $g = ($colorBefore -shr 8) -band 0xFF
    $b = $colorBefore -band 0xFF
    Write-Host "   BEFORE: R=$r, G=$g, B=$b (int=$colorBefore)"
} else {
    Write-Host "   BEFORE: Not set (int=$colorBefore)"
}

Write-Host "3. Calling Invoke-ThemeHotReload with #ff0000..."
$result = Invoke-ThemeHotReload "#ff0000"
Write-Host "   Result: $result"

Write-Host "4. Getting Engine color AFTER change..."
$colorAfter = $engine.GetThemeColorInt('Background.FieldFocused')
if ($colorAfter -gt 0) {
    $r = ($colorAfter -shr 16) -band 0xFF
    $g = ($colorAfter -shr 8) -band 0xFF
    $b = $colorAfter -band 0xFF
    Write-Host "   AFTER:  R=$r, G=$g, B=$b (int=$colorAfter)"
    if ($r -eq 255 -and $g -eq 0 -and $b -eq 0) {
        Write-Host "   *** SUCCESS - Engine received #ff0000 ***"
    } else {
        Write-Host "   *** FAILURE - Expected R=255,G=0,B=0 ***"
    }
} else {
    Write-Host "   AFTER: Not set (int=$colorAfter)"
}

Write-Host "5. Reverting..."
Invoke-ThemeHotReload "#33aaff"
Write-Host "DONE"
