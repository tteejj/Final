# RenderCache.ps1 - Unified widget-level caching engine for SpeedTUI
# Operates before the render engine to avoid redundant widget rendering
#
# ARCHITECTURE:
# - Widget calls RenderWithCache() instead of RenderToEngine()
# - Cache checks if widget state hash matches cached entry
# - HIT: Replay cached cells directly to backbuffer
# - MISS: Render normally, capture cells, store in cache
#
# DESIGN DECISIONS:
# - Widget-based caching (not region-based)
# - Cache clears on screen transitions
# - Opt-in: widgets must implement GetContentHash() to enable caching
# - LRU eviction when cache exceeds max entries

using namespace System.Collections.Generic

Set-StrictMode -Off

$script:_RenderCacheInstance = $null

<#
.SYNOPSIS
Represents a cached widget's rendered output
#>
class CachedWidget {
    [int]$X
    [int]$Y
    [int]$Width
    [int]$Height
    [int]$ZIndex              # Z-layer used during capture
    [string]$ContentHash      # Hash of widget state when captured
    [object]$Cells            # 2D array of cells [row][col]
    
    CachedWidget([int]$x, [int]$y, [int]$width, [int]$height, [int]$zIndex) {
        $this.X = $x
        $this.Y = $y
        $this.Width = $width
        $this.Height = $height
        $this.ZIndex = $zIndex
        $this.Cells = $null
        $this.ContentHash = ""
    }
}

<#
.SYNOPSIS
Unified caching engine for widget rendering
#>
class RenderCache {
    # Cache storage: Key → CachedWidget
    hidden [hashtable]$_cache = @{}
    
    # LRU tracking: most recently used keys at end
    hidden [System.Collections.Generic.LinkedList[string]]$_lruOrder
    
    # Configuration
    hidden [int]$_maxEntries = 100
    
    # Statistics
    hidden [int]$_hits = 0
    hidden [int]$_misses = 0
    
    # Constructor (private - use GetInstance)
    RenderCache() {
        $this._lruOrder = [System.Collections.Generic.LinkedList[string]]::new()
    }
    
    <#
    .SYNOPSIS
    Get singleton instance
    #>
    static [RenderCache] GetInstance() {
        if ($null -eq $script:_RenderCacheInstance) {
            $script:_RenderCacheInstance = [RenderCache]::new()
        }
        return $script:_RenderCacheInstance
    }
    
    <#
    .SYNOPSIS
    Reset singleton (for testing or clean restart)
    #>
    static [void] Reset() {
        $script:_RenderCacheInstance = $null
    }
    
    <#
    .SYNOPSIS
    Try to get a cached widget by key and hash
    
    .PARAMETER key
    Cache key: {WidgetType}:{WidgetName}:{X},{Y},{W},{H}:{Z}
    
    .PARAMETER contentHash
    Hash of current widget state
    
    .PARAMETER result
    [ref] to receive cached widget if found
    
    .OUTPUTS
    Boolean - true if cache hit with matching hash
    #>
    [bool] TryGet([string]$key, [string]$contentHash, [ref]$result) {
        if ([string]::IsNullOrEmpty($key) -or [string]::IsNullOrEmpty($contentHash)) {
            $this._misses++
            return $false
        }
        
        if ($this._cache.ContainsKey($key)) {
            $cached = $this._cache[$key]
            
            # Validate hash matches
            if ($cached.ContentHash -eq $contentHash) {
                # Cache HIT - update LRU order
                $this._UpdateLRU($key)
                $result.Value = $cached
                $this._hits++
                
                # Debug logging
                if ((Test-Path variable:global:PmcTuiLogFile) -and (Test-Path variable:global:PmcDebugLevel) -and $global:PmcDebugLevel -ge 3) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [RenderCache] HIT: $key"
                }
                
                return $true
            }
            
            # Hash mismatch - stale entry, remove it
            $this._Remove($key)
        }
        
        $this._misses++
        
