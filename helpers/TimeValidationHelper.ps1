# TimeValidationHelper.ps1 - Validation helpers for time entry screens
# Extracted from TimeListScreen.ps1 to reduce code duplication

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Validate and convert hours input from form values

.PARAMETER values
Hashtable containing 'hours' key

.OUTPUTS
Hashtable with: @{ Valid = $bool; Minutes = $int; Hours = $double; ErrorMessage = $string }

.EXAMPLE
$result = ValidateHoursInput @{ hours = '2.5' }
if ($result.Valid) { $minutes = $result.Minutes }
#>
function ConvertTo-TimeMinutes {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$values
    )

    $result = @{ Valid = $false; Minutes = 0; Hours = 0.0; ErrorMessage = '' }

    # Check required
    if (-not $values.ContainsKey('hours') -or [string]::IsNullOrWhiteSpace($values.hours)) {
        $result.ErrorMessage = "Hours field is required"
        return $result
    }

    # Convert to double
    try {
        $result.Hours = [double]$values.hours
    } catch {
        $result.ErrorMessage = "Invalid hours value: $($values.hours)"
        return $result
    }

    # Validate range
    if ($result.Hours -le 0) {
        $result.ErrorMessage = "Hours must be greater than 0"
        return $result
    }

    $maxHours = (Get-Variable -Name 'MAX_HOURS_PER_ENTRY' -Scope Global -ValueOnly -ErrorAction SilentlyContinue)
    if (-not $maxHours) { $maxHours = 24 }
    if ($result.Hours -gt $maxHours) {
        $result.ErrorMessage = "Hours must be $maxHours or less"
        return $result
    }

    # Convert to minutes with proper rounding
    $result.Minutes = [int][Math]::Round($result.Hours * 60)
    $result.Valid = $true
    return $result
}

<#
.SYNOPSIS
Safely parse date from form values, defaulting to today

.PARAMETER values
Hashtable containing 'date' key

.OUTPUTS
DateTime value (parsed from values or today's date)

.EXAMPLE
$date = ConvertTo-SafeDate @{ date = '2024-01-15' }
#>
function ConvertTo-SafeDate {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$values
    )

    if ($values.ContainsKey('date') -and $values.date) {
        try {
            return [DateTime]$values.date
        } catch {
            Write-PmcTuiLog "Failed to parse date '$($values.date)', using today" "WARNING"
        }
    }
    return [DateTime]::Today
}

<#
.SYNOPSIS
Build time entry data hashtable from form values

.PARAMETER values
Form values hashtable

.PARAMETER minutes
Pre-validated minutes value

.PARAMETER dateValue
Pre-validated date value

.OUTPUTS
Hashtable ready for TaskStore operations

.EXAMPLE
$data = Build-TimeEntryData -Values $values -Minutes 120 -DateValue (Get-Date)
#>
function Build-TimeEntryData {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$values,

        [Parameter(Mandatory=$true)]
        [int]$minutes,

        [Parameter(Mandatory=$true)]
        [DateTime]$dateValue
    )

    return @{
        date = $dateValue
        task = $(if ($values.ContainsKey('task')) { $values.task } else { '' })
        project = $(if ($values.ContainsKey('project')) { $values.project } else { '' })
        timecode = $(if ($values.ContainsKey('timecode')) { $values.timecode } else { '' })
        id1 = $(if ($values.ContainsKey('id1')) { $values.id1 } else { '' })
        id2 = $(if ($values.ContainsKey('id2')) { $values.id2 } else { '' })
        minutes = $minutes
        notes = $(if ($values.ContainsKey('notes')) { $values.notes } else { '' })
    }
}

# Only export when running as a module, not when dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    Export-ModuleMember -Function ConvertTo-TimeMinutes, ConvertTo-SafeDate, Build-TimeEntryData
}
