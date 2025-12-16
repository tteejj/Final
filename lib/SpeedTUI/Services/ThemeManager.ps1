# SpeedTUI Enhanced Theme Manager - Simple theming with powerful features
# Replaces the existing ThemeManager with enhanced capabilities and better performance

using namespace System.Collections.Generic

# Load performance optimizations for cached color generation
. "$PSScriptRoot/../Core/Internal/PerformanceCore.ps1"

<#
.SYNOPSIS
Enhanced theme color class with RGB support and caching

.DESCRIPTION
Represents a theme color with:
- Foreground and background colors
- RGB color support
- Automatic ANSI sequence caching
- Simple API for common operations

.EXAMPLE
$color = [SimpleThemeColor]::new("primary", @(0, 255, 0), @(0, 0, 0))  # Green on black
$ansiSequence = $color.GetForeground()  # Get cached ANSI sequence
#>
class SimpleThemeColor {
    [string]$Name                    # Color role name (primary, secondary, etc.)
    [string]$Foreground              # Cached foreground ANSI sequence
    [string]$Background              # Cached background ANSI sequence
    [int[]]$ForegroundRGB            # RGB values for foreground
    [int[]]$BackgroundRGB            # RGB values for background
    
    <#
    .SYNOPSIS
    Create a theme color with RGB values
    
    .PARAMETER name
    Color role name
    
    .PARAMETER fgRGB
    Foreground RGB array [r, g, b]
    
    .PARAMETER bgRGB
    Background RGB array [r, g, b] (optional)
    #>
    SimpleThemeColor([string]$name, [int[]]$fgRGB, [int[]]$bgRGB = $null) {
        $this.Name = $name
        
        # Store RGB values
        $this.ForegroundRGB = $fgRGB
        $this.BackgroundRGB = $bgRGB
        
        # Generate and cache ANSI sequences using optimized VT100 helper
        if ($fgRGB -and $fgRGB.Length -eq 3) {
            # Pre-computed and cached by InternalVT100
            $this.Foreground = [InternalVT100]::RGB($fgRGB[0], $fgRGB[1], $fgRGB[2])
            
            # Also cache with theme-specific key
            [InternalStringCache]::CacheCustomString("theme_fg_$name", $this.Foreground)
        } else {
            $this.Foreground = [InternalVT100]::Default()
        }
        
        if ($bgRGB -and $bgRGB.Length -eq 3) {
            # Pre-computed and cached by InternalVT100
            $this.Background = [InternalVT100]::BgRGB($bgRGB[0], $bgRGB[1], $bgRGB[2])
            
            # Also cache with theme-specific key
            [InternalStringCache]::CacheCustomString("theme_bg_$name", $this.Background)
        } else {
            $this.Background = ""
        }
    }
    
    <#
    .SYNOPSIS
    Create a theme color with ANSI sequences
    
    .PARAMETER name
    Color role name
    
    .PARAMETER foreground
    Foreground ANSI sequence
    
    .PARAMETER background
    Background ANSI sequence (optional)
    #>
    SimpleThemeColor([string]$name, [string]$foreground, [string]$background = "") {
        $this.Name = $name
        $this.Foreground = $foreground
        $this.Background = $background
        
        # Try to extract RGB values from ANSI sequences (basic extraction)
        $this.ForegroundRGB = @(255, 255, 255)  # Default to white
        $this.BackgroundRGB = @(0, 0, 0)        # Default to black
    }
    
    # Get the foreground ANSI sequence
    [string] GetForeground() {
        return $this.Foreground
    }
    
    # Get the background ANSI sequence
    [string] GetBackground() {
        return $this.Background
    }
    
    # Get combined foreground and background
    [string] GetCombined() {
        return $this.Foreground + $this.Background
    }
    
    # ToString for debugging
    [string] ToString() {
        return "$($this.Name): FG=RGB($($this.ForegroundRGB -join ',')) BG=RGB($($this.BackgroundRGB -join ','))"
    }
}

<#
.SYNOPSIS
Simple theme container with pre-computed colors

.DESCRIPTION
Contains a complete theme with:
- Named colors (primary, secondary, success, etc.)
- Pre-computed ANSI sequences for performance
- Metadata (name, description, author)
- Easy color access methods

