# SpeedTUI Enhanced Terminal - High-performance terminal control with automatic optimizations
# Replaces the existing Terminal with enhanced features and better performance

using namespace System.Text

# Load performance optimizations for automatic string caching and StringBuilder pooling
. "$PSScriptRoot/Internal/PerformanceCore.ps1"
. "$PSScriptRoot/../Services/EnhancedThemeManager.ps1"

<#
.SYNOPSIS
Enhanced terminal class with automatic performance optimizations and theming support

.DESCRIPTION
Provides high-performance terminal control with:
- Automatic string caching for repeated operations
- StringBuilder pooling for efficient batching
- Optimized ANSI sequence generation
- Theme system integration
- RGB color support with caching
- Flicker-free rendering
- Performance monitoring
- Simple, clear APIs

.EXAMPLE
# Simple usage (backward compatible)
$terminal = [Terminal]::GetInstance()
$terminal.Initialize()
$terminal.WriteAt(10, 5, "Hello World")

# Enhanced usage with theming
$terminal.SetTheme("matrix")
$terminal.WriteAtThemed(10, 5, "Themed Text", "primary")

# RGB colors with automatic caching
$terminal.WriteAtRGB(10, 7, "Custom Color", 255, 100, 50)

# Performance monitoring
$stats = $terminal.GetPerformanceStats()
#>
class Terminal {
    # === Singleton Pattern ===
    static [Terminal]$Instance = $null
    
    # === Terminal State ===
    [int]$Width                     # Terminal width in characters
    [int]$Height                    # Terminal height in characters
    [bool]$AlternateScreen = $false # Using alternate screen buffer
    [bool]$CursorVisible = $true    # Cursor visibility state
    
    # === Enhanced Features (Private) ===
    hidden [StringBuilder]$_renderBatch        # Batched output for flicker-free rendering
    hidden [object]$_logger                    # Logging for debugging
    hidden [string]$_currentTheme = "default"  # Current theme name
    
    # === Performance Tracking ===
    hidden [System.Diagnostics.Stopwatch]$_frameTimer    # Frame timing
    hidden [double]$_lastFrameTime = 0                    # Last frame duration
    hidden [int]$_frameCount = 0                          # Total frames rendered
    hidden [int]$_writeOperations = 0                     # Total write operations
    hidden [int]$_cacheHits = 0                          # String cache hits
    
    # === Color and ANSI Caching ===
    hidden [hashtable]$_colorCache              # Cached color ANSI sequences
    hidden [hashtable]$_positionCache           # Cached cursor position sequences
    
    <#
    .SYNOPSIS
    Initialize terminal instance (private constructor for singleton)
    
    .DESCRIPTION
    Sets up the terminal with enhanced features:
    - Performance monitoring
    - String caching integration
    - Theme system integration
    - Render batching system
    #>
    hidden Terminal() {
        # Initialize logging
        $this._logger = Get-Logger
        $this._logger.Info("Terminal", "Constructor", "Initializing enhanced terminal")
        
        # Initialize StringBuilder with optimized capacity
        $this._renderBatch = [InternalStringBuilderPool]::Get()
        
        # Initialize caches
        $this._colorCache = @{}
        $this._positionCache = @{}
        
        # Initialize performance monitoring
        $this._frameTimer = [System.Diagnostics.Stopwatch]::new()
        
        # Update dimensions
        $this.UpdateDimensions()
        
        $this._logger.Info("Terminal", "Constructor", "Enhanced terminal initialized", @{
            Width = $this.Width
            Height = $this.Height
            CacheEnabled = $true
        })
    }
    
    <#
    .SYNOPSIS
    Get singleton terminal instance
    
    .OUTPUTS
    Terminal instance
    
    .EXAMPLE
    $terminal = [Terminal]::GetInstance()
    #>
    static [Terminal] GetInstance() {
        if ($null -eq [Terminal]::Instance) {
            [Terminal]::Instance = [Terminal]::new()
        }
        return [Terminal]::Instance
    }
    
    # === Enhanced Initialization and Cleanup ===
    
