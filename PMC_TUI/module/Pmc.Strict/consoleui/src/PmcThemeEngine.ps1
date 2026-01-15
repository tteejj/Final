# PmcThemeEngine.ps1 - Core theme system with gradient support
#
# Handles all color resolution for the TUI:
# - Solid colors (single RGB value)
# - Multi-stop gradients (horizontal/vertical transitions)
# - Aggressive caching for performance
# - JSON-based theme configuration
#
# REFACTORED: Delegates to PmcThemeManager for Single Source of Truth

using namespace System.Collections.Generic

Set-StrictMode -Off

$script:_PmcThemeEngineInstance = $null

class PmcThemeEngine {
    # REMOVED: [hashtable] $_properties - Now delegates to PmcThemeManager
    [object] $_cache

    static [PmcThemeEngine] GetInstance() {
        if ($null -eq $script:_PmcThemeEngineInstance) {
            $script:_PmcThemeEngineInstance = [PmcThemeEngine]::new()
        }
        return $script:_PmcThemeEngineInstance
    }

    static [void] Reset() {
        $script:_PmcThemeEngineInstance = $null
    }

    PmcThemeEngine() {
        # Fallback: simple hashtable
        $this._cache = @{}
    }

    [void] Configure([hashtable]$properties) {
        # NO-OP: Properties are managed by PmcThemeManager
        # We just invalidate cache to be safe
        $this.InvalidateCache()
        
        # Targeted diagnostic: log when Configure is called (only if debug enabled)
        if ((Test-Path variable:global:PmcDebug) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
            Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [PmcThemeEngine] Configure called (Delegated Mode - No-Op)"
        }
    }

    # Public Primitive: Get ANSI from Hex (for Manager)
    [string] GetAnsiFromHex([string]$hex, [bool]$background) {
        if ([string]::IsNullOrEmpty($hex)) { return '' }
        return $this._GetSolidAnsiCached($hex, $background)
    }

    # Public Primitive: Get Int from Hex (for Manager)
    [int] GetIntFromHex([string]$hex) {
        if ([string]::IsNullOrEmpty($hex)) { return -1 }
        return $this._GetSolidIntCached($hex)
    }

    # Get background ANSI - handles solid or gradient
    [string] GetBackgroundAnsi([string]$propertyName, [int]$width, [int]$charIndex) {
        # DELEGATE: Get property from Manager
        $manager = [PmcThemeManager]::GetInstance()
        if (-not $manager.PmcTheme.Properties.ContainsKey($propertyName)) {
            throw "Theme Property Missing: '$propertyName'"
        }

        $prop = $manager.PmcTheme.Properties[$propertyName]

        if ($prop.Type -eq 'Solid') {
            return $this._GetSolidAnsiCached($prop.Color, $true)
        }
        elseif ($prop.Type -eq 'Gradient') {
            $gradient = $this._GetGradientArrayCached($propertyName, $prop, $width, $true)
            if ($charIndex -ge 0 -and $charIndex -lt $gradient.Count) {
                return $gradient[$charIndex]
            }
            return ''
        }

        return ''
    }

    # Get foreground ANSI - usually solid
    [string] GetForegroundAnsi([string]$propertyName) {
        # DELEGATE: Get property from Manager
        $manager = [PmcThemeManager]::GetInstance()
        if (-not $manager.PmcTheme.Properties.ContainsKey($propertyName)) {
            throw "Theme Property Missing: '$propertyName'"
        }

        $prop = $manager.PmcTheme.Properties[$propertyName]

        if ($prop.Type -eq 'Solid') {
            $ansi = $this._GetSolidAnsiCached($prop.Color, $false)
            return $ansi
        }

        return ''
    }

