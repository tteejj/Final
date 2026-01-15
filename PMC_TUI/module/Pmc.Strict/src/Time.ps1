# Time.ps1 - Time tracking and timer functions

function Add-PmcTimeEntry {
    param($Context)

    try {
        $allData = Get-PmcAllData

        # Default values for new time entry
        $entry = @{
            id = Get-PmcNextTimeId $allData
            project = $allData.currentContext
            id1 = $null
            id2 = $null
            date = (Get-Date).ToString('yyyy-MM-dd')
            minutes = 0
            description = ""
            created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }

        # Parse free text for time entry details
        if ($Context.FreeText.Count -gt 0) {
            $text = ($Context.FreeText -join ' ').Trim()

            # Parse minutes from text (look for numbers followed by 'm' or 'min')
            if ($text -match '(\d+)m(?:in)?') {
                $entry.minutes = [int]$matches[1]
                $text = $text -replace '\d+m(?:in)?', ''
            }

            # Parse indirect code from #code syntax (2-5 digits)
            if ($text -match '#(\d{2,5})') {
                $entry.id1 = $matches[1]
                $entry.project = $null  # Indirect means no project
                $text = $text -replace '#\d{2,5}', ''
            }
            # Parse project from @project syntax (only if no indirect code)
            elseif ($text -match '@(\w+)') {
                $entry.project = $matches[1]
                $text = $text -replace '@\w+', ''
            }

            # Parse date - enhanced with +/- relative dates
            $dateSet = $false

            # Check for relative dates: today, tomorrow, +N, -N
            if ($text -match '\b(today)\b') {
                $entry.date = (Get-Date).ToString('yyyy-MM-dd')
                $text = $text -replace '\btoday\b', ''
                $dateSet = $true
            } elseif ($text -match '\b(tomorrow)\b') {
                $entry.date = (Get-Date).AddDays(1).ToString('yyyy-MM-dd')
                $text = $text -replace '\btomorrow\b', ''
                $dateSet = $true
            } elseif ($text -match '\+(\d+)\b') {
                $daysAhead = [int]$matches[1]
                $entry.date = (Get-Date).AddDays($daysAhead).ToString('yyyy-MM-dd')
                $text = $text -replace '\+\d+\b', ''
                $dateSet = $true
            } elseif ($text -match '\-(\d+)\b') {
                $daysAgo = [int]$matches[1]
                $entry.date = (Get-Date).AddDays(-$daysAgo).ToString('yyyy-MM-dd')
                $text = $text -replace '\-\d+\b', ''
                $dateSet = $true
            }

            # If no relative date, check for YYYYMMDD or MMDD format
            if (-not $dateSet -and $text -match '\b(?:(\d{4})(\d{2})(\d{2})|(\d{2})(\d{2}))\b') {
                if ($matches[1]) {
                    # YYYYMMDD format
                    $year = [int]$matches[1]
                    $month = [int]$matches[2]
                    $day = [int]$matches[3]
                } else {
                    # MMDD format - assume current year
                    $year = (Get-Date).Year
                    $month = [int]$matches[4]
                    $day = [int]$matches[5]
                }
                try {
                    $entry.date = (Get-Date -Year $year -Month $month -Day $day).ToString('yyyy-MM-dd')
                    $text = $text -replace '\b(?:\d{4}\d{2}\d{2}|\d{2}\d{2})\b', ''
                } catch {
                    # Invalid date, keep default
                }
            }

            # Rest is description
            $entry.description = $text.Trim()
        }

        # Add to time entries
        if (-not $allData.timelogs) { $allData.timelogs = @() }
        $allData.timelogs += $entry

        Set-PmcAllData $allData
        $target = $(if ($entry.id1) { "#$($entry.id1)" } else { "@$($entry.project)" })
        Write-PmcStyled -Style 'Success' -Text "[OK] Time entry added: $($entry.minutes)m $target - $($entry.description)"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error adding time entry: $_"
    }
}

function Get-PmcTimeReport {
    param($Context)

    try {
        $allData = Get-PmcAllData
        $timelogs = $allData.timelogs | Where-Object { $_ }

        if (-not $timelogs) {
            Write-PmcStyled -Style 'Info' -Text "No time entries found"
            return
        }

        # Determine week to display (current week default)
        $weekOffset = 0
        if ($Context.Args.ContainsKey('week')) {
            try { $weekOffset = [int]$Context.Args['week'] } catch {}
        }

        Show-PmcWeeklyTimeReport -TimeLogs $timelogs -WeekOffset $weekOffset

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error generating time report: $_"
    }
}

