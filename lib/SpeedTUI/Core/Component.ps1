# SpeedTUI Enhanced Component System - The new foundation for all SpeedTUI components
# Combines performance optimizations with simple, clear APIs for easy development

using namespace System.Collections.Generic

# Load performance optimizations (automatically improves string operations)
. "$PSScriptRoot/Internal/PerformanceCore.ps1"

<#
.SYNOPSIS
Enhanced base component class for all SpeedTUI UI elements

.DESCRIPTION
The foundation class for all SpeedTUI components, providing:
- Simple positioning and sizing with SetPosition(x, y) and SetSize(w, h)
- Easy theming with SetTheme(name) and SetColor(role)
- Automatic performance optimizations (string caching, render caching)
- Event system integration
- Layout helpers and constraints
- Debug and development tools

.EXAMPLE
# Simple usage - clear and intuitive
$button = [Button]::new("OK", 0, 0)
$button.SetPosition(10, 5)
$button.SetSize(20, 3)
$button.SetTheme("matrix")
$button.SetColor("primary")

# Automatic arrangement
@($button1, $button2, $button3) | Arrange-Vertically -StartX 10 -StartY 5 -Spacing 2

# Performance monitoring
$button.EnableRenderCaching($true)
$stats = $button.GetPerformanceStats()
#>
class Component {
    # === Core Properties ===
    [string]$Id                    # Unique identifier
    [Component]$Parent             # Parent in component hierarchy
    [List[Component]]$Children     # Child components
    
    # === Layout Properties ===
    [int]$X = 0                    # X position relative to parent
    [int]$Y = 0                    # Y position relative to parent
    [int]$Width = 0                # Width in characters
    [int]$Height = 0               # Height in characters
    [bool]$Visible = $true         # Visibility flag
    
    # === Focus Management ===
    [bool]$CanFocus = $false       # Can receive keyboard focus
    [bool]$HasFocus = $false        # Currently has focus
    [int]$TabIndex = 0              # Tab order for navigation
    
    # === Event Handlers ===
    [scriptblock]$OnFocus = {}     # Focus gained event
    [scriptblock]$OnBlur = {}      # Focus lost event
    [scriptblock]$OnKeyPress = {}  # Key press event
    [scriptblock]$OnClick = {}     # Click/activation event
    
    # === Enhanced Features (Private) ===
    hidden [string]$_regionId                    # Render region identifier
    hidden [object]$_renderEngine                         # Rendering engine reference (supports both Optimized and Enhanced)
    hidden [bool]$_needsRedraw = $true          # Redraw flag

    # Performance and caching
    hidden [bool]$_renderCacheEnabled = $false   # Enable render caching
    hidden [string]$_cachedRenderResult = ""     # Cached output
    hidden [int]$_renderCount = 0                # Total renders
    hidden [int]$_cacheHitCount = 0              # Cache hits
    hidden [bool]$_cacheInvalid = $true          # Cache invalidation flag (Praxis style)
    hidden [string]$_cachedPosition = ""         # Pre-computed position ANSI

    # Batch invalidation support (reduces cascades)
    hidden static [bool]$_batchMode = $false
    hidden static [object]$_batchInvalidated = $null
    
    # Theming system
    hidden [string]$_themeName = "default"       # Current theme
    hidden [string]$_currentColor = ""           # Current color role
    hidden [hashtable]$_customColors = @{}      # Custom color overrides
    
    # Layout constraints
    hidden [int]$_minWidth = 1                   # Minimum width
    hidden [int]$_minHeight = 1                  # Minimum height
    hidden [int]$_maxWidth = 1000                # Maximum width
    hidden [int]$_maxHeight = 1000               # Maximum height
    
            # Logging and debugging
            hidden [object]$_logger = $null
            hidden [string]$_logModule = ""    
    <#
    .SYNOPSIS
    Initialize a new component instance
    
    .DESCRIPTION
    Sets up the component with enhanced features including:
    - Performance optimizations
    - Theme system integration
    - Logging and debugging
    - Render caching system
    #>
    Component() {
        # Generate unique identifier
        $this.Id = [Guid]::NewGuid().ToString()
        
        # Initialize collections
        $this.Children = [List[Component]]::new()
        $this._customColors = @{}
        
        # Setup logging for debugging
        # $this._logger = [object](Get-Logger) 
        $this._logModule = $this.GetType().Name
        $this._regionId = "component_$($this.Id)"
        
        # Component created
    }
    
