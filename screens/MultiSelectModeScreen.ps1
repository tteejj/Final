using namespace System.Collections.Generic
using namespace System.Text

# MultiSelectModeScreen - Multi-select task operations
# Task list with checkboxes for bulk operations


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Multi-select mode for bulk task operations

.DESCRIPTION
Shows task list with checkboxes for selection.
Supports bulk operations on selected tasks:
- Space to toggle individual selection
- A to select all
- N to clear all selections
- B to bulk complete
- D to bulk delete
- P to change priority for all selected
Shows selected count in footer.
#>
class MultiSelectModeScreen : PmcScreen {
    # Data
    [array]$Tasks = @()
    [int]$SelectedIndex = 0
    [hashtable]$MultiSelect = @{}
    [int]$ScrollOffset = 0

    # Constructor
    MultiSelectModeScreen() : base("MultiSelectMode", "Multi-Select Mode") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tasks", "Multi-Select"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Space", "Toggle")
        $this.Footer.AddShortcut("A", "All")
        $this.Footer.AddShortcut("N", "None")
        $this.Footer.AddShortcut("B", "Bulk Complete")
        $this.Footer.AddShortcut("D", "Bulk Delete")
        $this.Footer.AddShortcut("P", "Set Priority")
        $this.Footer.AddShortcut("Esc", "Exit")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    # Constructor with container
    MultiSelectModeScreen([object]$container) : base("MultiSelectMode", "Multi-Select Mode", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tasks", "Multi-Select"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Space", "Toggle")
        $this.Footer.AddShortcut("A", "All")
        $this.Footer.AddShortcut("N", "None")
        $this.Footer.AddShortcut("B", "Bulk Complete")
        $this.Footer.AddShortcut("D", "Bulk Delete")
        $this.Footer.AddShortcut("P", "Set Priority")
        $this.Footer.AddShortcut("Esc", "Exit")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    [void] LoadData() {
        $this.ShowStatus("Loading tasks...")

        try {
            # Get PMC data
            $data = Get-PmcData

            # Filter active tasks
            $this.Tasks = @($data.tasks | Where-Object {
                -not ($_.completed)
            })

            # Sort by priority (descending), then id
            $this.Tasks = @($this.Tasks | Sort-Object { $_.priority }, { $_.id } -Descending)

            # Reset selection if out of bounds
            if ($this.SelectedIndex -ge $this.Tasks.Count) {
                $this.SelectedIndex = [Math]::Max(0, $this.Tasks.Count - 1)
            }

            # Update status
            $selectedCount = @($this.MultiSelect.Values | Where-Object { $_ }).Count
            $this.ShowStatus("$($this.Tasks.Count) tasks | $selectedCount selected")

        } catch {
            $this.ShowError("Failed to load tasks: $_")
            $this.Tasks = @()
        }
    }

    [string] RenderContent() {
        $sb = [System.Text.StringBuilder]::new(4096)

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
        $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
        $successColor = $this.Header.GetThemedFg('Foreground.Success')
        $priorityColor = $this.Header.GetThemedAnsi('Warning', $false)
        $reset = "`e[0m"

        $y = $contentRect.Y

        # Show selected count
        $selectedCount = @($this.MultiSelect.Values | Where-Object { $_ }).Count
        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y))
        $sb.Append($successColor)
        $sb.Append("$selectedCount selected")
        $sb.Append($reset)
        $y += 2

        # Column headers
        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y))
        $sb.Append($mutedColor)
        $sb.Append("SEL".PadRight(5))
        $sb.Append("ID".PadRight(6))
        $sb.Append("PRI".PadRight(5))
        $sb.Append("TASK")
        $sb.Append($reset)
        $y++

        # Task list
        $maxLines = $contentRect.Height - 5
        for ($i = 0; $i -lt [Math]::Min($this.Tasks.Count, $maxLines); $i++) {
            $taskIdx = $i + $this.ScrollOffset
            if ($taskIdx -ge $this.Tasks.Count) { break }

            $task = $this.Tasks[$taskIdx]
            $taskId = $task.id
            $taskPriority = $task.priority
            $taskText = $task.text
            $isSelected = ($taskIdx -eq $this.SelectedIndex)
            $isMarked = $this.MultiSelect[$taskId]

            # Cursor
            $sb.Append($this.Header.BuildMoveTo($contentRect.X + 2, $y))
            if ($isSelected) {
                $sb.Append($cursorColor)
                $sb.Append(">")
                $sb.Append($reset)
            } else {
                $sb.Append(" ")
            }

            # Task row
            $x = $contentRect.X + 4
            $sb.Append($this.Header.BuildMoveTo($x, $y))

            # Checkbox
            $marker = $(if ($isMarked) { "[X]" } else { "[ ]" })
            if ($isMarked) {
                $sb.Append($successColor)
            } else {
                $sb.Append($mutedColor)
            }
            $sb.Append($marker.PadRight(5))
            $sb.Append($reset)

            # ID
            if ($isSelected) {
                $sb.Append($selectedBg)
                $sb.Append($selectedFg)
            } else {
                $sb.Append($textColor)
            }
            $sb.Append("#$taskId".PadRight(6))

            # Priority
            if ($taskPriority -and $taskPriority -gt 0) {
                if (-not $isSelected) {
                    $sb.Append($reset)
                    $sb.Append($priorityColor)
                }
                $sb.Append("P$taskPriority".PadRight(5))
                if (-not $isSelected) {
                    $sb.Append($reset)
                    $sb.Append($textColor)
                }
            } else {
                $sb.Append("  ".PadRight(5))
            }

            # Task text
            $maxTaskWidth = $contentRect.Width - 25
            $taskTextDisplay = $(if ($taskText) { $taskText } else { "" })
            if ($taskTextDisplay.Length -gt $maxTaskWidth) {
                $taskTextDisplay = $taskTextDisplay.Substring(0, $maxTaskWidth - 3) + "..."
            }
            $sb.Append($taskTextDisplay)

            $sb.Append($reset)
            $y++
        }

        return $sb.ToString()
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this.SelectedIndex -gt 0) {
                    $this.SelectedIndex--
                    if ($this.SelectedIndex -lt $this.ScrollOffset) {
                        $this.ScrollOffset = $this.SelectedIndex
                    }
                    return $true
                }
            }
            'DownArrow' {
                if ($this.SelectedIndex -lt ($this.Tasks.Count - 1)) {
                    $this.SelectedIndex++
                    $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)
                    $maxLines = $contentRect.Height - 5
                    if ($this.SelectedIndex -ge $this.ScrollOffset + $maxLines) {
                        $this.ScrollOffset = $this.SelectedIndex - $maxLines + 1
                    }
                    return $true
                }
            }
            'Spacebar' {
                if ($this.SelectedIndex -lt $this.Tasks.Count) {
                    $task = $this.Tasks[$this.SelectedIndex]
                    $taskId = $task.id
                    $this.MultiSelect[$taskId] = -not $this.MultiSelect[$taskId]
                    $this._UpdateStatus()
                    return $true
                }
            }
        }

        switch ($keyChar) {
            'a' {
                foreach ($task in $this.Tasks) {
                    $taskId = $task.id
                    $this.MultiSelect[$taskId] = $true
                }
                $this._UpdateStatus()
                return $true
            }
            'n' {
                $this.MultiSelect.Clear()
                $this._UpdateStatus()
                return $true
            }
            'b' {
                $this._BulkComplete()
                return $true
            }
            'd' {
                $this._BulkDelete()
                return $true
            }
            'p' {
                $this._BulkSetPriority()
                return $true
            }
        }

        return $false
    }

    hidden [void] _UpdateStatus() {
        $selectedCount = @($this.MultiSelect.Values | Where-Object { $_ }).Count
        $this.ShowStatus("$($this.Tasks.Count) tasks | $selectedCount selected")
    }

    hidden [void] _BulkComplete() {
        $selectedIds = @($this.MultiSelect.Keys | Where-Object { $this.MultiSelect[$_] })
        if ($selectedIds.Count -eq 0) {
            $this.ShowStatus("No tasks selected")
            return
        }

        try {
            $data = Get-PmcData
            $count = 0

            foreach ($id in $selectedIds) {
                $task = $data.tasks | Where-Object { ($_.id) -eq $id } | Select-Object -First 1
                if ($task) {
                    $task.completed = $true
                    $task.completedDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    $count++
                }
            }

            Save-PmcData -Data $data -Action "Bulk completed $count tasks"

            $this.ShowSuccess("Completed $count tasks")
            $this.MultiSelect.Clear()

            # Reload data
            Start-Sleep -Milliseconds 500
            $this.LoadData()

        } catch {
            $this.ShowError("Failed to complete tasks: $_")
        }
    }

    hidden [void] _BulkDelete() {
        $selectedIds = @($this.MultiSelect.Keys | Where-Object { $this.MultiSelect[$_] })
        if ($selectedIds.Count -eq 0) {
            $this.ShowStatus("No tasks selected")
            return
        }

        try {
            $data = Get-PmcData
            $count = $selectedIds.Count

            # Remove selected tasks
            $data.tasks = @($data.tasks | Where-Object { $selectedIds -notcontains ($_.id) })

            Save-PmcData -Data $data -Action "Bulk deleted $count tasks"

            $this.ShowSuccess("Deleted $count tasks")
            $this.MultiSelect.Clear()

            # Reload data
            Start-Sleep -Milliseconds 500
            $this.LoadData()

        } catch {
            $this.ShowError("Failed to delete tasks: $_")
        }
    }

    hidden [void] _BulkSetPriority() {
        $selectedIds = @($this.MultiSelect.Keys | Where-Object { $this.MultiSelect[$_] })
        if ($selectedIds.Count -eq 0) {
            $this.ShowStatus("No tasks selected")
            return
        }

        # Set priority for all selected tasks
        $allData = Get-PmcData
        $updatedCount = 0

        foreach ($taskId in $selectedIds) {
            $task = $allData.tasks | Where-Object { ($_.id) -eq $taskId }
            if ($task) {
                # Cycle priority: 0 -> 1 -> 2 -> 3 -> 0
                $currentPriority = $task.priority
                $task.priority = ($currentPriority + 1) % 4
                $updatedCount++
            }
        }

        if ($updatedCount -gt 0) {
            # FIX: Use Save-PmcData instead of Set-PmcAllData
            Save-PmcData -Data $allData
            $this.ShowSuccess("Updated priority for $updatedCount tasks")
            $this.LoadData()
        }
    }
}

# Entry point function for compatibility
function Show-MultiSelectModeScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object MultiSelectModeScreen
    $App.PushScreen($screen)
}