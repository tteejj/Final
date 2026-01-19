# ThemePicker.ps1 - Theme selection modal with live preview and restart
# Opens with '0' key, lists themes from themes/ folder, restarts app on selection

class ThemePicker {
    hidden [bool]$_visible = $false
    hidden [array]$_themes = @()
    hidden [int]$_selectedIndex = 0
    hidden [string]$_currentTheme = ""
    hidden [bool]$_restartRequested = $false
    
    ThemePicker() {
        $this._LoadThemes()
    }
    
    hidden [void] _LoadThemes() {
        $this._themes = @()
        
        # Find themes directory
        $themesDir = $null
        if ($global:PmcAppRoot) {
            $themesDir = Join-Path $global:PmcAppRoot "themes"
        }
        
        if (-not $themesDir -or -not (Test-Path $themesDir)) {
            # Fallback: look relative to script
            $scriptDir = $PSScriptRoot
            $themesDir = Join-Path (Split-Path $scriptDir -Parent) "themes"
        }
        
        if (Test-Path $themesDir) {
            $themeFiles = Get-ChildItem -Path $themesDir -Filter "*.json" -File
            foreach ($file in $themeFiles) {
                try {
                    $themeData = Get-Content $file.FullName -Raw | ConvertFrom-Json
                    $this._themes += @{
                        Name = $themeData.Name
                        FileName = $file.BaseName
                        Hex = $themeData.Hex
                        Description = if ($themeData.Description) { $themeData.Description } else { "" }
                    }
                } catch {
                    # Skip invalid theme files
                }
            }
        }
        
        # Get current theme from config
        try {
            $config = [DataService]::LoadConfig()
            if ($config.Display -and $config.Display.Theme -and $config.Display.Theme.Active) {
                $this._currentTheme = $config.Display.Theme.Active
            }
        } catch {
            $this._currentTheme = "default"
        }
        
        # Set selection to current theme
        for ($i = 0; $i -lt $this._themes.Count; $i++) {
            if ($this._themes[$i].FileName -eq $this._currentTheme) {
                $this._selectedIndex = $i
                break
            }
        }
    }
    
    [void] Open() {
        $this._LoadThemes()
        $this._visible = $true
        $this._restartRequested = $false
    }
    
    [void] Close() {
        $this._visible = $false
    }
    
    [bool] IsVisible() {
        return $this._visible
    }
    
    [bool] RestartRequested() {
        return $this._restartRequested
    }
    
    [void] Render([HybridRenderEngine]$engine) {
        if (-not $this._visible) { return }
        
        $w = 50
        $h = [Math]::Min(16, $this._themes.Count + 6)
        $x = [int](($engine.Width - $w) / 2)
        $y = [int](($engine.Height - $h) / 2)
        
        $engine.BeginLayer(200)
        
        # Draw modal box
        $engine.Fill($x, $y, $w, $h, ' ', [Colors]::Foreground, [Colors]::PanelBg)
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
        $engine.WriteAt($x + 2, $y, " Select Theme ", [Colors]::White, [Colors]::Accent)
        
        # Instructions
        $engine.WriteAt($x + 2, $y + 2, "Current: $($this._currentTheme)", [Colors]::Gray, [Colors]::PanelBg)
        
        # Theme list
        $listY = $y + 4
        $listH = $h - 6
        
        if ($this._themes.Count -eq 0) {
            $engine.WriteAt($x + 4, $listY, "No themes found in themes/", [Colors]::Gray, [Colors]::PanelBg)
        } else {
            for ($i = 0; $i -lt [Math]::Min($listH, $this._themes.Count); $i++) {
                $theme = $this._themes[$i]
                $isSelected = ($i -eq $this._selectedIndex)
                $isCurrent = ($theme.FileName -eq $this._currentTheme)
                
                $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
                $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::PanelBg }
                
                # Clear row
                $engine.Fill($x + 2, $listY + $i, $w - 4, 1, " ", $fg, $bg)
                
                # Marker for current theme
                $marker = if ($isCurrent) { "*" } else { " " }
                $engine.WriteAt($x + 2, $listY + $i, $marker, [Colors]::Cyan, $bg)
                
                # Theme name
                $displayName = $theme.Name
                if ($displayName.Length -gt 30) { $displayName = $displayName.Substring(0, 27) + "..." }
                $engine.WriteAt($x + 4, $listY + $i, $displayName, $fg, $bg)
                
                # Color preview (show hex as colored block)
                $hexInt = $this._HexToInt($theme.Hex)
                if ($hexInt -ne -1) {
                    $engine.WriteAt($x + $w - 10, $listY + $i, "  ████  ", $hexInt, $bg)
                }
            }
        }
        
