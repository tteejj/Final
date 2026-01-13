# Universal Display System - Command routing for unified grid interface
# Replaces all fragmented Show-Pmc* functions with grid-based equivalents

Set-StrictMode -Version Latest

# Main universal data display dispatcher
function Show-PmcData {
    param(
        [string]$DataType,              # "tasks", "projects", "timelog", "stats"
        [hashtable]$Filters = @{},      # Data filters
        [hashtable]$Columns = @{},      # Column configuration
        [string]$Title = "",            # Display title
        [hashtable]$Theme = @{},        # Theme overrides
        [switch]$Interactive,           # Start interactive mode (overridden by -i flag in Context)
        [PmcCommandContext]$Context = $null  # PMC command context
    )

    Write-PmcDebug -Level 2 -Category "UniversalDisplay" -Message "Universal data display" -Data @{
        DataType = $DataType
        Interactive = $Interactive.IsPresent
        FilterCount = $Filters.Keys.Count
    }

    # Default column configurations for different data types
    if ($Columns.Keys.Count -eq 0) {
        $Columns = Get-PmcDefaultColumns -DataType $DataType
    }

    # Add help navigation callback if this is help data
    $additionalParams = @{}
    if ($DataType -eq "help" -and $Interactive) {
        $additionalParams.OnSelectCallback = {
            param($selectedItem)
            Show-PmcHelpCategory -Category $selectedItem.Category -Context $Context
        }
    }

    # Call the enhanced grid system
    Write-PmcDebug -Level 2 -Category 'UniversalDisplay' -Message 'Show-PmcData calling Show-PmcDataGrid' -Data @{ DataType = $DataType; Interactive = $Interactive.IsPresent }
    # Determine interactive based on explicit param or Context -i flag
    $startInteractive = $Interactive.IsPresent
    try { if (-not $startInteractive -and $Context -and $Context.Args.ContainsKey('interactive') -and $Context.Args['interactive']) { $startInteractive = $true } } catch {}

    Show-PmcDataGrid -Domains @($DataType) -Columns $Columns -Filters $Filters -Title $Title -Theme $Theme -Interactive:$startInteractive @additionalParams
}

function Get-PmcDefaultColumns {
    param([string]$DataType)

    switch ($DataType) {
        "task" {
            return @{
                "id" = @{ Header = "#"; Width = 4; Alignment = "Right"; Editable = $false; Sensitive = $true }
                "text" = @{ Header = "Task"; Width = 40; Alignment = "Left"; Editable = $true }
                "project" = @{ Header = "Project"; Width = 12; Alignment = "Left"; Truncate = $true; Editable = $false; Sensitive = $true }
                "due" = @{ Header = "Due"; Width = 8; Alignment = "Center"; Editable = $true }
                "priority" = @{ Header = "P"; Width = 3; Alignment = "Center"; Editable = $true }
            }
        }
        "help" {
            return @{
                "Category" = @{ Header = "Category"; Width = 25; Alignment = "Left"; Editable = $false }
                "CommandCount" = @{ Header = "Commands"; Width = 10; Alignment = "Right"; Editable = $false }
                "Description" = @{ Header = "Description"; Width = 50; Alignment = "Left"; Editable = $false }
            }
        }
        "project" {
            return @{
                "name" = @{ Header = "Project"; Width = 20; Alignment = "Left" }
                "description" = @{ Header = "Description"; Width = 30; Alignment = "Left"; Truncate = $true }
                "task_count" = @{ Header = "Tasks"; Width = 6; Alignment = "Right" }
                "completion" = @{ Header = "%"; Width = 6; Alignment = "Right" }
            }
        }
        "timelog" {
            return @{
                "date" = @{ Header = "Date"; Width = 10; Alignment = "Center" }
                "project" = @{ Header = "Project"; Width = 15; Alignment = "Left" }
                "duration" = @{ Header = "Duration"; Width = 8; Alignment = "Right" }
                "description" = @{ Header = "Description"; Width = 35; Alignment = "Left"; Truncate = $true }
            }
        }
        default {
            return @{
                "id" = @{ Header = "#"; Width = 6; Alignment = "Right" }
                "name" = @{ Header = "Item"; Width = 30; Alignment = "Left" }
                "value" = @{ Header = "Value"; Width = 20; Alignment = "Left" }
            }
        }
    }
}

