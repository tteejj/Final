# Undo/Redo System Implementation
# Based on t2.ps1 undo/redo functionality

# Global variables for undo/redo stacks
$Script:PmcUndoStack = @()
$Script:PmcRedoStack = @()
$Script:PmcMaxUndoSteps = 5

function Invoke-PmcUndo {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "System" -Message "Starting undo operation"
    $file = Get-PmcTaskFilePath
    $stacks = Get-PmcUndoRedoStacks $file
    $undo = @($stacks.undo); $redo = @($stacks.redo)
    if (@($undo).Count -eq 0) { Write-PmcStyled -Style 'Muted' -Text 'Nothing to undo'; return }
    try {
        $current = Get-PmcData
        $redo += ($current | ConvertTo-Json -Depth 10)
    } catch {
        # Undo state push failed - undo history may be incomplete
    }
    $snap = $undo[-1]; if (@($undo).Count -gt 1) { $undo = $undo[0..($undo.Count-2)] } else { $undo=@() }
    try {
        $state = $snap | ConvertFrom-Json
        $tmp = "$file.tmp"; $state | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding UTF8; Move-Item -Force -Path $tmp -Destination $file
        Save-PmcUndoRedoStacks -Undo $undo -Redo $redo -UndoFile $stacks.undoFile -RedoFile $stacks.redoFile
        Write-PmcStyled -Style 'Success' -Text 'Undid last action'
        Write-PmcDebug -Level 2 -Category 'System' -Message 'Undo completed' -Data @{ UndoCount=@($undo).Count; RedoCount=@($redo).Count }
    } catch {
        Write-PmcStyled -Style 'Error' -Text ("Undo failed: {0}" -f $_)
    }
}

function Invoke-PmcRedo {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "System" -Message "Starting redo operation"
    $file = Get-PmcTaskFilePath
    $stacks = Get-PmcUndoRedoStacks $file
    $undo = @($stacks.undo); $redo = @($stacks.redo)
    if (@($redo).Count -eq 0) { Write-PmcStyled -Style 'Muted' -Text 'Nothing to redo'; return }
    $snap = $redo[-1]; if (@($redo).Count -gt 1) { $redo = $redo[0..($redo.Count-2)] } else { $redo=@() }
    try {
        $current = Get-PmcData
        $undo += ($current | ConvertTo-Json -Depth 10)
    } catch {
        # Undo state push failed - undo history may be incomplete
    }
    try {
        $state = $snap | ConvertFrom-Json
        $tmp = "$file.tmp"; $state | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding UTF8; Move-Item -Force -Path $tmp -Destination $file
        Save-PmcUndoRedoStacks -Undo $undo -Redo $redo -UndoFile $stacks.undoFile -RedoFile $stacks.redoFile
        Write-PmcStyled -Style 'Success' -Text 'Redid last action'
        Write-PmcDebug -Level 2 -Category 'System' -Message 'Redo completed' -Data @{ UndoCount=@($undo).Count; RedoCount=@($redo).Count }
    } catch {
        Write-PmcStyled -Style 'Error' -Text ("Redo failed: {0}" -f $_)
    }
}

function New-PmcBackup {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "System" -Message "Starting manual backup"

    try {
        $data = Get-PmcDataAlias
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

        # Create backups directory if it doesn't exist
        $backupDir = "backups"
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }

        $backupFile = Join-Path $backupDir "pmc_backup_$timestamp.json"

        # Export data to backup file
        $data | ConvertTo-Json -Depth 10 | Set-Content -Path $backupFile -Encoding UTF8

        Write-PmcStyled -Style 'Success' -Text ("Backup created: {0}" -f $backupFile)

        # Clean up old backups (keep last 2)
        $backupFiles = Get-ChildItem -Path $backupDir -Filter "pmc_backup_*.json" | Sort-Object LastWriteTime -Descending
        if ($backupFiles.Count -gt 2) {
            $oldBackups = $backupFiles | Select-Object -Skip 2
            foreach ($oldBackup in $oldBackups) {
                Remove-Item $oldBackup.FullName -Force
                Write-PmcStyled -Style 'Muted' -Text ("Removed old backup: {0}" -f $oldBackup.Name)
            }
        }

        Write-PmcDebug -Level 2 -Category "System" -Message "Manual backup completed successfully" -Data @{ BackupFile = $backupFile }
    } catch {
        Write-PmcStyled -Style 'Error' -Text ("Backup failed: {0}" -f $_)
        Write-PmcDebug -Level 1 -Category "System" -Message "Manual backup failed" -Data @{ Error = $_.Exception.Message }
    }
}

