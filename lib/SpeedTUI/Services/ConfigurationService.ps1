# SpeedTUI ConfigurationService - Application settings and configuration management

# Load dependencies
if (-not ([System.Management.Automation.PSTypeName]'DataService').Type) {
    . "$PSScriptRoot/DataService.ps1"
}

class ConfigurationService : DataService {
    [hashtable]$Settings = @{}
    [hashtable]$DefaultSettings = @{}
    [string]$FileName = "config"
    [bool]$AutoSave = $true
    [string]$ConfigVersion = "1.0"
    
    ConfigurationService() : base("_ProjectData") {
        Write-Host "ConfigurationService initialized"
        $this.InitializeDefaultSettings()
        $this.LoadConfiguration()
    }
    
    # =============================================================================
    # INITIALIZATION
    # =============================================================================
    
    [void] InitializeDefaultSettings() {
        $this.DefaultSettings = @{
            # Application Settings
            Application = @{
                Name = "SpeedTUI"
                Version = "1.0.0"
                StartupMode = "Dashboard"  # Dashboard, LastScreen, Custom
                AutoSave = $true
                LogLevel = "Info"          # Debug, Info, Warning, Error
                MaxLogFiles = 10
                BackupRetention = 30       # Days
                RefreshInterval = 5000     # Milliseconds
            }
            
            # UI Settings
            UI = @{
                Theme = "Default"
                ShowBorders = $true
                ShowStatusBar = $true
                ShowToolbar = $true
                WindowTitle = "SpeedTUI - PowerShell Terminal Interface"
                DefaultWidth = 120
                DefaultHeight = 30
                FullScreen = $false
                ShowLineNumbers = $true
                WordWrap = $true
                HighlightCurrentLine = $true
            }
            
            # Colors and Themes
            Colors = @{
                Background = "Black"
                Foreground = "White"
                Border = "Gray"
                Selection = "Blue"
                Error = "Red"
                Warning = "Yellow"
                Success = "Green"
                Info = "Cyan"
                Header = "Magenta"
                Accent = "DarkBlue"
            }
            
            # Editor Settings
            Editor = @{
                TabSize = 4
                UseTabs = $false
                AutoIndent = $true
                ShowWhitespace = $false
                LineEndings = "CRLF"       # CRLF, LF, CR
                Encoding = "UTF8"
                AutoComplete = $true
                BracketMatching = $true
                SyntaxHighlighting = $true
            }
            
            # Time Tracking Settings
            TimeTracking = @{
                DefaultHoursPerDay = 8.0
                FiscalYearStart = "April"  # Month name
                WeekStartDay = "Monday"    # Monday, Sunday
                RoundingMinutes = 15       # Round to nearest 15 minutes
                ShowWeekends = $false
                AutoCalculateTotal = $true
                RequireProjectCode = $true
                ValidateTimeEntries = $true
            }
            
            # Command Settings
            Commands = @{
                MaxRecentCommands = 20
                ShowUsageCount = $true
                GroupByCategory = $true
                DefaultLanguage = "PowerShell"
                AutoCreateBackups = $true
                ShowFavorites = $true
                EnableTemplates = $true
                CacheSearchResults = $true
            }
            
            # File Management
            Files = @{
                DefaultDirectory = "_ProjectData"
                BackupDirectory = "Backups"
                MaxBackups = 10
                AutoBackup = $true
                BackupInterval = 24        # Hours
                CompressBackups = $true
                ShowHiddenFiles = $false
            }
            
            # Network Settings
            Network = @{
                EnableUpdates = $true
                UpdateCheckInterval = 7    # Days
                ProxyEnabled = $false
                ProxyServer = ""
                ProxyPort = 8080
                ProxyAuth = $false
                ProxyUsername = ""
                Timeout = 30               # Seconds
            }
            
            # Keyboard Shortcuts
            Shortcuts = @{
                Save = "Ctrl+S"
                Open = "Ctrl+O"
                New = "Ctrl+N"
                Exit = "Ctrl+Q"
                Search = "Ctrl+F"
                Replace = "Ctrl+H"
                Undo = "Ctrl+Z"
                Redo = "Ctrl+Y"
                Cut = "Ctrl+X"
                Copy = "Ctrl+C"
                Paste = "Ctrl+V"
                SelectAll = "Ctrl+A"
                ToggleFullScreen = "F11"
                ShowHelp = "F1"
                QuickCommand = "Ctrl+Shift+P"
                TimeEntry = "Ctrl+T"
            }
            
            # Recent Items
            Recent = @{
                MaxFiles = 10
                MaxProjects = 10
                MaxCommands = 20
                MaxSearches = 15
                ClearOnExit = $false
            }
            
            # Advanced Settings
            Advanced = @{
                EnableDebugMode = $false
                ShowPerformanceMetrics = $false
                EnableTelemetry = $false
                CacheSize = 100            # MB
                MaxUndoLevels = 50
                AutoRecovery = $true
                RecoveryInterval = 300     # Seconds
                ThreadPoolSize = 4
            }
        }
    }
    
