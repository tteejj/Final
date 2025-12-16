using namespace System.Collections.Generic
using namespace System.Text

# KanbanScreenV2 - Enhanced Kanban board with independent scrolling, custom colors, and subtask support
# Displays tasks in 3 columns: TODO / In Progress / Done

Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"
. "$PSScriptRoot/../helpers/LinuxKeyHelper.ps1"

<#
.SYNOPSIS
Enhanced Kanban board view with 3 columns, independent scrolling, and custom colors

.DESCRIPTION
Shows tasks grouped into 3 columns based on status:
- TODO (status = 'todo' or 'pending')
- In Progress (status = 'in-progress')
- Done (status = 'done' or completed = true)

Features:
- Independent scrolling per column
- Ctrl+Up/Down to reorder tasks within column
- Ctrl+Left/Right to move tasks between columns
- Custom per-task and per-tag colors
- Subtask hierarchy with parent/child movement
- Tag editing (T key)
- Dynamic column width based on terminal size
#>
class KanbanScreenV2 : PmcScreen {
    # Data store
    [TaskStore]$Store = $null

    # Data arrays for each column
    [array]$TodoTasks = @()
    [array]$InProgressTasks = @()
    [array]$DoneTasks = @()

    # Navigation state
    [int]$SelectedColumn = 0  # 0=TODO, 1=InProgress, 2=Done
    [int]$SelectedIndexTodo = 0
    [int]$SelectedIndexInProgress = 0
    [int]$SelectedIndexDone = 0

    # Scroll offsets (independent per column)
    [int]$ScrollOffsetTodo = 0
    [int]$ScrollOffsetInProgress = 0
    [int]$ScrollOffsetDone = 0

    # Expanded parent tasks (for subtask display)
    [HashSet[string]]$ExpandedParents = [HashSet[string]]::new()

    # Parent-child relationship cache (for performance optimization)
    [hashtable]$_parentChildCache = @{}

    # Tag color mapping (loaded from config)
    [hashtable]$TagColors = @{}

    # Constructor
    KanbanScreenV2() : base("KanbanV2", "Kanban Board") {
        # Initialize data store
        $this.Store = [TaskStore]::GetInstance()

        # Configure header - DISABLE separator since we have column borders
        $this.Header.SetBreadcrumb(@("Home", "Tasks", "Kanban"))
        $this.Header.ShowSeparator = $false

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("↑↓", "Navigate")
        $this.Footer.AddShortcut("←→", "Column")
        $this.Footer.AddShortcut("J/K", "Reorder")
        $this.Footer.AddShortcut("H/L", "Move")
        $this.Footer.AddShortcut("Space", "Expand")
        $this.Footer.AddShortcut("T", "Tags")
        $this.Footer.AddShortcut("C", "Color")
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Esc", "Back")

        # Load tag colors from config
        $this._LoadTagColors()
    }

    # Constructor with container
    KanbanScreenV2([object]$container) : base("KanbanV2", "Kanban Board", $container) {
        # Initialize data store
        $this.Store = [TaskStore]::GetInstance()

        # Configure header - DISABLE separator since we have column borders
        $this.Header.SetBreadcrumb(@("Home", "Tasks", "Kanban"))
        $this.Header.ShowSeparator = $false

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("↑↓", "Navigate")
        $this.Footer.AddShortcut("←→", "Column")
        $this.Footer.AddShortcut("J/K", "Reorder")
        $this.Footer.AddShortcut("H/L", "Move")
        $this.Footer.AddShortcut("Space", "Expand")
        $this.Footer.AddShortcut("T", "Tags")
        $this.Footer.AddShortcut("C", "Color")
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Esc", "Back")

        # Load tag colors from config
        $this._LoadTagColors()
    }

    # Load tag color mappings from config
    hidden [void] _LoadTagColors() {
        try {
            $cfg = Get-PmcConfig
            if ($cfg.Kanban -and $cfg.Kanban.TagColors) {
                $this.TagColors = $cfg.Kanban.TagColors
            }
            else {
                # Default tag colors
                $this.TagColors = @{
                    'urgent'    = '#FF0000'
                    'important' = '#FFA500'
                    'work'      = '#0066CC'
                    'personal'  = '#00CC66'
                    'blocked'   = '#CC0000'
                    'waiting'   = '#CCCC00'
                }
            }
        }
        catch {
            # MEDIUM FIX KSV2-M1: Add logging to catch block
            Write-PmcTuiLog "KanbanScreenV2._LoadTagColors: Failed to load tag colors: $($_.Exception.Message)" "WARNING"
            $this.TagColors = @{}
        }
    }

    [void] LoadData() {
        $this.ShowStatus("Loading kanban board...")

        try {
            # Load PMC data
            # CRITICAL FIX KSV2-C4: Add null check on GetAllTasks()
            $allTasks = $this.Store.GetAllTasks()
            if ($null -eq $allTasks) {
                # FAIL FAST: Do not pretend we have 0 tasks.
                throw "Store.GetAllTasks() returned null. Database access failed."
            }

            # In Progress column: ONLY tasks with explicit status = 'in-progress'
            $this.InProgressTasks = @($allTasks | Where-Object {
                    $taskCompleted = Get-SafeProperty $_ 'completed'
                    $taskStatus = Get-SafeProperty $_ 'status'
                    -not $taskCompleted -and $taskStatus -eq 'in-progress'
                })

            # Done column: status = 'done' or completed = true
            $this.DoneTasks = @($allTasks | Where-Object {
                    $taskCompleted = Get-SafeProperty $_ 'completed'
                    $taskStatus = Get-SafeProperty $_ 'status'
                    $taskCompleted -or $taskStatus -eq 'done'
                })

            # TODO column: Everything else (not in-progress, not done)
            # This includes: no status, status='todo', status='pending', status='blocked', etc.
            $this.TodoTasks = @($allTasks | Where-Object {
                    $taskId = Get-SafeProperty $_ 'id'
                    $inProgressIds = @($this.InProgressTasks | ForEach-Object { Get-SafeProperty $_ 'id' })
                    $doneIds = @($this.DoneTasks | ForEach-Object { Get-SafeProperty $_ 'id' })
                    $taskId -notin $inProgressIds -and $taskId -notin $doneIds
                })

            # Sort by order field (for manual reordering), then priority
            # CRITICAL FIX KSV2-C1: Safe [int] cast with validation
            $this.TodoTasks = @($this.TodoTasks | Sort-Object {
                    $order = Get-SafeProperty $_ 'order'
                    if ($order -and $order -match '^\d+$') { [int]$order } else { 999 }
                }, { Get-SafeProperty $_ 'priority' } -Descending)

            # CRITICAL FIX KSV2-C2: Safe [int] cast with validation
            $this.InProgressTasks = @($this.InProgressTasks | Sort-Object {
                    $order = Get-SafeProperty $_ 'order'
                    if ($order -and $order -match '^\d+$') { [int]$order } else { 999 }
                }, { Get-SafeProperty $_ 'priority' } -Descending)

            # CRITICAL FIX KSV2-C3: Safe [int] cast with validation
            $this.DoneTasks = @($this.DoneTasks | Sort-Object {
                    $order = Get-SafeProperty $_ 'order'
                    if ($order -and $order -match '^\d+$') { [int]$order } else { 999 }
                }, { Get-SafeProperty $_ 'priority' } -Descending)

            # Build parent-child cache for performance optimization
            # KSV2-M1 FIX: Add count check before iterating allTasks array
            $this._parentChildCache = @{}
            if ($null -ne $allTasks -and $allTasks.Count -gt 0) {
                foreach ($task in $allTasks) {
                    $parentId = Get-SafeProperty $task 'parent_id'
                    if ($parentId) {
                        if (-not $this._parentChildCache.ContainsKey($parentId)) {
                            $this._parentChildCache[$parentId] = @()
                        }
                        $this._parentChildCache[$parentId] += Get-SafeProperty $task 'id'
                    }
                }
            }

            # Reset selections if out of bounds
            if ($this.SelectedIndexTodo -ge $this.TodoTasks.Count) {
                $this.SelectedIndexTodo = [Math]::Max(0, $this.TodoTasks.Count - 1)
            }
            if ($this.SelectedIndexInProgress -ge $this.InProgressTasks.Count) {
                $this.SelectedIndexInProgress = [Math]::Max(0, $this.InProgressTasks.Count - 1)
            }
            if ($this.SelectedIndexDone -ge $this.DoneTasks.Count) {
                $this.SelectedIndexDone = [Math]::Max(0, $this.DoneTasks.Count - 1)
            }

            # Update status
            $total = $this.TodoTasks.Count + $this.InProgressTasks.Count + $this.DoneTasks.Count
            $this.ShowStatus("Kanban: $($this.TodoTasks.Count) TODO, $($this.InProgressTasks.Count) In Progress, $($this.DoneTasks.Count) Done")

        }
        catch {
            $this.ShowError("Failed to load kanban board: $_")
            $this.TodoTasks = @()
            $this.InProgressTasks = @()
            $this.DoneTasks = @()
        }
    }

