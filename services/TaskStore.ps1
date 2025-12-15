# TaskStore.ps1 - Centralized Observable Data Store for PMC TUI
#
# SINGLETON pattern - provides centralized data access with:
# - Load data once from Get-PmcAllData
# - In-memory caching (tasks, projects, time logs)
# - CRUD operations (Add, Update, Delete, Get)
# - Event-driven updates (OnTaskAdded, OnTaskUpdated, OnTaskDeleted, etc.)
# - Auto-persistence via Set-PmcAllData
# - Thread-safe operations
# - Validation and error handling
# - Rollback on save failure
#
# Usage:
#   $store = [TaskStore]::GetInstance()
#
#   # CRUD operations
#   $task = $store.GetTask($id)
#   $allTasks = $store.GetAllTasks()
#   $store.AddTask($task)        # Fires OnTaskAdded, persists
#   $store.UpdateTask($id, $changes)  # Fires OnTaskUpdated, persists
#   $store.DeleteTask($id)       # Fires OnTaskDeleted, persists
#
#   # Subscribe to changes
#   $store.OnTaskAdded = { param($task) $this.RefreshUI() }
#   $store.OnTaskUpdated = { param($task) $this.RefreshUI() }
#   $store.OnTaskDeleted = { param($id) $this.RefreshUI() }
#
# The store automatically persists changes to disk and provides
# rollback capabilities if persistence fails.

using namespace System
using namespace System.Collections.Generic
using namespace System.Threading

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Centralized observable data store for PMC data with event-driven updates

.DESCRIPTION
TaskStore provides:
- Singleton instance for centralized data access
- In-memory caching of tasks, projects, time logs
- CRUD operations with automatic persistence
- Event callbacks for data changes (OnTaskAdded, OnTaskUpdated, etc.)
- Validation before persistence
- Rollback on save failure
- Thread-safe operations with locking
- Query methods (filtering, searching)
- Batch operations for performance

.EXAMPLE
$store = [TaskStore]::GetInstance()
$store.OnTaskAdded = { param($task) Write-Host "New task: $($task.text)" }
$store.AddTask(@{ text='Buy milk'; project='personal'; priority=3 })
#>
class TaskStore {
    # === Singleton Instance ===
    static hidden [TaskStore]$_instance = $null
    static hidden [object]$_instanceLock = [object]::new()

    # === Data Storage ===
    hidden [hashtable]$_data = @{
        tasks    = @()
        projects = @()
        timelogs = @()
        settings = @{}
        metadata = @{
            lastLoaded = $null
            lastSaved  = $null
            version    = "1.0"
        }
    }

    # === Backup for Rollback ===
    hidden [hashtable]$_dataBackup = $null

    # === Thread Safety ===
    hidden [object]$_dataLock = [object]::new()

    # === Event Callbacks - Tasks ===
    [scriptblock]$OnTaskAdded = {}
    [scriptblock]$OnTaskUpdated = {}
    [scriptblock]$OnTaskDeleted = {}
    [scriptblock]$OnTasksChanged = {}  # Fired after any task change

    # === Event Callbacks - Projects ===
    [scriptblock]$OnProjectAdded = {}
    [scriptblock]$OnProjectUpdated = {}
    [scriptblock]$OnProjectDeleted = {}
    [scriptblock]$OnProjectsChanged = {}

    # === Event Callbacks - Time Logs ===
    [scriptblock]$OnTimeLogAdded = {}
    [scriptblock]$OnTimeLogUpdated = {}
    [scriptblock]$OnTimeLogDeleted = {}
    [scriptblock]$OnTimeLogsChanged = {}

    # === Event Callbacks - Global ===
    [scriptblock]$OnDataChanged = {}   # Fired after any data change
    [scriptblock]$OnLoadError = {}     # Fired when load fails
    [scriptblock]$OnSaveError = {}     # Fired when save fails

    # === State Flags ===
    [bool]$IsLoaded = $false
    [bool]$IsSaving = $false
    [string]$LastError = ""
    [bool]$AutoSave = $true  # CRITICAL: Enable by default to prevent data loss
    [bool]$HasPendingChanges = $false  # True when changes need to be saved

    # === Cached Statistics ===
    hidden [hashtable]$_cachedStats = $null
    hidden [bool]$_statsNeedUpdate = $true

    # === Validation Rules ===
    hidden [hashtable]$_validationRules = @{
        task    = @{
            required = @('text')
            types    = @{
                id        = 'string'
                text      = 'string'
                details   = 'string'
                project   = 'string'
                priority  = 'int'
                status    = 'string'
                due       = 'datetime'
                tags      = 'array'
                completed = 'bool'
                created   = 'datetime'
                parent_id = 'string'
            }
        }
        project = @{
            required = @('name')
            types    = @{
                id              = 'string'
                name            = 'string'
                description     = 'string'
                created         = 'datetime'
                status          = 'string'
                tags            = 'array'
                ID1             = 'string'
                ID2             = 'string'
                ProjFolder      = 'string'
                CAAName         = 'string'
                RequestName     = 'string'
                T2020           = 'string'
                AssignedDate    = 'datetime'
                DueDate         = 'datetime'
                BFDate          = 'datetime'
                RequestDate     = 'datetime'
                AuditType       = 'string'
                AuditorName     = 'string'
                AuditorPhone    = 'string'
                AuditorTL       = 'string'
                AuditorTLPhone  = 'string'
                AuditCase       = 'string'
                CASCase         = 'string'
                AuditStartDate  = 'datetime'
                TPName          = 'string'
                TPNum           = 'string'
                Address         = 'string'
                City            = 'string'
                Province        = 'string'
                PostalCode      = 'string'
                Country         = 'string'
                AuditPeriodFrom = 'datetime'
                AuditPeriodTo   = 'datetime'
            }
        }
        timelog = @{
            required = @('date', 'minutes')
            types    = @{
                date     = 'datetime'
                task     = 'string'
                project  = 'string'
                timecode = 'string'
                id1      = 'string'
                id2      = 'string'
                minutes  = 'int'
                notes    = 'string'
                created  = 'datetime'
            }
        }
    }

    # === Constructor (Private) ===
    TaskStore() {
        # Private constructor for singleton
        $this._InitializeStore()
    }

    # === Singleton Pattern ===

    <#
    .SYNOPSIS
    Get the singleton instance of TaskStore

    .OUTPUTS
    TaskStore singleton instance
    #>
    static [TaskStore] GetInstance() {
        if ($null -eq [TaskStore]::_instance) {
            [Monitor]::Enter([TaskStore]::_instanceLock)
            try {
                if ($null -eq [TaskStore]::_instance) {
                    [TaskStore]::_instance = [TaskStore]::new()
                    if (-not [TaskStore]::_instance.LoadData()) {
                        # FAIL FAST: Do not allow app to start with empty/corrupted state.
                        $err = [TaskStore]::_instance.LastError
                        [TaskStore]::_instance = $null # Reset instance so retry is possible
                        throw "CRITICAL: TaskStore failed to load data. Aborting to prevent data loss. Error: $err"
                    }
                }
            }
            finally {
                [Monitor]::Exit([TaskStore]::_instanceLock)
            }
        }

        return [TaskStore]::_instance
    }

