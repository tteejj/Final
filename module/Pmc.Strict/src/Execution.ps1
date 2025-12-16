# Execution pipeline for domain-action commands

function Set-PmcContextDefaults {
    param([PmcCommandContext]$Context)

    # Apply default values based on domain/action patterns
    # This function sets defaults for common arguments to simplify command usage

    if (-not $Context.Args) { $Context.Args = @{} }
    if (-not $Context.FreeText) { $Context.FreeText = @() }

    # Domain-specific defaults
    switch ($Context.Domain) {
        'task' {
            # For task operations, ensure priority defaults exist
            if ($Context.Action -in @('add', 'update', 'edit') -and -not $Context.Args.ContainsKey('priority')) {
                $Context.Args['priority'] = 0  # Default priority
            }
        }
        'project' {
            # Project operations may need defaults
            if ($Context.Action -eq 'add' -and -not $Context.Args.ContainsKey('status')) {
                $Context.Args['status'] = 'active'  # Default status
            }
        }
        'time' {
            # Time logging defaults
            if ($Context.Action -eq 'log' -and -not $Context.Args.ContainsKey('date')) {
                $Context.Args['date'] = (Get-Date).ToString('yyyy-MM-dd')  # Default to today
            }
        }
    }
}

function Normalize-PmcContextFields {
    param([PmcCommandContext]$Context)
    if (-not $Context -or -not $Context.Domain) { return }
    try {
        $schemas = Get-PmcFieldSchemasForDomain -Domain $Context.Domain
        foreach ($k in @($Context.Args.Keys)) {
            if ($schemas.ContainsKey($k)) {
                $sch = $schemas[$k]
                if ($sch.ContainsKey('Normalize') -and $sch.Normalize) {
                    try {
                        $Context.Args[$k] = & $sch.Normalize ([string]$Context.Args[$k])
                    } catch {
                        # Leave raw value; validation will surface the error later
                    }
                }
            }
        }
    } catch { }
}

function Resolve-PmcHandler {
    param([string]$Domain,[string]$Action)
    if (-not $Script:PmcCommandMap.ContainsKey($Domain)) { return $null }
    $map = $Script:PmcCommandMap[$Domain]
    if (-not $map.ContainsKey($Action)) { return $null }
    return $map[$Action]
}

function Resolve-PmcProjectFromTokens {
    param(
        [string[]] $Tokens,
        [int] $StartIndex
    )
    # Returns a hashtable: @{ Name = <string>; Consumed = <int> }
    # If no resolution, returns @{ Name=$null; Consumed=1 } (consume only the '@...' token)
    $result = @{ Name = $null; Consumed = 1 }
    if ($StartIndex -lt 0 -or $StartIndex -ge $Tokens.Count) { return $result }
    $first = $Tokens[$StartIndex]
    if (-not ($first -match '^@(.+)$')) { return $result }

    $initial = $matches[1]
    $candidates = @()
    try {
        $data = Get-PmcDataAlias
        $projects = @($data.projects | ForEach-Object { [string]$_.name })
        if (-not $projects) { return $result }

        # Greedily extend with following plain tokens (no prefixes, not '--')
        $bestName = $null
        $bestLen = 1
        $current = $initial
        if ($projects -contains $current) { $bestName = $current; $bestLen = 1 }

        for ($i = $StartIndex + 1; $i -lt $Tokens.Count; $i++) {
            $t = $Tokens[$i]
            if ($t -eq '--' -or $t -match '^@' -or $t -match '^(p[1-3])$' -or $t -match '^due:' -or $t -match '^#' -or $t -match '^-#') {
                break
            }
            $current = "$current $t"
            if ($projects -contains $current) { $bestName = $current; $bestLen = ($i - $StartIndex + 1) }
        }

        if ($bestName) {
            $result.Name = $bestName
            $result.Consumed = $bestLen
            return $result
        }
    } catch { }

    return $result
}

