# PmcWidget - Base class for all PMC widgets
# Extends SpeedTUI Component with PMC-specific theme and layout integration

using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

# SpeedTUI framework must be loaded before this file
# (loaded by PmcApplication.ps1 or Start-PmcTUI.ps1)
# This check ensures Component class is available
if (-not ([System.Management.Automation.PSTypeName]'Component').Type) {
    throw "SpeedTUI Component class not found. Ensure SpeedTUILoader.ps1 is loaded before PmcWidget.ps1"
}

# PmcThemeEngine must be loaded before this file
# (loaded by SpeedTUILoader.ps1)
if (-not ([System.Management.Automation.PSTypeName]'PmcThemeEngine').Type) {
    throw "PmcThemeEngine class not found. Ensure PmcThemeEngine.ps1 is loaded before PmcWidget.ps1"
}

# Ensure ZIndex is loaded (needed by most widgets)
if (-not ([System.Management.Automation.PSTypeName]'ZIndex').Type) {
    $zIndexPath = Join-Path $PSScriptRoot '../ZIndex.ps1'
    if (Test-Path $zIndexPath) {
        . $zIndexPath
    }
}

<#
.SYNOPSIS
Base class for all PMC widgets extending SpeedTUI Component

.DESCRIPTION
PmcWidget provides the foundation for all PMC UI components:
- Integration with PMC's theme system (single hex → full palette derivation)
- Layout constraint support (named regions, percentage-based positioning)
- Box drawing with full Unicode character set
- Performance optimizations (string caching, pre-computation)
- Unified event handling
- State management hooks

.EXAMPLE
# Example: Custom widget implementation
# class MyCustomWidget : PmcWidget {
#     [void] RenderToEngine([object]$engine) {
#         $this.DrawBox($this.X, $this.Y, 20, 5, $this.GetThemedInt('Border'), $this.GetThemedBgInt('Background', 20, 0))
#     }
# }
#>
class PmcWidget : Component {
    # === PMC-Specific Properties ===
    [string]$Name = ""                    # Widget name for debugging
    [hashtable]$LayoutConstraints = @{}   # Named region constraints
    [string]$RegionID = ""                # Engine Layout Region ID

    # === Theme Integration ===
    hidden [hashtable]$_pmcTheme = $null        # Cached PMC theme
    hidden [hashtable]$_pmcStyleTokens = $null  # Cached style tokens
    hidden [bool]$_themeInitialized = $false

    # === Box Drawing Characters ===
    hidden [hashtable]$_boxChars = @{
        # Single line
        'single_horizontal'   = '─'
        'single_vertical'     = '│'
        'single_topleft'      = '┌'
        'single_topright'     = '┐'
        'single_bottomleft'   = '└'
        'single_bottomright'  = '┘'
        'single_cross'        = '┼'
        'single_t_down'       = '┬'
        'single_t_up'         = '┴'
        'single_t_right'      = '├'
        'single_t_left'       = '┤'

        # Double line
        'double_horizontal'   = '═'
        'double_vertical'     = '║'
        'double_topleft'      = '╔'
        'double_topright'     = '╗'
        'double_bottomleft'   = '╚'
        'double_bottomright'  = '╝'
        'double_cross'        = '╬'
        'double_t_down'       = '╦'
        'double_t_up'         = '╩'
        'double_t_right'      = '╠'
        'double_t_left'       = '╣'

        # Heavy line
        'heavy_horizontal'    = '━'
        'heavy_vertical'      = '┃'
        'heavy_topleft'       = '┏'
        'heavy_topright'      = '┓'
        'heavy_bottomleft'    = '┗'
        'heavy_bottomright'   = '┛'

        # Rounded
        'rounded_topleft'     = '╭'
        'rounded_topright'    = '╮'
        'rounded_bottomleft'  = '╰'
        'rounded_bottomright' = '╯'
    }

    # === Constructor ===
    PmcWidget() : base() {
        $this.Name = $this.GetType().Name
        $this._EnsureThemeInitialized()
    }

    PmcWidget([string]$name) : base() {
        $this.Name = $name
        $this._EnsureThemeInitialized()
    }

    # === Layout System ===

