# PmcLayoutManager - Named regions and constraint-based layout system
# Eliminates magic numbers and provides standard layouts for PMC screens

using namespace System.Collections.Generic

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Layout manager providing named regions and constraint-based positioning

.DESCRIPTION
PmcLayoutManager provides:
- Named regions (MenuBar, Header, Content, Footer, StatusBar)
- Percentage-based positioning and sizing
- Fill constraints (FILL, BOTTOM, CENTER)
- Standard margin/padding constants
- Automatic recalculation on terminal resize

.EXAMPLE
$layout = [PmcLayoutManager]::new()
$headerRect = $layout.GetRegion('Header', 120, 40)
$menuBar.SetPosition($headerRect.X, $headerRect.Y)
$menuBar.SetSize($headerRect.Width, $headerRect.Height)
#>

<#
.SYNOPSIS
Rectangle structure for layout calculations
#>
class PmcRect {
    [int]$X = 0
    [int]$Y = 0
    [int]$Width = 0
    [int]$Height = 0

    PmcRect([int]$x, [int]$y, [int]$width, [int]$height) {
        $this.X = $x
        $this.Y = $y
        $this.Width = $width
        $this.Height = $height
    }
}

<#
.SYNOPSIS
Layout manager for screen regions
#>
class PmcLayoutManager {
    # === Standard Regions ===
    [hashtable]$Regions = @{
        # Menu bar at very top
        'MenuBar' = @{
            X = 0
            Y = 0
            Width = '100%'
            Height = 1
        }

        # Header below menu bar
        'Header' = @{
            X = '2%'
            Y = 3
            Width = '96%'
            Height = 3
        }

        # Main content area (fills available space)
        'Content' = @{
            X = '2%'
            Y = 8
            Width = '96%'
            Height = 'FILL'  # Calculated: termHeight - Y - FooterHeight - StatusBarHeight
        }

        # Footer above status bar
        'Footer' = @{
            X = '2%'
            Y = 'BOTTOM-2'  # 2 lines from bottom
            Width = '96%'
            Height = 1
        }

        # Status bar at very bottom
        'StatusBar' = @{
            X = 0
            Y = 'BOTTOM'
            Width = '100%'
            Height = 1
        }

        # Sidebar (optional, for split layouts)
        'Sidebar' = @{
            X = '2%'
            Y = 8
            Width = '30%'
            Height = 'FILL'
        }

        # Main area when sidebar present
        'MainWithSidebar' = @{
            X = '33%'
            Y = 8
            Width = '65%'
            Height = 'FILL'
        }
    }

    # === Standard Constants ===
    static [int]$MarginSmall = 1      # Small screen edge margin
    static [int]$MarginMedium = 2     # Standard screen edge margin
    static [int]$MarginLarge = 4      # Large screen edge margin

    static [int]$PaddingSmall = 1     # Inside widget padding
    static [int]$PaddingMedium = 2
    static [int]$PaddingLarge = 3

    static [int]$HeaderHeight = 3
    static [int]$FooterHeight = 1
    static [int]$StatusBarHeight = 1
    static [int]$MenuBarHeight = 1

    static [int]$MinTermWidth = 80
    static [int]$MinTermHeight = 24

    # === Constructor ===
    PmcLayoutManager() {
        # Initialize with default regions (can be customized per instance)
    }

    # === Public API ===

    <#
    .SYNOPSIS
    Get calculated rectangle for a named region

    .PARAMETER name
    Region name (MenuBar, Header, Content, Footer, StatusBar, Sidebar, MainWithSidebar)

    .PARAMETER termWidth
    Terminal width in characters

    .PARAMETER termHeight
    Terminal height in characters

    .OUTPUTS
    PmcRect with calculated X, Y, Width, Height

    .EXAMPLE
    $rect = $layout.GetRegion('Header', 120, 40)
    # Returns PmcRect with X=2, Y=3, Width=115, Height=3
    #>
    [PmcRect] GetRegion([string]$name, [int]$termWidth, [int]$termHeight) {
        if (-not $this.Regions.ContainsKey($name)) {
            throw "Unknown region: $name. Available regions: $($this.Regions.Keys -join ', ')"
        }

        $def = $this.Regions[$name]
        return $this._CalculateRect($def, $termWidth, $termHeight)
    }

