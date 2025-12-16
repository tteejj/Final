# SpeedTUI Optimized Render Engine - Praxis-style performance with minimal flickering
# This replaces SimplifiedRenderEngine with better differential rendering

using namespace System.Text
using namespace System.Collections.Generic

<#
.SYNOPSIS
Optimized render engine that minimizes flickering like Praxis

.DESCRIPTION
This render engine:
- Uses absolute positioning for all content
- Only updates changed regions
- Caches rendered content aggressively
- Minimizes screen clears
- Provides flicker-free experience

.EXAMPLE
$engine = [OptimizedRenderEngine]::new()
$engine.Initialize()
$engine.BeginFrame()
$engine.WriteAt(10, 5, "Hello")
$engine.EndFrame()
#>
class OptimizedRenderEngine {
    # Core properties
    hidden [Dictionary[string, string]]$_lastContent  # Last content by position key (DEPRECATED - kept for reference)
    hidden [StringBuilder]$_currentFrame              # Current frame being built
    hidden [bool]$_initialized = $false              # Initialization state

    # Z-INDEX LAYER SYSTEM (NEW)
    hidden [int]$_currentZIndex = 0                                          # Current layer being written to
    hidden [Dictionary[string, Dictionary[int, string]]]$_layeredContent     # "x,y" -> {zIndex -> content}
    hidden [Dictionary[string, string]]$_compositedContent                   # Final composited content (for diff)

    # Screen dimensions
    [int]$Width
    [int]$Height

    # Performance tracking
    hidden [int]$_frameCount = 0
    hidden [int]$_updatedCells = 0
    hidden [int]$_layerSwitches = 0  # Track layer changes for debugging

    # DIRTY RECTANGLE OPTIMIZATION
    # Tracks the bounding box of all content written this frame to avoid scanning unchanged regions
    hidden [hashtable]$_dirtyBounds = $null

    <#
    .SYNOPSIS
    Initialize the optimized render engine
    #>
    OptimizedRenderEngine() {
        # Initialize layer system
        $this._layeredContent = [Dictionary[string, Dictionary[int, string]]]::new()
        $this._compositedContent = [Dictionary[string, string]]::new()
        $this._lastContent = [Dictionary[string, string]]::new()  # Keep for reference

        # Get console dimensions
        $this.UpdateDimensions()

        # Initialize dirty bounds (start with full screen on first frame)
        $this._ResetDirtyBounds($true)
    }
    
    <#
    .SYNOPSIS
    Initialize the render engine for use
    #>
    [void] Initialize() {
        if ($this._initialized) { return }
        
        # Clear screen once and hide cursor
        [Console]::Clear()
        [Console]::CursorVisible = $false
        [Console]::SetCursorPosition(0, 0)
        
        # Initialize string cache
        [InternalStringCache]::Initialize()

        $this._initialized = $true
    }
    
    <#
    .SYNOPSIS
    Cleanup and restore console state
    #>
    [void] Cleanup() {
        # Restore cursor
        [Console]::CursorVisible = $true
        [Console]::Clear()
        
        # Clear caches
        $this._lastContent.Clear()
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
    Begin rendering at specific z-index layer

    .PARAMETER zIndex
    Z-index for this layer (higher values render on top)

    .DESCRIPTION
    Sets the current z-index for subsequent WriteAt() calls.
    Layers are composited at EndFrame() with highest z-index winning.
    #>
    [void] BeginLayer([int]$zIndex) {
        $this._currentZIndex = $zIndex
        $this._layerSwitches++

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [LAYER] BeginLayer(zIndex=$zIndex) - Total switches: $($this._layerSwitches)"
        }
    }

    <#
    .SYNOPSIS
    End current layer (resets to z-index 0)