    # === Enhanced Layout Methods (Simple and Clear) ===
    
    <#
    .SYNOPSIS
    Set component position with clear, simple method
    
    .PARAMETER x
    X coordinate (left edge)
    
    .PARAMETER y
    Y coordinate (top edge)
    
    .EXAMPLE
    $button.SetPosition(10, 5)  # Much clearer than SetBounds(10, 5, width, height)
    #>
    [void] SetPosition([int]$x, [int]$y) {
        # Input validation
        [Guard]::NonNegative($x, "x")
        [Guard]::NonNegative($y, "y")
        
        # Skip if no change (performance optimization)
        if ($this.X -eq $x -and $this.Y -eq $y) {
            return
        }
        
        # Removed trace logging for performance
        
        # Update position
        $this.X = $x
        $this.Y = $y
        
        # Update render region if initialized
        if ($null -ne $this._renderEngine -and $this.Width -gt 0 -and $this.Height -gt 0) {
            # No region updates needed for simplified engine
        }
        
        # Invalidate cached render
        $this.InvalidateRenderCache()
        $this.Invalidate()
    }
    
    <#
    .SYNOPSIS
    Set component size with clear, simple method
    
    .PARAMETER width
    Width in characters
    
    .PARAMETER height
    Height in characters
    
    .EXAMPLE
    $button.SetSize(20, 3)  # Much clearer than SetBounds(x, y, 20, 3)
    #>
    [void] SetSize([int]$width, [int]$height) {
        # Input validation
        [Guard]::Positive($width, "width")
        [Guard]::Positive($height, "height")
        
        # Apply constraints
        $constrainedWidth = [Math]::Max($this._minWidth, [Math]::Min($this._maxWidth, $width))
        $constrainedHeight = [Math]::Max($this._minHeight, [Math]::Min($this._maxHeight, $height))
        
        # Skip if no change (performance optimization)
        if ($this.Width -eq $constrainedWidth -and $this.Height -eq $constrainedHeight) {
            return
        }
        
        # Removed trace logging for performance
        
        # Update size
        $this.Width = $constrainedWidth
        $this.Height = $constrainedHeight
        
        # Update render region if initialized
        if ($null -ne $this._renderEngine) {
            # No region updates needed for simplified engine
        }
        
        # Trigger layout update
        $this.OnBoundsChanged()
        $this.InvalidateRenderCache()
        $this.Invalidate()
    }
    
    <#
    .SYNOPSIS
    Move component to new position (convenience method)
    
    .PARAMETER x
    New X coordinate
    
    .PARAMETER y  
    New Y coordinate
    
    .EXAMPLE
    $button.MoveTo(15, 8)  # Simple movement
    #>
    [void] MoveTo([int]$x, [int]$y) {
        $this.SetPosition($x, $y)
    }
    
    <#
    .SYNOPSIS
    Resize component (convenience method)
    
    .PARAMETER width
    New width
    
    .PARAMETER height
    New height
    
    .EXAMPLE
    $button.Resize(25, 4)  # Simple resizing
    #>
    [void] Resize([int]$width, [int]$height) {
        $this.SetSize($width, $height)
    }
    
    <#
    .SYNOPSIS
    Set size constraints for automatic layout
    
    .PARAMETER minWidth
    Minimum width
    
    .PARAMETER minHeight
    Minimum height
    
    .PARAMETER maxWidth
    Maximum width
    
    .PARAMETER maxHeight
    Maximum height
    
    .EXAMPLE
    $input.SetSizeConstraints(10, 1, 50, 5)  # Min 10x1, max 50x5
    #>
    [void] SetSizeConstraints([int]$minWidth, [int]$minHeight, [int]$maxWidth, [int]$maxHeight) {
        [Guard]::Positive($minWidth, "minWidth")
        [Guard]::Positive($minHeight, "minHeight")
        [Guard]::Condition($maxWidth -ge $minWidth, "maxWidth must be >= minWidth")
        [Guard]::Condition($maxHeight -ge $minHeight, "maxHeight must be >= minHeight")
        
        $this._minWidth = $minWidth
        $this._minHeight = $minHeight
        $this._maxWidth = $maxWidth
        $this._maxHeight = $maxHeight
        
        # Re-apply current size to enforce constraints
        $this.SetSize($this.Width, $this.Height)
    }
    
