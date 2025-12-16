# SpeedTUI Data Service - Base service for JSON persistence and CRUD operations

class DataService {
    [string]$DataDirectory
    [string]$BackupDirectory
    [hashtable]$Cache = @{}
    [bool]$EnableCache = $true
    [int]$MaxBackups = 10
    
    DataService([string]$dataDir) {
        $this.DataDirectory = $dataDir
        $this.BackupDirectory = Join-Path $dataDir "Backups"
        $this.EnsureDirectories()
    }
    
    [void] EnsureDirectories() {
        if (-not (Test-Path $this.DataDirectory)) {
            New-Item -ItemType Directory -Path $this.DataDirectory -Force | Out-Null
        }
        
        if (-not (Test-Path $this.BackupDirectory)) {
            New-Item -ItemType Directory -Path $this.BackupDirectory -Force | Out-Null
        }
    }
    
    [string] GetDataFilePath([string]$filename) {
        return Join-Path $this.DataDirectory "$filename.json"
    }
    
    [string] GetBackupFilePath([string]$filename) {
        $timestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss")
        return Join-Path $this.BackupDirectory "${filename}_$timestamp.json"
    }
    
    [hashtable[]] LoadData([string]$filename) {
        $filePath = $this.GetDataFilePath($filename)
        
        # Check cache first
        if ($this.EnableCache -and $this.Cache.ContainsKey($filename)) {
            return $this.Cache[$filename]
        }
        
        if (-not (Test-Path $filePath)) {
            $emptyData = @()
            if ($this.EnableCache) {
                $this.Cache[$filename] = $emptyData
            }
            return $emptyData
        }
        
        try {
            $jsonContent = Get-Content -Path $filePath -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($jsonContent)) {
                $emptyData = @()
                if ($this.EnableCache) {
                    $this.Cache[$filename] = $emptyData
                }
                return $emptyData
            }
            
            $data = $jsonContent | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            
            # Ensure we have an array
            if ($data -is [hashtable]) {
                $data = @($data)
            } elseif ($null -eq $data) {
                $data = @()
            }
            
            if ($this.EnableCache) {
                $this.Cache[$filename] = $data
            }
            
            return $data
        } catch {
            Write-Warning "Failed to load data from $filePath : $_"
            $emptyData = @()
            if ($this.EnableCache) {
                $this.Cache[$filename] = $emptyData
            }
            return $emptyData
        }
    }
    
    [void] SaveData([string]$filename, [hashtable[]]$data) {
        $filePath = $this.GetDataFilePath($filename)
        
        try {
            # Create backup if file exists
            if (Test-Path $filePath) {
                $this.CreateBackup($filename)
            }
            
            # Convert to JSON with proper formatting
            $jsonData = $data | ConvertTo-Json -Depth 10 -Compress:$false
            
            # Write to file with UTF8 encoding
            $jsonData | Out-File -FilePath $filePath -Encoding UTF8 -Force
            
            # Update cache
            if ($this.EnableCache) {
                $this.Cache[$filename] = $data
            }
            
            # Clean old backups
            $this.CleanOldBackups($filename)
            
        } catch {
            Write-Error "Failed to save data to $filePath : $_"
            throw
        }
    }
    
    [void] CreateBackup([string]$filename) {
        $sourceFile = $this.GetDataFilePath($filename)
        
        if (Test-Path $sourceFile) {
            try {
                $backupFile = $this.GetBackupFilePath($filename)
                Copy-Item -Path $sourceFile -Destination $backupFile -Force
            } catch {
                Write-Warning "Failed to create backup for $filename : $_"
            }
        }
    }
    
    [void] CleanOldBackups([string]$filename) {
        try {
            $backupPattern = "${filename}_*.json"
            $backupFiles = Get-ChildItem -Path $this.BackupDirectory -Filter $backupPattern | 
                          Sort-Object LastWriteTime -Descending
            
            if ($backupFiles.Count -gt $this.MaxBackups) {
                $filesToDelete = $backupFiles | Select-Object -Skip $this.MaxBackups
                foreach ($file in $filesToDelete) {
                    Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Warning "Failed to clean old backups for $filename : $_"
        }
    }
    
    [void] ClearCache([string]$filename = "") {
        if ([string]::IsNullOrEmpty($filename)) {
            $this.Cache.Clear()
        } elseif ($this.Cache.ContainsKey($filename)) {
            $this.Cache.Remove($filename)
        }
    }
    
    [hashtable[]] FilterData([hashtable[]]$data, [scriptblock]$filter) {
        if ($null -eq $filter) {
            return $data
        }
        
        return $data | Where-Object $filter
    }
    
    [hashtable[]] SortData([hashtable[]]$data, [string]$property, [bool]$descending = $false) {
        if ([string]::IsNullOrEmpty($property)) {
            return $data
        }
        
        if ($descending) {
            return $data | Sort-Object { $_[$property] } -Descending
        } else {
            return $data | Sort-Object { $_[$property] }
        }
    }
    
    [hashtable] FindById([hashtable[]]$data, [string]$id) {
        return $data | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    }
    
    [int] FindIndexById([hashtable[]]$data, [string]$id) {
        for ($i = 0; $i -lt $data.Count; $i++) {
            if ($data[$i].Id -eq $id) {
                return $i
            }
        }
        return -1
    }
    
    [bool] ExistsById([hashtable[]]$data, [string]$id) {
        return $null -ne ($this.FindById($data, $id))
    }
    
    [hashtable[]] AddItem([hashtable[]]$data, [hashtable]$item) {
        # Ensure the item has required base fields
        if (-not $item.ContainsKey('Id') -or [string]::IsNullOrEmpty($item.Id)) {
            $item.Id = [Guid]::NewGuid().ToString()
        }
        
        if (-not $item.ContainsKey('CreatedAt')) {
            $item.CreatedAt = [DateTime]::Now
        }
        
        if (-not $item.ContainsKey('UpdatedAt')) {
            $item.UpdatedAt = [DateTime]::Now
        }
        
        if (-not $item.ContainsKey('Deleted')) {
            $item.Deleted = $false
        }
        
        # Create new array with the item
        $newData = @($data) + @($item)
        return $newData
    }
    
    [hashtable[]] UpdateItem([hashtable[]]$data, [string]$id, [hashtable]$updates) {
        $index = $this.FindIndexById($data, $id)
        if ($index -eq -1) {
            throw "Item with ID '$id' not found"
        }
        
        # Update the item
        $item = $data[$index]
        foreach ($key in $updates.Keys) {
            $item[$key] = $updates[$key]
        }
        $item.UpdatedAt = [DateTime]::Now
        
        # Return updated array
        return $data
    }
    
    [hashtable[]] DeleteItem([hashtable[]]$data, [string]$id, [bool]$softDelete = $true) {
        $index = $this.FindIndexById($data, $id)
        if ($index -eq -1) {
            throw "Item with ID '$id' not found"
        }
        
        if ($softDelete) {
            # Soft delete - mark as deleted
            $data[$index].Deleted = $true
            $data[$index].UpdatedAt = [DateTime]::Now
            return $data
        } else {
            # Hard delete - remove from array
            $newData = @()
            for ($i = 0; $i -lt $data.Count; $i++) {
                if ($i -ne $index) {
                    $newData += $data[$i]
                }
            }
            return $newData
        }
    }
    
    [hashtable[]] GetActiveItems([hashtable[]]$data) {
        return $data | Where-Object { -not $_.Deleted }
    }
    
    [hashtable[]] SearchItems([hashtable[]]$data, [string]$searchTerm, [string[]]$searchFields) {
        if ([string]::IsNullOrEmpty($searchTerm)) {
            return $data
        }
        
        $results = @()
        $searchTerm = $searchTerm.ToLower()
        
        foreach ($item in $data) {
            $found = $false
            foreach ($field in $searchFields) {
                if ($item.ContainsKey($field) -and $null -ne $item[$field]) {
                    $value = $item[$field].ToString().ToLower()
                    if ($value -like "*$searchTerm*") {
                        $found = $true
                        break
                    }
                }
            }
            
            if ($found) {
                $results += $item
            }
        }
        
        return $results
    }
    
    [hashtable] GetStatistics([hashtable[]]$data) {
        $activeCount = ($data | Where-Object { -not $_.Deleted }).Count
        $deletedCount = ($data | Where-Object { $_.Deleted }).Count
        $totalCount = $data.Count
        
        return @{
            Total = $totalCount
            Active = $activeCount
            Deleted = $deletedCount
            CacheEnabled = $this.EnableCache
            CacheSize = $this.Cache.Count
            LastModified = $(if ($data.Count -gt 0) { 
                ($data | Sort-Object { $_.UpdatedAt } -Descending | Select-Object -First 1).UpdatedAt 
            } else { $null })
        }
    }
}