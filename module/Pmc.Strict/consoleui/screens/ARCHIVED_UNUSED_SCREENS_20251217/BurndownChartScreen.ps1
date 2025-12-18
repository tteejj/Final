using namespace System.Collections.Generic
using namespace System.Text

# BurndownChartScreen - Shows burndown chart with task metrics
# Displays completion metrics and progress bar visualization


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Screen showing burndown chart with task completion metrics

.DESCRIPTION
Shows a burndown chart with:
- Task summary (total, completed, in progress, blocked, todo)
- Completion percentage
- Visual progress bar
- Legend

Can filter by project or show all projects.
This is a read-only chart screen with no task navigation.
#>
class BurndownChartScreen : PmcScreen {
    # Data
    [int]$TotalTasks = 0
    [int]$CompletedTasks = 0
    [int]$InProgressTasks = 0
    [int]$BlockedTasks = 0
    [int]$TodoTasks = 0
    [double]$CompletionPct = 0
    [string]$FilterProject = ""

    # Constructor
    BurndownChartScreen() : base("BurndownChart", "Burndown Chart") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Views", "Burndown"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("F", "Filter")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    # Constructor with container
    BurndownChartScreen([object]$container) : base("BurndownChart", "Burndown Chart", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Views", "Burndown"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("F", "Filter")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    [void] LoadData() {
        $this.ShowStatus("Loading burndown metrics...")

        try {
            # Load PMC data
            $data = Get-PmcData

            # Filter tasks by project if needed
            $projectTasks = $(if ($this.FilterProject) {
                @($data.tasks | Where-Object { ($_.project) -eq $this.FilterProject })
            } else {
                @($data.tasks)
            })

            # Calculate burndown metrics
            $this.TotalTasks = $projectTasks.Count

            # Completed tasks (completed = true or status = 'done'/'completed')
            $this.CompletedTasks = @($projectTasks | Where-Object {
                $taskCompleted = $_.completed
                $taskStatus = $_.status
                $taskCompleted -or $taskStatus -eq 'done' -or $taskStatus -eq 'completed'
            }).Count

            # In progress tasks
            $this.InProgressTasks = @($projectTasks | Where-Object {
                $taskCompleted = $_.completed
                $taskStatus = $_.status
                -not $taskCompleted -and ($taskStatus -eq 'in-progress' -or $taskStatus -eq 'active')
            }).Count

            # Blocked tasks
            $this.BlockedTasks = @($projectTasks | Where-Object {
                $taskCompleted = $_.completed
                $taskStatus = $_.status
                -not $taskCompleted -and $taskStatus -eq 'blocked'
            }).Count

            # Todo tasks (everything else that's not completed)
            $this.TodoTasks = @($projectTasks | Where-Object {
                $taskCompleted = $_.completed
                $taskStatus = $_.status
                -not $taskCompleted -and
                $taskStatus -ne 'in-progress' -and
                $taskStatus -ne 'active' -and
                $taskStatus -ne 'blocked'
            }).Count

            # Calculate completion percentage
            $this.CompletionPct = $(if ($this.TotalTasks -gt 0) {
                [math]::Round(($this.CompletedTasks / $this.TotalTasks) * 100, 1)
            } else {
                0
            })

            # Update status
            $projectText = $(if ($this.FilterProject) { "Project: $($this.FilterProject)" } else { "All Projects" })
            $this.ShowStatus("$projectText - $($this.CompletionPct)% complete")

        } catch {
            $this.ShowError("Failed to load burndown metrics: $_")
            $this.TotalTasks = 0
            $this.CompletedTasks = 0
            $this.InProgressTasks = 0
            $this.BlockedTasks = 0
            $this.TodoTasks = 0
            $this.CompletionPct = 0
        }
    }

