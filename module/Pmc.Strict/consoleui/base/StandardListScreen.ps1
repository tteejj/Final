using namespace System
using namespace System.Collections.Generic
using namespace System.Text

# StandardListScreen.ps1 - Base class for ALL list-based screens
#
# This is the FOUNDATION for every screen that shows a list of items:
# - TaskListScreen
# - ProjectListScreen
# - TimeLogListScreen
# - SearchResultsScreen
# - etc.
#
# Provides:
# - UniversalList integration (columns, sorting, filtering, search)
# - FilterPanel integration (dynamic filter builder)
# - InlineEditor integration (add/edit items)
# - TaskStore integration (automatic CRUD + events)
# - Keyboard navigation (arrows, PageUp/Down, Home/End)
# - Action handling (Add, Edit, Delete, custom actions)
# - Automatic UI refresh on data changes
#
# Usage:
#   class TaskListScreen : StandardListScreen {
#       TaskListScreen() : base("TaskList", "My Tasks") {
#           # Configuration in constructor
#       }
#
#       [void] LoadData() {
#           $tasks = $this.Store.GetAllTasks() | Where { -not $_.completed }
#           $this.List.SetData($tasks)
#       }
#
#       [array] GetColumns() {
#           return @(
#               @{ Name='priority'; Label='Pri'; Width=4 }
#               @{ Name='text'; Label='Task'; Width=40 }
#               @{ Name='due'; Label='Due'; Width=12 }
#           )
#       }
#
#       [array] GetEditFields($item) {
#           return @(
#               @{ Name='text'; Type='text'; Label='Task'; Value=$item.text; Required=$true }
#               @{ Name='due'; Type='date'; Label='Due'; Value=$item.due }
#               @{ Name='priority'; Type='number'; Label='Priority'; Value=$item.priority; Min=0; Max=5 }
#           )
#       }
#   }

Set-StrictMode -Version Latest

# Load dependencies
# NOTE: These are now loaded by the launcher script in the correct order.
# Commenting out to avoid circular dependency issues.
# $scriptDir = Split-Path -Parent $PSScriptRoot
# . "$scriptDir/PmcScreen.ps1"
# . "$scriptDir/widgets/UniversalList.ps1"
# . "$scriptDir/widgets/FilterPanel.ps1"
# . "$scriptDir/widgets/InlineEditor.ps1"
# . "$scriptDir/services/TaskStore.ps1"

<#
.SYNOPSIS
Base class for all list-based screens in PMC TUI

.DESCRIPTION
StandardListScreen provides a complete list-viewing experience with:
- Universal list widget with columns, sorting, filtering
- Filter panel for advanced filtering
- Inline editor for add/edit operations
- TaskStore integration for automatic CRUD
- Event-driven UI updates
- Keyboard-driven navigation
- Extensible via abstract methods

Abstract Methods (override in subclasses):
- LoadData() - Load data into list
- GetColumns() - Define column configuration
- GetEditFields($item) - Define edit form fields

Optional Overrides:
- OnItemSelected($item) - Handle item selection
- OnItemActivated($item) - Handle item activation (Enter key)
- GetCustomActions() - Add custom actions beyond Add/Edit/Delete
- GetEntityType() - Return 'task', 'project', or 'timelog' for store operations

.EXAMPLE
# Example: List screen implementation
# class MyListScreen : StandardListScreen {
#     MyListScreen() : base("MyList", "My Items") {}
#
#     [void] LoadData() {
#         $items = $this.Store.GetAllItems()
#         $this.List.SetData($items)
#     }
#
#     [array] GetColumns() {
#         return @(
#             @{ Name='name'; Label='Name'; Width=40 }
#             @{ Name='status'; Label='Status'; Width=12 }
#         )
#     }
#
#     [array] GetEditFields($item) {
#         return @(
#             @{ Name='name'; Type='text'; Label='Name'; Value=$item.name; Required=$true }
#         )
#     }
# }
#>
class StandardListScreen : PmcScreen {
    # === Core Components ===
    [UniversalList]$List = $null
    [FilterPanel]$FilterPanel = $null
    [InlineEditor]$InlineEditor = $null
    [TaskStore]$Store = $null

    # === Component State ===
    [bool]$ShowFilterPanel = $false
    [bool]$ShowInlineEditor = $false
    [string]$EditorMode = ""  # 'add' or 'edit'
    [object]$CurrentEditItem = $null
    hidden [bool]$_isHandlingInput = $false  # Re-entry guard for HandleKeyPress

    # === Configuration ===
    [bool]$AllowAdd = $true
    [bool]$AllowEdit = $true
    [bool]$AllowDelete = $true
    [bool]$AllowFilter = $true
    [bool]$AllowSearch = $true
    [bool]$AllowMultiSelect = $true

    # === Constructor (backward compatible - no container) ===
    StandardListScreen([string]$key, [string]$title) : base($key, $title) {
        # UniversalList has its own status and action footer, so disable the screen's StatusBar
        $this.StatusBar = $null

        # Initialize components
        $this._InitializeComponents()
    }

    # === Constructor (with ServiceContainer) ===
    StandardListScreen([string]$key, [string]$title, [object]$container) : base($key, $title, $container) {
        # UniversalList has its own status and action footer, so disable the screen's StatusBar
        $this.StatusBar = $null

        # Initialize components
        $this._InitializeComponents()
    }

