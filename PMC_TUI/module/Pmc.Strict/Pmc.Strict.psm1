# Pmc.Strict module - strict domain-action engine

# NOTE: Completions use plain strings; no PmcCompletionItem class is used anymore.

enum PmcCompletionMode {
    Domain      # Completing domain names (task, project, time)
    Action      # Completing actions (add, list, done)
    Arguments   # Completing arguments (@project, due:date, p1)
    FreeText    # No completions available
}

class PmcEditorState {
    [string] $Buffer = ""
    [int] $CursorPos = 0
    [bool] $InCompletion = $false
    [string] $OriginalBuffer = ""
    [string[]] $Completions = @()
    [int] $CompletionIndex = -1
    [PmcCompletionMode] $Mode = [PmcCompletionMode]::Domain
    [string] $CurrentToken = ""
    [int] $TokenStart = 0
    [int] $TokenEnd = 0

    # History and undo/redo
    [string[]] $History = @()
    [int] $HistoryIndex = -1
    [string[]] $UndoStack = @()
    [string[]] $RedoStack = @()
    [int] $MaxUndoItems = 50
    [int] $MaxHistoryItems = 100
}

# Template specification and renderer - moved to module scope for proper class export
class PmcTemplate {
    [string]$Name
    [string]$Type        # 'grid', 'list', 'card', 'summary'
    [string]$Header      # Header template
    [string]$Row         # Row/item template
    [string]$Footer      # Footer template
    [hashtable]$Settings # Width, alignment, etc.

    PmcTemplate([string]$name, [hashtable]$config) {
        $this.Name = $name
        $this.Type = $(if ($config.ContainsKey('type')) { $config.type } else { 'list' })
        $this.Header = $(if ($config.ContainsKey('header')) { $config.header } else { '' })
        $this.Row = $(if ($config.ContainsKey('row')) { $config.row } else { '' })
        $this.Footer = $(if ($config.ContainsKey('footer')) { $config.footer } else { '' })
        $this.Settings = $(if ($config.ContainsKey('settings')) { $config.settings } else { @{} })
    }
}

# Dot-source internal components with debug tracing
# Module loading in progress...

try {
    # Loading Types.ps1...
    . $PSScriptRoot/src/Types.ps1
    # [OK] Types.ps1 loaded
} catch {
    Write-Host "[ERROR] PMC module loading failed: Types.ps1 - $_" -ForegroundColor Red
    throw
}

# Load terminal dimension service early as many modules depend on it
try {
    # Loading TerminalDimensions.ps1...
    . $PSScriptRoot/src/TerminalDimensions.ps1
    # [OK] TerminalDimensions.ps1 loaded
} catch {
    Write-Host "[ERROR] PMC module loading failed: TerminalDimensions.ps1 - $_" -ForegroundColor Red
    throw
}

# Ensure centralized state is available before any consumer
try {
    # Loading State.ps1...
    . $PSScriptRoot/src/State.ps1
    # [OK] State.ps1 loaded
} catch {
    Write-Host "[ERROR] PMC module loading failed: State.ps1 - $_" -ForegroundColor Red
    throw
}

# Config providers and helpers before Debug/Security which consult config
try {
    # Loading Config.ps1...
    . $PSScriptRoot/src/Config.ps1
    # [OK] Config.ps1 loaded
} catch {
    Write-Host "[ERROR] PMC module loading failed: Config.ps1 - $_" -ForegroundColor Red
    throw
}

# Now load Debug and Security modules (no auto-init inside files)
try {
    # Loading Debug.ps1...
    . $PSScriptRoot/src/Debug.ps1
    # [OK] Debug.ps1 loaded
} catch {
    Write-Host "  [ERROR] Debug.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Security.ps1...
    . $PSScriptRoot/src/Security.ps1
    # [OK] Security.ps1 loaded
} catch {
    Write-Host "  [ERROR] Security.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Storage.ps1...
    . $PSScriptRoot/src/Storage.ps1
    # [OK] Storage.ps1 loaded
} catch {
    Write-Host "  [ERROR] Storage.ps1 failed: $_" -ForegroundColor Red
    throw
}