function Clear-PmcBackups {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "System" -Message "Starting system clean"

    $data = Get-PmcDataAlias
    $completedTasks = @($data.tasks | Where-Object { $_.status -eq 'completed' })

    if ($completedTasks.Count -eq 0) {
        Write-PmcStyled -Style 'Muted' -Text "No completed tasks to clean"
        return
    }

    Write-PmcStyled -Style 'Warning' -Text ("Found {0} completed tasks" -f $completedTasks.Count)

    # Show sample of what will be cleaned
    $sample = $completedTasks | Select-Object -First 5
    foreach ($task in $sample) {
        $completedDate = $(if ($task.completed) { $task.completed } else { 'unknown' })
        Write-PmcStyled -Style 'Muted' -Text ("  #$($task.id) - $($task.text) (completed: $completedDate)")
    }

    if ($completedTasks.Count -gt 5) {
        Write-PmcStyled -Style 'Muted' -Text ("  ... and {0} more" -f ($completedTasks.Count - 5))
    }

    # Ask for confirmation
    $response = Read-Host "`nProceed with cleaning? This will permanently remove completed tasks. (y/N)"

    if ($response -match '^[Yy]') {
        # Record current state for undo
        Record-PmcUndoState $data 'system clean'

        # Remove completed tasks
        $data.tasks = @($data.tasks | Where-Object { $_.status -ne 'completed' })

        # Save cleaned data
        Save-StrictData $data 'system clean'

        Write-PmcStyled -Style 'Success' -Text ("Cleaned {0} completed tasks" -f $completedTasks.Count)

        Write-PmcDebug -Level 2 -Category "System" -Message "System clean completed successfully" -Data @{ RemovedTasks = $completedTasks.Count }
    } else {
        Write-PmcStyled -Style 'Muted' -Text "Clean operation cancelled"
    }
}

# Initialize undo system - integrate with existing Add-PmcUndoEntry mechanism
function Initialize-PmcUndoSystem {
    $taskFile = Get-PmcTaskFilePath
    $undoFile = $taskFile + '.undo'

    if (-not $Script:PmcUndoStack -or $Script:PmcUndoStack.Count -eq 0) {
        if (Test-Path $undoFile) {
            try {
                $undoStack = Get-Content $undoFile -Raw | ConvertFrom-Json
                $Script:PmcUndoStack = @($undoStack)

                Write-PmcDebug -Level 3 -Category "System" -Message "Undo system initialized from existing file" -Data @{
                    UndoSteps = $Script:PmcUndoStack.Count
                    RedoSteps = $Script:PmcRedoStack.Count
                }
            } catch {
                $Script:PmcUndoStack = @()
                $Script:PmcRedoStack = @()
                Write-PmcDebug -Level 1 -Category "System" -Message "Failed to load undo data" -Data @{ Error = $_.Exception.Message }
            }
        } else {
            $Script:PmcUndoStack = @()
            $Script:PmcRedoStack = @()
        }
    }
}

# Record state for undo
function Record-PmcUndoState {
    param($data, [string]$action)

    if (-not $data) { return }

    # Add current state to undo stack
    $Script:PmcUndoStack += ($data | ConvertTo-Json -Depth 10)

    # Limit undo stack size
    if ($Script:PmcUndoStack.Count -gt $Script:PmcMaxUndoSteps) {
        $Script:PmcUndoStack = $Script:PmcUndoStack[1..($Script:PmcUndoStack.Count-1)]
    }

    # Clear redo stack when new action is performed
    $Script:PmcRedoStack = @()

    # Save undo stack
    Save-PmcUndoStack

    Write-PmcDebug -Level 3 -Category "System" -Message "Undo state recorded" -Data @{
        Action = $action
        UndoStackSize = $Script:PmcUndoStack.Count
    }
}

# Save undo stack to disk
function Save-PmcUndoStack {
    $undoFile = "pmc_undo.json"

    try {
        $undoData = @{
            undoStack = $Script:PmcUndoStack
            redoStack = $Script:PmcRedoStack
            lastUpdated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }

        $undoData | ConvertTo-Json -Depth 10 | Set-Content -Path $undoFile -Encoding UTF8

        Write-PmcDebug -Level 3 -Category "System" -Message "Undo stack saved to disk"
    } catch {
        Write-PmcDebug -Level 1 -Category "System" -Message "Failed to save undo stack" -Data @{ Error = $_.Exception.Message }
    }
}

# Save data directly without recording undo state
function Save-PmcDataDirect {
    param($data)

    $dataFile = "pmc_data.json"
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $dataFile -Encoding UTF8

    # Update in-memory cache if it exists
    if (Get-Variable -Name 'Script:PmcDataCache' -Scope Script -ErrorAction SilentlyContinue) {
        $Script:PmcDataCache = $data
    }
}

# Get undo/redo status
function Get-PmcUndoStatus {
    Initialize-PmcUndoSystem

    return @{
        UndoSteps = $Script:PmcUndoStack.Count
        RedoSteps = $Script:PmcRedoStack.Count
        MaxSteps = $Script:PmcMaxUndoSteps
    }
}

Export-ModuleMember -Function Invoke-PmcUndo, Invoke-PmcRedo, New-PmcBackup, Clear-PmcBackups, Initialize-PmcUndoSystem, Record-PmcUndoState, Save-PmcUndoStack, Save-PmcDataDirect, Get-PmcUndoStatus