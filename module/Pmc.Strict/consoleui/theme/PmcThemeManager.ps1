# PmcThemeManager - Unified theme system bridging PMC and SpeedTUI
# Handles PMC's sophisticated palette derivation + SpeedTUI's theme manager

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
        # Load theme from PMC state
        $this.PmcTheme = Get-PmcState -Section 'Display' -Key 'Theme'
        
        # FIX: Convert Properties to Hashtable if it's a PSCustomObject
        # This prevents "Method invocation failed... does not contain a method named 'ContainsKey'"
        if ($this.PmcTheme -and $this.PmcTheme.Properties -is [System.Management.Automation.PSCustomObject]) {
            $propsHash = @{}
            foreach ($prop in $this.PmcTheme.Properties.PSObject.Properties) {
                $propsHash[$prop.Name] = $prop.Value
            }
            # Update PmcTheme to use the hashtable for Properties
            $this.PmcTheme | Add-Member -MemberType NoteProperty -Name 'Properties' -Value $propsHash -Force
        }

        # Configure Engine if available
        try {
            if ($this.PmcTheme -and $this.PmcTheme.Properties) {
                $engine = [PmcThemeEngine]::GetInstance()
                if ($engine) {
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
        if (-not $this.PmcTheme -or -not $this.PmcTheme.Properties) {
            return '#ffffff'
        }

        $props = $this.PmcTheme.Properties

        # Direct property match
        if ($props.ContainsKey($role)) {
            return $this._ExtractColor($props[$role])
        }

        # Foreground prefix match
        $fgRole = "Foreground.$role"
        if ($props.ContainsKey($fgRole)) {
            return $this._ExtractColor($props[$fgRole])
        }
        
        # Semantic mapping
        switch ($role) {
            'Border' { if ($props.ContainsKey('Border.Widget')) { return $this._ExtractColor($props['Border.Widget']) } }
            'Header' { if ($props.ContainsKey('Foreground.Header')) { return $this._ExtractColor($props['Foreground.Header']) } }
            'Title'  { if ($props.ContainsKey('Foreground.Title')) { return $this._ExtractColor($props['Foreground.Title']) } }
            'Text'   { if ($props.ContainsKey('Foreground.Text')) { return $this._ExtractColor($props['Foreground.Text']) } }
            'Body'   { if ($props.ContainsKey('Foreground.Body')) { return $this._ExtractColor($props['Foreground.Body']) } }
            'Muted'  { if ($props.ContainsKey('Foreground.Muted')) { return $this._ExtractColor($props['Foreground.Muted']) } }
            'Label'  { if ($props.ContainsKey('Foreground.Label')) { return $this._ExtractColor($props['Foreground.Label']) } }
            'Error'  { if ($props.ContainsKey('Foreground.Error')) { return $this._ExtractColor($props['Foreground.Error']) } }
            'Success'{ if ($props.ContainsKey('Foreground.Success')) { return $this._ExtractColor($props['Foreground.Success']) } }
            'Warning'{ if ($props.ContainsKey('Foreground.Warning')) { return $this._ExtractColor($props['Foreground.Warning']) } }
            'Info'   { if ($props.ContainsKey('Foreground.Info')) { return $this._ExtractColor($props['Foreground.Info']) } }
            'Highlight'{ if ($props.ContainsKey('Foreground.Highlight')) { return $this._ExtractColor($props['Foreground.Highlight']) } }
            'Primary' { if ($props.ContainsKey('Foreground.Primary')) { return $this._ExtractColor($props['Foreground.Primary']) } }
        }

        return '#ffffff'
    }

    hidden [string] _ExtractColor($propValue) {
        if ($propValue -is [string]) { return $propValue }
        if ($propValue -is [hashtable] -or $propValue -is [pscustomobject]) {
            if ($propValue.Color) { return $propValue.Color }
            if ($propValue.Start) { return $propValue.Start } # Gradient fallback
        }
        return '#ffffff'
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

    [void] Reload() {
        # Clear caches
        $this._colorCache.Clear()
        $this._ansiCache.Clear()

        # Reload from state
        $this._Initialize()
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