# Enhanced task view functions using universal system
function Show-PmcTodayTasksInteractive {
    param([PmcCommandContext]$Context)

    $today = (Get-Date).Date
    $title = "📅 TASKS DUE TODAY - {0}" -f $today.ToString('yyyy-MM-dd')

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
        "due_range" = "today"
    } -Title $title -Interactive -Context $Context
}

function Show-PmcOverdueTasksInteractive {
    param([PmcCommandContext]$Context)

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
        "due_range" = "overdue"
    } -Title "[WARN]️  OVERDUE TASKS" -Interactive -Context $Context
}

function Show-PmcAgendaInteractive {
    param([PmcCommandContext]$Context)

    $today = (Get-Date).Date
    $title = "🗓️ AGENDA - {0}" -f $today.ToString('yyyy-MM-dd')

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
        "due_range" = "overdue_and_today"
    } -Title $title -Interactive -Context $Context
}

function Show-PmcProjectsInteractive {
    param([PmcCommandContext]$Context)

    Show-PmcData -DataType "project" -Filters @{
        "archived" = $false
    } -Title "📊 PROJECTS DASHBOARD" -Interactive -Context $Context
}

# Static list of projects (no screen takeover)
function Get-PmcProjectList {
    param([PmcCommandContext]$Context)
    $filters = @{ archived = $false }

    # Use simple template-based display
    if (Get-Command Show-PmcSimpleData -ErrorAction SilentlyContinue) {
        Show-PmcSimpleData -DataType "project" -Filters $filters
    } else {
        # Fallback to old system
        Show-PmcData -DataType "project" -Filters $filters -Title "Projects" -Context $Context
    }
}

function Show-PmcAllTasksInteractive {
    param([PmcCommandContext]$Context)

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
    } -Title "📋 ALL TASKS" -Interactive -Context $Context
}

# Static list of tasks (pending by default; honors @project when provided)
function Get-PmcTaskList {
    param($Context)

    $filters = @{ status = 'pending' }
    try {
        if ($Context -and $Context.Args -and $Context.Args.ContainsKey('project')) {
            $filters['project'] = [string]$Context.Args['project']
        }
        if ($Context -and $Context.Args -and $Context.Args.ContainsKey('due')) {
            $dv = ([string]$Context.Args['due']).ToLower()
            switch ($dv) {
                'today'   { $filters['due_range'] = 'today' }
                'overdue' { $filters['due_range'] = 'overdue' }
                'upcoming'{ $filters['due_range'] = 'upcoming' }
            }
        }
    } catch {}

    # Use simple template-based display instead of complex TUI
    if (Get-Command Show-PmcSimpleData -ErrorAction SilentlyContinue) {
        Show-PmcSimpleData -DataType "task" -Filters $filters
    } else {
        # Fallback to old system if template system not loaded
        $title = "Tasks"
        if ($filters.ContainsKey('project')) { $title = "Tasks — @" + $filters['project'] }
        Show-PmcData -DataType "task" -Filters $filters -Title $title -Context $Context
    }
}

function Show-PmcTomorrowTasksInteractive {
    param([PmcCommandContext]$Context)

    $tomorrow = (Get-Date).Date.AddDays(1)
    $title = "📅 TASKS DUE TOMORROW - {0}" -f $tomorrow.ToString('yyyy-MM-dd')

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
        "due_range" = "tomorrow"
    } -Title $title -Interactive -Context $Context
}