    # Get integer color value (Generic - for Solid colors)
    # Returns packed RGB int (0x00RRGGBB)
    [int] GetThemeColorInt([string]$propertyName) {
        # DELEGATE: Get property from Manager
        $manager = [PmcThemeManager]::GetInstance()
        if (-not $manager.PmcTheme.Properties.ContainsKey($propertyName)) {
            throw "Theme Property Missing: '$propertyName'"
        }

        $prop = $manager.PmcTheme.Properties[$propertyName]
        $hex = ""
        
        if ($prop.Type -eq 'Solid') {
            $hex = $prop.Color
        }
        elseif ($prop.Type -eq 'Gradient') {
            # Use first color for gradient fallback
            # Use ContainsKey to avoid strict mode errors on missing keys
            if ($prop.ContainsKey('Start') -and $prop.Start) {
                $hex = $prop.Start
            }
            elseif ($prop.ContainsKey('Stops') -and $prop.Stops -and $prop.Stops.Count -gt 0) {
                $hex = $prop.Stops[0].Color
            }
        }

        if ([string]::IsNullOrEmpty($hex)) { return 0 }

        return $this._ColorToInt($hex)
    }

    # Get gradient info for a property (returns null if solid)
    # Returns @{ Start = [int]; End = [int] } for gradient, or $null for solid
    [object] GetGradientInfo([string]$propertyName) {
        # DELEGATE: Get property from Manager
        $manager = [PmcThemeManager]::GetInstance()
        if (-not $manager.PmcTheme.Properties.ContainsKey($propertyName)) {
            return $null
        }

        $prop = $manager.PmcTheme.Properties[$propertyName]
        
        if ($prop.Type -eq 'Gradient') {
            $startHex = $prop.Start
            $endHex = $prop.End
            if ($startHex -and $endHex) {
                return @{
                    Start = $this._ColorToInt($startHex)
                    End = $this._ColorToInt($endHex)
                }
            }
        }

        return $null
    }

    # === INT API (For Hybrid Engine) ===

    # Get foreground Packed Int - usually solid
    [int] GetForegroundInt([string]$propertyName) {
        # DELEGATE: Get property from Manager
        $manager = [PmcThemeManager]::GetInstance()
        if (-not $manager.PmcTheme.Properties.ContainsKey($propertyName)) {
            throw "Theme Property Missing: '$propertyName'"
        }

        $prop = $manager.PmcTheme.Properties[$propertyName]

        if ($prop.Type -eq 'Solid') {
            return $this._GetSolidIntCached($prop.Color)
        }
        
        # Fallback for gradients acting as foregrounds (use generic)
        return $this.GetThemeColorInt($propertyName)
    }

    # Get background Packed Int
    [int] GetBackgroundInt([string]$propertyName, [int]$width, [int]$charIndex) {
        # DELEGATE: Get property from Manager
        $manager = [PmcThemeManager]::GetInstance()
        if (-not $manager.PmcTheme.Properties.ContainsKey($propertyName)) {
            throw "Theme Property Missing: '$propertyName'"
        }

        $prop = $manager.PmcTheme.Properties[$propertyName]

        if ($prop.Type -eq 'Solid') {
            return $this._GetSolidIntCached($prop.Color)
        }
        elseif ($prop.Type -eq 'Gradient') {
            # Gradient support for Ints
            $gradient = $this._GetGradientIntArrayCached($propertyName, $prop, $width)
            if ($charIndex -ge 0 -and $charIndex -lt $gradient.Count) {
                return $gradient[$charIndex]
            }
            return -1
        }

        return -1
    }

    # Public: Get gradient array as Ints (for bulk rendering)
    [int[]] GetGradientIntArray([string]$propertyName, [int]$width) {
        # DELEGATE: Get property from Manager
        $manager = [PmcThemeManager]::GetInstance()
        if (-not $manager.PmcTheme.Properties.ContainsKey($propertyName)) { return @() }
        $prop = $manager.PmcTheme.Properties[$propertyName]
        
        if ($prop.Type -eq 'Gradient') {
            return $this._GetGradientIntArrayCached($propertyName, $prop, $width)
        }
        
        return @()
    }

