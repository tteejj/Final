# PmcThemeManager - Unified theme system bridging PMC and SpeedTUI
# Handles PMC's sophisticated palette derivation + SpeedTUI's theme manager

using namespace System.Collections.Generic

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Unified theme manager bridging PMC's theme system with SpeedTUI

.DESCRIPTION
PmcThemeManager provides a single interface for theme management:
- Wraps PMC's existing theme system (single hex → full palette)
- Integrates with SpeedTUI's theme manager (if available)
- Provides unified color role API
- Handles theme switching and synchronization
- Singleton pattern for global access

.EXAMPLE
$theme = [PmcThemeManager]::GetInstance()
$color = $theme.GetColor('Primary')
$ansi = $theme.GetAnsiSequence('Primary', $false)
#>
class PmcThemeManager {
    # === Singleton Instance ===
    hidden static [PmcThemeManager]$_instance = $null

    # === PMC Theme Data ===
    [hashtable]$PmcTheme           # From Get-PmcState -Section 'Display' -Key 'Theme'
    [hashtable]$StyleTokens        # From Get-PmcState -Section 'Display' -Key 'Styles'
    [hashtable]$ColorPalette       # From Get-PmcColorPalette()

    # === SpeedTUI Integration ===
    [object]$SpeedTUITheme = $null # SpeedTUI ThemeManager (if available)

    # === Cached Data ===
    hidden [hashtable]$_colorCache = @{}
    hidden [hashtable]$_ansiCache = @{}

    # === Singleton Constructor ===
    hidden PmcThemeManager() {
        $this._Initialize()
    }

    <#
    .SYNOPSIS
    Get singleton instance of PmcThemeManager
    #>
    static [PmcThemeManager] GetInstance() {
        if ($null -eq [PmcThemeManager]::_instance) {
            [PmcThemeManager]::_instance = [PmcThemeManager]::new()
        }
        return [PmcThemeManager]::_instance
    }

    # === Initialization ===

    <#
    .SYNOPSIS
    Initialize theme system by loading PMC theme state
    #>
    hidden [void] _Initialize() {
        try {
            if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
                Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [PmcThemeManager] _Initialize started"
            }

            # Load PMC theme from state (for StyleTokens)
            $displayState = Get-PmcState -Section 'Display'
            if ($displayState) {
                $this.PmcTheme = $displayState.Theme
                $this.StyleTokens = $displayState.Styles
            }

            # Load color palette
            $this.ColorPalette = Get-PmcColorPalette

            # Initialize caches
            $this._colorCache = @{}
            $this._ansiCache = @{}

            # ONE PATH: Load theme from file
            $theme = Get-ActiveTheme
            if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
                Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [PmcThemeManager] Active theme name: '$($theme.Name)' Hex: '$($theme.Hex)' Props: $($theme.Properties.Count)"
            }

