# SpeedTUI Loader for PMC
# Loads SpeedTUI framework components in correct order for PMC widget integration

Set-StrictMode -Version Latest

$ErrorActionPreference = "Continue"

# Determine SpeedTUI root (vendored in PMC)
$SpeedTUIRoot = Join-Path $PSScriptRoot "../../../lib/SpeedTUI"

if (-not (Test-Path $SpeedTUIRoot)) {
    throw "SpeedTUI not found at $SpeedTUIRoot (expected vendored copy)"
}

# Loading SpeedTUI (Write-ConsoleUIDebug not available yet)

try {
    # Load core components in correct order (from SpeedTUI.ps1)

    # 1. Logger and performance
    . "$SpeedTUIRoot/Core/Logger.ps1"
    . "$SpeedTUIRoot/Core/PerformanceMonitor.ps1"
    . "$SpeedTUIRoot/Core/NullCheck.ps1"

    # 2. Performance optimizations (REQUIRED for Component)
    . "$SpeedTUIRoot/Core/Internal/PerformanceCore.ps1"

    # 3. Terminal and rendering
    . "$SpeedTUIRoot/Core/SimplifiedTerminal.ps1"
    . "$SpeedTUIRoot/Core/CellBuffer.ps1"
    # HybridRenderEngine replaces OptimizedRenderEngine and EnhancedRenderEngine
    . "$SpeedTUIRoot/Core/HybridRenderEngine.ps1"

    # 4. Base Component class (THIS IS WHAT PmcWidget EXTENDS)
    . "$SpeedTUIRoot/Core/Component.ps1"

    # 5. Border helper (may be needed)
    . "$SpeedTUIRoot/BorderHelper.ps1"

    # 6. Initialize global logger and perf monitor
    $global:logger = [Logger]::GetInstance()
    $global:logger.GlobalLevel = [LogLevel]::Debug  # Enable debug logging for troubleshooting

    $global:perfMonitor = Get-PerformanceMonitor
    $global:perfMonitor.SetLogger($global:logger)
    # Don't enable perf monitor by default in PMC

    # SpeedTUI framework loaded successfully
    # NOTE: PmcThemeEngine is loaded by Start-PmcTUI.ps1 in proper dependency order

} catch {
    Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [SpeedTUILoader] Failed to load SpeedTUI: $_"
    throw
}