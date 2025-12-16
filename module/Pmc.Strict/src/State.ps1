# Centralized State Management for PMC
# Consolidates all scattered script variables into a thread-safe, organized system

Set-StrictMode -Version Latest

# =============================================================================
# CENTRAL STATE CONTAINER
# =============================================================================

# Single master state object containing all global state
$Script:PmcGlobalState = @{
    # System & Core Configuration
    Config = @{
        ProviderGet = { @{} }
        ProviderSet = $null
    }

    # Security System State
    Security = @{
        InputValidationEnabled = $true
        PathWhitelistEnabled = $true
        ResourceLimitsEnabled = $true
        SensitiveDataScanEnabled = $true
        AuditLoggingEnabled = $true
        TemplateExecutionEnabled = $false
        AllowedWritePaths = @()
        MaxFileSize = 100MB
        MaxMemoryUsage = 500MB
        MaxExecutionTime = 300000  # 5 minutes in milliseconds
    }

    # Debug System State
    Debug = @{
        Level = 0                    # 0=off, 1-3=debug levels
        LogPath = 'debug.log'        # Relative to PMC root
        MaxSize = 10MB              # File size before rotation
        RedactSensitive = $true     # Redact sensitive data
        IncludePerformance = $false # Include timing information
        SessionId = (New-Guid).ToString().Substring(0,8)
        StartTime = Get-Date
    }

    # Display / Theme / UI State
    Display = @{
        Theme = @{ PaletteName='default'; Hex='#33aaff'; TrueColor=$true; HighContrast=$false; ColorBlindMode='none' }
        Icons = @{ Mode='emoji' }
        Capabilities = @{ AnsiSupport=$true; TrueColorSupport=$true; IsTTY=$true; NoColor=$false; Platform='unknown' }
        Styles = @{}
    }

    # Help and UI System State
    HelpUI = @{
        # Interactive help browser state
        HelpState = @{
            CurrentCategory = 'All'
            SelectedCommand = 0
            SearchFilter = ''
            ShowExamples = $false
            ViewMode = 'Categories'  # Categories, Commands, Examples, Search
        }
        # Command categories for organized browsing (this will be populated from CommandMap)
        CommandCategories = @{}
    }

    # Interactive Editor State
    Interactive = @{
        Editor = $null              # Will be initialized with PmcEditorState instance
        CompletionCache = @{}       # Completion caching for performance
        CompletionInfoMap = @{}     # Completion info mapping for interactive system
        GhostTextEnabled = $true    # Enable/disable ghost text feature
    }

    # Focus / Context State
    Focus = @{
        Current = 'inbox'
    }

    # Undo/Redo System State
    UndoRedo = @{
        UndoStack = @()
        RedoStack = @()
        MaxUndoSteps = 5
        DataCache = $null           # Cached data for performance
    }

    # Task and Time Mapping State (consolidated from multiple files)
    ViewMappings = @{
        LastTaskListMap = @{}       # Maps display numbers to task IDs
        LastTimeListMap = @{}       # Maps display numbers to time entry IDs
    }

    # Command System State (schemas, maps, metadata)
    Commands = @{
        ParameterMap = @{}          # Parameter schemas from Schemas.ps1
        CommandMap = @{}            # Command mappings from CommandMap.ps1
        ShortcutMap = @{}           # Shortcut mappings from CommandMap.ps1
        CommandMeta = @{}           # Command metadata from CommandMap.ps1
    }

    # State synchronization lock
    _Lock = $false
}

# Convenience: repo root path
function Get-PmcRootPath {
    try {
        return (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent)
    } catch { return (Get-Location).Path }
}

# =============================================================================
# THREAD-SAFE STATE ACCESS FUNCTIONS
# =============================================================================