function Show-PmcWeeklyTimeReport {
    param([array]$TimeLogs, [int]$WeekOffset = 0)

    # Calculate week start (Monday)
    $today = Get-Date
    $daysFromMonday = ($today.DayOfWeek.value__ + 6) % 7  # Monday = 0
    $thisMonday = $today.AddDays(-$daysFromMonday).Date
    $weekStart = $thisMonday.AddDays($WeekOffset * 7)
    $weekEnd = $weekStart.AddDays(4)  # Friday

    # Week header
    $weekHeader = "Week of {0} - {1}" -f $weekStart.ToString('MMM dd'), $weekEnd.ToString('MMM dd, yyyy')

    Write-Host ""
    Write-PmcStyled -Style 'Header' -Text "TIME REPORT"
    Write-PmcStyled -Style 'Header' -Text $weekHeader
    Write-PmcStyled -Style 'Muted' -Text "Use '=' next week, '-' previous week"
    Write-Host ""

    # Filter logs for the week
    $weekLogs = @()
    for ($d = 0; $d -lt 5; $d++) {
        $dayDate = $weekStart.AddDays($d).ToString('yyyy-MM-dd')
        $dayLogs = $TimeLogs | Where-Object { $_.date -eq $dayDate }
        $weekLogs += $dayLogs
    }

    if ($weekLogs.Count -eq 0) {
        Write-PmcStyled -Style 'Warning' -Text "No time entries for this week"
        return
    }

    # Group by project/indirect code
    $grouped = @{}
    foreach ($log in $weekLogs) {
        $key = $(if ($log.id1) {
            "#$($log.id1)"
        } else {
            if ($null -ne $log.project) { $log.project } else { 'Unknown' }
        })

        if (-not $grouped.ContainsKey($key)) {
            $grouped[$key] = @{
                Name = $(if ($log.id1) { "" } else { if ($null -ne $log.project) { $log.project } else { 'Unknown' } })
                ID1 = $(if ($log.id1) { $log.id1 } else { '' })
                ID2 = $(if ($log.id1) { '' } else { '' })
                Mon = 0; Tue = 0; Wed = 0; Thu = 0; Fri = 0; Total = 0
            }
        }

        # Add minutes to appropriate day
        $logDate = [datetime]$log.date
        $dayIndex = ($logDate.DayOfWeek.value__ + 6) % 7  # Monday = 0
        $hours = [Math]::Round($log.minutes / 60.0, 1)

        switch ($dayIndex) {
            0 { $grouped[$key].Mon += $hours }
            1 { $grouped[$key].Tue += $hours }
            2 { $grouped[$key].Wed += $hours }
            3 { $grouped[$key].Thu += $hours }
            4 { $grouped[$key].Fri += $hours }
        }
        $grouped[$key].Total += $hours
    }

    # Get theme styles and build color codes
    $headerStyle = Get-PmcStyle 'Header'
    $bodyStyle = Get-PmcStyle 'Body'
    $borderStyle = Get-PmcStyle 'Border'
    $highlightStyle = Get-PmcStyle 'Highlight'
    $mutedStyle = Get-PmcStyle 'Muted'

    # Convert hex colors to VT sequences
    $headerColor = $(if ($headerStyle.Fg -match '^#') { $rgb = ConvertFrom-PmcHex $headerStyle.Fg; [PmcVT]::FgRGB($rgb.R, $rgb.G, $rgb.B) } else { "" })
    $bodyColor = $(if ($bodyStyle.Fg -match '^#') { $rgb = ConvertFrom-PmcHex $bodyStyle.Fg; [PmcVT]::FgRGB($rgb.R, $rgb.G, $rgb.B) } else { "" })
    $borderColor = $(if ($borderStyle.Fg -match '^#') { $rgb = ConvertFrom-PmcHex $borderStyle.Fg; [PmcVT]::FgRGB($rgb.R, $rgb.G, $rgb.B) } else { "" })
    $highlightColor = $(if ($highlightStyle.Fg -match '^#') { $rgb = ConvertFrom-PmcHex $highlightStyle.Fg; [PmcVT]::FgRGB($rgb.R, $rgb.G, $rgb.B) } else { "" })
    $mutedColor = $(if ($mutedStyle.Fg -match '^#') { $rgb = ConvertFrom-PmcHex $mutedStyle.Fg; [PmcVT]::FgRGB($rgb.R, $rgb.G, $rgb.B) } else { "" })
    $reset = [PmcVT]::Reset()

    # Display table
    $headerFormat = "{0,-20} {1,-5} {2,-5} {3,6} {4,6} {5,6} {6,6} {7,6} {8,8}"
    $rowFormat = "{0,-20} {1,-5} {2,-5} {3,6:F1} {4,6:F1} {5,6:F1} {6,6:F1} {7,6:F1} {8,8:F1}"

    Write-Host "$headerColor" + ($headerFormat -f "Name", "ID1", "ID2", "Mon", "Tue", "Wed", "Thu", "Fri", "Total") + "$reset"
    Write-Host "$borderColor" + ("─" * 80) + "$reset"

    $grandTotal = 0
    foreach ($entry in ($grouped.GetEnumerator() | Sort-Object Key)) {
        $data = $entry.Value
        Write-Host "$bodyColor" + ($rowFormat -f $data.Name, $data.ID1, $data.ID2, $data.Mon, $data.Tue, $data.Wed, $data.Thu, $data.Fri, $data.Total) + "$reset"
        $grandTotal += $data.Total
    }

    Write-Host "$borderColor" + ("─" * 80) + "$reset"
    Write-Host "$highlightColor" + ($headerFormat -f "", "", "", "", "", "", "", "Total:", $grandTotal.ToString('F1')) + "$reset"

    # Interactive week navigation
    Write-Host "`n$mutedColor" + "Press '=' for next week, '-' for previous week, any other key to exit" + "$reset"

    while ($true) {
        if (-not $Host.UI.RawUI.KeyAvailable) {
            Start-Sleep -Milliseconds 50
            continue
        }
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($key.Character -eq '=') {
            Show-PmcWeeklyTimeReport -TimeLogs $TimeLogs -WeekOffset ($WeekOffset + 1)
            return
        } elseif ($key.Character -eq '-') {
            Show-PmcWeeklyTimeReport -TimeLogs $TimeLogs -WeekOffset ($WeekOffset - 1)
            return
        } else {
            return
        }
    }
}