        # Debug logging
        if ((Test-Path variable:global:PmcTuiLogFile) -and (Test-Path variable:global:PmcDebugLevel) -and $global:PmcDebugLevel -ge 3) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [RenderCache] MISS: $key"
        }
        
        return $false
    }
    
    <#
    .SYNOPSIS
    Store a widget snapshot in the cache
    
    .PARAMETER key
    Cache key
    
    .PARAMETER contentHash
    Hash of widget state
    
    .PARAMETER cached
    CachedWidget with cell snapshot
    #>
    [void] Store([string]$key, [string]$contentHash, [CachedWidget]$cached) {
        if ([string]::IsNullOrEmpty($key) -or [string]::IsNullOrEmpty($contentHash)) {
            return
        }
        
        # Set hash on cached object
        $cached.ContentHash = $contentHash
        
        # Remove existing entry if present
        if ($this._cache.ContainsKey($key)) {
            $this._Remove($key)
        }
        
        # Evict oldest entries if at capacity
        while ($this._cache.Count -ge $this._maxEntries) {
            $this._EvictOldest()
        }
        
        # Store new entry
        $this._cache[$key] = $cached
        [void]$this._lruOrder.AddLast($key)
        
        # Debug logging
        if ((Test-Path variable:global:PmcTuiLogFile) -and (Test-Path variable:global:PmcDebugLevel) -and $global:PmcDebugLevel -ge 3) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [RenderCache] STORE: $key (count=$($this._cache.Count))"
        }
    }
    
    <#
    .SYNOPSIS
    Invalidate a specific cache entry
    
    .PARAMETER key
    Cache key to invalidate
    #>
    [void] Invalidate([string]$key) {
        if ($this._cache.ContainsKey($key)) {
            $this._Remove($key)
        }
    }
    
    <#
    .SYNOPSIS
    Clear all cache entries
    
    .DESCRIPTION
    Called on screen transitions and theme changes
    #>
    [void] Clear() {
        $this._cache.Clear()
        $this._lruOrder.Clear()
        
        if ((Test-Path variable:global:PmcTuiLogFile) -and (Test-Path variable:global:PmcDebugLevel) -and $global:PmcDebugLevel -ge 2) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [RenderCache] CLEAR: all entries removed"
        }
    }
    
    <#
    .SYNOPSIS
    Get cache statistics
    
    .OUTPUTS
    Hashtable with hits, misses, count, hit rate
    #>
    [hashtable] GetStats() {
        $total = $this._hits + $this._misses
        $hitRate = if ($total -gt 0) { [Math]::Round(($this._hits / $total) * 100, 1) } else { 0 }
        
        return @{
            Hits = $this._hits
            Misses = $this._misses
            Count = $this._cache.Count
            MaxEntries = $this._maxEntries
            HitRate = $hitRate
        }
    }
    
    <#
    .SYNOPSIS
    Build a cache key for a widget
    
    .PARAMETER widgetType
    Widget class name
    
    .PARAMETER widgetName
    Widget instance name
    
    .PARAMETER x, y, width, height
    Widget bounds
    
    .PARAMETER zIndex
    Widget Z-layer
    #>
    static [string] BuildKey([string]$widgetType, [string]$widgetName, [int]$x, [int]$y, [int]$width, [int]$height, [int]$zIndex) {
        return "${widgetType}:${widgetName}:${x},${y},${width},${height}:${zIndex}"
    }
    
    # --- Private Methods ---
    
    hidden [void] _UpdateLRU([string]$key) {
        # Move key to end of LRU list (most recently used)
        $node = $this._lruOrder.Find($key)
        if ($node) {
            $this._lruOrder.Remove($node)
            [void]$this._lruOrder.AddLast($key)
        }
    }
    
    hidden [void] _Remove([string]$key) {
        $this._cache.Remove($key)
        $node = $this._lruOrder.Find($key)
        if ($node) {
            $this._lruOrder.Remove($node)
        }
    }
    
    hidden [void] _EvictOldest() {
        if ($this._lruOrder.Count -gt 0) {
            $oldestKey = $this._lruOrder.First.Value
            $this._Remove($oldestKey)
            
            if ((Test-Path variable:global:PmcTuiLogFile) -and (Test-Path variable:global:PmcDebugLevel) -and $global:PmcDebugLevel -ge 3) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [RenderCache] EVICT: $oldestKey"
            }
        }
    }
}

# Export classes