function Parse-PmcArgsFromTokens {
    param(
        [string[]] $Tokens,
        [int] $StartIndex = 0
    )

    $args = @{}
    $free = @()
    $seenPlain = $false
    for ($i = $StartIndex; $i -lt $Tokens.Count; $i++) {
        $t = $Tokens[$i]
        if ($seenPlain) { $free += $t; continue }
        if ($t -eq '--') { $seenPlain = $true; continue }
        if ($t -match '^@') {
            $res = Resolve-PmcProjectFromTokens -Tokens $Tokens -StartIndex $i
            if ($res.Name) { $args['project'] = $res.Name; $i += ($res.Consumed - 1); continue }
            if ($t -match '^@(.+)$') { $args['project'] = $matches[1]; continue }
        }
        if ($t -eq '-i') { $args['interactive'] = $true; continue }
        if ($t -match '^(?i)task:(\d+)$') { $args['taskId'] = [int]$matches[1]; continue }
        if ($t -match '^(p[1-3])$') { $args['priority'] = $matches[1]; continue }
        if ($t -match '^due:(.+)$') { $args['due'] = $matches[1]; continue }
        if ($t -match '^#(.+)$' -or $t -match '^\+(.+)$') { if (-not $args.ContainsKey('tags')) { $args['tags']=@() }; $args['tags'] += $matches[1]; continue }
        if ($t -match '^-#?(.+)$') { if (-not $args.ContainsKey('removeTags')) { $args['removeTags']=@() }; $args['removeTags'] += $matches[1]; continue }
        $seenPlain = $true
        $free += $t
    }
    return @{ Args = $args; Free = $free }
}

function ConvertTo-PmcIdSet {
    param([string]$text)
    $ids = @()
    foreach ($part in ($text -split ',')) {
        $p = $part.Trim()
        if ($p -match '^(\d+)-(\d+)$') { $a=[int]$matches[1]; $b=[int]$matches[2]; if ($a -le $b) { for ($i=$a; $i -le $b; $i++) { $ids += $i } } else { for ($i=$a; $i -ge $b; $i--) { $ids += $i } } }
        elseif ($p -match '^\d+$') { $ids += [int]$p }
    }
    return @($ids | Select-Object -Unique)
}