function Get-PmcTimeList {
    param($Context)

    try {
        $allData = Get-PmcAllData
        $timelogs = $allData.timelogs | Where-Object { $_ }

        if (-not $timelogs) {
            Write-PmcStyled -Style 'Info' -Text "No time entries found"
            return
        }

        # Filter recent entries (last 30 days)
        $recent = $timelogs | Where-Object {
            [datetime]$_.date -ge (Get-Date).AddDays(-30)
        } | Sort-Object date -Descending

        # Use template display
        $timeTemplate = [PmcTemplate]::new('time-list', @{
            type = 'grid'
            header = 'ID     Date       Project/Code  Hours   Description'
            row = '{id,-6} {date,-10} {target,-12} {hours,6:F1} {description}'
            settings = @{ separator = '─'; minWidth = 60 }
        })

        # Format data for display
        $displayData = @()
        foreach ($log in $recent) {
            $target = $(if ($log.id1) { "#$($log.id1)" } else { if ($null -ne $log.project) { $log.project } else { 'Unknown' } })
            $hours = [Math]::Round($log.minutes / 60.0, 1)
            $displayData += [pscustomobject]@{
                id = $log.id
                date = $log.date
                target = $target
                hours = $hours
                description = $(if ($null -ne $log.description) { $log.description } else { '' })
            }
        }

        Write-PmcStyled -Style 'Header' -Text "`nRECENT TIME ENTRIES`n"
        Render-GridTemplate -Data $displayData -Template $timeTemplate

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error listing time entries: $_"
    }
}

function Edit-PmcTimeEntry {
    param($Context)

    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Error' -Text "Usage: time edit <id>"
        return
    }

    $entryId = $Context.FreeText[0]

    try {
        $allData = Get-PmcAllData
        $entry = $allData.timelogs | Where-Object { $_.id -eq $entryId }

        if (-not $entry) {
            Write-PmcStyled -Style 'Error' -Text "Time entry '$entryId' not found"
            return
        }

        Write-PmcStyled -Style 'Info' -Text "Time entry editing not yet implemented"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error editing time entry: $_"
    }
}