    <#
    .SYNOPSIS
    Reset the singleton instance (for testing)
    #>
    static [void] ResetInstance() {
        [Monitor]::Enter([TaskStore]::_instanceLock)
        try {
            [TaskStore]::_instance = $null
        }
        finally {
            [Monitor]::Exit([TaskStore]::_instanceLock)
        }
    }

    # === Data Loading ===

    <#
    .SYNOPSIS
    Initialize the store
    #>
    hidden [void] _InitializeStore() {
        $this._data.tasks = [System.Collections.ArrayList]::new()
        $this._data.projects = [System.Collections.ArrayList]::new()
        $this._data.timelogs = [System.Collections.ArrayList]::new()
        $this.IsLoaded = $false
    }

    <#
    .SYNOPSIS
    Load data from Get-PmcAllData

    .OUTPUTS
    True if load succeeded, False otherwise
    #>
    [bool] LoadData() {
        Write-PmcTuiLog "TaskStore.LoadData: Starting" "DEBUG"
        [Monitor]::Enter($this._dataLock)
        try {
            try {
                # FIX: Call Get-PmcData via explicit module invocation
                Write-PmcTuiLog "TaskStore.LoadData: Calling Get-PmcData" "DEBUG"
                $pmcModule = Get-Module -Name 'Pmc.Strict'
                $pmcData = & $pmcModule { Get-PmcData }
                Write-PmcTuiLog "TaskStore.LoadData: Get-PmcData returned - tasks=$($pmcData.tasks.Count) projects=$($pmcData.projects.Count) timelogs=$($pmcData.timelogs.Count)" "DEBUG"

                if ($null -eq $pmcData) {
                    $this.LastError = "Get-PmcData returned null"
                    Write-PmcTuiLog "TaskStore.LoadData: ERROR - Get-PmcData returned null" "ERROR"
                    $this._InvokeCallback($this.OnLoadError, $this.LastError)
                    return $false
                }

                # Extract data sections
                if ($pmcData.tasks) {
                    $this._data.tasks = [System.Collections.ArrayList]::new()
                    foreach ($task in $pmcData.tasks) {
                        # Convert PSCustomObject to hashtable if needed
                        if ($task -isnot [hashtable]) {
                            $taskHash = @{}
                            foreach ($prop in $task.PSObject.Properties) {
                                $taskHash[$prop.Name] = $prop.Value
                            }
                            [void]$this._data.tasks.Add($taskHash)
                        }
                        else {
                            [void]$this._data.tasks.Add($task)
                        }
                    }
                    Write-PmcTuiLog "TaskStore.LoadData: Loaded $($this._data.tasks.Count) tasks" "DEBUG"
                }
                else {
                    $this._data.tasks = [System.Collections.ArrayList]::new()
                    Write-PmcTuiLog "TaskStore.LoadData: No tasks in data, initialized empty list" "DEBUG"
                }

                if ($pmcData.projects) {
                    $this._data.projects = [System.Collections.ArrayList]::new()
                    foreach ($project in $pmcData.projects) {
                        # Convert PSCustomObject to hashtable if needed
                        if ($project -isnot [hashtable]) {
                            $projectHash = @{}
                            foreach ($prop in $project.PSObject.Properties) {
                                $projectHash[$prop.Name] = $prop.Value
                            }
                            [void]$this._data.projects.Add($projectHash)
                        }
                        else {
                            [void]$this._data.projects.Add($project)
                        }
                    }
                    Write-PmcTuiLog "TaskStore.LoadData: Loaded $($this._data.projects.Count) projects" "DEBUG"
                    if ($this._data.projects.Count -gt 0) {
                        $firstProj = $this._data.projects[0]
                        Write-PmcTuiLog "TaskStore.LoadData: First project name='$(Get-SafeProperty $firstProj 'name')' ID1='$(Get-SafeProperty $firstProj 'ID1')'" "DEBUG"
                    }
                }
                else {
                    $this._data.projects = [System.Collections.ArrayList]::new()
                    Write-PmcTuiLog "TaskStore.LoadData: No projects in data, initialized empty list" "DEBUG"
                }

                if ($pmcData.timelogs) {
                    $this._data.timelogs = [System.Collections.ArrayList]::new()
                    foreach ($log in $pmcData.timelogs) {
                        # Convert PSCustomObject to hashtable if needed
                        if ($log -isnot [hashtable]) {
                            $logHash = @{}
                            foreach ($prop in $log.PSObject.Properties) {
                                $logHash[$prop.Name] = $prop.Value
                            }
                            [void]$this._data.timelogs.Add($logHash)
                        }
                        else {
                            [void]$this._data.timelogs.Add($log)
                        }
                    }
                }
                else {
                    $this._data.timelogs = [System.Collections.ArrayList]::new()
                }

                if ($pmcData.settings) {
                    $this._data.settings = $pmcData.settings
                }
                else {
                    $this._data.settings = @{}
                }

                $this._data.metadata.lastLoaded = Get-Date
                $this.IsLoaded = $true
                $this.LastError = ""

                return $true
            }
            catch {
                $this.LastError = "Failed to load data: $($_.Exception.Message)"
                Write-PmcTuiLog "TaskStore.LoadData: EXCEPTION: $($_.Exception.Message)" "ERROR"
                Write-PmcTuiLog "TaskStore.LoadData: Stack trace: $($_.ScriptStackTrace)" "ERROR"
                $this._InvokeCallback($this.OnLoadError, $this.LastError)
                return $false
            }
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Reload data from disk (discards in-memory changes)

    .OUTPUTS
    True if reload succeeded, False otherwise
    #>
    [bool] ReloadData() {
        return $this.LoadData()
    }

    # === Data Persistence ===

    <#
    .SYNOPSIS
    Save all data to disk via Set-PmcAllData

    .OUTPUTS
    True if save succeeded, False otherwise
    #>
    [bool] SaveData() {
        # CRITICAL FIX #3: Acquire lock BEFORE checking IsSaving to prevent race condition
        [Monitor]::Enter($this._dataLock)
        try {
            # Check IsSaving INSIDE the lock to ensure thread safety
            if ($this.IsSaving) {
                $this.LastError = "Save already in progress"
                Write-PmcTuiLog "TaskStore.SaveData: Already saving, returning false" "ERROR"
                return $false
            }

            $this.IsSaving = $true
            Write-PmcTuiLog "TaskStore.SaveData: START - tasks=$($this._data.tasks.Count) projects=$($this._data.projects.Count) timelogs=$($this._data.timelogs.Count)" "INFO"

            try {
                # PHASE 1: Create in-memory backup for rollback
                Write-PmcTuiLog "TaskStore.SaveData: Creating in-memory backup" "DEBUG"
                $this._CreateBackup()

                # PHASE 2: Create persistent timestamped backup before destructive operation
                Write-PmcTuiLog "TaskStore.SaveData: Creating persistent backup" "DEBUG"
                $this._CreatePersistentBackup()

                # PHASE 3: Build data structure for Save-PmcData
                Write-PmcTuiLog "TaskStore.SaveData: Building data structure" "DEBUG"
                $dataToSave = @{
                    tasks    = $this._data.tasks.ToArray()
                    projects = $this._data.projects.ToArray()
                    timelogs = $this._data.timelogs.ToArray()
                    settings = $this._data.settings
                }

                Write-PmcTuiLog "TaskStore.SaveData: Data structure built - tasks=$($dataToSave.tasks.Count) projects=$($dataToSave.projects.Count) timelogs=$($dataToSave.timelogs.Count)" "INFO"
                
                # Log first task/project for verification
                if ($dataToSave.tasks.Count -gt 0) {
                    $firstTask = $dataToSave.tasks[0]
                    Write-PmcTuiLog "TaskStore.SaveData: First task - text='$(Get-SafeProperty $firstTask 'text')' id='$(Get-SafeProperty $firstTask 'id')'" "DEBUG"
                }
                if ($dataToSave.projects.Count -gt 0) {
                    $firstProject = $dataToSave.projects[0]
                    Write-PmcTuiLog "TaskStore.SaveData: First project - name='$(Get-SafeProperty $firstProject 'name')' ID1='$(Get-SafeProperty $firstProject 'ID1')'" "DEBUG"
                }

                # PHASE 4: Call Save-PmcData via explicit module invocation
                Write-PmcTuiLog "TaskStore.SaveData: Calling Save-PmcData" "INFO"
                $pmcModule = Get-Module -Name 'Pmc.Strict'
                if ($null -eq $pmcModule) {
                    $this.LastError = "Pmc.Strict module not loaded - cannot save"
                    Write-PmcTuiLog "TaskStore.SaveData: FATAL - Pmc.Strict module not found" "ERROR"
                    return $false
                }
                
                & $pmcModule { param($data) Save-PmcData -Data $data } $dataToSave
                Write-PmcTuiLog "TaskStore.SaveData: Save-PmcData completed successfully" "INFO"

                # PHASE 5: Verify save success
                Write-PmcTuiLog "TaskStore.SaveData: Verifying save" "DEBUG"
                $this._VerifySave($dataToSave)

                # PHASE 6: Update metadata
                $this._data.metadata.lastSaved = Get-Date
                $this.LastError = ""
                $this.HasPendingChanges = $false

                # Clear in-memory backup on successful save
                $this._dataBackup = $null

                Write-PmcTuiLog "TaskStore.SaveData: SUCCESS - Data saved and verified" "INFO"
                return $true
            }
            catch {
                $this.LastError = "Failed to save data: $($_.Exception.Message)"
                Write-PmcTuiLog "TaskStore.SaveData: EXCEPTION: $($_.Exception.Message)" "ERROR"
                Write-PmcTuiLog "TaskStore.SaveData: Exception type: $($_.Exception.GetType().FullName)" "ERROR"
                Write-PmcTuiLog "TaskStore.SaveData: Stack trace: $($_.ScriptStackTrace)" "ERROR"
                
                # Log actionable error guidance
                Write-PmcTuiLog "TaskStore.SaveData: ERROR GUIDANCE:" "ERROR"
                Write-PmcTuiLog "  1. Check log for detailed error above" "ERROR"
                Write-PmcTuiLog "  2. Verify disk space available" "ERROR"
                Write-PmcTuiLog "  3. Check file permissions on tasks.json" "ERROR"
                Write-PmcTuiLog "  4. Look for backup files: tasks.json.backup.*" "ERROR"

                $this._InvokeCallback($this.OnSaveError, $this.LastError)

                # Rollback to in-memory backup
                Write-PmcTuiLog "TaskStore.SaveData: Rolling back to in-memory backup" "INFO"
                $this._Rollback()

                return $false
            }
        }
        finally {
            $this.IsSaving = $false
            [Monitor]::Exit($this._dataLock)
            Write-PmcTuiLog "TaskStore.SaveData: END" "DEBUG"
        }
    }

    <#
    .SYNOPSIS
    Create backup of current data for rollback
    #>
    hidden [void] _CreateBackup() {
        # Create shallow copy of arrays - deep copy not needed for backup/rollback
        $tasksCopy = [System.Collections.ArrayList]::new()
        foreach ($task in $this._data.tasks) { $tasksCopy.Add($task) | Out-Null }

        $projectsCopy = [System.Collections.ArrayList]::new()
        foreach ($project in $this._data.projects) { $projectsCopy.Add($project) | Out-Null }

        $timelogsCopy = [System.Collections.ArrayList]::new()
        foreach ($log in $this._data.timelogs) { $timelogsCopy.Add($log) | Out-Null }

        $this._dataBackup = @{
            tasks    = $tasksCopy
            projects = $projectsCopy
            timelogs = $timelogsCopy
            settings = $this._data.settings
        }
    }

    <#
    .SYNOPSIS
    Rollback to backup data
    #>
    hidden [void] _Rollback() {
        if ($null -ne $this._dataBackup) {
            $this._data.tasks = $this._dataBackup.tasks
            $this._data.projects = $this._dataBackup.projects
            $this._data.timelogs = $this._dataBackup.timelogs
            $this._data.settings = $this._dataBackup.settings
            $this._dataBackup = $null
        }
    }

    <#
    .SYNOPSIS
    Create persistent timestamped backup before save (separate from in-memory backup)
    
    .DESCRIPTION
    Creates a backup file like tasks.json.backup.20231215-143527
    Keeps last 5 backups, deletes older ones
    This protects against corruption from save failures
    #>
    hidden [void] _CreatePersistentBackup() {
        try {
            # Get tasks.json path
            $pmcModule = Get-Module -Name 'Pmc.Strict'
            if ($null -eq $pmcModule) {
                Write-PmcTuiLog "_CreatePersistentBackup: Pmc.Strict module not found, skipping backup" "WARNING"
                return
            }

            $tasksFile = & $pmcModule { Get-PmcTaskFilePath }
            if (-not (Test-Path $tasksFile)) {
                Write-PmcTuiLog "_CreatePersistentBackup: tasks.json does not exist yet, skipping backup" "DEBUG"
                return
            }

            # Create timestamped backup
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $backupFile = "$tasksFile.backup.$timestamp"
            
            Copy-Item -Path $tasksFile -Destination $backupFile -Force
            Write-PmcTuiLog "_CreatePersistentBackup: Created backup at $backupFile" "INFO"

            # Rotate backups - keep only last 5
            $backupDir = Split-Path $tasksFile -Parent
            $backupPattern = "$(Split-Path $tasksFile -Leaf).backup.*"
            $backups = Get-ChildItem -Path $backupDir -Filter $backupPattern | 
                Sort-Object LastWriteTime -Descending

            if ($backups.Count -gt 5) {
                $toDelete = $backups | Select-Object -Skip 5
                foreach ($old in $toDelete) {
                    Remove-Item $old.FullName -Force
                    Write-PmcTuiLog "_CreatePersistentBackup: Deleted old backup $($old.Name)" "DEBUG"
                }
            }
        }
        catch {
            # Backup creation is non-critical, log but continue
            Write-PmcTuiLog "_CreatePersistentBackup: Failed to create backup: $_" "WARNING"
        }
    }

    <#
    .SYNOPSIS
    Verify save succeeded by re-loading data from disk
    
    .DESCRIPTION
    Attempts to load tasks.json and verify task count matches
    This catches save failures early
    #>
    hidden [void] _VerifySave([hashtable]$savedData) {
        try {
            $pmcModule = Get-Module -Name 'Pmc.Strict'
            if ($null -eq $pmcModule) {
                Write-PmcTuiLog "_VerifySave: Pmc.Strict module not found, cannot verify" "WARNING"
                return
            }

            # Reload data from disk
            $reloadedData = & $pmcModule { Get-PmcData }
            
            if ($null -eq $reloadedData) {
                Write-PmcTuiLog "_VerifySave: Reloaded data is null!" "ERROR"
                throw "Save verification failed - reloaded data is null"
            }

            # Compare counts
            $savedTasks = $savedData.tasks.Count
            $reloadedTasks = if ($reloadedData.tasks) { @($reloadedData.tasks).Count } else { 0 }
            
            $savedProjects = $savedData.projects.Count  
            $reloadedProjects = if ($reloadedData.projects) { @($reloadedData.projects).Count } else { 0 }

            if ($savedTasks -ne $reloadedTasks) {
                Write-PmcTuiLog "_VerifySave: Task count mismatch! Saved=$savedTasks Reloaded=$reloadedTasks" "ERROR"
                throw "Save verification failed - task count mismatch (saved:$savedTasks vs reloaded:$reloadedTasks)"
            }

            if ($savedProjects -ne $reloadedProjects) {
                Write-PmcTuiLog "_VerifySave: Project count mismatch! Saved=$savedProjects Reloaded=$reloadedProjects" "ERROR"
                throw "Save verification failed - project count mismatch (saved:$savedProjects vs reloaded:$reloadedProjects)"
            }

            Write-PmcTuiLog "_VerifySave: Verification passed - tasks=$reloadedTasks projects=$reloadedProjects" "DEBUG"
        }
        catch {
            Write-PmcTuiLog "_VerifySave: Verification failed: $_" "ERROR"
            throw
        }
    }


    # === Task CRUD Operations ===

    <#
    .SYNOPSIS
    Get all tasks

    .OUTPUTS
    Array of task hashtables
    #>
    [array] GetAllTasks() {
        [Monitor]::Enter($this._dataLock)
        try {
            # HIGH FIX #9: Always return array, never null
            if ($null -eq $this._data.tasks) {
                Write-PmcTuiLog "GetAllTasks: No tasks collection, returning empty array" "WARNING"
                return @()
            }

            $tasks = $this._data.tasks.ToArray()
            # Write-PmcTuiLog "GetAllTasks: Returning $($tasks.Count) tasks" "DEBUG"
            return $tasks
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Get task by ID

    .PARAMETER id
    Task ID

    .OUTPUTS
    Task hashtable or $null if not found

    .NOTES
    HIGH FIX #9: Consistent error handling pattern
    - Collections (GetAllTasks, GetAllProjects) ALWAYS return arrays (never null)
    - Single items (GetTask, GetProject) return object or $null
    - Operations (Add, Update, Delete) return bool with LastError on failure
    #>
    [hashtable] GetTask([string]$id) {
        [Monitor]::Enter($this._dataLock)
        try {
            # HIGH FIX #9: Explicit null check with consistent behavior
            if ([string]::IsNullOrWhiteSpace($id)) {
                Write-PmcTuiLog "GetTask: Invalid ID (null or empty)" "WARNING"
                return $null
            }

            $task = $this._data.tasks | Where-Object { $_.id -eq $id } | Select-Object -First 1

            if ($null -eq $task) {
                # Write-PmcTuiLog "GetTask: Task not found with ID '$id'" "DEBUG"
            }

            return $task
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Add a new task

    .PARAMETER task
    Task hashtable (must include 'text' field minimum)

    .OUTPUTS
    True if add succeeded, False otherwise
    #>
    [bool] AddTask([hashtable]$task) {
        Write-PmcTuiLog "AddTask: Starting with task keys: $($task.Keys -join ', ')" "DEBUG"
        [Monitor]::Enter($this._dataLock)

        $success = $false
        $capturedTask = $null
        $capturedTasks = $null

        try {
            # Validate task
            $validationErrors = $this._ValidateEntity($task, 'task')
            if ($validationErrors.Count -gt 0) {
                $this.LastError = "Task validation failed: $($validationErrors -join ', ')"
                Write-PmcTuiLog "AddTask: Validation FAILED: $($validationErrors -join ', ')" "ERROR"
                return $false
            }
            # Write-PmcTuiLog "AddTask: Validation passed" "DEBUG"

            # Create backup BEFORE any modifications
            $this._CreateBackup()

            # Generate ID if not present
            # LOW FIX ES-L5: Check for GUID collision (extremely rare but validate)
            if (-not $task.ContainsKey('id') -or [string]::IsNullOrEmpty($task.id)) {
                $maxRetries = 3
                $retryCount = 0
                $guidGenerated = $false
                while (-not $guidGenerated -and $retryCount -lt $maxRetries) {
                    $newGuid = [Guid]::NewGuid().ToString()
                    # Check if this GUID already exists (collision check)
                    $collision = $this._data.tasks | Where-Object { $_.id -eq $newGuid } | Select-Object -First 1
                    if (-not $collision) {
                        $task.id = $newGuid
                        $guidGenerated = $true
                    }
                    else {
                        Write-PmcTuiLog "GUID collision detected: $newGuid (retry $($retryCount + 1)/$maxRetries)" "WARNING"
                        $retryCount++
                    }
                }
                if (-not $guidGenerated) {
                    $this.LastError = "Failed to generate unique GUID after $maxRetries attempts"
                    Write-PmcTuiLog "AddTask: GUID generation failed after $maxRetries retries" "ERROR"
                    return $false
                }
            }

            # H-VAL-7: Check for duplicate ID before insert
            $existingTask = $this._data.tasks | Where-Object { $_.id -eq $task.id } | Select-Object -First 1
            if ($existingTask) {
                $this.LastError = "Task with ID '$($task.id)' already exists"
                Write-PmcTuiLog "AddTask: Duplicate ID detected: $($task.id)" "ERROR"
                return $false
            }

            # Add default status fields if not present
            if (-not $task.ContainsKey('completed')) {
                $task.completed = $false
            }
            if (-not $task.ContainsKey('status')) {
                $task.status = 'pending'
            }

            # Add timestamps
            $now = Get-Date
            if (-not $task.ContainsKey('created')) {
                $task.created = $now
            }
            $task.modified = $now

            # Add to collection
            $this._data.tasks.Add($task)
            Write-PmcTuiLog "AddTask: Added to collection, total tasks=$($this._data.tasks.Count)" "DEBUG"

            # Mark pending changes and invalidate stats cache
            $this.HasPendingChanges = $true
            $this._statsNeedUpdate = $true

            # Persist only if AutoSave is enabled
            if ($this.AutoSave) {
                if (-not $this.SaveData()) {
                    Write-PmcTuiLog "AddTask: SaveData FAILED" "ERROR"
                    return $false
                }
                Write-PmcTuiLog "AddTask: SaveData succeeded" "DEBUG"
            }

            # Capture data for callbacks BEFORE releasing lock
            # Clone creates shallow copy - sufficient for callback isolation
            $capturedTask = $(if ($task -is [hashtable]) { $task.Clone() } else { $task.PSObject.Copy() })
            $capturedTasks = $this._data.tasks.ToArray()
            $success = $true

            # Write-PmcTuiLog "AddTask: Success (lock held)" "DEBUG"
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }

        # Fire events AFTER releasing lock to avoid deadlock
        if ($success) {
            Write-PmcTuiLog "AddTask: Firing callbacks" "DEBUG"
            $this._InvokeCallback($this.OnTaskAdded, $capturedTask)
            $this._InvokeCallback($this.OnTasksChanged, $capturedTasks)
            $this._InvokeCallback($this.OnDataChanged, $null)
        }

        return $success
    }

    <#
    .SYNOPSIS
    Update an existing task

    .PARAMETER id
    Task ID

    .PARAMETER changes
    Hashtable of fields to update

    .OUTPUTS
    True if update succeeded, False otherwise
    #>
    [bool] UpdateTask([string]$id, [hashtable]$changes) {
        [Monitor]::Enter($this._dataLock)

        $success = $false
        $capturedTask = $null
        $capturedTasks = $null

        try {
            # Find task
            $task = $this._data.tasks | Where-Object { $_.id -eq $id } | Select-Object -First 1

            if ($null -eq $task) {
                $this.LastError = "Task not found: $id"
                return $false
            }

            # Create backup BEFORE any modifications
            $this._CreateBackup()

            # CRITICAL FIX: Convert PSCustomObject to hashtable to prevent PowerShell's type coercion
            # When assigning to PSCustomObject properties, PowerShell forces type conversion based on existing property type
            if ($task -isnot [hashtable]) {
                # Add-Content -Path "$($env:TEMP)\pmc-edit-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') TaskStore.UpdateTask: Converting PSCustomObject to hashtable"
                $taskHash = @{}
                foreach ($prop in $task.PSObject.Properties) {
                    $taskHash[$prop.Name] = $prop.Value
                }
                # Find and replace in the tasks list
                $taskIndex = -1
                for ($i = 0; $i -lt $this._data.tasks.Count; $i++) {
                    if ((Get-SafeProperty $this._data.tasks[$i] 'id') -eq $id) {
                        $taskIndex = $i
                        break
                    }
                }
                if ($taskIndex -ge 0) {
                    $this._data.tasks[$taskIndex] = $taskHash
                    $task = $taskHash
                    # Add-Content -Path "$($env:TEMP)\pmc-edit-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') TaskStore.UpdateTask: Replaced task at index $taskIndex with hashtable"
                }
            }

            # Apply changes - now task is guaranteed to be hashtable
            foreach ($key in $changes.Keys) {
                if ($key -eq 'tags') {
                    # Add-Content -Path "$($env:TEMP)\pmc-edit-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') TaskStore.UpdateTask: BEFORE setting tags - changes[$key] type=$($changes[$key].GetType().Name) isArray=$($changes[$key] -is [array]) value=$($changes[$key] -join ',')"
                }
                $task[$key] = $changes[$key]
                if ($key -eq 'tags') {
                    # Add-Content -Path "$($env:TEMP)\pmc-edit-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') TaskStore.UpdateTask: AFTER setting tags - task.tags type=$($task[$key].GetType().Name) isArray=$($task[$key] -is [array]) value=$($task[$key] -join ',')"
                }
            }

            # Update modified timestamp
            if ($task -is [hashtable]) {
                $task['modified'] = Get-Date
            }
            elseif ($task.PSObject.Properties.Name -contains 'modified') {
                $task.modified = Get-Date
            }
            else {
                Add-Member -InputObject $task -MemberType NoteProperty -Name 'modified' -Value (Get-Date) -Force
            }

            # Validate updated task
            # Add-Content -Path "$($env:TEMP)\pmc-edit-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') TaskStore.UpdateTask: BEFORE VALIDATION - task.tags type=$(if ($task.ContainsKey('tags')) { $task['tags'].GetType().FullName } else { 'MISSING' }) isArray=$(if ($task.ContainsKey('tags')) { $task['tags'] -is [array] } else { 'N/A' })"
            $validationErrors = $this._ValidateEntity($task, 'task')
            # Add-Content -Path "$($env:TEMP)\pmc-edit-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') TaskStore.UpdateTask: AFTER VALIDATION - errors count=$($validationErrors.Count) errors=$($validationErrors -join '; ')"
            if ($validationErrors.Count -gt 0) {
                $this.LastError = "Task validation failed: $($validationErrors -join ', ')"
                $this._Rollback()
                return $false
            }

            # Mark pending changes and invalidate stats cache
            $this.HasPendingChanges = $true
            $this._statsNeedUpdate = $true

            # Persist only if AutoSave is enabled
            if ($this.AutoSave) {
                if (-not $this.SaveData()) {
                    return $false
                }
            }

            # Capture data for callbacks BEFORE releasing lock
            # Clone creates shallow copy - sufficient for callback isolation
            $capturedTask = $(if ($task -is [hashtable]) { $task.Clone() } else { $task.PSObject.Copy() })
            $capturedTasks = $this._data.tasks.ToArray()
            $success = $true
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }

        # Fire events AFTER releasing lock to avoid deadlock
        if ($success) {
            $this._InvokeCallback($this.OnTaskUpdated, $capturedTask)
            $this._InvokeCallback($this.OnTasksChanged, $capturedTasks)
            $this._InvokeCallback($this.OnDataChanged, $null)
        }

        return $success
    }

    <#
    .SYNOPSIS
    Delete a task by ID

    .PARAMETER id
    Task ID

    .OUTPUTS
    True if delete succeeded, False otherwise
    #>
    [bool] DeleteTask([string]$id) {
        [Monitor]::Enter($this._dataLock)

        $success = $false
        $capturedId = $id
        $capturedTasks = $null

        try {
            # Find task index
            $index = -1
            for ($i = 0; $i -lt $this._data.tasks.Count; $i++) {
                if ($this._data.tasks[$i].id -eq $id) {
                    $index = $i
                    break
                }
            }

            if ($index -eq -1) {
                $this.LastError = "Task not found: $id"
                return $false
            }

            # Create backup BEFORE any modifications
            $this._CreateBackup()

            # Remove task
            $this._data.tasks.RemoveAt($index)

            # Mark pending changes and invalidate stats cache
            $this.HasPendingChanges = $true
            $this._statsNeedUpdate = $true

            # Persist only if AutoSave is enabled
            if ($this.AutoSave) {
                if (-not $this.SaveData()) {
                    return $false
                }
            }

            # Capture data for callbacks BEFORE releasing lock
            $capturedTasks = $this._data.tasks.ToArray()
            $success = $true
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }

        # Fire events AFTER releasing lock to avoid deadlock
        if ($success) {
            $this._InvokeCallback($this.OnTaskDeleted, $capturedId)
            $this._InvokeCallback($this.OnTasksChanged, $capturedTasks)
            $this._InvokeCallback($this.OnDataChanged, $null)
        }

        return $success
    }

    # === Project CRUD Operations ===

    <#
    .SYNOPSIS
    Get all projects

    .OUTPUTS
    Array of project hashtables
    #>
    [array] GetAllProjects() {
        [Monitor]::Enter($this._dataLock)
        try {
            return $this._data.projects.ToArray()
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Get project by name

    .PARAMETER name
    Project name

    .OUTPUTS
    Project hashtable or $null if not found
    #>
    [hashtable] GetProject([string]$name) {
        [Monitor]::Enter($this._dataLock)
        try {
            $project = $this._data.projects | Where-Object { $_.name -eq $name } | Select-Object -First 1
            return $project
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Add a new project

    .PARAMETER project
    Project hashtable (must include 'name' field minimum)

    .OUTPUTS
    True if add succeeded, False otherwise
    #>
    [bool] AddProject([hashtable]$project) {
        Write-PmcTuiLog "TaskStore.AddProject: START - name='$($project.name)'" "DEBUG"
        [Monitor]::Enter($this._dataLock)
        try {
            # Validate project
            Write-PmcTuiLog "TaskStore.AddProject: Calling _ValidateEntity..." "DEBUG"
            $validationErrors = $this._ValidateEntity($project, 'project')
            if ($validationErrors.Count -gt 0) {
                $errorMsg = "Project validation failed: $($validationErrors -join ', ')"
                $this.LastError = $errorMsg
                Write-PmcTuiLog "TaskStore.AddProject: FAILED - $errorMsg" "ERROR"
                return $false
            }
            Write-PmcTuiLog "TaskStore.AddProject: Validation passed" "DEBUG"

            # Check for duplicate name
            $existing = $this._data.projects | Where-Object { $_.name -eq $project.name }
            if ($existing) {
                $errorMsg = "Project already exists: $($project.name)"
                $this.LastError = $errorMsg
                Write-PmcTuiLog "TaskStore.AddProject: FAILED - $errorMsg" "ERROR"
                return $false
            }
            Write-PmcTuiLog "TaskStore.AddProject: No duplicate found" "DEBUG"

            # Create backup BEFORE any modifications
            $this._CreateBackup()

            # Add timestamps
            $now = Get-Date
            if (-not $project.ContainsKey('created')) {
                $project.created = $now
            }
            $project.modified = $now

            # Add to collection
            Write-PmcTuiLog "TaskStore.AddProject: Adding to collection..." "DEBUG"
            $this._data.projects.Add($project)

            # Mark pending changes
            $this.HasPendingChanges = $true

            # Persist only if AutoSave is enabled
            if ($this.AutoSave) {
                Write-PmcTuiLog "TaskStore.AddProject: AutoSave enabled, calling SaveData..." "DEBUG"
                if (-not $this.SaveData()) {
                    Write-PmcTuiLog "TaskStore.AddProject: FAILED - SaveData returned false" "ERROR"
                    return $false
                }
                Write-PmcTuiLog "TaskStore.AddProject: SaveData succeeded" "DEBUG"
            }

            # Fire events
            $this._InvokeCallback($this.OnProjectAdded, $project)
            $this._InvokeCallback($this.OnProjectsChanged, $this._data.projects.ToArray())
            $this._InvokeCallback($this.OnDataChanged, $null)

            Write-PmcTuiLog "TaskStore.AddProject: SUCCESS" "DEBUG"
            return $true
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Update an existing project

    .PARAMETER name
    Project name

    .PARAMETER changes
    Hashtable of fields to update

    .OUTPUTS
    True if update succeeded, False otherwise
    #>
    [bool] UpdateProject([string]$name, [hashtable]$changes) {
        [Monitor]::Enter($this._dataLock)
        try {
            # Write-PmcTuiLog "UpdateProject: START - name='$name' changes=$($changes.Count)" "DEBUG"

            # Find project
            $project = $this._data.projects | Where-Object { $_.name -eq $name } | Select-Object -First 1

            if ($null -eq $project) {
                $this.LastError = "Project not found: $name"
                Write-PmcTuiLog "UpdateProject: Project not found: $name" "ERROR"
                return $false
            }

            Write-PmcTuiLog "UpdateProject: Found project, type=$($project.GetType().Name) BEFORE ID1='$(Get-SafeProperty $project 'ID1')'" "DEBUG"

            # Create backup BEFORE any modifications
            $this._CreateBackup()

            # Apply changes - handle both hashtable and PSCustomObject
            foreach ($key in $changes.Keys) {
                if ($key -eq 'ID1') {
                    Write-PmcTuiLog "UpdateProject: Updating ID1 from '$(Get-SafeProperty $project 'ID1')' to '$($changes[$key])'" "DEBUG"
                }

                # Check if hashtable or PSCustomObject
                if ($project -is [hashtable]) {
                    # Hashtable: direct assignment
                    $project[$key] = $changes[$key]
                    if ($key -eq 'ID1') {
                        Write-PmcTuiLog "UpdateProject: Hashtable assignment - project['ID1']='$($project[$key])'" "DEBUG"
                    }
                }
                else {
                    # PSCustomObject: use PSObject.Properties or Add-Member
                    if ($project.PSObject.Properties.Name -contains $key) {
                        $project.$key = $changes[$key]
                    }
                    else {
                        Add-Member -InputObject $project -MemberType NoteProperty -Name $key -Value $changes[$key] -Force
                    }
                }
            }

            Write-PmcTuiLog "UpdateProject: AFTER applying changes - ID1='$(Get-SafeProperty $project 'ID1')'" "DEBUG"

            # Update modified timestamp
            if ($project -is [hashtable]) {
                $project['modified'] = Get-Date
            }
            else {
                if ($project.PSObject.Properties.Name -contains 'modified') {
                    $project.modified = Get-Date
                }
                else {
                    Add-Member -InputObject $project -MemberType NoteProperty -Name 'modified' -Value (Get-Date) -Force
                }
            }

            # Validate updated project
            $validationErrors = $this._ValidateEntity($project, 'project')
            if ($validationErrors.Count -gt 0) {
                $this.LastError = "Project validation failed: $($validationErrors -join ', ')"
                Write-PmcTuiLog "UpdateProject: Validation FAILED - $($validationErrors -join ', ')" "ERROR"
                $this._Rollback()
                return $false
            }

            # Mark pending changes
            $this.HasPendingChanges = $true

            # Verify the change is in the projects array BEFORE SaveData
            $verifyProject = $this._data.projects | Where-Object { $_.name -eq $name } | Select-Object -First 1
            if ($verifyProject) {
                Write-PmcTuiLog "UpdateProject: VERIFY before SaveData - project in array has ID1='$(Get-SafeProperty $verifyProject 'ID1')'" "DEBUG"
            }

            # Persist only if AutoSave is enabled
            if ($this.AutoSave) {
                Write-PmcTuiLog "UpdateProject: AutoSave is enabled, calling SaveData" "DEBUG"
                if (-not $this.SaveData()) {
                    Write-PmcTuiLog "UpdateProject: SaveData FAILED" "ERROR"
                    return $false
                }
                Write-PmcTuiLog "UpdateProject: SaveData succeeded" "DEBUG"
            }
            else {
                Write-PmcTuiLog "UpdateProject: AutoSave is DISABLED, skipping SaveData" "WARNING"
            }

            # Fire events
            $this._InvokeCallback($this.OnProjectUpdated, $project)
            $this._InvokeCallback($this.OnProjectsChanged, $this._data.projects.ToArray())
            $this._InvokeCallback($this.OnDataChanged, $null)

            return $true
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Delete a project by name

    .PARAMETER name
    Project name

    .OUTPUTS
    True if delete succeeded, False otherwise
    #>
    [bool] DeleteProject([string]$name) {
        [Monitor]::Enter($this._dataLock)
        try {
            # Find project index
            $index = -1
            for ($i = 0; $i -lt $this._data.projects.Count; $i++) {
                if ($this._data.projects[$i].name -eq $name) {
                    $index = $i
                    break
                }
            }

            if ($index -eq -1) {
                $this.LastError = "Project not found: $name"
                return $false
            }

            # Create backup BEFORE any modifications
            $this._CreateBackup()

            # Remove project
            $this._data.projects.RemoveAt($index)

            # Mark pending changes
            $this.HasPendingChanges = $true

            # Persist only if AutoSave is enabled
            if ($this.AutoSave) {
                if (-not $this.SaveData()) {
                    return $false
                }
            }

            # Fire events
            $this._InvokeCallback($this.OnProjectDeleted, $name)
            $this._InvokeCallback($this.OnProjectsChanged, $this._data.projects.ToArray())
            $this._InvokeCallback($this.OnDataChanged, $null)

            return $true
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    # === Time Log CRUD Operations ===

    <#
    .SYNOPSIS
    Get all time logs

    .OUTPUTS
    Array of time log hashtables
    #>
    [array] GetAllTimeLogs() {
        [Monitor]::Enter($this._dataLock)
        try {
            return $this._data.timelogs.ToArray()
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Get time logs for a specific task

    .PARAMETER taskId
    Task ID

    .OUTPUTS
    Array of time log hashtables
    #>
    [array] GetTimeLogsForTask([string]$taskId) {
        [Monitor]::Enter($this._dataLock)
        try {
            $logs = $this._data.timelogs | Where-Object { $_.taskId -eq $taskId }
            return $(if ($logs) { $logs } else { @() })
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Add a new time log

    .PARAMETER timelog
    Time log hashtable (must include 'taskId' and 'duration')

    .OUTPUTS
    True if add succeeded, False otherwise
    #>
    [bool] AddTimeLog([hashtable]$timelog) {
        [Monitor]::Enter($this._dataLock)
        try {
            if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
                Write-PmcTuiLog "TaskStore.AddTimeLog: CALLED with timelog keys: $($timelog.Keys -join ', ')" "DEBUG"
                foreach ($key in $timelog.Keys) {
                    $val = $timelog[$key]
                    $valType = if ($null -eq $val) { 'null' } else { $val.GetType().Name }
                    Write-PmcTuiLog "TaskStore.AddTimeLog:   $key = $val (type: $valType)" "DEBUG"
                }
            }
            # Validate time log
            $validationErrors = $this._ValidateEntity($timelog, 'timelog')
            if ($validationErrors.Count -gt 0) {
                $this.LastError = "Time log validation failed: $($validationErrors -join ', ')"
                Write-PmcTuiLog "TaskStore.AddTimeLog: VALIDATION FAILED: $($validationErrors -join ', ')" "ERROR"
                return $false
            }
            Write-PmcTuiLog "TaskStore.AddTimeLog: Validation passed" "DEBUG"

            # Create backup BEFORE any modifications
            $this._CreateBackup()

            # Generate ID if not present
            if (-not $timelog.ContainsKey('id') -or [string]::IsNullOrEmpty($timelog.id)) {
                $timelog.id = [Guid]::NewGuid().ToString()
            }

            # Add timestamp if not present
            if (-not $timelog.ContainsKey('timestamp')) {
                $timelog.timestamp = Get-Date
            }

            # Add to collection
            $this._data.timelogs.Add($timelog)

            # Mark pending changes
            $this.HasPendingChanges = $true

            # Persist only if AutoSave is enabled
            if ($this.AutoSave) {
                if (-not $this.SaveData()) {
                    return $false
                }
            }

            # Fire events
            $this._InvokeCallback($this.OnTimeLogAdded, $timelog)
            $this._InvokeCallback($this.OnTimeLogsChanged, $this._data.timelogs.ToArray())
            $this._InvokeCallback($this.OnDataChanged, $null)

            return $true
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Delete a time log by ID

    .PARAMETER id
    Time log ID

    .OUTPUTS
    True if delete succeeded, False otherwise
    #>
    [bool] DeleteTimeLog([string]$id) {
        [Monitor]::Enter($this._dataLock)
        try {
            # Find time log index
            $index = -1
            for ($i = 0; $i -lt $this._data.timelogs.Count; $i++) {
                if ($this._data.timelogs[$i].id -eq $id) {
                    $index = $i
                    break
                }
            }

            if ($index -eq -1) {
                $this.LastError = "Time log not found: $id"
                return $false
            }

            # Create backup BEFORE any modifications
            $this._CreateBackup()

            # Remove time log
            $this._data.timelogs.RemoveAt($index)

            # Mark pending changes
            $this.HasPendingChanges = $true

            # Persist only if AutoSave is enabled
            if ($this.AutoSave) {
                if (-not $this.SaveData()) {
                    return $false
                }
            }

            # Fire events
            $this._InvokeCallback($this.OnTimeLogDeleted, $id)
            $this._InvokeCallback($this.OnTimeLogsChanged, $this._data.timelogs.ToArray())
            $this._InvokeCallback($this.OnDataChanged, $null)

            return $true
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Update a time log entry

    .PARAMETER id
    Time log ID

    .PARAMETER changes
    Hashtable of fields to update

    .OUTPUTS
    True if update succeeded, False otherwise
    #>
    [bool] UpdateTimeLog([string]$id, [hashtable]$changes) {
        [Monitor]::Enter($this._dataLock)
        try {
            # Find time log
            $timelog = $null
            foreach ($log in $this._data.timelogs) {
                if ($log.id -eq $id) {
                    $timelog = $log
                    break
                }
            }

            if (-not $timelog) {
                $this.LastError = "Time log not found: $id"
                return $false
            }

            # Create backup BEFORE any modifications
            $this._CreateBackup()

            # Apply changes
            foreach ($key in $changes.Keys) {
                if ($key -ne 'id') {
                    # Don't allow ID changes
                    $timelog[$key] = $changes[$key]
                }
            }

            # Add modified timestamp
            $timelog.modified = [DateTime]::Now

            # Validate
            $validationErrors = $this._ValidateEntity($timelog, 'timelog')
            if ($validationErrors.Count -gt 0) {
                $this.LastError = "Validation failed: $($validationErrors -join ', ')"
                return $false
            }

            # Mark pending changes
            $this.HasPendingChanges = $true

            # Persist only if AutoSave is enabled
            if ($this.AutoSave) {
                if (-not $this.SaveData()) {
                    return $false
                }
            }

            # Fire events
            $this._InvokeCallback($this.OnTimeLogUpdated, $timelog)
            $this._InvokeCallback($this.OnTimeLogsChanged, $this._data.timelogs.ToArray())
            $this._InvokeCallback($this.OnDataChanged, $null)

            return $true
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    # === Query Methods ===

    <#
    .SYNOPSIS
    Get tasks by project

    .PARAMETER projectName
    Project name

    .OUTPUTS
    Array of task hashtables
    #>
    [array] GetTasksByProject([string]$projectName) {
        [Monitor]::Enter($this._dataLock)
        try {
            $tasks = $this._data.tasks | Where-Object { $_.project -eq $projectName }
            return $(if ($tasks) { $tasks } else { @() })
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Search tasks by text

    .PARAMETER searchText
    Search query

    .OUTPUTS
    Array of task hashtables
    #>
    [array] SearchTasks([string]$searchText) {
        [Monitor]::Enter($this._dataLock)
        try {
            $searchLower = $searchText.ToLower()
            $tasks = $this._data.tasks | Where-Object {
                $null -ne $_.text -and $_.text.ToLower().Contains($searchLower)
            }
            return $(if ($tasks) { $tasks } else { @() })
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Get tasks by priority range

    .PARAMETER minPriority
    Minimum priority (inclusive)

    .PARAMETER maxPriority
    Maximum priority (inclusive)

    .OUTPUTS
    Array of task hashtables
    #>
    [array] GetTasksByPriority([int]$minPriority, [int]$maxPriority) {
        [Monitor]::Enter($this._dataLock)
        try {
            $tasks = $this._data.tasks | Where-Object {
                $_.priority -ge $minPriority -and $_.priority -le $maxPriority
            }
            return $(if ($tasks) { $tasks } else { @() })
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    # === Validation ===

    <#
    .SYNOPSIS
    Validate an entity against rules

    .PARAMETER entity
    Entity hashtable to validate

    .PARAMETER entityType
    Entity type ('task', 'project', 'timelog')

    .OUTPUTS
    Array of validation error messages (empty if valid)
    #>
    hidden [string[]] _ValidateEntity($entity, [string]$entityType) {
        $errors = @()

        if (-not $this._validationRules.ContainsKey($entityType)) {
            $errors += "Unknown entity type: $entityType"
            return $errors
        }

        $rules = $this._validationRules[$entityType]

        # Check required fields
        foreach ($field in $rules.required) {
            $value = Get-SafeProperty $entity $field
            if ([string]::IsNullOrEmpty($value)) {
                $errors += "Required field missing: $field"
            }
        }

        # Check field types
        foreach ($field in $rules.types.Keys) {
            $hasField = Test-SafeProperty $entity $field
            if ($hasField) {
                $value = Get-SafeProperty $entity $field
                if ($field -eq 'tags') {
                    # Add-Content -Path "$($env:TEMP)\pmc-edit-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') _ValidateEntity: Checking tags - value type=$($value.GetType().FullName) isArray=$($value -is [array]) value=$value"
                }
                if ($null -ne $value) {
                    $expectedType = $rules.types[$field]

                    $isValid = switch ($expectedType) {
                        'string' { $value -is [string] }
                        'int' {
                            # Accept both Int32 and Int64
                            $result = ($value -is [int]) -or ($value -is [int64]) -or ($value -is [int32])
                            if ($field -eq 'priority') {
                                # Add-Content -Path "$($env:TEMP)\pmc-edit-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') TaskStore: Validating priority - value=$value type=$($value.GetType().FullName) isInt=$result"
                            }
                            $result
                        }
                        'bool' { $value -is [bool] }
                        'datetime' { $value -is [DateTime] }
                        'array' { $value -is [array] }
                        default { $true }
                    }

                    if (-not $isValid) {
                        $errors += "Field '$field' has invalid type (expected $expectedType, got $($value.GetType().FullName))"
                    }
                }
            }
        }

        return $errors
    }

    # === Helper Methods ===

    <#
    .SYNOPSIS
    Invoke callback safely
    #>
    hidden [void] _InvokeCallback([scriptblock]$callback, $arg) {
        if ($null -ne $callback -and $callback -ne {}) {
            try {
                if ($null -ne $arg) {
                    # Use Invoke-Command with -ArgumentList to pass single arg without array wrapping
                    Invoke-Command -ScriptBlock $callback -ArgumentList (, $arg)
                }
                else {
                    & $callback
                }
            }
            catch {
                # Log callback errors but DON'T rethrow - callbacks must never crash the app
                $this.LastError = "Callback failed: $($_.Exception.Message)"
                if (Get-Command Write-PmcTuiLog -ErrorAction SilentlyContinue) {
                    Write-PmcTuiLog "TaskStore callback error: $($_.Exception.Message)" "ERROR"
                    Write-PmcTuiLog "Callback code: $($callback.ToString())" "ERROR"
                    Write-PmcTuiLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
                }
                # DON'T rethrow - background operations must not crash
            }
        }
    }

    # === Batch Operations ===

    <#
    .SYNOPSIS
    Add multiple tasks in a single transaction

    .PARAMETER tasks
    Array of task hashtables

    .OUTPUTS
    Number of tasks successfully added
    #>
    [int] AddTasks([hashtable[]]$tasks) {
        [Monitor]::Enter($this._dataLock)
        try {
            $addedCount = 0
            $this._CreateBackup()

            foreach ($task in $tasks) {
                # Validate task
                $validationErrors = $this._ValidateEntity($task, 'task')
                if ($validationErrors.Count -gt 0) {
                    continue  # Skip invalid tasks
                }

                # Generate ID if not present
                if (-not $task.ContainsKey('id') -or [string]::IsNullOrEmpty($task.id)) {
                    $task.id = [Guid]::NewGuid().ToString()
                }

                # Add timestamps
                $now = Get-Date
                if (-not $task.ContainsKey('created')) {
                    $task.created = $now
                }
                $task.modified = $now

                # Add to collection
                $this._data.tasks.Add($task)
                $addedCount++
            }

            # Persist once for all tasks
            if ($addedCount -gt 0) {
                if ($this.SaveData()) {
                    # Fire events once
                    $this._InvokeCallback($this.OnTasksChanged, $this._data.tasks.ToArray())
                    $this._InvokeCallback($this.OnDataChanged, $null)
                }
                else {
                    return 0
                }
            }

            return $addedCount
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Get data statistics

    .OUTPUTS
    Hashtable with data statistics
    #>
    [hashtable] GetStatistics() {
        [Monitor]::Enter($this._dataLock)
        try {
            # Return cached stats if available and not dirty
            if (-not $this._statsNeedUpdate -and $null -ne $this._cachedStats) {
                return $this._cachedStats
            }

            # Compute statistics (only when cache is dirty)
            $completedCount = 0
            $pendingCount = 0
            foreach ($task in $this._data.tasks) {
                if (Get-SafeProperty $task 'completed') {
                    $completedCount++
                }
                else {
                    $pendingCount++
                }
            }

            $this._cachedStats = @{
                taskCount          = $this._data.tasks.Count
                projectCount       = $this._data.projects.Count
                timeLogCount       = $this._data.timelogs.Count
                completedTaskCount = $completedCount
                pendingTaskCount   = $pendingCount
                lastLoaded         = $this._data.metadata.lastLoaded
                lastSaved          = $this._data.metadata.lastSaved
            }

            $this._statsNeedUpdate = $false
            return $this._cachedStats
        }
        finally {
            [Monitor]::Exit($this._dataLock)
        }
    }

    <#
    .SYNOPSIS
    Flush pending changes to disk

    .DESCRIPTION
    When AutoSave is disabled, changes accumulate in memory.
    Call this method to persist all pending changes to disk.

    .OUTPUTS
    True if flush succeeded, False otherwise
    #>
    [bool] Flush() {
        if (-not $this.HasPendingChanges) {
            return $true  # Nothing to save
        }

        if ($this.SaveData()) {
            $this.HasPendingChanges = $false
            return $true
        }

        return $false
    }

    <#
    .SYNOPSIS
    Enable automatic saving after each operation
    #>
    [void] EnableAutoSave() {
        $this.AutoSave = $true
    }

    <#
    .SYNOPSIS
    Disable automatic saving (batch mode)
    #>
    [void] DisableAutoSave() {
        $this.AutoSave = $false
    }
}