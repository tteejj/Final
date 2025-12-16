function Get-PmcSchema {
    param([string]$Domain,[string]$Action)
    $key = "$($Domain.ToLower()) $($Action.ToLower())"
    if ($Script:PmcParameterMap.ContainsKey($key)) { return $Script:PmcParameterMap[$key] }
    return @()
}

function Get-PmcHelp {
    param([PmcCommandContext]$Context)
    # Route to clean help system
    Show-PmcSmartHelp -Context $Context
}

# Static domain help (non-interactive)
function Show-PmcHelpDomain {
    param([PmcCommandContext]$Context)

    # Use AST parsing to better understand domain query
    $domain = $null

    if ($Context -and $Context.FreeText.Count -ge 1) {
        # Try AST parsing first
        try {
            $helpQuery = $Context.FreeText -join ' '
            if (Get-Command ConvertTo-PmcCommandAst -ErrorAction SilentlyContinue) {
                $ast = ConvertTo-PmcCommandAst -CommandText $helpQuery
                if ($ast.Domain) { $domain = $ast.Domain.ToLower() }
            }
        } catch {
            Write-PmcDebug -Level 2 -Category 'Help' -Message "AST parsing failed for domain help query"
        }

        # Fallback to simple token parsing
        if (-not $domain) { $domain = $Context.FreeText[0].ToLower() }
    }

    if (-not $domain) {
        Write-PmcStyled -Style 'Warning' -Text "Usage: help domain <domain> (e.g., help domain task)"
        return
    }
    if (-not $Script:PmcCommandMap.ContainsKey($domain)) { Write-PmcStyled -Style 'Error' -Text ("Unknown domain '{0}'" -f $domain); return }

    Write-PmcStyled -Style 'Title' -Text ("\nHELP — {0}" -f $domain.ToUpper())
    Write-PmcStyled -Style 'Border' -Text ("─" * 80)

    $rows = @()
    foreach ($a in ($Script:PmcCommandMap[$domain].Keys | Sort-Object)) {
        $key = "$domain $a"
        $desc = ''
        try { if ($Script:PmcCommandMeta.ContainsKey($key)) { $desc = [string]$Script:PmcCommandMeta[$key].Desc } } catch {}
        $rows += [pscustomobject]@{ Action=$a; Description=$desc }
    }
    foreach ($row in $rows) {
        $act = $row.Action.PadRight(18).Substring(0,18)
        $desc = $(if ($row.Description) { $row.Description } else { '' })
        Write-Host ("  {0} {1}" -f $act, $desc)
    }
}

# Static command help (arguments, usage)
function Show-PmcHelpCommand {
    param([PmcCommandContext]$Context)

    # Use AST parsing to better understand help command structure
    $domain = $null
    $action = $null

    if ($Context -and $Context.FreeText.Count -ge 1) {
        # Try AST parsing first for better command understanding
        try {
            $helpQuery = $Context.FreeText -join ' '
            if (Get-Command ConvertTo-PmcCommandAst -ErrorAction SilentlyContinue) {
                $ast = ConvertTo-PmcCommandAst -CommandText $helpQuery
                if ($ast.Domain) { $domain = $ast.Domain.ToLower() }
                if ($ast.Action) { $action = $ast.Action.ToLower() }
            }
        } catch {
            Write-PmcDebug -Level 2 -Category 'Help' -Message "AST parsing failed for help query, using fallback"
        }

        # Fallback to simple token parsing
        if (-not $domain -and $Context.FreeText.Count -ge 1) { $domain = $Context.FreeText[0].ToLower() }
        if (-not $action -and $Context.FreeText.Count -ge 2) { $action = $Context.FreeText[1].ToLower() }
    }

    if (-not $domain -or -not $action) {
        Write-PmcStyled -Style 'Warning' -Text "Usage: help command <domain> <action> (e.g., help command task add)"
        return
    }
    if (-not $Script:PmcCommandMap.ContainsKey($domain)) { Write-PmcStyled -Style 'Error' -Text ("Unknown domain '{0}'" -f $domain); return }
    if (-not $Script:PmcCommandMap[$domain].ContainsKey($action)) { Write-PmcStyled -Style 'Error' -Text ("Unknown action '{0}' for domain '{1}'" -f $action,$domain); return }

    $title = "HELP — {0} {1}" -f $domain.ToUpper(), $action
    Write-PmcStyled -Style 'Title' -Text ("\n{0}" -f $title)
    Write-PmcStyled -Style 'Border' -Text ("─" * 80)

    # Description (if available)
    $key = "$domain $action"
    $desc = ''
    try { if ($Script:PmcCommandMeta.ContainsKey($key)) { $desc = [string]$Script:PmcCommandMeta[$key].Desc } } catch {}
    if ($desc) { Write-PmcStyled -Style 'Info' -Text ("  {0}" -f $desc) }

    # Schema
    $schema = Get-PmcSchema -Domain $domain -Action $action
    if (-not $schema -or @($schema).Count -eq 0) { Write-PmcStyled -Style 'Muted' -Text '  (no arguments)'; return }

    Write-PmcStyled -Style 'Header' -Text "\n  Args:"
    foreach ($def in $schema) {
        $name = [string]$def['Name']
        $pref = $(if ($def['Prefix']) { [string]$def['Prefix'] } else { '' })
        $type = $(if ($def['Type']) { [string]$def['Type'] } else { 'Text' })
        $req  = $(if ($def['Required']) { 'required' } else { '' })
        $help = $(if ($def['Description']) { [string]$def['Description'] } else { '' })
        $left = $(if ($pref) { "$pref$name" } else { $name }).PadRight(18).Substring(0,18)
        $right = ("[{0}] {1}" -f $type,$help)
        if ($req) { $right = "$right (required)" }
        Write-Host ("  {0} {1}" -f $left, $right)
    }

    # Usage hint
    $usage = "{0} {1}" -f $domain, $action
    foreach ($def in $schema) {
        $token = $(if ($def['Prefix']) { "" + [string]$def['Prefix'] + [string]$def['Name'] } elseif ($def['Name'] -match '^(?i)text$') { '<text>' } else { "<" + [string]$def['Name'] + ">" })
        if (-not $def['Required']) { $token = "[$token]" }
        $usage += " $token"
    }
    Write-PmcStyled -Style 'Border' -Text ("\n{0}" -f $usage)
}

