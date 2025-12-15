using namespace System.Collections.Generic
using namespace System.Text

# TaskDetailScreen - Shows detailed view of a single task
# Displays all fields for a specific task


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Screen showing detailed view of a single task

.DESCRIPTION
Shows all fields and metadata for a specific task:
- ID, text, project
- Priority, status, due date
- Created/completed dates
- Tags, dependencies
- Notes, subtasks
- Recurrence, estimated time
#>
class TaskDetailScreen : PmcScreen {
    # Data
    [object]$Task = $null
    [int]$TaskId = 0

    # Constructor with task ID
    TaskDetailScreen([int]$taskId) : base("TaskDetail", "Task Detail") {
        $this.TaskId = $taskId

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tasks", "Detail"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("E", "Edit")
        $this.Footer.AddShortcut("C", "Complete")
        $this.Footer.AddShortcut("D", "Delete")
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    # Constructor with container
    TaskDetailScreen([int]$taskId, [object]$container) : base("TaskDetail", "Task Detail", $container) {
        $this.TaskId = $taskId

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tasks", "Detail"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("E", "Edit")
        $this.Footer.AddShortcut("C", "Complete")
        $this.Footer.AddShortcut("D", "Delete")
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    # Default constructor (for compatibility)
    TaskDetailScreen() : base("TaskDetail", "Task Detail") {
        $this.TaskId = 0

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tasks", "Detail"))

        # Configure footer
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    [void] LoadData() {
        if ($this.TaskId -eq 0) {
            $this.ShowError("No task ID specified")
            return
        }

        $this.ShowStatus("Loading task #$($this.TaskId)...")

        try {
            # Load PMC data
            $data = Get-PmcData

            # CRITICAL: Validate data before use
            if ($null -eq $data) {
                $this.ShowError("Failed to load data - data is null")
                $this.Task = $null
                return
            }

            if ($null -eq $data.tasks) {
                $this.ShowError("Failed to load data - tasks collection is null")
                $this.Task = $null
                return
            }

            # Find the task
            $this.Task = $data.tasks | Where-Object { ($_.id) -eq $this.TaskId } | Select-Object -First 1

            if (-not $this.Task) {
                $this.ShowError("Task #$($this.TaskId) not found")
                return
            }

            # Update header with task ID
            $this.Header.SetTitle("Task #$($this.TaskId)")
            $this.ShowStatus("Loaded task #$($this.TaskId)")

        } catch {
            $this.ShowError("Failed to load task: $_")
            $this.Task = $null
        }
    }

    [string] RenderContent() {
        if (-not $this.Task) {
            return $this._RenderEmptyState()
        }

        return $this._RenderTaskDetail()
    }

    hidden [string] _RenderEmptyState() {
        $sb = [System.Text.StringBuilder]::new(512)

        # Get content area
        if ($this.LayoutManager) {
            $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

            # Center message
            $message = $(if ($this.TaskId -eq 0) { "No task selected" } else { "Task #$($this.TaskId) not found" })
            $x = $contentRect.X + [Math]::Floor(($contentRect.Width - $message.Length) / 2)
            $y = $contentRect.Y + [Math]::Floor($contentRect.Height / 2)

            $errorColor = $this.Header.GetThemedFg('Foreground.Error')
            $reset = "`e[0m"

            $sb.Append($this.Header.BuildMoveTo($x, $y))
            $sb.Append($errorColor)
            $sb.Append($message)
            $sb.Append($reset)
        }

        return $sb.ToString()
    }

    hidden [string] _RenderTaskDetail() {
        $sb = [System.Text.StringBuilder]::new(4096)

        if (-not $this.LayoutManager) {
            return $sb.ToString()
        }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors
        $textColor = $this.Header.GetThemedFg('Foreground.Field')
        $labelColor = $this.Header.GetThemedFg('Foreground.Muted')
        $valueColor = $this.Header.GetThemedFg('Foreground.Field')
        $priorityColor = $this.Header.GetThemedAnsi('Warning', $false)
        $successColor = $this.Header.GetThemedFg('Foreground.Success')
        $errorColor = $this.Header.GetThemedFg('Foreground.Error')
        $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
        $reset = "`e[0m"

        $x = $contentRect.X + 4
        $y = $contentRect.Y + 2
        $labelWidth = 18

        # Task ID and Status
        $taskIdValue = $this.Task.id
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($labelColor)
        $sb.Append("ID:".PadRight($labelWidth))
        $sb.Append($reset)
        $sb.Append($valueColor)
        $sb.Append("#$taskIdValue")
        $sb.Append($reset)

        # Completion status indicator
        $sb.Append("  ")
        $taskCompleted = $this.Task.completed
        $taskStatus = $this.Task.status
        if ($taskCompleted) {
            $sb.Append($successColor)
            $sb.Append("[COMPLETED]")
        } else {
            $statusColor = $textColor
            if ($taskStatus -eq 'blocked') { $statusColor = $errorColor }
            elseif ($taskStatus -eq 'in-progress') { $statusColor = $priorityColor }
            $sb.Append($statusColor)
            $sb.Append("[$($taskStatus.ToUpper())]")
        }
        $sb.Append($reset)
        $y++

        # Text
        $y++
        $taskText = $this.Task.text
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($labelColor)
        $sb.Append("Task:".PadRight($labelWidth))
        $sb.Append($reset)
        $sb.Append($valueColor)
        $sb.Append($taskText)
        $sb.Append($reset)
        $y++

        # Project
        $y++
        $taskProject = $this.Task.project
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($labelColor)
        $sb.Append("Project:".PadRight($labelWidth))
        $sb.Append($reset)
        $sb.Append($valueColor)
        $sb.Append($taskProject)
        $sb.Append($reset)
        $y++

        # Priority
        $y++
        $taskPriority = $this.Task.priority
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($labelColor)
        $sb.Append("Priority:".PadRight($labelWidth))
        $sb.Append($reset)
        if ($taskPriority -gt 0) {
            $sb.Append($priorityColor)
            $sb.Append("P$taskPriority")
        } else {
            $sb.Append($mutedColor)
            $sb.Append("None")
        }
        $sb.Append($reset)
        $y++

        # Status
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($labelColor)
        $sb.Append("Status:".PadRight($labelWidth))
        $sb.Append($reset)
        $sb.Append($valueColor)
        $sb.Append($taskStatus)
        $sb.Append($reset)
        $y++

        # Due Date
        $y++
        $taskDue = $this.Task.due
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($labelColor)
        $sb.Append("Due Date:".PadRight($labelWidth))
        $sb.Append($reset)
        if ($taskDue) {
            $schema = Get-PmcFieldSchema -Domain 'task' -Field 'due'
            $dueDisplay = & $schema.DisplayFormat $taskDue

            # Color based on due date
            $dueDate = ([DateTime]$taskDue).Date
            $today = (Get-Date).Date
            if (-not $taskCompleted -and $dueDate -lt $today) {
                $sb.Append($errorColor)
                $sb.Append("$dueDisplay (OVERDUE)")
            } elseif ($dueDate -eq $today) {
                $sb.Append($priorityColor)
                $sb.Append("$dueDisplay (TODAY)")
            } else {
                $sb.Append($valueColor)
                $sb.Append($dueDisplay)
            }
        } else {
            $sb.Append($mutedColor)
            $sb.Append("Not set")
        }
        $sb.Append($reset)
        $y++

        # Created Date
        $taskCreated = $this.Task.created
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($labelColor)
        $sb.Append("Created:".PadRight($labelWidth))
        $sb.Append($reset)
        if ($taskCreated) {
            $sb.Append($mutedColor)
            $sb.Append($taskCreated)
        } else {
            $sb.Append($mutedColor)
            $sb.Append("Unknown")
        }
        $sb.Append($reset)
        $y++

        # Completed Date
        $taskCompletedDate = $this.Task.completedDate
        if ($taskCompleted -and $taskCompletedDate) {
            $sb.Append($this.Header.BuildMoveTo($x, $y))
            $sb.Append($labelColor)
            $sb.Append("Completed:".PadRight($labelWidth))
            $sb.Append($reset)
            $sb.Append($successColor)
            $sb.Append($taskCompletedDate)
            $sb.Append($reset)
            $y++
        }

        # Estimated Time
        $y++
        $taskEstimatedMinutes = $this.Task.estimatedMinutes
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($labelColor)
        $sb.Append("Estimated Time:".PadRight($labelWidth))
        $sb.Append($reset)
        if ($taskEstimatedMinutes) {
            $hours = [Math]::Floor($taskEstimatedMinutes / 60)
            $mins = $taskEstimatedMinutes % 60
            $sb.Append($valueColor)
            if ($hours -gt 0) {
                $sb.Append("${hours}h ${mins}m")
            } else {
                $sb.Append("${mins}m")
            }
        } else {
            $sb.Append($mutedColor)
            $sb.Append("Not set")
        }
        $sb.Append($reset)
        $y++

        # Recurrence
        $taskRecur = $this.Task.recur
        if ($taskRecur) {
            $sb.Append($this.Header.BuildMoveTo($x, $y))
            $sb.Append($labelColor)
            $sb.Append("Recurrence:".PadRight($labelWidth))
            $sb.Append($reset)
            $sb.Append($valueColor)
            $sb.Append($taskRecur)
            $sb.Append($reset)
            $y++
        }

        # Tags
        $y++
        $taskTags = $this.Task.tags
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($labelColor)
        $sb.Append("Tags:".PadRight($labelWidth))
        $sb.Append($reset)
        if ($taskTags -and $taskTags.Count -gt 0) {
            $sb.Append($valueColor)
            $sb.Append(($taskTags -join ", "))
        } else {
            $sb.Append($mutedColor)
            $sb.Append("None")
        }
        $sb.Append($reset)
        $y++

        # Dependencies
        $taskDepends = $this.Task.depends
        $sb.Append($this.Header.BuildMoveTo($x, $y))
        $sb.Append($labelColor)
        $sb.Append("Depends On:".PadRight($labelWidth))
        $sb.Append($reset)
        if ($taskDepends -and $taskDepends.Count -gt 0) {
            $sb.Append($valueColor)
            $sb.Append(($taskDepends -join ", "))
        } else {
            $sb.Append($mutedColor)
            $sb.Append("None")
        }
        $sb.Append($reset)
        $y++

        # Notes
        $taskNotes = $this.Task.notes
        if ($taskNotes -and $taskNotes.Count -gt 0) {
            $y++
            $y++
            $sb.Append($this.Header.BuildMoveTo($x, $y))
            $sb.Append($labelColor)
            $sb.Append("Notes:")
            $sb.Append($reset)
            $y++

            foreach ($note in $taskNotes) {
                $sb.Append($this.Header.BuildMoveTo($x + 2, $y))
                $sb.Append($mutedColor)
                $sb.Append("- ")
                $sb.Append($reset)
                $sb.Append($textColor)
                $noteText = [string]$note
                $maxWidth = $contentRect.Width - $x - 4
                if ($noteText.Length -gt $maxWidth) {
                    $noteText = $noteText.Substring(0, $maxWidth - 3) + "..."
                }
                $sb.Append($noteText)
                $sb.Append($reset)
                $y++
            }
        }

        # Subtasks
        $taskSubtasks = $this.Task.subtasks
        if ($taskSubtasks -and $taskSubtasks.Count -gt 0) {
            $y++
            $y++
            $sb.Append($this.Header.BuildMoveTo($x, $y))
            $sb.Append($labelColor)
            $sb.Append("Subtasks:")
            $sb.Append($reset)
            $y++

            foreach ($subtask in $taskSubtasks) {
                $sb.Append($this.Header.BuildMoveTo($x + 2, $y))
                $sb.Append($mutedColor)
                $sb.Append("[ ] ")
                $sb.Append($reset)
                $sb.Append($textColor)
                $subtaskText = [string]$subtask
                $maxWidth = $contentRect.Width - $x - 6
                if ($subtaskText.Length -gt $maxWidth) {
                    $subtaskText = $subtaskText.Substring(0, $maxWidth - 3) + "..."
                }
                $sb.Append($subtaskText)
                $sb.Append($reset)
                $y++
            }
        }

        return $sb.ToString()
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # CRITICAL: Call parent FIRST for MenuBar, F10, Alt+keys, content widgets
        $handled = ([PmcScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        if (-not $this.Task) {
            return $false
        }

        $keyChar = [char]::ToLower($keyInfo.KeyChar)

        switch ($keyChar) {
            'e' {
                $this._EditTask()
                return $true
            }
            'c' {
                $this._CompleteTask()
                return $true
            }
            'd' {
                $this._DeleteTask()
                return $true
            }
            'r' {
                $this.LoadData()
                return $true
            }
        }

        return $false
    }

    hidden [void] _EditTask() {
        if ($this.Task) {
            $taskIdValue = $this.Task.id
            $this.ShowStatus("Edit task: [$taskIdValue]")
            . "$PSScriptRoot/TaskListScreen.ps1"
            $global:PmcApp.PopScreen()
            $global:PmcApp.PushScreen((New-Object -TypeName TaskListScreen))
        }
    }

    hidden [void] _CompleteTask() {
        if (-not $this.Task) {
            return
        }

        $this.TaskId = $this.Task.id

        # Update storage
        $allData = Get-PmcData
        $taskToComplete = $allData.tasks | Where-Object { ($_.id) -eq $this.TaskId }

        if ($taskToComplete) {
            $taskToComplete.completed = $true
            $taskToComplete.completedDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            # FIX: Use Save-PmcData instead of Set-PmcAllData
            Save-PmcData -Data $allData
        }

        $this.ShowSuccess("Task #$($this.TaskId) completed")
        $this.LoadData()  # Reload to show updated status
    }

    hidden [void] _DeleteTask() {
        if (-not $this.Task) {
            return
        }

        $this.TaskId = $this.Task.id

        # Update storage
        $allData = Get-PmcData
        $allData.tasks = @($allData.tasks | Where-Object { ($_.id) -ne $this.TaskId })
        # FIX: Use Save-PmcData instead of Set-PmcAllData
        Save-PmcData -Data $allData

        $this.ShowSuccess("Task #$($this.TaskId) deleted - Press Esc to go back")
        $this.Task = $null  # Clear task to show empty state
    }

    # Helper method to set task ID after construction
    [void] SetTaskId([int]$taskId) {
        $this.TaskId = $taskId
    }
}

# Entry point function for compatibility
function Show-TaskDetailScreen {
    param(
        [object]$App,
        [int]$TaskId
    )

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object TaskDetailScreen -ArgumentList $TaskId
    $App.PushScreen($screen)
}