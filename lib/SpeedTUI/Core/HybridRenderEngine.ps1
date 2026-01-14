# SpeedTUI Hybrid Render Engine
# "The Best of Both Worlds" - Combines Cell-based precision with Layer-based flexibility.
#
# ARCHITECTURAL OVERVIEW:
# -----------------------
# This engine represents the evolution of the SpeedTUI rendering pipeline. It merges the
# robustness of the OptimizedRenderEngine (Z-Layers, Compatibility) with the high-performance
# architecture of the EnhancedRenderEngine (Cell Buffers, Smart Diffing).
#
# KEY FEATURES:
# 1. CELL-BASED RENDERING: Uses a grid of Cell objects (Char, Color, Attributes) instead of
#    strings. This prevents text bleeding and allows precise merging of layers.
# 2. Z-BUFFERING: Supports overlapping layers (popups over backgrounds) natively.
#    Uses a Depth Buffer to determine which pixel wins at any given coordinate.
# 3. VIEWPORT CLIPPING: Prevents UI components from drawing outside their bounds.
#    Essential for scrollable lists and complex layouts.
# 4. DIRTY RECTANGLE TRACKING: Only processes screen areas that actually changed,
#    massively improving performance for small updates (like progress bars).
# 5. OBJECT POOLING: reuses StringBuilder objects to minimize memory allocation pressure.
#
# USAGE:
# $engine = [HybridRenderEngine]::new()
# $engine.Initialize()
# $engine.BeginFrame()
# $engine.BeginLayer(10) # Draw on top
# $engine.WriteAt(0,0, "Popup")
# $engine.EndFrame()

using namespace System.Text
using namespace System.Collections.Generic

# Ensure dependencies are loaded (CellBuffer, PerformanceCore)
# These usually come from the module loader, but we depend on them here.

class LayoutRegion {
    [string]$ID
    [int]$X
    [int]$Y
    [int]$Width
    [int]$Height
    [int]$ZIndex
    [string]$ParentID
    [bool]$Clip

    LayoutRegion([string]$id, [int]$x, [int]$y, [int]$width, [int]$height) {
        $this.ID = $id
        $this.X = $x
        $this.Y = $y
        $this.Width = $width
        $this.Height = $height
        $this.ZIndex = 0
        $this.ParentID = ""
        $this.Clip = $true
    }
}

class HybridRenderEngine {
    # -- CORE BUFFERS --
    # FrontBuffer: Represents exactly what is currently visible on the user's screen.
    hidden [object]$_frontBuffer  # NativeCellBuffer or CellBuffer
    # BackBuffer: The "Canvas" we are currently painting on for the next frame.
    hidden [object]$_backBuffer   # NativeCellBuffer or CellBuffer
    # ZBuffer: Stores the depth (layer index) of each cell. Used to decide if a new
    # write should overwrite existing content or appear behind it.
    hidden [int[][]] $_zBuffer

    # -- STATE MANAGEMENT --
    hidden [bool]$_initialized = $false
    hidden [bool]$_inFrame = $false
    
    # -- RENDERING CONTEXT --
    # Current Z-Index (Depth). Higher numbers appear on top.
    hidden [int]$_currentZ = 0
    # Clipping Stack: Stores active viewports. Content outside the top rect is discarded.
    hidden [Stack[object]]$_clipStack
    # Offset Stack: Stores coordinate translations. (0,0) becomes (OffsetX, OffsetY).
    hidden [Stack[object]]$_offsetStack
    # Dirty Bounds: Tracks the min/max X/Y coordinates that have been touched this frame.
    # Used to optimize the Diffing phase (don't scan the whole screen if only one line changed).
    hidden [object]$_dirtyBounds
    # Cursor Logic: Where the cursor *should* be after rendering.
    hidden [int]$_cursorX = -1
    hidden [int]$_cursorY = -1

    # -- DIMENSIONS --
    [int]$Width
    [int]$Height

    # -- PERFORMANCE TRACKING --
    hidden [int]$_frameCount = 0
    hidden [int]$_cellsUpdated = 0

    # -- CACHING --
    static hidden [hashtable]$_ansiCache = @{}

    # -- LAYOUT SYSTEM --
    hidden [hashtable]$_regions = @{}

    HybridRenderEngine() {
        $this._clipStack = [Stack[object]]::new()
        $this._offsetStack = [Stack[object]]::new()
        $this.UpdateDimensions()
        $this._InitializeBuffers()
    }

    # -------------------------------------------------------------------------
    # LIFECYCLE METHODS
    # -------------------------------------------------------------------------

    [void] Initialize() {
        if ($this._initialized) { return }

        # Prepare the terminal
        [Console]::Clear()
        [Console]::CursorVisible = $false
        [Console]::SetCursorPosition(0, 0)
        
        # Ensure internal performance caches are ready
        # (InternalStringCache/InternalVT100 from PerformanceCore.ps1)
        if (-not [InternalStringCache]::_initialized) {
            [InternalStringCache]::Initialize()
        }

        $this._initialized = $true
    }

    [void] Cleanup() {
        [Console]::CursorVisible = $true
        [Console]::Clear()
        $this._initialized = $false
    }

    [void] UpdateDimensions() {
        try {
            $newWidth = [Console]::WindowWidth
            $newHeight = [Console]::WindowHeight
            
            # Only resize if actually changed to avoid overhead
            if ($this.Width -ne $newWidth -or $this.Height -ne $newHeight) {
                $this.Width = $newWidth
                $this.Height = $newHeight
                $this._InitializeBuffers()
            }
        }
        catch {
            # Safe fallbacks if running in non-interactive environment
            $this.Width = 80
            $this.Height = 24
            $this._InitializeBuffers()
        }
    }

    hidden [void] _InitializeBuffers() {
        # Re-allocate all buffers to match new dimensions
        # Use C# NativeCellBuffer for ~50-100x speedup (if loaded)
        $nativeType = ([System.Management.Automation.PSTypeName]'NativeCellBuffer').Type
        if ($nativeType) {
            $this._frontBuffer = $nativeType::new($this.Width, $this.Height)
            $this._backBuffer = $nativeType::new($this.Width, $this.Height)
        } else {
            $this._frontBuffer = [CellBuffer]::new($this.Width, $this.Height)
            $this._backBuffer = [CellBuffer]::new($this.Width, $this.Height)
        }
        
        # Z-Buffer is a primitive int array for speed
        $this._zBuffer = [int[][]]::new($this.Height)
        for ($y = 0; $y -lt $this.Height; $y++) {
            $this._zBuffer[$y] = [int[]]::new($this.Width)
        }
        
        # Reset Dirty Bounds to full screen initially
        $this._ResetDirtyBounds($true)
    }