    # =============================================================================
    # CONFIGURATION LOADING AND SAVING
    # =============================================================================
    
    [void] LoadConfiguration() {
        try {
            $configData = $this.LoadData($this.FileName)
            
            if ($configData -and $configData.Count -gt 0) {
                # Load existing configuration
                $config = $configData[0]  # Configuration is stored as single object
                
                # Merge with defaults (in case new settings were added)
                $this.Settings = $this.MergeSettings($this.DefaultSettings, $config)
                
                Write-Host "Configuration loaded successfully"
            } else {
                # Use defaults for first time
                $this.Settings = $this.DefaultSettings.Clone()
                $this.SaveConfiguration()
                Write-Host "Default configuration created"
            }
        } catch {
            Write-Host "Error loading configuration, using defaults: $($_.Exception.Message)"
            $this.Settings = $this.DefaultSettings.Clone()
        }
    }
    
    [void] SaveConfiguration() {
        try {
            # Add metadata
            $configWithMeta = $this.Settings.Clone()
            $configWithMeta._metadata = @{
                Version = $this.ConfigVersion
                LastModified = [DateTime]::Now
                Application = "SpeedTUI"
            }
            
            # Save as single configuration object
            $configArray = @($configWithMeta)
            $this.SaveData($this.FileName, $configArray)
            
            Write-Host "Configuration saved successfully"
        } catch {
            Write-Host "Error saving configuration: $($_.Exception.Message)"
        }
    }
    
    [hashtable] MergeSettings([hashtable]$defaults, [hashtable]$current) {
        $merged = @{}
        
        # Start with defaults
        foreach ($key in $defaults.Keys) {
            if ($defaults[$key] -is [hashtable]) {
                if ($current.ContainsKey($key) -and $current[$key] -is [hashtable]) {
                    $merged[$key] = $this.MergeSettings($defaults[$key], $current[$key])
                } else {
                    $merged[$key] = $defaults[$key].Clone()
                }
            } else {
                if ($current.ContainsKey($key)) {
                    $merged[$key] = $current[$key]
                } else {
                    $merged[$key] = $defaults[$key]
                }
            }
        }
        
        # Add any additional settings from current that aren't in defaults
        foreach ($key in $current.Keys) {
            if (-not $merged.ContainsKey($key) -and $key -ne "_metadata") {
                $merged[$key] = $current[$key]
            }
        }
        
        return $merged
    }
    
    # =============================================================================
    # SETTING MANAGEMENT
    # =============================================================================
    
    [object] GetSetting([string]$path) {
        $pathParts = $path.Split('.')
        $current = $this.Settings
        
        foreach ($part in $pathParts) {
            if ($current -is [hashtable] -and $current.ContainsKey($part)) {
                $current = $current[$part]
            } else {
                return $null
            }
        }
        
        return $current
    }
    
    [void] SetSetting([string]$path, [object]$value) {
        $pathParts = $path.Split('.')
        $current = $this.Settings
        
        # Navigate to parent
        for ($i = 0; $i -lt ($pathParts.Count - 1); $i++) {
            $part = $pathParts[$i]
            if (-not $current.ContainsKey($part)) {
                $current[$part] = @{}
            }
            $current = $current[$part]
        }
        
        # Set the value
        $finalKey = $pathParts[-1]
        $current[$finalKey] = $value
        
        if ($this.AutoSave) {
            $this.SaveConfiguration()
        }
        
        Write-Host "Setting updated: $path = $value"
    }
    
