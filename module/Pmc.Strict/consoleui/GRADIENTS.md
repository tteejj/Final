# Gradient Themes Research
## Updated: 2025-12-18 (Widget Integration Analysis)

> Research for implementing foreground/text gradient themes.  
> Background gradients are already handled by the render engine.

---

## Engine Architecture Verified

**File:** `/home/teej/ztest/lib/SpeedTUI/Core/HybridRenderEngine.ps1`

### Two WriteAt Overloads

| Signature | Behavior |
|-----------|----------|
| `WriteAt(x, y, content)` | **Parses embedded ANSI** - per-char color in cell buffer |
| `WriteAt(x, y, content, fg, bg)` | **Uniform color** - ignores embedded ANSI |

### How ANSI Parsing Works (Lines 305-390)

```powershell
while ($i -lt $len) {
    if ($content[$i] -eq "`e" -and $content[$i + 1] -eq '[') {
        # Parse ANSI, update currentFg/currentBg state
        $this._ParseAnsiState($cmd, $paramStr, [ref]$currentFg, [ref]$currentBg, ...)
        continue
    }
    # Write cell with CURRENT color state (which ANSI just updated)
    $this._backBuffer.SetCell($currentX, $finalY, $content[$i], $currentFg, $currentBg, ...)
}
```

**Key:** Each character stored with its own FG/BG color in cell buffer. Differential rendering intact.

---

## Recommended Approach: Embedded ANSI String

Build gradient text with per-character ANSI codes, pass as one string:

```powershell
$gradientText = Get-GradientText -Text "Hello" -StartHex "#ff00ff" -EndHex "#00ffff"
# Returns: "\e[38;2;255;0;255mH\e[38;2;200;0;255me\e[38;2;150;0;255ml..."

