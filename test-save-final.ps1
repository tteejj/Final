#!/usr/bin/env pwsh
# Test that save actually works now

Import-Module '/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1' -Force

Write-Host "Testing save functionality..." -ForegroundColor Cyan

# Use module scope to call functions
$pmcModule = Get-Module -Name 'Pmc.Strict'

# Get data
$data = & $pmcModule { Get-PmcData }
$before = $data.tasks.Count
Write-Host "Tasks before: $before"

# Add test task
$testTask = @{
    id = [Guid]::NewGuid().ToString()
    text = "FINAL TEST $(Get-Date -Format 'HH:mm:ss')"
    priority = 3
    status = 'todo'
    completed = $false
    created = Get-Date
}

$data.tasks += $testTask

# Save
Write-Host "Saving..."
& $pmcModule { param($d) Save-PmcData -Data $d } $data

# Reload
$reloaded = & $pmcModule { Get-PmcData }
$after = $reloaded.tasks.Count
Write-Host "Tasks after: $after"

if ($after -gt $before) {
    Write-Host "SUCCESS! Save works!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "FAILED! Save didn't work!" -ForegroundColor Red
    exit 1
}
