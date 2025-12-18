# Gradient Themes Research
## Updated: 2025-12-17 (Engine Code Verified)

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

## Implementation

### Helper Function (~20 lines)

```powershell
function Get-GradientText {
    param(
        [string]$Text,
        [string]$StartHex,
        [string]$EndHex
    )
    
    $sb = [System.Text.StringBuilder]::new()
    $len = $Text.Length
    
    # Parse start/end colors
    $sR = [Convert]::ToInt32($StartHex.Substring(1,2), 16)
    $sG = [Convert]::ToInt32($StartHex.Substring(3,2), 16)
    $sB = [Convert]::ToInt32($StartHex.Substring(5,2), 16)
    $eR = [Convert]::ToInt32($EndHex.Substring(1,2), 16)
    $eG = [Convert]::ToInt32($EndHex.Substring(3,2), 16)
    $eB = [Convert]::ToInt32($EndHex.Substring(5,2), 16)
    
    for ($i = 0; $i -lt $len; $i++) {
        $ratio = if ($len -eq 1) { 0 } else { $i / ($len - 1) }
        $r = [int]($sR + ($eR - $sR) * $ratio)
        $g = [int]($sG + ($eG - $sG) * $ratio)
        $b = [int]($sB + ($eB - $sB) * $ratio)
        [void]$sb.Append("`e[38;2;$r;$g;${b}m$($Text[$i])")
    }
    [void]$sb.Append("`e[0m")  # Reset at end
    
    return $sb.ToString()
}
```

### Usage

```powershell
# Where gradient text is wanted:
$title = Get-GradientText -Text "Synthwave Theme" -StartHex "#ff00ff" -EndHex "#00ffff"
$engine.WriteAt($x, $y, $title)

# Regular widgets unchanged:
$engine.WriteAt($x, $y, "Normal text", $fg, $bg)
```

---

## Files To Modify

| File | Change |
|------|--------|
| `consoleui/helpers/ThemeHelper.ps1` | Add `Get-GradientText` function |
| Any screen wanting gradients | Call helper, use 3-arg WriteAt |

**Widgets unchanged. Engine unchanged.**
