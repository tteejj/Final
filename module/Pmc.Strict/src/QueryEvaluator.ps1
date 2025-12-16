# Query evaluation engine for the PMC query language system

Set-StrictMode -Version Latest

function Evaluate-PmcQuery {
    param([PmcQuerySpec]$Spec)
    if (-not $Spec -or -not $Spec.Domain) { throw 'Evaluate-PmcQuery: Spec/Domain required' }

    Write-PmcDebug -Level 2 -Category 'QueryEvaluator' -Message 'Starting query evaluation' -Data @{ Domain=$Spec.Domain }

    $data = Get-PmcDataAlias
    $rows = @()
    switch ($Spec.Domain) {
        'task'    { $rows = $(if ($data.tasks) { @($data.tasks | Where-Object { $_ -ne $null }) } else { @() }) }
        'project' { $rows = $(if ($data.projects) { @($data.projects | Where-Object { $_ -ne $null }) } else { @() }) }
        'timelog' { $rows = $(if ($data.timelogs) { @($data.timelogs | Where-Object { $_ -ne $null }) } else { @() }) }
        default   { $rows = @() }
    }

    # Apply basic filters (task domain)
    if ($Spec.Domain -eq 'task' -and $Spec.Filters) {
        $proj = $(if ($Spec.Filters.ContainsKey('project')) { [string]$Spec.Filters['project'] } else { $null })
        $overdue = ($Spec.Filters.ContainsKey('overdue'))
        $dueTok = $(if ($Spec.Filters.ContainsKey('due')) { [string]$Spec.Filters['due'] } else { $null })
        $due_gt = $(if ($Spec.Filters.ContainsKey('due_gt')) { [string]$Spec.Filters['due_gt'] } else { $null })
        $due_lt = $(if ($Spec.Filters.ContainsKey('due_lt')) { [string]$Spec.Filters['due_lt'] } else { $null })
        $due_ge = $(if ($Spec.Filters.ContainsKey('due_ge')) { [string]$Spec.Filters['due_ge'] } else { $null })
        $due_le = $(if ($Spec.Filters.ContainsKey('due_le')) { [string]$Spec.Filters['due_le'] } else { $null })
        $p_le = $(if ($Spec.Filters.ContainsKey('p_le')) { [int]$Spec.Filters['p_le'] } else { 0 })
        $p_ge = $(if ($Spec.Filters.ContainsKey('p_ge')) { [int]$Spec.Filters['p_ge'] } else { 0 })
        $p_gt = $(if ($Spec.Filters.ContainsKey('p_gt')) { [int]$Spec.Filters['p_gt'] } else { 0 })
        $p_lt = $(if ($Spec.Filters.ContainsKey('p_lt')) { [int]$Spec.Filters['p_lt'] } else { 0 })
        $p_eq = $(if ($Spec.Filters.ContainsKey('p_eq')) { [int]$Spec.Filters['p_eq'] } else { 0 })
        $tagsIn = $(if ($Spec.Filters.ContainsKey('tags_in')) { @($Spec.Filters['tags_in']) } else { @() })
        $tagsOut = $(if ($Spec.Filters.ContainsKey('tags_out')) { @($Spec.Filters['tags_out']) } else { @() })
        $textQ = $(if ($Spec.Filters.ContainsKey('text')) { [string]$Spec.Filters['text'] } else { '' })

        $rows = @($rows | Where-Object {
            $ok = $true
            if ($proj) { $ok = $ok -and ($_.PSObject.Properties['project'] -and [string]$_.project -eq $proj) }
            if ($Spec.Filters.ContainsKey('status')) {
                $sts = [string]$Spec.Filters['status']
                $ok = $ok -and ($_.PSObject.Properties['status'] -and ([string]$_.status).ToLower() -eq $sts)
            }
            if ($p_le -gt 0) {
                $v = $(if ($_.PSObject.Properties['priority']) { try { [int]$_.priority } catch { 0 } } else { 0 })
                $ok = $ok -and ($v -gt 0 -and $v -le $p_le)
            }
            if ($p_ge -gt 0) {
                $v = $(if ($_.PSObject.Properties['priority']) { try { [int]$_.priority } catch { 0 } } else { 0 })
                $ok = $ok -and ($v -gt 0 -and $v -ge $p_ge)
            }
            if ($p_gt -gt 0) {
                $v = $(if ($_.PSObject.Properties['priority']) { try { [int]$_.priority } catch { 0 } } else { 0 })
                $ok = $ok -and ($v -gt $p_gt)
            }
            if ($p_lt -gt 0) {
                $v = $(if ($_.PSObject.Properties['priority']) { try { [int]$_.priority } catch { 0 } } else { 0 })
                $ok = $ok -and ($v -gt 0 -and $v -lt $p_lt)
            }
            if ($p_eq -gt 0) {
                $v = $(if ($_.PSObject.Properties['priority']) { try { [int]$_.priority } catch { 0 } } else { 0 })
                $ok = $ok -and ($v -eq $p_eq)
            }
            if ($Spec.Filters.ContainsKey('p_range')) {
                $min = [int]$Spec.Filters['p_range'].Min; $max=[int]$Spec.Filters['p_range'].Max
                $v = $(if ($_.PSObject.Properties['priority']) { try { [int]$_.priority } catch { 0 } } else { 0 })
                $ok = $ok -and ($v -ge $min -and $v -le $max)
            }
            if ($overdue) {
                if ($_.PSObject.Properties['due']) {
                    try { $ok = $ok -and (([datetime]$_.due).Date -lt (Get-Date).Date) } catch { $ok = $false }
                }
            }
            if ($dueTok) {
                $d = $null
                try {
                    # Use flexible date parsing logic from FieldSchemas
                    $schemas = Get-PmcFieldSchemasForDomain -Domain 'task'
                    if ($schemas.ContainsKey('due') -and $schemas.due.ContainsKey('Normalize')) {
                        $normalizedDate = & $schemas.due.Normalize $dueTok
                        if ($normalizedDate) { $d = [datetime]$normalizedDate }
                    }
                } catch {
                    # Fallback to basic parsing
                    if ($dueTok -match '^(?i)today$') { $d = (Get-Date).Date }
                    elseif ($dueTok -match '^\d{4}-\d{2}-\d{2}$') { try { $d = [datetime]$dueTok } catch { $d=$null } }
                }
                if ($d -ne $null -and $_.PSObject.Properties['due']) {
                    try { $ok = $ok -and (([datetime]$_.due).Date -eq $d.Date) } catch { $ok = $false }
                }
            }
            if ($Spec.Filters.ContainsKey('due_range')) {
                $startTok = [string]$Spec.Filters['due_range'].Start; $endTok=[string]$Spec.Filters['due_range'].End
                try { $start=[datetime]$startTok; $end=[datetime]$endTok } catch { $start=$null; $end=$null }
                if ($start -ne $null -and $end -ne $null -and $_.PSObject.Properties['due']) {
                    try { $dd=[datetime]$_.due; $ok = $ok -and ($dd -ge $start -and $dd -le $end) } catch { $ok = $false }
                }
            }
            if ($due_gt -and $_.PSObject.Properties['due']) {
                $d = $null
                try {
                    $schemas = Get-PmcFieldSchemasForDomain -Domain 'task'
                    if ($schemas.ContainsKey('due') -and $schemas.due.ContainsKey('Normalize')) {
                        $normalizedDate = & $schemas.due.Normalize $due_gt
                        if ($normalizedDate) { $d = [datetime]$normalizedDate }
                    }
                } catch {
                    if ($due_gt -match '^(?i)today$') { $d = (Get-Date).Date }
                    elseif ($due_gt -match '^\d{4}-\d{2}-\d{2}$') { try { $d = [datetime]$due_gt } catch { $d=$null } }
                }
                if ($d -ne $null) {
                    try { $ok = $ok -and (([datetime]$_.due).Date -gt $d.Date) } catch { $ok = $false }
                }
            }
            if ($due_lt -and $_.PSObject.Properties['due']) {
                $d = $null
                try {
                    $schemas = Get-PmcFieldSchemasForDomain -Domain 'task'
                    if ($schemas.ContainsKey('due') -and $schemas.due.ContainsKey('Normalize')) {
                        $normalizedDate = & $schemas.due.Normalize $due_lt
                        if ($normalizedDate) { $d = [datetime]$normalizedDate }
                    }
                } catch {
                    if ($due_lt -match '^(?i)today$') { $d = (Get-Date).Date }
                    elseif ($due_lt -match '^\d{4}-\d{2}-\d{2}$') { try { $d = [datetime]$due_lt } catch { $d=$null } }
                }
                if ($d -ne $null) {
                    try { $ok = $ok -and (([datetime]$_.due).Date -lt $d.Date) } catch { $ok = $false }
                }
            }
            if ($due_ge -and $_.PSObject.Properties['due']) {
                $d = $null
                try {
                    $schemas = Get-PmcFieldSchemasForDomain -Domain 'task'
                    if ($schemas.ContainsKey('due') -and $schemas.due.ContainsKey('Normalize')) {
                        $normalizedDate = & $schemas.due.Normalize $due_ge
                        if ($normalizedDate) { $d = [datetime]$normalizedDate }
                    }
                } catch {
                    if ($due_ge -match '^(?i)today$') { $d = (Get-Date).Date }
                    elseif ($due_ge -match '^\d{4}-\d{2}-\d{2}$') { try { $d = [datetime]$due_ge } catch { $d=$null } }
                }
                if ($d -ne $null) {
                    try { $ok = $ok -and (([datetime]$_.due).Date -ge $d.Date) } catch { $ok = $false }
                }
            }
            if ($due_le -and $_.PSObject.Properties['due']) {
                $d = $null
                try {
                    $schemas = Get-PmcFieldSchemasForDomain -Domain 'task'
                    if ($schemas.ContainsKey('due') -and $schemas.due.ContainsKey('Normalize')) {
                        $normalizedDate = & $schemas.due.Normalize $due_le
                        if ($normalizedDate) { $d = [datetime]$normalizedDate }
                    }
                } catch {
                    if ($due_le -match '^(?i)today$') { $d = (Get-Date).Date }
                    elseif ($due_le -match '^\d{4}-\d{2}-\d{2}$') { try { $d = [datetime]$due_le } catch { $d=$null } }
                }
                if ($d -ne $null) {
                    try { $ok = $ok -and (([datetime]$_.due).Date -le $d.Date) } catch { $ok = $false }
                }
            }
            if (@($tagsIn).Count -gt 0) {
                if ($_.PSObject.Properties['tags']) {
                    try { $ok = $ok -and (@($tagsIn | Where-Object { $($_) -in $_.tags }).Count -eq @($tagsIn).Count) } catch { $ok = $false }
                }
            }
            if (@($tagsOut).Count -gt 0) {
                if ($_.PSObject.Properties['tags']) {
                    try { $ok = $ok -and -not (@($tagsOut | Where-Object { $($_) -in $_.tags }).Count -gt 0) } catch { $ok = $true }
                }
            }
            if ($textQ) {
                if ($_.PSObject.Properties['text']) {
                    try { $ok = $ok -and ([string]$_.text).ToLower().Contains($textQ.ToLower()) } catch { $ok = $false }
                }
            }
            $ok
        })
    }

    # Apply basic filters (project domain)
    if ($Spec.Domain -eq 'project' -and $Spec.Filters) {
        $textQ = $(if ($Spec.Filters.ContainsKey('text')) { [string]$Spec.Filters['text'] } else { '' })
        $arch = $null; if ($Spec.Filters.ContainsKey('archived')) { $arch = [bool]$Spec.Filters['archived'] }
        if ($textQ) {
            $rows = @($rows | Where-Object {
                try {
                    ($_.PSObject.Properties['name'] -and ([string]$_.name).ToLower().Contains($textQ.ToLower())) -or
                    ($_.PSObject.Properties['description'] -and ([string]$_.description).ToLower().Contains($textQ.ToLower()))
                } catch { $false }
            })
        }
        if ($arch -ne $null) {
            $rows = @($rows | Where-Object { $_.PSObject.Properties['isArchived'] -and [bool]$_.isArchived -eq $arch })
        }
    }

    # Apply basic filters (timelog domain)
    if ($Spec.Domain -eq 'timelog' -and $Spec.Filters) {
        $proj = $(if ($Spec.Filters.ContainsKey('project')) { [string]$Spec.Filters['project'] } else { $null })
        $dateTok = $(if ($Spec.Filters.ContainsKey('date')) { [string]$Spec.Filters['date'] } elseif ($Spec.Filters.ContainsKey('due')) { [string]$Spec.Filters['due'] } else { $null })
        $textQ = $(if ($Spec.Filters.ContainsKey('text')) { [string]$Spec.Filters['text'] } else { '' })
        $taskId = $(if ($Spec.Filters.ContainsKey('taskId')) { [int]$Spec.Filters['taskId'] } else { 0 })
        $rows = @($rows | Where-Object {
            $ok = $true
            if ($proj) { $ok = $ok -and ($_.PSObject.Properties['project'] -and [string]$_.project -eq $proj) }
            if ($dateTok) {
                if ($dateTok -match '^\d{4}-\d{2}-\d{2}\.\.\d{4}-\d{2}-\d{2}$') {
                    $parts = $dateTok -split '\.\.'
                    try { $ds=[datetime]$parts[0]; $de=[datetime]$parts[1] } catch { $ds=$null; $de=$null }
                    if ($ds -ne $null -and $de -ne $null -and $_.PSObject.Properties['date']) {
                        try { $dd=[datetime]$_.date; $ok = $ok -and ($dd -ge $ds -and $dd -le $de) } catch { $ok = $false }
                    }
                } else {
                    $d = $null
                    if ($dateTok -match '^(?i)today$') { $d = (Get-Date).Date }
                    elseif ($dateTok -match '^\d{4}-\d{2}-\d{2}$') { try { $d = [datetime]$dateTok } catch { $d=$null } }
                    if ($d -ne $null -and $_.PSObject.Properties['date']) {
                        try { $ok = $ok -and (([datetime]$_.date).Date -eq $d.Date) } catch { $ok = $false }
                    }
                }
            }
            if ($taskId -gt 0 -and $_.PSObject.Properties['taskId']) {
                try { $ok = $ok -and ([int]$_.taskId -eq $taskId) } catch { $ok = $false }
            }
            if ($textQ -and $_.PSObject.Properties['notes']) {
                try { $ok = $ok -and ([string]$_.notes).ToLower().Contains($textQ.ToLower()) } catch { $ok = $false }
            }
            $ok
        })
    }

    # Relations (attach derived fields)
    Write-PmcDebug -Level 3 -Category 'QueryEvaluator' -Message 'Checking relations' -Data @{ With=$Spec.With; WithType=($Spec.With).GetType().Name }
    if ($Spec.With -and @($Spec.With).Count -gt 0) {
        foreach ($rel in $Spec.With) {
            foreach ($row in $rows) {
                $rels = Get-PmcRelationResolvers -Domain $Spec.Domain -Relation $rel
                foreach ($key in $rels.Keys) {
                    try { $val = & $rels[$key] $row $data } catch { $val = $null }
                    try { if ($row.PSObject.Properties[$key]) { $row.$key = $val } else { Add-Member -InputObject $row -MemberType NoteProperty -Name $key -NotePropertyValue $val -Force } } catch {}
                }
            }
        }
    }

    # Compute requested metrics and attach as NoteProperties
    Write-PmcDebug -Level 3 -Category 'QueryEvaluator' -Message 'Checking metrics' -Data @{ Metrics=$Spec.Metrics; MetricsType=($Spec.Metrics).GetType().Name }
    if ($Spec.Metrics -and @($Spec.Metrics).Count -gt 0) {
        $metrics = Get-PmcMetricsForDomain -Domain $Spec.Domain
        foreach ($row in $rows) {
            foreach ($m in $Spec.Metrics) {
                if (-not $metrics.ContainsKey($m)) { continue }
                $def = $metrics[$m]
                try {
                    $val = & $def.Resolver $row $data
                } catch { $val = $null }
                    try { if ($row.PSObject.Properties[$m]) { $row.$m = $val } else { Add-Member -InputObject $row -MemberType NoteProperty -Name $m -NotePropertyValue $val -Force } } catch {}
            }
        }
    }

    # Apply group pre-sort (simple group ascending)
    if ($Spec.Group -and $Spec.Group.Trim()) {
        $g = $Spec.Group.Trim()
        $rows = @($rows | Sort-Object -Property $g)
    }

    # Apply sort if specified
    Write-PmcDebug -Level 3 -Category 'QueryEvaluator' -Message 'Checking sort' -Data @{ Sort=$Spec.Sort; SortType=($Spec.Sort).GetType().Name }
    if ($Spec.Sort -and @($Spec.Sort).Count -gt 0) {
        $props = @()
        foreach ($s in $Spec.Sort) {
            $f = [string]$s.Field; if (-not $f) { continue }
            $asc = ($s.Dir -ne 'Desc')
            $props += @{ Expression = $f; Ascending = $asc }
        }
        if (@($props).Count -gt 0) { $rows = @($rows | Sort-Object -Property $props) }
    }

    return @{ Domain=$Spec.Domain; Rows=$rows }
}

Export-ModuleMember -Function Evaluate-PmcQuery