function Remove-PmcTimeEntry {
    param($Context)

    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Error' -Text "Usage: time delete <id>"
        return
    }

    $entryId = $Context.FreeText[0]

    try {
        $allData = Get-PmcAllData
        $entry = $allData.timelogs | Where-Object { $_.id -eq $entryId }

        if (-not $entry) {
            Write-PmcStyled -Style 'Error' -Text "Time entry '$entryId' not found"
            return
        }

        # Remove from time logs
        $allData.timelogs = $allData.timelogs | Where-Object { $_.id -ne $entryId }

        Set-PmcAllData $allData
        Write-PmcStyled -Style 'Success' -Text "[OK] Time entry deleted"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error deleting time entry: $_"
    }
}

function Start-PmcTimer {
    param($Context)

    try {
        $project = $(if ($Context.FreeText.Count -gt 0) {
            $Context.FreeText[0]
        } else {
            $allData = Get-PmcAllData
            $allData.currentContext
        })

        Set-PmcState -Section 'Timer' -Key 'Running' -Value $true
        Set-PmcState -Section 'Timer' -Key 'Project' -Value $project
        Set-PmcState -Section 'Timer' -Key 'StartTime' -Value (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

        Write-PmcStyled -Style 'Success' -Text "Timer started for project: $project"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error starting timer: $_"
    }
}

function Stop-PmcTimer {
    param($Context)

    try {
        $running = Get-PmcState -Section 'Timer' -Key 'Running'
        if (-not $running) {
            Write-PmcStyled -Style 'Warning' -Text "No timer is currently running"
            return
        }

        $project = Get-PmcState -Section 'Timer' -Key 'Project'
        $startTime = [datetime](Get-PmcState -Section 'Timer' -Key 'StartTime')
        $endTime = Get-Date
        $minutes = [Math]::Round(($endTime - $startTime).TotalMinutes, 0)

        # Create time entry
        $allData = Get-PmcAllData
        $entry = @{
            id = Get-PmcNextTimeId $allData
            project = $project
            date = $startTime.ToString('yyyy-MM-dd')
            minutes = $minutes
            description = "Timer session"
            created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }

        if (-not $allData.timelogs) { $allData.timelogs = @() }
        $allData.timelogs += $entry
        Set-PmcAllData $allData

        # Clear timer state
        Set-PmcState -Section 'Timer' -Key 'Running' -Value $false

        Write-PmcStyled -Style 'Success' -Text "Timer stopped. Logged $minutes minutes to $project"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error stopping timer: $_"
    }
}

function Get-PmcTimerStatus {
    param($Context)

    try {
        $running = Get-PmcState -Section 'Timer' -Key 'Running'

        if (-not $running) {
        Write-PmcStyled -Style 'Info' -Text "No timer is currently running"
            return
        }

        $project = Get-PmcState -Section 'Timer' -Key 'Project'
        $startTime = [datetime](Get-PmcState -Section 'Timer' -Key 'StartTime')
        $elapsed = (Get-Date) - $startTime
        $minutes = [Math]::Round($elapsed.TotalMinutes, 0)

        Write-PmcStyled -Style 'Warning' -Text "Timer running for $project ($minutes minutes elapsed)"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error checking timer status: $_"
    }
}

function Get-PmcNextTimeId {
    param($data)

    if (-not $data.timelogs -or $data.timelogs.Count -eq 0) {
        return "T001"
    }

    $maxId = 0
    foreach ($entry in $data.timelogs) {
        if ($entry.id -match '^T(\d+)$') {
            $num = [int]$matches[1]
            if ($num -gt $maxId) { $maxId = $num }
        }
    }

    return "T{0:000}" -f ($maxId + 1)
}

Export-ModuleMember -Function Add-PmcTimeEntry, Get-PmcTimeReport, Get-PmcTimeList, Edit-PmcTimeEntry, Remove-PmcTimeEntry, Start-PmcTimer, Stop-PmcTimer, Get-PmcTimerStatus, Show-PmcWeeklyTimeReport