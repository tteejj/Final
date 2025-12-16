# SpeedTUI Enhanced Theme Manager - Simple interface with powerful features
# Maintains backward compatibility while adding advanced theming capabilities

# Load the performance core for optimizations
. "$PSScriptRoot/../Core/Internal/PerformanceCore.ps1"

<#
.SYNOPSIS
Simple theme color definition for easy theme creation

.DESCRIPTION
Represents a single color in a theme with foreground and optional background.
Keeps the familiar SpeedTUI pattern while enabling advanced features.

.EXAMPLE
$color = [ThemeColor]::new("primary", [EnhancedColors]::Blue)
$colorWithBg = [ThemeColor]::new("selection", [EnhancedColors]::White, [EnhancedColors]::BgBlue)
#>
class SimpleThemeColor {
    [string]$Name
    [string]$Foreground
    [string]$Background
    [int[]]$RGB = $null          # For advanced RGB theming
    [int[]]$BackgroundRGB = $null # For advanced RGB backgrounds
    
    # Simple constructor (backward compatible)
    SimpleThemeColor([string]$name, [string]$foreground) {
        $this.Name = $name
        $this.Foreground = $foreground
        $this.Background = ""
    }
    
    # Constructor with background (backward compatible)
    SimpleThemeColor([string]$name, [string]$foreground, [string]$background) {
        $this.Name = $name
        $this.Foreground = $foreground
        $this.Background = $background
    }
    
    # Advanced RGB constructor (new feature)
    SimpleThemeColor([string]$name, [int[]]$rgb) {
        $this.Name = $name
        $this.RGB = $rgb
        $this.Foreground = [InternalVT100]::RGB($rgb[0], $rgb[1], $rgb[2])
        $this.Background = ""
    }
    
    # Advanced RGB with background constructor (new feature)
    SimpleThemeColor([string]$name, [int[]]$rgb, [int[]]$backgroundRgb) {
        $this.Name = $name
        $this.RGB = $rgb
        $this.BackgroundRGB = $backgroundRgb
        $this.Foreground = [InternalVT100]::RGB($rgb[0], $rgb[1], $rgb[2])
        $this.Background = [InternalVT100]::RGBBackground($backgroundRgb[0], $backgroundRgb[1], $backgroundRgb[2])
    }
    
    # Get the complete color sequence (foreground + background)
    [string] GetSequence() {
        return $this.Foreground + $this.Background
    }
}

<#
.SYNOPSIS
Simple theme definition that's easy to create and use

.DESCRIPTION
Maintains the familiar SpeedTUI Theme pattern while enabling advanced features
like RGB colors, gradients, and pre-computed sequences for performance.

.EXAMPLE
# Simple theme creation (backward compatible)
$theme = [SimpleTheme]::new("MyTheme")
$theme.DefineColor("primary", [Colors]::Blue)
$theme.DefineColor("selection", [Colors]::White, [Colors]::BgBlue)

# Advanced RGB theme creation (new feature)
$theme.DefineRGBColor("matrix", @(0, 255, 0))
$theme.DefineRGBColor("amber", @(255, 191, 0))
#>
class SimpleTheme {
    [string]$Name
    [System.Collections.Generic.Dictionary[string, SimpleThemeColor]]$Colors
    [System.Collections.Generic.Dictionary[string, string]]$Styles
    [hashtable]$Metadata = @{}  # For theme descriptions, authors, etc.
    
    # Cached sequences for performance (invisible to developers)
    hidden [hashtable]$_cachedSequences = @{}
    
    SimpleTheme([string]$name) {
        $this.Name = $name
        $this.Colors = [System.Collections.Generic.Dictionary[string, SimpleThemeColor]]::new()
        $this.Styles = [System.Collections.Generic.Dictionary[string, string]]::new()
        $this.Metadata = @{
            Description = ""
            Author = ""
            Version = "1.0"
            Created = [DateTime]::Now
        }
    }
    
    <#
    .SYNOPSIS
    Define a color using ANSI sequences (backward compatible)
    
    .PARAMETER name
    Color name (e.g., "primary", "secondary", "error")
    
    .PARAMETER foreground
    Foreground color ANSI sequence
    
