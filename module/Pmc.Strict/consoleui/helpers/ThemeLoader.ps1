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
    $themesDir = Join-Path (Get-PmcRootPath) 'themes'
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
                if ($global:PmcDebug -and $global:PmcTuiLogFile) {
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
    
    $themesDir = Join-Path (Get-PmcRootPath) 'themes'
    $themeFile = Join-Path $themesDir "$($themeName.ToLower()).json"
    
    if (Test-Path $themeFile) {
        try {
            $theme = Get-Content $themeFile -Raw | ConvertFrom-Json
            return $theme
        }
        catch {
            if ($global:PmcDebug -and $global:PmcTuiLogFile) {
                Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeLoader] ERROR loading theme '$themeName': $_"
            }
            return $null
        }
    }
    
    if ($global:PmcDebug -and $global:PmcTuiLogFile) {
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
        if ($global:PmcDebug -and $global:PmcTuiLogFile) {
            Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeLoader] ERROR reading config: $_"
        }
    }
    
    $theme = Load-Theme -themeName $themeName
    
    # If theme not found, try default
    if (-not $theme -and $themeName -ne 'default') {
        if ($global:PmcDebug -and $global:PmcTuiLogFile) {
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
    
    $cfg = Get-PmcConfig
    if (-not $cfg) { $cfg = @{} }
    if (-not $cfg.Display) { $cfg.Display = @{} }
    if (-not $cfg.Display.Theme) { $cfg.Display.Theme = @{} }
    
    $cfg.Display.Theme.Active = $themeName.ToLower()
    
    # Remove old Properties and Hex - no longer needed in config
    if ($cfg.Display.Theme.Properties) { $cfg.Display.Theme.Remove('Properties') }
    if ($cfg.Display.Theme.Hex) { $cfg.Display.Theme.Remove('Hex') }
    
    Save-PmcConfig $cfg
}

Export-ModuleMember -Function Get-AvailableThemes, Load-Theme, Get-ActiveTheme, Set-ActiveTheme