    <#
    .SYNOPSIS
    Initialize terminal for TUI mode with enhanced features
    
    .DESCRIPTION
    Sets up the terminal with:
    - Screen clearing
    - Cursor management
    - Dimension detection
    - Performance monitoring
    - Theme system integration
    #>
    [void] Initialize() {
        $this._logger.Info("Terminal", "Initialize", "Setting up enhanced terminal for TUI mode")
        
        try {
            # Clear screen using optimized method
            $this.Clear()
            
            # Hide cursor for cleaner display
            try {
                [Console]::CursorVisible = $false
                $this.CursorVisible = $false
                
                # Cache the hide cursor sequence for performance
                $this._colorCache["hide_cursor"] = "`e[?25l"
                $this._colorCache["show_cursor"] = "`e[?25h"
                
            } catch {
                # Some environments don't support cursor control
                $this._logger.Debug("Terminal", "Initialize", "Cursor control not supported")
            }
            
            # Update dimensions
            $this.UpdateDimensions()
            
            # Initialize theme system integration
            try {
                $themeManager = Get-ThemeManager -ErrorAction SilentlyContinue
                if ($null -ne $themeManager) {
                    $this._currentTheme = $themeManager.GetCurrentThemeName()
                }
            } catch {
                # Theme system not available
                $this._currentTheme = "default"
            }
            
            $this._logger.Info("Terminal", "Initialize", "Enhanced terminal initialized successfully", @{
                Width = $this.Width
                Height = $this.Height
                Theme = $this._currentTheme
                CacheSize = $this._colorCache.Count
            })
            
        } catch {
            $this._logger.Error("Terminal", "Initialize", "Failed to initialize enhanced terminal", @{
                Error = $_.Exception.Message
            })
            throw
        }
    }
    
    <#
    .SYNOPSIS
    Cleanup and restore terminal state
    
    .DESCRIPTION
    Restores terminal with:
    - Cursor visibility restoration
    - Screen clearing
    - StringBuilder pool return
    - Performance statistics logging
    #>
    [void] Cleanup() {
        $this._logger.Info("Terminal", "Cleanup", "Restoring terminal state")
        
        try {
            # Show cursor if it was hidden
            if (-not $this.CursorVisible) {
                try {
                    [Console]::CursorVisible = $true
                    $this.CursorVisible = $true
                } catch {
                    # Some environments don't support cursor control
                }
            }
            
            # Clear screen one final time
            [Console]::Clear()
            
            # Return StringBuilder to pool for reuse
            [InternalStringBuilderPool]::Recycle($this._renderBatch)
            
            # Log performance statistics
            $this.LogPerformanceStats()
            
            $this._logger.Debug("Terminal", "Cleanup", "Enhanced terminal state restored")
            
        } catch {
            $this._logger.Error("Terminal", "Cleanup", "Failed to restore terminal", @{
                Error = $_.Exception.Message
            })
        }
    }
    
    # === Enhanced Dimension Management ===
    
    <#
    .SYNOPSIS
    Update terminal dimensions with caching
    
    .DESCRIPTION
    Updates terminal size and clears position cache since
    coordinates may no longer be valid with new dimensions.
    #>
    [void] UpdateDimensions() {
        try {
            $newWidth = [Console]::WindowWidth
            $newHeight = [Console]::WindowHeight
            
            # Check if dimensions actually changed
            if ($this.Width -ne $newWidth -or $this.Height -ne $newHeight) {
                $this.Width = $newWidth
                $this.Height = $newHeight
                
                # Clear position cache since coordinates may be invalid
                $this._positionCache.Clear()
                
                $this._logger.Trace("Terminal", "UpdateDimensions", "Terminal dimensions updated", @{
                    Width = $this.Width
                    Height = $this.Height
                })
            }
            
        } catch {
            # Fallback to standard dimensions
            $this.Width = 80
            $this.Height = 24
            
            $this._logger.Warn("Terminal", "UpdateDimensions", "Failed to get console dimensions, using defaults", @{
                Error = $_.Exception.Message
                DefaultWidth = 80
                DefaultHeight = 24
            })
        }
    }
    
