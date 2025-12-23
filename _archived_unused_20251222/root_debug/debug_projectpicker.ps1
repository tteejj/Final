
$ErrorActionPreference = "Stop"
try {
    # Load dependencies
    $SpeedTUIRoot = "/home/teej/ztest/lib/SpeedTUI"
    . "$SpeedTUIRoot/Core/Logger.ps1"
    . "$SpeedTUIRoot/Core/PerformanceMonitor.ps1"
    . "$SpeedTUIRoot/Core/NullCheck.ps1"
    . "$SpeedTUIRoot/Core/Internal/PerformanceCore.ps1"
    . "$SpeedTUIRoot/Core/SimplifiedTerminal.ps1"
    . "$SpeedTUIRoot/Core/NativeRenderCore.ps1"
    . "$SpeedTUIRoot/Core/CellBuffer.ps1"
    . "$SpeedTUIRoot/Core/HybridRenderEngine.ps1"
    . "$SpeedTUIRoot/Core/Component.ps1"

    if (-not ("ZIndex" -as [type])) {
        enum ZIndex { Background = 0; Content = 10; Panel = 20; Header = 50; Footer = 55; StatusBar = 65; Dropdown = 100 }
    }

    $moduleRoot = "/home/teej/ztest/module/Pmc.Strict/consoleui"
    . "$moduleRoot/src/PmcThemeEngine.ps1"
    . "$moduleRoot/widgets/PmcWidget.ps1"
    . "$moduleRoot/widgets/ProjectPicker.ps1"
    
    Write-Host "ProjectPicker loaded successfully"
}
catch {
    Write-Host "Error loading ProjectPicker: $_"
    Write-Host $_.ScriptStackTrace
}
