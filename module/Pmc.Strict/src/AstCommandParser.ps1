# AST-based command parser for PMC
# Replaces regex-heavy Parse-PmcArgsFromTokens with structured parsing

Set-StrictMode -Version Latest

# Token types for semantic parsing
enum PmcTokenType {
    Domain
    Action
    ProjectRef    # @project
    Priority      # p1, p2, p3
    Tag          # #tag
    DueDate      # due:date
    TaskId       # task:123
    StringLiteral # "quoted text"
    Flag         # -i, --interactive
    Separator    # --
    FreeText     # unstructured text
}

class PmcParsedToken {
    [PmcTokenType]$Type
    [string]$Value
    [string]$RawValue
    [int]$Position

    PmcParsedToken([PmcTokenType]$type, [string]$value, [string]$raw, [int]$pos) {
        $this.Type = $type
        $this.Value = $value
        $this.RawValue = $raw
        $this.Position = $pos
    }
}

class PmcCommandAst {
    [string]$Domain
    [string]$Action
    [hashtable]$Args = @{}
    [string[]]$FreeText = @()
    [PmcParsedToken[]]$Tokens = @()
    [string]$Raw

    PmcCommandAst([string]$raw) {
        $this.Raw = $raw
        $this.Args = @{}
        $this.FreeText = @()
        $this.Tokens = @()
    }
}

# Main AST parsing function
function ConvertTo-PmcCommandAst {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CommandText
    )

    try {
        # Use PowerShell AST to get proper tokenization
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($CommandText, [ref]$null, [ref]$null)

        # Find the command AST node
        $cmdAst = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.CommandAst]}, $true) | Select-Object -First 1

        if (-not $cmdAst) {
            Write-PmcDebug -Level 2 -Category 'AstParser' -Message "No command AST found, trying fallback parsing"
            throw "No command found in input"
        }

        $result = [PmcCommandAst]::new($CommandText)
        $elements = $cmdAst.CommandElements

        if ($elements.Count -lt 1) {
            throw "Empty command"
        }

        # Check if PowerShell AST stripped important tokens (like #tags)
        $originalTokenCount = ($CommandText -split '\s+').Count
        $astTokenCount = $elements.Count

        if ($astTokenCount -lt $originalTokenCount) {
            Write-PmcDebug -Level 2 -Category 'AstParser' -Message "PowerShell AST stripped tokens (comments?), falling back to manual parsing"
            throw "AST incomplete, using fallback"
        }

        # Parse domain (first element)
        $result.Domain = $elements[0].Extent.Text.ToLower()

        # Parse action (second element, if exists)
        if ($elements.Count -gt 1) {
            $result.Action = $elements[1].Extent.Text.ToLower()
        }

        # Parse remaining arguments (semantic parsing)
        if ($elements.Count -gt 2) {
            $argElements = $elements[2..($elements.Count-1)]
            Parse-CommandArguments -Elements $argElements -Result $result
        }

        return $result

    } catch {
        Write-PmcDebug -Level 1 -Category 'AstParser' -Message "AST parsing failed: $_" -Data @{ CommandText = $CommandText }

        # No fallback - throw the error so we know AST isn't working
        throw "AST parsing failed: $_"
    }
}

