# Canonical domain -> action -> function map (strict)

$Script:PmcCommandMap = @{
    task = @{
        add     = 'Add-PmcTask'
        list    = 'Get-PmcTaskList'
        view    = 'Show-PmcTask'
        update  = 'Set-PmcTask'
        done    = 'Complete-PmcTask'
        delete  = 'Remove-PmcTask'
        move    = 'Move-PmcTask'
        postpone= 'Set-PmcTaskPostponed'
        duplicate='Copy-PmcTask'
        note    = 'Add-PmcTaskNote'
        edit    = 'Edit-PmcTask'
        search  = 'Find-PmcTask'
        priority= 'Set-PmcTaskPriority'
        agenda  = 'Show-PmcAgenda'
        week    = 'Show-PmcWeekTasksInteractive'
        month   = 'Show-PmcMonthTasksInteractive'
    }
    subtask = @{
        add     = 'Add-PmcSubtask'
    }
    project = @{
        add     = 'Add-PmcProject'
        list    = 'Get-PmcProjectList'
        view    = 'Show-PmcProject'
        update  = 'Set-PmcProject'
        edit    = 'Edit-PmcProject'
        rename  = 'Rename-PmcProject'
        delete  = 'Remove-PmcProject'
        archive = 'Set-PmcProjectArchived'
        'set-fields' = 'Set-PmcProjectFields'
        'show-fields'= 'Show-PmcProjectFields'
        stats   = 'Get-PmcProjectStats'
        info    = 'Show-PmcProjectInfo'
        recent  = 'Get-PmcRecentProjects'
    }
    activity = @{
        list    = 'Get-PmcActivityList'
    }
    time = @{
        log     = 'Add-PmcTimeEntry'
        report  = 'Get-PmcTimeReport'
        list    = 'Get-PmcTimeList'
        edit    = 'Edit-PmcTimeEntry'
        delete  = 'Remove-PmcTimeEntry'
    }
    timer = @{
        start   = 'Start-PmcTimer'
        stop    = 'Stop-PmcTimer'
        status  = 'Get-PmcTimerStatus'
    }
    template = @{
        save    = 'Save-PmcTemplate'
        apply   = 'Invoke-PmcTemplate'
        list    = 'Get-PmcTemplateList'
        remove  = 'Remove-PmcTemplate'
    }
    recurring = @{
        add     = 'Add-PmcRecurringTask'
    }
    alias = @{
        add     = 'Add-PmcAlias'
        remove  = 'Remove-PmcAlias'
    }
    dep = @{
        add     = 'Add-PmcDependency'
        remove  = 'Remove-PmcDependency'
        show    = 'Show-PmcDependencies'
        graph   = 'Show-PmcDependencyGraph'
    }
    focus = @{
        set     = 'Set-PmcFocus'
        clear   = 'Clear-PmcFocus'
        status  = 'Get-PmcFocusStatus'
    }
    system = @{
        undo    = 'Invoke-PmcUndo'
        redo    = 'Invoke-PmcRedo'
        backup  = 'New-PmcBackup'
        clean   = 'Clear-PmcCompletedTasks'
        gui     = 'Start-PmcFakeTUI'
    }
    view = @{
        today     = 'Show-PmcTodayTasksInteractive'
        tomorrow  = 'Show-PmcTomorrowTasksInteractive'
        overdue   = 'Show-PmcOverdueTasksInteractive'
        upcoming  = 'Show-PmcUpcomingTasksInteractive'
        blocked   = 'Show-PmcBlockedTasksInteractive'
        noduedate = 'Show-PmcTasksWithoutDueDateInteractive'
        projects  = 'Show-PmcProjectsInteractive'
        next      = 'Show-PmcNextTasksInteractive'
    }
    excel = @{
        import   = 'Import-PmcExcelData'
        view     = 'Show-PmcExcelPreview'
        latest   = 'Get-PmcLatestExcelFile'
    }
    xflow = @{
        'browse-source' = 'Set-PmcXFlowSourcePathInteractive'
        'browse-dest'   = 'Set-PmcXFlowDestPathInteractive'
        'preview'       = 'Show-PmcXFlowPreview'
        'run'           = 'Invoke-PmcXFlowRun'
        'export'        = 'Export-PmcXFlowText'
        'import-mappings' = 'Import-PmcXFlowMappingsFromFile'
        'set-latest'    = 'Set-PmcXFlowLatestFromFile'
        'config'        = 'Show-PmcXFlowConfig'
    }
    theme = @{
        reset    = 'Reset-PmcTheme'
        adjust   = 'Edit-PmcTheme'
        list     = 'Get-PmcThemeList'
        apply    = 'Apply-PmcTheme'
        info     = 'Show-PmcThemeInfo'
    }
    interactive = @{
        status   = 'Get-PmcInteractiveStatus'
    }
    config = @{
        show    = 'Show-PmcConfig'
        edit    = 'Edit-PmcConfig'
        set     = 'Set-PmcConfigValue'
        reload  = 'Reload-PmcConfig'
        validate= 'Validate-PmcConfig'
        icons   = 'Set-PmcIconMode'
    }
    import = @{
        tasks   = 'Import-PmcTasks'
    }
    export = @{
        tasks   = 'Export-PmcTasks'
    }
    show = @{
        aliases = 'Get-PmcAliasList'
        commands= 'Show-PmcCommands'
    }
    help = @{
        show     = 'Show-PmcSmartHelp'     # Interactive help browser (full takeover)
        domain   = 'Show-PmcHelpDomain'    # Static print of domain actions
        command  = 'Show-PmcHelpCommand'   # Static print of specific command (args/usage)
        query    = 'Show-PmcHelpQuery'     # Static print of query language overview
        guide    = 'Show-PmcHelpGuide'     # Interactive guides for query/kanban
        examples = 'Show-PmcHelpExamples'  # Practical examples
        search   = 'Show-PmcHelpSearch'    # Search across help content and commands
    }
}

