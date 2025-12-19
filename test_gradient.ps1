
$ErrorActionPreference = 'Stop'
Write-Host "=== Gradient Theme System Test ==="

Import-Module "/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1" -Force
. "/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1"
. "/home/teej/ztest/module/Pmc.Strict/src/PraxisVT.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/theme/PmcThemeManager.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/helpers/ThemeHelper.ps1"

$global:PmcTuiLogFile = "/tmp/pmc-debug.log"
$global:PmcApp = $null

Write-Host "1. Initializing with default theme..."
Initialize-PmcThemeSystem

$engine = [PmcThemeEngine]::GetInstance()

Write-Host "2. Testing GetGradientInfo on solid theme..."
$info = $engine.GetGradientInfo('Foreground.Row')
Write-Host "   Result: $(if($info){'Gradient'}else{'Solid (null)'})"

Write-Host "3. Switching to Synthwave (#ff00ff)..."
Invoke-ThemeHotReload "#ff00ff"

Write-Host "4. Testing GetGradientInfo on synthwave theme..."
$info = $engine.GetGradientInfo('Foreground.Row')
if ($info) {
    $startR = ($info.Start -shr 16) -band 0xFF
    $startG = ($info.Start -shr 8) -band 0xFF
    $startB = $info.Start -band 0xFF
    $endR = ($info.End -shr 16) -band 0xFF
    $endG = ($info.End -shr 8) -band 0xFF
    $endB = $info.End -band 0xFF
    Write-Host "   Start: R=$startR G=$startG B=$startB"
    Write-Host "   End:   R=$endR G=$endG B=$endB"
    
    if ($startR -eq 255 -and $startG -eq 0 -and $startB -eq 255 -and
        $endR -eq 0 -and $endG -eq 255 -and $endB -eq 255) {
        Write-Host "   *** SUCCESS - Magenta to Cyan gradient detected ***"
    } else {
        Write-Host "   *** UNEXPECTED colors ***"
    }
} else {
    Write-Host "   *** FAILURE - Expected gradient info, got null ***"
}

Write-Host "5. Reverting to default..."
Invoke-ThemeHotReload "#33aaff"

Write-Host "DONE"
