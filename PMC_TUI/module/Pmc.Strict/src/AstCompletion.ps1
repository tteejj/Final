# AST-based tab completion for PMC commands
# Replaces regex-based completion with semantic understanding

Set-StrictMode -Version Latest

# Enhanced completion providers using AST context
function Get-PmcCompletionsFromAst {
    param(
        [string]$Buffer,
        [int]$CursorPos
    )

    try {
        # Handle empty buffer case
        if ([string]::IsNullOrWhiteSpace($Buffer)) {
            Write-PmcDebug -Level 2 -Category 'AstCompletion' -Message "Empty buffer, providing domain completions"
            return Get-DomainCompletions
        }

        $context = Get-PmcCompletionContextFromAst -Buffer $Buffer -CursorPos $CursorPos

        if (-not $context) {
            Write-PmcDebug -Level 2 -Category 'AstCompletion' -Message "No AST context available, falling back"
            return @()
        }

        Write-PmcDebug -Level 2 -Category 'AstCompletion' -Message "AST completion context" -Data @{
            Domain = $context.Domain
            Action = $context.Action
            ExpectedType = $context.ExpectedType
            LastToken = $context.LastToken
        }

        # Get completions based on expected type
        $completions = @()
        switch ($context.ExpectedType) {
            'Domain' {
                $completions = Get-DomainCompletions -Filter $context.LastToken
            }
            'Action' {
                $completions = Get-ActionCompletions -Domain $context.Domain -Filter $context.LastToken
            }
            'Project' {
                $completions = Get-ProjectCompletions -Filter $context.LastToken
            }
            'Priority' {
                $completions = Get-PriorityCompletions -Filter $context.LastToken
            }
            'Tag' {
                $completions = Get-TagCompletions -Filter $context.LastToken
            }
            'Date' {
                $completions = Get-DateCompletions -Filter $context.LastToken
            }
            'TaskId' {
                $completions = Get-TaskIdCompletions -Filter $context.LastToken
            }
            'Arguments' {
                $completions = Get-ArgumentCompletions -Context $context
            }
            default {
                $completions = Get-GenericCompletions -Context $context
            }
        }

        Write-PmcDebug -Level 2 -Category 'AstCompletion' -Message "Completions generated" -Data @{
            Count = $completions.Count
            Type = $context.ExpectedType
        }

        return $completions

    } catch {
        Write-PmcDebug -Level 1 -Category 'AstCompletion' -Message "AST completion failed: $_" -Data @{
            Buffer = $Buffer
            CursorPos = $CursorPos
            Exception = $_.Exception.Message
        }
        # No fallback - re-throw the error so we know AST completion isn't working
        throw "AST completion failed: $_"
    }
}

# Domain completions
function Get-DomainCompletions {
    param([string]$Filter = "")

    $domains = @('task', 'project', 'time', 'timer', 'activity', 'help', 'q')

    if ([string]::IsNullOrEmpty($Filter)) {
        return $domains
    }

    return $domains | Where-Object { $_.StartsWith($Filter, [StringComparison]::OrdinalIgnoreCase) }
}

# Action completions based on domain
function Get-ActionCompletions {
    param(
        [string]$Domain,
        [string]$Filter = ""
    )

    $actions = @()

    if ([string]::IsNullOrEmpty($Domain)) {
        Write-PmcDebug -Level 2 -Category 'AstCompletion' -Message "No domain provided for action completion"
        return @()
    }

    switch ($Domain.ToLower()) {
        'task' {
            $actions = @('add', 'list', 'view', 'update', 'done', 'delete', 'move', 'postpone', 'duplicate', 'note', 'edit', 'search', 'priority', 'agenda', 'week', 'month')
        }
        'project' {
            $actions = @('add', 'list', 'view', 'update', 'edit', 'rename', 'delete', 'archive', 'set-fields', 'show-fields', 'stats', 'info', 'recent')
        }
        'time' {
            $actions = @('log', 'report', 'list', 'edit', 'delete')
        }
        'timer' {
            $actions = @('start', 'stop', 'status')
        }
        'activity' {
            $actions = @('list')
        }
        'help' {
            $actions = @('show', 'guide', 'examples', 'query', 'domain', 'command', 'search')
        }
        default {
            return @()
        }
    }

    if ([string]::IsNullOrEmpty($Filter)) {
        return $actions
    }

    return $actions | Where-Object { $_.StartsWith($Filter, [StringComparison]::OrdinalIgnoreCase) }
}

# Project completions
function Get-ProjectCompletions {
    param([string]$Filter = "")

    try {
        $data = Get-PmcData
        $projects = @()

        foreach ($project in $data.projects) {
            $name = "@" + $project.name
            $projects += $name
        }

        if ([string]::IsNullOrEmpty($Filter)) {
            return $projects
        }

        # Handle @ prefix in filter
        $searchFilter = $(if ($Filter.StartsWith('@')) { $Filter } else { "@" + $Filter })

        return $projects | Where-Object { $_.StartsWith($searchFilter, [StringComparison]::OrdinalIgnoreCase) }

    } catch {
        Write-PmcDebug -Level 2 -Category 'AstCompletion' -Message "Project completion error: $_"
        return @('@work', '@personal', '@urgent')  # Fallback
    }
}