# Create Save-StrictData alias for backward compatibility
# Used by Focus.ps1, Aliases.ps1, and other modules
Set-Alias -Name Save-StrictData -Value Save-PmcData

try {
    # Loading UI.ps1...
    . $PSScriptRoot/src/UI.ps1
    # [OK] UI.ps1 loaded
} catch {
    Write-Host "  [ERROR] UI.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading ScreenManager.ps1...
    . $PSScriptRoot/src/ScreenManager.ps1
    # [OK] ScreenManager.ps1 loaded
} catch {
    Write-Host "  [ERROR] ScreenManager.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Resolvers.ps1...
    . $PSScriptRoot/src/Resolvers.ps1
    # [OK] Resolvers.ps1 loaded
} catch {
    Write-Host "  [ERROR] Resolvers.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading CommandMap.ps1...
    . $PSScriptRoot/src/CommandMap.ps1
    # [OK] CommandMap.ps1 loaded
} catch {
    Write-Host "  [ERROR] CommandMap.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Schemas.ps1...
    . $PSScriptRoot/src/Schemas.ps1
    # [OK] Schemas.ps1 loaded
} catch {
    Write-Host "  [ERROR] Schemas.ps1 failed: $_" -ForegroundColor Red
    throw
}

## moved earlier

try {
    # Loading AstCommandParser.ps1...
    . $PSScriptRoot/src/AstCommandParser.ps1
    # [OK] AstCommandParser.ps1 loaded
} catch {
    Write-Host "  [ERROR] AstCommandParser.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading AstCompletion.ps1...
    . $PSScriptRoot/src/AstCompletion.ps1
    # [OK] AstCompletion.ps1 loaded
} catch {
    Write-Host "  [ERROR] AstCompletion.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading TemplateDisplay.ps1...
    . $PSScriptRoot/src/TemplateDisplay.ps1
    # [OK] TemplateDisplay.ps1 loaded
} catch {
    Write-Host "  [ERROR] TemplateDisplay.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Execution.ps1...
    . $PSScriptRoot/src/Execution.ps1
    # [OK] Execution.ps1 loaded
} catch {
    Write-Host "  [ERROR] Execution.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Dependencies.ps1...
    . $PSScriptRoot/src/Dependencies.ps1
    # [OK] Dependencies.ps1 loaded
} catch {
    Write-Host "  [ERROR] Dependencies.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Focus.ps1...
    . $PSScriptRoot/src/Focus.ps1
    # [OK] Focus.ps1 loaded
} catch {
    Write-Host "  [ERROR] Focus.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Time.ps1...
    . $PSScriptRoot/src/Time.ps1
    # [OK] Time.ps1 loaded
} catch {
    Write-Host "  [ERROR] Time.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading UndoRedo.ps1...
    . $PSScriptRoot/src/UndoRedo.ps1
    # [OK] UndoRedo.ps1 loaded
} catch {
    Write-Host "  [ERROR] UndoRedo.ps1 failed: $_" -ForegroundColor Red
    throw
}



# Views.ps1 functionality migrated to UniversalDisplay.ps1 during technical debt cleanup

try {
    # Loading Aliases.ps1...
    . $PSScriptRoot/src/Aliases.ps1
    # [OK] Aliases.ps1 loaded
} catch {
    Write-Host "  [ERROR] Aliases.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Analytics.ps1...
    . $PSScriptRoot/src/Analytics.ps1
    # [OK] Analytics.ps1 loaded
} catch {
    Write-Host "  [ERROR] Analytics.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Theme.ps1...
    . $PSScriptRoot/src/Theme.ps1
    # [OK] Theme.ps1 loaded
} catch {
    Write-Host "  [ERROR] Theme.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading ImportExport.ps1...
    . $PSScriptRoot/src/ImportExport.ps1
    # [OK] ImportExport.ps1 loaded
} catch {
    Write-Host "  [ERROR] ImportExport.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Shortcuts.ps1...
    . $PSScriptRoot/src/Shortcuts.ps1
    # [OK] Shortcuts.ps1 loaded
} catch {
    Write-Host "  [ERROR] Shortcuts.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Review.ps1...
    . $PSScriptRoot/src/Review.ps1
    # [OK] Review.ps1 loaded
} catch {
    Write-Host "  [ERROR] Review.ps1 failed: $_" -ForegroundColor Red
    throw
}

