# ValidationHelper.ps1 - Centralized Validation for PMC Entities
#
# Provides comprehensive validation for tasks, projects, and time logs with:
# - Required field validation
# - Type checking
# - Date range validation
# - Priority validation (0-5)
# - Duplicate detection
# - Custom validators via scriptblocks
# - Detailed error messages
#
# Usage:
#   $result = Test-TaskValid $task
#   if (-not $result.IsValid) {
#       Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [ValidationHelper] Errors: $($result.Errors -join ', ')"
#   }
#
#   $errors = Get-ValidationErrors $data @{
#       name = @{ Required = $true; Type = 'string'; MaxLength = 100 }
#       priority = @{ Required = $false; Type = 'int'; Min = 0; Max = 5 }
#   }

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Validation result object

.DESCRIPTION
Contains validation state and error messages
#>
class ValidationResult {
    [bool]$IsValid
    [List[string]]$Errors
    [hashtable]$FieldErrors  # Field-specific errors: @{ fieldName = @('error1', 'error2') }

    ValidationResult() {
        $this.IsValid = $true
        $this.Errors = [List[string]]::new()
        $this.FieldErrors = @{}
    }

    [void] AddError([string]$message) {
        $this.IsValid = $false
        $this.Errors.Add($message)
    }

    [void] AddFieldError([string]$fieldName, [string]$message) {
        $this.IsValid = $false
        $this.Errors.Add($message)

        if (-not $this.FieldErrors.ContainsKey($fieldName)) {
            $this.FieldErrors[$fieldName] = [List[string]]::new()
        }
        $this.FieldErrors[$fieldName].Add($message)
    }
}

<#
.SYNOPSIS
Validate a task entity

.PARAMETER task
Task hashtable to validate

.OUTPUTS
ValidationResult object

.EXAMPLE
$result = Test-TaskValid @{ text='Buy milk'; priority=3 }
if ($result.IsValid) { Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [ValidationHelper] Valid!" }
#>
function Test-TaskValid {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$task
    )

    $result = [ValidationResult]::new()

    # Required: text
    if (-not $task.ContainsKey('text') -or [string]::IsNullOrWhiteSpace($task.text)) {
        $result.AddFieldError('text', 'Task text is required')
    }

    # Optional: project (string)
    if ($task.ContainsKey('project') -and $task.project -isnot [string]) {
        $result.AddFieldError('project', 'Project must be a string')
    }

    # Optional: priority (0-5)
    if ($task.ContainsKey('priority')) {
        if ($task.priority -isnot [int]) {
            $result.AddFieldError('priority', 'Priority must be an integer')
        }
        elseif ($task.priority -lt 0 -or $task.priority -gt 5) {
            $result.AddFieldError('priority', 'Priority must be between 0 and 5')
        }
    }

    # Optional: due (DateTime)
    if ($task.ContainsKey('due') -and $task.due -ne $null) {
        if ($task.due -isnot [DateTime]) {
            $result.AddFieldError('due', 'Due date must be a DateTime')
        }
        else {
            # H-VAL-1: Date range validation - must be within reasonable range
            $minDate = [DateTime]::new(1900, 1, 1)
            $maxDate = [DateTime]::Now.AddYears(100)
            if ($task.due -lt $minDate -or $task.due -gt $maxDate) {
                $result.AddFieldError('due', 'Due date must be between 1900-01-01 and 100 years from now')
            }
        }
    }

    # Optional: tags (array)
    if ($task.ContainsKey('tags') -and $task.tags -ne $null) {
        if ($task.tags -isnot [array]) {
            $result.AddFieldError('tags', 'Tags must be an array')
        }
    }

    # Optional: completed (bool)
    if ($task.ContainsKey('completed') -and $task.completed -ne $null) {
        if ($task.completed -isnot [bool]) {
            $result.AddFieldError('completed', 'Completed must be a boolean')
        }
    }

    # Optional: status (string, limited values)
    if ($task.ContainsKey('status') -and $task.status -ne $null) {
        $validStatuses = @('todo', 'in-progress', 'done', 'blocked')
        if ($task.status -notin $validStatuses) {
            $result.AddFieldError('status', "Status must be one of: $($validStatuses -join ', ')")
        }
    }

    return $result
}