    # === Initialization ===

    <#
    .SYNOPSIS
    Initialize screen with render engine and load initial data
    #>
    [void] Initialize([object]$renderEngine) {
        
        # Call base class initialization
        ([PmcScreen]$this).Initialize($renderEngine)

        # Load data into the list
        $this.LoadData()

        $this.RefreshList()

    }

    # === Abstract Methods (MUST override) ===

    # === Layout Methods ===

    [void] Resize([int]$width, [int]$height) {
        # Set dimensions first
        $this.TermWidth = $width
        $this.TermHeight = $height

        # Ensure LayoutManager exists
        if (-not $this.LayoutManager) {
            $this.LayoutManager = [PmcLayoutManager]::new()
            $this.LayoutManager.DefineRegion('ListContent', 0, 6, '100%', 'FILL')
        }

        # Apply layout to Header, Footer, MenuBar, StatusBar via base
        if ($this.MenuBar) {
            $rect = $this.LayoutManager.GetRegion('MenuBar', $width, $height)
            $this.MenuBar.SetPosition($rect.X, $rect.Y)
            $this.MenuBar.SetSize($rect.Width, $rect.Height)
        }
        if ($this.Header) {
            $rect = $this.LayoutManager.GetRegion('Header', $width, $height)
            $this.Header.SetPosition($rect.X, $rect.Y)
            $this.Header.SetSize($rect.Width, $rect.Height)
        }
        if ($this.Footer) {
            $rect = $this.LayoutManager.GetRegion('Footer', $width, $height)
            $this.Footer.SetPosition($rect.X, $rect.Y)
            $this.Footer.SetSize($rect.Width, $rect.Height)
        }
        if ($this.StatusBar) {
            $rect = $this.LayoutManager.GetRegion('StatusBar', $width, $height)
            $this.StatusBar.SetPosition($rect.X, $rect.Y)
            $this.StatusBar.SetSize($rect.Width, $rect.Height)
        }

        # CRITICAL FIX: Let subclasses apply their own content layout AFTER chrome
        # Subclasses like TaskListScreen override ApplyContentLayout for 70/30 split
        $this.ApplyContentLayout($this.LayoutManager, $width, $height)

        # Resize overlays
        if ($this.FilterPanel) {
            $this.FilterPanel.SetPosition([Math]::Max(0, [Math]::Floor(($width - 80) / 2)), 5)
        }

        # InlineEditor resizes itself based on active row usually
    }

    # Default content layout - subclasses override for custom layouts like 70/30 split
    [void] ApplyContentLayout([PmcLayoutManager]$layoutManager, [int]$termWidth, [int]$termHeight) {
        # Full-width list for standard list screens
        if ($this.List) {
            try {
                $contentRect = $layoutManager.GetRegion('ListContent', $termWidth, $termHeight)
            } catch {
                # Fallback: define the region now
                $layoutManager.DefineRegion('ListContent', 0, 6, '100%', 'FILL')
                $contentRect = $layoutManager.GetRegion('ListContent', $termWidth, $termHeight)
            }
            $this.List.SetPosition($contentRect.X, $contentRect.Y)
            $this.List.SetSize($contentRect.Width, $contentRect.Height)
        }
    }

    # === Rendering ===

    <#
    .SYNOPSIS
    Render screen components to the engine
    #>
    [void] RenderToEngine([object]$engine) {

        # 1. Render base chrome (Menu, Header, Footer, etc.)
        ([PmcScreen]$this).RenderToEngine($engine)

        # 2. Render List (Main Content)
        if ($this.List) {
            # Ensure render mode is correct
            $this.List.RenderToEngine($engine)
        }

        # 3. Render Overlays (Z-ordered on top)
        if ($this.ShowFilterPanel -and $this.FilterPanel) {
            $this.FilterPanel.RenderToEngine($engine)
        }

        if ($this.ShowInlineEditor -and $this.InlineEditor) {
            # CRITICAL FIX: Position editor over the current row
            if ($this.List) {
                $selIndex = $this.List.GetSelectedIndex()
                $scrollOffset = $this.List.GetScrollOffset()
                $relativeIndex = $selIndex - $scrollOffset
                
                # Check if visible
                if ($relativeIndex -ge 0 -and $relativeIndex -lt ($this.List.Height - 4)) {
                    # List Y + TopBorder(1) + Header(1) + Separator(1) = Y+3 ??
                    # UniversalList render: Header=Y, Sep=Y+1, Row0=Y+2.
                    # Wait, if Title is empty:
                    # UniversalList (fixed layout):
                    # Y   : Top Border
                    # Y+1 : Header Labels
                    # Y+2 : Separator
                    # Y+3 : Row 0
                    # So offset should be +3.
                    $editY = $this.List.Y + 3 + $relativeIndex
                    
                    # Update Editor Geometry to match row
                    $this.InlineEditor.X = $this.List.X + 2  # Inside border
                    $this.InlineEditor.Y = $editY
                    $this.InlineEditor.Width = $this.List.Width - 4 # Inside borders
                    $this.InlineEditor.Height = 1 # Single row mode
                    
                    # Force layout recalc
                    # $this.InlineEditor.Resize(...) isn't needed if we set props directly 
                }
            }
            $this.InlineEditor.RenderToEngine($engine)
        }
    }