function ConvertTo-PmcContext {
    param([string[]]$Tokens)
    if ($Tokens.Count -lt 1) { return @{ Success=$false; Error='Empty command' } }

    # Special handling for 'help' so users can type: 'help', 'help guide [topic]', 'help examples [topic]', 'help query', 'help domain <d>', 'help command <d> <a>'
    if ($Tokens[0].ToLower() -eq 'help') {
        if ($Tokens.Count -eq 1) {
            $ctx = [PmcCommandContext]::new('help','show')
            $ctx.Raw = 'help show'
            return @{ Success=$true; Context=$ctx; Handler='Show-PmcSmartHelp' }
        } elseif ($Tokens.Count -ge 2) {
            $sub = $Tokens[1].ToLower()
            switch ($sub) {
                'guide' {
                    $ctx = [PmcCommandContext]::new('help','guide')
                    $ctx.Raw = ($Tokens -join ' ')
                    if ($Tokens.Count -ge 3) { $ctx.FreeText = @($Tokens[2]) }
                    return @{ Success=$true; Context=$ctx; Handler='Show-PmcHelpGuide' }
                }
                'search' {
                    $ctx = [PmcCommandContext]::new('help','search')
                    $ctx.Raw = ($Tokens -join ' ')
                    if ($Tokens.Count -ge 3) { $ctx.FreeText = @(($Tokens[2..($Tokens.Count-1)] -join ' ')) }
                    else { $ctx.FreeText = @('') }
                    return @{ Success=$true; Context=$ctx; Handler='Show-PmcHelpSearch' }
                }
                'examples' {
                    $ctx = [PmcCommandContext]::new('help','examples')
                    $ctx.Raw = ($Tokens -join ' ')
                    if ($Tokens.Count -ge 3) { $ctx.FreeText = @($Tokens[2]) }
                    return @{ Success=$true; Context=$ctx; Handler='Show-PmcHelpExamples' }
                }
                'query' {
                    $ctx = [PmcCommandContext]::new('help','query')
                    $ctx.Raw = ($Tokens -join ' ')
                    return @{ Success=$true; Context=$ctx; Handler='Show-PmcHelpQuery' }
                }
                'domain' {
                    $ctx = [PmcCommandContext]::new('help','domain')
                    $ctx.Raw = ($Tokens -join ' ')
                    if ($Tokens.Count -ge 3) { $ctx.FreeText = @($Tokens[2]) }
                    return @{ Success=$true; Context=$ctx; Handler='Show-PmcHelpDomain' }
                }
                'command' {
                    $ctx = [PmcCommandContext]::new('help','command')
                    $ctx.Raw = ($Tokens -join ' ')
                    if ($Tokens.Count -ge 4) { $ctx.FreeText = @($Tokens[2], $Tokens[3]) }
                    return @{ Success=$true; Context=$ctx; Handler='Show-PmcHelpCommand' }
                }
                default {
                    if ($Tokens.Count -eq 2) {
                        # Interpret as: help domain <domain>
                        $ctx = [PmcCommandContext]::new('help','domain')
                        $ctx.Raw = ($Tokens -join ' ')
                        $ctx.FreeText = @($Tokens[1])
                        return @{ Success=$true; Context=$ctx; Handler='Show-PmcHelpDomain' }
                    } else {
                        # Interpret as: help command <domain> <action>
                        $ctx = [PmcCommandContext]::new('help','command')
                        $ctx.Raw = ($Tokens -join ' ')
                        $ctx.FreeText = @($Tokens[1], $Tokens[2])
                        return @{ Success=$true; Context=$ctx; Handler='Show-PmcHelpCommand' }
                    }
                }
            }
        }
    }

    # Treat first token matching a shortcut as a shortcut command (with args)
    $firstToken = $Tokens[0].ToLower()
    if ($Script:PmcShortcutMap.ContainsKey($firstToken)) {
        $fn = $Script:PmcShortcutMap[$firstToken]
        $ctx = [PmcCommandContext]::new('shortcut', $firstToken)
        $ctx.Raw = ($Tokens -join ' ')
        $parsedArgs = Parse-PmcArgsFromTokens -Tokens $Tokens -StartIndex 1
        $ctx.Args = $parsedArgs.Args
        $ctx.FreeText = $parsedArgs.Free
        return @{ Success=$true; Context=$ctx; Handler=$fn }
    }

    # No fallback here — shortcuts must be initialized by the module loader

    # Standard domain-action parsing
    if ($Tokens.Count -lt 2) {
        return @{ Success=$false; Error='Missing action. Use: <domain> <action> [...] or use shortcuts like: add, done, list' }
    }
    $domain = $Tokens[0].ToLower()
    $action = $Tokens[1].ToLower()
    $fn = Resolve-PmcHandler -Domain $domain -Action $action
    if (-not $fn) {
        if (-not $Script:PmcCommandMap.ContainsKey($domain)) {
            return @{ Success=$false; Error="Unknown domain '$domain'" }
        }
        return @{ Success=$false; Error="Unknown action '$action' for domain '$domain'" }
    }
    $ctx = [PmcCommandContext]::new($domain,$action)
    $ctx.Raw = ($Tokens -join ' ')
    # Use AST-based parsing instead of regex-heavy token parsing
    $commandText = ($Tokens -join ' ')

    # Try AST-based parsing first
    try {
        if (Get-Command ConvertTo-PmcCommandAst -ErrorAction SilentlyContinue) {
            $astResult = ConvertTo-PmcCommandAst -CommandText $commandText
            $ctx.Args = $astResult.Args
            $ctx.FreeText = $astResult.FreeText
            Write-PmcDebug -Level 2 -Category 'Execution' -Message "Using AST-based argument parsing"
        } else {
            # Fallback to legacy parsing if AST not available
            $rest = @($Tokens | Select-Object -Skip 2)
            $parsed = Parse-PmcArgsFromTokens -Tokens $rest -StartIndex 0
            $ctx.Args = $parsed.Args
            $ctx.FreeText = $parsed.Free
            Write-PmcDebug -Level 2 -Category 'Execution' -Message "Using legacy token parsing"
        }
    } catch {
        Write-PmcDebug -Level 1 -Category 'Execution' -Message "AST parsing failed, using legacy: $_"
        # Fallback to legacy parsing
        $rest = @($Tokens | Select-Object -Skip 2)
        $parsed = Parse-PmcArgsFromTokens -Tokens $rest -StartIndex 0
        $ctx.Args = $parsed.Args
        $ctx.FreeText = $parsed.Free
    }
    # Normalize known field values using Field Schemas
    Normalize-PmcContextFields -Context $ctx
    return @{ Success=$true; Context=$ctx; Handler=$fn }
}

