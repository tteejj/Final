using namespace System.Collections.Generic
using namespace System.Text

# TimerStartScreen - Start timer for a task
# Shows task list, select task to start timer for


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Timer start screen

.DESCRIPTION
Shows list of active tasks to start timer for.
Supports:
- Navigating task list (Up/Down arrows)
- Starting timer for selected task (Enter key)
- Canceling (Esc key)
#>
class TimerStartScreen : PmcScreen {
    # Data
    [array]$Tasks = @()
    [int]$SelectedIndex = 0
    [object]$TimerStatus = $null

    # Backward compatible constructor
    TimerStartScreen() : base("TimerStart", "Start Timer") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Timer", "Start"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Up/Down", "Select")
        $this.Footer.AddShortcut("Enter", "Start Timer")
        $this.Footer.AddShortcut("Esc", "Cancel")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    # Container constructor
    TimerStartScreen([object]$container) : base("TimerStart", "Start Timer", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Timer", "Start"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Up/Down", "Select")
        $this.Footer.AddShortcut("Enter", "Start Timer")
        $this.Footer.AddShortcut("Esc", "Cancel")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    [void] LoadData() {
        $this.ShowStatus("Loading tasks...")

        try {
            # Get timer status
            try {
                $this.TimerStatus = Get-PmcTimerStatus
            }
            catch {
                $this.TimerStatus = [PSCustomObject]@{
                    Running   = $false
                    StartTime = $null
                    Elapsed   = 0
                    Task      = $null
                    Project   = $null
                }
            }

            # Check if timer is already running
            if ($this.TimerStatus.Running) {
                $this.ShowStatus("Timer already running! Stop it first.")
                $this.Tasks = @()
                return
            }

            # Get PMC data
            $data = Get-PmcData

            # Filter active tasks
            $this.Tasks = @($data.tasks | Where-Object {
                    -not $_.completed -and $_.status -ne 'completed'
                })

            # Sort by priority (descending), then id
            $this.Tasks = @($this.Tasks | Sort-Object -Property @{Expression = { $_.priority }; Descending = $true }, id)

            # Reset selection if out of bounds
            if ($this.SelectedIndex -ge $this.Tasks.Count) {
                $this.SelectedIndex = [Math]::Max(0, $this.Tasks.Count - 1)
            }

            # Update status
            if ($this.Tasks.Count -eq 0) {
                $this.ShowStatus("No active tasks to track")
            }
            else {
                $this.ShowStatus("Select a task to start timer")
            }

        }
        catch {
            $this.ShowError("Failed to load tasks: $_")
            $this.Tasks = @()
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $warningColor = $this.Header.GetThemedColorInt('Foreground.Warning') 
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $successColor = $this.Header.GetThemedColorInt('Foreground.Success')
        $priorityColor = $this.Header.GetThemedColorInt('Foreground.Warning') # Approximate for now
        
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.Field')
        $cursorColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $y = 4
        $x = 4

        # Check if timer is already running
        if ($this.TimerStatus -and $this.TimerStatus.Running) {
            $engine.WriteAt($x, $y, "Timer is already running!", $warningColor, $bg)
            $y += 2

            $engine.WriteAt($x + 2, $y, "Started: $($this.TimerStatus.StartTime)", $textColor, $bg)
            $y++

            $engine.WriteAt($x + 2, $y, "Elapsed: ", $textColor, $bg)
            $engine.WriteAt($x + 11, $y, "$($this.TimerStatus.Elapsed)h", $highlightColor, $bg)
            $y++

            if ($this.TimerStatus.Task) {
                $y++
                $engine.WriteAt($x + 2, $y, "Task: $($this.TimerStatus.Task)", $textColor, $bg)
                $y++
            }

            if ($this.TimerStatus.Project) {
                $engine.WriteAt($x + 2, $y, "Project: $($this.TimerStatus.Project)", $textColor, $bg)
                $y++
            }

            $y += 2
            $engine.WriteAt($x, $y, "Stop the timer first before starting a new one.", $mutedColor, $bg)
            return
        }

        # Show task list if no timer running
        if ($this.Tasks.Count -eq 0) {
            $engine.WriteAt($x, $y, "No active tasks available", $mutedColor, $bg)
            return
        }

        # Title
        $engine.WriteAt($x, $y, "Select a task to start timer:", $successColor, $bg)
        $y += 2

        # Column headers
        $headerY = $y
        $engine.WriteAt($x, $headerY, "PRI ", $mutedColor, $bg)
        $engine.WriteAt($x + 4, $headerY, "ID   ", $mutedColor, $bg)
        $engine.WriteAt($x + 9, $headerY, "TASK", $mutedColor, $bg)
        $y++

        # Render task rows
        $startY = $y
        $maxLines = $this.TermHeight - $startY - 2 # Footer allowance

        for ($i = 0; $i -lt [Math]::Min($this.Tasks.Count, $maxLines); $i++) {
            $task = $this.Tasks[$i]
            $y = $startY + $i
            $isSelected = ($i -eq $this.SelectedIndex)
            
            $rowBg = $(if ($isSelected) { $selectedBg } else { $bg })
            $rowFg = $(if ($isSelected) { $selectedFg } else { $textColor })
            $prioFg = $(if ($isSelected) { $selectedFg } else { $priorityColor })
            $idFg = $(if ($isSelected) { $selectedFg } else { $mutedColor })

            # Cursor
            if ($isSelected) {
                $engine.WriteAt($x - 2, $y, ">", $cursorColor, $bg)
            }

            $currentX = $x

            # Priority column
            if ($task.priority -gt 0) {
                $engine.WriteAt($currentX, $y, "P$($task.priority)".PadRight(4), $prioFg, $rowBg)
            }
            else {
                $engine.WriteAt($currentX, $y, "    ", $rowFg, $rowBg)
            }
            $currentX += 4

            # ID column
            $engine.WriteAt($currentX, $y, "#$($task.id)".PadRight(5), $idFg, $rowBg)
            $currentX += 5

            # Task text
            $textWidth = $this.TermWidth - $currentX - 2
            $taskText = $task.text
            if ($taskText.Length -gt $textWidth) {
                $taskText = $taskText.Substring(0, [Math]::Max(0, $textWidth - 3)) + "..."
            }
            
            $engine.WriteAt($currentX, $y, $taskText, $rowFg, $rowBg)
        }
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # Check if timer is running
        if ($this.TimerStatus -and $this.TimerStatus.Running) {
            # No navigation, just exit
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
                if ($this.SelectedIndex -lt ($this.Tasks.Count - 1)) {
                    $this.SelectedIndex++
                    return $true
                }
            }
            'Enter' {
                $this._StartTimer()
                return $true
            }
        }

        switch ($keyChar) {
            's' {
                $this._StartTimer()
                return $true
            }
        }

        return $false
    }

    hidden [void] _StartTimer() {
        # Check if timer is already running
        if ($this.TimerStatus -and $this.TimerStatus.Running) {
            $this.ShowError("Timer is already running! Stop it first.")
            return
        }

        if ($this.SelectedIndex -lt 0 -or $this.SelectedIndex -ge $this.Tasks.Count) {
            $this.ShowError("No task selected")
            return
        }

        $task = $this.Tasks[$this.SelectedIndex]

        try {
            # Start timer using PMC function
            Start-PmcTimer -TaskId $task.id -Project $task.project

            $this.ShowSuccess("Timer started for task #$($task.id)")

            # Return to previous screen
            $global:PmcApp.PopScreen()
        }
        catch {
            $this.ShowError("Error starting timer: $_")
        }
    }

    hidden [void] _Cancel() {
        $this.ShowStatus("Timer start cancelled")
        $global:PmcApp.PopScreen()
    }
}

# Entry point function for compatibility
function Show-TimerStartScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object TimerStartScreen
    $App.PushScreen($screen)
}