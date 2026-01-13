using namespace System
using namespace System.Collections.Generic
using namespace System.Text

# UniversalList.ps1 - Generic list widget with columns, sorting, filtering, and inline editing
# THE BIG ONE - Replaces 12+ specialized list screens!
#
#
# Usage:
#   $columns = @(
#       @{ Name='id'; Label='ID'; Width=4; Align='right' }
#       @{ Name='priority'; Label='Pri'; Width=4; Align='center'; Format={ "[P$_]" }}
#       @{ Name='text'; Label='Task'; Width=40; Align='left' }
#       @{ Name='due'; Label='Due'; Width=12; Format={ $_.ToString('MMM dd yyyy') }}
#       @{ Name='project'; Label='Project'; Width=15 }
#   )
#
#   $list = [UniversalList]::new()
#   $list.SetColumns($columns)
#   $list.SetData($tasks)
#   $list.SetPosition(0, 3)
#   $list.SetSize(120, 35)
#
#   # Events
#   $list.OnSelectionChanged = { param($item) Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [UniversalList] Selected: $($item.text)" }
#   $list.OnItemEdit = { param($item) $this.ShowInlineEditor($item) }
#   $list.OnItemDelete = { param($item) Remove-PmcTask $item.id }
#
#   # Actions (shown in footer)
#   $list.AddAction('a', 'Add', { $this.ShowInlineEditor(@{}) })
#   $list.AddAction('e', 'Edit', { $this.ShowInlineEditor($this.SelectedItem) })
#   $list.AddAction('d', 'Delete', { $this.DeleteSelectedItem() })

Set-StrictMode -Version Latest

# Load PmcWidget base class
if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

# NOTE: InlineEditor and FilterPanel are now loaded by the launcher script.
# Commenting out to avoid circular dependency issues.
# . "$PSScriptRoot/InlineEditor.ps1"
# . "$PSScriptRoot/FilterPanel.ps1"

<#
.SYNOPSIS
Universal list widget with columns, sorting, filtering, inline editing

.DESCRIPTION
Features:
- Column configuration with width, alignment, formatting
- Data binding to array of objects
- Sorting by column (click header or hotkey)
- Filtering with FilterPanel integration
- Selection with arrow keys, Home/End, PageUp/Down
- Multi-select mode (Space to toggle)
- Inline editing with InlineEditor integration
- Configurable actions (Add, Edit, Delete, etc.)
- Virtual scrolling for large datasets (handles 1000+ items)
- Differential rendering for performance
- Search mode (/ key to filter by text)
- Column resizing (future enhancement)

.EXAMPLE
$list = [UniversalList]::new()
$columns = @(
    @{ Name='id'; Label='ID'; Width=4 }
    @{ Name='text'; Label='Task'; Width=40 }
)
$list.SetColumns($columns)
$list.SetData($tasks)
#>

<#
.SYNOPSIS
Cell information passed to Format callbacks

.DESCRIPTION
Provides context about a cell during rendering:
- Column metadata (name, width, alignment)
- Screen position (X, Y coordinates)
- Edit state (is this cell focused for editing?)
- Row state (is the row being edited?)

This allows Format callbacks to make rendering decisions based on
cell state without needing to check global variables.

.EXAMPLE
Format = { param($item, $cellInfo)
    if ($cellInfo.IsFocused) {
        return "$orangeColor$($cellInfo.Value)"
    }
    return $cellInfo.Value
}
#>
class CellInfo {
    [string]$ColumnName        # Column identifier
    [object]$Value             # Raw cell value (from item data)
    [int]$X                    # Screen X position
    [int]$Y                    # Screen Y position
    [int]$Width                # Allocated width for this cell
    [string]$Align             # Alignment: 'left', 'center', 'right'
    [bool]$IsFocused           # Is this cell currently focused in edit mode?
    [bool]$IsInEditMode        # Is the parent row in edit mode?
    [bool]$IsSelected          # Is the parent row selected?
    [int]$RowIndex             # Row index in the list
    [int]$ColumnIndex          # Column index in the row

    CellInfo(
        [string]$columnName,
        [object]$value,
        [int]$x,
        [int]$y,
        [int]$width,
        [string]$align,
        [bool]$isFocused,
        [bool]$isInEditMode,
        [bool]$isSelected,
        [int]$rowIndex,
        [int]$columnIndex
    ) {
        $this.ColumnName = $columnName
        $this.Value = $value
        $this.X = $x
        $this.Y = $y
        $this.Width = $width
        $this.Align = $align
        $this.IsFocused = $isFocused
        $this.IsInEditMode = $isInEditMode
        $this.IsSelected = $isSelected
        $this.RowIndex = $rowIndex
        $this.ColumnIndex = $columnIndex
    }
}

class CachedRow {
    [string]$Text
    [int[]]$Foregrounds
    [int[]]$Backgrounds
    [byte[]]$Attributes
    [string]$ContentHash
}

class UniversalList : PmcWidget {
    # === Public Properties ===
    [string]$Title = "List"                    # List title
    [bool]$AllowMultiSelect = $true            # Allow multi-select mode
    [bool]$AllowInlineEdit = $true             # Allow inline editing
    [bool]$AllowSearch = $true                 # Allow search mode
    [bool]$ShowLineNumbers = $false            # Show line numbers in first column
    [int]$ItemsPerPage = 10                    # Items per page (for PageUp/Down)

    # === Event Callbacks ===
    [scriptblock]$OnSelectionChanged = {}      # Called when selection changes: param($item)
    [scriptblock]$OnItemEdit = {}              # Called when item edited: param($item)
    [scriptblock]$OnItemDelete = {}            # Called when item deleted: param($item)
    [scriptblock]$OnItemActivated = {}         # Called when item activated (Enter): param($item)
    [scriptblock]$OnMultiSelectChanged = {}    # Called when multi-select changes: param($selectedItems)
    [scriptblock]$OnDataChanged = {}           # Called when data changes: param($newData)

