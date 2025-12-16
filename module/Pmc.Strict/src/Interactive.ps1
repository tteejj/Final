# t2.ps1-Style Interactive Engine for PMC
# Complete implementation with inline cycling, history, undo/redo, and comprehensive instrumentation
# IMPORTANT: Completions MUST be plain strings. PSObjects/PSCustomObject and
# PSReadLine-style completion objects are not supported by this custom Console.ReadKey
# engine. Using objects breaks input flow and causes type/serialization errors.

Set-StrictMode -Version Latest

# Completions are simple strings throughout the system
# Classes remain defined in the main .psm1 file if needed elsewhere

# Centralized interactive state accessors (state-only)
function Pmc-GetEditor { $e = Get-PmcState -Section 'Interactive' -Key 'Editor'; if ($null -eq $e) { $e = [PmcEditorState]::new(); Set-PmcState -Section 'Interactive' -Key 'Editor' -Value $e }; return $e }
function Pmc-SetEditor($e) { Set-PmcState -Section 'Interactive' -Key 'Editor' -Value $e }
function Pmc-GetCache { $c = Get-PmcState -Section 'Interactive' -Key 'CompletionCache'; if ($null -eq $c) { $c=@{}; Set-PmcState -Section 'Interactive' -Key 'CompletionCache' -Value $c }; return $c }
function Pmc-SetCache($c) { Set-PmcState -Section 'Interactive' -Key 'CompletionCache' -Value $c }
function Pmc-ClearCache { $c = Pmc-GetCache; $c.Clear() | Out-Null; Pmc-SetCache $c }
function Pmc-GetGhost { $g = Get-PmcState -Section 'Interactive' -Key 'GhostTextEnabled'; if ($null -eq $g) { $g=$false; Set-PmcState -Section 'Interactive' -Key 'GhostTextEnabled' -Value $g }; return [bool]$g }
function Pmc-SetGhost([bool]$g) { Set-PmcState -Section 'Interactive' -Key 'GhostTextEnabled' -Value $g }
function Pmc-GetInfoMap { $m = Get-PmcState -Section 'Interactive' -Key 'CompletionInfoMap'; if ($null -eq $m) { $m=@{}; Set-PmcState -Section 'Interactive' -Key 'CompletionInfoMap' -Value $m }; return $m }
function Pmc-SetInfoMap($m) { Set-PmcState -Section 'Interactive' -Key 'CompletionInfoMap' -Value $m }

# Insert literal text at cursor and re-render input line
function Pmc-InsertAtCursor {
    param([Parameter(Mandatory=$true)][string]$Text)
    try {
        $ed = Pmc-GetEditor
        $before = $ed.Buffer
        $pos = [Math]::Max(0, [Math]::Min($ed.CursorPos, $before.Length))
        $ed.Buffer = $before.Substring(0, $pos) + $Text + $before.Substring($pos)
        $ed.CursorPos = $pos + $Text.Length
        Render-Interactive -Buffer $ed.Buffer -CursorPos $ed.CursorPos -InCompletion $false
    } catch {}
}

# Fuzzy matching utilities (subsequence with ranking)
function Invoke-PmcFuzzyFilter {
    param(
        [string[]] $Items,
        [string] $Query
    )
    if (-not $Items) { return @() }
    if ([string]::IsNullOrWhiteSpace($Query)) { return ,@($Items) }

    $q = $Query.ToLowerInvariant()
    $scored = @()
    foreach ($it in $Items) {
        $s = [string]$it
        $t = $s.ToLowerInvariant()
        $rank = $null
        if ($t.StartsWith($q)) { $rank = 0 }
        elseif ($t.Contains($q)) { $rank = 1 }
        elseif (Test-PmcSubsequence -Haystack $t -Needle $q) { $rank = 2 }
        if ($rank -ne $null) { $scored += [pscustomobject]@{ Item=$s; Rank=$rank } }
    }
    $ordered = $scored | Sort-Object Rank, @{Expression={$_.Item.Length}; Ascending=$true}, Item
    return @($ordered | Select-Object -ExpandProperty Item)
}

function Test-PmcSubsequence {
    param([string] $Haystack, [string] $Needle)
    if ([string]::IsNullOrEmpty($Needle)) { return $true }
    $i = 0; $j = 0
    while ($i -lt $Haystack.Length -and $j -lt $Needle.Length) {
        if ($Haystack[$i] -eq $Needle[$j]) { $j++ }
        $i++
    }
    return ($j -eq $Needle.Length)
}

function Initialize-PmcCompletionInfoMap {
    $map = @{}

    # Domain descriptions
    $map['task']      = @{ Description = 'Task management';       Category = 'Domain' }
    $map['project']   = @{ Description = 'Project management';     Category = 'Domain' }
    $map['time']      = @{ Description = 'Time logging/reporting'; Category = 'Domain' }
    $map['timer']     = @{ Description = 'Timers';                 Category = 'Domain' }
    $map['view']      = @{ Description = 'Predefined views';       Category = 'Domain' }
    $map['focus']     = @{ Description = 'Focus mode';             Category = 'Domain' }
    $map['system']    = @{ Description = 'System ops';             Category = 'Domain' }
    $map['config']    = @{ Description = 'Configuration';          Category = 'Domain' }
    $map['excel']     = @{ Description = 'Excel I/O';              Category = 'Domain' }
    $map['theme']     = @{ Description = 'Theme settings';         Category = 'Domain' }
    $map['activity']  = @{ Description = 'Activity log';           Category = 'Domain' }
    $map['template']  = @{ Description = 'Templates';              Category = 'Domain' }
    $map['recurring'] = @{ Description = 'Recurring rules';        Category = 'Domain' }
    $map['alias']     = @{ Description = 'Aliases';                Category = 'Domain' }
    $map['dep']       = @{ Description = 'Dependencies';           Category = 'Domain' }
    $map['import']    = @{ Description = 'Import data';            Category = 'Domain' }
    $map['export']    = @{ Description = 'Export data';            Category = 'Domain' }
    $map['show']      = @{ Description = 'Show info';              Category = 'Domain' }
    $map['interactive']= @{ Description = 'Interactive mode';      Category = 'Domain' }
    $map['help']      = @{ Description = 'Help';                   Category = 'Domain' }

    # Domain:Action descriptions (keyed as "domain:action")
    $pairs = @(
        'task:add=Add new task','task:list=List tasks','task:done=Mark task done','task:edit=Edit task','task:delete=Delete task','task:view=View task','task:search=Search tasks',
        'project:add=Add project','project:list=List projects','project:view=View project','project:update=Update project','project:rename=Rename project','project:delete=Delete project','project:archive=Archive project','project:set-fields=Set custom fields','project:show-fields=Show custom fields','project:stats=Project statistics','project:info=Project info','project:recent=Recent projects',
        'time:log=Log time','time:list=List entries','time:report=Report','time:edit=Edit entries',
        'timer:start=Start timer','timer:stop=Stop timer','timer:status=Timer status',
        'view:today=Today view','view:tomorrow=Tomorrow view','view:overdue=Overdue tasks','view:upcoming=Upcoming','view:blocked=Blocked','view:noduedate=No due date','view:projects=Projects overview','view:next=Next actions',
        'focus:set=Set focus','focus:clear=Clear focus','focus:status=Focus status',
        'system:undo=Undo last action','system:redo=Redo last action','system:backup=Create backup','system:clean=Clean data',
        'config:show=Show config','config:edit=Edit config','config:set=Set config','config:icons=Icon config',
        'excel:import=Import from Excel','excel:view=View excel output','excel:export=Export to Excel',
        'theme:set=Set theme','theme:list=List themes','theme:create=Create theme','theme:edit=Edit theme',
        'activity:log=Log activity','activity:list=List activity','activity:report=Activity report',
        'template:create=Create template','template:list=List templates','template:apply=Apply template','template:edit=Edit template','template:delete=Delete template',
        'recurring:add=Add recurring rule','recurring:list=List recurring rules','recurring:edit=Edit recurring rule','recurring:delete=Delete recurring rule','recurring:process=Process recurring',
        'alias:add=Add alias','alias:list=List aliases','alias:edit=Edit alias','alias:delete=Delete alias',
        'dep:add=Add dependency','dep:list=List dependencies','dep:remove=Remove dependency','dep:check=Check dependencies',
        'import:excel=Import from Excel','import:csv=Import from CSV','import:json=Import from JSON','import:outlook=Import from Outlook',
        'export:excel=Export to Excel','export:csv=Export to CSV','export:json=Export to JSON','export:ical=Export to iCal',
        'show:status=Show status','show:config=Show config','show:help=Show help','show:version=Show version',
        'interactive:enable=Enable interactive','interactive:disable=Disable interactive','interactive:status=Interactive status',
        'help:commands=Help commands','help:examples=Help examples','help:guide=Help guide','help:quick=Quick help'
    )
    foreach ($pair in $pairs) {
        $kv = $pair.Split('=')
        $map[$kv[0]] = @{ Description = $kv[1]; Category = 'Action' }
    }

    # Common argument suggestions
    $map['due:today'] = @{ Description = 'Due today';    Category = 'Argument' }
    $map['due:tomorrow'] = @{ Description = 'Due tomorrow'; Category = 'Argument' }
    $map['due:friday'] = @{ Description = 'Due Friday';  Category = 'Argument' }
    $map['due:+1w'] = @{ Description = 'Due +1 week';    Category = 'Argument' }
    $map['due:+1m'] = @{ Description = 'Due +1 month';   Category = 'Argument' }
    $map['p1'] = @{ Description = 'Priority 1'; Category = 'Argument' }
    $map['p2'] = @{ Description = 'Priority 2'; Category = 'Argument' }
    $map['p3'] = @{ Description = 'Priority 3'; Category = 'Argument' }
    $map['#urgent'] = @{ Description = 'Urgent tag'; Category = 'Argument' }
    $map['#bug']    = @{ Description = 'Bug tag'; Category = 'Argument' }
    $map['#feature']= @{ Description = 'Feature tag'; Category = 'Argument' }
    $map['#review'] = @{ Description = 'Review tag'; Category = 'Argument' }

    Pmc-SetInfoMap $map
}