    # === Abstract Methods (MUST override) ===

    <#
    .SYNOPSIS
    Load data into the list (ABSTRACT - must override)
    #>
    [void] LoadData() {
        throw "LoadData() must be implemented in subclass"
    }

    <#
    .SYNOPSIS
    Get column configuration (ABSTRACT - must override)

    .OUTPUTS
    Array of column hashtables with Name, Label, Width, Align, Format properties
    #>
    [array] GetColumns() {
        throw "GetColumns() must be implemented in subclass"
    }

    <#
    .SYNOPSIS
    Get edit field configuration (ABSTRACT - must override)

    .PARAMETER item
    Item being edited (or empty hashtable for new item)

    .OUTPUTS
    Array of field hashtables for InlineEditor
    #>
    [array] GetEditFields($item) {
        throw "GetEditFields() must be implemented in subclass"
    }

    # === Optional Override Methods ===

    <#
    .SYNOPSIS
    Get entity type for store operations ('task', 'project', 'timelog')

    .OUTPUTS
    Entity type string
    #>
    [string] GetEntityType() {
        # Default to 'task' - override if using projects or timelogs
        return 'task'
    }

    <#
    .SYNOPSIS
    Handle item selection change (optional override)

    .PARAMETER item
    Selected item
    #>
    [void] OnItemSelected($item) {
        # Default: update status bar
        if ($null -ne $item -and $this.StatusBar) {
            try {
                $text = $(if ($null -ne $item.text) { $item.text } elseif ($null -ne $item.name) { $item.name } else { "Item selected" })
                $this.StatusBar.SetLeftText($text)
            }
            catch {
                # Write-PmcTuiLog "OnItemSelected: Error accessing item properties: $_" "ERROR"
            }
        }
    }

    <#
    .SYNOPSIS
    Handle item activation (Enter key) (optional override)

    .PARAMETER item
    Activated item
    #>
    [void] OnItemActivated($item) {
        # Default: open inline editor
        try {
            $this.EditItem($item)
        }
        catch {
        }
    }

    <#
    .SYNOPSIS
    Get custom actions beyond Add/Edit/Delete (optional override)

    .OUTPUTS
    Array of action hashtables with Key, Label, Callback properties
    #>
    [array] GetCustomActions() {
        return @()
    }

    # === Component Initialization ===

    <#
    .SYNOPSIS
    Initialize all components
    #>
    hidden [void] _InitializeComponents() {
        # Get terminal size
        $termSize = $this._GetTerminalSize()
        $this.TermWidth = $termSize.Width
        $this.TermHeight = $termSize.Height

        # Initialize TaskStore singleton
        $this.Store = [TaskStore]::GetInstance()

        # Initialize UniversalList
        $this.List = [UniversalList]::new()

        # LAYOUTMANAGER FIX: Use LayoutManager for positioning instead of hardcoded values
        # NOTE: List screens use full-width layout (no side margins) unlike other screens
        if (-not $this.LayoutManager) {
            $this.LayoutManager = [PmcLayoutManager]::new()
            # Define a full-width 'ListContent' region for list screens
            # X=0, Y=6 to start below header, Width=100%, Height=FILL
            $this.LayoutManager.DefineRegion('ListContent', 0, 6, '100%', 'FILL')
        }
        $contentRect = $this.LayoutManager.GetRegion('ListContent', $this.TermWidth, $this.TermHeight)
        $this.List.SetPosition($contentRect.X, $contentRect.Y)
        $this.List.SetSize($contentRect.Width, $contentRect.Height)

        $this.List.Title = "" # Empty title to avoid duplication with Screen Header
        $this.List.AllowMultiSelect = $this.AllowMultiSelect
        $this.List.AllowInlineEdit = $this.AllowEdit
        $this.List.AllowSearch = $this.AllowSearch

        # FIX Z-ORDER BUG: Disable Header separator since UniversalList draws its own box
        # The Header separator was overlapping list content (Header z=50 beats Content z=10)
        if ($this.Header) {
            $this.Header.ShowSeparator = $false
        }

        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] StandardListScreen._InitializeComponents: List created"
        # }

        # Wire up list events using GetNewClosure()
        $self = $this
        $this.List.OnSelectionChanged = {
            param($item)
            $self.OnItemSelected($item)
        }.GetNewClosure()

        $this.List.OnItemEdit = {
            param($data)
            # Data is hashtable with Item and Values keys from inline editing
            if ($data -is [hashtable] -and $data.ContainsKey('Values')) {
                $self.OnItemUpdated($data.Item, $data.Values)
            }
            else {
                # Legacy callback - just open editor
                $self.EditItem($data)
            }
        }.GetNewClosure()

        $this.List.OnItemDelete = {
            param($item)
            $self.DeleteItem($item)
        }.GetNewClosure()

        $this.List.OnItemActivated = {
            param($item)
            $self.OnItemActivated($item)
        }.GetNewClosure()

        # Initialize FilterPanel
        $this.FilterPanel = [FilterPanel]::new()
        $this.FilterPanel.SetPosition(10, 5)
        $this.FilterPanel.SetSize(80, 12)
        $this.FilterPanel.OnFiltersChanged = {
            param($filters)
            $this._ApplyFilters()
        }