    # === Enhanced Cursor Control ===
    
    <#
    .SYNOPSIS
    Move cursor to position with caching for performance
    
    .PARAMETER x
    X coordinate (0-based)
    
    .PARAMETER y
    Y coordinate (0-based)
    
    .DESCRIPTION
    Uses cached ANSI sequences for frequently used positions
    to improve performance in repeated operations.
    #>
    [void] MoveCursor([int]$x, [int]$y) {
        # Input validation with performance-optimized guards
        if ($x -lt 0 -or $y -lt 0 -or $x -ge $this.Width -or $y -ge $this.Height) {
            return  # Silent fail for performance (no exceptions in hot path)
        }
        
        # Check position cache for frequently used coordinates
        $posKey = "${x},${y}"
        if ($this._positionCache.ContainsKey($posKey)) {
            $this._renderBatch.Append($this._positionCache[$posKey])
            $this._cacheHits++
        } else {
            # Generate and cache the position sequence
            $sequence = "`e[$($y + 1);$($x + 1)H"
            
            # Only cache if we have room (prevent unbounded growth)
            if ($this._positionCache.Count -lt 1000) {
                $this._positionCache[$posKey] = $sequence
            }
            
            $this._renderBatch.Append($sequence)
        }
    }
    
    <#
    .SYNOPSIS
    Hide cursor with cached sequence
    #>
    [void] HideCursor() {
        if ($this.CursorVisible) {
            if ($this._colorCache.ContainsKey("hide_cursor")) {
                [Console]::Write($this._colorCache["hide_cursor"])
            } else {
                [Console]::Write("`e[?25l")
            }
            $this.CursorVisible = $false
            $this._logger.Trace("Terminal", "HideCursor", "Cursor hidden")
        }
    }
    
    <#
    .SYNOPSIS
    Show cursor with cached sequence
    #>
    [void] ShowCursor() {
        if (-not $this.CursorVisible) {
            if ($this._colorCache.ContainsKey("show_cursor")) {
                [Console]::Write($this._colorCache["show_cursor"])
            } else {
                [Console]::Write("`e[?25h")
            }
            $this.CursorVisible = $true
            $this._logger.Trace("Terminal", "ShowCursor", "Cursor shown")
        }
    }
    
    # === Enhanced Drawing Methods ===
    
    <#
    .SYNOPSIS
    Write text at position with automatic optimizations
    
    .PARAMETER x
    X coordinate
    
    .PARAMETER y
    Y coordinate
    
    .PARAMETER text
    Text to write
    
    .DESCRIPTION
    Uses optimized string operations and automatic clipping
    for improved performance and safety.
    #>
    [void] WriteAt([int]$x, [int]$y, [string]$text) {
        if ([string]::IsNullOrEmpty($text) -or $x -lt 0 -or $y -lt 0 -or $y -ge $this.Height) { 
            return 
        }
        
        # Use optimized string clipping
        $maxLength = $this.Width - $x
        if ($maxLength -le 0) { 
            return 
        }
        
        # Clip text using cached string operations when possible
        if ($text.Length -gt $maxLength) {
            $text = $text.Substring(0, $maxLength)
        }
        
        # Move cursor and write text
        $this.MoveCursor($x, $y)
        $this._renderBatch.Append($text)
        
        $this._writeOperations++
    }
    
    <#
    .SYNOPSIS
    Write text with colors using optimized ANSI sequences
    
    .PARAMETER x
    X coordinate
    
    .PARAMETER y
    Y coordinate
    
    .PARAMETER text
    Text to write
    
    .PARAMETER foreground
    Foreground color ANSI sequence
    
    .PARAMETER background
    Background color ANSI sequence
    