function Get-PmcCompletionInfo {
    param(
        [string] $Domain,
        [string] $Action,
        [string] $Text
    )
    if ($Action) {
        $d = $null
        if ($Domain) { $d = $Domain.ToLower() }
        $a = $Action.ToLower()
        $key = "${d}:${a}"
        return (Pmc-GetInfoMap)[$key]
    }
    if ($Text) { return (Pmc-GetInfoMap)[$Text.ToLower()] }
    return $null
}

# High-level renderer that computes transient help text before delegating to Render-Line
function Render-Interactive {
    param(
        [string] $Buffer,
        [int] $CursorPos,
        [int] $IndicatorIndex = 0,
        [int] $IndicatorCount = 0,
        [bool] $InCompletion = $false
    )

    $helpText = $null
    $ghostText = ""
    if (-not $InCompletion) {
        try {
            $ctx = Parse-CompletionContext -Buffer $Buffer -CursorPos $CursorPos
            if ($ctx.Mode -eq [PmcCompletionMode]::Domain) {
                if ($ctx.CurrentToken) {
                    $info = Get-PmcCompletionInfo -Text $ctx.CurrentToken
                    if ($info) { $helpText = $info.Description }
                }
            } elseif ($ctx.Mode -eq [PmcCompletionMode]::Action) {
                if ($ctx.Tokens.Count -gt 0 -and $ctx.CurrentToken) {
                    $info = Get-PmcCompletionInfo -Domain $ctx.Tokens[0] -Action $ctx.CurrentToken
                    $summary = Pmc-FormatSchemaSummary -Domain $ctx.Tokens[0] -Action $ctx.CurrentToken
                    if ($summary) { $helpText = $summary }
                    elseif ($info) { $helpText = $info.Description }
                }
            } elseif ($ctx.Mode -eq [PmcCompletionMode]::Arguments) {
                $dom = $null; if ($ctx.Tokens.Count -gt 0) { $dom = $ctx.Tokens[0] }
                $act = $null; if ($ctx.Tokens.Count -gt 1) { $act = $ctx.Tokens[1] }
                if ($dom -and $act) {
                    $summary = Pmc-FormatSchemaSummary -Domain $dom -Action $act
                    if ($summary) { $helpText = $summary }
                } elseif ($ctx.CurrentToken) {
                    $info = Get-PmcCompletionInfo -Text $ctx.CurrentToken
                    if ($info) { $helpText = $info.Description }
                }
            }
            # Compute ghost text (inline suggestion) - DISABLED
            $ghostText = ""

            # No numeric suggestion line; keep help minimal and passive
        } catch {}
    }

    Render-Line -Buffer $Buffer -CursorPos $CursorPos -IndicatorIndex $IndicatorIndex -IndicatorCount $IndicatorCount -InCompletion $InCompletion -HelpText $helpText -GhostText $ghostText
}

# Build a compact argument summary from schema for inline guidance
function Pmc-FormatSchemaSummary {
    param([string]$Domain,[string]$Action)
    if (-not $Domain -or -not $Action) { return $null }
    try {
        $schema = Get-PmcSchema -Domain $Domain -Action $Action
        if (-not $schema -or @($schema).Count -eq 0) { return $null }
        $parts = @()
        foreach ($def in $schema) {
            $name = [string]$def['Name']
            $type = [string]$def['Type']
            $prefix = [string]$def['Prefix']
            $req = [bool]$def['Required']
            $allowsMulti = [bool]$def['AllowsMultiple']

            $token = $null
            switch ($type) {
                'ProjectName' { $token = '@project' }
                'Priority'    { $token = 'p1|p2|p3' }
                'DateString'  { $token = 'due:YYYY-MM-DD' }
                'TagName'     { if ($allowsMulti) { $token = '#tag...' } else { $token = '#tag' } }
                'TaskID'      { $token = '<id>' }
                'Duration'    { $token = '<duration>' }
                'DateRange'   { $token = '<range>' }
                default {
                    if ($prefix) { $token = "$prefix$name" }
                    elseif ($name -match '^(?i)text$') { $token = '<text>' }
                    else { $token = "<$name>" }
                }
            }

            if (-not $req) { $token = "[$token]" }
            $parts += $token
        }
        if ($parts.Count -gt 0) { return ('Args: ' + ($parts -join ' ')) }
    } catch {}
    return $null
}

# Helper function removed - we now use simple strings instead of PSCustomObjects
# This eliminates the dual completion path issue where PSCustomObjects were being created

# Debug helper: log state transitions at Debug2
function Write-StateChange {
    param(
        [string] $KeyName,
        [hashtable] $BeforeCtx,
        [bool] $BeforeInCompletion
    )
    try {
        $ed = Pmc-GetEditor
        $afterCtx = Parse-CompletionContext -Buffer $ed.Buffer -CursorPos $ed.CursorPos
        $afterIn = $ed.InCompletion
        Write-PmcDebug -Level 2 -Category 'STATE' -Message "Key=$KeyName InCompletion: $BeforeInCompletion->$afterIn Mode: $($BeforeCtx.Mode)->$($afterCtx.Mode) BufferLen=$($ed.Buffer.Length) Cursor=$($ed.CursorPos)"
    } catch {
        # Ghost text computation failed - return empty string
    }
}

