# Domain Field Schemas for PMC (authoritative field rules)

Set-StrictMode -Version Latest

function Get-PmcFieldSchemasForDomain {
    param([Parameter(Mandatory=$true)][string]$Domain)

    switch ($Domain.ToLower()) {
        'task' {
            return @{
                'id' = @{
                    Name = 'id'
                    Editable = $false
                    Sensitive = $true
                    Hint = '#'
                    DefaultWidth = 4
                    MinWidth = 3
                    DisplayFormat = { param($val) if ($null -ne $val) { [string]$val } else { '' } }
                }
                'text' = @{
                    Name = 'text'
                    Editable = $true
                    Sensitive = $false
                    Hint = 'task text'
                    DefaultWidth = 40
                    MinWidth = 20
                    Normalize = { param([string]$v) return $(if ($null -ne $v) { $v } else { '' }) }
                    Validate = { param([string]$v) return $true }
                    DisplayFormat = { param($val) if ($null -ne $val) { [string]$val } else { '' } }
                }
                'project' = @{
                    Name = 'project'
                    Editable = $false
                    Sensitive = $true
                    Hint = '@project'
                    DefaultWidth = 12
                    MinWidth = 10
                    Normalize = { param([string]$v) return ($v.TrimStart('@').Trim()) }
                    Validate = { param([string]$v) return $true }
                    DisplayFormat = { param($val) if ($null -ne $val) { [string]$val } else { '' } }
                }
                'due' = @{
                    Name = 'due'
                    Editable = $true
                    Sensitive = $false
                    Hint = 'Many formats: yyyymmdd, mmdd, today, eow, eom, +3, 1m, yyyy/mm/dd, etc.'
                    DefaultWidth = 10
                    MinWidth = 8
                    Normalize = {
                        param([string]$v)
                        $x = $(if ($null -ne $v) { $v } else { '' }).Trim()
                        if ($x -eq '') { return '' }

                        # Already correct format
                        if ($x -match '^\d{4}-\d{2}-\d{2}$') { return $x }

                        $today = Get-Date
                        $currentYear = $today.Year

                        # Special keywords
                        switch -Regex ($x) {
                            '^(?i)today$' { return $today.Date.ToString('yyyy-MM-dd') }
                            '^(?i)tomorrow$' { return $today.Date.AddDays(1).ToString('yyyy-MM-dd') }
                            '^(?i)eow$' {
                                # End of week (Sunday)
                                $daysUntilSunday = (7 - [int]$today.DayOfWeek) % 7
                                if ($daysUntilSunday -eq 0) { $daysUntilSunday = 7 }
                                return $today.Date.AddDays($daysUntilSunday).ToString('yyyy-MM-dd')
                            }
                            '^(?i)eom$' {
                                # End of month
                                $lastDay = [DateTime]::DaysInMonth($today.Year, $today.Month)
                                return (New-Object DateTime($today.Year, $today.Month, $lastDay)).ToString('yyyy-MM-dd')
                            }
                            '^[+-]\d+$' {
                                # +3, -5 (days from today)
                                $days = [int]$x
                                return $today.Date.AddDays($days).ToString('yyyy-MM-dd')
                            }
                            '^(\d+)[dmwy]$' {
                                # 1d, 2w, 3m, 1y (relative from today)
                                $matches = [regex]::Match($x, '^(\d+)([dmwy])$')
                                $num = [int]$matches.Groups[1].Value
                                $unit = $matches.Groups[2].Value.ToLower()
                                $targetDate = switch ($unit) {
                                    'd' { $today.AddDays($num) }
                                    'w' { $today.AddDays($num * 7) }
                                    'm' { $today.AddMonths($num) }
                                    'y' { $today.AddYears($num) }
                                }
                                return $targetDate.Date.ToString('yyyy-MM-dd')
                            }
                            '^(\d{1,2})(\d{2})$' {
                                # mmdd format (current year assumed)
                                $matches = [regex]::Match($x, '^(\d{1,2})(\d{2})$')
                                $month = [int]$matches.Groups[1].Value
                                $day = [int]$matches.Groups[2].Value
                                if ($month -lt 1 -or $month -gt 12) { throw "Invalid month: $month" }
                                if ($day -lt 1 -or $day -gt 31) { throw "Invalid day: $day" }
                                return (New-Object DateTime($currentYear, $month, $day)).ToString('yyyy-MM-dd')
                            }
                            '^(\d{4})(\d{2})(\d{2})$' {
                                # yyyymmdd format
                                $matches = [regex]::Match($x, '^(\d{4})(\d{2})(\d{2})$')
                                $year = [int]$matches.Groups[1].Value
                                $month = [int]$matches.Groups[2].Value
                                $day = [int]$matches.Groups[3].Value
                                if ($month -lt 1 -or $month -gt 12) { throw "Invalid month: $month" }
                                if ($day -lt 1 -or $day -gt 31) { throw "Invalid day: $day" }
                                return (New-Object DateTime($year, $month, $day)).ToString('yyyy-MM-dd')
                            }
                        }

                        # Try standard date parsing (yyyy/mm/dd, yy-mm-dd, etc.)
                        $dt = $null
                        if ([DateTime]::TryParse($x, [Globalization.CultureInfo]::CurrentCulture, [Globalization.DateTimeStyles]::None, [ref]$dt)) {
                            return $dt.ToString('yyyy-MM-dd')
                        }

                        throw "Date format not recognized. Try: yyyymmdd, mmdd, today, eow, eom, +3, 1m, or standard formats like yyyy/mm/dd"
                    }
                    Validate = {
                        param([string]$v)
                        if ($v -eq '') { return $true }
                        if ($v -match '^\d{4}-\d{2}-\d{2}$') { return $true }
                        throw "Due must be yyyy-MM-dd"
                    }
                    DisplayFormat = {
                        param($val)
                        $s = [string]$val
                        if (-not $s) { return '' }
                        try { $d=[datetime]::ParseExact($s,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture); return $d.ToString('MM/dd') } catch { return $s }
                    }
                }
                'priority' = @{
                    Name = 'priority'
                    Editable = $true
                    Sensitive = $false
                    Hint = '1..3 (e.g., 2 or P2)'
                    DefaultWidth = 3
                    MinWidth = 3
                    Normalize = {
                        param([string]$v)
                        $x = $(if ($null -ne $v) { $v } else { '' }).Trim()
                        if ($x -eq '') { return '' }
                        if ($x -match '^[Pp]([1-3])$') { return $matches[1] }
                        if ($x -match '^[1-3]$') { return $x }
                        throw "Priority must be 1..3 (e.g., 2 or P2)"
                    }
                    Validate = {
                        param([string]$v)
                        if ($v -eq '') { return $true }
                        if ($v -match '^[1-3]$') { return $true }
                        throw "Priority must be 1..3"
                    }
                    DisplayFormat = { param($val) if ($val) { 'P' + [string]$val } else { '' } }
                }
            }
        }
        'project' {
            return @{
                'name' = @{
                    Name='name'; Editable=$false; Sensitive=$false; Hint='project name'; DefaultWidth=20; MinWidth=12
                    DisplayFormat = { param($v) if ($null -ne $v) { [string]$v } else { '' } }
                }
                'description' = @{
                    Name='description'; Editable=$false; Sensitive=$false; Hint='description'; DefaultWidth=30; MinWidth=15
                    DisplayFormat = { param($v) if ($null -ne $v) { [string]$v } else { '' } }
                }
                'task_count' = @{
                    Name='task_count'; Editable=$false; Sensitive=$false; Hint='tasks'; DefaultWidth=6; MinWidth=4
                    DisplayFormat = { param($v) if ($v -ne $null) { [string]$v } else { '' } }
                }
                'completion' = @{
                    Name='completion'; Editable=$false; Sensitive=$false; Hint='% done'; DefaultWidth=6; MinWidth=3
                    Normalize = { param([string]$v) $(if ($null -ne $v) { $v } else { '' }).Trim('%') }
                    Validate = { param([string]$v) if ($v -eq '' -or $v -match '^\d{1,3}$') { return $true } throw 'completion must be 0..100' }
                    DisplayFormat = { param($v) if ($v -ne $null -and $v -ne '') { ([string]$v).Trim('%') + '%' } else { '' } }
                }
            }
        }
        'timelog' {
            return @{
                'date' = @{
                    Name='date'; Editable=$true; Sensitive=$false; Hint='yyyy-MM-dd'; DefaultWidth=10; MinWidth=8
                    Normalize = {
                        param([string]$v)
                        $x = $(if ($null -ne $v) { $v } else { '' }).Trim(); if ($x -eq '') { return '' }
                        if ($x -match '^\d{4}-\d{2}-\d{2}$') { return $x }
                        $dt = $null
                        if ([DateTime]::TryParse($x, [Globalization.CultureInfo]::CurrentCulture, [Globalization.DateTimeStyles]::None, [ref]$dt)) { return $dt.ToString('yyyy-MM-dd') }
                        throw 'Date must be yyyy-MM-dd'
                    }
                    Validate = { param([string]$v) if ($v -eq '' -or $v -match '^\d{4}-\d{2}-\d{2}$') { return $true } throw 'Date must be yyyy-MM-dd' }
                    DisplayFormat = { param($v) if ($v) { try { ([datetime]::ParseExact([string]$v,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)).ToString('MM/dd') } catch { [string]$v } } else { '' } }
                }
                'project' = @{
                    Name='project'; Editable=$false; Sensitive=$true; Hint='@project'; DefaultWidth=15; MinWidth=10
                    DisplayFormat = { param($v) if ($null -ne $v) { [string]$v } else { '' } }
                }
                'duration' = @{
                    Name='duration'; Editable=$true; Sensitive=$false; Hint='minutes or h/m (e.g., 1.5h, 90m)'; DefaultWidth=8; MinWidth=6
                    Normalize = {
                        param([string]$v)
                        $x = $(if ($null -ne $v) { $v } else { '' }).Trim(); if ($x -eq '') { return '' }
                        if ($x -match '^(\d+(?:\.\d+)?)h$') { return ([int]([double]$matches[1] * 60)).ToString() }
                        if ($x -match '^(\d+)m$') { return $matches[1] }
                        if ($x -match '^(\d+)$') { return $x }
                        throw 'Duration must be minutes or h/m format'
                    }
                    Validate = { param([string]$v) if ($v -eq '' -or $v -match '^\d+$') { return $true } throw 'Duration must be whole minutes' }
                    DisplayFormat = { param($v)
                        if ($v -match '^\d+$') {
                            $mins=[int]$v
                            if ($mins -ge 60) {
                                return '{0}h {1}m' -f ([int]($mins/60)), ($mins%60)
                            } else {
                                return $mins.ToString() + 'm'
                            }
                        } else {
                            return [string]$v
                        }
                    }
                }
                'description' = @{
                    Name='description'; Editable=$true; Sensitive=$false; Hint='description'; DefaultWidth=35; MinWidth=15
                    DisplayFormat = { param($v) if ($null -ne $v) { [string]$v } else { '' } }
                }
            }
        }
        default {
            return @{}
        }
    }
}

function Get-PmcFieldSchema {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string]$Field
    )
    $all = Get-PmcFieldSchemasForDomain -Domain $Domain
    if ($all.ContainsKey($Field)) { return $all[$Field] }
    return $null
}

#Export-ModuleMember -Function Get-PmcFieldSchemasForDomain, Get-PmcFieldSchema