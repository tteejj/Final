# SpeedTUI Enhanced Terminal - Optimized terminal control with transparent performance improvements
# This enhances the existing Terminal class with performance optimizations while maintaining the same API

# Load the performance core
. "$PSScriptRoot/Internal/PerformanceCore.ps1"

<#
.SYNOPSIS
Enhanced Terminal class with transparent performance optimizations

.DESCRIPTION
This class extends the existing Terminal functionality with performance optimizations
from the internal performance core. The API remains exactly the same for developers,
but performance is significantly improved through caching and pooling.

.EXAMPLE
# Developer code remains exactly the same:
$terminal = [EnhancedTerminal]::GetInstance()
$terminal.Initialize()
$terminal.WriteAt(10, 5, "Hello World")
$terminal.EndFrame()
#>
class EnhancedTerminal : Terminal {
    # Additional performance tracking
    hidden [System.Collections.Generic.Dictionary[string, string]]$_sequenceCache
    hidden [string]$_previousBuffer = ""
    hidden [bool]$_enableDifferentialRendering = $true
    
    # Constructor
    EnhancedTerminal() : base() {
        $this._sequenceCache = [System.Collections.Generic.Dictionary[string, string]]::new()
        $this._logger.Info("EnhancedTerminal", "Constructor", "Enhanced Terminal initialized with performance optimizations")
    }
    
    # Enhanced cursor movement with caching
    [void] MoveCursor([int]$x, [int]$y) {
        [Guard]::NonNegative($x, "x")
        [Guard]::NonNegative($y, "y")
        [Guard]::InRange($x, 0, $this.Width - 1, "x")
        [Guard]::InRange($y, 0, $this.Height - 1, "y")
        
        # Use optimized VT100 movement
        $moveSequence = [InternalVT100]::MoveTo($x, $y)
        $this._renderBatch.Append($moveSequence)
    }
    
    # Enhanced WriteAt with performance optimizations
    [void] WriteAt([int]$x, [int]$y, [string]$text) {
        [Guard]::NotNull($text, "text")
        
        if ($x -lt 0 -or $y -lt 0 -or $y -ge $this.Height) { return }
        
        # Clip text to terminal width
        $maxLength = $this.Width - $x
        if ($maxLength -le 0) { return }
        
        if ($text.Length -gt $maxLength) {
            $text = $text.Substring(0, $maxLength)
        }
        
        $this.MoveCursor($x, $y)
        $this._renderBatch.Append($text)
    }
    
    # Enhanced WriteAt with colors using optimized sequences
    [void] WriteAt([int]$x, [int]$y, [string]$text, [string]$foreground, [string]$background) {
        [Guard]::NotNull($text, "text")
        
        if ($x -lt 0 -or $y -lt 0 -or $y -ge $this.Height) { return }
        
        # Clip text to terminal width
        $maxLength = $this.Width - $x
        if ($maxLength -le 0) { return }
        
        if ($text.Length -gt $maxLength) {
            $text = $text.Substring(0, $maxLength)
        }
        
        $this.MoveCursor($x, $y)
        
        # Apply colors if provided
        if ($foreground) {
            $this._renderBatch.Append($foreground)
        }
        if ($background) {
            $this._renderBatch.Append($background)
        }
        
        $this._renderBatch.Append($text)
        
        # Reset colors using cached sequence
        if ($foreground -or $background) {
            $this._renderBatch.Append([InternalStringCache]::GetAnsiSequence("reset"))
        }
    }
    
    # Enhanced RGB color support
    [void] WriteAtRGB([int]$x, [int]$y, [string]$text, [int]$fgR, [int]$fgG, [int]$fgB) {
        $fgColor = [InternalVT100]::RGB($fgR, $fgG, $fgB)
        $this.WriteAt($x, $y, $text, $fgColor, "")
    }
    