    [string] RenderContent() {
        return $this._RenderKanbanBoard()
    }

    # PERFORMANCE: Direct engine rendering (bypasses ANSI string building/parsing)
    [void] RenderContentToEngine([object]$engine) {
        $this._RenderKanbanBoardDirect($engine)
    }

    hidden [string] _RenderKanbanBoard() {
        $sb = [System.Text.StringBuilder]::new(8192)

        if (-not $this.LayoutManager) {
            return $sb.ToString()
        }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors
        $textColor = $this.Header.GetThemedFg('Foreground.Field')
        $selectedBg = $this.Header.GetThemedBg('Background.FieldFocused', 80, 0)
        $selectedFg = $this.Header.GetThemedFg('Foreground.Field')
        $cursorColor = $this.Header.GetThemedFg('Foreground.FieldFocused')
        $priorityColor = $this.Header.GetThemedAnsi('Warning', $false)
        $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
        $headerColor = $this.Header.GetThemedFg('Foreground.Muted')
        $successColor = $this.Header.GetThemedFg('Foreground.Success')
        $reset = "`e[0m"

        # Calculate dynamic column widths based on terminal width
        # Use actual available width, no minimum requirement
        $actualWidth = $contentRect.Width

        # 3 columns with spacing between them
        # Each column: left border (1) + content (width) + right border (1) = width+2
        # Spacing between columns: 2 chars
        $columnWidth = [Math]::Floor(($actualWidth - 10) / 3)  # 10 = 6 borders + 4 spacing
        $col1X = $contentRect.X + 1
        $col2X = $col1X + $columnWidth + 4  # +2 for borders, +2 for spacing
        $col3X = $col2X + $columnWidth + 4

        # Starting Y position
        $startY = $contentRect.Y

        # Column height
        $columnHeight = $contentRect.Height - 2
        $taskContentHeight = $columnHeight - 3  # Subtract header + borders

        # Render each column with full borders
        $this._RenderColumnBorder($sb, $col1X, $startY, $columnWidth, $columnHeight, "TODO ($($this.TodoTasks.Count))", ($this.SelectedColumn -eq 0), $cursorColor, $headerColor, $mutedColor, $reset)
        $this._RenderColumnBorder($sb, $col2X, $startY, $columnWidth, $columnHeight, "IN PROGRESS ($($this.InProgressTasks.Count))", ($this.SelectedColumn -eq 1), $cursorColor, $headerColor, $mutedColor, $reset)
        $this._RenderColumnBorder($sb, $col3X, $startY, $columnWidth, $columnHeight, "DONE ($($this.DoneTasks.Count))", ($this.SelectedColumn -eq 2), $cursorColor, $headerColor, $mutedColor, $reset)

        # Render task items in columns with independent scrolling
        $taskStartY = $startY + 2  # Below column header
        # Tasks render at column X + 2 (1 for column border + 1 for padding inside)
        $sb.Append($this._RenderColumn($col1X + 2, $taskStartY, $taskContentHeight, $columnWidth - 4,
                $this.TodoTasks, $this.SelectedIndexTodo, $this.ScrollOffsetTodo, ($this.SelectedColumn -eq 0)))

        $sb.Append($this._RenderColumn($col2X + 2, $taskStartY, $taskContentHeight, $columnWidth - 4,
                $this.InProgressTasks, $this.SelectedIndexInProgress, $this.ScrollOffsetInProgress, ($this.SelectedColumn -eq 1)))

        $sb.Append($this._RenderColumn($col3X + 2, $taskStartY, $taskContentHeight, $columnWidth - 4,
                $this.DoneTasks, $this.SelectedIndexDone, $this.ScrollOffsetDone, ($this.SelectedColumn -eq 2)))

        return $sb.ToString()
    }

