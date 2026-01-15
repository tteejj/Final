# PMC Screen Management System
# Adapted from praxis-main/Core patterns for persistent screen layout

class PmcScreenBounds {
    [int]$X = 0
    [int]$Y = 0
    [int]$Width = 0
    [int]$Height = 0

    PmcScreenBounds([int]$x, [int]$y, [int]$width, [int]$height) {
        $this.X = $x
        $this.Y = $y
        $this.Width = $width
        $this.Height = $height
    }

    [string] ToString() {
        return "($($this.X),$($this.Y) $($this.Width)x$($this.Height))"
    }
}

class PmcScreenRegions {
    [PmcScreenBounds]$Header
    [PmcScreenBounds]$Content
    [PmcScreenBounds]$Status
    [PmcScreenBounds]$Input
    [PmcScreenBounds]$Full

    PmcScreenRegions([int]$terminalWidth, [int]$terminalHeight) {
        # Calculate regions based on terminal size
        $this.Full = [PmcScreenBounds]::new(0, 0, $terminalWidth, $terminalHeight)
        $this.Header = [PmcScreenBounds]::new(0, 0, $terminalWidth, 3)  # Title + separator
        $this.Input = [PmcScreenBounds]::new(0, $terminalHeight - 2, $terminalWidth, 2)  # Input line + separator
        $this.Status = [PmcScreenBounds]::new($terminalWidth - 30, 1, 30, 1)  # Right side of header
        $this.Content = [PmcScreenBounds]::new(0, 3, $terminalWidth, $terminalHeight - 5)  # Between header and input

        if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
            Write-PmcDebug -Level 3 -Category 'ScreenManager' -Message "Screen regions calculated" -Data @{
                Terminal = "$terminalWidth x $terminalHeight"
                Header = $this.Header.ToString()
                Content = $this.Content.ToString()
                Status = $this.Status.ToString()
                Input = $this.Input.ToString()
            }
        }
    }
}

class PmcScreenManager {
    hidden [PmcScreenRegions]$_regions
    hidden [string]$_lastContent = ""
    hidden [bool]$_needsClear = $true
    hidden [int]$_terminalWidth = 0
    hidden [int]$_terminalHeight = 0

    # VT100 sequences - adapted from praxis patterns
    hidden [string]$_hideCursor = "`e[?25l"
    hidden [string]$_showCursor = "`e[?25h"
    hidden [string]$_clearScreen = "`e[2J"
    hidden [string]$_home = "`e[H"

    PmcScreenManager() {
        $this.UpdateTerminalDimensions()
    }