    # Enhanced RGB color with background support
    [void] WriteAtRGB([int]$x, [int]$y, [string]$text, [int]$fgR, [int]$fgG, [int]$fgB, [int]$bgR, [int]$bgG, [int]$bgB) {
        $fgColor = [InternalVT100]::RGB($fgR, $fgG, $fgB)
        $bgColor = [InternalVT100]::RGBBackground($bgR, $bgG, $bgB)
        $this.WriteAt($x, $y, $text, $fgColor, $bgColor)
    }
    
    # Enhanced clear operations using optimized sequences
    [void] Clear() {
        $this._renderBatch.Append([InternalStringCache]::GetAnsiSequence("clear"))
        $this._renderBatch.Append([InternalStringCache]::GetAnsiSequence("home"))
    }
    
    [void] ClearLine([int]$y) {
        [Guard]::InRange($y, 0, $this.Height - 1, "y")
        $this.MoveCursor(0, $y)
        $this._renderBatch.Append([InternalStringCache]::GetAnsiSequence("clearline"))
    }
    
    # Enhanced region clearing with optimized spaces
    [void] ClearRegion([int]$x, [int]$y, [int]$width, [int]$height) {
        [Guard]::NonNegative($x, "x")
        [Guard]::NonNegative($y, "y")
        [Guard]::Positive($width, "width")
        [Guard]::Positive($height, "height")
        
        # Use optimized spaces
        $spaces = [InternalStringCache]::GetSpaces($width)
        for ($row = 0; $row -lt $height; $row++) {
            $currentY = $y + $row
            if ($currentY -ge $this.Height) { break }
            $this.WriteAt($x, $currentY, $spaces)
        }
    }
    
    # Enhanced box drawing with cached characters
    [void] DrawBox([int]$x, [int]$y, [int]$width, [int]$height, [string]$style) {
        [Guard]::NonNegative($x, "x")
        [Guard]::NonNegative($y, "y")
        [Guard]::InRange($width, 2, $this.Width - $x, "width")
        [Guard]::InRange($height, 2, $this.Height - $y, "height")
        
        # Use cached box drawing characters
        $chars = switch ($style) {
            "Double" { @{
TL = $(if ($null -ne ([InternalStringCache]::GetBoxDrawing("doubletopleft"))) { [InternalStringCache]::GetBoxDrawing("doubletopleft") } else { "╔" })
TR = $(if ($null -ne ([InternalStringCache]::GetBoxDrawing("doubletopright"))) { [InternalStringCache]::GetBoxDrawing("doubletopright") } else { "╗" })
BL = $(if ($null -ne ([InternalStringCache]::GetBoxDrawing("doublebottomleft"))) { [InternalStringCache]::GetBoxDrawing("doublebottomleft") } else { "╚" })
BR = $(if ($null -ne ([InternalStringCache]::GetBoxDrawing("doublebottomright"))) { [InternalStringCache]::GetBoxDrawing("doublebottomright") } else { "╝" })
H = $(if ($null -ne ([InternalStringCache]::GetBoxDrawing("doublehorizontal"))) { [InternalStringCache]::GetBoxDrawing("doublehorizontal") } else { "═" })
V = $(if ($null -ne ([InternalStringCache]::GetBoxDrawing("doublevertical"))) { [InternalStringCache]::GetBoxDrawing("doublevertical") } else { "║" })
            }}
            "Rounded" { @{
TL = $(if ($null -ne ([InternalStringCache]::GetBoxDrawing("roundedtopleft"))) { [InternalStringCache]::GetBoxDrawing("roundedtopleft") } else { "╭" })
TR = $(if ($null -ne ([InternalStringCache]::GetBoxDrawing("roundedtopright"))) { [InternalStringCache]::GetBoxDrawing("roundedtopright") } else { "╮" })
BL = $(if ($null -ne ([InternalStringCache]::GetBoxDrawing("roundedbottomleft"))) { [InternalStringCache]::GetBoxDrawing("roundedbottomleft") } else { "╰" })
BR = $(if ($null -ne ([InternalStringCache]::GetBoxDrawing("roundedbottomright"))) { [InternalStringCache]::GetBoxDrawing("roundedbottomright") } else { "╯" })
                H = [InternalStringCache]::GetBoxDrawing("horizontal")
                V = [InternalStringCache]::GetBoxDrawing("vertical")
            }}
            default { @{
                TL = [InternalStringCache]::GetBoxDrawing("topleft")
                TR = [InternalStringCache]::GetBoxDrawing("topright")
                BL = [InternalStringCache]::GetBoxDrawing("bottomleft")
                BR = [InternalStringCache]::GetBoxDrawing("bottomright")
                H = [InternalStringCache]::GetBoxDrawing("horizontal")
                V = [InternalStringCache]::GetBoxDrawing("vertical")
            }}
        }
        
        # Use optimized horizontal line generation
        $horizontalLine = $(if ($chars.H -eq "─") {
            [InternalStringCache]::GetSpaces($width - 2) -replace ' ', '─'
        } else {
            $chars.H * ($width - 2)
        })
        
        # Top border
        $this.WriteAt($x, $y, $chars.TL)
        if ($width -gt 2) {
            $this.WriteAt($x + 1, $y, $horizontalLine)
        }
        $this.WriteAt($x + $width - 1, $y, $chars.TR)
        
        # Side borders
        for ($row = 1; $row -lt $height - 1; $row++) {
            $this.WriteAt($x, $y + $row, $chars.V)
            $this.WriteAt($x + $width - 1, $y + $row, $chars.V)
        }
        
        # Bottom border
        if ($height -gt 1) {
            $this.WriteAt($x, $y + $height - 1, $chars.BL)
            if ($width -gt 2) {
                $this.WriteAt($x + 1, $y + $height - 1, $horizontalLine)
            }
            $this.WriteAt($x + $width - 1, $y + $height - 1, $chars.BR)
        }
    }
    