    # PERFORMANCE: Direct engine rendering (bypasses string building and ANSI parsing)
    hidden [void] _RenderKanbanBoardDirect([object]$engine) {
        if (-not $this.LayoutManager) {
            return
        }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors
        $textColor = $this.Header.GetThemedFg('Foreground.Field')
        $selectedBg = $this.Header.GetThemedBg('Background.FieldFocused', 80, 0)
        $selectedFg = $this.Header.GetThemedFg('Foreground.Field')
        $cursorColor = $this.Header.GetThemedFg('Foreground.FieldFocused')
        $priorityColor = $this.Header.GetThemedAnsi('Warning', $false)
        $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
        $headerColor = $this.Header.GetThemedFg('Foreground.Muted')
        $successColor = $this.Header.GetThemedFg('Foreground.Success')
        $reset = "`e[0m"

        # Calculate dynamic column widths based on terminal width
        $minTotalWidth = 120
        $actualWidth = [Math]::Max($minTotalWidth, $contentRect.Width)

        # 3 columns with spacing between them
        $columnWidth = [Math]::Floor(($actualWidth - 10) / 3)
        $col1X = $contentRect.X + 1
        $col2X = $col1X + $columnWidth + 4
        $col3X = $col2X + $columnWidth + 4

        # Starting Y position
        $startY = $contentRect.Y

        # Column height
        $columnHeight = $contentRect.Height - 2
        $taskContentHeight = $columnHeight - 3

        # Render each column with full borders (direct to engine)
        $this._RenderColumnBorderDirect($engine, $col1X, $startY, $columnWidth, $columnHeight, "TODO ($($this.TodoTasks.Count))", ($this.SelectedColumn -eq 0), $cursorColor, $headerColor, $mutedColor, $reset)
        $this._RenderColumnBorderDirect($engine, $col2X, $startY, $columnWidth, $columnHeight, "IN PROGRESS ($($this.InProgressTasks.Count))", ($this.SelectedColumn -eq 1), $cursorColor, $headerColor, $mutedColor, $reset)
        $this._RenderColumnBorderDirect($engine, $col3X, $startY, $columnWidth, $columnHeight, "DONE ($($this.DoneTasks.Count))", ($this.SelectedColumn -eq 2), $cursorColor, $headerColor, $mutedColor, $reset)

        # Render task items in columns with independent scrolling (direct to engine)
        $taskStartY = $startY + 2  # Below column header
        # Tasks render at column X + 2 (1 for column border + 1 for padding inside)
        $this._RenderColumnDirect($engine, $col1X + 2, $taskStartY, $taskContentHeight, $columnWidth - 4,
            $this.TodoTasks, $this.SelectedIndexTodo, $this.ScrollOffsetTodo, ($this.SelectedColumn -eq 0))

        $this._RenderColumnDirect($engine, $col2X + 2, $taskStartY, $taskContentHeight, $columnWidth - 4,
            $this.InProgressTasks, $this.SelectedIndexInProgress, $this.ScrollOffsetInProgress, ($this.SelectedColumn -eq 1))

        $this._RenderColumnDirect($engine, $col3X + 2, $taskStartY, $taskContentHeight, $columnWidth - 4,
            $this.DoneTasks, $this.SelectedIndexDone, $this.ScrollOffsetDone, ($this.SelectedColumn -eq 2))
    }

    # Render borders around a column
    hidden [void] _RenderColumnBorder([System.Text.StringBuilder]$sb, [int]$x, [int]$y, [int]$width, [int]$height, [string]$title, [bool]$isActive, [string]$activeColor, [string]$inactiveColor, [string]$borderColor, [string]$reset) {
        # HIGH FIX KSV2-H1: Add null check on $title parameter
        if ($null -eq $title) { $title = "" }

        $titleColor = $(if ($isActive) { $activeColor } else { $inactiveColor })

        # Top border with title: ┌─ TITLE ───┐
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($borderColor + "┌─ " + $reset + $titleColor + $title + $reset + $borderColor)
        $titleLen = $title.Length + 3  # "─ " + title
        $remainingWidth = $width - $titleLen - 1  # -1 for right corner
        if ($remainingWidth -gt 0) {
            $sb.Append(" " + ("─" * $remainingWidth) + "┐")
        }
        else {
            $sb.Append("┐")
        }
        $sb.Append($reset)

        # Left and right borders for each line
        for ($i = 1; $i -lt $height; $i++) {
            $lineY = $y + $i
            # Left border
            $sb.Append($this.Header.BuildMoveTo($x, $lineY))
            $sb.Append($borderColor + "│" + $reset)
            # Right border
            $sb.Append($this.Header.BuildMoveTo($x + $width - 1, $lineY))
            $sb.Append($borderColor + "│" + $reset)
        }

        # Bottom border: └─────┘
        $sb.Append($this.Header.BuildMoveTo($x, $y + $height))
        $sb.Append($borderColor + "└" + ("─" * ($width - 2)) + "┘" + $reset)
    }

    hidden [string] _RenderColumn([int]$x, [int]$y, [int]$maxLines, [int]$width, [array]$tasks, [int]$selectedIndex, [int]$scrollOffset, [bool]$isActiveColumn) {
        $sb = [System.Text.StringBuilder]::new(2048)

        $textColor = $this.Header.GetThemedFg('Foreground.Field')
        $selectedBg = $this.Header.GetThemedBg('Background.FieldFocused', 80, 0)
        $selectedFg = $this.Header.GetThemedFg('Foreground.Field')
        $cursorColor = $this.Header.GetThemedFg('Foreground.FieldFocused')
        $priorityColor = $this.Header.GetThemedAnsi('Warning', $false)
        $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
        $reset = "`e[0m"

        # Build flat list including subtasks based on expanded state
        $flatList = $this._BuildFlatTaskList($tasks)

        # Each task card takes 4 lines: top border, text line, tags line, bottom border
        $linesPerCard = 4
        $maxCards = [Math]::Floor($maxLines / $linesPerCard)

        # Calculate visible range with scrolling (in terms of card index, not lines)
        $visibleTasks = @()
        $visibleStart = $scrollOffset
        $visibleEnd = [Math]::Min($flatList.Count, $scrollOffset + $maxCards)

        # CRITICAL FIX KSV2-C5: Validate range before array slice
        if ($visibleStart -lt $flatList.Count -and $visibleEnd -gt $visibleStart) {
            $visibleTasks = $flatList[$visibleStart..($visibleEnd - 1)]
        }

        # Render visible tasks as bordered cards
        $currentY = $y
        for ($i = 0; $i -lt $visibleTasks.Count; $i++) {
            $item = $visibleTasks[$i]
            # CRITICAL FIX KSV2-C6 & C11: Add null check before accessing .Task property
            if ($null -eq $item -or $null -eq $item.Task) {
                Write-PmcTuiLog "KanbanScreenV2._RenderColumn: item or item.Task is null at index $i" "WARNING"
                continue
            }
            $task = $item.Task
            $depth = $item.Depth
            $globalIndex = $visibleStart + $i
            $isSelected = ($globalIndex -eq $selectedIndex) -and $isActiveColumn

            # Get custom color (per-task or per-tag)
            $customColor = $this._GetTaskColor($task)
            $cardColor = $textColor
            if ($customColor) {
                $cardColor = $this._HexToAnsi($customColor, $false)
            }

            # Build task text with hierarchy indicators
            $indent = "  " * $depth
            $prefix = ""

            # Expand/collapse indicator for parent tasks
            if ($this._HasChildren($task)) {
                $taskId = Get-SafeProperty $task 'id'
                if ($this.ExpandedParents.Contains($taskId)) {
                    $prefix = "▼ "
                }
                else {
                    $prefix = "▸ "
                }
            }
            elseif ($depth -gt 0) {
                $prefix = "├─"
            }

            # Priority prefix
            $taskPriority = Get-SafeProperty $task 'priority'
            if ($taskPriority -gt 0) {
                $prefix += "P$taskPriority "
            }

            # Get task text
            # HIGH FIX KSV2-H2: Add null check before string concatenation
            $taskTextValue = Get-SafeProperty $task 'text'
            if (-not $taskTextValue) { $taskTextValue = "" }
            $taskText = $indent + $prefix + $taskTextValue

            # Get tags
            $taskTags = Get-SafeProperty $task 'tags'
            $tagsText = ""
            if ($taskTags -and $taskTags.Count -gt 0) {
                $tagsText = "#" + ($taskTags -join " #")
            }

            # Card dimensions
            $cardWidth = $width - 2
            $innerWidth = $cardWidth - 2  # Accounting for left/right borders

            # Truncate text if needed
            # HIGH FIX KSV2-H3: Add null check before .Length access
            if ($taskText -and $taskText.Length -gt $innerWidth) {
                $taskText = $taskText.Substring(0, $innerWidth - 3) + "..."
            }
            # HIGH FIX KSV2-H4: Add null check before .Length access
            if ($tagsText -and $tagsText.Length -gt $innerWidth) {
                $tagsText = $tagsText.Substring(0, $innerWidth - 3) + "..."
            }

            # Determine card colors
            $borderColor = $cardColor
            $contentColor = $cardColor
            if ($isSelected) {
                $borderColor = $selectedBg + $selectedFg
                $contentColor = $selectedBg + $selectedFg
            }

            # Top border: ┌────────┐
            # Note: Cursor indicator removed - selection shown by card highlighting
            $sb.Append($this.Header.BuildMoveTo($x, $currentY))
            $sb.Append($borderColor + "┌" + ("─" * $innerWidth) + "┐" + $reset)
            $currentY++

            # Task text line: │ text │
            $sb.Append($this.Header.BuildMoveTo($x, $currentY))
            $paddedText = $taskText.PadRight($innerWidth)
            $sb.Append($borderColor + "│" + $reset + $contentColor + $paddedText + $reset + $borderColor + "│" + $reset)
            $currentY++

            # Tags line: │ #tags │
            $sb.Append($this.Header.BuildMoveTo($x, $currentY))
            $paddedTags = $tagsText.PadRight($innerWidth)
            $sb.Append($borderColor + "│" + $reset + $mutedColor + $paddedTags + $reset + $borderColor + "│" + $reset)
            $currentY++

            # Bottom border: └────────┘
            $sb.Append($this.Header.BuildMoveTo($x, $currentY))
            $sb.Append($borderColor + "└" + ("─" * $innerWidth) + "┘" + $reset)
            $currentY++
        }

        # Show scroll indicators
        if ($scrollOffset -gt 0) {
            # Can scroll up
            $sb.Append($this.Header.BuildMoveTo($x, $y - 1))
            $sb.Append($mutedColor + "↑ More above" + $reset)
        }
        if ($visibleEnd -lt $flatList.Count) {
            # Can scroll down (show below last card)
            $remaining = $flatList.Count - $visibleEnd
            $sb.Append($this.Header.BuildMoveTo($x, $currentY))
            $sb.Append($mutedColor + "↓ +$remaining more" + $reset)
        }

        return $sb.ToString()
    }

