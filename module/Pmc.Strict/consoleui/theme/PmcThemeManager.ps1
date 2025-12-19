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
            # Load PMC theme from state
            $displayState = Get-PmcState -Section 'Display'
            if ($displayState) {
                $this.PmcTheme = $displayState.Theme
                $this.StyleTokens = $displayState.Styles
            }

            # Load color palette
            $this.ColorPalette = Get-PmcColorPalette

            # Try to load SpeedTUI theme manager (may not be available)
            $this._InitializeSpeedTUITheme()

            # Initialize caches
            $this._colorCache = @{}
            $this._ansiCache = @{}

            # Build properties and configure Engine
            $props = $this._BuildThemeProperties()
            [PmcThemeEngine]::GetInstance().Configure($props, $this.ColorPalette)

        } catch {
            # Fallback to defaults if state system not available
            $this._InitializeDefaults()
        }
    }

    <#
    .SYNOPSIS
    Initialize with default theme values
    #>
    hidden [void] _InitializeDefaults() {
        $this.PmcTheme = @{
            PaletteName = 'default'
            Hex = '#33aaff'
            TrueColor = $true
            HighContrast = $false
            ColorBlindMode = 'none'
        }

        $defaultHex = '#33aaff'
        $this.StyleTokens = @{
            Title = @{ Fg = $defaultHex }
            Header = @{ Fg = $defaultHex }
            Body = @{ Fg = '#CCCCCC' }
            Muted = @{ Fg = '#888888' }
            Success = @{ Fg = '#44FF44' }
            Warning = @{ Fg = '#FFAA00' }
            Error = @{ Fg = '#FF4444' }
            Info = @{ Fg = $defaultHex }
            Prompt = @{ Fg = '#888888' }
            Border = @{ Fg = '#666666' }
            Highlight = @{ Fg = '#55BBFF' }
            Editing = @{ Bg = $defaultHex; Fg = 'White'; Bold = $true }
            Selected = @{ Bg = $defaultHex; Fg = 'White' }
            Subheader = @{ Fg = '#888888' }
        }

        $this.ColorPalette = @{
            Primary = @{ R = 51; G = 170; B = 255 }
            Border = @{ R = 102; G = 102; B = 102 }
            Text = @{ R = 204; G = 204; B = 204 }
            Muted = @{ R = 136; G = 136; B = 136 }
            Error = @{ R = 255; G = 68; B = 68 }
            Warning = @{ R = 255; G = 170; B = 0 }
            Success = @{ R = 68; G = 255; B = 68 }
            Bright = @{ R = 85; G = 221; B = 255 }
            Header = @{ R = 51; G = 170; B = 255 }
            Label = @{ R = 136; G = 136; B = 136 }
            Highlight = @{ R = 51; G = 170; B = 255 }
            Footer = @{ R = 102; G = 102; B = 102 }
            Cursor = @{ R = 51; G = 170; B = 255 }
            Status = @{ R = 136; G = 136; B = 136 }
        }

        # Also configure Engine with defaults
        $props = $this._BuildThemeProperties()
        [PmcThemeEngine]::GetInstance().Configure($props, $this.ColorPalette)
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

    # Helper method to get hex color from palette (no closure)
    hidden [string] _GetPaletteHex([string]$role, [string]$default) {
        if ($this.ColorPalette -and $this.ColorPalette.ContainsKey($role)) {
            $rgb = $this.ColorPalette[$role]
            return ("#{0:X2}{1:X2}{2:X2}" -f $rgb.R, $rgb.G, $rgb.B)
        }
        return $default
    }

    <#
    .SYNOPSIS
    Build UI properties from current palette for Engine
    #>
    hidden [hashtable] _BuildThemeProperties() {
        $primaryHex = $this._GetPaletteHex('Primary', '#ff8833')
        $textHex = $this._GetPaletteHex('Text', '#ffe8c8')
        $mutedHex = $this._GetPaletteHex('Muted', '#888888')
        $warningHex = $this._GetPaletteHex('Warning', '#ffaa00')
        $errorHex = $this._GetPaletteHex('Error', '#ff3333')
        $successHex = $this._GetPaletteHex('Success', '#33ff33')
        $borderHex = $this._GetPaletteHex('Border', '#b25f24')

        # Check if this is a gradient theme (Synthwave = #ff00ff)
        $isSynthwave = $this.PmcTheme -and $this.PmcTheme.Hex -eq '#ff00ff'

        if ($isSynthwave) {
            return @{
                'Background.Field'        = @{ Type = 'Solid'; Color = '#0a0015' }
                'Background.FieldFocused' = @{ Type = 'Solid'; Color = '#2a0040' }
                'Background.Row'          = @{ Type = 'Solid'; Color = '#0a0015' }
                'Background.RowSelected'  = @{ Type = 'Solid'; Color = '#2a0040' }
                'Background.Warning'      = @{ Type = 'Solid'; Color = '#332200' }
                'Background.MenuBar'      = @{ Type = 'Solid'; Color = '#1a0030' }
                'Background.TabActive'    = @{ Type = 'Solid'; Color = '#2a0040' }
                'Background.TabInactive'  = @{ Type = 'Solid'; Color = '#0f001a' }
                'Background.Primary'      = @{ Type = 'Solid'; Color = '#0a0015' }
                'Background.Widget'       = @{ Type = 'Solid'; Color = '#0f001a' }
                'Background.Panel'        = @{ Type = 'Solid'; Color = '#0f001a' }
                'Background.Header'       = @{ Type = 'Solid'; Color = '#1a0030' }
                'Background.Footer'       = @{ Type = 'Solid'; Color = '#1a0030' }
                'Foreground.Field'        = @{ Type = 'Gradient'; Start = '#ff00ff'; End = '#00ffff' }
                'Foreground.FieldFocused' = @{ Type = 'Solid'; Color = '#ffffff' }
                'Foreground.Row'          = @{ Type = 'Gradient'; Start = '#ff00ff'; End = '#00ffff' }
                'Foreground.RowSelected'  = @{ Type = 'Solid'; Color = '#ffffff' }
                'Foreground.Title'        = @{ Type = 'Gradient'; Start = '#ff00ff'; End = '#00ffff' }
                'Foreground.Muted'        = @{ Type = 'Solid'; Color = '#666680' }
                'Foreground.Warning'      = @{ Type = 'Solid'; Color = '#ffaa00' }
                'Foreground.Error'        = @{ Type = 'Solid'; Color = '#ff3333' }
                'Foreground.Success'      = @{ Type = 'Solid'; Color = '#33ff88' }
                'Foreground.TabActive'    = @{ Type = 'Gradient'; Start = '#ff00ff'; End = '#00ffff' }
                'Foreground.TabInactive'  = @{ Type = 'Solid'; Color = '#666680' }
                'Foreground.Primary'      = @{ Type = 'Gradient'; Start = '#ff00ff'; End = '#00ffff' }
                'Border.Widget'           = @{ Type = 'Solid'; Color = '#6600aa' }
            }
        }

        return @{
            'Background.Field'        = @{ Type = 'Solid'; Color = '#000000' }
            'Background.FieldFocused' = @{ Type = 'Solid'; Color = $primaryHex }
            'Background.Row'          = @{ Type = 'Solid'; Color = '#000000' }
            'Background.RowSelected'  = @{ Type = 'Solid'; Color = $primaryHex }
            'Background.Warning'      = @{ Type = 'Solid'; Color = $warningHex }
            'Background.MenuBar'      = @{ Type = 'Solid'; Color = $borderHex }
            'Background.TabActive'    = @{ Type = 'Solid'; Color = $primaryHex }
            'Background.TabInactive'  = @{ Type = 'Solid'; Color = '#333333' }
            'Background.Primary'      = @{ Type = 'Solid'; Color = '#000000' }
            'Background.Widget'       = @{ Type = 'Solid'; Color = '#1a1a1a' }
            'Background.Panel'        = @{ Type = 'Solid'; Color = '#1a1a1a' }
            'Background.Header'       = @{ Type = 'Solid'; Color = '#1a1a1a' }
            'Background.Footer'       = @{ Type = 'Solid'; Color = '#1a1a1a' }
            'Foreground.Field'        = @{ Type = 'Solid'; Color = $textHex }
            'Foreground.FieldFocused' = @{ Type = 'Solid'; Color = '#FFFFFF' }
            'Foreground.Row'          = @{ Type = 'Solid'; Color = $textHex }
            'Foreground.RowSelected'  = @{ Type = 'Solid'; Color = '#FFFFFF' }
            'Foreground.Title'        = @{ Type = 'Solid'; Color = $primaryHex }
            'Foreground.Muted'        = @{ Type = 'Solid'; Color = $mutedHex }
            'Foreground.Warning'      = @{ Type = 'Solid'; Color = $warningHex }
            'Foreground.Error'        = @{ Type = 'Solid'; Color = $errorHex }
            'Foreground.Success'      = @{ Type = 'Solid'; Color = $successHex }
            'Foreground.TabActive'    = @{ Type = 'Solid'; Color = '#FFFFFF' }
            'Foreground.TabInactive'  = @{ Type = 'Solid'; Color = $mutedHex }
            'Foreground.Primary'      = @{ Type = 'Solid'; Color = $textHex }
            'Border.Widget'           = @{ Type = 'Solid'; Color = $borderHex }
        }
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

        # Fallback to defaults based on common roles
        return $this._GetDefaultColor($role)
    }

    <#
    .SYNOPSIS
    Get default color for a role
    #>
    hidden [string] _GetDefaultColor([string]$role) {
        $defaultHex = $(if ($this.PmcTheme -and $this.PmcTheme.Hex) { $this.PmcTheme.Hex } else { '#33aaff' })

        $result = switch ($role) {
            'Primary' { $defaultHex }
            'Header' { $defaultHex }
            'Title' { $defaultHex }
            'Info' { $defaultHex }
            'Highlight' { $defaultHex }
            'Border' { '#666666' }
            'Text' { '#CCCCCC' }
            'Body' { '#CCCCCC' }
            'Muted' { '#888888' }
            'Subheader' { '#888888' }
            'Label' { '#888888' }
            'Status' { '#888888' }
            'Error' { '#FF4444' }
            'Warning' { '#FFAA00' }
            'Success' { '#44FF44' }
            'Bright' { '#55BBFF' }
            default { '#CCCCCC' }
        }
        return $result
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

    <#
    .SYNOPSIS
    Convert RGB to hex color

    .PARAMETER r
    Red component (0-255)

    .PARAMETER g
    Green component (0-255)

    .PARAMETER b
    Blue component (0-255)

    .OUTPUTS
    Hex color string (e.g., "#33aaff")
    #>
    [string] RgbToHex([int]$r, [int]$g, [int]$b) {
        return ("#{0:X2}{1:X2}{2:X2}" -f $r, $g, $b)
    }

    <#
    .SYNOPSIS
    Get all available color roles

    .OUTPUTS
    Array of color role names
    #>
    [string[]] GetAvailableRoles() {
        $roles = [List[string]]::new()

        # Add from StyleTokens
        if ($this.StyleTokens) {
            $roles.AddRange($this.StyleTokens.Keys)
        }

        # Add from ColorPalette
        if ($this.ColorPalette) {
            foreach ($key in $this.ColorPalette.Keys) {
                if (-not $roles.Contains($key)) {
                    $roles.Add($key)
                }
            }
        }

        return $roles.ToArray()
    }
}

# Classes exported automatically in PowerShell 5.1+