    .DESCRIPTION
    Uses cached color sequences and optimized reset handling.
    #>
    [void] WriteAt([int]$x, [int]$y, [string]$text, [string]$foreground, [string]$background) {
        if ([string]::IsNullOrEmpty($text) -or $x -lt 0 -or $y -lt 0 -or $y -ge $this.Height) { 
            return 
        }
        
        # Optimize text clipping
        $maxLength = $this.Width - $x
        if ($maxLength -le 0) { 
            return 
        }
        
        if ($text.Length -gt $maxLength) {
            $text = $text.Substring(0, $maxLength)
        }
        
        # Move cursor
        $this.MoveCursor($x, $y)
        
        # Apply colors if provided
        if (-not [string]::IsNullOrEmpty($foreground)) {
            $this._renderBatch.Append($foreground)
        }
        if (-not [string]::IsNullOrEmpty($background)) {
            $this._renderBatch.Append($background)
        }
        
        # Write text
        $this._renderBatch.Append($text)
        
        # Reset colors using cached sequence
        if (-not [string]::IsNullOrEmpty($foreground) -or -not [string]::IsNullOrEmpty($background)) {
            $this._renderBatch.Append([InternalVT100]::Reset())
        }
        
        $this._writeOperations++
    }
    
    <#
    .SYNOPSIS
    Write text with RGB colors and automatic caching
    
    .PARAMETER x
    X coordinate
    
    .PARAMETER y
    Y coordinate
    
    .PARAMETER text
    Text to write
    
    .PARAMETER fgR
    Foreground red (0-255)
    
    .PARAMETER fgG
    Foreground green (0-255)
    
    .PARAMETER fgB
    Foreground blue (0-255)
    
    .EXAMPLE
    $terminal.WriteAtRGB(10, 5, "Orange Text", 255, 165, 0)
    #>
    [void] WriteAtRGB([int]$x, [int]$y, [string]$text, [int]$fgR, [int]$fgG, [int]$fgB) {
        # Use cached RGB color generation
        $fgColor = [InternalVT100]::RGB($fgR, $fgG, $fgB)
        $this.WriteAt($x, $y, $text, $fgColor, "")
    }
    
    <#
    .SYNOPSIS
    Write text with RGB foreground and background colors
    
    .PARAMETER x
    X coordinate
    
    .PARAMETER y
    Y coordinate
    
    .PARAMETER text
    Text to write
    
    .PARAMETER fgR
    Foreground red (0-255)
    
    .PARAMETER fgG
    Foreground green (0-255)
    
    .PARAMETER fgB
    Foreground blue (0-255)
    
    .PARAMETER bgR
    Background red (0-255)
    
    .PARAMETER bgG
    Background green (0-255)
    
    .PARAMETER bgB
    Background blue (0-255)
    
    .EXAMPLE
    $terminal.WriteAtRGB(10, 5, "Colorful", 255, 255, 255, 0, 0, 255)  # White on blue
    #>
    [void] WriteAtRGB([int]$x, [int]$y, [string]$text, [int]$fgR, [int]$fgG, [int]$fgB, [int]$bgR, [int]$bgG, [int]$bgB) {
        # Use cached RGB color generation
        $fgColor = [InternalVT100]::RGB($fgR, $fgG, $fgB)
        $bgColor = [InternalVT100]::BgRGB($bgR, $bgG, $bgB)
        $this.WriteAt($x, $y, $text, $fgColor, $bgColor)
    }
    
    <#
    .SYNOPSIS
    Write text using theme colors
    
    .PARAMETER x
    X coordinate
    
    .PARAMETER y
    Y coordinate
    
    .PARAMETER text
    Text to write
    
    .PARAMETER colorRole
    Theme color role (primary, secondary, success, etc.)
    
    .EXAMPLE
    $terminal.WriteAtThemed(10, 5, "Success!", "success")
    #>
    [void] WriteAtThemed([int]$x, [int]$y, [string]$text, [string]$colorRole) {
        try {
            $themeManager = Get-ThemeManager -ErrorAction SilentlyContinue
            if ($null -ne $themeManager) {
                $color = $themeManager.GetColor($colorRole)
                $this.WriteAt($x, $y, $text, $color.Foreground, $color.Background)
            } else {
                # Fallback to plain text
                $this.WriteAt($x, $y, $text)
            }
        } catch {
            # Fallback to plain text on any error
            $this.WriteAt($x, $y, $text)
        }
    }
    