    # Update terminal dimensions and recalculate regions
    [void] UpdateTerminalDimensions() {
        try {
            $newWidth = [Math]::Max([Console]::WindowWidth, 80)
            $newHeight = [Math]::Max([Console]::WindowHeight, 24)

            if ($newWidth -ne $this._terminalWidth -or $newHeight -ne $this._terminalHeight) {
                $this._terminalWidth = $newWidth
                $this._terminalHeight = $newHeight
                $this._regions = [PmcScreenRegions]::new($newWidth, $newHeight)
                $this._needsClear = $true

                if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
                    Write-PmcDebug -Level 2 -Category 'ScreenManager' -Message "Terminal dimensions updated" -Data @{
                        Width = $newWidth
                        Height = $newHeight
                    }
                }
            }
        } catch {
            if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
                Write-PmcDebug -Level 1 -Category 'ScreenManager' -Message "Failed to get terminal dimensions" -Data @{ Error = $_.ToString() }
            }
            # Fallback to defaults
            if ($this._terminalWidth -eq 0) {
                $this._terminalWidth = 120
                $this._terminalHeight = 30
                $this._regions = [PmcScreenRegions]::new(120, 30)
            }
        }
    }

    # Get current screen regions
    [PmcScreenRegions] GetRegions() {
        $this.UpdateTerminalDimensions()
        return $this._regions
    }

    # Clear entire screen and set up persistent layout
    [void] ClearScreen() {
        Write-Host $this._clearScreen -NoNewline
        Write-Host $this._home -NoNewline
        Write-Host $this._hideCursor -NoNewline
        $this._needsClear = $false
        $this._lastContent = ""

        if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
            Write-PmcDebug -Level 3 -Category 'ScreenManager' -Message "Screen cleared and cursor hidden"
        }
    }

    # Clear only the content region (preserves header/input/status)
    [void] ClearContentRegion() {
        if (-not $this._regions) { $this.UpdateTerminalDimensions() }

        $content = $this._regions.Content
        $clearLine = " " * $content.Width

        for ($y = 0; $y -lt $content.Height; $y++) {
            $this.MoveTo($content.X, $content.Y + $y)
            Write-Host $clearLine -NoNewline
        }

        if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
            Write-PmcDebug -Level 3 -Category 'ScreenManager' -Message "Content region cleared" -Data @{
                Bounds = $content.ToString()
            }
        }
    }

    # Position cursor at specific coordinates
    [void] MoveTo([int]$x, [int]$y) {
        Write-Host "`e[$y;$($x)H" -NoNewline
    }

    # Write text at specific position in a region
    [void] WriteAtPosition([PmcScreenBounds]$region, [int]$offsetX, [int]$offsetY, [string]$text) {
        $actualX = $region.X + $offsetX
        $actualY = $region.Y + $offsetY

        # Bounds checking
        if ($actualX -ge ($region.X + $region.Width) -or $actualY -ge ($region.Y + $region.Height)) {
            if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
                Write-PmcDebug -Level 2 -Category 'ScreenManager' -Message "Text position out of bounds" -Data @{
                    RequestedX = $actualX
                    RequestedY = $actualY
                    RegionBounds = $region.ToString()
                }
            }
            return
        }

        $this.MoveTo($actualX, $actualY)

        # Truncate text if it would exceed region width
        $maxWidth = $region.Width - $offsetX
        if ($text.Length -gt $maxWidth) {
            $text = $text.Substring(0, $maxWidth - 3) + "..."
        }

        Write-Host $text -NoNewline
    }

    # Render header with title and status
    [void] RenderHeader([string]$title, [string]$status = "") {
        if (-not $this._regions) { $this.UpdateTerminalDimensions() }

        # Clear header region
        $header = $this._regions.Header
        $clearLine = " " * $header.Width
        $this.MoveTo($header.X, $header.Y)
        Write-Host $clearLine -NoNewline

        # Write title
        $this.WriteAtPosition($header, 0, 0, $title)

        # Write status on right side
        if ($status) {
            $statusPos = $header.Width - $status.Length - 1
            if ($statusPos -gt $title.Length + 2) {
                $this.WriteAtPosition($header, $statusPos, 0, $status)
            }
        }

        # Draw separator line
        $this.MoveTo($header.X, $header.Y + 1)
        Write-Host ("─" * $header.Width) -NoNewline

        if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
            Write-PmcDebug -Level 3 -Category 'ScreenManager' -Message "Header rendered" -Data @{
                Title = $title
                Status = $status
            }
        }
    }

    # Render input prompt at bottom
    [void] RenderInputPrompt([string]$prompt) {
        if (-not $this._regions) { $this.UpdateTerminalDimensions() }

        $input = $this._regions.Input

        # Draw separator line above input
        $this.MoveTo($input.X, $input.Y)
        Write-Host ("─" * $input.Width) -NoNewline

        # Clear input line
        $this.MoveTo($input.X, $input.Y + 1)
        $clearLine = " " * $input.Width
        Write-Host $clearLine -NoNewline

        # Write prompt
        $this.WriteAtPosition($input, 0, 1, $prompt)

        # Position cursor after prompt for input
        $this.MoveTo($input.X + $prompt.Length, $input.Y + 1)
        Write-Host $this._showCursor -NoNewline

        if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
            Write-PmcDebug -Level 3 -Category 'ScreenManager' -Message "Input prompt rendered" -Data @{
                Prompt = $prompt
            }
        }
    }

    # Show cursor for input
    [void] ShowCursor() {
        Write-Host $this._showCursor -NoNewline
    }

    # Hide cursor for display
    [void] HideCursor() {
        Write-Host $this._hideCursor -NoNewline
    }

    # Get content region for components to render into
    [PmcScreenBounds] GetContentBounds() {
        if (-not $this._regions) { $this.UpdateTerminalDimensions() }
        return $this._regions.Content
    }

    # Set up initial screen layout
    [void] Initialize([string]$title = "PMC — Project Management Console") {
        $this.ClearScreen()
        $this.RenderHeader($title, "")
        $this.RenderInputPrompt("pmc> ")

        if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
            Write-PmcDebug -Level 2 -Category 'ScreenManager' -Message "Screen manager initialized" -Data @{
                Title = $title
                Regions = $this._regions
            }
        }
    }

    # Cleanup on exit
    [void] Cleanup() {
        $this.ShowCursor()
        $this.ClearScreen()
        if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
            Write-PmcDebug -Level 2 -Category 'ScreenManager' -Message "Screen manager cleanup completed"
        }
    }
}

