using namespace System.Collections.Generic
using namespace System.Text

# BlockedTasksScreen - Migrated from DrawBlockedView in ConsoleUI.Core.ps1
# Shows blocked and waiting tasks in new widget architecture

Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Screen showing blocked/waiting tasks

.DESCRIPTION
Migrated from DrawBlockedView() method.
Shows list of tasks with status 'blocked' or 'waiting'.
#>
class BlockedTasksScreen : PmcScreen {
    # Data
    [array]$BlockedTasks = @()
    [int]$SelectedIndex = 0
    [string]$InputBuffer = ""
    [string]$InputMode = ""  # "", "edit-field"
    [string]$EditField = ""  # Which field being edited (priority, text)
    [array]$EditableFields = @('priority', 'text')
    [int]$EditFieldIndex = 0

    # Content panel
    [PmcPanel]$ContentPanel

    # TaskStore instance (singleton)
    [object]$Store = $null

    # Legacy constructor (backward compatible)
    BlockedTasksScreen() : base("BlockedTasks", "Blocked/Waiting Tasks") {
        $this._InitializeScreen()
    }

    # Container constructor
    BlockedTasksScreen([object]$container) : base("BlockedTasks", "Blocked/Waiting Tasks", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        # Get TaskStore singleton
        $this.Store = [TaskStore]::GetInstance()

        # Subscribe to data changes for auto-refresh
        $screen = $this
        $this.Store.OnTasksChanged = {
            $screen.LoadData()
            $screen.RequestRender()
        }.GetNewClosure()
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tasks", "Blocked"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Up/Down", "Select")
        $this.Footer.AddShortcut("E", "Edit")
        $this.Footer.AddShortcut("Tab", "Next Field")
        $this.Footer.AddShortcut("D", "Toggle")
        $this.Footer.AddShortcut("Esc", "Cancel")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")

        # Don't create panel here - will be created in LoadData after we know content size

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    [void] LoadData() {
        $this.ShowStatus("Loading blocked tasks...")

        try {
            # Use TaskStore instead of Get-PmcAllData
            $allTasks = $this.Store.GetAllTasks()

            # Filter blocked/waiting tasks
            $this.BlockedTasks = @($allTasks | Where-Object {
                $_.status -eq 'blocked' -or $_.status -eq 'waiting'
            })

            # Reset selection
            $this.SelectedIndex = 0

            # Update status
            if ($this.BlockedTasks.Count -eq 0) {
                $this.ShowSuccess("No blocked tasks")
            } else {
                $this.ShowStatus("$($this.BlockedTasks.Count) blocked/waiting tasks")
            }

        } catch {
            $this.ShowError("Failed to load blocked tasks: $_")
            $this.BlockedTasks = @()
        }
    }

    [string] RenderContent() {
        if ($this.BlockedTasks.Count -eq 0) {
            return $this._RenderEmptyState()
        }

        return $this._RenderTaskList()
    }

    hidden [string] _RenderEmptyState() {
        $sb = [System.Text.StringBuilder]::new(512)

        # Get content area
        if ($this.LayoutManager) {
            $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

            # Center message
            $message = "No blocked tasks"
            $x = $contentRect.X + [Math]::Floor(($contentRect.Width - $message.Length) / 2)
            $y = $contentRect.Y + [Math]::Floor($contentRect.Height / 2)

            $successColor = $this.Header.GetThemedFg('Foreground.Success')
            $reset = "`e[0m"

            $sb.Append($this.Header.BuildMoveTo($x, $y))
            $sb.Append($successColor)
            $sb.Append($message)
            $sb.Append($reset)
        }

        $result = $sb.ToString()
        
        return $result
    }