# Compute ghost hint text based on current context (pure)
function Compute-GhostText {
    param(
        [string] $Buffer,
        [hashtable] $Context
    )

    if (-not (Pmc-GetGhost)) { return "" }

    try {
        $ghost = ""
        $hasTrailingSpace = $Buffer.EndsWith(' ')

        if ($Context.Mode -eq [PmcCompletionMode]::Domain) {
            # Show domain hints when starting or when current token is incomplete
            if ([string]::IsNullOrEmpty($Context.CurrentToken) -or -not $hasTrailingSpace) {
                $ghost = " task|project|time..."
            }
        } elseif ($Context.Mode -eq [PmcCompletionMode]::Action) {
            # Show action hints when we have a domain and are ready for action
            if ($Context.Tokens.Count -ge 1 -and $hasTrailingSpace) {
                $domain = $Context.Tokens[0].ToLower()
                switch ($domain) {
                    'task' { $ghost = " add|list|done|edit" }
                    'project' { $ghost = " add|list|view|edit" }
                    'time' { $ghost = " log|report|list" }
                    'timer' { $ghost = " start|stop|status" }
                    'view' { $ghost = " today|tomorrow|overdue" }
                    'focus' { $ghost = " set|clear|status" }
                    'system' { $ghost = " undo|redo|backup" }
                    'config' { $ghost = " show|edit|set" }
                    default { $ghost = " help" }
                }
            }
        } elseif ($Context.Mode -eq [PmcCompletionMode]::Arguments) {
            # Show argument hints when we have domain and action
            if ($Context.Tokens.Count -ge 2 -and $hasTrailingSpace) {
                $ghost = " @project due:date p1-3 #tags"
            }
        }

        Write-PmcDebug -Level 3 -Category 'GHOST' -Message "Ghost computation: Mode=$($Context.Mode), Tokens=[$($Context.Tokens -join ', ')], HasTrailingSpace=$hasTrailingSpace, Ghost='$ghost'"
        return $(if ($null -ne $ghost) { $ghost } else { "" })
    } catch {
        Write-PmcDebug -Level 1 -Category 'GHOST' -Message "Ghost computation error: $_"
        return ""
    }
}

# Get terminal dimensions for TUI layout
function Get-TerminalSize {
    return [PmcTerminalService]::GetDimensions()
}

# Clear screen and position cursor for command output
function Clear-CommandOutput {
    [Console]::Write("`e[2J`e[H")  # Clear screen + move to top
    [Console]::Out.Flush()
}

# Simplified inline renderer for compatibility
function Render-Line {
    param(
        [string] $Buffer,
        [int] $CursorPos,
        [int] $IndicatorIndex = 0,
        [int] $IndicatorCount = 0,
        [bool] $InCompletion = $false,
        [string] $HelpText = $null,
        [string] $GhostText = $null
    )

    $prompt = "pmc> "
    $promptLen = $prompt.Length

    # Compute indicator text
    $indicatorText = ''
    if ($IndicatorCount -gt 1) {
        $displayIndex = [Math]::Max(1, $IndicatorIndex)
        $indicatorText = " ($displayIndex/$IndicatorCount)"
    }

    # Two-line HUD: input at last-1 row, help at last row
    $term = Get-TerminalSize
    $inputRow = [Math]::Max(1, $term.Height - 1)
    $helpRow = $term.Height

    # Compute visible input line (truncate to width)
    $lineCore = "$prompt$Buffer$indicatorText"
    if ($lineCore.Length -gt $term.Width) {
        # Prefer to keep cursor region visible; simple right-trim for now
        $lineCore = $lineCore.Substring(0, $term.Width)
    }

    # Compute help line (truncate to width)
    $helpOut = ''
    if ($HelpText -and $HelpText.Trim().Length -gt 0) {
        $helpOut = $HelpText.Trim()
        if ($helpOut.Length -gt $term.Width) { $helpOut = $helpOut.Substring(0, $term.Width) }
    }

    # Clear the two bottom lines and render
    [Console]::Write("`e[${inputRow};1H`e[2K")
    [Console]::Write($lineCore)

    # Ghost text rendering disabled
    [Console]::Write("`e[${helpRow};1H`e[2K")
    if ($helpOut) { [Console]::Write($helpOut) }
    [Console]::Out.Flush()

    # Restore cursor to input line/column
    # Place caret at the insertion point (after the last typed character)
    $targetCol = [Math]::Min($term.Width, $promptLen + $CursorPos + 1)
    if ($targetCol -lt 1) { $targetCol = 1 }
    [Console]::Write("`e[${inputRow};${targetCol}H")
    [Console]::Out.Flush()

    Write-PmcDebug -Level 2 -Category 'RENDER' -Message "Bottom HUD render: bufferLen=$($Buffer.Length), cursorPos=$CursorPos, width=$($term.Width)"
}

# No conversion factory: completions are plain strings by design

# Tokenization: compute current token boundaries for replacement
function Get-TokenBoundaries {
    param(
        [string] $Buffer,
        [int] $CursorPos
    )

    if ([string]::IsNullOrEmpty($Buffer)) {
        return @{ Start = 0; End = 0; Token = "" }
    }

    # Find token boundaries around cursor
    $start = $CursorPos
    $end = $CursorPos

    # Move start backward to beginning of current token
    while ($start -gt 0 -and $Buffer[$start - 1] -ne ' ') {
        $start--
    }

    # Move end forward to end of current token
    while ($end -lt $Buffer.Length -and $Buffer[$end] -ne ' ') {
        $end++
    }

    $token = $(if ($start -lt $Buffer.Length -and $end -gt $start) {
        $Buffer.Substring($start, $end - $start)
    } else {
        ""
    })

    return @{
        Start = $start
        End = $end
        Token = $token
    }
}

# Parse buffer to determine completion mode and context
function Parse-CompletionContext {
    param(
        [string] $Buffer,
        [int] $CursorPos
    )

    # Use the same tokenizer as the rest of the system for consistency
    $tokens = ConvertTo-PmcTokens $Buffer
    $tokenInfo = Get-TokenBoundaries -Buffer $Buffer -CursorPos $CursorPos

    $mode = [PmcCompletionMode]::Domain
    $currentToken = $tokenInfo.Token

    # Determine completion mode based on token position and trailing space
    $hasTrailingSpace = $Buffer.EndsWith(' ')

    if ($tokens.Count -eq 0) {
        $mode = [PmcCompletionMode]::Domain
    } elseif ($tokens.Count -eq 1 -and -not $hasTrailingSpace) {
        # Still typing first token (domain)
        $mode = [PmcCompletionMode]::Domain
    } elseif ($tokens.Count -eq 1 -and $hasTrailingSpace) {
        # First token complete, ready for action
        $mode = [PmcCompletionMode]::Action
    } elseif ($tokens.Count -eq 2 -and -not $hasTrailingSpace) {
        # Still typing second token (action)
        $mode = [PmcCompletionMode]::Action
    } elseif ($tokens.Count -eq 2 -and $hasTrailingSpace) {
        # Domain and action complete, ready for arguments
        $mode = [PmcCompletionMode]::Arguments
    } elseif ($tokens.Count -ge 3) {
        # In arguments phase
        $mode = [PmcCompletionMode]::Arguments
    } else {
        $mode = [PmcCompletionMode]::FreeText
    }

    Write-PmcDebug -Level 3 -Category 'COMPLETION' -Message "Parsed context: Tokens=[$($tokens -join ', ')], Mode=$mode (tokenCount=$($tokens.Count), hasTrailingSpace=$hasTrailingSpace)"

    return @{
        Mode = $mode
        CurrentToken = $currentToken
        TokenStart = $tokenInfo.Start
        TokenEnd = $tokenInfo.End
        Tokens = $tokens
    }
}

# Domain completion provider
function Get-PmcDomainCompletions {
    param(
        [string] $Filter = ""
    )

    Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Getting domain completions for filter='$Filter'"

    try {
        # Simple string array - no objects, no type conversion issues
        $domains = @(
            "task", "project", "time", "timer", "view", "focus",
            "system", "config", "excel", "theme", "activity",
            "template", "recurring", "alias", "dep", "import",
            "export", "show", "interactive", "help"
        )

        # Add shortcut commands from the shortcut map
        $shortcuts = @()
        if ($Script:PmcShortcutMap -and $Script:PmcShortcutMap.Keys) {
            $shortcuts = @($Script:PmcShortcutMap.Keys)
        }

        # Combine domains and shortcuts
        $allCompletions = $domains + $shortcuts

        $result = Invoke-PmcFuzzyFilter -Items $allCompletions -Query $Filter
        Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Domain completions: found $(@($result).Count) items"
        return ,@($result)

    } catch {
        Write-PmcDebug -Level 1 -Category 'COMPLETION' -Message "Domain completion error: $_"
        return @()
    }
}