    # -------------------------------------------------------------------------
    # FRAME MANAGEMENT
    # -------------------------------------------------------------------------

    [void] BeginFrame() {
        if (-not $this._initialized) { throw "Engine not initialized" }
        
        $this._inFrame = $true
        $this._currentZ = 0
        $this._cellsUpdated = 0
        
        # Reset BackBuffer (Clear text/colors)
        # Note: We don't allocate new memory, just reset values.
        $this._backBuffer.Clear()

        # Reset Z-Buffer to lowest possible value so Layer 0 can write
        $minInt = [int]::MinValue
        for ($y = 0; $y -lt $this.Height; $y++) {
            # Array.Fill is faster than loop
            # Check if PowerShell version supports it, otherwise loop
            for ($x = 0; $x -lt $this.Width; $x++) {
                $this._zBuffer[$y][$x] = $minInt
            }
        }
        
        # Reset Render State
        $this._clipStack.Clear()
        $this._offsetStack.Clear()
        $this._ResetDirtyBounds($false) # Start with "nothing changed"
    }

    [void] EndFrame() {
        if (-not $this._inFrame) { return }

        # THE MAGIC HAPPENS HERE:
        # Compare BackBuffer vs FrontBuffer and emit minimal ANSI.
        # We assume _dirtyBounds contains the area that might have changed.
        
        $diff = $this._BuildOptimizedDiff()
        
        if ($diff.Length -gt 0) {
            [Console]::Write($diff)
        }

        # Apply Logical Cursor Position (if set)
        if ($this._cursorX -ge 0 -and $this._cursorY -ge 0) {
            [Console]::SetCursorPosition($this._cursorX, $this._cursorY)
        }

        # Swap Buffers: BackBuffer becomes the new FrontBuffer
        # We use CopyFrom because swapping references breaks if we hold references elsewhere,
        # but for this engine, swapping content is safer.
        $this._frontBuffer.CopyFrom($this._backBuffer)

        $this._frameCount++
        $this._inFrame = $false
    }

    # -------------------------------------------------------------------------
    # Z-LAYER & CLIPPING API
    # -------------------------------------------------------------------------

    # Sets the current drawing layer. Higher Z = On Top.
    [void] BeginLayer([int]$zIndex) {
        $this._currentZ = $zIndex
    }

    [void] EndLayer() {
        $this._currentZ = 0
    }

    # Restricts rendering to a specific rectangle. Useful for scrolling lists.
    [void] PushClip([int]$x, [int]$y, [int]$width, [int]$height) {
        # Calculate intersection with current clip (if any)
        $newClip = @{ X = $x; Y = $y; R = ($x + $width); B = ($y + $height) }

        if ($this._clipStack.Count -gt 0) {
            $parent = $this._clipStack.Peek()
            $newClip.X = [Math]::Max($newClip.X, $parent.X)
            $newClip.Y = [Math]::Max($newClip.Y, $parent.Y)
            $newClip.R = [Math]::Min($newClip.R, $parent.R)
            $newClip.B = [Math]::Min($newClip.B, $parent.B)
        }
        
        $this._clipStack.Push($newClip)
    }

    [void] PopClip() {
        if ($this._clipStack.Count -gt 0) {
            [void]$this._clipStack.Pop()
        }
    }

    # Translates the coordinate system.
    # PushOffset(10, 5) means WriteAt(0,0) will actually draw at Screen(10,5).
    # Useful for reusable components that draw relative to their container.
    [void] PushOffset([int]$x, [int]$y) {
        $current = @{ X = 0; Y = 0 }
        if ($this._offsetStack.Count -gt 0) {
            $current = $this._offsetStack.Peek()
        }
        
        $newOffset = @{ 
            X = $current.X + $x
            Y = $current.Y + $y
        }
        
        $this._offsetStack.Push($newOffset)
    }

    [void] PopOffset() {
        if ($this._offsetStack.Count -gt 0) {
            [void]$this._offsetStack.Pop()
        }
    }

    # Sets where the hardware cursor should be placed at the end of the frame.
    # Use -1, -1 to hide it (or leave it where drawing ended).
    [void] SetCursor([int]$x, [int]$y) {
        # Apply current offset to cursor position if needed?
        # Typically cursor is set in local coordinates too.
        $offsetX = 0
        $offsetY = 0
        if ($this._offsetStack.Count -gt 0) {
            $current = $this._offsetStack.Peek()
            $offsetX = $current.X
            $offsetY = $current.Y
        }

        $this._cursorX = $x + $offsetX
        $this._cursorY = $y + $offsetY
    }

    # Shows the hardware cursor (makes it visible on screen)
    [void] ShowCursor() {
        [Console]::CursorVisible = $true
    }

    # Hides the hardware cursor (makes it invisible)
    [void] HideCursor() {
        [Console]::CursorVisible = $false
    }


    # -------------------------------------------------------------------------
    # DRAWING API
    # -------------------------------------------------------------------------

