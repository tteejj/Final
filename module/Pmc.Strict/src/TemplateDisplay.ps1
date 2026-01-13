# Template-Based Universal Display System for PMC
# Simple, fast, customizable display without TUI complexity

Set-StrictMode -Version Latest

# Template specification and renderer - class moved to main module file for proper export

# Built-in templates - initialized lazily to avoid class loading issues
$Script:PmcTemplates = $null

function Initialize-PmcTemplates {
    if ($Script:PmcTemplates) { return }

    $Script:PmcTemplates = @{
        'task-grid' = [PmcTemplate]::new('task-grid', @{
            type = 'grid'
            header = 'ID    Project      Task                                  Due        Pri'
            row = '{id,-4} {project,-12} {text,-36} {due,-10} {priority,-3}'
            settings = @{ separator = '─'; minWidth = 60 }
        })

        'task-list' = [PmcTemplate]::new('task-list', @{
            type = 'list'
            row = '[{id}] {text} (@{project}, due: {due}, {priority})'
        })

        'task-summary' = [PmcTemplate]::new('task-summary', @{
            type = 'summary'
            header = 'Tasks Summary'
            row = '• {text} ({project})'
            footer = 'Total: {count} tasks'
        })

        'project-card' = [PmcTemplate]::new('project-card', @{
            type = 'card'
            row = @'
┌─ Project: {name} ─────────────────────────
│ Tasks: {task_count} | Completion: {completion}%
│ {description}
└─────────────────────────────────────────
'@
        })

        'project-list' = [PmcTemplate]::new('project-list', @{
            type = 'list'
            row = '{name,-20} {task_count,3} tasks  {completion,3}%'
        })

        'time-report' = [PmcTemplate]::new('time-report', @{
            type = 'grid'
            header = 'Date       Project      Hours  Description'
            row = '{date,-10} {project,-12} {hours,5}h {description}'
        })

        'help-categories' = [PmcTemplate]::new('help-categories', @{
            type = 'grid'
            header = 'Category                    Items  Description'
            row = '{Category,-26} {Items,5}  {Description}'
            settings = @{ separator = '─'; minWidth = 60 }
        })
    }
}

# Default templates by data type
$Script:PmcDefaultTemplates = @{
    'task' = 'task-grid'
    'project' = 'project-list'
    'time' = 'time-report'
    'timelog' = 'time-report'
    'help' = 'help-categories'
}

# Universal template renderer
function Show-PmcDataWithTemplate {
    param(
        [object[]]$Data,
        [string]$DataType,
        [string]$Template = '',
        [string]$Title = '',
        [hashtable]$Filters = @{}
    )

    if (-not $Data -or $Data.Count -eq 0) {
        $filterDesc = $(if ($Filters.Count -gt 0) { " with filters" } else { "" })
        Write-PmcStyled -Style 'Info' -Text "No $DataType data found$filterDesc"
        return
    }

    # Ensure templates are initialized
    Initialize-PmcTemplates

    # Determine template to use
    $templateName = $Template
    if (-not $templateName) {
        $templateName = $(if ($Script:PmcDefaultTemplates.ContainsKey($DataType)) { $Script:PmcDefaultTemplates[$DataType] } else { 'task-list' })
    }

    $tmpl = $Script:PmcTemplates[$templateName]
    if (-not $tmpl) {
        Write-PmcStyled -Style 'Warning' -Text "Template '$templateName' not found, using default"
        $tmpl = $Script:PmcTemplates['task-list']
    }

    # Render based on template type
    switch ($tmpl.Type) {
        'grid' { Render-GridTemplate -Data $Data -Template $tmpl -Title $Title }
        'list' { Render-ListTemplate -Data $Data -Template $tmpl -Title $Title }
        'card' { Render-CardTemplate -Data $Data -Template $tmpl -Title $Title }
        'summary' { Render-SummaryTemplate -Data $Data -Template $tmpl -Title $Title }
        default { Render-ListTemplate -Data $Data -Template $tmpl -Title $Title }
    }
}

