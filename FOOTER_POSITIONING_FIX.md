# Footer Positioning Bug Fix

## Issue
The footer was appearing in the header area visually, causing visual layout corruption in the PMC TUI application.

## Root Cause
The `Resize()` method in `PmcScreen.ps1` had conflicting and incorrect positioning logic:

```powershell
# BEFORE (buggy code):
# Line 103-104: Footer positioned at WRONG location
$this.Footer.SetPosition(0, $height - 1)  # ← BUG: Should be height-2

# Line 109-110: StatusBar positioned at WRONG location
$this.StatusBar.SetPosition(0, $height - 2)  # ← BUG: Should be height-1
```

**The Problem**:
- Footer and StatusBar positions were SWAPPED
- Footer was at the very bottom line (`height - 1`) when it should be one line above (`height - 2`)
- This conflicted with the CORRECT positioning in `ApplyLayout()` which uses `PmcLayoutManager`

## Technical Analysis

### Correct Layout Definitions (PmcLayoutManager.ps1)
```powershell
'Footer' = @{
    Y = 'BOTTOM-2'  # → Resolves to: termHeight - 2
}

'StatusBar' = @{
    Y = 'BOTTOM'    # → Resolves to: termHeight - 1
}
```

### Why the Bug Manifested
1. **Initial Load**: `ApplyLayout()` runs during screen initialization with CORRECT positions
2. **Later**: If `Resize()` is called (e.g., terminal resize or subclass override), it OVERWRITES with WRONG positions
3. **Result**: Visual corruption - Footer appears in wrong location

### Code Flow
```
PmcApplication.PushScreen()
  → Screen.Initialize()
    → Screen.ApplyLayout()  [CORRECT - uses PmcLayoutManager]

Terminal resize event
  → Screen.OnTerminalResize()
    → Screen.Resize()  [BUG - had conflicting positions]
      → This would OVERWRITE the correct positions from ApplyLayout()
```

## Solution
**Commit**: `93c3a2a`

Changed `Resize()` to simply delegate to `ApplyLayout()`:

```powershell
[void] Resize([int]$width, [int]$height) {
    $this.TermWidth = $width
    $this.TermHeight = $height

    # Delegate to ApplyLayout for correct positioning
    # ApplyLayout uses PmcLayoutManager which has the correct constraints:
    # - Footer: Y = 'BOTTOM-2' (height - 2)
    # - StatusBar: Y = 'BOTTOM' (height - 1)
    if ($this.LayoutManager) {
        $this.ApplyLayout($this.LayoutManager, $width, $height)
    }
}
```

## Benefits
1. **Single Source of Truth**: PmcLayoutManager is now the only place defining layout constraints
2. **No Duplication**: Eliminated 30+ lines of redundant positioning code
3. **Correct by Default**: All positioning goes through ApplyLayout which uses verified constraints
4. **Maintainability**: Future layout changes only need to update PmcLayoutManager
5. **Consistency**: Same logic path whether called initially or on resize

## Files Changed
- `PmcScreen.ps1`: Simplified `Resize()` method (removed ~35 lines of buggy code)
- `Start-PmcTUI.ps1`: Minor formatting changes

## Testing

### How to Test
1. Start the application:
   ```bash
   pwsh /home/teej/ztest/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1
   ```

2. Verify positioning:
   - Footer should appear at the **second-to-last line**
   - StatusBar should appear at the **very bottom line**
   - Header should appear near the top (around line 3)
   - No visual overlap between widgets

3. Resize the terminal:
   - Should maintain correct positions when window is resized
   - Footer should stay 2 lines from bottom

### Verification Points
- ✓ Footer at `height - 2`
- ✓ StatusBar at `height - 1`
- ✓ Header at `Y = 3`
- ✓ No visual overlap
- ✓ Resize events maintain correct layout

## Affected Components
- **Primary**: PmcScreen base class (all screens inherit this)
- **Related**:
  - PmcLayoutManager (correct constraints)
  - PmcApplication (initialization order)
  - StandardListScreen (calls Resize() during setup)
  - All subclasses using inherited Resize() method

## Backward Compatibility
- ✓ Fully backward compatible
- ✓ Existing subclasses continue to work without changes
- ✓ No API changes
- ✓ Only internal implementation was changed

## Edge Cases Handled
1. **Screens without LayoutManager**: The `if ($this.LayoutManager)` check ensures no errors
2. **Terminal resize events**: Now correctly use ApplyLayout() path
3. **Dynamic screen switching**: Each screen maintains correct layout

## Prevention for Future Issues
- This fix establishes a pattern: Always delegate positioning logic to the layout manager
- Never duplicate positioning constraints in multiple methods
- Use PmcLayoutManager as the single source of truth for all layout decisions
