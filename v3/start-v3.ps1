Param(
    [int]$DebugLevel = 1
)

# start-v3.ps1 - V3 Bootstrapper
$ErrorActionPreference = "Stop"

# 1. Define Paths
$scriptDir = $PSScriptRoot
$moduleDir = "$scriptDir/module/Pmc.Strict"
$logFile = "$scriptDir/pmc_v3.log"

# 2. Key Binding Manifest (for StatusBar)
$manifest = @{
    "F1" = @{ Menu = "Main"; Label = "Help" }
    "F5" = @{ Menu = "Main"; Label = "Refresh" }
    "Q" = @{ Menu = "Global"; Label = "Quit" }
    "V" = @{ Menu = "Project"; Label = "Project Info" }
    "T" = @{ Menu = "Project"; Label = "Time" }
    "O" = @{ Menu = "Global"; Label = "Overview" }
    "M" = @{ Menu = "Details"; Label = "Add Note" }
    "N" = @{ Menu = "List"; Label = "New" }
}

# 3. Load Dependencies in strict order
# First, load NativeRenderCore.ps1 from lib for C# NativeCellBuffer (50-100x speedup)
$nativeCorePath = Join-Path (Split-Path $scriptDir -Parent) "lib/SpeedTUI/Core/NativeRenderCore.ps1"
if (Test-Path $nativeCorePath) {
    Write-Host "DEBUG: Loading NativeRenderCore.ps1 for C# acceleration..." -ForegroundColor Yellow
    try {
        . $nativeCorePath
        Write-Host "DEBUG: NativeRenderCore.ps1 loaded - C# acceleration enabled!" -ForegroundColor Green
    } catch {
        Write-Host "DEBUG: NativeRenderCore.ps1 failed to load, using PowerShell fallback" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "DEBUG: NativeRenderCore.ps1 not found at $nativeCorePath, using PowerShell fallback" -ForegroundColor DarkYellow
}

$files = @(
    "Logger.ps1",
    "Enums.ps1",
    "PerformanceCore.ps1",
    "CellBuffer.ps1",
    "RenderCache.ps1",
    "HybridRenderEngine.Dependencies.ps1",
    "HybridRenderEngine.ps1",
    "GapBuffer.ps1",
    "DataService.ps1",
    "FluxStore.ps1",
    "UniversalList.ps1",
    "Dashboard.ps1",
    "WeeklyView.ps1",
    "NoteEditor.ps1",
    "InputLogic.ps1",
    "SmartEditor.ps1",
    "FilePicker.ps1",
    "TabbedModal.ps1",
    "NotesModal.ps1",
    "ChecklistsModal.ps1",
    "FieldMappingService.ps1",
    "TextExportService.ps1",
    "ProjectInfoModal.ps1",
    "TimeModal.ps1",
    "OverviewModal.ps1",
    "CommandPalette.ps1",
    "ThemePicker.ps1",
    "StatusBar.ps1",
    "TuiApp.ps1"
)

try {
    # Logging first
    . "$scriptDir/Logger.ps1"
    [Logger]::Initialize($logFile, $DebugLevel)
    
    foreach ($file in $files) {
        $filePath = Join-Path $scriptDir $file
        Write-Host "DEBUG: Checking $file..." -ForegroundColor DarkGray
        if (Test-Path $filePath) {
            Write-Host "DEBUG: Loading $file..." -ForegroundColor Yellow
            try {
                . $filePath
                Write-Host "DEBUG: Loaded $file OK." -ForegroundColor Green
            } catch {
                Write-Host "DEBUG: FAILED to load $file" -ForegroundColor Red
                Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
                throw $_
            }
        } else {
            throw "Missing required file: $file at $filePath"
        }
    }

    # 3b. Load Theme System from module
    $moduleRoot = Join-Path (Split-Path $scriptDir -Parent) "module/Pmc.Strict"
    $themeFiles = @(
        "consoleui/helpers/ThemeLoader.ps1",
        "consoleui/theme/PmcThemeManager.ps1"
    )
    
    # Set PmcAppRoot for theme loading (expects themes/ folder at app root)
    $global:PmcAppRoot = Split-Path $scriptDir -Parent
    
    foreach ($themeFile in $themeFiles) {
        $themePath = Join-Path $moduleRoot $themeFile
        if (Test-Path $themePath) {
            Write-Host "DEBUG: Loading $themeFile..." -ForegroundColor Yellow
            try {
                . $themePath
                Write-Host "DEBUG: Loaded $themeFile OK." -ForegroundColor Green
            } catch {
                Write-Host "DEBUG: FAILED to load $themeFile - themes may not work" -ForegroundColor DarkYellow
            }
        }
    }
    
    # 3c. Apply theme colors to Colors class
    try {
        if (([System.Management.Automation.PSTypeName]'PmcThemeManager').Type) {
            $themeManager = [PmcThemeManager]::GetInstance()
            if ($themeManager -and $themeManager.PmcTheme -and $themeManager.PmcTheme.Properties) {
                $props = $themeManager.PmcTheme.Properties
                
                # Map theme properties to Colors class
                # Helper function to convert hex to int
                $hexToInt = {
                    param([string]$hex)
                    if ([string]::IsNullOrEmpty($hex)) { return -1 }
                    $hex = $hex.TrimStart('#')
                    if ($hex.Length -ne 6) { return -1 }
                    try {
                        return [Convert]::ToInt32($hex, 16)
                    } catch { return -1 }
                }
                
                # Apply theme colors if available
                if ($props.ContainsKey('Background') -and $props.Background.Color) {
                    [Colors]::Background = & $hexToInt $props.Background.Color
                }
                if ($props.ContainsKey('Surface') -and $props.Surface.Color) {
                    [Colors]::PanelBg = & $hexToInt $props.Surface.Color
                }
                if ($props.ContainsKey('Border') -and $props.Border.Color) {
                    [Colors]::PanelBorder = & $hexToInt $props.Border.Color
                }
                if ($props.ContainsKey('Text') -and $props.Text.Color) {
                    [Colors]::Foreground = & $hexToInt $props.Text.Color
                }
                if ($props.ContainsKey('Primary') -and $props.Primary.Color) {
                    [Colors]::Accent = & $hexToInt $props.Primary.Color
                }
                if ($props.ContainsKey('Success') -and $props.Success.Color) {
                    [Colors]::Success = & $hexToInt $props.Success.Color
                }
                if ($props.ContainsKey('Warning') -and $props.Warning.Color) {
                    [Colors]::Warning = & $hexToInt $props.Warning.Color
                }
                if ($props.ContainsKey('Error') -and $props.Error.Color) {
                    [Colors]::Error = & $hexToInt $props.Error.Color
                }
                if ($props.ContainsKey('Highlight') -and $props.Highlight.Color) {
                    [Colors]::SelectionBg = & $hexToInt $props.Highlight.Color
                }
                
                Write-Host "DEBUG: Theme '$($themeManager.PmcTheme.PaletteName)' applied to Colors class" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "DEBUG: Theme loading skipped: $_" -ForegroundColor DarkYellow
    }

    # 4. Initialize and Run (with restart support)
    $global:PmcRestartRequested = $false
    
    do {
        $global:PmcRestartRequested = $false
        
        $dataService = [DataService]::new((Join-Path $scriptDir "tasks.json"))
        $store = [FluxStore]::new($dataService)
        $engine = [HybridRenderEngine]::new()

        $app = [TuiApp]::new($engine, $store)

        # 5. Start
        if ($global:PmcRestartRequested -eq $false) {
            Write-Host "Starting FluxTUI V3..." -ForegroundColor Cyan
        } else {
            Write-Host "Restarting FluxTUI V3 (theme changed)..." -ForegroundColor Cyan
        }
        
        $app.Run()
        
        # If restart requested, cleanup and reload theme colors
        if ($global:PmcRestartRequested) {
            $engine.Cleanup()
            
            # Reload PmcThemeManager to get new theme
            try {
                [PmcThemeManager]::Reset()
                $themeManager = [PmcThemeManager]::GetInstance()
                if ($themeManager -and $themeManager.PmcTheme -and $themeManager.PmcTheme.Properties) {
                    $props = $themeManager.PmcTheme.Properties
                    
                    $hexToInt = {
                        param([string]$hex)
                        if ([string]::IsNullOrEmpty($hex)) { return -1 }
                        $hex = $hex.TrimStart('#')
                        if ($hex.Length -ne 6) { return -1 }
                        try { return [Convert]::ToInt32($hex, 16) } catch { return -1 }
                    }
                    
                    if ($props.ContainsKey('Background') -and $props.Background.Color) {
                        [Colors]::Background = & $hexToInt $props.Background.Color
                    }
                    if ($props.ContainsKey('Surface') -and $props.Surface.Color) {
                        [Colors]::PanelBg = & $hexToInt $props.Surface.Color
                    }
                    if ($props.ContainsKey('Border') -and $props.Border.Color) {
                        [Colors]::PanelBorder = & $hexToInt $props.Border.Color
                    }
                    if ($props.ContainsKey('Text') -and $props.Text.Color) {
                        [Colors]::Foreground = & $hexToInt $props.Text.Color
                    }
                    if ($props.ContainsKey('Primary') -and $props.Primary.Color) {
                        [Colors]::Accent = & $hexToInt $props.Primary.Color
                    }
                    if ($props.ContainsKey('Success') -and $props.Success.Color) {
                        [Colors]::Success = & $hexToInt $props.Success.Color
                    }
                    if ($props.ContainsKey('Warning') -and $props.Warning.Color) {
                        [Colors]::Warning = & $hexToInt $props.Warning.Color
                    }
                    if ($props.ContainsKey('Error') -and $props.Error.Color) {
                        [Colors]::Error = & $hexToInt $props.Error.Color
                    }
                    if ($props.ContainsKey('Highlight') -and $props.Highlight.Color) {
                        [Colors]::SelectionBg = & $hexToInt $props.Highlight.Color
                    }
                    
                    Write-Host "DEBUG: Theme '$($themeManager.PmcTheme.PaletteName)' applied for restart" -ForegroundColor Green
                }
            } catch {
                Write-Host "DEBUG: Theme reload on restart failed: $_" -ForegroundColor DarkYellow
            }
        }
        
    } while ($global:PmcRestartRequested)

} catch {
    [Logger]::Log("Fatal Error (Trapped): $($_.Exception.Message)", 3)
    [Logger]::Log($_.ScriptStackTrace, 3)
    # Don't Write-Error as it corrupts TUI. 
    if ([Logger]) {
        [Logger]::Error("Fatal crash in bootstrapper", $_.Exception)
    }
}