    <#
    .SYNOPSIS
    Calculate rectangle from constraint definition
    #>
    hidden [PmcRect] _CalculateRect([hashtable]$def, [int]$termWidth, [int]$termHeight) {
        $x = $this._ResolveX($def.X, $termWidth, $termHeight)
        $y = $this._ResolveY($def.Y, $termWidth, $termHeight)
        $width = $this._ResolveWidth($def.Width, $x, $termWidth, $termHeight)
        $height = $this._ResolveHeight($def.Height, $y, $termWidth, $termHeight)

        return [PmcRect]::new($x, $y, $width, $height)
    }

    # === Constraint Resolution ===

    <#
    .SYNOPSIS
    Resolve X constraint to absolute position
    #>
    hidden [int] _ResolveX([object]$constraint, [int]$termWidth, [int]$termHeight) {
        if ($constraint -is [int]) {
            return $constraint
        }

        $strConstraint = [string]$constraint

        # Percentage
        if ($strConstraint -match '^(\d+)%$') {
            $pct = [int]$Matches[1]
            return [Math]::Floor($termWidth * $pct / 100.0)
        }

        # CENTER (requires width to be known, not commonly used for X)
        if ($strConstraint -eq 'CENTER') {
            # Can't center without knowing width - return 0
            return 0
        }

        # Default
        return 0
    }

    <#
    .SYNOPSIS
    Resolve Y constraint to absolute position
    #>
    hidden [int] _ResolveY([object]$constraint, [int]$termWidth, [int]$termHeight) {
        if ($constraint -is [int]) {
            return $constraint
        }

        $strConstraint = [string]$constraint

        # Percentage
        if ($strConstraint -match '^(\d+)%$') {
            $pct = [int]$Matches[1]
            return [Math]::Floor($termHeight * $pct / 100.0)
        }

        # BOTTOM (last line)
        if ($strConstraint -eq 'BOTTOM') {
            return [Math]::Max(0, $termHeight - 1)
        }

        # BOTTOM-N (N lines from bottom)
        if ($strConstraint -match '^BOTTOM-(\d+)$') {
            $offset = [int]$Matches[1]
            return [Math]::Max(0, $termHeight - $offset)
        }

        # Default
        return 0
    }

    <#
    .SYNOPSIS
    Resolve Width constraint to absolute width
    #>
    hidden [int] _ResolveWidth([object]$constraint, [int]$x, [int]$termWidth, [int]$termHeight) {
        if ($constraint -is [int]) {
            return $constraint
        }

        $strConstraint = [string]$constraint

        # Percentage
        if ($strConstraint -match '^(\d+)%$') {
            $pct = [int]$Matches[1]
            return [Math]::Floor($termWidth * $pct / 100.0)
        }

        # FILL (fill remaining width from X)
        if ($strConstraint -eq 'FILL') {
            return [Math]::Max(1, $termWidth - $x)
        }

        # Default
        return 1
    }

    <#
    .SYNOPSIS
    Resolve Height constraint to absolute height
    #>
    hidden [int] _ResolveHeight([object]$constraint, [int]$y, [int]$termWidth, [int]$termHeight) {
        if ($constraint -is [int]) {
            return $constraint
        }

        $strConstraint = [string]$constraint

        # Percentage
        if ($strConstraint -match '^(\d+)%$') {
            $pct = [int]$Matches[1]
            return [Math]::Floor($termHeight * $pct / 100.0)
        }

        # FILL (fill remaining height from Y, accounting for footer/statusbar)
        if ($strConstraint -eq 'FILL') {
            # Reserve space for footer (1 line) + statusbar (1 line) + 1 line margin
            $reserved = [PmcLayoutManager]::FooterHeight + [PmcLayoutManager]::StatusBarHeight + 1
            return [Math]::Max(1, $termHeight - $y - $reserved)
        }

        # Default
        return 1
    }

    # === Custom Regions ===

    <#
    .SYNOPSIS
    Define a custom named region

    .PARAMETER name
    Region name

    .PARAMETER x
    X constraint (int or string like "10%", "CENTER")

    .PARAMETER y
    Y constraint (int or string like "20%", "BOTTOM", "BOTTOM-5")

    .PARAMETER width
    Width constraint (int or string like "50%", "FILL")

    .PARAMETER height
    Height constraint (int or string like "30%", "FILL")

    .EXAMPLE
    $layout.DefineRegion('CustomPanel', '10%', 10, '80%', 15)
    $rect = $layout.GetRegion('CustomPanel', 120, 40)
    #>
    [void] DefineRegion([string]$name, [object]$x, [object]$y, [object]$width, [object]$height) {
        $this.Regions[$name] = @{
            X = $x
            Y = $y
            Width = $width
            Height = $height
        }
    }

