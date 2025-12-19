# PreferencesService.ps1 - User preferences persistence
#
# M-CFG-2: Preferences Persistence
# Saves and loads user preferences like sort order, view modes, column widths,
# theme settings, and other user-specific configuration.
#
# Usage:
#   $prefs = [PreferencesService]::GetInstance()
#   $prefs.SetPreference('defaultViewMode', 'active')
#   $viewMode = $prefs.GetPreference('defaultViewMode', 'all')
#   $prefs.SavePreferences()

using namespace System
using namespace System.IO
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

<#
.SYNOPSIS
User preferences persistence service

.DESCRIPTION
Singleton service that manages user preferences for PMC TUI.
Preferences are stored in JSON format in the user's config directory.

Supported preferences:
- defaultViewMode: Default task list view (all, active, blocked, etc.)
- defaultSortColumn: Default column to sort by
- defaultSortAscending: Default sort direction
- defaultPriority: Default priority for new tasks
- showCompleted: Show completed tasks by default
- columnWidths: Custom column widths
- theme: Selected theme name
- useSymbols: Use Unicode symbols vs text alternatives
- dateFormat: Preferred date format
- timeFormat: Preferred time format

.EXAMPLE
$prefs = [PreferencesService]::GetInstance()
$prefs.SetPreference('defaultViewMode', 'active')
$prefs.SavePreferences()
#>
class PreferencesService {
    # Singleton instance
    static [PreferencesService]$_instance = $null

    # Preferences storage
    hidden [hashtable]$_preferences = @{}

    # File path for preferences
    hidden [string]$_preferencesPath = ""

    # Dirty flag for unsaved changes
    hidden [bool]$_isDirty = $false

    # Default preferences
    hidden [hashtable]$_defaults = @{
        # View preferences
        defaultViewMode = 'active'
        defaultSortColumn = 'due'
        defaultSortAscending = $true
        showCompleted = $false

        # Task defaults
        defaultPriority = 'medium'
        defaultStatus = 'pending'

        # UI preferences
        useSymbols = $true
        dateFormat = 'yyyy-MM-dd'
        timeFormat = 'HH:mm'
        theme = 'default'

        # Column widths (null means auto)
        columnWidths = @{
            title = $null
            due = 10
            priority = 10
            status = 12
            project = 20
            tags = 15
        }

        # Performance preferences
        enableVirtualScrolling = $true
        maxVisibleRows = 1000
        searchDebounceMs = 150
        cacheRefreshIntervalMs = 500
        showEditorStatistics = $false

        # Accessibility
        screenReaderMode = $false
        highContrastMode = $false
        largeFont = $false

        # Auto-save preferences
        autoSaveEnabled = $true
        autoSaveIntervalSeconds = 300
    }

    # === Singleton Pattern ===

    <#
    .SYNOPSIS
    Get the singleton instance of PreferencesService

    .OUTPUTS
    PreferencesService singleton instance
    #>
    static [PreferencesService] GetInstance() {
        if ($null -eq [PreferencesService]::_instance) {
            [PreferencesService]::_instance = [PreferencesService]::new()
        }
        return [PreferencesService]::_instance
    }

    # Private constructor for singleton
    hidden PreferencesService() {
        $this._InitializePreferencesPath()
        $this._LoadPreferences()
    }

    # === Initialization ===

    <#
    .SYNOPSIS
    Initialize preferences file path