# Global screen manager instance
$Script:PmcScreenManager = [PmcScreenManager]::new()

# Public functions for screen management
function Initialize-PmcScreen {
    param(
        [string]$Title = "PMC — Project Management Console"
    )

    $Script:PmcScreenManager.Initialize($Title)
    if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
        Write-PmcDebug -Level 1 -Category 'ScreenManager' -Message "PMC screen initialized" -Data @{ Title = $Title }
    }
}

function Clear-PmcContentArea {
    $Script:PmcScreenManager.ClearContentRegion()
    if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
        Write-PmcDebug -Level 2 -Category 'ScreenManager' -Message "PMC content area cleared"
    }
}

function Get-PmcContentBounds {
    return $Script:PmcScreenManager.GetContentBounds()
}

function Set-PmcHeader {
    param(
        [string]$Title,
        [string]$Status = ""
    )

    $Script:PmcScreenManager.RenderHeader($Title, $Status)
}

# Update header with dynamic status chips (focus, debug, security)
function Update-PmcHeaderStatus {
    param(
        [string]$Title = "pmc — enhanced project management console"
    )

    $statusParts = @()
    try {
        # Focus context
        if (Get-Command Get-PmcCurrentContext -ErrorAction SilentlyContinue) {
            $ctx = [string](Get-PmcCurrentContext)
            if ($ctx -and $ctx.ToLower() -ne 'inbox') { $statusParts += ("🎯 " + $ctx) }
        }
    } catch {}

    try {
        # Debug level
        if (Get-Command Get-PmcDebugStatus -ErrorAction SilentlyContinue) {
            $dbg = Get-PmcDebugStatus
            if ($dbg -and $dbg.Enabled) { $statusParts += ("DBG:" + ([string]$dbg.Level)) }
        }
    } catch {}

    try {
        # Security mode (simplified)
        if (Get-Command Get-PmcSecurityStatus -ErrorAction SilentlyContinue) {
            $sec = Get-PmcSecurityStatus
            if ($sec) {
                $secStr = $(if ($sec.PathWhitelistEnabled) { 'SEC:ON' } else { 'SEC:OFF' })
                $statusParts += $secStr
            }
        }
    } catch {}

    $statusText = ($statusParts -join '  ')
    Set-PmcHeader -Title $Title -Status $statusText
}

function Set-PmcInputPrompt {
    param(
        [string]$Prompt = "pmc> "
    )

    $Script:PmcScreenManager.RenderInputPrompt($Prompt)
}

function Hide-PmcCursor {
    $Script:PmcScreenManager.HideCursor()
}

function Show-PmcCursor {
    $Script:PmcScreenManager.ShowCursor()
}

function Reset-PmcScreen {
    $Script:PmcScreenManager.Cleanup()
}

function Write-PmcAtPosition {
    param(
        [int]$X,
        [int]$Y,
        [string]$Text
    )

    $contentBounds = Get-PmcContentBounds
    $Script:PmcScreenManager.WriteAtPosition($contentBounds, $X, $Y, $Text)
}

function Clear-CommandOutput {
    Clear-PmcContentArea
    if (Get-Command Write-PmcDebug -ErrorAction SilentlyContinue) {
        Write-PmcDebug -Level 2 -Category 'ScreenManager' -Message "Command output area cleared"
    }
}

# Export screen management functions
Export-ModuleMember -Function Initialize-PmcScreen, Clear-PmcContentArea, Get-PmcContentBounds, Set-PmcHeader, Update-PmcHeaderStatus, Set-PmcInputPrompt, Hide-PmcCursor, Show-PmcCursor, Reset-PmcScreen, Write-PmcAtPosition, Clear-CommandOutput