.EXAMPLE
$theme = [SimpleTheme]::new("Matrix", "Green terminal theme")
$theme.DefineRGBColor("primary", @(0, 255, 0))      # Green
$theme.DefineRGBColor("background", @(0, 0, 0))     # Black
#>
class SimpleTheme {
    [string]$Name                                    # Theme name
    [string]$Description                             # Theme description
    [string]$Author                                  # Theme author
    [Dictionary[string, SimpleThemeColor]]$Colors    # Color definitions
    [hashtable]$Metadata                            # Additional metadata
    
    <#
    .SYNOPSIS
    Create a new theme
    
    .PARAMETER name
    Theme name
    
    .PARAMETER description
    Theme description
    #>
    SimpleTheme([string]$name, [string]$description = "") {
        $this.Name = $name
        $this.Description = $description
        $this.Author = ""
        $this.Colors = [Dictionary[string, SimpleThemeColor]]::new()
        $this.Metadata = @{}
        
        # Define default colors that every theme should have
        $this.DefineDefaultColors()
    }
    
    <#
    .SYNOPSIS
    Define default colors for the theme
    
    .DESCRIPTION
    Sets up standard color roles that all themes should provide:
    - primary, secondary (main colors)
    - success, warning, error, info (semantic colors)
    - text, background (basic colors)
    - focus, selection (interaction colors)
    #>
    hidden [void] DefineDefaultColors() {
        # Basic colors (will be overridden by specific themes)
        $this.DefineColor("primary", [InternalVT100]::Blue(), "")
        $this.DefineColor("secondary", [InternalVT100]::Cyan(), "")
        $this.DefineColor("success", [InternalVT100]::Green(), "")
        $this.DefineColor("warning", [InternalVT100]::Yellow(), "")
        $this.DefineColor("error", [InternalVT100]::Red(), "")
        $this.DefineColor("info", [InternalVT100]::Cyan(), "")
        $this.DefineColor("text", [InternalVT100]::White(), "")
        $this.DefineColor("background", "", [InternalVT100]::BgBlack())
        $this.DefineColor("focus", [InternalVT100]::Yellow(), "")
        $this.DefineColor("selection", [InternalVT100]::Black(), [InternalVT100]::BgWhite())
    }
    
    <#
    .SYNOPSIS
    Define a color using ANSI sequences (pre-computed)
    
    .PARAMETER name
    Color role name
    
    .PARAMETER foreground
    Foreground ANSI sequence
    
    .PARAMETER background
    Background ANSI sequence
    
    .EXAMPLE
    $theme.DefineColor("primary", "`e[34m", "`e[40m")  # Blue on black
    #>
    [void] DefineColor([string]$name, [string]$foreground, [string]$background = "") {
        # Cache the ANSI sequences immediately
        if (-not [string]::IsNullOrEmpty($foreground)) {
            [InternalStringCache]::CacheCustomString("color_fg_$name", $foreground)
        }
        if (-not [string]::IsNullOrEmpty($background)) {
            [InternalStringCache]::CacheCustomString("color_bg_$name", $background)
        }
        
        $color = [SimpleThemeColor]::new($name, $foreground, $background)
        $this.Colors[$name] = $color
    }
    
    <#
    .SYNOPSIS
    Define a color using RGB values
    
    .PARAMETER name
    Color role name
    
    .PARAMETER fgRGB
    Foreground RGB array [r, g, b]
    
    .PARAMETER bgRGB
    Background RGB array [r, g, b] (optional)
    
    .EXAMPLE
    $theme.DefineRGBColor("primary", @(0, 255, 0))           # Green text
    $theme.DefineRGBColor("highlight", @(255, 255, 0), @(0, 0, 255))  # Yellow on blue
    #>
    [void] DefineRGBColor([string]$name, [int[]]$fgRGB, [int[]]$bgRGB = $null) {
        $color = [SimpleThemeColor]::new($name, $fgRGB, $bgRGB)
        $this.Colors[$name] = $color
    }
    
    <#
    .SYNOPSIS
    Get a color by name
    
    .PARAMETER name
    Color role name
    
    .OUTPUTS
    SimpleThemeColor object or default color if not found
    