function Show-PmcUpcomingTasksInteractive {
    param([PmcCommandContext]$Context)

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
        "due_range" = "upcoming"
    } -Title "📆 UPCOMING TASKS (7 days)" -Interactive -Context $Context
}

function Show-PmcBlockedTasksInteractive {
    param([PmcCommandContext]$Context)

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
        "has_dependencies" = $true
    } -Title "🚫 BLOCKED TASKS" -Interactive -Context $Context
}

function Show-PmcTasksWithoutDueDateInteractive {
    param([PmcCommandContext]$Context)

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
        "no_due_date" = $true
    } -Title "📋 TASKS WITHOUT DUE DATE" -Interactive -Context $Context
}

function Show-PmcNextTasksInteractive {
    param([PmcCommandContext]$Context)

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
        "next_actions" = $true
    } -Title "⏭️ NEXT ACTIONS" -Interactive -Context $Context
}

function Show-PmcWeekTasksInteractive {
    param([PmcCommandContext]$Context)

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
        "due_range" = "week"
    } -Title "📅 THIS WEEK'S TASKS" -Interactive -Context $Context
}

function Show-PmcMonthTasksInteractive {
    param([PmcCommandContext]$Context)

    Show-PmcData -DataType "task" -Filters @{
        "status" = "pending"
        "due_range" = "month"
    } -Title "📅 THIS MONTH'S TASKS" -Interactive -Context $Context
}

# Command shortcuts that route to unified display system
function Get-PmcUniversalCommands {
    return @{
        # Interactive shortcuts (using function names for PMC compatibility)
        "tasks"     = 'Show-PmcAllTasksInteractive'
        "today"     = 'Show-PmcTodayTasksInteractive'
        "overdue"   = 'Show-PmcOverdueTasksInteractive'
        "agenda"    = 'Show-PmcAgendaInteractive'
        "projects"  = 'Show-PmcProjectsInteractive'

        # Enhanced static views (preserve existing functionality)
        "tomorrow"  = 'Show-PmcTomorrowTasks'
        "upcoming"  = 'Show-PmcUpcomingTasks'
        "blocked"   = 'Show-PmcBlockedTasks'
        "noduedate" = 'Show-PmcTasksWithoutDueDate'
        "next"      = 'Show-PmcNextTasks'
        "week"      = 'Show-PmcWeekTasks'
        "month"     = 'Show-PmcMonthTasks'

        # Interactive mode aliases
        "itasks"    = 'Show-PmcAllTasksInteractive'
        "itoday"    = 'Show-PmcTodayTasksInteractive'
        "ioverdue"  = 'Show-PmcOverdueTasksInteractive'
        "iagenda"   = 'Show-PmcAgendaInteractive'
        "iprojects" = 'Show-PmcProjectsInteractive'
    }
}

# Integration with PMC's command system
function Register-PmcUniversalCommands {
    $commands = Get-PmcUniversalCommands

    # Register each command with PMC's shortcut system
    foreach ($cmdName in $commands.Keys) {
        try {
            # Override existing shortcuts in PMC's shortcut map
            if ($Script:PmcShortcutMap.ContainsKey($cmdName)) {
                Write-PmcDebug -Level 1 -Category "UniversalDisplay" -Message "Overriding existing shortcut" -Data @{ Command = $cmdName }
            }

            # Update the global shortcut map to use our interactive functions
            $Script:PmcShortcutMap[$cmdName] = $commands[$cmdName]

            Write-PmcDebug -Level 3 -Category "UniversalDisplay" -Message "Registered universal command" -Data @{ Command = $cmdName }
        } catch {
            Write-PmcDebug -Level 1 -Category "UniversalDisplay" -Message "Failed to register command" -Data @{
                Command = $cmdName
                Error = $_.Exception.Message
            }
        }
    }
}