    .PARAMETER background
    Optional background color ANSI sequence
    
    .OUTPUTS
    SimpleTheme instance for method chaining
    #>
    [SimpleTheme] DefineColor([string]$name, [string]$foreground) {
        $color = [SimpleThemeColor]::new($name, $foreground)
        $this.Colors[$name] = $color
        $this._cachedSequences[$name] = $foreground
        return $this
    }
    
    [SimpleTheme] DefineColor([string]$name, [string]$foreground, [string]$background) {
        $color = [SimpleThemeColor]::new($name, $foreground, $background)
        $this.Colors[$name] = $color
        $this._cachedSequences[$name] = $foreground + $background
        return $this
    }
    
    <#
    .SYNOPSIS
    Define a color using RGB values (new advanced feature)
    
    .PARAMETER name
    Color name
    
    .PARAMETER rgb
    RGB array [r, g, b] where each component is 0-255
    
    .OUTPUTS
    SimpleTheme instance for method chaining
    #>
    [SimpleTheme] DefineRGBColor([string]$name, [int[]]$rgb) {
        $color = [SimpleThemeColor]::new($name, $rgb)
        $this.Colors[$name] = $color
        $this._cachedSequences[$name] = $color.GetSequence()
        return $this
    }
    
    [SimpleTheme] DefineRGBColor([string]$name, [int[]]$rgb, [int[]]$backgroundRgb) {
        $color = [SimpleThemeColor]::new($name, $rgb, $backgroundRgb)
        $this.Colors[$name] = $color
        $this._cachedSequences[$name] = $color.GetSequence()
        return $this
    }
    
    <#
    .SYNOPSIS
    Define a style (backward compatible)
    
    .PARAMETER name
    Style name (e.g., "bold", "italic")
    
    .PARAMETER style
    ANSI style sequence
    
    .OUTPUTS
    SimpleTheme instance for method chaining
    #>
    [SimpleTheme] DefineStyle([string]$name, [string]$style) {
        $this.Styles[$name] = $style
        $this._cachedSequences["style.$name"] = $style
        return $this
    }
    
    <#
    .SYNOPSIS
    Get a color by name with performance caching
    
    .PARAMETER name
    Color name to retrieve
    
    .OUTPUTS
    SimpleThemeColor instance or default color if not found
    #>
    [SimpleThemeColor] GetColor([string]$name) {
        if ($this.Colors.ContainsKey($name)) {
            return $this.Colors[$name]
        }
        # Return default if not found (safe fallback)
        return [SimpleThemeColor]::new($name, [EnhancedColors]::Default)
    }
    
    <#
    .SYNOPSIS
    Get cached color sequence for maximum performance
    
    .PARAMETER name
    Color name to retrieve
    
    .OUTPUTS
    Cached ANSI color sequence
    #>
    [string] GetSequence([string]$name) {
        if ($this._cachedSequences.ContainsKey($name)) {
            return $this._cachedSequences[$name]
        }
        
        # Try to get from color and cache it
        if ($this.Colors.ContainsKey($name)) {
            $sequence = $this.Colors[$name].GetSequence()
            $this._cachedSequences[$name] = $sequence
            return $sequence
        }
        
        return ""  # No color found
    }
    
    <#
    .SYNOPSIS
    Get a style by name (backward compatible)
    
    .PARAMETER name
    Style name to retrieve
    
    .OUTPUTS
    ANSI style sequence
    #>
    [string] GetStyle([string]$name) {
        if ($this.Styles.ContainsKey($name)) {
            return $this.Styles[$name]
        }
        return ""
    }
    
    # Set theme metadata
    [SimpleTheme] SetDescription([string]$description) {
        $this.Metadata.Description = $description
        return $this
    }
    
    [SimpleTheme] SetAuthor([string]$author) {
        $this.Metadata.Author = $author
        return $this
    }
}

<#
.SYNOPSIS
Enhanced Theme Manager with simple API and powerful features

.DESCRIPTION
Provides a clean, simple interface for theme management while offering advanced
features like RGB colors, theme hot-swapping, and performance optimizations.
Maintains full backward compatibility with existing SpeedTUI themes.