    .EXAMPLE
    $primaryColor = $theme.GetColor("primary")
    $ansi = $primaryColor.GetForeground()
    #>
    [SimpleThemeColor] GetColor([string]$name) {
        if ($this.Colors.ContainsKey($name)) {
            return $this.Colors[$name]
        }
        
        # Return a default color if not found
        return [SimpleThemeColor]::new($name, [InternalVT100]::Default(), "")
    }
    
    <#
    .SYNOPSIS
    Check if theme has a specific color
    
    .PARAMETER name
    Color role name
    
    .OUTPUTS
    Boolean indicating if color exists
    #>
    [bool] HasColor([string]$name) {
        return $this.Colors.ContainsKey($name)
    }
    
    <#
    .SYNOPSIS
    Get all color names in this theme
    
    .OUTPUTS
    Array of color role names
    #>
    [string[]] GetColorNames() {
        return $this.Colors.Keys | Sort-Object
    }
    
    <#
    .SYNOPSIS
    Get theme information for debugging
    
    .OUTPUTS
    Hashtable with theme metadata
    #>
    [hashtable] GetInfo() {
        return @{
            Name = $this.Name
            Description = $this.Description
            Author = $this.Author
            ColorCount = $this.Colors.Count
            Colors = $this.GetColorNames()
            Metadata = $this.Metadata
        }
    }
    
    # ToString for debugging
    [string] ToString() {
        return "$($this.Name) ($($this.Colors.Count) colors)"
    }
    
    <#
    .SYNOPSIS
    Pre-compute all color combinations for performance (Praxis optimization)
    
    .DESCRIPTION
    Pre-generates common color combinations to avoid runtime concatenation
    #>
    [void] PrecomputeColorCombinations() {
        foreach ($colorName in $this.Colors.Keys) {
            $color = $this.Colors[$colorName]
            
            # Cache combined foreground + background
            $combined = $color.Foreground + $color.Background
            [InternalStringCache]::CacheCustomString("theme_combined_$colorName", $combined)
            
            # Cache with reset
            $withReset = $combined + [InternalVT100]::Reset()
            [InternalStringCache]::CacheCustomString("theme_reset_$colorName", $withReset)
            
            # Cache with bold
            $withBold = $color.Foreground + [InternalVT100]::Bold() + $color.Background
            [InternalStringCache]::CacheCustomString("theme_bold_$colorName", $withBold)
        }
    }
}

<#
.SYNOPSIS
Enhanced theme manager with performance optimizations and simple APIs

.DESCRIPTION
Manages themes with:
- Pre-built themes (matrix, amber, electric)
- Simple theme switching with SetTheme()
- RGB color support
- Performance monitoring
- Theme caching and optimization
- Event notifications
- Simple development APIs

.EXAMPLE
# Simple usage
$themeManager = [EnhancedThemeManager]::new()
$themeManager.SetTheme("matrix")                    # Switch to matrix theme
$color = $themeManager.GetColor("primary")         # Get primary color
$themeManager.SetCustomColor("button.special", @(255, 100, 200))  # Custom color

# Performance monitoring
$stats = $themeManager.GetPerformanceStats()
#>
class EnhancedThemeManager {
    # === Core Properties ===
    [Dictionary[string, SimpleTheme]]$_themes        # All available themes
    [SimpleTheme]$_currentTheme                      # Currently active theme
    [string]$_currentThemeName                       # Current theme name
    
    # === Performance and Caching ===
    hidden [hashtable]$_colorCache                   # Cached color lookups
    hidden [int]$_colorLookups = 0                   # Total color lookups
    hidden [int]$_cacheHits = 0                      # Cache hits for performance
    
    # === Event System ===
    hidden [List[scriptblock]]$_changeHandlers      # Theme change event handlers
    
    # === Logging ===
    hidden [object]$_logger
    
    <#
    .SYNOPSIS
    Initialize enhanced theme manager
    
    .DESCRIPTION
    Sets up the theme manager with:
    - Built-in themes (matrix, amber, electric, default)
    - Performance monitoring
    - Event system integration
    - Color caching
    #>
    EnhancedThemeManager() {
        # Initialize collections
        $this._themes = [Dictionary[string, SimpleTheme]]::new()
        $this._changeHandlers = [List[scriptblock]]::new()
        $this._colorCache = @{}
        
        # Initialize logging
        $this._logger = Get-Logger
        $this._logger.Info("EnhancedThemeManager", "Constructor", "Initializing enhanced theme manager")
        
        # Register built-in themes
        $this.RegisterBuiltInThemes()
        
        # Set default theme
        $this.SetTheme("default")
        
        $this._logger.Info("EnhancedThemeManager", "Constructor", "Enhanced theme manager initialized", @{
            ThemeCount = $this._themes.Count
            DefaultTheme = $this._currentThemeName
        })
    }
    