        # Initialize InlineEditor
        $this.InlineEditor = [InlineEditor]::new()
        # Use properties, not methods (SetPosition/SetSize don't exist)
        $termSize = $this._GetTerminalSize()
        $this.InlineEditor.X = [Math]::Max(1, [Math]::Floor(($termSize.Width - 70) / 2))
        $this.InlineEditor.Y = [Math]::Max(3, [Math]::Floor(($termSize.Height - 15) / 2))
        $this.InlineEditor.Width = [Math]::Min(70, $termSize.Width - 2)
        $this.InlineEditor.Height = [Math]::Min(15, $termSize.Height - 4)
        # Capture $this explicitly to avoid wrong screen receiving callback
        $thisScreen = $this
        $this.InlineEditor.OnConfirmed = {
            param($text)
            $thisScreen.OnInlineEditConfirmed($text)
        }.GetNewClosure()

        $this.InlineEditor.OnCancelled = {
            $thisScreen.OnInlineEditCancelled()
        }.GetNewClosure()

        # Add widgets to content list for rendering
        $this.AddContentWidget($this.List)
        # BUG FIX: Do NOT add FilterPanel and InlineEditor to ContentWidgets.
        # They are overlay widgets managed manually in RenderToEngine for precise Z-ordering.
        # Adding them here causes double rendering (once by base PmcScreen, once by subclass).
        # $this.AddContentWidget($this.FilterPanel)
        # $this.AddContentWidget($this.InlineEditor)

        $this.InlineEditor.OnValidationFailed = {
            param($errors)
            # Show first validation error in status bar
            if ($errors -and $errors.Count -gt 0) {
                $thisScreen.SetStatusMessage($errors[0], "error")
            }
        }.GetNewClosure()

        # Wire up store events for auto-refresh
        # Use $self to capture THIS screen instance, not global current screen
        $self = $this
        $entityType = $this.GetEntityType()
        switch ($entityType) {
            'task' {
                $this.Store.OnTasksChanged = {
                    param($tasks)
                    if ($self.IsActive) {
                        $self.RefreshList()
                    }
                }.GetNewClosure()
            }
            'project' {
                $this.Store.OnProjectsChanged = {
                    param($projects)
                    if ($self.IsActive) {
                        $self.RefreshList()
                    }
                }.GetNewClosure()
            }
            'timelog' {
                $this.Store.OnTimeLogsChanged = {
                    param($logs)
                    if ($self.IsActive) {
                        $self.RefreshList()
                    }
                }.GetNewClosure()
            }
        }

