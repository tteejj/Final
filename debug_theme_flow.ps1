#!/usr/bin/env pwsh
# Debug script to trace theme loading - run with: pwsh ./debug_theme_flow.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "=== Theme Flow Debug ===" -ForegroundColor Cyan

# 1. Load the config directly
$configPath = "$PSScriptRoot/config.json"
$cfg = Get-Content $configPath -Raw | ConvertFrom-Json
Write-Host "`n[1] Config.json Properties:" -ForegroundColor Yellow
if ($cfg.Display.Theme.Properties) {
    $propCount = ($cfg.Display.Theme.Properties | Get-Member -MemberType NoteProperty).Count
    Write-Host "  Found $propCount properties"
    Write-Host "  Type: $($cfg.Display.Theme.Properties.GetType().Name)"
    # Show first few
    $cfg.Display.Theme.Properties | Get-Member -MemberType NoteProperty | Select-Object -First 5 | ForEach-Object {
        $name = $_.Name
        $val = $cfg.Display.Theme.Properties.$name
        Write-Host "    $name = Type:$($val.Type)"
    }
} else {
    Write-Host "  NO PROPERTIES FOUND!" -ForegroundColor Red
}

# 2. Load the PMC module
Write-Host "`n[2] Loading PMC Module..." -ForegroundColor Yellow
Import-Module "$PSScriptRoot/module/Pmc.Strict/Pmc.Strict.psd1" -Force

# 3. Check Get-PmcConfig
Write-Host "`n[3] Get-PmcConfig Properties:" -ForegroundColor Yellow
$pmcCfg = Get-PmcConfig
if ($pmcCfg.Display.Theme.Properties) {
    $propCount = ($pmcCfg.Display.Theme.Properties | Get-Member -MemberType NoteProperty).Count
    Write-Host "  Found $propCount properties"
} else {
    Write-Host "  NO PROPERTIES FOUND!" -ForegroundColor Red
}

# 4. Initialize theme system
Write-Host "`n[4] Initializing theme system..." -ForegroundColor Yellow
Initialize-PmcThemeSystem -Force

# 5. Check state after init
Write-Host "`n[5] Get-PmcState Display.Theme:" -ForegroundColor Yellow
$themeState = Get-PmcState -Section 'Display' -Key 'Theme'
if ($themeState.Properties) {
    $propCount = if ($themeState.Properties -is [hashtable]) { 
        $themeState.Properties.Count 
    } else { 
        ($themeState.Properties | Get-Member -MemberType NoteProperty).Count 
    }
    Write-Host "  Found $propCount properties"
    Write-Host "  Type: $($themeState.Properties.GetType().Name)"
} else {
    Write-Host "  NO PROPERTIES IN STATE!" -ForegroundColor Red
}

# 6. Load TUI components
Write-Host "`n[6] Loading TUI components..." -ForegroundColor Yellow
. "$PSScriptRoot/lib/SpeedTUI/Loader.ps1"
. "$PSScriptRoot/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1"
. "$PSScriptRoot/module/Pmc.Strict/consoleui/theme/PmcThemeManager.ps1"

# 7. Get PmcThemeManager instance
Write-Host "`n[7] PmcThemeManager.PmcTheme.Properties:" -ForegroundColor Yellow
$manager = [PmcThemeManager]::GetInstance()
if ($manager.PmcTheme -and $manager.PmcTheme.Properties) {
    Write-Host "  Found properties"
    Write-Host "  Type: $($manager.PmcTheme.Properties.GetType().Name)"
} else {
    Write-Host "  NO PROPERTIES IN MANAGER! manager.PmcTheme=$($manager.PmcTheme | Out-String)" -ForegroundColor Red
}

# 8. Get PmcThemeEngine properties
Write-Host "`n[8] PmcThemeEngine._properties:" -ForegroundColor Yellow
$engine = [PmcThemeEngine]::GetInstance()
# Access private field via reflection
$propsField = $engine.GetType().GetField('_properties', [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
if ($propsField) {
    $engineProps = $propsField.GetValue($engine)
    if ($engineProps -and $engineProps.Count -gt 0) {
        Write-Host "  Found $($engineProps.Count) properties"
        $engineProps.Keys | Select-Object -First 5 | ForEach-Object {
            $val = $engineProps[$_]
            Write-Host "    $_ = Type:$($val.Type)"
        }
    } else {
        Write-Host "  NO PROPERTIES IN ENGINE!" -ForegroundColor Red
    }
} else {
    Write-Host "  Could not access _properties field" -ForegroundColor Red
}

Write-Host "`n=== Debug Complete ===" -ForegroundColor Cyan