# Semantic argument parsing
function Parse-CommandArguments {
    param(
        [System.Management.Automation.Language.CommandElementAst[]]$Elements,
        [PmcCommandAst]$Result
    )

    $position = 0
    $seenSeparator = $false

    foreach ($element in $Elements) {
        $text = $element.Extent.Text
        $position++

        # Handle separator (everything after -- is free text)
        if ($text -eq '--') {
            $seenSeparator = $true
            $token = [PmcParsedToken]::new([PmcTokenType]::Separator, '', $text, $position)
            $Result.Tokens += $token
            continue
        }

        if ($seenSeparator) {
            # Everything after -- goes to free text
            $token = [PmcParsedToken]::new([PmcTokenType]::FreeText, $text, $text, $position)
            $Result.Tokens += $token
            $Result.FreeText += $text
            continue
        }

        # Semantic parsing based on token patterns
        $tokenInfo = Parse-SemanticToken -Text $text -Position $position
        $Result.Tokens += $tokenInfo

        # Add to appropriate result field based on token type
        switch ($tokenInfo.Type) {
            ([PmcTokenType]::ProjectRef) {
                $Result.Args['project'] = $tokenInfo.Value
            }
            ([PmcTokenType]::Priority) {
                $Result.Args['priority'] = $tokenInfo.Value
            }
            ([PmcTokenType]::Tag) {
                if (-not $Result.Args.ContainsKey('tags')) { $Result.Args['tags'] = @() }
                $Result.Args['tags'] += $tokenInfo.Value
            }
            ([PmcTokenType]::DueDate) {
                $Result.Args['due'] = $tokenInfo.Value
            }
            ([PmcTokenType]::TaskId) {
                $Result.Args['taskId'] = [int]$tokenInfo.Value
            }
            ([PmcTokenType]::Flag) {
                # Handle flags like -i, --interactive
                $flagName = $tokenInfo.Value
                $Result.Args[$flagName] = $true
            }
            ([PmcTokenType]::StringLiteral) {
                # Quoted strings go to free text (usually task titles, descriptions)
                $Result.FreeText += $tokenInfo.Value
            }
            ([PmcTokenType]::FreeText) {
                $Result.FreeText += $tokenInfo.Value
            }
        }
    }
}

# Parse individual tokens semantically
function Parse-SemanticToken {
    param(
        [string]$Text,
        [int]$Position
    )

    # Project reference: @project
    if ($Text -match '^@(.+)$') {
        return [PmcParsedToken]::new([PmcTokenType]::ProjectRef, $matches[1], $Text, $Position)
    }

    # Priority: p1, p2, p3
    if ($Text -match '^p([1-3])$') {
        return [PmcParsedToken]::new([PmcTokenType]::Priority, $Text, $Text, $Position)
    }

    # Tag: #tag
    if ($Text -match '^#(.+)$') {
        return [PmcParsedToken]::new([PmcTokenType]::Tag, $matches[1], $Text, $Position)
    }

    # Due date: due:date
    if ($Text -match '^due:(.+)$') {
        return [PmcParsedToken]::new([PmcTokenType]::DueDate, $matches[1], $Text, $Position)
    }

    # Task ID: task:123
    if ($Text -match '^task:(\d+)$') {
        return [PmcParsedToken]::new([PmcTokenType]::TaskId, $matches[1], $Text, $Position)
    }

    # Flags: -i, --interactive
    if ($Text -match '^-+(.+)$') {
        $flagName = $matches[1]
        # Normalize common flags
        switch ($flagName.ToLower()) {
            'i' { $flagName = 'interactive' }
            'interactive' { $flagName = 'interactive' }
        }
        return [PmcParsedToken]::new([PmcTokenType]::Flag, $flagName, $Text, $Position)
    }

    # Quoted strings (AST should handle these, but fallback)
    if ($Text -match '^"(.*)"$') {
        return [PmcParsedToken]::new([PmcTokenType]::StringLiteral, $matches[1], $Text, $Position)
    }

    # Everything else is free text
    return [PmcParsedToken]::new([PmcTokenType]::FreeText, $Text, $Text, $Position)
}