    [string] RenderContent() {
        $sb = [System.Text.StringBuilder]::new(2048)

        if (-not $this.LayoutManager) {
            return $sb.ToString()
        }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors
        $textColor = $this.Header.GetThemedFg('Foreground.Field')
        $headerColor = $this.Header.GetThemedAnsi('Accent', $false)
        $completedColor = $this.Header.GetThemedFg('Foreground.Success')
        $inProgressColor = $this.Header.GetThemedAnsi('Warning', $false)
        $blockedColor = $this.Header.GetThemedFg('Foreground.Error')
        $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
        $reset = "`e[0m"

        $y = $this.Header.Y + 4  # Start after header and breadcrumb

        # Project title
        $projectTitle = $(if ($this.FilterProject) { "Project: $($this.FilterProject)" } else { "All Projects" })
        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y++))
        $sb.Append($headerColor)
        $sb.Append($projectTitle)
        $sb.Append($reset)
        $y++

        # Task Summary
        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y++))
        $sb.Append($headerColor)
        $sb.Append("Task Summary:")
        $sb.Append($reset)

        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $y++))
        $sb.Append($textColor)
        $sb.Append("Total Tasks:      $($this.TotalTasks)")
        $sb.Append($reset)

        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $y++))
        $sb.Append($completedColor)
        $sb.Append("Completed:        $($this.CompletedTasks)")
        $sb.Append($reset)

        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $y++))
        $sb.Append($inProgressColor)
        $sb.Append("In Progress:      $($this.InProgressTasks)")
        $sb.Append($reset)

        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $y++))
        $sb.Append($blockedColor)
        $sb.Append("Blocked:          $($this.BlockedTasks)")
        $sb.Append($reset)

        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $y++))
        $sb.Append($textColor)
        $sb.Append("To Do:            $($this.TodoTasks)")
        $sb.Append($reset)
        $y++

        # Completion percentage
        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y++))
        $sb.Append($headerColor)
        $sb.Append("Completion: $($this.CompletionPct)%")
        $sb.Append($reset)
        $y++

        # Draw progress bar
        $barWidth = 50
        $completedWidth = $(if ($this.TotalTasks -gt 0) {
            [math]::Floor(($this.CompletedTasks / $this.TotalTasks) * $barWidth)
        } else {
            0
        })
        $inProgressWidth = $(if ($this.TotalTasks -gt 0) {
            [math]::Floor(($this.InProgressTasks / $this.TotalTasks) * $barWidth)
        } else {
            0
        })
        $remainingWidth = $barWidth - $completedWidth - $inProgressWidth

        $bar = ""
        if ($completedWidth -gt 0) {
            $bar += [string]::new([char]0x2588, $completedWidth)  # █
        }
        if ($inProgressWidth -gt 0) {
            $bar += [string]::new([char]0x2592, $inProgressWidth)  # ▒
        }
        if ($remainingWidth -gt 0) {
            $bar += [string]::new([char]0x2591, $remainingWidth)  # ░
        }

        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y++))
        $sb.Append($textColor)
        $sb.Append("Progress:")
        $sb.Append($reset)

        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y++))
        $sb.Append($textColor)
        $sb.Append("[$bar]")
        $sb.Append($reset)
        $y++

        # Legend
        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y++))
        $sb.Append($headerColor)
        $sb.Append("Legend:")
        $sb.Append($reset)

        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $y++))
        $sb.Append($completedColor)
        $sb.Append([char]0x2588)
        $sb.Append(" Completed")
        $sb.Append($reset)

        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $y++))
        $sb.Append($inProgressColor)
        $sb.Append([char]0x2592)
        $sb.Append(" In Progress")
        $sb.Append($reset)

        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 6, $y++))
        $sb.Append($mutedColor)
        $sb.Append([char]0x2591)
        $sb.Append(" To Do")
        $sb.Append($reset)

        return $sb.ToString()
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # This is a chart screen with no navigation
        # Only handle refresh and filter commands
        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyChar) {
            'r' {
                $this.LoadData()
                return $true
            }
            'f' {
                # Show project list for filtering
                $allData = Get-PmcData
                $projects = $allData.projects | Where-Object { -not ($_.archived) }

                if ($projects.Count -eq 0) {
                    $this.ShowError("No projects available")
                    return $true
                }

                # For now, cycle through projects
                $currentIndex = -1
                for ($i = 0; $i -lt $projects.Count; $i++) {
                    $projectName = $projects[$i].name
                    if ($projectName -eq $this.FilterProject) {
                        $currentIndex = $i
                        break
                    }
                }

                $nextIndex = ($currentIndex + 1) % ($projects.Count + 1)

                if ($nextIndex -eq $projects.Count) {
                    $this.FilterProject = ""
                    $this.ShowStatus("Filter cleared - showing all projects")
                } else {
                    $nextProjectName = $projects[$nextIndex].name
                    $this.FilterProject = $nextProjectName
                    $this.ShowStatus("Filtered to project: $($this.FilterProject)")
                }

                $this.LoadData()
                return $true
            }
        }

        return $false
    }
}

# Entry point function for compatibility
function Show-BurndownChartScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object BurndownChartScreen
    $App.PushScreen($screen)
}