<#
.SYNOPSIS
Validate a project entity

.PARAMETER project
Project hashtable to validate

.PARAMETER existingProjects
Optional array of existing projects for duplicate checking

.OUTPUTS
ValidationResult object

.EXAMPLE
$result = Test-ProjectValid @{ name='MyProject'; description='...' }
#>
function Test-ProjectValid {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$project,

        [Parameter(Mandatory=$false)]
        [array]$existingProjects = @()
    )

    $result = [ValidationResult]::new()

    # Required: name
    if (-not $project.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($project.name)) {
        $result.AddFieldError('name', 'Project name is required')
    }
    else {
        # Check for duplicates
        $duplicate = $existingProjects | Where-Object { $_.name -eq $project.name }
        if ($duplicate) {
            $result.AddFieldError('name', "Project with name '$($project.name)' already exists")
        }
    }

    # Optional: description (string)
    if ($project.ContainsKey('description') -and $project.description -ne $null) {
        if ($project.description -isnot [string]) {
            $result.AddFieldError('description', 'Description must be a string')
        }
    }

    # Optional: status (string, limited values)
    if ($project.ContainsKey('status') -and $project.status -ne $null) {
        $validStatuses = @('active', 'archived', 'on-hold')
        if ($project.status -notin $validStatuses) {
            $result.AddFieldError('status', "Status must be one of: $($validStatuses -join ', ')")
        }
    }

    return $result
}

<#
.SYNOPSIS
Validate a time log entity

.PARAMETER timelog
Time log hashtable to validate

.PARAMETER taskExists
Optional scriptblock to check if task exists: { param($taskId) return $true/$false }

.OUTPUTS
ValidationResult object

.EXAMPLE
$result = Test-TimeLogValid @{ taskId='abc'; duration=30 }
#>
function Test-TimeLogValid {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$timelog,

        [Parameter(Mandatory=$false)]
        [scriptblock]$taskExists = $null
    )

    $result = [ValidationResult]::new()

    # Required: taskId
    if (-not $timelog.ContainsKey('taskId') -or [string]::IsNullOrWhiteSpace($timelog.taskId)) {
        $result.AddFieldError('taskId', 'Task ID is required')
    }
    elseif ($null -ne $taskExists) {
        # Check if task exists
        $exists = & $taskExists $timelog.taskId
        if (-not $exists) {
            $result.AddFieldError('taskId', "Task with ID '$($timelog.taskId)' does not exist")
        }
    }

    # Required: duration (positive integer)
    if (-not $timelog.ContainsKey('duration')) {
        $result.AddFieldError('duration', 'Duration is required')
    }
    elseif ($timelog.duration -isnot [int]) {
        $result.AddFieldError('duration', 'Duration must be an integer')
    }
    elseif ($timelog.duration -le 0) {
        $result.AddFieldError('duration', 'Duration must be greater than 0')
    }
    # H-VAL-8: Add maximum duration check (1440 minutes = 24 hours)
    elseif ($timelog.duration -gt 1440) {
        $result.AddFieldError('duration', 'Duration must not exceed 1440 minutes (24 hours)')
    }

    # Optional: timestamp (DateTime)
    if ($timelog.ContainsKey('timestamp') -and $timelog.timestamp -ne $null) {
        if ($timelog.timestamp -isnot [DateTime]) {
            $result.AddFieldError('timestamp', 'Timestamp must be a DateTime')
        }
    }

    return $result
}

<#
.SYNOPSIS
Generic validation using a schema definition

.PARAMETER data
Data hashtable to validate

.PARAMETER schema
Validation schema: @{
    fieldName = @{
        Required = $true/$false
        Type = 'string'/'int'/'bool'/'datetime'/'array'
        Min = 0 (for int)
        Max = 100 (for int)
        MinLength = 1 (for string)
        MaxLength = 200 (for string)
        Pattern = '^[a-z]+$' (regex for string)
        Validator = { param($value) return $true/$false } (custom)
    }
}