    # === Enhanced Theming Methods (Simple and Powerful) ===
    
    <#
    .SYNOPSIS
    Apply a theme to this component
    
    .PARAMETER themeName
    Name of theme to apply (matrix, amber, electric, etc.)
    
    .EXAMPLE
    $button.SetTheme("matrix")    # Apply matrix theme (green on black)
    $button.SetTheme("electric")  # Apply electric theme (blue on dark)
    #>
    [void] SetTheme([string]$themeName) {
        if ([string]::IsNullOrWhiteSpace($themeName)) {
            $themeName = "default"
        }
        
        # Skip if no change
        if ($this._themeName -eq $themeName) {
            return
        }
        
        # Removed trace logging for performance
        
        $this._themeName = $themeName
        
        # Clear custom colors when changing themes
        $this._customColors.Clear()
        
        # Invalidate render cache since colors changed
        $this.InvalidateRenderCache()
        $this.Invalidate()
    }
    
    <#
    .SYNOPSIS
    Set the color role for this component within current theme
    
    .PARAMETER colorRole
    Color role (primary, secondary, success, warning, error, etc.)
    
    .EXAMPLE
    $button.SetColor("primary")    # Use primary color from current theme
    $button.SetColor("success")    # Use success color (usually green)
    #>
    [void] SetColor([string]$colorRole) {
        if ([string]::IsNullOrWhiteSpace($colorRole)) {
            $colorRole = "text"
        }
        
        # Skip if no change
        if ($this._currentColor -eq $colorRole) {
            return
        }
        
        # Removed trace logging for performance
        
        $this._currentColor = $colorRole
        
        # Invalidate render cache since color changed
        $this.InvalidateRenderCache()
        $this.Invalidate()
    }
    
    <#
    .SYNOPSIS
    Set custom RGB color for this component (overrides theme)
    
    .PARAMETER r
    Red component (0-255)
    
    .PARAMETER g
    Green component (0-255)
    
    .PARAMETER b
    Blue component (0-255)
    
    .EXAMPLE
    $button.SetCustomColor(255, 100, 50)  # Custom orange color
    #>
    [void] SetCustomColor([int]$r, [int]$g, [int]$b) {
        [Guard]::InRange($r, 0, 255, "r")
        [Guard]::InRange($g, 0, 255, "g")
        [Guard]::InRange($b, 0, 255, "b")
        
        # Use internal VT100 helper for optimized ANSI sequences
        $customColor = [InternalVT100]::RGB($r, $g, $b)
        $this._customColors["foreground"] = $customColor
        
        # Removed trace logging for performance
        
        $this.InvalidateRenderCache()
        $this.Invalidate()
    }
    
    # === Performance and Caching Methods ===
    
    <#
    .SYNOPSIS
    Enable or disable render caching for performance
    
    .PARAMETER enabled
    Whether to enable render caching
    
    .EXAMPLE
    $component.EnableRenderCaching($true)  # Cache render output for speed
    #>
    [void] EnableRenderCaching([bool]$enabled) {
        if ($this._renderCacheEnabled -eq $enabled) {
            return
        }
        
        $this._renderCacheEnabled = $enabled
        
        if (-not $enabled) {
            # Clear cache when disabling
            $this._cachedRenderResult = ""
        }
        
        # Render caching toggled
    }
    
    <#
    .SYNOPSIS
    Invalidate render cache (call when visual properties change)
    
    .DESCRIPTION
    Forces the component to re-render on next draw by clearing cached results.
    Called automatically by SetPosition, SetSize, SetTheme, etc.
    #>
    [void] InvalidateRenderCache() {
        $this._cacheInvalid = $true
        if ($this._renderCacheEnabled -and $this._cachedRenderResult.Length -gt 0) {
            $this._cachedRenderResult = ""
            # Cache cleared
        }
    }
    
