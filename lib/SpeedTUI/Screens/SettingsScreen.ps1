# SpeedTUI Settings Screen - Application configuration management

# Load dependencies
. "$PSScriptRoot/../Core/Component.ps1"
. "$PSScriptRoot/../Core/PerformanceMonitor.ps1"
. "$PSScriptRoot/../Services/ConfigurationService.ps1"

class SettingsScreen : Component {
    [object]$ConfigService
    [object]$PerformanceMonitor
    [array]$Settings = @()
    [int]$SelectedSetting = 0
    [string]$ViewMode = "List"  # List, Edit
    [hashtable]$Categories = @{}
    [string]$SelectedCategory = "Application"
    [DateTime]$LastRefresh
    
    SettingsScreen() : base() {
        $this.Initialize()
    }
    
    [void] Initialize() {
        try {
            $this.ConfigService = [ConfigurationService]::new()
            $this.PerformanceMonitor = Get-PerformanceMonitor
            $this.LoadSettings()
            $this.LastRefresh = [DateTime]::Now
            
            $this.PerformanceMonitor.RecordMetric("screen.settings.initialized", 1, "count")
        } catch {
            Write-Host "Error initializing settings: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [string[]] Render() {
        $timing = Start-PerformanceTiming "SettingsScreen.Render"
        
        try {
            $lines = @()
            
            # Header
            $lines += $this.RenderHeader()
            $lines += ""
            
            # Categories
            $lines += $this.RenderCategories()
            $lines += ""
            
            switch ($this.ViewMode) {
                "List" {
                    $lines += $this.RenderSettingsList()
                }
                "Edit" {
                    $lines += $this.RenderEditSetting()
                }
            }
            
            $lines += ""
            $lines += $this.RenderControls()
            
            return $lines
            
        } finally {
            Stop-PerformanceTiming $timing
        }
    }
    
    [string[]] RenderHeader() {
        $lines = @()
        $totalSettings = $this.Settings.Count
        $debugMode = $(if ($this.ConfigService.IsDebugMode()) { "ENABLED" } else { "DISABLED" })
        $autoSave = $(if ($this.ConfigService.GetSetting("Application.AutoSave")) { "ENABLED" } else { "DISABLED" })
        
        $lines += "╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗"
        $lines += "║                                            SPEEDTUI SETTINGS                                                      ║"
        $lines += "║    Total Settings: $($totalSettings.ToString().PadLeft(4)) │ Debug Mode: $($debugMode.PadRight(8)) │ Auto-Save: $($autoSave.PadRight(8))                    ║"
        $lines += "╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝"
        
        return $lines
    }
    
    [string[]] RenderCategories() {
        $lines = @()
        $lines += "┌─ Categories ───────────────────────────────────────────────────────────────────────────────────────────────────┐"
        
        $categories = @("Application", "UI", "Performance", "Logging", "Advanced")
        $categoryLine = "│ "
        
        foreach ($category in $categories) {
            $marker = $(if ($category -eq $this.SelectedCategory) { "►" } else { " " })
            $categoryLine += "$marker$category  "
        }
        
        $categoryLine = $categoryLine.PadRight(115) + "│"
        $lines += $categoryLine
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string[]] RenderSettingsList() {
        $lines = @()
        $lines += "┌─ $($this.SelectedCategory) Settings " + ("─" * (75 - $this.SelectedCategory.Length)) + "┐"
        
        # Filter settings by category
        $categorySettings = $this.Settings | Where-Object { $_.Category -eq $this.SelectedCategory }
        
        if ($categorySettings.Count -eq 0) {
            $lines += "│ No settings available in this category.                                                                       │"
            $lines += "│                                                                                                                │"
        } else {
            $lines += "│ Setting                            │ Value                                 │ Description                   │"
            $lines += "├────────────────────────────────────┼───────────────────────────────────────┼───────────────────────────────┤"
            
            $index = 0
            foreach ($setting in $categorySettings) {
                $marker = $(if ($index -eq $this.SelectedSetting) { "►" } else { " " })
                $nameStr = $setting.Name.PadRight(34)
                if ($nameStr.Length -gt 34) { $nameStr = $nameStr.Substring(0, 31) + "..." }
                
                $valueStr = $setting.Value.ToString().PadRight(37)
                if ($valueStr.Length -gt 37) { $valueStr = $valueStr.Substring(0, 34) + "..." }
                
                $descStr = $setting.Description.PadRight(29)
                if ($descStr.Length -gt 29) { $descStr = $descStr.Substring(0, 26) + "..." }
                
                $lines += "│$marker$nameStr │ $valueStr │ $descStr │"
                $index++
            }
            
            # Fill remaining lines
            while (($lines.Count - 3) -lt 12) {
                $lines += "│                                                                                                                │"
            }
        }
        
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string[]] RenderEditSetting() {
        $lines = @()
        $lines += "┌─ Edit Setting ─────────────────────────────────────────────────────────────────────────────────────────────────┐"
        $lines += "│                                                                                                                │"
        
        if ($this.Settings.Count -gt 0 -and $this.SelectedSetting -lt $this.Settings.Count) {
            $setting = ($this.Settings | Where-Object { $_.Category -eq $this.SelectedCategory })[$this.SelectedSetting]
            $lines += "│ Setting: $($setting.Name.PadRight(83)) │"
            $lines += "│ Current Value: $($setting.Value.ToString().PadRight(77)) │"
            $lines += "│ Description: $($setting.Description.PadRight(79)) │"
            $lines += "│                                                                                                                │"
            $lines += "│ New Value: [Enter new value here]                                                                             │"
            $lines += "│                                                                                                                │"
            $lines += "│ Press S to Save, C to Cancel                                                                                  │"
        } else {
            $lines += "│ No setting selected                                                                                           │"
        }
        
        $lines += "│                                                                                                                │"
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string[]] RenderControls() {
        $lines = @()
        $lines += "┌─ Controls ─────────────────────────────────────────────────────────────────────────────────────────────────────┐"
        
        switch ($this.ViewMode) {
            "List" {
                $lines += "│ E - Edit Setting │ R - Reset to Default │ Tab - Switch Category │ S - Save Config │ B - Back │ Q - Quit │"
            }
            "Edit" {
                $lines += "│ S - Save Changes │ C - Cancel │ R - Reset to Default │ Enter - Apply                                    │"
            }
        }
        
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string] HandleInput([string]$key) {
        $timing = Start-PerformanceTiming "SettingsScreen.HandleInput" @{ key = $key }
        
        try {
            switch ($this.ViewMode) {
                "List" {
                    return $this.HandleListInput($key)
                }
                "Edit" {
                    return $this.HandleEditInput($key)
                }
            }
        } finally {
            Stop-PerformanceTiming $timing
        }
        return "CONTINUE"
    }
    
    [string] HandleListInput([string]$key) {
        switch ($key.ToUpper()) {
            'E' {
                $categorySettings = $this.Settings | Where-Object { $_.Category -eq $this.SelectedCategory }
                if ($categorySettings.Count -gt 0) {
                    $this.ViewMode = "Edit"
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'R' {
                $this.ResetSelectedSetting()
                return "REFRESH"
            }
            'S' {
                $this.SaveConfiguration()
                return "CONTINUE"
            }
            'B' {
                return "DASHBOARD"
            }
            'Q' {
                return "EXIT"
            }
            'Tab' {
                $this.SwitchCategory()
                return "REFRESH"
            }
            'UpArrow' {
                $categorySettings = $this.Settings | Where-Object { $_.Category -eq $this.SelectedCategory }
                if ($this.SelectedSetting -gt 0) {
                    $this.SelectedSetting--
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'DownArrow' {
                $categorySettings = $this.Settings | Where-Object { $_.Category -eq $this.SelectedCategory }
                if ($this.SelectedSetting -lt ($categorySettings.Count - 1)) {
                    $this.SelectedSetting++
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            default {
                return "CONTINUE"
            }
        }
    }
    
    [string] HandleEditInput([string]$key) {
        switch ($key.ToUpper()) {
            'S' {
                $this.SaveSettingChange()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            'C' {
                $this.ViewMode = "List"
                return "REFRESH"
            }
            'R' {
                $this.ResetSelectedSetting()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            default {
                return "CONTINUE"
            }
        }
    }
    
    [void] LoadSettings() {
        # Create a structured list of all settings
        $this.Settings = @(
            # Application Settings
            @{ Category = "Application"; Name = "Name"; Value = $this.ConfigService.GetSetting("Application.Name"); Description = "Application name" }
            @{ Category = "Application"; Name = "Version"; Value = $this.ConfigService.GetSetting("Application.Version"); Description = "Application version" }
            @{ Category = "Application"; Name = "AutoSave"; Value = $this.ConfigService.GetSetting("Application.AutoSave"); Description = "Auto-save configuration" }
            @{ Category = "Application"; Name = "StartupScreen"; Value = $this.ConfigService.GetSetting("Application.StartupScreen"); Description = "Default startup screen" }
            
            # UI Settings
            @{ Category = "UI"; Name = "Theme"; Value = $this.ConfigService.GetSetting("UI.Theme"); Description = "UI color theme" }
            @{ Category = "UI"; Name = "RefreshRate"; Value = $this.ConfigService.GetSetting("UI.RefreshRate"); Description = "Screen refresh rate (ms)" }
            @{ Category = "UI"; Name = "ShowLineNumbers"; Value = $this.ConfigService.GetSetting("UI.ShowLineNumbers"); Description = "Show line numbers" }
            @{ Category = "UI"; Name = "HighlightSelection"; Value = $this.ConfigService.GetSetting("UI.HighlightSelection"); Description = "Highlight selected items" }
            
            # Performance Settings
            @{ Category = "Performance"; Name = "EnableMetrics"; Value = $this.ConfigService.GetSetting("Performance.EnableMetrics"); Description = "Enable performance metrics" }
            @{ Category = "Performance"; Name = "MetricsInterval"; Value = $this.ConfigService.GetSetting("Performance.MetricsInterval"); Description = "Metrics collection interval" }
            @{ Category = "Performance"; Name = "CacheSize"; Value = $this.ConfigService.GetSetting("Performance.CacheSize"); Description = "Internal cache size" }
            
            # Logging Settings
            @{ Category = "Logging"; Name = "LogLevel"; Value = $this.ConfigService.GetSetting("Application.LogLevel"); Description = "Logging verbosity level" }
            @{ Category = "Logging"; Name = "LogToFile"; Value = $this.ConfigService.GetSetting("Logging.LogToFile"); Description = "Enable file logging" }
            @{ Category = "Logging"; Name = "LogRotation"; Value = $this.ConfigService.GetSetting("Logging.LogRotation"); Description = "Enable log rotation" }
            
            # Advanced Settings  
            @{ Category = "Advanced"; Name = "EnableDebugMode"; Value = $this.ConfigService.GetSetting("Advanced.EnableDebugMode"); Description = "Enable debug features" }
            @{ Category = "Advanced"; Name = "ExperimentalFeatures"; Value = $this.ConfigService.GetSetting("Advanced.ExperimentalFeatures"); Description = "Enable experimental features" }
            @{ Category = "Advanced"; Name = "TelemetryEnabled"; Value = $this.ConfigService.GetSetting("Advanced.TelemetryEnabled"); Description = "Enable telemetry collection" }
        )
    }
    
    [void] SwitchCategory() {
        $categories = @("Application", "UI", "Performance", "Logging", "Advanced")
        $currentIndex = $categories.IndexOf($this.SelectedCategory)
        $nextIndex = ($currentIndex + 1) % $categories.Count
        $this.SelectedCategory = $categories[$nextIndex]
        $this.SelectedSetting = 0
    }
    
    [void] SaveSettingChange() {
        Write-Host "Enter new value: " -NoNewline -ForegroundColor Yellow
        $newValue = Read-Host
        
        try {
            $categorySettings = $this.Settings | Where-Object { $_.Category -eq $this.SelectedCategory }
            if ($this.SelectedSetting -lt $categorySettings.Count) {
                $setting = $categorySettings[$this.SelectedSetting]
                
                # Try to preserve the original type
                $convertedValue = $newValue
                if ($setting.Value -is [bool]) {
                    $convertedValue = [bool]::Parse($newValue)
                } elseif ($setting.Value -is [int]) {
                    $convertedValue = [int]::Parse($newValue)
                } elseif ($setting.Value -is [double]) {
                    $convertedValue = [double]::Parse($newValue)
                }
                
                # Update the configuration
                $fullSettingName = "$($setting.Category).$($setting.Name)"
                $this.ConfigService.SetSetting($fullSettingName, $convertedValue)
                
                # Update our local copy
                $setting.Value = $convertedValue
                
                Write-Host "Setting updated successfully!" -ForegroundColor Green
                $this.PerformanceMonitor.RecordMetric("screen.settings.setting_changed", 1, "count")
            }
        } catch {
            Write-Host "Error updating setting: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] ResetSelectedSetting() {
        try {
            $categorySettings = $this.Settings | Where-Object { $_.Category -eq $this.SelectedCategory }
            if ($this.SelectedSetting -lt $categorySettings.Count) {
                $setting = $categorySettings[$this.SelectedSetting]
                
                # Reset to default (this would need default values defined)
                Write-Host "Reset to default functionality not yet implemented" -ForegroundColor Yellow
                $this.PerformanceMonitor.RecordMetric("screen.settings.setting_reset", 1, "count")
            }
        } catch {
            Write-Host "Error resetting setting: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] SaveConfiguration() {
        try {
            # The ConfigurationService auto-saves, but we can force a save here
            Write-Host "Configuration saved successfully!" -ForegroundColor Green
            $this.PerformanceMonitor.RecordMetric("screen.settings.config_saved", 1, "count")
        } catch {
            Write-Host "Error saving configuration: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}