    [bool] HasSetting([string]$path) {
        return $null -ne $this.GetSetting($path)
    }
    
    [void] RemoveSetting([string]$path) {
        $pathParts = $path.Split('.')
        $current = $this.Settings
        
        # Navigate to parent
        for ($i = 0; $i -lt ($pathParts.Count - 1); $i++) {
            $part = $pathParts[$i]
            if ($current -is [hashtable] -and $current.ContainsKey($part)) {
                $current = $current[$part]
            } else {
                return  # Path doesn't exist
            }
        }
        
        # Remove the key
        $finalKey = $pathParts[-1]
        if ($current -is [hashtable] -and $current.ContainsKey($finalKey)) {
            $current.Remove($finalKey)
            
            if ($this.AutoSave) {
                $this.SaveConfiguration()
            }
            
            Write-Host "Setting removed: $path"
        }
    }
    
    [hashtable] GetSection([string]$section) {
        $result = $this.GetSetting($section)
        return $(if ($result -is [hashtable]) { $result } else { @{} })
    }
    
    [void] SetSection([string]$section, [hashtable]$values) {
        $this.SetSetting($section, $values)
    }
    
    # =============================================================================
    # THEME MANAGEMENT
    # =============================================================================
    
    [string] GetCurrentTheme() {
        return $this.GetSetting("UI.Theme")
    }
    
    [void] SetTheme([string]$themeName) {
        $this.SetSetting("UI.Theme", $themeName)
    }
    
    [hashtable] GetThemeColors() {
        return $this.GetSection("Colors")
    }
    
    [void] SetThemeColor([string]$colorName, [string]$colorValue) {
        $this.SetSetting("Colors.$colorName", $colorValue)
    }
    
    [hashtable] CreateCustomTheme([string]$name, [hashtable]$colors) {
        $themePath = "Themes.$name"
        $this.SetSetting($themePath, $colors)
        return $colors
    }
    
    [string[]] GetAvailableThemes() {
        $themes = @("Default", "Dark", "Light", "HighContrast")
        
        # Add custom themes
        $customThemes = $this.GetSection("Themes")
        foreach ($theme in $customThemes.Keys) {
            $themes += $theme
        }
        
        return $themes
    }
    
    # =============================================================================
    # SHORTCUT MANAGEMENT
    # =============================================================================
    
    [string] GetShortcut([string]$action) {
        return $this.GetSetting("Shortcuts.$action")
    }
    
    [void] SetShortcut([string]$action, [string]$keyCombo) {
        $this.SetSetting("Shortcuts.$action", $keyCombo)
    }
    
    [hashtable] GetAllShortcuts() {
        return $this.GetSection("Shortcuts")
    }
    
    [void] ResetShortcuts() {
        $defaultShortcuts = $this.DefaultSettings.Shortcuts
        $this.SetSection("Shortcuts", $defaultShortcuts)
    }
    
    [bool] IsShortcutInUse([string]$keyCombo) {
        $shortcuts = $this.GetAllShortcuts()
        foreach ($action in $shortcuts.Keys) {
            if ($shortcuts[$action] -eq $keyCombo) {
                return $true
            }
        }
        return $false
    }
    
    # =============================================================================
    # RECENT ITEMS MANAGEMENT
    # =============================================================================
    
    [void] AddRecentFile([string]$filePath) {
        $recentFiles = $this.GetRecentFiles()
        
        # Remove if already exists
        $recentFiles = $recentFiles | Where-Object { $_ -ne $filePath }
        
        # Add to beginning
        $recentFiles = @($filePath) + $recentFiles
        
        # Limit to max count
        $maxFiles = $this.GetSetting("Recent.MaxFiles")
        if ($recentFiles.Count -gt $maxFiles) {
            $recentFiles = $recentFiles[0..($maxFiles - 1)]
        }
        
        $this.SetSetting("Recent.Files", $recentFiles)
    }
    
