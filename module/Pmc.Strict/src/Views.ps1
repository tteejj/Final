# Views.ps1 - Task view functions updated for current PMC system

function Show-PmcTodayTasks {
    param($Context)

    try {
        $allData = Get-PmcAllData
        $today = (Get-Date).Date

        # Filter tasks due today
        $todayTasks = @($allData.tasks | Where-Object {
            $_.status -eq 'pending' -and $_.due -and
            [datetime]::ParseExact($_.due, 'yyyy-MM-dd', $null).Date -eq $today
        })

        Show-PmcCustomGrid -Domain 'task' -Data $todayTasks -Title "📅 Tasks Due Today" -Interactive

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing today's tasks: $_"
    }
}

function Show-PmcTomorrowTasks {
    param($Context)

    try {
        $allData = Get-PmcAllData
        $tomorrow = (Get-Date).Date.AddDays(1)

        # Filter tasks due tomorrow
        $tomorrowTasks = @($allData.tasks | Where-Object {
            $_.status -eq 'pending' -and $_.due -and
            [datetime]::ParseExact($_.due, 'yyyy-MM-dd', $null).Date -eq $tomorrow
        })

        Show-PmcCustomGrid -Domain 'task' -Data $tomorrowTasks -Title "📅 Tasks Due Tomorrow" -Interactive

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing tomorrow's tasks: $_"
    }
}

function Show-PmcOverdueTasks {
    param($Context)

    try {
        $allData = Get-PmcAllData
        $today = (Get-Date).Date

        # Filter overdue tasks
        $overdueTasks = @($allData.tasks | Where-Object {
            $_.status -eq 'pending' -and $_.due -and
            [datetime]::ParseExact($_.due, 'yyyy-MM-dd', $null).Date -lt $today
        })

        Show-PmcCustomGrid -Domain 'task' -Data $overdueTasks -Title "[WARN]️ Overdue Tasks" -Interactive

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing overdue tasks: $_"
    }
}

function Show-PmcUpcomingTasks {
    param($Context)

    try {
        $allData = Get-PmcAllData
        $today = (Get-Date).Date
        $nextWeek = $today.AddDays(7)

        # Filter upcoming tasks (next 7 days)
        $upcomingTasks = @($allData.tasks | Where-Object {
            $_.status -eq 'pending' -and $_.due -and {
                $dueDate = [datetime]::ParseExact($_.due, 'yyyy-MM-dd', $null).Date
                $dueDate -gt $today -and $dueDate -le $nextWeek
            }
        })

        Show-PmcCustomGrid -Domain 'task' -Data $upcomingTasks -Title "📆 Upcoming Tasks (Next 7 Days)" -Interactive

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing upcoming tasks: $_"
    }
}

function Show-PmcBlockedTasks {
    param($Context)

    try {
        $allData = Get-PmcAllData

        # Filter blocked tasks (tasks with dependencies)
        $blockedTasks = @($allData.tasks | Where-Object {
            $_.status -eq 'pending' -and $_.depends -and $_.depends.Count -gt 0
        })

        Show-PmcCustomGrid -Domain 'task' -Data $blockedTasks -Title "🚫 Blocked Tasks" -Interactive

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing blocked tasks: $_"
    }
}

function Show-PmcNoDueDateTasks {
    param($Context)

    try {
        $allData = Get-PmcAllData

        # Filter tasks with no due date
        $noDueTasks = @($allData.tasks | Where-Object {
            $_.status -eq 'pending' -and (-not $_.due -or $_.due -eq '')
        })

        Show-PmcCustomGrid -Domain 'task' -Data $noDueTasks -Title "📋 Tasks Without Due Date" -Interactive

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing tasks without due date: $_"
    }
}

function Show-PmcWeekTasksInteractive {
    param($Context)

    try {
        $allData = Get-PmcAllData
        $today = (Get-Date).Date
        $endOfWeek = $today.AddDays(6)

        # Filter tasks for this week
        $weekTasks = @($allData.tasks | Where-Object {
            $_.status -eq 'pending' -and $_.due -and {
                $dueDate = [datetime]::ParseExact($_.due, 'yyyy-MM-dd', $null).Date
                $dueDate -ge $today -and $dueDate -le $endOfWeek
            }
        })

        Show-PmcCustomGrid -Domain 'task' -Data $weekTasks -Title "📆 This Week's Tasks" -Interactive

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing week's tasks: $_"
    }
}

function Show-PmcMonthTasksInteractive {
    param($Context)

    try {
        $allData = Get-PmcAllData
        $today = (Get-Date).Date
        $endOfMonth = $today.AddDays(29)

        # Filter tasks for this month
        $monthTasks = @($allData.tasks | Where-Object {
            $_.status -eq 'pending' -and $_.due -and {
                $dueDate = [datetime]::ParseExact($_.due, 'yyyy-MM-dd', $null).Date
                $dueDate -ge $today -and $dueDate -le $endOfMonth
            }
        })

        Show-PmcCustomGrid -Domain 'task' -Data $monthTasks -Title "📅 This Month's Tasks" -Interactive

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing month's tasks: $_"
    }
}

