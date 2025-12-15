using namespace System
using namespace System.Collections.Generic
using namespace System.Text

# FilterPanel.ps1 - Dynamic filter builder UI
# Builds complex filters with visual chips and dropdown configuration
#
# Usage:
#   $panel = [FilterPanel]::new()
#   $panel.SetPosition(5, 5)
#   $panel.SetSize(80, 12)
#   $panel.OnFiltersChanged = { param($filters) $this.ReloadData() }
#
#   # Apply filters to data
#   $filteredTasks = $panel.ApplyFilters($allTasks)
#
#   # Export/import filter presets
#   $preset = $panel.GetFilterPreset()
#   $panel.LoadFilterPreset($preset)

Set-StrictMode -Version Latest

# Load PmcWidget base class
if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

<#
.SYNOPSIS
Dynamic filter builder widget with visual filter chips

.DESCRIPTION
Features:
- Add/remove filters dynamically
- Filter types: Project, Priority, DueDate, Tags, Status, Text
- Visual filter chips: [Project: work] [Priority >= 3] [Due: This Week]
- Alt+A to add filter (shows dropdown of filter types)
- Alt+R to remove selected filter
- Alt+C to clear all filters
- Apply filters to data arrays
- OnFiltersChanged event
- Export/import filter presets
- Smart filter matching with multiple operators
- Preset filters (common filter combinations)

Filter Types:
- Project: Filter by project name (equals, contains)
- Priority: Filter by priority number (=, !=, <, <=, >, >=)
- DueDate: Filter by due date (today, this week, this month, before, after, between)
- Tags: Filter by tags (has, has all, has any)
- Status: Filter by status (pending, completed, archived)
- Text: Full-text search in task text

.EXAMPLE
$panel = [FilterPanel]::new()
$panel.SetPosition(5, 5)
$allTasks = Get-PmcData | Select-Object -ExpandProperty tasks
$filteredTasks = $panel.ApplyFilters($allTasks)
#>
class FilterPanel : PmcWidget {
    # === Public Properties ===
    [string]$Title = "Filters"                 # Panel title

    # === Event Callbacks ===
    [scriptblock]$OnFiltersChanged = {}        # Called when filters change: param($filters)
    [scriptblock]$OnFilterAdded = {}           # Called when filter added: param($filter)
    [scriptblock]$OnFilterRemoved = {}         # Called when filter removed: param($index)
    [scriptblock]$OnFiltersCleared = {}        # Called when all filters cleared

    # === State Flags ===
    [bool]$IsEditing = $false                  # True when editing filters

    # === Private State ===
    hidden [List[hashtable]]$_filters = [List[hashtable]]::new()     # Active filters
    hidden [int]$_selectedFilterIndex = 0                             # Selected filter index
    hidden [bool]$_showAddMenu = $false                               # Show add filter menu
    hidden [int]$_addMenuSelectedIndex = 0                            # Selected item in add menu
    hidden [string[]]$_availableFilterTypes = @(
        'Project', 'Priority', 'DueDate', 'Tags', 'Status', 'Text'
    )

    # Filter presets (common filter combinations)
    hidden [hashtable]$_presets = @{
        'Today'         = @(
            @{ Type = 'DueDate'; Op = 'equals'; Value = [DateTime]::Today }
        )
        'This Week'     = @(
            @{ Type = 'DueDate'; Op = 'between'; Value = @([DateTime]::Today, [DateTime]::Today.AddDays(7)) }
        )
        'High Priority' = @(
            @{ Type = 'Priority'; Op = '>='; Value = 4 }
        )
        'Work Project'  = @(
            @{ Type = 'Project'; Op = 'equals'; Value = 'work' }
        )
    }

    # === Constructor ===
    FilterPanel() : base("FilterPanel") {
        $this.Width = 80
        $this.Height = 12
        $this.CanFocus = $true
    }

    # === Layout System ===

    [void] Resize([int]$width, [int]$height) {
        $this.Width = $width
        $this.Height = $height
    }

    # === Public API Methods ===

