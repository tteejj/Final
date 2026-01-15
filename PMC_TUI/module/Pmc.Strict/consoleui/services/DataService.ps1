# DataService.ps1 - Direct file I/O for consoleui (no module dependency)
# Reads/writes tasks.json and config.json directly

Set-StrictMode -Version Latest

class DataService {
    static [string] $_dataFilePath = $null
    static [string] $_configFilePath = $null
    static [string] $_appRoot = $null

    # Get application root directory
    static [string] GetAppRoot() {
        if ([DataService]::_appRoot) {
            return [DataService]::_appRoot
        }
        
        # Derive from $global:PmcAppRoot if set, or from script location
        if ($global:PmcAppRoot) {
            [DataService]::_appRoot = $global:PmcAppRoot
        } else {
            # Go up from consoleui/services to workspace root
            $scriptDir = $PSScriptRoot
            if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
            [DataService]::_appRoot = Split-Path (Split-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) -Parent) -Parent
        }
        return [DataService]::_appRoot
    }

    # Get path to tasks.json
    static [string] GetDataFilePath() {
        if ([DataService]::_dataFilePath) {
            return [DataService]::_dataFilePath
        }
        
        $root = [DataService]::GetAppRoot()
        [DataService]::_dataFilePath = Join-Path $root 'data/tasks.json'
        return [DataService]::_dataFilePath
    }

    # Get path to config.json  
    static [string] GetConfigFilePath() {
        if ([DataService]::_configFilePath) {
            return [DataService]::_configFilePath
        }
        
        $root = [DataService]::GetAppRoot()
        [DataService]::_configFilePath = Join-Path $root 'config.json'
        return [DataService]::_configFilePath
    }

    # Load all data from tasks.json
    static [hashtable] LoadData() {
        $file = [DataService]::GetDataFilePath()
        
        # Initialize empty data structure
        $emptyData = @{
            tasks = @()
            projects = @(@{
                name = 'inbox'
                description = 'Default inbox'
                aliases = @()
                created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            })
            timelogs = @()
            settings = @{}
        }
        
        # Create file if doesn't exist
        if (-not (Test-Path $file)) {
            $dir = Split-Path $file -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $emptyData | ConvertTo-Json -Depth 10 | Set-Content -Path $file -Encoding UTF8
            return $emptyData
        }
        
        # Read file
        try {
            $json = Get-Content -Path $file -Raw -Encoding UTF8
            $data = $json | ConvertFrom-Json
            
            # Convert to hashtable
            $result = @{
                tasks = @()
                projects = @()
                timelogs = @()
                settings = @{}
            }
            
            if ($data.tasks) {
                foreach ($item in $data.tasks) {
                    if ($item -is [hashtable]) {
                        $result.tasks += $item
                    } else {
                        $hash = @{}
                        foreach ($prop in $item.PSObject.Properties) {
                            $hash[$prop.Name] = $prop.Value
                        }
                        $result.tasks += $hash
                    }
                }
            }
            
            if ($data.projects) {
                foreach ($item in $data.projects) {
                    if ($item -is [hashtable]) {
                        $result.projects += $item
                    } else {
                        $hash = @{}
                        foreach ($prop in $item.PSObject.Properties) {
                            $hash[$prop.Name] = $prop.Value
                        }
                        $result.projects += $hash
                    }
                }
            }
            
            if ($data.timelogs) {
                foreach ($item in $data.timelogs) {
                    if ($item -is [hashtable]) {
                        $result.timelogs += $item
                    } else {
                        $hash = @{}
                        foreach ($prop in $item.PSObject.Properties) {
                            $hash[$prop.Name] = $prop.Value
                        }
                        $result.timelogs += $hash
                    }
                }
            }
            
            if ($data.settings) {
                if ($data.settings -is [hashtable]) {
                    $result.settings = $data.settings
                } else {
                    foreach ($prop in $data.settings.PSObject.Properties) {
                        $result.settings[$prop.Name] = $prop.Value
                    }
                }
            }
            
            return $result
        }
        catch {
            # Try backup files
            for ($i = 1; $i -le 5; $i++) {
                $backup = "$file.backup.*" | Get-ChildItem -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($backup) {
                    try {
                        $json = Get-Content -Path $backup.FullName -Raw -Encoding UTF8
                        $data = $json | ConvertFrom-Json
                        # Return basic structure - recovery mode
                        return @{
                            tasks = @($data.tasks)
                            projects = @($data.projects)
                            timelogs = @($data.timelogs)
                            settings = @{}
                        }
                    } catch {
                        continue
                    }
                }
            }
            
            # Return empty data as last resort
            return $emptyData
        }
    }

    # Save all data to tasks.json (atomic write)
    static [void] SaveData([hashtable]$data) {
        $file = [DataService]::GetDataFilePath()
        $dir = Split-Path $file -Parent
        
        # Ensure directory exists
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        
        # Create backup before writing
        if (Test-Path $file) {
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $backupFile = "$file.backup.$timestamp"
            Copy-Item -Path $file -Destination $backupFile -Force -ErrorAction SilentlyContinue
            
            # Keep only last 5 backups
            Get-ChildItem -Path "$file.backup.*" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -Skip 5 |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
        
        # Atomic write: write to temp, then rename
        $tempFile = "$file.tmp"
        try {
            $json = $data | ConvertTo-Json -Depth 10
            $json | Set-Content -Path $tempFile -Encoding UTF8 -Force
            
            # Verify temp file is valid JSON
            $verify = Get-Content -Path $tempFile -Raw | ConvertFrom-Json
            if (-not $verify) {
                throw "Verification failed"
            }
            
            # Atomic rename
            Move-Item -Path $tempFile -Destination $file -Force
        }
        catch {
            # Cleanup temp file on failure
            if (Test-Path $tempFile) {
                Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            }
            throw "Failed to save data: $_"
        }
    }

    # Load config.json
    static [hashtable] LoadConfig() {
        $file = [DataService]::GetConfigFilePath()
        
        if (-not (Test-Path $file)) {
            return @{}
        }
        
        try {
            $json = Get-Content -Path $file -Raw -Encoding UTF8
            $config = $json | ConvertFrom-Json
            
            # Convert to hashtable
            $result = @{}
            foreach ($prop in $config.PSObject.Properties) {
                $result[$prop.Name] = $prop.Value
            }
            return $result
        }
        catch {
            return @{}
        }
    }

    # Save config.json
    static [void] SaveConfig([hashtable]$config) {
        $file = [DataService]::GetConfigFilePath()
        $json = $config | ConvertTo-Json -Depth 10
        $json | Set-Content -Path $file -Encoding UTF8
    }

    # Get active theme name from config
    static [string] GetActiveTheme() {
        $config = [DataService]::LoadConfig()
        if ($config.Display -and $config.Display.Theme -and $config.Display.Theme.Active) {
            return $config.Display.Theme.Active
        }
        return 'default'
    }

    # Set active theme in config
    static [void] SetActiveTheme([string]$themeName) {
        $config = [DataService]::LoadConfig()
        
        if (-not $config.ContainsKey('Display')) {
            $config['Display'] = @{}
        }
        if ($config.Display -isnot [hashtable]) {
            $displayHash = @{}
            foreach ($prop in $config.Display.PSObject.Properties) {
                $displayHash[$prop.Name] = $prop.Value
            }
            $config['Display'] = $displayHash
        }
        
        if (-not $config.Display.ContainsKey('Theme')) {
            $config.Display['Theme'] = @{}
        }
        if ($config.Display.Theme -isnot [hashtable]) {
            $themeHash = @{}
            foreach ($prop in $config.Display.Theme.PSObject.Properties) {
                $themeHash[$prop.Name] = $prop.Value
            }
            $config.Display['Theme'] = $themeHash
        }
        
        $config.Display.Theme['Active'] = $themeName.ToLower()
        [DataService]::SaveConfig($config)
    }
}