function Invoke-PmcCommand {
    param([Parameter(Mandatory=$true)][string]$Buffer)

    Write-PmcDebugCommand -Command $Buffer -Status 'START'

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # Expand user-defined aliases before tokenization
        # Check for alias expansion
        if (Get-Command Expand-PmcUserAliases -ErrorAction SilentlyContinue) {
            $Buffer = Expand-PmcUserAliases -Buffer $Buffer
        }

        $tokens = ConvertTo-PmcTokens $Buffer
        Write-PmcDebug -Level 2 -Category 'PARSER' -Message "Tokenized command" -Data @{ TokenCount = $tokens.Count; Tokens = $tokens }

        $parsed = ConvertTo-PmcContext $tokens
        if (-not $parsed.Success) {
            Write-PmcDebugCommand -Command $Buffer -Status 'PARSE_ERROR' -Context @{ Error = $parsed.Error } -Timing $stopwatch.ElapsedMilliseconds
            Write-PmcStyled -Style 'Error' -Text "Error: $($parsed.Error)"
            return
        }

        $fn = $parsed.Handler
        $ctx = $parsed.Context

        Write-PmcDebug -Level 2 -Category 'PARSER' -Message "Context parsed" -Data @{ Domain = $ctx.Domain; Action = $ctx.Action; ArgCount = $ctx.Args.Count; Handler = $fn }

        try {
            Set-PmcContextDefaults -Context $ctx
            Write-PmcDebug -Level 3 -Category 'COERCION' -Message "Context coerced" -Data @{ Args = $ctx.Args }
        } catch {
            Write-PmcDebug -Level 1 -Category 'COERCION' -Message "Coercion failed: $_"
        }

        try {
            $ok = Test-PmcContext -Context $ctx
            if (-not $ok) {
                Write-PmcDebugCommand -Command $Buffer -Status 'VALIDATION_ERROR' -Context @{ Domain = $ctx.Domain; Action = $ctx.Action } -Timing $stopwatch.ElapsedMilliseconds
                return
            }
            Write-PmcDebug -Level 3 -Category 'VALIDATION' -Message "Context validated successfully"
        } catch {
            Write-PmcDebug -Level 1 -Category 'VALIDATION' -Message "Validation failed: $_"
        }

        if (Get-Command -Name $fn -ErrorAction SilentlyContinue) {
            Write-PmcDebug -Level 2 -Category 'Execution' -Message "About to execute function: $fn"
            $cmdInfo = Get-Command -Name $fn -ErrorAction SilentlyContinue
            $srcFile = $null
            try { if ($cmdInfo -and $cmdInfo.CommandType -eq 'Function' -and $cmdInfo.ScriptBlock) { $srcFile = $cmdInfo.ScriptBlock.File } } catch { }
            $sourceInfo = $(if ($null -ne $srcFile) { $srcFile } else { '(unknown)' })
            Write-PmcDebug -Level 2 -Category 'EXECUTION' -Message "Invoking handler: $fn" -Data @{ Source = $sourceInfo }

            & $fn -Context $ctx

            $stopwatch.Stop()
            Write-PmcDebugCommand -Command $Buffer -Status 'SUCCESS' -Context @{ Domain = $ctx.Domain; Action = $ctx.Action; Handler = $fn } -Timing $stopwatch.ElapsedMilliseconds
        } else {
            Write-PmcDebugCommand -Command $Buffer -Status 'NO_HANDLER' -Context @{ Domain = $ctx.Domain; Action = $ctx.Action; Handler = $fn } -Timing $stopwatch.ElapsedMilliseconds
            Write-PmcStyled -Style 'Warning' -Text "Not implemented: $($ctx.Domain) $($ctx.Action)"
        }

    } catch {
        $stopwatch.Stop()
        Write-PmcDebugCommand -Command $Buffer -Status 'ERROR' -Context @{ Error = $_.ToString(); Exception = $_.Exception.GetType().Name } -Timing $stopwatch.ElapsedMilliseconds
        Write-PmcStyled -Style 'Error' -Text "Command execution failed: $_"
    }
}

