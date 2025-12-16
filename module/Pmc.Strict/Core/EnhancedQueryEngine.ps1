# PMC Enhanced Query Engine - Optimized query parsing and execution
# Implements Phase 3 query language improvements

Set-StrictMode -Version Latest

# Enhanced query specification with validation and optimization
class PmcEnhancedQuerySpec {
    [string] $Domain
    [string[]] $RawTokens = @()
    [hashtable] $Filters = @{}
    [hashtable] $Directives = @{}
    [hashtable] $Metadata = @{}
    [bool] $IsOptimized = $false
    [string[]] $ValidationErrors = @()
    [datetime] $ParseTime = [datetime]::Now

    # Query optimization hints
    [bool] $UseIndex = $false
    [string[]] $IndexFields = @()
    [int] $EstimatedRows = -1
    [string] $OptimizationStrategy = 'default'

    [void] AddValidationError([string]$error) {
        $this.ValidationErrors += $error
    }

    [bool] IsValid() {
        return $this.ValidationErrors.Count -eq 0
    }

    [void] MarkOptimized([string]$strategy) {
        $this.IsOptimized = $true
        $this.OptimizationStrategy = $strategy
    }
}

# AST model for enhanced queries (typed, structured)
class PmcAstNode { }
class PmcAstFilterNode : PmcAstNode {
    [string] $Field
    [string] $Operator
    [string] $Value
    PmcAstFilterNode([string]$f,[string]$op,[string]$v){ $this.Field=$f; $this.Operator=$op; $this.Value=$v }
}
class PmcAstDirectiveNode : PmcAstNode {
    [string] $Name
    [object] $Value
    PmcAstDirectiveNode([string]$n,[object]$v){ $this.Name=$n; $this.Value=$v }
}
class PmcAstQuery : PmcAstNode {
    [string] $Domain
    [System.Collections.Generic.List[PmcAstFilterNode]] $Filters
    [System.Collections.Generic.List[PmcAstDirectiveNode]] $Directives
    [string[]] $SearchTerms
    PmcAstQuery(){ $this.Filters = [System.Collections.Generic.List[PmcAstFilterNode]]::new(); $this.Directives=[System.Collections.Generic.List[PmcAstDirectiveNode]]::new(); $this.SearchTerms=@() }
}

# Query cache for performance optimization
class PmcQueryCache {
    hidden [hashtable] $_cache = @{}
    hidden [int] $_maxSize = 50
    hidden [hashtable] $_stats = @{
        Hits = 0
        Misses = 0
        Evictions = 0
    }