    # === Edit Mode Callbacks (for CellInfo) ===
    # Parent screen sets these to provide edit state info to Format callbacks via CellInfo
    [scriptblock]$GetIsInEditMode = {}         # Returns true if row is in edit mode: param($item)
    [scriptblock]$GetFocusedColumnIndex = {}   # Returns focused column index: param($item) -> int (-1 if not focused)
    [scriptblock]$GetEditValue = {}            # Returns edit value for cell: param($item, $columnName) -> value or null

    # === State Flags ===
    [bool]$IsInMultiSelectMode = $false        # True when in multi-select mode
    [bool]$IsInSearchMode = $false             # True when in search mode
    [bool]$IsInFilterMode = $false             # True when filter panel shown

    # === Private State ===
    hidden [List[hashtable]]$_columns = [List[hashtable]]::new()         # Column definitions
    hidden [object[]]$_data = @()                                        # Original data array
    hidden [object[]]$_filteredData = @()                                # Filtered/sorted data
    hidden [int]$_selectedIndex = 0                                      # Selected item index
    hidden [HashSet[int]]$_selectedIndices = [HashSet[int]]::new()       # Multi-select indices
    hidden [int]$_scrollOffset = 0                                       # Virtual scroll offset
    hidden [string]$_sortColumn = ""                                     # Current sort column
    hidden [bool]$_sortAscending = $true                                 # Sort direction
    hidden [string]$_searchText = ""                                     # Search filter text
    hidden [hashtable]$_actions = @{}                                    # Registered actions (key -> scriptblock)
    hidden [object]$_filterPanel = $null                                 # Filter panel instance (FilterPanel)
    hidden [object]$_inlineEditor = $null                                # Inline editor instance (InlineEditor)
    hidden [bool]$_showInlineEditor = $false                             # Show inline editor overlay
    hidden [string]$_lastRenderedContent = ""                            # Last rendered content (for diff)
    # L-POL-22: Column width adjustment
    hidden [hashtable]$_columnWidths = @{}                               # Custom column widths (overrides defaults)

    # === Region Cache for Layout System ===
    hidden [string[]]$_headerColRegions = @()                            # Region IDs for header columns
    hidden [hashtable]$_rowColRegions = @{}                              # Region IDs for data row columns (key: row index, value: array of region IDs)

    # Reset column widths to defaults
    [void] ResetColumnWidths() {
        $this._columnWidths.Clear()
        $this._cacheGeneration++
        $this._rowCache.Clear()
        $this._cacheAccessOrder.Clear()
    }
    hidden [int]$_selectedColumnIndex = -1                               # Currently selected column for width adjustment

    # === Row-Level Caching for Performance ===
    hidden [hashtable]$_rowCache = @{}                                   # Cache of rendered rows by index
    hidden [int]$_cacheGeneration = 0                                    # Increment to invalidate all cache
    # H-MEM-1: LRU cache management
    hidden [System.Collections.Generic.LinkedList[string]]$_cacheAccessOrder = [System.Collections.Generic.LinkedList[string]]::new()
    hidden [int]$_maxCacheSize = 500                                     # Maximum cache entries

    # === Constructor ===
    UniversalList() : base("UniversalList") {
        $this.Width = 120
        $this.Height = 35
        $this.CanFocus = $true

        # Initialize filter panel
        $this._filterPanel = [FilterPanel]::new()
        $this._filterPanel.SetPosition($this.X + 10, $this.Y + 5)
        $this._filterPanel.SetSize(60, 12)
        $self = $this
        $this._filterPanel.OnFiltersChanged = { param($filters)
            $self._ApplyFilters()
        }
    }

    # === Layout System ===

    [void] SetPosition([int]$x, [int]$y) {
        ([PmcWidget]$this).SetPosition($x, $y)
        
        # Update filter panel relative position
        if ($this._filterPanel) {
            $this._filterPanel.SetPosition($x + 10, $y + 5)
        }
    }

    <#
    .SYNOPSIS
    Register layout regions with the engine.
    This defines the grid structure for the list.
    #>
    [void] RegisterLayout([object]$engine) {
        # Call base class to register its own region
        ([PmcWidget]$this).RegisterLayout($engine)
        
        # NOTE: We do not define sub-regions for cells/headers.
        # We render dynamic content using WriteAt (FilterPanel pattern) 
        # to ensure robust visibility and precise layout control.
    }


    <#
    .SYNOPSIS
    Get property value from item (handles both hashtable and PSCustomObject)

    .PARAMETER item
    The item (hashtable or PSCustomObject)

    .PARAMETER propertyName
    Property name to retrieve

    .OUTPUTS
    Property value or $null if not found
    #>
    hidden [object] _GetItemProperty([object]$item, [string]$propertyName) {
        if ($null -eq $item) { return $null }

        if ($item -is [hashtable]) {
            $hasKey = $item.ContainsKey($propertyName)
            # Write-PmcTuiLog "_GetItemProperty: hashtable propertyName='$propertyName' hasKey=$hasKey"
            if ($hasKey) {
                $value = $item[$propertyName]
                $typeStr = $(if ($null -ne $value) { $value.GetType().Name } else { 'NULL' })
                # Write-PmcTuiLog "_GetItemProperty: returning value='$value' (type=$typeStr)"
                return $value
            }
        }
        elseif ($item.PSObject.Properties[$propertyName]) {
            $value = $item.$propertyName
            # Write-PmcTuiLog "_GetItemProperty: PSObject propertyName='$propertyName' value='$value'"
            return $value
        }

        # Write-PmcTuiLog "_GetItemProperty: propertyName='$propertyName' NOT FOUND, returning null"
        return $null
    }

    <#
    .SYNOPSIS
    Check if item has property (handles both hashtable and PSCustomObject)
    #>
    hidden [bool] _HasItemProperty([object]$item, [string]$propertyName) {
        if ($null -eq $item) { return $false }

        if ($item -is [hashtable]) {
            return $item.ContainsKey($propertyName)
        }
        else {
            return $null -ne $item.PSObject.Properties[$propertyName]
        }
    }

