#!/usr/bin/env pwsh
# Simple test: Can we save a task?

Set-StrictMode -Version Latest

Write-Host "=== SIMPLE SAVE TEST ===" -ForegroundColor Cyan

try {
    # Load module
    Import-Module '/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1' -Force -ErrorAction Stop
    Write-Host "✓ Module loaded" -ForegroundColor Green
    
    # Get current data
    $data = Get-PmcData
    $beforeCount = $data.tasks.Count
    Write-Host "✓ Current tasks: $beforeCount" -ForegroundColor Green
    
    # Add a test task
    $testTask = @{
        id = [Guid]::NewGuid().ToString()
        text = "SIMPLE TEST $(Get-Date -Format 'HH:mm:ss')"
        priority = 3
        status = 'todo'
        completed = $false
        created = Get-Date
    }
    
    $data.tasks += $testTask
    Write-Host "✓ Added test task" -ForegroundColor Green
    
    # Save
    Write-Host "Saving..." -ForegroundColor Yellow
    Save-PmcData -Data $data
    Write-Host "✓ Save completed without error" -ForegroundColor Green
    
    # Reload and verify
    $reloaded = Get-PmcData
    $afterCount = $reloaded.tasks.Count
    Write-Host "✓ Reloaded data, tasks: $afterCount" -ForegroundColor Green
    
    if ($afterCount -gt $beforeCount) {
        Write-Host ""
        Write-Host "SUCCESS! Task was saved." -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "FAIL! Task count didn't increase." -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
    exit 1
}
