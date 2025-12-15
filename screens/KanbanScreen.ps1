using namespace System.Collections.Generic
using namespace System.Text

# KanbanScreen - Shows tasks in 3-column kanban board
# Displays tasks grouped by status: TODO / In Progress / Done


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Kanban board view with 3 columns

.DESCRIPTION
Shows tasks grouped into 3 columns based on status:
- TODO (pending/blocked/waiting)
- In Progress (in-progress)
- Done (done/completed in last 7 days)

Uses left/right arrow keys to navigate between columns.
#>
class KanbanScreen : PmcScreen {
    # Data
    [array]$TodoTasks = @()
    [array]$InProgressTasks = @()
    [array]$DoneTasks = @()

    # Navigation
    [int]$SelectedColumn = 0  # 0=TODO, 1=InProgress, 2=Done
    [int]$SelectedIndexTodo = 0
    [int]$SelectedIndexInProgress = 0
    [int]$SelectedIndexDone = 0

    # TaskStore for data access
    [TaskStore]$Store = $null

    # Constructor
    KanbanScreen() : base("Kanban", "Kanban Board") {
        # Initialize TaskStore
        $this.Store = [TaskStore]::GetInstance()
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tasks", "Kanban"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Up/Down", "Select")
        $this.Footer.AddShortcut("Left/Right", "Column")
        $this.Footer.AddShortcut("Enter", "Detail")
        $this.Footer.AddShortcut("M", "Move")
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    # Constructor with container
    KanbanScreen([object]$container) : base("Kanban", "Kanban Board", $container) {
        # Initialize TaskStore
        $this.Store = [TaskStore]::GetInstance()

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tasks", "Kanban"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Up/Down", "Select")
        $this.Footer.AddShortcut("Left/Right", "Column")
        $this.Footer.AddShortcut("Enter", "Detail")
        $this.Footer.AddShortcut("M", "Move")
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    [void] LoadData() {
        $this.ShowStatus("Loading kanban board...")

        try {
            # Load tasks from TaskStore
            # CRITICAL FIX KAN-C2: Add null check on GetAllTasks()
            $allTasks = $this.Store.GetAllTasks()
            if ($null -eq $allTasks) {
                Write-PmcTuiLog "KanbanScreen.LoadData: GetAllTasks() returned null" "WARNING"
                $allTasks = @()
            }
            $sevenDaysAgo = (Get-Date).AddDays(-7)

            # HIGH FIX KAN-H1: Single-pass filtering instead of 3 separate Where-Object calls
            # Group tasks in one iteration for O(n) instead of O(3n)
            $todoList = [System.Collections.ArrayList]::new()
            $inProgressList = [System.Collections.ArrayList]::new()
            $doneList = [System.Collections.ArrayList]::new()

            foreach ($task in $allTasks) {
                $taskCompleted = Get-SafeProperty $task 'completed'
                $taskStatus = Get-SafeProperty $task 'status'
                $taskCompletedDate = Get-SafeProperty $task 'completedDate'

                # TODO column: pending, blocked, waiting (not completed)
                if (-not $taskCompleted -and ($taskStatus -eq 'pending' -or $taskStatus -eq 'blocked' -or $taskStatus -eq 'waiting' -or -not $taskStatus)) {
                    [void]$todoList.Add($task)
                }
                # In Progress column: in-progress (not completed)
                elseif (-not $taskCompleted -and $taskStatus -eq 'in-progress') {
                    [void]$inProgressList.Add($task)
                }
                # Done column: completed in last 7 days OR status=done
                # CRITICAL FIX KAN-C3: Safe DateTime parsing with try-catch
                elseif ($taskStatus -eq 'done') {
                    [void]$doneList.Add($task)
                }
                elseif ($taskCompleted -and $taskCompletedDate) {
                    try {
                        $completedDateTime = [DateTime]$taskCompletedDate
                        if ($completedDateTime -gt $sevenDaysAgo) {
                            [void]$doneList.Add($task)
                        }
                    }
                    catch {
                        Write-PmcTuiLog "KanbanScreen: Invalid completedDate format: $taskCompletedDate" "WARNING"
                        # Skip this task from Done column if date is invalid
                    }
                }
            }

            # Sort and convert to arrays
            $this.TodoTasks = @($todoList.ToArray() | Sort-Object { Get-SafeProperty $_ 'priority' }, { Get-SafeProperty $_ 'id' })
            $this.InProgressTasks = @($inProgressList.ToArray() | Sort-Object { Get-SafeProperty $_ 'priority' }, { Get-SafeProperty $_ 'id' })
            $this.DoneTasks = @($doneList.ToArray() | Sort-Object { Get-SafeProperty $_ 'completedDate' }, { Get-SafeProperty $_ 'id' })

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
            # KAN-3 FIX: Show proper error to user instead of silent failure
            $errorMsg = "Failed to load kanban board: $($_.Exception.Message)"
            $this.ShowError($errorMsg)
            Write-PmcTuiLog "KanbanScreen.LoadData ERROR: $_" "ERROR"

            # Reset to empty state so screen doesn't show stale data
            $this.TodoTasks = @()
            $this.InProgressTasks = @()
            $this.DoneTasks = @()

            # Log the full error for debugging
            Write-PmcTuiLog "KanbanScreen.LoadData full exception: $($_.Exception | Format-List -Force | Out-String)" "ERROR"
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        if (-not $this.LayoutManager) {
            return
        }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.Field')
        $cursorColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $priorityColor = $this.Header.GetThemedColorInt('Warning')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $successColor = $this.Header.GetThemedColorInt('Foreground.Success')
        $defaultBg = $this.Header.GetThemedColorInt('Background.Default')

        # Calculate column widths (3 equal columns with borders)
        $columnWidth = [Math]::Floor(($contentRect.Width - 6) / 3)
        $col1X = $contentRect.X + 2
        $col2X = $col1X + $columnWidth + 2
        $col3X = $col2X + $columnWidth + 2

        # Starting Y position
        $startY = $contentRect.Y + 1

        # Render column headers
        $this._RenderHeader($engine, $col1X, $startY, "TODO ($($this.TodoTasks.Count))", ($this.SelectedColumn -eq 0), $cursorColor, $headerColor, $defaultBg)
        $this._RenderHeader($engine, $col2X, $startY, "IN PROGRESS ($($this.InProgressTasks.Count))", ($this.SelectedColumn -eq 1), $cursorColor, $headerColor, $defaultBg)
        $this._RenderHeader($engine, $col3X, $startY, "DONE ($($this.DoneTasks.Count))", ($this.SelectedColumn -eq 2), $cursorColor, $headerColor, $defaultBg)

        # Render separator line
        $separatorY = $startY + 1
        $separatorLine = "-" * $contentRect.Width
        $engine.WriteAt($contentRect.X, $separatorY, $separatorLine, $mutedColor, $defaultBg)

        # Render task items in columns
        $maxLines = $contentRect.Height - 4
        $taskStartY = $separatorY + 1

        # Render TODO column
        $this._RenderColumnToEngine($engine, $col1X, $taskStartY, $maxLines, $columnWidth, $this.TodoTasks, $this.SelectedIndexTodo, ($this.SelectedColumn -eq 0), $defaultBg)

        # Render In Progress column
        $this._RenderColumnToEngine($engine, $col2X, $taskStartY, $maxLines, $columnWidth, $this.InProgressTasks, $this.SelectedIndexInProgress, ($this.SelectedColumn -eq 1), $defaultBg)

        # Render Done column
        $this._RenderColumnToEngine($engine, $col3X, $taskStartY, $maxLines, $columnWidth, $this.DoneTasks, $this.SelectedIndexDone, ($this.SelectedColumn -eq 2), $defaultBg)
    }

    hidden [void] _RenderHeader([object]$engine, [int]$x, [int]$y, [string]$text, [bool]$isSelected, [int]$selectedColor, [int]$normalColor, [int]$bg) {
        $color = if ($isSelected) { $selectedColor } else { $normalColor }
        $engine.WriteAt($x, $y, $text, $color, $bg)
    }

    hidden [void] _RenderColumnToEngine([object]$engine, [int]$x, [int]$y, [int]$maxLines, [int]$width, [array]$tasks, [int]$selectedIndex, [bool]$isActiveColumn, [int]$defaultBg) {
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.Field')
        $cursorColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $priorityColor = $this.Header.GetThemedColorInt('Warning')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')

        for ($i = 0; $i -lt [Math]::Min($tasks.Count, $maxLines); $i++) {
            $task = $tasks[$i]
            $lineY = $y + $i
            $isSelected = ($i -eq $selectedIndex) -and $isActiveColumn

            # Cursor
            if ($isSelected) {
                $engine.WriteAt($x - 1, $lineY, ">", $cursorColor, $defaultBg)
            }

            # Task text logic
            $taskPriority = Get-SafeProperty $task 'priority'
            $taskTextValue = Get-SafeProperty $task 'text'
            if ($null -eq $taskTextValue) { $taskTextValue = "" }

            $taskText = ""
            if ($taskPriority -gt 0) {
                $taskText = "P$taskPriority "
            }
            $taskText += $taskTextValue

            # Truncate
            $maxWidth = $width - 2
            if ($null -ne $taskText -and $taskText.Length -gt $maxWidth) {
                $taskText = $taskText.Substring(0, $maxWidth - 3) + "..."
            }

            $fg = $textColor
            $bg = $defaultBg

            if ($isSelected) {
                $fg = $selectedFg
                $bg = $selectedBg
                # Draw full background for selected item
                $paddedText = $taskText.PadRight($maxWidth)
                $engine.WriteAt($x, $lineY, $paddedText, $fg, $bg)
            }
            else {
                # Normal item rendering
                # If priority, we need multi-color writing or just simplify
                # Simplify to single color for now to match engine API cleanliness or use multiple WriteAt
                
                if ($taskPriority -gt 0) {
                    $prioText = "P$taskPriority "
                    $engine.WriteAt($x, $lineY, $prioText, $priorityColor, $defaultBg)
                    
                    # Remaining text
                    $remText = $taskTextValue
                    $remWidth = $maxWidth - $prioText.Length
                    if ($remText.Length -gt $remWidth) {
                        $remText = $remText.Substring(0, $remWidth - 3) + "..."
                    }
                    $engine.WriteAt($x + $prioText.Length, $lineY, $remText, $textColor, $defaultBg)
                }
                else {
                    $engine.WriteAt($x, $lineY, $taskText, $textColor, $defaultBg)
                }
            }
        }

        # Show truncation indicator if needed
        if ($tasks.Count -gt $maxLines) {
            $lineY = $y + $maxLines
            $remaining = $tasks.Count - $maxLines
            $engine.WriteAt($x, $lineY, "... +$remaining more", $mutedColor, $defaultBg)
        }
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyInfo.Key) {
            'Enter' {
                $this._ShowTaskDetail()
                return $true
            }
            'LeftArrow' {
                if ($this.SelectedColumn -gt 0) {
                    $this.SelectedColumn--
                    return $true
                }
            }
            'RightArrow' {
                if ($this.SelectedColumn -lt 2) {
                    $this.SelectedColumn++
                    return $true
                }
            }
            'UpArrow' {
                $this._MoveSelectionUp()
                return $true
            }
            'DownArrow' {
                $this._MoveSelectionDown()
                return $true
            }
        }

        switch ($keyChar) {
            'm' {
                $this._MoveTask()
                return $true
            }
            'r' {
                $this.LoadData()
                return $true
            }
        }

        return $false
    }

