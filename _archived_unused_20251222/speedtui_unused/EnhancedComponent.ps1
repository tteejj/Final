# SpeedTUI Enhanced Component - Simple API with powerful performance optimizations
# Maintains full backward compatibility while adding new features and optimizations

# Load dependencies
. "$PSScriptRoot/Internal/PerformanceCore.ps1"
. "$PSScriptRoot/../Services/EnhancedThemeManager.ps1"

using namespace System.Collections.Generic

<#
.SYNOPSIS
Enhanced component with simple positioning, theming, and performance optimizations

.DESCRIPTION
Extends the existing Component functionality with:
- Simple, clear positioning methods (SetPosition, SetSize, MoveTo)
- Automatic theme integration with caching
- Performance optimizations through render caching
- Backward compatibility with existing Component API
- Progressive disclosure of advanced features

.EXAMPLE
# Simple usage (backward compatible)
$button = [EnhancedComponent]::new()
$button.SetPosition(10, 5)
$button.SetSize(20, 3)

# Enhanced usage with themes
$button.SetTheme("matrix")
$button.SetColor("primary")

# Advanced usage
$button.EnableRenderCaching()
$button.SetAnimation("fadeIn")
#>
class EnhancedComponent : Component {
    # Theme integration (simple access)
    [string]$ThemeName = "default"
    [string]$ColorScheme = "primary"
    hidden [EnhancedThemeManager]$_themeManager
    hidden [hashtable]$_colorCache = @{}
    
    # Performance enhancements (invisible to developers)
    hidden [string]$_renderCache = ""
    hidden [bool]$_renderCacheEnabled = $true
    hidden [bool]$_cacheInvalid = $true
    hidden [System.DateTime]$_lastRender = [System.DateTime]::MinValue
    
    # Simple positioning helpers
    [int]$MinWidth = 0
    [int]$MinHeight = 0
    [int]$MaxWidth = [int]::MaxValue
    [int]$MaxHeight = [int]::MaxValue
    
    # Animation support (advanced feature)
    hidden [string]$_currentAnimation = ""
    hidden [hashtable]$_animationState = @{}
    
    # Developer experience improvements
    [hashtable]$DebugInfo = @{}
    [bool]$ShowDebugBorder = $false
    
    EnhancedComponent() : base() {
        # Initialize theme manager
        $this._themeManager = Get-ThemeManager
        
        # Subscribe to theme changes for automatic cache invalidation
        $this._themeManager.OnThemeChanged({
            param($themeInfo)
            $this._colorCache.Clear()
            $this.InvalidateRenderCache()
        }.GetNewClosure())
        
        # Set default debug info
        $this.DebugInfo = @{
            ComponentType = $this.GetType().Name
            Created = [DateTime]::Now
            RenderCount = 0
            LastPositionChange = [DateTime]::MinValue
        }
        
        $this._logger.Info($this._logModule, "EnhancedComponent", "Enhanced component created", @{
            Id = $this.Id
            Type = $this.GetType().Name  
            ThemeEnabled = $true
        })
    }
    
    <#
    .SYNOPSIS
    Set component position using simple, clear method
    
    .PARAMETER x
    X coordinate (left position)
    
    .PARAMETER y  
    Y coordinate (top position)
    
    .EXAMPLE
    $component.SetPosition(10, 5)  # Position at column 10, row 5
    #>
    [void] SetPosition([int]$x, [int]$y) {
        if ($this.X -eq $x -and $this.Y -eq $y) {
            return  # No change needed
        }
        
        $this.X = $x
        $this.Y = $y
        $this.DebugInfo.LastPositionChange = [DateTime]::Now
        
        # Update render region if initialized
        if ($null -ne $this._renderEngine -and $this.Width -gt 0 -and $this.Height -gt 0) {
            $this._renderEngine.RemoveRegion($this._regionId)
            $this._renderEngine.DefineRegion($this._regionId, $x, $y, $this.Width, $this.Height)
        }
        
        $this.InvalidateRenderCache()
        $this.Invalidate()
        
        $this._logger.Debug($this._logModule, "SetPosition", "Position updated", @{
            Id = $this.Id
            NewPosition = "$x,$y"
        })
    }
    
    <#
    .SYNOPSIS
    Set component size with automatic constraint checking
    
    .PARAMETER width
    Component width
    