# Initialize help content data structure - organized from reference doc
$Script:PmcHelpContent = @{
    'Query Language' = @{
        Description = 'Filter, sort, and display tasks, projects, and time logs'
        Items = @(
            @{ Type='Basic'; Command='q tasks'; Description='Show all tasks' }
            @{ Type='Filter'; Command='q tasks p1'; Description='High priority tasks' }
            @{ Type='Filter'; Command='q tasks due:today'; Description='Tasks due today' }
            @{ Type='Filter'; Command='q tasks @webapp'; Description='Tasks for webapp project' }
            @{ Type='Filter'; Command='q tasks #urgent'; Description='Tasks tagged urgent' }
            @{ Type='Filter'; Command='q tasks overdue'; Description='Overdue tasks' }
            @{ Type='Filter'; Command='q tasks "database"'; Description='Text search for "database"' }
            @{ Type='View'; Command='q tasks group:status'; Description='Kanban board by status' }
            @{ Type='View'; Command='q tasks cols:id,text,due'; Description='Custom columns' }
            @{ Type='View'; Command='q tasks sort:due+'; Description='Sort by due date ascending' }
            @{ Type='Combo'; Command='q tasks @webapp p<=2 due:+7'; Description='Multiple filters combined' }
            @{ Type='Save'; Command='q tasks p1 due:today save:urgent'; Description='Save query as "urgent"' }
            @{ Type='Load'; Command='q load:urgent'; Description='Load saved query' }
        )
    }
    'Priority Filters' = @{
        Description = 'Filter tasks by priority level'
        Items = @(
            @{ Type='Basic'; Command='q tasks p1'; Description='Priority 1 (highest)' }
            @{ Type='Basic'; Command='q tasks p2'; Description='Priority 2 (medium)' }
            @{ Type='Basic'; Command='q tasks p3'; Description='Priority 3 (lowest)' }
            @{ Type='Range'; Command='q tasks p<=2'; Description='Priority 2 or higher' }
            @{ Type='Range'; Command='q tasks p1..3'; Description='Priority range 1 to 3' }
        )
    }
    'Date Filters' = @{
        Description = 'Filter tasks by dates and deadlines'
        Items = @(
            @{ Type='Relative'; Command='q tasks due:today'; Description='Due today' }
            @{ Type='Relative'; Command='q tasks due:tomorrow'; Description='Due tomorrow' }
            @{ Type='Relative'; Command='q tasks due:+7'; Description='Due in 7 days' }
            @{ Type='Relative'; Command='q tasks due:eow'; Description='Due end of week (Sunday)' }
            @{ Type='Relative'; Command='q tasks due:eom'; Description='Due end of month' }
            @{ Type='Relative'; Command='q tasks due:1m'; Description='Due in 1 month' }
            @{ Type='Absolute'; Command='q tasks due:20251225'; Description='Due Dec 25, 2025 (yyyymmdd)' }
            @{ Type='Absolute'; Command='q tasks due:1225'; Description='Due Dec 25 (current year)' }
            @{ Type='Status'; Command='q tasks overdue'; Description='Overdue tasks' }
        )
    }
    'Project Filters' = @{
        Description = 'Filter by project names and assignments'
        Items = @(
            @{ Type='Basic'; Command='q tasks @webapp'; Description='Tasks for project "webapp"' }
            @{ Type='Quoted'; Command='q tasks @"project name"'; Description='Projects with spaces' }
            @{ Type='Multiple'; Command='q tasks @webapp @api'; Description='Tasks from multiple projects' }
            @{ Type='Negative'; Command='q tasks -@archived'; Description='Exclude archived project' }
        )
    }
    'Tag Filters' = @{
        Description = 'Filter by tags and labels'
        Items = @(
            @{ Type='Basic'; Command='q tasks #urgent'; Description='Has "urgent" tag' }
            @{ Type='Multiple'; Command='q tasks #web #api'; Description='Has both "web" and "api" tags' }
            @{ Type='Negative'; Command='q tasks -#blocked'; Description='Does NOT have "blocked" tag' }
        )
    }
    'Display Options' = @{
        Description = 'Control how results are displayed'
        Items = @(
            @{ Type='Columns'; Command='q tasks cols:id,text,due'; Description='Show only specified columns' }
            @{ Type='Columns'; Command='q tasks cols:id,text,due,priority'; Description='Include priority column' }
            @{ Type='Sort'; Command='q tasks sort:due+'; Description='Sort by due date ascending' }
            @{ Type='Sort'; Command='q tasks sort:priority-'; Description='Sort by priority descending' }
            @{ Type='Sort'; Command='q tasks sort:due+,priority-'; Description='Multi-column sort' }
            @{ Type='View'; Command='q tasks view:kanban'; Description='Display as Kanban board' }
            @{ Type='View'; Command='q tasks view:list'; Description='Display as list (default)' }
            @{ Type='Group'; Command='q tasks group:status'; Description='Group by status' }
            @{ Type='Group'; Command='q tasks group:project'; Description='Group by project' }
        )
    }
    'Advanced Features' = @{
        Description = 'Metrics, relations, and saved queries'
        Items = @(
            @{ Type='Metrics'; Command='q tasks metrics:time_week'; Description='Add time logged this week' }
            @{ Type='Metrics'; Command='q tasks metrics:time_today'; Description='Add time logged today' }
            @{ Type='Metrics'; Command='q tasks metrics:overdue_days'; Description='Add days overdue' }
            @{ Type='Relations'; Command='q tasks with:project'; Description='Include related project data' }
            @{ Type='Relations'; Command='q projects with:tasks'; Description='Include related tasks' }
            @{ Type='Save'; Command='q tasks p1 due:today save:myquery'; Description='Save query as "myquery"' }
            @{ Type='Load'; Command='q load:myquery'; Description='Load saved query' }
        )
    }
    'Quick Tasks' = @{
        Description = 'Common task management commands'
        Items = @(
            @{ Type='View'; Command='today'; Description='Tasks due today' }
            @{ Type='View'; Command='overdue'; Description='Overdue tasks' }
            @{ Type='View'; Command='agenda'; Description='Agenda view' }
            @{ Type='Add'; Command='add "Task text" @project p1 due:today'; Description='Add new task' }
            @{ Type='Edit'; Command='edit 123'; Description='Edit task by ID' }
            @{ Type='Complete'; Command='done 123'; Description='Mark task complete' }
        )
    }
    'Projects' = @{
        Description = 'Project management commands'
        Items = @(
            @{ Type='View'; Command='projects'; Description='List all projects' }
            @{ Type='Add'; Command='project add "Project Name"'; Description='Create new project' }
            @{ Type='View'; Command='project show webapp'; Description='Show project details' }
            @{ Type='Edit'; Command='project edit webapp'; Description='Edit project settings' }
        )
    }
    'Time Tracking' = @{
        Description = 'Time logging and reports'
        Items = @(
            @{ Type='Start'; Command='timer start @project "Working on feature"'; Description='Start timer' }
            @{ Type='Stop'; Command='timer stop'; Description='Stop current timer' }
            @{ Type='Status'; Command='timer status'; Description='Show timer status' }
            @{ Type='Add'; Command='time add 2h @project "Meeting"'; Description='Log time manually' }
            @{ Type='Report'; Command='time report week'; Description='Weekly time report' }
        )
    }
}