    [void] WriteAt([int]$x, [int]$y, [string]$content) {
        if (-not $this._inFrame -or [string]::IsNullOrEmpty($content)) { return }

        # Apply Offset (Coordinate Translation)
        $offsetX = 0
        $offsetY = 0
        if ($this._offsetStack.Count -gt 0) {
            $current = $this._offsetStack.Peek()
            $offsetX = $current.X
            $offsetY = $current.Y
        }
        
        $finalX = $x + $offsetX
        $finalY = $y + $offsetY

        # 1. Parse ANSI content (Extract text + attributes)
        # We reuse the logic style from EnhancedRenderEngine for parsing
        # (This is simplified for brevity - assumes logic similar to Enhanced)
        
        # State tracking for the string
        $currentFg = -1
        $currentBg = -1
        $currentAttr = 0
        
        $currentX = $finalX
        $len = $content.Length
        $i = 0
        
        # Check current clip bounds
        $clip = $null
        if ($this._clipStack.Count -gt 0) { $clip = $this._clipStack.Peek() }

        while ($i -lt $len) {
            # Check for ANSI escape sequence start
            if ($content[$i] -eq "`e" -and ($i + 1) -lt $len -and $content[$i + 1] -eq '[') {
                # -- ANSI PARSING BLOCK --
                # (Ideally abstracted, but inline here for performance/portability)
                $seqEnd = $i + 2
                while ($seqEnd -lt $len -and $content[$seqEnd] -match '[0-9;]') { $seqEnd++ }
                
                if ($seqEnd -lt $len) {
                    $cmd = $content[$seqEnd]
                    $paramStr = $content.Substring($i + 2, $seqEnd - ($i + 2))
                    
                    # Update current color/attr state based on params
                    # (Simplified logic: Calls a helper to update state vars)
                    $this._ParseAnsiState($cmd, $paramStr, [ref]$currentFg, [ref]$currentBg, [ref]$currentAttr)
                    
                    $i = $seqEnd + 1
                    continue
                }
            }
            
            # Normal Character Processing
            # 1. Check Bounds (Screen)
            if ($finalY -ge 0 -and $finalY -lt $this.Height -and $currentX -ge 0 -and $currentX -lt $this.Width) {
                
                # 2. Check Clipping (Viewport)
                $isClipped = $false
                if ($clip) {
                    if ($currentX -lt $clip.X -or $currentX -ge $clip.R -or $finalY -lt $clip.Y -or $finalY -ge $clip.B) {
                        $isClipped = $true
                    }
                }

                # 3. Check Z-Index (Depth)
                if (-not $isClipped) {
                    if ($this._currentZ -ge $this._zBuffer[$finalY][$currentX]) {
                        # ** WRITE IS ALLOWED **
                        
                        # Update Back Buffer
                        $this._backBuffer.SetCell($currentX, $finalY, $content[$i], $currentFg, $currentBg, $currentAttr)
                        
                        # Update Z Buffer
                        $this._zBuffer[$finalY][$currentX] = $this._currentZ
                        
                        # Update Dirty Rectangle (Grow to include this point)
                        $this._UpdateDirtyBounds($currentX, $finalY)
                    } else {
                        # Z-BUFFER DEBUG: Log when a write is REJECTED in dropdown area
                        if ($finalY -ge 1 -and $finalY -le 15 -and $global:PmcTuiLogFile) {
                            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [Z-BUFFER] REJECTED at ($currentX,$finalY): currentZ=$($this._currentZ) < zBuffer=$($this._zBuffer[$finalY][$currentX]) char='$($content[$i])'"
                        }
                    }
                }
            }
            
            $currentX++
            $i++
        }
    }

    [void] WriteAt([int]$x, [int]$y, [string]$content, [int]$fg, [int]$bg) {
        if (-not $this._inFrame -or [string]::IsNullOrEmpty($content)) { return }

        # OPTIMIZATION: Use WriteRow if available (Native Speedup)
        # We need to construct arrays, but for solid colors we can pass null?
        # NativeCellBuffer.WriteRow signature: (int x, int y, string text, int[] fgs, int[] bgs, byte[] attrs, ...)
        # If we pass null arrays, NativeCellBuffer might crash or not handle it.
        # We need to check NativeRenderCore.ps1 implementation.
        # Assuming we need to fill arrays.
        
        # However, creating arrays in PowerShell might be slower than the loop for short strings.
        # But for long strings (like fills), WriteRow is much faster.
        # Threshold: 10 chars?
        
        if ($content.Length -gt 5) {
             # Construct arrays
             $len = $content.Length
             $fgs = [int[]]::new($len)
             $bgs = [int[]]::new($len)
             $attrs = [byte[]]::new($len)
             
             # Fill arrays (Array.Fill is fast)
             # PowerShell 7+ supports [Array]::Fill
             # Or loop.
             
             # Actually, if we modify NativeCellBuffer.WriteRow to accept single int for solid color, that would be best.
             # But we can't easily change C# signature without recompiling.
             # So we fill arrays.
             
             for ($i = 0; $i -lt $len; $i++) {
                 $fgs[$i] = $fg
                 $bgs[$i] = $bg
                 $attrs[$i] = 0
             }
             
             $this.WriteRow($x, $y, $content, $fgs, $bgs, $attrs)
             return
        }

        # Fallback to loop for short strings
        # Apply Offset
        $offsetX = 0
        $offsetY = 0
        if ($this._offsetStack.Count -gt 0) {
            $current = $this._offsetStack.Peek()
            $offsetX = $current.X
            $offsetY = $current.Y
        }
        
        $finalX = $x + $offsetX
        $finalY = $y + $offsetY
        $currentX = $finalX
        
        # Check current clip bounds
        $clip = $null
        if ($this._clipStack.Count -gt 0) { $clip = $this._clipStack.Peek() }

        $len = $content.Length
        for ($i = 0; $i -lt $len; $i++) {
            # Check Bounds
            if ($finalY -ge 0 -and $finalY -lt $this.Height -and $currentX -ge 0 -and $currentX -lt $this.Width) {
                
                # Check Clipping
                $isClipped = $false
                if ($clip) {
                    if ($currentX -lt $clip.X -or $currentX -ge $clip.R -or $finalY -lt $clip.Y -or $finalY -ge $clip.B) {
                        $isClipped = $true
                    }
                }

                # Check Z-Index
                if (-not $isClipped) {
                    if ($this._currentZ -ge $this._zBuffer[$finalY][$currentX]) {
                        # Write
                        $this._backBuffer.SetCell($currentX, $finalY, $content[$i], $fg, $bg, 0)
                        $this._zBuffer[$finalY][$currentX] = $this._currentZ
                        $this._UpdateDirtyBounds($currentX, $finalY)
                    } else {
                        # Z-BUFFER DEBUG: Log when a write is REJECTED in dropdown area
                        if ($finalY -ge 1 -and $finalY -le 15 -and $global:PmcTuiLogFile) {
                            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [Z-BUFFER] REJECTED at ($currentX,$finalY): currentZ=$($this._currentZ) < zBuffer=$($this._zBuffer[$finalY][$currentX]) char='$($content[$i])'"
                        }
                    }
                }
            }
            $currentX++
        }
    }

