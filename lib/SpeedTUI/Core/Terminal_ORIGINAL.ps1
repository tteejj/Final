# SpeedTUI Terminal - Direct terminal control with flicker-free rendering

class Terminal {
    # Singleton instance
    static [Terminal]$Instance = $null
    
    # Terminal state
    [int]$Width
    [int]$Height
    [bool]$AlternateScreen = $false
    [bool]$CursorVisible = $true
    hidden [string]$_currentBuffer = ""
    hidden [System.Text.StringBuilder]$_renderBatch
    hidden [object]$_logger
    
    # Performance tracking
    hidden [System.Diagnostics.Stopwatch]$_frameTimer
    hidden [double]$_lastFrameTime = 0
    hidden [int]$_frameCount = 0
    
    hidden Terminal() {
        $this._logger = Get-Logger
        $this._logger.Info("Terminal", "Constructor", "Initializing Terminal")
        
        $this._renderBatch = [System.Text.StringBuilder]::new(4096)
        $this._frameTimer = [System.Diagnostics.Stopwatch]::new()
        $this.UpdateDimensions()
    }
    
    static [Terminal] GetInstance() {
        if ($null -eq [Terminal]::Instance) {
            [Terminal]::Instance = [Terminal]::new()
        }
        return [Terminal]::Instance
    }
    
    # Initialize terminal for TUI mode
    [void] Initialize() {
        $this._logger.Info("Terminal", "Initialize", "Setting up terminal for TUI mode")
        
        try {
            # Simple initialization - just clear screen and hide cursor
            [Console]::Clear()
            
            # Hide cursor for cleaner display
            try {
                [Console]::CursorVisible = $false
                $this.CursorVisible = $false
            } catch {
                # Some environments don't support cursor control
                $this._logger.Debug("Terminal", "Initialize", "Cursor control not supported")
            }
            
            # Update dimensions
            $this.UpdateDimensions()
            
            $this._logger.Info("Terminal", "Initialize", "Terminal initialized", @{
                Width = $this.Width
                Height = $this.Height
            })
        } catch {
            $this._logger.Error("Terminal", "Initialize", "Failed to initialize terminal", @{
                Error = $_.Exception.Message
            })
            throw
        }
    }
    
    # Restore terminal to normal mode
    [void] Cleanup() {
        $this._logger.Info("Terminal", "Cleanup", "Restoring terminal state")
        
        try {
            # Restore cursor visibility
            try {
                [Console]::CursorVisible = $true
                $this.CursorVisible = $true
            } catch {
                # Some environments don't support cursor control
            }
            
            # Clear screen one more time
            [Console]::Clear()
            
            $this._logger.Debug("Terminal", "Cleanup", "Terminal state restored")
        } catch {
            $this._logger.Error("Terminal", "Cleanup", "Failed to restore terminal", @{
                Error = $_.Exception.Message
            })
        }
    }
    
    # Update terminal dimensions
    [void] UpdateDimensions() {
        try {
            $this.Width = [Console]::WindowWidth
            $this.Height = [Console]::WindowHeight
            
            $this._logger.Trace("Terminal", "UpdateDimensions", "Terminal dimensions updated", @{
                Width = $this.Width
                Height = $this.Height
            })
        } catch {
            # Fallback dimensions
            $this.Width = 80
            $this.Height = 24
            
            $this._logger.Warn("Terminal", "UpdateDimensions", "Failed to get console dimensions, using defaults", @{
                Error = $_.Exception.Message
            })
        }
    }
    
    # Cursor control
    [void] MoveCursor([int]$x, [int]$y) {
        [Guard]::NonNegative($x, "x")
        [Guard]::NonNegative($y, "y")
        [Guard]::InRange($x, 0, $this.Width - 1, "x")
        [Guard]::InRange($y, 0, $this.Height - 1, "y")
        
        $this._renderBatch.Append("`e[$($y + 1);$($x + 1)H")
    }
    
    [void] HideCursor() {
        if ($this.CursorVisible) {
            [Console]::Write("`e[?25l")
            $this.CursorVisible = $false
            $this._logger.Trace("Terminal", "HideCursor", "Cursor hidden")
        }
    }
    
    [void] ShowCursor() {
        if (-not $this.CursorVisible) {
            [Console]::Write("`e[?25h")
            $this.CursorVisible = $true
            $this._logger.Trace("Terminal", "ShowCursor", "Cursor shown")
        }
    }
    
    # Drawing primitives
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
        
