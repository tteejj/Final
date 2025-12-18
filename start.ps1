# start.ps1 - Portable entry point for PMC TUI
# Works on both Windows and Linux - keeps all files within program folder
param(
    [switch]$DebugLog,
    [int]$LogLevel = 0
)

Set-StrictMode -Version Latest

# Determine application root (cross-platform)
$script:AppRoot = $PSScriptRoot

# Create data directory structure if needed
$dataDir = Join-Path $script:AppRoot "data"
$logDir = Join-Path $dataDir "logs"
$backupDir = Join-Path $dataDir "backups"

foreach ($dir in @($dataDir, $logDir, $backupDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Set global path for debug logging (replaces hardcoded /tmp/pmc-debug.log)
$global:PmcDebugLogPath = Join-Path $logDir "pmc-debug.log"
$global:PmcAppRoot = $script:AppRoot

# Export for other modules
$env:PMC_APP_ROOT = $script:AppRoot
$env:PMC_LOG_PATH = $logDir

# Launch TUI
try {
    # Dot-source to load the function
    . "$script:AppRoot/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1"
    
    # Now call the function explicitly
    Start-PmcTUI -DebugLog:$DebugLog -LogLevel $LogLevel
}
catch {
    Write-Host "PMC TUI Error: $_" -ForegroundColor Red
    Write-Host "See log at: $global:PmcDebugLogPath" -ForegroundColor Yellow
    throw
}
