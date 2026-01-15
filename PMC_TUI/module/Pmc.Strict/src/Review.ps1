# Weekly Review workflow

function Start-PmcReview {
    param([PmcCommandContext]$Context)
    Write-Host ([PraxisVT]::ClearScreen())
    Show-PmcHeader -Title 'WEEKLY REVIEW' -Icon '🗓'
    Show-PmcTip 'Walk through overdue, today/tomorrow, upcoming, blocked, and projects.'

    $sections = @(
        @{ title='Overdue';        action={ param($ctx) Show-PmcOverdueTasks -Context $ctx } },
        @{ title='Today & Tomorrow'; action={ param($ctx) Show-PmcTodayTasks -Context $ctx; Show-PmcTomorrowTasks -Context $ctx } },
        @{ title='Upcoming (7d)'; action={ param($ctx) Show-PmcUpcomingTasks -Context $ctx } },
        @{ title='Blocked';       action={ param($ctx) Show-PmcBlockedTasks -Context $ctx } },
        @{ title='Next Actions';  action={ param($ctx) Show-PmcNextTasks -Context $ctx } },
        @{ title='Projects';      action={ param($ctx) Show-PmcProjectsView -Context $ctx } }
    )

    foreach ($s in $sections) {
        Show-PmcSeparator -Width 60
        Show-PmcNotice ("Section: {0}" -f $s.title)
        & $s.action $Context
        $resp = Read-Host "Press Enter to continue, or 'q' to quit review"
        if ($resp -match '^(?i)q$') { break }
    }

    Show-PmcSeparator -Width 60
    Show-PmcSuccess 'Review complete.'
}

#Export-ModuleMember -Function Start-PmcReview