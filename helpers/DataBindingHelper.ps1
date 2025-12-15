# DataBindingHelper.ps1 - Helper functions to bind PMC data to widgets
#
# Provides conversion functions between PMC data structures and widget field configurations:
# - PMC field schema → InlineEditor field definitions
# - Widget values → PMC data format
# - Type conversions (string, int, datetime, array)
# - Default value handling
#
# Usage:
#   # Convert PMC task to widget fields
#   $fields = ConvertTo-WidgetFields -Entity $task -EntityType 'task'
#
#   # Convert widget values back to PMC format
#   $pmcTask = ConvertFrom-WidgetValues -Values $widgetValues -EntityType 'task'
#
#   # Get field definitions for entity type
#   $fieldDefs = Get-EntityFieldDefinitions -EntityType 'task'

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Convert PMC entity to widget field definitions

.PARAMETER Entity
Entity hashtable (task, project, timelog)

.PARAMETER EntityType
Entity type: 'task', 'project', 'timelog'

.PARAMETER FieldSchema
Optional custom field schema (uses default if not provided)

.OUTPUTS
Array of field definition hashtables for InlineEditor
#>
function ConvertTo-WidgetFields {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Entity,

        [Parameter(Mandatory=$true)]
        [ValidateSet('task', 'project', 'timelog', 'custom')]
        [string]$EntityType,

        [Parameter(Mandatory=$false)]
        [hashtable[]]$FieldSchema = $null
    )

    # Use default schema if not provided
    if ($null -eq $FieldSchema) {
        $FieldSchema = Get-EntityFieldDefinitions -EntityType $EntityType
    }

    $widgetFields = @()

    foreach ($fieldDef in $FieldSchema) {
        $fieldName = $fieldDef.Name
        $fieldType = $fieldDef.Type
        $fieldLabel = $(if ($fieldDef.ContainsKey('Label')) { $fieldDef.Label } else { $fieldName })

        # Get current value from entity
        $value = $(if ($Entity.ContainsKey($fieldName)) { $Entity[$fieldName] } else { $null })

        # Build widget field definition
        $widgetField = @{
            Name = $fieldName
            Label = $fieldLabel
            Type = $fieldType
            Value = $value
        }

        # Add optional properties
        if ($fieldDef.ContainsKey('Required')) {
            $widgetField.Required = $fieldDef.Required
        }

        if ($fieldDef.ContainsKey('Min')) {
            $widgetField.Min = $fieldDef.Min
        }

        if ($fieldDef.ContainsKey('Max')) {
            $widgetField.Max = $fieldDef.Max
        }

        if ($fieldDef.ContainsKey('MaxLength')) {
            $widgetField.MaxLength = $fieldDef.MaxLength
        }

        if ($fieldDef.ContainsKey('Placeholder')) {
            $widgetField.Placeholder = $fieldDef.Placeholder
        }

        if ($fieldDef.ContainsKey('Options')) {
            $widgetField.Options = $fieldDef.Options
        }

        $widgetFields += $widgetField
    }

    return $widgetFields
}

<#
.SYNOPSIS
Convert widget values back to PMC entity format

.PARAMETER Values
Hashtable of widget values

.PARAMETER EntityType
Entity type: 'task', 'project', 'timelog'

.PARAMETER FieldSchema
Optional custom field schema (uses default if not provided)

.OUTPUTS
Hashtable in PMC entity format
#>
function ConvertFrom-WidgetValues {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Values,

        [Parameter(Mandatory=$true)]
        [ValidateSet('task', 'project', 'timelog', 'custom')]
        [string]$EntityType,

        [Parameter(Mandatory=$false)]
        [hashtable[]]$FieldSchema = $null
    )

    # Use default schema if not provided
    if ($null -eq $FieldSchema) {
        $FieldSchema = Get-EntityFieldDefinitions -EntityType $EntityType
    }

    $pmcEntity = @{}

    foreach ($fieldDef in $FieldSchema) {
        $fieldName = $fieldDef.Name
        $fieldType = $fieldDef.Type

        if ($Values.ContainsKey($fieldName)) {
            $value = $Values[$fieldName]

            # Type conversion
            $convertedValue = ConvertTo-PmcType -Value $value -TargetType $fieldType

            $pmcEntity[$fieldName] = $convertedValue
        }
    }

    return $pmcEntity
}

<#
.SYNOPSIS
Convert value to PMC type

.PARAMETER Value
Value to convert

.PARAMETER TargetType
Target PMC type: 'string', 'int', 'bool', 'datetime', 'array'