.EXAMPLE
# Simple usage (backward compatible)
$themeManager = [EnhancedThemeManager]::new()
$themeManager.SetTheme("dark")

# Advanced usage
$themeManager.SetTheme("matrix")
$customColor = $themeManager.GetColor("primary")
$themeManager.SetCustomColor("button.hover", @(100, 200, 255))
#>
class EnhancedThemeManager {
    hidden [System.Collections.Generic.Dictionary[string, SimpleTheme]]$_themes
    hidden [SimpleTheme]$_currentTheme
    hidden [string]$_currentThemeName = "default"
    hidden [object]$_logger
    hidden [System.Collections.Generic.List[scriptblock]]$_changeHandlers
    hidden [hashtable]$_globalCache = @{}  # Performance cache
    
    # Event support (will be connected to EventManager later)
    hidden [System.Collections.Generic.List[hashtable]]$_eventSubscribers = @()
    
    EnhancedThemeManager() {
        $this._themes = [System.Collections.Generic.Dictionary[string, SimpleTheme]]::new()
        $this._changeHandlers = [System.Collections.Generic.List[scriptblock]]::new()
        $this._logger = Get-Logger
        
        # Register built-in themes
        $this.RegisterBuiltInThemes()
        
        # Set default theme
        $this.SetTheme("default")
        
        $this._logger.Info("EnhancedThemeManager", "Constructor", "Enhanced ThemeManager initialized with built-in themes")
    }
    