    hidden [void] _MoveSelectionUp() {
        switch ($this.SelectedColumn) {
            0 {
                if ($this.SelectedIndexTodo -gt 0) {
                    $this.SelectedIndexTodo--
                }
            }
            1 {
                if ($this.SelectedIndexInProgress -gt 0) {
                    $this.SelectedIndexInProgress--
                }
            }
            2 {
                if ($this.SelectedIndexDone -gt 0) {
                    $this.SelectedIndexDone--
                }
            }
        }
    }

    hidden [void] _MoveSelectionDown() {
        # HIGH FIX KAN-H2: Prevent navigation when array is empty (Count = 0)
        switch ($this.SelectedColumn) {
            0 {
                if ($this.TodoTasks.Count -gt 0 -and $this.SelectedIndexTodo -lt ($this.TodoTasks.Count - 1)) {
                    $this.SelectedIndexTodo++
                }
            }
            1 {
                if ($this.InProgressTasks.Count -gt 0 -and $this.SelectedIndexInProgress -lt ($this.InProgressTasks.Count - 1)) {
                    $this.SelectedIndexInProgress++
                }
            }
            2 {
                if ($this.DoneTasks.Count -gt 0 -and $this.SelectedIndexDone -lt ($this.DoneTasks.Count - 1)) {
                    $this.SelectedIndexDone++
                }
            }
        }
    }

