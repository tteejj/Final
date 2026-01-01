# Config provider indirection - now uses centralized state

function Set-PmcConfigProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)] [scriptblock]$Get,
        [Parameter(Position=1)] [scriptblock]$Set
    )
    Set-PmcConfigProviders -Get $Get -Set $Set
}

function Get-PmcConfig {
    $providers = Get-PmcConfigProviders
    try {
        $cfg = & $providers.Get
        # If provider returns empty config, try reading from default file
        if (-not $cfg -or ($cfg.GetType().Name -eq 'Hashtable' -and $cfg.Count -eq 0)) {
            try {
                $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
                $path = Join-Path $root 'config.json'
                if (Test-Path $path) {
                    $json = Get-Content -Path $path -Raw -Encoding UTF8
                    $cfg = $json | ConvertFrom-Json
                    $cfg = ConvertPSObjectToHashtable $cfg
                    return $cfg
                }
            } catch { }
        }
        return $cfg
    } catch {
        return @{}
    }
}

function ConvertPSObjectToHashtable {
    param($obj)
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IDictionary]) { return $obj }
    if ($obj -is [System.Collections.IEnumerable] -and $obj -isnot [string]) {
        return @($obj | ForEach-Object { ConvertPSObjectToHashtable $_ })
    }
    if ($obj -is [PSCustomObject]) {
        $ht = @{}
        foreach ($prop in $obj.PSObject.Properties) {
            $ht[$prop.Name] = ConvertPSObjectToHashtable $prop.Value
        }
        return $ht
    }
    return $obj
}

function Save-PmcConfig {
    param($cfg)
    
    # Debug log path
    # Use absolute path for log - try global root first, fallback to hardcoded path
    $debugLog = $null
    if ($global:PmcAppRoot) {
        $debugLog = Join-Path $global:PmcAppRoot 'data/logs/config-debug.log'
    } elseif ($PSScriptRoot) {
        $debugLog = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'data/logs/config-debug.log'
    } else {
        $debugLog = '/home/teej/ztest/data/logs/config-debug.log'
    }
    
    $providers = Get-PmcConfigProviders
    Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Save-PmcConfig] providers.Set is $($null -ne $providers.Set)" -ErrorAction SilentlyContinue
    
    if ($providers.Set) {
        try {
            Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Save-PmcConfig] Calling provider Set" -ErrorAction SilentlyContinue
            & $providers.Set $cfg
            Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Save-PmcConfig] Provider Set succeeded - RETURNING EARLY" -ErrorAction SilentlyContinue
            return
        } catch {
            Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Save-PmcConfig] Provider Set FAILED: $_ - falling back to file" -ErrorAction SilentlyContinue
        }
    }
    
    # Default: write to config.json
    try {
        $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        $path = Join-Path $root 'config.json'
        Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Save-PmcConfig] Writing to file: $path" -ErrorAction SilentlyContinue
        $cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
        Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Save-PmcConfig] File write SUCCESS" -ErrorAction SilentlyContinue
    } catch {
        Add-Content -Path $debugLog -Value "[$(Get-Date -F 'HH:mm:ss.fff')] [Save-PmcConfig] File write FAILED: $_" -ErrorAction SilentlyContinue
    }
}

function Get-PmcDefaultConfig {
    return @{
        Display = @{ Theme = @{ Enabled=$true; Hex='#33aaff' }; Icons=@{ Mode='emoji' } }
        Debug = @{ Level=0; LogPath='debug.log'; MaxSize='10MB'; RedactSensitive=$true; IncludePerformance=$false }
        Security = @{ AllowedWritePaths=@('./','./reports/','./backups/'); MaxFileSize='100MB'; MaxMemoryUsage='500MB'; ScanForSensitiveData=$true; RequirePathWhitelist=$true; AuditAllFileOps=$true }
        Behavior = @{ StrictDataMode = $true; SafePathsStrict = $true; MaxBackups = 3; MaxUndoLevels = 10; WhatIf = $false }
    }
}

