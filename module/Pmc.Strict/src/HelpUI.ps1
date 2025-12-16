function Show-PmcHelpCategories {
    param($Context)

    Write-PmcDebug -Level 1 -Category 'HELP' -Message 'Show-PmcHelpCategories START'

    # Build help categories data
    $rows = @()
    $useCurated = ($Script:PmcHelpContent -and $Script:PmcHelpContent.Count -gt 0)
    if ($useCurated) {
        foreach ($entry in $Script:PmcHelpContent.GetEnumerator()) {
            $rows += [pscustomobject]@{
                category = [string]$entry.Key
                items = @($entry.Value.Items).Count
                description = [string]$entry.Value.Description
            }
        }
    } else {
        # Fallback to domain listing from CommandMap
        foreach ($domain in ($Script:PmcCommandMap.Keys | Sort-Object)) {
            $actions = 0
            try { $actions = @($Script:PmcCommandMap[$domain].Keys).Count } catch { $actions = 0 }
            $desc = switch ($domain) {
                'task' { 'Task management commands' }
                'project' { 'Project management commands' }
                'time' { 'Time tracking commands' }
                'view' { 'Data viewing commands' }
                'help' { 'Help system commands' }
                'config' { 'Configuration commands' }
                default { 'Domain commands' }
            }
            $rows += [pscustomobject]@{
                category = $domain
                items = $actions
                description = $desc
            }
        }
    }

    # Use template display system
    $helpTemplate = [PmcTemplate]::new('help-categories', @{
        type = 'grid'
        header = 'Category          Items  Description'
        row = '{category,-16} {items,6}  {description}'
        settings = @{ separator = '─'; minWidth = 60 }
    })

    Write-PmcStyled -Style 'Header' -Text "`n📚 PMC HELP — CATEGORIES`n"
    Render-GridTemplate -Data $rows -Template $helpTemplate
    Write-PmcStyled -Style 'Info' -Text "`nUse: help domain <category> (e.g., 'help domain task')"
}

function Show-PmcHelpCommands {
    param($Context,[string]$Domain)

    Write-PmcDebug -Level 1 -Category 'HELP' -Message 'Show-PmcHelpCommands START' -Data @{ Domain = $Domain }

    if ([string]::IsNullOrWhiteSpace($Domain)) { return }

    # Build rows from domain actions
    $rows = @()
    $map = $null
    try { $map = $Script:PmcCommandMap[$Domain] } catch { $map = $null }

    if ($map) {
        foreach ($action in ($map.Keys | Sort-Object)) {
            $full = "{0} {1}" -f $Domain, $action
            $desc = ''
            try {
                if ($Script:PmcCommandMeta.ContainsKey($full)) {
                    $desc = [string]$Script:PmcCommandMeta[$full].Desc
                }
            } catch {}
            $rows += [pscustomobject]@{
                command = $action
                full = $full
                description = $desc
            }
        }
    } else {
        Write-PmcStyled -Style 'Error' -Text "Domain '$Domain' not found."
        return
    }

    # Use template display system
    $helpTemplate = [PmcTemplate]::new('help-commands', @{
        type = 'grid'
        header = 'Command           Description'
        row = '{command,-18} {description}'
        settings = @{ separator = '─'; minWidth = 50 }
    })

    Write-PmcStyled -Style 'Header' -Text "`n📚 PMC HELP — $($Domain.ToUpper())`n"
    Render-GridTemplate -Data $rows -Template $helpTemplate
    Write-PmcStyled -Style 'Info' -Text "`nUse: help command <domain> <action> (e.g., 'help command task add')"
}

# Show help topic content using template display
function Show-PmcHelpTopic {
    param($Context,[string]$Topic)
    Write-PmcDebug -Level 1 -Category 'HELP' -Message 'Show-PmcHelpTopic START' -Data @{ Topic=$Topic }

    Write-PmcStyled -Style 'Header' -Text "`n📚 HELP — $($Topic.ToUpper())`n"

    $topicLC = ($Topic + '').ToLower().Trim()
    switch ($topicLC) {
        'query' {
            Write-PmcStyled -Style 'Subheader' -Text 'PMC Query Language'
            Write-PmcStyled -Style 'Info' -Text 'Basic query syntax:'
            Write-PmcStyled -Style 'Code' -Text '  task list status:pending'
            Write-PmcStyled -Style 'Code' -Text '  task list due:today'
            Write-PmcStyled -Style 'Code' -Text '  task list project:work'
            Write-PmcStyled -Style 'Info' -Text '`nOperators: =, !=, <, >, contains, startswith, endswith'
            Write-PmcStyled -Style 'Info' -Text 'Logical: and, or, not'
        }
        'examples' {
            Write-PmcStyled -Style 'Subheader' -Text 'Common PMC Examples'
            Write-PmcStyled -Style 'Info' -Text 'Add a task:'
            Write-PmcStyled -Style 'Code' -Text '  task add "Fix login bug" project:web due:2024-01-15'
            Write-PmcStyled -Style 'Info' -Text '`nList overdue tasks:'
            Write-PmcStyled -Style 'Code' -Text '  view overdue'
            Write-PmcStyled -Style 'Info' -Text '`nStart time tracking:'
            Write-PmcStyled -Style 'Code' -Text '  timer start'
        }
        default {
            Write-PmcStyled -Style 'Warning' -Text "No detailed help available for topic: $Topic"
        }
    }
}

