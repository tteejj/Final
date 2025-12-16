# Dependencies System Implementation
# Based on t2.ps1 dependencies functionality

function Update-PmcBlockedStatus {
    param($data = (Get-PmcDataAlias))

    Write-PmcDebug -Level 3 -Category "Dependencies" -Message "Updating blocked status for all tasks"

    # Clear all blocked status first
    foreach ($task in @($data.tasks)) {
        if ($null -eq $task) { continue }
        if (Pmc-HasProp $task 'blocked') { $task.PSObject.Properties.Remove('blocked') }
    }

    # Set blocked status for tasks with pending dependencies
    foreach ($task in @($data.tasks) | Where-Object {
        $null -ne $_ -and
        (Pmc-HasProp $_ 'depends') -and
        $_.depends -and
        $_.depends.Count -gt 0
    }) {
        $blockers = $data.tasks | Where-Object {
            Pmc-HasProp $_ 'id' -and ($_.id -in $task.depends) -and (Pmc-HasProp $_ 'status') -and $_.status -eq 'pending'
        }
        $isBlocked = ($blockers.Count -gt 0)

        if ($isBlocked) {
            if (Pmc-HasProp $task 'blocked') { $task.blocked = $true } else { Add-Member -InputObject $task -MemberType NoteProperty -Name blocked -Value $true }
        }
    }

    Write-PmcDebug -Level 3 -Category "Dependencies" -Message "Blocked status update completed"
}

function Add-PmcDependency {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Dependencies" -Message "Starting dep add" -Data @{ FreeText = $Context.FreeText }

    $data = Get-PmcDataAlias
    $ids = $Context.FreeText

    if ($ids.Count -lt 2) {
        Write-PmcStyled -Style 'Warning' -Text "Usage: dep add <task> <depends-on>"
        return
    }

    $taskId = $null
    $dependsOnId = $null

    # Resolve task IDs
    if ($ids[0] -match '^\d+$') { $taskId = [int]$ids[0] }
    if ($ids[1] -match '^\d+$') { $dependsOnId = [int]$ids[1] }

    if (-not $taskId -or -not $dependsOnId) {
        Write-PmcStyled -Style 'Error' -Text "Invalid task IDs"
        return
    }

    $task = $data.tasks | Where-Object { $_.id -eq $taskId } | Select-Object -First 1
    $dependsOnTask = $data.tasks | Where-Object { $_.id -eq $dependsOnId } | Select-Object -First 1

    if (-not $task) {
        Write-PmcStyled -Style 'Error' -Text "Task #$taskId not found"
        return
    }

    if (-not $dependsOnTask) {
        Write-PmcStyled -Style 'Error' -Text "Task #$dependsOnId not found"
        return
    }

    # Initialize depends array if needed
    if (-not (Pmc-HasProp $task 'depends')) { $task | Add-Member -NotePropertyName depends -NotePropertyValue @() -Force }

    # Check if dependency already exists
    if ($task.depends -contains $dependsOnId) {
        Write-PmcStyled -Style 'Warning' -Text "Dependency already exists"
        return
    }

    # Add dependency
    $task.depends = @($task.depends + $dependsOnId)

    # Update blocked status for all tasks
    Update-PmcBlockedStatus -data $data

    Save-StrictData $data 'dep add'
    Write-PmcStyled -Style 'Success' -Text "Added dependency: Task #$taskId depends on Task #$dependsOnId"

    Write-PmcDebug -Level 2 -Category "Dependencies" -Message "Dependency added successfully" -Data @{ TaskId = $taskId; DependsOn = $dependsOnId }
}

function Remove-PmcDependency {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Dependencies" -Message "Starting dep remove" -Data @{ FreeText = $Context.FreeText }

    $data = Get-PmcDataAlias
    $ids = $Context.FreeText

    if ($ids.Count -lt 2) {
        Write-PmcStyled -Style 'Warning' -Text "Usage: dep remove <task> <depends-on>"
        return
    }

    $taskId = $null
    $dependsOnId = $null

    # Resolve task IDs
    if ($ids[0] -match '^\d+$') { $taskId = [int]$ids[0] }
    if ($ids[1] -match '^\d+$') { $dependsOnId = [int]$ids[1] }

    if (-not $taskId -or -not $dependsOnId) {
        Write-PmcStyled -Style 'Error' -Text "Invalid task IDs"
        return
    }

    $task = $data.tasks | Where-Object { $_.id -eq $taskId } | Select-Object -First 1

    if (-not $task -or -not (Pmc-HasProp $task 'depends') -or -not $task.depends) {
        Write-PmcStyled -Style 'Warning' -Text "No such dependency found"
        return
    }

    # Remove dependency
    $task.depends = @($task.depends | Where-Object { $_ -ne $dependsOnId })

    # Clean up empty depends array
    if ($task.depends.Count -eq 0) { try { $task.PSObject.Properties.Remove('depends') } catch {} }

    # Update blocked status for all tasks
    Update-PmcBlockedStatus -data $data

    Save-StrictData $data 'dep remove'
    Write-Host "Removed dependency: Task #$taskId no longer depends on Task #$dependsOnId" -ForegroundColor Green

    Write-PmcDebug -Level 2 -Category "Dependencies" -Message "Dependency removed successfully" -Data @{ TaskId = $taskId; DependsOn = $dependsOnId }
}