function ConvertTo-PmcContextType {
    param([PmcCommandContext]$Context)
    if (-not $Context) { return }
    $key = "$($Context.Domain) $($Context.Action)".ToLower()
    $schema = $(if ($Script:PmcParameterMap.ContainsKey($key)) { $Script:PmcParameterMap[$key] } else { @() })
    if (-not $schema -or @($schema).Count -eq 0) { return }
    # TaskID: parse first free text token to ids if applicable
    $needsId = $false
    foreach ($def in $schema) { if ($def['Type'] -eq 'TaskID') { $needsId = $true; break } }
    if ($needsId -and @($Context.FreeText).Count -ge 1) {
        $t0 = $Context.FreeText[0]
        if ($t0 -match '^[0-9,\-]+$') {
            $set = ConvertTo-PmcIdSet $t0
            if (@($set).Count -gt 0) { $Context.Args['ids'] = $set }
        }
        elseif ($t0 -match '^\d+$') {
            # list index handled in handlers via map; still pass as singleton id candidate
            $Context.Args['ids'] = @([int]$t0)
        }
    }
    # Normalize priority string to int for convenience (add priorityInt) after schema normalization
    if ($Context.Args.ContainsKey('priority')) {
        $pv = [string]$Context.Args['priority']
        if ($pv -match '^[1-3]$') { $Context.Args['priorityInt'] = [int]$pv }
    }
    # Due already normalized by schema; add convenience dueIso if matches ISO
    if ($Context.Args.ContainsKey('due')) {
        $dv = [string]$Context.Args['due']
        if ($dv -match '^\d{4}-\d{2}-\d{2}$') { $Context.Args['dueIso'] = $dv }
    }

    # Resolve project names when schema expects a ProjectName
    $needsProject = $false
    foreach ($def in $schema) { if ($def['Type'] -eq 'ProjectName') { $needsProject = $true; break } }
    if ($needsProject -and $Context.Args.ContainsKey('project')) {
        try { $data = Get-PmcDataAlias; $p = Resolve-Project -Data $data -Name $Context.Args['project']; if ($p) { $Context.Args['projectNameResolved'] = $p.name } } catch {
            # Project resolution failed - continue without resolved name
        }
    }

    # Parse duration tokens for commands that expect Duration
    $needsDuration = $false
    foreach ($def in $schema) { if ($def['Type'] -eq 'Duration') { $needsDuration = $true; break } }
    if ($needsDuration) {
        $durTok = $null
        foreach ($t in $Context.FreeText) {
            if ($t -match '^\d+(?:\.\d+)?$' -or $t -match '^\d+(?:\.\d+)?h$' -or $t -match '^\d+m$') { $durTok = $t; break }
        }
        if ($durTok) {
            try { $mins = ConvertTo-PmcDurationMinutes $durTok; if ($mins -gt 0) { $Context.Args['durationMinutes'] = $mins } } catch {
                # Duration parsing failed - continue without duration
            }
        }
    }
}

