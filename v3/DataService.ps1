# DataService.ps1 - Clean JSON I/O
using namespace System.Collections.Generic

class DataService {
    [string]$FilePath
    
    DataService([string]$path) {
        $this.FilePath = $path
    }
    
    [hashtable] LoadData() {
        if (-not (Test-Path $this.FilePath)) {
            return @{
                projects = @()
                tasks = @()
                timelogs = @()
                notes = @()
                checklists = @()
                settings = @{}
            }
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
        
        $json = ""
        
        try {
            # Atomic Write Strategy:
            # 1. Write to temp file
            # 2. Backup existing file
            # 3. Move temp to target
            
            $json = $output | ConvertTo-Json -Depth 10
            $tempFile = "$($this.FilePath).tmp"
            $bakFile = "$($this.FilePath).bak"
            
            # 1. Write to temp
            $json | Set-Content -Path $tempFile -Encoding utf8
            
            # 2. Backup existing
            if (Test-Path $this.FilePath) {
                Copy-Item $this.FilePath $bakFile -Force
            }
            
            # 3. Move temp to target (Atomic on POSIX, usually safe on Windows)
            Move-Item -Path $tempFile -Destination $this.FilePath -Force
            
        } catch {
            [Logger]::Log("DataService: Failed to save data - $($_.Exception.Message)")
            # Try to save to emergency file if main save fails
            try {
                $emergencyFile = "$($this.FilePath).emergency.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                $json | Set-Content -Path $emergencyFile
                [Logger]::Log("DataService: Saved to emergency file: $emergencyFile")
            } catch {}
            throw
        }
    }
    
    static [string] NewGuid() {
        return [guid]::NewGuid().ToString()
    }
    
    static [string] Timestamp() {
        return (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")
    }
    
    # Static config methods for PmcThemeManager compatibility
    static [hashtable] LoadConfig() {
        # Config.json is at the app root (parent of v3 folder)
        $configPath = Join-Path $global:PmcAppRoot "config.json"
        
        if (-not (Test-Path $configPath)) {
            return @{}
        }
        
        try {
            $json = Get-Content -Raw $configPath | ConvertFrom-Json
            $config = @{}
            foreach ($prop in $json.PSObject.Properties) {
                $config[$prop.Name] = $prop.Value
            }
            return $config
        } catch {
            return @{}
        }
    }
    
    static [void] SaveConfig([hashtable]$config) {
        $configPath = Join-Path $global:PmcAppRoot "config.json"
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
    }
}