    <#
    .SYNOPSIS
    Set active filters

    .PARAMETER filters
    Array of filter hashtables
    #>
    [void] SetFilters([hashtable[]]$filters) {
        $this._filters.Clear()

        if ($null -ne $filters -and $filters.Count -gt 0) {
            foreach ($filter in $filters) {
                $this._filters.Add($filter)
            }
        }

        $this._InvokeCallback($this.OnFiltersChanged, $this.GetFilters())
    }

    <#
    .SYNOPSIS
    Get current filters

    .OUTPUTS
    Array of filter hashtables
    #>
    [hashtable[]] GetFilters() {
        return $this._filters.ToArray()
    }

    <#
    .SYNOPSIS
    Add a new filter

    .PARAMETER filter
    Filter hashtable with Type, Op, Value properties
    #>
    [void] AddDoFilter([hashtable]$filter) {
        $this._filters.Add($filter)
        $this._InvokeCallback($this.OnFilterAdded, $filter)
        $this._InvokeCallback($this.OnFiltersChanged, $this.GetFilters())
    }

    <#
    .SYNOPSIS
    Remove filter by index

    .PARAMETER index
    Zero-based filter index
    #>
    [void] RemoveDoFilter([int]$index) {
        if ($index -ge 0 -and $index -lt $this._filters.Count) {
            $this._filters.RemoveAt($index)
            $this._InvokeCallback($this.OnFilterRemoved, $index)
            $this._InvokeCallback($this.OnFiltersChanged, $this.GetFilters())

            # Adjust selected index
            if ($this._selectedFilterIndex -ge $this._filters.Count) {
                $this._selectedFilterIndex = [Math]::Max(0, $this._filters.Count - 1)
            }
        }
    }

    <#
    .SYNOPSIS
    Clear all filters
    #>
    [void] ClearFilters() {
        $this._filters.Clear()
        $this._selectedFilterIndex = 0
        $this._InvokeCallback($this.OnFiltersCleared, $null)
        $this._InvokeCallback($this.OnFiltersChanged, $this.GetFilters())
    }

    <#
    .SYNOPSIS
    Apply filters to data array

    .PARAMETER dataArray
    Array of objects to filter

    .OUTPUTS
    Filtered array
    #>
    [array] ApplyFilters([array]$dataArray) {
        if ($null -eq $dataArray -or $dataArray.Count -eq 0) {
            return @()
        }

        if ($this._filters.Count -eq 0) {
            return $dataArray
        }

        $filtered = $dataArray

        foreach ($filter in $this._filters) {
            $filtered = $this._ApplySingleDoFilter($filtered, $filter)
        }

        return $filtered
    }

    <#
    .SYNOPSIS
    Get human-readable filter string

    .OUTPUTS
    String describing all active filters
    #>
    [string] GetFilterString() {
        if ($this._filters.Count -eq 0) {
            return "No filters"
        }

        $sb = [StringBuilder]::new()

        foreach ($filter in $this._filters) {
            if ($sb.Length -gt 0) {
                $sb.Append(" AND ")
            }

            $sb.Append($this._FormatFilterChip($filter))
        }

        return $sb.ToString()
    }

    <#
    .SYNOPSIS
    Get filter preset

    .OUTPUTS
    Hashtable with filter configuration
    #>
    [hashtable] GetFilterPreset() {
        return @{
            Filters   = $this.GetFilters()
            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }

    <#
    .SYNOPSIS
    Load filter preset

    .PARAMETER preset
    Preset hashtable from GetFilterPreset()
    #>
    [void] LoadFilterPreset([hashtable]$preset) {
        if ($preset.ContainsKey('Filters')) {
            $this.SetFilters($preset.Filters)
        }
    }

    <#
    .SYNOPSIS
    Handle keyboard input

    .PARAMETER keyInfo
    ConsoleKeyInfo from [Console]::ReadKey($true)

    .OUTPUTS
    True if input was handled, False otherwise
    #>
    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        # Add menu navigation
        if ($this._showAddMenu) {
            return $this._HandleAddMenuInput($keyInfo)
        }

        # Alt+A - add filter
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt -and $keyInfo.Key -eq 'A') {
            $this._showAddMenu = $true
            $this._addMenuSelectedIndex = 0
            return $true
        }

