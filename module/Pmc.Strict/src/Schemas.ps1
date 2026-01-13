# Parameter schemas for strict commands (subset to start)

# Each entry uses a simple schema array: ordered hints and prefixes
$Script:PmcParameterMap = @{
    'task add' = @(
        @{ Name='Text'; Type='FreeText'; Required=$true; Description='Task description' },
        @{ Name='Project'; Prefix='@'; Type='ProjectName' },
        @{ Name='Priority'; Prefix='p'; Type='Priority'; Pattern='^p[1-3]$' },
        @{ Name='Due'; Prefix='due:'; Type='DateString' },
        @{ Name='Tags'; Prefix='#'; Type='TagName'; AllowsMultiple=$true }
    )
    'task done' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true; Pattern='^\d+$' }
    )
    'task list' = @()
    'task delete' = @()
    'task view' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true }
    )
    'task agenda' = @()
    'task week' = @()
    'task month' = @()
    'time log' = @(
        @{ Name='Project'; Prefix='@'; Type='ProjectName' },
        @{ Name='TaskId'; Prefix='task:'; Type='TaskID' },
        @{ Name='Date'; Type='DateString' },
        @{ Name='Duration'; Type='Duration' },
        @{ Name='Description'; Type='FreeText' }
    )
    'time report' = @(
        @{ Name='Range'; Type='DateRange' },
        @{ Name='Project'; Prefix='@'; Type='ProjectName' }
    )
    'time list' = @()
    'time edit' = @(
        @{ Name='Id'; Type='FreeText'; Required=$true }
    )
    'time delete' = @(
        @{ Name='Id'; Type='FreeText'; Required=$true }
    )
    'timer start' = @(
        @{ Name='Project'; Prefix='@'; Type='ProjectName' },
        @{ Name='Description'; Type='FreeText' }
    )
    'timer stop' = @()
    'timer status' = @()
    'task update' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true },
        @{ Name='Project'; Prefix='@'; Type='ProjectName' },
        @{ Name='Priority'; Prefix='p'; Type='Priority' },
        @{ Name='Due'; Prefix='due:'; Type='DateString' },
        @{ Name='Tags'; Prefix='#'; Type='TagName'; AllowsMultiple=$true },
        @{ Name='Text'; Type='FreeText' }
    )
    'task move' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true },
        @{ Name='Project'; Prefix='@'; Type='ProjectName'; Required=$true }
    )
    'task postpone' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true },
        @{ Name='Delta'; Type='FreeText'; Required=$true }
    )
    'task duplicate' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true }
    )
    'task note' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true },
        @{ Name='Note'; Type='FreeText'; Required=$true }
    )
    'task edit' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true }
    )
    'task search' = @(
        @{ Name='Query'; Type='FreeText'; Required=$true }
    )
    'task priority' = @(
        @{ Name='Level'; Type='FreeText'; Required=$true }
    )

    # Project advanced
    'project add' = @(
        # Name is optional to allow launching the Project Wizard when omitted
        @{ Name='Name'; Type='FreeText'; Required=$false }
    )
    'project list' = @()
    'project stats' = @()
    'project info' = @()
    'project recent' = @()
    'project view' = @(
        @{ Name='Name'; Type='FreeText'; Required=$true }
    )
    'project rename' = @(
        @{ Name='Old'; Type='FreeText'; Required=$true },
        @{ Name='New'; Type='FreeText'; Required=$true }
    )
    'project delete' = @(
        @{ Name='Name'; Type='FreeText'; Required=$true }
    )
    'project archive' = @(
        @{ Name='Name'; Type='FreeText'; Required=$true }
    )
    'project set-fields' = @(
        @{ Name='Project'; Prefix='@'; Type='ProjectName'; Required=$true },
        @{ Name='Fields'; Type='FreeText' }
    )
    'project show-fields' = @(
        @{ Name='Project'; Prefix='@'; Type='ProjectName'; Required=$true }
    )
    'project update' = @(
        @{ Name='Project'; Prefix='@'; Type='ProjectName'; Required=$true },
        @{ Name='Fields'; Type='FreeText' }
    )
    'project edit' = @(
        @{ Name='Project'; Prefix='@'; Type='ProjectName'; Required=$true }
    )

    # Config / Template / Recurring
    'config show' = @()
    'config icons' = @()
    'config set' = @(
        @{ Name='Path'; Type='FreeText'; Required=$true },
        @{ Name='Value'; Type='FreeText'; Required=$true }
    )
    'config edit' = @()

    'template save' = @(
        @{ Name='Name'; Type='FreeText'; Required=$true },
        @{ Name='Body'; Type='FreeText' }
    )
    'template apply' = @(
        @{ Name='Name'; Type='FreeText'; Required=$true }
    )
    'template list' = @()
    'template remove' = @(
        @{ Name='Name'; Type='FreeText'; Required=$true }
    )

    'recurring add' = @(
        @{ Name='Pattern'; Type='FreeText'; Required=$true },
        @{ Name='Body'; Type='FreeText' }
    )
    'recurring list' = @()

    # Dependencies
    'dep add' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true },
        @{ Name='Requires'; Type='FreeText'; Required=$true }
    )
    'dep remove' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true },
        @{ Name='Requires'; Type='FreeText'; Required=$true }
    )
    'dep show' = @(
        @{ Name='Id'; Type='TaskID'; Required=$true }
    )
    'dep graph' = @()

    # Activity / System
    'activity list' = @()
    'system undo' = @()
    'system redo' = @()
    'system backup' = @()
    'system clean' = @()
    'theme reset' = @()
    'theme adjust' = @()

    # Theme management (complete)
    'theme list' = @()
    'theme apply' = @(
        @{ Name='ColorOrPreset'; Type='FreeText'; Required=$true; Description='Color #RRGGBB or preset name' }
    )
    'theme info' = @()
    'excel import' = @()
    'excel bind' = @()
    'excel view' = @()
    'excel latest' = @()
    'import tasks' = @()
    'export tasks' = @()
    'focus set' = @(
        @{ Name='Project'; Type='FreeText'; Required=$true }
    )
    'focus clear' = @()
    'focus status' = @()
    'interactive status' = @()
    'show aliases' = @()
    'show commands' = @()
    'alias add' = @(
        @{ Name='NameAndExpansion'; Type='FreeText'; Required=$true }
    )
    'alias remove' = @(
        @{ Name='Name'; Type='FreeText'; Required=$true }
    )
    'help all' = @()
    'help show' = @()
    'help commands' = @()
    'help examples' = @()
    'help guide' = @()
    'help domain' = @(
        @{ Name='Domain'; Type='FreeText'; Required=$true; Description='Domain name (e.g., task, project, time)' }
    )
    'help command' = @(
        @{ Name='Domain'; Type='FreeText'; Required=$true; Description='Domain name' },
        @{ Name='Action'; Type='FreeText'; Required=$true; Description='Action name' }
    )

    # Views
    'view today' = @()
    'view tomorrow' = @()
    'view overdue' = @()
    'view upcoming' = @()
    'view blocked' = @()
    'view noduedate' = @()
    'view projects' = @()
    'view next' = @()
}

# Schemas.ps1 contains only data structures, no functions to export