function Get-PmcState {
    <#
    .SYNOPSIS
    Gets a specific state section or the entire state object

    .PARAMETER Section
    The state section to retrieve (Config, Security, Debug, etc.)

    .PARAMETER Key
    Optional specific key within the section

    .EXAMPLE
    Get-PmcState -Section 'Security'
    Get-PmcState -Section 'Debug' -Key 'Level'
    #>
    [CmdletBinding()]
    param(
        [string]$Section,
        [string]$Key
    )

    # Acquire lock to ensure a consistent read snapshot
    while ($Script:PmcGlobalState._Lock) { Start-Sleep -Milliseconds 1 }
    $Script:PmcGlobalState._Lock = $true

    try {
        if (-not $Section) {
            # Return a shallow clone of the entire state without exposing the lock directly
            $snapshot = @{}
            foreach ($k in $Script:PmcGlobalState.Keys) {
                if ($k -eq '_Lock') { continue }
                $val = $Script:PmcGlobalState[$k]
                if ($val -is [hashtable]) { $snapshot[$k] = $val.Clone() } else { $snapshot[$k] = $val }
            }
            return $snapshot
        }

        if (-not $Script:PmcGlobalState.ContainsKey($Section)) {
            Write-Warning "State section '$Section' does not exist"
            return $null
        }

        $sectionState = $Script:PmcGlobalState[$Section]

        if ($Key) {
            if ($sectionState -is [hashtable] -and $sectionState.ContainsKey($Key)) {
                return $sectionState[$Key]
            } else {
                Write-Warning "State key '$Key' does not exist in section '$Section'"
                return $null
            }
        }

        # Return a copy to avoid external mutation of shared state
        if ($sectionState -is [hashtable]) { return $sectionState.Clone() }
        return $sectionState
    }
    finally {
        $Script:PmcGlobalState._Lock = $false
    }
}

function Set-PmcState {
    <#
    .SYNOPSIS
    Sets a value in the centralized state system

    .PARAMETER Section
    The state section to modify

    .PARAMETER Key
    The key within the section to set

    .PARAMETER Value
    The value to set

    .PARAMETER Merge
    If true, merge hashtable values instead of replacing

    .EXAMPLE
    Set-PmcState -Section 'Debug' -Key 'Level' -Value 2
    Set-PmcState -Section 'Security' -Key 'MaxFileSize' -Value 200MB
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Section,

        [Parameter(Mandatory=$true)]
        [string]$Key,

        [Parameter(Mandatory=$true)]
        $Value,

        [switch]$Merge
    )

    # Acquire lock for thread safety
    while ($Script:PmcGlobalState._Lock) {
        Start-Sleep -Milliseconds 1
    }
    $Script:PmcGlobalState._Lock = $true

    try {
        if (-not $Script:PmcGlobalState.ContainsKey($Section)) {
            Write-Warning "State section '$Section' does not exist"
            return
        }

        $sectionState = $Script:PmcGlobalState[$Section]

        if ($Merge -and $sectionState[$Key] -is [hashtable] -and $Value -is [hashtable]) {
            # Merge hashtables
            foreach ($k in $Value.Keys) {
                $sectionState[$Key][$k] = $Value[$k]
            }
        } else {
            # Direct assignment
            $sectionState[$Key] = $Value
        }

        # Debug logging removed to avoid circular dependency during initialization
    }
    finally {
        $Script:PmcGlobalState._Lock = $false
    }
}

# Convenience helpers for common view mapping state
function Get-PmcLastTaskListMap {
    $map = Get-PmcState -Section 'ViewMappings' -Key 'LastTaskListMap'
    if (-not $map) { $map = @{}; Set-PmcState -Section 'ViewMappings' -Key 'LastTaskListMap' -Value $map }
    return $map
}

function Set-PmcLastTaskListMap {
    param([hashtable]$Map)
    if (-not $Map) { $Map = @{} }
    Set-PmcState -Section 'ViewMappings' -Key 'LastTaskListMap' -Value $Map
}

function Get-PmcLastTimeListMap {
    $map = Get-PmcState -Section 'ViewMappings' -Key 'LastTimeListMap'
    if (-not $map) { $map = @{}; Set-PmcState -Section 'ViewMappings' -Key 'LastTimeListMap' -Value $map }
    return $map
}

function Set-PmcLastTimeListMap {
    param([hashtable]$Map)
    if (-not $Map) { $Map = @{} }
    Set-PmcState -Section 'ViewMappings' -Key 'LastTimeListMap' -Value $Map
}