    <#
    .SYNOPSIS
    Register layout regions with the engine.
    Override this to define complex grids or sub-regions.
    #>
    [void] RegisterLayout([object]$engine) {
        if ([string]::IsNullOrEmpty($this.RegionID)) {
            $this.RegionID = $this.Name + "_" + [Guid]::NewGuid().ToString().Substring(0, 8)
        }
        
        # Define base region for this widget
        # Z-Index default 0, parent relative if supported later
        if ($engine.PSObject.Methods['DefineRegion']) {
            $engine.DefineRegion($this.RegionID, $this.X, $this.Y, $this.Width, $this.Height)
        }
    }

    # === Rendering ===

    <#
    .SYNOPSIS
    Ensure PMC theme system is loaded
    #>
    hidden [void] _EnsureThemeInitialized() {
        if ($this._themeInitialized) { return }

        try {
            # Get PMC theme state
            $displayState = Get-PmcState -Section 'Display'
            if ($displayState) {
                $this._pmcTheme = $displayState.Theme
                $this._pmcStyleTokens = $displayState.Styles
            }

            # Fallback to defaults if state not available
            # FAIL FAST
            # if (-not $this._pmcTheme) {
            #    $this._pmcTheme = @{
            #        PaletteName = 'default'
            #        Hex = '#33aaff'
            #        TrueColor = $true
            #    }
            # }

            # FAIL FAST
            # if (-not $this._pmcStyleTokens) {
            #    $this._pmcStyleTokens = @{
            #        Title = @{ Fg = '#33aaff' }
            #        Body = @{ Fg = '#CCCCCC' }
            #        Border = @{ Fg = '#666666' }
            #    }
            # }

            $this._themeInitialized = $true
        }
        catch {
            # FAIL FAST
            throw
            
            # Fallback - widget still functional with defaults
            # if (Get-Command Write-PmcTuiLog -ErrorAction SilentlyContinue) {
            #     Write-PmcTuiLog "Theme initialization failed: $($_.Exception.Message)" "ERROR"
            #     Write-PmcTuiLog "Stack: $($_.ScriptStackTrace)"
            # }
            # $this._themeInitialized = $true
        }
    }

    <#
    .SYNOPSIS
    Get color for a specific role from PMC theme system

    .PARAMETER role
    Color role: Primary, Border, Text, Muted, Error, Warning, Success, Bright, Header, etc.

    .OUTPUTS
    String - background ANSI escape sequence

    .NOTES
    NEW THEME API - Replaces GetThemedAnsi()
    Delegates to PmcThemeEngine singleton for all color resolution
    Supports both solid colors and gradients automatically

    Property name format: "Background.Field", "Background.FieldFocused", etc.
    For solid colors: width/charIndex ignored, same ANSI for all positions
    For gradients: returns interpolated ANSI for specific character position
    #>
    [string] GetThemedBg([string]$propertyName, [int]$width, [int]$charIndex) {
        $engine = [PmcThemeEngine]::GetInstance()
        $result = $engine.GetBackgroundAnsi($propertyName, $width, $charIndex)
        # CRITICAL DEBUG: Log what theme engine returns
        return $result
    }

    <#
    .SYNOPSIS
    Get foreground ANSI color sequence from theme engine

    .PARAMETER propertyName
    Theme property name (e.g., "Foreground.Field", "Foreground.FieldFocused")

    .OUTPUTS
    String - foreground ANSI escape sequence

    .NOTES
    NEW THEME API - Replaces GetThemedAnsi()
    Foregrounds are typically solid colors
    #>
    [string] GetThemedFg([string]$propertyName) {
        $engine = [PmcThemeEngine]::GetInstance()
        $result = $engine.GetForegroundAnsi($propertyName)
        # CRITICAL DEBUG: Log what theme engine returns
        return $result
    }

    <#
    .SYNOPSIS
    Get integer color value for HybridRenderEngine
    #>
    [int] GetThemedColorInt([string]$propertyName) {
        $engine = [PmcThemeEngine]::GetInstance()
        return $engine.GetThemeColorInt($propertyName)
    }

    <#
    .SYNOPSIS
    Get packed RGB integer for a specific role (Hybrid Engine optimized)

    .PARAMETER role
    Color role or property name

    .PARAMETER background
    If true, gets background color (supports gradient/position if index provided)

    .OUTPUTS
    Int - Packed RGB integer or -1
    #>
    [int] GetThemedInt([string]$role) {
        $engine = [PmcThemeEngine]::GetInstance()
        return $engine.GetForegroundInt($role)
    }

    [int] GetThemedBgInt([string]$role, [int]$width, [int]$charIndex) {
        $engine = [PmcThemeEngine]::GetInstance()
        return $engine.GetBackgroundInt($role, $width, $charIndex)
    }