    <#
    .SYNOPSIS
    Register all built-in themes
    
    .DESCRIPTION
    Creates and registers high-quality themes:
    - default: Clean, professional theme
    - matrix: Green-on-black terminal theme  
    - amber: Retro amber terminal theme
    - electric: Modern electric blue theme
    #>
    hidden [void] RegisterBuiltInThemes() {
        # === Default Theme - Clean and Professional ===
        $defaultTheme = [SimpleTheme]::new("default", "Clean, professional theme suitable for business applications")
        $defaultTheme.Author = "SpeedTUI Team"
        
        # Define colors using RGB for precision
        $defaultTheme.DefineRGBColor("primary", @(59, 130, 246))        # Blue-500
        $defaultTheme.DefineRGBColor("secondary", @(107, 114, 128))     # Gray-500
        $defaultTheme.DefineRGBColor("success", @(34, 197, 94))         # Green-500
        $defaultTheme.DefineRGBColor("warning", @(251, 191, 36))        # Yellow-500
        $defaultTheme.DefineRGBColor("error", @(239, 68, 68))           # Red-500
        $defaultTheme.DefineRGBColor("info", @(59, 130, 246))           # Blue-500
        $defaultTheme.DefineRGBColor("text", @(243, 244, 246))          # Gray-100
        $defaultTheme.DefineRGBColor("textDim", @(156, 163, 175))       # Gray-400
        $defaultTheme.DefineRGBColor("background", @(17, 24, 39))       # Gray-900
        $defaultTheme.DefineRGBColor("focus", @(251, 191, 36))          # Yellow-500
        $defaultTheme.DefineRGBColor("selection", @(17, 24, 39), @(59, 130, 246))  # Dark on blue
        
        $this.RegisterTheme($defaultTheme)
        
        # === Matrix Theme - Classic Green Terminal ===
        $matrixTheme = [SimpleTheme]::new("matrix", "Classic green-on-black matrix terminal theme")
        $matrixTheme.Author = "SpeedTUI Team"
        
        $matrixTheme.DefineRGBColor("primary", @(0, 255, 0))            # Bright green
        $matrixTheme.DefineRGBColor("secondary", @(0, 200, 0))          # Medium green
        $matrixTheme.DefineRGBColor("success", @(0, 255, 100))          # Bright green-cyan
        $matrixTheme.DefineRGBColor("warning", @(255, 255, 0))          # Bright yellow
        $matrixTheme.DefineRGBColor("error", @(255, 0, 0))              # Bright red
        $matrixTheme.DefineRGBColor("info", @(0, 255, 255))             # Bright cyan
        $matrixTheme.DefineRGBColor("text", @(0, 220, 0))               # Green text
        $matrixTheme.DefineRGBColor("textDim", @(0, 150, 0))            # Dim green
        $matrixTheme.DefineRGBColor("background", @(0, 0, 0))           # Pure black
        $matrixTheme.DefineRGBColor("focus", @(0, 255, 0))              # Bright green
        $matrixTheme.DefineRGBColor("selection", @(0, 0, 0), @(0, 255, 0))  # Black on green
        
        $this.RegisterTheme($matrixTheme)
        
        # === Amber Theme - Retro Amber Terminal ===
        $amberTheme = [SimpleTheme]::new("amber", "Retro amber monochrome terminal theme")
        $amberTheme.Author = "SpeedTUI Team"
        
        $amberTheme.DefineRGBColor("primary", @(255, 191, 0))           # Amber
        $amberTheme.DefineRGBColor("secondary", @(255, 160, 0))         # Dark amber
        $amberTheme.DefineRGBColor("success", @(255, 220, 0))           # Light amber
        $amberTheme.DefineRGBColor("warning", @(255, 140, 0))           # Orange amber
        $amberTheme.DefineRGBColor("error", @(255, 100, 0))             # Red amber
        $amberTheme.DefineRGBColor("info", @(255, 200, 0))              # Info amber
        $amberTheme.DefineRGBColor("text", @(255, 180, 0))              # Text amber
        $amberTheme.DefineRGBColor("textDim", @(200, 140, 0))           # Dim amber
        $amberTheme.DefineRGBColor("background", @(25, 20, 0))          # Dark amber background
        $amberTheme.DefineRGBColor("focus", @(255, 220, 0))             # Light amber
        $amberTheme.DefineRGBColor("selection", @(25, 20, 0), @(255, 191, 0))  # Dark on amber
        
        $this.RegisterTheme($amberTheme)
        
        # === Electric Theme - Modern Electric Blue ===
        $electricTheme = [SimpleTheme]::new("electric", "Modern electric blue theme with cyan accents")
        $electricTheme.Author = "SpeedTUI Team"
        
        $electricTheme.DefineRGBColor("primary", @(0, 150, 255))        # Electric blue
        $electricTheme.DefineRGBColor("secondary", @(100, 200, 255))    # Light blue
        $electricTheme.DefineRGBColor("success", @(0, 255, 150))        # Electric green
        $electricTheme.DefineRGBColor("warning", @(255, 200, 0))        # Electric yellow
        $electricTheme.DefineRGBColor("error", @(255, 50, 100))         # Electric red
        $electricTheme.DefineRGBColor("info", @(0, 200, 255))           # Electric cyan
        $electricTheme.DefineRGBColor("text", @(200, 230, 255))         # Light blue text
        $electricTheme.DefineRGBColor("textDim", @(100, 150, 200))      # Dim blue
        $electricTheme.DefineRGBColor("background", @(10, 15, 35))      # Dark blue background
        $electricTheme.DefineRGBColor("focus", @(0, 255, 255))          # Bright cyan
        $electricTheme.DefineRGBColor("selection", @(10, 15, 35), @(0, 150, 255))  # Dark on electric blue
        
        $this.RegisterTheme($electricTheme)
        
        $this._logger.Debug("EnhancedThemeManager", "RegisterBuiltInThemes", "Built-in themes registered", @{
            ThemeNames = @("default", "matrix", "amber", "electric")
        })
    }
    