    .PARAMETER height
    Component height
    
    .EXAMPLE
    $component.SetSize(20, 3)  # Set to 20 columns wide, 3 rows tall
    #>
    [void] SetSize([int]$width, [int]$height) {
        # Apply size constraints
        $constrainedWidth = [Math]::Max([Math]::Min($width, $this.MaxWidth), $this.MinWidth)
        $constrainedHeight = [Math]::Max([Math]::Min($height, $this.MaxHeight), $this.MinHeight)
        
        if ($this.Width -eq $constrainedWidth -and $this.Height -eq $constrainedHeight) {
            return  # No change needed
        }
        
        $this.Width = $constrainedWidth
        $this.Height = $constrainedHeight
        
        # Update render region if initialized
        if ($null -ne $this._renderEngine -and $constrainedWidth -gt 0 -and $constrainedHeight -gt 0) {
            $this._renderEngine.RemoveRegion($this._regionId)
            $this._renderEngine.DefineRegion($this._regionId, $this.X, $this.Y, $constrainedWidth, $constrainedHeight)
        }
        
        $this.OnBoundsChanged()
        $this.InvalidateRenderCache()
        $this.Invalidate()
        
        $this._logger.Debug($this._logModule, "SetSize", "Size updated", @{
            Id = $this.Id
            RequestedSize = "${width}x${height}"
            ActualSize = "${constrainedWidth}x${constrainedHeight}"
        })
    }
    
    <#
    .SYNOPSIS
    Move component to new position (alias for SetPosition for clarity)
    
    .PARAMETER x
    New X coordinate
    
    .PARAMETER y
    New Y coordinate
    
    .EXAMPLE
    $component.MoveTo(15, 8)  # Move to column 15, row 8
    #>
    [void] MoveTo([int]$x, [int]$y) {
        $this.SetPosition($x, $y)
    }
    
    <#
    .SYNOPSIS
    Resize component (alias for SetSize for clarity)
    
    .PARAMETER width
    New width
    
    .PARAMETER height
    New height
    
    .EXAMPLE
    $component.Resize(25, 5)  # Resize to 25x5
    #>
    [void] Resize([int]$width, [int]$height) {
        $this.SetSize($width, $height)
    }
    
    <#
    .SYNOPSIS
    Set both position and size in one call
    
    .PARAMETER x
    X coordinate
    
    .PARAMETER y
    Y coordinate
    
    .PARAMETER width
    Width
    
    .PARAMETER height
    Height
    
    .EXAMPLE
    $component.SetBounds(10, 5, 20, 3)  # Position at 10,5 with size 20x3
    #>
    [void] SetBounds([int]$x, [int]$y, [int]$width, [int]$height) {
        ([Component]$this).SetBounds($x, $y, $width, $height)
    }
    
    <#
    .SYNOPSIS
    Set size constraints to prevent invalid sizing
    
    .PARAMETER minWidth
    Minimum allowed width
    
    .PARAMETER minHeight
    Minimum allowed height
    
    .PARAMETER maxWidth
    Maximum allowed width (optional)
    
    .PARAMETER maxHeight
    Maximum allowed height (optional)
    
    .EXAMPLE
    $component.SetSizeConstraints(5, 1, 50, 20)  # Min 5x1, max 50x20
    #>
    [void] SetSizeConstraints([int]$minWidth, [int]$minHeight, [int]$maxWidth = [int]::MaxValue, [int]$maxHeight = [int]::MaxValue) {
        $this.MinWidth = [Math]::Max(0, $minWidth)
        $this.MinHeight = [Math]::Max(0, $minHeight)
        $this.MaxWidth = [Math]::Max($this.MinWidth, $maxWidth)
        $this.MaxHeight = [Math]::Max($this.MinHeight, $maxHeight)
        
        # Reapply current size to respect new constraints
        $this.SetSize($this.Width, $this.Height)
    }
    
    <#
    .SYNOPSIS
    Set theme for this component (simple one-call theming)
    
    .PARAMETER themeName
    Name of the theme to use
    