    # Build flat list of tasks including expanded subtasks
    hidden [array] _BuildFlatTaskList([array]$tasks) {
        $result = [List[object]]::new()

        foreach ($task in $tasks) {
            $taskId = Get-SafeProperty $task 'id'
            $parentId = Get-SafeProperty $task 'parent_id'

            # Only include root tasks (no parent) at top level
            if (-not $parentId) {
                $result.Add(@{ Task = $task; Depth = 0 })

                # If expanded, add children
                # KSV2-M1 FIX: Add count check before iterating children array
                if ($this.ExpandedParents.Contains($taskId)) {
                    $children = $this._GetChildren($task, $tasks)
                    if ($null -ne $children -and $children.Count -gt 0) {
                        foreach ($child in $children) {
                            $result.Add(@{ Task = $child; Depth = 1 })
                        }
                    }
                }
            }
        }

        return $result.ToArray()
    }

    # Check if task has children (using cached parent-child relationships)
    hidden [bool] _HasChildren([object]$task) {
        $taskId = Get-SafeProperty $task 'id'
        return $this._parentChildCache.ContainsKey($taskId) -and $this._parentChildCache[$taskId].Count -gt 0
    }

    # Get children of a task
    hidden [array] _GetChildren([object]$task, [array]$allTasks) {
        # HIGH FIX KSV2-H5: Add parameter validation
        if ($null -eq $task -or $null -eq $allTasks) {
            Write-PmcTuiLog "KanbanScreenV2._GetChildren: null parameter (task=$($null -eq $task), allTasks=$($null -eq $allTasks))" "WARNING"
            return @()
        }
        $taskId = Get-SafeProperty $task 'id'
        return @($allTasks | Where-Object {
                $parentId = Get-SafeProperty $_ 'parent_id'
                $parentId -eq $taskId
            })
    }

    # Get task color (per-task overrides per-tag)
    hidden [string] _GetTaskColor([object]$task) {
        # Check per-task color first
        $taskColor = Get-SafeProperty $task 'color'
        if ($taskColor) {
            return $taskColor
        }

        # Check tag colors
        $tags = Get-SafeProperty $task 'tags'
        if ($tags -and $tags.Count -gt 0) {
            foreach ($tag in $tags) {
                if ($this.TagColors.ContainsKey($tag)) {
                    return $this.TagColors[$tag]
                }
            }
        }

        return $null
    }

    # Convert hex color to ANSI sequence
    hidden [string] _HexToAnsi([string]$hex, [bool]$background) {
        # HIGH FIX KSV2-H6: Add null check on $hex parameter
        if ($null -eq $hex) {
            Write-PmcTuiLog "KanbanScreenV2._HexToAnsi: hex parameter is null" "WARNING"
            return ''
        }
        $hex = $hex.TrimStart('#')
        if ($hex.Length -ne 6) { return '' }

        try {
            $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
            $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
            $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)

            if ($background) {
                return "`e[48;2;${r};${g};${b}m"
            }
            else {
                return "`e[38;2;${r};${g};${b}m"
            }
        }
        catch {
            # MEDIUM FIX KSV2-M2: Add logging to catch block
            Write-PmcTuiLog "KanbanScreenV2._HexToAnsi: Invalid hex color '$hex': $($_.Exception.Message)" "WARNING"
            return ''
        }
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        $key = $keyInfo.Key
        $ctrl = $keyInfo.Modifiers -band [ConsoleModifiers]::Control

        # LINUX WORKAROUND: Detect Ctrl+Arrow via escape sequence parsing
        # On Linux, Console.ReadKey may return ESC followed by [1;5A instead of proper Ctrl+UpArrow
        $ctrlArrowDetected = [LinuxKeyHelper]::DetectCtrlArrow($keyInfo)
        if ($ctrlArrowDetected) {
            switch ($ctrlArrowDetected) {
                "Ctrl+Up" {
                    $this.ShowStatus("Ctrl+Up: Reordering task up")
                    $this._ReorderTaskUp()
                    return $true
                }
                "Ctrl+Down" {
                    $this.ShowStatus("Ctrl+Down: Reordering task down")
                    $this._ReorderTaskDown()
                    return $true
                }
                "Ctrl+Left" {
                    $this.ShowStatus("Ctrl+Left: Moving task left")
                    $this._MoveTaskLeft()
                    return $true
                }
                "Ctrl+Right" {
                    $this.ShowStatus("Ctrl+Right: Moving task right")
                    $this._MoveTaskRight()
                    return $true
                }
            }
        }