    # Gradient WriteAt: Interpolates foreground color per character from fgStart to fgEnd
    [void] WriteAt([int]$x, [int]$y, [string]$content, [int]$fgStart, [int]$fgEnd, [int]$bg) {
        if (-not $this._inFrame -or [string]::IsNullOrEmpty($content)) { return }

        # Apply Offset
        $offsetX = 0
        $offsetY = 0
        if ($this._offsetStack.Count -gt 0) {
            $current = $this._offsetStack.Peek()
            $offsetX = $current.X
            $offsetY = $current.Y
        }
        
        $finalX = $x + $offsetX
        $finalY = $y + $offsetY
        $currentX = $finalX
        
        # Check current clip bounds
        $clip = $null
        if ($this._clipStack.Count -gt 0) { $clip = $this._clipStack.Peek() }

        $len = $content.Length
        for ($i = 0; $i -lt $len; $i++) {
            # Calculate interpolation factor
            $t = if ($len -eq 1) { 0.0 } else { [double]$i / ($len - 1) }
            $fg = $this._LerpColor($fgStart, $fgEnd, $t)
            
            # Check Bounds
            if ($finalY -ge 0 -and $finalY -lt $this.Height -and $currentX -ge 0 -and $currentX -lt $this.Width) {
                
                # Check Clipping
                $isClipped = $false
                if ($clip) {
                    if ($currentX -lt $clip.X -or $currentX -ge $clip.R -or $finalY -lt $clip.Y -or $finalY -ge $clip.B) {
                        $isClipped = $true
                    }
                }

                # Check Z-Index
                if (-not $isClipped) {
                    if ($this._currentZ -ge $this._zBuffer[$finalY][$currentX]) {
                        # Write with interpolated color
                        $this._backBuffer.SetCell($currentX, $finalY, $content[$i], $fg, $bg, 0)
                        $this._zBuffer[$finalY][$currentX] = $this._currentZ
                        $this._UpdateDirtyBounds($currentX, $finalY)
                    }
                }
            }
            $currentX++
        }
    }

    # Bulk Row Write - Optimized for UniversalList
    [void] WriteRow([int]$x, [int]$y, [string]$text, [int[]]$fgs, [int[]]$bgs, [byte[]]$attrs) {
        if (-not $this._inFrame -or [string]::IsNullOrEmpty($text)) { return }

        # Apply Offset
        $offsetX = 0; $offsetY = 0
        if ($this._offsetStack.Count -gt 0) {
            $current = $this._offsetStack.Peek()
            $offsetX = $current.X; $offsetY = $current.Y
        }
        $finalX = $x + $offsetX
        $finalY = $y + $offsetY

        if ($finalY -lt 0 -or $finalY -ge $this.Height) { return }

        # Calculate Clip
        $minX = 0; $maxX = $this.Width
        if ($this._clipStack.Count -gt 0) {
            $clip = $this._clipStack.Peek()
            if ($finalY -lt $clip.Y -or $finalY -ge $clip.B) { return } # Row outside clip Y
            $minX = [Math]::Max(0, $clip.X)
            $maxX = [Math]::Min($this.Width, $clip.R)
        }

        # Native Path
        if ($this._backBuffer.GetType().Name -eq 'NativeCellBuffer') {
            # CRITICAL FIX: Check Z-Buffer before bulk write
            # NativeCellBuffer.WriteRow blindly overwrites. We must ensure we are on top.
            
            $len = $text.Length
            $startX = [Math]::Max($finalX, $minX)
            $endX = [Math]::Min($finalX + $len, $maxX)
            
            if ($startX -lt $endX) {
                $zRow = $this._zBuffer[$finalY]
                $z = $this._currentZ
                $isOccluded = $false
                
                # Check for occlusion
                for ($cx = $startX; $cx -lt $endX; $cx++) {
                    if ($z -lt $zRow[$cx]) {
                        $isOccluded = $true
                        break
                    }
                }
                
                if (-not $isOccluded) {
                    # Safe to bulk write
                    $this._backBuffer.WriteRow($finalX, $finalY, $text, $fgs, $bgs, $attrs, $minX, $maxX)
                    
                    # Bulk update Z-buffer
                    for ($cx = $startX; $cx -lt $endX; $cx++) {
                        $zRow[$cx] = $z
                    }
                    $this._UpdateDirtyBounds($startX, $finalY)
                    $this._UpdateDirtyBounds($endX - 1, $finalY)
                    return
                }
            }
        }
        
        # Fallback Path (Loop) - Used if occluded or not using NativeBuffer
            $len = $text.Length
            $currentX = $finalX
            
            for ($i = 0; $i -lt $len; $i++) {
                if ($currentX -ge $minX -and $currentX -lt $maxX) {
                    if ($this._currentZ -ge $this._zBuffer[$finalY][$currentX]) {
                        $fg = if ($fgs -and $i -lt $fgs.Length) { $fgs[$i] } else { -1 }
                        $bg = if ($bgs -and $i -lt $bgs.Length) { $bgs[$i] } else { -1 }
                        $at = if ($attrs -and $i -lt $attrs.Length) { $attrs[$i] } else { 0 }
                        
                        $this._backBuffer.SetCell($currentX, $finalY, $text[$i], $fg, $bg, $at)
                        $this._zBuffer[$finalY][$currentX] = $this._currentZ
                        $this._UpdateDirtyBounds($currentX, $finalY)
                    }
                }
                $currentX++
            }
    }

    # Linear interpolation between two packed RGB colors
    hidden [int] _LerpColor([int]$c1, [int]$c2, [double]$t) {
        # Extract RGB components
        $r1 = ($c1 -shr 16) -band 0xFF
        $g1 = ($c1 -shr 8) -band 0xFF
        $b1 = $c1 -band 0xFF
        $r2 = ($c2 -shr 16) -band 0xFF
        $g2 = ($c2 -shr 8) -band 0xFF
        $b2 = $c2 -band 0xFF
        
        # Interpolate
        $r = [int]($r1 + ($r2 - $r1) * $t)
        $g = [int]($g1 + ($g2 - $g1) * $t)
        $b = [int]($b1 + ($b2 - $b1) * $t)
        
        # Pack and return
        return ($r -shl 16) -bor ($g -shl 8) -bor $b
    }