# Enhanced view functions that preserve existing behavior but add interactive options
function Show-PmcDataWithMode {
    param(
        [string]$ViewName,
        [hashtable]$ViewConfig,
        [PmcCommandContext]$Context,
        [switch]$Interactive
    )

    if ($Interactive) {
        Show-PmcData @ViewConfig -Interactive -Context $Context
    } else {
        # Call original function if it exists
        $originalCommand = "Show-Pmc$ViewName"
        if (Get-Command $originalCommand -ErrorAction SilentlyContinue) {
            & $originalCommand $Context
        } else {
            Show-PmcData @ViewConfig -Context $Context
        }
    }
}

# Theme enhancements for better visual feedback
function Get-PmcUniversalTheme {
    param([string]$ViewType)

    $baseTheme = @{
        Default = @{ Style = "Body" }
        Columns = @{}
        Rows = @{
            Header = @{ Style = "Header" }
            Separator = @{ Style = "Border" }
        }
        Cells = @()
    }

    switch ($ViewType) {
        "today" {
            $baseTheme.Cells += @{
                Column = "due"
                Condition = { param($item) $item.due -eq (Get-Date).ToString('yyyy-MM-dd') }
                Style = @{ Fg = "Yellow"; Bold = $true }
            }
        }
        "overdue" {
            $baseTheme.Cells += @{
                Column = "due"
                Condition = { param($item)
                    if (-not $item.due) { return $false }
                    try {
                        $dueDate = [DateTime]$item.due
                        return $dueDate -lt (Get-Date).Date
                    } catch { return $false }
                }
                Style = @{ Fg = "Red"; Bold = $true }
            }
        }
        "projects" {
            $baseTheme.Cells += @{
                Column = "completion"
                Condition = { param($item)
                    if (-not $item.completion) { return $false }
                    $pct = [int]($item.completion -replace '%', '')
                    return $pct -ge 80
                }
                Style = @{ Fg = "Green"; Bold = $true }
            }
        }
    }

    return $baseTheme
}

# Help category drill-down function
function Show-PmcHelpCategory {
    param(
        [string]$Category,
        [PmcCommandContext]$Context
    )

    Write-PmcDebug -Level 1 -Category 'Help' -Message "Showing help category" -Data @{ Category = $Category }

    # Get help content for this category
    if (-not $Script:PmcHelpContent.ContainsKey($Category)) {
        Write-Host "[WARN]️  Category '$Category' not found in help content" -ForegroundColor Yellow
        return
    }

    $categoryData = $Script:PmcHelpContent[$Category]
    $helpItems = @()
    $id = 1

    # Convert help items to display format
    foreach ($item in $categoryData.Items) {
        $helpItems += [PSCustomObject]@{
            id = $id++
            Type = $item.Type
            Command = $item.Command
            Description = $item.Description
        }
    }

    # Use universal display system for detailed help
    $columns = @{
        "Type" = @{ Header = "Type"; Width = 12; Alignment = "Left"; Editable = $false }
        "Command" = @{ Header = "Command"; Width = 35; Alignment = "Left"; Editable = $false }
        "Description" = @{ Header = "Description"; Width = 50; Alignment = "Left"; Editable = $false }
    }

    $title = "📚 {0} - {1}" -f $Category, $categoryData.Description

    # Display with interactive mode for further navigation
    Show-PmcDataGrid -Data $helpItems -Columns $columns -Title $title -Interactive
}

Export-ModuleMember -Function Get-PmcTaskList, Get-PmcProjectList, Show-PmcData, Show-PmcTodayTasksInteractive, Show-PmcOverdueTasksInteractive, Show-PmcAgendaInteractive, Show-PmcProjectsInteractive, Show-PmcAllTasksInteractive, Show-PmcTomorrowTasksInteractive, Show-PmcUpcomingTasksInteractive, Show-PmcBlockedTasksInteractive, Show-PmcTasksWithoutDueDateInteractive, Show-PmcNextTasksInteractive, Show-PmcWeekTasksInteractive, Show-PmcMonthTasksInteractive, Register-PmcUniversalCommands, Get-PmcUniversalCommands