# Action completion provider
function Get-PmcActionCompletions {
    param([string] $Domain = "", [string] $Filter = "")

    Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Getting action completions for domain='$Domain', filter='$Filter'"

    try {
        $actions = @()

        switch ($Domain.ToLower()) {
            'task' {
                $actions = @("add", "list", "done", "edit", "delete", "view", "search")
            }
            'project' {
                $actions = @("add", "list", "view", "update", "rename", "delete", "archive", "set-fields", "show-fields", "stats", "info", "recent")
            }
            'time' {
                $actions = @("log", "list", "report", "edit")
            }
            'timer' {
                $actions = @("start", "stop", "status")
            }
            'view' {
                $actions = @("today", "tomorrow", "overdue", "upcoming", "blocked", "noduedate", "projects", "next")
            }
            'focus' {
                $actions = @("set", "clear", "status")
            }
            'system' {
                $actions = @("undo", "redo", "backup", "clean")
            }
            'config' {
                $actions = @("show", "edit", "set", "icons")
            }
            'excel' {
                $actions = @("import", "view", "export")
            }
            'theme' {
                $actions = @("set", "list", "create", "edit")
            }
            'activity' {
                $actions = @("log", "list", "report")
            }
            'template' {
                $actions = @("create", "list", "apply", "edit", "delete")
            }
            'recurring' {
                $actions = @("add", "list", "edit", "delete", "process")
            }
            'alias' {
                $actions = @("add", "list", "edit", "delete")
            }
            'dep' {
                $actions = @("add", "list", "remove", "check")
            }
            'import' {
                $actions = @("excel", "csv", "json", "outlook")
            }
            'export' {
                $actions = @("excel", "csv", "json", "ical")
            }
            'show' {
                $actions = @("status", "config", "help", "version")
            }
            'interactive' {
                $actions = @("enable", "disable", "status")
            }
            'help' {
                $actions = @("commands", "examples", "guide", "quick")
            }
            default {
                return @()
            }
        }

        $result = Invoke-PmcFuzzyFilter -Items $actions -Query $Filter
        Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Action completions: found $(@($result).Count) items"
        return ,@($result)

    } catch {
        Write-PmcDebug -Level 1 -Category 'COMPLETION' -Message "Error in Get-PmcActionCompletions: $_"
        return @()
    }
}

# Argument completion provider (projects, dates, priorities, etc.)
function Get-PmcArgumentCompletions {
    param(
        [string] $Domain,
        [string] $Action,
        [string] $Filter = ""
    )

    Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Getting argument completions for domain='$Domain' action='$Action' filter='$Filter'"

    try {
        $completions = @()

        # Project completions (@project)
        if ($Filter.StartsWith('@') -or [string]::IsNullOrEmpty($Filter)) {
            try {
                $data = Get-PmcData
                $projects = @($data.projects)
                $all = @()
                foreach ($project in $projects) { $all += ("@" + [string]$project.name) }
                $needle = $(if ($Filter -like '@*') { $Filter } else { '@' + $Filter })
                $filtered = Invoke-PmcFuzzyFilter -Items $all -Query $needle
                $completions += $filtered
            } catch {
                Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Project loading error: $_"
            }
        }

        # Date completions (due:)
        if ($Filter.StartsWith('due') -or [string]::IsNullOrWhiteSpace($Filter)) {
            $dates = @("due:today", "due:tomorrow", "due:friday", "due:+1w", "due:+1m", "due>today", "due<today", "due>=today", "due<=today", "due>2024-12-31", "due<2024-12-31")
            $completions += (Invoke-PmcFuzzyFilter -Items $dates -Query $Filter)
        }

        # Priority completions
        if ($Filter.StartsWith('p') -or [string]::IsNullOrWhiteSpace($Filter)) {
            $priorities = @("p1", "p2", "p3", "p<=1", "p<=2", "p<=3", "p>=1", "p>=2", "p>=3", "p>1", "p>2", "p<2", "p<3")
            $completions += (Invoke-PmcFuzzyFilter -Items $priorities -Query $Filter)
        }

        # '#' handling: for time log, '#' means ID1 time codes (2-5 digits).
        # Otherwise, '#' is tag completion.
        if ($Filter.StartsWith('#') -or [string]::IsNullOrWhiteSpace($Filter)) {
            if (($Domain -eq 'time') -and ($Action -eq 'log')) {
                try {
                    $data = Get-PmcDataAlias
                    $codes = @()
                    foreach ($l in $data.timelogs) {
                        try { if ($l.PSObject.Properties['id1'] -and $l.id1 -match '^\d{2,5}$') { $codes += ('#' + [string]$l.id1) } } catch {}
                    }
                    $codes = @($codes | Select-Object -Unique)
                    if ($codes.Count -gt 0) { $completions += (Invoke-PmcFuzzyFilter -Items $codes -Query $Filter) }
                } catch {}
            } else {
                $tags = @()
                try {
                    $data = Get-PmcDataAlias
                    foreach ($t in $data.tasks) {
                        try {
                            if ($t -and $t.PSObject.Properties['tags']) {
                                foreach ($tg in @($t.tags)) { if ($tg) { $tags += ("#" + [string]$tg) } }
                            }
                        } catch {}
                    }
                } catch {}
                if ($tags.Count -eq 0) { $tags = @("#urgent", "#todo", "#review") }
                $tags = @($tags | Select-Object -Unique)
                $completions += (Invoke-PmcFuzzyFilter -Items $tags -Query $Filter)
            }
        }

        # Add query history suggestions if no specific prefix
        if ([string]::IsNullOrWhiteSpace($Filter) -or ($Filter.Length -eq 1 -and $Filter -match '^[a-z]$')) {
            try {
                $history = Get-PmcQueryHistory -Last 5
                $historyCompletions = @()
                foreach ($h in $history) {
                    if ($h -and $h.Trim() -ne '' -and $h -notlike "*$Filter*") { continue }
                    $historyCompletions += "◄ $h"
                }
                $completions += $historyCompletions
            } catch {
                Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "History loading error: $_"
            }
        }

        Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Argument completions: found $(@($completions).Count) items"
        return ,@($completions)

    } catch {
        Write-PmcDebug -Level 1 -Category 'COMPLETION' -Message "Argument completion error: $_"
        return @()
    }
}