    # === Theme Management ===
    
    <#
    .SYNOPSIS
    Register a theme
    
    .PARAMETER theme
    SimpleTheme object to register
    
    .EXAMPLE
    $customTheme = [SimpleTheme]::new("MyTheme", "My custom theme")
    $themeManager.RegisterTheme($customTheme)
    #>
    [void] RegisterTheme([SimpleTheme]$theme) {
        if ($null -eq $theme) {
            throw [ArgumentNullException]::new("theme")
        }
        
        # Pre-compute all color combinations for performance
        $theme.PrecomputeColorCombinations()
        
        $this._themes[$theme.Name] = $theme
        
        # Clear color cache since we have a new theme
        $this._colorCache.Clear()
        
        $this._logger.Debug("EnhancedThemeManager", "RegisterTheme", "Theme registered", @{
            ThemeName = $theme.Name
            ColorCount = $theme.Colors.Count
            PreComputed = $true
        })
    }
    
    <#
    .SYNOPSIS
    Set active theme by name
    
    .PARAMETER themeName
    Name of theme to activate
    
    .DESCRIPTION
    Switches to the specified theme and:
    - Clears color cache for performance
    - Notifies change handlers
    - Updates current theme reference
    
    .EXAMPLE
    $themeManager.SetTheme("matrix")    # Switch to matrix theme
    $themeManager.SetTheme("electric")  # Switch to electric theme
    #>
    [void] SetTheme([string]$themeName) {
        if ([string]::IsNullOrWhiteSpace($themeName)) {
            $themeName = "default"
        }
        
        # Check if theme exists
        if (-not $this._themes.ContainsKey($themeName)) {
            $this._logger.Warn("EnhancedThemeManager", "SetTheme", "Theme not found, using default", @{
                RequestedTheme = $themeName
                AvailableThemes = ($this._themes.Keys -join ", ")
            })
            $themeName = "default"
        }
        
        # Skip if no change
        if ($this._currentThemeName -eq $themeName) {
            return
        }
        
        $oldTheme = $this._currentThemeName
        $this._currentTheme = $this._themes[$themeName]
        $this._currentThemeName = $themeName
        
        # Clear color cache since theme changed
        $this._colorCache.Clear()
        
        $this._logger.Info("EnhancedThemeManager", "SetTheme", "Theme changed", @{
            OldTheme = $oldTheme
            NewTheme = $themeName
            ColorCount = $this._currentTheme.Colors.Count
        })
        
        # Notify change handlers
        $this.NotifyThemeChanged()
    }
    