        # Reset colors
        if ($foreground -or $background) {
            $this._renderBatch.Append("`e[0m")
        }
    }
    
    # Clear operations
    [void] Clear() {
        $this._renderBatch.Append("`e[2J`e[H")
    }
    
    [void] ClearLine([int]$y) {
        [Guard]::InRange($y, 0, $this.Height - 1, "y")
        $this.MoveCursor(0, $y)
        $this._renderBatch.Append("`e[2K")
    }
    
    [void] ClearRegion([int]$x, [int]$y, [int]$width, [int]$height) {
        [Guard]::NonNegative($x, "x")
        [Guard]::NonNegative($y, "y")
        [Guard]::Positive($width, "width")
        [Guard]::Positive($height, "height")
        
        $spaces = " " * $width
        for ($row = 0; $row -lt $height; $row++) {
            $currentY = $y + $row
            if ($currentY -ge $this.Height) { break }
            $this.WriteAt($x, $currentY, $spaces)
        }
    }
    
    # Box drawing
    [void] DrawBox([int]$x, [int]$y, [int]$width, [int]$height) {
        $this.DrawBox($x, $y, $width, $height, "Single")
    }
    
    [void] DrawBox([int]$x, [int]$y, [int]$width, [int]$height, [string]$style) {
        [Guard]::NonNegative($x, "x")
        [Guard]::NonNegative($y, "y")
        [Guard]::InRange($width, 2, $this.Width - $x, "width")
        [Guard]::InRange($height, 2, $this.Height - $y, "height")
        
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
        $this.WriteAt($x, $y, $chars.TL)
        $this.WriteAt($x + 1, $y, $chars.H * ($width - 2))
        $this.WriteAt($x + $width - 1, $y, $chars.TR)
        
        # Side borders
        for ($row = 1; $row -lt $height - 1; $row++) {
            $this.WriteAt($x, $y + $row, $chars.V)
            $this.WriteAt($x + $width - 1, $y + $row, $chars.V)
        }
        
        # Bottom border
        $this.WriteAt($x, $y + $height - 1, $chars.BL)
        $this.WriteAt($x + 1, $y + $height - 1, $chars.H * ($width - 2))
        $this.WriteAt($x + $width - 1, $y + $height - 1, $chars.BR)
    }
    
    # Performance tracking
    [void] BeginFrame() {
        $this._frameTimer.Restart()
        $this._renderBatch.Clear()
        # Move cursor to top-left for each frame
        [Console]::SetCursorPosition(0, 0)
    }
    
    [void] EndFrame() {
        # Write batch to terminal
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
        
        # Track performance
        $this._frameTimer.Stop()
        $this._lastFrameTime = $this._frameTimer.Elapsed.TotalMilliseconds
        $this._frameCount++
        
        if ($this._frameCount % 60 -eq 0) {
            $this._logger.Debug("Terminal", "Performance", "Frame timing", @{
                LastFrameMs = [Math]::Round($this._lastFrameTime, 2)
                FPS = [Math]::Round(1000.0 / $this._lastFrameTime, 1)
            })
        }
    }
    
    # Get current FPS
    [double] GetFPS() {
        if ($this._lastFrameTime -gt 0) {
            return 1000.0 / $this._lastFrameTime
        }
        return 0
    }
}

# ANSI color helpers
class Colors {
    # Basic colors
    static [string] $Black = "`e[30m"
    static [string] $Red = "`e[31m"
    static [string] $Green = "`e[32m"
    static [string] $Yellow = "`e[33m"
    static [string] $Blue = "`e[34m"
    static [string] $Magenta = "`e[35m"
    static [string] $Cyan = "`e[36m"
    static [string] $White = "`e[37m"
    static [string] $Default = "`e[39m"
    
    # Bright colors
    static [string] $BrightBlack = "`e[90m"
    static [string] $BrightRed = "`e[91m"
    static [string] $BrightGreen = "`e[92m"
    static [string] $BrightYellow = "`e[93m"
    static [string] $BrightBlue = "`e[94m"
    static [string] $BrightMagenta = "`e[95m"
    static [string] $BrightCyan = "`e[96m"
    static [string] $BrightWhite = "`e[97m"
    
    # Background colors
    static [string] $BgBlack = "`e[40m"
    static [string] $BgRed = "`e[41m"
    static [string] $BgGreen = "`e[42m"
    static [string] $BgYellow = "`e[43m"
    static [string] $BgBlue = "`e[44m"
    static [string] $BgMagenta = "`e[45m"
    static [string] $BgCyan = "`e[46m"
    static [string] $BgWhite = "`e[47m"
    static [string] $BgDefault = "`e[49m"
    
    # Styles
    static [string] $Reset = "`e[0m"
    static [string] $Bold = "`e[1m"
    static [string] $Dim = "`e[2m"
    static [string] $Italic = "`e[3m"
    static [string] $Underline = "`e[4m"
    static [string] $Blink = "`e[5m"
    static [string] $Reverse = "`e[7m"
    static [string] $Hidden = "`e[8m"
    static [string] $Strike = "`e[9m"
    
    # RGB color
    static [string] RGB([int]$r, [int]$g, [int]$b) {
        [Guard]::InRange($r, 0, 255, "r")
        [Guard]::InRange($g, 0, 255, "g")
        [Guard]::InRange($b, 0, 255, "b")
        return "`e[38;2;$r;$g;${b}m"
    }
    
    static [string] BgRGB([int]$r, [int]$g, [int]$b) {
        [Guard]::InRange($r, 0, 255, "r")
        [Guard]::InRange($g, 0, 255, "g")
        [Guard]::InRange($b, 0, 255, "b")
        return "`e[48;2;$r;$g;${b}m"
    }
}