    hidden [void] _MoveTask() {
        $task = $this._GetSelectedTask()
        if ($task) {
            # HIGH FIX KAN-H3: Cycle through all statuses including blocked/waiting
            # Cycle: pending -> in-progress -> blocked -> waiting -> done -> pending
            $taskId = Get-SafeProperty $task 'id'
            $taskStatus = Get-SafeProperty $task 'status'
            $newStatus = 'in-progress'  # Initialize variable for strict mode
            $completedDate = $null
            switch ($taskStatus) {
                'pending' { $newStatus = 'in-progress' }
                'in-progress' { $newStatus = 'blocked' }
                'blocked' { $newStatus = 'waiting' }
                'waiting' {
                    $newStatus = 'done'
                    $completedDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                }
                'done' { $newStatus = 'pending' }
                default { $newStatus = 'in-progress' }
            }

            # Build changes hashtable
            $changes = @{ status = $newStatus }
            if ($newStatus -eq 'done') {
                $changes.completed = $true
                $changes.completedDate = $completedDate
            }
            elseif ($newStatus -eq 'pending') {
                $changes.completed = $false
                $changes.completedDate = $null
            }

            # CRITICAL FIX KAN-C1: Optimistic UI update before Store persistence
            # Apply changes to local task object immediately for responsive UI
            foreach ($key in $changes.Keys) {
                if ($task -is [hashtable]) {
                    $task[$key] = $changes[$key]
                }
                else {
                    $task.$key = $changes[$key]
                }
            }
            # Refresh UI immediately with optimistic changes
            $this.LoadData()

            # Update via TaskStore (handles validation, events, persistence, rollback)
            $success = $this.Store.UpdateTask($taskId, $changes)
            if ($success) {
                $this.ShowSuccess("Moved task #$taskId to $newStatus")
                # Data already refreshed optimistically above
            }
            else {
                $this.ShowError("Failed to move task: $($this.Store.LastError)")
                # Rollback: Reload from store to revert optimistic changes
                $this.LoadData()
            }
        }
    }