function Test-PmcConfigSchema {
    $cfg = Get-PmcConfig
    $errors = @(); $warnings=@()
    try { $hex = [string]$cfg.Display.Theme.Hex; if (-not ($hex -match '^#?[0-9a-fA-F]{6}$')) { $warnings += 'Display.Theme.Hex invalid; using default' } } catch { $warnings += 'Display.Theme.Hex missing' }
    try { $mode = [string]$cfg.Display.Icons.Mode; if ($mode -notin @('ascii','emoji')) { $warnings += 'Display.Icons.Mode must be ascii|emoji' } } catch { $warnings += 'Display.Icons.Mode missing' }
    try { $lvl = [int]$cfg.Debug.Level; if ($lvl -lt 0 -or $lvl -gt 3) { $warnings += 'Debug.Level out of range (0-3)' } } catch { $warnings += 'Debug.Level missing' }
    try { if (-not ($cfg.Security.AllowedWritePaths -is [System.Collections.IEnumerable])) { $warnings += 'Security.AllowedWritePaths must be an array' } } catch { $warnings += 'Security.AllowedWritePaths missing' }
    return [pscustomobject]@{ IsValid = ($errors.Count -eq 0); Errors=$errors; Warnings=$warnings }
}

function Normalize-PmcConfig {
    $cfg = Get-PmcConfig
    $def = Get-PmcDefaultConfig
    foreach ($k in $def.Keys) {
        if (-not $cfg.ContainsKey($k)) { $cfg[$k] = $def[$k]; continue }
        foreach ($k2 in $def[$k].Keys) {
            if (-not $cfg[$k].ContainsKey($k2)) { $cfg[$k][$k2] = $def[$k][$k2] }
        }
    }
    try { if ($cfg.Display.Theme.Hex -and -not ($cfg.Display.Theme.Hex.ToString().StartsWith('#'))) { $cfg.Display.Theme.Hex = '#' + $cfg.Display.Theme.Hex } } catch {}
    try { if (-not $cfg.Display.Icons.Mode) { $cfg.Display.Icons.Mode = 'emoji' } } catch {}
    Save-PmcConfig $cfg
    return $cfg
}

function Validate-PmcConfig { param([PmcCommandContext]$Context)
    $result = Test-PmcConfigSchema
    if (-not $result.IsValid -or $result.Warnings.Count -gt 0) {
        Write-PmcStyled -Style 'Warning' -Text 'Config issues detected:'
        foreach ($w in $result.Warnings) { Write-PmcStyled -Style 'Muted' -Text ('  - ' + $w) }
    } else {
        Write-PmcStyled -Style 'Success' -Text 'Config looks good.'
    }
}

function Show-PmcConfig {
    param($Context)
    $cfg = Get-PmcConfig
    Write-PmcStyled -Style 'Header' -Text "`n⚙️ PMC CONFIGURATION`n"
    Write-PmcStyled -Style 'Subheader' -Text "Data Path:"
    Write-PmcStyled -Style 'Info' -Text "  $($cfg.Storage.DataPath)"
    Write-PmcStyled -Style 'Subheader' -Text "`nDisplay Settings:"
    Write-PmcStyled -Style 'Info' -Text "  Icons: $($cfg.Display.Icons.Mode)"
    Write-PmcStyled -Style 'Subheader' -Text "`nSecurity Level:"
    Write-PmcStyled -Style 'Info' -Text "  $($cfg.Security.Level)"
}

function Edit-PmcConfig {
    param($Context)
    Write-PmcStyled -Style 'Warning' -Text 'Config editing not yet implemented'
    Write-PmcStyled -Style 'Info' -Text 'Use: Show-PmcConfig to view current settings'
}

function Set-PmcConfigValue {
    param($Context)
    Write-PmcStyled -Style 'Warning' -Text 'Config value setting not yet implemented'
    Write-PmcStyled -Style 'Info' -Text 'Manual config editing required'
}

function Reload-PmcConfig {
    param($Context)
    $Script:PmcConfig = $null
    $cfg = Get-PmcConfig
    Write-PmcStyled -Style 'Success' -Text '[OK] Config reloaded'
}

function Set-PmcIconMode {
    param($Context)
    $mode = 'emoji'
    if ($Context.FreeText.Count -gt 0) {
        $mode = $Context.FreeText[0].ToLower()
    }
    if ($mode -notin @('ascii', 'emoji')) {
        Write-PmcStyled -Style 'Error' -Text 'Icon mode must be: ascii or emoji'
        return
    }
    $cfg = Get-PmcConfig
    $cfg.Display.Icons.Mode = $mode
    Save-PmcConfig $cfg
    Write-PmcStyled -Style 'Success' -Text "[OK] Icon mode set to: $mode"
}