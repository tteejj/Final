# SpeedTUI Simplified Render Engine - Direct console output with Praxis-style performance
# This replaces the complex RenderEngine with a simpler, faster approach

using namespace System.Text
using namespace System.Collections.Generic

<#
.SYNOPSIS
Simplified render engine that combines SpeedTUI ease with Praxis performance

.DESCRIPTION
This render engine:
- Uses direct console output (no complex region tracking)
- Implements frame-based rendering with double buffering
- Provides simple APIs for components
- Optimizes with string caching and pooling
- Minimizes allocations and overhead

.EXAMPLE
$engine = [SimplifiedRenderEngine]::new()
$engine.Initialize()
$engine.BeginFrame()
$engine.Write($component.Render())
$engine.EndFrame()
#>
class SimplifiedRenderEngine {
    # Core properties
    hidden [StringBuilder]$_currentFrame      # Current frame being built
    hidden [string]$_lastFrame = ""          # Previous frame for comparison
    hidden [bool]$_initialized = $false      # Initialization state
    hidden [object]$_logger                  # Logger for debugging
    
    # Performance tracking
    hidden [int]$_frameCount = 0             # Total frames rendered
    hidden [double]$_totalRenderTime = 0     # Total time spent rendering
    hidden [System.Diagnostics.Stopwatch]$_frameTimer
    
    # Screen dimensions
    [int]$Width
    [int]$Height
    
    <#
    .SYNOPSIS
    Initialize the simplified render engine
    #>
    SimplifiedRenderEngine() {
        $this._logger = Get-Logger
        $this._frameTimer = [System.Diagnostics.Stopwatch]::new()
        
        # Get console dimensions
        $this.UpdateDimensions()
        
        # Engine created
    }
    
    <#
    .SYNOPSIS
    Initialize the render engine for use
    #>
    [void] Initialize() {
        if ($this._initialized) { return }
        
        # Initializing render engine
        
        # Clear screen and hide cursor
        [Console]::Clear()
        [Console]::CursorVisible = $false
        [Console]::SetCursorPosition(0, 0)
        
        # Initialize string cache
        [InternalStringCache]::Initialize()
        
        $this._initialized = $true
        
        # Render engine initialized
    }
    
    <#
    .SYNOPSIS
    Cleanup and restore console state
    #>
    [void] Cleanup() {
        # Cleaning up render engine
        
        # Restore cursor
        [Console]::CursorVisible = $true
        [Console]::Clear()
        
        # Log performance stats
        if ($this._frameCount -gt 0) {
            $avgRenderTime = $this._totalRenderTime / $this._frameCount
            # Final performance stats logged
        }
    }
    
    <#
    .SYNOPSIS
    Update screen dimensions
    #>
    [void] UpdateDimensions() {
        try {
            $this.Width = [Console]::WindowWidth
            $this.Height = [Console]::WindowHeight
        } catch {
            # Fallback dimensions
            $this.Width = 80
            $this.Height = 24
        }
    }
    
    <#
    .SYNOPSIS
    Begin a new frame
    #>
    [void] BeginFrame() {
        $this._frameTimer.Restart()
        
        # Get a pooled StringBuilder for the frame
        $this._currentFrame = Get-PooledStringBuilder 4096
        
        # Don't clear here - let EndFrame decide based on content changes
    }
    
    <#
    .SYNOPSIS
    Write content to the current frame
    
    .PARAMETER content
    String content to write (should include positioning)
    #>
    [void] Write([string]$content) {
        if ($null -eq $this._currentFrame) {
            throw "BeginFrame must be called before Write"
        }
        
        if (-not [string]::IsNullOrEmpty($content)) {
            $this._currentFrame.Append($content)
        }
    }
    
    <#
    .SYNOPSIS
    Write content at specific position
    
    .PARAMETER x
    X coordinate
    
    .PARAMETER y
    Y coordinate
    
    .PARAMETER content
    Content to write
    #>
    [void] WriteAt([int]$x, [int]$y, [string]$content) {
        if ($null -eq $this._currentFrame) {
            throw "BeginFrame must be called before WriteAt"
        }
        
        if (-not [string]::IsNullOrEmpty($content)) {
            $this._currentFrame.Append([InternalVT100]::MoveTo($x, $y))
            $this._currentFrame.Append($content)
        }
    }
    