# Grid renderer (table-like)
function Render-GridTemplate {
    param([object[]]$Data, [PmcTemplate]$Template, [string]$Title)

    if ($Title) {
        Write-PmcStyled -Style 'Header' -Text $Title
        $sepChar = $(if ($Template.Settings.ContainsKey('separator')) { $Template.Settings.separator } else { '─' })
        Write-Host ($sepChar * 50)
    }

    # Header
    if ($Template.Header) {
        Write-Host $Template.Header
        $sepChar = $(if ($Template.Settings.ContainsKey('separator')) { $Template.Settings.separator } else { '─' })
        Write-Host ($sepChar * $Template.Header.Length)
    }

    # Data rows
    foreach ($item in $Data) {
        $rendered = Expand-TemplateString -Template $Template.Row -Data $item
        Write-Host $rendered
    }
}

# List renderer (simple lines)
function Render-ListTemplate {
    param([object[]]$Data, [PmcTemplate]$Template, [string]$Title)

    if ($Title) {
        Write-PmcStyled -Style 'Header' -Text $Title
        Write-Host ''
    }

    foreach ($item in $Data) {
        $rendered = Expand-TemplateString -Template $Template.Row -Data $item
        Write-Host $rendered
    }
}

# Card renderer (multi-line blocks)
function Render-CardTemplate {
    param([object[]]$Data, [PmcTemplate]$Template, [string]$Title)

    if ($Title) {
        Write-PmcStyled -Style 'Header' -Text $Title
        Write-Host ''
    }

    foreach ($item in $Data) {
        $rendered = Expand-TemplateString -Template $Template.Row -Data $item
        Write-Host $rendered
        Write-Host ''
    }
}

# Summary renderer (with totals)
function Render-SummaryTemplate {
    param([object[]]$Data, [PmcTemplate]$Template, [string]$Title)

    if ($Title -or $Template.Header) {
        $headerText = $(if ($Title) { $Title } else { $Template.Header })
        Write-PmcStyled -Style 'Header' -Text $headerText
        Write-Host ''
    }

    foreach ($item in $Data) {
        $rendered = Expand-TemplateString -Template $Template.Row -Data $item
        Write-Host $rendered
    }

    if ($Template.Footer) {
        Write-Host ''
        $footerData = @{ count = $Data.Count }
        $rendered = Expand-TemplateString -Template $Template.Footer -Data $footerData
        Write-Host $rendered
    }
}

# Template string expansion with data substitution
function Expand-TemplateString {
    param([string]$Template, [object]$Data)

    $result = $Template

    # Handle PSCustomObject and hashtables
    $properties = @{}
    if ($Data -is [hashtable]) {
        $properties = $Data
    } elseif ($Data.PSObject) {
        foreach ($prop in $Data.PSObject.Properties) {
            $properties[$prop.Name] = $prop.Value
        }
    }

    # Replace {field} and {field,width} patterns
    $result = [regex]::Replace($result, '\{([^}]+)\}', {
        param($match)
        $fieldSpec = $match.Groups[1].Value

        # Parse field name and formatting
        $parts = $fieldSpec -split ','
        $fieldName = $parts[0].Trim()
        $format = $(if ($parts.Length -gt 1) { $parts[1].Trim() } else { '' })

        # Get field value
        $value = $(if ($properties.ContainsKey($fieldName)) { $properties[$fieldName] } else { '' })
        $value = [string]$value

        # Apply formatting
        if ($format) {
            if ($format -match '^(-?\d+)$') {
                # Width formatting: {field,10} or {field,-10}
                $width = [int]$format
                if ($width -lt 0) {
                    # Left-align
                    $value = $value.PadRight([Math]::Abs($width))
                } else {
                    # Right-align
                    $value = $value.PadLeft($width)
                }
                # Truncate if too long
                if ($value.Length -gt [Math]::Abs($width)) {
                    $value = $value.Substring(0, [Math]::Abs($width))
                }
            }
        }

        return $value
    })

    return $result
}

# Get available templates
function Get-PmcTemplates {
    param([string]$DataType = '')

    Initialize-PmcTemplates

    if ($DataType) {
        return $Script:PmcTemplates.Keys | Where-Object { $_ -like "$DataType-*" }
    }

    return $Script:PmcTemplates.Keys
}