.OUTPUTS
Converted value
#>
function ConvertTo-PmcType {
    param(
        [Parameter(Mandatory=$true)]
        $Value,

        [Parameter(Mandatory=$true)]
        [string]$TargetType
    )

    if ($null -eq $Value) {
        return $null
    }

    switch ($TargetType) {
        'string' {
            return $Value.ToString()
        }
        'text' {
            return $Value.ToString()
        }
        'int' {
            return [int]$Value
        }
        'number' {
            return [int]$Value
        }
        'bool' {
            return [bool]$Value
        }
        'datetime' {
            if ($Value -is [DateTime]) {
                return $Value
            }
            return [DateTime]::Parse($Value.ToString())
        }
        'date' {
            if ($Value -is [DateTime]) {
                return $Value
            }
            return [DateTime]::Parse($Value.ToString())
        }
        'array' {
            if ($Value -is [array]) {
                return $Value
            }
            return @($Value)
        }
        'tags' {
            if ($Value -is [array]) {
                return $Value
            }
            return @($Value)
        }
        default {
            return $Value
        }
    }
}

<#
.SYNOPSIS
Get default field definitions for entity type

.PARAMETER EntityType
Entity type: 'task', 'project', 'timelog'

.OUTPUTS
Array of field definition hashtables
#>
function Get-EntityFieldDefinitions {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('task', 'project', 'timelog')]
        [string]$EntityType
    )

    switch ($EntityType) {
        'task' {
            return @(
                @{
                    Name = 'text'
                    Label = 'Task'
                    Type = 'text'
                    Required = $true
                    MaxLength = 500
                    Placeholder = 'What needs to be done?'
                }
                @{
                    Name = 'project'
                    Label = 'Project'
                    Type = 'project'
                    Required = $false
                }
                @{
                    Name = 'priority'
                    Label = 'Priority'
                    Type = 'number'
                    Required = $false
                    Min = 0
                    Max = 5
                    Value = 3
                }
                @{
                    Name = 'due'
                    Label = 'Due Date'
                    Type = 'date'
                    Required = $false
                }
                @{
                    Name = 'tags'
                    Label = 'Tags'
                    Type = 'tags'
                    Required = $false
                }
                @{
                    Name = 'notes'
                    Label = 'Notes'
                    Type = 'text'
                    Required = $false
                    MaxLength = 2000
                    Placeholder = 'Additional notes...'
                }
                @{
                    Name = 'completed'
                    Label = 'Completed'
                    Type = 'bool'
                    Required = $false
                    Value = $false
                }
            )
        }

        'project' {
            return @(
                @{
                    Name = 'name'
                    Label = 'Project Name'
                    Type = 'text'
                    Required = $true
                    MaxLength = 100
                    Placeholder = 'Project name'
                }
                @{
                    Name = 'description'
                    Label = 'Description'
                    Type = 'text'
                    Required = $false
                    MaxLength = 1000
                    Placeholder = 'Project description...'
                }
                @{
                    Name = 'status'
                    Label = 'Status'
                    Type = 'text'
                    Required = $false
                    Options = @('active', 'completed', 'archived', 'on-hold')
                    Value = 'active'
                }
                @{
                    Name = 'tags'
                    Label = 'Tags'
                    Type = 'tags'
                    Required = $false
                }
            )
        }

        'timelog' {
            return @(
                @{
                    Name = 'taskId'
                    Label = 'Task ID'
                    Type = 'text'
                    Required = $true
                }
                @{
                    Name = 'duration'
                    Label = 'Duration (minutes)'
                    Type = 'number'
                    Required = $true
                    Min = 1
                    Max = 1440
                    Value = 30
                }
                @{
                    Name = 'timestamp'
                    Label = 'Timestamp'
                    Type = 'datetime'
                    Required = $false
                    Value = (Get-Date)
                }
                @{
                    Name = 'notes'
                    Label = 'Notes'
                    Type = 'text'
                    Required = $false
                    MaxLength = 500
                }
            )
        }

        default {
            return @()
        }
    }
}

<#
.SYNOPSIS
Merge field definitions with entity values

.PARAMETER FieldDefinitions
Array of field definition hashtables

.PARAMETER Entity
Entity hashtable with values

.OUTPUTS
Array of field definitions with values populated
#>
function Merge-FieldDefinitionsWithEntity {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable[]]$FieldDefinitions,

        [Parameter(Mandatory=$true)]
        [hashtable]$Entity
    )

    $mergedFields = @()

    foreach ($fieldDef in $FieldDefinitions) {
        $mergedField = $fieldDef.Clone()
        $fieldName = $mergedField.Name

        if ($Entity.ContainsKey($fieldName)) {
            $mergedField.Value = $Entity[$fieldName]
        }

        $mergedFields += $mergedField
    }

    return $mergedFields
}

<#
.SYNOPSIS
Get display value for a field

.PARAMETER Value
Field value

.PARAMETER FieldType
Field type

