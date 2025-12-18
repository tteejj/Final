# Start-PmcTUI - Entry point for new PMC TUI architecture
# Replaces old ConsoleUI.Core.ps1 monolithic approach

param(
    [switch]$DebugLog,      # Enable debug logging to file
    [int]$LogLevel = 0      # 0=off, 1=errors only, 2=info, 3=verbose
)

Set-StrictMode -Version Latest

# PORTABILITY: Helper function to write debug logs to portable path
# Uses $global:PmcDebugLogPath set by start.ps1, or creates fallback in data/logs/
function Write-PmcDebugLog {
    param([string]$Message)
    
    # Determine log path (prefer global set by start.ps1)
    $debugLogPath = if (Test-Path variable:global:PmcDebugLogPath) { $global:PmcDebugLogPath } else { $null }
    if (-not $debugLogPath) {
        # Fallback: create path relative to script location
        $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        $logDir = Join-Path $root "data/logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $debugLogPath = Join-Path $logDir "pmc-debug.log"
        $global:PmcDebugLogPath = $debugLogPath
    }
    
    try {
        Add-Content -Path $debugLogPath -Value $Message -ErrorAction SilentlyContinue
    } catch {
        # Silently fail - don't crash app for logging issues
    }
}

# Setup logging (DISABLED BY DEFAULT for performance)
# M-CFG-1: Configurable Log Path - uses environment variable or local directory for portability
# PORTABILITY: Default to .pmc-data/logs directory relative to module root (self-contained)
# IMPORTANT: Check PMC_TUI_LOG_LEVEL environment variable (set by external config)
$effectiveLogLevel = if ($LogLevel -gt 0) { $LogLevel } else { [int]($env:PMC_TUI_LOG_LEVEL -as [int]) }

if ($DebugLog -or $effectiveLogLevel -gt 0) {
    try {
        $logPath = $null

        # Try environment variable first, but validate it's safe
        if ($env:PMC_LOG_PATH) {
            # SECURITY: Only use Windows paths on Windows, Unix paths on Linux
            if ($PSVersionTable.Platform -eq 'Win32NT' -or $IsWindows) {
                if ($env:PMC_LOG_PATH -match '^[A-Z]:' -or $env:PMC_LOG_PATH -match '^\\\\') {
                    $logPath = $env:PMC_LOG_PATH
                }
            } elseif ($PSVersionTable.Platform -eq 'Unix' -or -not $IsWindows) {
                if ($env:PMC_LOG_PATH -match '^/' -or $env:PMC_LOG_PATH -match '^\./') {
                    $logPath = $env:PMC_LOG_PATH
                }
            }
        }

        # Fallback to default location
        if (-not $logPath) {
            $moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $logPath = Join-Path $moduleRoot ".pmc-data/logs"
        }

        # Create directory if needed
        if (-not (Test-Path $logPath)) {
            New-Item -ItemType Directory -Path $logPath -Force -ErrorAction Stop | Out-Null
        }

        $global:PmcTuiLogFile = Join-Path $logPath "pmc-tui-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        $global:PmcTuiLogLevel = $effectiveLogLevel
        Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [Start-PmcTUI] Debug logging enabled: $global:PmcTuiLogFile (Level $effectiveLogLevel)"
    }
    catch {
        # If log setup fails, disable logging and continue
        Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [Start-PmcTUI] WARNING: Failed to setup logging: $_"
        $global:PmcTuiLogFile = $null
        $global:PmcTuiLogLevel = 0
    }
}
else {
    $global:PmcTuiLogFile = $null
    $global:PmcTuiLogLevel = 0
}

# PERFORMANCE FIX: Global flag to disable ALL debug logging
# Set to $false to disable pmc-flow-debug.log writes (huge performance gain)
$global:PmcEnableFlowDebug = $false

function Write-PmcTuiLog {
    param([string]$Message, [string]$Level = "INFO")

    # Skip if logging disabled
    if (-not $global:PmcTuiLogFile) { return }

    # Filter by log level
    $levelValue = switch ($Level) {
        "ERROR" { 1 }
        "INFO" { 2 }
        "DEBUG" { 3 }
        default { 2 }
    }

    if ($levelValue -gt $global:PmcTuiLogLevel) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logLine = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $global:PmcTuiLogFile -Value $logLine -ErrorAction Stop
    }
    catch {
        # Silently fail on log write errors to prevent cascading failures
        # This can happen if path is invalid or disk is full
        if ($Level -eq "ERROR") {
            Write-PmcDebugLog $logLine
        }
    }
    if ($Level -eq "ERROR") {
        Write-PmcDebugLog $logLine
    }
}