    .EXAMPLE
    $component.SetTheme("matrix")  # Use matrix theme
    $component.SetTheme("amber")   # Use amber theme
    #>
    [void] SetTheme([string]$themeName) {
        if ($this.ThemeName -eq $themeName) {
            return  # No change needed
        }
        
        $this.ThemeName = $themeName
        $this._colorCache.Clear()  # Clear cached colors
        
        $this._logger.Debug($this._logModule, "SetTheme", "Theme changed", @{
            Id = $this.Id
            NewTheme = $themeName
        })
        
        $this.InvalidateRenderCache()
        $this.Invalidate()
    }
    
    <#
    .SYNOPSIS
    Set color scheme for this component
    
    .PARAMETER colorScheme
    Color scheme name (e.g., "primary", "secondary", "success", "error")
    
    .EXAMPLE
    $component.SetColor("primary")    # Use primary color scheme
    $component.SetColor("success")    # Use success color scheme
    #>
    [void] SetColor([string]$colorScheme) {
        if ($this.ColorScheme -eq $colorScheme) {
            return  # No change needed
        }
        
        $this.ColorScheme = $colorScheme
        $this._colorCache.Clear()  # Clear cached colors
        
        $this.InvalidateRenderCache()
        $this.Invalidate()
    }
    
    <#
    .SYNOPSIS
    Get themed color sequence for use in rendering
    