    # === Public API Methods ===

    <#
    .SYNOPSIS
    Set column definitions

    .PARAMETER columns
    Array of column hashtables:
    - Name: Property name (required)
    - Label: Display label (required)
    - Width: Column width in characters (required)
    - Align: 'left', 'center', 'right' (optional, default 'left')
    - Format: Scriptblock to format value (optional)
    - Sortable: Whether column is sortable (optional, default $true)
    #>
    [void] SetColumns([hashtable[]]$columns) {
        $this._columns.Clear()

        # Force array type to prevent unwrapping
        $columnsArray = @($columns)

        if ($null -eq $columnsArray -or $columnsArray.Count -eq 0) {
            throw "At least one column is required"
        }

        foreach ($col in $columnsArray) {
            if (-not $col.ContainsKey('Name')) {
                throw "Column missing 'Name' property"
            }
            if (-not $col.ContainsKey('Label')) {
                throw "Column missing 'Label' property"
            }
            if (-not $col.ContainsKey('Width')) {
                throw "Column missing 'Width' property"
            }

            # Set defaults
            if (-not $col.ContainsKey('Align')) {
                $col.Align = 'left'
            }
            if (-not $col.ContainsKey('Sortable')) {
                $col.Sortable = $true
            }

            $this._columns.Add($col)
        }
    }

    <#
    .SYNOPSIS
    Set data array

    .PARAMETER data
    Array of objects to display
    #>
    [void] SetData([array]$data) {
        try {
            # Write-PmcTuiLog "UniversalList.SetData: START" "DEBUG"
        
            if ($null -ne $data) {
                $this._data = [object[]]@($data)
            }
            else {
                $this._data = [object[]]@()
            }

            $this._filteredData = [object[]]@($this._data)
            $this._selectedIndex = 0
            $this._scrollOffset = 0
            $this._selectedIndices.Clear()

            $this._cacheGeneration++
            $this._rowCache.Clear()
            $this._cacheAccessOrder.Clear()

            $this._ApplyFilters()
            $this._ApplySearch()

            $this._InvokeCallback($this.OnDataChanged, $this._data)
            # Write-PmcTuiLog "UniversalList.SetData: COMPLETE ($($this._data.Count) items)" "DEBUG"
        }
        catch {
            # Write-PmcTuiLog "FATAL ERROR UniversalList.SetData: $_" "ERROR"
            throw
        }
    }

    <#
    .SYNOPSIS
    Get currently selected item

    .OUTPUTS
    Selected item object or $null if none selected
    #>
    [object] GetSelectedItem() {
        if ($this._filteredData.Count -eq 0) {
            return $null
        }

        if ($this._selectedIndex -ge 0 -and $this._selectedIndex -lt $this._filteredData.Count) {
            return $this._filteredData[$this._selectedIndex]
        }

        return $null
    }

    <#
    .SYNOPSIS
    Get currently selected index
    #>
    <#
    .SYNOPSIS
    Get currently selected index
    #>
    [int] GetSelectedIndex() {
        return $this._selectedIndex
    }

    <#
    .SYNOPSIS
    Get current scroll offset
    #>
    [int] GetScrollOffset() {
        return $this._scrollOffset
    }

    <#
    .SYNOPSIS
    Set selected index
    #>
    [void] SelectIndex([int]$index) {
        if ($index -ge 0 -and $index -lt $this._filteredData.Count) {
            $this._selectedIndex = $index
            $this._AdjustScrollOffset()
            $this._TriggerSelectionChanged()
        }
    }

    <#
    .SYNOPSIS
    Get all selected items (multi-select mode)

    .OUTPUTS
    Array of selected items
    #>
    [array] GetSelectedItems() {
        $selected = @()

        foreach ($index in $this._selectedIndices) {
            if ($index -ge 0 -and $index -lt $this._filteredData.Count) {
                $selected += $this._filteredData[$index]
            }
        }

        return $selected
    }

    <#
    .SYNOPSIS
    Get the count of filtered items
    #>
    [int] GetItemCount() {
        return $this._filteredData.Count
    }

    <#
    .SYNOPSIS
    Invalidate the row rendering cache.
    Call this when external state that affects row rendering changes.
    #>
    [void] InvalidateCache() {
        if ($global:PmcTuiLogLevel -ge 3) {
            Write-PmcTuiLog "UniversalList.InvalidateCache: Clearing cache (generation $($this._cacheGeneration) -> $($this._cacheGeneration + 1))" "DEBUG"
        }
        $this._cacheGeneration++
        $this._rowCache.Clear()
        $this._cacheAccessOrder.Clear()
    }

    <#
    .SYNOPSIS
    Get content hash for RenderCache (opt-in caching)
    
    .DESCRIPTION
    Returns a hash of the widget's current visual state.
    Cache will hit if:
    - Same selected index
    - Same scroll offset
    - Same data count
    - Same cache generation (internal invalidation)
    
    .OUTPUTS
    String hash of widget state
    #>
    [string] GetContentHash() {
        # Include all state that affects visual output
        return "$($this._selectedIndex):$($this._scrollOffset):$($this._filteredData.Count):$($this._cacheGeneration):$($this._sortColumn):$($this._sortAscending)"
    }

    <#
    .SYNOPSIS
    Set sort column and direction

    .PARAMETER columnName
    Column name to sort by

    .PARAMETER ascending
    Sort ascending if $true, descending if $false
    #>
    [void] SetSortColumn([string]$columnName, [bool]$ascending) {
        $this._sortColumn = $columnName
        $this._sortAscending = $ascending
        $this._ApplySort()
    }

    <#
    .SYNOPSIS
    Add an action (hotkey + callback)

    .PARAMETER key
    Hotkey character

    .PARAMETER label
    Action label for display