# Add or update template
function Set-PmcTemplate {
    param(
        [string]$Name,
        [hashtable]$Config
    )

    Initialize-PmcTemplates
    $Script:PmcTemplates[$Name] = [PmcTemplate]::new($Name, $Config)
}

# Template management functions for CommandMap compatibility
function Save-PmcTemplate {
    param([PmcCommandContext]$Context)

    $args = $Context.Args
    if (-not $args.name -or -not $args.type) {
        Write-PmcStyled -Style 'Error' -Text 'Usage: template save name=<name> type=<type> [header=<header>] [row=<row>]'
        return
    }

    $config = @{
        type = $args.type
    }
    if ($args.header) { $config.header = $args.header }
    if ($args.row) { $config.row = $args.row }
    if ($args.footer) { $config.footer = $args.footer }

    Set-PmcTemplate -Name $args.name -Config $config
    Write-PmcStyled -Style 'Success' -Text "Template '$($args.name)' saved"
}

function Invoke-PmcTemplate {
    param([PmcCommandContext]$Context)

    $name = ($Context.FreeText -join ' ').Trim()
    if (-not $name) {
        Write-PmcStyled -Style 'Error' -Text 'Usage: template apply <name>'
        return
    }

    Initialize-PmcTemplates
    if ($Script:PmcTemplates.ContainsKey($name)) {
        Write-PmcStyled -Style 'Success' -Text "Template '$name' applied"
    } else {
        Write-PmcStyled -Style 'Error' -Text "Template '$name' not found"
    }
}

function Get-PmcTemplateList {
    param([PmcCommandContext]$Context)

    Initialize-PmcTemplates
    Write-PmcStyled -Style 'Header' -Text 'Available Templates:'
    foreach ($name in $Script:PmcTemplates.Keys | Sort-Object) {
        $template = $Script:PmcTemplates[$name]
        Write-PmcStyled -Style 'Info' -Text "  $name ($($template.Type))"
    }
}

function Remove-PmcTemplate {
    param([PmcCommandContext]$Context)

    $name = ($Context.FreeText -join ' ').Trim()
    if (-not $name) {
        Write-PmcStyled -Style 'Error' -Text 'Usage: template remove <name>'
        return
    }

    Initialize-PmcTemplates
    if ($Script:PmcTemplates.ContainsKey($name)) {
        $Script:PmcTemplates.Remove($name)
        Write-PmcStyled -Style 'Success' -Text "Template '$name' removed"
    } else {
        Write-PmcStyled -Style 'Error' -Text "Template '$name' not found"
    }
}

# Main display function - replaces the complex Show-PmcData
function Show-PmcSimpleData {
    param(
        [string]$DataType,
        [hashtable]$Filters = @{},
        [string]$Template = '',
        [string]$Title = ''
    )

    Write-PmcDebug -Level 2 -Category 'TemplateDisplay' -Message "Simple data display" -Data @{
        DataType = $DataType
        Template = $Template
        FilterCount = $Filters.Keys.Count
    }

    # Get filtered data using existing system
    $data = Get-PmcFilteredData -Domains @($DataType) -Filters $Filters

    # Generate title if not provided
    if (-not $Title) {
        $Title = $DataType.Substring(0,1).ToUpper() + $DataType.Substring(1) + "s"
        if ($Filters.ContainsKey('project')) {
            $Title += " — @$($Filters.project)"
        }
    }

    # Use template renderer
    Show-PmcDataWithTemplate -Data $data -DataType $DataType -Template $Template -Title $Title -Filters $Filters
}

Export-ModuleMember -Function Show-PmcSimpleData, Show-PmcDataWithTemplate, Get-PmcTemplates, Set-PmcTemplate, Expand-TemplateString, Render-GridTemplate, Render-ListTemplate, Render-CardTemplate, Render-SummaryTemplate, Initialize-PmcTemplates, Save-PmcTemplate, Invoke-PmcTemplate, Get-PmcTemplateList, Remove-PmcTemplate