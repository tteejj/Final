# PMC Query Language implementation and command processors

Set-StrictMode -Version Latest

function Invoke-PmcQuery {
    param($Context)

    # Handle both string and PmcCommandContext parameters for backward compatibility
    if ($Context -is [string]) {
        $tokens = ConvertTo-PmcTokens $Context
        Write-PmcDebug -Level 1 -Category 'Query' -Message 'Invoke-PmcQuery START (string input)' -Data @{ TokenCount=@($tokens).Count }
    } else {
        Write-PmcDebug -Level 1 -Category 'Query' -Message 'Invoke-PmcQuery START' -Data @{ FreeTextCount=@($Context.FreeText).Count }
        if (-not $Context -or $Context.FreeText.Count -lt 1) {
            Write-PmcStyled -Style 'Warning' -Text "Usage: q <tasks|projects|timelogs> [filters/directives]"
            return
        }
        $tokens = @($Context.FreeText)
    }

    # Try enhanced query engine first (Core/EnhancedQueryEngine.ps1)
    if (Get-Command Invoke-PmcEnhancedQuery -ErrorAction SilentlyContinue) {
        try {
            Write-PmcDebug -Level 2 -Category 'Query' -Message 'Attempting enhanced query execution'
            $result = Invoke-PmcEnhancedQuery -Tokens $tokens
            if ($result -and $result.Success -ne $false) {
                Write-PmcDebug -Level 1 -Category 'Query' -Message 'Enhanced query execution successful'
                return $result
            } else {
                Write-PmcDebug -Level 2 -Category 'Query' -Message 'Enhanced query failed, falling back to legacy'
            }
        } catch {
            Write-PmcDebug -Level 1 -Category 'Query' -Message "Enhanced query error: $_, falling back to legacy"
        }
    }

    # Usage: pmc q <tasks|projects|timelogs> [tokens ...]
    if (-not $tokens -or @($tokens).Count -lt 1) {
        Write-PmcStyled -Style 'Warning' -Text "Usage: q <tasks|projects|timelogs> [filters/directives]"
        return
    }
    $interactive = $false
    # Detect short interactive flag and strip it from tokens
    if ($tokens -contains '-i') {
        $interactive = $true
        $tokens = @($tokens | Where-Object { $_ -ne '-i' })
    }

    # Handle load: alias early
    $loadAlias = $tokens | Where-Object { $_ -match '^(?i)load:(.+)$' } | Select-Object -First 1
    if ($loadAlias) {
        $aliasName = ($loadAlias -replace '^(?i)load:','')
        $loaded = Get-PmcQueryAlias -Name $aliasName
        if ($loaded) { $tokens = @($loaded) } else { Write-PmcStyled -Style 'Error' -Text ("Unknown query alias '{0}'" -f $aliasName); return }
    }
    $domTok = [string]$tokens[0]
    $rest = @($tokens | Select-Object -Skip 1)

    # Normalize domain token to singular
    switch ($domTok.ToLower()) {
        'task' { $domain = 'task' }
        'tasks' { $domain = 'task' }
        'project' { $domain = 'project' }
        'projects' { $domain = 'project' }
        'timelog' { $domain = 'timelog' }
        'timelogs' { $domain = 'timelog' }
        default { Write-PmcStyled -Style 'Error' -Text ("Unknown domain '{0}'. Use tasks|projects|timelogs" -f $domTok); return }
    }

    $spec = [PmcQuerySpec]::new()
    $spec.Domain = $domain
    $spec.RawTokens = $rest

    # Parse directives: cols:, metrics:, sort:, with:, group:, view:
    $colsList = @()
    $metricsList = @()
    $sortList = @()
    $withList = @()
    $groupField = ''
    $textTerms = @()
    $viewType = ''
    foreach ($t in $rest) {
        if ($t -match '^(?i)cols:(.+)$') {
            $list = $matches[1]
            foreach ($c in ($list -split ',')) { $cv = $c.Trim(); if ($cv) { $colsList += $cv } }
        }
        elseif ($t -match '^(?i)metrics:(.+)$') {
            $list = $matches[1]
            foreach ($m in ($list -split ',')) { $mv = $m.Trim(); if ($mv) { $metricsList += $mv } }
        }
        elseif ($t -match '^(?i)sort:(.+)$') {
            $list = $matches[1]
            foreach ($s in ($list -split ',')) {
                $sv = $s.Trim(); if (-not $sv) { continue }
                $dir = 'Asc'; $field = $sv
                if ($sv.EndsWith('+')) { $field = $sv.Substring(0, $sv.Length-1); $dir='Asc' }
                elseif ($sv.EndsWith('-')) { $field = $sv.Substring(0, $sv.Length-1); $dir='Desc' }
                if ($field) { $sortList += @{ Field=$field; Dir=$dir } }
            }
        }
        elseif ($t -match '^(?i)with:(.+)$') {
            $val = $matches[1].ToLower()
            if ($val) { $withList += $val }
        }
        elseif ($t -match '^(?i)group:(.+)$') {
            $groupField = $matches[1]
        }
        elseif ($t -match '^(?i)view:(.+)$') {
            $v = $matches[1].ToLower()
            if ($v -in @('list','kanban')) { $viewType = $v }
        }
        elseif ($t -match '^@(.+)$') { $spec.Filters['project'] = $matches[1] }
        elseif ($t -match '^(?i)overdue$') { $spec.Filters['overdue'] = $true }
        elseif ($t -match '^(?i)due:(.+)$') {
            $dv = $matches[1]
            $spec.Filters['due'] = $dv
        }
        elseif ($t -match '^(?i)due:(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})$') {
            $spec.Filters['due_range'] = @{ Start=$matches[1]; End=$matches[2] }
        }
        elseif ($t -match '^(?i)p:([1-3])\.\.([1-3])$') { $spec.Filters['p_range'] = @{ Min=[int]$matches[1]; Max=[int]$matches[2] } }
        elseif ($t -match '^(?i)status:(pending|done)$') { $spec.Filters['status'] = $matches[1].ToLower() }
        elseif ($t -match '^(?i)archived:(true|false)$') { $spec.Filters['archived'] = ([bool]::Parse($matches[1])) }
        elseif ($t -match '^(?i)date:(.+)$') { $spec.Filters['date'] = $matches[1] }
        elseif ($t -match '^(?i)task:(\d+)$') { $spec.Filters['taskId'] = [int]$matches[1] }
        elseif ($t -match '^(?i)p<=([1-3])$') { $spec.Filters['p_le'] = [int]$matches[1] }
        elseif ($t -match '^(?i)p_le=([1-3])$') { $spec.Filters['p_le'] = [int]$matches[1] }
        elseif ($t -match '^(?i)p>=([1-3])$') { $spec.Filters['p_ge'] = [int]$matches[1] }
        elseif ($t -match '^(?i)p_ge=([1-3])$') { $spec.Filters['p_ge'] = [int]$matches[1] }
        elseif ($t -match '^(?i)p>([1-3])$') { $spec.Filters['p_gt'] = [int]$matches[1] }
        elseif ($t -match '^(?i)p_gt=([1-3])$') { $spec.Filters['p_gt'] = [int]$matches[1] }
        elseif ($t -match '^(?i)p<([1-3])$') { $spec.Filters['p_lt'] = [int]$matches[1] }
        elseif ($t -match '^(?i)p_lt=([1-3])$') { $spec.Filters['p_lt'] = [int]$matches[1] }
        elseif ($t -match '^(?i)p([1-3])$') { $spec.Filters['p_eq'] = [int]$matches[1] }
        elseif ($t -match '^(?i)due>(.+)$') { $spec.Filters['due_gt'] = $matches[1] }
        elseif ($t -match '^(?i)due<(.+)$') { $spec.Filters['due_lt'] = $matches[1] }
        elseif ($t -match '^(?i)due>=(.+)$') { $spec.Filters['due_ge'] = $matches[1] }
        elseif ($t -match '^(?i)due<=(.+)$') { $spec.Filters['due_le'] = $matches[1] }
        elseif ($t -match '^#(.+)$') {
            if (-not $spec.Filters.ContainsKey('tags_in')) { $spec.Filters['tags_in'] = @() }
            $spec.Filters['tags_in'] += $matches[1]
        }
        elseif ($t -match '^-(?:tag:)?(.+)$') {
            if (-not $spec.Filters.ContainsKey('tags_out')) { $spec.Filters['tags_out'] = @() }
            $spec.Filters['tags_out'] += $matches[1]
        }
        elseif ($t -match '^"(.+)"$') { $textTerms += $matches[1] }
        else { if ($t) { $textTerms += $t } }
    }
    if (@($colsList).Count -gt 0) { $spec.Columns = $colsList }
    if (@($metricsList).Count -gt 0) { $spec.Metrics = $metricsList }
    if (@($sortList).Count -gt 0) { $spec.Sort = $sortList }
    if (@($withList).Count -gt 0) { $spec.With = $withList }
    if ($groupField) { $spec.Group = $groupField }
    if (@($textTerms).Count -gt 0) { $spec.Filters['text'] = ($textTerms -join ' ') }
    if ($viewType) { $spec.View = $viewType }

    # Smart defaults: Auto-sort by due date if filtering by due
    if ($spec.Filters.ContainsKey('due') -and @($spec.Sort).Count -eq 0) {
        $spec.Sort = @(@{ Field='due'; Dir='Asc' })
        Write-PmcDebug -Level 2 -Category 'Query' -Message 'Auto-sorting by due date'
    }

    # Smart defaults: Auto-sort by priority if filtering by priority
    if (($spec.Filters.ContainsKey('p_le') -or $spec.Filters.ContainsKey('p_eq') -or $spec.Filters.ContainsKey('p_range')) -and @($spec.Sort).Count -eq 0) {
        $spec.Sort = @(@{ Field='priority'; Dir='Asc' })
        Write-PmcDebug -Level 2 -Category 'Query' -Message 'Auto-sorting by priority'
    }

    # Smart defaults: Enable kanban view if grouping by status
    if ($spec.Group -eq 'status' -and $spec.View -eq 'list') {
        $spec.View = 'kanban'
        Write-PmcDebug -Level 2 -Category 'Query' -Message 'Auto-switching to kanban view for status grouping'
    }

    # Validate filter values
    $priorityFilters = @('p_le', 'p_ge', 'p_gt', 'p_lt', 'p_eq')
    foreach ($pf in $priorityFilters) {
        if ($spec.Filters.ContainsKey($pf)) {
            $val = $spec.Filters[$pf]
            if ($val -lt 1 -or $val -gt 3) {
                Write-PmcStyled -Style 'Warning' -Text "Warning: Priority value '$val' should be between 1-3"
            }
        }
    }

    # Validate date filters
    $dateFilters = @('due', 'due_gt', 'due_lt', 'due_ge', 'due_le')
    foreach ($df in $dateFilters) {
        if ($spec.Filters.ContainsKey($df)) {
            $dateTok = $spec.Filters[$df]
            $isValid = $false
            try {
                if ($dateTok -match '^(?i)today$') { $isValid = $true }
                elseif ($dateTok -match '^\d{4}-\d{2}-\d{2}$') {
                    try { [datetime]$dateTok | Out-Null; $isValid = $true } catch { $isValid = $false }
                }
                else {
                    $schemas = Get-PmcFieldSchemasForDomain -Domain 'task'
                    if ($schemas.ContainsKey('due') -and $schemas.due.ContainsKey('Normalize')) {
                        $normalizedDate = & $schemas.due.Normalize $dateTok
                        if ($normalizedDate) { $isValid = $true }
                    }
                }
            } catch { $isValid = $false }

            if (-not $isValid) {
                Write-PmcStyled -Style 'Warning' -Text "Warning: Invalid date format '$dateTok'. Use YYYY-MM-DD, 'today', or relative dates like '+1d'"
            }
        }
    }

    # Build Columns hashtable if cols provided; else use defaults
    $columns = @{}
    if (@($spec.Columns).Count -gt 0) {
        $fs = Get-PmcFieldSchemasForDomain -Domain $spec.Domain
        foreach ($name in $spec.Columns) {
            if (-not $fs.ContainsKey($name)) { Write-PmcStyled -Style 'Warning' -Text ("Unknown column '{0}' for {1}" -f $name, $spec.Domain); continue }
            $sch = $fs[$name]
            $w = $(if ($sch.ContainsKey('DefaultWidth')) { [int]$sch.DefaultWidth } else { 12 })
            $al = 'Left'
            switch ($name) { 'id' { $al='Right' } 'priority' { $al='Center' } 'due' { $al='Center' } default { } }
            $columns[$name] = @{ Header = ($name); Width = $w; Alignment = $al }
        }
    } else {
        # Default columns based on domain
        if ($spec.Domain -eq 'task') {
            $columns = @{
                'id' = @{ Header = 'ID'; Width = 4; Alignment = 'Right' }
                'text' = @{ Header = 'Task'; Width = 0; Alignment = 'Left' }
                'priority' = @{ Header = 'pri'; Width = 3; Alignment = 'Center' }
                'due' = @{ Header = 'Due'; Width = 12; Alignment = 'Center' }
                'status' = @{ Header = 'Status'; Width = 10; Alignment = 'Left' }
            }
        } elseif ($spec.Domain -eq 'project') {
            $columns = @{
                'name' = @{ Header = 'Name'; Width = 0; Alignment = 'Left' }
                'description' = @{ Header = 'Description'; Width = 0; Alignment = 'Left' }
            }
        } elseif ($spec.Domain -eq 'timelog') {
            $columns = @{
                'date' = @{ Header = 'Date'; Width = 12; Alignment = 'Center' }
                'project' = @{ Header = 'Project'; Width = 15; Alignment = 'Left' }
                'notes' = @{ Header = 'Notes'; Width = 0; Alignment = 'Left' }
            }
        }
    }

    # Validate metrics before evaluating
    if (@($spec.Metrics).Count -gt 0) {
        $validMetrics = Get-PmcMetricsForDomain -Domain $spec.Domain
        $invalidMetrics = @($spec.Metrics | Where-Object { -not $validMetrics.ContainsKey($_) })
        if (@($invalidMetrics).Count -gt 0) {
            Write-PmcStyled -Style 'Warning' -Text ("Unknown metrics for {0}: {1}" -f $spec.Domain, ($invalidMetrics -join ', '))
            Write-PmcStyled -Style 'Muted' -Text ("Available metrics: {0}" -f ($validMetrics.Keys -join ', '))
        }
    }

    # Evaluate
    try {
        $result = Evaluate-PmcQuery -Spec $spec
        Write-PmcDebug -Level 2 -Category 'Query' -Message 'Query evaluation completed' -Data @{ RowCount=@($result.Rows).Count }
    } catch {
        Write-PmcStyled -Style 'Error' -Text "Query evaluation failed: $($_.Exception.Message)"
        Write-PmcDebug -Level 1 -Category 'Query' -Message 'Query evaluation failed' -Data @{ Error=$_.Exception.Message }
        return
    }

    # Append to history
    Write-PmcDebug -Level 2 -Category 'Query' -Message 'Adding to query history'
    try { Add-PmcQueryHistory -Args ($Context.FreeText -join ' ') } catch {}

    # If metrics requested and not in columns, append them to columns end
    Write-PmcDebug -Level 2 -Category 'Query' -Message 'Processing metrics' -Data @{ MetricsCount=@($spec.Metrics).Count }
    if (@($spec.Metrics).Count -gt 0) {
        foreach ($m in $spec.Metrics) {
            if (-not $columns.ContainsKey($m)) {
                $columns[$m] = @{ Header = $m; Width = 10; Alignment = 'Right' }
            }
        }
    }

    # Show custom grid with evaluated rows
    Write-PmcDebug -Level 2 -Category "Query" -Message "About to call Show-PmcCustomGrid with $(@($result.Rows).Count) rows"
    Write-PmcDebug -Level 2 -Category 'Query' -Message 'Calling Show-PmcCustomGrid' -Data @{ Domain=$spec.Domain; RowCount=@($result.Rows).Count; ColumnCount=@($columns.Keys).Count }
    try {
        if ($interactive) {
            Show-PmcCustomGrid -Domain $spec.Domain -Columns $columns -Data $result.Rows -Group $spec.Group -View $spec.View -Interactive
        } else {
            Show-PmcCustomGrid -Domain $spec.Domain -Columns $columns -Data $result.Rows -Group $spec.Group -View $spec.View
        }
        Write-PmcDebug -Level 2 -Category "Query" -Message "Show-PmcCustomGrid completed successfully"
    } catch {
        Write-PmcDebug -Level 1 -Category "Query" -Message "Show-PmcCustomGrid failed: $($_.Exception.Message)"
        Write-PmcDebug -Level 1 -Category 'Query' -Message 'Show-PmcCustomGrid failed' -Data @{ Error=$_.Exception.Message }
    }
    Write-PmcDebug -Level 2 -Category 'Query' -Message 'Show-PmcCustomGrid completed'

    # Save alias if requested
    $saveAlias = $rest | Where-Object { $_ -match '^(?i)save:(.+)$' } | Select-Object -First 1
    if ($saveAlias) {
        $aliasName = ($saveAlias -replace '^(?i)save:','')
        try { Set-PmcQueryAlias -Name $aliasName -Args ($Context.FreeText -join ' ') } catch {}
    }
}

