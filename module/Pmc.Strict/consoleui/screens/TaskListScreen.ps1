# TaskListScreen.ps1 - Complete Task List with CRUD + Filters
#
# Full-featured task list screen with:
# - UniversalList integration (sorting, virtual scrolling, multi-select)
# - FilterPanel integration (dynamic filtering by project, priority, due date, tags, status)
# - InlineEditor integration (full CRUD operations)
# - TaskStore integration (observable data layer with auto-refresh)
# - Keyboard shortcuts (CRUD operations, filters, search)
# - Custom actions (complete, archive, clone, bulk operations)
#
# Usage:
#   $screen = New-Object TaskListScreen
#   $screen.Initialize()
#   $screen.Render()
#   $screen.HandleInput($key)

using namespace System

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Complete task list screen with full CRUD and filtering

.DESCRIPTION
Extends StandardListScreen to provide:
- Full task CRUD (Create, Read, Update, Delete)
- Dynamic filtering (project, priority, due date, tags, status, text search)
- Sorting by any column
- Multi-select bulk operations
- Quick actions (complete, archive, clone)
- Auto-refresh on data changes
- Inline editing
- Comprehensive keyboard shortcuts

.EXAMPLE
$screen = New-Object TaskListScreen
$screen.Initialize()
while (-not $screen.ShouldExit) {
    $output = $screen.Render()
    # Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TaskListScreen] Rendered output"
    $key = [Console]::ReadKey($true)
    $screen.HandleInput($key)
}
#>

# Helper function to get title based on view mode
function Get-TaskListTitle {
    param([string]$viewMode)
    switch ($viewMode) {
        'all' { return 'All Tasks' }
        'active' { return 'Active Tasks' }
        'completed' { return 'Completed Tasks' }
        'overdue' { return 'Overdue Tasks' }
        'today' { return "Today's Tasks" }
        'tomorrow' { return "Tomorrow's Tasks" }
        'week' { return 'This Week' }
        'nextactions' { return 'Next Actions' }
        'noduedate' { return 'No Due Date' }
        'month' { return 'This Month' }
        'agenda' { return 'Agenda View' }
        'upcoming' { return 'Upcoming Tasks' }
        default { return 'Task List' }
    }
}

class TaskListScreen : StandardListScreen {
    # Constants for layout calculations
    static hidden [int]$LIST_HEADER_ROWS = 3  # Header + separator + first data row offset
    static hidden [double]$COL_WIDTH_TEXT = 0.30     # 30% for text column
    static hidden [double]$COL_WIDTH_DETAILS = 0.25  # 25% for details column
    static hidden [double]$COL_WIDTH_DUE = 0.12      # 12% for due column
    static hidden [double]$COL_WIDTH_PROJECT = 0.18  # 18% for project column
    static hidden [double]$COL_WIDTH_TAGS = 0.15     # 15% for tags column

    # Additional state
    [string]$_viewMode = 'all'  # all, active, completed, overdue, today, tomorrow, week, nextactions, noduedate, month, agenda, upcoming
    [bool]$_showCompleted = $true
    [string]$_sortColumn = 'due'
    [bool]$_sortAscending = $true
    [hashtable]$_stats = @{}
    [hashtable]$_collapsedSubtasks = @{}

    # Caching for performance
    hidden [array]$_cachedFilteredTasks = $null
    hidden [string]$_cacheKey = ""  # viewMode:sortColumn:sortAsc:showCompleted
    # BUG-13 FIX: Cache parent-child relationships for O(1) lookups
    hidden [hashtable]$_childrenIndex = @{}

    # L-POL-14: Strikethrough support detection
    hidden [bool]$_supportsStrikethrough = $true  # Assume support, can be overridden

    # BUG-2 FIX: Loading state flag to prevent reentrant LoadData() calls
    hidden [bool]$_isLoading = $false

    # Detail pane for 70/30 split layout
    # DetailPane shows task details on the right (30% width)
    # Default: visible (70/30 split), toggle with 'o' key for full-width list
    [PmcPanel]$DetailPane = $null
    hidden [bool]$_showDetailPane = $true  # true = detail pane visible by default

    # Telemetry helper for tracking user actions
    hidden [void] _EmitTelemetry([string]$eventName, [hashtable]$data) {
        # TODO: Implement telemetry when metrics system is available
        # For now, log at DEBUG level for observability
        # Write-PmcTuiLog "Telemetry: $eventName - $($data | ConvertTo-Json -Compress)" "DEBUG"
    }

    # LOW FIX TLS-L4: Centralized initialization to reduce constructor duplication
    hidden [void] _InitializeTaskListScreen([string]$viewMode) {
        $this._viewMode = $viewMode
        $this._showCompleted = $false
        $this._sortColumn = 'due'
        $this._sortAscending = $true
        # CRITICAL FIX: Keep AllowEdit = true so 'e' key triggers editing
        # We handle BOTH 'e' key and Enter key for inline editing
        # (AllowEdit defaults to true in base class, no need to set it)
        $this._SetupMenus()
    }

    # Constructor with optional view mode
    TaskListScreen() : base("TaskList", "Task List") {
        $this._InitializeTaskListScreen('active')
    }

    # Constructor with container (DI-enabled)
    TaskListScreen([object]$container) : base("TaskList", "Tasks", $container) {
        # Write-PmcTuiLog "TaskListScreen: Constructor started" "DEBUG"
        
        # Configure based on view mode (defaulting to 'active' or 'all')
        $this._InitializeTaskListScreen('active') 
        
        # Write-PmcTuiLog "TaskListScreen: Constructor completed" "DEBUG"
    }

    # Constructor with explicit view mode
    TaskListScreen([string]$viewMode) : base("TaskList", (Get-TaskListTitle $viewMode)) {
        $this._InitializeTaskListScreen($viewMode)
    }

    # Constructor with container and view mode (DI-enabled)
    TaskListScreen([object]$container, [string]$viewMode) : base("TaskList", (Get-TaskListTitle $viewMode), $container) {
        $this._InitializeTaskListScreen($viewMode)
    }

    # Test constructor - allows injecting mock store for unit testing
    # This enables testing without real TaskStore dependencies
    TaskListScreen([object]$container, [object]$mockStore, [string]$viewMode) : base("TaskList", (Get-TaskListTitle $viewMode), $container) {
        if ($mockStore) {
            $this.Store = $mockStore
        }
        $this._InitializeTaskListScreen($viewMode)
    }

    # Override to add cache invalidation to TaskStore event handler
    hidden [void] _InitializeComponents() {
        # Call parent initialization first
        ([StandardListScreen]$this)._InitializeComponents()

        # FIX Z-ORDER BUG: Disable Header separator since UniversalList draws its own box
        # The Header separator was overlapping task rows at Y=7 (Header z=50 beats Content z=10)
        if ($this.Header) {
            $this.Header.ShowSeparator = $false
        }

        # CRITICAL FIX: Override the TaskStore event handler to invalidate cache before refresh
        # BUG-2 FIX: Check _isLoading flag to prevent reentrant LoadData() calls
        $self = $this
        $this.Store.OnTasksChanged = {
            param($tasks)
            # Invalidate cache so LoadData will reload
            $self._cachedFilteredTasks = $null
            $self._cacheKey = ""
            # CRITICAL FIX: Invalidate children index when tasks change
            # This ensures hierarchy changes are reflected immediately
            $self._childrenIndex = @{}
            # Then refresh the list ONLY if not currently loading (prevents race condition)
            if ($self.IsActive -and -not $self._isLoading) {
                $self.RefreshList()
            }
        }.GetNewClosure()

        # CRITICAL: Re-register the Edit action to use OUR EditItem override, not the parent's
        # Write-PmcTuiLog "TaskListScreen._InitializeComponents: AllowEdit=$($this.AllowEdit)" "DEBUG"
        if ($this.AllowEdit) {
            # if ($global:PmcTuiLogFile) {
            #     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [DEBUG] TaskListScreen: Re-registering Edit action"
            $self = $this
            $editAction = {
                $selectedItem = $self.List.GetSelectedItem()
                if ($null -ne $selectedItem) {
                    $self.EditItem($selectedItem)
                }
            }.GetNewClosure()
            # Remove old action and add new one
            $this.List.RemoveAction('e')
            $this.List.AddAction('e', 'Edit', $editAction)
            # if ($global:PmcTuiLogFile) {
            #     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [DEBUG] TaskListScreen: Edit action registered"
        }

        # CRITICAL: Set GetIsInEditMode callback so UniversalList doesn't render row highlight in edit mode
        # ONLY return true for the item being edited, not all items!
        $this.List.GetIsInEditMode = {
            param($item)
            # DEBUG: Log what we're checking
            $itemId = $(if ($item -and $item.id) { $item.id } else { "NO-ID" })
            # Write-PmcTuiLog "GetIsInEditMode called for item: $itemId" "DEBUG"

            # In ADD mode, don't match any existing items - editor renders separately
            if ($self.ShowInlineEditor -and $self.EditorMode -eq 'add') {
                # Write-PmcTuiLog "Add mode - editor positioning handled separately" "DEBUG"
                return $false
            }

            # Only skip highlighting for the item currently being edited
            if ($self.ShowInlineEditor -and $self.CurrentEditItem) {
                $editId = $(if ($self.CurrentEditItem.id) { $self.CurrentEditItem.id } else { "NO-ID" })
                # Write-PmcTuiLog "Comparing: item.id=$itemId vs CurrentEditItem.id=$editId" "DEBUG"

                # Check if this is the item being edited
                if ($item.id -and $self.CurrentEditItem.id -and $item.id -eq $self.CurrentEditItem.id) {
                    # Write-PmcTuiLog "MATCH! Returning TRUE for edit mode" "DEBUG"
                    return $true
                }
            }
            # Write-PmcTuiLog "No match, returning FALSE" "DEBUG"
            return $false
        }.GetNewClosure()

        # Initialize DetailPane for 70/30 split layout
        $this.DetailPane = [PmcPanel]::new("Task Details [70/30]")
        $this.DetailPane.SetBorderStyle('rounded')
        $this.DetailPane.SetContent("Select a task to view details", 'left')
        $this.AddContentWidget($this.DetailPane)
    }

