# Storage and schema for strict engine (self-contained)

Set-StrictMode -Version Latest

function Add-PmcUndoEntry {
    param(
        [string]$file,
        [object]$data
    )

    # Create undo entry for the current data state before modification
    try {
        if (-not (Test-Path $file)) {
            # No existing file to backup
            return
        }

        $undoFile = $file + '.undo'
        $currentContent = Get-Content $file -Raw -ErrorAction SilentlyContinue

        if ($currentContent) {
            # Save current state for undo capability
            $undoEntry = @{
                timestamp = (Get-Date).ToString('o')
                file = $file
                content = $currentContent
            }

            $undoJson = $undoEntry | ConvertTo-Json -Compress
            Add-Content -Path $undoFile -Value $undoJson -ErrorAction SilentlyContinue

            # Keep only last 3 undo entries to prevent file growth
            $undoLines = Get-Content $undoFile -ErrorAction SilentlyContinue
            if ($undoLines -and $undoLines.Count -gt 3) {
                $undoLines[-3..-1] | Set-Content $undoFile -ErrorAction SilentlyContinue
            }
        }
    } catch {
        # Undo functionality is non-critical, don't fail the main operation
        Write-PmcDebug -Level 2 -Category 'STORAGE' -Message "Undo entry creation failed: $_"
    }
}

function Get-PmcTaskFilePath {
    $cfg = Get-PmcConfig
    $path = $null
    try { if ($cfg.Paths -and $cfg.Paths.TaskFile) { $path = [string]$cfg.Paths.TaskFile } } catch {
        # Configuration access failed - use default path
    }
    if (-not $path -or [string]::IsNullOrWhiteSpace($path)) {
        # Default to pmc/tasks.json (three levels up from module dir)
        # FIX: Use module path instead of $PSScriptRoot (which can be wrong in scriptblock context)
        $moduleBase = (Get-Module -Name 'Pmc.Strict').ModuleBase
        if ($moduleBase) {
            $root = Split-Path (Split-Path $moduleBase -Parent) -Parent
        } else {
            # Fallback to $PSScriptRoot
            $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        }
        $path = Join-Path $root 'tasks.json'
    }
    return $path
}

