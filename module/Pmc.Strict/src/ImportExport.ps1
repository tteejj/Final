# Generic import/export of tasks (CSV/JSON)

function Export-PmcTasks {
    param(
        $Context,
        [string]$Path
    )

    # Handle both Context and direct -Path parameter calls
    $outCsv = $null; $outJson = $null

    if ($Path) {
        # Direct path parameter provided
        if ($Path -match '\.json$') { $outJson = $Path }
        else { $outCsv = $Path }
    } elseif ($Context) {
        # Parse tokens from context like out:foo.csv json:bar.json
        foreach ($t in $Context.FreeText) {
            if ($t -match '^(?i)out:(.+)$') { $outCsv = $matches[1] }
            elseif ($t -match '^(?i)csv:(.+)$') { $outCsv = $matches[1] }
            elseif ($t -match '^(?i)json:(.+)$') { $outJson = $matches[1] }
        }
        if (-not $outCsv -and -not $outJson) { $outCsv = 'exports/tasks.csv' }
    } else {
        $outCsv = 'exports/tasks.csv'
    }

    $data = Get-PmcDataAlias

    $tasks = @($data.tasks)
    if ($outCsv) {
        try {
            $path = Get-PmcSafePath $outCsv
            if (-not (Test-Path (Split-Path $path -Parent))) { New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null }
            $rows = @()
            foreach ($t in $tasks) {
                $rows += [pscustomobject]@{
                    ID = $t.id
                    Text = $t.text
                    Project = $(if ($t.project) { $t.project } else { 'inbox' })
                    Priority = $(if ($t.priority) { $t.priority } else { 0 })
                    Due = $(if ($t.due) { $t.due } else { '' })
                    Status = $(if ($t.status) { $t.status } else { 'pending' })
                    Created = $(if ($t.created) { $t.created } else { '' })
                }
            }
            $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
            Show-PmcSuccess ("Exported CSV: {0}" -f $path)
        } catch { Show-PmcError ("CSV export failed: {0}" -f $_) }
    }
    if ($outJson) {
        try {
            $path = Get-PmcSafePath $outJson
            if (-not (Test-Path (Split-Path $path -Parent))) { New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null }
            $tasks | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
            Show-PmcSuccess ("Exported JSON: {0}" -f $path)
        } catch { Show-PmcError ("JSON export failed: {0}" -f $_) }
    }
}

function Import-PmcTasks {
    param([PmcCommandContext]$Context)
    $pathArg = ($Context.FreeText -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($pathArg)) { Write-PmcStyled -Style 'Warning' -Text "Usage: import tasks <path.csv|path.json>"; return }
    $path = Get-PmcSafePath $pathArg
    if (-not (Test-Path $path)) { Show-PmcError ("File not found: {0}" -f $path); return }
    $data = Get-PmcDataAlias
    $added = 0
    if ($path -match '\.json$') {
        try { $items = Get-Content $path -Raw | ConvertFrom-Json } catch { Show-PmcError "Invalid JSON"; return }
        foreach ($r in $items) {
            $text = $(if ($r.PSObject.Properties['text'] -and $r.text) { $r.text } elseif ($r.PSObject.Properties['Text'] -and $r.Text) { $r.Text } else { $null })
            if (-not $text) { continue }
            $id = Get-PmcNextTaskId $data
            $projVal = $(if ($r.PSObject.Properties['project'] -and $r.project) { $r.project } elseif ($r.PSObject.Properties['Project'] -and $r.Project) { $r.Project } else { 'inbox' })
            $priVal = $(if ($r.PSObject.Properties['priority'] -and $r.priority) { $r.priority } elseif ($r.PSObject.Properties['Priority'] -and $r.Priority) { $r.Priority } else { 0 })
            $t = @{ id=$id; text=$text; project=$projVal; priority=$priVal; status='pending'; created=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
            if (($r.PSObject.Properties['due'] -and $r.due) -or ($r.PSObject.Properties['Due'] -and $r.Due)) { try { $t.due = ([datetime]($(if ($r.due) { $r.due } else { $r.Due }))).ToString('yyyy-MM-dd') } catch {
                # Date parsing failed - skip due date assignment
            } }
            $data.tasks += $t; $added++
        }
        Save-StrictData $data 'import tasks'
        Show-PmcSuccess ("Imported {0} task(s) from JSON" -f $added)
        return
    }
    if ($path -match '\.csv$') {
        $rows = @(); try { $rows = Import-Csv -Path $path } catch { Show-PmcError ("Failed to read CSV: {0}" -f $_); return }
        foreach ($r in $rows) {
            $text = $(if ($r.PSObject.Properties['Text'] -and $r.Text) { $r.Text } elseif ($r.PSObject.Properties['Task'] -and $r.Task) { $r.Task } else { $null })
            if (-not $text) { continue }
            $proj = $(if ($r.PSObject.Properties['Project'] -and $r.Project) { $r.Project } else { 'inbox' })
            $pri = try { [int]$r.Priority } catch { 0 }
            $due = $null; try { if ($r.Due) { $due = [datetime]$r.Due } } catch {
                # Date parsing failed - due will remain null
            }
            $id = Get-PmcNextTaskId $data
            $task = @{ id=$id; text=$text; project=$proj; priority=$pri; status='pending'; created=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
            if ($due) { $task.due = $due.ToString('yyyy-MM-dd') }
            $data.tasks += $task; $added++
        }
        Save-StrictData $data 'import tasks'
        Show-PmcSuccess ("Imported {0} task(s) from CSV" -f $added)
        return
    }
    Show-PmcWarning 'Unsupported file type (use .csv or .json)'
}

Export-ModuleMember -Function Export-PmcTasks, Import-PmcTasks