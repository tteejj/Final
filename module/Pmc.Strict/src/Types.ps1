# Types and context for the strict engine

Set-StrictMode -Version Latest

class PmcCommandContext {
    [string] $Domain
    [string] $Action
    [hashtable] $Args = @{}
    [string[]] $FreeText = @()
    [string] $Raw = ''

    PmcCommandContext([string]$domain, [string]$action) {
        $this.Domain = $domain
        $this.Action = $action
    }
}

function ConvertTo-PmcTokens {
    param([string]$Buffer)

    # Always return an array, even for empty input
    if ([string]::IsNullOrWhiteSpace($Buffer)) {
        return ,[string[]]@()
    }

    # Simple split preserving quoted strings
    $pattern = '"([^"]*)"|(\S+)'
    $tokens = [string[]]@()

    foreach ($m in [regex]::Matches($Buffer, $pattern)) {
        if ($m.Groups[1].Success) {
            $tokens += $m.Groups[1].Value
        } elseif ($m.Groups[2].Success) {
            $tokens += $m.Groups[2].Value
        }
    }

    # Ensure we always return an array type with Count property
    return ,[string[]]$tokens
}

# Property helpers (consistent across PSCustomObject/Hashtable)
function Pmc-HasProp {
    param($Object, [string]$Name)
    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $false }
    try {
        if ($Object -is [hashtable]) { return $Object.ContainsKey($Name) }
        $psobj = $Object.PSObject
        if ($null -eq $psobj) { return $false }
        return ($psobj.Properties[$Name] -ne $null)
    } catch { return $false }
}

function Pmc-GetProp {
    param($Object, [string]$Name, $Default=$null)
    if (-not (Pmc-HasProp $Object $Name)) { return $Default }
    try { return $Object.$Name } catch { return $Default }
}

function Ensure-PmcTaskProperties {
    <#
    .SYNOPSIS
    Ensures all required properties exist on a task object with proper defaults

    .DESCRIPTION
    Normalizes task objects by adding missing properties with appropriate default values.
    This prevents "property cannot be found" errors when accessing task properties.

    .PARAMETER Task
    The task object to normalize
    #>
    param($Task)

    if ($null -eq $Task) { return }

    # Required task properties with their default values
    $requiredProperties = @{
        'depends' = @()
        'tags' = @()
        'notes' = @()
        'recur' = $null
        'estimatedMinutes' = $null
        'nextSuggestedCount' = 3
        'lastNextShown' = (Get-Date).ToString('yyyy-MM-dd')
        'status' = 'pending'
        'priority' = 0
        'created' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        'project' = 'inbox'
        'due' = $null
    }

    foreach ($propName in $requiredProperties.Keys) {
        if (-not (Pmc-HasProp $Task $propName)) {
            try {
                Add-Member -InputObject $Task -MemberType NoteProperty -Name $propName -NotePropertyValue $requiredProperties[$propName] -Force
            } catch {
                # Ignore errors - property may already exist or object may be read-only
            }
        }
    }
}

function Ensure-PmcProjectProperties {
    <#
    .SYNOPSIS
    Ensures all required properties exist on a project object
    #>
    param($Project)

    if ($null -eq $Project) { return }

    $requiredProperties = @{
        'name' = ''
        'description' = ''
        'aliases' = @()
        'created' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        'isArchived' = $false
        'color' = 'Gray'
        'icon' = '📁'
        'sortOrder' = 0
    }

    foreach ($propName in $requiredProperties.Keys) {
        if (-not (Pmc-HasProp $Project $propName)) {
            try {
                Add-Member -InputObject $Project -MemberType NoteProperty -Name $propName -NotePropertyValue $requiredProperties[$propName] -Force
            } catch {
                # Ignore errors
            }
        }
    }
}

Export-ModuleMember -Function ConvertTo-PmcTokens, Pmc-HasProp, Pmc-GetProp, Ensure-PmcTaskProperties, Ensure-PmcProjectProperties