    .PARAMETER callback
    Scriptblock to invoke when action triggered
    #>
    [void] AddAction([string]$key, [string]$label, [scriptblock]$callback) {
        # Normalize key to lowercase for consistent lookup (HandleInput uses ToLower())
        $normalizedKey = $key.ToLower()
        $this._actions[$normalizedKey] = @{
            Label    = $label
            Callback = $callback
        }
    }

    <#
    .SYNOPSIS
    Remove an action

    .PARAMETER key
    Hotkey character
    #>
    [void] RemoveAction([string]$key) {
        $this._actions.Remove($key.ToLower())
    }

    <#
    .SYNOPSIS
    Show inline editor for an item

    .PARAMETER item
    Item to edit (or empty hashtable for new item)

    .PARAMETER fieldDefinitions
    Field definitions for InlineEditor (optional, will infer from columns)
    #>
    [void] ShowInlineEditor([object]$item, [hashtable[]]$fieldDefinitions = $null) {
        if (-not $this.AllowInlineEdit) {
            return
        }

        # Create inline editor if not exists
        if ($null -eq $this._inlineEditor) {
            $this._inlineEditor = [InlineEditor]::new()
            # Position and Size are now managed by the Layout System via TargetRegionID
        }

        # Build field definitions from columns if not provided
        if ($null -eq $fieldDefinitions) {
            $fields = @()
            foreach ($col in $this._columns) {
                $field = @{
                    Name  = $col.Name
                    Label = $col.Label
                    Type  = 'text'  # Default to text, could be smarter
                    Value = $(if ($item.($col.Name)) { $item.($col.Name) } else { "" })
                }
                $fields += $field
            }
            $fieldDefinitions = $fields
        }

        $this._inlineEditor.SetFields($fieldDefinitions)
        $this._inlineEditor.IsConfirmed = $false
        $this._inlineEditor.IsCancelled = $false

        # Set callback for when editor confirms
        $this._inlineEditor.OnConfirmed = { param($values)
            # Update item with new values
            foreach ($key in $values.Keys) {
                $item.$key = $values[$key]
            }
            $this._InvokeCallback($this.OnItemEdit, $item)
            $this._showInlineEditor = $false
        }

        $this._inlineEditor.OnCancelled = {
            $this._showInlineEditor = $false
        }

        $this._showInlineEditor = $true
    }

    <#
    .SYNOPSIS
    Show filter panel
    #>
    [void] ShowFilterPanel() {
        $this.IsInFilterMode = $true
    }