# Single-word shortcuts (domain-less commands)
$Script:PmcShortcutMap = @{
    add       = 'Add-PmcTask'
    done      = 'Complete-PmcTask'
    delete    = 'Remove-PmcTask'
    update    = 'Set-PmcTask'
    move      = 'Move-PmcTask'
    postpone  = 'Set-PmcTaskPostponed'
    duplicate = 'Copy-PmcTask'
    note      = 'Add-PmcTaskNote'
    edit      = 'Edit-PmcTask'
    list      = 'Get-PmcTaskList'
    search    = 'Find-PmcTask'
    priority  = 'Set-PmcTaskPriority'
    agenda    = 'Show-PmcAgenda'
    week      = 'Show-PmcWeekTasksInteractive'
    month     = 'Show-PmcMonthTasksInteractive'
    log       = 'Add-PmcTimeEntry'
    report    = 'Get-PmcTimeReport'
    today     = 'Show-PmcTodayTasksInteractive'
    tomorrow  = 'Show-PmcTomorrowTasksInteractive'
    overdue   = 'Show-PmcOverdueTasksInteractive'
    upcoming  = 'Show-PmcUpcomingTasksInteractive'
    blocked   = 'Show-PmcBlockedTasksInteractive'
    noduedate = 'Show-PmcTasksWithoutDueDateInteractive'
    projects  = 'Show-PmcProjectsInteractive'
    # Explicit interactive aliases
    itoday    = 'Show-PmcTodayTasks'
    ioverdue  = 'Show-PmcOverdueTasks'
    iagenda   = 'Show-PmcAgenda'
    iprojects = 'Show-PmcProjectList'
    itasks    = 'Show-PmcTodayTasks'
    undo      = 'Invoke-PmcUndo'
    redo      = 'Invoke-PmcRedo'
    backup    = 'New-PmcBackup'
    clean     = 'Clear-PmcCompletedTasks'
    focus     = 'Set-PmcFocus'
    unfocus   = 'Clear-PmcFocus'
    context   = 'Get-PmcFocusStatus'
    next      = 'Show-PmcNextTasksInteractive'
    stats     = 'Get-PmcStats'
    burndown  = 'Show-PmcBurndown'
    velocity  = 'Get-PmcVelocity'
    theme     = 'Set-PmcTheme'
    prefs     = 'Show-PmcPreferences'
    '#'       = 'Invoke-PmcShortcutNumber'
    alias     = 'Get-PmcAliasList'
    time      = 'Get-PmcTimeList'
    config    = 'Validate-PmcConfig'
    review    = 'Start-PmcReview'
    import    = 'Import-PmcTasks'
    export    = 'Export-PmcTasks'
    tasks     = 'Show-PmcAllTasksInteractive'
    q         = 'Invoke-PmcQuery'
}