    <#
    .SYNOPSIS
    Get performance statistics for this component
    
    .OUTPUTS
    Hashtable with performance metrics
    
    .EXAMPLE
    $stats = $component.GetPerformanceStats()
    Write-Host "Renders: $($stats.RenderCount), Cache hits: $($stats.CacheHits)"
    #>
    [hashtable] GetPerformanceStats() {
        $cacheHitRate = $(if ($this._renderCount -gt 0) { 
            [Math]::Round(($this._cacheHitCount / $this._renderCount) * 100, 1) 
        } else { 0 })
        
        return @{
            Id = $this.Id
            Type = $this.GetType().Name
            Position = "$($this.X),$($this.Y)"
            Size = "$($this.Width)x$($this.Height)"
            Theme = $this._themeName
            Color = $this._currentColor
            RenderCount = $this._renderCount
            CacheHits = $this._cacheHitCount
            CacheHitRate = $cacheHitRate
            CacheEnabled = $this._renderCacheEnabled
        }
    }
    
    # === Existing Methods (Enhanced with Performance) ===
    
    # Initialize with render engine
    [void] Initialize([object]$renderEngine) {
        # Initializing component
        
        try {
            [Guard]::NotNull($renderEngine, "renderEngine")
            
            $this._renderEngine = $renderEngine
            
            # No region definition needed for simplified engine
            
            # Initialize children
            foreach ($child in $this.Children) {
                $child.Initialize($renderEngine)
            }
            
            # Component initialized successfully
            
        } catch {
            $this._logger.Error($this._logModule, "Initialize", "Initialization failed", @{
                Id = $this.Id
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    # Legacy SetBounds method (still works for existing code)
    [void] SetBounds([int]$x, [int]$y, [int]$width, [int]$height) {
        # Legacy SetBounds - use new methods internally
        
        # Use new enhanced methods internally
        $this.SetPosition($x, $y)
        $this.SetSize($width, $height)
    }
    
    # Enhanced render method with Praxis-style aggressive caching
    [string] Render() {
        if (-not $this.Visible) { 
            return ""
        }
        
        $this._renderCount++
        
        # Use cached result if available and valid (Praxis optimization)
        if ($this._renderCacheEnabled -and -not $this._cacheInvalid -and $this._cachedRenderResult) {
            $this._cacheHitCount++
            return $this._cachedRenderResult
        }
        
        # PERFORMANCE: Check if component implements direct engine rendering
        # This is detected by checking if OnRenderToEngine was overridden
        $hasFastPath = $this.GetType().GetMethod('OnRenderToEngine').DeclaringType.Name -ne 'Component'

        if ($hasFastPath -and $null -ne $this._renderEngine) {
            # FAST PATH: Component uses direct engine rendering
            # No string building, no ANSI parsing - just direct WriteAt() calls
            $this.OnRenderToEngine($this._renderEngine)

            # Render children (they may also use fast path)
            foreach ($child in $this.Children) {
                if ($child.Visible) {
                    $child.Render()  # Each child decides its own path
                }
            }

            $this._needsRedraw = $false
            # Return empty string to signal "already rendered to engine"
            return ""
        }

        # LEGACY PATH: Build ANSI string (backward compatible)
        $sb = Get-PooledStringBuilder 1024

        # Render component (calls OnRender)
        # No region clearing needed for simplified engine

        # Get component-specific render output
        $componentOutput = $this.OnRender()
        if ($componentOutput) {
            $sb.Append($componentOutput)
        }

        $this._needsRedraw = $false

        # Render children
        foreach ($child in $this.Children) {
            $childOutput = $child.Render()
            if ($childOutput) {
                $sb.Append($childOutput)
            }
        }

        # Cache the result
        $result = $sb.ToString()
        if ($this._renderCacheEnabled) {
            $this._cachedRenderResult = $result
            $this._cacheInvalid = $false
        }

        Return-PooledStringBuilder $sb
        return $result
    }
    
    # Virtual method for component-specific rendering
    [string] OnRender() {
        # Override in derived classes
        # Base implementation returns empty string
        return ""
    }

    # PERFORMANCE: Optional direct engine rendering (avoids ANSI string parsing)
    # Override this method in derived classes for maximum performance
    # When implemented, this completely bypasses string building and regex parsing
    [void] OnRenderToEngine([object]$engine) {
        # Override in derived classes for direct engine rendering
        # Base implementation is no-op (falls back to OnRender)
        #
        # Example implementation:
        # [void] OnRenderToEngine([object]$engine) {
        #     $engine.WriteAt($this.X, $this.Y, "Hello World")
        # }
    }

    # Virtual method called when bounds change
    [void] OnBoundsChanged() {
        # Override in derived classes for layout recalculation
        # Good place to call PrecomputeRenderData()
        $this.PrecomputeRenderData()
    }
    
    # Pre-compute expensive values (Praxis optimization)
    [void] PrecomputeRenderData() {
        # Pre-compute position ANSI sequence
        $this._cachedPosition = [InternalVT100]::MoveTo($this.X, $this.Y)
        
        # Override in derived classes to pre-compute:
        # - Border strings
        # - Padding calculations  
        # - Color sequences
        # - Any repeated calculations
    }
    
    # Component invalidation
    [void] Invalidate() {
        # If in batch mode, queue invalidation instead of cascading immediately
        if ([Component]::_batchMode) {
            if ($null -eq [Component]::_batchInvalidated) {
                [Component]::_batchInvalidated = [System.Collections.Generic.HashSet[Component]]::new()
            }
            [Component]::_batchInvalidated.Add($this)
            return
        }

        # Normal immediate invalidation with cascade
        $this._DoInvalidate()
    }

    # Internal method that performs actual invalidation with cascade
    hidden [void] _DoInvalidate() {
        $this._needsRedraw = $true
        $this.InvalidateRenderCache()

        # No dirty marking needed for simplified engine

        # Propagate to parent
        if ($null -ne $this.Parent) {
            $this.Parent.Invalidate()
        }
    }

    # Start batch invalidation mode (reduces cascade overhead)
    static [void] BeginBatch() {
        [Component]::_batchMode = $true
        [Component]::_batchInvalidated = [System.Collections.Generic.HashSet[Component]]::new()
    }

    # End batch mode and flush all queued invalidations
    static [void] EndBatch() {
        if (-not [Component]::_batchMode) { return }

        $components = [Component]::_batchInvalidated
        [Component]::_batchMode = $false
        [Component]::_batchInvalidated = $null

        # Process all queued invalidations
        if ($null -ne $components) {
            foreach ($component in $components) {
                $component._DoInvalidate()
            }
        }
    }
    
    # Child management
    [void] AddChild([Component]$child) {
        [Guard]::NotNull($child, "child")
        
        if ($child.Parent -ne $null) {
            throw [InvalidOperationException]::new("Component already has a parent")
        }
        
        $child.Parent = $this
        $this.Children.Add($child)
        
        # Initialize if we're already initialized
        if ($null -ne $this._renderEngine) {
            $child.Initialize($this._renderEngine)
        }
        
        $this.Invalidate()
    }
    
    [void] RemoveChild([Component]$child) {
        [Guard]::NotNull($child, "child")
        
        if ($this.Children.Remove($child)) {
            $child.Parent = $null
            
            # No region removal needed for simplified engine
            
            $this.Invalidate()
        }
    }
    
    # Focus management
    [void] Focus() {
        if (-not $this.CanFocus -or $this.HasFocus) { 
            return 
        }
        
        $this.HasFocus = $true
        
        if ($this.OnFocus) {
            & $this.OnFocus $this
        }
        
        $this.Invalidate()
    }
    
    [void] Blur() {
        if (-not $this.HasFocus) { 
            return 
        }
        
        $this.HasFocus = $false
        
        if ($this.OnBlur) {
            & $this.OnBlur $this
        }
        
        $this.Invalidate()
    }
    
    # Input handling
    [bool] HandleKeyPress([System.ConsoleKeyInfo]$keyInfo) {
        [Guard]::NotNull($keyInfo, "keyInfo")
        
        # Let focused children handle first
        foreach ($child in $this.Children) {
            if ($child.HasFocus -and $child.HandleKeyPress($keyInfo)) {
                return $true
            }
        }
        
        # Handle ourselves
        if ($this.HasFocus -and $this.OnKeyPress) {
            $result = & $this.OnKeyPress $this $keyInfo
            if ($result) {
                return $true
            }
        }
        
        return $false
    }
    
    # Helper methods for rendering
    hidden [void] WriteAt([int]$x, [int]$y, [string]$text) {
        if ($null -eq $this._renderEngine) { return }
        $this._renderEngine.WriteAt($this.X + $x, $this.Y + $y, $text)
    }
    
    # Get pre-computed position string (Praxis optimization)
    hidden [string] GetCachedPosition() {
        if (-not $this._cachedPosition) {
            $this._cachedPosition = [InternalVT100]::MoveTo($this.X, $this.Y)
        }
        return $this._cachedPosition
    }
    
    hidden [void] DrawBox([int]$x, [int]$y, [int]$width, [int]$height) {
        if ($null -eq $this._renderEngine) { return }
        $this._renderEngine.DrawBox($this.X + $x, $this.Y + $y, $width, $height)
    }
    
    hidden [void] DrawBox([int]$x, [int]$y, [int]$width, [int]$height, [string]$style) {
        if ($null -eq $this._renderEngine) { return }
        $this._renderEngine.DrawBox($this.X + $x, $this.Y + $y, $width, $height, $style)
    }
    
    # Utility methods
    [Component] FindById([string]$id) {
        [Guard]::NotNullOrEmpty($id, "id")
        
        if ($this.Id -eq $id) { 
            return $this 
        }
        
        foreach ($child in $this.Children) {
            $found = $child.FindById($id)
            if ($null -ne $found) { 
                return $found 
            }
        }
        
        return $null
    }
    
    [List[Component]] GetFocusableComponents() {
        $focusable = [List[Component]]::new()
        
        if ($this.CanFocus -and $this.Visible) {
            $focusable.Add($this)
        }
        
        foreach ($child in $this.Children) {
            $childFocusable = $child.GetFocusableComponents()
            $focusable.AddRange($childFocusable)
        }
        
        return $focusable
    }
    
    # Get current theme name for debugging
    [string] GetThemeName() {
        return $this._themeName
    }
    
    # Get current color role for debugging
    [string] GetCurrentColor() {
        return $this._currentColor
    }
}

# === Layout Helper Functions ===

<#
.SYNOPSIS
Arrange components vertically with automatic spacing

.PARAMETER Components
Array of components to arrange

.PARAMETER StartX
Starting X position

.PARAMETER StartY
Starting Y position

.PARAMETER Spacing
Space between components

.EXAMPLE
@($button1, $button2, $button3) | Arrange-Vertically -StartX 10 -StartY 5 -Spacing 2
#>
function Arrange-Vertically {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [Component[]]$Components,
        [int]$StartX = 0,
        [int]$StartY = 0,
        [int]$Spacing = 1
    )
    
    begin {
        $allComponents = @()
    }
    
    process {
        $allComponents += $Components
    }
    
    end {
        $currentY = $StartY
        
        foreach ($component in $allComponents) {
            $component.SetPosition($StartX, $currentY)
            $currentY += $component.Height + $Spacing
        }
    }
}

<#
.SYNOPSIS
Arrange components horizontally with automatic spacing

.PARAMETER Components
Array of components to arrange

.PARAMETER StartX
Starting X position

.PARAMETER StartY
Starting Y position

.PARAMETER Spacing
Space between components

.EXAMPLE
@($label1, $label2, $label3) | Arrange-Horizontally -StartX 5 -StartY 10 -Spacing 3
#>
function Arrange-Horizontally {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [Component[]]$Components,
        [int]$StartX = 0,
        [int]$StartY = 0,
        [int]$Spacing = 1
    )
    
    begin {
        $allComponents = @()
    }
    
    process {
        $allComponents += $Components
    }
    
    end {
        $currentX = $StartX
        
        foreach ($component in $allComponents) {
            $component.SetPosition($currentX, $StartY)
            $currentX += $component.Width + $Spacing
        }
    }
}

# Helper functions are available when this file is dot-sourced