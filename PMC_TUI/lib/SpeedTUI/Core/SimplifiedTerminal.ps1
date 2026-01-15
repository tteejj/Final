# SpeedTUI Simplified Terminal - Minimal terminal control with Praxis-style performance
# Strips out unnecessary complexity while keeping essential functionality

using namespace System.Text

# Load performance optimizations
. "$PSScriptRoot/Internal/PerformanceCore.ps1"

<#
.SYNOPSIS
Simplified terminal class focused on performance

.DESCRIPTION
Provides minimal terminal control with:
- Direct console output
- No complex caching or batching
- Simple position and color methods
- No unnecessary overhead

.EXAMPLE
$terminal = [SimplifiedTerminal]::GetInstance()
$terminal.Initialize()
$terminal.WriteAt(10, 5, "Hello World")
#>
class SimplifiedTerminal {
    # Singleton instance
    static [SimplifiedTerminal]$Instance = $null
    
    # Basic state
    [int]$Width
    [int]$Height
    [bool]$CursorVisible = $true
    
    # Private constructor
    hidden SimplifiedTerminal() {
        $this.UpdateDimensions()
    }
    
    # Get singleton instance
    static [SimplifiedTerminal] GetInstance() {
        if ($null -eq [SimplifiedTerminal]::Instance) {
            [SimplifiedTerminal]::Instance = [SimplifiedTerminal]::new()
        }
        return [SimplifiedTerminal]::Instance
    }
    
    # Initialize terminal
    [void] Initialize() {
        # Clear screen
        [Console]::Clear()
        
        # Hide cursor
        try {
            [Console]::CursorVisible = $false
            $this.CursorVisible = $false
        } catch {
            # Ignore cursor errors
        }
        
        # Update dimensions
        $this.UpdateDimensions()
    }
    
    # Cleanup terminal
    [void] Cleanup() {
        # Restore cursor
        try {
            [Console]::CursorVisible = $true
            $this.CursorVisible = $true
        } catch {
            # Ignore cursor errors
        }
        
        # Clear screen
        [Console]::Clear()
    }
    
    # Update terminal dimensions
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
    
    # Clear screen
    [void] Clear() {
        [Console]::Clear()
        [Console]::SetCursorPosition(0, 0)
    }
    
    # Write at position
    [void] WriteAt([int]$x, [int]$y, [string]$text) {
        if ([string]::IsNullOrEmpty($text)) { return }
        
        # Bounds check
        if ($x -lt 0 -or $y -lt 0 -or $x -ge $this.Width -or $y -ge $this.Height) {
            return
        }
        
        # Position and write
        [Console]::SetCursorPosition($x, $y)
        [Console]::Write($text)
    }
    
    # Write with color
    [void] WriteAtColor([int]$x, [int]$y, [string]$text, [string]$foreground, [string]$background = "") {
        if ([string]::IsNullOrEmpty($text)) { return }
        
        # Bounds check
        if ($x -lt 0 -or $y -lt 0 -or $x -ge $this.Width -or $y -ge $this.Height) {
            return
        }
        
        # Build colored text
        $colored = $foreground
        if (-not [string]::IsNullOrEmpty($background)) {
            $colored += $background
        }
        $colored += $text + [InternalVT100]::Reset()
        
        # Position and write
        [Console]::SetCursorPosition($x, $y)
        [Console]::Write($colored)
    }
    
    # Fill area with character
    [void] FillArea([int]$x, [int]$y, [int]$width, [int]$height, [char]$ch) {
        $line = [string]::new($ch, $width)
        
        for ($row = 0; $row -lt $height; $row++) {
            $this.WriteAt($x, $y + $row, $line)
        }
    }
    
    # Set cursor position
    [void] SetCursorPosition([int]$x, [int]$y) {
        if ($x -ge 0 -and $y -ge 0 -and $x -lt $this.Width -and $y -lt $this.Height) {
            [Console]::SetCursorPosition($x, $y)
        }
    }
    
    # Show/hide cursor
    [void] ShowCursor([bool]$visible) {
        try {
            [Console]::CursorVisible = $visible
            $this.CursorVisible = $visible
        } catch {
            # Ignore cursor errors
        }
    }
}