    <#
    .SYNOPSIS
    Register all built-in themes with both classic and modern options
    #>
    hidden [void] RegisterBuiltInThemes() {
        # Default theme (backward compatible)
        $default = [SimpleTheme]::new("default").
            DefineColor("primary", [EnhancedColors]::Blue).
            DefineColor("secondary", [EnhancedColors]::Cyan).
            DefineColor("success", [EnhancedColors]::Green).
            DefineColor("warning", [EnhancedColors]::Yellow).
            DefineColor("error", [EnhancedColors]::Red).
            DefineColor("info", [EnhancedColors]::Cyan).
            DefineColor("text", [EnhancedColors]::White).
            DefineColor("textDim", [EnhancedColors]::BrightBlack).
            DefineColor("background", "", [EnhancedColors]::BgBlack).
            DefineColor("selection", [EnhancedColors]::Black, [EnhancedColors]::BgWhite).
            DefineColor("focus", [EnhancedColors]::Yellow).
            DefineColor("border", [EnhancedColors]::BrightBlack).
            DefineColor("header", [EnhancedColors]::Bold + [EnhancedColors]::White).
            DefineStyle("bold", [EnhancedColors]::Bold).
            DefineStyle("dim", [EnhancedColors]::Dim).
            DefineStyle("italic", [EnhancedColors]::Italic).
            DefineStyle("underline", [EnhancedColors]::Underline).
            SetDescription("Classic SpeedTUI default theme").
            SetAuthor("SpeedTUI Team")
        
        $this.RegisterTheme($default)
        
        # Dark theme (enhanced version of default)
        $dark = [SimpleTheme]::new("dark").
            DefineRGBColor("primary", @(100, 149, 237)).     # Cornflower blue
            DefineRGBColor("secondary", @(70, 130, 180)).    # Steel blue
            DefineRGBColor("success", @(50, 205, 50)).       # Lime green
            DefineRGBColor("warning", @(255, 215, 0)).       # Gold
            DefineRGBColor("error", @(220, 20, 60)).         # Crimson
            DefineRGBColor("info", @(0, 191, 255)).          # Deep sky blue
            DefineRGBColor("text", @(248, 248, 242)).        # Off white
            DefineRGBColor("textDim", @(117, 113, 94)).      # Dim grey
            DefineRGBColor("background", @(40, 42, 54)).     # Dark purple-grey
            DefineRGBColor("selection", @(248, 248, 242), @(68, 71, 90)).  # Light text on purple
            DefineRGBColor("focus", @(241, 250, 140)).       # Light yellow
            DefineRGBColor("border", @(98, 114, 164)).       # Purple-blue
            DefineRGBColor("header", @(189, 147, 249)).      # Light purple
            DefineStyle("bold", [EnhancedColors]::Bold).
            DefineStyle("dim", [EnhancedColors]::Dim).
            SetDescription("Modern dark theme with purple accents").
            SetAuthor("SpeedTUI Team")
        
        $this.RegisterTheme($dark)
        
        # Matrix theme (green on black)
        $matrix = [SimpleTheme]::new("matrix").
            DefineRGBColor("primary", @(0, 255, 0)).         # Bright green
            DefineRGBColor("secondary", @(0, 200, 0)).       # Medium green
            DefineRGBColor("success", @(0, 255, 0)).         # Bright green
            DefineRGBColor("warning", @(255, 255, 0)).       # Yellow
            DefineRGBColor("error", @(255, 0, 0)).           # Red
            DefineRGBColor("info", @(0, 255, 255)).          # Cyan
            DefineRGBColor("text", @(0, 255, 0)).            # Bright green
            DefineRGBColor("textDim", @(0, 128, 0)).         # Dim green
            DefineRGBColor("background", @(0, 0, 0)).        # Pure black
            DefineRGBColor("selection", @(0, 0, 0), @(0, 255, 0)).  # Black on green
            DefineRGBColor("focus", @(0, 255, 0)).           # Bright green
            DefineRGBColor("border", @(0, 128, 0)).          # Dim green
            DefineRGBColor("header", @(0, 255, 0)).          # Bright green
            DefineStyle("bold", [EnhancedColors]::Bold).
            SetDescription("Matrix-inspired green on black theme").
            SetAuthor("SpeedTUI Team")
        
        $this.RegisterTheme($matrix)
        
        # Amber theme (warm amber on dark)
        $amber = [SimpleTheme]::new("amber").
            DefineRGBColor("primary", @(255, 191, 0)).       # Bright amber
            DefineRGBColor("secondary", @(255, 143, 0)).     # Orange amber
            DefineRGBColor("success", @(0, 255, 0)).         # Green
            DefineRGBColor("warning", @(255, 255, 0)).       # Yellow
            DefineRGBColor("error", @(255, 69, 0)).          # Red orange
            DefineRGBColor("info", @(135, 206, 235)).        # Sky blue
            DefineRGBColor("text", @(255, 191, 0)).          # Bright amber
            DefineRGBColor("textDim", @(204, 153, 0)).       # Dim amber
            DefineRGBColor("background", @(25, 20, 0)).      # Very dark amber
            DefineRGBColor("selection", @(25, 20, 0), @(255, 191, 0)).  # Dark on amber
            DefineRGBColor("focus", @(255, 215, 0)).         # Gold
            DefineRGBColor("border", @(204, 153, 0)).        # Dim amber
            DefineRGBColor("header", @(255, 215, 0)).        # Gold
            DefineStyle("bold", [EnhancedColors]::Bold).
            SetDescription("Warm amber theme inspired by vintage terminals").
            SetAuthor("SpeedTUI Team")
        
        $this.RegisterTheme($amber)
        
        # Electric theme (cyan/electric blue)
        $electric = [SimpleTheme]::new("electric").
            DefineRGBColor("primary", @(0, 255, 255)).       # Cyan
            DefineRGBColor("secondary", @(30, 144, 255)).    # Dodger blue
            DefineRGBColor("success", @(0, 255, 127)).       # Spring green
            DefineRGBColor("warning", @(255, 255, 0)).       # Yellow
            DefineRGBColor("error", @(255, 20, 147)).        # Deep pink
            DefineRGBColor("info", @(173, 216, 230)).        # Light blue
            DefineRGBColor("text", @(224, 255, 255)).        # Light cyan
            DefineRGBColor("textDim", @(95, 158, 160)).      # Cadet blue
            DefineRGBColor("background", @(8, 8, 16)).       # Very dark blue
            DefineRGBColor("selection", @(8, 8, 16), @(0, 255, 255)).  # Dark on cyan
            DefineRGBColor("focus", @(0, 255, 255)).         # Cyan
            DefineRGBColor("border", @(70, 130, 180)).       # Steel blue
            DefineRGBColor("header", @(135, 206, 250)).      # Light sky blue
            DefineStyle("bold", [EnhancedColors]::Bold).
            SetDescription("Electric blue theme with cyan highlights").
            SetAuthor("SpeedTUI Team")
        
        $this.RegisterTheme($electric)
        
        $this._logger.Info("EnhancedThemeManager", "RegisterBuiltInThemes", "Registered built-in themes", @{
            Themes = @($this._themes.Keys -join ", ")
        })
    }
    
