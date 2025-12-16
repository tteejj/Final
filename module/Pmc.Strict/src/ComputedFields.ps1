Set-StrictMode -Version Latest

# Computed metrics and relations registry for PMC Query Engine

function Get-PmcComputedRegistry {
    # Returns a hashtable keyed by domain with metrics definitions
    # Each metric: @{ Name; AppliesTo; DependsOn=@('timelog'); Type; Resolver=[scriptblock] }
    $weekRange = {
        $today = (Get-Date).Date
        $dow = [int]$today.DayOfWeek # Sunday=0
        $start = $today.AddDays(-$dow) # week starts Sunday
        $end = $start.AddDays(7)
        @{ Start=$start; End=$end }
    }

    $taskMetrics = @{
        time_week = @{
            Name='time_week'; AppliesTo='task'; DependsOn=@('timelog'); Type='int'
            Resolver = {
                param($row,$data)
                if (-not ($row.PSObject.Properties['id'])) { return 0 }
                $id = [int]$row.id
                $range = & $weekRange
                $logs = @($data.timelogs | Where-Object { $_ -ne $null -and $_.taskId -eq $id -and $_.date -and (try { $d=[datetime]$_.date; $d -ge $range.Start -and $d -lt $range.End } catch { $false }) })
                $mins = (@($logs | Measure-Object minutes -Sum).Sum)
                if ($mins -eq $null) { $mins = 0 }
                return [int]$mins
            }
        }
        overdue_days = @{
            Name='overdue_days'; AppliesTo='task'; DependsOn=@(); Type='int'
            Resolver = {
                param($row,$data)
                if (-not ($row.PSObject.Properties['due'])) { return 0 }
                try {
                    $d = [datetime]$row.due
                    $delta = ((Get-Date).Date - $d.Date).Days
                    return [Math]::Max(0, [int]$delta)
                } catch { return 0 }
            }
        }
        time_today = @{
            Name='time_today'; AppliesTo='task'; DependsOn=@('timelog'); Type='int'
            Resolver = {
                param($row,$data)
                if (-not ($row.PSObject.Properties['id'])) { return 0 }
                $id = [int]$row.id
                $today = (Get-Date).Date
                $logs = @($data.timelogs | Where-Object { $_ -ne $null -and $_.taskId -eq $id -and $_.date -and (try { ([datetime]$_.date).Date -eq $today } catch { $false }) })
                $mins = (@($logs | Measure-Object minutes -Sum).Sum)
                if ($mins -eq $null) { $mins = 0 }
                return [int]$mins
            }
        }
        time_month = @{
            Name='time_month'; AppliesTo='task'; DependsOn=@('timelog'); Type='int'
            Resolver = {
                param($row,$data)
                if (-not ($row.PSObject.Properties['id'])) { return 0 }
                $id = [int]$row.id
                $today = (Get-Date).Date
                $start = Get-Date -Year $today.Year -Month $today.Month -Day 1
                $end = $start.AddMonths(1)
                $logs = @($data.timelogs | Where-Object { $_ -ne $null -and $_.taskId -eq $id -and $_.date -and (try { $d=[datetime]$_.date; $d -ge $start -and $d -lt $end } catch { $false }) })
                $mins = (@($logs | Measure-Object minutes -Sum).Sum)
                if ($mins -eq $null) { $mins = 0 }
                return [int]$mins
            }
        }
    }

    $projectMetrics = @{
        task_count = @{
            Name='task_count'; AppliesTo='project'; DependsOn=@('task'); Type='int'
            Resolver = {
                param($row,$data)
                $name = $(if ($row.PSObject.Properties['name']) { [string]$row.name } else { '' })
                if (-not $name) { return 0 }
                $tasks = @($data.tasks | Where-Object { $_ -ne $null -and $_.PSObject.Properties['project'] -and $_.project -eq $name })
                return @($tasks).Count
            }
        }
        time_week = @{
            Name='time_week'; AppliesTo='project'; DependsOn=@('timelog'); Type='int'
            Resolver = {
                param($row,$data)
                $name = $(if ($row.PSObject.Properties['name']) { [string]$row.name } else { '' })
                if (-not $name) { return 0 }
                $range = & $weekRange
                $logs = @($data.timelogs | Where-Object { $_ -ne $null -and $_.project -eq $name -and $_.date -and (try { $d=[datetime]$_.date; $d -ge $range.Start -and $d -lt $range.End } catch { $false }) })
                $mins = (@($logs | Measure-Object minutes -Sum).Sum)
                if ($mins -eq $null) { $mins = 0 }
                return [int]$mins
            }
        }
        time_month = @{
            Name='time_month'; AppliesTo='project'; DependsOn=@('timelog'); Type='int'
            Resolver = {
                param($row,$data)
                $name = $(if ($row.PSObject.Properties['name']) { [string]$row.name } else { '' })
                if (-not $name) { return 0 }
                $today = (Get-Date).Date
                $start = Get-Date -Year $today.Year -Month $today.Month -Day 1
                $end = $start.AddMonths(1)
                $logs = @($data.timelogs | Where-Object { $_ -ne $null -and $_.project -eq $name -and $_.date -and (try { $d=[datetime]$_.date; $d -ge $start -and $d -lt $end } catch { $false }) })
                $mins = (@($logs | Measure-Object minutes -Sum).Sum)
                if ($mins -eq $null) { $mins = 0 }
                return [int]$mins
            }
        }
        overdue_task_count = @{
            Name='overdue_task_count'; AppliesTo='project'; DependsOn=@('task'); Type='int'
            Resolver = {
                param($row,$data)
                $name = $(if ($row.PSObject.Properties['name']) { [string]$row.name } else { '' })
                if (-not $name) { return 0 }
                $today = (Get-Date).Date
                $tasks = @($data.tasks | Where-Object { $_ -ne $null -and $_.PSObject.Properties['project'] -and $_.project -eq $name -and $_.PSObject.Properties['due'] -and (try { ([datetime]$_.due).Date -lt $today } catch { $false }) })
                return @($tasks).Count
            }
        }
    }

    return @{
        task = $taskMetrics
        project = $projectMetrics
        timelog = @{}
    }
}

