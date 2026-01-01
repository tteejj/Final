# ThemeLoader.ps1 - Simple theme file loading
# Loads themes from themes/*.json files
# ONE path: Load theme file -> Use Properties

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Get list of available themes from themes/ directory

.OUTPUTS
Array of theme objects with Name, Hex, Description, Properties
#>
function Get-AvailableThemes {
    $themesDir = Join-Path $global:PmcAppRoot 'themes'
    $themes = @()
    
    if (Test-Path $themesDir) {
        $themeFiles = Get-ChildItem -Path $themesDir -Filter '*.json' -File
        foreach ($file in $themeFiles) {
            try {
                $theme = Get-Content $file.FullName -Raw | ConvertFrom-Json
                $themes += $theme
            }
            catch {
                # Debug only when flag is set
                if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
                    Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeLoader] ERROR loading $($file.Name): $_"
                }
            }
        }
    }
    
    return $themes
}

<#
.SYNOPSIS
Load a specific theme by name

.PARAMETER themeName
Name of the theme (matching filename without .json extension)

.OUTPUTS
Theme object with Name, Hex, Description, Properties, or $null if not found
#>
function Load-Theme {
    param(
        [Parameter(Mandatory=$true)]
        [string]$themeName
    )
    
    # Debug log path (same as Start-PmcTUI)
    $debugLog = $null
    try {
        $debugLog = Join-Path (Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent) 'data/logs/theme-debug.log'
    } catch { }
    
    # Handle null PmcAppRoot
    $themesDir = $null
    if ($global:PmcAppRoot -and (Test-Path -Path $global:PmcAppRoot -ErrorAction SilentlyContinue)) {
        $themesDir = Join-Path $global:PmcAppRoot 'themes'
    }
    if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Load-Theme] themeName='$themeName' PmcAppRoot='$($global:PmcAppRoot)' themesDir='$themesDir'" -ErrorAction SilentlyContinue }
    
    # Fallback search if global root empty or themes dir doesn't exist
    if (-not $themesDir -or -not (Test-Path $themesDir -ErrorAction SilentlyContinue)) {
        if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Load-Theme] themesDir not found, searching fallbacks..." -ErrorAction SilentlyContinue }
        
        # Build search paths - include explicit module-relative paths for when PSScriptRoot is empty
        $moduleRoot = Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
        $searchPaths = @(
            $PSScriptRoot,
            (Split-Path $PSScriptRoot -Parent),
            (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
            (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent),
            $moduleRoot
        ) | Where-Object { $_ }  # Filter out nulls
        
        # If all are empty, try to derive from this script's location
        if ($searchPaths.Count -eq 0) {
            # Hardcoded fallback: navigate from module structure
            $searchPaths = @(
                (Get-Location).Path,
                (Join-Path (Get-Location).Path 'themes')
            )
        }
        
        foreach ($path in $searchPaths) {
            $testPath = Join-Path $path "themes"
            if ($path -and (Test-Path $testPath -ErrorAction SilentlyContinue)) {
                $themesDir = $testPath
                if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Load-Theme] Found themes at fallback: $themesDir" -ErrorAction SilentlyContinue }
                break
            }
        }
    }

    $themeFile = Join-Path $themesDir "$($themeName.ToLower()).json"
    if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Load-Theme] Looking for: $themeFile (exists=$(Test-Path $themeFile))" -ErrorAction SilentlyContinue }
    
    if (Test-Path $themeFile) {
        try {
            $themeObj = Get-Content $themeFile -Raw | ConvertFrom-Json
            if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Load-Theme] JSON loaded. Name='$($themeObj.Name)' Hex='$($themeObj.Hex)'" -ErrorAction SilentlyContinue }
            # Convert Properties from PSCustomObject to hashtable
            $props = @{}
            if ($themeObj.Properties) {
                $themeObj.Properties.PSObject.Properties | ForEach-Object {
                    $propValue = @{
                        Type = $_.Value.Type
                    }
                    # Solid types have Color, Gradient types have Start/End
                    if ($_.Value.PSObject.Properties['Color']) {
                        $propValue['Color'] = $_.Value.Color
                    }
                    if ($_.Value.PSObject.Properties['Start']) {
                        $propValue['Start'] = $_.Value.Start
                    }
                    if ($_.Value.PSObject.Properties['End']) {
                        $propValue['End'] = $_.Value.End
                    }
                    $props[$_.Name] = $propValue
                }
            }
            $theme = @{
                Name = $themeObj.Name
                Hex = $themeObj.Hex
                Description = $themeObj.Description
                Properties = $props
                Warning = $(if ($props.ContainsKey('Foreground.Warning')) { $props['Foreground.Warning'] } else { 'Red' })
            }
            if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Load-Theme] Returning theme with Hex='$($theme.Hex)'" -ErrorAction SilentlyContinue }
            return $theme
        }
        catch {
            if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Load-Theme] EXCEPTION: $_" -ErrorAction SilentlyContinue }
            if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
                Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeLoader] FATAL ERROR loading theme '$themeName': $_"
            }
            throw "Failed to load theme '$themeName': $_"
        }
    }
    
    if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Load-Theme] Theme file NOT FOUND, returning null" -ErrorAction SilentlyContinue }
    if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
        Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeLoader] Theme file not found: $themeFile"
    }
    return $null
}