function Initialize-PmcDataSchema {
    param($data)
    if (-not $data) { return $data }
    if (-not $data.PSObject.Properties['schema_version']) { $data | Add-Member -NotePropertyName schema_version -NotePropertyValue 1 -Force }
    foreach ($k in @('tasks','deleted','completed','projects','timelogs','activityLog','templates','recurringTemplates','aliases')) {
        if (-not $data.PSObject.Properties[$k] -or -not $data.$k) { $data | Add-Member -NotePropertyName $k -NotePropertyValue @() -Force }
    }
    # Normalize aliases to hashtable for reliable access
    try {
        if ($data.PSObject.Properties['aliases']) {
            $al = $data.aliases
            if ($al -is [pscustomobject]) {
                $ht = @{}
                foreach ($p in $al.PSObject.Properties) { $ht[$p.Name] = $p.Value }
                $data.aliases = $ht
            } elseif ($al -is [array]) {
                # Convert array of pairs into hashtable if possible
                $ht = @{}
                foreach ($item in $al) { try { $ht[$item.Name] = $item.Value } catch {
                    # Array item property access failed - skip this item
                } }
                $data.aliases = $ht
            } elseif (-not ($al -is [hashtable])) {
                $data.aliases = @{}
            }
        } else {
            $data | Add-Member -NotePropertyName aliases -NotePropertyValue @{} -Force
        }
    } catch {
        # Data schema normalization failed - continue with what we have
    }
    if (-not $data.PSObject.Properties['currentContext'] -or -not $data.currentContext) { $data | Add-Member -NotePropertyName currentContext -NotePropertyValue 'inbox' -Force }
    if (-not $data.PSObject.Properties['preferences']) { $data | Add-Member -NotePropertyName preferences -NotePropertyValue @{ autoBackup = $true } -Force }

    # Normalize task properties to prevent "property cannot be found" errors
    if ($data.tasks -and $data.tasks.Count -gt 0) {
        foreach ($task in $data.tasks) {
            if ($null -eq $task) { continue }
            try {
                # Check if Pmc-HasProp function exists before using it
                $hasPmcHasProp = Get-Command -Name 'Pmc-HasProp' -ErrorAction SilentlyContinue
                if (-not $hasPmcHasProp) {
                    Write-PmcDebug -Level 2 -Category 'STORAGE' -Message "Pmc-HasProp function not available, skipping task property normalization"
                    continue
                }

                # Ensure critical properties exist with defaults - wrap each in try-catch
                try { if (-not (Pmc-HasProp $task 'depends')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'depends' -NotePropertyValue @() -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.depends: $_" }
                try { if (-not (Pmc-HasProp $task 'tags')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'tags' -NotePropertyValue @() -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.tags: $_" }
                try { if (-not (Pmc-HasProp $task 'notes')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'notes' -NotePropertyValue @() -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.notes: $_" }
                try { if (-not (Pmc-HasProp $task 'recur')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'recur' -NotePropertyValue $null -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.recur: $_" }
                try { if (-not (Pmc-HasProp $task 'estimatedMinutes')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'estimatedMinutes' -NotePropertyValue $null -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.estimatedMinutes: $_" }
                try { if (-not (Pmc-HasProp $task 'status')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'status' -NotePropertyValue 'pending' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.status: $_" }
                try { if (-not (Pmc-HasProp $task 'priority')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'priority' -NotePropertyValue 0 -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.priority: $_" }
                try { if (-not (Pmc-HasProp $task 'project')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'project' -NotePropertyValue 'inbox' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.project: $_" }
                try { if (-not (Pmc-HasProp $task 'due')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'due' -NotePropertyValue $null -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.due: $_" }
                try { if (-not (Pmc-HasProp $task 'nextSuggestedCount')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'nextSuggestedCount' -NotePropertyValue 3 -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.nextSuggestedCount: $_" }
                try { if (-not (Pmc-HasProp $task 'lastNextShown')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'lastNextShown' -NotePropertyValue (Get-Date).ToString('yyyy-MM-dd') -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.lastNextShown: $_" }
                try { if (-not (Pmc-HasProp $task 'created')) { Add-Member -InputObject $task -MemberType NoteProperty -Name 'created' -NotePropertyValue (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize task.created: $_" }
            } catch {
                # Individual task property normalization failed - log and continue
                Write-PmcDebug -Level 2 -Category 'STORAGE' -Message "Failed to normalize task properties: $_"
            }
        }
    }
    # Ensure timelog entries have taskId (optional linkage to tasks)
    if ($data.timelogs -and $data.timelogs.Count -gt 0) {
        foreach ($log in $data.timelogs) {
            if ($null -eq $log) { continue }
            if (-not (Pmc-HasProp $log 'taskId')) {
                try { Add-Member -InputObject $log -MemberType NoteProperty -Name 'taskId' -NotePropertyValue $null -Force } catch {}
            }
        }
    }

    # Normalize project properties
    if ($data.projects -and $data.projects.Count -gt 0) {
        foreach ($project in $data.projects) {
            if ($null -eq $project) { continue }
            try {
                # Check if Pmc-HasProp function exists before using it
                $hasPmcHasProp = Get-Command -Name 'Pmc-HasProp' -ErrorAction SilentlyContinue
                if (-not $hasPmcHasProp) {
                    Write-PmcDebug -Level 2 -Category 'STORAGE' -Message "Pmc-HasProp function not available, skipping project property normalization"
                    continue
                }

                # Ensure critical properties exist with defaults - wrap each in try-catch
                try { if (-not (Pmc-HasProp $project 'name')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'name' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.name: $_" }
                try { if (-not (Pmc-HasProp $project 'description')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'description' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.description: $_" }
                try { if (-not (Pmc-HasProp $project 'aliases')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'aliases' -NotePropertyValue @() -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.aliases: $_" }
                try { if (-not (Pmc-HasProp $project 'created')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'created' -NotePropertyValue (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.created: $_" }
                try { if (-not (Pmc-HasProp $project 'isArchived')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'isArchived' -NotePropertyValue $false -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.isArchived: $_" }
                try { if (-not (Pmc-HasProp $project 'color')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'color' -NotePropertyValue 'Gray' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.color: $_" }
                try { if (-not (Pmc-HasProp $project 'icon')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'icon' -NotePropertyValue '📁' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.icon: $_" }
                try { if (-not (Pmc-HasProp $project 'sortOrder')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'sortOrder' -NotePropertyValue 0 -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.sortOrder: $_" }
                # Extended fields (t2 parity)
                try { if (-not (Pmc-HasProp $project 'ID1')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'ID1' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.ID1: $_" }
                try { if (-not (Pmc-HasProp $project 'ID2')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'ID2' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.ID2: $_" }
                try { if (-not (Pmc-HasProp $project 'ProjFolder')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'ProjFolder' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.ProjFolder: $_" }
                try { if (-not (Pmc-HasProp $project 'AssignedDate')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'AssignedDate' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.AssignedDate: $_" }
                try { if (-not (Pmc-HasProp $project 'DueDate')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'DueDate' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.DueDate: $_" }
                try { if (-not (Pmc-HasProp $project 'BFDate')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'BFDate' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.BFDate: $_" }
                try { if (-not (Pmc-HasProp $project 'CAAName')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'CAAName' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.CAAName: $_" }
                try { if (-not (Pmc-HasProp $project 'RequestName')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'RequestName' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.RequestName: $_" }
                try { if (-not (Pmc-HasProp $project 'T2020')) { Add-Member -InputObject $project -MemberType NoteProperty -Name 'T2020' -NotePropertyValue '' -Force } } catch { Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "Failed to normalize project.T2020: $_" }
            } catch {
                # Individual project property normalization failed - log and continue
                Write-PmcDebug -Level 2 -Category 'STORAGE' -Message "Failed to normalize project properties: $_"
            }
        }
    }

    return $data
}

# Normalize data to consistent shapes (fail-fast for irrecoverable cases)
function Normalize-PmcData {
    param($data)
    if (-not $data) { throw 'Data is null' }
    foreach ($k in @('tasks','deleted','completed','projects','timelogs','activityLog','templates','recurringTemplates')) {
        if (-not (Pmc-HasProp $data $k) -or -not $data.$k) { $data | Add-Member -NotePropertyName $k -NotePropertyValue @() -Force }
        elseif (-not ($data.$k -is [System.Collections.IEnumerable])) { throw "Data section '$k' is not a list" }
    }
    # Coerce hashtable entries to PSCustomObject for tasks/projects/timelogs
    $coerce = {
        param($arrRef)
        $new = @()
        foreach ($it in @($arrRef)) {
            if ($null -eq $it) { continue }
            if ($it -is [hashtable]) { $new += [pscustomobject]$it }
            else { $new += $it }
        }
        return ,$new
    }
    $data.tasks = & $coerce $data.tasks
    $data.projects = & $coerce $data.projects
    $data.timelogs = & $coerce $data.timelogs
    return $data
}

# Alias for backward compatibility - defined after Get-PmcData below

# Data provider for display system
function Get-PmcDataProvider {
    param([string]$ProviderType = 'Storage')

    # Return an object with GetData method
    return [PSCustomObject]@{
        GetData = { Get-PmcData }
    }
}

# Alias for backward compatibility - critical for Tasks/Time/Projects
function Set-PmcAllData {
    param($Data)
    Save-PmcData -Data $Data
}

# Enhanced Query Engine data providers
function Get-PmcTasksData {
    $data = Get-PmcData
    return $(if ($data -and $data.tasks) { @($data.tasks) } else { @() })
}

function Get-PmcProjectsData {
    $data = Get-PmcData
    return $(if ($data -and $data.projects) { @($data.projects) } else { @() })
}

function Get-PmcTimeLogsData {
    $data = Get-PmcData
    return $(if ($data -and $data.timelogs) { @($data.timelogs) } else { @() })
}

function Get-PmcData {
    $file = Get-PmcTaskFilePath
    if (-not (Test-Path $file)) {
        $root = Split-Path $file -Parent
        try { if (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null } } catch {
            # Directory creation failed - may cause subsequent save failures
        }
        $init = @{
            tasks=@(); deleted=@(); completed=@(); timelogs=@(); activityLog=@(); projects=@(@{ name='inbox'; description='Default inbox'; aliases=@(); created=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss') });
            currentContext='inbox'; schema_version=1; preferences=@{ autoBackup=$true }
        } | ConvertTo-Json -Depth 10
        $init | Set-Content -Path $file -Encoding UTF8
    }
    # Load with optional strict recovery policy
    # KR-M1 FIX: Add type validation before casting JSON boolean field
    $cfg = Get-PmcConfig; $strict = $true
    try {
        if ($cfg.Behavior -and $cfg.Behavior.StrictDataMode -ne $null) {
            # Validate and safely convert to boolean
            if ($cfg.Behavior.StrictDataMode -is [bool]) {
                $strict = $cfg.Behavior.StrictDataMode
            } elseif ($cfg.Behavior.StrictDataMode -is [string]) {
                $strict = $cfg.Behavior.StrictDataMode -eq 'true'
            } elseif ($cfg.Behavior.StrictDataMode -is [int]) {
                $strict = $cfg.Behavior.StrictDataMode -ne 0
            } else {
                $strict = [bool]$cfg.Behavior.StrictDataMode
            }
        }
    } catch {}
    try {
        $raw = Get-Content $file -Raw
        $data = $raw | ConvertFrom-Json
        # Coerce collections before adding default properties to ensure NoteProperty attaches to PSCustomObject
        $data = Normalize-PmcData $data
        $data = Initialize-PmcDataSchema $data
        return $data
    } catch {
        if ($strict) { throw }
        # Non-strict: Try .tmp
        $tmp = "$file.tmp"
        try {
            if (Test-Path $tmp) {
                $raw = Get-Content $tmp -Raw
                $data = $raw | ConvertFrom-Json
                Write-PmcDebug -Level 1 -Category 'STORAGE' -Message 'Recovered data from tmp'
                return (Initialize-PmcDataSchema $data)
            }
        } catch {
            # Temporary file recovery failed - try backup files
        }
        # Try rotating backups .bak1..bak9
        for ($i=1; $i -le 9; $i++) {
            $bak = "$file.bak$i"
            if (-not (Test-Path $bak)) { continue }
            try {
                $raw = Get-Content $bak -Raw
                $data = $raw | ConvertFrom-Json
                Write-PmcDebug -Level 1 -Category 'STORAGE' -Message ("Recovered data from backup: {0}" -f (Split-Path $bak -Leaf))
                return (Initialize-PmcDataSchema $data)
            } catch {
                # Backup file recovery failed - try next backup
            }
        }
        throw "Failed to load or recover data"
    }
}

function Get-PmcSafePath {
    param([string]$Path)
    $cfg = Get-PmcConfig
    $strict = $true; $allowed=@()
    try { if ($cfg.Behavior -and $cfg.Behavior.SafePathsStrict -ne $null) { $strict = [bool]$cfg.Behavior.SafePathsStrict } } catch {
        # Configuration access failed - use default strict mode
    }
    try { if ($cfg.Paths -and $cfg.Paths.AllowedWriteDirs) { $allowed = @($cfg.Paths.AllowedWriteDirs) } } catch {
        # Configuration access failed - use empty allowed paths list
    }
    $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    if ([string]::IsNullOrWhiteSpace($Path)) { return (Join-Path $root 'output.txt') }
    try {
        $baseFull = [System.IO.Path]::GetFullPath($root)
        $isAbs = [System.IO.Path]::IsPathRooted($Path)
        if (-not $isAbs) {
            $combined = Join-Path $root $Path
            $full = [System.IO.Path]::GetFullPath($combined)
            if (-not $full.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                return (Join-Path $baseFull ([System.IO.Path]::GetFileName($Path)))
            }
            return $full
        }
        # Absolute path
        $fullAbs = [System.IO.Path]::GetFullPath($Path)
        if ($fullAbs.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $fullAbs }
        if (-not $strict) { return $fullAbs }
        foreach ($dir in $allowed) {
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            # Allowlist entries are relative to base unless absolute
            $dirFull = $(if ([System.IO.Path]::IsPathRooted($dir)) { [System.IO.Path]::GetFullPath($dir) } else { [System.IO.Path]::GetFullPath((Join-Path $root $dir)) })
            if ($fullAbs.StartsWith($dirFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $fullAbs }
        }
        return (Join-Path $baseFull ([System.IO.Path]::GetFileName($Path)))
    } catch {
        return (Join-Path $root ([System.IO.Path]::GetFileName($Path)))
    }
}

function Lock-PmcFile {
    param([string]$file)
    $lockPath = $file + '.lock'
    $maxRetries = 20; $delay = 100
    for ($i=0; $i -lt $maxRetries; $i++) {
        try { return [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) } catch {
            # File lock acquisition failed - will retry
        }
        try { $info = Get-Item $lockPath -ErrorAction SilentlyContinue; if ($info -and ((Get-Date) - $info.LastWriteTime).TotalMinutes -gt 2) { Remove-Item $lockPath -Force -ErrorAction SilentlyContinue } } catch {
            # Stale lock cleanup failed - continue trying
        }
        Start-Sleep -Milliseconds $delay
    }
    throw "Could not acquire lock for $file"
}

function Unlock-PmcFile { param($lock,$file) try { if ($lock) { $lock.Close() } } catch {
        # Lock file close failed - file handle may remain open
    } ; try { Remove-Item ($file + '.lock') -Force -ErrorAction SilentlyContinue } catch {
        # Lock file removal failed - may cause future lock conflicts
    } }

function Invoke-PmcBackupRotation {
    param([string]$file,[int]$count=3)
    # Make backup retention configurable via Behavior.MaxBackups
    try { $cfg=Get-PmcConfig; if ($cfg.Behavior -and $cfg.Behavior.MaxBackups) { $count = [int]$cfg.Behavior.MaxBackups } } catch {
        # Configuration access failed - use default backup count
    }
    for ($i=$count-1; $i -ge 1; $i--) {
        $src = "$file.bak$i"; $dst = "$file.bak$($i+1)"; if (Test-Path $src) { Move-Item -Force $src $dst }
    }
    if (Test-Path $file) { Copy-Item $file "$file.bak1" -Force }
}

function Add-PmcUndoState {
    param([string]$file,[object]$data)
    $undoFile = $file + '.undo'
    $stack = @(); if (Test-Path $undoFile) { try { $stack = Get-Content $undoFile -Raw | ConvertFrom-Json } catch { $stack=@() } }
    $stack += ($data | ConvertTo-Json -Depth 10)
    $max = 10; try { $cfg=Get-PmcConfig; if ($cfg.Behavior -and $cfg.Behavior.MaxUndoLevels) { $max = [int]$cfg.Behavior.MaxUndoLevels } } catch {
        # Configuration access failed - use default undo levels
    }
    if (@($stack).Count -gt $max) { $stack = $stack[-$max..-1] }
    $stack | ConvertTo-Json -Depth 10 | Set-Content $undoFile -Encoding UTF8
}

function Get-PmcUndoRedoStacks {
    param([string]$file)
    $undoFile = $file + '.undo'
    $redoFile = $file + '.redo'
    $undo = @(); $redo = @()
    if (Test-Path $undoFile) { try { $undo = Get-Content $undoFile -Raw | ConvertFrom-Json } catch { $undo=@() } }
    if (Test-Path $redoFile) { try { $redo = Get-Content $redoFile -Raw | ConvertFrom-Json } catch { $redo=@() } }
    return @{ undo=$undo; redo=$redo; undoFile=$undoFile; redoFile=$redoFile }
}

function Save-PmcUndoRedoStacks {
    param([array]$Undo,[array]$Redo,[string]$UndoFile,[string]$RedoFile)
    try { $Undo | ConvertTo-Json -Depth 10 | Set-Content $UndoFile -Encoding UTF8 } catch {
        # Undo stack save failed - undo functionality may be impaired
    }
    try { $Redo | ConvertTo-Json -Depth 10 | Set-Content $RedoFile -Encoding UTF8 } catch {
        # Redo stack save failed - redo functionality may be impaired
    }
}

function Add-PmcActivity {
    param([object]$data,[string]$action)
    if (-not $data.PSObject.Properties['activityLog']) { $data | Add-Member -NotePropertyName activityLog -NotePropertyValue @() -Force }

    # Add new entry
    $data.activityLog += @{ timestamp=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); action=$action; user=$env:USERNAME }

    # Enforce limit IMMEDIATELY to prevent in-memory growth
    $currentCount = @($data.activityLog).Count
    if ($currentCount -gt 1000) {
        $data.activityLog = $data.activityLog[-1000..-1]
    }
}

function Save-PmcData {
    param(
        [Parameter(Mandatory=$true)][object]$data,
        [string]$Action=''
    )

    # CRITICAL FIX: Test-PmcResourceLimits function doesn't exist, causing all saves to fail
    # Commenting out until function is implemented
    # if (-not (Test-PmcResourceLimits)) {
    #     throw "Resource limits exceeded - cannot save data"
    # }

    $cfg = Get-PmcConfig; $whatIf=$false; try { if ($cfg.Behavior -and $cfg.Behavior.WhatIf) { $whatIf = [bool]$cfg.Behavior.WhatIf } } catch {
        # Configuration access failed - whatIf remains false
    }
    if ($whatIf) { Write-Host 'WhatIf: changes not saved' -ForegroundColor DarkYellow; return }

    $file = Get-PmcTaskFilePath

    # Validate file path security
    if (-not (Test-PmcPathSafety -Path $file -Operation 'write')) {
        throw "Path safety validation failed for: $file"
    }

    Write-PmcDebugStorage -Operation 'SaveData' -File $file -Data @{ Action = $Action; WhatIf = $whatIf }

    $lock = $null
    try {
        $lock = Lock-PmcFile $file

        Write-PmcDebugStorage -Operation 'AcquiredLock' -File $file

        Invoke-PmcBackupRotation -file $file -count 3
        Add-PmcUndoEntry -file $file -data $data
        if ($Action) { Add-PmcActivity -data $data -action $Action }

        $tmp = "$file.tmp"

        # Use secure file operation for the actual write
        $jsonContent = $data | ConvertTo-Json -Depth 10

        # CRITICAL: Validate content safety BEFORE writing
        if (-not (Test-PmcInputSafety -Input $jsonContent -InputType 'json')) {
            Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Data content failed safety validation - aborting save"
            throw "Data content failed safety validation - refusing to save potentially unsafe data"
        }

        Invoke-PmcSecureFileOperation -Path $tmp -Operation 'write' -Content $jsonContent

        # Atomic rename operation - if this fails, lock will prevent corruption
        try {
            Move-Item -Force -Path $tmp -Destination $file -ErrorAction Stop
        } catch {
            # If move fails, ensure temp file is cleaned up
            if (Test-Path $tmp) {
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
            throw  # Rethrow to be caught by outer try-catch
        }

        # Verify that the written file is valid JSON
        try {
            $verifyContent = Get-Content $file -Raw -ErrorAction Stop
            $null = $verifyContent | ConvertFrom-Json -ErrorAction Stop
            Write-PmcDebug -Level 3 -Category 'STORAGE' -Message "File verification successful after save"
        } catch {
            Write-PmcDebug -Level 1 -Category 'STORAGE' -Message "WARNING: Saved file failed JSON validation: $_"
            # Try to restore from backup
            if (Test-Path "$file.bak1") {
                Write-PmcDebug -Level 1 -Category 'STORAGE' -Message "Attempting to restore from backup"
                try {
                    Copy-Item "$file.bak1" $file -Force
                    Write-PmcDebug -Level 2 -Category 'STORAGE' -Message "Successfully restored from backup"
                } catch {
                    Write-PmcDebug -Level 1 -Category 'STORAGE' -Message "Failed to restore from backup: $_"
                }
            }
            throw "Saved file validation failed - data may be corrupted"
        }

        Write-PmcDebugStorage -Operation 'SaveCompleted' -File $file -Data @{ Size = $jsonContent.Length }

    } catch {
        Write-PmcDebugStorage -Operation 'SaveFailed' -File $file -Data @{ Error = $_.ToString() }
        Write-Host "Failed to save data: $_" -ForegroundColor Red
        throw
    } finally {
        Unlock-PmcFile $lock $file
    }
}

function Get-PmcDataAlias { return Get-PmcData }

# Alias for backward compatibility - now that Get-PmcData is defined
function Get-PmcAllData {
    return Get-PmcData
}

function Get-PmcNextTaskId {
    param($data)
    try { $ids = @($data.tasks | ForEach-Object { try { [int]$_.id } catch { 0 } }); $max = ($ids | Measure-Object -Maximum).Maximum; return ([int]$max + 1) } catch { return 1 }
}

function Get-PmcNextTimeLogId {
    param($data)
    try { $ids = @($data.timelogs | ForEach-Object { try { [int]$_.id } catch { 0 } }); $max = ($ids | Measure-Object -Maximum).Maximum; return ([int]$max + 1) } catch { return 1 }
}

# Functions will be exported by main module file
# Export-ModuleMember removed to avoid conflicts with main module exports