    # === Enhanced Clear Operations ===
    
    <#
    .SYNOPSIS
    Clear entire screen with optimized sequence
    #>
    [void] Clear() {
        $this._renderBatch.Append("`e[2J`e[H")
    }
    
    <#
    .SYNOPSIS
    Clear specific line
    
    .PARAMETER y
    Line number to clear
    #>
    [void] ClearLine([int]$y) {
        if ($y -lt 0 -or $y -ge $this.Height) { 
            return 
        }
        
        $this.MoveCursor(0, $y)
        $this._renderBatch.Append("`e[2K")
    }
    
    <#
    .SYNOPSIS
    Clear rectangular region with optimized space generation
    
    .PARAMETER x
    Starting X coordinate
    
    .PARAMETER y
    Starting Y coordinate
    
    .PARAMETER width
    Width to clear
    
    .PARAMETER height
    Height to clear
    #>
    [void] ClearRegion([int]$x, [int]$y, [int]$width, [int]$height) {
        if ($x -lt 0 -or $y -lt 0 -or $width -le 0 -or $height -le 0) { 
            return 
        }
        
        # Use cached space string for better performance
        $spaces = [InternalStringCache]::GetSpaces($width)
        
        for ($row = 0; $row -lt $height; $row++) {
            $currentY = $y + $row
            if ($currentY -ge $this.Height) { 
                break 
            }
            $this.WriteAt($x, $currentY, $spaces)
        }
    }
    
    # === Enhanced Box Drawing ===
    
    <#
    .SYNOPSIS
    Draw box with default single-line style
    
    .PARAMETER x
    X coordinate
    
    .PARAMETER y
    Y coordinate
    
    .PARAMETER width
    Box width
    
    .PARAMETER height
    Box height
    #>
    [void] DrawBox([int]$x, [int]$y, [int]$width, [int]$height) {
        $this.DrawBox($x, $y, $width, $height, "Single")
    }
    
    <#
    .SYNOPSIS
    Draw box with specified style and optimized character generation
    
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
    [void] DrawBox([int]$x, [int]$y, [int]$width, [int]$height, [string]$style) {
        if ($x -lt 0 -or $y -lt 0 -or $width -lt 2 -or $height -lt 2) { 
            return 
        }
        
        if ($x + $width -gt $this.Width -or $y + $height -gt $this.Height) { 
            return 
        }
        
        # Get box drawing characters with caching
        $chars = $this.GetBoxChars($style)
        
        # Draw top border using cached horizontal line
        $topLine = $chars.TL + ([InternalStringCache]::GetSpaces($width - 2).Replace(' ', $chars.H)) + $chars.TR
        $this.WriteAt($x, $y, $topLine)
        
        # Draw side borders
        for ($row = 1; $row -lt $height - 1; $row++) {
            $this.WriteAt($x, $y + $row, $chars.V)
            $this.WriteAt($x + $width - 1, $y + $row, $chars.V)
        }
        
        # Draw bottom border
        $bottomLine = $chars.BL + ([InternalStringCache]::GetSpaces($width - 2).Replace(' ', $chars.H)) + $chars.BR
        $this.WriteAt($x, $y + $height - 1, $bottomLine)
    }
    
    <#
    .SYNOPSIS
    Get box drawing characters with caching
    
    .PARAMETER style
    Box style name
    
