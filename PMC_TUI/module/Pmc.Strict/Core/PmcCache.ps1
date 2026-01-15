using namespace System.Collections.Generic
using namespace System.Collections.Concurrent
using namespace System.Threading

<#
.SYNOPSIS
Unified Caching Engine for PMC

.DESCRIPTION
Provides a thread-safe, region-based caching system with LRU eviction and tag-based invalidation.
Replaces ad-hoc caching in PmcThemeEngine, EnhancedQueryEngine, etc.

.FEATURES
- Regions: Partition data (e.g., "Query", "Theme", "Render")
- Tags: Invalidate groups of items (e.g., "domain:task")
- LRU: Least Recently Used eviction per region
- TTL: Time-To-Live support
- Thread Safety: Full concurrency support
#>
class PmcCacheEntry {
    [object]$Value
    [string[]]$Tags
    [datetime]$Created
    [datetime]$Expires
    [long]$Hits

    PmcCacheEntry([object]$value, [string[]]$tags, [timespan]$ttl) {
        $this.Value = $value
        $this.Tags = $tags
        $this.Created = [datetime]::Now
        $this.Hits = 0
        
        if ($ttl.TotalMilliseconds -gt 0) {
            $this.Expires = $this.Created.Add($ttl)
        } else {
            $this.Expires = [datetime]::MaxValue
        }
    }

    [bool] IsExpired() {
        return [datetime]::Now -gt $this.Expires
    }
}

class PmcCacheRegion {
    [string]$Name
    [int]$Capacity
    [Dictionary[string, PmcCacheEntry]]$Storage
    [LinkedList[string]]$LruList
    [Dictionary[string, LinkedListNode[string]]]$LruNodes
    [object]$Lock

    # Stats
    [long]$Hits
    [long]$Misses
    [long]$Evictions

    PmcCacheRegion([string]$name, [int]$capacity) {
        $this.Name = $name
        $this.Capacity = $capacity
        $this.Storage = [Dictionary[string, PmcCacheEntry]]::new()
        $this.LruList = [LinkedList[string]]::new()
        $this.LruNodes = [Dictionary[string, LinkedListNode[string]]]::new()
        $this.Lock = [object]::new()
        $this.Hits = 0
        $this.Misses = 0
        $this.Evictions = 0
    }
}

class PmcCache {
    static hidden [PmcCache]$_instance = $null
    static hidden [object]$_instanceLock = [object]::new()

    hidden [Dictionary[string, PmcCacheRegion]]$_regions
    hidden [Dictionary[string, HashSet[string]]]$_tagIndex # Tag -> Set of "Region:Key"
    hidden [object]$_globalLock

    PmcCache() {
        $this._regions = [Dictionary[string, PmcCacheRegion]]::new()
        $this._tagIndex = [Dictionary[string, HashSet[string]]]::new()
        $this._globalLock = [object]::new()
        
        # Initialize default regions
        $this.CreateRegion("Default", 1000)
        $this.CreateRegion("Query", 500)
        $this.CreateRegion("Theme", 2000) # High capacity for colors
        $this.CreateRegion("Render", 1000)
    }

    static [PmcCache] GetInstance() {
        if ($null -eq [PmcCache]::_instance) {
            [System.Threading.Monitor]::Enter([PmcCache]::_instanceLock)
            try {
                if ($null -eq [PmcCache]::_instance) {
                    [PmcCache]::_instance = [PmcCache]::new()
                }
            }
            finally {
                [System.Threading.Monitor]::Exit([PmcCache]::_instanceLock)
            }
        }
        return [PmcCache]::_instance
    }

    # === Region Management ===

    [void] CreateRegion([string]$name, [int]$capacity) {
        [System.Threading.Monitor]::Enter($this._globalLock)
        try {
            if (-not $this._regions.ContainsKey($name)) {
                $this._regions[$name] = [PmcCacheRegion]::new($name, $capacity)
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this._globalLock)
        }
    }

