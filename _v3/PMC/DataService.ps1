# DataService.ps1 - Clean JSON I/O with async saving
using namespace System.Collections.Generic

class DataService {
    [string]$FilePath
    [bool]$_isDirty = $false
    [object]$_saveJob = $null
    [System.Collections.Queue]$_saveQueue = [System.Collections.Queue]::new()
    
    DataService([string]$path) {
        $this.FilePath = $path
    }
    
    [hashtable] LoadData() {
        if (-not (Test-Path $this.FilePath)) {
            # Create default data file on first run
            $default = @{
                projects = @()
                tasks = @()
                timelogs = @()
                notes = @()
                checklists = @()
                commands = @()
                settings = @{}
            }
            # Save the default file immediately
            $default | ConvertTo-Json -Depth 10 | Set-Content -Path $this.FilePath -Encoding utf8
            return $default
        }
        
        $json = Get-Content -Raw $this.FilePath | ConvertFrom-Json
        
        # Convert everything to hashtables for internal Flux use
        $data = @{
            projects = @()
            tasks = @()
            timelogs = @()
            notes = @()
            checklists = @()
            settings = @{}
        }

        if ($json.projects) {
            foreach ($p in $json.projects) {
                $h = [hashtable]@{}
                $p.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
                $data.projects += $h
            }
        }

        if ($json.tasks) {
            foreach ($t in $json.tasks) {
                $h = [hashtable]@{}
                $t.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
                $data.tasks += $h
            }
        }

        if ($json.timelogs) {
            foreach ($l in $json.timelogs) {
                $h = [hashtable]@{}
                $l.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
                $data.timelogs += $h
            }
        }

        if ($json.PSObject.Properties['notes'] -and $json.notes) {
            foreach ($n in $json.notes) {
                $h = [hashtable]@{}
                $n.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
                $data.notes += $h
            }
        }

        if ($json.PSObject.Properties['checklists'] -and $json.checklists) {
            foreach ($c in $json.checklists) {
                $h = [hashtable]@{}
                $c.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
                # Convert items array too
                if ($c.PSObject.Properties['items'] -and $c.items) {
                    $h['items'] = @()
                    foreach ($item in $c.items) {
                        $itemH = [hashtable]@{}
                        $item.PSObject.Properties | ForEach-Object { $itemH[$_.Name] = $_.Value }
                        $h['items'] += $itemH
                    }
                }
                $data.checklists += $h
            }
        }

        if ($json.settings) {
            $json.settings.PSObject.Properties | ForEach-Object { $data.settings[$_.Name] = $_.Value }
        }
        
        return $data
    }
    
    [void] SaveData([hashtable]$data) {
        $output = @{
            projects = $data.projects
            tasks = $data.tasks
            timelogs = $data.timelogs
            notes = if ($data.ContainsKey('notes')) { $data.notes } else { @() }
            checklists = if ($data.ContainsKey('checklists')) { $data.checklists } else { @() }
            settings = $data.settings
        }
        
        # Queue data for async save (debouncing)
        $this._saveQueue.Enqueue($output)
        $this._isDirty = $true
        
        # Start async save job with debouncing
        $this._StartDebouncedSave()
    }
    
    hidden [void] _StartDebouncedSave() {
        # If there's already a job running, let it finish
        if ($null -ne $this._saveJob -and $this._saveJob.State -eq 'Running') {
            return
        }
        
        # Clean up completed jobs
        if ($null -ne $this._saveJob -and $this._saveJob.State -eq 'Completed') {
            $this._saveJob = $null
        }
        
        # Start new async job with 500ms debounce
        $script = {
            param($filePath, $queue, $isDirtyRef)
            
            # Wait for debounce period
            Start-Sleep -Milliseconds 500
            
            # Check if there's more data in queue
            $latestData = $null
            while ($queue.Count -gt 0) {
                $latestData = $queue.Dequeue()
            }
            
            if ($null -eq $latestData) {
                return
            }
            
            $json = ""
            try {
                # Atomic Write Strategy
                $json = $latestData | ConvertTo-Json -Depth 10
                $tempFile = "$($filePath).tmp"
                $bakFile = "$($filePath).bak"
                
                # Write to temp
                $json | Set-Content -Path $tempFile -Encoding utf8
                
                # Backup existing
                if (Test-Path $filePath) {
                    Copy-Item $filePath $bakFile -Force
                }
                
                # Move temp to target
                Move-Item -Path $tempFile -Destination $filePath -Force
                
                # Mark as not dirty
                $isDirtyRef.Value = $false
                
            } catch {
                [Logger]::Log("DataService: Failed to save data - $($_.Exception.Message)")
                try {
                    $emergencyFile = "$($filePath).emergency.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    $json | Set-Content -Path $emergencyFile
                    [Logger]::Log("DataService: Saved to emergency file: $emergencyFile")
                } catch {}
            }
        }
        
        # Create reference for isDirty that can be modified in scriptblock
        $isDirtyRef = [ref]$this._isDirty
        
        # Start the job
        $this._saveJob = Start-ThreadJob -ScriptBlock $script -ArgumentList @(
            $this.FilePath,
            $this._saveQueue,
            $isDirtyRef
        ) -ErrorAction SilentlyContinue
    }
    
    [bool] FlushPendingSaves() {
        # Force immediate save of any pending changes
        if (-not $this._isDirty) {
            return $true
        }
        
        # Wait for any pending job to complete
        if ($null -ne $this._saveJob -and $this._saveJob.State -eq 'Running') {
            $this._saveJob | Wait-Job | Out-Null
        }
        
        return -not $this._isDirty
    }
    
    hidden [void] _PerformSyncSave([hashtable]$output) {
        $json = ""
        try {
            $json = $output | ConvertTo-Json -Depth 10
            $tempFile = "$($this.FilePath).tmp"
            $bakFile = "$($this.FilePath).bak"
            
            $json | Set-Content -Path $tempFile -Encoding utf8
            
            if (Test-Path $this.FilePath) {
                Copy-Item $this.FilePath $bakFile -Force
            }
            
            Move-Item -Path $tempFile -Destination $this.FilePath -Force
            
        } catch {
            [Logger]::Log("DataService: Failed to save data - $($_.Exception.Message)")
            try {
                $emergencyFile = "$($this.FilePath).emergency.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                $json | Set-Content -Path $emergencyFile
                [Logger]::Log("DataService: Saved to emergency file: $emergencyFile")
            } catch {}
        }
    }
    
    static [string] NewGuid() {
        return [guid]::NewGuid().ToString()
    }
    
    static [string] Timestamp() {
        return (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")
    }
}