    [string[]] GetRecentFiles() {
        $recent = $this.GetSetting("Recent.Files")
        return $(if ($recent) { $recent } else { @() })
    }
    
    [void] ClearRecentFiles() {
        $this.SetSetting("Recent.Files", @())
    }
    
    [void] AddRecentProject([string]$projectId) {
        $recentProjects = $this.GetRecentProjects()
        
        # Remove if already exists
        $recentProjects = $recentProjects | Where-Object { $_ -ne $projectId }
        
        # Add to beginning
        $recentProjects = @($projectId) + $recentProjects
        
        # Limit to max count
        $maxProjects = $this.GetSetting("Recent.MaxProjects")
        if ($recentProjects.Count -gt $maxProjects) {
            $recentProjects = $recentProjects[0..($maxProjects - 1)]
        }
        
        $this.SetSetting("Recent.Projects", $recentProjects)
    }
    
    [string[]] GetRecentProjects() {
        $recent = $this.GetSetting("Recent.Projects")
        return $(if ($recent) { $recent } else { @() })
    }
    
    [void] AddRecentSearch([string]$searchTerm) {
        $recentSearches = $this.GetRecentSearches()
        
        # Remove if already exists
        $recentSearches = $recentSearches | Where-Object { $_ -ne $searchTerm }
        
        # Add to beginning
        $recentSearches = @($searchTerm) + $recentSearches
        
        # Limit to max count
        $maxSearches = $this.GetSetting("Recent.MaxSearches")
        if ($recentSearches.Count -gt $maxSearches) {
            $recentSearches = $recentSearches[0..($maxSearches - 1)]
        }
        
        $this.SetSetting("Recent.Searches", $recentSearches)
    }
    
    [string[]] GetRecentSearches() {
        $recent = $this.GetSetting("Recent.Searches")
        return $(if ($recent) { $recent } else { @() })
    }
    
    # =============================================================================
    # VALIDATION AND RESET
    # =============================================================================
    
    [bool] ValidateConfiguration() {
        try {
            # Check required sections exist
            $requiredSections = @("Application", "UI", "Colors", "Editor")
            foreach ($section in $requiredSections) {
                if (-not $this.HasSetting($section)) {
                    Write-Host "Missing required section: $section"
                    return $false
                }
            }
            
            # Validate specific settings
            $logLevel = $this.GetSetting("Application.LogLevel")
            $validLogLevels = @("Debug", "Info", "Warning", "Error")
            if ($logLevel -notin $validLogLevels) {
                Write-Host "Invalid log level: $logLevel"
                return $false
            }
            
            $theme = $this.GetSetting("UI.Theme")
            if ([string]::IsNullOrEmpty($theme)) {
                Write-Host "Theme not specified"
                return $false
            }
            
            Write-Host "Configuration validation passed"
            return $true
        } catch {
            Write-Host "Configuration validation failed: $($_.Exception.Message)"
            return $false
        }
    }
    
    [void] ResetToDefaults() {
        Write-Host "Resetting configuration to defaults"
        $this.Settings = $this.DefaultSettings.Clone()
        $this.SaveConfiguration()
    }
    
    [void] ResetSection([string]$section) {
        if ($this.DefaultSettings.ContainsKey($section)) {
            $this.SetSection($section, $this.DefaultSettings[$section])
            Write-Host "Reset section to defaults: $section"
        } else {
            Write-Host "Unknown section: $section"
        }
    }
    
    # =============================================================================
    # IMPORT/EXPORT
    # =============================================================================
    
    [hashtable] ExportConfiguration() {
        $exportData = @{
            Version = $this.ConfigVersion
            ExportDate = [DateTime]::Now
            Settings = $this.Settings
        }
        
        Write-Host "Configuration exported"
        return $exportData
    }
    
    [void] ImportConfiguration([hashtable]$configData) {
        try {
            if ($configData.ContainsKey("Settings")) {
                $this.Settings = $this.MergeSettings($this.DefaultSettings, $configData.Settings)
                $this.SaveConfiguration()
                Write-Host "Configuration imported successfully"
            } else {
                Write-Host "Invalid configuration data"
            }
        } catch {
            Write-Host "Error importing configuration: $($_.Exception.Message)"
        }
    }
    
