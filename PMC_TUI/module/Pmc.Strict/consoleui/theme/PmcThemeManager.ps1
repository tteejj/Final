# PmcThemeManager - Unified theme system bridging PMC and SpeedTUI
# Handles PMC's sophisticated palette derivation + SpeedTUI's theme manager
# STANDALONE: No module dependency - uses DataService and Load-Theme directly

using namespace System.Collections.Generic

Set-StrictMode -Off

$script:_PmcThemeManagerInstance = $null

class PmcThemeManager {
    [hashtable] $_ansiCache
    [hashtable] $_colorCache
    [object] $PmcTheme

    static [PmcThemeManager] GetInstance() {
        if ($null -eq $script:_PmcThemeManagerInstance) {
            $script:_PmcThemeManagerInstance = [PmcThemeManager]::new()
        }
        return $script:_PmcThemeManagerInstance
    }

    static [void] Reset() {
        $script:_PmcThemeManagerInstance = $null
    }

    PmcThemeManager() {
        $this._ansiCache = @{}
        $this._colorCache = @{}
        $this._Initialize()
    }

    [void] _Initialize() {
        # STANDALONE: Load theme directly from files (no module dependency)
        try {
            # Get theme name from config
            $themeName = 'default'
            try {
                $config = [DataService]::LoadConfig()
                if ($config.Display -and $config.Display.Theme -and $config.Display.Theme.Active) {
                    $themeName = $config.Display.Theme.Active
                }
            } catch {
                # Use default
            }
            
            # Load theme file
            $theme = Load-Theme -themeName $themeName
            if (-not $theme) {
                $theme = Load-Theme -themeName 'default'
            }
            
            if ($theme) {
                $this.PmcTheme = @{
                    PaletteName = $theme.Name
                    Hex = $theme.Hex
                    Properties = $theme.Properties
                    TrueColor = $true
                    HighContrast = $false
                    ColorBlindMode = 'none'
                }
            } else {
                # Minimal fallback
                $this.PmcTheme = @{
                    PaletteName = 'default'
                    Hex = '#33aaff'
                    Properties = @{}
                    TrueColor = $true
                    HighContrast = $false
                    ColorBlindMode = 'none'
                }
            }
        } catch {
            # Minimal fallback on any error
            $this.PmcTheme = @{
                PaletteName = 'default'
                Hex = '#33aaff'
                Properties = @{}
                TrueColor = $true
                HighContrast = $false
                ColorBlindMode = 'none'
            }
        }
        
        # FIX: Convert Properties to Hashtable if it's a PSCustomObject
        if ($this.PmcTheme -and $this.PmcTheme.Properties -is [System.Management.Automation.PSCustomObject]) {
            $propsHash = @{}
            foreach ($prop in $this.PmcTheme.Properties.PSObject.Properties) {
                $propsHash[$prop.Name] = $prop.Value
            }
            $this.PmcTheme.Properties = $propsHash
        }

        # Configure Engine if available
        # Configure Engine if available (Dynamic lookup to avoid circular dependency)
        try {
            $engineType = "PmcThemeEngine" -as [type]
            if ($engineType) {
                $engine = $engineType::GetInstance()
                if ($engine -and $this.PmcTheme -and $this.PmcTheme.Properties) {
                    $engine.Configure($this.PmcTheme.Properties)
                }
            }
        } catch {
            # Engine might not be available
        }
    }

    [string] GetColor([string]$role) {
        # Check cache
        if ($this._colorCache.ContainsKey($role)) {
            return $this._colorCache[$role]
        }

        $color = $this._ResolveColor($role)
        $this._colorCache[$role] = $color
        return $color
    }

    hidden [string] _ResolveColor([string]$role) {
        $props = $this.PmcTheme.Properties

        # Direct property match
        if ($props.ContainsKey($role)) {
            return $this._ExtractColor($props[$role])
        }

        throw "Theme Property Missing: '$role'"
    }

    hidden [string] _ExtractColor($propValue) {
        if ($propValue.Color) { return $propValue.Color }
        throw "Invalid theme property value"
    }

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

    [hashtable] GetStyle([string]$role) {
        # Fallback: construct basic style from color
        return @{
            Fg = $this.GetColor($role)
        }
    }

    [hashtable] GetTheme() {
        return @{
            # Primary colors
            Primary = $this.GetAnsiSequence('Primary', $false)
            PrimaryBg = $this.GetAnsiSequence('Primary', $true)

            # Dialog colors
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

    [void] Reload() {
        # Clear caches
        $this._colorCache.Clear()
        $this._ansiCache.Clear()

        # Reload theme
        $this._Initialize()

        # Force PmcThemeEngine to use our properties
        # Force PmcThemeEngine to use our properties (Dynamic lookup)
        try {
            $engineType = "PmcThemeEngine" -as [type]
            if ($engineType) {
                $engine = $engineType::GetInstance()
                if ($engine -and $this.PmcTheme -and $this.PmcTheme.Properties) {
                    $engine.Configure($this.PmcTheme.Properties)
                    $engine.InvalidateCache()
                }
            }
        } catch {
            # Engine might not be available
        }
    }

    [void] SetTheme([string]$hex) {
        if ([string]::IsNullOrWhiteSpace($hex)) {
            throw "Theme hex cannot be empty"
        }

        # Normalize hex format
        if (-not $hex.StartsWith('#')) {
            $hex = '#' + $hex
        }

        try {
            # STANDALONE: Update config via DataService
            $cfg = [DataService]::LoadConfig()
            if (-not $cfg.ContainsKey('Display')) { $cfg['Display'] = @{} }
            if ($cfg.Display -isnot [hashtable]) {
                $displayHash = @{}
                foreach ($prop in $cfg.Display.PSObject.Properties) { $displayHash[$prop.Name] = $prop.Value }
                $cfg['Display'] = $displayHash
            }
            if (-not $cfg.Display.ContainsKey('Theme')) { $cfg.Display['Theme'] = @{} }
            if ($cfg.Display.Theme -isnot [hashtable]) {
                $themeHash = @{}
                foreach ($prop in $cfg.Display.Theme.PSObject.Properties) { $themeHash[$prop.Name] = $prop.Value }
                $cfg.Display['Theme'] = $themeHash
            }
            $cfg.Display.Theme['Hex'] = $hex
            [DataService]::SaveConfig($cfg)

            # Force theme re-initialization
            Initialize-PmcThemeSystem -Force

            # Reload this manager
            $this.Reload()

            # Notify PmcThemeEngine of theme change (Dynamic lookup)
            try {
                $engineType = "PmcThemeEngine" -as [type]
                if ($engineType) {
                    $engine = $engineType::GetInstance()
                    if ($engine) {
                        $engine.InvalidateCache()
                    }
                }
            } catch {
                # PmcThemeEngine may not be available
            }
        } catch {
            throw "Failed to set theme: $_"
        }
    }

    [string] GetCurrentThemeHex() {
        if ($this.PmcTheme -and $this.PmcTheme.Hex) {
            return $this.PmcTheme.Hex
        }
        return '#33aaff'
    }

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