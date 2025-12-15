#!/usr/bin/env pwsh
# Deep debugging script for TaskListScreen and save functionality

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== DEEP DEBUGGING: TaskListScreen & Save Functionality ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check if Test-PmcResourceLimits works
Write-Host "[Test 1] Debugging Test-PmcResourceLimits..." -ForegroundColor Yellow
try {
    Import-Module '/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1' -Force
    
    # Try calling the function
    Write-Host "  Calling Test-PmcResourceLimits..." -ForegroundColor Gray
    $result = Test-PmcResourceLimits
    Write-Host "  Result: $result" -ForegroundColor $(if ($result) { 'Green' } else { 'Red' })
    
    # Check security state
    Write-Host "  Checking security state..." -ForegroundColor Gray
    $secState = Get-PmcSecurityState
    Write-Host "    ResourceLimitsEnabled: $($secState.ResourceLimitsEnabled)" -ForegroundColor Gray
    Write-Host "    MaxMemoryUsage: $($secState.MaxMemoryUsage)" -ForegroundColor Gray
    
    # Check current memory
    $process = Get-Process -Id $PID
    $memUsage = $process.WorkingSet64
    Write-Host "    Current Memory: $memUsage bytes ($([Math]::Round($memUsage/1MB, 2)) MB)" -ForegroundColor Gray
    Write-Host "    Limit: $($secState.MaxMemoryUsage) bytes ($([Math]::Round($secState.MaxMemoryUsage/1MB, 2)) MB)" -ForegroundColor Gray
    
    if ($memUsage -gt $secState.MaxMemoryUsage) {
        Write-Host "  ✗ MEMORY LIMIT EXCEEDED - This is why saves fail!" -ForegroundColor Red
    } else {
        Write-Host "  ✓ Memory within limits" -ForegroundColor Green
    }
} catch {
    Write-Host "  ✗ ERROR: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

# Test 2: Test Save-PmcData directly
Write-Host ""
Write-Host "[Test 2] Testing Save-PmcData directly..." -ForegroundColor Yellow
try {
    $data = Get-PmcData
    Write-Host "  Current tasks: $($data.tasks.Count)" -ForegroundColor Gray
    
    # Add a test task
    $testTask = @{
        id = [Guid]::NewGuid().ToString()
        text = "DEBUG TEST TASK $(Get-Date -Format 'HH:mm:ss')"
        priority = 3
        status = 'todo'
        completed = $false
        created = Get-Date
    }
    
    $data.tasks += $testTask
    Write-Host "  Added test task: $($testTask.text)" -ForegroundColor Gray
    
    # Try to save
    Write-Host "  Calling Save-PmcData..." -ForegroundColor Gray
    Save-PmcData -Data $data -Action "DEBUG: Test save"
    Write-Host "  ✓ Save succeeded!" -ForegroundColor Green
    
    # Verify it was saved
    $reloaded = Get-PmcData
    $found = $reloaded.tasks | Where-Object { $_.id -eq $testTask.id }
    if ($found) {
        Write-Host "  ✓ Task found in reloaded data!" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Task NOT found in reloaded data!" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ Save FAILED: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

# Test 3: Test TaskStore.AddTask
Write-Host ""
Write-Host "[Test 3] Testing TaskStore.AddTask..." -ForegroundColor Yellow
try {
    # Get TaskStore instance
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/services/TaskStore.ps1'
    $store = [TaskStore]::GetInstance()
    
    Write-Host "  TaskStore loaded, current tasks: $($store.GetAllTasks().Count)" -ForegroundColor Gray
    Write-Host "  AutoSave enabled: $($store.AutoSave)" -ForegroundColor Gray
    
    # Add a task via TaskStore
    $taskData = @{
        text = "TASKSTORE TEST $(Get-Date -Format 'HH:mm:ss')"
        priority = 2
        status = 'todo'
        project = 'test'
    }
    
    Write-Host "  Calling TaskStore.AddTask..." -ForegroundColor Gray
    $success = $store.AddTask($taskData)
    
    if ($success) {
        Write-Host "  ✓ AddTask returned true!" -ForegroundColor Green
        
        # Verify in store
        $allTasks = $store.GetAllTasks()
        Write-Host "  Total tasks after add: $($allTasks.Count)" -ForegroundColor Gray
        
        # Verify on disk
        $diskData = Get-PmcData
        $foundOnDisk = $diskData.tasks | Where-Object { $_.text -like "TASKSTORE TEST*" }
        if ($foundOnDisk) {
            Write-Host "  ✓ Task found on disk!" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Task NOT found on disk!" -ForegroundColor Red
        }
    } else {
        Write-Host "  ✗ AddTask returned false!" -ForegroundColor Red
        Write-Host "  LastError: $($store.LastError)" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ ERROR: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

# Test 4: Test TaskListScreen.OnItemCreated
Write-Host ""
Write-Host "[Test 4] Testing TaskListScreen.OnItemCreated..." -ForegroundColor Yellow
try {
    # This requires loading the full TUI stack
    Write-Host "  Loading TUI dependencies..." -ForegroundColor Gray
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/DepsLoader.ps1'
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/SpeedTUILoader.ps1'
    
    # Create a mock container
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/helpers/ServiceContainer.ps1'
    $container = [ServiceContainer]::new()
    
    # Register TaskStore
    $store = [TaskStore]::GetInstance()
    $container.Register('TaskStore', $store)
    
    # Create TaskListScreen
    . '/home/teej/ztest/module/Pmc.Strict/consoleui/screens/TaskListScreen.ps1'
    $screen = [TaskListScreen]::new($container)
    
    Write-Host "  TaskListScreen created" -ForegroundColor Gray
    
    # Call OnItemCreated
    $values = @{
        text = "SCREEN TEST $(Get-Date -Format 'HH:mm:ss')"
        priority = 1
        project = 'test'
    }
    
    Write-Host "  Calling OnItemCreated..." -ForegroundColor Gray
    $screen.OnItemCreated($values)
    
    # Check if it was saved
    $diskData = Get-PmcData
    $foundOnDisk = $diskData.tasks | Where-Object { $_.text -like "SCREEN TEST*" }
    if ($foundOnDisk) {
        Write-Host "  ✓ Task created via screen found on disk!" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Task created via screen NOT found on disk!" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ ERROR: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== DEBUGGING COMPLETE ===" -ForegroundColor Cyan
