# Analytics and Insights: stats, burndown, velocity

function Get-PmcStatistics {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Analytics" -Message "Starting stats"

    $data = Get-PmcDataAlias
    $now = Get-Date
    $d7 = $now.Date.AddDays(-7)
    $d30 = $now.Date.AddDays(-30)

    $pending = @($data.tasks | Where-Object { $_.status -eq 'pending' }).Count
    $completed = @($data.tasks | Where-Object { $_.status -eq 'completed' }).Count
    $completed7 = @($data.tasks | Where-Object { $_.completed -and ([datetime]$_.completed) -ge $d7 }).Count
    $added7 = @($data.tasks | Where-Object { $_.created -and ([datetime]$_.created) -ge $d7 }).Count

    $logs7 = @($data.timelogs | Where-Object { $_.date -and ([datetime]$_.date) -ge $d7 })
    $minutes7 = ($logs7 | Measure-Object minutes -Sum).Sum
    $hours7 = [Math]::Round(($minutes7/60),2)

    $rows = @(
        @{ metric='Pending tasks'; value=$pending },
        @{ metric='Completed (all)'; value=$completed },
        @{ metric='Completed (7d)'; value=$completed7 },
        @{ metric='Added (7d)'; value=$added7 },
        @{ metric='Hours logged (7d)'; value=$hours7 }
    )
    # Convert to universal display format
    $columns = @{
        "metric" = @{ Header = "Metric"; Width = 26; Alignment = "Left"; Editable = $false }
        "value" = @{ Header = "Value"; Width = 10; Alignment = "Right"; Editable = $false }
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

    Show-PmcCustomGrid -Domain "stats" -Columns $columns -Data $dataObjects -Title 'STATS'

    Write-PmcDebug -Level 2 -Category "Analytics" -Message "Stats completed" -Data @{ Pending=$pending; Completed7=$completed7; Hours7=$hours7 }
}

function Show-PmcBurndownChart {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Analytics" -Message "Starting burndown"

    $data = Get-PmcDataAlias
    $today = (Get-Date).Date
    $horizon = 7
    $rows = @()

    for ($i=0; $i -lt $horizon; $i++) {
        $day = $today.AddDays($i)
        $remaining = @($data.tasks | Where-Object {
            try {
                $_.status -eq 'pending' -and (
                    (-not $_.due) -or ([datetime]$_.due) -ge $day
                )
            } catch { $false }
        }).Count
        $rows += @{ date=$day.ToString('yyyy-MM-dd'); remaining=$remaining }
    }

    # Convert to universal display format
    $columns = @{
        "date" = @{ Header = "Date"; Width = 12; Alignment = "Center"; Editable = $false }
        "remaining" = @{ Header = "Remaining"; Width = 12; Alignment = "Right"; Editable = $false }
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

    Show-PmcCustomGrid -Domain "stats" -Columns $columns -Data $dataObjects -Title 'BURNDOWN (next 7 days)'
    Show-PmcTip 'Simple burndown: remaining tasks projected by day'

    Write-PmcDebug -Level 2 -Category "Analytics" -Message "Burndown completed"
}

function Get-PmcVelocity {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Analytics" -Message "Starting velocity"

    $data = Get-PmcDataAlias
    $startOfWeek = (Get-Date).Date.AddDays(-1 * (([int](Get-Date).DayOfWeek + 6) % 7))
    $rows = @()
    for ($w=0; $w -lt 4; $w++) {
        $wStart = $startOfWeek.AddDays(-7*$w)
        $wEnd = $wStart.AddDays(7)
        $done = @($data.tasks | Where-Object { $_.status -eq 'completed' -and $_.completed -and ([datetime]$_.completed) -ge $wStart -and ([datetime]$_.completed) -lt $wEnd }).Count
        $mins = @($data.timelogs | Where-Object { $_.date -and ([datetime]$_.date) -ge $wStart -and ([datetime]$_.date) -lt $wEnd } | Measure-Object minutes -Sum).Sum
        $hrs = [Math]::Round(($mins/60),1)
        $rows += @{ week=$wStart.ToString('yyyy-MM-dd'); completed=$done; hours=$hrs }
    }

    # Convert to universal display format
    $columns = @{
        "week" = @{ Header = "Week"; Width = 12; Alignment = "Center"; Editable = $false }
        "completed" = @{ Header = "Done"; Width = 8; Alignment = "Right"; Editable = $false }
        "hours" = @{ Header = "Hours"; Width = 8; Alignment = "Right"; Editable = $false }
    }

    # Convert rows to PSCustomObject format and sort
    $sortedRows = $rows | Sort-Object week
    $dataObjects = @()
    foreach ($row in $sortedRows) {
        $obj = New-Object PSCustomObject
        foreach ($key in $row.Keys) {
            $obj | Add-Member -NotePropertyName $key -NotePropertyValue $row[$key]
        }
        $dataObjects += $obj
    }

    Show-PmcCustomGrid -Domain "stats" -Columns $columns -Data $dataObjects -Title 'VELOCITY (last 4 weeks)'
    Write-PmcDebug -Level 2 -Category "Analytics" -Message "Velocity completed"
}

Export-ModuleMember -Function Get-PmcStatistics, Show-PmcBurndownChart, Get-PmcVelocity