.OUTPUTS
Formatted display string
#>
function Get-FieldDisplayValue {
    param(
        [Parameter(Mandatory=$true)]
        $Value,

        [Parameter(Mandatory=$true)]
        [string]$FieldType
    )

    if ($null -eq $Value) {
        return "(empty)"
    }

    switch ($FieldType) {
        'date' {
            if ($Value -is [DateTime]) {
                return $Value.ToString("yyyy-MM-dd (ddd)")
            }
            return $Value.ToString()
        }
        'datetime' {
            if ($Value -is [DateTime]) {
                return $Value.ToString("yyyy-MM-dd HH:mm")
            }
            return $Value.ToString()
        }
        'bool' {
            return $(if ($Value) { "Yes" } else { "No" })
        }
        'tags' {
            if ($Value -is [array]) {
                if ($Value.Count -eq 0) {
                    return "(no tags)"
                }
                return "[" + ($Value -join "] [") + "]"
            }
            return $Value.ToString()
        }
        'array' {
            if ($Value -is [array]) {
                if ($Value.Count -eq 0) {
                    return "(empty array)"
                }
                return ($Value -join ", ")
            }
            return $Value.ToString()
        }
        default {
            return $Value.ToString()
        }
    }
}

<#
.SYNOPSIS
Validate field value against field definition

.PARAMETER Value
Field value

.PARAMETER FieldDefinition
Field definition hashtable

.OUTPUTS
Array of validation error messages (empty if valid)
#>
function Test-FieldValue {
    param(
        [Parameter(Mandatory=$true)]
        $Value,

        [Parameter(Mandatory=$true)]
        [hashtable]$FieldDefinition
    )

    $errors = @()
    $fieldName = $FieldDefinition.Name
    $fieldType = $FieldDefinition.Type

    # Required field check
    if ($FieldDefinition.ContainsKey('Required') -and $FieldDefinition.Required) {
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace($Value.ToString())) {
            $errors += "$fieldName is required"
            return $errors
        }
    }

    # Skip remaining checks if value is null/empty
    if ($null -eq $Value) {
        return $errors
    }

    # Type-specific validation
    switch ($fieldType) {
        'number' {
            if ($FieldDefinition.ContainsKey('Min') -and $Value -lt $FieldDefinition.Min) {
                $errors += "$fieldName must be >= $($FieldDefinition.Min)"
            }
            if ($FieldDefinition.ContainsKey('Max') -and $Value -gt $FieldDefinition.Max) {
                $errors += "$fieldName must be <= $($FieldDefinition.Max)"
            }
        }
        'text' {
            $strValue = $Value.ToString()
            if ($FieldDefinition.ContainsKey('MaxLength') -and $strValue.Length -gt $FieldDefinition.MaxLength) {
                $errors += "$fieldName must be <= $($FieldDefinition.MaxLength) characters"
            }
        }
    }

    return $errors
}

<#
.SYNOPSIS
Create UniversalList column definitions from field definitions

.PARAMETER FieldDefinitions
Array of field definition hashtables

.PARAMETER ColumnWidths
Optional hashtable of column widths (fieldName -> width)

.OUTPUTS
Array of column definition hashtables for UniversalList
#>
function ConvertTo-ListColumns {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable[]]$FieldDefinitions,

        [Parameter(Mandatory=$false)]
        [hashtable]$ColumnWidths = @{}
    )

    $columns = @()

    foreach ($fieldDef in $FieldDefinitions) {
        $fieldName = $fieldDef.Name
        $fieldLabel = $(if ($fieldDef.ContainsKey('Label')) { $fieldDef.Label } else { $fieldName })
        $fieldType = $fieldDef.Type

        # Determine default width based on type
        $defaultWidth = switch ($fieldType) {
            'text' { 40 }
            'number' { 6 }
            'date' { 12 }
            'datetime' { 18 }
            'bool' { 8 }
            'tags' { 30 }
            'project' { 15 }
            default { 20 }
        }

        $width = $(if ($ColumnWidths.ContainsKey($fieldName)) { $ColumnWidths[$fieldName] } else { $defaultWidth })

        # Create column definition
        $column = @{
            Name = $fieldName
            Label = $fieldLabel
            Width = $width
            Align = 'left'
        }

        # Add formatter for specific types
        if ($fieldType -eq 'date' -or $fieldType -eq 'datetime') {
            $column.Format = {
                param($value)
                if ($null -ne $value -and $value -is [DateTime]) {
                    if ($fieldType -eq 'date') {
                        return $value.ToString("MMM dd yyyy")
                    } else {
                        return $value.ToString("MMM dd HH:mm")
                    }
                }
                return ""
            }
        }
        elseif ($fieldType -eq 'bool') {
            $column.Format = {
                param($value)
                return $(if ($value) { "[OK]" } else { "" })
            }
        }
        elseif ($fieldType -eq 'tags' -or $fieldType -eq 'array') {
            $column.Format = {
                param($value)
                if ($value -is [array]) {
                    return ($value -join ", ")
                }
                return ""
            }
        }

        $columns += $column
    }

    return $columns
}

# Export functions
Export-ModuleMember -Function @(
    'ConvertTo-WidgetFields',
    'ConvertFrom-WidgetValues',
    'ConvertTo-PmcType',
    'Get-EntityFieldDefinitions',
    'Merge-FieldDefinitionsWithEntity',
    'Get-FieldDisplayValue',
    'Test-FieldValue',
    'ConvertTo-ListColumns'
)