        # STANDARD: Also check normal way (works on Windows and some Linux terminals)
        if ($ctrl) {
            if ($key -eq [ConsoleKey]::UpArrow) {
                $this.ShowStatus("Ctrl+Up: Reordering task up")
                $this._ReorderTaskUp()
                return $true
            }
            if ($key -eq [ConsoleKey]::DownArrow) {
                $this.ShowStatus("Ctrl+Down: Reordering task down")
                $this._ReorderTaskDown()
                return $true
            }
            if ($key -eq [ConsoleKey]::LeftArrow) {
                $this.ShowStatus("Ctrl+Left: Moving task left")
                $this._MoveTaskLeft()
                return $true
            }
            if ($key -eq [ConsoleKey]::RightArrow) {
                $this.ShowStatus("Ctrl+Right: Moving task right")
                $this._MoveTaskRight()
                return $true
            }
        }

        # Regular arrow keys for navigation
        if ($key -eq [ConsoleKey]::LeftArrow) {
            if ($this.SelectedColumn -gt 0) {
                $this.SelectedColumn--
                return $true
            }
        }
        if ($key -eq [ConsoleKey]::RightArrow) {
            if ($this.SelectedColumn -lt 2) {
                $this.SelectedColumn++
                return $true
            }
        }
        if ($key -eq [ConsoleKey]::UpArrow) {
            $this._MoveSelectionUp()
            return $true
        }
        if ($key -eq [ConsoleKey]::DownArrow) {
            $this._MoveSelectionDown()
            return $true
        }
        if ($key -eq [ConsoleKey]::Spacebar) {
            $this._ToggleExpand()
            return $true
        }

        # Character keys
        switch ($keyChar) {
            't' {
                $this._EditTags()
                return $true
            }
            'c' {
                $this._PickColor()
                return $true
            }
            'r' {
                $this.LoadData()
                return $true
            }
            'h' {
                # Move left (H = left on keyboard)
                $this._MoveTaskLeft()
                return $true
            }
            'l' {
                # Move right (L = right on keyboard)
                $this._MoveTaskRight()
                return $true
            }
            'k' {
                # Move up (K = up in vim)
                $this._ReorderTaskUp()
                return $true
            }
            'j' {
                # Move down (J = down in vim)
                $this._ReorderTaskDown()
                return $true
            }
        }