# Get completions with caching and comprehensive instrumentation
function Get-CompletionsForState {
    param(
        [hashtable] $Context
    )

    # Try AST-based completion first
    try {
        if (Get-Command Get-PmcCompletionsFromAst -ErrorAction SilentlyContinue) {
            $buffer = $(if ($Context.Buffer) { $Context.Buffer } else { ($Context.Tokens -join ' ') + $Context.CurrentToken })
            $cursorPos = $(if ($Context.CursorPos) { $Context.CursorPos } else { $buffer.Length })

            $astCompletions = Get-PmcCompletionsFromAst -Buffer $buffer -CursorPos $cursorPos

            if ($astCompletions.Count -gt 0) {
                Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Using AST completions: found $($astCompletions.Count) items"
                return $astCompletions
            }
        }
    } catch {
        Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "AST completion failed: $_, falling back to legacy"
    }

    # Fallback to legacy completion system
    $cacheKey = "$($Context.Mode):$($Context.CurrentToken):$($Context.Tokens -join ' ')"

    Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Start Tab cycle (legacy): state=$($Context.Mode), token='$($Context.CurrentToken)', tokens=$($Context.Tokens.Count)"

    # Check cache first for performance
    $cache = Pmc-GetCache
    if ($cache.ContainsKey($cacheKey)) {
        $cached = $cache[$cacheKey]
        # Cache hit - reduced verbosity
        return $cached
    }

    try {
        $completions = @()

        # Force argument completions when token starts with well-known prefixes
        $tok = $Context.CurrentToken
        $forceArg = ($tok -and ($tok.StartsWith('@') -or $tok.StartsWith('p') -or $tok.StartsWith('due:') -or $tok.StartsWith('#')))
        if ($forceArg) {
            $dom = $(if ($Context.Tokens.Count -gt 0) { $Context.Tokens[0] } else { '' })
            $act = $(if ($Context.Tokens.Count -gt 1) { $Context.Tokens[1] } else { '' })
            $completions = Get-PmcArgumentCompletions -Domain $dom -Action $act -Filter $tok
        } else {
            switch ($Context.Mode) {
                ([PmcCompletionMode]::Domain) {
                    $completions = Get-PmcDomainCompletions -Filter $Context.CurrentToken
                }
                ([PmcCompletionMode]::Action) {
                    if ($Context.Tokens.Count -gt 0) {
                        $completions = Get-PmcActionCompletions -Domain $Context.Tokens[0] -Filter $Context.CurrentToken
                    }
                }
                ([PmcCompletionMode]::Arguments) {
                    if ($Context.Tokens.Count -ge 2) {
                        $completions = Get-PmcArgumentCompletions -Domain $Context.Tokens[0] -Action $Context.Tokens[1] -Filter $Context.CurrentToken
                    }
                }
                default {
                    Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Unknown completion mode: $($Context.Mode)"
                }
            }
        }

        # No type conversion needed - strings are stable

        # Cache results for performance
        $cache[$cacheKey] = $completions

        # Clean cache if it gets too large (simple LRU)
        if ($cache.Keys.Count -gt 100) { $cache.Clear() }
        Pmc-SetCache $cache

        $safeCount = $(if ($completions -is [array]) { $completions.Count } elseif ($completions) { 1 } else { 0 })
        $safeFirst3 = try { ($completions | Select-Object -First 3) -join ', ' } catch { 'N/A' }
        Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Provider outputs: type=string[], length=$safeCount, first3=$safeFirst3"

        return $completions

    } catch {
        Write-PmcDebug -Level 1 -Category 'COMPLETION' -Message "Completion provider error: $_ | StackTrace: $($_.ScriptStackTrace)"
        return @()
    }
}

# Replace token in buffer with inline replacement
function Replace-TokenInBuffer {
    param(
        [string] $Buffer,
        [int] $TokenStart,
        [int] $TokenEnd,
        [string] $Replacement
    )

    if ($TokenStart -eq $TokenEnd) {
        # Insert at cursor position
        return $Buffer.Substring(0, $TokenStart) + $Replacement + $Buffer.Substring($TokenStart)
    } else {
        # Replace existing token
        return $Buffer.Substring(0, $TokenStart) + $Replacement + $Buffer.Substring($TokenEnd)
    }
}

# Ghost text system with inline positioning
# Clear ghost text (no-op with overlay model; kept for compatibility)
function Clear-GhostText { Write-Host -NoNewline "`e[0K" }

# History management
function Add-ToHistory {
    param([string] $Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return }

    # Don't add duplicate consecutive entries
    if ((Pmc-GetEditor).History.Count -gt 0 -and (Pmc-GetEditor).History[-1] -eq $Command) {
        return
    }

    (Pmc-GetEditor).History += $Command

    # Trim history if too long
    if ((Pmc-GetEditor).History.Count -gt (Pmc-GetEditor).MaxHistoryItems) {
        (Pmc-GetEditor).History = (Pmc-GetEditor).History[-(Pmc-GetEditor).MaxHistoryItems..-1]
    }

    (Pmc-GetEditor).HistoryIndex = (Pmc-GetEditor).History.Count
}

# Undo/Redo system
function Add-ToUndoStack {
    param([string] $State)

    (Pmc-GetEditor).UndoStack += $State
    (Pmc-GetEditor).RedoStack = @()  # Clear redo stack on new action

    if ((Pmc-GetEditor).UndoStack.Count -gt (Pmc-GetEditor).MaxUndoItems) {
        (Pmc-GetEditor).UndoStack = (Pmc-GetEditor).UndoStack[-(Pmc-GetEditor).MaxUndoItems..-1]
    }
}

# State snapshot for debugging exceptions
function Get-EditorStateSnapshot {
    $ed = Pmc-GetEditor
    return @{
        Buffer = $ed.Buffer
        CursorPos = $ed.CursorPos
        InCompletion = $ed.InCompletion
        CompletionCount = $ed.Completions.Count
        CompletionIndex = $ed.CompletionIndex
        Mode = $ed.Mode
        Timestamp = Get-Date
        CompletionDetails = ($ed.Completions | ForEach-Object { "$($_.GetType().Name):$($_)" }) -join '; '
    }
}