# Help data provider function - needs to be in same scope as $Script:PmcHelpContent
function Get-PmcHelpData {
    param([PmcCommandContext]$Context)
    # Return help categories as domain data for universal display system
    $helpCategories = @()

    if ($Script:PmcHelpContent -and $Script:PmcHelpContent.Count -gt 0) {
        $id = 1
        foreach ($categoryEntry in $Script:PmcHelpContent.GetEnumerator()) {
            $helpCategories += [PSCustomObject]@{
                id = $id++
                Category = $categoryEntry.Key
                CommandCount = $categoryEntry.Value.Items.Count
                Description = $categoryEntry.Value.Description
            }
        }
    }

    return $helpCategories
}

try {
    # Loading TaskEditor.ps1...
    . $PSScriptRoot/src/TaskEditor.ps1
    # [OK] TaskEditor.ps1 loaded
} catch {
    Write-Host "  [ERROR] TaskEditor.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading ProjectWizard.ps1...
    . $PSScriptRoot/src/ProjectWizard.ps1
    # [OK] ProjectWizard.ps1 loaded
} catch {
    Write-Host "  [ERROR] ProjectWizard.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Projects.ps1...
    . $PSScriptRoot/src/Projects.ps1
    # [OK] Projects.ps1 loaded
} catch {
    Write-Host "  [ERROR] Projects.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Tasks.ps1...
    . $PSScriptRoot/src/Tasks.ps1
    # [OK] Tasks.ps1 loaded
} catch {
    Write-Host "  [ERROR] Tasks.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Views.ps1...
    . $PSScriptRoot/src/Views.ps1
    # [OK] Views.ps1 loaded
} catch {
    Write-Host "  [ERROR] Views.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading PraxisVT.ps1...
    . $PSScriptRoot/src/PraxisVT.ps1
    # [OK] PraxisVT.ps1 loaded
} catch {
    Write-Host "  [ERROR] PraxisVT.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading PraxisStringBuilder.ps1...
    . $PSScriptRoot/src/PraxisStringBuilder.ps1
    # [OK] PraxisStringBuilder.ps1 loaded
} catch {
    Write-Host "  [ERROR] PraxisStringBuilder.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading FieldSchemas.ps1...
    . $PSScriptRoot/src/FieldSchemas.ps1
    # [OK] FieldSchemas.ps1 loaded
} catch {
    Write-Host "  [ERROR] FieldSchemas.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading QuerySpec.ps1...
    . $PSScriptRoot/src/QuerySpec.ps1
    # [OK] QuerySpec.ps1 loaded
} catch {
    Write-Host "  [ERROR] QuerySpec.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Query.ps1...
    . $PSScriptRoot/src/Query.ps1
    # [OK] Query.ps1 loaded
} catch {
    Write-Host "  [ERROR] Query.ps1 failed: $_" -ForegroundColor Red
    throw
}