    <#
    .SYNOPSIS
    Write themed text that automatically uses gradient if theme defines it

    .PARAMETER renderEngine
    The render engine (HybridRenderEngine)

    .PARAMETER x
    X coordinate

    .PARAMETER y
    Y coordinate

    .PARAMETER text
    Text to render

    .PARAMETER fgProp
    Foreground theme property (e.g., 'Foreground.Row')

    .PARAMETER bgProp
    Background theme property (e.g., 'Background.Row')
    #>
    [void] WriteThemedAt([object]$renderEngine, [int]$x, [int]$y, [string]$text, [string]$fgProp, [string]$bgProp) {
        $themeEngine = [PmcThemeEngine]::GetInstance()
        
        # Check if foreground is gradient
        $gradientInfo = $themeEngine.GetGradientInfo($fgProp)
        
        # DEBUG: Log to file
        # Add-Content -Path "/tmp/pmc-gradient-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] WriteThemedAt: fgProp=$fgProp gradientInfo=$(if($gradientInfo){'GRADIENT'}else{'null'})"
        
        # Get background color (always solid for now)
        $bg = $themeEngine.GetThemeColorInt($bgProp)
        
        if ($gradientInfo) {
            # Use gradient overload
            # Add-Content -Path "/tmp/pmc-gradient-debug.log" -Value "  -> GRADIENT WriteAt: Start=$($gradientInfo.Start) End=$($gradientInfo.End)"
            $renderEngine.WriteAt($x, $y, $text, $gradientInfo.Start, $gradientInfo.End, $bg)
        }
        else {
            # Use solid color
            $fg = $themeEngine.GetThemeColorInt($fgProp)
            $renderEngine.WriteAt($x, $y, $text, $fg, $bg)
        }
    }


    # === Box Drawing Methods ===

    <#
    .SYNOPSIS
    Get box-drawing character by name

    .PARAMETER charName
    Character name (e.g., 'single_horizontal', 'double_topleft', 'rounded_topleft')

    .OUTPUTS
    Unicode box-drawing character
    #>
    [string] GetBoxChar([string]$charName) {
        if ($this._boxChars.ContainsKey($charName)) {
            return $this._boxChars[$charName]
        }
        return ''
    }

    <#
    .SYNOPSIS
    Build a horizontal line with specified style

    .PARAMETER width
    Width in characters

    .PARAMETER style
    Line style: 'single' (default), 'double', 'heavy'

    .OUTPUTS
    String containing repeated horizontal line character
    #>
    [string] BuildHorizontalLine([int]$width, [string]$style = 'single') {
        $char = $this.GetBoxChar("${style}_horizontal")
        if ([string]::IsNullOrEmpty($char)) {
            $char = '─'
        }
        return $char * $width
    }

    <#
    .SYNOPSIS
    Build a box border string (top, middle, or bottom line)

    .PARAMETER width
    Width in characters (total, including corners)

    .PARAMETER position
    'top', 'middle', 'bottom'

    .PARAMETER style
    Border style: 'single', 'double', 'heavy', 'rounded'

    .OUTPUTS
    String containing full border line with corners

    .EXAMPLE
    $topLine = $this.BuildBoxBorder(40, 'top', 'single')      # "┌──────────────────────────────────────┐"
    $bottomLine = $this.BuildBoxBorder(40, 'bottom', 'rounded')  # "╰──────────────────────────────────────╯"
    #>
    [string] BuildBoxBorder([int]$width, [string]$position, [string]$style = 'single') {
        if ($width -lt 2) { return '' }

        $leftChar = ''
        $rightChar = ''
        $horizChar = $this.GetBoxChar("${style}_horizontal")

        # Handle rounded style (special case - uses single for horizontal)
        if ($style -eq 'rounded') {
            $horizChar = $this.GetBoxChar('single_horizontal')
            switch ($position) {
                'top' {
                    $leftChar = $this.GetBoxChar('rounded_topleft')
                    $rightChar = $this.GetBoxChar('rounded_topright')
                }
                'bottom' {
                    $leftChar = $this.GetBoxChar('rounded_bottomleft')
                    $rightChar = $this.GetBoxChar('rounded_bottomright')
                }
                default {
                    $leftChar = $this.GetBoxChar('single_vertical')
                    $rightChar = $this.GetBoxChar('single_vertical')
                }
            }
        }
        else {
            switch ($position) {
                'top' {
                    $leftChar = $this.GetBoxChar("${style}_topleft")
                    $rightChar = $this.GetBoxChar("${style}_topright")
                }
                'bottom' {
                    $leftChar = $this.GetBoxChar("${style}_bottomleft")
                    $rightChar = $this.GetBoxChar("${style}_bottomright")
                }
                default {
                    $leftChar = $this.GetBoxChar("${style}_vertical")
                    $rightChar = $this.GetBoxChar("${style}_vertical")
                }
            }
        }

        $innerWidth = $width - 2
        return $leftChar + ($horizChar * $innerWidth) + $rightChar
    }