    # Cached solid color ANSI
    hidden [string] _GetSolidAnsiCached([string]$color, [bool]$background) {
        $cacheKey = "solid_ansi:${color}_${background}"
        
        if ($this._cache -is [hashtable]) {
            if ($this._cache.ContainsKey($cacheKey)) { return $this._cache[$cacheKey] }
            $ansi = $this._ColorToAnsi($color, $background)
            $this._cache[$cacheKey] = $ansi
            return $ansi
        }

        $cached = $this._cache.Get("Theme", $cacheKey)
        if ($null -ne $cached) { return $cached }

        $ansi = $this._ColorToAnsi($color, $background)
        $this._cache.Set("Theme", $cacheKey, $ansi)
        return $ansi
    }

    # Cached solid color Int
    hidden [int] _GetSolidIntCached([string]$color) {
        $cacheKey = "solid_int:${color}"

        if ($this._cache -is [hashtable]) {
            if ($this._cache.ContainsKey($cacheKey)) { return $this._cache[$cacheKey] }
            $intColor = $this._ColorToInt($color)
            $this._cache[$cacheKey] = $intColor
            return $intColor
        }

        $cached = $this._cache.Get("Theme", $cacheKey)
        if ($null -ne $cached) { return $cached }

        $intColor = $this._ColorToInt($color)
        $this._cache.Set("Theme", $cacheKey, $intColor)
        return $intColor
    }

    # Cached gradient array
    hidden [string[]] _GetGradientArrayCached([string]$propertyName, [hashtable]$gradient, [int]$width, [bool]$background) {
        $cacheKey = "grad_ansi:${propertyName}_${width}_${background}"

        if ($this._cache -is [hashtable]) {
            if ($this._cache.ContainsKey($cacheKey)) { return $this._cache[$cacheKey] }
            $array = $this._ComputeGradient($gradient, $width, $background)
            $this._cache[$cacheKey] = $array
            return $array
        }

        $cached = $this._cache.Get("Theme", $cacheKey)
        if ($null -ne $cached) { return $cached }

        $array = $this._ComputeGradient($gradient, $width, $background)
        $this._cache.Set("Theme", $cacheKey, $array)
        return $array
    }

    # Cached gradient Int array
    hidden [int[]] _GetGradientIntArrayCached([string]$propertyName, [hashtable]$gradient, [int]$width) {
        $cacheKey = "grad_int:${propertyName}_${width}"

        if ($this._cache -is [hashtable]) {
            if ($this._cache.ContainsKey($cacheKey)) { return $this._cache[$cacheKey] }
            $array = $this._ComputeGradientInt($gradient, $width)
            $this._cache[$cacheKey] = $array
            return $array
        }

        $cached = $this._cache.Get("Theme", $cacheKey)
        if ($null -ne $cached) { return $cached }

        $array = $this._ComputeGradientInt($gradient, $width)
        $this._cache.Set("Theme", $cacheKey, $array)
        return $array
    }

    # Clear all caches (call on theme reload)
    [void] InvalidateCache() {
        if ($this._cache -is [hashtable]) {
            $this._cache.Clear()
        } else {
            $this._cache.ClearRegion("Theme")
        }
    }

    # Compute gradient as array of ANSI sequences
    hidden [string[]] _ComputeGradient([hashtable]$gradient, [int]$length, [bool]$background) {
        $result = [List[string]]::new($length)
        
        # Support both Stops array and simple Start/End
        $stops = $null
        if ($gradient.PSObject.Properties['Stops'] -and $gradient.Stops) {
            $stops = $gradient.Stops | Sort-Object Position
        }
        elseif ($gradient.PSObject.Properties['Start'] -and $gradient.Start -and $gradient.PSObject.Properties['End'] -and $gradient.End) {
            $stops = @(
                @{ Position = 0.0; Color = $gradient.Start }
                @{ Position = 1.0; Color = $gradient.End }
            )
        }
        else {
            # Fallback - return empty
            return @()
        }

        for ($i = 0; $i -lt $length; $i++) {
            $ratio = $(if ($length -eq 1) { 0.0 } else { $i / ($length - 1) })
            $color = $this._GetColorAtRatio($stops, $ratio)
            $result.Add($this._ColorToAnsi($color, $background))
        }

        return $result.ToArray()
    }