# Simple completer scaffold for q (progressively enhance later)
function Register-PmcQueryCompleter {
    try {
        Register-ArgumentCompleter -CommandName q -ScriptBlock {
            param($wordToComplete, $commandAst, $cursorPosition)

            function New-CR([string]$text,[string]$tooltip=$text) { [System.Management.Automation.CompletionResult]::new($text,$text,'ParameterValue',$tooltip) }

            $line = $commandAst.ToString()
            $tokens = [regex]::Split($line.Trim(), '\s+')
            # tokens[0] = 'q'
            if ($tokens.Count -le 1) { return @( New-CR 'tasks' ; New-CR 'projects' ; New-CR 'timelogs' ) }

            # Domain candidates (second token)
            if ($tokens.Count -eq 2) {
                $doms = @('tasks','projects','timelogs')
                return @($doms | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { New-CR $_ })
            }

            # Determine domain
            $domTok = $tokens[1].ToLower()
            $domain = switch ($domTok) { 'tasks' {'task'} 'task' {'task'} 'projects' {'project'} 'project' {'project'} 'timelogs' {'timelog'} 'timelog' {'timelog'} default { '' } }

            # Completers for prefixes
            $results = @()

            # Directives starter
            $directiveStarters = @('with:','metrics:','cols:','sort:','group:','view:','limit:','offset:')
            foreach ($d in $directiveStarters) { if ($d -like "$wordToComplete*") { $results += (New-CR $d) } }

            # Helper for comma-separated lists
            function Complete-CommaList([string]$word,[string]$prefix,[string[]]$candidates) {
                $out = @()
                if (-not ($word -like "$prefix*")) { return $out }
                $tail = $word.Substring($prefix.Length)
                $parts = @($tail -split ',')
                if ($parts.Count -eq 0) { $parts = @('') }
                $existing = @()
                if ($parts.Count -gt 1) { $existing = $parts[0..($parts.Count-2)] }
                $partial = $parts[$parts.Count-1]
                foreach ($cand in $candidates) {
                    if ($cand -like "$partial*") {
                        $newList = @($existing + $cand) -join ','
                        $out += (New-CR ("$prefix$newList"))
                    }
                }
                return $out
            }

            # with: completions
            if ($wordToComplete -like 'with:*') {
                $rels = @()
                switch ($domain) {
                    'task'    { $rels = @('project','time') }
                    'project' { $rels = @('tasks','time') }
                    'timelog' { $rels = @('project','task') }
                    default { $rels = @() }
                }
                $results += Complete-CommaList -word $wordToComplete -prefix 'with:' -candidates $rels
                return $results
            }

            # metrics: completions
            if ($wordToComplete -like 'metrics:*') {
                $met = Get-PmcMetricsForDomain -Domain $domain
                $results += Complete-CommaList -word $wordToComplete -prefix 'metrics:' -candidates (@($met.Keys))
                return $results
            }

            # cols: completions
            if ($wordToComplete -like 'cols:*') {
                $fs = Get-PmcFieldSchemasForDomain -Domain $domain
                $all = @($fs.Keys)
                $met = Get-PmcMetricsForDomain -Domain $domain
                $all += @($met.Keys)
                $results += Complete-CommaList -word $wordToComplete -prefix 'cols:' -candidates $all
                return $results
            }

            # sort: completions
            if ($wordToComplete -like 'sort:*') {
                $fs = Get-PmcFieldSchemasForDomain -Domain $domain
                $items = @()
                foreach ($k in $fs.Keys) { $items += @("$k+","$k-") }
                $met = Get-PmcMetricsForDomain -Domain $domain
                foreach ($k in $met.Keys) { $items += @("$k+","$k-") }
                $results += Complete-CommaList -word $wordToComplete -prefix 'sort:' -candidates $items
                return $results
            }

            # group: completions (include relation-derived if with:project present)
            if ($wordToComplete -like 'group:*') {
                $fs = Get-PmcFieldSchemasForDomain -Domain $domain
                foreach ($k in $fs.Keys) { $txt = "group:$k"; if ($txt -like "$wordToComplete*") { $results += (New-CR $txt) } }
                $hasWithProject = ($tokens -match '^with:project(,|$)').Count -gt 0
                if ($hasWithProject) { foreach ($k in @('project_name')) { $txt = "group:$k"; if ($txt -like "$wordToComplete*") { $results += (New-CR $txt) } } }
                return $results
            }

            # view: completions
            if ($wordToComplete -like 'view:*') {
                foreach ($v in @('list','kanban')) { $txt = "view:$v"; if ($txt -like "$wordToComplete*") { $results += (New-CR $txt) } }
                return $results
            }

            # @project completion
            if ($wordToComplete -like '@*') {
                try {
                    $data = Get-PmcDataAlias
                    $projects = @($data.projects | ForEach-Object { try { [string]$_.name } catch { $null } } | Where-Object { $_ })
                    foreach ($p in $projects) { $txt = "@$p"; if ($txt -like "$wordToComplete*") { $results += (New-CR $txt) } }
                } catch {}
                return $results
            }

            # priority suggestions
            foreach ($p in @('p1','p2','p3','p<=1','p<=2','p<=3','p:1..2','p:2..3')) { if ($p -like "$wordToComplete*") { $results += (New-CR $p) } }

            # due suggestions
            foreach ($d in @('due:today','due:tomorrow','due:+7','date:today','date:tomorrow')) { if ($d -like "$wordToComplete*") { $results += (New-CR $d) } }

            # status / archived starters
            foreach ($s in @('status:pending','status:done','archived:true','archived:false','task:')) { if ($s -like "$wordToComplete*") { $results += (New-CR $s) } }

            # tags suggestion starter
            if ($wordToComplete -eq '#' -or $wordToComplete -like '#*' -or $wordToComplete -like '-tag:*') {
                try {
                    $data = Get-PmcDataAlias
                    $tags = @()
                    foreach ($t in @($data.tasks)) { try { if ($t -and $t.PSObject.Properties['tags']) { $tags += @($t.tags) } } catch {} }
                    $tags = @($tags | Where-Object { $_ } | Select-Object -Unique | Sort-Object)
                    foreach ($tg in $tags) {
                        $cand1 = "#$tg"; if ($cand1 -like "$wordToComplete*") { $results += (New-CR $cand1) }
                        $cand2 = "-tag:$tg"; if ($cand2 -like "$wordToComplete*") { $results += (New-CR $cand2) }
                    }
                } catch {}
                return $results
            }

            # Default: show directive starters and a few filter hints
            $base = @('with:','metrics:','cols:','sort:','group:','@','p1','p2','p3','due:today','#')
            foreach ($b in $base) { if ($b -like "$wordToComplete*") { $results += (New-CR $b) } }
            return $results
        } | Out-Null
    } catch { }
}