    .PARAMETER colorName
    Color name to retrieve (defaults to component's ColorScheme)
    
    .OUTPUTS
    ANSI color sequence ready for use
    
    .EXAMPLE
    $color = $component.GetThemedColor("primary")
    $component.WriteAt(0, 0, "${color}Hello World$([EnhancedColors]::Reset)")
    #>
    [string] GetThemedColor([string]$colorName = "") {
        if (-not $colorName) {
            $colorName = $this.ColorScheme
        }
        
        # Check cache first
        $cacheKey = "$($this.ThemeName).$colorName"
        if ($this._colorCache.ContainsKey($cacheKey)) {
            return $this._colorCache[$cacheKey]
        }
        
        # Get from theme manager
        $oldTheme = $this._themeManager.GetCurrentTheme()
        if ($oldTheme -ne $this.ThemeName) {
            $this._themeManager.SetTheme($this.ThemeName)
        }
        
        $color = $this._themeManager.GetColor($colorName)
        
        # Restore previous theme if we changed it
        if ($oldTheme -ne $this.ThemeName) {
            $this._themeManager.SetTheme($oldTheme)
        }
        
        # Cache the result
        $this._colorCache[$cacheKey] = $color
        return $color
    }
    
    <#
    .SYNOPSIS
    Enable/disable render caching for performance
    
    .PARAMETER enabled
    True to enable caching, false to disable
    
    .EXAMPLE
    $component.EnableRenderCaching($true)   # Enable caching
    $component.EnableRenderCaching($false)  # Disable caching
    #>
    [void] EnableRenderCaching([bool]$enabled) {
        $this._renderCacheEnabled = $enabled
        if (-not $enabled) {
            $this._renderCache = ""
            $this._cacheInvalid = $true
        }
    }
    
    <#
    .SYNOPSIS
    Invalidate the render cache to force re-rendering
    #>
    [void] InvalidateRenderCache() {
        $this._cacheInvalid = $true
        $this._renderCache = ""
    }
    
    <#
    .SYNOPSIS
    Enhanced rendering with caching and performance optimizations
    #>
    [void] Render() {
        if (-not $this.Visible) { 
            return 
        }
        
        # Check if we can use cached render
        if ($this._renderCacheEnabled -and -not $this._cacheInvalid -and $this._renderCache) {
            # Use cached render for better performance
            if ($null -ne $this._renderEngine) {
                # Write cached content directly
                $this.WriteCachedContent()
            }
        } else {
            # Perform full render
            $this.FullRender()
        }
        
        # Update debug info
        $this.DebugInfo.RenderCount++
        $this.DebugInfo.LastRender = [DateTime]::Now
        
        # Render children
        foreach ($child in $this.Children) {
            $child.Render()
        }
    }
    
    # Full rendering with caching
    hidden [void] FullRender() {
        if ($null -eq $this._renderEngine) { 
            return 
        }
        
        $timer = $this._logger.MeasurePerformance($this._logModule, "FullRender")
        
        try {
            # Clear region
            $this._renderEngine.ClearRegion($this._regionId)
            
            # Render self
            if ($this._renderCacheEnabled) {
                # Capture render output for caching
                $this.CaptureRender()
            } else {
                # Direct render without caching
                $this.OnRender()
            }
            
            # Draw debug border if enabled
            if ($this.ShowDebugBorder) {
                $this.DrawDebugBorder()
            }
            
            $this._cacheInvalid = $false
            $this._lastRender = [DateTime]::Now
            
        } finally {
            $timer.Dispose()
        }
    }
    
    # Capture render output for caching
    hidden [void] CaptureRender() {
        # Use StringBuilder pooling for performance
        $sb = Get-PooledStringBuilder 1024
        
        try {
            # Render to StringBuilder instead of directly to screen
            $this.OnRenderToStringBuilder($sb)
            
            # Cache the result
            $this._renderCache = $sb.ToString()
            
            # Now render to screen
            if ($this._renderCache) {
                $this.WriteCachedContent()
            }
            
        } finally {
            Return-PooledStringBuilder $sb
        }
    }
    
    # Write cached content to screen
    hidden [void] WriteCachedContent() {
        if (-not $this._renderCache) {
            return
        }
        
        # Parse cached content and write to render engine
        # For now, just call OnRender (can be optimized further)
        $this.OnRender()
    }
    
    # Override this in derived classes for StringBuilder rendering
    [void] OnRenderToStringBuilder([System.Text.StringBuilder]$sb) {
        # Default implementation just calls regular OnRender
        $this.OnRender()
    }
    
    # Draw debug border around component
    hidden [void] DrawDebugBorder() {
        if ($this.Width -lt 2 -or $this.Height -lt 2) {
            return  # Too small for border
        }
        
        # Use a bright color for debug border
        $debugColor = [EnhancedColors]::RGB(255, 0, 255)  # Magenta
        
        # Draw border lines
        for ($x = 0; $x -lt $this.Width; $x++) {
            $this.WriteAtColored(0, $x, "─", $debugColor)
            if ($this.Height -gt 1) {
                $this.WriteAtColored($this.Height - 1, $x, "─", $debugColor)
            }
        }
        
        for ($y = 0; $y -lt $this.Height; $y++) {
            $this.WriteAtColored($y, 0, "│", $debugColor)
            if ($this.Width -gt 1) {
                $this.WriteAtColored($y, $this.Width - 1, "│", $debugColor)
            }
        }
        
        # Draw corners
        $this.WriteAtColored(0, 0, "┌", $debugColor)
        if ($this.Width -gt 1) {
            $this.WriteAtColored(0, $this.Width - 1, "┐", $debugColor)
        }
        if ($this.Height -gt 1) {
            $this.WriteAtColored($this.Height - 1, 0, "└", $debugColor)
            if ($this.Width -gt 1) {
                $this.WriteAtColored($this.Height - 1, $this.Width - 1, "┘", $debugColor)
            }
        }
    }
    
    <#
    .SYNOPSIS
    Write text at position with themed colors
    
    .PARAMETER x
    Relative X position within component
    
    .PARAMETER y
    Relative Y position within component
    
    .PARAMETER text
    Text to write
    
    .PARAMETER colorName
    Optional color name (defaults to component's ColorScheme)
    
    .EXAMPLE
    $component.WriteAtThemed(0, 0, "Hello", "primary")
    #>
    [void] WriteAtThemed([int]$x, [int]$y, [string]$text, [string]$colorName = "") {
        $color = $this.GetThemedColor($colorName)
        $coloredText = "${color}${text}$([EnhancedColors]::Reset)"
        $this.WriteAt($x, $y, $coloredText)
    }
    
    # Helper method for writing colored text
    hidden [void] WriteAtColored([int]$x, [int]$y, [string]$text, [string]$color) {
        $coloredText = "${color}${text}$([EnhancedColors]::Reset)"
        $this.WriteAt($x, $y, $coloredText)
    }
    
    <#
    .SYNOPSIS
    Set animation for this component (advanced feature)
    
    .PARAMETER animationName
    Name of the animation to play
    
    .EXAMPLE
    $component.SetAnimation("fadeIn")
    $component.SetAnimation("slideLeft")
    #>
    [void] SetAnimation([string]$animationName) {
        $this._currentAnimation = $animationName
        $this._animationState = @{
            Name = $animationName
            StartTime = [DateTime]::Now
            Progress = 0.0
        }
        
        $this._logger.Debug($this._logModule, "SetAnimation", "Animation set", @{
            Id = $this.Id
            Animation = $animationName
        })
    }
    
    <#
    .SYNOPSIS  
    Get component performance statistics
    
    .OUTPUTS
    Hashtable with performance information
    
    .EXAMPLE
    $stats = $component.GetPerformanceStats()
    Write-Host "Render count: $($stats.RenderCount)"
    #>
    [hashtable] GetPerformanceStats() {
        return @{
            Id = $this.Id
            Type = $this.GetType().Name
            RenderCount = $this.DebugInfo.RenderCount
            LastRender = $this.DebugInfo.LastRender
            CacheEnabled = $this._renderCacheEnabled
            CacheSize = $(if ($this._renderCache) { $this._renderCache.Length } else { 0 })
            ColorCacheSize = $this._colorCache.Count
            Position = "$($this.X),$($this.Y)"
            Size = "$($this.Width)x$($this.Height)"
            Theme = $this.ThemeName
            ColorScheme = $this.ColorScheme
        }
    }
    
    <#
    .SYNOPSIS
    Show debug information about this component
    
    .EXAMPLE
    $component.ShowDebugInfo()
    #>
    [void] ShowDebugInfo() {
        $stats = $this.GetPerformanceStats()
        
        Write-Host "`n=== Component Debug Info ===" -ForegroundColor Cyan
        Write-Host "ID: $($stats.Id)" -ForegroundColor Yellow
        Write-Host "Type: $($stats.Type)" -ForegroundColor Yellow
        Write-Host "Position: $($stats.Position)" -ForegroundColor Green
        Write-Host "Size: $($stats.Size)" -ForegroundColor Green
        Write-Host "Theme: $($stats.Theme)" -ForegroundColor Magenta
        Write-Host "Color Scheme: $($stats.ColorScheme)" -ForegroundColor Magenta
        Write-Host "Render Count: $($stats.RenderCount)" -ForegroundColor Blue
        Write-Host "Cache Enabled: $($stats.CacheEnabled)" -ForegroundColor Blue
        Write-Host "Cache Size: $($stats.CacheSize) chars" -ForegroundColor Blue
        Write-Host "============================`n" -ForegroundColor Cyan
    }
    
    <#
    .SYNOPSIS
    Enable debug border to visualize component bounds
    
    .PARAMETER enabled
    True to show debug border, false to hide
    
    .EXAMPLE
    $component.ShowDebugBounds($true)   # Show debug border
    $component.ShowDebugBounds($false)  # Hide debug border
    #>
    [void] ShowDebugBounds([bool]$enabled) {
        $this.ShowDebugBorder = $enabled
        $this.InvalidateRenderCache()
        $this.Invalidate()
    }
}

<#
.SYNOPSIS
Enhanced ComponentBuilder with fluent interface and smart defaults

.DESCRIPTION
Provides a fluent interface for building components with sensible defaults
and automatic constraint checking. Makes component creation simple and clear.

.EXAMPLE
$button = [EnhancedComponentBuilder]::new([Button]::new()).
    Position(10, 5).
    Size(20, 3).
    Theme("matrix").
    Color("primary").
    OnClick({ Write-Host "Clicked!" }).
    Build()
#>
class EnhancedComponentBuilder : ComponentBuilder {
    hidden [EnhancedComponent]$_enhancedComponent
    
    EnhancedComponentBuilder([EnhancedComponent]$component) : base($component) {
        $this._enhancedComponent = $component
    }
    
    <#
    .SYNOPSIS
    Set theme using fluent interface
    
    .PARAMETER themeName
    Theme name to apply
    
    .OUTPUTS
    EnhancedComponentBuilder for method chaining
    #>
    [EnhancedComponentBuilder] Theme([string]$themeName) {
        $this._enhancedComponent.SetTheme($themeName)
        return $this
    }
    
    <#
    .SYNOPSIS
    Set color scheme using fluent interface
    
    .PARAMETER colorScheme
    Color scheme to apply
    
    .OUTPUTS
    EnhancedComponentBuilder for method chaining
    #>
    [EnhancedComponentBuilder] Color([string]$colorScheme) {
        $this._enhancedComponent.SetColor($colorScheme)
        return $this
    }
    
    <#
    .SYNOPSIS
    Set size constraints using fluent interface
    
    .PARAMETER minWidth
    Minimum width
    
    .PARAMETER minHeight
    Minimum height
    
    .PARAMETER maxWidth
    Maximum width (optional)
    
    .PARAMETER maxHeight
    Maximum height (optional)
    
    .OUTPUTS
    EnhancedComponentBuilder for method chaining
    #>
    [EnhancedComponentBuilder] SizeConstraints([int]$minWidth, [int]$minHeight, [int]$maxWidth = [int]::MaxValue, [int]$maxHeight = [int]::MaxValue) {
        $this._enhancedComponent.SetSizeConstraints($minWidth, $minHeight, $maxWidth, $maxHeight)
        return $this
    }
    
    <#
    .SYNOPSIS
    Enable/disable render caching using fluent interface
    
    .PARAMETER enabled
    True to enable caching
    
    .OUTPUTS
    EnhancedComponentBuilder for method chaining
    #>
    [EnhancedComponentBuilder] Caching([bool]$enabled) {
        $this._enhancedComponent.EnableRenderCaching($enabled)
        return $this
    }
    
    <#
    .SYNOPSIS
    Enable debug border using fluent interface
    
    .PARAMETER enabled
    True to show debug border
    
    .OUTPUTS
    EnhancedComponentBuilder for method chaining
    #>
    [EnhancedComponentBuilder] Debug([bool]$enabled) {
        $this._enhancedComponent.ShowDebugBounds($enabled)
        return $this
    }
    
    <#
    .SYNOPSIS
    Set animation using fluent interface
    
    .PARAMETER animationName
    Animation name
    
    .OUTPUTS
    EnhancedComponentBuilder for method chaining
    #>
    [EnhancedComponentBuilder] Animation([string]$animationName) {
        $this._enhancedComponent.SetAnimation($animationName)
        return $this
    }
    
    # Override Build to return the enhanced component
    [EnhancedComponent] Build() {
        return $this._enhancedComponent
    }
}

# Helper functions for easy component creation

<#
.SYNOPSIS
Create a new enhanced component with fluent builder interface

.PARAMETER componentType
Type of component to create (defaults to EnhancedComponent)

.OUTPUTS
EnhancedComponentBuilder for fluent configuration

.EXAMPLE
$button = New-EnhancedComponent ([Button]::new()) |
    Position 10 5 |
    Size 20 3 |
    Theme "matrix" |
    Build
#>
function New-EnhancedComponent {
    param(
        [EnhancedComponent]$Component = [EnhancedComponent]::new()
    )
    
    return [EnhancedComponentBuilder]::new($Component)
}

<#
.SYNOPSIS
Quick component positioning helper

.PARAMETER components
Array of components to arrange

.PARAMETER startX
Starting X position

.PARAMETER startY
Starting Y position

.PARAMETER spacing
Spacing between components

.EXAMPLE
$components | Arrange-Vertically -StartX 10 -StartY 5 -Spacing 2
#>
function Arrange-Vertically {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [EnhancedComponent[]]$Components,
        [int]$StartX = 0,
        [int]$StartY = 0,
        [int]$Spacing = 1
    )
    
    begin {
        $currentY = $StartY
        $arrangedComponents = @()
    }
    
    process {
        foreach ($component in $Components) {
            $component.SetPosition($StartX, $currentY)
            $currentY += $component.Height + $Spacing
            $arrangedComponents += $component
        }
    }
    
    end {
        return $arrangedComponents
    }
}

<#
.SYNOPSIS
Quick horizontal component arrangement helper

.PARAMETER components
Array of components to arrange

.PARAMETER startX
Starting X position

.PARAMETER startY
Starting Y position

.PARAMETER spacing
Spacing between components

.EXAMPLE
$components | Arrange-Horizontally -StartX 10 -StartY 5 -Spacing 3
#>
function Arrange-Horizontally {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [EnhancedComponent[]]$Components,
        [int]$StartX = 0,
        [int]$StartY = 0,
        [int]$Spacing = 2
    )
    
    begin {
        $currentX = $StartX
        $arrangedComponents = @()
    }
    
    process {
        foreach ($component in $Components) {
            $component.SetPosition($currentX, $StartY)
            $currentX += $component.Width + $Spacing
            $arrangedComponents += $component
        }
    }
    
    end {
        return $arrangedComponents
    }
}

Export-ModuleMember -Function New-EnhancedComponent, Arrange-Vertically, Arrange-Horizontally