    # === Layout Constraint Methods ===

    <#
    .SYNOPSIS
    Apply layout constraints to calculate actual position and size

    .PARAMETER termWidth
    Terminal width in characters

    .PARAMETER termHeight
    Terminal height in characters

    .DESCRIPTION
    Supports percentage-based positioning and sizing:
    - X/Y: Can be integers or strings like "10%" or "CENTER"
    - Width/Height: Can be integers or strings like "50%" or "FILL"
    #>
    [void] ApplyLayoutConstraints([int]$termWidth, [int]$termHeight) {
        if (-not $this.LayoutConstraints -or $this.LayoutConstraints.Count -eq 0) {
            return
        }

        $newX = $this.X
        $newY = $this.Y
        $newWidth = $this.Width
        $newHeight = $this.Height

        # Process X constraint
        if ($this.LayoutConstraints.ContainsKey('X')) {
            $xConstraint = $this.LayoutConstraints['X']
            if ($xConstraint -is [string]) {
                if ($xConstraint -match '^(\d+)%$') {
                    $pct = [int]$Matches[1]
                    $newX = [Math]::Floor($termWidth * $pct / 100.0)
                }
                elseif ($xConstraint -eq 'CENTER') {
                    $newX = [Math]::Floor(($termWidth - $newWidth) / 2.0)
                }
            }
            else {
                $newX = [int]$xConstraint
            }
        }

        # Process Y constraint
        if ($this.LayoutConstraints.ContainsKey('Y')) {
            $yConstraint = $this.LayoutConstraints['Y']
            if ($yConstraint -is [string]) {
                if ($yConstraint -match '^(\d+)%$') {
                    $pct = [int]$Matches[1]
                    $newY = [Math]::Floor($termHeight * $pct / 100.0)
                }
                elseif ($yConstraint -match '^BOTTOM-(\d+)$') {
                    $offset = [int]$Matches[1]
                    $newY = $termHeight - $offset
                }
                elseif ($yConstraint -eq 'BOTTOM') {
                    $newY = $termHeight - 1
                }
            }
            else {
                $newY = [int]$yConstraint
            }
        }

        # Process Width constraint
        if ($this.LayoutConstraints.ContainsKey('Width')) {
            $widthConstraint = $this.LayoutConstraints['Width']
            if ($widthConstraint -is [string]) {
                if ($widthConstraint -match '^(\d+)%$') {
                    $pct = [int]$Matches[1]
                    $newWidth = [Math]::Floor($termWidth * $pct / 100.0)
                }
                elseif ($widthConstraint -eq 'FILL') {
                    $newWidth = $termWidth - $newX
                }
            }
            else {
                $newWidth = [int]$widthConstraint
            }
        }

        # Process Height constraint
        if ($this.LayoutConstraints.ContainsKey('Height')) {
            $heightConstraint = $this.LayoutConstraints['Height']
            if ($heightConstraint -is [string]) {
                if ($heightConstraint -match '^(\d+)%$') {
                    $pct = [int]$Matches[1]
                    $newHeight = [Math]::Floor($termHeight * $pct / 100.0)
                }
                elseif ($heightConstraint -eq 'FILL') {
                    $newHeight = $termHeight - $newY
                }
            }
            else {
                $newHeight = [int]$heightConstraint
            }
        }

        # Apply calculated bounds (uses SpeedTUI's methods)
        $this.SetPosition($newX, $newY)
        $this.SetSize($newWidth, $newHeight)
    }

    # === Terminal Resize Handling ===

    <#
    .SYNOPSIS
    Handle terminal resize events

    .DESCRIPTION
    Override from Component to add layout constraint recalculation
    #>
    [void] OnTerminalResize([int]$newWidth, [int]$newHeight) {
        # Recalculate constraints
        $this.ApplyLayoutConstraints($newWidth, $newHeight)

        # Call base implementation (handles children, invalidation)
        ([Component]$this).OnTerminalResize($newWidth, $newHeight)
    }