    # Setup menu items using MenuRegistry
    hidden [void] _SetupMenus() {
        # Get singleton MenuRegistry instance
        . "$PSScriptRoot/../services/MenuRegistry.ps1"
        $registry = [MenuRegistry]::GetInstance()

        # Load menu items from manifest (only if not already loaded)
        $tasksMenuItems = $registry.GetMenuItems('Tasks')
        if (-not $tasksMenuItems -or @($tasksMenuItems).Count -eq 0) {
            $manifestPath = Join-Path $PSScriptRoot "MenuItems.psd1"

            # Get or create the service container
            if (-not $global:PmcContainer) {
                # Load ServiceContainer if not already loaded
                . "$PSScriptRoot/../ServiceContainer.ps1"
                $global:PmcContainer = [ServiceContainer]::new()

                # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TaskListScreen: Created new ServiceContainer"
            }

            # Load manifest with container
            $registry.LoadFromManifest($manifestPath, $global:PmcContainer)
        }

        # Build menus from registry
        $this._PopulateMenusFromRegistry($registry)

        # Store populated MenuBar globally for other screens to use
        $global:PmcSharedMenuBar = $this.MenuBar
    }

    # Populate MenuBar from registry
    hidden [void] _PopulateMenusFromRegistry([object]$registry) {
        $menuMapping = @{
            'Tasks'    = 0
            'Projects' = 1
            'Time'     = 2
            'Tools'    = 3
            'Options'  = 4
            'Help'     = 5
        }

        foreach ($menuName in $menuMapping.Keys) {
            $menuIndex = $menuMapping[$menuName]

            # CRITICAL: Validate menu index bounds before access
            if ($null -eq $this.MenuBar -or $null -eq $this.MenuBar.Menus) {
                # Write-PmcTuiLog "MenuBar or Menus collection is null - cannot populate menus" "ERROR"
                continue
            }

            if ($menuIndex -lt 0 -or $menuIndex -ge $this.MenuBar.Menus.Count) {
                # Write-PmcTuiLog "Menu index $menuIndex out of range (0-$($this.MenuBar.Menus.Count-1))" "ERROR"
                continue
            }

            $menu = $this.MenuBar.Menus[$menuIndex]
            $items = $registry.GetMenuItems($menuName)

            if ($global:PmcTuiLogFile) {
                if ($null -eq $items) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] _PopulateMenusFromRegistry: Menu '$menuName' has 0 items from registry (null)"
                }
                elseif ($items -is [array]) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] _PopulateMenusFromRegistry: Menu '$menuName' has $($items.Count) items from registry (array)"
                }
                else {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] _PopulateMenusFromRegistry: Menu '$menuName' has 1 item from registry (type: $($items.GetType().Name))"
                }
            }

            if ($null -ne $items) {
                # CRITICAL: Clear existing items to prevent duplication
                $menu.Items.Clear()

                foreach ($item in $items) {
                    # MEDIUM FIX TLS-M7: Validate $item is a hashtable before indexing
                    if ($item -isnot [hashtable]) {
                        # Write-PmcTuiLog "_PopulateMenusFromRegistry: Item is not a hashtable, type: $($item.GetType().Name)" "WARNING"
                        continue
                    }
                    # MenuRegistry returns hashtables, use hashtable indexing
                    $menuItem = [PmcMenuItem]::new($item['Label'], $item['Hotkey'], $item['Action'])
                    $menu.Items.Add($menuItem)
                }
            }
        }
    }

    # Filter tasks by view mode
    hidden [array] _FilterTasksByViewMode([array]$allTasks) {
        $result = switch ($this._viewMode) {
            'all' { $allTasks }
            'active' { $allTasks | Where-Object { -not (Get-SafeProperty $_ 'completed') } }
            'completed' { $allTasks | Where-Object { Get-SafeProperty $_ 'completed' } }
            'overdue' {
                $allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and $due -lt [DateTime]::Today
                }
            }
            'today' {
                $allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and $due.Date -eq [DateTime]::Today
                }
            }
            'tomorrow' {
                $tomorrow = [DateTime]::Today.AddDays(1)
                $allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and $due.Date -eq $tomorrow
                }
            }
            'week' {
                $weekEnd = [DateTime]::Today.AddDays(7)
                $allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and
                    $due -ge [DateTime]::Today -and $due -le $weekEnd
                }
            }
            'nextactions' {
                $allTasks | Where-Object {
                    $dependsOn = Get-SafeProperty $_ 'depends_on'
                    -not (Get-SafeProperty $_ 'completed') -and
                    (-not $dependsOn -or (-not ($dependsOn -is [array])) -or $dependsOn.Count -eq 0)
                }
            }
            'noduedate' {
                $allTasks | Where-Object {
                    -not (Get-SafeProperty $_ 'completed') -and -not (Get-SafeProperty $_ 'due')
                }
            }
            'month' {
                $monthEnd = [DateTime]::Today.AddDays(30)
                $allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and
                    $due -ge [DateTime]::Today -and $due -le $monthEnd
                }
            }
            'agenda' {
                $allTasks | Where-Object {
                    -not (Get-SafeProperty $_ 'completed') -and (Get-SafeProperty $_ 'due')
                }
            }
            'upcoming' {
                $allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and $due.Date -gt [DateTime]::Today
                }
            }
            default { $allTasks }
        }
        return $result
    }

    # Sort tasks by column
    hidden [array] _SortTasks([array]$tasks) {
        if ($null -eq $tasks -or $tasks.Count -eq 0) { return @() }

        $result = switch ($this._sortColumn) {
            'priority' { $tasks | Sort-Object { Get-SafeProperty $_ 'priority' } -Descending:(-not $this._sortAscending) }
            'text' { $tasks | Sort-Object { Get-SafeProperty $_ 'text' } -Descending:(-not $this._sortAscending) }
            'due' {
                $withDue = @($tasks | Where-Object { Get-SafeProperty $_ 'due' })
                $withoutDue = @($tasks | Where-Object { -not (Get-SafeProperty $_ 'due') })
                if ($this._sortAscending) {
                    @($withDue | Sort-Object { Get-SafeProperty $_ 'due' }) + $withoutDue
                }
                else {
                    @($withDue | Sort-Object { Get-SafeProperty $_ 'due' } -Descending) + $withoutDue
                }
            }
            'project' { $tasks | Sort-Object { Get-SafeProperty $_ 'project' } -Descending:(-not $this._sortAscending) }
            default { $tasks }
        }
        return $result
    }

    # Build children index for hierarchy
    hidden [hashtable] _BuildChildrenIndex([array]$tasks) {
        $childrenByParent = @{}
        foreach ($task in $tasks) {
            $parentId = Get-SafeProperty $task 'parent_id'
            if ($parentId) {
                if (-not $childrenByParent.ContainsKey($parentId)) {
                    $childrenByParent[$parentId] = [System.Collections.ArrayList]::new()
                }
                [void]$childrenByParent[$parentId].Add($task)
            }
        }
        return $childrenByParent
    }

    # Organize tasks into hierarchy
    hidden [array] _OrganizeHierarchy([array]$tasks) {
        $organized = [System.Collections.ArrayList]::new()
        $processedIds = @{}

        # Build children index
        $childrenByParent = $this._BuildChildrenIndex($tasks)
        $this._childrenIndex = $childrenByParent

        # Process parent tasks and their children
        foreach ($task in $tasks) {
            $taskId = Get-SafeProperty $task 'id'
            $parentId = Get-SafeProperty $task 'parent_id'

            if ($processedIds.ContainsKey($taskId)) { continue }

            # Only process top-level tasks (no parent)
            if (-not $parentId) {
                [void]$organized.Add($task)
                $processedIds[$taskId] = $true

                # Add children if not collapsed
                if ($childrenByParent.ContainsKey($taskId)) {
                    $isCollapsed = $this._collapsedSubtasks.ContainsKey($taskId)
                    foreach ($subtask in $childrenByParent[$taskId]) {
                        $subId = Get-SafeProperty $subtask 'id'
                        if (-not $processedIds.ContainsKey($subId)) {
                            if (-not $isCollapsed) {
                                [void]$organized.Add($subtask)
                            }
                            $processedIds[$subId] = $true
                        }
                    }
                }
            }
        }

        # Add orphaned subtasks
        foreach ($task in $tasks) {
            $taskId = Get-SafeProperty $task 'id'
            if (-not $processedIds.ContainsKey($taskId)) {
                [void]$organized.Add($task)
                $processedIds[$taskId] = $true
            }
        }

        return $organized
    }

    # Check if cache is valid
    hidden [bool] _IsCacheValid([string]$currentKey) {
        return ($this._cacheKey -eq $currentKey -and $null -ne $this._cachedFilteredTasks)
    }

    # Implement abstract method: Load data from TaskStore
    [void] LoadData() {
        $this._isLoading = $true
        try {
            # Build cache key
            $collapsedKey = ($this._collapsedSubtasks.Keys | Sort-Object) -join ','
            $currentKey = "$($this._viewMode):$($this._sortColumn):$($this._sortAscending):$($this._showCompleted):$collapsedKey"

            # Return cached data if valid
            if ($this._IsCacheValid($currentKey)) {
                # Write-PmcTuiLog "LoadData: Using cached data" "DEBUG"
                $this.List.SetData($this._cachedFilteredTasks)
                return
            }

            # Load all tasks
            $allTasks = $this.Store.GetAllTasks()
            # Write-PmcTuiLog "LoadData: Got $($allTasks.Count) tasks from Store" "DEBUG"

            if ($null -eq $allTasks -or $allTasks.Count -eq 0) {
                $this.List.SetData(@())
                $this._cachedFilteredTasks = @()
                $this._cacheKey = $currentKey
                return
            }

            # Filter by view mode
            $filteredTasks = $this._FilterTasksByViewMode($allTasks)
            if ($null -eq $filteredTasks) { $filteredTasks = @() }

            # Apply completed filter
            if (-not $this._showCompleted) {
                $filteredTasks = $filteredTasks | Where-Object { -not (Get-SafeProperty $_ 'completed') }
                if ($null -eq $filteredTasks) { $filteredTasks = @() }
            }

            # Sort tasks
            $sortedTasks = $this._SortTasks($filteredTasks)

            # Organize hierarchy
            $organizedTasks = $this._OrganizeHierarchy($sortedTasks)

            # Update stats and cache
            $this._UpdateStats($allTasks)
            $this._cachedFilteredTasks = $organizedTasks
            $this._cacheKey = $currentKey

            # Write-PmcTuiLog "TaskListScreen.LoadData: Setting $($organizedTasks.Count) tasks" "DEBUG"

            # Set data and invalidate cache (do NOT request clear - let rendering system handle it)
            $this.List.SetData($organizedTasks)

            # Update detail pane with currently selected item (if any) after data load
            # This ensures detail pane shows content on initial screen load
            if ($this.DetailPane -and $this._showDetailPane -and $organizedTasks.Count -gt 0) {
                $selectedItem = $this.List.GetSelectedItem()
                if ($selectedItem) {
                    $this.OnItemSelected($selectedItem)
                }
            }
        }
        finally {
            $this._isLoading = $false
        }
    }

    # Override to invalidate cache when data changes
    hidden [void] _OnTaskStoreDataChanged() {
        $this._cachedFilteredTasks = $null
        $this._cacheKey = ""
    }

    # Implement abstract method: Define columns for UniversalList
    [array] GetColumns() {
        $self = $this

        # CRITICAL FIX: Capture helper functions for scriptblock closures
        # GetNewClosure() captures variables but NOT functions from outer scope
        $getSafe = ${function:Global:Get-SafeProperty}
        $testSafe = ${function:Global:Test-SafeProperty}

        # Calculate column widths based on terminal width
        # Account for 4 separators (2 spaces each = 8 chars total) between 5 columns
        $availableWidth = $(if ($this.List -and $this.List.Width -gt 4) { $this.List.Width - 4 - 8 } else { 105 })
        $titleWidth = [Math]::Max(20, [Math]::Floor($availableWidth * 0.32))
        $detailsWidth = [Math]::Max(15, [Math]::Floor($availableWidth * 0.22))
        $dueWidth = [Math]::Max(10, [Math]::Floor($availableWidth * 0.12))
        $projectWidth = [Math]::Max(12, [Math]::Floor($availableWidth * 0.16))
        $tagsWidth = [Math]::Max(10, [Math]::Floor($availableWidth * 0.18))

        return @(
            @{
                Name             = 'title'
                Label            = 'Task'
                Width            = $titleWidth
                Align            = 'left'
                SkipRowHighlight = { param($item)
                    # Skip row highlighting ONLY for the row being edited
                    $itemId = & $getSafe $item 'id'
                    # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [SkipRowHighlight] CALLED for item $itemId"

                    if (-not $self.ShowInlineEditor) {
                        # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [SkipRowHighlight]   ShowInlineEditor=false, returning false"
                        return $false
                    }
                    if (-not $self.CurrentEditItem) {
                        # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [SkipRowHighlight]   CurrentEditItem=null, returning false"
                        return $false
                    }

                    # Check if this item is the one being edited
                    $editId = & $getSafe $self.CurrentEditItem 'id'
                    # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [SkipRowHighlight]   Comparing: itemId=$itemId vs editId=$editId"

                    # Only skip rendering for the exact item being edited
                    $skip = ($itemId -and $editId -and $itemId -eq $editId)
                    # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [SkipRowHighlight]   Result: $skip"
                    return $skip
                }.GetNewClosure()
                Format           = { param($task, $cellInfo)
                    try {
                        $t = & $getSafe $task 'title'
                        if (-not $t) { $t = & $getSafe $task 'text' }

                        # Add subtask indicators with better indentation
                        $taskId = & $getSafe $task 'id'
                        $hasParent = (& $testSafe $task 'parent_id') -and (& $getSafe $task 'parent_id')
                        if ($hasParent) {
                            # For subtasks, add tree branch with indentation
                            $t = "  └─ $t"  # Added extra spaces for indentation
                        }
                        else {
                            # CRITICAL FIX: Use cached children index instead of GetAllTasks() in render loop
                            $hasChildren = $self._childrenIndex.ContainsKey($taskId)
                            if ($hasChildren) {
                                $isCollapsed = $self._collapsedSubtasks.ContainsKey($taskId)
                                $indicator = $(if ($isCollapsed) { "▶" } else { "▼" })
                                $t = "$indicator $t"
                            }
                        }
                        if (& $getSafe $task 'completed') {
                            $t = "[[OK]] $t"
                        }
                        # CRITICAL FIX: Apply edit mode highlighting using theme
                        if ($cellInfo.IsFocused -and $cellInfo.IsInEditMode) {
                            $editBg = $self.List.GetThemedBg('Background.FieldFocused', $t.Length, 0)
                            $editFg = $self.List.GetThemedFg('Foreground.FieldFocused')
                            $reset = "`e[0m"
                            return "$editBg$editFg$t$reset"
                        }
                        return $t
                    }
                    catch {
                        $taskId = $(if ($task.id) { $task.id } else { "unknown" })
                        # Write-PmcTuiLog "Format title ERROR for task ${taskId}: $($_.Exception.Message)" "ERROR"
                        return "(error: ${taskId})"
                    }
                }.GetNewClosure()
                Color            = { param($task)
                    if (& $getSafe $task 'completed') {
                        $mutedColor = $self.List.GetThemedFg('Foreground.Muted')
                        return $(if ($self._supportsStrikethrough) { "${mutedColor}`e[9m" } else { $mutedColor })
                    }
                    $tags = & $getSafe $task 'tags'
                    if ($tags -and $tags -is [array]) {
                        if ($tags -contains 'urgent' -or $tags -contains 'critical') { return $self.List.GetThemedFg('Foreground.Error') }
                        if ($tags -contains 'bug') { return $self.List.GetThemedFg('Foreground.Error') }
                        if ($tags -contains 'feature') { return $self.List.GetThemedFg('Foreground.Success') }
                    }
                    return $self.List.GetThemedFg('Foreground.Row')
                }.GetNewClosure()
            }
            @{
                Name   = 'details'
                Label  = 'Details'
                Width  = $detailsWidth
                Align  = 'left'
                Format = { param($task, $cellInfo)
                    $d = & $getSafe $task 'details'
                    if ($d -and $d.Length -gt $detailsWidth) { return $d.Substring(0, $detailsWidth - 3) + "..." }
                    return $(if ($null -ne $d) { $d } else { '' })
                }.GetNewClosure()
                Color  = { return $self.List.GetThemedFg('Foreground.Muted') }.GetNewClosure()
            }
            @{
                Name   = 'due'
                Label  = 'Due'
                Width  = $dueWidth
                Align  = 'left'
                Format = { param($task, $cellInfo)
                    $d = & $getSafe $task 'due'
                    if (-not $d) { return '' }
                    try {
                        $date = [DateTime]$d
                        if ($date.Date -eq [DateTime]::Today) { return 'Today' }
                        if ($date.Date -eq [DateTime]::Today.AddDays(1)) { return 'Tomorrow' }
                        if ($date.Date -lt [DateTime]::Today) { return 'OVERDUE!' }
                        return $date.ToString('MMM dd')
                    }
                    catch {
                        return $d
                    }
                }.GetNewClosure()
                Color  = { param($task)
                    $d = & $getSafe $task 'due'
                    if (-not $d -or (& $getSafe $task 'completed')) { return $self.List.GetThemedFg('Foreground.Muted') }
                    try {
                        $date = [DateTime]$d
                        $diff = ($date.Date - [DateTime]::Today).Days
                        if ($diff -lt 0) { return $self.List.GetThemedFg('Foreground.Error') }
                        if ($diff -eq 0) { return $self.List.GetThemedFg('Foreground.Error') }
                        if ($diff -le 3) { return $self.List.GetThemedFg('Foreground.Error') }
                        return $self.List.GetThemedFg('Foreground.Success')
                    }
                    catch {
                        return $self.List.GetThemedFg('Foreground.Muted')
                    }
                }.GetNewClosure()
            }
            @{
                Name   = 'project'
                Label  = 'Project'
                Width  = $projectWidth
                Align  = 'left'
                Format = { param($task, $cellInfo)
                    $p = & $getSafe $task 'project'
                    if ($p -and $p.Length -gt $projectWidth) { return $p.Substring(0, $projectWidth - 3) + "..." }
                    return $(if ($null -ne $p) { $p } else { '' })
                }.GetNewClosure()
                Color  = { return $self.List.GetThemedFg('Foreground.Row') }.GetNewClosure()
            }
            @{
                Name   = 'tags'
                Label  = 'Tags'
                Width  = $tagsWidth
                Align  = 'left'
                Format = { param($task, $cellInfo)
                    $t = & $getSafe $task 'tags'
                    # Handle nested arrays (unwrap if needed)
                    while ($t -is [array] -and $t.Count -eq 1 -and $t[0] -is [array]) {
                        $t = $t[0]
                    }
                    # Convert array to string
                    if ($t -is [array]) { $t = $t -join ', ' }
                    # Convert to string explicitly
                    $t = [string]$t
                    if ($t -and $t.Length -gt $tagsWidth) { return $t.Substring(0, $tagsWidth - 3) + "..." }
                    return $(if ($null -ne $t) { $t } else { '' })
                }.GetNewClosure()
                Color  = { return $self.List.GetThemedFg('Foreground.Muted') }.GetNewClosure()
            }
        )
    }

    # Override: Get edit fields for inline editor
    [array] GetEditFields($item) {
        # CRITICAL: Match column widths from GetColumns() for proper alignment
        # Calculate field widths using same logic as GetColumns()
        $availableWidth = $(if ($this.List -and $this.List.Width -gt 4) { $this.List.Width - 4 - 8 } else { 105 })
        $textWidth = [Math]::Max(20, [Math]::Floor($availableWidth * 0.32))
        $detailsWidth = [Math]::Max(15, [Math]::Floor($availableWidth * 0.22))
        $dueWidth = [Math]::Max(10, [Math]::Floor($availableWidth * 0.12))
        $projectWidth = [Math]::Max(12, [Math]::Floor($availableWidth * 0.16))
        $tagsWidth = [Math]::Max(10, [Math]::Floor($availableWidth * 0.18))

        return @(
            @{ Name = 'text'; Label = 'Task'; Type = 'text'; Value = (Get-SafeProperty $item 'text'); Required = $true; MaxLength = 200; Width = $textWidth }
            @{ Name = 'details'; Label = 'Details'; Type = 'text'; Value = (Get-SafeProperty $item 'details'); Width = $detailsWidth }
            @{ Name = 'due'; Label = 'Due'; Type = 'date'; Value = (Get-SafeProperty $item 'due'); Width = $dueWidth }
            @{ Name = 'project'; Label = 'Project'; Type = 'project'; Value = (Get-SafeProperty $item 'project'); Width = $projectWidth }
            @{ Name = 'tags'; Label = 'Tags'; Type = 'tags'; Value = (Get-SafeProperty $item 'tags'); Width = $tagsWidth }
        )
    }

    # Override: Handle item creation
    [void] OnItemCreated([hashtable]$values) {
        # MEDIUM FIX TLS-M3: Add null check on $values parameter
        if ($null -eq $values) {
            # Write-PmcTuiLog "OnItemCreated called with null values" "ERROR"
            $this.SetStatusMessage("Cannot create task: no data provided", "error")
            return
        }
        try {
            # Convert widget values to task format
            # FIX: Convert "(No Project)" to empty string
            $projectValue = ''
            if ($values.ContainsKey('project') -and $values.project -ne '(No Project)') {
                $projectValue = $values.project
            }

            # Validate text field (required)
            $taskText = $(if ($values.ContainsKey('text')) { $values.text } else { '' })
            if ([string]::IsNullOrWhiteSpace($taskText)) {
                $this.SetStatusMessage("Task description is required", "error")
                return
            }

            # Validate text length
            # MEDIUM FIX TLS-M1 & TLS-M2: Correct error message to match actual limit (200, not 500)
            if ($taskText.Length -gt 200) {
                $this.SetStatusMessage("Task description must be 200 characters or less", "error")
                return
            }

            # Handle tags - ensure it's an array
            $tagsValue = $(if ($values.ContainsKey('tags') -and $values.tags) {
                    if ($values.tags -is [array]) {
                        , $values.tags  # Already an array
                    }
                    elseif ($values.tags -is [string]) {
                        , @($values.tags -split ',' | ForEach-Object { $_.Trim() })
                    }
                    else {
                        , @()
                    }
                }
                else {
                    , @()
                })

            $detailsValue = $(if ($values.ContainsKey('details')) { $values.details } else { '' })

            $taskData = @{
                text      = $taskText
                details   = $detailsValue
                priority  = 3  # Default priority when creating new tasks
                status    = 'todo'  # Default status for new tasks
                project   = $projectValue
                tags      = $tagsValue  # Comma prevents PowerShell from unwrapping single-element arrays
                completed = $false
                created   = [DateTime]::Now
            }

            # Add due date if provided - NO VALIDATION, just set it
            if ($values.ContainsKey('due') -and $values.due) {
                try {
                    $dueDate = [DateTime]$values.due
                    $taskData.due = $dueDate
                }
                catch {
                    # Write-PmcTuiLog "Failed to convert due date '$($values.due)', omitting" "WARNING"
                }
            }

            # H-VAL-3: Preserve parent_id from CurrentEditItem if it exists (for subtasks)
            # FIX: Safe property access for parent_id with validation
            if ($this.CurrentEditItem) {
                $parentId = Get-SafeProperty $this.CurrentEditItem 'parent_id'
                if ($parentId) {
                    # Validate parent exists before setting
                    $parentTask = $this.Store.GetTask($parentId)
                    if ($parentTask) {
                        $taskData.parent_id = $parentId
                    }
                    else {
                        # Write-PmcTuiLog "OnItemCreated: Invalid parent_id $parentId (not found), omitting" "WARNING"
                        $this.SetStatusMessage("Warning: Parent task not found, creating without parent", "warning")
                    }
                }
            }

            # VALIDATION DISABLED - Save directly without validation

            # Add to store (auto-persists and fires events)
            $success = $this.Store.AddTask($taskData)
            if ($success) {
                $this.SetStatusMessage("Task created: $($taskData.text)", "success")
            }
            else {
                $this.SetStatusMessage("Failed to create task: $($this.Store.LastError)", "error")
            }
        }
        catch {
            # LOW FIX TLS-L1: Add context to exception messages
            $taskText = $(if ($values.ContainsKey('text')) { $values.text } else { "(no title)" })
            # Write-PmcTuiLog "OnItemCreated exception while creating task '$taskText': $_" "ERROR"
            $this.SetStatusMessage("Error creating task '$taskText': $($_.Exception.Message)", "error")
        }
    }

    # Override: Handle item update
    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] START item=$($item.id)"
        # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] Values received: $($values | ConvertTo-Json -Compress)"
        # Write-PmcTuiLog "OnItemUpdated CALLED - item=$($item.id) values=$($values.Keys -join ',')" "INFO"
        # Write-PmcTuiLog "OnItemUpdated values: $($values | ConvertTo-Json -Compress)" "INFO"

        # CRITICAL FIX: Check if this is ADD mode (item is null)
        $isAddMode = ($null -eq $item)

        if ($isAddMode) {
            # Write-PmcTuiLog "OnItemUpdated: Processing ADD (new task) mode" "INFO"
            # Create new task instead of updating existing
            $this.OnItemCreated($values)
            return
        }

        # MEDIUM FIX TLS-M4: Add null checks on parameters
        if ($null -eq $item) {
            # Write-PmcTuiLog "OnItemUpdated called with null item in EDIT mode" "ERROR"
            $this.SetStatusMessage("Cannot update task: no item selected", "error")
            return
        }
        if ($null -eq $values) {
            # Write-PmcTuiLog "OnItemUpdated called with null values" "ERROR"
            $this.SetStatusMessage("Cannot update task: no data provided", "error")
            return
        }
        try {
            # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] Entering try block"
            # Build changes hashtable
            # FIX: Convert "(No Project)" to empty string
            $projectValue = ''
            if ($values.ContainsKey('project')) {
                # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] Processing project value: $($values.project)"
                if ($values.project -is [array]) {
                    # If it's an array, take first element
                    if ($values.project.Count -gt 0) {
                        $projectValue = [string]$values.project[0]
                    }
                }
                elseif ($values.project -is [string] -and $values.project -ne '(No Project)' -and $values.project -ne '') {
                    $projectValue = $values.project
                }
            }
            # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] Project value set to: '$projectValue'"

            # Validate text field (required)
            $taskText = $(if ($values.ContainsKey('text')) { $values.text } else { '' })
            # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] Task text: '$taskText' (length=$($taskText.Length))"
            if ([string]::IsNullOrWhiteSpace($taskText)) {
                # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] VALIDATION FAILED: text is empty"
                $this.SetStatusMessage("Task description is required", "error")
                return
            }

            # Validate text length
            # MEDIUM FIX TLS-M1 & TLS-M2: Correct error message to match actual limit (200, not 500)
            if ($taskText.Length -gt 200) {
                # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] VALIDATION FAILED: text too long ($($taskText.Length) > 200)"
                $this.SetStatusMessage("Task description must be 200 characters or less", "error")
                return
            }
            # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] Text validation passed"

            # Ensure all values have correct types for Store validation
            $detailsValue = $(if ($values.ContainsKey('details')) { $values.details } else { '' })
            # Handle tags - ensure it's an array and use comma operator to prevent unwrapping
            $tagsValue = $(if ($values.ContainsKey('tags') -and $values.tags) {
                    if ($values.tags -is [array]) {
                        , $values.tags  # Comma prevents PowerShell from unwrapping single-element arrays
                    }
                    elseif ($values.tags -is [string]) {
                        $splitResult = @($values.tags -split ',' | ForEach-Object { $_.Trim() })
                        , $splitResult  # Comma prevents unwrapping
                    }
                    else {
                        , @()
                    }
                }
                else {
                    , @()
                })

            $changes = @{
                text    = [string]$taskText
                details = [string]$detailsValue
                project = [string]$projectValue
                tags    = $tagsValue  # Comma prevents PowerShell from unwrapping single-element arrays
            }

            # Update due date with validation
            if ($values.ContainsKey('due') -and $values.due) {
                try {
                    $dueDate = [DateTime]$values.due
                    # Validate date is reasonable
                    $minDate = [DateTime]::Today.AddDays(-7) # Allow past week for updates
                    $maxDate = [DateTime]::Today.AddYears(10)

                    if ($dueDate -lt $minDate) {
                        $this.SetStatusMessage("Due date too far in the past (max 7 days)", "warning")
                        # Don't return - just omit the due date update
                    }
                    elseif ($dueDate -gt $maxDate) {
                        $this.SetStatusMessage("Due date cannot be more than 10 years in the future", "warning")
                        # Don't return - just omit the due date update
                    }
                    else {
                        $changes.due = $dueDate
                    }
                }
                catch {
                    $this.SetStatusMessage("Invalid due date format", "warning")
                    # Write-PmcTuiLog "Failed to convert due date '$($values.due)', omitting" "WARNING"
                    # Don't include due in changes - keep existing value
                }
            }
            else {
                $changes.due = $null
            }

            # CRITICAL FIX: Check for circular dependency when changing parent_id
            if ($values.ContainsKey('parent_id') -and $values.parent_id) {
                $newParentId = $values.parent_id
                $taskId = Get-SafeProperty $item 'id'

                # Validate parent exists
                $parentTask = $this.Store.GetTask($newParentId)
                if (-not $parentTask) {
                    $this.SetStatusMessage("Cannot set parent: parent task not found", "error")
                    # Write-PmcTuiLog "OnItemUpdated: Invalid parent_id $newParentId, task not found" "ERROR"
                    return
                }

                # Check for circular dependency
                if ($this._IsCircularDependency($newParentId, $taskId)) {
                    $this.SetStatusMessage("Cannot set parent: would create circular dependency", "error")
                    # Write-PmcTuiLog "OnItemUpdated: Circular dependency detected for task $taskId with parent $newParentId" "ERROR"
                    return
                }

                $changes.parent_id = $newParentId
            }
            elseif ($values.ContainsKey('parent_id')) {
                # Explicitly clear parent_id if value is null/empty
                $changes.parent_id = $null
            }

            # VALIDATION DISABLED - Save directly without validation

            # Update in store
            # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] Calling Store.UpdateTask with id=$($item.id)"
            # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] Changes: $($changes | ConvertTo-Json -Compress)"
            $success = $this.Store.UpdateTask($item.id, $changes)
            # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] Store.UpdateTask returned: $success"

            if ($success) {
                # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] SUCCESS - calling LoadData()"
                $this.SetStatusMessage("Task updated: $($values.text)", "success")
                try {
                    $this.LoadData()  # Refresh the list to show updated data
                    # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] LoadData() completed"
                }
                catch {
                    # Write-PmcTuiLog "OnItemUpdated: LoadData failed: $_" "WARNING"
                    # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] LoadData() FAILED: $_"
                    $this.SetStatusMessage("Task updated but display refresh failed", "warning")
                }
            }
            else {
                # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [OnItemUpdated] FAILED: $($this.Store.LastError)"
                $this.SetStatusMessage("Failed to update task: $($this.Store.LastError)", "error")
                # BUG-4 FIX: Reload data on failure to restore consistent state
                try {
                    $this.LoadData()
                }
                catch {
                    # Write-PmcTuiLog "OnItemUpdated: LoadData after failure failed: $_" "WARNING"
                }
            }
        }
        catch {
            # LOW FIX TLS-L1: Add context to exception messages
            $taskId = $(if ($null -ne $item -and (Get-SafeProperty $item 'id')) { $item.id } else { "(unknown)" })
            $taskText = $(if ($values.ContainsKey('text')) { $values.text } else { if ($null -ne $item) { (Get-SafeProperty $item 'text') } else { "(no title)" } })
            # Write-PmcTuiLog "OnItemUpdated exception while updating task '$taskText' (ID: $taskId): $_" "ERROR"
            $this.SetStatusMessage("Error updating task '$taskText': $($_.Exception.Message)", "error")
        }
    }

    # Override: Handle item deletion
    [void] OnItemDeleted([object]$item) {
        # CRITICAL FIX TLS-C2: Add null check on $item
        if ($null -eq $item) {
            # Write-PmcTuiLog "OnItemDeleted called with null item" "ERROR"
            $this.SetStatusMessage("Cannot delete: no item selected", "error")
            return
        }
        $taskId = Get-SafeProperty $item 'id'
        if ($null -eq $taskId) {
            # Write-PmcTuiLog "OnItemDeleted called with item missing id property" "ERROR"
            $this.SetStatusMessage("Cannot delete: task has no ID", "error")
            return
        }

        # BUG-15 FIX: Check for subtasks before deletion to prevent orphaning
        if ($this._childrenIndex.ContainsKey($taskId)) {
            $childCount = $this._childrenIndex[$taskId].Count
            $taskText = Get-SafeProperty $item 'text'

            # Log detailed guidance for resolving the blocker
            # Write-PmcTuiLog "OnItemDeleted: Cannot delete parent task '$taskText' (ID: $taskId) with $childCount subtasks" "WARNING"
            # Write-PmcTuiLog "OnItemDeleted: User must either: (1) Delete each subtask individually, or (2) Reassign subtasks to different parent" "INFO"

            # Show actionable error message to user
            $this.SetStatusMessage("Cannot delete: task has $childCount subtask(s). Delete or reassign each subtask first, then retry.", "error")

            # TODO ENHANCEMENT: Add bulk reassignment dialog
            # Future enhancement: Show interactive dialog with options:
            # - Option 1: Delete all subtasks recursively (with confirmation)
            # - Option 2: Reassign all subtasks to a different parent task
            # - Option 3: Move all subtasks to root level (remove parent)
            # This would eliminate tedious manual work for large task hierarchies

            return
        }

        try {
            $success = $this.Store.DeleteTask($taskId)
            if ($success) {
                $this.SetStatusMessage("Task deleted: $($item.text)", "success")
            }
            else {
                $this.SetStatusMessage("Failed to delete task: $($this.Store.LastError)", "error")
            }
        }
        catch {
            # LOW FIX TLS-L1: Add context to exception messages
            $taskId = $(if ($null -ne $item) { (Get-SafeProperty $item 'id') } else { "(unknown)" })
            $taskText = $(if ($null -ne $item) { (Get-SafeProperty $item 'text') } else { "(no title)" })
            # Write-PmcTuiLog "OnItemDeleted exception while deleting task '$taskText' (ID: $taskId): $_" "ERROR"
            $this.SetStatusMessage("Error deleting task '$taskText': $($_.Exception.Message)", "error")
        }
    }

    # Virtual method called when inline editor is confirmed
    [void] OnInlineEditConfirmed([hashtable]$values) {
        # This method is called by StandardListScreen when inline editing is confirmed
        # It handles BOTH add and edit modes, since EditItem only overrides the callback for edit mode
        # Write-PmcTuiLog "OnInlineEditConfirmed called - EditorMode=$($this.EditorMode) values=$($values.Keys -join ',')" "DEBUG"

        if ($null -eq $values) {
            # Write-PmcTuiLog "OnInlineEditConfirmed called with null values" "WARNING"
            return
        }

        # Determine if we're adding a new task or editing existing one
        $isAddMode = ($this.EditorMode -eq 'add')

        if ($isAddMode) {
            # ADDING NEW TASK
            # Write-PmcTuiLog "OnInlineEditConfirmed: Processing ADD operation" "INFO"
            $this.OnItemUpdated($null, $values)
        }
        else {
            # EDITING EXISTING TASK
            # Write-PmcTuiLog "OnInlineEditConfirmed: Processing EDIT operation for item=$($this.CurrentEditItem.id)" "INFO"
            if ($this.CurrentEditItem) {
                $this.OnItemUpdated($this.CurrentEditItem, $values)
            }
            else {
                # Write-PmcTuiLog "OnInlineEditConfirmed: EDIT mode but no CurrentEditItem!" "ERROR"
            }
        }
    }

    # Virtual method called when inline editor is cancelled
    [void] OnInlineEditCancelled() {
        # This method is called by StandardListScreen when inline editing is cancelled
        # TaskListScreen overrides the InlineEditor callbacks, so this is rarely called
        # But we provide it for completeness and to prevent method-not-found errors
        # Write-PmcTuiLog "OnInlineEditCancelled called" "DEBUG"
        # No-op: TaskListScreen handles inline editor callbacks directly
    }

    # Custom action: Toggle task completion
    [void] ToggleTaskCompletion([object]$task) {
        if ($null -eq $task) { return }

        $completed = Get-SafeProperty $task 'completed'
        $taskId = Get-SafeProperty $task 'id'
        $taskText = Get-SafeProperty $task 'text'

        $newStatus = -not $completed
        # CRITICAL FIX: Clear completed_at when reopening task, set it when completing
        $updates = @{ completed = $newStatus }
        if ($newStatus) {
            $updates.completed_at = [DateTime]::Now
        }
        else {
            $updates.completed_at = $null
        }
        $success = $this.Store.UpdateTask($taskId, $updates)

        if ($success) {
            $statusText = $(if ($newStatus) { "completed" } else { "reopened" })
            $this.SetStatusMessage("Task ${statusText}: $taskText", "success")
            # TaskStore event will invalidate cache and trigger refresh
        }
        else {
            $this.SetStatusMessage("Failed to update task: $($this.Store.LastError)", "error")
            # Write-PmcTuiLog "ToggleTaskCompletion failed: $($this.Store.LastError)" "ERROR"
            # BUG-4 FIX: Reload data on failure to restore consistent state
            try {
                $this.LoadData()
            }
            catch {
                # Write-PmcTuiLog "ToggleTaskCompletion: LoadData after failure failed: $_" "WARNING"
            }
        }
    }

    # Custom action: Mark task complete
    [void] CompleteTask([object]$task) {
        if ($null -eq $task) {
            # Write-PmcTuiLog "CompleteTask called with null task" "WARNING"
            return
        }
        # Write-PmcTuiLog "CompleteTask called for task: $($task.id)" "INFO"

        $taskId = Get-SafeProperty $task 'id'
        $taskText = Get-SafeProperty $task 'text'

        $success = $this.Store.UpdateTask($taskId, @{
                completed    = $true
                completed_at = [DateTime]::Now
            })

        if ($success) {
            $this.SetStatusMessage("Task completed: $taskText", "success")
            # TaskStore event will invalidate cache and trigger refresh
        }
        else {
            $this.SetStatusMessage("Failed to complete task: $($this.Store.LastError)", "error")
            # Write-PmcTuiLog "CompleteTask failed: $($this.Store.LastError)" "ERROR"
            # BUG-4 FIX: Reload data on failure to restore consistent state
            try {
                $this.LoadData()
            }
            catch {
                # Write-PmcTuiLog "CompleteTask: LoadData after failure failed: $_" "WARNING"
            }
        }
    }

    # Custom action: Clone task
    [void] CloneTask([object]$task) {
        if ($null -eq $task) { return }

        $taskText = Get-SafeProperty $task 'text'
        $taskPriority = Get-SafeProperty $task 'priority'
        $taskProject = Get-SafeProperty $task 'project'
        $taskTags = Get-SafeProperty $task 'tags'
        $taskDue = Get-SafeProperty $task 'due'

        $clonedTask = @{
            text         = "$taskText (copy)"
            priority     = $taskPriority
            project      = $taskProject
            tags         = $taskTags
            completed    = $false
            completed_at = $null  # Explicitly clear timestamp
            created      = [DateTime]::Now
        }

        if ($taskDue) {
            $clonedTask.due = $taskDue
        }

        $success = $this.Store.AddTask($clonedTask)
        if ($success) {
            $this.SetStatusMessage("Task cloned: $($clonedTask.text)", "success")
            # TaskStore event will invalidate cache and trigger refresh
        }
        else {
            $this.SetStatusMessage("Failed to clone task: $($this.Store.LastError)", "error")
            # Write-PmcTuiLog "CloneTask failed: $($this.Store.LastError)" "ERROR"
        }
    }

    # H-VAL-3: Check for circular dependency in task hierarchy
    hidden [bool] _IsCircularDependency([string]$parentId, [string]$childId) {
        $current = $parentId
        $visited = @{}

        while ($current) {
            # If we encounter the child ID in the parent chain, it's circular
            if ($current -eq $childId) { return $true }

            # Detect infinite loop (same parent visited twice)
            if ($visited.ContainsKey($current)) { return $true }
            $visited[$current] = $true

            # Get the parent of the current task
            $task = $this.Store.GetTask($current)
            $current = $(if ($task) { Get-SafeProperty $task 'parent_id' } else { $null })
        }

        return $false
    }

    # Custom action: Add subtask
    [void] AddSubtask([object]$parentTask) {
        if ($null -eq $parentTask) { return }

        # Get parent id with null check
        $parentId = $null
        if ($parentTask -is [hashtable] -and $parentTask.ContainsKey('id')) {
            $parentId = $parentTask['id']
        }
        elseif ($parentTask.PSObject.Properties['id']) {
            $parentId = $parentTask.id
        }

        if ($null -eq $parentId) {
            $this.SetStatusMessage("Cannot add subtask: parent task has no ID", "error")
            return
        }

        # Create new task with parent_id set
        $subtask = @{
            text      = ""
            priority  = 3
            project   = ""
            tags      = @()
            completed = $false
            created   = [DateTime]::Now
            parent_id = $parentId
        }

        # CRITICAL FIX: Set EditorMode so UniversalList knows to render the editor
        # This was missing, causing the editor to be invisible (though functionally active)
        $this.EditorMode = 'add'
        $this.CurrentEditItem = $subtask

        # Use base class inline editor system
        # Configure for horizontal inline editing
        $this.InlineEditor.LayoutMode = 'horizontal'
        $fields = $this.GetEditFields($subtask)
        $this.InlineEditor.SetFields($fields)
        $this.InlineEditor.Title = "Add Subtask"

        # CRITICAL FIX: Position editor using List selection like AddItem() does
        # Don't use manual SetPosition - let UniversalList render it inline
        $itemCount = $(if ($this.List._filteredData) { $this.List._filteredData.Count } else { 0 })
        $this.List._selectedIndex = $itemCount  # Select the "new row" position

        # Set up callbacks for subtask creation
        $self = $this
        $this.InlineEditor.OnConfirmed = {
            param($values)
            # Ensure parent_id is preserved
            $values.parent_id = $parentId
            $self.Store.AddTask($values)
            $self.ShowInlineEditor = $false
            $self.RefreshList()
            $self.SetStatusMessage("Subtask added", "success")
        }.GetNewClosure()

        $this.InlineEditor.OnCancelled = {
            $self.ShowInlineEditor = $false
            $self.SetStatusMessage("Subtask cancelled", "info")
        }.GetNewClosure()

        # Use base class flag
        $this.ShowInlineEditor = $true
        $this.SetStatusMessage("Add subtask - Tab=next field, Enter=save, Esc=cancel", "info")
    }

    # Custom action: Bulk complete selected tasks
    [void] BulkCompleteSelected() {
        $selected = $this.List.GetSelectedItems()
        if ($selected.Count -eq 0) {
            $this.SetStatusMessage("No tasks selected", "warning")
            return
        }

        $successCount = 0
        $failCount = 0
        foreach ($task in $selected) {
            $taskId = Get-SafeProperty $task 'id'
            $success = $this.Store.UpdateTask($taskId, @{
                    completed    = $true
                    completed_at = [DateTime]::Now
                })
            if ($success) {
                $successCount++
            }
            else {
                $failCount++
                # Write-PmcTuiLog "BulkCompleteSelected failed for task ${taskId}: $($this.Store.LastError)" "ERROR"
            }
        }

        if ($failCount -eq 0) {
            $this.SetStatusMessage("Completed $successCount tasks", "success")
        }
        else {
            $this.SetStatusMessage("Completed $successCount tasks, failed $failCount", "warning")
        }
        $this.List.ClearSelection()

        # BUG-12 FIX: Reload data after bulk operations to show updated state
        try {
            $this.LoadData()
        }
        catch {
            # Write-PmcTuiLog "BulkCompleteSelected: LoadData failed: $_" "WARNING"
        }
    }

    # Custom action: Bulk delete selected tasks
    [void] BulkDeleteSelected() {
        $selected = $this.List.GetSelectedItems()
        if ($selected.Count -eq 0) {
            $this.SetStatusMessage("No tasks selected", "warning")
            return
        }

        $successCount = 0
        $failCount = 0
        $skippedCount = 0
        foreach ($task in $selected) {
            $taskId = Get-SafeProperty $task 'id'
            # BUG-15 FIX: Check for subtasks before deletion
            if ($this._childrenIndex.ContainsKey($taskId)) {
                $childCount = $this._childrenIndex[$taskId].Count
                # Write-PmcTuiLog "BulkDeleteSelected: Skipping task $taskId with $childCount subtasks" "WARNING"
                $skippedCount++
                continue
            }
            $success = $this.Store.DeleteTask($taskId)
            if ($success) {
                $successCount++
            }
            else {
                $failCount++
                # Write-PmcTuiLog "BulkDeleteSelected failed for task ${taskId}: $($this.Store.LastError)" "ERROR"
            }
        }

        if ($failCount -eq 0 -and $skippedCount -eq 0) {
            $this.SetStatusMessage("Deleted $successCount tasks", "success")
        }
        elseif ($skippedCount -gt 0) {
            $this.SetStatusMessage("Deleted $successCount, skipped $skippedCount (have subtasks), failed $failCount", "warning")
        }
        else {
            $this.SetStatusMessage("Deleted $successCount tasks, failed $failCount", "warning")
        }
        $this.List.ClearSelection()
    }

    # Change view mode
    [void] SetViewMode([string]$mode) {
        $validModes = @('all', 'active', 'completed', 'overdue', 'today', 'tomorrow', 'week', 'nextactions', 'noduedate', 'month', 'agenda', 'upcoming')
        if ($mode -notin $validModes) {
            # Write-PmcTuiLog "Invalid view mode '$mode', defaulting to 'all'" "WARNING"
            $mode = 'all'
        }

        $this._viewMode = $mode
        $titleText = Get-TaskListTitle $mode
        $this.ScreenTitle = $titleText
        if ($this.List) {
            $this.List.Title = $titleText
        }
        $this.LoadData()
        $this.SetStatusMessage("View: $mode", "info")
    }

    # Toggle show completed
    [void] ToggleShowCompleted() {
        $this._showCompleted = -not $this._showCompleted
        $this.LoadData()

        $status = $(if ($this._showCompleted) { "showing" } else { "hiding" })
        $this.SetStatusMessage("Now $status completed tasks", "info")
    }

    # Change sort column
    [void] SetSortColumn([string]$column) {
        if ($this._sortColumn -eq $column) {
            # Toggle sort direction
            $this._sortAscending = -not $this._sortAscending
        }
        else {
            $this._sortColumn = $column
            $this._sortAscending = $true
        }

        $this.LoadData()

        $direction = $(if ($this._sortAscending) { "ascending" } else { "descending" })
        $this.SetStatusMessage("Sorting by $column ($direction)", "info")
    }

    # Override: Apply 70/30 split layout for List and DetailPane
    [void] ApplyContentLayout([PmcLayoutManager]$layoutManager, [int]$termWidth, [int]$termHeight) {
        # Don't call base - we handle everything ourselves
        $rect = $layoutManager.GetRegion('Content', $termWidth, $termHeight)

        if ($this._showDetailPane -and $this.DetailPane) {
            # 70/30 split within the content region
            $listWidth = [Math]::Floor($rect.Width * 0.70)
            $detailWidth = $rect.Width - $listWidth - 1  # -1 for spacing

            $this.List.SetPosition($rect.X, $rect.Y)
            $this.List.SetSize($listWidth, $rect.Height)

            $this.DetailPane.SetPosition($rect.X + $listWidth + 1, $rect.Y)
            $this.DetailPane.SetSize($detailWidth, $rect.Height)
            $this.DetailPane.Visible = $true
        } else {
            # Full width list
            $this.List.SetPosition($rect.X, $rect.Y)
            $this.List.SetSize($rect.Width, $rect.Height)

            if ($this.DetailPane) {
                $this.DetailPane.Visible = $false
            }
        }

        # Invalidate cache to force column recalculation
        $this.List.InvalidateCache()
    }

    # Override: Update detail pane when selection changes
    [void] OnItemSelected($item) {
        # Call base implementation
        ([StandardListScreen]$this).OnItemSelected($item)

        # Update detail pane
        if ($this.DetailPane -and $this._showDetailPane) {
            if ($null -ne $item) {
                $details = $this._FormatTaskDetails($item)
                $this.DetailPane.SetContent($details, 'left')
            } else {
                $this.DetailPane.SetContent("", 'left')
            }
        }
    }

    # Toggle detail pane visibility
    hidden [void] _ToggleDetailPane() {
        $this._showDetailPane = -not $this._showDetailPane

        # Force layout recalculation
        $this.Resize($this.TermWidth, $this.TermHeight)

        if ($this._showDetailPane) {
            $this.SetStatusMessage("Detail pane visible", "info")
            # Update with current selection
            $selected = $this.List.GetSelectedItem()
            if ($selected) {
                $this.OnItemSelected($selected)
            }
        } else {
            $this.SetStatusMessage("Detail pane hidden", "info")
        }
    }

    # Format task details for display in detail pane
    hidden [string] _FormatTaskDetails([object]$task) {
        $sb = [System.Text.StringBuilder]::new()

        $title = Get-SafeProperty $task 'text'
        $project = Get-SafeProperty $task 'project'
        $tags = Get-SafeProperty $task 'tags'
        $due = Get-SafeProperty $task 'due'
        $details = Get-SafeProperty $task 'details'
        $priority = Get-SafeProperty $task 'priority'
        $completed = Get-SafeProperty $task 'completed'

        [void]$sb.AppendLine("Task: $title")
        [void]$sb.AppendLine("")

        if ($completed) {
            [void]$sb.AppendLine("Status: COMPLETED")
        } else {
            [void]$sb.AppendLine("Status: Active")
        }

        if ($priority) {
            [void]$sb.AppendLine("Priority: $priority")
        }

        if ($project) {
            [void]$sb.AppendLine("Project: $project")
        }

        if ($tags -and $tags -is [array] -and $tags.Count -gt 0) {
            [void]$sb.AppendLine("Tags: $($tags -join ', ')")
        }

        if ($due) {
            try {
                $dueDate = [DateTime]$due
                [void]$sb.AppendLine("Due: $($dueDate.ToString('yyyy-MM-dd (ddd)'))")
            } catch {
                [void]$sb.AppendLine("Due: $due")
            }
        }

        [void]$sb.AppendLine("")

        if ($details) {
            # Word wrap based on DetailPane width (accounting for padding and borders)
            $wrapWidth = $(if ($this.DetailPane.Width -gt 6) { $this.DetailPane.Width - 6 } else { 30 })
            $wrapped = $this._WrapText($details, $wrapWidth)
            [void]$sb.AppendLine("Details:")
            [void]$sb.AppendLine($wrapped)
        }

        return $sb.ToString()
    }

    # Word wrap text to fit within specified width
    hidden [string] _WrapText([string]$text, [int]$width) {
        if ([string]::IsNullOrEmpty($text)) { return "" }
        if ($width -le 0) { return $text }

        $result = [System.Collections.Generic.List[string]]::new()

        # Split by existing newlines first
        $paragraphs = $text -split "`r?`n"

        foreach ($para in $paragraphs) {
            if ([string]::IsNullOrWhiteSpace($para)) {
                $result.Add("")
                continue
            }

            # Wrap this paragraph
            $words = $para -split '\s+'
            $currentLine = ""

            foreach ($word in $words) {
                # Handle words longer than width
                if ($word.Length -gt $width) {
                    if ($currentLine) {
                        $result.Add($currentLine)
                        $currentLine = ""
                    }
                    # Split long word across lines
                    for ($i = 0; $i -lt $word.Length; $i += $width) {
                        $chunk = $word.Substring($i, [Math]::Min($width, $word.Length - $i))
                        $result.Add($chunk)
                    }
                    continue
                }

                # Try adding word to current line
                $testLine = $(if ($currentLine) { "$currentLine $word" } else { $word })

                if ($testLine.Length -le $width) {
                    $currentLine = $testLine
                } else {
                    # Word doesn't fit, flush current line and start new one
                    if ($currentLine) {
                        $result.Add($currentLine)
                    }
                    $currentLine = $word
                }
            }

            # Flush last line of paragraph
            if ($currentLine) {
                $result.Add($currentLine)
            }
        }

        return ($result -join "`n")
    }

    # Update statistics
    hidden [void] _UpdateStats([array]$allTasks) {
        # Handle null or empty tasks
        if ($null -eq $allTasks) {
            $allTasks = @()
        }

        $tomorrow = [DateTime]::Today.AddDays(1)
        $weekEnd = [DateTime]::Today.AddDays(7)
        $monthEnd = [DateTime]::Today.AddDays(30)

        $this._stats = @{
            Total       = $allTasks.Count
            Active      = @($allTasks | Where-Object { -not (Get-SafeProperty $_ 'completed') }).Count
            Completed   = @($allTasks | Where-Object { Get-SafeProperty $_ 'completed' }).Count
            Overdue     = @($allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and $due -lt [DateTime]::Today
                }).Count
            Today       = @($allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and $due.Date -eq [DateTime]::Today
                }).Count
            Tomorrow    = @($allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and $due.Date -eq $tomorrow
                }).Count
            Week        = @($allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and
                    $due -ge [DateTime]::Today -and
                    $due -le $weekEnd
                }).Count
            Month       = @($allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and
                    $due -ge [DateTime]::Today -and
                    $due -le $monthEnd
                }).Count
            NextActions = @($allTasks | Where-Object {
                    $dependsOn = Get-SafeProperty $_ 'depends_on'
                    -not (Get-SafeProperty $_ 'completed') -and
                    (-not $dependsOn -or (-not ($dependsOn -is [array])) -or $dependsOn.Count -eq 0)
                }).Count
            NoDueDate   = @($allTasks | Where-Object {
                    -not (Get-SafeProperty $_ 'completed') -and -not (Get-SafeProperty $_ 'due')
                }).Count
            Upcoming    = @($allTasks | Where-Object {
                    $due = Get-SafeProperty $_ 'due'
                    -not (Get-SafeProperty $_ 'completed') -and $due -and $due.Date -gt [DateTime]::Today
                }).Count
        }
    }

    # Get custom actions for footer display
    [array] GetCustomActions() {
        $self = $this
        return @(
            @{ Key = 'o'; Label = 'Details'; Callback = {
                    $self._ToggleDetailPane()
                }.GetNewClosure()
            },
            @{ Key = 'c'; Label = 'Complete'; Callback = {
                    $selected = $self.List.GetSelectedItem()
                    $self.CompleteTask($selected)
                }.GetNewClosure() 
            },
            @{ Key = 'x'; Label = 'Clone'; Callback = {
                    $selected = $self.List.GetSelectedItem()
                    $self.CloneTask($selected)
                }.GetNewClosure() 
            },
            @{ Key = 's'; Label = 'Subtask'; Callback = {
                    # Write-PmcTuiLog "Action 's' (Subtask) triggered" "INFO"
                    $selected = $self.List.GetSelectedItem()
                    if ($selected) {
                        $self.AddSubtask($selected)
                    }
                    else {
                        # Write-PmcTuiLog "Action 's': No item selected" "WARNING"
                        $self.SetStatusMessage("Select a task to add a subtask", "warning")
                    }
                }.GetNewClosure() 
            },
            @{ Key = 'h'; Label = 'Hide Done'; Callback = {
                    $self.ToggleShowCompleted()
                }.GetNewClosure() 
            },
            @{ Key = '1'; Label = 'All'; Callback = {
                    $self.SetViewMode('all')
                }.GetNewClosure() 
            },
            @{ Key = '2'; Label = 'Active'; Callback = {
                    $self.SetViewMode('active')
                }.GetNewClosure() 
            },
            @{ Key = '3'; Label = 'Done'; Callback = {
                    $self.SetViewMode('completed')
                }.GetNewClosure() 
            },
            @{ Key = '4'; Label = 'Overdue'; Callback = {
                    $self.SetViewMode('overdue')
                }.GetNewClosure() 
            },
            @{ Key = '5'; Label = 'Today'; Callback = {
                    $self.SetViewMode('today')
                }.GetNewClosure() 
            },
            @{ Key = '6'; Label = 'Week'; Callback = {
                    $self.SetViewMode('week')
                }.GetNewClosure() 
            }
        )
    }

    # Override EditItem to use InlineEditor horizontally at row position
    [void] EditItem($item) {
        # Write-PmcTuiLog "TaskListScreen.EditItem called - item.id=$(if ($item) { $item.id } else { 'NULL' })" "INFO"
        if ($null -eq $item) { return }

        # Get row position
        $selectedIndex = $this.List.GetSelectedIndex()
        $scrollOffset = $(if ($null -ne $this.List._scrollOffset) { $this.List._scrollOffset } else { 0 })
        $visibleRow = $selectedIndex - $scrollOffset

        # Check if row is visible on screen
        $listHeight = $this.List.Height
        if ($visibleRow -lt 0 -or $visibleRow -ge ($listHeight - [TaskListScreen]::LIST_HEADER_ROWS)) {
            $this.SetStatusMessage("Cannot edit: row not visible on screen", "warning")
            return
        }

        # Position at the EXACT row where the task is displayed
        # UniversalList rows: Y + 1 (header), Y + 2 (separator), Y + 3 (first data row)
        $rowY = $this.List.Y + [TaskListScreen]::LIST_HEADER_ROWS + $visibleRow

        # Ensure InlineEditor is loaded
        if (-not ([System.Management.Automation.PSTypeName]'InlineEditor').Type) {
            . "$PSScriptRoot/../widgets/InlineEditor.ps1"
        }

        # Build fields for inline editor - PERCENTAGE-BASED widths
        # CRITICAL FIX: Calculate based on available terminal width using SAME formula as GetColumns()
        # Account for 4 separators (2 spaces each = 8 chars total) between 5 columns
        $availableWidth = $this.List.Width - 4 - 8  # Subtract borders and column separators
        $textWidth = [Math]::Floor($availableWidth * [TaskListScreen]::COL_WIDTH_TEXT)
        $detailsWidth = [Math]::Floor($availableWidth * [TaskListScreen]::COL_WIDTH_DETAILS)
        $dueWidth = [Math]::Floor($availableWidth * [TaskListScreen]::COL_WIDTH_DUE)
        $projectWidth = [Math]::Floor($availableWidth * [TaskListScreen]::COL_WIDTH_PROJECT)
        $tagsWidth = [Math]::Floor($availableWidth * [TaskListScreen]::COL_WIDTH_TAGS)

        $fields = @(
            @{ Name = 'text'; Label = ''; Type = 'text'; Value = (Get-SafeProperty $item 'text'); Required = $true; MaxLength = 200; Width = $textWidth }
            @{ Name = 'details'; Label = ''; Type = 'text'; Value = (Get-SafeProperty $item 'details'); Width = $detailsWidth }
            @{ Name = 'due'; Label = ''; Type = 'date'; Value = (Get-SafeProperty $item 'due'); Width = $dueWidth }
            @{ Name = 'project'; Label = ''; Type = 'project'; Value = (Get-SafeProperty $item 'project'); Width = $projectWidth }
            @{ Name = 'tags'; Label = ''; Type = 'tags'; Value = (Get-SafeProperty $item 'tags'); Width = $tagsWidth }
        )

        # Configure base class inline editor for horizontal inline editing
        $this.InlineEditor.LayoutMode = 'horizontal'
        $this.InlineEditor.SetFields($fields)

        # CRITICAL FIX: Set X and Y explicitly for horizontal mode
        # InlineEditor.RenderToEngine uses $this.X and $this.Y directly, NOT TargetRegionID
        # List content starts at List.X + 2 (for border), and rowY calculated above
        $this.InlineEditor.X = $this.List.X + 2
        $this.InlineEditor.Y = $rowY
        $this.InlineEditor.Width = $this.List.Width - 4  # Account for borders on both sides

        # Set up save callback
        $self = $this
        $taskId = $item.id
        # Write-PmcTuiLog "TaskListScreen.EditItem: Setting OnConfirmed callback for taskId=$taskId" "INFO"
        $this.InlineEditor.OnConfirmed = {
            param($values)
            # Write-PmcTuiLog "InlineEditor.OnConfirmed FIRED - taskId=$taskId values=$($values.Keys -join ',')" "INFO"
            # CRITICAL FIX: Get fresh item from store, then call OnItemUpdated
            $freshItem = $self.Store.GetTask($taskId)
            if ($freshItem) {
                $self.OnItemUpdated($freshItem, $values)
            }
            else {
                # Write-PmcTuiLog "InlineEditor.OnConfirmed - task $taskId not found!" "ERROR"
            }
            $self.ShowInlineEditor = $false
            $self.EditorMode = ""
            $self.CurrentEditItem = $null
        }.GetNewClosure()

        $this.InlineEditor.OnCancelled = {
            # Force refresh to clear the inline editor display
            $self.ShowInlineEditor = $false
            $self.EditorMode = ""
            $self.CurrentEditItem = $null
            $self.List.InvalidateCache()
            $self.SetStatusMessage("Edit cancelled", "info")
        }.GetNewClosure()

        # Mark that we're showing inline editor using base class property
        # BUG FIX: Set EditorMode and CurrentEditItem so SkipRowHighlight works correctly
        $this.EditorMode = 'edit'
        $this.CurrentEditItem = $item
        $this.ShowInlineEditor = $true
        # NOTE: NeedsClear NOT set - inline editing should not clear the screen
        $this.SetStatusMessage("Editing inline - Tab=next field, Enter=save, Esc=cancel", "success")
    }

    # Override RenderContent to call parent (which handles inline editor rendering)
    [string] RenderContent() {
        # Call base class which handles list, filter panel, and inline editor
        return ([StandardListScreen]$this).RenderContent()
    }

    # Override: Additional keyboard shortcuts
    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # CRITICAL: If inline editor is showing, let IT handle input first
        # Otherwise parent will steal Enter/Esc keys
        if ($this.ShowInlineEditor -and $null -ne $this.InlineEditor) {
            # Let inline editor handle ALL keys when it's active
            return ([StandardListScreen]$this).HandleKeyPress($keyInfo)
        }

        # CRITICAL FIX: Call parent FIRST to handle MenuBar and base navigation
        # But ONLY when inline editor is NOT active
        $handled = ([StandardListScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        # Custom shortcuts AFTER base class (parent didn't handle them)
        $key = $keyInfo.Key
        $ctrl = $keyInfo.Modifiers -band [ConsoleModifiers]::Control
        $alt = $keyInfo.Modifiers -band [ConsoleModifiers]::Alt

        # O: Toggle detail pane visibility
        if ($keyInfo.KeyChar -eq 'o' -or $keyInfo.KeyChar -eq 'O') {
            $this._ToggleDetailPane()
            return $true
        }

        # Space: Toggle subtask collapse OR completion
        # NOTE: This is custom TaskListScreen behavior, not base class behavior
        if ($key -eq [ConsoleKey]::Spacebar -and -not $ctrl -and -not $alt) {
            $selected = $this.List.GetSelectedItem()
            if ($selected) {
                $taskId = Get-SafeProperty $selected 'id'
                # BUG-13 FIX: Use cached children index instead of loading all tasks
                # O(1) hashtable lookup instead of O(n) GetAllTasks() + filtering
                $hasChildren = $this._childrenIndex.ContainsKey($taskId)

                if ($hasChildren) {
                    # Toggle collapse
                    $wasCollapsed = $this._collapsedSubtasks.ContainsKey($taskId)
                    if ($wasCollapsed) {
                        $this._collapsedSubtasks.Remove($taskId)
                    }
                    else {
                        $this._collapsedSubtasks[$taskId] = $true
                    }
                    # Invalidate cache because collapsed state changed
                    $this._cachedFilteredTasks = $null
                    $this._cacheKey = ""
                    $this.LoadData()
                    $this.List.InvalidateCache()  # Force re-render with new collapse state
                }
                else {
                    # No children - toggle completion
                    $this.ToggleTaskCompletion($selected)
                }
            }
            return $true
        }

        # C: Complete task
        if ($keyInfo.KeyChar -eq 'c' -or $keyInfo.KeyChar -eq 'C') {
            $selected = $this.List.GetSelectedItem()
            $this.CompleteTask($selected)
            return $true
        }

        # X: Clone task
        if ($keyInfo.KeyChar -eq 'x' -or $keyInfo.KeyChar -eq 'X') {
            $selected = $this.List.GetSelectedItem()
            $this.CloneTask($selected)
            return $true
        }

        # S: Add subtask
        if ($keyInfo.KeyChar -eq 's' -or $keyInfo.KeyChar -eq 'S') {
            $selected = $this.List.GetSelectedItem()
            if ($selected) {
                $this.AddSubtask($selected)
            }
            return $true
        }

        # Ctrl+C: Bulk complete selected
        if ($key -eq [ConsoleKey]::C -and $ctrl) {
            $this.BulkCompleteSelected()
            return $true
        }

        # Ctrl+X: Bulk delete selected
        if ($key -eq [ConsoleKey]::X -and $ctrl) {
            $this.BulkDeleteSelected()
            return $true
        }

        # View mode shortcuts
        if ($keyInfo.KeyChar -eq '1') { $this.SetViewMode('all'); return $true }
        if ($keyInfo.KeyChar -eq '2') { $this.SetViewMode('active'); return $true }
        if ($keyInfo.KeyChar -eq '3') { $this.SetViewMode('completed'); return $true }
        if ($keyInfo.KeyChar -eq '4') { $this.SetViewMode('overdue'); return $true }
        if ($keyInfo.KeyChar -eq '5') { $this.SetViewMode('today'); return $true }
        if ($keyInfo.KeyChar -eq '6') { $this.SetViewMode('week'); return $true }

        # H: Toggle show completed
        if ($keyInfo.KeyChar -eq 'h' -or $keyInfo.KeyChar -eq 'H') {
            $this.ToggleShowCompleted()
            return $true
        }

        return $false
    }

    # Override: Custom rendering (add header with stats and view mode)
    # Override: Custom rendering (add stats and view mode)
    [void] RenderToEngine([object]$engine) {
        # 1. Base StandardListScreen rendering (Header, List, Footer, etc.)
        ([StandardListScreen]$this).RenderToEngine($engine)

        # 2. Draw Stats in the gap between Header and List
        # Header ends at Y=something. List starts at Y=6.
        # Let's draw at Y=3 and Y=4.
        
        # Colors
        $labelColor = $this.Header.GetThemedColorInt('Foreground.Primary')
        $valueColor = $this.Header.GetThemedColorInt('Foreground.Success')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        # Position status at third line from bottom (above footer at TermHeight-1)
        $y = $this.TermHeight - 3
        $x = 0

        # View Mode
        $viewMode = $(if ($this._viewMode) { $this._viewMode.ToUpper() } else { 'ALL' })
        $engine.WriteAt(2, $y, "View: $viewMode", $labelColor, $bg)

        # Stats (with null safety)
        $statsX = 20
        $total = if ($this._stats.ContainsKey('Total')) { $this._stats.Total } else { 0 }
        $active = if ($this._stats.ContainsKey('Active')) { $this._stats.Active } else { 0 }
        $completed = if ($this._stats.ContainsKey('Completed')) { $this._stats.Completed } else { 0 }
        $overdue = if ($this._stats.ContainsKey('Overdue')) { $this._stats.Overdue } else { 0 }

        $engine.WriteAt($statsX, $y, "Total: $total", $labelColor, $bg)
        $engine.WriteAt($statsX + 15, $y, "Active: $active", $valueColor, $bg)
        $engine.WriteAt($statsX + 30, $y, "Done: $completed", $labelColor, $bg)

        if ($overdue -gt 0) {
            $errorColor = $this.Header.GetThemedColorInt('Foreground.Error')
            $engine.WriteAt($statsX + 45, $y, "Overdue: $overdue", $errorColor, $bg)
        }
        else {
            $engine.WriteAt($statsX + 45, $y, "Overdue: 0", $mutedColor, $bg)
        }

        # Keyboard shortcuts help (one line below status)
        $help = "F:Filter A:Add E:Edit D:Delete O:Details Space:Toggle C:Complete X:Clone 1-6:Views H:Hide Q:Quit"
        $engine.WriteAt(2, $y + 1, $help, $mutedColor, $bg)
    }




    # Static: Register menu items for all view modes
    static [void] RegisterMenuItems([object]$registry) {
        # Task List (all tasks)
        $registry.AddMenuItem('Tasks', 'Task List', 'L', {
                . "$PSScriptRoot/TaskListScreen.ps1"
                $global:PmcApp.PushScreen((New-Object -TypeName TaskListScreen))
            }, 5)

        # Today's tasks
        $registry.AddMenuItem('Tasks', 'Today', 'Y', {
                . "$PSScriptRoot/TaskListScreen.ps1"
                $global:PmcApp.PushScreen([TaskListScreen]::new('today'))
            }, 10)

        # Tomorrow's tasks
        $registry.AddMenuItem('Tasks', 'Tomorrow', 'T', {
                . "$PSScriptRoot/TaskListScreen.ps1"
                $global:PmcApp.PushScreen([TaskListScreen]::new('tomorrow'))
            }, 15)

        # This week
        $registry.AddMenuItem('Tasks', 'Week View', 'W', {
                . "$PSScriptRoot/TaskListScreen.ps1"
                $global:PmcApp.PushScreen([TaskListScreen]::new('week'))
            }, 20)

        # Upcoming tasks
        $registry.AddMenuItem('Tasks', 'Upcoming', 'U', {
                . "$PSScriptRoot/TaskListScreen.ps1"
                $global:PmcApp.PushScreen([TaskListScreen]::new('upcoming'))
            }, 25)

        # Overdue tasks (changed from V to O to avoid conflict with ProjectList V=View)
        $registry.AddMenuItem('Tasks', 'Overdue', 'O', {
                . "$PSScriptRoot/TaskListScreen.ps1"
                $global:PmcApp.PushScreen([TaskListScreen]::new('overdue'))
            }, 30)

        # Next actions (no dependencies)
        $registry.AddMenuItem('Tasks', 'Next Actions', 'N', {
                . "$PSScriptRoot/TaskListScreen.ps1"
                $global:PmcApp.PushScreen([TaskListScreen]::new('nextactions'))
            }, 35)

        # No due date
        $registry.AddMenuItem('Tasks', 'No Due Date', 'D', {
                . "$PSScriptRoot/TaskListScreen.ps1"
                $global:PmcApp.PushScreen([TaskListScreen]::new('noduedate'))
            }, 40)

        # Month view
        $registry.AddMenuItem('Tasks', 'Month View', 'M', {
                . "$PSScriptRoot/TaskListScreen.ps1"
                $global:PmcApp.PushScreen([TaskListScreen]::new('month'))
            }, 45)

        # Agenda view
        $registry.AddMenuItem('Tasks', 'Agenda View', 'A', {
                . "$PSScriptRoot/TaskListScreen.ps1"
                $global:PmcApp.PushScreen([TaskListScreen]::new('agenda'))
            }, 50)
    }
}

# Export for use in other modules
if ($MyInvocation.MyCommand.Path) {
    Export-ModuleMember -Variable TaskListScreen
}