$engine.WriteAt($x, $y, $gradientText)  # 3-arg version, no fg/bg
```

**Result:**
- One WriteAt call
- Per-character gradient colors
- Cell buffer tracks each character separately
- Differential rendering works correctly
- Widgets unchanged

---

## GradientHelper.ps1 - Already Implemented

Located at `consoleui/helpers/GradientHelper.ps1`:

| Function | Purpose |
|----------|---------|
| `Get-GradientText` | Returns ANSI string with gradient |
| `Write-GradientAt` | Writes per-char to engine with int colors |
| `Get-SynthwaveGradient` | Preset magenta→cyan |
| `Write-SynthwaveGradientAt` | Preset direct render |

---

## Widget Integration Analysis (2025-12-18)

### Current Widget Pattern

All widgets use the **5-argument WriteAt** which applies uniform colors:

```powershell
$fg = $this.GetThemedInt('Foreground.Title')      # Returns packed int
$bg = $this.GetThemedBgInt('Background.Widget', $width, 0)
$engine.WriteAt($x, $y, "Some text", $fg, $bg)    # Uniform color
```

**Widgets bypass gradient support** by never using the 3-arg overload.

### Why 5-arg vs 3-arg?

| Overload | Performance | Gradient | Use Case |
|----------|-------------|----------|----------|
| 5-arg `(x,y,text,fg,bg)` | Fastest | ❌ No | Data rows, most UI |
| 3-arg `(x,y,ansiText)` | ANSI parse overhead | ✅ Yes | Titles, accents |

**Widgets use 5-arg for performance** - parsing ANSI per-character is slower for bulk content like list rows.

### PmcThemeEngine Already Has Gradient Plumbing

```powershell
# PmcThemeEngine.GetBackgroundAnsi() supports both:
if ($prop.Type -eq 'Solid') {
    return $this._GetSolidAnsiCached($prop.Color, $true)
}
elseif ($prop.Type -eq 'Gradient') {
    $gradient = $this._GetGradientArrayCached($propertyName, $prop, $width, $true)
    return $gradient[$charIndex]  # Per-char gradient!
}
```

But widgets don't call per-character - they get one color and apply to whole string.

---

## Implementation Strategy: Option C (Theme-Declared Gradients)

### Phase 1: Theme Schema (No Widget Changes)

Themes declare gradient specs in `_BuildThemeProperties`:

```powershell
'Foreground.Title' = @{ 
    Type = 'Gradient'
    Direction = 'Horizontal'
    Stops = @(
        @{ Position = 0.0; Color = '#ff00ff' }
        @{ Position = 1.0; Color = '#00ffff' }
    )
}
```

### Phase 2: Helper in PmcWidget

Add `WriteThemedText` that auto-detects gradient vs solid:

```powershell
[void] WriteThemedText($engine, $x, $y, $text, $fgProp, $bgProp) {
    $propInfo = [PmcThemeEngine]::GetInstance().GetPropertyInfo($fgProp)
    if ($propInfo.Type -eq 'Gradient') {
        Write-GradientAt -Engine $engine -X $x -Y $y -Text $text ...
    } else {
        $engine.WriteAt($x, $y, $text, $this.GetThemedInt($fgProp), ...)
    }
}
```

### Phase 3: Opt-In Per Widget

Only widgets wanting gradients upgrade to `WriteThemedText`. Others unchanged.

---

## Screens vs Widgets

### Current Widgets (consoleui/widgets/)

| Widget | Purpose | Gradient Candidate? |
|--------|---------|---------------------|
| PmcHeader | App title bar | ✅ Yes - titles look great |
| PmcFooter | Keybind hints | Maybe - short text |
| PmcMenuBar | Menu items | Maybe |
| UniversalList | Data rows | ❌ No - performance |
| TextInput | Input fields | ❌ No |
| TagEditor | Tag chips | Maybe |
| DatePicker | Calendar popup | ❌ No |
| ProjectPicker | Project selector | ❌ No |

**Most widgets don't need gradients** - they display data, not decorative text.

### Screens Can Use Gradients Directly

Screens control their own `RenderToEngine()`:

```powershell
# ThemeEditorScreen already does this:
$title = Get-SynthwaveGradient "Synthwave Theme"
$engine.WriteAt($x, $y, $title)  # 3-arg, gradient works!
```

**Screens don't need widget changes** - they can call `Get-GradientText` directly.

---

## Full Gradient Theme Without Widget Changes?

**YES.** Here's what can be gradient TODAY without touching widgets:

| Element | How | Works Now? |
|---------|-----|------------|
| Screen titles | Screen calls `Get-GradientText` | ✅ |
| Theme preview text | Screen calls helper | ✅ |
| About screen | Screen renders accent text | ✅ |
| Help screen | Screen renders headers | ✅ |

**Widgets showing data (lists, forms) stay solid** - which is correct. Data should be readable, not decorative.

---

## Semantic Colors (Overdue, Priority)

Currently hardcoded in `UI.ps1 Get-PmcCellStyle`:

```powershell
switch ($p) {
    '1' { return @{ Fg = 'Red';    Bold = $true } }  # HARDCODED
    '2' { return @{ Fg = 'Yellow'; Bold = $true } }
}
if ($dt.Date -lt $today) { return @{ Fg = 'Red'; Bold = $true } }  # HARDCODED
```

**Fix:** Add to `_BuildThemeProperties`:

```powershell
'Semantic.Priority1' = @{ Type = 'Solid'; Color = '#ff5555' }
'Semantic.Priority2' = @{ Type = 'Solid'; Color = '#ffcc00' }
'Semantic.Overdue'   = @{ Type = 'Solid'; Color = '#ff3333' }
'Semantic.DueSoon'   = @{ Type = 'Solid'; Color = '#ffaa00' }
```

Then `Get-PmcCellStyle` queries theme instead of hardcoding.

---

## Summary

- **Gradient infrastructure exists** - Engine parses per-char ANSI
- **Widgets don't need changes for v1** - screens can use gradients directly
- **Widgets use 5-arg for performance** - correct for data display
- **Option C is best** - theme declares, widgets opt-in later
- **Semantic colors** just need properties added to theme
- **Headers/footers** are still useful for consistent chrome