        # Footer
        $engine.WriteAt($x + 2, $y + $h - 2, "Enter: Apply & Restart  Esc: Cancel", [Colors]::Gray, [Colors]::PanelBg)
        
        $engine.EndLayer()
    }
    
    hidden [int] _HexToInt([string]$hex) {
        if ([string]::IsNullOrEmpty($hex)) { return -1 }
        $hex = $hex.TrimStart('#')
        if ($hex.Length -ne 6) { return -1 }
        try {
            return [Convert]::ToInt32($hex, 16)
        } catch { return -1 }
    }
    
    [string] HandleInput([ConsoleKeyInfo]$key) {
        if (-not $this._visible) { return "None" }
        
        switch ($key.Key) {
            'Escape' {
                $this._visible = $false
                return "Close"
            }
            'Enter' {
                if ($this._themes.Count -gt 0 -and $this._selectedIndex -ge 0) {
                    $selectedTheme = $this._themes[$this._selectedIndex]
                    $this._ApplyTheme($selectedTheme.FileName)
                    return "Restart"
                }
                return "None"
            }
            'UpArrow' {
                if ($this._selectedIndex -gt 0) {
                    $this._selectedIndex--
                }
                return "None"
            }
            'DownArrow' {
                if ($this._selectedIndex -lt $this._themes.Count - 1) {
                    $this._selectedIndex++
                }
                return "None"
            }
        }
        return "None"
    }
    
    hidden [void] _ApplyTheme([string]$themeName) {
        try {
            # Load current config
            $configPath = Join-Path $global:PmcAppRoot "config.json"
            $config = @{}
            
            if (Test-Path $configPath) {
                try {
                    $configObj = Get-Content -Path $configPath -Raw | ConvertFrom-Json
                    foreach ($prop in $configObj.PSObject.Properties) {
                        $config[$prop.Name] = $prop.Value
                    }
                } catch {}
            }
            
            # Ensure Display.Theme structure exists
            if (-not $config.ContainsKey('Display')) { $config['Display'] = @{} }
            if ($config.Display -isnot [hashtable]) {
                $displayHash = @{}
                foreach ($prop in $config.Display.PSObject.Properties) { $displayHash[$prop.Name] = $prop.Value }
                $config['Display'] = $displayHash
            }
            if (-not $config.Display.ContainsKey('Theme')) { $config.Display['Theme'] = @{} }
            if ($config.Display.Theme -isnot [hashtable]) {
                $themeHash = @{}
                foreach ($prop in $config.Display.Theme.PSObject.Properties) { $themeHash[$prop.Name] = $prop.Value }
                $config.Display['Theme'] = $themeHash
            }
            
            # Set theme
            $config.Display.Theme['Active'] = $themeName.ToLower()
            
            # Get theme hex for config
            $theme = $this._themes | Where-Object { $_.FileName -eq $themeName } | Select-Object -First 1
            if ($theme -and $theme.Hex) {
                $config.Display.Theme['Hex'] = $theme.Hex
            }
            
            # Write config
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
            
            $this._restartRequested = $true
            [Logger]::Log("ThemePicker: Theme '$themeName' saved to config", 2)
        } catch {
            [Logger]::Error("ThemePicker: Failed to save theme", $_)
        }
    }
}
