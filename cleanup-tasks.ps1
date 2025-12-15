#!/usr/bin/env pwsh
# Clean up corrupted tasks from tasks.json

Import-Module '/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1' -Force

Write-Host "Cleaning corrupted tasks..." -ForegroundColor Cyan

$pmcModule = Get-Module -Name 'Pmc.Strict'

# Get data
$data = & $pmcModule { Get-PmcData }
$before = $data.tasks.Count
Write-Host "Tasks before cleanup: $before"

# Show all tasks
Write-Host "`nCurrent tasks:"
foreach ($task in $data.tasks) {
    $text = if ($task.text) { $task.text } else { "(no text)" }
    $id = if ($task.id) { $task.id } else { "(no id)" }
    Write-Host "  [$id] $text"
}

# Remove corrupted tasks (those with very short text or missing required fields)
$cleaned = $data.tasks | Where-Object {
    $_.text -and 
    $_.text.Length -gt 2 -and 
    $_.text -ne 'B]' -and 
    $_.text -ne 'task' -and
    $_.id
}

$removed = $before - $cleaned.Count
Write-Host "`nRemoving $removed corrupted tasks..."

$data.tasks = $cleaned

# Save
& $pmcModule { param($d) Save-PmcData -Data $d -Action "Cleaned corrupted tasks" } $data

# Verify
$reloaded = & $pmcModule { Get-PmcData }
Write-Host "`nTasks after cleanup: $($reloaded.tasks.Count)"
Write-Host "`nCleaned tasks:"
foreach ($task in $reloaded.tasks) {
    Write-Host "  - $($task.text)"
}

Write-Host "`nDONE!" -ForegroundColor Green
