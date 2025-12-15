# Terminal Size Detection Issue - Analysis

## Problem
Terminal size detected as **21x10** instead of actual screen size.

## Evidence
```
$ echo $COLUMNS x $LINES
21 x 10

$ tput cols && tput lines
21
10

$ stty size
10 21

$ pwsh -Command "[Console]::WindowWidth; [Console]::WindowHeight"
21
10
```

## Root Cause
The terminal size is actually 21x10 in the environment where the TUI is running.
This is NOT a detection bug - PowerShell is correctly reading the terminal size.

## Impact
1. **Rendering Corruption**: Widgets try to render in 21-column space
   - Text wraps incorrectly
   - Shows fragments like "B]" and "task"
   - List columns don't fit

2. **Screen Not Filling**: TUI renders for 21x10, not full screen

3. **Task Saving**: Likely works, but can't see confirmation due to rendering issues

## Solution Options

### Option 1: Resize Terminal (User Action Required)
User needs to resize their terminal window to proper size (e.g., 120x30 or larger).

### Option 2: Override Size Detection (Code Fix)
Modify PmcApplication to use minimum size if detected size is too small:

```powershell
hidden [void] _UpdateTerminalSize() {
    try {
        $width = [Console]::WindowWidth
        $height = [Console]::WindowHeight
        
        # Enforce minimum size
        $this.TermWidth = [Math]::Max($width, 80)
        $this.TermHeight = [Math]::Max($height, 24)
    }
    catch {
        $this.TermWidth = 80
        $this.TermHeight = 24
    }
}
```

### Option 3: Use tput/stty (Linux-specific)
Try to get size from tput instead of .NET Console API.

## Recommendation
**Option 1** - User should resize terminal.
The TUI is designed for terminals 80x24 minimum.
21x10 is too small for any TUI application.

## Testing Task Saving
Need to verify if tasks are actually being saved despite rendering issues.
Checking TaskStore.SaveData() implementation...