# Minimal descriptions for help
$Script:PmcCommandMeta = @{
    'task add'      = @{ Desc='Add a new task' }
    'task list'     = @{ Desc='List tasks' }
    'task done'     = @{ Desc='Complete a task' }
    'project add'   = @{ Desc='Create project' }
    'project list'  = @{ Desc='List projects' }
    'time log'      = @{ Desc='Log time entry' }
    'time report'   = @{ Desc='Show time report' }
    'time list'     = @{ Desc='List time logs' }
    'timer start'   = @{ Desc='Start timer' }
    'timer stop'    = @{ Desc='Stop timer' }
    'timer status'  = @{ Desc='Show timer' }
    'dep add'       = @{ Desc='Add task dependency' }
    'dep remove'    = @{ Desc='Remove task dependency' }
    'dep show'      = @{ Desc='Show task dependencies' }
    'dep graph'     = @{ Desc='Visual dependency graph' }
    'focus set'     = @{ Desc='Set project context' }
    'focus clear'   = @{ Desc='Clear project context' }
    'focus status'  = @{ Desc='Show current context' }
    'system undo'   = @{ Desc='Undo last action' }
    'system redo'   = @{ Desc='Redo last action' }
    'system backup' = @{ Desc='Create data backup' }
    'system clean'  = @{ Desc='Clean completed tasks' }
    'system gui'    = @{ Desc='Launch FakeTUI interface' }
    'view today'    = @{ Desc='Tasks due today' }
    'view tomorrow' = @{ Desc='Tasks due tomorrow' }
    'view overdue'  = @{ Desc='Overdue tasks' }
    'view upcoming' = @{ Desc='Upcoming tasks (7 days)' }
    'view blocked'  = @{ Desc='Tasks blocked by dependencies' }
    'view noduedate'= @{ Desc='Tasks without due dates' }
    'view projects' = @{ Desc='Projects dashboard' }
    'view next'     = @{ Desc='Next actions summary' }
    'excel import'  = @{ Desc='Import tasks from Excel/CSV' }
    'excel view'    = @{ Desc='Preview Excel/CSV import' }
    'excel latest'  = @{ Desc='Show latest Excel/CSV file' }
    'xflow browse-source' = @{ Desc='Choose source Excel file (interactive)' }
    'xflow browse-dest'   = @{ Desc='Choose destination Excel file (interactive)' }
    'xflow preview' = @{ Desc='Preview first mapped fields from source' }
    'xflow run'     = @{ Desc='Run Excel mapping; optional text export' }
    'xflow export'  = @{ Desc='Export last extract to CSV/JSON' }
    'xflow import-mappings' = @{ Desc='Import field mappings from settings.json' }
    'xflow set-latest' = @{ Desc='Set latest extract from JSON file' }
    'xflow config' = @{ Desc='Show current xflow configuration' }
    'theme reset'   = @{ Desc='Reset theme to default' }
    'theme adjust'  = @{ Desc='Adjust theme interactively' }
    'config icons'  = @{ Desc='Set icons: ascii|emoji' }
    'stats'         = @{ Desc='Productivity statistics' }
    'burndown'      = @{ Desc='Burndown overview (7d)' }
    'velocity'      = @{ Desc='Velocity (last 4 weeks)' }
    'prefs'         = @{ Desc='Edit preferences' }
    'alias add'     = @{ Desc='Add user alias' }
    'alias remove'  = @{ Desc='Remove user alias' }
    'show aliases'  = @{ Desc='Show user aliases' }
    'show commands' = @{ Desc='List all commands' }
    'help guide'    = @{ Desc='Guides for query language and kanban' }
    'help examples' = @{ Desc='Examples for queries and kanban flows' }
    'help query'    = @{ Desc='Query language overview' }
    'help search'   = @{ Desc='Search help content and commands' }
    'project stats' = @{ Desc='Project statistics' }
    'project info'  = @{ Desc='Project information' }
    'project recent'= @{ Desc='Recent projects' }
    'import tasks'  = @{ Desc='Import tasks from CSV/JSON' }
    'export tasks'  = @{ Desc='Export tasks to CSV/JSON' }
    'review'        = @{ Desc='Weekly review workflow' }
}

# Ensure Universal Display is available and shortcuts are registered.
function Ensure-PmcUniversalDisplay {
    try {
        $ud = Join-Path $PSScriptRoot 'UniversalDisplay.ps1'
        # Load if core entry not available
        if (-not (Get-Command Show-PmcData -ErrorAction SilentlyContinue)) {
            if (-not (Test-Path $ud)) { throw "UniversalDisplay.ps1 not found at $ud" }
            . $ud
        }
        if (Get-Command Register-PmcUniversalCommands -ErrorAction SilentlyContinue) {
            Register-PmcUniversalCommands
            return $true
        }
        throw 'Register-PmcUniversalCommands not found after loading UniversalDisplay.ps1'
    } catch {
        # Write-PmcDebug -Level 1 -Category 'UniversalDisplay' -Message "Initialization failed" -Data @{ Error = $_.ToString() }
        Write-Warning "UniversalDisplay initialization failed: $($_.ToString())"
        return $false
    }
}

# Initialize Universal Display system when this module is loaded
# Ensure-PmcUniversalDisplay  # Commented out to prevent CommandMap loading issues