function Show-PmcDependencies {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Dependencies" -Message "Starting dep show" -Data @{ FreeText = $Context.FreeText }

    $data = Get-PmcDataAlias
    $text = ($Context.FreeText -join ' ').Trim()

    if (-not $text) {
        Write-Host "Usage: dep show <task>" -ForegroundColor Yellow
        return
    }

    $taskId = $null
    if ($text -match '^\d+$') { $taskId = [int]$text }

    if (-not $taskId) {
        Write-Host "Invalid task ID" -ForegroundColor Red
        return
    }

    $task = $data.tasks | Where-Object { $_.id -eq $taskId } | Select-Object -First 1

    if (-not $task) {
        Write-PmcStyled -Style 'Error' -Text "Task #$taskId not found"
        return
    }

    Write-Host "`nDEPENDENCIES for Task #$taskId" -ForegroundColor Cyan
    Write-Host ("Task: {0}" -f $task.text) -ForegroundColor White
    Write-PmcStyled -Style 'Border' -Text "─────────────────────────────────"

    $depends = $(if ((Pmc-HasProp $task 'depends') -and $task.depends) { $task.depends } else { @() })

    if ($depends.Count -eq 0) {
        Write-Host "  No dependencies" -ForegroundColor Gray
        return
    }

    $rows = @()
    foreach ($depId in $depends) {
        $depTask = $data.tasks | Where-Object { $_.id -eq $depId } | Select-Object -First 1
        $status = $(if ($depTask) { $depTask.status } else { 'missing' })
        $text = $(if ($depTask) { $depTask.text } else { '(missing task)' })
        $rows += @{ id = "#$depId"; status = $status; text = $text }
    }

    # Convert to universal display format
    $columns = @{
        "id" = @{ Header = "ID"; Width = 6; Alignment = "Left"; Editable = $false }
        "status" = @{ Header = "Status"; Width = 10; Alignment = "Center"; Editable = $false }
        "text" = @{ Header = "Task"; Width = 50; Alignment = "Left"; Editable = $false }
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

    # Use template display
    $depTemplate = [PmcTemplate]::new('dependencies', @{
        type = 'grid'
        header = 'Task ID   Title                          Type        Status'
        row = '{id,-9} {title,-30} {type,-10} {status}'
    })
    Write-PmcStyled -Style 'Header' -Text "Dependencies for Task #$taskId"
    Render-GridTemplate -Data $dataObjects -Template $depTemplate

    # Show if this task is blocked
    if ($task.blocked) {
        Write-Host "`n[WARN]️  This task is BLOCKED by pending dependencies" -ForegroundColor Red
    } else {
        Write-Host "`n✅ This task is ready to work on" -ForegroundColor Green
    }

    Write-PmcDebug -Level 2 -Category "Dependencies" -Message "Dependencies shown successfully" -Data @{ TaskId = $taskId; DependencyCount = $depends.Count }
}

function Show-PmcDependencyGraph {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Dependencies" -Message "Starting dep graph"

    $data = Get-PmcDataAlias
    $rows = @()

    foreach ($task in $data.tasks) {
        if ((Pmc-HasProp $task 'depends') -and @($task.depends).Count -gt 0) {
            $dependsText = ($task.depends -join ', ')
            $status = $(if ($task.blocked) { "🔒 BLOCKED" } else { "✅ Ready" })
            $rows += @{
                task = "#$($task.id)"
                depends = $dependsText
                status = $status
                text = $task.text
            }
        }
    }

    if (@($rows).Count -eq 0) {
        Write-Host "`nDEPENDENCY GRAPH" -ForegroundColor Cyan
        Write-Host "No task dependencies found" -ForegroundColor Gray
        return
    }

    # Convert to universal display format
    $columns = @{
        "task" = @{ Header = "Task"; Width = 8; Alignment = "Left"; Editable = $false }
        "depends" = @{ Header = "Depends On"; Width = 15; Alignment = "Left"; Editable = $false }
        "status" = @{ Header = "Status"; Width = 12; Alignment = "Center"; Editable = $false }
        "text" = @{ Header = "Description"; Width = 40; Alignment = "Left"; Editable = $false }
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

    # Use template display
    $depTemplate = [PmcTemplate]::new('dep-graph', @{
        type = 'grid'
        header = 'Task ID   Title                          Type        Status'
        row = '{id,-9} {title,-30} {type,-10} {status}'
    })
    Write-PmcStyled -Style 'Header' -Text 'DEPENDENCY GRAPH'
    Render-GridTemplate -Data $dataObjects -Template $depTemplate

    # Summary statistics
    $blockedCount = @($data.tasks | Where-Object { $_.blocked }).Count
    $dependentCount = @($data.tasks | Where-Object { (Pmc-HasProp $_ 'depends') -and $_.depends }).Count

    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Tasks with dependencies: $dependentCount" -ForegroundColor White
    Write-Host "  Currently blocked tasks: $blockedCount" -ForegroundColor $(if ($blockedCount -gt 0) { 'Red' } else { 'Green' })

    Write-PmcDebug -Level 2 -Category "Dependencies" -Message "Dependency graph shown successfully" -Data @{ DependentTasks = $dependentCount; BlockedTasks = $blockedCount }
}

Export-ModuleMember -Function Update-PmcBlockedStatus, Add-PmcDependency, Remove-PmcDependency, Show-PmcDependencies, Show-PmcDependencyGraph