        # Alt+R - remove selected filter
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt -and $keyInfo.Key -eq 'R') {
            if ($this._filters.Count -gt 0) {
                $this.RemoveDoFilter($this._selectedFilterIndex)
            }
            return $true
        }

        # Alt+C - clear all filters
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt -and $keyInfo.Key -eq 'C') {
            $this.ClearFilters()
            return $true
        }

        # Navigate filters
        if ($keyInfo.Key -eq 'LeftArrow') {
            if ($this._selectedFilterIndex -gt 0) {
                $this._selectedFilterIndex--
            }
            return $true
        }

        if ($keyInfo.Key -eq 'RightArrow') {
            if ($this._selectedFilterIndex -lt ($this._filters.Count - 1)) {
                $this._selectedFilterIndex++
            }
            return $true
        }

        # Delete - remove selected filter
        if ($keyInfo.Key -eq 'Delete') {
            if ($this._filters.Count -gt 0) {
                $this.RemoveDoFilter($this._selectedFilterIndex)
            }
            return $true
        }

        return $false
    }

    # === Layout System ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)
        
        $engine.DefineRegion("$($this.RegionID)_Title", $this.X + 2, $this.Y + 1, $this.Width - 4, 1)
        $engine.DefineRegion("$($this.RegionID)_Count", $this.X + $this.Width - 10, $this.Y + 1, 8, 1)
        $engine.DefineRegion("$($this.RegionID)_Filters", $this.X + 2, $this.Y + 2, $this.Width - 4, $this.Height - 4)
        $engine.DefineRegion("$($this.RegionID)_Help", $this.X + 2, $this.Y + $this.Height - 2, $this.Width - 4, 1)
    }

    <#
    .SYNOPSIS
    Render directly to engine (new high-performance path)
    #>
    [void] RenderToEngine([object]$engine) {
        $this.RegisterLayout($engine)

        # Colors (Ints)
        $bg = $this.GetThemedBgInt('Background.MenuBar', 1, 0)
        $fg = $this.GetThemedInt('Foreground.Row')
        $borderFg = $this.GetThemedInt('Border.Widget')
        $primaryFg = $this.GetThemedInt('Foreground.Title')
        $mutedFg = $this.GetThemedInt('Foreground.Muted')
        $highlightBg = $this.GetThemedBgInt('Background.RowSelected', 1, 0)
        
        if ($bg -eq -1) { $bg = [HybridRenderEngine]::_PackRGB(30, 30, 30) }

        # Draw Box
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $borderFg, $bg)
        
        # Title
        $titleText = " $($this.Title) "
        $engine.WriteToRegion("$($this.RegionID)_Title", $titleText, $primaryFg, $bg)
        
        # Count
        $countText = "($($this._filters.Count) active)"
        $engine.WriteToRegion("$($this.RegionID)_Count", $countText, $mutedFg, $bg)
        
        # Filters (Chips)
        $filtersRegion = "$($this.RegionID)_Filters"
        $bounds = $engine.GetRegionBounds($filtersRegion)
        
        if ($bounds) {
            $currentX = $bounds.X
            $currentY = $bounds.Y
            $maxX = $bounds.X + $bounds.Width
            $maxY = $bounds.Y + $bounds.Height
            
            if ($this._filters.Count -eq 0) {
                # No filters
                $msg = "No filters active"
                $pad = [Math]::Max(0, [Math]::Floor(($bounds.Width - $msg.Length) / 2))
                $engine.WriteAt($bounds.X, $currentY + 1, (" " * $pad) + $msg, $mutedFg, $bg)
            }
            else {
                for ($i = 0; $i -lt $this._filters.Count; $i++) {
                    $filter = $this._filters[$i]
                    $chipText = "[" + $this._FormatFilterChip($filter) + "]"
                    $chipLen = $chipText.Length + 1
                    
                    if ($currentX + $chipLen -gt $maxX) {
                        $currentX = $bounds.X
                        $currentY++
                    }
                    
                    if ($currentY -ge $maxY) { break }
                    
                    $isSelected = ($i -eq $this._selectedFilterIndex)
                    $chipBg = if ($isSelected) { $highlightBg } else { $bg }
                    
                    # Color based on type
                    $ansiColor = $this._GetFilterColor($filter.Type)
                    $chipFg = [HybridRenderEngine]::AnsiColorToInt($ansiColor)
                    
                    $engine.WriteAt($currentX, $currentY, $chipText, $chipFg, $chipBg)
                    $currentX += $chipLen
                }
            }
        }
        
        # Add Menu (Overlay)
        if ($this._showAddMenu) {
            $menuWidth = 30
            $menuHeight = $this._availableFilterTypes.Count + 4
            $menuX = $this.X + [Math]::Floor(($this.Width - $menuWidth) / 2)
            $menuY = $this.Y + 2
            
            $menuRegionId = "$($this.RegionID)_AddMenu"
            $engine.DefineRegion($menuRegionId, $menuX, $menuY, $menuWidth, $menuHeight, 100)
            
            $engine.Fill($menuX, $menuY, $menuWidth, $menuHeight, ' ', $fg, $bg)
            $engine.DrawBox($menuX, $menuY, $menuWidth, $menuHeight, $borderFg, $bg)
            
            # Menu Title
            $engine.WriteAt($menuX + 2, $menuY, " Add Filter ", $primaryFg, $bg)
            
            # Items
            for ($i = 0; $i -lt $this._availableFilterTypes.Count; $i++) {
                $type = $this._availableFilterTypes[$i]
                $isSel = ($i -eq $this._addMenuSelectedIndex)
                $iBg = if ($isSel) { $highlightBg } else { $bg }
                
                $engine.Fill($menuX + 1, $menuY + 1 + $i, $menuWidth - 2, 1, ' ', $fg, $iBg)
                $engine.WriteAt($menuX + 2, $menuY + 1 + $i, $type, $fg, $iBg)
            }
            
            # Help
            $engine.WriteAt($menuX + 2, $menuY + $menuHeight - 2, "Enter=Add | Esc=Cancel", $mutedFg, $bg)
        }
        
        # Help
        $helpText = "Alt+A: Add | Alt+R: Remove | Alt+C: Clear | Arrows: Navigate"
        $engine.WriteToRegion("$($this.RegionID)_Help", $helpText, $mutedFg, $bg)
    }

    <#
    .SYNOPSIS
    Render the filter panel

    .OUTPUTS
    ANSI string ready for display
    #>
    [string] Render() {
        $sb = [StringBuilder]::new(2048)

        # Colors from new theme system
        $borderColor = $this.GetThemedFg('Border.Widget')
        $textColor = $this.GetThemedFg('Foreground.Row')
        $primaryColor = $this.GetThemedFg('Foreground.Title')
        $mutedColor = $this.GetThemedFg('Foreground.Muted')
        $errorColor = $this.GetThemedFg('Foreground.Error')
        $successColor = $this.GetThemedFg('Foreground.Success')
        $highlightBg = $this.GetThemedBg('Background.RowSelected', 1, 0)
        $highlightFg = $this.GetThemedFg('Foreground.RowSelected')
        $reset = "`e[0m"

        # Draw top border
        $sb.Append($this.BuildMoveTo($this.X, $this.Y))
        $sb.Append($borderColor)
        $sb.Append($this.BuildBoxBorder($this.Width, 'top', 'single'))

        # Title
        $titleText = " $($this.Title) "
        $titlePos = 2
        $sb.Append($this.BuildMoveTo($this.X + $titlePos, $this.Y))
        $sb.Append($primaryColor)
        $sb.Append($titleText)

        # Filter count
        $countText = "($($this._filters.Count) active)"
        $sb.Append($this.BuildMoveTo($this.X + $this.Width - $countText.Length - 2, $this.Y))
        $sb.Append($mutedColor)
        $sb.Append($countText)

        # Active filters display (rows 1-8)
        $filterDisplayRows = 7
        $currentRow = 1

        if ($this._filters.Count -eq 0) {
            # No filters message
            $noFiltersY = $this.Y + $currentRow + 2
            $sb.Append($this.BuildMoveTo($this.X, $noFiltersY))
            $sb.Append($borderColor)
            $sb.Append($this.GetBoxChar('single_vertical'))

            $sb.Append($this.BuildMoveTo($this.X + 2, $noFiltersY))
            $sb.Append($mutedColor)
            $sb.Append($this.PadText("No filters active", $this.Width - 4, 'center'))

            $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $noFiltersY))
            $sb.Append($borderColor)
            $sb.Append($this.GetBoxChar('single_vertical'))
        }
        else {
            # Render filter chips
            $this._RenderFilterChips($sb, $currentRow, $borderColor, $textColor, $primaryColor, $highlightBg, $reset)
        }

        # Fill remaining rows
        for ($row = $currentRow; $row -lt $filterDisplayRows + 1; $row++) {
            $rowY = $this.Y + $row
            $sb.Append($this.BuildMoveTo($this.X, $rowY))
            $sb.Append($borderColor)
            $sb.Append($this.GetBoxChar('single_vertical'))
            $sb.Append(" " * ($this.Width - 2))
            $sb.Append($this.GetBoxChar('single_vertical'))
        }

        # Add menu overlay (if shown)
        if ($this._showAddMenu) {
            $this._RenderAddMenu($sb, $borderColor, $textColor, $primaryColor, $mutedColor, $highlightBg, $reset)
        }

        # Help text row
        $helpRowY = $this.Y + $this.Height - 2
        $sb.Append($this.BuildMoveTo($this.X, $helpRowY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        $sb.Append($this.BuildMoveTo($this.X + 2, $helpRowY))
        $sb.Append($mutedColor)
        $helpText = "Alt+A: Add | Alt+R: Remove | Alt+C: Clear | Arrows: Navigate"
        $sb.Append($this.TruncateText($helpText, $this.Width - 4))

        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $helpRowY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        # Bottom border
        $sb.Append($this.BuildMoveTo($this.X, $this.Y + $this.Height - 1))
        $sb.Append($borderColor)
        $sb.Append($this.BuildBoxBorder($this.Width, 'bottom', 'single'))

        $sb.Append($reset)
        return $sb.ToString()
    }

    # === Private Helper Methods ===

    <#
    .SYNOPSIS
    Render filter chips
    #>
    hidden [void] _RenderFilterChips([StringBuilder]$sb, [ref]$currentRow, [string]$borderColor, [string]$textColor, [string]$primaryColor, [string]$highlightBg, [string]$reset) {
        $innerWidth = $this.Width - 4
        $currentX = 0
        $currentY = $currentRow.Value

        for ($i = 0; $i -lt $this._filters.Count; $i++) {
            $filter = $this._filters[$i]
            $chipText = $this._FormatFilterChip($filter)
            $chipLen = $chipText.Length + 2  # Add padding

            # Check if we need to wrap to next row
            if ($currentX + $chipLen -gt $innerWidth) {
                # Fill rest of current row
                $padding = $innerWidth - $currentX
                $sb.Append(" " * $padding)

                # Right border
                $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $this.Y + $currentY))
                $sb.Append($borderColor)
                $sb.Append($this.GetBoxChar('single_vertical'))

                # Move to next row
                $currentY++
                $currentX = 0

                # Start new row
                $sb.Append($this.BuildMoveTo($this.X, $this.Y + $currentY))
                $sb.Append($borderColor)
                $sb.Append($this.GetBoxChar('single_vertical'))
            }

            # Position for chip
            if ($currentX -eq 0) {
                $sb.Append($this.BuildMoveTo($this.X + 2, $this.Y + $currentY))
            }

            # Render chip
            $isSelected = ($i -eq $this._selectedFilterIndex)

            if ($isSelected) {
                $sb.Append($highlightBg)
                $sb.Append("`e[30m")
            }
            else {
                $chipColor = $this._GetFilterColor($filter.Type)
                $sb.Append($chipColor)
            }

            $sb.Append("[")
            $sb.Append($chipText)
            $sb.Append("]")
            $sb.Append($reset)
            $sb.Append(" ")

            $currentX += $chipLen + 1
        }

        # Fill rest of current row
        if ($currentX -lt $innerWidth) {
            $padding = $innerWidth - $currentX
            $sb.Append(" " * $padding)
        }

        # Right border for last row
        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $this.Y + $currentY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        $currentRow.Value = $currentY + 1
    }

    <#
    .SYNOPSIS
    Render add filter menu overlay
    #>
    hidden [void] _RenderAddMenu([StringBuilder]$sb, [string]$borderColor, [string]$textColor, [string]$primaryColor, [string]$mutedColor, [string]$highlightBg, [string]$reset) {
        $menuWidth = 30
        $menuHeight = $this._availableFilterTypes.Count + 4
        $menuX = $this.X + [Math]::Floor(($this.Width - $menuWidth) / 2)
        $menuY = $this.Y + 2

        # Draw menu border
        $sb.Append($this.BuildMoveTo($menuX, $menuY))
        $sb.Append($primaryColor)
        $sb.Append($this.BuildBoxBorder($menuWidth, 'top', 'single'))

        # Title
        $sb.Append($this.BuildMoveTo($menuX + 2, $menuY))
        $sb.Append(" Add Filter ")

        # Filter types
        for ($i = 0; $i -lt $this._availableFilterTypes.Count; $i++) {
            $itemY = $menuY + $i + 1
            $filterType = $this._availableFilterTypes[$i]
            $isSelected = ($i -eq $this._addMenuSelectedIndex)

            $sb.Append($this.BuildMoveTo($menuX, $itemY))
            $sb.Append($borderColor)
            $sb.Append($this.GetBoxChar('single_vertical'))

            $sb.Append($this.BuildMoveTo($menuX + 2, $itemY))

            if ($isSelected) {
                $sb.Append($highlightBg)
                $sb.Append("`e[30m")
            }
            else {
                $sb.Append($textColor)
            }

            $sb.Append($this.PadText($filterType, $menuWidth - 4, 'left'))
            $sb.Append($reset)

            $sb.Append($this.BuildMoveTo($menuX + $menuWidth - 1, $itemY))
            $sb.Append($borderColor)
            $sb.Append($this.GetBoxChar('single_vertical'))
        }

        # Help row
        $helpY = $menuY + $this._availableFilterTypes.Count + 1
        $sb.Append($this.BuildMoveTo($menuX, $helpY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        $sb.Append($this.BuildMoveTo($menuX + 2, $helpY))
        $sb.Append($mutedColor)
        $sb.Append($this.TruncateText("Enter=Add | Esc=Cancel", $menuWidth - 4))

        $sb.Append($this.BuildMoveTo($menuX + $menuWidth - 1, $helpY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        # Bottom border
        $sb.Append($this.BuildMoveTo($menuX, $menuY + $menuHeight - 1))
        $sb.Append($borderColor)
        $sb.Append($this.BuildBoxBorder($menuWidth, 'bottom', 'single'))
    }

    <#
    .SYNOPSIS
    Handle add menu input
    #>
    hidden [bool] _HandleAddMenuInput([ConsoleKeyInfo]$keyInfo) {
        if ($keyInfo.Key -eq 'Escape') {
            $this._showAddMenu = $false
            return $true
        }

        if ($keyInfo.Key -eq 'Enter') {
            # Add filter of selected type
            $filterType = $this._availableFilterTypes[$this._addMenuSelectedIndex]
            $newFilter = $this._CreateDefaultDoFilter($filterType)
            $this.AddDoFilter($newFilter)
            $this._showAddMenu = $false
            return $true
        }

        if ($keyInfo.Key -eq 'UpArrow') {
            if ($this._addMenuSelectedIndex -gt 0) {
                $this._addMenuSelectedIndex--
            }
            return $true
        }

        if ($keyInfo.Key -eq 'DownArrow') {
            if ($this._addMenuSelectedIndex -lt ($this._availableFilterTypes.Count - 1)) {
                $this._addMenuSelectedIndex++
            }
            return $true
        }

        return $false
    }

    <#
    .SYNOPSIS
    Create default filter for a type
    #>
    hidden [hashtable] _CreateDefaultDoFilter([string]$filterType) {
        switch ($filterType) {
            'Project' {
                return @{ Type = 'Project'; Op = 'equals'; Value = 'work' }
            }
            'Priority' {
                return @{ Type = 'Priority'; Op = '>='; Value = 3 }
            }
            'DueDate' {
                return @{ Type = 'DueDate'; Op = 'equals'; Value = [DateTime]::Today }
            }
            'Tags' {
                return @{ Type = 'Tags'; Op = 'has'; Value = 'urgent' }
            }
            'Status' {
                return @{ Type = 'Status'; Op = 'equals'; Value = 'pending' }
            }
            'Text' {
                return @{ Type = 'Text'; Op = 'contains'; Value = '' }
            }
            default {
                return @{ Type = 'Unknown'; Op = 'equals'; Value = $null }
            }
        }
        # Fallback (should never reach here)
        return @{ Type = 'Unknown'; Op = 'equals'; Value = $null }
    }

    <#
    .SYNOPSIS
    Format filter as chip text
    #>
    hidden [string] _FormatFilterChip([hashtable]$filter) {
        $type = $filter.Type
        $op = $filter.Op
        $value = $filter.Value

        $opSymbol = switch ($op) {
            'equals' { '=' }
            'notequals' { '!=' }
            'contains' { '~' }
            'startswith' { '^' }
            'lt' { '<' }
            'lte' { '<=' }
            'gt' { '>' }
            'gte' { '>=' }
            'has' { 'has' }
            'hasall' { 'has all' }
            'hasany' { 'has any' }
            'between' { 'between' }
            default { $op }
        }

        # Format value based on type
        $valueStr = ""
        if ($value -is [DateTime]) {
            $valueStr = $value.ToString("MM/dd")
        }
        elseif ($value -is [array]) {
            $valueStr = $value -join ', '
        }
        else {
            $valueStr = $value.ToString()
        }

        return "$type $opSymbol $valueStr"
    }

    <#
    .SYNOPSIS
    Get color for filter type
    #>
    hidden [string] _GetFilterColor([string]$filterType) {
        $colorMap = @{
            'Project'  = '#3498db'
            'Priority' = '#e74c3c'
            'DueDate'  = '#2ecc71'
            'Tags'     = '#9b59b6'
            'Status'   = '#f39c12'
            'Text'     = '#1abc9c'
        }

        $hex = $(if ($colorMap.ContainsKey($filterType)) { $colorMap[$filterType] } else { '#CCCCCC' })

        # Convert hex to RGB
        $hex = $hex.TrimStart('#')
        $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)

        return "`e[38;2;${r};${g};${b}m"
    }

    <#
    .SYNOPSIS
    Apply a single filter to data array
    #>
    hidden [array] _ApplySingleDoFilter([array]$dataArray, [hashtable]$filter) {
        $type = $filter.Type
        $op = $filter.Op
        $value = $filter.Value

        $filtered = [System.Collections.ArrayList]::new()

        foreach ($item in $dataArray) {
            $match = $false

            switch ($type) {
                'Project' {
                    $itemValue = $(if ($item.project) { $item.project } else { "" })
                    $match = $this._CompareValues($itemValue, $op, $value)
                }

                'Priority' {
                    $itemValue = $(if ($null -ne $item.priority) { $item.priority } else { 0 })
                    $match = $this._CompareValues($itemValue, $op, $value)
                }

                'DueDate' {
                    if ($null -ne $item.due) {
                        try {
                            $itemDate = $(if ($item.due -is [DateTime]) { $item.due } else { [DateTime]::Parse($item.due) })
                            $match = $this._CompareDates($itemDate, $op, $value)
                        }
                        catch {
                            # Invalid date format - treat as non-matching
                            $match = $false
                        }
                    }
                }

                'Tags' {
                    $itemTags = $(if ($item.tags) { $item.tags } else { @() })
                    $match = $this._CompareTags($itemTags, $op, $value)
                }

                'Status' {
                    $itemValue = $(if ($item.status) { $item.status } else { "pending" })
                    $match = $this._CompareValues($itemValue, $op, $value)
                }

                'Text' {
                    $itemValue = $(if ($item.text) { $item.text } else { "" })
                    $match = $this._CompareValues($itemValue, $op, $value)
                }
            }

            if ($match) {
                [void]$filtered.Add($item)
            }
        }

        # Force array type - prevent PowerShell from unwrapping single-item arrays to scalars
        return @($filtered)
    }

    <#
    .SYNOPSIS
    Compare two values based on operator
    #>
    hidden [bool] _CompareValues($itemValue, [string]$op, $filterValue) {
        switch ($op) {
            'equals' { return $itemValue -eq $filterValue }
            'notequals' { return $itemValue -ne $filterValue }
            'contains' { return $itemValue -like "*$filterValue*" }
            'startswith' { return $itemValue -like "$filterValue*" }
            'lt' { return $itemValue -lt $filterValue }
            'lte' { return $itemValue -le $filterValue }
            'gt' { return $itemValue -gt $filterValue }
            'gte' { return $itemValue -ge $filterValue }
            '>=' { return $itemValue -ge $filterValue }
            '<=' { return $itemValue -le $filterValue }
            '>' { return $itemValue -gt $filterValue }
            '<' { return $itemValue -lt $filterValue }
            '=' { return $itemValue -eq $filterValue }
            '!=' { return $itemValue -ne $filterValue }
            default { return $false }
        }
        # Fallback (should never reach here)
        return $false
    }

    <#
    .SYNOPSIS
    Compare dates with operator
    #>
    hidden [bool] _CompareDates([DateTime]$itemDate, [string]$op, $filterValue) {
        if ($op -eq 'between' -and $filterValue -is [array] -and $filterValue.Count -ge 2) {
            $start = $filterValue[0]
            $end = $filterValue[1]
            return $itemDate -ge $start -and $itemDate -le $end
        }

        if ($filterValue -is [DateTime]) {
            return $this._CompareValues($itemDate, $op, $filterValue)
        }

        return $false
    }

    <#
    .SYNOPSIS
    Compare tags with operator
    #>
    hidden [bool] _CompareTags([array]$itemTags, [string]$op, $filterValue) {
        if ($null -eq $itemTags) {
            $itemTags = @()
        }

        switch ($op) {
            'has' {
                return $itemTags -contains $filterValue
            }
            'hasall' {
                if ($filterValue -is [array]) {
                    foreach ($tag in $filterValue) {
                        if ($itemTags -notcontains $tag) {
                            return $false
                        }
                    }
                    return $true
                }
                return $itemTags -contains $filterValue
            }
            'hasany' {
                if ($filterValue -is [array]) {
                    foreach ($tag in $filterValue) {
                        if ($itemTags -contains $tag) {
                            return $true
                        }
                    }
                    return $false
                }
                return $itemTags -contains $filterValue
            }
            default {
                return $false
            }
        }
        # Fallback (should never reach here)
        return $false
    }

    <#
    .SYNOPSIS
    Invoke callback safely
    #>
    hidden [void] _InvokeCallback([scriptblock]$callback, $args) {
        if ($null -ne $callback -and $callback -ne {}) {
            try {
                if ($null -ne $args) {
                    & $callback $args
                }
                else {
                    & $callback
                }
            }
            catch {
                # Silently ignore callback errors
            }
        }
    }
}