    hidden [object] _GetSelectedTask() {
        switch ($this.SelectedColumn) {
            0 {
                if ($this.SelectedIndexTodo -ge 0 -and $this.SelectedIndexTodo -lt $this.TodoTasks.Count) {
                    return $this.TodoTasks[$this.SelectedIndexTodo]
                }
            }
            1 {
                if ($this.SelectedIndexInProgress -ge 0 -and $this.SelectedIndexInProgress -lt $this.InProgressTasks.Count) {
                    return $this.InProgressTasks[$this.SelectedIndexInProgress]
                }
            }
            2 {
                if ($this.SelectedIndexDone -ge 0 -and $this.SelectedIndexDone -lt $this.DoneTasks.Count) {
                    return $this.DoneTasks[$this.SelectedIndexDone]
                }
            }
        }
        return $null
    }

    hidden [void] _ShowTaskDetail() {
        $task = $this._GetSelectedTask()
        if ($null -eq $task) {
            $this.ShowStatus("No task selected", "warning")
            return
        }

        $taskId = Get-SafeProperty $task 'id'
        if ($taskId) {
            # CRITICAL FIX KAN-C4: Add null check on $global:PmcApp
            if ($null -eq $global:PmcApp) {
                Write-PmcTuiLog "KanbanScreen._ShowTaskDetail: global:PmcApp is null" "ERROR"
                $this.ShowError("Application context not available")
                return
            }
            . "$PSScriptRoot/TaskDetailScreen.ps1"
            $detailScreen = New-Object TaskDetailScreen -ArgumentList $taskId
            $global:PmcApp.PushScreen($detailScreen)
        }
        else {
            $this.ShowError("Selected task has no ID")
        }
    }
}

# Entry point function for compatibility
function Show-KanbanScreen {
    param([object]$App)

    # MEDIUM FIX KAN-M2: Enhanced parameter validation
    if ($null -eq $App) {
        Write-PmcTuiLog "Show-KanbanScreen: App parameter is null" "ERROR"
        throw "PmcApplication required"
    }

    # Verify App has required method
    if (-not ($App.PSObject.Methods['PushScreen'])) {
        Write-PmcTuiLog "Show-KanbanScreen: App missing PushScreen method" "ERROR"
        throw "PmcApplication does not have PushScreen method"
    }

    $screen = New-Object KanbanScreen
    $App.PushScreen($screen)
}