    # Enhanced cursor control
    [void] HideCursor() {
        if ($this.CursorVisible) {
            [Console]::Write([InternalStringCache]::GetAnsiSequence("hidecursor"))
            $this.CursorVisible = $false
        }
    }
    
    [void] ShowCursor() {
        if (-not $this.CursorVisible) {
            [Console]::Write([InternalStringCache]::GetAnsiSequence("showcursor"))
            $this.CursorVisible = $true
        }
    }
    
    # Enhanced frame handling with differential rendering
    [void] BeginFrame() {
        $this._frameTimer.Restart()
        
        # Use pooled StringBuilder for better performance
        if ($this._renderBatch) {
            Return-PooledStringBuilder $this._renderBatch
        }
        $this._renderBatch = Get-PooledStringBuilder 4096
        
        # Only set cursor position if we need to
        if (-not $this._enableDifferentialRendering) {
            [Console]::SetCursorPosition(0, 0)
        }
    }
    
    [void] EndFrame() {
        # Get the current frame content
        $currentBuffer = $this._renderBatch.ToString()
        
        # Only write if content has changed (differential rendering)
        if ($this._enableDifferentialRendering -and $currentBuffer -eq $this._previousBuffer) {
            # No changes, skip the write
        } else {
            # Write batch to terminal
            if ($this._renderBatch.Length -gt 0) {
                try {
                    [Console]::Write($currentBuffer)
                    $this._previousBuffer = $currentBuffer
                } catch {
                    $this._logger.Error("EnhancedTerminal", "EndFrame", "Failed to write to console", @{
                        Error = $_.Exception.Message
                        BatchSize = $this._renderBatch.Length
                    })
                }
            }
        }
        
        # Return StringBuilder to pool
        Return-PooledStringBuilder $this._renderBatch
        $this._renderBatch = $null
        
        # Track performance
        $this._frameTimer.Stop()
        $this._lastFrameTime = $this._frameTimer.Elapsed.TotalMilliseconds
        $this._frameCount++
        
        # Reduced performance logging frequency
        if ($this._frameCount % 300 -eq 0) {  # Every 5 seconds at 60fps
            $perfStats = Get-PerformanceStats
            $this._logger.Debug("EnhancedTerminal", "Performance", "Frame timing and optimization stats", @{
                LastFrameMs = [Math]::Round($this._lastFrameTime, 2)
                FPS = [Math]::Round(1000.0 / $this._lastFrameTime, 1)
                StringBuilderReuseRate = $perfStats.StringBuilderPool.ReuseRate
                ColorCacheSize = $perfStats.ColorCacheSize
            })
        }
    }
    