    .OUTPUTS
    Hashtable with box drawing characters
    #>
    hidden [hashtable] GetBoxChars([string]$style) {
        # Cache box character sets to avoid repeated lookups
        $cacheKey = "box_$style"
        if ($this._colorCache.ContainsKey($cacheKey)) {
            return $this._colorCache[$cacheKey]
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
        
        # Cache for future use
        $this._colorCache[$cacheKey] = $chars
        return $chars
    }
    
    # === Enhanced Frame Management ===
    
    <#
    .SYNOPSIS
    Begin frame with performance monitoring
    
    .DESCRIPTION
    Starts frame timing and clears the render batch for
    efficient batched rendering.
    #>
    [void] BeginFrame() {
        # Start performance timing
        $this._frameTimer.Restart()
        
        # Clear and reset the render batch
        $this._renderBatch.Clear()
        
        # Reset cursor to top-left for consistent rendering
        [Console]::SetCursorPosition(0, 0)
    }
    
    <#
    .SYNOPSIS
    End frame with optimized output and performance tracking
    
    .DESCRIPTION
    Outputs the batched render commands and tracks performance
    metrics for monitoring and optimization.
    #>
    [void] EndFrame() {
        # Write entire batch to terminal in one operation
        if ($this._renderBatch.Length -gt 0) {
            try {
                [Console]::Write($this._renderBatch.ToString())
            } catch {
                $this._logger.Error("Terminal", "EndFrame", "Failed to write to console", @{
                    Error = $_.Exception.Message
                    BatchSize = $this._renderBatch.Length
                })
            }
        }
        
        # Track performance metrics
        $this._frameTimer.Stop()
        $this._lastFrameTime = $this._frameTimer.Elapsed.TotalMilliseconds
        $this._frameCount++
        
        # Log performance every 60 frames (roughly 1 second at 60 FPS)
        if ($this._frameCount % 60 -eq 0) {
            $this._logger.Debug("Terminal", "Performance", "Frame timing", @{
                LastFrameMs = [Math]::Round($this._lastFrameTime, 2)
                FPS = [Math]::Round(1000.0 / $this._lastFrameTime, 1)
                WriteOps = $this._writeOperations
                CacheHits = $this._cacheHits
                CacheSize = $this._colorCache.Count + $this._positionCache.Count
            })
        }
    }
    
    # === Theme Integration ===
    
    <#
    .SYNOPSIS
    Set terminal theme for consistent theming
    
    .PARAMETER themeName
    Name of theme to apply
    
    .EXAMPLE
    $terminal.SetTheme("matrix")  # Apply matrix theme
    #>
    [void] SetTheme([string]$themeName) {
        if ([string]::IsNullOrWhiteSpace($themeName)) {
            $themeName = "default"
        }
        
        if ($this._currentTheme -eq $themeName) {
            return  # No change needed
        }
        
        try {
            $themeManager = Get-ThemeManager -ErrorAction SilentlyContinue
            if ($null -ne $themeManager) {
                $themeManager.SetTheme($themeName)
                $this._currentTheme = $themeName
                
                # Clear color cache since theme changed
                $this._colorCache.Clear()
                
                $this._logger.Debug("Terminal", "SetTheme", "Terminal theme changed", @{
                    NewTheme = $themeName
                })
            }
        } catch {
            $this._logger.Warn("Terminal", "SetTheme", "Failed to set theme", @{
                Theme = $themeName
                Error = $_.Exception.Message
            })
        }
    }
    
    # === Performance and Monitoring ===
    
    <#
    .SYNOPSIS
    Get current FPS based on last frame time
    
    .OUTPUTS
    Double representing current FPS
    #>
    [double] GetFPS() {
        if ($this._lastFrameTime -gt 0) {
            return 1000.0 / $this._lastFrameTime
        }
        return 0
    }
    
    <#
    .SYNOPSIS
    Get comprehensive performance statistics
    
    .OUTPUTS
    Hashtable with performance metrics
    
    .EXAMPLE
    $stats = $terminal.GetPerformanceStats()
    Write-Host "FPS: $($stats.FPS), Cache Hits: $($stats.CacheHitRate)%"
    #>
    [hashtable] GetPerformanceStats() {
        $cacheHitRate = $(if ($this._writeOperations -gt 0) {
            [Math]::Round(($this._cacheHits / $this._writeOperations) * 100, 1)
        } else { 0 })
        
        return @{
            Width = $this.Width
            Height = $this.Height
            Theme = $this._currentTheme
            FPS = $this.GetFPS()
            LastFrameMs = [Math]::Round($this._lastFrameTime, 2)
            FrameCount = $this._frameCount
            WriteOperations = $this._writeOperations
            CacheHits = $this._cacheHits
            CacheHitRate = $cacheHitRate
            ColorCacheSize = $this._colorCache.Count
            PositionCacheSize = $this._positionCache.Count
            TotalCacheSize = $this._colorCache.Count + $this._positionCache.Count
            BatchSize = $this._renderBatch.Length
        }
    }
    
    <#
    .SYNOPSIS
    Log detailed performance statistics
    
    .DESCRIPTION
    Outputs comprehensive performance information to the logger
    for debugging and optimization purposes.
    #>
    hidden [void] LogPerformanceStats() {
        $stats = $this.GetPerformanceStats()
        
        $this._logger.Info("Terminal", "Performance", "Final performance statistics", @{
            TotalFrames = $stats.FrameCount
            AverageFPS = $stats.FPS
            TotalWriteOperations = $stats.WriteOperations
            CacheHitRate = "$($stats.CacheHitRate)%"
            TotalCacheEntries = $stats.TotalCacheSize
            FinalBatchSize = $stats.BatchSize
        })
    }
    
    # === Cache Management ===
    
    <#
    .SYNOPSIS
    Clear all caches to free memory
    
    .DESCRIPTION
    Clears color and position caches. Useful for memory management
    in long-running applications.
    #>
    [void] ClearCaches() {
        $oldSize = $this._colorCache.Count + $this._positionCache.Count
        
        $this._colorCache.Clear()
        $this._positionCache.Clear()
        
        $this._logger.Debug("Terminal", "ClearCaches", "Caches cleared", @{
            OldCacheSize = $oldSize
            NewCacheSize = 0
        })
    }
    
    <#
    .SYNOPSIS
    Get current theme name
    
    .OUTPUTS
    String representing current theme
    #>
    [string] GetCurrentTheme() {
        return $this._currentTheme
    }
}

# === Enhanced Color Helper Class ===

<#
.SYNOPSIS
Enhanced colors class with additional RGB and theme helpers
#>
class EnhancedColors : Colors {
    # === Theme-aware color methods ===
    