function Get-PmcMetricsForDomain {
    param([string]$Domain)
    $reg = Get-PmcComputedRegistry
    if ($reg.ContainsKey($Domain)) { return $reg[$Domain] }
    return @{}
}

# Relation-derived fields
function Get-PmcRelationResolvers {
    param([string]$Domain,[string]$Relation)
    $map = @{}
    switch ($Domain) {
        'task' {
            if ($Relation -eq 'project') {
                $map['project_name'] = {
                    param($row,$data)
                    try { if ($row.PSObject.Properties['project']) { return [string]$row.project } } catch {}
                    return ''
                }
            }
        }
        'timelog' {
            if ($Relation -eq 'project') {
                $map['project_name'] = {
                    param($row,$data)
                    try { if ($row.PSObject.Properties['project']) { return [string]$row.project } } catch {}
                    return ''
                }
            }
            if ($Relation -eq 'task') {
                $map['task_text'] = {
                    param($row,$data)
                    try { if ($row.PSObject.Properties['taskId'] -and $row.taskId) { $t = ($data.tasks | Where-Object { $_ -ne $null -and $_.PSObject.Properties['id'] -and [int]$_.id -eq [int]$row.taskId } | Select-Object -First 1); if ($t -and $t.PSObject.Properties['text']) { return [string]$t.text } } } catch {}
                    return ''
                }
            }
        }
        default {}
    }
    return $map
}

#Export-ModuleMember -Function Get-PmcComputedRegistry, Get-PmcMetricsForDomain, Get-PmcRelationResolvers