function Update-PmcStateSection {
    <#
    .SYNOPSIS
    Updates an entire state section

    .PARAMETER Section
    The state section to update

    .PARAMETER Values
    Hashtable of values to update in the section

    .PARAMETER Replace
    If true, replace entire section; if false, merge values

    .EXAMPLE
    Update-PmcStateSection -Section 'Security' -Values @{ MaxFileSize = 200MB; PathWhitelistEnabled = $false }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Section,

        [Parameter(Mandatory=$true)]
        [hashtable]$Values,

        [switch]$Replace
    )

    # Acquire lock for thread safety
    while ($Script:PmcGlobalState._Lock) {
        Start-Sleep -Milliseconds 1
    }
    $Script:PmcGlobalState._Lock = $true

    try {
        if (-not $Script:PmcGlobalState.ContainsKey($Section)) {
            Write-Warning "State section '$Section' does not exist"
            return
        }

        if ($Replace) {
            $Script:PmcGlobalState[$Section] = $Values
        } else {
            foreach ($key in $Values.Keys) {
                $Script:PmcGlobalState[$Section][$key] = $Values[$key]
            }
        }

        # Debug logging removed to avoid circular dependency during initialization
    }
    finally {
        $Script:PmcGlobalState._Lock = $false
    }
}

# =============================================================================
# BACKWARD COMPATIBILITY LAYER
# =============================================================================

# These functions provide backward compatibility for existing code
# They map old script variable access to the new centralized state

function Get-PmcConfigProviders {
    $config = Get-PmcState -Section 'Config'
    return @{
        Get = $config.ProviderGet
        Set = $config.ProviderSet
    }
}

function Set-PmcConfigProviders {
    param($Get, $Set)
    Set-PmcState -Section 'Config' -Key 'ProviderGet' -Value $Get
    if ($Set) {
        Set-PmcState -Section 'Config' -Key 'ProviderSet' -Value $Set
    }
}

function Get-PmcSecurityState {
    return Get-PmcState -Section 'Security'
}

function Get-PmcDebugState {
    return Get-PmcState -Section 'Debug'
}

function Get-PmcHelpState {
    return Get-PmcState -Section 'HelpUI' -Key 'HelpState'
}

function Get-PmcCommandCategories {
    return Get-PmcState -Section 'HelpUI' -Key 'CommandCategories'
}

function Get-PmcTaskListMap {
    return Get-PmcState -Section 'ViewMappings' -Key 'LastTaskListMap'
}

function Set-PmcTaskListMap {
    param([hashtable]$Map)
    Set-PmcState -Section 'ViewMappings' -Key 'LastTaskListMap' -Value $Map
}

function Get-PmcTimeListMap {
    return Get-PmcState -Section 'ViewMappings' -Key 'LastTimeListMap'
}

function Set-PmcTimeListMap {
    param([hashtable]$Map)
    Set-PmcState -Section 'ViewMappings' -Key 'LastTimeListMap' -Value $Map
}

function Get-PmcUndoRedoState {
    return Get-PmcState -Section 'UndoRedo'
}

function Get-PmcInteractiveState {
    return Get-PmcState -Section 'Interactive'
}

function Get-PmcCommandMaps {
    return Get-PmcState -Section 'Commands'
}

# =============================================================================
# STATE INITIALIZATION AND MIGRATION
# =============================================================================

function Initialize-PmcCentralizedState {
    <#
    .SYNOPSIS
    Initializes the centralized state system and migrates existing scattered state
    #>
    [CmdletBinding()]
    param()

    # Debug logging removed to avoid circular dependency during initialization

    # Initialize Interactive Editor if not already done
    if (-not (Get-PmcState -Section 'Interactive' -Key 'Editor')) {
        # Import the PmcEditorState class if it exists
        try {
            $editorState = [PmcEditorState]::new()
            Set-PmcState -Section 'Interactive' -Key 'Editor' -Value $editorState
            # Debug logging removed
        } catch {
            # Debug logging removed
        }
    }

    # Migrate any existing command maps from the old system
    try {
        if (Get-Variable -Name 'PmcCommandMap' -Scope Script -ErrorAction SilentlyContinue) {
            $oldCommandMap = Get-Variable -Name 'PmcCommandMap' -Scope Script -ValueOnly
            Set-PmcState -Section 'Commands' -Key 'CommandMap' -Value $oldCommandMap
            # Debug logging removed
        }

        if (Get-Variable -Name 'PmcParameterMap' -Scope Script -ErrorAction SilentlyContinue) {
            $oldParameterMap = Get-Variable -Name 'PmcParameterMap' -Scope Script -ValueOnly
            Set-PmcState -Section 'Commands' -Key 'ParameterMap' -Value $oldParameterMap
            # Debug logging removed
        }
    } catch {
        # Debug logging removed
    }

    # Debug logging removed
}