# Query engine dependencies (computed fields, evaluator, kanban renderer)
try {
    # Loading ComputedFields.ps1...
    . $PSScriptRoot/src/ComputedFields.ps1
    # [OK] ComputedFields.ps1 loaded
} catch {
    Write-Host "  [ERROR] ComputedFields.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading QueryEvaluator.ps1...
    . $PSScriptRoot/src/QueryEvaluator.ps1
    # [OK] QueryEvaluator.ps1 loaded
} catch {
    Write-Host "  [ERROR] QueryEvaluator.ps1 failed: $_" -ForegroundColor Red
    throw
}


try {
    # Loading PraxisFrameRenderer.ps1...
    . $PSScriptRoot/src/PraxisFrameRenderer.ps1
    # [OK] PraxisFrameRenderer.ps1 loaded
} catch {
    Write-Host "  [ERROR] PraxisFrameRenderer.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading DataDisplay.ps1...
    . $PSScriptRoot/src/DataDisplay.ps1
    # [OK] DataDisplay.ps1 loaded
} catch {
    Write-Host "  [ERROR] DataDisplay.ps1 failed: $_" -ForegroundColor Red
    throw
}

# DISABLED: KanbanRenderer has syntax errors
# try {
#     # Loading KanbanRenderer.ps1...
#     . $PSScriptRoot/src/KanbanRenderer.ps1
#     # [OK] KanbanRenderer.ps1 loaded
# } catch {
#     Write-Host "  [ERROR] KanbanRenderer.ps1 failed: $_" -ForegroundColor Red
#     throw
# }

try {
    # Loading UniversalDisplay.ps1...
    . $PSScriptRoot/src/UniversalDisplay.ps1
    # [OK] UniversalDisplay.ps1 loaded
} catch {
    Write-Host "  [ERROR] UniversalDisplay.ps1 failed: $_" -ForegroundColor Red
    throw
}