Write-PmcTuiLog "Loading PMC module..." "INFO"

try {
    # Import PMC module for data functions
    Import-Module "$PSScriptRoot/../Pmc.Strict.psd1" -Force -ErrorAction Stop
    Write-PmcTuiLog "PMC module loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load PMC module: $_" "ERROR"
    Write-PmcTuiLog $_.ScriptStackTrace "ERROR"
    throw
}

Write-PmcTuiLog "Loading dependencies (FieldSchemas, etc.)..." "INFO"

try {
    . "$PSScriptRoot/DepsLoader.ps1"
    Write-PmcTuiLog "Dependencies loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load dependencies: $_" "ERROR"
    Write-PmcTuiLog $_.ScriptStackTrace "ERROR"
    throw
}

# ============================================================================
# MANUAL LOADING - Direct loads in correct dependency order
# ============================================================================

Write-PmcTuiLog "Loading SpeedTUI framework..." "INFO"
try {
    . "$PSScriptRoot/SpeedTUILoader.ps1"
    Write-PmcTuiLog "SpeedTUI framework loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load SpeedTUI: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading PraxisVT..." "INFO"
try {
    . "$PSScriptRoot/../src/PraxisVT.ps1"
    Write-PmcTuiLog "PraxisVT loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load PraxisVT: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading core dependencies..." "INFO"
try {
    # Core infrastructure (no dependencies)
    . "$PSScriptRoot/ZIndex.ps1"
    . "$PSScriptRoot/src/PmcThemeEngine.ps1"
    . "$PSScriptRoot/theme/PmcThemeManager.ps1"
    . "$PSScriptRoot/layout/PmcLayoutManager.ps1"

    Write-PmcTuiLog "Core dependencies loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load core dependencies: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading widget base classes..." "INFO"
try {
    # Base widget classes (PmcWidget needs SpeedTUI Component + PmcThemeEngine)
    . "$PSScriptRoot/widgets/PmcWidget.ps1"
    . "$PSScriptRoot/widgets/PmcDialog.ps1"

    Write-PmcTuiLog "Widget base classes loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load widget base classes: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading services..." "INFO"
try {
    # Load services BEFORE widgets (ProjectPicker depends on TaskStore)
    . "$PSScriptRoot/services/ChecklistService.ps1"
    . "$PSScriptRoot/services/CommandService.ps1"
    . "$PSScriptRoot/services/ExcelComReader.ps1"
    . "$PSScriptRoot/services/ExcelMappingService.ps1"
    . "$PSScriptRoot/services/MenuRegistry.ps1"
    . "$PSScriptRoot/services/NoteService.ps1"
    . "$PSScriptRoot/services/PreferencesService.ps1"
    . "$PSScriptRoot/services/TaskStore.ps1"
    Write-PmcTuiLog "Services loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load services: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading helpers..." "INFO"
try {
    # Load helpers BEFORE widgets (TextAreaEditor depends on GapBuffer)
    . "$PSScriptRoot/helpers/ConfigCache.ps1"
    . "$PSScriptRoot/helpers/Constants.ps1"
    . "$PSScriptRoot/helpers/DataBindingHelper.ps1"
    . "$PSScriptRoot/helpers/GapBuffer.ps1"
    . "$PSScriptRoot/helpers/LinuxKeyHelper.ps1"
    . "$PSScriptRoot/helpers/ShortcutRegistry.ps1"
    . "$PSScriptRoot/helpers/ThemeHelper.ps1"
    . "$PSScriptRoot/helpers/TypeNormalization.ps1"
    . "$PSScriptRoot/helpers/ValidationHelper.ps1"
    Write-PmcTuiLog "Helpers loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load helpers: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading widgets..." "INFO"
try {
    # All widgets (inherit from PmcWidget) - MUST load before PmcScreen
    # IMPORTANT: Load TextInput and ProjectPicker BEFORE InlineEditor (which depends on them)
    . "$PSScriptRoot/widgets/TextInput.ps1"
    . "$PSScriptRoot/widgets/ProjectPicker.ps1"
    . "$PSScriptRoot/widgets/DatePicker.ps1"
    . "$PSScriptRoot/widgets/FilterPanel.ps1"
    . "$PSScriptRoot/widgets/InlineEditor.ps1"
    . "$PSScriptRoot/widgets/PmcFilePicker.ps1"
    . "$PSScriptRoot/widgets/PmcFooter.ps1"
    . "$PSScriptRoot/widgets/PmcHeader.ps1"
    . "$PSScriptRoot/widgets/PmcMenuBar.ps1"
    . "$PSScriptRoot/widgets/PmcPanel.ps1"
    . "$PSScriptRoot/widgets/PmcStatusBar.ps1"
    . "$PSScriptRoot/widgets/SimpleFilePicker.ps1"
    . "$PSScriptRoot/widgets/TabPanel.ps1"
    . "$PSScriptRoot/widgets/TagEditor.ps1"
    . "$PSScriptRoot/widgets/TextAreaEditor.ps1"
    . "$PSScriptRoot/widgets/TimeEntryDetailDialog.ps1"
    . "$PSScriptRoot/widgets/UniversalList.ps1"
    Write-PmcTuiLog "Widgets loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load widgets: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading screen base class..." "INFO"
try {
    # PmcScreen base (uses PmcHeader, PmcFooter, PmcMenuBar - MUST be after widgets)
    . "$PSScriptRoot/PmcScreen.ps1"

    Write-PmcTuiLog "Screen base class loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load screen base: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading HelpViewScreen (needed by base classes)..." "INFO"
try {
    # Load HelpViewScreen FIRST (StandardListScreen depends on it)
    . "$PSScriptRoot/screens/HelpViewScreen.ps1"
    Write-PmcTuiLog "HelpViewScreen loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load HelpViewScreen: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading base classes..." "INFO"
try {
    . "$PSScriptRoot/base/StandardDashboard.ps1"
    . "$PSScriptRoot/base/StandardFormScreen.ps1"
    . "$PSScriptRoot/base/StandardListScreen.ps1"
    . "$PSScriptRoot/base/TabbedScreen.ps1"
    Write-PmcTuiLog "Base classes loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load base classes: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading ServiceContainer (needed by screens)..." "INFO"
try {
    # Load ServiceContainer BEFORE screens (TaskListScreen depends on it)
    . "$PSScriptRoot/ServiceContainer.ps1"
    Write-PmcTuiLog "ServiceContainer loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load ServiceContainer: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading remaining screens..." "INFO"
try {
    # Load remaining screens AFTER base classes (they inherit from StandardListScreen, etc.)
    . "$PSScriptRoot/screens/TaskListScreen.ps1"
    . "$PSScriptRoot/screens/ProjectListScreen.ps1"
    . "$PSScriptRoot/screens/ProjectInfoScreenV4.ps1"
    Write-PmcTuiLog "Remaining screens loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load screens: $_" "ERROR"
    throw
}

Write-PmcTuiLog "Loading PmcApplication..." "INFO"
try {
    . "$PSScriptRoot/PmcApplication.ps1"
    Write-PmcTuiLog "PmcApplication loaded" "INFO"
}
catch {
    Write-PmcTuiLog "Failed to load PmcApplication: $_" "ERROR"
    throw
}

Write-PmcTuiLog "All components loaded successfully" "INFO"

<#
.SYNOPSIS
Start PMC TUI with new architecture

.DESCRIPTION
Entry point for SpeedTUI-based PMC interface.
Creates application and launches screens.

.PARAMETER StartScreen
Which screen to launch (default: BlockedTasks)

.EXAMPLE
Start-PmcTUI
Start-PmcTUI -StartScreen BlockedTasks
#>
function Start-PmcTUI {
    param(
        [string]$StartScreen = "TaskList"
    )

    Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [Start-PmcTUI] Starting PMC TUI (SpeedTUI Architecture)..."
    Write-PmcTuiLog "Starting PMC TUI with screen: $StartScreen" "INFO"

    try {
        # === Clear stale global state ===
        # CRITICAL FIX: Clear shared menu bar and registry singleton to ensure fresh menus are loaded
        # This fixes the issue where Notes and Checklist screens don't appear after manifest updates
        $global:PmcSharedMenuBar = $null

        # Clear MenuRegistry singleton (it caches menu items across sessions)
        if ([MenuRegistry]) {
            [MenuRegistry]::_instance = $null
        }
        Write-PmcTuiLog "Cleared stale PmcSharedMenuBar and MenuRegistry singleton" "INFO"

        # === Create DI Container ===
        Write-PmcTuiLog "Creating ServiceContainer..." "INFO"
        $global:PmcContainer = [ServiceContainer]::new()
        Write-PmcTuiLog "ServiceContainer created" "INFO"

        # === Register Core Services (in dependency order) ===

        # 1. Theme (no dependencies)
        Write-PmcTuiLog "Registering Theme service..." "INFO"
        $global:PmcContainer.Register('Theme', {
                param($container)
                Write-PmcTuiLog "Resolving Theme: Calling Initialize-PmcThemeSystem..." "INFO"
                Initialize-PmcThemeSystem
                $theme = Get-PmcState -Section 'Display' | Select-Object -ExpandProperty Theme
                Write-PmcTuiLog "Theme resolved: $($theme.Hex)" "INFO"

                # CRITICAL FIX: Initialize PmcThemeEngine with theme data from PMC palette
                Write-PmcTuiLog "Loading PmcThemeEngine..." "INFO"
                $engine = [PmcThemeEngine]::GetInstance()

                # Get PMC color palette (derived from theme hex)
                $palette = Get-PmcColorPalette

                # Convert RGB objects to hex strings for PmcThemeEngine
                $paletteHex = @{}
                foreach ($key in $palette.Keys) {
                    $rgb = $palette[$key]
                    $currentHex = "#{0:X2}{1:X2}{2:X2}" -f $rgb.R, $rgb.G, $rgb.B
                    $paletteHex[$key] = $currentHex
                    Write-PmcTuiLog "Palette [$key] -> $currentHex (R=$($rgb.R) G=$($rgb.G) B=$($rgb.B))" "DEBUG"
                }

                # Define Default Properties (Explicitly, no engine fallbacks)
                $p = $paletteHex
                $properties = @{
                    'Background.Field'        = @{ Type = 'Solid'; Color = '#000000' }
                    'Background.FieldFocused' = @{ Type = 'Solid'; Color = $p['Primary'] }
                    'Background.Row'          = @{ Type = 'Solid'; Color = '#000000' }
                    'Background.RowSelected'  = @{ Type = 'Solid'; Color = $p['Primary'] }
                    'Background.Warning'      = @{ Type = 'Solid'; Color = $p['Warning'] }
                    'Background.MenuBar'      = @{ Type = 'Solid'; Color = $p['Border'] }
                    'Foreground.Field'        = @{ Type = 'Solid'; Color = $p['Text'] }
                    'Foreground.FieldFocused' = @{ Type = 'Solid'; Color = '#FFFFFF' }
                    'Foreground.Row'          = @{ Type = 'Solid'; Color = $p['Text'] }
                    'Foreground.RowSelected'  = @{ Type = 'Solid'; Color = '#FFFFFF' }
                    'Foreground.Title'        = @{ Type = 'Solid'; Color = $p['Primary'] }
                    'Foreground.Muted'        = @{ Type = 'Solid'; Color = $p['Muted'] }
                    'Foreground.Warning'      = @{ Type = 'Solid'; Color = $p['Warning'] }
                    'Foreground.Error'        = @{ Type = 'Solid'; Color = $p['Error'] }
                    'Foreground.Success'      = @{ Type = 'Solid'; Color = $p['Success'] }
                    'Border.Widget'           = @{ Type = 'Solid'; Color = $p['Border'] }
                    'Background.TabActive'    = @{ Type = 'Solid'; Color = $p['Primary'] }
                    'Background.TabInactive'  = @{ Type = 'Solid'; Color = '#333333' }
                    'Foreground.TabActive'    = @{ Type = 'Solid'; Color = '#FFFFFF' }
                    'Foreground.TabInactive'  = @{ Type = 'Solid'; Color = $p['Muted'] }
                    'Background.Primary'      = @{ Type = 'Solid'; Color = '#000000' }
                    'Background.Widget'       = @{ Type = 'Solid'; Color = '#1a1a1a' }
                    'Foreground.Primary'      = @{ Type = 'Solid'; Color = $p['Text'] }
                }

                # Load theme config with palette AND properties
                $themeConfig = @{
                    Palette    = $paletteHex
                    Properties = $properties
                }
                $engine.LoadFromConfig($themeConfig)
                Write-PmcTuiLog "PmcThemeEngine initialized with PMC palette ($($paletteHex.Count) colors)" "INFO"

                return $theme
            }, $true)

        # Register ThemeManager (depends on Theme)
        Write-PmcTuiLog "Registering ThemeManager..." "INFO"
        $global:PmcContainer.Register('ThemeManager', {
                param($container)
                Write-PmcTuiLog "Resolving ThemeManager..." "INFO"
                $null = $container.Resolve('Theme')
                return [PmcThemeManager]::GetInstance()
            }, $true)

        # 2. Config (no dependencies) - CACHED for performance
        Write-PmcTuiLog "Registering Config service..." "INFO"
        $global:PmcContainer.Register('Config', {
                param($container)
                Write-PmcTuiLog "Resolving Config..." "INFO"

                # Determine config path (same logic as Get-PmcConfig)
                # CRITICAL FIX: Use workspace root (three levels up from module dir)
                $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
                $configPath = Join-Path $root 'config.json'

                # Use cached config for performance (eliminates repeated file I/O)
                try {
                    return [ConfigCache]::GetConfig($configPath)
                }
                catch {
                    Write-PmcTuiLog "Config load failed, falling back to Get-PmcConfig: $_" "ERROR"
                    # Fallback to original method if cache fails
                    return Get-PmcConfig
                }
            }, $true)

        # 3. TaskStore (depends on Theme via state)
        Write-PmcTuiLog "Registering TaskStore service..." "INFO"
        $global:PmcContainer.Register('TaskStore', {
                param($container)
                Write-PmcTuiLog "Resolving TaskStore..." "INFO"
                # Ensure theme is initialized first
                $null = $container.Resolve('Theme')
                return [TaskStore]::GetInstance()
            }, $true)

        # 4. MenuRegistry (depends on Theme)
        Write-PmcTuiLog "Registering MenuRegistry service..." "INFO"
        $global:PmcContainer.Register('MenuRegistry', {
                param($container)
                Write-PmcTuiLog "Resolving MenuRegistry..." "INFO"
                # Ensure theme is initialized first
                $null = $container.Resolve('Theme')
                return [MenuRegistry]::GetInstance()
            }, $true)

        # 5. Application (depends on Theme)
        Write-PmcTuiLog "Registering Application service..." "INFO"
        $global:PmcContainer.Register('Application', {
                param($container)
                Write-PmcTuiLog "Resolving Application..." "INFO"
                # Ensure theme is initialized first
                $null = $container.Resolve('Theme')
                return [PmcApplication]::new($container)
            }, $true)

        # 6. CommandService (no dependencies)
        Write-PmcTuiLog "Registering CommandService..." "INFO"
        $global:PmcContainer.Register('CommandService', {
                param($container)
                Write-PmcTuiLog "Resolving CommandService..." "INFO"
                return [CommandService]::GetInstance()
            }, $true)

        # 7. ChecklistService (no dependencies)
        Write-PmcTuiLog "Registering ChecklistService..." "INFO"
        $global:PmcContainer.Register('ChecklistService', {
                param($container)
                Write-PmcTuiLog "Resolving ChecklistService..." "INFO"
                return [ChecklistService]::GetInstance()
            }, $true)

        # 8. NoteService (no dependencies)
        Write-PmcTuiLog "Registering NoteService..." "INFO"
        $global:PmcContainer.Register('NoteService', {
                param($container)
                Write-PmcTuiLog "Resolving NoteService..." "INFO"
                return [NoteService]::GetInstance()
            }, $true)

        # 9. ExcelMappingService (no dependencies)
        Write-PmcTuiLog "Registering ExcelMappingService..." "INFO"
        $global:PmcContainer.Register('ExcelMappingService', {
                param($container)
                Write-PmcTuiLog "Resolving ExcelMappingService..." "INFO"
                return [ExcelMappingService]::GetInstance()
            }, $true)

        # 10. PreferencesService (no dependencies)
        Write-PmcTuiLog "Registering PreferencesService..." "INFO"
        $global:PmcContainer.Register('PreferencesService', {
                param($container)
                Write-PmcTuiLog "Resolving PreferencesService..." "INFO"
                return [PreferencesService]::GetInstance()
            }, $true)

        # 11. Screen factories (depend on Application, TaskStore, etc.)
        Write-PmcTuiLog "Registering screen factories..." "INFO"

        $global:PmcContainer.Register('TaskListScreen', {
                param($container)
                Write-PmcTuiLog "Resolving TaskListScreen..." "INFO"
                # Ensure dependencies
                $null = $container.Resolve('Theme')
                $null = $container.Resolve('TaskStore')
                return [TaskListScreen]::new($container)
            }, $false)  # Not singleton - create new instance each time

        # === Resolve Application ===
        Write-PmcTuiLog "Resolving Application from container..." "INFO"
        $global:PmcApp = $global:PmcContainer.Resolve('Application')
        Write-PmcTuiLog "Application resolved and assigned to `$global:PmcApp" "INFO"

        # === Load Menus from Manifest ===
        Write-PmcTuiLog "Loading menus from manifest..." "INFO"
        $menuRegistry = $global:PmcContainer.Resolve('MenuRegistry')
        $manifestPath = Join-Path $PSScriptRoot "screens/MenuItems.psd1"
        if (Test-Path $manifestPath) {
            $menuRegistry.LoadFromManifest($manifestPath, $global:PmcContainer)
            Write-PmcTuiLog "Menus loaded from $manifestPath" "INFO"
        }
        else {
            Write-PmcTuiLog "Menu manifest not found at $manifestPath" "ERROR"
        }

        # === Launch Initial Screen ===
        Write-PmcTuiLog "Launching screen: $StartScreen" "INFO"
        switch ($StartScreen) {
            'TaskList' {
                Write-PmcTuiLog "Resolving TaskListScreen from container..." "INFO"
                $screen = $global:PmcContainer.Resolve('TaskListScreen')
                Write-PmcTuiLog "Pushing screen to app..." "INFO"
                try {
                    $global:PmcApp.PushScreen($screen)
                    Write-PmcTuiLog "Screen pushed successfully" "INFO"
                }
                catch {
                    Add-Content -Path "$(Join-Path ([System.IO.Path]::GetTempPath()) 'pmc_debug.txt')" -Value "[$(Get-Date)] FATAL ERROR IN PUSHSCREEN: $_"
                    Add-Content -Path "$(Join-Path ([System.IO.Path]::GetTempPath()) 'pmc_debug.txt')" -Value "[$(Get-Date)] Stack Trace: $($_.ScriptStackTrace)"
                    throw
                }

            }
            'BlockedTasks' {
                Write-PmcTuiLog "Creating BlockedTasksScreen with container..." "INFO"
                $screen = [BlockedTasksScreen]::new($global:PmcContainer)
                Write-PmcTuiLog "Pushing screen to app..." "INFO"
                $global:PmcApp.PushScreen($screen)
                Write-PmcTuiLog "Screen pushed successfully" "INFO"
            }
            'Demo' {
                Write-PmcTuiLog "Loading DemoScreen (not containerized)..." "INFO"
                . "$PSScriptRoot/DemoScreen.ps1"
                $screen = [DemoScreen]::new()
                $global:PmcApp.PushScreen($screen)
                Write-PmcTuiLog "Demo screen pushed" "INFO"
            }
            default {
                Write-PmcTuiLog "Unknown screen: $StartScreen" "ERROR"
                throw "Unknown screen: $StartScreen"
            }
        }

        # Run event loop
        Write-PmcTuiLog "Starting event loop..." "INFO"
        $global:PmcApp.Run()
        Write-PmcTuiLog "Event loop exited normally" "INFO"

    }
    catch {
        Write-PmcTuiLog "EXCEPTION: $_" "ERROR"
        Write-PmcTuiLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        Write-PmcTuiLog "Exception details: $($_.Exception | Out-String)" "ERROR"

        Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [Start-PmcTUI] PMC TUI Error: $_"
        Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [Start-PmcTUI] Log file: $global:PmcTuiLogFile"
        Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [Start-PmcTUI] Stack trace: $($_.ScriptStackTrace)"
        throw
    }
    finally {
        # Cleanup
        Write-PmcTuiLog "Cleanup - showing cursor and resetting terminal" "INFO"
        Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [Start-PmcTUI] Log saved to: $global:PmcTuiLogFile"
    }
}

# Allow direct execution
# Allow direct execution
Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [Start-PmcTUI] DEBUG: InvocationName='$($MyInvocation.InvocationName)' MyCommand='$($MyInvocation.MyCommand.Name)'"
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.InvocationName -ne '&') {
    Start-PmcTUI @args
}