# Priority completions
function Get-PriorityCompletions {
    param([string]$Filter = "")

    $priorities = @('p1', 'p2', 'p3')

    if ([string]::IsNullOrEmpty($Filter)) {
        return $priorities
    }

    return $priorities | Where-Object { $_.StartsWith($Filter, [StringComparison]::OrdinalIgnoreCase) }
}

# Tag completions
function Get-TagCompletions {
    param([string]$Filter = "")

    try {
        $data = Get-PmcData
        $tags = @()

        foreach ($task in $data.tasks) {
            if ($task.tags) {
                foreach ($tag in $task.tags) {
                    $tagName = "#" + $tag
                    if ($tags -notcontains $tagName) {
                        $tags += $tagName
                    }
                }
            }
        }

        if ([string]::IsNullOrEmpty($Filter)) {
            return $tags
        }

        # Handle # prefix in filter
        $searchFilter = $(if ($Filter.StartsWith('#')) { $Filter } else { "#" + $Filter })

        return $tags | Where-Object { $_.StartsWith($searchFilter, [StringComparison]::OrdinalIgnoreCase) }

    } catch {
        Write-PmcDebug -Level 2 -Category 'AstCompletion' -Message "Tag completion error: $_"
        return @('#urgent', '#bug', '#review')  # Fallback
    }
}

# Date completions
function Get-DateCompletions {
    param([string]$Filter = "")

    $dates = @(
        'due:today',
        'due:tomorrow',
        'due:friday',
        'due:+1d',
        'due:+1w',
        'due:+1m',
        'due:2024-12-25'
    )

    if ([string]::IsNullOrEmpty($Filter)) {
        return $dates
    }

    return $dates | Where-Object { $_.StartsWith($Filter, [StringComparison]::OrdinalIgnoreCase) }
}

# Task ID completions
function Get-TaskIdCompletions {
    param([string]$Filter = "")

    try {
        $data = Get-PmcData
        $taskIds = @()

        foreach ($task in $data.tasks) {
            if ($task.id) {
                $taskId = "task:" + $task.id
                $taskIds += $taskId
            }
        }

        if ([string]::IsNullOrEmpty($Filter)) {
            return $taskIds | Select-Object -First 10  # Limit to recent tasks
        }

        return $taskIds | Where-Object { $_.StartsWith($Filter, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 10

    } catch {
        Write-PmcDebug -Level 2 -Category 'AstCompletion' -Message "Task ID completion error: $_"
        return @()
    }
}

# Argument completions when we already have domain/action
function Get-ArgumentCompletions {
    param([hashtable]$Context)

    $completions = @()

    # Add common argument types that haven't been used yet
    if (-not $Context.Args.ContainsKey('project')) {
        $completions += '@'
    }

    if (-not $Context.Args.ContainsKey('priority')) {
        $completions += @('p1', 'p2', 'p3')
    }

    if (-not $Context.Args.ContainsKey('tags')) {
        $completions += '#'
    }

    if (-not $Context.Args.ContainsKey('due') -and $Context.Domain -eq 'task') {
        $completions += 'due:'
    }

    if (-not $Context.Args.ContainsKey('taskId') -and $Context.Action -in @('view', 'update', 'done', 'delete')) {
        $completions += 'task:'
    }

    return $completions
}

# Generic completions fallback
function Get-GenericCompletions {
    param([hashtable]$Context)

    $completions = @()

    # Suggest based on domain and action
    switch ("$($Context.Domain):$($Context.Action)") {
        'task:add' {
            $completions += @('@', 'p1', 'p2', 'p3', '#', 'due:')
        }
        'task:list' {
            $completions += @('@', 'p1', 'p2', 'p3', '#', 'due:', 'overdue')
        }
        'task:view' {
            $completions += @('task:')
        }
        'project:list' {
            $completions += @('@')
        }
        'time:log' {
            $completions += @('@', 'task:', '#')
        }
        default {
            $completions += @('@', 'p1', '#')
        }
    }

    return $completions
}

# Replace completion logic in Interactive.ps1
function Get-CompletionsForStateAst {
    param([hashtable]$Context)

    # Try AST-based completion first
    $buffer = $(if ($null -ne $Context.Buffer -and $Context.Buffer -ne "") { $Context.Buffer } else { "" })
    $cursorPos = $(if ($null -ne $Context.CursorPos) { $Context.CursorPos } else { 0 })

    $astCompletions = Get-PmcCompletionsFromAst -Buffer $buffer -CursorPos $cursorPos

    if ($astCompletions.Count -gt 0) {
        return $astCompletions
    }

    # Fallback to existing system if AST fails
    Write-PmcDebug -Level 2 -Category 'AstCompletion' -Message "AST completion failed, using fallback"
    return @()
}

Export-ModuleMember -Function Get-PmcCompletionsFromAst, Get-CompletionsForStateAst