    <#
    .SYNOPSIS
    Remove a custom region

    .PARAMETER name
    Region name to remove
    #>
    [void] RemoveRegion([string]$name) {
        if ($this.Regions.ContainsKey($name)) {
            $this.Regions.Remove($name)
        }
    }

    # === Utility Methods ===

    <#
    .SYNOPSIS
    Get all defined region names

    .OUTPUTS
    Array of region names
    #>
    [string[]] GetRegionNames() {
        return $this.Regions.Keys
    }

    <#
    .SYNOPSIS
    Check if terminal size is within acceptable range

    .PARAMETER termWidth
    Terminal width

    .PARAMETER termHeight
    Terminal height

    .OUTPUTS
    Boolean indicating if size is acceptable
    #>
    [bool] IsTerminalSizeAcceptable([int]$termWidth, [int]$termHeight) {
        return ($termWidth -ge [PmcLayoutManager]::MinTermWidth -and
                $termHeight -ge [PmcLayoutManager]::MinTermHeight)
    }

    <#
    .SYNOPSIS
    Get standard layout (all standard regions)

    .PARAMETER termWidth
    Terminal width

    .PARAMETER termHeight
    Terminal height

    .OUTPUTS
    Hashtable with region name → PmcRect mappings

    .EXAMPLE
    $layout = $layoutManager.GetStandardLayout(120, 40)
    $menuBarRect = $layout['MenuBar']
    $headerRect = $layout['Header']
    #>
    [hashtable] GetStandardLayout([int]$termWidth, [int]$termHeight) {
        $result = @{}

        foreach ($regionName in $this.Regions.Keys) {
            $result[$regionName] = $this.GetRegion($regionName, $termWidth, $termHeight)
        }

        return $result
    }

    # === Layout Presets ===

    <#
    .SYNOPSIS
    Create a layout manager with standard screen layout

    .OUTPUTS
    PmcLayoutManager with standard regions
    #>
    static [PmcLayoutManager] CreateStandardLayout() {
        return [PmcLayoutManager]::new()
    }

    <#
    .SYNOPSIS
    Create a layout manager with full-screen layout (no margins)

    .OUTPUTS
    PmcLayoutManager with full-screen regions
    #>
    static [PmcLayoutManager] CreateFullScreenLayout() {
        $layout = [PmcLayoutManager]::new()

        $layout.Regions['Header'] = @{
            X = 0
            Y = 2
            Width = '100%'
            Height = 3
        }

        $layout.Regions['Content'] = @{
            X = 0
            Y = 6
            Width = '100%'
            Height = 'FILL'
        }

        $layout.Regions['Footer'] = @{
            X = 0
            Y = 'BOTTOM-2'
            Width = '100%'
            Height = 1
        }

        return $layout
    }

    <#
    .SYNOPSIS
    Create a layout manager with sidebar layout

    .OUTPUTS
    PmcLayoutManager with sidebar and main content regions
    #>
    static [PmcLayoutManager] CreateSidebarLayout() {
        $layout = [PmcLayoutManager]::new()

        # Override Content region to work with Sidebar
        $layout.Regions['Content'] = $layout.Regions['MainWithSidebar']

        return $layout
    }
}

# === Helper Functions ===

<#
.SYNOPSIS
Apply layout constraints to a widget

.PARAMETER widget
Widget to apply constraints to

.PARAMETER regionName
Name of region to use

.PARAMETER layoutManager
Layout manager instance

.PARAMETER termWidth
Terminal width

.PARAMETER termHeight
Terminal height

.EXAMPLE
Apply-PmcLayout -Widget $header -RegionName 'Header' -LayoutManager $layout -TermWidth 120 -TermHeight 40
#>
function Apply-PmcLayout {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Widget,

        [Parameter(Mandatory = $true)]
        [string]$RegionName,

        [Parameter(Mandatory = $true)]
        [PmcLayoutManager]$LayoutManager,

        [Parameter(Mandatory = $true)]
        [int]$TermWidth,

        [Parameter(Mandatory = $true)]
        [int]$TermHeight
    )

    $rect = $LayoutManager.GetRegion($RegionName, $TermWidth, $TermHeight)

    if ($Widget.PSObject.Methods['SetPosition']) {
        $Widget.SetPosition($rect.X, $rect.Y)
    }

    if ($Widget.PSObject.Methods['SetSize']) {
        $Widget.SetSize($rect.Width, $rect.Height)
    }
}

# Classes and functions exported automatically in PowerShell 5.1+