        return $false
    }

    # Navigation with scrolling
    hidden [void] _MoveSelectionUp() {
        switch ($this.SelectedColumn) {
            0 {
                if ($this.SelectedIndexTodo -gt 0) {
                    $this.SelectedIndexTodo--
                    # Adjust scroll if needed
                    if ($this.SelectedIndexTodo -lt $this.ScrollOffsetTodo) {
                        $this.ScrollOffsetTodo = $this.SelectedIndexTodo
                    }
                }
            }
            1 {
                if ($this.SelectedIndexInProgress -gt 0) {
                    $this.SelectedIndexInProgress--
                    if ($this.SelectedIndexInProgress -lt $this.ScrollOffsetInProgress) {
                        $this.ScrollOffsetInProgress = $this.SelectedIndexInProgress
                    }
                }
            }
            2 {
                if ($this.SelectedIndexDone -gt 0) {
                    $this.SelectedIndexDone--
                    if ($this.SelectedIndexDone -lt $this.ScrollOffsetDone) {
                        $this.ScrollOffsetDone = $this.SelectedIndexDone
                    }
                }
            }
        }
    }

    hidden [void] _MoveSelectionDown() {
        if (-not $this.LayoutManager) {
            return
        }

        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)
        $maxVisibleLines = $contentRect.Height - 4

        switch ($this.SelectedColumn) {
            0 {
                $flatList = $this._BuildFlatTaskList($this.TodoTasks)
                if ($this.SelectedIndexTodo -lt ($flatList.Count - 1)) {
                    $this.SelectedIndexTodo++
                    # Adjust scroll if needed
                    if ($this.SelectedIndexTodo -ge ($this.ScrollOffsetTodo + $maxVisibleLines)) {
                        $this.ScrollOffsetTodo = $this.SelectedIndexTodo - $maxVisibleLines + 1
                    }
                }
            }
            1 {
                $flatList = $this._BuildFlatTaskList($this.InProgressTasks)
                if ($this.SelectedIndexInProgress -lt ($flatList.Count - 1)) {
                    $this.SelectedIndexInProgress++
                    if ($this.SelectedIndexInProgress -ge ($this.ScrollOffsetInProgress + $maxVisibleLines)) {
                        $this.ScrollOffsetInProgress = $this.SelectedIndexInProgress - $maxVisibleLines + 1
                    }
                }
            }
            2 {
                $flatList = $this._BuildFlatTaskList($this.DoneTasks)
                if ($this.SelectedIndexDone -lt ($flatList.Count - 1)) {
                    $this.SelectedIndexDone++
                    if ($this.SelectedIndexDone -ge ($this.ScrollOffsetDone + $maxVisibleLines)) {
                        $this.ScrollOffsetDone = $this.SelectedIndexDone - $maxVisibleLines + 1
                    }
                }
            }
        }
    }

    # Toggle expand/collapse for parent tasks
    hidden [void] _ToggleExpand() {
        $task = $this._GetSelectedTask()
        if ($task -and $this._HasChildren($task)) {
            $taskId = Get-SafeProperty $task 'id'
            if ($this.ExpandedParents.Contains($taskId)) {
                $this.ExpandedParents.Remove($taskId)
            }
            else {
                $this.ExpandedParents.Add($taskId)
            }
        }
    }

    # Move task between columns (Ctrl+Left/Right)
    hidden [void] _MoveTaskLeft() {
        $task = $this._GetSelectedTask()
        if (-not $task) { return }

        $taskId = Get-SafeProperty $task 'id'
        $currentStatus = Get-SafeProperty $task 'status'
        $newStatus = ''

        # Determine new status based on current column
        switch ($this.SelectedColumn) {
            0 { return }  # Already in TODO, can't move left
            1 { $newStatus = 'todo' }  # In Progress -> TODO
            2 { $newStatus = 'in-progress' }  # Done -> In Progress
        }

        # Update task and children if parent
        $this._UpdateTaskStatus($task, $newStatus)
        $this.ShowSuccess("Moved task to $newStatus")
        $this.LoadData()
    }

    hidden [void] _MoveTaskRight() {
        $task = $this._GetSelectedTask()
        if (-not $task) { return }

        $taskId = Get-SafeProperty $task 'id'
        $currentStatus = Get-SafeProperty $task 'status'
        $newStatus = ''

        # Determine new status based on current column
        switch ($this.SelectedColumn) {
            0 { $newStatus = 'in-progress' }  # TODO -> In Progress
            1 { $newStatus = 'done' }  # In Progress -> Done
            2 { return }  # Already in Done, can't move right
        }

        # Update task and children if parent
        $this._UpdateTaskStatus($task, $newStatus)
        $this.ShowSuccess("Moved task to $newStatus")
        $this.LoadData()
    }

    # Update task status (and children if parent)
    hidden [void] _UpdateTaskStatus([object]$task, [string]$newStatus) {
        if (-not $task) {
            return
        }

        $taskId = Get-SafeProperty $task 'id'
        if (-not $taskId) {
            return
        }

        # Update main task
        $changes = @{ status = $newStatus }
        if ($newStatus -eq 'done') {
            $changes.completed = $true
            $changes.completedDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
        else {
            $changes.completed = $false
            $changes.completedDate = $null
        }
        $this.Store.UpdateTask($taskId, $changes)

        # Update children if parent (with validation)
        # KSV2-M1 FIX: Add count check before iterating children array
        if ($this._HasChildren($task)) {
            try {
                # CRITICAL FIX KSV2-C7: Add null check on Store before calling GetAllTasks()
                if ($null -eq $this.Store) {
                    Write-PmcTuiLog "KanbanScreenV2._MoveTask: Store is null" "ERROR"
                    return
                }
                $allTasks = $this.Store.GetAllTasks()
                if ($null -ne $allTasks -and $allTasks.Count -gt 0) {
                    $children = @($allTasks | Where-Object {
                            $parentId = Get-SafeProperty $_ 'parent_id'
                            $parentId -eq $taskId
                        })
                    if ($null -ne $children -and $children.Count -gt 0) {
                        foreach ($child in $children) {
                            if ($child) {
                                $childId = Get-SafeProperty $child 'id'
                                if ($childId) {
                                    $this.Store.UpdateTask($childId, $changes)
                                }
                            }
                        }
                    }
                }
            }
            catch {
                # Log error but don't fail parent update
                Write-PmcTuiLog "Failed to update child tasks: $_" "ERROR"
            }
        }
    }

    # Reorder task within column (Ctrl+Up/Down)
    hidden [void] _ReorderTaskUp() {
        $task = $this._GetSelectedTask()
        if (-not $task) { return }

        # Don't reorder subtasks - they should only move with parent
        $parentId = Get-SafeProperty $task 'parent_id'
        if ($parentId) {
            $this.ShowStatus("Cannot reorder subtasks independently")
            return
        }

        $currentTasks = $this._GetCurrentColumnTasks()
        $taskId = Get-SafeProperty $task 'id'
        $currentIndex = -1

        for ($i = 0; $i -lt $currentTasks.Count; $i++) {
            if ((Get-SafeProperty $currentTasks[$i] 'id') -eq $taskId) {
                $currentIndex = $i
                break
            }
        }

        if ($currentIndex -le 0) { return }  # Already at top

        # Swap with previous task
        $prevTask = $currentTasks[$currentIndex - 1]
        $this._SwapTaskOrder($task, $prevTask)

        $this.LoadData()

        # Update selection to keep it on the moved task in the flat list
        $this._UpdateSelectionAfterReorder($taskId)
    }

    hidden [void] _ReorderTaskDown() {
        $task = $this._GetSelectedTask()
        if (-not $task) { return }

        # Don't reorder subtasks - they should only move with parent
        $parentId = Get-SafeProperty $task 'parent_id'
        if ($parentId) {
            $this.ShowStatus("Cannot reorder subtasks independently")
            return
        }

        $currentTasks = $this._GetCurrentColumnTasks()
        $taskId = Get-SafeProperty $task 'id'
        $currentIndex = -1

        for ($i = 0; $i -lt $currentTasks.Count; $i++) {
            if ((Get-SafeProperty $currentTasks[$i] 'id') -eq $taskId) {
                $currentIndex = $i
                break
            }
        }

        if ($currentIndex -lt 0 -or $currentIndex -ge ($currentTasks.Count - 1)) { return }  # Already at bottom

        # Swap with next task
        $nextTask = $currentTasks[$currentIndex + 1]
        $this._SwapTaskOrder($task, $nextTask)

        $this.LoadData()

        # Update selection to keep it on the moved task in the flat list
        $this._UpdateSelectionAfterReorder($taskId)
    }

    # Swap order values of two tasks
    hidden [void] _SwapTaskOrder([object]$task1, [object]$task2) {
        # CRITICAL FIX KSV2-C8: Add null check on GetAllTasks()
        $allTasks = $this.Store.GetAllTasks()
        if ($null -eq $allTasks) {
            Write-PmcTuiLog "KanbanScreenV2._SwapTaskOrder: GetAllTasks() returned null" "ERROR"
            $allTasks = @()
        }
        $id1 = Get-SafeProperty $task1 'id'
        $id2 = Get-SafeProperty $task2 'id'

        $t1 = $allTasks | Where-Object { (Get-SafeProperty $_ 'id') -eq $id1 }
        $t2 = $allTasks | Where-Object { (Get-SafeProperty $_ 'id') -eq $id2 }

        if ($t1 -and $t2) {
            $order1 = Get-SafeProperty $t1 'order'
            $order2 = Get-SafeProperty $t2 'order'

            if (-not $order1) { $order1 = 0 }
            if (-not $order2) { $order2 = 0 }

            # Swap using TaskStore
            $this.Store.UpdateTask($id1, @{ order = $order2 })
            $this.Store.UpdateTask($id2, @{ order = $order1 })
        }
    }

    # Edit tags for selected task
    hidden [void] _EditTags() {
        $task = $this._GetSelectedTask()
        if (-not $task) { return }

        # Load TagEditor widget
        . "$PSScriptRoot/../widgets/TagEditor.ps1"

        # Create editor with current tags
        $currentTags = Get-SafeProperty $task 'tags'
        if (-not $currentTags) { $currentTags = @() }

        $editor = [TagEditor]::new()
        $editor.SetPosition(10, 8)
        $editor.SetSize(60, 8)
        $editor.SetTags($currentTags)

        # Run modal loop with exception handling
        try {
            $done = $false
            while (-not $done) {
                # Render
                [Console]::CursorVisible = $false
                Write-Host $editor.Render() -NoNewline

                # Handle input
                $key = [Console]::ReadKey($true)
                $editor.HandleInput($key)

                if ($editor.IsConfirmed -or $editor.IsCancelled) {
                    $done = $true
                }
            }

            # Save tags if confirmed
            if ($editor.IsConfirmed) {
                $newTags = $editor.GetTags()
                $taskId = Get-SafeProperty $task 'id'

                # Update tags using TaskStore
                $this.Store.UpdateTask($taskId, @{ tags = $newTags })
                $this.ShowSuccess("Tags updated")
                $this.LoadData()
            }
        }
        catch {
            $this.ShowError("Tag editing failed: $_")
        }
        finally {
            # Force screen refresh after tag editor closes
            $this.NeedsClear = $true
            [Console]::CursorVisible = $false
        }
    }

    # Pick custom color for selected task
    hidden [void] _PickColor() {
        $task = $this._GetSelectedTask()
        if (-not $task) { return }

        # Show simple color picker menu
        $colors = @(
            @{ Name = "Red"; Hex = "#FF0000" }
            @{ Name = "Orange"; Hex = "#FFA500" }
            @{ Name = "Yellow"; Hex = "#FFFF00" }
            @{ Name = "Green"; Hex = "#00FF00" }
            @{ Name = "Blue"; Hex = "#0000FF" }
            @{ Name = "Purple"; Hex = "#9966FF" }
            @{ Name = "Pink"; Hex = "#FF69B4" }
            @{ Name = "Cyan"; Hex = "#00FFFF" }
            @{ Name = "Clear (use tag color)"; Hex = "" }
        )

        $selected = 0
        $done = $false

        try {
            while (-not $done) {
                # Render color picker
                $sb = [System.Text.StringBuilder]::new(1024)
                $x = 20
                $y = 8

                $textColor = $this.Header.GetThemedFg('Foreground.Field')
                $selectedBg = $this.Header.GetThemedBg('Background.FieldFocused', 80, 0)
                $selectedFg = $this.Header.GetThemedFg('Foreground.Field')
                $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
                $reset = "`e[0m"

                # Title
                $sb.Append($this.Header.BuildMoveTo($x, $y))
                $sb.Append($textColor + "Pick Task Color:" + $reset)

                # Color options
                for ($i = 0; $i -lt $colors.Count; $i++) {
                    $color = $colors[$i]
                    $lineY = $y + $i + 1

                    $sb.Append($this.Header.BuildMoveTo($x, $lineY))

                    if ($i -eq $selected) {
                        $sb.Append($selectedBg + $selectedFg)
                    }

                    if ($color.Hex) {
                        $colorAnsi = $this._HexToAnsi($color.Hex, $false)
                        $sb.Append($colorAnsi + "███" + $reset)
                    }
                    else {
                        $sb.Append("   ")
                    }

                    if ($i -eq $selected) {
                        $sb.Append(" > " + $color.Name.PadRight(25) + $reset)
                    }
                    else {
                        $sb.Append($textColor + "   " + $color.Name + $reset)
                    }
                }

                # Help text
                $helpY = $y + $colors.Count + 2
                $sb.Append($this.Header.BuildMoveTo($x, $helpY))
                $sb.Append($mutedColor + "↑↓ to select, Enter to confirm, Esc to cancel" + $reset)

                Write-Host $sb.ToString() -NoNewline

                # Handle input
                $key = [Console]::ReadKey($true)
                switch ($key.Key) {
                    'UpArrow' {
                        if ($selected -gt 0) { $selected-- }
                    }
                    'DownArrow' {
                        if ($selected -lt ($colors.Count - 1)) { $selected++ }
                    }
                    'Enter' {
                        # Save color
                        $taskId = Get-SafeProperty $task 'id'
                        # CRITICAL FIX KSV2-C9: Add bounds check before array access
                        if ($selected -ge 0 -and $selected -lt $colors.Count) {
                            $chosenHex = $colors[$selected].Hex
                        }
                        else {
                            Write-PmcTuiLog "KanbanScreenV2._ShowColorPicker: selected index $selected out of bounds (0-$($colors.Count-1))" "ERROR"
                            $chosenHex = $null
                        }

                        # Update color using TaskStore
                        if ($chosenHex) {
                            $this.Store.UpdateTask($taskId, @{ color = $chosenHex })
                            $this.ShowSuccess("Color set to $($colors[$selected].Name)")
                        }
                        else {
                            $this.Store.UpdateTask($taskId, @{ color = $null })
                            $this.ShowSuccess("Color cleared")
                        }
                        $this.LoadData()
                        $done = $true
                    }
                    'Escape' {
                        $done = $true
                    }
                }
            }
        }
        catch {
            $this.ShowError("Color picker failed: $_")
        }
        finally {
            # Force screen refresh after color picker closes
            $this.NeedsClear = $true
            [Console]::CursorVisible = $false
        }
    }

    # Get selected task in current column
    hidden [object] _GetSelectedTask() {
        switch ($this.SelectedColumn) {
            0 {
                $flatList = $this._BuildFlatTaskList($this.TodoTasks)
                if ($null -eq $flatList -or $flatList.Count -eq 0) {
                    return $null
                }
                if ($this.SelectedIndexTodo -lt 0 -or $this.SelectedIndexTodo -ge $flatList.Count) {
                    $this.SelectedIndexTodo = 0  # Reset to valid index
                    if ($flatList.Count -eq 0) { return $null }
                }
                # CRITICAL FIX KSV2-C10: Check array element before accessing .Task
                $item = $flatList[$this.SelectedIndexTodo]
                if ($null -ne $item) { return $item.Task } else { return $null }
            }
            1 {
                $flatList = $this._BuildFlatTaskList($this.InProgressTasks)
                if ($null -eq $flatList -or $flatList.Count -eq 0) {
                    return $null
                }
                if ($this.SelectedIndexInProgress -lt 0 -or $this.SelectedIndexInProgress -ge $flatList.Count) {
                    $this.SelectedIndexInProgress = 0  # Reset to valid index
                    if ($flatList.Count -eq 0) { return $null }
                }
                # CRITICAL FIX KSV2-C10: Check array element before accessing .Task
                $item = $flatList[$this.SelectedIndexInProgress]
                if ($null -ne $item) { return $item.Task } else { return $null }
            }
            2 {
                $flatList = $this._BuildFlatTaskList($this.DoneTasks)
                if ($null -eq $flatList -or $flatList.Count -eq 0) {
                    return $null
                }
                if ($this.SelectedIndexDone -lt 0 -or $this.SelectedIndexDone -ge $flatList.Count) {
                    $this.SelectedIndexDone = 0  # Reset to valid index
                    if ($flatList.Count -eq 0) { return $null }
                }
                # CRITICAL FIX KSV2-C10: Check array element before accessing .Task
                $item = $flatList[$this.SelectedIndexDone]
                if ($null -ne $item) { return $item.Task } else { return $null }
            }
        }
        return $null
    }

    # Get tasks in current column
    hidden [array] _GetCurrentColumnTasks() {
        switch ($this.SelectedColumn) {
            0 { return $this.TodoTasks }
            1 { return $this.InProgressTasks }
            2 { return $this.DoneTasks }
        }
        return @()
    }

    # Update selection index after reorder to keep the moved task selected
    hidden [void] _UpdateSelectionAfterReorder([string]$taskId) {
        $currentTasks = $this._GetCurrentColumnTasks()
        $flatList = $this._BuildFlatTaskList($currentTasks)

        # Find the task in the flat list
        for ($i = 0; $i -lt $flatList.Count; $i++) {
            if ((Get-SafeProperty $flatList[$i].Task 'id') -eq $taskId) {
                switch ($this.SelectedColumn) {
                    0 { $this.SelectedIndexTodo = $i }
                    1 { $this.SelectedIndexInProgress = $i }
                    2 { $this.SelectedIndexDone = $i }
                }
                break
            }
        }
    }

    # ===== PERFORMANCE: Direct Engine Rendering Methods =====

    # Render column border directly to engine (no string building)
    hidden [void] _RenderColumnBorderDirect([object]$engine, [int]$x, [int]$y, [int]$width, [int]$height, [string]$title, [bool]$isActive, [string]$activeColor, [string]$inactiveColor, [string]$borderColor, [string]$reset) {
        # HIGH FIX KSV2-H1: Add null check on $title parameter (duplicate in direct render)
        if ($null -eq $title) { $title = "" }

        $titleColor = $(if ($isActive) { $activeColor } else { $inactiveColor })

        # Top border with title: ┌─ TITLE ───┐
        $titleLen = $title.Length + 3  # "─ " + title
        $remainingWidth = $width - $titleLen - 1
        if ($remainingWidth -gt 0) {
            $topLine = $borderColor + "┌─ " + $reset + $titleColor + $title + $reset + $borderColor + " " + ("─" * $remainingWidth) + "┐" + $reset
        }
        else {
            $topLine = $borderColor + "┌─ " + $reset + $titleColor + $title + $reset + $borderColor + "┐" + $reset
        }
        $engine.WriteAt($x - 1, $y - 1, $topLine)  # Convert to 0-based

        # Left and right borders for each line
        for ($i = 1; $i -lt $height; $i++) {
            $lineY = $y + $i
            # Left border
            $engine.WriteAt($x - 1, $lineY - 1, $borderColor + "│" + $reset)
            # Right border
            $engine.WriteAt($x + $width - 2, $lineY - 1, $borderColor + "│" + $reset)
        }

        # Bottom border: └─────┘
        $bottomLine = $borderColor + "└" + ("─" * ($width - 2)) + "┘" + $reset
        $engine.WriteAt($x - 1, $y + $height - 1, $bottomLine)
    }

    # Render column tasks directly to engine (no string building)
    # LOW FIX KSV2-L1 TODO: Refactor to extract common card rendering logic shared with _RenderColumn()
    # to reduce code duplication and improve maintainability
    hidden [void] _RenderColumnDirect([object]$engine, [int]$x, [int]$y, [int]$maxLines, [int]$width, [array]$tasks, [int]$selectedIndex, [int]$scrollOffset, [bool]$isActiveColumn) {
        $textColor = $this.Header.GetThemedFg('Foreground.Field')
        $selectedBg = $this.Header.GetThemedBg('Background.FieldFocused', 80, 0)
        $selectedFg = $this.Header.GetThemedFg('Foreground.Field')
        $cursorColor = $this.Header.GetThemedFg('Foreground.FieldFocused')
        $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
        $reset = "`e[0m"

        # Build flat list including subtasks
        $flatList = $this._BuildFlatTaskList($tasks)

        # Each task card takes 4 lines
        $linesPerCard = 4
        $maxCards = [Math]::Floor($maxLines / $linesPerCard)

        # Calculate visible range
        $visibleStart = $scrollOffset
        $visibleEnd = [Math]::Min($flatList.Count, $scrollOffset + $maxCards)

        $visibleTasks = @()
        # CRITICAL FIX KSV2-C5: Validate range before array slice (duplicate in direct render)
        if ($visibleStart -lt $flatList.Count -and $visibleEnd -gt $visibleStart) {
            $visibleTasks = $flatList[$visibleStart..($visibleEnd - 1)]
        }

        # Render visible tasks as bordered cards
        $currentY = $y
        for ($i = 0; $i -lt $visibleTasks.Count; $i++) {
            $item = $visibleTasks[$i]
            # CRITICAL FIX KSV2-C6 & C11: Add null check before accessing .Task property
            if ($null -eq $item -or $null -eq $item.Task) {
                Write-PmcTuiLog "KanbanScreenV2._RenderColumn: item or item.Task is null at index $i" "WARNING"
                continue
            }
            $task = $item.Task
            $depth = $item.Depth
            $globalIndex = $visibleStart + $i
            $isSelected = ($globalIndex -eq $selectedIndex) -and $isActiveColumn

            # Get custom color
            $customColor = $this._GetTaskColor($task)
            $cardColor = $textColor
            if ($customColor) {
                $cardColor = $this._HexToAnsi($customColor, $false)
            }

            # Build task text with hierarchy
            $indent = "  " * $depth
            $prefix = ""

            if ($this._HasChildren($task)) {
                $taskId = Get-SafeProperty $task 'id'
                if ($this.ExpandedParents.Contains($taskId)) {
                    $prefix = "▼ "
                }
                else {
                    $prefix = "▸ "
                }
            }
            elseif ($depth -gt 0) {
                $prefix = "├─"
            }

            $taskPriority = Get-SafeProperty $task 'priority'
            if ($taskPriority -gt 0) {
                $prefix += "P$taskPriority "
            }

            # HIGH FIX KSV2-H7: Add null check before string concatenation (duplicate in direct render)
            $taskTextValue = Get-SafeProperty $task 'text'
            if (-not $taskTextValue) { $taskTextValue = "" }
            $taskText = $indent + $prefix + $taskTextValue

            # Get tags
            $taskTags = Get-SafeProperty $task 'tags'
            $tagsText = ""
            if ($taskTags -and $taskTags.Count -gt 0) {
                $tagsText = "#" + ($taskTags -join " #")
            }

            # Card dimensions
            $cardWidth = $width - 2
            $innerWidth = $cardWidth - 2

            # Truncate if needed
            # HIGH FIX KSV2-H8: Add null check before .Length access (duplicate in direct render)
            if ($taskText -and $taskText.Length -gt $innerWidth) {
                $taskText = $taskText.Substring(0, $innerWidth - 3) + "..."
            }
            if ($tagsText -and $tagsText.Length -gt $innerWidth) {
                $tagsText = $tagsText.Substring(0, $innerWidth - 3) + "..."
            }

            # Determine colors
            $borderColor = $cardColor
            $contentColor = $cardColor
            if ($isSelected) {
                $borderColor = $selectedBg + $selectedFg
                $contentColor = $selectedBg + $selectedFg
            }

            # Top border: ┌────────┐
            # Selected cards use different background color (no external cursor needed)
            $topBorder = $borderColor + "┌" + ("─" * $innerWidth) + "┐" + $reset
            $engine.WriteAt($x - 1, $currentY - 1, $topBorder)
            $currentY++

            # Text line: │ task text │
            $paddedText = $taskText.PadRight($innerWidth)
            $textLine = $borderColor + "│" + $reset + $contentColor + $paddedText + $reset + $borderColor + "│" + $reset
            $engine.WriteAt($x - 1, $currentY - 1, $textLine)
            $currentY++

            # Tags line: │ #tags │
            $paddedTags = $tagsText.PadRight($innerWidth)
            $tagsLine = $borderColor + "│" + $reset + $mutedColor + $paddedTags + $reset + $borderColor + "│" + $reset
            $engine.WriteAt($x - 1, $currentY - 1, $tagsLine)
            $currentY++

            # Bottom border: └────────┘
            $bottomBorder = $borderColor + "└" + ("─" * $innerWidth) + "┘" + $reset
            $engine.WriteAt($x - 1, $currentY - 1, $bottomBorder)
            $currentY++
        }

        # Scroll indicators
        if ($scrollOffset -gt 0) {
            $engine.WriteAt($x - 1, $y - 2, $mutedColor + "↑ More above" + $reset)
        }
        if ($visibleEnd -lt $flatList.Count) {
            $remaining = $flatList.Count - $visibleEnd
            $engine.WriteAt($x - 1, $currentY - 1, $mutedColor + "↓ +$remaining more" + $reset)
        }
    }
}

# Entry point function for compatibility
function Show-KanbanScreenV2 {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = [KanbanScreenV2]::new()
    $App.PushScreen($screen)
}