    # === Utility Methods ===

    <#
    .SYNOPSIS
    Build a VT100 cursor position sequence

    .PARAMETER x
    X coordinate (column, 0-based)

    .PARAMETER y
    Y coordinate (row, 0-based)

    .OUTPUTS
    ANSI escape sequence to move cursor
    #>
    [string] BuildMoveTo([int]$x, [int]$y) {
        # VT100 uses 1-based coordinates
        $col = $x + 1
        $row = $y + 1
        return "`e[${row};${col}H"
    }

    <#
    .SYNOPSIS
    Get cached spaces string (performance optimization)

    .PARAMETER count
    Number of spaces

    .OUTPUTS
    String of spaces
    #>
    [string] GetSpaces([int]$count) {
        if ($count -le 0) { return '' }
        return (" " * $count)
    }

    <#
    .SYNOPSIS
    Truncate text to fit width with ellipsis

    .PARAMETER text
    Text to truncate

    .PARAMETER maxWidth
    Maximum width

    .OUTPUTS
    Truncated text with ellipsis if needed
    #>
    [string] TruncateText([string]$text, [int]$maxWidth) {
        if ([string]::IsNullOrEmpty($text)) { return '' }

        # Use visible length for truncation decision
        $visibleLen = $this.GetVisibleLength($text)
        if ($visibleLen -le $maxWidth) { return $text }
        if ($maxWidth -le 1) { return '…' }

        # Truncation with ANSI codes is complex - strip codes, truncate, return
        # (We lose color formatting, but that's acceptable for truncated text)
        $stripped = $text -replace '\e\[[0-9;]*m', ''
        return $stripped.Substring(0, $maxWidth - 1) + '…'
    }

    <#
    .SYNOPSIS
    Get visible length of text (excluding ANSI escape codes)

    .PARAMETER text
    Text to measure

    .OUTPUTS
    Visible character count
    #>
    [int] GetVisibleLength([string]$text) {
        if ([string]::IsNullOrEmpty($text)) { return 0 }
        # Remove ANSI escape sequences: \e[...m or \e[..;..m etc.
        $stripped = $text -replace '\e\[[0-9;]*m', ''
        return $stripped.Length
    }

    <#
    .SYNOPSIS
    Pad text to specified width

    .PARAMETER text
    Text to pad (may contain ANSI escape codes)

    .PARAMETER width
    Target width in visible characters

    .PARAMETER align
    Alignment: 'left' (default), 'center', 'right'

    .OUTPUTS
    Padded text
    #>
    [string] PadText([string]$text, [int]$width, [string]$align = 'left') {
        if ([string]::IsNullOrEmpty($text)) { return (" " * $width) }

        # Use visible length instead of raw .Length to account for ANSI codes
        $visibleLen = $this.GetVisibleLength($text)
        if ($text.Length -lt 50) {
            # Write-PmcTuiLog "PadText: text='$text' rawLen=$($text.Length) visibleLen=$visibleLen width=$width align=$align"
        }

        if ($visibleLen -ge $width) {
            # Text is already wide enough - truncate if needed
            # For now, just return as-is (truncation is complex with ANSI codes)
            return $text
        }

        $padding = $width - $visibleLen
        $result = switch ($align) {
            'center' {
                $leftPad = [Math]::Floor($padding / 2.0)
                $rightPad = $padding - $leftPad
                (" " * $leftPad) + $text + (" " * $rightPad)
            }
            'right' { (" " * $padding) + $text }
            default { $text + (" " * $padding) }
        }
        return $result
    }

    <#
    .SYNOPSIS
    L-POL-1: Truncate help text to fit narrow terminals

    .PARAMETER text
    Help text to truncate

    .PARAMETER maxWidth
    Maximum width (defaults to terminal width - 10)

    .OUTPUTS
    Truncated string with ellipsis if needed
    #>
    [string] TruncateHelpText([string]$text, [int]$maxWidth = -1) {
        if ($maxWidth -lt 0) {
            # L-POL-1: Use centralized terminal service (cached, optimized)
            $termWidth = [Console]::WindowWidth
            $maxWidth = $termWidth - 10
        }

        if ($text.Length -le $maxWidth) {
            return $text
        }

        # Truncate with ellipsis
        return $text.Substring(0, $maxWidth - 3) + "..."
    }
}


# Classes and functions are exported automatically in PowerShell 5.1+
