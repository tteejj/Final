# Focus/Context System Implementation
# Based on t2.ps1 focus functionality

# State-only: no global context initialization

function Set-PmcFocus {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Focus" -Message "Starting focus set" -Data @{ FreeText = $Context.FreeText }

    $data = Get-PmcDataAlias
    $focusText = ($Context.FreeText -join ' ').Trim()

    if ([string]::IsNullOrWhiteSpace($focusText)) {
        Write-PmcStyled -Style 'Warning' -Text "Usage: focus set <project-name>"
        return
    }

    # Find matching project
    $project = $data.projects | Where-Object { $_.name -and ($_.name.ToLower() -eq $focusText.ToLower()) } | Select-Object -First 1

    if (-not $project) {
        Write-PmcStyled -Style 'Warning' -Text ("Project '{0}' not found. Creating new project context." -f $focusText)
        # Auto-create project if it doesn't exist
        $project = [pscustomobject]@{
            name = $focusText
            description = "Auto-created via focus $(Get-Date -Format yyyy-MM-dd)"
            created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
        $data.projects += $project
    }

    # Persist context in data
    if (-not $data.PSObject.Properties['currentContext']) {
        $data | Add-Member -NotePropertyName currentContext -NotePropertyValue $project.name -Force
    } else {
        $data.currentContext = $project.name
    }

    # Mirror to centralized state
    Set-PmcState -Section 'Focus' -Key 'Current' -Value $project.name

    Save-StrictData $data 'focus set'

    Write-PmcStyled -Style 'Success' -Text ("🎯 Focus set to: '{0}'" -f $project.name)

    # Show context summary
    $contextTasks = @($data.tasks | Where-Object {
        $_ -ne $null -and (Pmc-HasProp $_ 'project') -and $_.project -eq $project.name -and (Pmc-HasProp $_ 'status') -and $_.status -eq 'pending'
    })

    Write-PmcStyled -Style 'Info' -Text ("   Pending tasks: {0}" -f $contextTasks.Count)

    if ($contextTasks.Count -gt 0) {
        $overdue = @($contextTasks | Where-Object { (Pmc-HasProp $_ 'due') -and $_.due -and ([datetime]$_.due) -lt (Get-Date).Date })
        $today = @($contextTasks | Where-Object { (Pmc-HasProp $_ 'due') -and $_.due -and ([datetime]$_.due) -eq (Get-Date).Date })

        if ($overdue.Count -gt 0) { Write-PmcStyled -Style 'Error' -Text ("   [WARN]️  Overdue: {0}" -f $overdue.Count) }
        if ($today.Count -gt 0)   { Write-PmcStyled -Style 'Warning' -Text ("   📅 Due today: {0}" -f $today.Count) }
    }

    Write-PmcDebug -Level 2 -Category "Focus" -Message "Focus set successfully" -Data @{ Project = $project.name; PendingTasks = $contextTasks.Count }
}

function Clear-PmcFocus {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Focus" -Message "Starting focus clear"

    $data = Get-PmcDataAlias

    # Clear persisted context
    if ($data.PSObject.Properties['currentContext']) {
        $data.currentContext = 'inbox'
    }

    # Mirror to centralized state
    Set-PmcState -Section 'Focus' -Key 'Current' -Value 'inbox'

    Save-StrictData $data 'focus clear'

    Write-PmcStyled -Style 'Success' -Text "🎯 Project focus cleared. Back to inbox."

    Write-PmcDebug -Level 2 -Category "Focus" -Message "Focus cleared successfully"
}

function Get-PmcFocusStatus {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Focus" -Message "Starting focus status"

    $data = Get-PmcDataAlias

    Write-PmcStyled -Style 'Info' -Text "`nℹ️  CURRENT CONTEXT"
    Write-PmcStyled -Style 'Border' -Text "─────────────────────"

    # Resolve context via helper (handles uninitialized global state)
    $currentContext = Get-PmcCurrentContext

    if (-not $currentContext -or $currentContext -eq 'inbox') {
        Write-PmcStyled -Style 'Muted' -Text "  No active focus (inbox mode)"

        # Show inbox summary
    $inboxTasks = @($data.tasks | Where-Object {
            $_ -ne $null -and ((-not (Pmc-HasProp $_ 'project')) -or $_.project -eq 'inbox') -and (Pmc-HasProp $_ 'status') -and $_.status -eq 'pending'
        })
        Write-PmcStyled -Style 'Body' -Text ("  Inbox tasks: {0}" -f $inboxTasks.Count)
        return
    }

    Write-PmcStyled -Style 'Warning' -Text ("  Active Focus: {0}" -f $currentContext)

    # Find the project
    $project = $data.projects | Where-Object { $_.name -eq $currentContext } | Select-Object -First 1

    if ($project) {
        $desc = $(if ((Pmc-HasProp $project 'description') -and $project.description) { [string]$project.description } else { 'None' })
        Write-PmcStyled -Style 'Muted' -Text ("  Description: {0}" -f $desc)
    }

    # Show context statistics
    $contextTasks = @($data.tasks | Where-Object { (Pmc-HasProp $_ 'project') -and $_.project -eq $currentContext -and (Pmc-HasProp $_ 'status') -and $_.status -eq 'pending' })

    Write-PmcStyled -Style 'Body' -Text ("  Pending Tasks: {0}" -f $contextTasks.Count)

    if ($contextTasks.Count -gt 0) {
        $overdue = @($contextTasks | Where-Object { (Pmc-HasProp $_ 'due') -and $_.due -and [datetime]$_.due -lt (Get-Date).Date })
        $today = @($contextTasks | Where-Object { (Pmc-HasProp $_ 'due') -and $_.due -and ([datetime]$_.due) -eq (Get-Date).Date })
        $upcoming = @($contextTasks | Where-Object { (Pmc-HasProp $_ 'due') -and $_.due -and ([datetime]$_.due) -gt (Get-Date).Date -and ([datetime]$_.due) -le (Get-Date).Date.AddDays(7) })
        $nodue = @($contextTasks | Where-Object { -not (Pmc-HasProp $_ 'due') -or -not $_.due })

        Write-PmcStyled -Style 'Info' -Text "`n  Task Breakdown:"
        if ($overdue.Count -gt 0)  { Write-PmcStyled -Style 'Error'   -Text ("    [WARN]️  Overdue: {0}" -f $overdue.Count) }
        if ($today.Count -gt 0)    { Write-PmcStyled -Style 'Warning' -Text ("    📅 Due today: {0}" -f $today.Count) }
        if ($upcoming.Count -gt 0) { Write-PmcStyled -Style 'Success' -Text ("    📋 Upcoming (7d): {0}" -f $upcoming.Count) }
        if ($nodue.Count -gt 0)    { Write-PmcStyled -Style 'Muted'   -Text ("    📝 No due date: {0}" -f $nodue.Count) }

        # Show blocked tasks in context
        $blocked = @($contextTasks | Where-Object { (Pmc-HasProp $_ 'blocked') -and $_.blocked })
        if ($blocked.Count -gt 0) { Write-PmcStyled -Style 'Error' -Text ("    🔒 Blocked: {0}" -f $blocked.Count) }

        # Show high priority tasks
        $highPriority = @($contextTasks | Where-Object { $_.priority -and $_.priority -le 2 })
        if ($highPriority.Count -gt 0) { Write-PmcStyled -Style 'Highlight' -Text ("    ⭐ High priority: {0}" -f $highPriority.Count) }
    }

    # Show recent activity in context
    $recentLogs = @($data.timelogs | Where-Object {
        $_.project -eq $currentContext -and
        [datetime]$_.date -ge (Get-Date).Date.AddDays(-7)
    })

    if ($recentLogs.Count -gt 0) {
        $totalMinutes = ($recentLogs | Measure-Object minutes -Sum).Sum
        $totalHours = [Math]::Round($totalMinutes / 60, 1)
        Write-PmcStyled -Style 'Info' -Text ("  Recent time (7d): {0} hours" -f $totalHours)
    }

    Write-PmcStyled -Style 'Muted' -Text ("`nTip: Use 'task list @{0}' to see all tasks in this context" -f $currentContext)

    Write-PmcDebug -Level 2 -Category "Focus" -Message "Focus status shown successfully" -Data @{ Context = $currentContext; TaskCount = $contextTasks.Count }
}

# Helper function to get current context
function Get-PmcCurrentContext {
    # State-only source of truth
    $cur = Get-PmcState -Section 'Focus' -Key 'Current'
    if ($null -eq $cur -or [string]::IsNullOrWhiteSpace([string]$cur)) { return 'inbox' }
    return $cur
}

# Helper function to filter tasks by current context
function Get-PmcContextTasks {
    param([switch]$PendingOnly)

    $data = Get-PmcDataAlias
    $context = Get-PmcCurrentContext

    $tasks = $data.tasks

    if ($context -ne 'inbox') {
        $tasks = $tasks | Where-Object { $_.project -eq $context }
    } else {
        $tasks = $tasks | Where-Object { -not $_.project -or $_.project -eq 'inbox' }
    }

    if ($PendingOnly) {
        $tasks = $tasks | Where-Object { $_.status -eq 'pending' }
    }

    return @($tasks)
}

Export-ModuleMember -Function Set-PmcFocus, Clear-PmcFocus, Get-PmcFocusStatus, Get-PmcCurrentContext, Get-PmcContextTasks