    # Compute gradient as array of Ints
    hidden [int[]] _ComputeGradientInt([hashtable]$gradient, [int]$length) {
        $result = [List[int]]::new($length)
        
        # Support both Stops array and simple Start/End
        $stops = $null
        if ($gradient.PSObject.Properties['Stops'] -and $gradient.Stops) {
            $stops = $gradient.Stops | Sort-Object Position
        }
        elseif ($gradient.PSObject.Properties['Start'] -and $gradient.Start -and $gradient.PSObject.Properties['End'] -and $gradient.End) {
            $stops = @(
                @{ Position = 0.0; Color = $gradient.Start }
                @{ Position = 1.0; Color = $gradient.End }
            )
        }
        else {
            # Fallback - return empty
            return @()
        }

        for ($i = 0; $i -lt $length; $i++) {
            $ratio = $(if ($length -eq 1) { 0.0 } else { $i / ($length - 1) })
            $color = $this._GetColorAtRatio($stops, $ratio)
            $result.Add($this._ColorToInt($color))
        }

        return $result.ToArray()
    }

    hidden [string] _GetColorAtRatio([array]$stops, [double]$ratio) {
        # Find surrounding stops
        $beforeStop = $stops[0]
        $afterStop = $stops[-1]

        for ($s = 0; $s -lt $stops.Count - 1; $s++) {
            if ($ratio -ge $stops[$s].Position -and $ratio -le $stops[$s + 1].Position) {
                $beforeStop = $stops[$s]
                $afterStop = $stops[$s + 1]
                break
            }
        }

        # Local interpolation between the two stops
        $localRatio = $(if ($afterStop.Position -eq $beforeStop.Position) {
                0.0
            }
            else {
                ($ratio - $beforeStop.Position) / ($afterStop.Position - $beforeStop.Position)
            })

        return $this._InterpolateColor($beforeStop.Color, $afterStop.Color, $localRatio)
    }

    # Linear color interpolation
    hidden [string] _InterpolateColor([string]$start, [string]$end, [double]$ratio) {
        $startHex = $start.TrimStart('#')
        $endHex = $end.TrimStart('#')

        $startR = [Convert]::ToInt32($startHex.Substring(0, 2), 16)
        $startG = [Convert]::ToInt32($startHex.Substring(2, 2), 16)
        $startB = [Convert]::ToInt32($startHex.Substring(4, 2), 16)

        $endR = [Convert]::ToInt32($endHex.Substring(0, 2), 16)
        $endG = [Convert]::ToInt32($endHex.Substring(2, 2), 16)
        $endB = [Convert]::ToInt32($endHex.Substring(4, 2), 16)

        $r = [int]($startR + ($endR - $startR) * $ratio)
        $g = [int]($startG + ($endG - $startG) * $ratio)
        $b = [int]($startB + ($endB - $startB) * $ratio)

        return "#{0:X2}{1:X2}{2:X2}" -f $r, $g, $b
    }

    # Convert hex color to ANSI escape sequence
    hidden [string] _ColorToAnsi([string]$hex, [bool]$background) {
        $hex = $hex.TrimStart('#')

        if ($hex.Length -ne 6) {
            return ''
        }

        try {
            $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
            $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
            $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)

            if ($background) {
                return "`e[48;2;${r};${g};${b}m"
            }
            else {
                return "`e[38;2;${r};${g};${b}m"
            }
        }
        catch {
            return ''
        }
    }

    # Convert hex color to Packed Int
    hidden [int] _ColorToInt([string]$hex) {
        $hex = $hex.TrimStart('#')
        if ($hex.Length -ne 6) { return -1 }

        try {
            $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
            $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
            $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)

            # Pack RGB: (R << 16) | (G << 8) | B
            return ($r -shl 16) -bor ($g -shl 8) -bor $b
        }
        catch {
            return -1
        }
    }
}