    <#
    .SYNOPSIS
    Hide filter panel
    #>
    [void] HideFilterPanel() {
        $this.IsInFilterMode = $false
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
        # DON'T handle inline editor input here - let StandardListScreen handle it
        # This prevents the list and screen from getting out of sync
        # if ($this._showInlineEditor) {
        #     $handled = $this._inlineEditor.HandleInput($keyInfo)
        #
        #     if ($this._inlineEditor.IsConfirmed -or $this._inlineEditor.IsCancelled) {
        #         $this._showInlineEditor = $false
        #     }
        #
        #     # If editor handled the key, we're done
        #     # Otherwise, fall through to allow parent/global handlers (e.g., Ctrl+Q)
        #     if ($handled) {
        #         return $true
        #     }
        #     # Don't return false here - let parent handlers have a chance
        # }

        # Route input to filter panel if shown
        if ($this.IsInFilterMode) {
            $handled = $this._filterPanel.HandleInput($keyInfo)

            # Esc closes filter panel
            if ($keyInfo.Key -eq 'Escape') {
                $this.IsInFilterMode = $false
                return $true
            }

            # If filter panel handled the key, we're done
            # Otherwise, fall through to allow parent/global handlers
            if ($handled) {
                return $true
            }
            # Don't return false here - let parent handlers have a chance
        }

        # Search mode input
        if ($this.IsInSearchMode) {
            $handled = $this._HandleSearchInput($keyInfo)
            # If search handled the key, we're done
            # Otherwise, fall through to allow parent/global handlers (e.g., Ctrl+Q)
            if ($handled) {
                return $true
            }
            # Don't return false here - let parent handlers have a chance
        }

        # Global shortcuts
        if ($keyInfo.Key -eq 'Enter') {
            # Don't activate item if inline editor is showing
            if ($this._showInlineEditor) {
                return $false  # Let parent handle it
            }
            # Activate selected item
            try {
                $selectedItem = $this.GetSelectedItem()
                if ($null -ne $selectedItem) {
                    $this._InvokeCallback($this.OnItemActivated, $selectedItem)
                }
                else {
                }
            }
            catch {
            }
            return $true
        }

        # PRIORITY: Check registered actions FIRST - screen-specific actions take precedence
        # over built-in widget behaviors (F/C/?//) AND navigation. This allows screens to override any key.
        $keyChar = $keyInfo.KeyChar.ToString().ToLower()
        if ($this._actions.ContainsKey($keyChar)) {
            $action = $this._actions[$keyChar]
            $this._InvokeCallback($action.Callback, $this)
            return $true
        }

        # Navigation
        if ($keyInfo.Key -eq 'UpArrow') {
            $this._MoveSelectionUp(1)
            return $true
        }

        if ($keyInfo.Key -eq 'DownArrow') {
            $this._MoveSelectionDown(1)
            return $true
        }

        if ($keyInfo.Key -eq 'PageUp') {
            $this._MoveSelectionUp($this.ItemsPerPage)
            return $true
        }

        if ($keyInfo.Key -eq 'PageDown') {
            $this._MoveSelectionDown($this.ItemsPerPage)
            return $true
        }

        if ($keyInfo.Key -eq 'Home') {
            if ($this._filteredData.Count -eq 0) {
                $this._selectedIndex = -1
            }
            else {
                $this._selectedIndex = 0
            }
            $this._AdjustScrollOffset()
            $this._TriggerSelectionChanged()
            return $true
        }

        if ($keyInfo.Key -eq 'End') {
            if ($this._filteredData.Count -eq 0) {
                $this._selectedIndex = -1
            }
            else {
                $this._selectedIndex = $this._filteredData.Count - 1
            }
            $this._AdjustScrollOffset()
            $this._TriggerSelectionChanged()
            return $true
        }

        # Multi-select mode
        if ($keyInfo.Key -eq 'Spacebar' -and $this.AllowMultiSelect) {
            $this._ToggleMultiSelect()
            return $true
        }

        # Enter multi-select mode
        if ($keyInfo.Key -eq 'M' -and $this.AllowMultiSelect) {
            $this.IsInMultiSelectMode = -not $this.IsInMultiSelectMode
            if (-not $this.IsInMultiSelectMode) {
                $this._selectedIndices.Clear()
            }
            return $true
        }

        # /: Toggle sort (cycle through columns)
        if ($keyInfo.KeyChar -eq '/') {
            if ($this._columns.Count -gt 0) {
                # Find current sort column index
                $currentIdx = -1
                for ($i = 0; $i -lt $this._columns.Count; $i++) {
                    if ($this._columns[$i].Name -eq $this._sortColumn) {
                        $currentIdx = $i
                        break
                    }
                }

                # Move to next column (or reverse if same column)
                if ($currentIdx -eq -1) {
                    # No sort, start with first column
                    $this._sortColumn = $this._columns[0].Name
                    $this._sortAscending = $true
                }
                elseif ($this._sortAscending) {
                    # Same column, reverse to descending
                    $this._sortAscending = $false
                }
                else {
                    # Next column, ascending
                    $nextIdx = ($currentIdx + 1) % $this._columns.Count
                    $this._sortColumn = $this._columns[$nextIdx].Name
                    $this._sortAscending = $true
                }

                # Re-sort data
                $this._ApplySort()
                return $true
            }
        }



        # ?: Search mode (filter by text) - fallback if no action registered
        if ($keyInfo.KeyChar -eq '?' -and $this.AllowSearch) {
            $this.IsInSearchMode = $true
            $this._searchText = ""
            return $true
        }

        # F: Filter mode
        if ($keyInfo.Key -eq 'F') {
            $this.ShowFilterPanel()
            return $true
        }

        # L-POL-22: Alt+Left/Right - adjust column width, Alt+0 - reset all widths
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt) {
            if ($keyInfo.Key -eq 'LeftArrow') {
                # Decrease width of current column
                if ($this._selectedColumnIndex -ge 0 -and $this._selectedColumnIndex -lt $this._columns.Count) {
                    $colName = $this._columns[$this._selectedColumnIndex].Name
                    $currentWidth = $(if ($this._columnWidths.ContainsKey($colName)) {
                            $this._columnWidths[$colName]
                        }
                        else {
                            $this._columns[$this._selectedColumnIndex].Width
                        })
                    $this._columnWidths[$colName] = [Math]::Max(5, $currentWidth - 2)
                    # Invalidate row cache
                    $this._cacheGeneration++
                    $this._rowCache.Clear()
                    $this._cacheAccessOrder.Clear()
                }
                return $true
            }
            if ($keyInfo.Key -eq 'RightArrow') {
                # Increase width of current column
                if ($this._selectedColumnIndex -ge 0 -and $this._selectedColumnIndex -lt $this._columns.Count) {
                    $colName = $this._columns[$this._selectedColumnIndex].Name
                    $currentWidth = $(if ($this._columnWidths.ContainsKey($colName)) {
                            $this._columnWidths[$colName]
                        }
                        else {
                            $this._columns[$this._selectedColumnIndex].Width
                        })
                    $this._columnWidths[$colName] = [Math]::Min(100, $currentWidth + 2)
                    # Invalidate row cache
                    $this._cacheGeneration++
                    $this._rowCache.Clear()
                    $this._cacheAccessOrder.Clear()
                }
                return $true
            }
            if ($keyInfo.Key -eq 'D0' -or $keyInfo.KeyChar -eq '0') {
                # Reset all column widths to defaults
                $this.ResetColumnWidths()
                return $true
            }
        }

        # C key - cycle selected column for width adjustment (fallback if no action registered)
        if ($keyInfo.KeyChar -eq 'c' -or $keyInfo.KeyChar -eq 'C') {
            $this._selectedColumnIndex = ($this._selectedColumnIndex + 1) % $this._columns.Count
            return $true
        }