    [void] Clear([int]$x, [int]$y, [int]$width, [int]$height) {
        # Helper to clear area using spaces
        # We construct a string of spaces and use WriteAt so Z-Index/Clipping applies automatically
        $spaces = " " * $width # (In prod: use InternalStringCache::GetSpaces($width))
        for ($r = 0; $r -lt $height; $r++) {
            $this.WriteAt($x, $y + $r, $spaces)
        }
    }

    [void] Fill([int]$x, [int]$y, [int]$width, [int]$height, [string]$char, [int]$fg, [int]$bg) {
        if ($width -le 0 -or $height -le 0) { return }
        if ([string]::IsNullOrEmpty($char)) { $char = " " }
        
        # Create the fill string once
        # If char is multi-character, we take the first char
        $fillChar = $char[0]
        $line = [string]$fillChar * $width
        
        for ($r = 0; $r -lt $height; $r++) {
            $this.WriteAt($x, $y + $r, $line, $fg, $bg)
        }
    }

    [void] RequestClear() {
        # Force full redraw on next frame
        $this.InvalidateCachedRegion(0, $this.Height - 1)
        # Also clear the terminal immediately to prevent artifacts during transition
        [Console]::Clear()
    }

    [void] DrawBox([int]$x, [int]$y, [int]$width, [int]$height, [int]$fg, [int]$bg) {
        # Overload 2: Colors only (Default Style) - This fixes the 6-arg call
        $this.DrawBox($x, $y, $width, $height, $fg, $bg, "Single")
    }

    [void] DrawBox([int]$x, [int]$y, [int]$width, [int]$height, [int]$fg, [int]$bg, [string]$style) {
        if ($width -lt 2 -or $height -lt 2) { return }

        # Get box characters from cache or define them
        $chars = switch ($style) {
            "Double" {
                @{
                    TL = "╔"; TR = "╗"; BL = "╚"; BR = "╝"
                    V = "║"; H = "═"
                }
            }
            "Rounded" {
                @{
                    TL = "╭"; TR = "╮"; BL = "╰"; BR = "╯"
                    V = "│"; H = "─"
                }
            }
            Default {
                # Single
                @{
                    TL = "┌"; TR = "┐"; BL = "└"; BR = "┘"
                    V = "│"; H = "─"
                }
            }
        }

        # Draw top border
        $topLine = $chars.TL + ($chars.H * ($width - 2)) + $chars.TR
        $this.WriteAt($x, $y, $topLine, $fg, $bg)

        # Draw sides
        $middleLine = $chars.V + (" " * ($width - 2)) + $chars.V
        
        for ($i = 1; $i -lt ($height - 1); $i++) {
            $this.WriteAt($x, $y + $i, $middleLine, $fg, $bg)
        }

        # Draw bottom border
        $bottomLine = $chars.BL + ($chars.H * ($width - 2)) + $chars.BR
        $this.WriteAt($x, $y + $height - 1, $bottomLine, $fg, $bg)
    }

    [void] InvalidateCachedRegion([int]$minY, [int]$maxY) {
        # Forcing a redraw is easy: Just corrupt the FrontBuffer in that area.
        # This makes the Diff engine think "Everything changed" for those rows.
        for ($y = $minY; $y -le $maxY; $y++) {
            if ($y -ge 0 -and $y -lt $this.Height) {
                for ($x = 0; $x -lt $this.Width; $x++) {
                    # Set front buffer char to a specialized 'invalid' state
                    # so it definitely mismatches whatever is in backbuffer
                    $this._frontBuffer.SetCell($x, $y, [char]0, -1, -1, 0)
                }
            }
        }

        # VISUAL FIX: Also clear the lines on the terminal immediately
        # This prevents artifacts (like old menu items) from remaining visible
        # if the new frame doesn't write to those exact locations.
        try {
            $sb = [InternalStringBuilderPool]::Get()
            for ($y = $minY; $y -le $maxY; $y++) {
                if ($y -ge 0 -and $y -lt $this.Height) {
                    [void]$sb.Append("`e[$($y + 1);1H") # Move to start of line
                    [void]$sb.Append("`e[2K")           # Clear line
                }
            }
            [Console]::Write($sb.ToString())
            [InternalStringBuilderPool]::Recycle($sb)
        }
        catch {
            # Ignore errors if console is not available
        }

        # Mark dirty so EndFrame scans it
        $this._UpdateDirtyBounds(0, $minY)
        $this._UpdateDirtyBounds($this.Width - 1, $maxY)
    }

    # -------------------------------------------------------------------------
    # INTERNAL HELPERS
    # -------------------------------------------------------------------------

    hidden [void] _ResetDirtyBounds([bool]$fullScreen) {
        if ($fullScreen) {
            $this._dirtyBounds = @{ MinX = 0; MinY = 0; MaxX = $this.Width; MaxY = $this.Height }
        }
        else {
            # Inverted bounds to start
            $this._dirtyBounds = @{ MinX = $this.Width; MinY = $this.Height; MaxX = -1; MaxY = -1 }
        }
    }

    hidden [void] _UpdateDirtyBounds([int]$x, [int]$y) {
        if ($x -lt $this._dirtyBounds.MinX) { $this._dirtyBounds.MinX = $x }
        if ($x -gt $this._dirtyBounds.MaxX) { $this._dirtyBounds.MaxX = $x }
        if ($y -lt $this._dirtyBounds.MinY) { $this._dirtyBounds.MinY = $y }
        if ($y -gt $this._dirtyBounds.MaxY) { $this._dirtyBounds.MaxY = $y }
    }

