using namespace System.Text

# PmcHeader - Screen header widget with title, breadcrumb, and context info
# Provides consistent header appearance across all PMC screens

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Header widget for screen titles and navigation context

.DESCRIPTION
PmcHeader displays:
- Screen title (large, themed)
- Optional icon
- Optional breadcrumb trail
- Optional context information
- Horizontal separator line

.EXAMPLE
$header = [PmcHeader]::new("Tasks")
$header.SetBreadcrumb(@("Home", "Projects", "Tasks"))
$header.SetContext("15 active tasks")
#>
class PmcHeader : PmcWidget {
    # === Properties ===
    [string]$Title = ""
    [string]$Icon = ""
    [string[]]$Breadcrumb = @()
    [string]$ContextInfo = ""
    [bool]$ShowSeparator = $true
    [string]$BorderStyle = 'single'  # 'single', 'double', 'heavy'

    # === Constructor ===
    PmcHeader() : base("Header") {
        $this.Height = 5  # Title + blank + breadcrumb + blank + separator (max height with breadcrumb)
        $this.Width = 80
    }

    PmcHeader([string]$title) : base("Header") {
        $this.Title = $title
        $this.Height = 5  # Title + blank + breadcrumb + blank + separator (max height with breadcrumb)
        $this.Width = 80
    }

    # === Configuration ===

    <#
    .SYNOPSIS
    Set the title text