    <#
    .SYNOPSIS
    Register a new theme (backward compatible)
    
    .PARAMETER theme
    SimpleTheme instance to register
    #>
    [void] RegisterTheme([SimpleTheme]$theme) {
        $this._themes[$theme.Name] = $theme
        $this._logger.Info("EnhancedThemeManager", "RegisterTheme", "Registered theme", @{
            Name = $theme.Name
            Description = $theme.Metadata.Description
        })
    }
    
    <#
    .SYNOPSIS
    Set the current theme (simple, one-method approach)
    
    .PARAMETER themeName
    Name of the theme to activate
    
    .EXAMPLE
    $themeManager.SetTheme("matrix")  # That's it!
    #>
    [void] SetTheme([string]$themeName) {
        if (-not $this._themes.ContainsKey($themeName)) {
            $availableThemes = $this._themes.Keys -join ", "
            $this._logger.Error("EnhancedThemeManager", "SetTheme", "Theme not found", @{
                RequestedTheme = $themeName
                AvailableThemes = $availableThemes
            })
            throw "Theme '$themeName' not found. Available themes: $availableThemes"
        }
        
        $oldTheme = $this._currentThemeName
        $this._currentTheme = $this._themes[$themeName]
        $this._currentThemeName = $themeName
        
        # Clear cache when theme changes
        $this._globalCache.Clear()
        
        $this._logger.Info("EnhancedThemeManager", "SetTheme", "Theme changed", @{
            OldTheme = $oldTheme
            NewTheme = $themeName
        })
        
        # Notify all change handlers
        $this.NotifyThemeChanged($oldTheme, $themeName)
    }
    
    <#
    .SYNOPSIS
    Get a color from the current theme (simple access)
    
    .PARAMETER colorName
    Name of the color to retrieve
    
    .OUTPUTS
    ANSI color sequence ready to use
    
    .EXAMPLE
    $primaryColor = $themeManager.GetColor("primary")
    Write-Host "${primaryColor}Hello World$([EnhancedColors]::Reset)"
    #>
    [string] GetColor([string]$colorName) {
        # Check global cache first for performance
        $cacheKey = "$($this._currentThemeName).$colorName"
        if ($this._globalCache.ContainsKey($cacheKey)) {
            return $this._globalCache[$cacheKey]
        }
        
        # Get from current theme
        $sequence = $this._currentTheme.GetSequence($colorName)
        
        # Cache for next time
        if ($sequence) {
            $this._globalCache[$cacheKey] = $sequence
        }
        
        return $sequence
    }
    
    <#
    .SYNOPSIS
    Get a style from the current theme
    
    .PARAMETER styleName
    Name of the style to retrieve
    
    .OUTPUTS
    ANSI style sequence
    #>
    [string] GetStyle([string]$styleName) {
        return $this._currentTheme.GetStyle($styleName)
    }
    
    <#
    .SYNOPSIS
    Set a custom color dynamically (advanced feature)
    
    .PARAMETER colorName
    Name of the color to set
    
    .PARAMETER rgb
    RGB array [r, g, b] for the color
    
    .EXAMPLE
    $themeManager.SetCustomColor("button.hover", @(100, 200, 255))
    #>
    [void] SetCustomColor([string]$colorName, [int[]]$rgb) {
        $this._currentTheme.DefineRGBColor($colorName, $rgb)
        
        # Update cache
        $cacheKey = "$($this._currentThemeName).$colorName"
        $this._globalCache[$cacheKey] = [InternalVT100]::RGB($rgb[0], $rgb[1], $rgb[2])
        
        $this._logger.Debug("EnhancedThemeManager", "SetCustomColor", "Custom color set", @{
            ColorName = $colorName
            RGB = ($rgb -join ",")
        })
    }
    