    # Core Diffing Logic - delegates to C# for performance
    hidden [string] _BuildOptimizedDiff() {
        # If nothing changed, return empty
        if ($this._dirtyBounds.MaxX -lt 0) { return "" }

        # Delegate to C# BuildDiff for ~50-100x speedup
        if ($this._backBuffer.GetType().Name -eq 'NativeCellBuffer') {
            return $this._backBuffer.BuildDiff($this._frontBuffer)
        }

        # PowerShell fallback - Clamp bounds to screen
        $minX = [Math]::Max(0, $this._dirtyBounds.MinX)
        $maxX = [Math]::Min($this.Width - 1, $this._dirtyBounds.MaxX)
        $minY = [Math]::Max(0, $this._dirtyBounds.MinY)
        $maxY = [Math]::Min($this.Height - 1, $this._dirtyBounds.MaxY)

        # Use Pooled StringBuilder to save memory
        $sb = [InternalStringBuilderPool]::Get()

        $currentFg = -1
        $currentBg = -1
        $currentAttr = 0
        $termCursorX = -1
        $termCursorY = -1

        for ($y = $minY; $y -le $maxY; $y++) {
            $x = $minX
            while ($x -le $maxX) {
                # Get cells
                $back = $this._backBuffer.GetCell($x, $y)
                $front = $this._frontBuffer.GetCell($x, $y)

                # Skip if identical
                if ($back.Equals($front)) {
                    $x++
                    continue
                }

                # CHANGE DETECTED: We need to draw.
                
                # 1. Position Cursor (if needed)
                if ($termCursorX -ne $x -or $termCursorY -ne $y) {
                    # Optimized VT100 move
                    [void]$sb.Append("`e[$($y + 1);$($x + 1)H")
                    $termCursorX = $x
                    $termCursorY = $y
                }

                # 2. Look Ahead (Run Length Encoding)
                # Find how many subsequent cells have same color/attr AND need updating
                # (Or have same visual look, even if prev buffer matches... actually simpler:
                # just group by Attribute/Color for the write)
                
                $runLen = 0
                while (($x + $runLen) -le $maxX) {
                    $nextBack = $this._backBuffer.GetCell($x + $runLen, $y)
                    
                    # Stop if colors/attrs change
                    if (-not ($nextBack.ForegroundRgb -eq $back.ForegroundRgb -and 
                            $nextBack.BackgroundRgb -eq $back.BackgroundRgb -and 
                            $nextBack.Attributes -eq $back.Attributes)) {
                        break
                    }
                    
                    # Optimization: If the NEXT cell matches the front buffer (is unchanged),
                    # we technically *could* skip it. But breaking the run to skip 1 char 
                    # usually costs more bytes (cursor move) than just overwriting it.
                    # So we generally blast through unless there's a huge gap.
                    $runLen++
                }

                # 3. Update Colors/Attrs (Only if changed from current terminal state)
                if ($back.Attributes -ne $currentAttr) {
                    # Reset first if needed (simplified)
                    if ($currentAttr -ne 0) { 
                        [void]$sb.Append("`e[0m")
                        $currentFg = -1; $currentBg = -1
                    }
                    # Apply bits... (Bold, Underline, etc)
                    if ($back.Attributes -band 1) { [void]$sb.Append("`e[1m") } # Bold
                    if ($back.Attributes -band 2) { [void]$sb.Append("`e[4m") } # Underline
                    $currentAttr = $back.Attributes
                }

                if ($back.ForegroundRgb -ne $currentFg) {
                    # Emit RGB or Reset sequence
                    if ($back.ForegroundRgb -eq -1) { [void]$sb.Append("`e[39m") }
                    else { 
                        $rgb = [HybridRenderEngine]::_UnpackRGB($back.ForegroundRgb)
                        [void]$sb.Append("`e[38;2;$($rgb.R);$($rgb.G);$($rgb.B)m") 
                    }
                    $currentFg = $back.ForegroundRgb
                }

                if ($back.BackgroundRgb -ne $currentBg) {
                    if ($back.BackgroundRgb -eq -1) { [void]$sb.Append("`e[49m") }
                    else { 
                        $rgb = [HybridRenderEngine]::_UnpackRGB($back.BackgroundRgb)
                        [void]$sb.Append("`e[48;2;$($rgb.R);$($rgb.G);$($rgb.B)m") 
                    }
                    $currentBg = $back.BackgroundRgb
                }

                # 4. Write Characters
                for ($k = 0; $k -lt $runLen; $k++) {
                    [void]$sb.Append($this._backBuffer.GetCell($x + $k, $y).Char)
                }

                $x += $runLen
                $termCursorX += $runLen
            }
        }
        
        # Reset color at end of burst to be safe (optional, but good for cursor)
        if ($currentAttr -ne 0 -or $currentFg -ne -1 -or $currentBg -ne -1) {
            [void]$sb.Append("`e[0m")
        }

        $result = $sb.ToString()
        [InternalStringBuilderPool]::Recycle($sb)
        return $result
    }

    hidden [void] _ParseAnsiState([char]$cmd, [string]$params, [ref]$fg, [ref]$bg, [ref]$attr) {
        # Helper to parse ANSI codes and update state integers
        if ($cmd -ne 'm') { return }
        
        if ([string]::IsNullOrEmpty($params)) {
            $fg.Value = -1; $bg.Value = -1; $attr.Value = 0
            return
        }

        # Check cache
        if ([HybridRenderEngine]::_ansiCache.ContainsKey($params)) {
            $cached = [HybridRenderEngine]::_ansiCache[$params]
            # If cached value is a hashtable with state changes, apply them
            # However, since we need to update refs based on current state (accumulative?), 
            # actually ANSI codes like '31' are absolute for color, but '1' is additive for attr.
            # Simple caching of the *parsing result* (the loop below) is hard because of 'parts'.
            # But we can cache the *operations* for a param string.
            
            # For now, let's implement a simple cache for the most common single-code params
            # which avoids splitting and looping.
            if ($cached -is [hashtable]) {
                if ($cached.ContainsKey('Fg')) { $fg.Value = $cached.Fg }
                if ($cached.ContainsKey('Bg')) { $bg.Value = $cached.Bg }
                if ($cached.ContainsKey('Attr')) { $attr.Value = $attr.Value -bor $cached.Attr }
                if ($cached.ContainsKey('Reset')) { $fg.Value = -1; $bg.Value = -1; $attr.Value = 0 }
                return
            }
        }

        $parts = $params -split ';'
        $i = 0
        
        # Track changes for caching (only for simple cases)
        $cacheable = $true
        $cachedChanges = @{}

        while ($i -lt $parts.Length) {
            $code = [int]$parts[$i]
            switch ($code) {
                0 { 
                    $fg.Value = -1; $bg.Value = -1; $attr.Value = 0 
                    $cachedChanges['Reset'] = $true
                }
                1 { 
                    $attr.Value = $attr.Value -bor 1 
                    $cachedChanges['Attr'] = ($cachedChanges['Attr'] -bor 1)
                } # Bold
                4 { 
                    $attr.Value = $attr.Value -bor 2 
                    $cachedChanges['Attr'] = ($cachedChanges['Attr'] -bor 2)
                } # Underline
                38 { 
                    # FG RGB: 38;2;R;G;B
                    $cacheable = $false # Don't cache complex RGB for now
                    if ($i + 4 -lt $parts.Length -and $parts[$i + 1] -eq 2) {
                        $fg.Value = [HybridRenderEngine]::_PackRGB($parts[$i + 2], $parts[$i + 3], $parts[$i + 4])
                        $i += 4
                    }
                }
                48 { 
                    # BG RGB: 48;2;R;G;B
                    $cacheable = $false
                    if ($i + 4 -lt $parts.Length -and $parts[$i + 1] -eq 2) {
                        $bg.Value = [HybridRenderEngine]::_PackRGB($parts[$i + 2], $parts[$i + 3], $parts[$i + 4])
                        $i += 4
                    }
                }
                39 { 
                    $fg.Value = -1 
                    $cachedChanges['Fg'] = -1
                }
                49 { 
                    $bg.Value = -1 
                    $cachedChanges['Bg'] = -1
                }
                default {
                    # Handle standard 16 colors
                    if ($code -ge 30 -and $code -le 37) { 
                        # Standard FG (map to approximated RGB or special value? 
                        # CellBuffer uses int RGB. Let's map to -1 for now or implementation dependent.
                        # For strictly RGB engine, we might ignore or map to standard palette.
                        # This implementation seems to assume RGB or -1.
                        # Let's mark not cacheable if we don't handle it fully here.
                        $cacheable = $false
                    }
                }
            }
            $i++
        }

        # Cache simple results
        if ($cacheable -and $parts.Length -eq 1) {
            [HybridRenderEngine]::_ansiCache[$params] = $cachedChanges
        }
    }