    [void] BackupConfiguration() {
        try {
            $backupData = $this.ExportConfiguration()
            $timestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss")
            $backupFileName = "config_backup_$timestamp"
            
            $backupArray = @($backupData)
            $this.SaveData($backupFileName, $backupArray)
            
            Write-Host "Configuration backed up as: $backupFileName"
        } catch {
            Write-Host "Error backing up configuration: $($_.Exception.Message)"
        }
    }
    
    # =============================================================================
    # UTILITY METHODS
    # =============================================================================
    
    [hashtable] GetAllSettings() {
        return $this.Settings
    }
    
    [string] GetConfigurationSummary() {
        $summary = @()
        $summary += "SpeedTUI Configuration Summary"
        $summary += "================================"
        $summary += "Version: $($this.ConfigVersion)"
        $summary += "Theme: $($this.GetSetting('UI.Theme'))"
        $summary += "Log Level: $($this.GetSetting('Application.LogLevel'))"
        $summary += "Auto Save: $($this.GetSetting('Application.AutoSave'))"
        $summary += "Default Directory: $($this.GetSetting('Files.DefaultDirectory'))"
        $summary += "Recent Files: $($this.GetRecentFiles().Count)"
        $summary += "Recent Projects: $($this.GetRecentProjects().Count)"
        $summary += ""
        $summary += "Sections:"
        foreach ($section in $this.Settings.Keys | Sort-Object) {
            if ($section -ne "_metadata") {
                $count = $(if ($this.Settings[$section] -is [hashtable]) { 
                    $this.Settings[$section].Keys.Count 
                } else { 
                    1 
                })
                $summary += "  $section ($count settings)"
            }
        }
        
        return $summary -join "`n"
    }
    
    [void] EnableDebugMode() {
        $this.SetSetting("Advanced.EnableDebugMode", $true)
        $this.SetSetting("Application.LogLevel", "Debug")
        Write-Host "Debug mode enabled"
    }
    
    [void] DisableDebugMode() {
        $this.SetSetting("Advanced.EnableDebugMode", $false)
        $this.SetSetting("Application.LogLevel", "Info")
        Write-Host "Debug mode disabled"
    }
    
    [bool] IsDebugMode() {
        return $this.GetSetting("Advanced.EnableDebugMode")
    }
    
    [void] ToggleAutoSave() {
        $current = $this.GetSetting("Application.AutoSave")
        $this.SetSetting("Application.AutoSave", -not $current)
        Write-Host "Auto save: $(-not $current)"
    }
    
    # =============================================================================
    # CONFIGURATION PRESETS
    # =============================================================================
    
    [void] LoadDeveloperPreset() {
        Write-Host "Loading developer preset"
        $this.SetSetting("Advanced.EnableDebugMode", $true)
        $this.SetSetting("Application.LogLevel", "Debug")
        $this.SetSetting("UI.ShowLineNumbers", $true)
        $this.SetSetting("Editor.SyntaxHighlighting", $true)
        $this.SetSetting("Editor.AutoComplete", $true)
        $this.SetSetting("Commands.ShowUsageCount", $true)
        $this.SetSetting("Advanced.ShowPerformanceMetrics", $true)
    }
    
    [void] LoadProductionPreset() {
        Write-Host "Loading production preset"
        $this.SetSetting("Advanced.EnableDebugMode", $false)
        $this.SetSetting("Application.LogLevel", "Warning")
        $this.SetSetting("Advanced.EnableTelemetry", $false)
        $this.SetSetting("Network.EnableUpdates", $false)
        $this.SetSetting("Files.AutoBackup", $true)
        $this.SetSetting("Application.AutoSave", $true)
    }
    
    [void] LoadMinimalPreset() {
        Write-Host "Loading minimal preset"
        $this.SetSetting("UI.ShowBorders", $false)
        $this.SetSetting("UI.ShowStatusBar", $false)
        $this.SetSetting("UI.ShowToolbar", $false)
        $this.SetSetting("Editor.ShowWhitespace", $false)
        $this.SetSetting("Commands.ShowUsageCount", $false)
        $this.SetSetting("Advanced.ShowPerformanceMetrics", $false)
    }
}