# Fallback parser when AST fails
function ConvertTo-PmcCommandAstFallback {
    param([string]$CommandText)

    $result = [PmcCommandAst]::new($CommandText)
    $tokens = ConvertTo-PmcTokens $CommandText

    if ($tokens.Count -gt 0) { $result.Domain = $tokens[0].ToLower() }
    if ($tokens.Count -gt 1) { $result.Action = $tokens[1].ToLower() }

    # Parse remaining tokens
    if ($tokens.Count -gt 2) {
        $argTokens = $tokens[2..($tokens.Count-1)]
        $position = 2

        foreach ($token in $argTokens) {
            $position++
            $tokenInfo = Parse-SemanticToken -Text $token -Position $position
            $result.Tokens += $tokenInfo

            # Add to result like above
            switch ($tokenInfo.Type) {
                ([PmcTokenType]::ProjectRef) { $result.Args['project'] = $tokenInfo.Value }
                ([PmcTokenType]::Priority) { $result.Args['priority'] = $tokenInfo.Value }
                ([PmcTokenType]::Tag) {
                    if (-not $result.Args.ContainsKey('tags')) { $result.Args['tags'] = @() }
                    $result.Args['tags'] += $tokenInfo.Value
                }
                ([PmcTokenType]::DueDate) { $result.Args['due'] = $tokenInfo.Value }
                ([PmcTokenType]::TaskId) { $result.Args['taskId'] = [int]$tokenInfo.Value }
                ([PmcTokenType]::Flag) { $result.Args[$tokenInfo.Value] = $true }
                default { $result.FreeText += $tokenInfo.Value }
            }
        }
    }

    return $result
}

# Replace the existing Parse-PmcArgsFromTokens function
function Parse-PmcArgsFromTokensAst {
    param(
        [string[]]$Tokens,
        [int]$StartIndex = 0
    )

    # Reconstruct command from tokens
    $commandText = ($Tokens[$StartIndex..($Tokens.Count-1)] -join ' ')
    $astResult = ConvertTo-PmcCommandAst -CommandText $commandText

    return @{
        Args = $astResult.Args
        Free = $astResult.FreeText
    }
}

# Get completion context from AST
function Get-PmcCompletionContextFromAst {
    param(
        [string]$Buffer,
        [int]$CursorPos
    )

    try {
        # Parse what we have so far - handle empty/partial commands
        if ([string]::IsNullOrWhiteSpace($Buffer)) {
            $ast = [PmcCommandAst]::new("")
        } else {
            $ast = ConvertTo-PmcCommandAst -CommandText $Buffer
        }

        # Determine what kind of completion we need
        $context = @{
            Domain = $ast.Domain
            Action = $ast.Action
            Args = $ast.Args
            LastToken = $null
            ExpectedType = $null
            Position = $ast.Tokens.Count
        }

        # Find the token at cursor position
        $beforeCursor = $Buffer.Substring(0, [Math]::Min($CursorPos, $Buffer.Length))
        $lastSpace = $beforeCursor.LastIndexOf(' ')

        if ($lastSpace -ge 0 -and $lastSpace -lt $beforeCursor.Length - 1) {
            $context.LastToken = $beforeCursor.Substring($lastSpace + 1)
        } elseif ($lastSpace -eq $beforeCursor.Length - 1) {
            $context.LastToken = ''
        } else {
            $context.LastToken = $beforeCursor
        }

        # Determine expected completion type
        $context.ExpectedType = Get-ExpectedCompletionType -Context $context

        return $context

    } catch {
        Write-PmcDebug -Level 2 -Category 'AstCompletion' -Message "AST completion context failed: $_"
        return $null
    }
}

# Determine what type of completion to show
function Get-ExpectedCompletionType {
    param([hashtable]$Context)

    $lastToken = $(if ($Context.LastToken) { $Context.LastToken } else { '' })

    # If last token has a prefix, complete that type
    if ($lastToken -and $lastToken.StartsWith('@')) { return 'Project' }
    if ($lastToken -and $lastToken.StartsWith('#')) { return 'Tag' }
    if ($lastToken -and $lastToken -match '^p[1-3]?$') { return 'Priority' }  # Only p1, p2, p3, not "project"
    if ($lastToken -and $lastToken.StartsWith('due:')) { return 'Date' }
    if ($lastToken -and $lastToken.StartsWith('task:')) { return 'TaskId' }

    # If we don't have domain/action yet
    if (-not $Context.Domain -or [string]::IsNullOrEmpty($Context.Domain)) { return 'Domain' }
    if (-not $Context.Action -or [string]::IsNullOrEmpty($Context.Action)) { return 'Action' }

    # Otherwise, suggest argument types
    return 'Arguments'
}

Export-ModuleMember -Function ConvertTo-PmcCommandAst, Parse-PmcArgsFromTokensAst, Get-PmcCompletionContextFromAst