    <#
    .SYNOPSIS
    Get color from current theme with caching
    
    .PARAMETER colorName
    Color role name
    
    .OUTPUTS
    SimpleThemeColor object
    
    .DESCRIPTION
    Gets color with performance optimizations:
    - Color lookup caching
    - Fallback to default colors
    - Performance tracking
    
    .EXAMPLE
    $primaryColor = $themeManager.GetColor("primary")
    $ansi = $primaryColor.GetForeground()
    #>
    [SimpleThemeColor] GetColor([string]$colorName) {
        $this._colorLookups++
        
        # Check cache first
        $cacheKey = "$($this._currentThemeName):$colorName"
        if ($this._colorCache.ContainsKey($cacheKey)) {
            $this._cacheHits++
            return $this._colorCache[$cacheKey]
        }
        
        # Get color from current theme
        $color = $this._currentTheme.GetColor($colorName)
        
        # Cache the result (but limit cache size)
        if ($this._colorCache.Count -lt 200) {
            $this._colorCache[$cacheKey] = $color
        }
        
        return $color
    }
    
    <#
    .SYNOPSIS
    Set a custom color override
    
    .PARAMETER colorName
    Color role name
    
    .PARAMETER rgbValues
    RGB array [r, g, b]
    
    .DESCRIPTION
    Adds a custom color to the current theme that overrides the default.
    Useful for component-specific customizations.
    
    .EXAMPLE
    $themeManager.SetCustomColor("button.special", @(255, 100, 200))  # Custom pink
    #>
    [void] SetCustomColor([string]$colorName, [int[]]$rgbValues) {
        if ([string]::IsNullOrWhiteSpace($colorName) -or $null -eq $rgbValues -or $rgbValues.Length -ne 3) {
            throw [ArgumentException]::new("Invalid color name or RGB values")
        }
        
        # Add custom color to current theme
        $this._currentTheme.DefineRGBColor($colorName, $rgbValues)
        
        # Clear cache since colors changed
        $this._colorCache.Clear()
        
        $this._logger.Debug("EnhancedThemeManager", "SetCustomColor", "Custom color set", @{
            ColorName = $colorName
            RGB = ($rgbValues -join ",")
            Theme = $this._currentThemeName
        })
    }
    
    # === Information and Querying ===
    
    <#
    .SYNOPSIS
    Get current theme name
    
    .OUTPUTS
    String with current theme name
    #>
    [string] GetCurrentThemeName() {
        return $this._currentThemeName
    }
    
    <#
    .SYNOPSIS
    Get current theme object
    
    .OUTPUTS
    SimpleTheme object
    #>
    [SimpleTheme] GetCurrentTheme() {
        return $this._currentTheme
    }
    
    <#
    .SYNOPSIS
    Get all available theme names
    
    .OUTPUTS
    Array of theme names
    #>
    [string[]] GetAvailableThemes() {
        return $this._themes.Keys | Sort-Object
    }
    
    <#
    .SYNOPSIS
    Get theme information
    
    .PARAMETER themeName
    Name of theme to get info for
    
    .OUTPUTS
    Hashtable with theme information
    
    .EXAMPLE
    $info = $themeManager.GetThemeInfo("matrix")
    Write-Host "Theme: $($info.Name) - $($info.Description)"
    #>
    [hashtable] GetThemeInfo([string]$themeName) {
        if ($this._themes.ContainsKey($themeName)) {
            return $this._themes[$themeName].GetInfo()
        }
        
        return @{
            Name = $themeName
            Description = "Theme not found"
            Author = ""
            ColorCount = 0
            Colors = @()
            Metadata = @{}
        }
    }
    
    <#
    .SYNOPSIS
    Check if theme exists
    
    .PARAMETER themeName
    Theme name to check
    
