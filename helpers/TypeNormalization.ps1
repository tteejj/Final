using namespace System.Collections.Generic

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Type normalization helpers to eliminate scattered type checking across the codebase.

.DESCRIPTION
Provides utility functions for handling mixed hashtable/PSCustomObject types that
result from different data sources (JSON, TaskStore, etc).

.NOTES
This module eliminates the need for repeated type checks like:
  if ($obj -is [hashtable]) { ... } else { ... }
#>

<#
.SYNOPSIS
Convert PSCustomObject or other types to hashtable format.

.DESCRIPTION
Normalizes data to hashtable format for consistent access patterns.
Handles null values, existing hashtables, and PSCustomObject conversion.

.PARAMETER obj
The object to normalize.

.EXAMPLE
$normalized = ConvertTo-NormalizedHashtable $task
#>
function ConvertTo-NormalizedHashtable {
    param([object]$obj)

    if ($null -eq $obj) { return $null }
    if ($obj -is [hashtable]) { return $obj }

    # Convert PSCustomObject to hashtable
    $hash = @{}
    foreach ($prop in $obj.PSObject.Properties) {
        $hash[$prop.Name] = $prop.Value
    }
    return $hash
}

<#
.SYNOPSIS
Safely get a property from hashtable or PSCustomObject.

.DESCRIPTION
Retrieves property value from either hashtable or PSCustomObject formats,
with fallback to default value if property doesn't exist.

Replaces patterns like:
  if ($obj -is [hashtable]) {
    if ($obj.ContainsKey('name')) { $obj['name'] } else { $default }
  } else {
    if ($null -ne ($obj.PSObject.Properties | Where-Object Name -eq 'name')) { $obj.name } else { $default }
  }

.PARAMETER obj
The object to query (hashtable or PSCustomObject).

.PARAMETER name
The property name to retrieve.

.PARAMETER default
The value to return if property doesn't exist. Default is $null.

.EXAMPLE
$id = $task.id
$parentId = $task.parent_id $null
#>
function Global:Get-SafeProperty {
    param(
        [object]$obj,
        [string]$name,
        [object]$default = $null
    )

    if ($null -eq $obj) { return $default }

    if ($obj -is [hashtable]) {
        if ($obj.ContainsKey($name)) {
            # CRITICAL: Use comma operator to prevent PowerShell from unwrapping single-element arrays
            return ,$obj[$name]
        }
        return $default
    }

    if ($null -ne ($obj.PSObject.Properties | Where-Object Name -eq $name)) {
        # CRITICAL: Use comma operator to prevent PowerShell from unwrapping single-element arrays
        return ,$obj.$name
    }

    return $default
}

<#
.SYNOPSIS
Check if an object has a property or key.

.DESCRIPTION
Checks both hashtable keys and PSCustomObject properties.

.PARAMETER obj
The object to check.

.PARAMETER name
The property/key name to look for.

.EXAMPLE
if (Test-SafeProperty $task 'parent_id') {
    Write-Host "Has parent"
}
#>
function Global:Test-SafeProperty {
    param(
        [object]$obj,
        [string]$name
    )

    if ($null -eq $obj) { return $false }

    if ($obj -is [hashtable]) {
        return $obj.ContainsKey($name)
    }

    return $null -ne ($obj.PSObject.Properties | Where-Object Name -eq $name)
}