function Reset-PmcState {
    <#
    .SYNOPSIS
    Resets the entire state system to defaults (useful for testing)
    #>
    [CmdletBinding()]
    param()

    $Script:PmcGlobalState._Lock = $true
    try {
        # Reset to initial state structure
        $Script:PmcGlobalState = @{
            Config = @{
                ProviderGet = { @{} }
                ProviderSet = $null
            }
            Security = @{
                InputValidationEnabled = $true
                PathWhitelistEnabled = $true
                ResourceLimitsEnabled = $true
                SensitiveDataScanEnabled = $true
                AuditLoggingEnabled = $true
                TemplateExecutionEnabled = $false
                AllowedWritePaths = @()
                MaxFileSize = 100MB
                MaxMemoryUsage = 500MB
                MaxExecutionTime = 300000
            }
            Debug = @{
                Level = 0
                LogPath = 'debug.log'
                MaxSize = 10MB
                RedactSensitive = $true
                IncludePerformance = $false
                SessionId = (New-Guid).ToString().Substring(0,8)
                StartTime = Get-Date
            }
            HelpUI = @{
                HelpState = @{
                    CurrentCategory = 'All'
                    SelectedCommand = 0
                    SearchFilter = ''
                    ShowExamples = $false
                    ViewMode = 'Categories'
                }
                CommandCategories = @{}
            }
            Interactive = @{
                Editor = $null
                CompletionCache = @{}
                GhostTextEnabled = $true
            }
            UndoRedo = @{
                UndoStack = @()
                RedoStack = @()
                MaxUndoSteps = 5
                DataCache = $null
            }
            ViewMappings = @{
                LastTaskListMap = @{}
                LastTimeListMap = @{}
            }
            Commands = @{
                ParameterMap = @{}
                CommandMap = @{}
                ShortcutMap = @{}
                CommandMeta = @{}
            }
            _Lock = $false
        }

        # Debug logging removed
    }
    finally {
        $Script:PmcGlobalState._Lock = $false
    }
}

function Get-PmcStateSnapshot {
    <#
    .SYNOPSIS
    Gets a snapshot of the current state for debugging or backup purposes
    #>
    [CmdletBinding()]
    param()

    # Create a deep copy of the state (excluding the lock)
    $snapshot = @{}
    foreach ($section in $Script:PmcGlobalState.Keys) {
        if ($section -ne '_Lock') {
            $snapshot[$section] = $Script:PmcGlobalState[$section].Clone()
        }
    }

    return $snapshot
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Auto-initialize the state system when this module is loaded
Initialize-PmcCentralizedState

# Debug logging removed to avoid circular dependency during initialization

Export-ModuleMember -Function Get-PmcRootPath, Get-PmcState, Set-PmcState, Get-PmcLastTaskListMap, Set-PmcLastTaskListMap, Get-PmcLastTimeListMap, Set-PmcLastTimeListMap, Update-PmcStateSection, Get-PmcConfigProviders, Set-PmcConfigProviders, Get-PmcSecurityState, Get-PmcDebugState, Get-PmcHelpState, Get-PmcCommandCategories, Get-PmcTaskListMap, Set-PmcTaskListMap, Get-PmcTimeListMap, Set-PmcTimeListMap, Get-PmcUndoRedoState, Get-PmcInteractiveState, Get-PmcCommandMaps, Initialize-PmcCentralizedState, Reset-PmcState, Get-PmcStateSnapshot