    hidden static [int] _PackRGB([int]$r, [int]$g, [int]$b) {
        # Clamp to valid range
        $r = [Math]::Max(0, [Math]::Min(255, $r))
        $g = [Math]::Max(0, [Math]::Min(255, $g))
        $b = [Math]::Max(0, [Math]::Min(255, $b))

        return ($r -shl 16) -bor ($g -shl 8) -bor $b
    }

    hidden static [hashtable] _UnpackRGB([int]$packed) {
        return @{
            R = ($packed -shr 16) -band 0xFF
            G = ($packed -shr 8) -band 0xFF
            B = $packed -band 0xFF
        }
    }

    # Helper to convert ANSI string (e.g. from Theme) to Int Color
    static [int] AnsiColorToInt([string]$ansi) {
        if ([string]::IsNullOrEmpty($ansi)) { return -1 }
        
        # Parse RGB: \e[38;2;R;G;Bm or \e[48;2;R;G;Bm
        # We look for the sequence digit;digit;digit m
        if ($ansi -match '(\d+);(\d+);(\d+)m') {
            $r = [int]$matches[1]
            $g = [int]$matches[2]
            $b = [int]$matches[3]
            return [HybridRenderEngine]::_PackRGB($r, $g, $b)
        }
        
        return -1
    }

    # -------------------------------------------------------------------------
    # LAYOUT SYSTEM
    # -------------------------------------------------------------------------

    [void] DefineRegion([string]$id, [int]$x, [int]$y, [int]$width, [int]$height) {
        $this.DefineRegion($id, $x, $y, $width, $height, 0, "")
    }

    [void] DefineRegion([string]$id, [int]$x, [int]$y, [int]$width, [int]$height, [int]$zIndex) {
        $this.DefineRegion($id, $x, $y, $width, $height, $zIndex, "")
    }

    [void] DefineRegion([string]$id, [int]$x, [int]$y, [int]$width, [int]$height, [int]$zIndex, [string]$parentId) {
        $region = [LayoutRegion]::new($id, $x, $y, $width, $height)
        $region.ZIndex = $zIndex
        $region.ParentID = $parentId
        $this._regions[$id] = $region
    }

    [hashtable] GetRegionBounds([string]$id) {
        if (-not $this._regions.ContainsKey($id)) { return $null }
        
        $region = $this._regions[$id]
        $bounds = @{ X = $region.X; Y = $region.Y; Width = $region.Width; Height = $region.Height; ZIndex = $region.ZIndex }
        
        # Resolve parent offsets recursively
        $current = $region
        while (-not [string]::IsNullOrEmpty($current.ParentID)) {
            if ($this._regions.ContainsKey($current.ParentID)) {
                $parent = $this._regions[$current.ParentID]
                $bounds.X += $parent.X
                $bounds.Y += $parent.Y
                $bounds.ZIndex += $parent.ZIndex
                $current = $parent
            }
            else {
                break
            }
        }
        
        return $bounds
    }

    [void] WriteToRegion([string]$regionId, [string]$content) {
        $this.WriteToRegion($regionId, $content, -1, -1)
    }

    [void] WriteToRegion([string]$regionId, [string]$content, [int]$fg) {
        $this.WriteToRegion($regionId, $content, $fg, -1)
    }

