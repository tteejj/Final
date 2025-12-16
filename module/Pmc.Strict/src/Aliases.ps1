# User alias system: alias, alias add, alias remove; show aliases

function Get-PmcAliasTable {
    $data = Get-PmcDataAlias
    if (-not (Pmc-HasProp $data 'aliases') -or -not $data.aliases) { $data.aliases = @{} }
    # Normalize to hashtable if JSON loaded as PSCustomObject
    if ($data.aliases -is [pscustomobject]) {
        $ht = @{}
        foreach ($p in $data.aliases.PSObject.Properties) { $ht[$p.Name] = $p.Value }
        $data.aliases = $ht
    }
    # Seed helpful defaults if empty
    try {
        $keyCount = 0
        if ($data.aliases -is [hashtable]) { $keyCount = @($data.aliases.Keys).Count }
        elseif ($data.aliases.PSObject -and $data.aliases.PSObject.Properties) { $keyCount = @($data.aliases.PSObject.Properties.Name).Count }
    } catch { $keyCount = 0 }
    if ($keyCount -eq 0) {
        $data.aliases['projects'] = 'view projects'
    }
    return $data.aliases
}

function Save-PmcAliases($aliases) {
    $data = Get-PmcDataAlias
    $data.aliases = $aliases
    Save-StrictData $data 'alias update'
}

function Get-PmcAliasList {
    param([PmcCommandContext]$Context)
    $aliases = Get-PmcAliasTable
    Write-PmcStyled -Style 'Header' -Text "\nALIASES"
    Write-PmcStyled -Style 'Border' -Text "────────"
    $rows = @()
    if ($aliases -is [hashtable]) {
        foreach ($entry in $aliases.GetEnumerator()) {
            $rows += @{ alias = [string]$entry.Key; expands = [string]$entry.Value }
        }
    } elseif ($aliases -is [pscustomobject]) {
        foreach ($p in $aliases.PSObject.Properties) {
            $rows += @{ alias = [string]$p.Name; expands = [string]$p.Value }
        }
    }
    if (@($rows).Count -eq 0) { Write-PmcStyled -Style 'Warning' -Text 'No aliases defined'; return }
    $rows = $rows | Sort-Object alias

    # Convert to universal display format
    $columns = @{
        "alias" = @{ Header = "Alias"; Width = 16; Alignment = "Left"; Editable = $false }
        "expands" = @{ Header = "Expands To"; Width = 48; Alignment = "Left"; Editable = $false }
    }

    # Convert rows to PSCustomObject format
    $dataObjects = @()
    foreach ($row in $rows) {
        $obj = New-Object PSCustomObject
        foreach ($key in $row.Keys) {
            $obj | Add-Member -NotePropertyName $key -NotePropertyValue $row[$key]
        }
        $dataObjects += $obj
    }

    Show-PmcCustomGrid -Domain "config" -Columns $columns -Data $dataObjects -Title "User Aliases"
}

function Add-PmcAlias {
    param(
        $Context,
        [string]$Name,
        [string]$Value
    )

    # Handle both PmcCommandContext and direct parameter calls
    if ($Context -and -not $Name -and -not $Value) {
        # Called with Context parameter
        if ($Context.PSObject.Properties['FreeText']) {
            $text = ($Context.FreeText -join ' ').Trim()
            if (-not $text -or -not ($text -match '^(\S+)\s+(.+)$')) {
                Write-PmcStyled -Style 'Warning' -Text "Usage: alias add <name> <expansion...>"
                return
            }
            $name = $matches[1]; $expansion = $matches[2]
        } else {
            Write-PmcStyled -Style 'Error' -Text "Invalid context parameter"
            return
        }
    } elseif ($Name -and $Value) {
        # Called with direct parameters
        $name = $Name; $expansion = $Value
    } else {
        Write-PmcStyled -Style 'Warning' -Text "Usage: Add-PmcAlias -Name <name> -Value <expansion> or alias add <name> <expansion>"
        return
    }

    $aliases = Get-PmcAliasTable
    $aliases[$name] = $expansion
    Save-PmcAliases $aliases
    Write-PmcStyled -Style 'Success' -Text ("Added alias '{0}' = {1}" -f $name, $expansion)
}

function Remove-PmcAlias {
    param([PmcCommandContext]$Context)
    $name = ($Context.FreeText -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { Write-PmcStyled -Style 'Warning' -Text "Usage: alias remove <name>"; return }
    $aliases = Get-PmcAliasTable
    if (-not $aliases.ContainsKey($name)) { Write-PmcStyled -Style 'Error' -Text ("Alias '{0}' not found" -f $name); return }
    $aliases.Remove($name) | Out-Null
    Save-PmcAliases $aliases
    Write-PmcStyled -Style 'Success' -Text ("Removed alias '{0}'" -f $name)
}

function Expand-PmcUserAliases {
    param([string]$Buffer)
    try {
        $aliases = Get-PmcAliasTable
        if (-not $aliases) { return $Buffer }
        # Normalize alias keys safely
        $keys = @()
        if ($aliases -is [hashtable]) { $keys = @($aliases.Keys) }
        elseif ($aliases.PSObject -and $aliases.PSObject.Properties) { $keys = @($aliases.PSObject.Properties.Name) }
        if (@($keys).Count -eq 0) { return $Buffer }
        $tokens = ConvertTo-PmcTokens $Buffer
        if ($tokens.Count -eq 0) { return $Buffer }
        $first = $tokens[0]
        $hasKey = $false
        $expansion = $null
        if ($aliases -is [hashtable]) { $hasKey = $aliases.ContainsKey($first); if ($hasKey) { $expansion = [string]$aliases[$first] } }
        elseif ($aliases.PSObject) { try { $expansion = [string]($aliases.$first); $hasKey = -not [string]::IsNullOrEmpty($expansion) } catch {
            # Property access failed - alias does not exist
        } }
        if ($hasKey -and $expansion) {
            # Replace first token with its expansion
            $rest = ''
            if ($tokens.Count -gt 1) { $rest = ' ' + ($tokens[1..($tokens.Count-1)] -join ' ') }
            return ($expansion + $rest)
        }
    } catch {
        # Alias expansion failed - return original buffer
    }
    return $Buffer
}

Export-ModuleMember -Function Get-PmcAliasTable, Save-PmcAliases, Get-PmcAliasList, Add-PmcAlias, Remove-PmcAlias, Expand-PmcUserAliases