# Tasks.ps1 - Core task management functions

function Add-PmcTask {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Error' -Text "Usage: task add <description>"
        return
    }

    $taskText = ($Context.FreeText -join ' ').Trim()

    try {
        $allData = Get-PmcAllData

        # Create new task
        $newTask = @{
            id = Get-PmcNextTaskId $allData
            text = $taskText
            project = $allData.currentContext
            priority = 0
            completed = $false
            created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            status = 'pending'
            tags = @()
            depends = @()
            notes = @()
            subtasks = @()
            recur = $null
            estimatedMinutes = $null
            due = $null
            nextSuggestedCount = 3
            lastNextShown = (Get-Date).ToString('yyyy-MM-dd')
        }

        # Add to tasks
        if (-not $allData.tasks) { $allData.tasks = @() }
        $allData.tasks += $newTask

        # Save data
        Set-PmcAllData $allData

        Write-PmcStyled -Style 'Success' -Text "[OK] Task added: $taskText"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error adding task: $_"
    }
}

function Add-PmcSubtask {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -lt 2) {
        Write-PmcStyled -Style 'Error' -Text "Usage: subtask add <taskid> <description>"
        return
    }

    $taskId = $Context.FreeText[0]
    $subtaskText = ($Context.FreeText | Select-Object -Skip 1) -join ' '

    try {
        $allData = Get-PmcAllData
        $task = $allData.tasks | Where-Object { $_.id -eq $taskId }

        if (-not $task) {
            Write-PmcStyled -Style 'Error' -Text "Task #$taskId not found"
            return
        }

        # Ensure subtasks array exists
        if (-not $task.subtasks) {
            $task.subtasks = @()
        }

        # Add subtask as simple string
        $task.subtasks += $subtaskText

        Set-PmcAllData $allData
        Write-PmcStyled -Style 'Success' -Text "[OK] Subtask added to task #${taskId}: $subtaskText"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error adding subtask: $_"
    }
}

function Get-PmcTaskListOld {
    param([PmcCommandContext]$Context)

    try {
        $allData = Get-PmcAllData
        $tasks = $allData.tasks | Where-Object { -not $_.completed }

        # Apply project filter if specified
        Write-Host "DEBUG TASK LIST: Context.Args = $($Context.Args | ConvertTo-Json -Compress)"
        Write-Host "DEBUG TASK LIST: Context.Args type = $($Context.Args.GetType().Name)"
        Write-Host "DEBUG TASK LIST: ContainsKey check = $($Context.Args.ContainsKey('project'))"

        if ($Context.Args -and $Context.Args.ContainsKey('project')) {
            $projectFilter = $Context.Args['project']
            Write-Host "DEBUG: Filtering tasks by project '$projectFilter'"
            $originalCount = $tasks.Count
            $tasks = $tasks | Where-Object { $_.project -eq $projectFilter }
            Write-Host "DEBUG: Filtered from $originalCount to $($tasks.Count) tasks"
        } else {
            Write-Host "DEBUG: No project filter applied"
        }

        if (-not $tasks) {
            $filterMsg = $(if ($Context.Args -and $Context.Args.ContainsKey('project')) { " for project '$($Context.Args['project'])'" } else { "" })
            Write-PmcStyled -Style 'Info' -Text "No active tasks found$filterMsg"
            return
        }

        # Use universal display
        $title = $(if ($Context.Args -and $Context.Args.ContainsKey('project')) { "Active Tasks — @$($Context.Args['project'])" } else { "Active Tasks" })
        Show-PmcCustomGrid -Domain 'task' -Data $tasks -Title $title

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error listing tasks: $_"
    }
}

function Complete-PmcTask {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Error' -Text "Usage: task done <id>"
        return
    }

    $taskId = $Context.FreeText[0]

    try {
        $allData = Get-PmcAllData
        $task = $allData.tasks | Where-Object { $_.id -eq $taskId }

        if (-not $task) {
            Write-PmcStyled -Style 'Error' -Text "Task '$taskId' not found"
            return
        }

        $task.completed = $true
        $task.status = 'completed'

        Set-PmcAllData $allData
        Write-PmcStyled -Style 'Success' -Text "[OK] Task completed: $($task.text)"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error completing task: $_"
    }
}

function Remove-PmcTask {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Error' -Text "Usage: task delete <id>"
        return
    }

    $taskId = $Context.FreeText[0]

    try {
        $allData = Get-PmcAllData
        $task = $allData.tasks | Where-Object { $_.id -eq $taskId }

        if (-not $task) {
            Write-PmcStyled -Style 'Error' -Text "Task '$taskId' not found"
            return
        }

        # Move to deleted
        if (-not $allData.deleted) { $allData.deleted = @() }
        $allData.deleted += $task

        # Remove from tasks
        $allData.tasks = $allData.tasks | Where-Object { $_.id -ne $taskId }

        Set-PmcAllData $allData
        Write-PmcStyled -Style 'Success' -Text "[OK] Task deleted: $($task.text)"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error deleting task: $_"
    }
}

function Show-PmcTask {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Error' -Text "Usage: task view <id>"
        return
    }

    $taskId = $Context.FreeText[0]

    try {
        $allData = Get-PmcAllData
        $task = $allData.tasks | Where-Object { $_.id -eq $taskId }

        if (-not $task) {
            Write-PmcStyled -Style 'Error' -Text "Task '$taskId' not found"
            return
        }

        Write-PmcStyled -Style 'Header' -Text "`nTask: $($task.text)"
        Write-PmcStyled -Style 'Body' -Text "ID: $($task.id)"
        Write-PmcStyled -Style 'Body' -Text "Project: $($task.project)"
        Write-PmcStyled -Style 'Body' -Text "Priority: $($task.priority)"
        Write-PmcStyled -Style 'Body' -Text "Status: $($task.status)"
        Write-PmcStyled -Style 'Body' -Text "Created: $($task.created)"
        if ($task.due) { Write-PmcStyled -Style 'Body' -Text "Due: $($task.due)" }

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error viewing task: $_"
    }
}

function Set-PmcTask {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -lt 3) {
        Write-PmcStyled -Style 'Error' -Text "Usage: task update <id> <field> <value>"
        return
    }

    $taskId = $Context.FreeText[0]
    $field = $Context.FreeText[1]
    $value = ($Context.FreeText[2..($Context.FreeText.Count-1)] -join ' ')

    try {
        $allData = Get-PmcAllData
        $task = $allData.tasks | Where-Object { $_.id -eq $taskId }

        if (-not $task) {
            Write-PmcStyled -Style 'Error' -Text "Task '$taskId' not found"
            return
        }

        switch ($field.ToLower()) {
            'text' { $task.text = $value }
            'priority' { $task.priority = [int]$value }
            'project' { $task.project = $value }
            'due' { $task.due = $value }
            default {
                Write-PmcStyled -Style 'Error' -Text "Unknown field '$field'. Available: text, priority, project, due"
                return
            }
        }

        Set-PmcAllData $allData
        Write-PmcStyled -Style 'Success' -Text "[OK] Task updated"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error updating task: $_"
    }
}

# Export all task functions
Export-ModuleMember -Function Add-PmcTask, Complete-PmcTask, Remove-PmcTask, Show-PmcTask, Set-PmcTask