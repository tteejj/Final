# SpeedTUI Render Engine - Flicker-free differential rendering

using namespace System.Collections.Generic

class RenderRegion {
    [int]$X
    [int]$Y
    [int]$Width
    [int]$Height
    [string]$Id
    [int]$ZOrder = 0
    hidden [object]$_logger
    
    RenderRegion([string]$id, [int]$x, [int]$y, [int]$width, [int]$height) {
        $this._logger = Get-Logger
        
        $this._logger.Trace("RenderRegion", "Constructor", "Creating render region", @{
            Id = $id
            X = $x
            Y = $y
            Width = $width
            Height = $height
        })
        
        try {
            [Guard]::NotNullOrEmpty($id, "id")
            [Guard]::NonNegative($x, "x")
            [Guard]::NonNegative($y, "y")
            [Guard]::Positive($width, "width")
            [Guard]::Positive($height, "height")
            
            $this.Id = $id
            $this.X = $x
            $this.Y = $y
            $this.Width = $width
            $this.Height = $height
            
            $this._logger.Debug("RenderRegion", "Constructor", "Render region created successfully", @{
                Id = $id
                Bounds = "$x,$y ${width}x${height}"
            })
        } catch {
            $this._logger.Error("RenderRegion", "Constructor", "Failed to create render region", @{
                Id = $id
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    [bool] Contains([int]$x, [int]$y) {
        $this._logger.Trace("RenderRegion", "Contains", "Checking if point is contained", @{
            Id = $this.Id
            PointX = $x
            PointY = $y
            RegionBounds = "$($this.X),$($this.Y) $($this.Width)x$($this.Height)"
        })
        
        try {
            $contains = $x -ge $this.X -and $x -lt ($this.X + $this.Width) -and
                       $y -ge $this.Y -and $y -lt ($this.Y + $this.Height)
            
            $this._logger.Trace("RenderRegion", "Contains", "Contains check completed", @{
                Id = $this.Id
                Contains = $contains
            })
            
            return $contains
        } catch {
            $this._logger.Error("RenderRegion", "Contains", "Contains check failed", @{
                Id = $this.Id
                PointX = $x
                PointY = $y
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    [bool] Intersects([RenderRegion]$other) {
        $this._logger.Trace("RenderRegion", "Intersects", "Checking region intersection", @{
            Id = $this.Id
            OtherId = $(if ($other) { $other.Id } else { "null" })
            ThisBounds = "$($this.X),$($this.Y) $($this.Width)x$($this.Height)"
            OtherBounds = $(if ($other) { "$($other.X),$($other.Y) $($other.Width)x$($other.Height)" } else { "null" })
        })
        
        try {
            [Guard]::NotNull($other, "other")
            
            $intersects = -not (
                ($this.X + $this.Width) -le $other.X -or
                ($other.X + $other.Width) -le $this.X -or
                ($this.Y + $this.Height) -le $other.Y -or
                ($other.Y + $other.Height) -le $this.Y
            )
            
            $this._logger.Debug("RenderRegion", "Intersects", "Intersection check completed", @{
                Id = $this.Id
                OtherId = $other.Id
                Intersects = $intersects
            })
            
            return $intersects
        } catch {
            $this._logger.Error("RenderRegion", "Intersects", "Intersection check failed", @{
                Id = $this.Id
                Exception = $_.Exception.Message
            })
            throw
        }
    }
}

class RenderBuffer {
    [int]$Width
    [int]$Height
    hidden [string[,]]$_buffer
    hidden [string[,]]$_previousBuffer
    hidden [object]$_logger
    
    RenderBuffer([int]$width, [int]$height) {
        [Guard]::Positive($width, "width")
        [Guard]::Positive($height, "height")
        
        $this.Width = $width
        $this.Height = $height
        $this._buffer = New-Object 'string[,]' $height, $width
        $this._previousBuffer = New-Object 'string[,]' $height, $width
        $this._logger = Get-Logger
        
        # Initialize buffers with spaces
        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $this._buffer[$y, $x] = " "
                $this._previousBuffer[$y, $x] = " "
            }
        }
        
        $this._logger.Debug("RenderBuffer", "Constructor", "Buffer initialized", @{
            Width = $width
            Height = $height
        })
    }
    
    [void] WriteAt([int]$x, [int]$y, [string]$text) {
        $this._logger.Trace("RenderBuffer", "WriteAt", "Writing text to buffer", @{
            X = $x
            Y = $y
            Text = $text
            TextLength = $(if ($text) { $text.Length } else { 0 })
            BufferSize = "$($this.Width)x$($this.Height)"
        })
        
        try {
            [Guard]::NotNull($text, "text")
            
            if ($x -lt 0 -or $y -lt 0 -or $y -ge $this.Height) { 
                $this._logger.Debug("RenderBuffer", "WriteAt", "Coordinates out of bounds, skipping", @{
                    X = $x
                    Y = $y
                    Width = $this.Width
                    Height = $this.Height
                })
                return 
            }
            
            $chars = $text.ToCharArray()
            $currentX = $x
            $charsWritten = 0
            
            foreach ($char in $chars) {
                if ($currentX -ge $this.Width) { break }
                $this._buffer[$y, $currentX] = $char.ToString()
                $currentX++
                $charsWritten++
            }
            
            $this._logger.Trace("RenderBuffer", "WriteAt", "Text written successfully", @{
                X = $x
                Y = $y
                CharsWritten = $charsWritten
                TotalChars = $chars.Length
            })
        } catch {
            $this._logger.Error("RenderBuffer", "WriteAt", "Failed to write text to buffer", @{
                X = $x
                Y = $y
                Text = $text
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    [void] Clear() {
        $this._logger.Trace("RenderBuffer", "Clear", "Clearing entire buffer", @{
            BufferSize = "$($this.Width)x$($this.Height)"
        })
        
        try {
            $cellsCleared = 0
            for ($y = 0; $y -lt $this.Height; $y++) {
                for ($x = 0; $x -lt $this.Width; $x++) {
                    $this._buffer[$y, $x] = " "
                    $cellsCleared++
                }
            }
            
            $this._logger.Debug("RenderBuffer", "Clear", "Buffer cleared successfully", @{
                CellsCleared = $cellsCleared
            })
        } catch {
            $this._logger.Error("RenderBuffer", "Clear", "Failed to clear buffer", @{
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    [void] ClearRegion([int]$x, [int]$y, [int]$width, [int]$height) {
        $this._logger.Trace("RenderBuffer", "ClearRegion", "Clearing buffer region", @{
            X = $x
            Y = $y
            Width = $width
            Height = $height
            BufferSize = "$($this.Width)x$($this.Height)"
        })
        
        try {
            $endX = [Math]::Min($x + $width, $this.Width)
            $endY = [Math]::Min($y + $height, $this.Height)
            $startX = [Math]::Max(0, $x)
            $startY = [Math]::Max(0, $y)
            
            $cellsCleared = 0
            for ($cy = $startY; $cy -lt $endY; $cy++) {
                for ($cx = $startX; $cx -lt $endX; $cx++) {
                    $this._buffer[$cy, $cx] = " "
                    $cellsCleared++
                }
            }
            
            $this._logger.Debug("RenderBuffer", "ClearRegion", "Region cleared successfully", @{
                ActualBounds = "$startX,$startY to $endX,$endY"
                CellsCleared = $cellsCleared
            })
        } catch {
            $this._logger.Error("RenderBuffer", "ClearRegion", "Failed to clear region", @{
                X = $x
                Y = $y
                Width = $width
                Height = $height
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    [List[hashtable]] GetDifferences() {
        $this._logger.Trace("RenderBuffer", "GetDifferences", "Computing buffer differences", @{
            BufferSize = "$($this.Width)x$($this.Height)"
        })
        
        try {
            $differences = [List[hashtable]]::new()
            $cellsCompared = 0
            $changedCells = 0
            
            for ($y = 0; $y -lt $this.Height; $y++) {
                $lineChanged = $false
                $lineStart = -1
                $lineContent = [System.Text.StringBuilder]::new()
                
                for ($x = 0; $x -lt $this.Width; $x++) {
                    $current = $this._buffer[$y, $x]
                    $previous = $this._previousBuffer[$y, $x]
                    $cellsCompared++
                    
                    if ($current -ne $previous) {
                        $changedCells++
                        if (-not $lineChanged) {
                            $lineChanged = $true
                            $lineStart = $x
                        }
                        $lineContent.Append($current)
                    } else {
                        if ($lineChanged) {
                            # End of changed region
                            $differences.Add(@{
                                X = $lineStart
                                Y = $y
                                Content = $lineContent.ToString()
                            })
                            $lineChanged = $false
                            $lineContent.Clear()
                        }
                    }
                }
                
                # Handle end of line
                if ($lineChanged) {
                    $differences.Add(@{
                        X = $lineStart
                        Y = $y
                        Content = $lineContent.ToString()
                    })
                }
            }
            
            $this._logger.Debug("RenderBuffer", "GetDifferences", "Differences computed", @{
                DifferenceCount = $differences.Count
                CellsCompared = $cellsCompared
                ChangedCells = $changedCells
                ChangePercentage = $(if ($cellsCompared -gt 0) { [Math]::Round(($changedCells / $cellsCompared) * 100, 2) } else { 0 })
            })
            
            return $differences
        } catch {
            $this._logger.Error("RenderBuffer", "GetDifferences", "Failed to compute differences", @{
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    [void] Swap() {
        $this._logger.Trace("RenderBuffer", "Swap", "Swapping render buffers")
        
        try {
            # Swap buffers
            $temp = $this._previousBuffer
            $this._previousBuffer = $this._buffer
            $this._buffer = $temp
            
            # Clear new buffer
            $this.Clear()
            
            $this._logger.Trace("RenderBuffer", "Swap", "Buffer swap completed successfully")
        } catch {
            $this._logger.Error("RenderBuffer", "Swap", "Failed to swap buffers", @{
                Exception = $_.Exception.Message
            })
            throw
        }
    }
}

class RenderEngine {
    hidden [Terminal]$_terminal
    hidden [RenderBuffer]$_buffer
    hidden [Dictionary[string, RenderRegion]]$_regions
    hidden [List[string]]$_dirtyRegions
    hidden [object]$_logger
    hidden [bool]$_initialized = $false
    
    # Performance tracking
    hidden [int]$_frameCount = 0
    hidden [double]$_totalRenderTime = 0
    
    RenderEngine() {
        $this._logger = Get-Logger
        
        $this._logger.Trace("RenderEngine", "Constructor", "Creating render engine")
        
        try {
            $this._terminal = [Terminal]::GetInstance()
            $this._regions = [Dictionary[string, RenderRegion]]::new()
            $this._dirtyRegions = [List[string]]::new()
            
            $this._logger.Info("RenderEngine", "Constructor", "RenderEngine created successfully")
        } catch {
            $this._logger.Error("RenderEngine", "Constructor", "Failed to create render engine", @{
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    [void] Initialize() {
        $this._logger.Trace("RenderEngine", "Initialize", "Initialize method started", @{
            AlreadyInitialized = $this._initialized
        })
        
        if ($this._initialized) { 
            $this._logger.Debug("RenderEngine", "Initialize", "Already initialized, skipping")
            return 
        }
        
        try {
            $this._logger.Info("RenderEngine", "Initialize", "Initializing render engine")
            
            # Initialize terminal
            $this._logger.Debug("RenderEngine", "Initialize", "Initializing terminal")
            $this._terminal.Initialize()
            
            # Create buffer matching terminal size
            $this._logger.Debug("RenderEngine", "Initialize", "Creating render buffer", @{
                Width = $this._terminal.Width
                Height = $this._terminal.Height
            })
            $this._buffer = [RenderBuffer]::new($this._terminal.Width, $this._terminal.Height)
            
            $this._initialized = $true
            
            $this._logger.Info("RenderEngine", "Initialize", "Render engine initialized successfully", @{
                Width = $this._terminal.Width
                Height = $this._terminal.Height
            })
        } catch {
            $this._logger.Error("RenderEngine", "Initialize", "Failed to initialize render engine", @{
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    [void] Cleanup() {
        $this._logger.Trace("RenderEngine", "Cleanup", "Cleanup method started", @{
            Initialized = $this._initialized
            FrameCount = $this._frameCount
        })
        
        try {
            $this._logger.Info("RenderEngine", "Cleanup", "Cleaning up render engine")
            
            if ($this._initialized) {
                $this._logger.Debug("RenderEngine", "Cleanup", "Cleaning up terminal")
                $this._terminal.Cleanup()
                $this._initialized = $false
            }
            
            # Log performance stats
            if ($this._frameCount -gt 0) {
                $avgRenderTime = $this._totalRenderTime / $this._frameCount
                $this._logger.Info("RenderEngine", "Performance", "Final render statistics", @{
                    TotalFrames = $this._frameCount
                    TotalRenderTime = [Math]::Round($this._totalRenderTime, 2)
                    AverageRenderMs = [Math]::Round($avgRenderTime, 2)
                    AverageFPS = [Math]::Round(1000.0 / $avgRenderTime, 1)
                })
            } else {
                $this._logger.Info("RenderEngine", "Performance", "No frames rendered")
            }
            
            $this._logger.Info("RenderEngine", "Cleanup", "Render engine cleanup completed")
        } catch {
            $this._logger.Error("RenderEngine", "Cleanup", "Failed to cleanup render engine", @{
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    [RenderRegion] DefineRegion([string]$id, [int]$x, [int]$y, [int]$width, [int]$height) {
        $this._logger.Trace("RenderEngine", "DefineRegion", "Defining new region", @{
            Id = $id
            X = $x
            Y = $y
            Width = $width
            Height = $height
            ExistingRegions = $this._regions.Count
        })
        
        try {
            [Guard]::NotNullOrEmpty($id, "id")
            
            if ($this._regions.ContainsKey($id)) {
                $this._logger.Warn("RenderEngine", "DefineRegion", "Region already exists, replacing", @{
                    Id = $id
                })
            }
            
            $region = [RenderRegion]::new($id, $x, $y, $width, $height)
            $this._regions[$id] = $region
            
            $this._logger.Debug("RenderEngine", "DefineRegion", "Region defined successfully", @{
                Id = $id
                X = $x
                Y = $y
                Width = $width
                Height = $height
                TotalRegions = $this._regions.Count
            })
            
            return $region
        } catch {
            $this._logger.Error("RenderEngine", "DefineRegion", "Failed to define region", @{
                Id = $id
                X = $x
                Y = $y
                Width = $width
                Height = $height
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    [void] RemoveRegion([string]$id) {
        $this._logger.Trace("RenderEngine", "RemoveRegion", "Removing region", @{
            Id = $id
            RegionExists = $this._regions.ContainsKey($id)
            TotalRegions = $this._regions.Count
        })
        
        try {
            [Guard]::NotNullOrEmpty($id, "id")
            
            if ($this._regions.ContainsKey($id)) {
                $this._regions.Remove($id)
                $this.MarkDirty($id)
                
                $this._logger.Debug("RenderEngine", "RemoveRegion", "Region removed successfully", @{
                    Id = $id
                    RemainingRegions = $this._regions.Count
                })
            } else {
                $this._logger.Warn("RenderEngine", "RemoveRegion", "Region not found", @{
                    Id = $id
                    AvailableRegions = ($this._regions.Keys -join ", ")
                })
            }
        } catch {
            $this._logger.Error("RenderEngine", "RemoveRegion", "Failed to remove region", @{
                Id = $id
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    [void] MarkDirty([string]$regionId) {
        $this._logger.Trace("RenderEngine", "MarkDirty", "Marking region dirty", @{
            RegionId = $regionId
            AlreadyDirty = $this._dirtyRegions.Contains($regionId)
            TotalDirtyRegions = $this._dirtyRegions.Count
        })
        
        try {
            [Guard]::NotNullOrEmpty($regionId, "regionId")
            
            if (-not $this._dirtyRegions.Contains($regionId)) {
                $this._dirtyRegions.Add($regionId)
                
                $this._logger.Debug("RenderEngine", "MarkDirty", "Region marked dirty", @{
                    RegionId = $regionId
                    TotalDirtyRegions = $this._dirtyRegions.Count
                })
            } else {
                $this._logger.Trace("RenderEngine", "MarkDirty", "Region already dirty")
            }
        } catch {
            $this._logger.Error("RenderEngine", "MarkDirty", "Failed to mark region dirty", @{
                RegionId = $regionId
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    [void] WriteToRegion([string]$regionId, [int]$x, [int]$y, [string]$text) {
        $this._logger.Trace("RenderEngine", "WriteToRegion", "Writing to region", @{
            RegionId = $regionId
            X = $x
            Y = $y
            Text = $text
            TextLength = $(if ($text) { $text.Length } else { 0 })
        })
        
        try {
            [Guard]::NotNullOrEmpty($regionId, "regionId")
            [Guard]::NotNull($text, "text")
            
            $region = $this._regions[$regionId]
            if ($null -eq $region) {
                $this._logger.Warn("RenderEngine", "WriteToRegion", "Region not found", @{
                    RegionId = $regionId
                    AvailableRegions = ($this._regions.Keys -join ", ")
                })
                return
            }
            
            # Convert to absolute coordinates
            $absX = $region.X + $x
            $absY = $region.Y + $y
            
            # Clip to region bounds
            if ($x -lt 0 -or $y -lt 0 -or $x -ge $region.Width -or $y -ge $region.Height) {
                $this._logger.Debug("RenderEngine", "WriteToRegion", "Coordinates outside region bounds", @{
                    RegionId = $regionId
                    RelativeCoords = "$x,$y"
                    RegionBounds = "$($region.Width)x$($region.Height)"
                })
                return
            }
            
            # Write to buffer
            $this._buffer.WriteAt($absX, $absY, $text)
            $this.MarkDirty($regionId)
            
            $this._logger.Trace("RenderEngine", "WriteToRegion", "Text written successfully", @{
                RegionId = $regionId
                AbsoluteCoords = "$absX,$absY"
            })
        } catch {
            $this._logger.Error("RenderEngine", "WriteToRegion", "Failed to write to region", @{
                RegionId = $regionId
                X = $x
                Y = $y
                Text = $text
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    [void] ClearRegion([string]$regionId) {
        $this._logger.Trace("RenderEngine", "ClearRegion", "Clearing region", @{
            RegionId = $regionId
        })
        
        try {
            [Guard]::NotNullOrEmpty($regionId, "regionId")
            
            $region = $this._regions[$regionId]
            if ($null -eq $region) { 
                $this._logger.Warn("RenderEngine", "ClearRegion", "Region not found", @{
                    RegionId = $regionId
                    AvailableRegions = ($this._regions.Keys -join ", ")
                })
                return 
            }
            
            $this._logger.Debug("RenderEngine", "ClearRegion", "Clearing region buffer", @{
                RegionId = $regionId
                Bounds = "$($region.X),$($region.Y) $($region.Width)x$($region.Height)"
            })
            
            $this._buffer.ClearRegion($region.X, $region.Y, $region.Width, $region.Height)
            $this.MarkDirty($regionId)
            
            $this._logger.Trace("RenderEngine", "ClearRegion", "Region cleared successfully")
        } catch {
            $this._logger.Error("RenderEngine", "ClearRegion", "Failed to clear region", @{
                RegionId = $regionId
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    [void] BeginFrame() {
        $this._logger.Trace("RenderEngine", "BeginFrame", "Beginning frame", @{
            FrameCount = $this._frameCount
            DirtyRegions = $this._dirtyRegions.Count
        })
        
        try {
            # For the very first frame, clear the screen
            if ($this._frameCount -eq 0) {
                [Console]::Clear()
                [Console]::SetCursorPosition(0, 0)
            }
            # After first frame, differential rendering handles everything
            
            $this._logger.Trace("RenderEngine", "BeginFrame", "Frame begun successfully")
        } catch {
            $this._logger.Error("RenderEngine", "BeginFrame", "Failed to begin frame", @{
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    [void] EndFrame() {
        $this._logger.Trace("RenderEngine", "EndFrame", "Ending frame", @{
            FrameCount = $this._frameCount
            DirtyRegions = $this._dirtyRegions.Count
        })
        
        $timer = $this._logger.MeasurePerformance("RenderEngine", "Frame")
        
        try {
            # Get differences
            $this._logger.Debug("RenderEngine", "EndFrame", "Computing buffer differences")
            $differences = $this._buffer.GetDifferences()
            
            if ($differences.Count -gt 0) {
                $this._logger.Trace("RenderEngine", "EndFrame", "Rendering differences", @{
                    DifferenceCount = $differences.Count
                })
                
                # Apply differences directly to console using ANSI sequences like @praxis
                foreach ($diff in $differences) {
                    # Use ANSI positioning (1-based coordinates)
                    $ansiPosition = "`e[$($diff.Y + 1);$($diff.X + 1)H"
                    [Console]::Write($ansiPosition + $diff.Content)
                }
            } else {
                $this._logger.Trace("RenderEngine", "EndFrame", "No differences to render")
            }
            
            # Swap buffers
            $this._logger.Debug("RenderEngine", "EndFrame", "Swapping buffers")
            $this._buffer.Swap()
            
            # Clear dirty regions
            $dirtyCount = $this._dirtyRegions.Count
            $this._dirtyRegions.Clear()
            
            # Note: Not calling Terminal.EndFrame() since we're using direct console output
            # The Terminal's batched system is bypassed by RenderEngine
            
            # Track performance
            $this._frameCount++
            $frameTime = $timer.Elapsed.TotalMilliseconds
            $this._totalRenderTime += $frameTime
            
            $this._logger.Trace("RenderEngine", "EndFrame", "Frame completed", @{
                FrameNumber = $this._frameCount
                DifferencesRendered = $differences.Count
                DirtyRegionsCleared = $dirtyCount
                FrameTimeMs = [Math]::Round($frameTime, 2)
            })
            
        } catch {
            $this._logger.Error("RenderEngine", "EndFrame", "Failed to end frame", @{
                FrameCount = $this._frameCount
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        } finally {
            $timer.Dispose()
        }
    }
    
    # Helper methods for common drawing operations
    [void] DrawBox([string]$regionId, [int]$x, [int]$y, [int]$width, [int]$height) {
        $this._logger.Trace("RenderEngine", "DrawBox", "Drawing box with default style", @{
            RegionId = $regionId
            X = $x
            Y = $y
            Width = $width
            Height = $height
            Style = "Single"
        })
        
        try {
            $this.DrawBox($regionId, $x, $y, $width, $height, "Single")
        } catch {
            $this._logger.Error("RenderEngine", "DrawBox", "Failed to draw box", @{
                RegionId = $regionId
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    [void] DrawBox([string]$regionId, [int]$x, [int]$y, [int]$width, [int]$height, [string]$style) {
        $this._logger.Trace("RenderEngine", "DrawBox", "Drawing styled box", @{
            RegionId = $regionId
            X = $x
            Y = $y
            Width = $width
            Height = $height
            Style = $style
        })
        
        try {
            [Guard]::NotNullOrEmpty($regionId, "regionId")
            
            if ($width -lt 2 -or $height -lt 2) {
                $this._logger.Warn("RenderEngine", "DrawBox", "Box too small to draw borders", @{
                    Width = $width
                    Height = $height
                })
                return
            }
            
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
            
            $this._logger.Debug("RenderEngine", "DrawBox", "Drawing box borders", @{
                RegionId = $regionId
                Style = $style
                CharSet = $chars.Keys -join ", "
            })
            
            # Top border
            $this.WriteToRegion($regionId, $x, $y, $chars.TL)
            if ($width -gt 2) {
                $this.WriteToRegion($regionId, $x + 1, $y, $chars.H * ($width - 2))
            }
            $this.WriteToRegion($regionId, $x + $width - 1, $y, $chars.TR)
            
            # Side borders
            for ($row = 1; $row -lt $height - 1; $row++) {
                $this.WriteToRegion($regionId, $x, $y + $row, $chars.V)
                $this.WriteToRegion($regionId, $x + $width - 1, $y + $row, $chars.V)
            }
            
            # Bottom border
            if ($height -gt 1) {
                $this.WriteToRegion($regionId, $x, $y + $height - 1, $chars.BL)
                if ($width -gt 2) {
                    $this.WriteToRegion($regionId, $x + 1, $y + $height - 1, $chars.H * ($width - 2))
                }
                $this.WriteToRegion($regionId, $x + $width - 1, $y + $height - 1, $chars.BR)
            }
            
            $this._logger.Trace("RenderEngine", "DrawBox", "Box drawn successfully")
        } catch {
            $this._logger.Error("RenderEngine", "DrawBox", "Failed to draw styled box", @{
                RegionId = $regionId
                X = $x
                Y = $y
                Width = $width
                Height = $height
                Style = $style
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
}