    .OUTPUTS
    Boolean indicating if theme exists
    #>
    [bool] HasTheme([string]$themeName) {
        return $this._themes.ContainsKey($themeName)
    }
    
    # === Event System ===
    
    <#
    .SYNOPSIS
    Register theme change event handler
    
    .PARAMETER handler
    Script block to execute when theme changes
    
    .EXAMPLE
    $themeManager.OnThemeChanged({ param($theme) 
        Write-Host "Theme changed to: $($theme.Name)" 
    })
    #>
    [void] OnThemeChanged([scriptblock]$handler) {
        if ($null -eq $handler) {
            throw [ArgumentNullException]::new("handler")
        }
        
        $this._changeHandlers.Add($handler)
        
        $this._logger.Debug("EnhancedThemeManager", "OnThemeChanged", "Theme change handler registered", @{
            HandlerCount = $this._changeHandlers.Count
        })
    }
    
    <#
    .SYNOPSIS
    Notify all theme change handlers
    
    .DESCRIPTION
    Called automatically when theme changes. Executes all registered
    event handlers with the new theme as parameter.
    #>
    hidden [void] NotifyThemeChanged() {
        foreach ($handler in $this._changeHandlers) {
            try {
                & $handler $this._currentTheme
            } catch {
                $this._logger.Error("EnhancedThemeManager", "NotifyThemeChanged", "Theme change handler failed", @{
                    Error = $_.Exception.Message
                    Theme = $this._currentThemeName
                })
            }
        }
    }
    
    # === Performance and Monitoring ===
    
    <#
    .SYNOPSIS
    Get performance statistics
    
    .OUTPUTS
    Hashtable with performance metrics
    
    .EXAMPLE
    $stats = $themeManager.GetPerformanceStats()
    Write-Host "Cache hit rate: $($stats.CacheHitRate)%"
    #>
    [hashtable] GetPerformanceStats() {
        $cacheHitRate = $(if ($this._colorLookups -gt 0) {
            [Math]::Round(($this._cacheHits / $this._colorLookups) * 100, 1)
        } else { 0 })
        
        return @{
            CurrentTheme = $this._currentThemeName
            RegisteredThemes = $this._themes.Count
            ColorLookups = $this._colorLookups
            CacheHits = $this._cacheHits
            CacheHitRate = $cacheHitRate
            CacheSize = $this._colorCache.Count
            ChangeHandlers = $this._changeHandlers.Count
            ThemeNames = ($this._themes.Keys | Sort-Object)
        }
    }
    
    <#
    .SYNOPSIS
    Clear performance counters and cache
    
    .DESCRIPTION
    Resets performance tracking and clears color cache.
    Useful for testing or memory management.
    #>
    [void] ClearCache() {
        $oldCacheSize = $this._colorCache.Count
        $this._colorCache.Clear()
        $this._colorLookups = 0
        $this._cacheHits = 0
        
        $this._logger.Debug("EnhancedThemeManager", "ClearCache", "Cache and counters cleared", @{
            OldCacheSize = $oldCacheSize
        })
    }
    
    # === Convenience Methods ===
    
    <#
    .SYNOPSIS
    Apply color to text with reset
    
    .PARAMETER colorName
    Color role name
    
    .PARAMETER text
    Text to colorize
    
    .OUTPUTS
    String with ANSI color codes
    
    .EXAMPLE
    $coloredText = $themeManager.ApplyColor("success", "Operation completed!")
    Write-Host $coloredText
    #>
    [string] ApplyColor([string]$colorName, [string]$text) {
        $color = $this.GetColor($colorName)
        $combined = $color.GetCombined()
        $reset = [InternalVT100]::Reset()
        
        return "$combined$text$reset"
    }
    
    # === Helper Methods for Theme Creation ===
    
    <#
    .SYNOPSIS
    Create a new theme with builder pattern
    
    .PARAMETER name
    Theme name
    
    .PARAMETER description
    Theme description
    
    .OUTPUTS
    SimpleTheme object for further configuration
    
    .EXAMPLE
    $theme = $themeManager.CreateTheme("MyTheme", "Custom theme")
    $theme.DefineRGBColor("primary", @(255, 100, 50))
    $themeManager.RegisterTheme($theme)
    #>
    [SimpleTheme] CreateTheme([string]$name, [string]$description) {
        return [SimpleTheme]::new($name, $description)
    }
}