            if ($theme -and $theme.Properties) {
                [PmcThemeEngine]::GetInstance().Configure($theme.Properties, $this.ColorPalette)
            } else {
                # No theme file found - this should not happen
                if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
                    Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [PmcThemeManager] ERROR: No theme loaded"
                }
            }
        } catch {
            if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
                Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [PmcThemeManager] _Initialize ERROR: $_"
            }
        }
    }


    <#
    .SYNOPSIS
    Try to initialize SpeedTUI theme manager if available
    #>
    hidden [void] _InitializeSpeedTUITheme() {
        # SpeedTUI integration would go here if needed
        # For now, PMC theme is primary source of truth
        $this.SpeedTUITheme = $null
    }


    # === Public API ===

    <#
    .SYNOPSIS
    Get hex color string for a specific role

    .PARAMETER role
    Color role: Primary, Border, Text, Muted, Error, Warning, Success, Bright, Header, etc.

    .OUTPUTS
    Hex color string (e.g., "#33aaff") or empty string if not found

    .EXAMPLE
    $color = $theme.GetColor('Primary')  # Returns "#33aaff"
    #>
    [string] GetColor([string]$role) {
        # Check cache first
        if ($this._colorCache.ContainsKey($role)) {
            return $this._colorCache[$role]
        }

        $color = $this._ResolveColor($role)
        $this._colorCache[$role] = $color
        return $color
    }

    <#
    .SYNOPSIS
    Resolve color from theme system
    #>
    hidden [string] _ResolveColor([string]$role) {
        # Try style tokens first (includes Fg property)
        if ($this.StyleTokens -and $this.StyleTokens.ContainsKey($role)) {
            $style = $this.StyleTokens[$role]
            if ($style.Fg) {
                return $style.Fg
            }
        }

        # Try color palette (RGB object → hex)
        if ($this.ColorPalette -and $this.ColorPalette.ContainsKey($role)) {
            $rgb = $this.ColorPalette[$role]
            if ($rgb.R -ne $null -and $rgb.G -ne $null -and $rgb.B -ne $null) {
                return ("#{0:X2}{1:X2}{2:X2}" -f $rgb.R, $rgb.G, $rgb.B)
            }
        }

        # STRICT THEME ENFORCEMENT: No fallbacks.
        throw "Theme Property Missing: '$role'"
    }

    <#
    .SYNOPSIS
    Get ANSI escape sequence for a color role

    .PARAMETER role
    Color role

    .PARAMETER background
    If true, returns background color sequence; otherwise foreground

    .OUTPUTS
    ANSI escape sequence (e.g., "`e[38;2;51;170;255m")

    .EXAMPLE
    $ansi = $theme.GetAnsiSequence('Primary', $false)  # Foreground
    $ansiBg = $theme.GetAnsiSequence('Primary', $true)  # Background
    #>
    [string] GetAnsiSequence([string]$role, [bool]$background = $false) {
        $cacheKey = "${role}_${background}"

        # Check cache
        if ($this._ansiCache.ContainsKey($cacheKey)) {
            return $this._ansiCache[$cacheKey]
        }

        # Get hex color
        $hex = $this.GetColor($role)
        if ([string]::IsNullOrEmpty($hex)) {
            return ''
        }

        # Convert to ANSI
        $ansi = $this._HexToAnsi($hex, $background)
        $this._ansiCache[$cacheKey] = $ansi
        return $ansi
    }

    <#
    .SYNOPSIS
    Convert hex color to ANSI sequence
    #>
    hidden [string] _HexToAnsi([string]$hex, [bool]$background) {
        # Parse hex
        $hex = $hex.TrimStart('#')
        if ($hex.Length -ne 6) { return '' }

        try {
            $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
            $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
            $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)

            if ($background) {
                return "`e[48;2;${r};${g};${b}m"
            } else {
                return "`e[38;2;${r};${g};${b}m"
            }
        } catch {
            return ''
        }
    }

    <#
    .SYNOPSIS
    Get style object with foreground, background, and formatting

    .PARAMETER role
    Style role from StyleTokens (Title, Header, Body, Editing, Selected, etc.)

    .OUTPUTS
    Hashtable with Fg, Bg, Bold properties

    .EXAMPLE
    $style = $theme.GetStyle('Selected')
    # Returns @{ Bg = '#33aaff'; Fg = 'White' }
    #>
    [hashtable] GetStyle([string]$role) {
        if ($this.StyleTokens -and $this.StyleTokens.ContainsKey($role)) {
            return $this.StyleTokens[$role]
        }

        # Fallback: construct basic style from color
        return @{
            Fg = $this.GetColor($role)
        }
    }

    <#
    .SYNOPSIS
    Get complete theme hashtable with ANSI sequences for dialogs/widgets

    .DESCRIPTION
    Returns a standard hashtable with common theme elements as ANSI sequences.
    Useful for passing to dialogs, widgets, and other components that need
    multiple theme colors.

    .OUTPUTS
    Hashtable with ANSI sequences for common theme roles

    .EXAMPLE
    $theme = $themeManager.GetTheme()
    # Returns @{
    #   Primary = "`e[38;2;51;170;255m"
    #   PrimaryBg = "`e[48;2;51;170;255m"
    #   Text = "`e[38;2;204;204;204m"
    #   ...
    # }
    #>
    [hashtable] GetTheme() {
        return @{
            # Primary colors
            Primary = $this.GetAnsiSequence('Primary', $false)
            PrimaryBg = $this.GetAnsiSequence('Primary', $true)

            # Dialog colors (common pattern from TimeListScreen)
            DialogBg = $this.GetAnsiSequence('Surface', $true)
            DialogFg = $this.GetAnsiSequence('OnSurface', $false)
            DialogBorder = $this.GetAnsiSequence('Outline', $false)

            # Text hierarchy
            Header = $this.GetAnsiSequence('Header', $false)
            Title = $this.GetAnsiSequence('Title', $false)
            Text = $this.GetAnsiSequence('Text', $false)
            Body = $this.GetAnsiSequence('Body', $false)
            Muted = $this.GetAnsiSequence('Muted', $false)
            Label = $this.GetAnsiSequence('Label', $false)

            # Semantic colors
            Highlight = $this.GetAnsiSequence('Highlight', $false)
            Error = $this.GetAnsiSequence('Error', $false)
            Warning = $this.GetAnsiSequence('Warning', $false)
            Success = $this.GetAnsiSequence('Success', $false)
            Info = $this.GetAnsiSequence('Info', $false)

            # UI elements
            Border = $this.GetAnsiSequence('Border', $false)
            Status = $this.GetAnsiSequence('Status', $false)

            # Special
            Bright = $this.GetAnsiSequence('Bright', $false)
            Reset = "`e[0m"
        }
    }

    # === Theme Management ===

    <#
    .SYNOPSIS
    Reload theme from PMC state system

    .DESCRIPTION
    Call this after theme changes to refresh cached data
    #>
    [void] Reload() {
        # Clear caches
        $this._colorCache.Clear()
        $this._ansiCache.Clear()

        # Reload from state
        $this._Initialize()
    }

    <#
    .SYNOPSIS
    Set theme hex color and regenerate palette

    .PARAMETER hex
    New theme hex color (e.g., "#33aaff")

    .DESCRIPTION
    Updates PMC theme, saves config, and regenerates palette
    #>
    [void] SetTheme([string]$hex) {
        if ([string]::IsNullOrWhiteSpace($hex)) {
            throw "Theme hex cannot be empty"
        }

        # Normalize hex format
        if (-not $hex.StartsWith('#')) {
            $hex = '#' + $hex
        }

        try {
            # Update config
            $cfg = Get-PmcConfig
            if (-not $cfg.Display) { $cfg.Display = @{} }
            if (-not $cfg.Display.Theme) { $cfg.Display.Theme = @{} }
            $cfg.Display.Theme.Hex = $hex
            Save-PmcConfig $cfg

            # Force theme re-initialization
            Initialize-PmcThemeSystem -Force

            # Reload this manager
            $this.Reload()

            # CRITICAL FIX: Notify PmcThemeEngine of theme change
            # The engine caches theme properties and needs to reload
            try {
                $engine = [PmcThemeEngine]::GetInstance()
                if ($engine) {
                    $engine.InvalidateCache()
                }
            } catch {
                # PmcThemeEngine may not be available in all contexts
            }
        } catch {
            throw "Failed to set theme: $_"
        }
    }

    <#
    .SYNOPSIS
    Get current theme hex color

    .OUTPUTS
    Hex color string (e.g., "#33aaff")
    #>
    [string] GetCurrentThemeHex() {
        if ($this.PmcTheme -and $this.PmcTheme.Hex) {
            return $this.PmcTheme.Hex
        }
        return '#33aaff'
    }

    # === Utility Methods ===

    <#
    .SYNOPSIS
    Get RGB components from hex color

    .PARAMETER hex
    Hex color string (with or without #)

    .OUTPUTS
    Hashtable with R, G, B properties (0-255)
    #>
    [hashtable] HexToRgb([string]$hex) {
        $hex = $hex.TrimStart('#')
        if ($hex.Length -ne 6) {
            return @{ R = 0; G = 0; B = 0 }
        }

        try {
            return @{
                R = [Convert]::ToInt32($hex.Substring(0, 2), 16)
                G = [Convert]::ToInt32($hex.Substring(2, 2), 16)
                B = [Convert]::ToInt32($hex.Substring(4, 2), 16)
            }
        } catch {
            return @{ R = 0; G = 0; B = 0 }
        }
    }
}