# Main command reader with comprehensive instrumentation
function Read-PmcCommand {
    Write-PmcDebug -Level 2 -Category 'INPUT' -Message "Starting Read-PmcCommand session"

    # Initialize or reset only the current line state (preserve history across prompts)
    $ed = Pmc-GetEditor
    if ($null -eq $ed) {
        $ed = [PmcEditorState]::new()
        Pmc-SetEditor $ed
    }
    $ed.Buffer = ''
    $ed.CursorPos = 0
    $ed.InCompletion = $false
    $ed.OriginalBuffer = ''
    $ed.Completions = @()
    $ed.CompletionIndex = -1
    $ed.Mode = [PmcCompletionMode]::Domain
    $ed.CurrentToken = ''
    $ed.TokenStart = 0
    $ed.TokenEnd = 0
    Pmc-SetEditor $ed

    # Initial prompt render
    try { Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false } catch {}

    while ($true) {
        try {
            # Defensive I/O: verify Console.ReadKey is available

            $key = [Console]::ReadKey($true)
            # Key press details reduced to completion/input summaries only

        } catch {
            Write-PmcStyled -Style 'Error' -Text "Console.ReadKey failed: $_"
            Write-PmcStyled -Style 'Warning' -Text "Interactive mode not available (input redirected or no TTY)"
            break
        }

        # Save state for undo before major changes
        if ($key.Key -in @('Spacebar', 'Enter', 'Delete', 'Backspace')) {
            Add-ToUndoStack -State (Pmc-GetEditor).Buffer
        }

        try {
            switch ($key.Key) {
                'LeftArrow' {
                    if ((Pmc-GetEditor).CursorPos -gt 0) {
                        (Pmc-GetEditor).CursorPos--
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    }
                    continue
                }
                'RightArrow' {
                    if ((Pmc-GetEditor).CursorPos -lt (Pmc-GetEditor).Buffer.Length) {
                        (Pmc-GetEditor).CursorPos++
                    }
                    Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    continue
                }
                'Home' {
                    (Pmc-GetEditor).CursorPos = 0
                    Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    continue
                }
                'End' {
                    (Pmc-GetEditor).CursorPos = (Pmc-GetEditor).Buffer.Length
                    Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    continue
                }
                'Delete' {
                    if ((Pmc-GetEditor).CursorPos -lt (Pmc-GetEditor).Buffer.Length) {
                        (Pmc-GetEditor).Buffer = (Pmc-GetEditor).Buffer.Remove((Pmc-GetEditor).CursorPos, 1)
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    }
                    continue
                }
                # Removed Alt+1/2/3 quick-accept bindings to avoid input interference
                'Tab' {
                    $beforeCtx = Parse-CompletionContext -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos
                    $beforeIn = (Pmc-GetEditor).InCompletion
                    $isShiftTab = ($key.Modifiers -band [ConsoleModifiers]::Shift) -eq [ConsoleModifiers]::Shift
                    $direction = $(if ($isShiftTab) { "reverse" } else { "forward" })
                    Write-PmcDebug -Level 2 -Category 'INPUT' -Message "Tab key pressed (Shift=$isShiftTab): buffer='$((Pmc-GetEditor).Buffer)', cursor=$((Pmc-GetEditor).CursorPos), inCompletion=$((Pmc-GetEditor).InCompletion)"
                    Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Tab cycle start: buffer='$((Pmc-GetEditor).Buffer)', cursor=$((Pmc-GetEditor).CursorPos), mode=initial, direction=$direction"

                    if (-not (Pmc-GetEditor).InCompletion) {
                        # First Tab: initialize completion cycling
                        (Pmc-GetEditor).OriginalBuffer = (Pmc-GetEditor).Buffer
                        $context = Parse-CompletionContext -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos
                        (Pmc-GetEditor).Mode = $context.Mode
                        (Pmc-GetEditor).CurrentToken = $context.CurrentToken
                        (Pmc-GetEditor).TokenStart = $context.TokenStart
                        (Pmc-GetEditor).TokenEnd = $context.TokenEnd

                        # Use unified completion system
                        (Pmc-GetEditor).Completions = Get-CompletionsForState -Context $context
                        $safeCompletionCount = $(if ((Pmc-GetEditor).Completions -is [array]) { (Pmc-GetEditor).Completions.Count } elseif ((Pmc-GetEditor).Completions) { 1 } else { 0 })
                        $safeCompletionFirst3 = try { ((Pmc-GetEditor).Completions | Select-Object -First 3) -join ', ' } catch { 'N/A' }
                        Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Provider outputs: type=string[], length=$safeCompletionCount, first3=$safeCompletionFirst3"

                        if ($safeCompletionCount -gt 0) {
                            (Pmc-GetEditor).InCompletion = $true
                            # For Shift+Tab on first press, start at the end
                            (Pmc-GetEditor).CompletionIndex = $(if ($isShiftTab) { $safeCompletionCount - 1 } else { 0 })

                            # Replace token with selected completion
                            $firstCompletion = (Pmc-GetEditor).Completions[(Pmc-GetEditor).CompletionIndex]
                            (Pmc-GetEditor).Buffer = Replace-TokenInBuffer -Buffer (Pmc-GetEditor).Buffer -TokenStart (Pmc-GetEditor).TokenStart -TokenDoEnd (Pmc-GetEditor).TokenEnd -Replacement $firstCompletion
                            (Pmc-GetEditor).CursorPos = (Pmc-GetEditor).TokenStart + $firstCompletion.Length

                            # Render with indicator and transient help from aux map
                            $helpInfo = $null
                            if ((Pmc-GetEditor).Mode -eq [PmcCompletionMode]::Action -and $context.Tokens.Count -gt 0) {
                                $helpInfo = Get-PmcCompletionInfo -Domain $context.Tokens[0] -Action $firstCompletion
                            } else {
                                $helpInfo = Get-PmcCompletionInfo -Text $firstCompletion
                            }
                            $helpText = $(if ($helpInfo) { $helpInfo.Description } else { $null })
                            Render-Line -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -IndicatorIndex 1 -IndicatorCount $safeCompletionCount -InCompletion $true -HelpText $helpText

                            Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Before Tab accept: index=0, selected item type=$($firstCompletion.GetType().Name), text='$($firstCompletion)'"
                            Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "After Tab accept: new buffer='$((Pmc-GetEditor).Buffer)', phase=cycling (1/$safeCompletionCount)"
                        } else {
                        Write-Host "`r`e[0Kpmc> $((Pmc-GetEditor).Buffer) [no completions]" -NoNewline
                        Start-Sleep -Milliseconds 350
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                            Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "No completions found for context: $($context | ConvertTo-Json -Compress)"
                        }
                    } else {
                        # Cycle to next/previous completion based on direction
                        $safeCurrentCount = $(if ((Pmc-GetEditor).Completions -is [array]) { (Pmc-GetEditor).Completions.Count } elseif ((Pmc-GetEditor).Completions) { 1 } else { 0 })
                        if ($safeCurrentCount -gt 0) {
                        if ($isShiftTab) {
                            # Reverse direction (Shift+Tab)
                            (Pmc-GetEditor).CompletionIndex = ((Pmc-GetEditor).CompletionIndex - 1 + $safeCurrentCount) % $safeCurrentCount
                        } else {
                            # Forward direction (Tab)
                            (Pmc-GetEditor).CompletionIndex = ((Pmc-GetEditor).CompletionIndex + 1) % $safeCurrentCount
                        }
                    } else {
                        (Pmc-GetEditor).CompletionIndex = 0
                    }
                    $selectedCompletion = (Pmc-GetEditor).Completions[(Pmc-GetEditor).CompletionIndex]

                        # Replace token with cycled completion
                    (Pmc-GetEditor).Buffer = Replace-TokenInBuffer -Buffer (Pmc-GetEditor).OriginalBuffer -TokenStart (Pmc-GetEditor).TokenStart -TokenDoEnd (Pmc-GetEditor).TokenEnd -Replacement $selectedCompletion
                    (Pmc-GetEditor).CursorPos = (Pmc-GetEditor).TokenStart + $selectedCompletion.Length

                        # Render with indicator and transient help from aux map
                    $ctxForHelp = Parse-CompletionContext -Buffer (Pmc-GetEditor).OriginalBuffer -CursorPos (Pmc-GetEditor).TokenStart
                        $helpInfo = $null
                    if ((Pmc-GetEditor).Mode -eq [PmcCompletionMode]::Action -and $ctxForHelp.Tokens.Count -gt 0) {
                        $helpInfo = Get-PmcCompletionInfo -Domain $ctxForHelp.Tokens[0] -Action $selectedCompletion
                    } else {
                        $helpInfo = Get-PmcCompletionInfo -Text $selectedCompletion
                    }
                    $helpText = $(if ($helpInfo) { $helpInfo.Description } else { $null })
                    Render-Line -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -IndicatorIndex ((Pmc-GetEditor).CompletionIndex + 1) -IndicatorCount $safeCurrentCount -InCompletion $true -HelpText $helpText

                    Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Before Tab cycle ($direction): index=$((Pmc-GetEditor).CompletionIndex), selected item type=$($selectedCompletion.GetType().Name), text='$($selectedCompletion)'"
                    Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "After Tab cycle ($direction): new buffer='$((Pmc-GetEditor).Buffer)', phase=cycling ($((Pmc-GetEditor).CompletionIndex + 1)/$safeCurrentCount)"
                    }
                    Write-StateChange -KeyName 'Tab' -BeforeCtx $beforeCtx -BeforeInCompletion $beforeIn
                    continue
                }

                'Spacebar' {
                    $beforeCtx = Parse-CompletionContext -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos
                    $beforeIn = (Pmc-GetEditor).InCompletion
                    Write-PmcDebug -Level 2 -Category 'INPUT' -Message "Space key pressed: buffer='$((Pmc-GetEditor).Buffer)', cursor=$((Pmc-GetEditor).CursorPos), inCompletion=$((Pmc-GetEditor).InCompletion)"

                    if ((Pmc-GetEditor).InCompletion) {
                        # Accept current completion, add space, reset for next state
                        $selectedCompletion = (Pmc-GetEditor).Completions[(Pmc-GetEditor).CompletionIndex]
                        (Pmc-GetEditor).Buffer = Replace-TokenInBuffer -Buffer (Pmc-GetEditor).OriginalBuffer -TokenStart (Pmc-GetEditor).TokenStart -TokenDoEnd (Pmc-GetEditor).TokenEnd -Replacement $selectedCompletion

                        if (-not (Pmc-GetEditor).Buffer.EndsWith(' ')) {
                            (Pmc-GetEditor).Buffer += ' '
                        }
                        (Pmc-GetEditor).CursorPos = (Pmc-GetEditor).Buffer.Length

                        # Reset completion state
                        (Pmc-GetEditor).InCompletion = $false
                        (Pmc-GetEditor).Completions = @()
                        (Pmc-GetEditor).CompletionIndex = -1

                        # Get new context after state change for logging
                        $afterCtx = Parse-CompletionContext -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos

                        # Redraw and show ghost for next phase
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false

                        Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Before Space accept: index=$((Pmc-GetEditor).CompletionIndex), selected item type=$($selectedCompletion.GetType().Name), text='$($selectedCompletion)'"
                        Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "After Space accept: new buffer='$((Pmc-GetEditor).Buffer)', phase=domain/action/prefix, nextState=$($afterCtx.Mode)"
                    } else {
                        # Insert space normally
                        (Pmc-GetEditor).Buffer = (Pmc-GetEditor).Buffer.Substring(0, (Pmc-GetEditor).CursorPos) + ' ' + (Pmc-GetEditor).Buffer.Substring((Pmc-GetEditor).CursorPos)
                        (Pmc-GetEditor).CursorPos++
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    }
                    Write-StateChange -KeyName 'Space' -BeforeCtx $beforeCtx -BeforeInCompletion $beforeIn
                    continue
                }

                'Enter' {
                    $beforeCtx = Parse-CompletionContext -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos
                    $beforeIn = (Pmc-GetEditor).InCompletion
                    Write-PmcDebug -Level 2 -Category 'INPUT' -Message "Enter key pressed: buffer='$((Pmc-GetEditor).Buffer)', cursor=$((Pmc-GetEditor).CursorPos), inCompletion=$((Pmc-GetEditor).InCompletion)"

                    if ((Pmc-GetEditor).InCompletion) {
                        # Accept completion then submit
                        $selectedCompletion = (Pmc-GetEditor).Completions[(Pmc-GetEditor).CompletionIndex]
                        (Pmc-GetEditor).Buffer = Replace-TokenInBuffer -Buffer (Pmc-GetEditor).OriginalBuffer -TokenStart (Pmc-GetEditor).TokenStart -TokenDoEnd (Pmc-GetEditor).TokenEnd -Replacement $selectedCompletion
                        Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "Before Enter accept: index=$((Pmc-GetEditor).CompletionIndex), selected item type=$($selectedCompletion.GetType().Name), text='$($selectedCompletion)'"
                        Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message "After Enter accept: final buffer='$((Pmc-GetEditor).Buffer)', phase=submit"
                    }

                    Clear-GhostText

                    if (-not [string]::IsNullOrWhiteSpace((Pmc-GetEditor).Buffer)) {
                        Add-ToHistory -Command (Pmc-GetEditor).Buffer
                    }

                    Write-StateChange -KeyName 'Enter' -BeforeCtx $beforeCtx -BeforeInCompletion $beforeIn
                    return (Pmc-GetEditor).Buffer
                }

                'Escape' {
                    $beforeCtx = Parse-CompletionContext -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos
                    $beforeIn = (Pmc-GetEditor).InCompletion
                    Write-PmcDebug -Level 2 -Category 'INPUT' -Message "Escape key pressed: buffer='$((Pmc-GetEditor).Buffer)', cursor=$((Pmc-GetEditor).CursorPos), inCompletion=$((Pmc-GetEditor).InCompletion)"

                    if ((Pmc-GetEditor).InCompletion) {
                        # Cancel completion, restore original buffer
                        (Pmc-GetEditor).Buffer = (Pmc-GetEditor).OriginalBuffer
                        (Pmc-GetEditor).CursorPos = (Pmc-GetEditor).OriginalBuffer.Length
                        (Pmc-GetEditor).InCompletion = $false
                        (Pmc-GetEditor).Completions = @()
                        (Pmc-GetEditor).CompletionIndex = -1
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    } else {
                        # Clear entire line
                        (Pmc-GetEditor).Buffer = ""
                        (Pmc-GetEditor).CursorPos = 0
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    }
                    Write-StateChange -KeyName 'Escape' -BeforeCtx $beforeCtx -BeforeInCompletion $beforeIn
                    continue
                }

                'Backspace' {
                    $beforeCtx = Parse-CompletionContext -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos
                    $beforeIn = (Pmc-GetEditor).InCompletion
                    Write-PmcDebug -Level 2 -Category 'INPUT' -Message "Backspace key pressed: buffer='$((Pmc-GetEditor).Buffer)', cursor=$((Pmc-GetEditor).CursorPos), inCompletion=$((Pmc-GetEditor).InCompletion)"
                    if ((Pmc-GetEditor).CursorPos -gt 0) {
                        (Pmc-GetEditor).Buffer = (Pmc-GetEditor).Buffer.Substring(0, (Pmc-GetEditor).CursorPos - 1) + (Pmc-GetEditor).Buffer.Substring((Pmc-GetEditor).CursorPos)
                        (Pmc-GetEditor).CursorPos--

                        # Exit completion mode when editing
                        if ((Pmc-GetEditor).InCompletion) {
                            (Pmc-GetEditor).InCompletion = $false
                            (Pmc-GetEditor).Completions = @()
                            (Pmc-GetEditor).CompletionIndex = -1
                        }

                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    }
                    Write-StateChange -KeyName 'Backspace' -BeforeCtx $beforeCtx -BeforeInCompletion $beforeIn
                    continue
                }

                'UpArrow' {
                    $beforeCtx = Parse-CompletionContext -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos
                    $beforeIn = (Pmc-GetEditor).InCompletion
                    Write-PmcDebug -Level 2 -Category 'INPUT' -Message "UpArrow key pressed: buffer='$((Pmc-GetEditor).Buffer)', historyIndex=$((Pmc-GetEditor).HistoryIndex), historySize=$((Pmc-GetEditor).History.Count)"

                    if ((Pmc-GetEditor).History.Count -gt 0) {
                        if ((Pmc-GetEditor).HistoryIndex -gt 0) { (Pmc-GetEditor).HistoryIndex-- }
                        (Pmc-GetEditor).Buffer = (Pmc-GetEditor).History[(Pmc-GetEditor).HistoryIndex]
                        (Pmc-GetEditor).CursorPos = (Pmc-GetEditor).Buffer.Length
                        (Pmc-GetEditor).InCompletion = $false
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    }
                    Write-StateChange -KeyName 'UpArrow' -BeforeCtx $beforeCtx -BeforeInCompletion $beforeIn
                    continue
                }

                'DownArrow' {
                    $beforeCtx = Parse-CompletionContext -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos
                    $beforeIn = (Pmc-GetEditor).InCompletion
                    Write-PmcDebug -Level 2 -Category 'INPUT' -Message "DownArrow key pressed: buffer='$((Pmc-GetEditor).Buffer)', historyIndex=$((Pmc-GetEditor).HistoryIndex), historySize=$((Pmc-GetEditor).History.Count)"

                    if ((Pmc-GetEditor).History.Count -gt 0) {
                        if ((Pmc-GetEditor).HistoryIndex -lt ((Pmc-GetEditor).History.Count - 1)) {
                            (Pmc-GetEditor).HistoryIndex++
                            (Pmc-GetEditor).Buffer = (Pmc-GetEditor).History[(Pmc-GetEditor).HistoryIndex]
                        } else {
                            (Pmc-GetEditor).HistoryIndex = (Pmc-GetEditor).History.Count
                            (Pmc-GetEditor).Buffer = ""
                        }
                        (Pmc-GetEditor).CursorPos = (Pmc-GetEditor).Buffer.Length
                        (Pmc-GetEditor).InCompletion = $false
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    }
                    Write-StateChange -KeyName 'DownArrow' -BeforeCtx $beforeCtx -BeforeInCompletion $beforeIn
                    continue
                }

                'R' {
                    if (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0) {
                        Write-PmcDebug -Level 2 -Category 'INPUT' -Message "Ctrl+R key pressed: reverse history search initiated, historySize=$((Pmc-GetEditor).History.Count)"

                        Write-Host "`r`e[0K(reverse-i-search): " -NoNewline
                        $searchTerm = ""
                    $searchResults = @()
                    $searchIndex = 0

                    while ($true) {
                        $searchKey = [Console]::ReadKey($true)

                        if ($searchKey.Key -eq 'Enter' -or $searchKey.Key -eq 'Escape') {
                            if ($searchKey.Key -eq 'Enter' -and $searchResults.Count -gt 0) {
                                (Pmc-GetEditor).Buffer = $searchResults[$searchIndex]
                                (Pmc-GetEditor).CursorPos = (Pmc-GetEditor).Buffer.Length
                            }
                            Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                            break
                        } elseif ($searchKey.Key -eq 'Backspace' -and $searchTerm.Length -gt 0) {
                            $searchTerm = $searchTerm.Substring(0, $searchTerm.Length - 1)
                        } elseif ($searchKey.Key -eq 'R' -and $searchKey.Modifiers -eq 'Control') {
                            # Next search result
                            if ($searchResults.Count -gt 1) {
                                $searchIndex = ($searchIndex + 1) % $searchResults.Count
                            }
                        } elseif (-not [char]::IsControl($searchKey.KeyChar)) {
                            $searchTerm += $searchKey.KeyChar
                        }

                        # Update search results
                        if ($searchTerm.Length -gt 0) {
                            $searchResults = @((Pmc-GetEditor).History | Where-Object { $_ -like "*$searchTerm*" } | Select-Object -Last 10)
                            if ($searchResults.Count -eq 0) {
                                $searchResults = @()
                                $searchIndex = 0
                            } elseif ($searchIndex -ge $searchResults.Count) {
                                $searchIndex = 0
                            }
                        }

                        # Display search state
                        $displayText = $(if ($searchResults.Count -gt 0) { $searchResults[$searchIndex] } else { "" })
                        Write-Host "`r`e[0K(reverse-i-search)'$searchTerm': $displayText" -NoNewline
                    }

                        continue
                    } else {
                        # Regular 'R' character input
                        $editor = Pmc-GetEditor
                        $editor.Buffer = $editor.Buffer.Insert($editor.CursorPos, $key.KeyChar)
                        $editor.CursorPos++
                        Pmc-SetEditor $editor
                        Render-Interactive -Buffer $editor.Buffer -CursorPos $editor.CursorPos -InCompletion $false
                    }
                    continue
                }

                'Z' {
                    if (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0) {
                        Write-PmcDebug -Level 2 -Category 'INPUT' -Message "Ctrl+Z key pressed: undo, undoStackSize=$((Pmc-GetEditor).UndoStack.Count), redoStackSize=$((Pmc-GetEditor).RedoStack.Count)"

                        if ((Pmc-GetEditor).UndoStack.Count -gt 0) {
                            (Pmc-GetEditor).RedoStack += (Pmc-GetEditor).Buffer
                            (Pmc-GetEditor).Buffer = (Pmc-GetEditor).UndoStack[-1]
                            (Pmc-GetEditor).UndoStack = (Pmc-GetEditor).UndoStack[0..((Pmc-GetEditor).UndoStack.Count - 2)]
                            (Pmc-GetEditor).CursorPos = (Pmc-GetEditor).Buffer.Length
                            (Pmc-GetEditor).InCompletion = $false
                            Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                        }
                        continue
                    } else {
                        # Regular 'Z' character input
                        (Pmc-GetEditor).Buffer = (Pmc-GetEditor).Buffer.Insert((Pmc-GetEditor).CursorPos, $key.KeyChar)
                        (Pmc-GetEditor).CursorPos++
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    }
                    continue
                }

                'Y' {
                    if (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0) {
                        Write-PmcDebug -Level 2 -Category 'INPUT' -Message "Ctrl+Y key pressed: redo, undoStackSize=$((Pmc-GetEditor).UndoStack.Count), redoStackSize=$((Pmc-GetEditor).RedoStack.Count)"

                        if ((Pmc-GetEditor).RedoStack.Count -gt 0) {
                            (Pmc-GetEditor).UndoStack += (Pmc-GetEditor).Buffer
                            (Pmc-GetEditor).Buffer = (Pmc-GetEditor).RedoStack[-1]
                            (Pmc-GetEditor).RedoStack = (Pmc-GetEditor).RedoStack[0..((Pmc-GetEditor).RedoStack.Count - 2)]
                            (Pmc-GetEditor).CursorPos = (Pmc-GetEditor).Buffer.Length
                            (Pmc-GetEditor).InCompletion = $false
                            Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                        }
                        continue
                    } else {
                        # Regular 'Y' character input
                        (Pmc-GetEditor).Buffer = (Pmc-GetEditor).Buffer.Insert((Pmc-GetEditor).CursorPos, $key.KeyChar)
                        (Pmc-GetEditor).CursorPos++
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    }
                    continue
                }

                default {
                    $beforeCtx = Parse-CompletionContext -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos
                    $beforeIn = (Pmc-GetEditor).InCompletion
                    # Regular character input
                    if (-not [char]::IsControl($key.KeyChar)) {
                        # Character input reduced verbosity
                        # Exit completion mode when typing new characters
                        if ((Pmc-GetEditor).InCompletion) {
                            (Pmc-GetEditor).InCompletion = $false
                            (Pmc-GetEditor).Completions = @()
                            (Pmc-GetEditor).CompletionIndex = -1
                        }

                        (Pmc-GetEditor).Buffer = (Pmc-GetEditor).Buffer.Substring(0, (Pmc-GetEditor).CursorPos) + $key.KeyChar + (Pmc-GetEditor).Buffer.Substring((Pmc-GetEditor).CursorPos)
                        (Pmc-GetEditor).CursorPos++
                        Render-Interactive -Buffer (Pmc-GetEditor).Buffer -CursorPos (Pmc-GetEditor).CursorPos -InCompletion $false
                    }
                    Write-StateChange -KeyName 'Char' -BeforeCtx $beforeCtx -BeforeInCompletion $beforeIn
                    continue
                }
            }

        } catch {
            $snapshot = Get-EditorStateSnapshot
            Write-PmcDebug -Level 1 -Category 'INPUT' -Message "EXCEPTION: Input processing error: $_ | FULL STATE DUMP: $($snapshot | ConvertTo-Json -Depth 5 -Compress) | StackTrace: $($_.ScriptStackTrace)"
            Write-PmcDebug -Level 1 -Category 'INPUT' -Message "EXCEPTION CONTEXT: Key=$($key.Key), KeyChar='$($key.KeyChar)', Modifiers=$($key.Modifiers)"
            Write-PmcStyled -Style 'Error' -Text "Input processing failed: $_"
            break
        }
    }
}

