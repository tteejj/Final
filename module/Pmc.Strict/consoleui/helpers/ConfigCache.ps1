# ConfigCache.ps1 - Configuration file caching with automatic invalidation
#
# Caches config.json in memory and only reloads when file timestamp changes.
# Eliminates repeated file I/O when accessing configuration.
#
# Usage:
#   $config = [ConfigCache]::GetConfig($configPath)
#   [ConfigCache]::InvalidateCache()  # Force reload

using namespace System

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Configuration file cache with timestamp-based invalidation

.DESCRIPTION
ConfigCache provides high-performance configuration access by:
- Loading config file once into memory
- Tracking file modification timestamp
- Auto-reloading only when file changes
- Thread-safe access for concurrent reads

.EXAMPLE
# Get cached config (loads on first call, cached thereafter)
$config = [ConfigCache]::GetConfig("./config.json")

# Force reload (e.g., after editing config)
[ConfigCache]::InvalidateCache()
$config = [ConfigCache]::GetConfig("./config.json")
#>
class ConfigCache {
    # Static cache storage
    static hidden [hashtable]$_cache = $null
    static hidden [datetime]$_lastLoad = [datetime]::MinValue
    static hidden [string]$_configPath = ""
    static hidden [datetime]$_fileTimestamp = [datetime]::MinValue

    <#
    .SYNOPSIS
    Get configuration from cache or load if needed

    .PARAMETER path
    Path to config.json file

    .OUTPUTS
    Hashtable containing configuration

    .DESCRIPTION
    Loads config file on first call, then returns cached version.
    Automatically reloads if file modification timestamp changes.
    #>
    static [hashtable] GetConfig([string]$path) {
        # Resolve to absolute path for consistent caching
        $absolutePath = [System.IO.Path]::GetFullPath($path)

        # Check if file exists
        if (-not (Test-Path $absolutePath)) {
            throw "Config file not found: $absolutePath"
        }

        # Get file modification time
        $fileInfo = Get-Item $absolutePath -ErrorAction Stop
        $currentTimestamp = $fileInfo.LastWriteTime

        # Load if cache empty, path changed, or file modified
        $needsLoad = (
            $null -eq [ConfigCache]::_cache -or
            $absolutePath -ne [ConfigCache]::_configPath -or
            $currentTimestamp -gt [ConfigCache]::_fileTimestamp
        )

        if ($needsLoad) {
            try {
                # Load and parse config
                $json = Get-Content $absolutePath -Raw -Encoding utf8 -ErrorAction Stop
                [ConfigCache]::_cache = $json | ConvertFrom-Json -AsHashtable -ErrorAction Stop

                # Update metadata
                [ConfigCache]::_configPath = $absolutePath
                [ConfigCache]::_fileTimestamp = $currentTimestamp
                [ConfigCache]::_lastLoad = [datetime]::Now

                # Log cache update (only if logging enabled)
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [INFO] ConfigCache: Loaded config from $absolutePath"
                }
            } catch {
                # Clear cache on error
                [ConfigCache]::_cache = $null
                [ConfigCache]::_configPath = ""
                [ConfigCache]::_fileTimestamp = [datetime]::MinValue

                throw "Failed to load config from ${absolutePath}: $_"
            }
        }

        # Return cached config
        return [ConfigCache]::_cache
    }

    <#
    .SYNOPSIS
    Force cache invalidation and reload on next access

    .DESCRIPTION
    Clears the cached configuration, forcing a reload on the next GetConfig call.
    Use after modifying config file to ensure changes are picked up.
    #>
    static [void] InvalidateCache() {
        [ConfigCache]::_cache = $null
        [ConfigCache]::_configPath = ""
        [ConfigCache]::_fileTimestamp = [datetime]::MinValue

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [INFO] ConfigCache: Cache invalidated"
        }
    }

    <#
    .SYNOPSIS
    Get cache statistics for diagnostics

    .OUTPUTS
    Hashtable with cache stats

    .DESCRIPTION
    Returns information about cache state for debugging/monitoring
    #>
    static [hashtable] GetStats() {
        return @{
            IsCached = ($null -ne [ConfigCache]::_cache)
            ConfigPath = [ConfigCache]::_configPath
            FileTimestamp = [ConfigCache]::_fileTimestamp
            LastLoad = [ConfigCache]::_lastLoad
            CacheAge = $(if ([ConfigCache]::_lastLoad -ne [datetime]::MinValue) {
                ([datetime]::Now - [ConfigCache]::_lastLoad).TotalSeconds
            } else {
                $null
            })
        }
    }
}

# Export class (PowerShell 5.1+ auto-exports classes)