# === Global Theme Manager Instance ===

# Global instance for easy access
$global:SpeedTUIThemeManager = $null

<#
.SYNOPSIS
Get the global enhanced theme manager instance

.OUTPUTS
EnhancedThemeManager instance

.EXAMPLE
$themeManager = Get-ThemeManager
$themeManager.SetTheme("matrix")
#>
function Get-ThemeManager {
    if ($null -eq $global:SpeedTUIThemeManager) {
        $global:SpeedTUIThemeManager = [EnhancedThemeManager]::new()
    }
    return $global:SpeedTUIThemeManager
}

# === Helper Functions ===

<#
.SYNOPSIS
Set global SpeedTUI theme

.PARAMETER ThemeName
Name of theme to apply

.EXAMPLE
Set-SpeedTUITheme "matrix"    # Apply matrix theme globally
Set-SpeedTUITheme "electric"  # Apply electric theme globally
#>
function Set-SpeedTUITheme {
    param([string]$ThemeName)
    
    $themeManager = Get-ThemeManager
    $themeManager.SetTheme($ThemeName)
}

<#
.SYNOPSIS
Get color from current theme

.PARAMETER ColorRole
Color role name

.OUTPUTS
ANSI color sequence

.EXAMPLE
$primaryColor = Get-SpeedTUIColor "primary"
Write-Host "${primaryColor}This is primary colored text$([InternalVT100]::Reset())"
#>
function Get-SpeedTUIColor {
    param([string]$ColorRole)
    
    $themeManager = Get-ThemeManager
    $color = $themeManager.GetColor($ColorRole)
    return $color.GetForeground()
}

<#
.SYNOPSIS
Create a new theme with fluent API

.PARAMETER Name
Theme name

.PARAMETER Description
Theme description

.PARAMETER ScriptBlock
Script block to configure the theme

.OUTPUTS
SimpleTheme object

.EXAMPLE
$theme = New-SpeedTUITheme "Corporate" "Professional corporate theme" {
    $this.DefineRGBColor("primary", @(0, 74, 173))      # Corporate blue
    $this.DefineRGBColor("secondary", @(108, 117, 125))  # Gray
    $this.DefineRGBColor("success", @(40, 167, 69))      # Green
}
#>
function New-SpeedTUITheme {
    param(
        [string]$Name,
        [string]$Description,
        [scriptblock]$ScriptBlock
    )
    
    $theme = [SimpleTheme]::new($Name, $Description)
    
    if ($ScriptBlock) {
        # Execute script block in context of theme object
        $ScriptBlock.InvokeWithContext($null, @($theme), $theme)
    }
    
    return $theme
}

<#
.SYNOPSIS
Show theme demonstration with all colors

.PARAMETER ThemeName
Name of theme to demonstrate (optional, uses current theme)

.EXAMPLE
Show-SpeedTUITheme "matrix"    # Show matrix theme colors
Show-SpeedTUITheme             # Show current theme colors
#>
function Show-SpeedTUITheme {
    param([string]$ThemeName = "")
    
    $themeManager = Get-ThemeManager
    
    if (-not [string]::IsNullOrWhiteSpace($ThemeName)) {
        $originalTheme = $themeManager.GetCurrentThemeName()
        $themeManager.SetTheme($ThemeName)
    }
    
    $theme = $themeManager.GetCurrentTheme()
    $info = $theme.GetInfo()
    
    Write-Host "`n=== SpeedTUI Theme: $($info.Name) ===" -ForegroundColor Cyan
    Write-Host $info.Description -ForegroundColor Gray
    if ($info.Author) {
        Write-Host "Author: $($info.Author)" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Show all colors
    foreach ($colorName in $info.Colors) {
        $color = $theme.GetColor($colorName)
        $sample = $color.GetCombined() + "████ $colorName" + [InternalVT100]::Reset()
        Write-Host "  $sample"
    }
    
    Write-Host "`n=== End Theme Demo ===`n" -ForegroundColor Cyan
    
    # Restore original theme if we changed it
    if (-not [string]::IsNullOrWhiteSpace($ThemeName) -and $originalTheme) {
        $themeManager.SetTheme($originalTheme)
    }
}

# Helper functions are available when this file is dot-sourced