    .PARAMETER title
    Title to display
    #>
    [void] SetTitle([string]$title) {
        $this.Title = $title
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Set the icon character

    .PARAMETER icon
    Icon character or emoji
    #>
    [void] SetIcon([string]$icon) {
        $this.Icon = $icon
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Set breadcrumb trail

    .PARAMETER breadcrumb
    Array of breadcrumb segments (e.g., @("Home", "Projects", "My Project"))
    #>
    [void] SetBreadcrumb([string[]]$breadcrumb) {
        $this.Breadcrumb = $breadcrumb
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Set context information (right-aligned)

    .PARAMETER contextInfo
    Context text (e.g., "15 items", "Last updated: 2024-01-15")
    #>
    [void] SetContext([string]$contextInfo) {
        $this.ContextInfo = $contextInfo
        $this.Invalidate()
    }

    # === Rendering ===

    [string] OnRender() {
        $sb = [System.Text.StringBuilder]::new(512)

        # Colors
        $titleColor = $this.GetThemedFg('Foreground.Title')
        $mutedColor = $this.GetThemedFg('Foreground.Muted')
        $borderColor = $this.GetThemedFg('Border.Widget')
        $reset = "`e[0m"

        # Line 1: Title (with optional icon and context)
        $sb.Append($this.BuildMoveTo($this.X, $this.Y))
        $sb.Append($titleColor)

        $titleText = ""
        if ($this.Icon) {
            $titleText = "$($this.Icon) "
        }
        $titleText += $this.Title

        # If context info exists, show it right-aligned
        if ($this.ContextInfo) {
            $contextText = " [$($this.ContextInfo)]"
            $availableWidth = $this.Width - $titleText.Length - $contextText.Length
            if ($availableWidth -gt 0) {
                $sb.Append($titleText)
                $sb.Append($this.GetSpaces($availableWidth))
                $sb.Append($mutedColor)
                $sb.Append($contextText)
                $sb.Append($reset)
            } else {
                # Not enough room, just show title
                $sb.Append($this.TruncateText($titleText, $this.Width))
                $sb.Append($reset)
            }
        } else {
            $sb.Append($titleText)
            $sb.Append($reset)
        }

        # Line 2: Blank line for visual space
        # (intentionally blank)

        # Line 3: Breadcrumb (if present)
        if ($this.Breadcrumb -and $this.Breadcrumb.Count -gt 0) {
            $sb.Append($this.BuildMoveTo($this.X, $this.Y + 2))
            $sb.Append($mutedColor)

            $breadcrumbText = $this.Breadcrumb -join " → "
            $sb.Append($this.TruncateText($breadcrumbText, $this.Width))
            $sb.Append($reset)
        }

        # Line 4: Column headers will be rendered by TaskListScreen here
        # Line 5: Separator (if enabled)
        if ($this.ShowSeparator) {
            $separatorY = $(if ($this.Breadcrumb -and $this.Breadcrumb.Count -gt 0) { $this.Y + 4 } else { $this.Y + 2 })
            $sb.Append($this.BuildMoveTo($this.X, $separatorY))
            $sb.Append($borderColor)
            $sb.Append($this.BuildHorizontalLine($this.Width, $this.BorderStyle))
            $sb.Append($reset)
        }

        $result = $sb.ToString()

        return $result
    }

    # === Layout System ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)

        # Region for Title (Left side)
        $contextWidth = [Math]::Min(30, [Math]::Max(10, $this.Width - 20))  # Clamp between 10-30
        $titleWidth = [Math]::Max(10, $this.Width - $contextWidth)
        $engine.DefineRegion("$($this.RegionID)_Title", $this.X, $this.Y, $titleWidth, 1)

        # Region for Context (Right side) - ensure it doesn't extend past widget bounds
        $engine.DefineRegion("$($this.RegionID)_Context", $this.X + $titleWidth, $this.Y, $contextWidth, 1)
        
        # Region for Breadcrumb (Line 3, Y+2)
        $engine.DefineRegion("$($this.RegionID)_Breadcrumb", $this.X, $this.Y + 2, $this.Width, 1)
        
        # Region for Separator (Line 5 or 3 depending on breadcrumb)
        # We calculate Y dynamically based on state during render, but regions are static.
        # So we define TWO separator regions and use the right one? Or just one flexible one?
        # Better: Define potential regions.
        $engine.DefineRegion("$($this.RegionID)_Separator_Breadcrumb", $this.X, $this.Y + 4, $this.Width, 1)
        $engine.DefineRegion("$($this.RegionID)_Separator_Simple", $this.X, $this.Y + 2, $this.Width, 1)
    }

    <#
    .SYNOPSIS
    Render directly to engine (new high-performance path)
    #>
    [void] RenderToEngine([object]$engine) {
        $this.RegisterLayout($engine)

        # Colors (Ints)
        $titleFg = $this.GetThemedInt('Foreground.Title')
        $mutedFg = $this.GetThemedInt('Foreground.Muted')
        $borderFg = $this.GetThemedInt('Border.Widget')
        $defaultBg = -1

        # Calculate region widths (must match RegisterLayout)
        $contextWidth = [Math]::Min(30, [Math]::Max(10, $this.Width - 20))
        $titleWidth = [Math]::Max(10, $this.Width - $contextWidth)

        # Title
        $titleText = if ($this.Icon) { "$($this.Icon) $($this.Title)" } else { $this.Title }
        $engine.WriteToRegion("$($this.RegionID)_Title", $titleText, $titleFg, $defaultBg)

        # Context Info (Right-aligned within its region)
        if ($this.ContextInfo) {
             $ctxText = "[$($this.ContextInfo)]"
             $padCount = [Math]::Max(0, $contextWidth - $ctxText.Length)
             $paddedCtx = (" " * $padCount) + $ctxText
             $engine.WriteToRegion("$($this.RegionID)_Context", $paddedCtx, $mutedFg, $defaultBg)
        }

        # Breadcrumb
        $hasBreadcrumb = ($this.Breadcrumb -and $this.Breadcrumb.Count -gt 0)
        if ($hasBreadcrumb) {
            $crumbText = $this.Breadcrumb -join " → "
            $engine.WriteToRegion("$($this.RegionID)_Breadcrumb", $crumbText, $mutedFg, $defaultBg)
        }

        # Separator
        if ($this.ShowSeparator) {
            $sepRegion = if ($hasBreadcrumb) { "$($this.RegionID)_Separator_Breadcrumb" } else { "$($this.RegionID)_Separator_Simple" }
            
            # Fill with line char
            # We need bounds for Fill. 
            $bounds = $engine.GetRegionBounds($sepRegion)
            if ($bounds) {
                # Determine char based on style
                $char = $this.GetBoxChar('single_horizontal')
                if ($this.BorderStyle -eq 'double') { $char = $this.GetBoxChar('double_horizontal') }
                
                $engine.Fill($bounds.X, $bounds.Y, $bounds.Width, 1, $char, $borderFg, $defaultBg)
            }
        }
    }

    # === Pre-computation ===

    [void] PrecomputeRenderData() {
        # Pre-compute layout based on current size
        # Called by base class when bounds change
    }
}

# Classes exported automatically in PowerShell 5.1+
# Classes exported automatically in PowerShell 5.1+