function Test-PmcContext {
    param([PmcCommandContext]$Context)
    $key = "$($Context.Domain) $($Context.Action)".ToLower()
    $schema = $(if ($Script:PmcParameterMap.ContainsKey($key)) { $Script:PmcParameterMap[$key] } else { @() })
    if (-not $schema -or @($schema).Count -eq 0) { return $true }
    $errors = @()
    # Check required schema elements
    foreach ($def in $schema) {
        $name = [string]$def['Name']
        $type = [string]$def['Type']
        $required = $false; try { $required = [bool]$def['Required'] } catch {
            # Schema definition access failed - assume not required
        }
        if (-not $required) { continue }
        switch ($type) {
            'FreeText' {
                if (-not $Context.FreeText -or @($Context.FreeText).Count -eq 0) { $errors += "Missing required text" }
            }
            'TaskID' {
                $hasIds = ($Context.Args.ContainsKey('ids') -and @($Context.Args['ids']).Count -gt 0)
                $hasToken = (@($Context.FreeText).Count -ge 1)
                if (-not $hasIds -and -not $hasToken) { $errors += "Missing required id(s)" }
            }
            'ProjectName' {
                if (-not $Context.Args.ContainsKey('project')) { $errors += "Missing required @project" }
            }
            'Priority' {
                if (-not $Context.Args.ContainsKey('priority') -and -not $Context.Args.ContainsKey('priorityInt')) { $errors += "Missing required priority (p1/p2/p3)" }
            }
            'DateString' {
                if (-not $Context.Args.ContainsKey('due') -and -not $Context.Args.ContainsKey('dueIso')) { $errors += "Missing required date" }
            }
            'DateRange' {
                # If required, ensure at least one recognizable token exists
                $has = $false
                foreach ($t in $Context.FreeText) {
                    if ($t -match '^(?i)today|yesterday|week$' -or $t -match '^\d{4}-\d{2}-\d{2}$') { $has=$true; break }
                }
                if (-not $has) { $errors += "Missing required date range" }
            }
            'Duration' {
                if (-not $Context.Args.ContainsKey('durationMinutes')) {
                    $hasLike = $false
                    foreach ($t in $Context.FreeText) { if ($t -match '^\d+(?:\.\d+)?$' -or $t -match '^\d+(?:\.\d+)?h$' -or $t -match '^\d+m$') { $hasLike=$true; break } }
                    if (-not $hasLike) { $errors += "Missing required duration (e.g., 1.5 hours or 90m)" }
                }
            }
            default { }
        }
    }
    # Field-level validation via Field Schemas
    try {
        $schemas = Get-PmcFieldSchemasForDomain -Domain $Context.Domain
        foreach ($k in @($Context.Args.Keys)) {
            if ($schemas.ContainsKey($k)) {
                $sch = $schemas[$k]
                if ($sch.ContainsKey('Validate') -and $sch.Validate) {
                    try { & $sch.Validate ([string]$Context.Args[$k]) | Out-Null } catch { $errors += $_.Exception.Message }
                }
            }
        }
    } catch { }

    # Basic tag validation if tags present
    if ($Context.Args.ContainsKey('tags')) {
        foreach ($tag in @($Context.Args['tags'])) { if (-not $tag -or ($tag -match '\s')) { $errors += ("Invalid tag '{0}'" -f $tag) } }
    }
    if (@($errors).Count -gt 0) {
        foreach ($e in $errors) { Write-PmcStyled -Style 'Error' -Text ("Error: {0}" -f $e) }
        return $false
    }
    return $true
}

Export-ModuleMember -Function Set-PmcContextDefaults, Normalize-PmcContextFields, Resolve-PmcHandler, Resolve-PmcProjectFromTokens, Parse-PmcArgsFromTokens, ConvertTo-PmcIdSet, ConvertTo-PmcContext, Invoke-PmcCommand, ConvertTo-PmcContextType, Test-PmcContext