    <#
    .SYNOPSIS
    Get list of available themes
    
    .OUTPUTS
    Array of theme names
    #>
    [string[]] GetAvailableThemes() {
        return $this._themes.Keys | Sort-Object
    }
    
    <#
    .SYNOPSIS
    Get current theme name
    
    .OUTPUTS
    Current theme name
    #>
    [string] GetCurrentTheme() {
        return $this._currentThemeName
    }
    
    <#
    .SYNOPSIS
    Get theme information for display
    
    .PARAMETER themeName
    Optional theme name (defaults to current theme)
    
    .OUTPUTS
    Hashtable with theme information
    #>
    [hashtable] GetThemeInfo([string]$themeName = "") {
        if (-not $themeName) {
            $themeName = $this._currentThemeName
        }
        
        if (-not $this._themes.ContainsKey($themeName)) {
            return @{}
        }
        
        $theme = $this._themes[$themeName]
        return @{
            Name = $theme.Name
            Description = $theme.Metadata.Description
            Author = $theme.Metadata.Author
            Version = $theme.Metadata.Version
            ColorCount = $theme.Colors.Count
            StyleCount = $theme.Styles.Count
            Colors = $theme.Colors.Keys | Sort-Object
        }
    }
    
    <#
    .SYNOPSIS
    Subscribe to theme change events (backward compatible)
    
    .PARAMETER callback
    Scriptblock to call when theme changes
    #>
    [void] OnThemeChanged([scriptblock]$callback) {
        $this._changeHandlers.Add($callback)
    }
    
    # Notify all listeners of theme change
    hidden [void] NotifyThemeChanged([string]$oldTheme, [string]$newTheme) {
        foreach ($handler in $this._changeHandlers) {
            try {
                & $handler @{
                    OldTheme = $oldTheme
                    NewTheme = $newTheme
                    ThemeManager = $this
                }
            } catch {
                $this._logger.Warn("EnhancedThemeManager", "NotifyThemeChanged", "Theme change handler failed", @{
                    Error = $_.Exception.Message
                })
            }
        }
    }
    
    <#
    .SYNOPSIS
    Get performance statistics
    
    .OUTPUTS
    Hashtable with theme performance stats
    #>
    [hashtable] GetPerformanceStats() {
        return @{
            RegisteredThemes = $this._themes.Count
            CacheSize = $this._globalCache.Count
            CurrentTheme = $this._currentThemeName
            ChangeHandlers = $this._changeHandlers.Count
        }
    }
}

# Global functions for easy access (backward compatibility)

<#
.SYNOPSIS
Get the enhanced theme manager instance
#>
function Get-ThemeManager {
    if (-not $global:SpeedTUIThemeManager) {
        $global:SpeedTUIThemeManager = [EnhancedThemeManager]::new()
    }
    return $global:SpeedTUIThemeManager
}

<#
.SYNOPSIS
Quick theme switching helper
#>
function Set-SpeedTUITheme {
    param([string]$ThemeName)
    $themeManager = Get-ThemeManager
    $themeManager.SetTheme($ThemeName)
}

<#
.SYNOPSIS
Quick color access helper
#>
function Get-SpeedTUIColor {
    param([string]$ColorName)
    $themeManager = Get-ThemeManager
    return $themeManager.GetColor($ColorName)
}

<#
.SYNOPSIS
Create a new theme easily
#>
function New-SpeedTUITheme {
    param(
        [string]$Name,
        [string]$Description = "",
        [scriptblock]$Definition = {}
    )
    
    $theme = [SimpleTheme]::new($Name)
    if ($Description) {
        $theme.SetDescription($Description)
    }
    
    # Execute the definition block in the context of the theme
    $theme | ForEach-Object { & $Definition }
    
    $themeManager = Get-ThemeManager
    $themeManager.RegisterTheme($theme)
    
    return $theme
}

# Initialize the global theme manager
$global:SpeedTUIThemeManager = [EnhancedThemeManager]::new()

Export-ModuleMember -Function Get-ThemeManager, Set-SpeedTUITheme, Get-SpeedTUIColor, New-SpeedTUITheme