    .DESCRIPTION
    Determines where to store preferences based on environment and platform
    #>
    hidden [void] _InitializePreferencesPath() {
        # PORTABILITY: Use local directory for self-contained deployment
        # Priority: ENV > Get-PmcConfigPath > Local .pmc-data directory
        $configPath = $(if ($env:PMC_CONFIG_PATH) {
            # Explicit override via environment variable
            $env:PMC_CONFIG_PATH
        } elseif (Get-Command Get-PmcConfigPath -ErrorAction SilentlyContinue) {
            # Use PMC module's config path if available
            Get-PmcConfigPath
        } else {
            # Default: Use .pmc-data directory relative to module root (self-contained)
            $moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            Join-Path $moduleRoot ".pmc-data"
        })

        # Ensure directory exists
        if (-not (Test-Path $configPath)) {
            New-Item -ItemType Directory -Path $configPath -Force | Out-Null
        }

        $this._preferencesPath = Join-Path $configPath "preferences.json"

        if ((Get-Variable -Name 'PmcTuiLogFile' -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PreferencesService: Preferences path: $($this._preferencesPath)"
        }
    }

    <#
    .SYNOPSIS
    Load preferences from file

    .DESCRIPTION
    Loads preferences from JSON file, validates them, and merges with defaults
    #>
    hidden [void] _LoadPreferences() {
        try {
            if (Test-Path $this._preferencesPath) {
                $json = Get-Content -Path $this._preferencesPath -Raw
                $loaded = $json | ConvertFrom-Json -AsHashtable

                if ((Get-Variable -Name 'PmcTuiLogFile' -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PreferencesService: Loaded preferences from file"
                }

                # M-CFG-6: Config Validation - validate loaded preferences
                $validated = $this._ValidatePreferences($loaded)

                # Merge with defaults (defaults for missing keys)
                $this._preferences = $this._MergeWithDefaults($validated)
                $this._isDirty = $false
            } else {
                if ((Get-Variable -Name 'PmcTuiLogFile' -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PreferencesService: No preferences file found, using defaults"
                }

                # Use defaults
                $this._preferences = $this._defaults.Clone()
                $this._isDirty = $true  # Mark dirty to save defaults
            }
        } catch {
            if ((Get-Variable -Name 'PmcTuiLogFile' -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PreferencesService: Error loading preferences: $_"
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PreferencesService: Using defaults"
            }

            # On error, use defaults
            $this._preferences = $this._defaults.Clone()
            $this._isDirty = $true
        }
    }

    # === Validation ===

    <#
    .SYNOPSIS
    Validate preferences object

    .PARAMETER prefs
    Preferences hashtable to validate

    .OUTPUTS
    Validated preferences hashtable

    .DESCRIPTION
    M-CFG-6: Config Validation
    Validates each preference value, removes invalid ones, uses defaults for invalid values
    #>
    hidden [hashtable] _ValidatePreferences([hashtable]$prefs) {
        $validated = @{}

        # Validate each preference
        foreach ($key in $prefs.Keys) {
            $value = $prefs[$key]

            switch ($key) {
                'defaultViewMode' {
                    $validModes = @('all', 'active', 'completed', 'blocked', 'overdue', 'today', 'tomorrow', 'week', 'nextactions', 'noduedate', 'month', 'agenda', 'upcoming')
                    if ($value -in $validModes) {
                        $validated[$key] = $value
                    }
                }
                'defaultSortColumn' {
                    $validColumns = @('title', 'due', 'priority', 'status', 'project', 'created', 'modified')
                    if ($value -in $validColumns) {
                        $validated[$key] = $value
                    }
                }
                'defaultPriority' {
                    $validPriorities = @('high', 'medium', 'low', 'none')
                    if ($value -in $validPriorities) {
                        $validated[$key] = $value
                    }
                }
                'defaultStatus' {
                    $validStatuses = @('pending', 'active', 'completed', 'blocked', 'cancelled', 'deferred')
                    if ($value -in $validStatuses) {
                        $validated[$key] = $value
                    }
                }
                'defaultSortAscending' {
                    if ($value -is [bool]) {
                        $validated[$key] = $value
                    }
                }
                'showCompleted' {
                    if ($value -is [bool]) {
                        $validated[$key] = $value
                    }
                }
                'useSymbols' {
                    if ($value -is [bool]) {
                        $validated[$key] = $value
                    }
                }
                'enableVirtualScrolling' {
                    if ($value -is [bool]) {
                        $validated[$key] = $value
                    }
                }
                'maxVisibleRows' {
                    if ($value -is [int] -and $value -gt 0 -and $value -le 10000) {
                        $validated[$key] = $value
                    }
                }
                'searchDebounceMs' {
                    if ($value -is [int] -and $value -ge 0 -and $value -le 5000) {
                        $validated[$key] = $value
                    }
                }
                'cacheRefreshIntervalMs' {
                    if ($value -is [int] -and $value -ge 0 -and $value -le 10000) {
                        $validated[$key] = $value
                    }
                }
                'showEditorStatistics' {
                    if ($value -is [bool]) {
                        $validated[$key] = $value
                    }
                }
                'autoSaveIntervalSeconds' {
                    if ($value -is [int] -and $value -ge 30 -and $value -le 3600) {
                        $validated[$key] = $value
                    }
                }
                default {
                    # For unknown keys or complex types (columnWidths, etc), just pass through
                    $validated[$key] = $value
                }
            }
        }

        return $validated
    }

    <#
    .SYNOPSIS
    Merge preferences with defaults

    .PARAMETER prefs
    User preferences hashtable

    .OUTPUTS
    Merged hashtable with defaults filled in for missing keys
    #>
    hidden [hashtable] _MergeWithDefaults([hashtable]$prefs) {
        $merged = $this._defaults.Clone()

        foreach ($key in $prefs.Keys) {
            $merged[$key] = $prefs[$key]
        }

        return $merged
    }

    # === Public API ===

    <#
    .SYNOPSIS
    Get a preference value

    .PARAMETER key
    Preference key

    .PARAMETER defaultValue
    Default value if key doesn't exist (optional, uses system default if not provided)

    .OUTPUTS
    Preference value or default
    #>
    [object] GetPreference([string]$key) {
        if ($this._preferences.ContainsKey($key)) {
            return $this._preferences[$key]
        }

        if ($this._defaults.ContainsKey($key)) {
            return $this._defaults[$key]
        }

        return $null
    }

    [object] GetPreference([string]$key, [object]$defaultValue) {
        if ($this._preferences.ContainsKey($key)) {
            return $this._preferences[$key]
        }

        return $defaultValue
    }

    <#
    .SYNOPSIS
    Set a preference value

    .PARAMETER key
    Preference key

    .PARAMETER value
    Preference value

    .DESCRIPTION
    Sets a preference and marks preferences as dirty (needing save)
    #>
    [void] SetPreference([string]$key, [object]$value) {
        $this._preferences[$key] = $value
        $this._isDirty = $true

        if ((Get-Variable -Name 'PmcTuiLogFile' -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PreferencesService: Set preference '$key' = '$value'"
        }
    }

    <#
    .SYNOPSIS
    Get all preferences

    .OUTPUTS
    Hashtable of all current preferences
    #>
    [hashtable] GetAllPreferences() {
        return $this._preferences.Clone()
    }

    <#
    .SYNOPSIS
    Reset all preferences to defaults

    .DESCRIPTION
    M-CFG-4: Reset to Defaults functionality
    #>
    [void] ResetToDefaults() {
        $this._preferences = $this._defaults.Clone()
        $this._isDirty = $true

        if ((Get-Variable -Name 'PmcTuiLogFile' -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PreferencesService: Reset all preferences to defaults"
        }
    }

    <#
    .SYNOPSIS
    Reset a specific preference to its default

    .PARAMETER key
    Preference key to reset

    .DESCRIPTION
    M-CFG-4: Reset to Defaults functionality
    #>
    [void] ResetPreference([string]$key) {
        if ($this._defaults.ContainsKey($key)) {
            $this._preferences[$key] = $this._defaults[$key]
            $this._isDirty = $true

            if ((Get-Variable -Name 'PmcTuiLogFile' -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PreferencesService: Reset preference '$key' to default"
            }
        }
    }

    <#
    .SYNOPSIS
    Save preferences to file

    .DESCRIPTION
    Saves current preferences to JSON file
    #>
    [void] SavePreferences() {
        try {
            # Convert to JSON with nice formatting
            $json = $this._preferences | ConvertTo-Json -Depth 10

            # Save to file
            $json | Set-Content -Path $this._preferencesPath -Force

            $this._isDirty = $false

            if ((Get-Variable -Name 'PmcTuiLogFile' -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PreferencesService: Saved preferences to $($this._preferencesPath)"
            }
        } catch {
            if ((Get-Variable -Name 'PmcTuiLogFile' -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PreferencesService: Error saving preferences: $_"
            }
            throw
        }
    }

    <#
    .SYNOPSIS
    Check if preferences have unsaved changes

    .OUTPUTS
    Boolean indicating if preferences are dirty
    #>
    [bool] IsDirty() {
        return $this._isDirty
    }

    <#
    .SYNOPSIS
    Get the preferences file path

    .OUTPUTS
    String path to preferences file
    #>
    [string] GetPreferencesPath() {
        return $this._preferencesPath
    }
}

# Export for module usage
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Export-ModuleMember -Variable PreferencesService
    } catch {
        # Ignore Export-ModuleMember errors when not in a module context
    }
}