# Dedicated query help (static)
function Show-PmcHelpQuery {
    param([PmcCommandContext]$Context)
    Write-PmcStyled -Style 'Title' -Text "\nQUERY LANGUAGE"
    Write-PmcStyled -Style 'Border' -Text ("─" * 80)

    # Try to load reference doc and print key sections
    $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    $ref = Join-Path $root 'PMC_QUERY_LANGUAGE_REFERENCE.md'
    if (-not (Test-Path $ref)) { Write-PmcStyled -Style 'Warning' -Text 'Reference file not found.'; return }
    $content = Get-Content $ref -Raw

    # Extract top sections by headings
    $sections = @()
    $pattern = "(?ms)^##\s+(.+?)\n(.*?)(?=\n##\s+|\Z)"
    $matches = [regex]::Matches($content, $pattern)
    foreach ($m in $matches) {
        $sections += @{ Title=$m.Groups[1].Value.Trim(); Body=$m.Groups[2].Value.Trim() }
    }

    $wanted = @('Overview','Core Syntax','Filters','Operators','Grouping & Sorting','Views','Examples')
    foreach ($w in $wanted) {
        $sec = $sections | Where-Object { $_.Title -like "$w*" } | Select-Object -First 1
        if ($sec) {
            Write-PmcStyled -Style 'Header' -Text ("\n  {0}" -f $sec.Title)
            $lines = ($sec.Body -split "`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -First 12
            foreach ($ln in $lines) { Write-Host ("    {0}" -f $ln.TrimDoEnd()) }
        }
    }
    Write-PmcStyled -Style 'Muted' -Text ("\nSee: {0}" -f $ref)
    Write-PmcStyled -Style 'Info' -Text "\nRelated help:"
    Write-Host "  help guide query      — Guided tour of filters and views"
    Write-Host "  help examples query   — Practical, copyable query examples"
}

# Search across commands and help content
function Show-PmcHelpSearch {
    param([PmcCommandContext]$Context)

    # Use AST parsing to better understand search query
    $q = ''
    if ($Context -and $Context.FreeText -and $Context.FreeText.Count -gt 0) {
        # Try AST parsing first for complex queries
        try {
            $searchQuery = $Context.FreeText -join ' '
            if (Get-Command ConvertTo-PmcCommandAst -ErrorAction SilentlyContinue) {
                $ast = ConvertTo-PmcCommandAst -CommandText $searchQuery
                # For search, we want the full free text, not just structured parts
                $q = $searchQuery
            } else {
                $q = $searchQuery
            }
        } catch {
            $q = ($Context.FreeText[0] + '')
        }
    }

    $q = $q.Trim()
    if (-not $q) {
        Write-PmcStyled -Style 'Warning' -Text "Usage: help search <text> (e.g., help search 'task add')"
        return
    }

    $rows = @()
    # Search domain/actions with descriptions
    foreach ($domain in ($Script:PmcCommandMap.Keys)) {
        foreach ($action in ($Script:PmcCommandMap[$domain].Keys)) {
            $cmd = ("{0} {1}" -f $domain, $action)
            $desc = ''
            try { if ($Script:PmcCommandMeta.ContainsKey($cmd)) { $desc = [string]$Script:PmcCommandMeta[$cmd].Desc } } catch {}
            $rows += [pscustomobject]@{ Type='Command'; Text=$cmd; Description=$desc; Source=$domain }
        }
    }
    # Search curated help content
    try {
        if ($Script:PmcHelpContent) {
            foreach ($kv in $Script:PmcHelpContent.GetEnumerator()) {
                $cat = [string]$kv.Key
                foreach ($it in $kv.Value.Items) {
                    $text = $(if ($it.PSObject.Properties['Command']) { [string]$it.Command } elseif ($it.PSObject.Properties['Item']) { [string]$it.Item } else { '' })
                    $desc = $(if ($it.PSObject.Properties['Description']) { [string]$it.Description } else { '' })
                    if ($text -or $desc) { $rows += [pscustomobject]@{ Type='Guide'; Text=$text; Description=$desc; Source=$cat } }
                }
            }
        }
    } catch {}

    # Parse quoted phrases and remaining terms
    $phraseRegex = '"([^"]+)"'
    $phrases = @()
    $m = [regex]::Matches($q, $phraseRegex)
    foreach ($mm in $m) { $phrases += ($mm.Groups[1].Value + '').ToLowerInvariant() }
    $rest = ([regex]::Replace($q, $phraseRegex, ' ')).Trim()
    $terms = @()
    foreach ($t in ($rest -split '\s+')) { if (-not [string]::IsNullOrWhiteSpace($t)) { $terms += $t.ToLowerInvariant() } }
    if ($phrases.Count -eq 0 -and $terms.Count -eq 0) { $terms = @($q.ToLowerInvariant()) }

    $normalizedQuery = $q.ToLowerInvariant()

    # Scoring:
    # - Exact full command match: +10 (commands only)
    # - Phrase match in Text: +6 if startswith; +5 if contains; +4 if in Description
    # - Term match: Text startswith +3; word-boundary +3; contains +2; Description/Source +1
    # - Commands get +1 baseline
    $scored = @()
    foreach ($row in $rows) {
        if ($null -eq $row) { continue }
        $text = ([string]$row.Text)
        $desc = ([string]$row.Description)
        $src  = ([string]$row.Source)
        $lt = $text.ToLowerInvariant()
        $ld = $desc.ToLowerInvariant()
        $ls = $src.ToLowerInvariant()
        $score = 0
        $ok = $true

        # Require each phrase to appear somewhere
        foreach ($p in $phrases) {
            $phraseHit = $false
            if ($lt.StartsWith($p)) { $score += 6; $phraseHit = $true }
            elseif ($lt.Contains($p)) { $score += 5; $phraseHit = $true }
            elseif ($ld.Contains($p)) { $score += 4; $phraseHit = $true }
            elseif ($ls.Contains($p)) { $score += 3; $phraseHit = $true }
            if (-not $phraseHit) { $ok = $false; break }
        }
        if (-not $ok) { continue }

        # Terms (AND logic)
        foreach ($term in $terms) {
            $termScore = 0
            if ($lt -eq $term) { $termScore = [Math]::Max($termScore, 4) }
            if ($lt.StartsWith($term)) { $termScore = [Math]::Max($termScore, 3) }
            $wb = "\\b" + [regex]::Escape($term) + "\\b"
            if ([regex]::IsMatch($lt, $wb)) { $termScore = [Math]::Max($termScore, 3) }
            if ($lt.Contains($term)) { $termScore = [Math]::Max($termScore, 2) }
            if ($ld.Contains($term)) { $termScore = [Math]::Max($termScore, 1) }
            if ($ls.Contains($term)) { $termScore = [Math]::Max($termScore, 1) }
            if ($termScore -eq 0) { $ok = $false; break }
            $score += $termScore
        }
        if (-not $ok) { continue }

        # Bonuses
        if ($row.Type -eq 'Command') {
            $score += 1
            if ($lt -eq $normalizedQuery) { $score += 10 }
            elseif ($phrases.Count -eq 1 -and $lt -eq $phrases[0]) { $score += 8 }
        }

        $scored += [pscustomobject]@{ Score=$score; Type=$row.Type; Text=$text; Description=$desc; Source=$src }
    }

    $matches = @($scored | Sort-Object -Property @{Expression='Score';Descending=$true}, @{Expression='Type';Descending=$false}, @{Expression='Text';Descending=$false})

    if ($matches.Count -eq 0) {
        Write-PmcStyled -Style 'Muted' -Text ("No help results for: '{0}'" -f $q)
        return
    }

    $cols = @{
        Type=@{ Header='Type'; Width=8; Alignment='Left' }
        Text=@{ Header='Text'; Width=32; Alignment='Left' }
        Description=@{ Header='Description'; Width=0; Alignment='Left' }
        Source=@{ Header='Source'; Width=14; Alignment='Left' }
    }

    Show-PmcDataGrid -Domains @('help-search') -Columns $cols -Data $matches -Title ("Help Search — {0}" -f $q) -Interactive -OnSelectCallback {
        param($item)
        try { if ($item -and $item.PSObject.Properties['Text'] -and $item.Text) { Pmc-InsertAtCursor (([string]$item.Text) + ' ') } } catch {}
    }
}

# Interactive examples for common tasks and query/kanban
function Show-PmcHelpExamples {
    param([PmcCommandContext]$Context)
    $topic = $(if ($Context -and $Context.FreeText.Count -gt 0) { ($Context.FreeText[0] + '').ToLower() } else { '' })

    switch ($topic) {
        'query' {
            $rows = @(
                [pscustomobject]@{ Category='🎯 PRIORITY'; Command='q tasks p1'; Description='Only high priority tasks' }
                [pscustomobject]@{ Category='🎯 PRIORITY'; Command='q tasks p<=2'; Description='High and medium priority' }
                [pscustomobject]@{ Category='📅 DATE'; Command='q tasks due:today'; Description='Due today' }
                [pscustomobject]@{ Category='📅 DATE'; Command='q tasks overdue'; Description='Past due' }
                [pscustomobject]@{ Category='🏷️ PROJECT'; Command='q tasks @work'; Description='Project filter' }
                [pscustomobject]@{ Category='🏷️ TAG'; Command='q tasks #urgent'; Description='Tagged urgent' }
                [pscustomobject]@{ Category='📊 VIEW'; Command='q tasks group:status'; Description='Kanban by status' }
                [pscustomobject]@{ Category='⚡ COMBO'; Command='q tasks p<=2 @work due>=today'; Description='Combined filters' }
            )

            $cols = @{
                Category=@{ Header='Category'; Width=14; Alignment='Left' }
                Command=@{ Header='Command'; Width=28; Alignment='Left' }
                Description=@{ Header='Description'; Width=0; Alignment='Left' }
            }
            Show-PmcDataGrid -Domains @('help-examples') -Columns $cols -Data $rows -Title 'Query Language Examples' -Interactive
            return
        }
        'kanban' {
            $rows = @(
                [pscustomobject]@{ Category='🎯 ACCESS'; Command='q tasks group:status'; Description='Auto-kanban by status' }
                [pscustomobject]@{ Category='🎯 ACCESS'; Command='q tasks view:kanban'; Description='Force kanban view' }
                [pscustomobject]@{ Category='🎮 KEYS'; Command='←/→'; Description='Move between lanes' }
                [pscustomobject]@{ Category='🎮 KEYS'; Command='↑/↓'; Description='Move between cards' }
                [pscustomobject]@{ Category='🎮 KEYS'; Command='Space'; Description='Start/complete move' }
                [pscustomobject]@{ Category='🎮 KEYS'; Command='Enter'; Description='Open details/editor' }
                [pscustomobject]@{ Category='🎮 KEYS'; Command='Esc'; Description='Exit or cancel' }
            )
            $cols = @{
                Category=@{ Header='Category'; Width=14; Alignment='Left' }
                Command=@{ Header='Command/Key'; Width=20; Alignment='Left' }
                Description=@{ Header='Description'; Width=0; Alignment='Left' }
            }
            Show-PmcDataGrid -Domains @('help-examples') -Columns $cols -Data $rows -Title 'Kanban Workflow Examples' -Interactive
            return
        }
        default {
            $rows = @(
                [pscustomobject]@{ Category='🚀 QUICK START'; Command='today'; Description='Tasks due today' }
                [pscustomobject]@{ Category='🚀 QUICK START'; Command='add "New task" @work p1 due:today'; Description='Add new task' }
                [pscustomobject]@{ Category='🔎 QUERY'; Command='help examples query'; Description='See query examples' }
                [pscustomobject]@{ Category='📋 KANBAN'; Command='help examples kanban'; Description='See kanban examples' }
            )
            $cols = @{
                Category=@{ Header='Category'; Width=16; Alignment='Left' }
                Command=@{ Header='Command'; Width=32; Alignment='Left' }
                Description=@{ Header='Description'; Width=0; Alignment='Left' }
            }
            Show-PmcDataGrid -Domains @('help-examples') -Columns $cols -Data $rows -Title 'PMC Examples — Quick Start' -Interactive
        }
    }
}

# Focused guides for important features
function Show-PmcHelpGuide {
    param([PmcCommandContext]$Context)
    $topic = $(if ($Context -and $Context.FreeText.Count -gt 0) { ($Context.FreeText[0] + '').ToLower() } else { '' })

    switch ($topic) {
        'query' {
            $rows = @(
                [pscustomobject]@{ Section='🚀 BASICS'; Item='q tasks'; Description='Show all tasks' }
                [pscustomobject]@{ Section='🎯 PRIORITY'; Item='q tasks p1'; Description='High priority' }
                [pscustomobject]@{ Section='📅 DATES'; Item='q tasks due:today'; Description='Due today' }
                [pscustomobject]@{ Section='🏷️ PROJECT'; Item='q tasks @work'; Description='Project filter' }
                [pscustomobject]@{ Section='📊 DISPLAY'; Item='q tasks cols:id,text,due'; Description='Choose columns' }
                [pscustomobject]@{ Section='📊 VIEWS'; Item='q tasks group:status'; Description='Kanban by status' }
                [pscustomobject]@{ Section='🔗 COMBINE'; Item='q tasks p<=2 @work due>today'; Description='Multiple filters' }
                [pscustomobject]@{ Section='💡 TIPS'; Item='Tab completion'; Description='Complete filters and values' }
            )
            $cols = @{
                Section=@{ Header='Category'; Width=14; Alignment='Left' }
                Item=@{ Header='Filter/Command'; Width=28; Alignment='Left' }
                Description=@{ Header='Description'; Width=0; Alignment='Left' }
            }
            Show-PmcDataGrid -Domains @('help-guide') -Columns $cols -Data $rows -Title 'Query Language Guide' -Interactive
            return
        }
        'kanban' {
            $rows = @(
                [pscustomobject]@{ Category='🎯 ACCESS'; Item='q tasks group:status'; Description='Auto-enable kanban' }
                [pscustomobject]@{ Category='🎮 NAV'; Item='←/→, ↑/↓'; Description='Move lanes/cards' }
                [pscustomobject]@{ Category='🎮 NAV'; Item='Space'; Description='Start/complete move' }
                [pscustomobject]@{ Category='🎮 NAV'; Item='Enter'; Description='Open/edit task' }
                [pscustomobject]@{ Category='🎮 NAV'; Item='Esc'; Description='Exit/cancel' }
                [pscustomobject]@{ Category='🎨 VISUAL'; Item='🔴🟡🟢'; Description='Priority indicators' }
                [pscustomobject]@{ Category='🎨 VISUAL'; Item='[WARN]️📅'; Description='Due indicators' }
            )
            $cols = @{
                Category=@{ Header='Category'; Width=14; Alignment='Left' }
                Item=@{ Header='Command/Key'; Width=22; Alignment='Left' }
                Description=@{ Header='Description'; Width=0; Alignment='Left' }
            }
            Show-PmcDataGrid -Domains @('help-guide') -Columns $cols -Data $rows -Title 'Kanban View Guide' -Interactive
            return
        }
        default {
            $rows = @(
                [pscustomobject]@{ Topic='help guide query'; Description='Query language & filtering guide' }
                [pscustomobject]@{ Topic='help guide kanban'; Description='Kanban navigation and usage' }
                [pscustomobject]@{ Topic='help examples'; Description='Practical, copyable examples' }
            )
            $cols = @{
                Topic=@{ Header='Command'; Width=26; Alignment='Left' }
                Description=@{ Header='Description'; Width=0; Alignment='Left' }
            }
            Show-PmcDataGrid -Domains @('help-guide') -Columns $cols -Data $rows -Title 'PMC Help Guide — Topics' -Interactive
        }
    }
}