function Show-PmcSmartHelp {
    param($Context)
    # Show main help categories with template display
    Show-PmcHelpCategories -Context $Context
}

# Show help for a specific domain (static display)
function Show-PmcHelpDomain {
    param($Context, [string]$Domain)
    if ($Context.Args.ContainsKey('domain')) {
        $Domain = $Context.Args['domain']
    }
    if ([string]::IsNullOrWhiteSpace($Domain)) {
        Write-PmcStyled -Style 'Warning' -Text 'Usage: help domain <domain_name>'
        return
    }
    Show-PmcHelpCommands -Context $Context -Domain $Domain
}

# Show help for a specific command (static display)
function Show-PmcHelpCommand {
    param($Context, [string]$Command)
    if ($Context.Args.ContainsKey('command')) {
        $Command = $Context.Args['command']
    }
    if ([string]::IsNullOrWhiteSpace($Command)) {
        Write-PmcStyled -Style 'Warning' -Text 'Usage: help command <command_name>'
        return
    }

    Write-PmcStyled -Style 'Header' -Text "`n📚 COMMAND HELP: $($Command.ToUpper())"

    # Try to find command info
    $found = $false
    foreach ($domain in $Script:PmcCommandMap.Keys) {
        foreach ($action in $Script:PmcCommandMap[$domain].Keys) {
            $fullCmd = "$domain $action"
            if ($fullCmd -eq $Command) {
                $func = $Script:PmcCommandMap[$domain][$action]
                $desc = $(if ($Script:PmcCommandMeta.ContainsKey($fullCmd)) { $Script:PmcCommandMeta[$fullCmd].Desc } else { 'No description available' })

                Write-PmcStyled -Style 'Info' -Text "`nCommand: $fullCmd"
                Write-PmcStyled -Style 'Info' -Text "Function: $func"
                Write-PmcStyled -Style 'Info' -Text "Description: $desc"
                $found = $true
                break
            }
        }
        if ($found) { break }
    }

    if (-not $found) {
        Write-PmcStyled -Style 'Warning' -Text "Command '$Command' not found."
    }
}

# Show query language help
function Show-PmcHelpQuery {
    param($Context)
    Show-PmcHelpTopic -Context $Context -Topic 'query'
}

# Show help examples
function Show-PmcHelpExamples {
    param($Context)
    Show-PmcHelpTopic -Context $Context -Topic 'examples'
}

# Show interactive help guide
function Show-PmcHelpGuide {
    param($Context)
    Write-PmcStyled -Style 'Header' -Text "`n📚 PMC HELP GUIDE`n"
    Write-PmcStyled -Style 'Subheader' -Text 'Getting Started:'
    Write-PmcStyled -Style 'Info' -Text '• help show - Browse all help categories'
    Write-PmcStyled -Style 'Info' -Text '• help domain <name> - Show commands for a domain'
    Write-PmcStyled -Style 'Info' -Text '• help command <cmd> - Show detailed command help'
    Write-PmcStyled -Style 'Info' -Text '• help query - Learn the query language'
    Write-PmcStyled -Style 'Info' -Text '• help examples - See practical examples'
    Write-PmcStyled -Style 'Subheader' -Text '`nQuick Start:'
    Write-PmcStyled -Style 'Code' -Text '  task add "My first task"'
    Write-PmcStyled -Style 'Code' -Text '  task list'
    Write-PmcStyled -Style 'Code' -Text '  view today'
}

# Search help content and commands
function Show-PmcHelpSearch {
    param($Context, [string]$Query)
    if ($Context.Args.ContainsKey('query')) {
        $Query = $Context.Args['query']
    }
    if ([string]::IsNullOrWhiteSpace($Query)) {
        Write-PmcStyled -Style 'Warning' -Text 'Usage: help search <search_term>'
        return
    }

    Write-PmcStyled -Style 'Header' -Text "`n🔍 HELP SEARCH: $Query`n"

    $results = @()
    $queryLower = $Query.ToLower()

    # Search command descriptions
    foreach ($domain in $Script:PmcCommandMap.Keys) {
        foreach ($action in $Script:PmcCommandMap[$domain].Keys) {
            $fullCmd = "$domain $action"
            $desc = $(if ($Script:PmcCommandMeta.ContainsKey($fullCmd)) { $Script:PmcCommandMeta[$fullCmd].Desc } else { '' })

            if ($fullCmd.ToLower().Contains($queryLower) -or $desc.ToLower().Contains($queryLower)) {
                $results += [pscustomobject]@{
                    command = $fullCmd
                    description = $desc
                }
            }
        }
    }

    if ($results.Count -gt 0) {
        $searchTemplate = [PmcTemplate]::new('help-search', @{
            type = 'grid'
            header = 'Command              Description'
            row = '{command,-20} {description}'
            settings = @{ separator = '─'; minWidth = 50 }
        })
        Render-GridTemplate -Data $results -Template $searchTemplate
    } else {
        Write-PmcStyled -Style 'Warning' -Text "No help results found for: $Query"
    }
}

Export-ModuleMember -Function Show-PmcSmartHelp, Show-PmcHelpCategories, Show-PmcHelpCommands, Show-PmcHelpDomain, Show-PmcHelpCommand, Show-PmcHelpQuery, Show-PmcHelpExamples, Show-PmcHelpGuide, Show-PmcHelpSearch