    <#
    .SYNOPSIS
    End the current frame and render to console
    #>
    [void] EndFrame() {
        if ($null -eq $this._currentFrame) {
            throw "BeginFrame must be called before EndFrame"
        }
        
        # Get the complete frame
        $currentFrameContent = $this._currentFrame.ToString()
        
        # Only render if content changed (Praxis optimization)
        if ($currentFrameContent -ne $this._lastFrame) {
            # For significant changes, clear and redraw
            if ($this._lastFrame.Length -eq 0 -or 
                [Math]::Abs($currentFrameContent.Length - $this._lastFrame.Length) -gt 100) {
                # Major change - clear screen first
                [Console]::Write([InternalVT100]::Clear())
                [Console]::Write([InternalVT100]::MoveTo(0, 0))
            }
            
            # Write the new content
            [Console]::Write($currentFrameContent)
            $this._lastFrame = $currentFrameContent
        }
        
        # Return StringBuilder to pool
        Return-PooledStringBuilder $this._currentFrame
        $this._currentFrame = $null
        
        # Track performance
        $this._frameTimer.Stop()
        $frameTime = $this._frameTimer.Elapsed.TotalMilliseconds
        $this._frameCount++
        $this._totalRenderTime += $frameTime
        
        # Performance tracking disabled for speed
    }
    
    <#
    .SYNOPSIS
    Clear a rectangular area
    
    .PARAMETER x
    Starting X coordinate
    
    .PARAMETER y
    Starting Y coordinate
    
    .PARAMETER width
    Width to clear
    
    .PARAMETER height
    Height to clear
    #>
    [void] Clear([int]$x, [int]$y, [int]$width, [int]$height) {
        if ($null -eq $this._currentFrame) {
            throw "Clear can only be called between BeginFrame and EndFrame"
        }
        
        $spaces = [InternalStringCache]::GetSpaces($width)
        
        for ($row = 0; $row -lt $height; $row++) {
            $this._currentFrame.Append([InternalVT100]::MoveTo($x, $y + $row))
            $this._currentFrame.Append($spaces)
        }
    }
    
    <#
    .SYNOPSIS
    Draw a box at the specified location
    
    .PARAMETER x
    X coordinate
    
    .PARAMETER y
    Y coordinate
    
    .PARAMETER width
    Box width
    
    .PARAMETER height
    Box height
    
    .PARAMETER style
    Box style (Single, Double, Rounded)
    #>
    [void] DrawBox([int]$x, [int]$y, [int]$width, [int]$height, [string]$style = "Single") {
        if ($null -eq $this._currentFrame) {
            throw "DrawBox can only be called between BeginFrame and EndFrame"
        }
        
        if ($width -lt 2 -or $height -lt 2) { return }
        
        # Get box characters
        $chars = switch ($style) {
            "Double" { @{
                TL = "╔"; TR = "╗"; BL = "╚"; BR = "╝"
                H = "═"; V = "║"
            }}
            "Rounded" { @{
                TL = "╭"; TR = "╮"; BL = "╰"; BR = "╯"
                H = "─"; V = "│"
            }}
            default { @{
                TL = "┌"; TR = "┐"; BL = "└"; BR = "┘"
                H = "─"; V = "│"
            }}
        }
        
        # Top border
        $this.WriteAt($x, $y, $chars.TL + ($chars.H * ($width - 2)) + $chars.TR)
        
        # Side borders
        for ($row = 1; $row -lt $height - 1; $row++) {
            $this.WriteAt($x, $y + $row, $chars.V)
            $this.WriteAt($x + $width - 1, $y + $row, $chars.V)
        }
        
        # Bottom border
        $this.WriteAt($x, $y + $height - 1, $chars.BL + ($chars.H * ($width - 2)) + $chars.BR)
    }
    
    <#
    .SYNOPSIS
    Get current FPS
    
    .OUTPUTS
    Current frames per second
    #>
    [double] GetFPS() {
        if ($this._frameCount -eq 0) { return 0 }
        $avgTime = $this._totalRenderTime / $this._frameCount
        return 1000.0 / $avgTime
    }
    
    <#
    .SYNOPSIS
    Get performance statistics
    
    .OUTPUTS
    Hashtable with performance metrics
    #>
    [hashtable] GetPerformanceStats() {
        $avgTime = $(if ($this._frameCount -gt 0) { 
            $this._totalRenderTime / $this._frameCount 
        } else { 0 })
        
        return @{
            FrameCount = $this._frameCount
            TotalRenderTime = [Math]::Round($this._totalRenderTime, 2)
            AverageFrameMs = [Math]::Round($avgTime, 2)
            CurrentFPS = [Math]::Round($this.GetFPS(), 1)
            Width = $this.Width
            Height = $this.Height
        }
    }
}

<#
.SYNOPSIS
Global helper to get the simplified render engine

.OUTPUTS
SimplifiedRenderEngine instance

.EXAMPLE
$engine = Get-RenderEngine
$engine.BeginFrame()
$engine.Write($content)
$engine.EndFrame()
#>
function Get-RenderEngine {
    if ($null -eq $global:SpeedTUIRenderEngine) {
        $global:SpeedTUIRenderEngine = [SimplifiedRenderEngine]::new()
    }
    return $global:SpeedTUIRenderEngine
}