<#
.SYNOPSIS
Get the currently active theme

.DESCRIPTION
Reads active theme name from config.json, loads that theme file

.OUTPUTS
Theme object with Properties, or default theme if not found
#>
function Get-ActiveTheme {
    $themeName = 'default'  # Default if nothing configured
    
    try {
        $cfg = Get-PmcConfig
        if ($cfg -and $cfg.Display -and $cfg.Display.Theme -and $cfg.Display.Theme.Active) {
            $themeName = $cfg.Display.Theme.Active
        }
    }
    catch {
        if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
            Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeLoader] ERROR reading config: $_"
        }
    }
    
    $theme = Load-Theme -themeName $themeName
    
    # If theme not found, try default
    if (-not $theme -and $themeName -ne 'default') {
        if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
            Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeLoader] Theme '$themeName' not found, falling back to default"
        }
        $theme = Load-Theme -themeName 'default'
    }
    
    return $theme
}

<#
.SYNOPSIS
Set the active theme by name

.PARAMETER themeName
Name of the theme to set as active
#>
function Set-ActiveTheme {
    param(
        [Parameter(Mandatory=$true)]
        [string]$themeName
    )
    
    # Debug log path
    $debugLog = $null
    try {
        $debugLog = Join-Path (Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent) 'data/logs/theme-debug.log'
    } catch { }
    if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Set-ActiveTheme] Starting for themeName='$themeName'" -ErrorAction SilentlyContinue }
    
    # Read config.json directly - don't rely on Get-PmcConfig which may not be in scope
    $configPath = $null
    if ($global:PmcAppRoot) {
        $configPath = Join-Path $global:PmcAppRoot 'config.json'
    } else {
        # Fallback: derive from script location
        $configPath = Join-Path (Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent) 'config.json'
    }
    
    if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Set-ActiveTheme] Reading config from: $configPath" -ErrorAction SilentlyContinue }
    
    $cfg = @{}
    if (Test-Path $configPath) {
        try {
            $json = Get-Content -Path $configPath -Raw -Encoding UTF8
            $cfgObj = $json | ConvertFrom-Json
            # Convert PSCustomObject to hashtable recursively
            $cfg = @{}
            foreach ($prop in $cfgObj.PSObject.Properties) {
                $cfg[$prop.Name] = $prop.Value
            }
        } catch {
            if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Set-ActiveTheme] ERROR reading config: $_" -ErrorAction SilentlyContinue }
        }
    }
    
    # Ensure Display exists and is a hashtable
    if (-not $cfg.ContainsKey('Display') -or -not $cfg.Display) { 
        $cfg['Display'] = @{} 
    } elseif ($cfg.Display -isnot [hashtable]) {
        $displayHash = @{}
        foreach ($prop in $cfg.Display.PSObject.Properties) {
            $displayHash[$prop.Name] = $prop.Value
        }
        $cfg['Display'] = $displayHash
    }
    
    # Ensure Theme exists and is a hashtable
    if (-not $cfg.Display.ContainsKey('Theme') -or -not $cfg.Display.Theme) { 
        $cfg.Display['Theme'] = @{} 
    } elseif ($cfg.Display.Theme -isnot [hashtable]) {
        $themeHash = @{}
        foreach ($prop in $cfg.Display.Theme.PSObject.Properties) {
            $themeHash[$prop.Name] = $prop.Value
        }
        $cfg.Display['Theme'] = $themeHash
    }
    
    $cfg.Display.Theme['Active'] = $themeName.ToLower()
    if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Set-ActiveTheme] Set Active='$($cfg.Display.Theme.Active)'" -ErrorAction SilentlyContinue }
    
    # Load the theme to get its hex color
    $theme = Load-Theme -themeName $themeName
    if (-not $theme) {
        if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Set-ActiveTheme] Load-Theme returned null!" -ErrorAction SilentlyContinue }
        throw "Set-ActiveTheme: Failed to load theme '$themeName' - theme file may not exist in themes/ directory"
    }
    if (-not $theme.Hex) {
        if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Set-ActiveTheme] Theme has no Hex property!" -ErrorAction SilentlyContinue }
        throw "Set-ActiveTheme: Theme '$themeName' loaded but has no Hex property defined"
    }
    $cfg.Display.Theme['Hex'] = $theme.Hex
    if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Set-ActiveTheme] Set Hex='$($cfg.Display.Theme.Hex)'" -ErrorAction SilentlyContinue }
    
    # Remove old Properties - no longer needed in config
    try {
        if ($cfg.Display.Theme -is [hashtable]) {
            $cfg.Display.Theme.Remove('Properties')
        }
    } catch { }
    
    # Write config.json directly
    if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Set-ActiveTheme] Writing config to: $configPath" -ErrorAction SilentlyContinue }
    try {
        $cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
        if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Set-ActiveTheme] Config saved successfully" -ErrorAction SilentlyContinue }
    } catch {
        if ($debugLog) { Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Set-ActiveTheme] ERROR writing config: $_" -ErrorAction SilentlyContinue }
        throw
    }
}



Export-ModuleMember -Function Get-AvailableThemes, Load-Theme, Get-ActiveTheme, Set-ActiveTheme