.OUTPUTS
Array of validation error messages (empty if valid)

.EXAMPLE
$errors = Get-ValidationErrors $data @{
    name = @{ Required = $true; Type = 'string'; MaxLength = 100 }
    age = @{ Required = $false; Type = 'int'; Min = 0; Max = 120 }
}
#>
function Get-ValidationErrors {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$data,

        [Parameter(Mandatory=$true)]
        [hashtable]$schema
    )

    $errors = @()

    foreach ($fieldName in $schema.Keys) {
        $fieldSchema = $schema[$fieldName]
        $fieldErrors = Test-FieldValid $fieldName $data[$fieldName] $fieldSchema -DataContainsKey $data.ContainsKey($fieldName)
        $errors += $fieldErrors
    }

    return $errors
}

<#
.SYNOPSIS
Validate a single field against a schema

.PARAMETER fieldName
Field name (for error messages)

.PARAMETER value
Field value

.PARAMETER schema
Field schema (see Get-ValidationErrors)

.PARAMETER DataContainsKey
Whether the data hashtable contains this key

.OUTPUTS
Array of validation error messages (empty if valid)
#>
function Test-FieldValid {
    param(
        [Parameter(Mandatory=$true)]
        [string]$fieldName,

        [Parameter(Mandatory=$false)]
        $value,

        [Parameter(Mandatory=$true)]
        [hashtable]$schema,

        [Parameter(Mandatory=$false)]
        [bool]$DataContainsKey = $true
    )

    $errors = @()

    # Check if required
    if ($schema.ContainsKey('Required') -and $schema.Required) {
        if (-not $DataContainsKey -or $null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
            $errors += "Field '$fieldName' is required"
            return $errors  # No point checking further if missing
        }
    }

    # If field is optional and not provided, skip validation
    if (-not $DataContainsKey -or $null -eq $value) {
        return $errors
    }

    # Type validation
    if ($schema.ContainsKey('Type')) {
        $expectedType = $schema.Type
        $isValid = switch ($expectedType) {
            'string' { $value -is [string] }
            'int' { $value -is [int] }
            'bool' { $value -is [bool] }
            'datetime' { $value -is [DateTime] }
            'array' { $value -is [array] }
            default { $true }
        }

        if (-not $isValid) {
            $errors += "Field '$fieldName' must be of type $expectedType"
            return $errors  # No point checking further if type is wrong
        }
    }

    # Integer validation
    if ($value -is [int]) {
        if ($schema.ContainsKey('Min') -and $value -lt $schema.Min) {
            $errors += "Field '$fieldName' must be at least $($schema.Min)"
        }
        if ($schema.ContainsKey('Max') -and $value -gt $schema.Max) {
            $errors += "Field '$fieldName' must be at most $($schema.Max)"
        }
    }

    # String validation
    if ($value -is [string]) {
        if ($schema.ContainsKey('MinLength') -and $value.Length -lt $schema.MinLength) {
            $errors += "Field '$fieldName' must be at least $($schema.MinLength) characters"
        }
        if ($schema.ContainsKey('MaxLength') -and $value.Length -gt $schema.MaxLength) {
            $errors += "Field '$fieldName' must be at most $($schema.MaxLength) characters"
        }
        if ($schema.ContainsKey('Pattern') -and $value -notmatch $schema.Pattern) {
            $errors += "Field '$fieldName' does not match required pattern"
        }
    }

    # Custom validator
    if ($schema.ContainsKey('Validator') -and $null -ne $schema.Validator) {
        try {
            $isValid = & $schema.Validator $value
            if (-not $isValid) {
                $errors += "Field '$fieldName' failed custom validation"
            }
        }
        catch {
            $errors += "Field '$fieldName' validator error: $($_.Exception.Message)"
        }
    }

    return $errors
}

Export-ModuleMember -Function Test-TaskValid, Test-ProjectValid, Test-TimeLogValid, Get-ValidationErrors, Test-FieldValid