    # Enable/disable differential rendering
    [void] SetDifferentialRendering([bool]$enabled) {
        $this._enableDifferentialRendering = $enabled
        if (-not $enabled) {
            $this._previousBuffer = ""
        }
    }
    
    # Get enhanced performance statistics
    [hashtable] GetPerformanceStats() {
        $baseStats = @{
            FPS = $this.GetFPS()
            FrameCount = $this._frameCount
            LastFrameTime = $this._lastFrameTime
            DifferentialRendering = $this._enableDifferentialRendering
        }
        
        $perfStats = Get-PerformanceStats
        return $baseStats + $perfStats
    }
}

<#
.SYNOPSIS
Enhanced Colors class with RGB caching and optimization

.DESCRIPTION
Extends the basic Colors class with RGB color support and caching for improved performance.
Maintains backward compatibility while adding new features.
#>
class EnhancedColors : Colors {
    <#
    .SYNOPSIS
    Create RGB foreground color with caching
    
    .PARAMETER r
    Red component (0-255)
    
    .PARAMETER g
    Green component (0-255)
    
    .PARAMETER b
    Blue component (0-255)
    
    .OUTPUTS
    Cached RGB color sequence
    #>
    static [string] RGB([int]$r, [int]$g, [int]$b) {
        return [InternalVT100]::RGB($r, $g, $b)
    }
    
    <#
    .SYNOPSIS
    Create RGB background color with caching
    
    .PARAMETER r
    Red component (0-255)
    
    .PARAMETER g
    Green component (0-255)
    
    .PARAMETER b
    Blue component (0-255)
    
    .OUTPUTS
    Cached RGB background color sequence
    #>
    static [string] BgRGB([int]$r, [int]$g, [int]$b) {
        return [InternalVT100]::RGBBackground($r, $g, $b)
    }
    
    # Predefined theme colors (these will be expanded in the theme system)
    static [string] $Matrix = [EnhancedColors]::RGB(0, 255, 0)
    static [string] $MatrixDim = [EnhancedColors]::RGB(0, 128, 0)
    static [string] $Amber = [EnhancedColors]::RGB(255, 191, 0)
    static [string] $AmberDim = [EnhancedColors]::RGB(204, 153, 0)
    static [string] $Electric = [EnhancedColors]::RGB(0, 255, 255)
    static [string] $ElectricDim = [EnhancedColors]::RGB(0, 128, 128)
}

# Provide easy access to the enhanced terminal
function Get-EnhancedTerminal {
    <#
    .SYNOPSIS
    Get the enhanced terminal instance
    
    .DESCRIPTION
    Returns the singleton enhanced terminal instance with performance optimizations.
    This is a drop-in replacement for the standard terminal.
    
    .OUTPUTS
    EnhancedTerminal instance
    
    .EXAMPLE
    $terminal = Get-EnhancedTerminal
    $terminal.WriteAtRGB(10, 5, "Hello", 255, 0, 0)  # Red text
    #>
    return [EnhancedTerminal]::GetInstance()
}

# Export the enhanced classes for use throughout SpeedTUI
Export-ModuleMember -Function Get-EnhancedTerminal