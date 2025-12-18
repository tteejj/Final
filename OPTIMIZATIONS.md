# Performance Optimization Implementation Plan

The PMC TUI application suffers from significant performance issues caused by architectural inefficiencies, not just surface-level string operations. This plan addresses the root causes in priority order.

## User Review Required

> [!IMPORTANT]
> **Breaking Change Risk**: The layout caching (Phase 2) changes how `DataDisplay` handles resize events. Existing code that relies on per-frame recalculation may need adjustment.

> [!WARNING]
> **Scope Decision**: This plan has 4 phases. Phases 1-2 provide ~80% of the gains. Should we implement all 4, or start with 1-2 and measure before proceeding?

---

## Proposed Changes

### Phase 1: Terminal Dimension Singleton (High Impact, Low Effort)

**Goal**: Eliminate redundant `[Console]::WindowWidth/Height` syscalls (currently 64+ call sites)

#### [MODIFY] [PmcTerminalService](file:///home/teej/ztest/module/Pmc.Strict/src/TerminalDimensions.ps1)

- Add frame-rate limited refresh (max 1 check per 100ms instead of per-call)
- Add `OnResize` event for listeners
- Change from 500ms cache to event-driven + 100ms fallback poll

```diff
 static [hashtable] GetDimensions() {
     $now = [datetime]::Now
-    if (($now - [PmcTerminalService]::LastUpdate).TotalMilliseconds -lt [PmcTerminalService]::CacheValidityMs -and
+    # Only refresh cache if explicitly invalidated or 100ms passed
+    if (($now - [PmcTerminalService]::LastUpdate).TotalMilliseconds -lt 100 -and
         [PmcTerminalService]::CachedWidth -gt 0) {
         return @{ Width = ...; IsCached = $true }
     }
```

#### [MODIFY] [PmcApplication.ps1](file:///home/teej/ztest/module/Pmc.Strict/consoleui/PmcApplication.ps1)

- Replace inline `[Console]::WindowWidth` checks with single `PmcTerminalService` call
- Move resize check to once per 10 iterations (already partially done, complete it)

#### [MODIFY] Multiple widget files

Files with direct `[Console]::WindowWidth` calls to convert:
- `PmcWidget.ps1:634`
- `InlineEditor.ps1:1071`
- `DatePicker.ps1:276`
- `ProjectPicker.ps1:443`
- `TimeListScreen.ps1:653`
- `ExcelImportScreen.ps1:647`

---

### Phase 2: Layout Pre-computation and Caching (Very High Impact, Medium Effort)

**Goal**: Compute column widths and static elements once on data load/resize, not every frame

#### [MODIFY] [DataDisplay.ps1](file:///home/teej/ztest/module/Pmc.Strict/src/DataDisplay.ps1)

Add cached layout state:

```powershell
# New properties
hidden [hashtable]$_cachedWidths = @{}
hidden [string]$_cachedHeaderLine = ""
hidden [string]$_cachedSeparatorLine = ""
hidden [bool]$_layoutDirty = $true

# New method
[void] InvalidateLayout() {
    $this._layoutDirty = $true
}

# Modified BuildInteractiveLines()
[object[]] BuildInteractiveLines() {
    # Only recalc layout when dirty
    if ($this._layoutDirty) {
        $this._cachedWidths = $this.GetColumnWidths($this.CurrentData)
        $this._cachedHeaderLine = $this.FormatRow($null, $this._cachedWidths, $true, -1, $false)
        $this._cachedSeparatorLine = $this._BuildSeparatorLine($this._cachedWidths)
        $this._layoutDirty = $false
    }
    # Use cached values instead of recalculating
    ...
}
```

Call `InvalidateLayout()` from:
- `RefreshData()` (data changed)
- Resize handler (terminal dimensions changed)
- `ApplyDoFilter()` (filtered data may have different widths)

---

### Phase 3: Row Caching System (Very High Impact, Medium Effort)

**Goal**: Cache formatted row strings, only rebuild changed rows

#### [MODIFY] [DataDisplay.ps1](file:///home/teej/ztest/module/Pmc.Strict/src/DataDisplay.ps1)

Add row cache:

```powershell
hidden [hashtable]$_rowCache = @{}  # Key: row index, Value: formatted string
hidden [hashtable]$_rowHashes = @{} # Key: row index, Value: data hash for invalidation

[string] GetCachedRow([int]$index, [object]$item, [hashtable]$widths, [bool]$isSelected) {
    $hash = $this._ComputeRowHash($item, $isSelected)
    
    if ($this._rowCache.ContainsKey($index) -and $this._rowHashes[$index] -eq $hash) {
        return $this._rowCache[$index]
    }
    
    $formatted = $this.FormatRow($item, $widths, $false, $index, $isSelected)
    $this._rowCache[$index] = $formatted
    $this._rowHashes[$index] = $hash
    return $formatted
}

[void] InvalidateRowCache() {
    $this._rowCache.Clear()
    $this._rowHashes.Clear()
}
```

---

### Phase 4: StringBuilder/List[T] Conversions (Medium Impact, Easy Effort)

**Goal**: Replace O(n²) string/array concatenation with O(n) operations

#### [MODIFY] [TerminalDimensions.ps1](file:///home/teej/ztest/module/Pmc.Strict/src/TerminalDimensions.ps1)

Convert `TruncateWithAnsi` and `EnforceContentBounds`:

```diff
 static [string] TruncateWithAnsi([string]$Text, [int]$MaxWidth) {
-    $result = ""
+    $sb = [System.Text.StringBuilder]::new($Text.Length)
     ...
     foreach ($part in $parts) {
         if ($part -match $ansiPattern) {
-            $result += $part
+            [void]$sb.Append($part)
         }
     }
-    return $result
+    return $sb.ToString()
 }
```

#### [MODIFY] [DataDisplay.ps1](file:///home/teej/ztest/module/Pmc.Strict/src/DataDisplay.ps1)

Convert `ApplyDoFilter`:

```diff
 [void] ApplyDoFilter() {
-    $filtered = @()
+    $filtered = [System.Collections.Generic.List[object]]::new()
     foreach ($it in $this.AllData) {
         ...
-        if ($hay.Contains($q)) { $filtered += $it }
+        if ($hay.Contains($q)) { $filtered.Add($it) }
     }
+    $this.CurrentData = $filtered.ToArray()
 }
```

---

## Verification Plan

### Automated Tests

Existing Pester tests to run after each phase:

```bash
# Run all Pester tests
cd /home/teej/ztest/module/Pmc.Strict/consoleui/tests
pwsh -Command "Invoke-Pester -Path . -Output Detailed"
```

Specific tests relevant to changes:
- `TaskStore.Tests.ps1` - data operations
- `PmcApplication.Tests.ps1` - render loop
- `UIFunctional.Tests.ps1` - UI interactions

### Manual Verification

**Phase 1 (Terminal caching):**
1. Launch TUI: `pwsh /home/teej/ztest/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1`
2. Resize terminal window multiple times rapidly
3. Verify UI redraws correctly without lag or corruption
4. Navigate through menus - should feel snappier

**Phase 2 (Layout caching):**
1. Load task list with 50+ tasks
2. Scroll up/down rapidly
3. Resize terminal - columns should adjust
4. Add/edit task - verify layout updates

**Phase 3 (Row caching):**
1. Scroll through list
2. Verify no visual corruption
3. Edit a task inline - verify that row updates while others remain stable
4. Use arrow keys - cursor movement should be instant

**Phase 4 (StringBuilder):**
1. Open task list with tasks containing long text (100+ chars)
2. Apply filter with complex query
3. Verify no truncation bugs
4. Resize terminal - verify ANSI codes still render correctly

### Performance Benchmarking

Create a simple timing script (to be added) that measures:
- Time to render 100 items
- Time to scroll 50 rows
- Memory usage before/after large list load

---

## Implementation Order

| Phase | Effort | Impact | Dependencies |
|-------|--------|--------|--------------|
| 1. Terminal Singleton | 2 hours | High | None |
| 2. Layout Caching | 4 hours | Very High | Phase 1 |
| 3. Row Caching | 4 hours | Very High | Phase 2 |
| 4. StringBuilder | 2 hours | Medium | None (can parallelize) |

**Recommended approach**: Implement Phase 1 + 4 together (easy wins), then Phase 2, then Phase 3. Measure after each phase.
