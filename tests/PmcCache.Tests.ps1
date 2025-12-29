
# PmcCache.Tests.ps1
$ErrorActionPreference = 'Stop'

# Load PmcCache
$moduleRoot = Resolve-Path "$PSScriptRoot/../module/Pmc.Strict"
. "$moduleRoot/Core/PmcCache.ps1"

Write-Host "Starting PmcCache Tests..." -ForegroundColor Cyan

# Helper
function Assert-True($condition, $msg) {
    if (-not $condition) { throw "FAIL: $msg" }
    Write-Host "PASS: $msg" -ForegroundColor Green
}

function Assert-Equal($expected, $actual, $msg) {
    if ($expected -ne $actual) { throw "FAIL: $msg (Expected: '$expected', Actual: '$actual')" }
    Write-Host "PASS: $msg" -ForegroundColor Green
}

# 1. Singleton
$cache = [PmcCache]::GetInstance()
Assert-True ($null -ne $cache) "Singleton instance created"

# 2. Basic Set/Get
$cache.Set("Test", "Key1", "Value1")
$val = $cache.Get("Test", "Key1")
Assert-Equal "Value1" $val "Basic Set/Get works"

# 3. Region Isolation
$cache.Set("Other", "Key1", "Value2")
$val1 = $cache.Get("Test", "Key1")
$val2 = $cache.Get("Other", "Key1")
Assert-Equal "Value1" $val1 "Region Test preserved"
Assert-Equal "Value2" $val2 "Region Other preserved"

# 4. LRU Eviction
$cache.CreateRegion("LRU", 3) # Max 3 items
$cache.Set("LRU", "A", 1)
$cache.Set("LRU", "B", 2)
$cache.Set("LRU", "C", 3)
$cache.Set("LRU", "D", 4) # Should evict A

Assert-True ($null -eq $cache.Get("LRU", "A")) "Item A evicted"
Assert-Equal 2 ($cache.Get("LRU", "B")) "Item B remains"
Assert-Equal 4 ($cache.Get("LRU", "D")) "Item D exists"

# Access B to make it MRU, then add E. C should be evicted.
[void]$cache.Get("LRU", "B")
$cache.Set("LRU", "E", 5)
Assert-True ($null -eq $cache.Get("LRU", "C")) "Item C evicted (LRU)"
Assert-Equal 2 ($cache.Get("LRU", "B")) "Item B remains (MRU)"

# 5. TTL
$cache.CreateRegion("TTL", 100)
$cache.Set("TTL", "A", 1, @(), [TimeSpan]::FromMilliseconds(100))
Start-Sleep -Milliseconds 50
Assert-Equal 1 ($cache.Get("TTL", "A")) "Item A valid before TTL"
Start-Sleep -Milliseconds 100
Assert-True ($null -eq $cache.Get("TTL", "A")) "Item A expired after TTL"

# 6. Tags
$cache.CreateRegion("Tags", 100)
$cache.Set("Tags", "A", 1, @("tag1"))
$cache.Set("Tags", "B", 2, @("tag1", "tag2"))
$cache.Set("Tags", "C", 3, @("tag2"))

$cache.InvalidateTag("tag1")
Assert-True ($null -eq $cache.Get("Tags", "A")) "Item A invalidated by tag1"
Assert-True ($null -eq $cache.Get("Tags", "B")) "Item B invalidated by tag1"
Assert-Equal 3 ($cache.Get("Tags", "C")) "Item C remains (no tag1)"

# 7. Stats
$stats = $cache.GetStats()
Write-Host "Stats: $($stats | ConvertTo-Json -Depth 2)" -ForegroundColor Gray
Assert-True ($stats.Test.Hits -gt 0) "Stats tracking hits"

Write-Host "All Tests Passed!" -ForegroundColor Cyan