        return $false
    }

    <#
    .SYNOPSIS
    Render the universal list using native HybridRenderEngine
    #>
    [void] RenderToEngine([object]$engine) {
        # Ensure layout is registered (for mouse/interaction if supported)
        $this.RegisterLayout($engine)

        $borderColor = $this.GetThemedColorInt('Border.Widget')
        $textColor = $this.GetThemedColorInt('Foreground.Row')
        $primaryColor = $this.GetThemedColorInt('Foreground.Title')
        $mutedColor = $this.GetThemedColorInt('Foreground.Muted')
        $successColor = $this.GetThemedColorInt('Foreground.Success')

        $rowBg = $this.GetThemedColorInt('Background.Row')
        $selBg = $this.GetThemedColorInt('Background.RowSelected')
        $selFg = $this.GetThemedColorInt('Foreground.RowSelected')
        $warnBg = $this.GetThemedColorInt('Background.Warning')

        # 1. Draw Container Box
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $borderColor, $rowBg)

        # 2. Draw Title
        if (-not [string]::IsNullOrWhiteSpace($this.Title)) {
            try {
                $engine.WriteAt($this.X + 2, $this.Y, " $($this.Title) ", $primaryColor, $rowBg)
            }
            catch {
                # Title write failure is non-critical
            }
        }


        # Header uses transparent background to show list background through
        $defaultBg = -1
        $highlightBg = $selBg
        $highlightFg = $selFg

        $currentRow = 1

        # Draw Headers (Using WriteAt - Matching FilterPanel Pattern)
        $supportsUnicode = $env:LANG -match 'UTF-8' -or [Console]::OutputEncoding.EncodingName -match 'UTF'
        $sortUpSymbol = $(if ($supportsUnicode) { "↑" } else { "^" })
        $sortDownSymbol = $(if ($supportsUnicode) { "↓" } else { "v" })

        $currentX = $this.X + 2
        for ($i = 0; $i -lt $this._columns.Count; $i++) {
            $col = $this._columns[$i]
            $label = $col.Label

            # Determine Width
            $colWidth = 10
            if ($this._columnWidths.ContainsKey($col.Name)) {
                $colWidth = $this._columnWidths[$col.Name]
            }
            elseif ($col.Width) {
                $colWidth = $col.Width
            }

            if ($this._sortColumn -eq $col.Name) {
                $sortIndicator = $(if ($this._sortAscending) { " $sortUpSymbol" } else { " $sortDownSymbol" })
                $label += $sortIndicator
            }

            # Clip Label
            if ($label.Length -gt $colWidth) {
                $label = $label.Substring(0, $colWidth)
            }
            
            # Write Header directly
            $engine.WriteAt($currentX, $this.Y + 1, $label, $primaryColor, $defaultBg)
            $currentX += $colWidth
        }
        
        # 4. Draw Rows (Virtual Scrolling with WriteAt)
        $maxVisibleRows = $this.Height - 6 
        $visibleStartIndex = $this._scrollOffset
        $itemCount = $this.GetItemCount()
        
        for ($i = 0; $i -lt $maxVisibleRows; $i++) {
            $dataIndex = $visibleStartIndex + $i
            $rowY = $this.Y + 3 + $i

            # If beyond data, fill with background (preserve borders!)
            if ($dataIndex -ge $itemCount) {
                $engine.Fill($this.X + 1, $rowY, $this.Width - 2, 1, ' ', $textColor, $rowBg)
                continue
            }

            $item = $this._filteredData[$dataIndex]
            $isSelected = ($dataIndex -eq $this._selectedIndex)
            $isMultiSelected = $this._selectedIndices.Contains($dataIndex)

            # Skip rendering selected row if inline editor is active
            if ($isSelected -and $this._showInlineEditor) {
                Write-PmcTuiLog "UniversalList.RenderToEngine: SKIPPING row $dataIndex (editor active, filling with blank)" "INFO"
                $engine.Fill($this.X + 2, $rowY, $this.Width - 4, 1, ' ', $textColor, $rowBg)
                continue
            }

            # --- ROW CACHING LOGIC ---
            # Calculate Cache Key
            # Key depends on: Data Item, Selection State, Column Widths, Theme Generation?
            # We use a simplified key for now: "DataIndex_IsSelected_IsMulti_Width_Gen"
            # Ideally we hash the item content too, but that's expensive.
            # We rely on InvalidateCache() when data changes.
            $cacheKey = "${dataIndex}_${isSelected}_${isMultiSelected}_$($this.Width)_$($this._cacheGeneration)"
            
            $cached = $null
            if ($this._rowCache.ContainsKey($cacheKey)) {
                $cached = $this._rowCache[$cacheKey]
                # Update LRU
                if ($this._cacheAccessOrder.Contains($cacheKey)) {
                    [void]$this._cacheAccessOrder.Remove($cacheKey)
                }
                [void]$this._cacheAccessOrder.AddLast($cacheKey)
            }

            if ($null -ne $cached) {
                # HIT: Write cached row
                if ($global:PmcTuiLogLevel -ge 3) {
                    Write-PmcTuiLog "UniversalList: Row $dataIndex CACHE HIT (key: $cacheKey)" "DEBUG"
                }
                $engine.WriteRow($this.X + 2, $rowY, $cached.Text, $cached.Foregrounds, $cached.Backgrounds, $cached.Attributes)
                continue
            }

            # MISS: Build Row
            if ($global:PmcTuiLogLevel -ge 3) {
                Write-PmcTuiLog "UniversalList: Row $dataIndex CACHE MISS - rebuilding (key: $cacheKey)" "DEBUG"
            }
            $rowWidth = $this.Width - 4 # Inside borders
            $rowText = [System.Text.StringBuilder]::new($rowWidth)
            $rowFgs = [int[]]::new($rowWidth)
            $rowBgs = [int[]]::new($rowWidth)
            $rowAttrs = [byte[]]::new($rowWidth)
            
            # Default colors
            $defFg = $textColor
            $defBg = $rowBg
            if ($isSelected) { $defFg = $selFg; $defBg = $selBg }
            elseif ($isMultiSelected) { $defFg = $successColor; $defBg = $rowBg }

            # Fill defaults
            for ($k = 0; $k -lt $rowWidth; $k++) {
                $rowFgs[$k] = $defFg
                $rowBgs[$k] = $defBg
                $rowAttrs[$k] = 0
            }

            # Gradient Support (if not selected)
            if (-not $isSelected -and -not $isMultiSelected) {
                $gradFgs = [PmcThemeEngine]::GetInstance().GetGradientIntArray('Foreground.Row', $rowWidth)
                if ($gradFgs.Count -eq $rowWidth) {
                    # Copy gradient
                    for ($k = 0; $k -lt $rowWidth; $k++) {
                        $rowFgs[$k] = $gradFgs[$k]
                    }
                }
            }

            $currentX = 0
            
            for ($c = 0; $c -lt $this._columns.Count; $c++) {
                $col = $this._columns[$c]
                
                # Determine Width
                $colWidth = 10
                if ($this._columnWidths.ContainsKey($col.Name)) {
                    $colWidth = $this._columnWidths[$col.Name]
                }
                elseif ($col.Width) {
                    $colWidth = $col.Width
                }
                
                # Get Value & Format
                $val = $this._GetItemProperty($item, $col.Name)
                if ($col.ContainsKey('Format') -and $col.Format) {
                    try { $val = & $col.Format $item $null } catch {}
                }
                $strVal = $(if ($val -ne $null) { $val.ToString() } else { "" })
                
                # Clip & Pad
                if ($strVal.Length -gt $colWidth) { $strVal = $strVal.Substring(0, $colWidth) }
                $strVal = $strVal.PadRight($colWidth)
                
                # Append to Row
                [void]$rowText.Append($strVal)
                
                # Apply Colors (Gradient support if not selected)
                if (-not $isSelected -and -not $isMultiSelected) {
                    # Use Theme Engine for gradient
                    # We need to map column property to theme property?
                    # Currently WriteThemedAt uses 'Foreground.Row' and 'Background.Row'
                    # which are usually solid.
                    # But if we want gradient, we need PmcThemeEngine to give us the array.
                    
                    # For now, we stick to solid colors for performance unless specified.
                    # If we want per-column coloring (e.g. status), we need logic here.
                    # But UniversalList usually uses uniform row color.
                    
                    # TODO: If we want per-cell formatting (e.g. red text), we need to parse $strVal for ANSI?
                    # UniversalList Format callbacks might return ANSI!
                    # If $strVal contains ANSI, we need to parse it into the arrays.
                    # This is complex.
                    
                    # For now, we assume Format returns PLAIN TEXT.
                    # If Format returns ANSI, this optimization breaks (text length mismatch).
                    # UniversalList documentation says Format returns string.
                    # But some users might return ANSI.
                    # If they do, we need a full ANSI parser here.
                    
                    # Simplification: We assume plain text for now.
                }
                
                $currentX += $colWidth
            }

            # Pad remaining width if any
            if ($rowText.Length -lt $rowWidth) {
                [void]$rowText.Append(' ' * ($rowWidth - $rowText.Length))
            }
            
            # Create Cache Entry
            $newCache = [CachedRow]::new()
            $newCache.Text = $rowText.ToString()
            $newCache.Foregrounds = $rowFgs
            $newCache.Backgrounds = $rowBgs
            $newCache.Attributes = $rowAttrs
            
            # Store
            $this._rowCache[$cacheKey] = $newCache
            [void]$this._cacheAccessOrder.AddLast($cacheKey)
            
            # Evict if full
            if ($this._cacheAccessOrder.Count -gt $this._maxCacheSize) {
                $oldest = $this._cacheAccessOrder.First.Value
                [void]$this._cacheAccessOrder.RemoveFirst()
                $this._rowCache.Remove($oldest)
            }
            
            # Write
            if ($global:PmcTuiLogLevel -ge 3) {
                Write-PmcTuiLog "UniversalList: Row $dataIndex rendered, text='$($newCache.Text.Substring(0, [Math]::Min(40, $newCache.Text.Length)))...'" "DEBUG"
            }
            $engine.WriteRow($this.X + 2, $rowY, $newCache.Text, $newCache.Foregrounds, $newCache.Backgrounds, $newCache.Attributes)
        }
        
        # 5. Status Footer (Item Count)
        try {
            $countText = "($($itemCount) items)"
            $engine.WriteAt($this.X + $this.Width - $countText.Length - 2, $this.Y, $countText, $mutedColor, $rowBg)
        }
        catch {
            # Item count display is non-critical
        }
        
        # 6. Inline Editor (Delegate)
        if ($this._showInlineEditor -and $this._inlineEditor) {
            $relIndex = $this._selectedIndex - $this._scrollOffset
            if ($relIndex -ge 0 -and $relIndex -lt $maxVisibleRows) {
                $rowY = $this.Y + 3 + $relIndex

                # Position editor at the selected row
                $this._inlineEditor.X = $this.X + 2
                $this._inlineEditor.Y = $rowY
                $this._inlineEditor.Width = $this.Width - 4
                $this._inlineEditor.Height = 1


                # Render Editor
                $this._inlineEditor.RenderToEngine($engine)
            }
        }
    }



    # Helper methods for search/input remain...
    # Helper methods for search/input follow...

    <#
    .SYNOPSIS
    Move selection up
    #>
    hidden [void] _MoveSelectionUp() {
        $this._MoveSelectionUp(1)
    }

    hidden [void] _MoveSelectionUp([int]$count) {
        if ($this._filteredData.Count -eq 0) {
            $this._selectedIndex = -1
        }
        else {
            $this._selectedIndex = [Math]::Max(0, $this._selectedIndex - $count)
            $this._selectedIndex = [Math]::Min($this._selectedIndex, $this._filteredData.Count - 1)
        }
        $this._AdjustScrollOffset()
        $this._TriggerSelectionChanged()
    }

    <#
    .SYNOPSIS
    Move selection down
    #>
    hidden [void] _MoveSelectionDown() {
        $this._MoveSelectionDown(1)
    }

    hidden [void] _MoveSelectionDown([int]$count) {
        if ($this._filteredData.Count -eq 0) {
            $this._selectedIndex = -1
        }
        else {
            $this._selectedIndex = [Math]::Min($this._filteredData.Count - 1, $this._selectedIndex + $count)
            $this._selectedIndex = [Math]::Max(0, $this._selectedIndex)
        }
        $this._AdjustScrollOffset()
        $this._TriggerSelectionChanged()
    }

    <#
    .SYNOPSIS
    Adjust scroll offset to keep selection visible
    #>
    hidden [void] _AdjustScrollOffset() {
        $maxVisibleRows = $this.Height - 6

        # If selected item is above visible area, scroll up
        if ($this._selectedIndex -lt $this._scrollOffset) {
            $this._scrollOffset = $this._selectedIndex
        }

        # If selected item is below visible area, scroll down
        if ($this._selectedIndex -ge ($this._scrollOffset + $maxVisibleRows)) {
            $this._scrollOffset = $this._selectedIndex - $maxVisibleRows + 1
        }

        # Clamp scroll offset
        if ($this._scrollOffset -lt 0) {
            $this._scrollOffset = 0
        }

        $maxScroll = [Math]::Max(0, $this._filteredData.Count - $maxVisibleRows)
        if ($this._scrollOffset -gt $maxScroll) {
            $this._scrollOffset = $maxScroll
        }
    }

    <#
    .SYNOPSIS
    Toggle multi-select for current item
    #>
    hidden [void] _ToggleMultiSelect() {
        # Don't toggle if no data or invalid selection
        if ($this._filteredData.Count -eq 0 -or $this._selectedIndex -lt 0) {
            return
        }

        if ($this._selectedIndices.Contains($this._selectedIndex)) {
            [void]$this._selectedIndices.Remove($this._selectedIndex)
        }
        else {
            [void]$this._selectedIndices.Add($this._selectedIndex)
        }

        $this._InvokeCallback($this.OnMultiSelectChanged, $this.GetSelectedItems())

        # Move down to next item
        $this._MoveSelectionDown(1)
    }

    <#
    .SYNOPSIS
    Trigger selection changed event
    #>
    hidden [void] _TriggerSelectionChanged() {
        $selectedItem = $this.GetSelectedItem()
        $this._InvokeCallback($this.OnSelectionChanged, $selectedItem)
    }

    <#
    .SYNOPSIS
    Apply sort to filtered data
    #>
    hidden [void] _ApplySort() {
        if ([string]::IsNullOrWhiteSpace($this._sortColumn)) {
            return
        }

        $col = $this._columns | Where-Object { $_.Name -eq $this._sortColumn } | Select-Object -First 1

        if ($null -eq $col -or ($col.ContainsKey('Sortable') -and -not $col.Sortable)) {
            return
        }

        # Sort filtered data
        if ($this._sortAscending) {
            $this._filteredData = @($this._filteredData | Sort-Object -Property $this._sortColumn)
        }
        else {
            $this._filteredData = @($this._filteredData | Sort-Object -Property $this._sortColumn -Descending)
        }
    }

    <#
    .SYNOPSIS
    Apply filters to data
    #>
    hidden [void] _ApplyFilters() {
        $this._filteredData = @($this._filterPanel.ApplyFilters($this._data))
        $this._ApplySearch()
        $this._ApplySort()

        # Reset selection with proper bounds checking
        if ($this._filteredData.Count -eq 0) {
            $this._selectedIndex = -1  # Explicitly invalid when no data
        }
        else {
            $this._selectedIndex = [Math]::Min($this._selectedIndex, $this._filteredData.Count - 1)
            $this._selectedIndex = [Math]::Max(0, $this._selectedIndex)
        }
        $this._AdjustScrollOffset()
    }

    <#
    .SYNOPSIS
    Apply search filter
    #>
    hidden [void] _ApplySearch() {
        if ([string]::IsNullOrWhiteSpace($this._searchText)) {
            return
        }

        $searchLower = $this._searchText.ToLower()
        $filtered = [System.Collections.ArrayList]::new()

        foreach ($item in $this._filteredData) {
            # Search in all columns
            $match = $false
            foreach ($col in $this._columns) {
                $value = $this._GetItemProperty($item, $col.Name)
                if ($null -eq $value) { $value = "" }
                if ($null -ne $value) {
                    $valueStr = $value.ToString().ToLower()
                    if ($valueStr.Contains($searchLower)) {
                        $match = $true
                        break
                    }
                }
            }

            if ($match) {
                [void]$filtered.Add($item)
            }
        }

        # Force array type - prevent PowerShell from unwrapping single-item arrays
        $this._filteredData = @($filtered)
    }

    <#
    .SYNOPSIS
    Handle search mode input
    #>
    hidden [bool] _HandleSearchInput([ConsoleKeyInfo]$keyInfo) {
        if ($keyInfo.Key -eq 'Escape') {
            $this.IsInSearchMode = $false
            $this._searchText = ""
            $this._ApplyFilters()
            return $true
        }

        if ($keyInfo.Key -eq 'Enter') {
            $this.IsInSearchMode = $false
            $this._ApplyFilters()
            return $true
        }

        if ($keyInfo.Key -eq 'Backspace') {
            if ($this._searchText.Length -gt 0) {
                $this._searchText = $this._searchText.Substring(0, $this._searchText.Length - 1)
                $this._ApplyFilters()
            }
            return $true
        }

        # Regular character input
        if ($keyInfo.KeyChar -ge 32 -and $keyInfo.KeyChar -le 126) {
            $this._searchText += $keyInfo.KeyChar
            $this._ApplyFilters()
            return $true
        }

        return $false
    }

    <#
    .SYNOPSIS
    L-POL-9: Get consistent color for a tag using hash-based selection

    .PARAMETER tag
    Tag string to colorize

    .OUTPUTS
    ANSI color code string
    #>
    hidden [string] _GetTagColor([string]$tag) {
        # Hash the tag name to get a consistent color
        $hash = 0
        foreach ($char in $tag.ToCharArray()) {
            $hash = ($hash * 31 + [int]$char) % 256
        }

        # Use a palette of distinct, readable colors
        $colors = @(
            "`e[94m"   # Bright blue
            "`e[92m"   # Bright green
            "`e[96m"   # Bright cyan
            "`e[93m"   # Bright yellow
            "`e[95m"   # Bright magenta
            "`e[91m"   # Bright red
            "`e[34m"   # Blue
            "`e[32m"   # Green
            "`e[36m"   # Cyan
            "`e[35m"   # Magenta
        )

        return $colors[$hash % $colors.Count]
    }

    <#
    .SYNOPSIS
    Invoke callback safely
    #>
    hidden [void] _InvokeCallback([scriptblock]$callback, $arg) {
        if ($null -ne $callback -and $callback -ne {}) {
            try {
                if ($null -ne $arg) {
                    # Use Invoke-Command with -ArgumentList to pass single arg without array wrapping
                    Invoke-Command -ScriptBlock $callback -ArgumentList (, $arg)
                }
                else {
                    & $callback
                }
            }
            catch {
                # Log callback errors but DON'T rethrow - callbacks must never crash the app
                Write-PmcTuiLog "UniversalList callback error: $($_.Exception.Message)" "ERROR"
                Write-PmcTuiLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
                # DON'T rethrow - UI callbacks must not crash
            }
        }
    }

    # Legacy rendering methods removed. Use RenderToEngine.



}