# Register on import
Register-PmcQueryCompleter

# Query alias/history helpers
function Get-PmcQueryStoreDir {
    try { $root = Get-PmcRootPath } catch { $root = (Get-Location).Path }
    $dir = Join-Path $root '.pmc'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-PmcQueryAliasPath { param([string]$Name)
    $dir = Get-PmcQueryStoreDir
    return (Join-Path $dir 'query_aliases.json')
}

function Get-PmcQueryHistoryPath {
    $dir = Get-PmcQueryStoreDir
    return (Join-Path $dir 'query_history.log')
}

function Get-PmcQueryAlias { param([string]$Name)
    $path = Get-PmcQueryAliasPath -Name $Name
    if (-not (Test-Path $path)) { return $null }
    try {
        $json = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json.PSObject.Properties[$Name]) { return @([string]$json.$Name) }
    } catch {}
    return $null
}

function Set-PmcQueryAlias { param([string]$Name,[string]$Args)
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $path = Get-PmcQueryAliasPath -Name $Name
    $map = @{}
    if (Test-Path $path) { try { $map = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $map=@{} } }
    $map[$Name] = $Args
    try { ($map | ConvertTo-Json -Depth 5) | Set-Content -Path $path -Encoding UTF8 } catch {}
}

function Add-PmcQueryHistory { param([string]$Args)
    $path = Get-PmcQueryHistoryPath
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | q $Args"
    try { Add-Content -Path $path -Value $line -Encoding UTF8 } catch {}
}

function Get-PmcQueryHistory { param([int]$Last = 10)
    $path = Get-PmcQueryHistoryPath
    if (-not (Test-Path $path)) { return @() }
    try {
        $lines = Get-Content -Path $path -Encoding UTF8 -ErrorAction SilentlyContinue
        $queries = @()
        foreach ($line in ($lines | Select-Object -Last $Last)) {
            if ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| q (.+)$') {
                $queries += $matches[1]
            }
        }
        return $queries
    } catch { return @() }
}

#Export-ModuleMember -Function Invoke-PmcQuery, Register-PmcQueryCompleter, Get-PmcQueryStoreDir, Get-PmcQueryAliasPath, Get-PmcQueryHistoryPath, Get-PmcQueryAlias, Set-PmcQueryAlias, Add-PmcQueryHistory, Get-PmcQueryHistory