    [void] ClearRegion([string]$name) {
        [System.Threading.Monitor]::Enter($this._globalLock)
        try {
            if ($this._regions.ContainsKey($name)) {
                $region = $this._regions[$name]
                [System.Threading.Monitor]::Enter($region.Lock)
                try {
                    # Remove from tag index first
                    foreach ($key in $region.Storage.Keys) {
                        $entry = $region.Storage[$key]
                        $this._RemoveFromTagIndex($name, $key, $entry.Tags)
                    }
                    
                    $region.Storage.Clear()
                    $region.LruList.Clear()
                    $region.LruNodes.Clear()
                    $region.Hits = 0
                    $region.Misses = 0
                    $region.Evictions = 0
                }
                finally {
                    [System.Threading.Monitor]::Exit($region.Lock)
                }
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this._globalLock)
        }
    }

    # === Core Caching API ===

    [void] Set([string]$regionName, [string]$key, [object]$value) {
        $this.Set($regionName, $key, $value, @(), [timespan]::Zero)
    }

    [void] Set([string]$regionName, [string]$key, [object]$value, [string[]]$tags) {
        $this.Set($regionName, $key, $value, $tags, [timespan]::Zero)
    }

    [void] Set([string]$regionName, [string]$key, [object]$value, [string[]]$tags, [timespan]$ttl) {
        $region = $this._GetRegion($regionName)
        if ($null -eq $region) { return }

        [System.Threading.Monitor]::Enter($region.Lock)
        try {
            # Check capacity and evict if needed (only if new key)
            if (-not $region.Storage.ContainsKey($key) -and $region.Storage.Count -ge $region.Capacity) {
                $this._EvictLru($region)
            }

            # Create entry
            $entry = [PmcCacheEntry]::new($value, $tags, $ttl)

            # Update storage
            $region.Storage[$key] = $entry

            # Update LRU
            if ($region.LruNodes.ContainsKey($key)) {
                $region.LruList.Remove($region.LruNodes[$key])
            }
            $node = $region.LruList.AddFirst($key)
            $region.LruNodes[$key] = $node

            # Update Tag Index
            if ($tags -and $tags.Count -gt 0) {
                $this._AddToTagIndex($regionName, $key, $tags)
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($region.Lock)
        }
    }

    [object] Get([string]$regionName, [string]$key) {
        $region = $this._GetRegion($regionName)
        if ($null -eq $region) { return $null }

        [System.Threading.Monitor]::Enter($region.Lock)
        try {
            if ($region.Storage.ContainsKey($key)) {
                $entry = $region.Storage[$key]
                
                # Check Expiration
                if ($entry.IsExpired()) {
                    $this._Remove($region, $key)
                    $region.Misses++
                    return $null
                }

                # Update LRU (Move to front)
                if ($region.LruNodes.ContainsKey($key)) {
                    $region.LruList.Remove($region.LruNodes[$key])
                    $node = $region.LruList.AddFirst($key)
                    $region.LruNodes[$key] = $node
                }

                $entry.Hits++
                $region.Hits++
                return $entry.Value
            }
            else {
                $region.Misses++
                return $null
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($region.Lock)
        }
    }

    [bool] TryGet([string]$regionName, [string]$key, [ref]$result) {
        $val = $this.Get($regionName, $key)
        if ($null -ne $val) {
            $result.Value = $val
            return $true
        }
        return $false
    }

    [void] Invalidate([string]$regionName, [string]$key) {
        $region = $this._GetRegion($regionName)
        if ($null -eq $region) { return }

        [System.Threading.Monitor]::Enter($region.Lock)
        try {
            $this._Remove($region, $key)
        }
        finally {
            [System.Threading.Monitor]::Exit($region.Lock)
        }
    }

    [void] InvalidateTag([string]$tag) {
        [System.Threading.Monitor]::Enter($this._globalLock)
        try {
            if ($this._tagIndex.ContainsKey($tag)) {
                $keys = [string[]]@($this._tagIndex[$tag]) # Copy to avoid modification during iteration
                
                foreach ($compositeKey in $keys) {
                    # Parse "Region:Key"
                    $parts = $compositeKey -split ':', 2
                    if ($parts.Count -eq 2) {
                        $rName = $parts[0]
                        $k = $parts[1]
                        $this.Invalidate($rName, $k)
                    }
                }
                
                # Clear tag index for this tag
                $this._tagIndex.Remove($tag)
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this._globalLock)
        }
    }

    # === Internal Helpers ===

    hidden [PmcCacheRegion] _GetRegion([string]$name) {
        if ($this._regions.ContainsKey($name)) {
            return $this._regions[$name]
        }
        # Auto-create if missing? Or return null?
        # For safety, let's auto-create with default size
        $this.CreateRegion($name, 1000)
        return $this._regions[$name]
    }

    hidden [void] _EvictLru([PmcCacheRegion]$region) {
        if ($region.LruList.Count -eq 0) { return }

        $lastNode = $region.LruList.Last
        if ($null -ne $lastNode) {
            $key = $lastNode.Value
            $this._Remove($region, $key)
            $region.Evictions++
        }
    }

    hidden [void] _Remove([PmcCacheRegion]$region, [string]$key) {
        if ($region.Storage.ContainsKey($key)) {
            $entry = $region.Storage[$key]
            
            # Remove from storage
            $region.Storage.Remove($key)
            
            # Remove from LRU
            if ($region.LruNodes.ContainsKey($key)) {
                $region.LruList.Remove($region.LruNodes[$key])
                $region.LruNodes.Remove($key)
            }

            # Remove from Tag Index
            $this._RemoveFromTagIndex($region.Name, $key, $entry.Tags)
        }
    }

    hidden [void] _AddToTagIndex([string]$regionName, [string]$key, [string[]]$tags) {
        # Lock is held by caller (Set) or global lock needed?
        # Tag index is global, so we need global lock or concurrent dictionary
        # Using global lock for safety on tag index operations
        [System.Threading.Monitor]::Enter($this._globalLock)
        try {
            $compositeKey = "${regionName}:$key"
            foreach ($tag in $tags) {
                if (-not $this._tagIndex.ContainsKey($tag)) {
                    $this._tagIndex[$tag] = [HashSet[string]]::new()
                }
                [void]$this._tagIndex[$tag].Add($compositeKey)
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this._globalLock)
        }
    }

    hidden [void] _RemoveFromTagIndex([string]$regionName, [string]$key, [string[]]$tags) {
        [System.Threading.Monitor]::Enter($this._globalLock)
        try {
            $compositeKey = "${regionName}:$key"
            foreach ($tag in $tags) {
                if ($this._tagIndex.ContainsKey($tag)) {
                    [void]$this._tagIndex[$tag].Remove($compositeKey)
                    if ($this._tagIndex[$tag].Count -eq 0) {
                        $this._tagIndex.Remove($tag)
                    }
                }
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this._globalLock)
        }
    }

    # === Diagnostics ===

    [hashtable] GetStats() {
        $stats = @{}
        [System.Threading.Monitor]::Enter($this._globalLock)
        try {
            foreach ($rName in $this._regions.Keys) {
                $r = $this._regions[$rName]
                $stats[$rName] = @{
                    Count = $r.Storage.Count
                    Capacity = $r.Capacity
                    Hits = $r.Hits
                    Misses = $r.Misses
                    Evictions = $r.Evictions
                    HitRate = $(if ($r.Hits + $r.Misses -gt 0) { [Math]::Round(($r.Hits / ($r.Hits + $r.Misses)) * 100, 1) } else { 0 })
                }
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this._globalLock)
        }
        return $stats
    }
}