    .DESCRIPTION
    Optional method for clarity - resets to default layer.
    Not strictly required as BeginLayer() can be called multiple times.
    #>
    [void] EndLayer() {
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [LAYER] EndLayer() - Reset to zIndex=0"
        }
        $this._currentZIndex = 0
    }

    <#
    .SYNOPSIS
    Begin a new frame
    #>
    [void] BeginFrame() {
        if ($global:PmcTuiLogFile) {
            $compositedCount = $this._compositedContent.Count
            $layeredCount = $this._layeredContent.Count
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [RENDER] BeginFrame #$($this._frameCount + 1) - BEFORE clear: composited=$compositedCount, layered=$layeredCount"
        }

        # Clear layer data for new frame
        $this._layeredContent.Clear()
        $this._currentZIndex = 0
        $this._layerSwitches = 0

        # Get a pooled StringBuilder
        $this._currentFrame = Get-PooledStringBuilder 4096
        $this._updatedCells = 0

        # Reset dirty bounds to "nothing changed" - will grow as WriteAt calls are made
        $this._ResetDirtyBounds($false)

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [RENDER] BeginFrame: Layer data cleared, composited cache still has $($this._compositedContent.Count) entries, dirty bounds reset"
        }
    }
    
    <#
    .SYNOPSIS
    Write content at specific position (Praxis-style)
    
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

        if ([string]::IsNullOrEmpty($content)) {
            if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [LAYER] WriteAt($x,$y,zIndex=$($this._currentZIndex)) - content is null/empty, skipping"
            }
            return
        }

        # Create position key
        $key = "$x,$y"

        # Store content at current z-index layer
        if (-not $this._layeredContent.ContainsKey($key)) {
            $this._layeredContent[$key] = @{}
        }

        $this._layeredContent[$key][$this._currentZIndex] = $content

        # Update dirty bounds to include this position
        # Note: We don't know exact content width yet (ANSI codes), so we expand conservatively
        $this._UpdateDirtyBounds($x, $y)

        if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
            $preview = $(if ($content.Length -gt 50) { $content.Substring(0, 50) + "..." } else { $content })
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [LAYER] WriteAt($x,$y,zIndex=$($this._currentZIndex)) - stored content (len=$($content.Length)): $preview"
        }
    }
    
    <#
    .SYNOPSIS
    Clear a specific line
    
    .PARAMETER y
    Line number to clear
    #>
    [void] ClearLine([int]$y) {
        if ($null -eq $this._currentFrame) {
            throw "BeginFrame must be called before ClearLine"
        }
        
        $this._currentFrame.Append([InternalVT100]::MoveTo(0, $y))
        $this._currentFrame.Append([InternalStringCache]::GetAnsiSequence("clearline"))
        
        # Remove cached content for this line
        $keysToRemove = @()
        foreach ($key in $this._lastContent.Keys) {
            if ($key -match "^\d+,$y$") {
                $keysToRemove += $key
            }
        }
        foreach ($key in $keysToRemove) {
            $this._lastContent.Remove($key)
        }
    }
    
    <#
    .SYNOPSIS
    Clear terminal and invalidate render cache

    .DESCRIPTION
    CRITICAL FIX: Clears the terminal screen AND the cache. This is necessary when switching
    screens because differential rendering only writes cells that changed. If old content
    (like dropdown menus) existed at positions that the new screen doesn't write to, that
    old content remains visible even though the cache was cleared.

    The terminal clear happens BEFORE cache clear to ensure old visible content is removed,
    then the cache clear forces a full redraw of the new screen content.
    #>
    [void] RequestClear() {
        # CRITICAL: Clear terminal first to remove old visible content
        [Console]::Clear()

        # Then clear both caches - this forces everything to be redrawn
        $this._compositedContent.Clear()
        $this._layeredContent.Clear()

        # Mark entire screen as dirty for next frame
        $this._ResetDirtyBounds($true)

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [RENDER] RequestClear: Terminal cleared + caches invalidated + full screen marked dirty"
        }
    }

    <#
    .SYNOPSIS
    Invalidate cached content for a specific Y coordinate range WITHOUT clearing screen

    .PARAMETER minY
    Minimum Y coordinate to invalidate (inclusive)

    .PARAMETER maxY
    Maximum Y coordinate to invalidate (inclusive)

    .DESCRIPTION
    Removes cache entries for specified Y range, forcing those rows to be redrawn
    in the next frame. This is surgical - no screen flicker, just invalidate the cache
    so differential rendering will write those positions.

    Use this instead of RequestClear() when you know the specific region that needs updating.
    #>
    [void] InvalidateCachedRegion([int]$minY, [int]$maxY) {
        $keysToRemove = [System.Collections.Generic.List[string]]::new()

        foreach ($key in $this._compositedContent.Keys) {
            $parts = $key -split ','
            $y = [int]$parts[1]
            if ($y -ge $minY -and $y -le $maxY) {
                $keysToRemove.Add($key)
            }
        }

        $removedCount = 0
        foreach ($key in $keysToRemove) {
            $this._compositedContent.Remove($key)
            $removedCount++
        }

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [RENDER] InvalidateCachedRegion: Y=$minY-$maxY, removed $removedCount cache entries (no screen clear)"
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

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [RENDER] EndFrame: Starting - positions=$($this._layeredContent.Count) layerSwitches=$($this._layerSwitches)"
        }

        # CRITICAL: Composite all layers into final frame
        $this._CompositeLayersToFrame()

        # Write composited frame to console
        # No screen clearing needed - differential engine handles overwrites
        if ($this._updatedCells -gt 0) {
            $frameContent = $this._currentFrame.ToString()
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [RENDER] EndFrame: Writing $($this._updatedCells) updated cells, frame length=$($frameContent.Length)"
            }
            [Console]::Write($frameContent)
        } else {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [RENDER] EndFrame: No updates, skipping write"
            }
        }

        # Return StringBuilder to pool
        Return-PooledStringBuilder $this._currentFrame
        $this._currentFrame = $null

        $this._frameCount++
    }

    <#
    .SYNOPSIS
    Composite all layers into final frame (internal method)

    .DESCRIPTION
    For each position with layered content:
    1. Find the highest z-index layer
    2. Compare with last frame's content (differential rendering)
    3. Write to frame buffer if changed

    This method implements the core z-ordering logic.
    #>
    hidden [void] _CompositeLayersToFrame() {
        $positionsProcessed = 0
        $layersComposited = 0

        # DIRTY RECTANGLE OPTIMIZATION: Only process positions within dirty bounds
        # This can reduce iteration from 1000s of positions to just the changed region
        $dirtyMinX = $this._dirtyBounds.MinX
        $dirtyMaxX = $this._dirtyBounds.MaxX
        $dirtyMinY = $this._dirtyBounds.MinY
        $dirtyMaxY = $this._dirtyBounds.MaxY

        # If nothing was written this frame, skip compositing entirely
        if ($dirtyMaxX -lt 0) {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [COMPOSITE] No dirty bounds - skipping (empty frame)"
            }
            return
        }

        if ($global:PmcTuiLogFile) {
            $dirtyWidth = $dirtyMaxX - $dirtyMinX + 1
            $dirtyHeight = $dirtyMaxY - $dirtyMinY + 1
            $dirtyArea = $dirtyWidth * $dirtyHeight
            $totalArea = $this.Width * $this.Height
            $coverage = [Math]::Round(($dirtyArea / $totalArea) * 100, 1)
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [COMPOSITE] Starting layer composition - total positions=$($this._layeredContent.Count), dirty rect=($dirtyMinX,$dirtyMinY)-($dirtyMaxX,$dirtyMaxY) [$dirtyWidth x $dirtyHeight] = $coverage% of screen"
        }

        foreach ($key in $this._layeredContent.Keys) {
            # Parse position from key "x,y" to check if it's in dirty bounds
            $parts = $key -split ','
            $keyX = [int]$parts[0]
            $keyY = [int]$parts[1]

            # Skip positions outside dirty rectangle
            if ($keyX -lt $dirtyMinX -or $keyX -gt $dirtyMaxX -or $keyY -lt $dirtyMinY -or $keyY -gt $dirtyMaxY) {
                if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [COMPOSITE] Position $key OUTSIDE dirty rect, skipping"
                }
                continue
            }
            $positionsProcessed++
            $layers = $this._layeredContent[$key]

            # Find highest z-index for this position
            $maxZ = -999999
            $finalContent = $null
            $layerCount = 0

            foreach ($zIndex in $layers.Keys) {
                $layerCount++
                if ($zIndex -gt $maxZ) {
                    $maxZ = $zIndex
                    $finalContent = $layers[$zIndex]
                }
            }

            $layersComposited += $layerCount

            if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [COMPOSITE] Position $key - $layerCount layers, maxZ=$maxZ, content length=$($finalContent.Length)"
            }

            # Check if content changed from last frame (differential rendering)
            $lastValue = $null
            $hadCachedValue = $this._compositedContent.TryGetValue($key, [ref]$lastValue)

            if ($hadCachedValue -and $lastValue -eq $finalContent) {
                # No change - skip
                if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [COMPOSITE] Position $key - UNCHANGED (cached), skipping"
                }
                continue
            }

            # Content changed or new position - write to frame
            if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 2) {
                $reason = $(if ($hadCachedValue) { "CHANGED" } else { "NEW" })
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [COMPOSITE] Position $key - $reason, will write"
            }
            # Parse position from key "x,y"
            $parts = $key -split ','
            $x = [int]$parts[0]
            $y = [int]$parts[1]

            $this._currentFrame.Append([InternalVT100]::MoveTo($x, $y))

            # DEBUG: Log full content being written for row 7
            if ($global:PmcTuiLogFile -and $y -eq 7 -and $x -eq 2) {
                # Extract visible text (strip ANSI codes) for debugging
                $visibleText = $finalContent -replace '\x1b\[[0-9;]+m', ''
                $contentPreview = $(if ($finalContent.Length -gt 100) { $finalContent.Substring(0, 100) + "..." } else { $finalContent })
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [WRITE] Position $key - Writing $($finalContent.Length) chars ($($visibleText.Length) visible): $contentPreview"
            }

            $this._currentFrame.Append($finalContent)

            # Update cache for next frame's differential
            $this._compositedContent[$key] = $finalContent
            $this._updatedCells++

            if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
                $preview = $(if ($finalContent.Length -gt 50) { $finalContent.Substring(0, 50) + "..." } else { $finalContent })
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [COMPOSITE] Position $key - WRITING at ($x,$y) zIndex=$($maxZ): $preview"
            }
        }

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [COMPOSITE] Finished - positions=$positionsProcessed layers=$layersComposited updates=$($this._updatedCells)"
        }
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
            $this.WriteAt($x, $y + $row, $spaces)
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
        
        # Pre-compute horizontal line
        $hLine = $chars.H * ($width - 2)
        
        # Top border
        $this.WriteAt($x, $y, $chars.TL + $hLine + $chars.TR)
        
        # Side borders with spaces in between
        $spaces = [InternalStringCache]::GetSpaces($width - 2)
        for ($row = 1; $row -lt $height - 1; $row++) {
            $this.WriteAt($x, $y + $row, $chars.V)
            $this.WriteAt($x + 1, $y + $row, $spaces)
            $this.WriteAt($x + $width - 1, $y + $row, $chars.V)
        }
        
        # Bottom border
        $this.WriteAt($x, $y + $height - 1, $chars.BL + $hLine + $chars.BR)
    }
    
    # -------------------------------------------------------------------------
    # DIRTY RECTANGLE TRACKING (INTERNAL)
    # -------------------------------------------------------------------------

    <#
    .SYNOPSIS
    Reset dirty bounds to either full screen or empty

    .PARAMETER fullScreen
    If true, marks entire screen as dirty. If false, marks nothing as dirty (inverted bounds).
    #>
    hidden [void] _ResetDirtyBounds([bool]$fullScreen) {
        if ($fullScreen) {
            # Mark entire screen as dirty (for initial frame or after RequestClear)
            $this._dirtyBounds = @{
                MinX = 0
                MinY = 0
                MaxX = $this.Width - 1
                MaxY = $this.Height - 1
            }
        } else {
            # Start with inverted bounds that will expand as WriteAt is called
            # MinX/MinY start at max, MaxX/MaxY start at min - this ensures first WriteAt sets proper bounds
            $this._dirtyBounds = @{
                MinX = $this.Width
                MinY = $this.Height
                MaxX = -1
                MaxY = -1
            }
        }
    }

    <#
    .SYNOPSIS
    Expand dirty bounds to include a specific position

    .PARAMETER x
    X coordinate to include

    .PARAMETER y
    Y coordinate to include
    #>
    hidden [void] _UpdateDirtyBounds([int]$x, [int]$y) {
        if ($x -lt $this._dirtyBounds.MinX) { $this._dirtyBounds.MinX = $x }
        if ($x -gt $this._dirtyBounds.MaxX) { $this._dirtyBounds.MaxX = $x }
        if ($y -lt $this._dirtyBounds.MinY) { $this._dirtyBounds.MinY = $y }
        if ($y -gt $this._dirtyBounds.MaxY) { $this._dirtyBounds.MaxY = $y }
    }

    <#
    .SYNOPSIS
    Get performance statistics

    .OUTPUTS
    Hashtable with performance metrics
    #>
    [hashtable] GetPerformanceStats() {
        return @{
            FrameCount = $this._frameCount
            CachedPositions = $this._lastContent.Count
            LastUpdatedCells = $this._updatedCells
            Width = $this.Width
            Height = $this.Height
            DirtyBounds = $this._dirtyBounds
        }
    }
}