try {
    # Loading Core/EnhancedCommandProcessor.ps1...
    . $PSScriptRoot/Core/EnhancedCommandProcessor.ps1
    # [OK] Core/EnhancedCommandProcessor.ps1 loaded
} catch {
    Write-Host "  [ERROR] Core/EnhancedCommandProcessor.ps1 failed: $_" -ForegroundColor Red
    throw
}

 


# Clear screen after module loading completes
if (Get-Command Reset-PmcScreen -ErrorAction SilentlyContinue) {
    Reset-PmcScreen
}

# Define Get-PmcData wrapper - MUST be before Export-ModuleMember
function Get-PmcData {
    # Forward to Storage.ps1's implementation if it exists, otherwise load directly
    $file = Get-PmcTaskFilePath
    if (-not (Test-Path $file)) {
        $root = Split-Path $file -Parent
        try { if (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null } } catch {}
        $init = @{
            tasks=@(); deleted=@(); completed=@(); timelogs=@(); activityLog=@(); projects=@(@{ name='inbox'; description='Default inbox'; aliases=@(); created=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss') });
            currentContext='inbox'; schema_version=1; preferences=@{ autoBackup=$true }
        } | ConvertTo-Json -Depth 10
        $init | Set-Content -Path $file -Encoding UTF8
    }
    # KR-M1 FIX: Add type validation before casting JSON boolean field
    $cfg = Get-PmcConfig; $strict = $true
    try {
        if ($cfg.Behavior -and $cfg.Behavior.StrictDataMode -ne $null) {
            # Validate and safely convert to boolean
            if ($cfg.Behavior.StrictDataMode -is [bool]) {
                $strict = $cfg.Behavior.StrictDataMode
            } elseif ($cfg.Behavior.StrictDataMode -is [string]) {
                $strict = $cfg.Behavior.StrictDataMode -eq 'true'
            } elseif ($cfg.Behavior.StrictDataMode -is [int]) {
                $strict = $cfg.Behavior.StrictDataMode -ne 0
            } else {
                $strict = [bool]$cfg.Behavior.StrictDataMode
            }
        }
    } catch {}
    try {
        $raw = Get-Content $file -Raw
        $data = $raw | ConvertFrom-Json
        $data = Normalize-PmcData $data
        $data = Initialize-PmcDataSchema $data
        return $data
    } catch {
        if ($strict) { throw }
        return @{
            schema_version = 1; tasks=@(); projects=@(); timelogs=@(); deleted=@(); completed=@(); activityLog=@(); templates=@(); recurringTemplates=@(); aliases=@{}; currentContext='inbox'; preferences=@{ autoBackup=$true }
        }
    }
}

# FakeTUI function loaded from src/FakeTUICommand.ps1

# Export aliases
Export-ModuleMember -Alias Save-StrictData

# Services directory - REFERENCE ONLY (disabled to avoid conflicts)
# Future service-oriented architecture available in Services/ directory
# To re-enable: Uncomment the block below (after resolving display system conflicts)
#
# try {
#     . $PSScriptRoot/Services/LegacyCompat.ps1
#     Write-Host "[OK] LegacyCompat services loaded" -ForegroundColor Green
# } catch {
#     Write-Host "[ERROR] LegacyCompat services failed: $_" -ForegroundColor Red
# }

# Initialize core systems
try {
    Initialize-PmcThemeSystem
    Initialize-PmcSecuritySystem
    $cfg = Get-PmcConfig
    $lvl = try { [int]$cfg.Debug.Level } catch { 0 }
    Initialize-PmcDebugSystem -Level $lvl
} catch {
    Write-Host "[ERROR] Core system initialization failed: $_" -ForegroundColor Red
}

# Register universal command shortcuts after export so functions are available
try {
    if (Get-Command Register-PmcUniversalCommands -ErrorAction SilentlyContinue) {
        Register-PmcUniversalCommands
        Write-Host "[OK] Universal command shortcuts registered" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Register-PmcUniversalCommands function not found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[ERROR] Universal Display initialization failed: $_" -ForegroundColor Red
}

# Modules loaded after Export-ModuleMember removed to fix export issues