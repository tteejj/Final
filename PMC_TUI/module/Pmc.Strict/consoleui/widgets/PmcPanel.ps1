using namespace System.Text
using namespace System.Collections.Generic

# PmcPanel - Container widget with border and title
# Provides grouped content areas with visual boundaries

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Panel widget - container with border, title, and optional scrolling

.DESCRIPTION
PmcPanel provides:
- Border with customizable style (single, double, heavy, rounded)
- Optional title in border
- Content area with automatic padding
- Optional scroll support
- Child widget container

.EXAMPLE
$panel = [PmcPanel]::new("Settings")
$panel.SetBorderStyle('rounded')
$panel.SetPadding(2)
#>
class PmcPanel : PmcWidget {
    # === Properties ===
    [string]$PanelTitle = ""
    [string]$BorderStyle = 'single'  # 'single', 'double', 'heavy', 'rounded'
    [int]$PaddingLeft = 1
    [int]$PaddingTop = 1
    [int]$PaddingRight = 1
    [int]$PaddingBottom = 1
    [bool]$ShowTitle = $true
    [bool]$ShowBorder = $true

    # Content
    [string]$ContentText = ""        # Simple text content (alternative to children)
    [string]$ContentAlign = 'left'   # 'left', 'center', 'right'

    # === Constructor ===
    PmcPanel() : base("Panel") {
        $this.Width = 40
        $this.Height = 10
    }

    PmcPanel([string]$title) : base("Panel") {
        $this.PanelTitle = $title
        $this.Width = 40
        $this.Height = 10
    }

    PmcPanel([string]$title, [int]$width, [int]$height) : base("Panel") {
        $this.PanelTitle = $title
        $this.Width = $width
        $this.Height = $height
    }

    # === Configuration ===

    <#
    .SYNOPSIS
    Set border style

    .PARAMETER style
    Border style: 'single', 'double', 'heavy', 'rounded'
    #>
    [void] SetBorderStyle([string]$style) {
        $this.BorderStyle = $style
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Set padding (all sides)

    .PARAMETER padding
    Padding in characters
    #>
    [void] SetPadding([int]$padding) {
        $this.PaddingLeft = $padding
        $this.PaddingTop = $padding
        $this.PaddingRight = $padding
        $this.PaddingBottom = $padding
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Set padding (individual sides)
    #>
    [void] SetPadding([int]$left, [int]$top, [int]$right, [int]$bottom) {
        $this.PaddingLeft = $left
        $this.PaddingTop = $top
        $this.PaddingRight = $right
        $this.PaddingBottom = $bottom
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Set simple text content

    .PARAMETER text
    Text to display in panel

    .PARAMETER align
    Alignment: 'left', 'center', 'right'
    #>
    [void] SetContent([string]$text, [string]$align = 'left') {
        $this.ContentText = $text
        $this.ContentAlign = $align
        $this.Invalidate()
    }

    # === Layout System ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)
        
        $borderOffset = if ($this.ShowBorder) { 1 } else { 0 }
        
        $contentX = $this.X + $borderOffset + $this.PaddingLeft
        $contentY = $this.Y + $borderOffset + $this.PaddingTop
        $contentW = $this.Width - (2 * $borderOffset) - $this.PaddingLeft - $this.PaddingRight
        $contentH = $this.Height - (2 * $borderOffset) - $this.PaddingTop - $this.PaddingBottom
        
        $engine.DefineRegion("$($this.RegionID)_Content", $contentX, $contentY, $contentW, $contentH)
        
        if ($this.ShowTitle -and $this.PanelTitle) {
            $engine.DefineRegion("$($this.RegionID)_Title", $this.X + 2, $this.Y, $this.Width - 4, 1)
        }
    }

    <#
    .SYNOPSIS
    Render directly to engine (new high-performance path)
    #>
    [void] RenderToEngine([object]$engine) {
        # DEBUG: Conditional logging
        if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcPanel.RenderToEngine] CALLED X=$($this.X) Y=$($this.Y) W=$($this.Width) H=$($this.Height) ShowBorder=$($this.ShowBorder)"
        }
        $this.RegisterLayout($engine)

        # Colors (Ints) - Match UniversalList color methods for consistency
        $borderColor = $this.GetThemedColorInt('Border.Widget')
        $titleColor = $this.GetThemedColorInt('Foreground.Title')
        $textColor = $this.GetThemedColorInt('Foreground.Row')
        $bg = $this.GetThemedColorInt('Background.Row')
        
        # Draw Border
        if ($this.ShowBorder) {
            $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $borderColor, $bg, $this.BorderStyle)
            
            # Draw Title
            if ($this.ShowTitle -and $this.PanelTitle) {
                $titleText = " $($this.PanelTitle) "
                # DrawBox draws lines. We overwrite with title.
                # Use region logic or manual write.
                # Title region defined at X+2.
                $engine.WriteToRegion("$($this.RegionID)_Title", $titleText, $titleColor, $bg)
            }
        }
        