# Initialize interactive mode
function Enable-PmcInteractiveMode {
    Write-PmcDebug -Level 1 -Category 'INTERACTIVE' -Message "Enabling PMC interactive mode with full t2.ps1 feature set"

    try {
        try { if (Get-Module PSReadLine -ErrorAction SilentlyContinue) { Remove-Module PSReadLine -Force -ErrorAction SilentlyContinue } } catch {}
        try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
        try { [Console]::CursorVisible = $true } catch {}
        # Clear completion cache
        Pmc-ClearCache

        # Initialize auxiliary completion info map (idempotent)
        $iMap = Pmc-GetInfoMap
        if (-not $iMap -or $iMap.Keys.Count -eq 0) {
            Initialize-PmcCompletionInfoMap
        }

        # Initialize editor state
        Pmc-SetEditor ([PmcEditorState]::new())

        Write-PmcStyled -Style 'Success' -Text "[OK] Interactive mode enabled (Console.ReadKey)"
        return $true

    } catch {
        Write-PmcDebug -Level 1 -Category 'INTERACTIVE' -Message "Failed to enable interactive mode: $_"
        Write-PmcStyled -Style 'Error' -Text ("Failed to enable interactive mode: {0}" -f $_)
        return $false
    }
}

function Disable-PmcInteractiveMode {
    Write-PmcDebug -Level 1 -Category 'INTERACTIVE' -Message "Disabling PMC interactive mode"

    try {
        Pmc-ClearCache
        Pmc-SetEditor ([PmcEditorState]::new())
        Write-PmcStyled -Style 'Success' -Text "[OK] Interactive mode disabled"

    } catch {
        Write-PmcDebug -Level 1 -Category 'INTERACTIVE' -Message "Error disabling interactive mode: $_"
        Write-PmcStyled -Style 'Error' -Text ("Error disabling interactive mode: {0}" -f $_)
    }
}

function Get-PmcInteractiveStatus {
    return @{
        Enabled = $true
        GhostTextEnabled = (Pmc-GetGhost)
        CacheSize = (Pmc-GetCache).Keys.Count
        HistorySize = (Pmc-GetEditor).History.Count
        UndoStackSize = (Pmc-GetEditor).UndoStack.Count
        Features = @("InlineCycling", "GhostText", "History", "CtrlR", "UndoRedo", "ErrorRecovery")
    }
}

# Export functions
Export-ModuleMember -Function Enable-PmcInteractiveMode, Disable-PmcInteractiveMode, Get-PmcInteractiveStatus, Read-PmcCommand, Pmc-InsertAtCursor