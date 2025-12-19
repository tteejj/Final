# InlineEditorFields.ps1 - Field type handlers for InlineEditor
#
# Extracted helpers for field value parsing and preview formatting
# Used by InlineEditor.ps1 to handle different field types

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Parse date text input into DateTime

.PARAMETER dateText
Raw text from date input field

.OUTPUTS
DateTime or $null if parsing fails

.EXAMPLE
$date = ConvertTo-DateFromText "+7"  # Returns 7 days from now
$date = ConvertTo-DateFromText "today"  # Returns today
$date = ConvertTo-DateFromText "2024-01-15"  # Returns parsed date
#>
function ConvertTo-DateFromText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$dateText
    )

    $dateText = $dateText.Trim().ToLower()
    
    if ([string]::IsNullOrWhiteSpace($dateText)) {
        return $null
    }

    # Parse relative dates like "+7" or "-3"
    if ($dateText -match '^([+-])(\d+)$') {
        $sign = $matches[1]
        $days = [int]$matches[2]
        if ($sign -eq '+') {
            return [DateTime]::Now.AddDays($days)
        }
        else {
            return [DateTime]::Now.AddDays(-$days)
        }
    }

    # Special keywords
    switch ($dateText) {
        { $_ -in @('today', 't') } { return [DateTime]::Today }
        { $_ -in @('tomorrow', 'tom') } { return [DateTime]::Today.AddDays(1) }
        'yesterday' { return [DateTime]::Today.AddDays(-1) }
        'eom' { 
            $now = [DateTime]::Now
            return [DateTime]::new($now.Year, $now.Month, [DateTime]::DaysInMonth($now.Year, $now.Month))
        }
        'eoy' { return [DateTime]::new([DateTime]::Now.Year, 12, 31) }
        'som' {
            $now = [DateTime]::Now
            return [DateTime]::new($now.Year, $now.Month, 1)
        }
    }

    # Parse YYYYMMDD format (20251125)
    if ($dateText -match '^\d{8}$') {
        try {
            $year = [int]$dateText.Substring(0, 4)
            $month = [int]$dateText.Substring(4, 2)
            $day = [int]$dateText.Substring(6, 2)
            return [DateTime]::new($year, $month, $day)
        }
        catch {
            # Invalid date, fall through
        }
    }

    # Parse YYMMDD format (251125)
    if ($dateText -match '^\d{6}$') {
        try {
            $year = 2000 + [int]$dateText.Substring(0, 2)
            $month = [int]$dateText.Substring(2, 2)
            $day = [int]$dateText.Substring(4, 2)
            return [DateTime]::new($year, $month, $day)
        }
        catch {
            # Invalid date, fall through
        }
    }

    # Parse absolute dates (standard formats)
    try {
        return [DateTime]::Parse($dateText)
    }
    catch {
        return $null
    }
}

<#
.SYNOPSIS
Parse tags from comma-separated text

.PARAMETER tagsText
Comma-separated tag string

.OUTPUTS
Array of validated tag strings

.EXAMPLE
$tags = ConvertTo-TagsFromText "urgent, high-priority, bug"
#>
function ConvertTo-TagsFromText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$tagsText
    )

    if ([string]::IsNullOrWhiteSpace($tagsText)) {
        return @()
    }

    # Split by comma and trim
    $tags = $tagsText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    # Validate tags match pattern ^[a-zA-Z0-9_-]+$
    $validTags = @()
    foreach ($tag in $tags) {
        if ($tag -match '^[a-zA-Z0-9_-]+$') {
            $validTags += $tag
        }
        else {
            # Write-PmcTuiLog "Invalid tag '$tag' - must contain only letters, numbers, underscore, or hyphen" "WARNING"
        }
    }

    return @($validTags)
}

<#
.SYNOPSIS
Format a number value with a visual slider

.PARAMETER Value
Current value

.PARAMETER Min
Minimum value

.PARAMETER Max
Maximum value

.OUTPUTS
String like "[----●-----] 4"

.EXAMPLE
Format-NumberSlider -Value 4 -Min 0 -Max 10
#>
function Format-NumberSlider {
    param(
        [Parameter(Mandatory=$true)]
        [int]$Value,

        [Parameter(Mandatory=$false)]
        [int]$Min = 0,

        [Parameter(Mandatory=$false)]
        [int]$Max = 10
    )

    $range = $Max - $Min
    $position = if ($range -gt 0) { [Math]::Floor(($Value - $Min) / $range * 10) } else { 0 }
    $slider = "[" + ("-" * $position) + "●" + ("-" * (10 - $position)) + "] $Value"
    return $slider
}

<#
.SYNOPSIS
Format tags array for display

.PARAMETER Tags
Array of tag strings

.OUTPUTS
String like "[tag1] [tag2]" or "(no tags)"

.EXAMPLE
Format-TagsDisplay @("urgent", "bug")
#>
function Format-TagsDisplay {
    param(
        [Parameter(Mandatory=$false)]
        [array]$Tags
    )

    if ($null -eq $Tags -or $Tags.Count -eq 0) {
        return "(no tags)"
    }
    return "[" + ($Tags -join "] [") + "]"
}

# Only export when running as a module, not when dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    Export-ModuleMember -Function ConvertTo-DateFromText, ConvertTo-TagsFromText, Format-NumberSlider, Format-TagsDisplay
}