    [void] WriteToRegion([string]$regionId, [string]$content, [int]$fg, [int]$bg) {
        $bounds = $this.GetRegionBounds($regionId)
        if ($null -eq $bounds) { return }
        
        # Apply region z-index temporarily
        $oldZ = $this._currentZ
        $this._currentZ = $bounds.ZIndex
        
        # Set clip to region bounds
        $this.PushClip($bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
        
        # Write at region origin (0,0 relative to region)
        # Note: WriteAt handles clipping logic
        if ($fg -ne -1 -or $bg -ne -1) {
            $this.WriteAt($bounds.X, $bounds.Y, $content, $fg, $bg)
        }
        else {
            $this.WriteAt($bounds.X, $bounds.Y, $content)
        }
        
        $this.PopClip()
        $this._currentZ = $oldZ
    }

    [void] WriteToRegion([string]$regionId, [string]$content, [int]$fgStart, [int]$fgEnd, [int]$bg) {
        $bounds = $this.GetRegionBounds($regionId)
        if ($null -eq $bounds) { return }
        
        # Apply region z-index temporarily
        $oldZ = $this._currentZ
        $this._currentZ = $bounds.ZIndex
        
        # Set clip to region bounds
        $this.PushClip($bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
        
        # Write at region origin (0,0 relative to region) using Gradient WriteAt
        $this.WriteAt($bounds.X, $bounds.Y, $content, $fgStart, $fgEnd, $bg)
        
        $this.PopClip()
        $this._currentZ = $oldZ
    }

    # Fill a defined region with a character and colors
    [void] FillRegion([string]$regionId, [string]$char, [int]$fg, [int]$bg) {
        $bounds = $this.GetRegionBounds($regionId)
        if ($null -eq $bounds) { return }
        $this.Fill($bounds.X, $bounds.Y, $bounds.Width, $bounds.Height, $char, $fg, $bg)
    }

    # Define a grid of columns within a parent region
    # columns: array of hashtables @{ Name='...'; Width=... } or just widths
    # Returns: array of generated region IDs
    [string[]] DefineGrid([string]$baseId, [int]$x, [int]$y, [int]$totalWidth, [int]$height, [array]$columns) {
        $generatedIds = @()
        $currentX = $x
        
        for ($i = 0; $i -lt $columns.Count; $i++) {
            $col = $columns[$i]
            $colWidth = 0
            $colName = "Col$i"
            
            if ($col -is [hashtable]) {
                if ($col.ContainsKey('Width')) { $colWidth = $col.Width }
                if ($col.ContainsKey('Name')) { $colName = $col.Name }
            }
            elseif ($col -is [int]) {
                $colWidth = $col
            }
            
            # Create region for column content
            $regionId = "${baseId}_${colName}"
            # CRITICAL FIX: Set ParentID to baseId so GetChildRegions works!
            $this.DefineRegion($regionId, $currentX, $y, $colWidth, $height, 0, $baseId)
            $generatedIds += $regionId
            
            # Advance X (including 4-space gap which is NOT part of the region)
            $currentX += $colWidth + 4
        }
        
        return $generatedIds
    }

    # Get immediate child regions for a parent ID
    [string[]] GetChildRegions([string]$parentId) {
        $children = @()
        foreach ($key in $this._regions.Keys) {
            $region = $this._regions[$key]
            if ($region.ParentID -eq $parentId) {
                $children += $region.ID
            }
        }
        # Sort by X to ensure column order
        $sorted = $children | Sort-Object { $this._regions[$_].X }
        return $sorted
    }

    # -------------------------------------------------------------------------
    # RENDER CACHE INTEGRATION
    # -------------------------------------------------------------------------

    <#
    .SYNOPSIS
    Capture a widget's rendered cells from the backbuffer
    
    .DESCRIPTION
    Used by RenderCache to snapshot a widget's output after RenderToEngine().
    Captures cells from the backbuffer within the specified bounds.
    
    .PARAMETER x, y
    Top-left corner of widget
    
    .PARAMETER width, height
    Widget dimensions
    
    .PARAMETER zIndex
    Z-layer the widget was rendered at
    
    .OUTPUTS
    CachedWidget with cell snapshot
    #>
    [object] CaptureWidget([int]$x, [int]$y, [int]$width, [int]$height, [int]$zIndex) {
        # Ensure RenderCache classes are loaded
        $cachedType = ([System.Management.Automation.PSTypeName]'CachedWidget').Type
        if (-not $cachedType) {
            # RenderCache not loaded - return null
            return $null
        }
        
        # Create cached widget
        $cached = [CachedWidget]::new($x, $y, $width, $height, $zIndex)
        
        # Clamp bounds to screen
        $startX = [Math]::Max(0, $x)
        $startY = [Math]::Max(0, $y)
        $endX = [Math]::Min($this.Width, $x + $width)
        $endY = [Math]::Min($this.Height, $y + $height)
        
        $captureWidth = $endX - $startX
        $captureHeight = $endY - $startY
        
        if ($captureWidth -le 0 -or $captureHeight -le 0) {
            return $null
        }
        
        # Create cell array [row][col]
        $cells = [object[]]::new($captureHeight)
        
        for ($row = 0; $row -lt $captureHeight; $row++) {
            $cells[$row] = [object[]]::new($captureWidth)
            $screenY = $startY + $row
            
            for ($col = 0; $col -lt $captureWidth; $col++) {
                $screenX = $startX + $col
                
                # Copy cell from backbuffer
                $cell = $this._backBuffer.GetCell($screenX, $screenY)
                
                # Store as hashtable (lighter than cloning Cell objects)
                $cells[$row][$col] = @{
                    Char = $cell.Char
                    Fg = $cell.ForegroundRgb
                    Bg = $cell.BackgroundRgb
                    Attr = $cell.Attributes
                }
            }
        }
        
        $cached.Cells = $cells
        return $cached
    }

    <#
    .SYNOPSIS
    Write cached cells directly to the backbuffer
    
    .DESCRIPTION
    Used by RenderCache to replay a cached widget's cells.
    Writes cells directly without re-rendering the widget.
    Respects Z-index from cached data.
    
    .PARAMETER cached
    CachedWidget with cell snapshot
    #>
    [void] WriteFromCache([object]$cached) {
        if ($null -eq $cached -or $null -eq $cached.Cells) {
            return
        }
        
        # Set Z-index for proper layering
        $oldZ = $this._currentZ
        $this._currentZ = $cached.ZIndex
        
        $startX = $cached.X
        $startY = $cached.Y
        $cells = $cached.Cells
        
        for ($row = 0; $row -lt $cells.Count; $row++) {
            $screenY = $startY + $row
            
            if ($screenY -lt 0 -or $screenY -ge $this.Height) { continue }
            
            $rowCells = $cells[$row]
            for ($col = 0; $col -lt $rowCells.Count; $col++) {
                $screenX = $startX + $col
                
                if ($screenX -lt 0 -or $screenX -ge $this.Width) { continue }
                
                # Check Z-index (same logic as WriteAt)
                if ($this._currentZ -ge $this._zBuffer[$screenY][$screenX]) {
                    $cell = $rowCells[$col]
                    
                    # Write to backbuffer
                    $this._backBuffer.SetCell($screenX, $screenY, $cell.Char, $cell.Fg, $cell.Bg, $cell.Attr)
                    
                    # Update Z buffer
                    $this._zBuffer[$screenY][$screenX] = $this._currentZ
                    
                    # Update dirty bounds
                    $this._UpdateDirtyBounds($screenX, $screenY)
                }
            }
        }
        
        $this._currentZ = $oldZ
    }
}