    [string] GenerateCacheKey([PmcEnhancedQuerySpec]$spec) {
        $keyParts = @(
            $spec.Domain,
            ($spec.RawTokens -join '|'),
            ($spec.Filters.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '&',
            ($spec.Directives.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '&'
        )
        return ($keyParts -join '::')
    }

    [object] Get([string]$key) {
        if ($this._cache.ContainsKey($key)) {
            $entry = $this._cache[$key]
            if (([datetime]::Now - $entry.Timestamp).TotalMinutes -lt 5) {
                $this._stats.Hits++
                $entry.LastAccess = [datetime]::Now
                return $entry.Result
            } else {
                $this._cache.Remove($key)
            }
        }
        $this._stats.Misses++
        return $null
    }

    [void] Set([string]$key, [object]$result) {
        if ($this._cache.Count -ge $this._maxSize) {
            $this.EvictOldest()
        }

        $this._cache[$key] = @{
            Result = $result
            Timestamp = [datetime]::Now
            LastAccess = [datetime]::Now
        }
    }

    [void] EvictOldest() {
        $oldest = $null
        $oldestTime = [datetime]::MaxValue

        foreach ($entry in $this._cache.GetEnumerator()) {
            if ($entry.Value.LastAccess -lt $oldestTime) {
                $oldestTime = $entry.Value.LastAccess
                $oldest = $entry.Key
            }
        }

        if ($oldest) {
            $this._cache.Remove($oldest)
            $this._stats.Evictions++
        }
    }

    [hashtable] GetStats() {
        $total = $this._stats.Hits + $this._stats.Misses
        $hitRate = $(if ($total -gt 0) { [Math]::Round(($this._stats.Hits * 100.0) / $total, 2) } else { 0 })

        return @{
            Size = $this._cache.Count
            Hits = $this._stats.Hits
            Misses = $this._stats.Misses
            Evictions = $this._stats.Evictions
            HitRate = $hitRate
        }
    }

    [void] Clear() {
        $this._cache.Clear()
        $this._stats = @{ Hits = 0; Misses = 0; Evictions = 0 }
    }
}

# Enhanced query parser with validation and optimization
class PmcEnhancedQueryParser {
    hidden [hashtable] $_allowedDomains = @{
        'task' = @('id', 'text', 'project', 'due', 'priority', 'status', 'tags')
        'project' = @('name', 'description', 'status', 'created', 'updated')
        'timelog' = @('id', 'task', 'project', 'start', 'end', 'duration', 'description')
    }

    hidden [hashtable] $_optimizationRules = @{
        'task' = @{
            'id' = 'index'
            'project' = 'index'
            'due' = 'range'
            'priority' = 'category'
        }
        'project' = @{
            'name' = 'index'
            'status' = 'category'
        }
        'timelog' = @{
            'task' = 'index'
            'project' = 'index'
            'start' = 'range'
        }
    }

    [PmcEnhancedQuerySpec] ParseQuery([string[]]$tokens) {
        $spec = [PmcEnhancedQuerySpec]::new()
        $ast = [PmcAstQuery]::new()

        if ($tokens.Count -eq 0) {
            $spec.AddValidationError("Query requires at least a domain")
            return $spec
        }

        # Parse domain (first token)
        $domainToken = $tokens[0].ToLower()
        $spec.Domain = $this.NormalizeDomain($domainToken)
        $ast.Domain = $spec.Domain

        if (-not $spec.Domain) {
            $spec.AddValidationError("Unknown domain: $domainToken")
            return $spec
        }

        if (-not $this._allowedDomains.ContainsKey($spec.Domain)) {
            $spec.AddValidationError("Domain not supported: $($spec.Domain)")
            return $spec
        }

        # Parse remaining tokens
        $spec.RawTokens = $tokens | Select-Object -Skip 1
        $this.ParseTokens($spec, $spec.RawTokens)
        # Build AST nodes from parsed spec
        foreach ($field in $spec.Filters.Keys) { foreach ($f in $spec.Filters[$field]) { [void]$ast.Filters.Add([PmcAstFilterNode]::new($field,[string]$f.Operator,[string]$f.Value)) } }
        foreach ($k in $spec.Directives.Keys) { [void]$ast.Directives.Add([PmcAstDirectiveNode]::new($k,$spec.Directives[$k])) }
        if ($spec.Metadata.ContainsKey('search')) { $ast.SearchTerms = @($spec.Metadata['search']) }
        $spec.Metadata['Ast'] = $ast

        # Apply optimization hints
        $this.OptimizeQuery($spec)

        return $spec
    }

    [string] NormalizeDomain([string]$domain) {
        switch ($domain) {
            { $_ -in @('task', 'tasks') } { return 'task' }
            { $_ -in @('project', 'projects') } { return 'project' }
            { $_ -in @('timelog', 'timelogs', 'time') } { return 'timelog' }
            default { return $null }
        }
        # Fallback (should never reach here)
        return $null
    }

    [void] ParseTokens([PmcEnhancedQuerySpec]$spec, [string[]]$tokens) {
        $allowedFields = $this._allowedDomains[$spec.Domain]

        foreach ($token in $tokens) {
            if ([string]::IsNullOrWhiteSpace($token)) { continue }

            if ($token.StartsWith('@')) {
                $proj = $token.Substring(1).Trim('"')
                if (-not $spec.Filters.ContainsKey('project')) { $spec.Filters['project'] = @() }
                $spec.Filters['project'] += @{ Operator = '='; Value = $proj }
                continue
            }

            if ($token.StartsWith('#')) {
                $tag = $token.Substring(1).Trim('"')
                if (-not $spec.Filters.ContainsKey('tags')) { $spec.Filters['tags'] = @() }
                $spec.Filters['tags'] += @{ Operator = 'contains'; Value = $tag }
                continue
            }

            if ($token -match '^(?i)p(\d+)$') {
                $val = $matches[1]
                if (-not $spec.Filters.ContainsKey('priority')) { $spec.Filters['priority'] = @() }
                $spec.Filters['priority'] += @{ Operator = '='; Value = $val }
                continue
            }
            if ($token -match '^(?i)p([<>]=?)(\d+)$') {
                $op = $matches[1]; $val = $matches[2]
                if (-not $spec.Filters.ContainsKey('priority')) { $spec.Filters['priority'] = @() }
                $spec.Filters['priority'] += @{ Operator = $op; Value = $val }
                continue
            }
            if ($token -match '^(?i)p(\d+)\.\.(\d+)$') {
                $low = $matches[1]; $high = $matches[2]
                if (-not $spec.Filters.ContainsKey('priority')) { $spec.Filters['priority'] = @() }
                $spec.Filters['priority'] += @{ Operator = '>='; Value = $low }
                $spec.Filters['priority'] += @{ Operator = '<='; Value = $high }
                continue
            }

            if ($spec.Domain -eq 'task' -and $token -in @('overdue','today','tomorrow')) {
                if (-not $spec.Filters.ContainsKey('due')) { $spec.Filters['due'] = @() }
                $spec.Filters['due'] += @{ Operator = ':'; Value = $token }
                continue
            }
            # Directives (cols:, sort:, etc.)
            if ($token -match '^(cols?|columns?):(.+)$') {
                $spec.Directives['columns'] = $matches[2] -split ','
                continue
            }

            if ($token -match '^sort:(.+)$') {
                $spec.Directives['sort'] = $matches[1]
                continue
            }

            if ($token -match '^limit:(\d+)$') {
                $spec.Directives['limit'] = [int]$matches[1]
                continue
            }

            if ($token -match '^group:(.+)$') {
                $spec.Directives['groupBy'] = $matches[1]
                continue
            }

            # Field filters (field:value or field>value, etc.)
            if ($token -match '^(\w+)([:]|>=|<=|=|>|<|~)(.+)$') {
                $field = $matches[1].ToLower()
                $operator = $matches[2]
                $value = $matches[3]

                if ($field -notin $allowedFields) {
                    $spec.AddValidationError("Unknown field for $($spec.Domain): $field")
                    continue
                }

                # Validate operator
                if ($operator -notin @(':', '=', '>', '<', '>=', '<=', '~')) {
                    $spec.AddValidationError("Unknown operator: $operator")
                    continue
                }

                # Sanitize value
                if ($value.Length -gt 100) {
                    $spec.AddValidationError("Filter value too long: $field")
                    continue
                }

                if (-not $spec.Filters.ContainsKey($field)) {
                    $spec.Filters[$field] = @()
                }
                $spec.Filters[$field] += @{ Operator = $operator; Value = $value }
                continue
            }

            # Simple field names (for existence checks)
            if ($token -match '^\w+$' -and $token.ToLower() -in $allowedFields) {
                $field = $token.ToLower()
                if (-not $spec.Filters.ContainsKey($field)) {
                    $spec.Filters[$field] = @()
                }
                $spec.Filters[$field] += @{ Operator = 'exists'; Value = $true }
                continue
            }

            # Free text search
            if (-not $spec.Metadata.ContainsKey('search')) {
                $spec.Metadata['search'] = @()
            }
            $spec.Metadata['search'] += $token
        }
    }

    [void] OptimizeQuery([PmcEnhancedQuerySpec]$spec) {
        if (-not $this._optimizationRules.ContainsKey($spec.Domain)) {
            return
        }

        $rules = $this._optimizationRules[$spec.Domain]
        $indexableFields = @()
        $strategy = 'scan'

        # Check for indexed fields in filters
        foreach ($field in $spec.Filters.Keys) {
            if ($rules.ContainsKey($field) -and $rules[$field] -eq 'index') {
                $indexableFields += $field
                $strategy = 'index'
            }
        }

        if ($indexableFields.Count -gt 0) {
            $spec.UseIndex = $true
            $spec.IndexFields = $indexableFields
            $spec.MarkOptimized($strategy)
        }

        # Estimate result size
        if ($spec.Filters.ContainsKey('id')) {
            $spec.EstimatedRows = 1
        } elseif ($indexableFields.Count -gt 0) {
            $spec.EstimatedRows = 10  # Rough estimate for indexed queries
        } else {
            $spec.EstimatedRows = 100  # Full scan estimate
        }
    }
}

# Enhanced query executor with performance optimization
class PmcEnhancedQueryExecutor {
    hidden [PmcQueryCache] $_cache
    hidden [hashtable] $_executionStats = @{
        QueriesExecuted = 0
        TotalDuration = 0
        CacheHits = 0
        CacheMisses = 0
    }

    PmcEnhancedQueryExecutor() {
        $this._cache = [PmcQueryCache]::new()
    }

    [object] ExecuteQuery([PmcEnhancedQuerySpec]$spec) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Check cache first
            $cacheKey = $this._cache.GenerateCacheKey($spec)
            $cached = $this._cache.Get($cacheKey)

            if ($cached) {
                $this._executionStats.CacheHits++
                Write-PmcDebug -Level 3 -Category 'EnhancedQuery' -Message "Cache hit for query" -Data @{ Domain = $spec.Domain; Strategy = 'cache' }
                return $cached
            }

            $this._executionStats.CacheMisses++

            # Execute AST first (normalizes spec), then execute optimized path
            $result = $this.ExecuteAst($spec)

            # Cache successful results
            if ($result -and -not $result.Error) {
                $this._cache.Set($cacheKey, $result)
            }

            $this._executionStats.QueriesExecuted++
            $this._executionStats.TotalDuration += $stopwatch.ElapsedMilliseconds

            Write-PmcDebug -Level 2 -Category 'EnhancedQuery' -Message "Query executed" -Data @{
                Domain = $spec.Domain
                Strategy = $spec.OptimizationStrategy
                Duration = $stopwatch.ElapsedMilliseconds
                Cached = $false
                Results = $(if ($result.Data) { $result.Data.Count } else { 0 })
            }

            return $result

        } catch {
            Write-PmcDebug -Level 1 -Category 'EnhancedQuery' -Message "Query execution failed" -Data @{ Error = $_.ToString(); Domain = $spec.Domain }
            return @{ Error = $_.ToString(); Success = $false }
        } finally {
            $stopwatch.Stop()
        }
    }