        # Content Text
        if ($this.ContentText) {
            $regionId = "$($this.RegionID)_Content"
            $bounds = $engine.GetRegionBounds($regionId)
            
            if ($bounds) {
                # Simple text wrapping or direct write?
                # ContentText might be multiline.
                $lines = $this.ContentText -split "`n"
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($i -ge $bounds.Height) { break }
                    
                    $line = $lines[$i]
                    # Alignment
                    if ($this.ContentAlign -eq 'center') {
                        $pad = [Math]::Max(0, [Math]::Floor(($bounds.Width - $line.Length) / 2))
                        $line = (" " * $pad) + $line
                    }
                    elseif ($this.ContentAlign -eq 'right') {
                        $pad = [Math]::Max(0, $bounds.Width - $line.Length)
                        $line = (" " * $pad) + $line
                    }
                    
                    $engine.WriteAt($bounds.X, $bounds.Y + $i, $line, $textColor, $bg)
                }
            }
        }
    }

    # === Rendering ===

    [string] OnRender() {
        # Legacy render stub
        return ""
    }



    # === Helper Methods ===

    <#
    .SYNOPSIS
    Get content area bounds (excluding border and padding)

    .OUTPUTS
    Hashtable with X, Y, Width, Height of usable content area
    #>
    [hashtable] GetContentBounds() {
        $borderOffset = $(if ($this.ShowBorder) { 1 } else { 0 })

        return @{
            X      = $this.X + $borderOffset + $this.PaddingLeft
            Y      = $this.Y + $borderOffset + $this.PaddingTop
            Width  = $this.Width - (2 * $borderOffset) - $this.PaddingLeft - $this.PaddingRight
            Height = $this.Height - (2 * $borderOffset) - $this.PaddingTop - $this.PaddingBottom
        }
    }

    <#
    .SYNOPSIS
    Create simple info panel

    .PARAMETER title
    Panel title

    .PARAMETER content
    Panel content text

    .OUTPUTS
    Configured PmcPanel
    #>
    static [PmcPanel] CreateInfoPanel([string]$title, [string]$content) {
        $panel = [PmcPanel]::new($title)
        $panel.SetContent($content, 'left')
        $panel.SetBorderStyle('single')
        return $panel
    }

    <#
    .SYNOPSIS
    Create emphasized panel with double border

    .PARAMETER title
    Panel title

    .OUTPUTS
    Configured PmcPanel
    #>
    static [PmcPanel] CreateEmphasisPanel([string]$title) {
        $panel = [PmcPanel]::new($title)
        $panel.SetBorderStyle('double')
        return $panel
    }

    # === RenderCache Support ===
    [string] GetContentHash() {
        return "$($this.PanelTitle)|$($this.ContentText)|$($this.Width)|$($this.Height)"
    }
}

# Classes exported automatically in PowerShell 5.1+
# Classes exported automatically in PowerShell 5.1+