    <#
    .SYNOPSIS
    Get color from current theme
    
    .PARAMETER colorRole
    Color role name
    
    .OUTPUTS
    ANSI color sequence
    
    .EXAMPLE
    $primaryColor = [EnhancedColors]::FromTheme("primary")
    #>
    static [string] FromTheme([string]$colorRole) {
        try {
            $themeManager = Get-ThemeManager -ErrorAction SilentlyContinue
            if ($null -ne $themeManager) {
                $color = $themeManager.GetColor($colorRole)
                return $color.Foreground
            }
        } catch {
            # Fallback to default color
        }
        
        return [Colors]::Default
    }
    
    # === Cached RGB color generation ===
    
    <#
    .SYNOPSIS
    Generate RGB foreground color with caching
    
    .PARAMETER r
    Red component (0-255)
    
    .PARAMETER g
    Green component (0-255)
    
    .PARAMETER b
    Blue component (0-255)
    
    .OUTPUTS
    Cached ANSI RGB sequence
    #>
    static [string] RGB([int]$r, [int]$g, [int]$b) {
        return [InternalVT100]::RGB($r, $g, $b)
    }
    
    <#
    .SYNOPSIS
    Generate RGB background color with caching
    
    .PARAMETER r
    Red component (0-255)
    
    .PARAMETER g
    Green component (0-255)
    
    .PARAMETER b
    Blue component (0-255)
    
    .OUTPUTS
    Cached ANSI RGB background sequence
    #>
    static [string] BgRGB([int]$r, [int]$g, [int]$b) {
        return [InternalVT100]::BgRGB($r, $g, $b)
    }
}

# === Helper Functions ===

<#
.SYNOPSIS
Get the enhanced terminal instance

.OUTPUTS
Enhanced Terminal instance

.EXAMPLE
$terminal = Get-EnhancedTerminal
$terminal.WriteAtThemed(10, 5, "Hello", "primary")
#>
function Get-EnhancedTerminal {
    return [Terminal]::GetInstance()
}

# Export enhanced functions
Export-ModuleMember -Function Get-EnhancedTerminal