function Show-PmcProjectList {
    param($Context)

    try {
        $allData = Get-PmcAllData
        $projects = $allData.projects | Where-Object { -not $_.isArchived }

        Show-PmcCustomGrid -Domain 'project' -Data $projects -Title "📁 Active Projects" -Interactive

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing projects: $_"
    }
}

function Show-PmcNextActions {
    param($Context)

    try {
        $allData = Get-PmcAllData

        # Get high priority pending tasks
        $nextActions = @($allData.tasks | Where-Object {
            $_.status -eq 'pending' -and $_.priority -gt 0
        } | Sort-Object priority -Descending | Select-Object -First 10)

        Show-PmcCustomGrid -Domain 'task' -Data $nextActions -Title "⭐ Next Actions (Top 10)" -Interactive

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing next actions: $_"
    }
}

# Add Interactive aliases for CommandMap compatibility
function Show-PmcTodayTasksInteractive { param($Context); Show-PmcTodayTasks -Context $Context }
function Show-PmcTomorrowTasksInteractive { param($Context); Show-PmcTomorrowTasks -Context $Context }
function Show-PmcOverdueTasksInteractive { param($Context); Show-PmcOverdueTasks -Context $Context }
function Show-PmcUpcomingTasksInteractive { param($Context); Show-PmcUpcomingTasks -Context $Context }
function Show-PmcBlockedTasksInteractive { param($Context); Show-PmcBlockedTasks -Context $Context }
function Show-PmcTasksWithoutDueDateInteractive { param($Context); Show-PmcNoDueDateTasks -Context $Context }
function Show-PmcProjectsInteractive { param($Context); Show-PmcProjectList -Context $Context }
function Show-PmcNextTasksInteractive { param($Context); Show-PmcNextActions -Context $Context }

# Direct aliases for CommandMap compatibility
function Show-PmcTasksWithoutDueDate { param($Context); Show-PmcNoDueDateTasks -Context $Context }

function Show-PmcKanban {
    param($Context)

    try {
        $allData = Get-PmcAllData

        # Group tasks by status into columns
        $todoTasks = @($allData.tasks | Where-Object { $_.status -eq 'pending' -and (-not $_.due -or (Get-Date $_.due) -gt (Get-Date)) })
        $doingTasks = @($allData.tasks | Where-Object { $_.status -eq 'active' })
        $doneTasks = @($allData.tasks | Where-Object { $_.status -eq 'completed' } | Select-Object -First 10)

        Write-PmcStyled -Style 'Header' -Text "`n🗂️  PMC Kanban Board`n"

        # Display columns side by side
        Write-PmcStyled -Style 'Subheader' -Text "📝 TODO ($($todoTasks.Count))"
        Write-PmcStyled -Style 'Info' -Text "────────────────────"
        foreach ($task in $todoTasks) {
            $priority = $(if ($task.priority -gt 0) { "⭐" } else { "  " })
            $due = $(if ($task.due) { " 📅$($task.due)" } else { "" })
            Write-PmcStyled -Style 'Task' -Text "$priority $($task.title)$due"
        }

        Write-PmcStyled -Style 'Subheader' -Text "`n🔄 DOING ($($doingTasks.Count))"
        Write-PmcStyled -Style 'Info' -Text "────────────────────"
        foreach ($task in $doingTasks) {
            $priority = $(if ($task.priority -gt 0) { "⭐" } else { "  " })
            Write-PmcStyled -Style 'ActiveTask' -Text "$priority $($task.title)"
        }

        Write-PmcStyled -Style 'Subheader' -Text "`n✅ DONE ($($doneTasks.Count))"
        Write-PmcStyled -Style 'Info' -Text "────────────────────"
        foreach ($task in $doneTasks) {
            Write-PmcStyled -Style 'CompletedTask' -Text "   $($task.title)"
        }

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error showing Kanban board: $_"
    }
}

# Export view functions
Export-ModuleMember -Function Show-PmcTodayTasks, Show-PmcTomorrowTasks, Show-PmcOverdueTasks, Show-PmcUpcomingTasks, Show-PmcBlockedTasks, Show-PmcNoDueDateTasks, Show-PmcWeekTasksInteractive, Show-PmcMonthTasksInteractive, Show-PmcProjectList, Show-PmcNextActions, Show-PmcTodayTasksInteractive, Show-PmcTomorrowTasksInteractive, Show-PmcOverdueTasksInteractive, Show-PmcUpcomingTasksInteractive, Show-PmcBlockedTasksInteractive, Show-PmcTasksWithoutDueDateInteractive, Show-PmcProjectsInteractive, Show-PmcNextTasksInteractive, Show-PmcTasksWithoutDueDate, Show-PmcKanban