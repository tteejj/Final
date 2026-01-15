# Project and argument resolvers for strict engine

Set-StrictMode -Version Latest

function Resolve-Project {
    param(
        [Parameter(Mandatory=$true)] $Data,
        [Parameter(Mandatory=$true)][string] $Name
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $q = $Name.Trim(); if ($q.StartsWith('@')) { $q = $q.Substring(1) }
    # Exact name match (case-insensitive)
    $p = $Data.projects | Where-Object { try { $_.name -and ($_.name.ToLower() -eq $q.ToLower()) } catch { $false } } | Select-Object -First 1
    if ($p) { return $p }
    # Alias match (case-insensitive)
    foreach ($proj in $Data.projects) {
        try {
            if (Pmc-HasProp $proj 'aliases' -and $proj.aliases) {
                foreach ($alias in $proj.aliases) {
                    if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                    if ($alias.ToLower() -eq $q.ToLower()) { return $proj }
                }
            }
        } catch {
            # Project alias property access failed - skip this project
        }
    }
    return $null
}

#Export-ModuleMember -Function Resolve-Project