    hidden [string] _RenderTaskList() {
        $sb = [System.Text.StringBuilder]::new(2048)

        if (-not $this.LayoutManager) {
            $result = $sb.ToString()

            return $result
        }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors
        $textColor = $this.Header.GetThemedFg('Foreground.Field')
        $blockedColor = $this.Header.GetThemedFg('Foreground.Error')
        $waitingColor = $this.Header.GetThemedAnsi('Warning', $false)
        $selectedBg = $this.Header.GetThemedBg('Background.FieldFocused', 80, 0)
        $selectedFg = $this.Header.GetThemedFg('Foreground.Field')
        $cursorColor = $this.Header.GetThemedFg('Foreground.FieldFocused')
        $priorityColor = $this.Header.GetThemedAnsi('Warning', $false)
        $headerColor = $this.Header.GetThemedFg('Foreground.Muted')
        $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
        $reset = "`e[0m"

        # Column widths
        $priorityWidth = 4   # "P2  "
        $statusWidth = 10    # "(blocked) "
        $textWidth = $contentRect.Width - $priorityWidth - $statusWidth - 10

        # Render column headers
        $headerY = $this.Header.Y + 3
        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $headerY))
        $sb.Append($headerColor)
        $sb.Append("PRI ")
        $sb.Append("STATUS    ")
        $sb.Append("TASK")
        $sb.Append($reset)

        # Render task list
        $startY = $headerY + 2
        $maxLines = $contentRect.Height - 4
        $currentY = $startY

        for ($i = 0; $i -lt $this.BlockedTasks.Count; $i++) {
            if ($currentY -ge ($startY + $maxLines)) { break }
            $task = $this.BlockedTasks[$i]
            $y = $currentY
            $isSelected = ($i -eq $this.SelectedIndex)
            $isEditing = ($i -eq $this.SelectedIndex) -and ($this.InputMode -eq 'edit-field')

            # Cursor
            $sb.Append($this.Header.BuildMoveTo($contentRect.X + 2, $y))
            if ($isSelected -or $isEditing) {
                $sb.Append($cursorColor)
                $cursorChar = $(if ($isEditing) { "E" } else { ">" })
                $sb.Append($cursorChar)
                $sb.Append($reset)
            } else {
                $sb.Append(" ")
            }

            # Task row with columns
            $x = $contentRect.X + 4

            # Priority column
            $sb.Append($this.Header.BuildMoveTo($x, $y))
            if ($isEditing -and $this.EditField -eq 'priority') {
                # Inline edit for priority
                $sb.Append($cursorColor)
                $sb.Append(($this.InputBuffer + "_").PadRight($priorityWidth))
                $sb.Append($reset)
            } elseif ($task.priority -gt 0) {
                $sb.Append($priorityColor)
                $sb.Append("P$($task.priority)".PadRight($priorityWidth))
                $sb.Append($reset)
            } else {
                $sb.Append(" " * $priorityWidth)
            }
            $x += $priorityWidth

            # Status column
            $sb.Append($this.Header.BuildMoveTo($x, $y))
            $statusColor = $(if ($task.status -eq 'blocked') { $blockedColor } else { $waitingColor })
            $sb.Append($statusColor)
            $sb.Append("($($task.status))".PadRight($statusWidth))
            $sb.Append($reset)
            $x += $statusWidth

            # Text column
            $sb.Append($this.Header.BuildMoveTo($x, $y))
            if ($isEditing -and $this.EditField -eq 'text') {
                # Inline edit for text
                $sb.Append($cursorColor)
                $text = $this.InputBuffer + "_"
                if ($text.Length -gt $textWidth) {
                    $text = $text.Substring(0, $textWidth)
                }
                $sb.Append($text)
                $sb.Append($reset)
            } else {
                if ($isSelected) {
                    $sb.Append($selectedBg)
                    $sb.Append($selectedFg)
                } else {
                    $sb.Append($textColor)
                }

                $taskText = $task.text
                if ($taskText.Length -gt $textWidth) {
                    $taskText = $taskText.Substring(0, $textWidth - 3) + "..."
                }
                $sb.Append($taskText)
                $sb.Append($reset)
            }

            $currentY++

            # Render subtasks if present
            if ($task.subtasks -and $task.subtasks.Count -gt 0) {
                foreach ($subtask in $task.subtasks) {
                    if ($currentY -ge ($startY + $maxLines)) { break }

                    $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $currentY))
                    $sb.Append($mutedColor)
                    $sb.Append("  └─ ")
                    $sb.Append($subtask)
                    $sb.Append($reset)
                    $currentY++
                }
            }

            # Render tags if present
            if ($task.tags -and $task.tags.Count -gt 0) {
                if ($currentY -lt ($startY + $maxLines)) {
                    $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $currentY))
                    $sb.Append($mutedColor)
                    $sb.Append("  Tags: ")
                    $sb.Append(($task.tags -join ', '))
                    $sb.Append($reset)
                    $currentY++
                }
            }

            # Render dependencies if present
            if ($task.depends -and $task.depends.Count -gt 0) {
                if ($currentY -lt ($startY + $maxLines)) {
                    $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $currentY))
                    $sb.Append($mutedColor)
                    $sb.Append("  Deps: ")
                    $sb.Append(($task.depends -join ', '))
                    $sb.Append($reset)
                    $currentY++
                }
            }

            # Render notes if present (first line only)
            if ($task.notes -and $task.notes.Count -gt 0) {
                if ($currentY -lt ($startY + $maxLines)) {
                    $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $currentY))
                    $sb.Append($mutedColor)
                    $sb.Append("  Note: ")
                    $noteText = $task.notes[0]
                    if ($noteText.Length -gt ($textWidth - 10)) {
                        $noteText = $noteText.Substring(0, $textWidth - 13) + "..."
                    }
                    $sb.Append($noteText)
                    $sb.Append($reset)
                    $currentY++
                }
            }
        }

        # Show truncation indicator if needed
        if ($this.BlockedTasks.Count -gt $maxLines) {
            $y = $startY + $maxLines
            $remaining = $this.BlockedTasks.Count - $maxLines
            $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y))
            $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
            $sb.Append($mutedColor)
            $sb.Append("... and $remaining more")
            $sb.Append($reset)
        }

        $result = $sb.ToString()
        
        return $result
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # Input mode handling
        if ($this.InputMode) {
            return $this._HandleInputMode($keyInfo)
        }

        # Normal mode handling
        if ($this.BlockedTasks.Count -eq 0) {
            return $false
        }

        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this.SelectedIndex -gt 0) {
                    $this.SelectedIndex--
                    return $true
                }
            }
            'DownArrow' {
                if ($this.SelectedIndex -lt ($this.BlockedTasks.Count - 1)) {
                    $this.SelectedIndex++
                    return $true
                }
            }
        }

        switch ($keyChar) {
            'e' {
                $this._StartEditField()
                return $true
            }
            'd' {
                $this._ToggleStatus()
                return $true
            }
            'r' {
                $this.LoadData()
                return $true
            }
        }

        return $false
    }

    hidden [bool] _HandleInputMode([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'Enter' {
                $this._SubmitInput()
                return $true
            }
            'Escape' {
                $this._CancelInput()
                return $true
            }
            'Tab' {
                if ($this.InputMode -eq 'edit-field') {
                    $this._CycleField()
                    return $true
                }
            }
            'Backspace' {
                if ($this.InputBuffer.Length -gt 0) {
                    $this.InputBuffer = $this.InputBuffer.Substring(0, $this.InputBuffer.Length - 1)
                    return $true
                }
            }
            default {
                # Add character to buffer
                if ($keyInfo.KeyChar -and -not [char]::IsControl($keyInfo.KeyChar)) {
                    $this.InputBuffer += $keyInfo.KeyChar
                    return $true
                }
            }
        }
        return $false
    }

    hidden [void] _StartEditField() {
        if ($this.SelectedIndex -lt 0 -or $this.SelectedIndex -ge $this.BlockedTasks.Count) {
            return
        }

        $task = $this.BlockedTasks[$this.SelectedIndex]

        # NULL GUARD: Validate task exists and has required properties
        if ($null -eq $task -or -not $task.id) {
            $this.ShowError("Invalid task selected")
            return
        }

        $this.InputMode = "edit-field"
        $this.EditFieldIndex = 0
        $this.EditField = $this.EditableFields[$this.EditFieldIndex]

        # Pre-fill with current value
        $currentValue = $task.($this.EditField)
        if ($currentValue) {
            $this.InputBuffer = [string]$currentValue
        } else {
            $this.InputBuffer = ""
        }

        $this.ShowStatus("Editing task #$($task.id) - Press Tab to cycle fields")
    }

    hidden [void] _SubmitInput() {
        try {
            if ($this.InputMode -eq 'edit-field') {
                # Update current field value
                $this._UpdateField($this.EditField, $this.InputBuffer)
                # Exit edit mode
                $this.InputMode = ""
                $this.InputBuffer = ""
                $this.EditField = ""
                $this.EditFieldIndex = 0
            }
        } catch {
            $this.ShowError("Operation failed: $_")
            $this.InputMode = ""
            $this.InputBuffer = ""
            $this.EditField = ""
            $this.EditFieldIndex = 0
        }
    }

    hidden [void] _CancelInput() {
        $this.InputMode = ""
        $this.InputBuffer = ""
        $this.EditField = ""
        $this.EditFieldIndex = 0
        $this.ShowStatus("Cancelled")
    }

    hidden [void] _CycleField() {
        if ($this.InputMode -eq 'edit-field') {
            if ($this.SelectedIndex -lt 0 -or $this.SelectedIndex -ge $this.BlockedTasks.Count) {
                return
            }

            $task = $this.BlockedTasks[$this.SelectedIndex]

            # Save current field value before switching
            try {
                if ($this.InputBuffer) {
                    $this._UpdateField($this.EditField, $this.InputBuffer)
                }
            } catch {
                # If update fails, show error but continue to next field
                $this.ShowError("Invalid value for $($this.EditField): $_")
            }

            # Move to next field
            $this.EditFieldIndex = ($this.EditFieldIndex + 1) % $this.EditableFields.Count
            $this.EditField = $this.EditableFields[$this.EditFieldIndex]

            # Load new field value
            $currentValue = $task.($this.EditField)
            if ($currentValue) {
                $this.InputBuffer = [string]$currentValue
            } else {
                $this.InputBuffer = ""
            }

            $this.ShowStatus("Now editing: $($this.EditField) - Press Tab for next field, Enter to finish")
        }
    }

    hidden [void] _UpdateField([string]$field, [string]$value) {
        if ($this.SelectedIndex -lt 0 -or $this.SelectedIndex -ge $this.BlockedTasks.Count) {
            return
        }

        $task = $this.BlockedTasks[$this.SelectedIndex]

        # NULL GUARD: Validate task exists and has required properties
        if ($null -eq $task -or -not $task.id) {
            $this.ShowError("Invalid task selected")
            return
        }

        try {
            # Use existing FieldSchema to normalize and validate
            $schema = Get-PmcFieldSchema -Domain 'task' -Field $field

            if (-not $schema) {
                $this.ShowError("Unknown field: $field")
                return
            }

            # Normalize the value using existing schema logic
            $normalizedValue = $value
            if ($schema.Normalize) {
                $normalizedValue = & $schema.Normalize $value
            }

            # Validate using existing schema logic
            if ($schema.Validate) {
                $isValid = & $schema.Validate $normalizedValue
                if (-not $isValid) {
                    $this.ShowError("Invalid value for $field")
                    return
                }
            }

            # Update via TaskStore (auto-persists and fires events)
            $changes = @{ $field = $normalizedValue }
            $success = $this.Store.UpdateTask($task.id, $changes)

            if (-not $success) {
                $this.ShowError("Failed to update task: $($this.Store.LastError)")
                return
            }

            # Update in-memory task for immediate UI update
            $task.$field = $normalizedValue

            # Show formatted value in success message
            $displayValue = $normalizedValue
            if ($schema.DisplayFormat) {
                $displayValue = & $schema.DisplayFormat $normalizedValue
            }

            $this.ShowSuccess("Task #$($task.id) $field = $displayValue")

        } catch {
            $this.ShowError("Error updating $field`: $_")
        }
    }

    hidden [void] _ToggleStatus() {
        if ($this.SelectedIndex -ge 0 -and $this.SelectedIndex -lt $this.BlockedTasks.Count) {
            $task = $this.BlockedTasks[$this.SelectedIndex]

            # NULL GUARD: Validate task exists and has required properties
            if ($null -eq $task -or -not $task.id) {
                $this.ShowError("Invalid task selected")
                return
            }

            # Toggle between blocked and waiting
            $newStatus = $(if ($task.status -eq 'blocked') { 'waiting' } else { 'blocked' })

            # Update via TaskStore (auto-persists and fires events)
            $success = $this.Store.UpdateTask($task.id, @{ status = $newStatus })

            if ($success) {
                # Update in-memory task for immediate UI update
                $task.status = $newStatus
                $this.ShowSuccess("Changed to $newStatus")
            } else {
                $this.ShowError("Failed to update status: $($this.Store.LastError)")
            }
        }
    }
}

# Entry point function for compatibility
function Show-BlockedTasksScreen {
    param([PmcApplication]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object BlockedTasksScreen
    $App.PushScreen($screen)
}