    [object] ExecuteAst([PmcEnhancedQuerySpec]$spec) {
        try {
            if (-not $spec.Metadata.ContainsKey('Ast')) { return $this.ExecuteScanQuery($spec) }
            $ast = [PmcAstQuery]$spec.Metadata['Ast']
            if ($null -eq $ast) { return $this.ExecuteScanQuery($spec) }

            # 1) Resolve dataset
            $data = switch ($ast.Domain) {
                'task'    { if (Get-Command Get-PmcTasksData -ErrorAction SilentlyContinue)    { Get-PmcTasksData }    else { @() } }
                'project' { if (Get-Command Get-PmcProjectsData -ErrorAction SilentlyContinue) { Get-PmcProjectsData } else { @() } }
                'timelog' { if (Get-Command Get-PmcTimeLogsData -ErrorAction SilentlyContinue) { Get-PmcTimeLogsData } else { @() } }
                default { @() }
            }

            $filtered = @($data)

            # 2) Apply filters (AND semantics)
            foreach ($node in $ast.Filters) {
                $field = $node.Field; $op = ($node.Operator + '') ; $val = ($node.Value + '')
                $filtered = @($filtered | Where-Object {
                    if ($null -eq $_) { return $false }
                    $has = $_.PSObject.Properties[$field]
                    $v = $(if ($has) { $_."$field" } else { $null })

                    # Special: due date filters
                    if ($field -eq 'due') {
                        $today = (Get-Date).Date
                        if ($op -eq ':' -and $val -eq 'today') { if (-not $v) { return $false }; try { return ([datetime]$v).Date -eq $today } catch { return $false } }
                        if ($op -eq ':' -and $val -eq 'tomorrow') { if (-not $v) { return $false }; try { return ([datetime]$v).Date -eq $today.AddDays(1) } catch { return $false } }
                        if ($op -eq ':' -and $val -eq 'overdue') { if (-not $v) { return $false }; try { return ([datetime]$v).Date -lt $today } catch { return $false } }
                        if ($op -eq ':' -and $val -match '^\+(\d+)$') { if (-not $v) { return $false }; $d=[int]$matches[1]; try { $date=[datetime]$v; return ($date.Date -le $today.AddDays($d)) -and ($date.Date -ge $today) } catch { return $false } }
                        if ($op -eq ':' -and $val -eq 'eow') { if (-not $v) { return $false }; $dow=[int]$today.DayOfWeek; $rem=(7-$dow)%7; try { return ([datetime]$v).Date -le $today.AddDays($rem) -and ([datetime]$v).Date -ge $today } catch { return $false } }
                        if ($op -eq ':' -and $val -eq 'eom') { if (-not $v) { return $false }; $eom=(Get-Date -Day 1).AddMonths(1).AddDays(-1).Date; try { return ([datetime]$v).Date -le $eom -and ([datetime]$v).Date -ge $today } catch { return $false } }
                        # support YYYYMMDD/YYMMDD quick parse
                        if ($op -eq ':' -and $val -match '^(\d{8}|\d{6})$') { if (-not $v) { return $false }; try { $dt=[datetime]$v; $y=$val; if ($y.Length -eq 8) { $qry=[datetime]::ParseExact($y,'yyyyMMdd',$null) } else { $qry=[datetime]::ParseExact($y,'yyMMdd',$null) }; return $dt.Date -eq $qry.Date } catch { return $false } }
                        $sv = $(if ($v) { [string]$v } else { '' })
                        return $sv -match [regex]::Escape($val)
                    }

                    # Special: tags contains
                    if ($field -eq 'tags') {
                        $arr=@(); try { if ($v -is [System.Collections.IEnumerable]) { $arr=@($v) } } catch {}
                        if ($op -eq 'contains') { return ($arr -contains $val) }
                        return $false
                    }

                    $sv = $(if ($v -ne $null) { [string]$v } else { '' })
                    switch ($op) {
                        'exists' { $has -and $sv -ne '' }
                        ':' { $sv -match [regex]::Escape($val) }
                        '=' { $sv -eq $val }
                        '>' { try { [double]$sv -gt [double]$val } catch { $false } }
                        '<' { try { [double]$sv -lt [double]$val } catch { $false } }
                        '>=' { try { [double]$sv -ge [double]$val } catch { $false } }
                        '<=' { try { [double]$sv -le [double]$val } catch { $false } }
                        '~' { $sv -like "*${val}*" }
                        default { $true }
                    }
                })
            }

            # 3) Apply free text search
            if ($ast.SearchTerms -and @($ast.SearchTerms).Count -gt 0) {
                foreach ($t in $ast.SearchTerms) {
                    $needle = ($t + '').ToLower()
                    $filtered = @($filtered | Where-Object {
                        $text = ''
                        try { $text = (($_.text) + ' ' + ($_.project) + ' ' + ($_.description) + ' ' + ($_.name)) } catch {}
                        $text.ToLower().Contains($needle)
                    })
                }
            }

            # 4) Apply directives: sort, group, columns, limit
            $dirMap = @{}
            foreach ($d in $ast.Directives) { $dirMap[$d.Name] = $d.Value }

            # Sort
            if ($dirMap.ContainsKey('sort')) {
                $sortExpr = [string]$dirMap['sort']; $asc = $true; $field = $sortExpr
                if ($sortExpr -match '^(.+?)([+-])$') { $field=$matches[1]; $asc = ($matches[2] -eq '+') }
                $filtered = @($filtered | Sort-Object -Property @{ Expression = { if ($_.PSObject.Properties[$field]) { $_."$field" } else { $null } }; Ascending = $asc })
            }

            # Group
            $grouped = $false
            if ($dirMap.ContainsKey('groupBy')) {
                $g = [string]$dirMap['groupBy']
                $projected = @()
                foreach ($row in $filtered) {
                    if ($null -eq $row) { continue }
                    $groupVal = $(if ($row.PSObject.Properties[$g]) { $row."$g" } else { $null })
                    $obj = [pscustomobject]@{ Group = $groupVal }
                    foreach ($p in $row.PSObject.Properties) { Add-Member -InputObject $obj -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
                    $projected += $obj
                }
                $filtered = @($projected | Sort-Object -Property @{ Expression = { $_.Group } })
                $grouped = $true
            }

            # Columns
            if ($dirMap.ContainsKey('columns')) {
                $cols = @($dirMap['columns'])
                $projected = @()
                foreach ($row in $filtered) {
                    $obj = [pscustomobject]@{}
                    if ($grouped) { Add-Member -InputObject $obj -NotePropertyName 'Group' -NotePropertyValue $row.Group -Force }
                    foreach ($c in $cols) {
                        $name = [string]$c
                        $val = $(if ($row.PSObject.Properties[$name]) { $row."$name" } else { $null })
                        Add-Member -InputObject $obj -NotePropertyName $name -NotePropertyValue $val -Force
                    }
                    $projected += $obj
                }
                $filtered = $projected
            } elseif ($grouped) {
                # ensure Group column visible when grouped
                $projected = @()
                foreach ($row in $filtered) {
                    $obj = [pscustomobject]@{ Group = $row.Group }
                    foreach ($p in $row.PSObject.Properties) { if ($p.Name -ne 'Group') { Add-Member -InputObject $obj -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force } }
                    $projected += $obj
                }
                $filtered = $projected
            }

            # Limit
            if ($dirMap.ContainsKey('limit')) { $n = [int]$dirMap['limit']; $filtered = @($filtered | Select-Object -First $n) }

            return @{
                Success = $true
                Data = ,$filtered
                Metadata = @{
                    EstimatedRows = $spec.EstimatedRows
                    ActualRows = @($filtered).Count
                    Strategy = $spec.OptimizationStrategy
                    Cached = $false
                }
            }
        } catch {
            Write-PmcDebug -Level 2 -Category 'EnhancedQuery' -Message "AST execution fallback: $_"
            return $this.ExecuteScanQuery($spec)
        }
    }

    [object] ExecuteIndexedQuery([PmcEnhancedQuerySpec]$spec) {
        # Indexed path – we still filter in-memory but can apply early prunes by index fields
        return $this.ExecuteScanQuery($spec)
    }

    [object] ExecuteScanQuery([PmcEnhancedQuerySpec]$spec) {
        # Execute against in-memory data from Storage via pure providers
        $data = switch ($spec.Domain) {
            'task'    { if (Get-Command Get-PmcTasksData -ErrorAction SilentlyContinue)    { Get-PmcTasksData }    else { @() } }
            'project' { if (Get-Command Get-PmcProjectsData -ErrorAction SilentlyContinue) { Get-PmcProjectsData } else { @() } }
            'timelog' { if (Get-Command Get-PmcTimeLogsData -ErrorAction SilentlyContinue) { Get-PmcTimeLogsData } else { @() } }
            default { @() }
        }

        # Apply filters
        $filtered = @($data)
        foreach ($field in $spec.Filters.Keys) {
            $ops = $spec.Filters[$field]
            foreach ($op in $ops) {
                $operator = [string]$op.Operator
                $val = [string]$op.Value
                $filtered = @($filtered | Where-Object {
                    if ($null -eq $_) { return $false }
                    $has = $_.PSObject.Properties[$field]
                    $v = $(if ($has) { $_."$field" } else { $null })
                    # Special cases
                    if ($field -eq 'due') {
                        $today = (Get-Date).Date
                        if ($val -eq 'today') { if (-not $v) { return $false }; try { return ([datetime]$v).Date -eq $today } catch { return $false } }
                        if ($val -eq 'tomorrow') { if (-not $v) { return $false }; try { return ([datetime]$v).Date -eq $today.AddDays(1) } catch { return $false } }
                        if ($val -eq 'overdue') { if (-not $v) { return $false }; try { return ([datetime]$v).Date -lt $today } catch { return $false } }
                        if ($val -match '^\+(\d+)$') { if (-not $v) { return $false }; $d=[int]$matches[1]; try { $date=[datetime]$v; return ($date.Date -le $today.AddDays($d)) -and ($date.Date -ge $today) } catch { return $false } }
                        if ($val -eq 'eow') { if (-not $v) { return $false }; $dow = [int]$today.DayOfWeek; $rem = (7 - $dow) % 7; try { return ([datetime]$v).Date -le $today.AddDays($rem) -and ([datetime]$v).Date -ge $today } catch { return $false } }
                        if ($val -eq 'eom') { if (-not $v) { return $false }; $eom = (Get-Date -Day 1).AddMonths(1).AddDays(-1).Date; try { return ([datetime]$v).Date -le $eom -and ([datetime]$v).Date -ge $today } catch { return $false } }
                        $vv = $(if ($v) { [string]$v } else { '' })
                        return $vv -match [regex]::Escape($val)
                    }
                    if ($field -eq 'tags') {
                        $arr = @(); try { if ($v -is [System.Collections.IEnumerable]) { $arr=@($v) } } catch {}
                        if ($operator -eq 'contains') { return ($arr -contains $val) }
                        return $false
                    }
                    $sv = $(if ($v -ne $null) { [string]$v } else { '' })
                    switch ($operator) {
                        'exists' { $has -and $sv -ne '' }
                        ':' { $sv -match [regex]::Escape($val) }
                        '=' { $sv -eq $val }
                        '>' { try { [double]$sv -gt [double]$val } catch { $false } }
                        '<' { try { [double]$sv -lt [double]$val } catch { $false } }
                        '>=' { try { [double]$sv -ge [double]$val } catch { $false } }
                        '<=' { try { [double]$sv -le [double]$val } catch { $false } }
                        '~' { $sv -like "*${val}*" }
                        default { $true }
                    }
                })
            }
        }

        # Free text search across common fields
        if ($spec.Metadata.ContainsKey('search')) {
            $terms = @($spec.Metadata['search'])
            foreach ($t in $terms) {
                $needle = $t.ToLower()
                $filtered = @($filtered | Where-Object {
                    $text = ''
                    try {
                        $text = (($_.text) + ' ' + ($_.project) + ' ' + ($_.description) + ' ' + ($_.name))
                    } catch {}
                    $text.ToLower().Contains($needle)
                })
            }
        }

        # Sorting
        if ($spec.Directives.ContainsKey('sort')) {
            $sortExpr = [string]$spec.Directives['sort']
            $asc = $true
            $field = $sortExpr
            if ($sortExpr -match '^(.+?)([+-])$') { $field = $matches[1]; $asc = ($matches[2] -eq '+') }
            $filtered = @($filtered | Sort-Object -Property @{ Expression = { if ($_.PSObject.Properties[$field]) { $_."$field" } else { $null } }; Ascending = $asc })
        }

        # Grouping (flat projection by adding Group field)
        if ($spec.Directives.ContainsKey('groupBy')) {
            $g = [string]$spec.Directives['groupBy']
            $projected = @()
            foreach ($row in $filtered) {
                if ($null -eq $row) { continue }
                $groupVal = $(if ($row.PSObject.Properties[$g]) { $row."$g" } else { $null })
                $obj = [pscustomobject]@{ Group = $groupVal }
                # Copy existing fields
                foreach ($p in $row.PSObject.Properties) { Add-Member -InputObject $obj -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
                $projected += $obj
            }
            $filtered = @($projected | Sort-Object -Property @{ Expression = { $_.Group } })
        }

        # Columns selection
        if ($spec.Directives.ContainsKey('columns')) {
            $cols = @($spec.Directives['columns'])
            $projected = @()
            foreach ($row in $filtered) {
                $obj = [pscustomobject]@{}
                if ($spec.Directives.ContainsKey('groupBy')) { Add-Member -InputObject $obj -NotePropertyName 'Group' -NotePropertyValue $row.Group -Force }
                foreach ($c in $cols) {
                    $name = [string]$c
                    $val = $(if ($row.PSObject.Properties[$name]) { $row."$name" } else { $null })
                    Add-Member -InputObject $obj -NotePropertyName $name -NotePropertyValue $val -Force
                }
                $projected += $obj
            }
            $filtered = $projected
        } elseif ($spec.Directives.ContainsKey('groupBy')) {
            # Ensure Group column appears by default if grouping
            $projected = @()
            foreach ($row in $filtered) {
                $obj = [pscustomobject]@{ Group = $row.Group }
                foreach ($p in $row.PSObject.Properties) { if ($p.Name -ne 'Group') { Add-Member -InputObject $obj -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force } }
                $projected += $obj
            }
            $filtered = $projected
        }

        # Limit
        if ($spec.Directives.ContainsKey('limit')) {
            $n = [int]$spec.Directives['limit']
            $filtered = @($filtered | Select-Object -First $n)
        }

        return @{
            Success = $true
            Data = ,$filtered
            Metadata = @{
                EstimatedRows = $spec.EstimatedRows
                ActualRows = @($filtered).Count
                Strategy = $spec.OptimizationStrategy
                Cached = $false
            }
        }
    }

    [object] ExecuteLegacyQuery([PmcEnhancedQuerySpec]$spec) {
        # Legacy query path removed - all queries go through AST now
        Write-PmcDebug -Level 1 -Category 'Query' -Message 'Legacy query execution attempted but disabled'
        return @()
        return @{ Success = $true; Data = @(); Metadata = @{ EstimatedRows = 0; ActualRows = 0; Strategy = 'none'; Cached = $false } }
    }

    [hashtable] GetExecutionStats() {
        $cacheStats = $this._cache.GetStats()
        $avgDuration = $(if ($this._executionStats.QueriesExecuted -gt 0) {
            [Math]::Round($this._executionStats.TotalDuration / $this._executionStats.QueriesExecuted, 2)
        } else { 0 })

        return @{
            QueriesExecuted = $this._executionStats.QueriesExecuted
            AverageDuration = $avgDuration
            TotalDuration = $this._executionStats.TotalDuration
            CacheStats = $cacheStats
        }
    }

    [void] ClearCache() {
        $this._cache.Clear()
    }

    [void] ResetStats() {
        $this._executionStats = @{
            QueriesExecuted = 0
            TotalDuration = 0
            CacheHits = 0
            CacheMisses = 0
        }
        $this._cache.Clear()
    }
}

# Global instances
$Script:PmcEnhancedQueryParser = $null
$Script:PmcEnhancedQueryExecutor = $null

function Initialize-PmcEnhancedQueryEngine {
    if ($Script:PmcEnhancedQueryParser) {
        Write-Warning "PMC Enhanced Query Engine already initialized"
        return
    }

    $Script:PmcEnhancedQueryParser = [PmcEnhancedQueryParser]::new()
    $Script:PmcEnhancedQueryExecutor = [PmcEnhancedQueryExecutor]::new()

    Write-PmcDebug -Level 2 -Category 'EnhancedQuery' -Message "Enhanced query engine initialized"
}

function Invoke-PmcEnhancedQuery {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Tokens,

        [switch]$NoCache
    )

    if (-not $Script:PmcEnhancedQueryParser) {
        Initialize-PmcEnhancedQueryEngine
    }

    $spec = $Script:PmcEnhancedQueryParser.ParseQuery($Tokens)

    if (-not $spec.IsValid()) {
        Write-PmcStyled -Style 'Error' -Text "Query validation failed: $($spec.ValidationErrors -join '; ')"
        return @{ Success = $false; Errors = $spec.ValidationErrors }
    }

    if ($NoCache) {
        $Script:PmcEnhancedQueryExecutor.ClearCache()
    }

    return $Script:PmcEnhancedQueryExecutor.ExecuteQuery($spec)
}

function Get-PmcQueryPerformanceStats {
    if (-not $Script:PmcEnhancedQueryExecutor) {
        Write-Host "Enhanced query engine not initialized"
        return
    }

    $stats = $Script:PmcEnhancedQueryExecutor.GetExecutionStats()

    Write-Host "PMC Query Performance Statistics" -ForegroundColor Green
    Write-Host "===============================" -ForegroundColor Green
    Write-Host "Queries Executed: $($stats.QueriesExecuted)"
    Write-Host "Average Duration: $($stats.AverageDuration) ms"
    Write-Host "Total Duration: $($stats.TotalDuration) ms"
    Write-Host ""
    Write-Host "Cache Performance:" -ForegroundColor Yellow
    Write-Host "Cache Size: $($stats.CacheStats.Size)"
    Write-Host "Cache Hit Rate: $($stats.CacheStats.HitRate)%"
    Write-Host "Cache Hits: $($stats.CacheStats.Hits)"
    Write-Host "Cache Misses: $($stats.CacheStats.Misses)"
    Write-Host "Cache Evictions: $($stats.CacheStats.Evictions)"
}

Export-ModuleMember -Function Initialize-PmcEnhancedQueryEngine, Invoke-PmcEnhancedQuery, Get-PmcQueryPerformanceStats