        # Configure list actions
        $this._ConfigureListActions()
    }

    <#
    .SYNOPSIS
    Configure list actions (Add, Edit, Delete, + custom)
    #>
    hidden [void] _ConfigureListActions() {
        # }


        if ($this.AllowAdd) {
            # Use GetNewClosure() to capture current scope
            $addAction = {
                # Find the screen that owns this List by walking up
                $currentScreen = $global:PmcApp.CurrentScreen
                # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] Action 'a' callback: currentScreen type=$($currentScreen.GetType().Name) key=$($currentScreen.ScreenKey)"
                # }
                $currentScreen.AddItem()
            }.GetNewClosure()
            $this.List.AddAction('a', 'Add', $addAction)
        }

        if ($this.AllowEdit) {
            $editAction = {
                $currentScreen = $global:PmcApp.CurrentScreen
                $selectedItem = $currentScreen.List.GetSelectedItem()
                if ($null -ne $selectedItem) {
                    $currentScreen.EditItem($selectedItem)
                }
            }.GetNewClosure()
            $this.List.AddAction('e', 'Edit', $editAction)
        }


        # Add custom actions from subclass
        try {
            $customActions = $this.GetCustomActions()
            $actionCount = $(if ($customActions -is [array]) { $customActions.Count } else { 1 })
            if ($null -ne $customActions) {
                foreach ($action in $customActions) {
                    if ($null -ne $action -and $action -is [hashtable] -and $action.ContainsKey('Key') -and $action.ContainsKey('Label') -and $action.ContainsKey('Callback')) {
                        $this.List.AddAction($action.Key, $action.Label, $action.Callback)
                    }
                }
            }
        }
        catch {
            # Write-PmcTuiLog "_ConfigureListActions: Error adding custom actions: $_" "ERROR"
            # Write-PmcTuiLog "_ConfigureListActions: Error stack: $($_.ScriptStackTrace)" "ERROR"
        }
    }

    # === Lifecycle Methods ===

    <#
    .SYNOPSIS
    Called when screen enters view
    #>
    [void] OnEnter() {
        $this.IsActive = $true

        # CRITICAL FIX: Force layout update on enter to ensure correct sizing
        # This fixes invisible MenuBar/Footer issues caused by 0x0 size
        $termSize = $this._GetTerminalSize()
        $this.Resize($termSize.Width, $termSize.Height)

        # Configure list actions (ensures custom actions are registered even for singleton screens)
        $this._ConfigureListActions()

        # Set columns
        try {
            $columns = $this.GetColumns()
            $this.List.SetColumns($columns)
        }
        catch {
            throw
        }

        # Load data
        try {
            $this.LoadData()
        }
        catch {
            throw
        }

        # Update header breadcrumb
        if ($this.Header) {
            $this.Header.SetBreadcrumb(@("Home", $this.ScreenTitle))
        }

        # Update status bar
        if ($this.StatusBar) {
            $itemCount = $this.List.GetItemCount()
            $this.StatusBar.SetLeftText("$itemCount items")
        }

    }

    <#
    .SYNOPSIS
    Called when screen exits view
    #>
    [void] OnDoExit() {
        $this.IsActive = $false

        # Cleanup event handlers to prevent memory leaks
        $entityType = $this.GetEntityType()
        switch ($entityType) {
            'task' {
                $this.Store.OnTasksChanged = $null
            }
            'project' {
                $this.Store.OnProjectsChanged = $null
            }
            'timelog' {
                $this.Store.OnTimeLogsChanged = $null
            }
        }
    }

    # === CRUD Operations ===

    <#
    .SYNOPSIS
    Add a new item
    #>
    [void] AddItem() {
        # DEBUG logging - ENABLED to trace add operation bugs
        # Write-PmcTuiLog "*** STANDARDLISTSCREEN.ADDITEM CALLED on type=$($this.GetType().Name) key=$($this.ScreenKey) ***" "INFO"

        $this.EditorMode = 'add'
        $this.CurrentEditItem = @{}
        $fields = $this.GetEditFields($this.CurrentEditItem)

        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] Got $($fields.Count) edit fields"
        # }

        $this.InlineEditor.LayoutMode = "horizontal"
        # Write-PmcTuiLog "StandardListScreen.AddItem: About to SetFields with $($fields.Count) fields" "DEBUG"
        $this.InlineEditor.SetFields($fields)
        # Write-PmcTuiLog "StandardListScreen.AddItem: SetFields completed successfully" "DEBUG"
        $this.InlineEditor.Title = "Add New"

        # Position editor at end of list (or first row if empty)
        $itemCount = $(if ($this.List._filteredData) { $this.List._filteredData.Count } else { 0 })
        $this.List._selectedIndex = $itemCount  # Select the "new row" position

        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] AddItem: Set selectedIndex=$itemCount for add mode"
        # }

        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] AddItem: About to set ShowInlineEditor=true (currently: $($this.ShowInlineEditor))"
        # }

        $this.ShowInlineEditor = $true

        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] AddItem: ShowInlineEditor set to: $($this.ShowInlineEditor)"
        # }

        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] AddItem: Exiting (ShowInlineEditor=$($this.ShowInlineEditor))"
        # }
    }

    <#
    .SYNOPSIS
    Edit an existing item

    .PARAMETER item
    Item to edit
    #>
    [void] EditItem($item) {
        # Write-PmcTuiLog "*** STANDARDLISTSCREEN.EDITITEM CALLED (base class) - item type=$($item.GetType().Name) ***" "WARN"
        if ($null -eq $item) {
            return
        }

        $this.EditorMode = 'edit'
        $this.CurrentEditItem = $item

        $fields = $this.GetEditFields($item)
        foreach ($field in $fields) {
        }

        $this.InlineEditor.LayoutMode = "horizontal"

        $this.InlineEditor.SetFields($fields)

        $this.InlineEditor.Title = "Edit"
        $this.ShowInlineEditor = $true
    }

    <#
    .SYNOPSIS
    Delete an item with confirmation

    .PARAMETER item
    Item to delete
    #>
    [void] DeleteItem($item) {
        if ($null -eq $item) {
            return
        }

        # MEDIUM FIX #13: Add simple inline confirmation before delete
        # Get item name/description for confirmation message
        $itemDesc = ""
        if ($item.text) {
            $itemDesc = $item.text
        }
        elseif ($item.name) {
            $itemDesc = $item.name
        }
        elseif ($item.title) {
            $itemDesc = $item.title
        }
        elseif ($item.id) {
            $itemDesc = "ID $($item.id)"
        }
        else {
            $itemDesc = "this item"
        }

        # Show confirmation in status bar and wait for Y/N
        if ($this.StatusBar) {
            $this.StatusBar.SetLeftText("Delete '$itemDesc'? Press Y to confirm, any other key to cancel")
            $this.Render() | Out-Host
            $confirmKey = [Console]::ReadKey($true)

            if ($confirmKey.KeyChar -ne 'y' -and $confirmKey.KeyChar -ne 'Y') {
                $this.StatusBar.SetLeftText("Delete cancelled")
                return
            }
        }

        # Try to call subclass-specific delete handler first
        try {
            $this.OnItemDeleted($item)
            # If OnItemDeleted is implemented and doesn't throw, assume success
            if ($this.StatusBar) {
                $this.StatusBar.SetLeftText("Item deleted: $itemDesc")
            }
            return
        }
        catch {
            # If OnItemDeleted throws "must be implemented" or similar, fall through to default behavior
            if ($_.Exception.Message -notmatch "must be implemented") {
                # Real error - report it
                if ($this.StatusBar) {
                    $this.StatusBar.SetLeftText("Delete failed: $($_.Exception.Message)")
                }
                return
            }
        }

        # Default behavior for TaskStore entity types
        $entityType = $this.GetEntityType()
        $success = $false

        switch ($entityType) {
            'task' {
                if ($null -ne $item.id) {
                    $success = $this.Store.DeleteTask($item.id)
                }
            }
            'project' {
                if ($null -ne $item.name) {
                    $success = $this.Store.DeleteProject($item.name)
                }
            }
            'timelog' {
                if ($null -ne $item.id) {
                    $success = $this.Store.DeleteTimeLog($item.id)
                }
            }
        }

        if ($success) {
            if ($this.StatusBar) {
                $this.StatusBar.SetLeftText("Item deleted: $itemDesc")
            }
        }
        else {
            if ($this.StatusBar) {
                $this.StatusBar.SetLeftText("Failed to delete: $($this.Store.LastError)")
            }
        }
    }

    <#
    .SYNOPSIS
    Save edited item to store

    .PARAMETER values
    Field values from InlineEditor
    #>
    hidden [void] _SaveEditedItem($values) {
        if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
            # Write-PmcTuiLog "StandardListScreen._SaveEditedItem: Mode=$($this.EditorMode) Values=$($values | ConvertTo-Json -Compress)" "DEBUG"
        }

        try {
            if ($this.EditorMode -eq 'add') {
                # Call subclass callback for item creation
                $this.OnItemCreated($values)
            }
            elseif ($this.EditorMode -eq 'edit') {
                # Call subclass callback for item update
                $this.OnItemUpdated($this.CurrentEditItem, $values)
            }
            else {
                # Write-PmcTuiLog "ERROR: EditorMode is '$($this.EditorMode)' - expected 'add' or 'edit'" "ERROR"
                $this.SetStatusMessage("Invalid editor mode", "error")
                return
            }

            # Only close editor on success
            $this.ShowInlineEditor = $false
            $this.EditorMode = ""
            $this.CurrentEditItem = $null

        }
        catch {
            # Write-PmcTuiLog "_SaveEditedItem failed: $_" "ERROR"
            # Write-PmcTuiLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
            $this.SetStatusMessage("Failed to save: $($_.Exception.Message)", "error")
            # Keep editor open so user can retry
        }

        # NOTE: Don't reset IsConfirmed/IsCancelled here - HandleKeyPress checks them
        # They will be reset when SetFields() is called for the next add/edit
    }

    <#
    .SYNOPSIS
    Virtual method called when inline editor is confirmed
    Subclasses should override to handle save, or rely on OnItemCreated/OnItemUpdated
    #>
    [void] OnInlineEditConfirmed([hashtable]$values) {
        # Default implementation: delegate to _SaveEditedItem which calls OnItemCreated or OnItemUpdated
        # This ensures all screens work even if they don't override this method
        # Write-PmcTuiLog "StandardListScreen.OnInlineEditConfirmed called - EditorMode=$($this.EditorMode)" "DEBUG"

        # Call save which will dispatch to OnItemCreated or OnItemUpdated
        $this._SaveEditedItem($values)
    }

    # === Filtering ===

    <#
    .SYNOPSIS
    Apply filters to list data
    #>
    hidden [void] _ApplyFilters() {
        $this.LoadData()  # Reload data, filters are applied by FilterPanel
    }

    <#
    .SYNOPSIS
    Toggle filter panel visibility
    #>
    [void] ToggleFilterPanel() {
        $this.ShowFilterPanel = -not $this.ShowFilterPanel
    }

    # === Status Messages ===

    <#
    .SYNOPSIS
    Set status message (displayed in status bar or logged)

    .PARAMETER message
    Message to display

    .PARAMETER level
    Message level: info, success, warning, error
    #>
    [void] SetStatusMessage([string]$message, [string]$level = "info") {
        # Log the message
        # }

        # If we have a status bar, update it
        if ($this.StatusBar) {
            $this.StatusBar.SetRightText($message)
        }

        # TODO: Could show a temporary overlay notification
    }

    # === List Refresh ===

    <#
    .SYNOPSIS
    Refresh the list (reload data)
    #>
    [void] RefreshList() {
        $this.LoadData()
    }

    # === Input Handling ===

    <#
    .SYNOPSIS
    Handle keyboard input

    .PARAMETER keyInfo
    ConsoleKeyInfo from [Console]::ReadKey($true)

    .OUTPUTS
    True if input was handled, False otherwise
    #>
    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # DEBUG: Log ALL Enter key presses at the very top
        if ($keyInfo.Key -eq 'Enter') {
        }

        # Re-entry guard: prevent infinite recursion
        if ($this._isHandlingInput) {
            if ($keyInfo.Key -eq 'Enter') {
            }
            return $false
        }
        $this._isHandlingInput = $true
        try {
            # Check Alt+key for menu bar first (before editor/filter)
            if ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt) {
                if ($null -ne $this.MenuBar -and $this.MenuBar.HandleKeyPress($keyInfo)) {
                    return $true
                }
            }

            # If menu is active, route all keys to it FIRST (including Esc to close)
            if ($null -ne $this.MenuBar -and $this.MenuBar.IsActive) {
                if ($this.MenuBar.HandleKeyPress($keyInfo)) {
                    return $true
                }
            }

            # CRITICAL FIX: Route to inline editor BEFORE other menu handling
            # This allows inline editor to handle Esc/Enter instead of menu stealing them
            if ($this.ShowInlineEditor) {
                # DEBUG: Trace input to find why typing doesn't work (COMMENTED OUT FOR PERFORMANCE)
                # Add-Content -Path "/tmp/pmc-input-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] StandardListScreen.HandleKeyPress: ShowInlineEditor=$($this.ShowInlineEditor) Key=$($keyInfo.Key) Char='$($keyInfo.KeyChar)' InlineEditor=$($null -ne $this.InlineEditor) _fields=$($this.InlineEditor._fields.Count) _currentFieldIndex=$($this.InlineEditor._currentFieldIndex)"
                # Write-PmcTuiLog "StandardListScreen: Routing to InlineEditor (Key=$($keyInfo.Key))" "DEBUG"
                $handled = $this.InlineEditor.HandleInput($keyInfo)
                # Write-PmcTuiLog "StandardListScreen: After HandleInput - IsConfirmed=$($this.InlineEditor.IsConfirmed) IsCancelled=$($this.InlineEditor.IsCancelled) ShowInlineEditor=$($this.ShowInlineEditor)" "DEBUG"

                # Check if editor needs clear (field widget was closed)
                if ($this.InlineEditor.NeedsClear) {
                    # Write-PmcTuiLog "StandardListScreen: Editor field widget closed - PROPAGATING CLEAR TO SCREEN" "DEBUG"
                    # CRITICAL FIX: Propagate NeedsClear to screen to remove overlay widget rendering
                    $this.NeedsClear = $true
                    $this.InlineEditor.NeedsClear = $false  # Reset flag
                    return $true
                }

                # Check if editor closed
                if ($this.InlineEditor.IsConfirmed -or $this.InlineEditor.IsCancelled) {
                    # Write-PmcTuiLog "StandardListScreen: Editor confirmed/cancelled - closing editor NO CLEAR" "DEBUG"

                    # BUG FIX: Save EditorMode BEFORE it gets cleared by OnCancelled callback
                    $wasAddMode = ($this.EditorMode -eq 'add')

                    $this.ShowInlineEditor = $false
                    # CRITICAL: Also update the list's editor state to stay in sync
                    $this.List._showInlineEditor = $false

                    # FIX: Invalidate the editor row region so differential renderer redraws it
                    # Without this, the dark grey background from the inline editor remains stale
                    if ($this.RenderEngine -and $this.InlineEditor) {
                        $editorY = $this.InlineEditor.Y
                        $this.RenderEngine.InvalidateCachedRegion($editorY, $editorY + 1)
                        # Write-PmcTuiLog "StandardListScreen: Invalidated editor row Y=$editorY after close" "DEBUG"
                    }

                    # BUG FIX: Restore selectedIndex after exiting add mode
                    # When in add mode, selectedIndex is set to itemCount (one past the last item)
                    # When cancelled, we need to restore it to a valid row index so the user can navigate
                    if ($wasAddMode) {
                        $itemCount = $(if ($this.List._filteredData) { $this.List._filteredData.Count } else { 0 })
                        if ($itemCount -gt 0) {
                            # Restore to last item (or first item if we just added one on confirm)
                            if ($this.InlineEditor.IsCancelled) {
                                # Cancelled - go back to last existing item
                                $this.List._selectedIndex = $itemCount - 1
                            }
                            else {
                                # Confirmed - select the newly added item (if it was added)
                                # Keep current selectedIndex if within bounds, otherwise select last
                                if ($this.List._selectedIndex -ge $itemCount) {
                                    $this.List._selectedIndex = $itemCount - 1
                                }
                            }
                        }
                        else {
                            # No items - select none (will be 0 when items are added)
                            $this.List._selectedIndex = 0
                        }
                        # Write-PmcTuiLog "StandardListScreen: Restored selectedIndex to $($this.List._selectedIndex) after add mode exit (itemCount=$itemCount)" "DEBUG"
                    }

                    # Clear EditorMode AFTER checking if it was add mode
                    $this.EditorMode = ""

                    # NOTE: NeedsClear NOT set - screen should not clear when closing inline editor
                    # MUST return true to trigger re-render
                    return $true
                }

                # Write-PmcTuiLog "StandardListScreen: After close check - ShowInlineEditor=$($this.ShowInlineEditor)" "DEBUG"

                # If editor handled the key, we're done
                if ($handled) {
                    return $true
                }
                # FIX: If editor is showing but didn't handle key, consume it anyway
                # This prevents keys from falling through to List.HandleInput when editor is active
                # Only allow global shortcuts (F10, Esc, ?) to pass through
                if ($keyInfo.Key -ne [ConsoleKey]::F10 -and $keyInfo.Key -ne [ConsoleKey]::Escape -and $keyInfo.KeyChar -ne '?') {
                    return $true
                }
            }

            # Route to filter panel if shown
            if ($this.ShowFilterPanel) {
                $handled = $this.FilterPanel.HandleInput($keyInfo)

                # Esc closes filter panel
                if ($keyInfo.Key -eq 'Escape') {
                    $this.ShowFilterPanel = $false
                    return $true
                }

                # If filter panel handled the key, we're done
                if ($handled) {
                    return $true
                }
                # Otherwise, fall through to global shortcuts
            }

            # F10 OR ESC activates menu (only if not already active and no editor/filter showing)
            if ($keyInfo.Key -eq [ConsoleKey]::F10 -or $keyInfo.Key -eq [ConsoleKey]::Escape) {
                if ($null -ne $this.MenuBar -and -not $this.MenuBar.IsActive -and -not $this.ShowInlineEditor -and -not $this.ShowFilterPanel) {
                    $this.MenuBar.Activate()
                    return $true
                }
            }

            # Global shortcuts (ONLY when editor/filter NOT showing - otherwise they block typing!)
            if (-not $this.ShowInlineEditor -and -not $this.ShowFilterPanel) {
                # ? = Help
                if ($keyInfo.KeyChar -eq '?') {
                    . "$PSScriptRoot/../screens/HelpViewScreen.ps1"
                    $screen = [HelpViewScreen]::new()
                    $this.App.PushScreen($screen)
                    return $true
                }

                if (($keyInfo.KeyChar -eq 'f' -or $keyInfo.KeyChar -eq 'F') -and $this.AllowFilter) {
                    $this.ToggleFilterPanel()
                    return $true
                }

                if ($keyInfo.KeyChar -eq 'r' -or $keyInfo.KeyChar -eq 'R') {
                    # Refresh
                    $this.RefreshList()
                    return $true
                }

                # Delete key: Delete selected item
                if ($keyInfo.Key -eq [ConsoleKey]::Delete -and $this.AllowDelete) {
                    $selectedItem = $this.List.GetSelectedItem()
                    if ($null -ne $selectedItem) {
                        $this.DeleteItem($selectedItem)
                    }
                    return $true
                }
            }

            # Route to list ONLY if editor and filter are NOT showing
            # CRITICAL FIX: When editor is open, don't let list actions (a/e/d) trigger
            # This prevents accidentally opening a new editor or deleting items while editing
            if ($keyInfo.Key -eq 'Enter') {
            }
            if (-not $this.ShowInlineEditor -and -not $this.ShowFilterPanel) {
                return $this.List.HandleInput($keyInfo)
            }

            # Editor/filter is showing but didn't handle key - ignore it
            if ($keyInfo.Key -eq 'Enter') {
            }
            return $false
        }
        finally {
            $this._isHandlingInput = $false
        }
    }

    # === Rendering ===

    <#
    .SYNOPSIS
    Render content area directly to engine
    Override from PmcScreen to use optimized list rendering
    #>
    [void] RenderContentToEngine([object]$engine) {
        if ($null -eq $this.List) {
            throw "CRITICAL ERROR: StandardListScreen.List is null"
        }

        # Sync state
        if ($this.ShowInlineEditor -and $this.InlineEditor) {
            $this.List._showInlineEditor = $true
            $this.List._inlineEditor = $this.InlineEditor
        }
        else {
            $this.List._showInlineEditor = $false
        }
        
        $this.List.IsInFilterMode = $this.ShowFilterPanel

        # Render list directly
        if ($this.List.PSObject.Methods['RenderToEngine']) {
            $this.List.RenderToEngine($engine)
        }
        
        # Render filter panel overlay if needed
        if ($this.ShowFilterPanel) {
            $output = $this.FilterPanel.Render()
            if ($output) {
                # HybridRenderEngine.WriteAt handles ANSI parsing
                $engine.WriteAt(0, 0, $output)
            }
        }
    }

    <#
    .SYNOPSIS
    Render the screen content area

    .OUTPUTS
    ANSI string ready for display
    #>
    [string] RenderContent() {
        # Priority rendering order: editor INLINE with list > filter panel > list
        $editItemId = $(if ($null -ne $this.CurrentEditItem -and $this.CurrentEditItem.PSObject.Properties['id']) { $this.CurrentEditItem.id } else { "null" })


        # }

        # HIGH FIX #8: Throw error instead of silent failure to make debugging easier
        if ($null -eq $this.List) {
            $errorMsg = "CRITICAL ERROR: StandardListScreen.List is null - screen was not properly initialized"
            # }
            throw $errorMsg
        }

        # If showing inline editor, pass it to the list for inline rendering BEFORE calling Render()
        if ($this.ShowInlineEditor -and $this.InlineEditor) {
            # Set inline editor mode on list
            $this.List._showInlineEditor = $true
            $this.List._inlineEditor = $this.InlineEditor
        }
        else {
            $this.List._showInlineEditor = $false
        }

        # Render list (it will handle inline editor internally)
        try {
            $listOutput = $this.List.Render()
        }
        catch {
            throw
        }

        if ($this.ShowFilterPanel) {
            # }
            # Render list with filter panel as overlay
            $filterContent = $this.FilterPanel.Render()
            return $listOutput + "`n" + $filterContent
        }


        # }
        return $listOutput
    }


    # === Helper Methods ===

    
    <#
    .SYNOPSIS
    Get terminal size

    .OUTPUTS
    Hashtable with Width and Height properties
    #>
    hidden [hashtable] _GetTerminalSize() {
        try {
            $width = [Console]::WindowWidth
            $height = [Console]::WindowHeight
        }
        catch {
            # Fallback to defaults if Console methods fail
            $width = 80
            $height = 24
        }
        return @{ Width = $width; Height = $height }
    }
}
