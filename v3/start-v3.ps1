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
        [Logger]::Log("ThemeApply: Checking for PmcThemeManager type...", 1)
        if (([System.Management.Automation.PSTypeName]'PmcThemeManager').Type) {
            [Logger]::Log("ThemeApply: PmcThemeManager type found, getting instance...", 1)
            $themeManager = [PmcThemeManager]::GetInstance()
            [Logger]::Log("ThemeApply: ThemeManager instance: $($themeManager -ne $null)", 1)
            [Logger]::Log("ThemeApply: PmcTheme: $($themeManager.PmcTheme -ne $null)", 1)
            
            if ($themeManager -and $themeManager.PmcTheme) {
                [Logger]::Log("ThemeApply: Theme PaletteName: $($themeManager.PmcTheme.PaletteName)", 1)
                [Logger]::Log("ThemeApply: Theme Hex: $($themeManager.PmcTheme.Hex)", 1)
                [Logger]::Log("ThemeApply: Properties null: $($themeManager.PmcTheme.Properties -eq $null)", 1)
                
                if ($themeManager.PmcTheme.Properties) {
                    $props = $themeManager.PmcTheme.Properties
                    [Logger]::Log("ThemeApply: Properties count: $($props.Count)", 1)
                    [Logger]::Log("ThemeApply: Property keys (first 10): $(($props.Keys | Select-Object -First 10) -join ', ')", 1)
                
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
                # Theme JSON uses names like "Background.Primary", "Surface", "Text", "Primary"
                
                # Background - try Background.Primary first, then fallback
                if ($props.ContainsKey('Background.Primary') -and $props['Background.Primary'].Color) {
                    [Colors]::Background = & $hexToInt $props['Background.Primary'].Color
                }
                
                # Panel background - use Surface or Background.Panel
                if ($props.ContainsKey('Surface') -and $props.Surface.Color) {
                    [Colors]::PanelBg = & $hexToInt $props.Surface.Color
                } elseif ($props.ContainsKey('Background.Panel') -and $props['Background.Panel'].Color) {
                    [Colors]::PanelBg = & $hexToInt $props['Background.Panel'].Color
                }
                
                # Border
                if ($props.ContainsKey('Border') -and $props.Border.Color) {
                    [Colors]::PanelBorder = & $hexToInt $props.Border.Color
                } elseif ($props.ContainsKey('Border.Widget') -and $props['Border.Widget'].Color) {
                    [Colors]::PanelBorder = & $hexToInt $props['Border.Widget'].Color
                }
                
                # Foreground/Text
                if ($props.ContainsKey('Text') -and $props.Text.Color) {
                    [Colors]::Foreground = & $hexToInt $props.Text.Color
                } elseif ($props.ContainsKey('OnSurface') -and $props.OnSurface.Color) {
                    [Colors]::Foreground = & $hexToInt $props.OnSurface.Color
                }
                
                # Accent (Primary color)
                if ($props.ContainsKey('Primary') -and $props.Primary.Color) {
                    [Colors]::Accent = & $hexToInt $props.Primary.Color
                }
                
                # Semantic colors
                if ($props.ContainsKey('Success') -and $props.Success.Color) {
                    [Colors]::Success = & $hexToInt $props.Success.Color
                }
                if ($props.ContainsKey('Warning') -and $props.Warning.Color) {
                    [Colors]::Warning = & $hexToInt $props.Warning.Color
                }
                if ($props.ContainsKey('Error') -and $props.Error.Color) {
                    [Colors]::Error = & $hexToInt $props.Error.Color
                }
                
                # Selection
                # Selection - prioritize Background.Selection (specific) over Highlight (generic)
                if ($props.ContainsKey('Background.Selection') -and $props['Background.Selection'].Color) {
                    [Colors]::SelectionBg = & $hexToInt $props['Background.Selection'].Color
                } elseif ($props.ContainsKey('Highlight') -and $props.Highlight.Color) {
                    [Colors]::SelectionBg = & $hexToInt $props.Highlight.Color
                }
                
                # SelectionFg
                if ($props.ContainsKey('Foreground.Selection') -and $props['Foreground.Selection'].Color) {
                    [Colors]::SelectionFg = & $hexToInt $props['Foreground.Selection'].Color
                } elseif ($props.ContainsKey('Bright') -and $props.Bright.Color) {
                    [Colors]::SelectionFg = & $hexToInt $props.Bright.Color
                }
                
                # Title (for headers, column titles - was Cyan)
                if ($props.ContainsKey('Title') -and $props.Title.Color) {
                    [Colors]::Title = & $hexToInt $props.Title.Color
                } elseif ($props.ContainsKey('Header') -and $props.Header.Color) {
                    [Colors]::Title = & $hexToInt $props.Header.Color
                } elseif ($props.ContainsKey('Primary') -and $props.Primary.Color) {
                    [Colors]::Title = & $hexToInt $props.Primary.Color
                }
                
                # Muted (for secondary text - was Gray)
                if ($props.ContainsKey('Muted') -and $props.Muted.Color) {
                    [Colors]::Muted = & $hexToInt $props.Muted.Color
                } elseif ($props.ContainsKey('Label') -and $props.Label.Color) {
                    [Colors]::Muted = & $hexToInt $props.Label.Color
                }
                
                # Bright (for emphasis - was White)
                if ($props.ContainsKey('Bright') -and $props.Bright.Color) {
                    [Colors]::Bright = & $hexToInt $props.Bright.Color
                } elseif ($props.ContainsKey('Foreground.Accent') -and $props['Foreground.Accent'].Color) {
                    [Colors]::Bright = & $hexToInt $props['Foreground.Accent'].Color
                }
                
                # Cursor (for text cursor display)
                if ($props.ContainsKey('Cursor') -and $props.Cursor.Color) {
                    [Colors]::Cursor = & $hexToInt $props.Cursor.Color
                } else {
                    [Colors]::Cursor = [Colors]::Foreground
                }
                if ($props.ContainsKey('CursorBg') -and $props.CursorBg.Color) {
                    [Colors]::CursorBg = & $hexToInt $props.CursorBg.Color
                } else {
                    [Colors]::CursorBg = [Colors]::Background
                }
                
                [Logger]::Log("ThemeApply: Theme '$($themeManager.PmcTheme.PaletteName)' applied to Colors class", 1)
                
                # Dump actual color values to verify
                [Logger]::Log("ThemeApply: Colors::Background = 0x$([Colors]::Background.ToString('X6'))", 1)
                [Logger]::Log("ThemeApply: Colors::PanelBg = 0x$([Colors]::PanelBg.ToString('X6'))", 1)
                [Logger]::Log("ThemeApply: Colors::Title = 0x$([Colors]::Title.ToString('X6'))", 1)
                [Logger]::Log("ThemeApply: Colors::SelectionBg = 0x$([Colors]::SelectionBg.ToString('X6'))", 1)
                [Logger]::Log("ThemeApply: Colors::SelectionFg = 0x$([Colors]::SelectionFg.ToString('X6'))", 1)
                [Logger]::Log("ThemeApply: Colors::Bright = 0x$([Colors]::Bright.ToString('X6'))", 1)

                } else {
                    [Logger]::Log("ThemeApply: Theme Properties is null or empty", 1)
                }
            } else {
                [Logger]::Log("ThemeApply: ThemeManager or PmcTheme is null", 1)
            }
        } else {
            [Logger]::Log("ThemeApply: PmcThemeManager type NOT found - theme files may not be loaded", 1)
        }
    } catch {
        [Logger]::Log("ThemeApply: Exception: $_", 3)
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
                    
                    if ($props.ContainsKey('Background.Primary') -and $props['Background.Primary'].Color) {
                        [Colors]::Background = & $hexToInt $props['Background.Primary'].Color
                    }
                    if ($props.ContainsKey('Surface') -and $props.Surface.Color) {
                        [Colors]::PanelBg = & $hexToInt $props.Surface.Color
                    } elseif ($props.ContainsKey('Background.Panel') -and $props['Background.Panel'].Color) {
                        [Colors]::PanelBg = & $hexToInt $props['Background.Panel'].Color
                    }
                    if ($props.ContainsKey('Border') -and $props.Border.Color) {
                        [Colors]::PanelBorder = & $hexToInt $props.Border.Color
                    } elseif ($props.ContainsKey('Border.Widget') -and $props['Border.Widget'].Color) {
                        [Colors]::PanelBorder = & $hexToInt $props['Border.Widget'].Color
                    }
                    if ($props.ContainsKey('Text') -and $props.Text.Color) {
                        [Colors]::Foreground = & $hexToInt $props.Text.Color
                    } elseif ($props.ContainsKey('OnSurface') -and $props.OnSurface.Color) {
                        [Colors]::Foreground = & $hexToInt $props.OnSurface.Color
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
                    # Selection - prioritize Background.Selection (specific) over Highlight (generic)
                    if ($props.ContainsKey('Background.Selection') -and $props['Background.Selection'].Color) {
                        [Colors]::SelectionBg = & $hexToInt $props['Background.Selection'].Color
                    } elseif ($props.ContainsKey('Highlight') -and $props.Highlight.Color) {
                        [Colors]::SelectionBg = & $hexToInt $props.Highlight.Color
                    }
                    
                    # SelectionFg
                    if ($props.ContainsKey('Foreground.Selection') -and $props['Foreground.Selection'].Color) {
                        [Colors]::SelectionFg = & $hexToInt $props['Foreground.Selection'].Color
                    } elseif ($props.ContainsKey('Bright') -and $props.Bright.Color) {
                        [Colors]::SelectionFg = & $hexToInt $props.Bright.Color
                    }
                    
                    # Title (for headers, column titles - was Cyan)
                    if ($props.ContainsKey('Title') -and $props.Title.Color) {
                        [Colors]::Title = & $hexToInt $props.Title.Color
                    } elseif ($props.ContainsKey('Header') -and $props.Header.Color) {
                        [Colors]::Title = & $hexToInt $props.Header.Color
                    } elseif ($props.ContainsKey('Primary') -and $props.Primary.Color) {
                        [Colors]::Title = & $hexToInt $props.Primary.Color
                    }
                    
                    # Muted (for secondary text - was Gray)
                    if ($props.ContainsKey('Muted') -and $props.Muted.Color) {
                        [Colors]::Muted = & $hexToInt $props.Muted.Color
                    } elseif ($props.ContainsKey('Label') -and $props.Label.Color) {
                        [Colors]::Muted = & $hexToInt $props.Label.Color
                    }
                    
                    # Bright (for emphasis - was White)
                    if ($props.ContainsKey('Bright') -and $props.Bright.Color) {
                        [Colors]::Bright = & $hexToInt $props.Bright.Color
                    } elseif ($props.ContainsKey('Foreground.Accent') -and $props['Foreground.Accent'].Color) {
                        [Colors]::Bright = & $hexToInt $props['Foreground.Accent'].Color
                    }
                    
                    # Cursor (for text cursor display)
                    if ($props.ContainsKey('Cursor') -and $props.Cursor.Color) {
                        [Colors]::Cursor = & $hexToInt $props.Cursor.Color
                    } else {
                        [Colors]::Cursor = [Colors]::Foreground
                    }
                    if ($props.ContainsKey('CursorBg') -and $props.CursorBg.Color) {
                        [Colors]::CursorBg = & $hexToInt $props.CursorBg.Color
                    } else {
                        [Colors]::CursorBg = [Colors]::Background
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

