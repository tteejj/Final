using namespace System.Text

# PmcStatusBar - Status information display at bottom of screen
# Shows current status, mode, notifications, and system info

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Status bar widget for bottom-of-screen status display

.DESCRIPTION
PmcStatusBar displays:
- Left section: Primary status message
- Center section: Mode or context
- Right section: System info (time, notifications, etc.)

.EXAMPLE
$statusBar = [PmcStatusBar]::new()
$statusBar.SetLeftText("15 tasks loaded")
$statusBar.SetCenterText("VIEW MODE")
$statusBar.SetRightText("10:30 AM")
#>
class PmcStatusBar : PmcWidget {
    # === Properties ===
    [string]$LeftText = ""
    [string]$CenterText = ""
    [string]$RightText = ""
    [bool]$UseBackground = $true  # Fill with background color

    # === Constructor ===
    PmcStatusBar() : base("StatusBar") {
        $this.Height = 1
        $this.Width = 80
    }

    # === Configuration ===

    <#
    .SYNOPSIS
    Set left section text

    .PARAMETER text
    Text to display on left side
    #>
    [void] SetLeftText([string]$text) {
        $this.LeftText = $text
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Set center section text

    .PARAMETER text
    Text to display in center
    #>
    [void] SetCenterText([string]$text) {
        $this.CenterText = $text
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Set right section text

    .PARAMETER text
    Text to display on right side
    #>
    [void] SetRightText([string]$text) {
        $this.RightText = $text
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Set all three sections at once

    .PARAMETER left
    Left text

    .PARAMETER center
    Center text

    .PARAMETER right
    Right text
    #>
    [void] SetStatus([string]$left, [string]$center, [string]$right) {
        $this.LeftText = $left
        $this.CenterText = $center
        $this.RightText = $right
        $this.Invalidate()
    }

    # === Rendering ===

    [string] OnRender() {
        $sb = [System.Text.StringBuilder]::new(256)

        # Colors
        $bgColor = $this.GetThemedBg('Background.MenuBar', 1, 0)
        $fgColor = $this.GetThemedFg('Foreground.Row')
        $mutedColor = $this.GetThemedFg('Foreground.Muted')
        $reset = "`e[0m"

        # Position
        $sb.Append($this.BuildMoveTo($this.X, $this.Y))

        # Background
        if ($this.UseBackground) {
            $sb.Append($bgColor)
            $sb.Append($fgColor)
        }

        # Calculate section widths
        $leftWidth = [Math]::Floor($this.Width * 0.4)
        $centerWidth = [Math]::Floor($this.Width * 0.2)
        $rightWidth = $this.Width - $leftWidth - $centerWidth

        # Left section
        $leftDisplay = $this.PadText($this.LeftText, $leftWidth, 'left')
        $sb.Append($leftDisplay)

        # Center section
        $centerDisplay = $this.PadText($this.CenterText, $centerWidth, 'center')
        $sb.Append($mutedColor)
        $sb.Append($centerDisplay)
        $sb.Append($fgColor)

        # Right section
        $rightDisplay = $this.PadText($this.RightText, $rightWidth, 'right')
        $sb.Append($rightDisplay)

        $sb.Append($reset)

        $result = $sb.ToString()

        return $result
    }

    # === Layout System ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)

        $leftWidth = [Math]::Floor($this.Width * 0.4)
        $centerWidth = [Math]::Floor($this.Width * 0.2)
        $rightWidth = $this.Width - $leftWidth - $centerWidth

        $engine.DefineRegion("$($this.RegionID)_Left", $this.X, $this.Y, $leftWidth, 1)
        $engine.DefineRegion("$($this.RegionID)_Center", $this.X + $leftWidth, $this.Y, $centerWidth, 1)
        $engine.DefineRegion("$($this.RegionID)_Right", $this.X + $leftWidth + $centerWidth, $this.Y, $rightWidth, 1)
    }

    <#
    .SYNOPSIS
    Render directly to engine (new high-performance path)
    #>
    [void] RenderToEngine([object]$engine) {
        $this.RegisterLayout($engine)

        $bg = $this.GetThemedBgInt('Background.MenuBar', 1, 0)
        $fg = $this.GetThemedInt('Foreground.Row')
        $muted = $this.GetThemedInt('Foreground.Muted')
        
        # FAIL FAST
        # if ($bg -eq -1) { $bg = [HybridRenderEngine]::_PackRGB(30, 30, 30) } # Dark grey fallback

        # Fill background
        $engine.Fill($this.X, $this.Y, $this.Width, 1, ' ', $fg, $bg)

        # Left section
        $engine.WriteToRegion("$($this.RegionID)_Left", $this.LeftText, $fg, $bg)

        # Center section (Centered)
        $boundsC = $engine.GetRegionBounds("$($this.RegionID)_Center")
        if ($boundsC) {
            $pad = [Math]::Max(0, [Math]::Floor(($boundsC.Width - $this.CenterText.Length) / 2))
            $cText = (" " * $pad) + $this.CenterText
            $engine.WriteToRegion("$($this.RegionID)_Center", $cText, $muted, $bg)
        }

        # Right section (Right-aligned)
        $boundsR = $engine.GetRegionBounds("$($this.RegionID)_Right")
        if ($boundsR) {
            $pad = [Math]::Max(0, $boundsR.Width - $this.RightText.Length)
            $rText = (" " * $pad) + $this.RightText
            $engine.WriteToRegion("$($this.RegionID)_Right", $rText, $fg, $bg)
        }
    }

    # === Helper Methods ===

    <#
    .SYNOPSIS
    Set status with timestamp

    .PARAMETER message
    Status message

    .DESCRIPTION
    Sets left text to message and right text to current time
    #>
    [void] SetStatusWithTime([string]$message) {
        $this.LeftText = $message
        $this.RightText = (Get-Date).ToString("HH:mm:ss")
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Show loading status

    .PARAMETER message
    Loading message
    #>
    [void] ShowLoading([string]$message) {
        $this.SetLeftText("⏳ $message")
    }

    <#
    .SYNOPSIS
    Show success status

    .PARAMETER message
    Success message
    #>
    [void] ShowSuccess([string]$message) {
        $this.SetLeftText("[OK] $message")
    }

    <#
    .SYNOPSIS
    Show error status

    .PARAMETER message
    Error message
    #>
    [void] ShowError([string]$message) {
        $this.SetLeftText("[ERROR] $message")
    }

    <#
    .SYNOPSIS
    Clear status bar

    .DESCRIPTION
    Clears all text sections
    #>
    [void] Clear() {
        $this.LeftText = ""
        $this.CenterText = ""
        $this.RightText = ""
        $this.Invalidate()
    }
}

# Classes exported automatically in PowerShell 5.1+
# Classes exported automatically in PowerShell 5.1+