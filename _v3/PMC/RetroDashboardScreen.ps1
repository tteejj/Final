#!/usr/bin/env pwsh
# RetroDashboardScreen.ps1 - V3: "NOSTROMO" Edition
# Aesthetic: Alien (1979) / Aliens (1986) Computer Terminal
# Features: Phosphor Green, Scanlines, "Mother" UI, Slide-out Details

using namespace System.Collections.Generic

Set-StrictMode -Version Latest

# --- 1. Load Dependencies ---
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = "." }

$nativeCorePath = Join-Path $scriptDir "NativeRenderCore.ps1"
if (-not (Test-Path $nativeCorePath)) {
    Write-Error "Error: NativeRenderCore.ps1 not found"
    exit 1
}
. $nativeCorePath

# --- 2. Constants & Configuration ---
class Colors {
    # Nostromo Palette (CRT Green/Teal)
    static [int] $Black      = 0x000500 # Very dark green tint
    static [int] $CRT_Dim    = 0x003300 # Scanline dim
    static [int] $CRT_Norm   = 0x00AA44 # Standard Text
    static [int] $CRT_Bright = 0x44FF88 # High intensity
    static [int] $CRT_Alert  = 0x00FF00 # Pure Green Alert (Alien style was often monochromatic)
    # Some red allowed for critical errors, but mostly green/amber
    static [int] $Critical   = 0xFF0000 
}

# --- 3. Animation Helpers ---
class AnimUtils {
    static [double] Lerp([double]$start, [double]$end, [double]$t) {
        return $start + ($end - $start) * $t
    }
    static [double] EaseOut([double]$t) {
        return 1.0 - [Math]::Pow(1.0 - $t, 3.0)
    }
}

class Typewriter {
    [string] $_text
    [double] $_progress
    [double] $_speed

    Typewriter([string]$text, [double]$speed) {
        $this._text = $text
        $this._speed = $speed
        $this._progress = 0.0
    }

    [bool] Update([double]$dt) {
        if ($this._progress -ge 1.0) { return $true }
        if ($this._text.Length -eq 0) { $this._progress = 1.0; return $true }
        $this._progress += ($this._speed * $dt) / $this._text.Length
        if ($this._progress -gt 1.0) { $this._progress = 1.0 }
        return $false
    }

    [string] GetVisibleText() {
        if ($this._text.Length -eq 0) { return "" }
        $count = [int]($this._text.Length * $this._progress)
        return $this._text.Substring(0, $count)
    }
    
    [void] Reset() { $this._progress = 0.0 }
}

# --- 4. Renderer Extensions ---
class BrailleRenderer {
    hidden [int[,]]$_grid
    hidden [int]$Width
    hidden [int]$Height
    hidden [int]$GridW
    hidden [int]$GridH

    BrailleRenderer([int]$w, [int]$h) {
        $this.Width = $w
        $this.Height = $h
        $this.GridW = $w * 2
        $this.GridH = $h * 4
        $this._grid = [int[,]]::new($this.GridH, $this.GridW)
    }

    [void] Clear() {
        [Array]::Clear($this._grid, 0, $this._grid.Length)
    }

    [void] SetPixel([int]$x, [int]$y) {
        if ($x -ge 0 -and $x -lt $this.GridW -and $y -ge 0 -and $y -lt $this.GridH) {
            $this._grid[$y, $x] = 1
        }
    }

    [void] DrawLine([int]$x0, [int]$y0, [int]$x1, [int]$y1) {
        $dx = [Math]::Abs($x1 - $x0); $sx = if ($x0 -lt $x1) { 1 } else { -1 }
        $dy = -[Math]::Abs($y1 - $y0); $sy = if ($y0 -lt $y1) { 1 } else { -1 }
        $err = $dx + $dy
        while ($true) {
            $this.SetPixel($x0, $y0)
            if ($x0 -eq $x1 -and $y0 -eq $y1) { break }
            $e2 = 2 * $err
            if ($e2 -ge $dy) { $err += $dy; $x0 += $sx }
            if ($e2 -le $dx) { $err += $dx; $y0 += $sy }
        }
    }

    # "Tech" Box with corner brackets
    [void] DrawTechBox([int]$x, [int]$y, [int]$w, [int]$h, [double]$p) {
        if ($p -le 0) { return }
        $x2=$x+$w; $y2=$y+$h
        
        # Brackets length
        $bl = [int]([Math]::Min($w, $h) * 0.2)
        $bl = [int]($bl * $p)
        if ($bl -lt 2) { return }

        # Top-Left
        $this.DrawLine($x, $y, $x+$bl, $y)
        $this.DrawLine($x, $y, $x, $y+$bl)

        # Top-Right
        $this.DrawLine($x2, $y, $x2-$bl, $y)
        $this.DrawLine($x2, $y, $x2, $y+$bl)

        # Bottom-Right
        $this.DrawLine($x2, $y2, $x2-$bl, $y2)
        $this.DrawLine($x2, $y2, $x2, $y2-$bl)

        # Bottom-Left
        $this.DrawLine($x, $y2, $x+$bl, $y2)
        $this.DrawLine($x, $y2, $x, $y2-$bl)
    }

    [void] Blit([object]$bufferObj, [int]$tx, [int]$ty, [int]$fg) {
        $buffer = $bufferObj
        $base = 0x2800 

        for ($y = 0; $y -lt $this.Height; $y++) {
            for ($x = 0; $x -lt $this.Width; $x++) {
                $bx = [int]($x * 2)
                $by = [int]($y * 4)
                
                # Pre-calc indices safely
                $by0=$by; $by1=$by+1; $by2=$by+2; $by3=$by+3
                $bx0=$bx; $bx1=$bx+1

                $code = 0
                if ($this._grid[$by0, $bx0] -ne 0) { $code = [int]($code + 1) }
                if ($this._grid[$by1, $bx0] -ne 0) { $code = [int]($code + 2) }
                if ($this._grid[$by2, $bx0] -ne 0) { $code = [int]($code + 4) }
                if ($this._grid[$by3, $bx0] -ne 0) { $code = [int]($code + 64) }
                
                if ($this._grid[$by0, $bx1] -ne 0) { $code = [int]($code + 8) }
                if ($this._grid[$by1, $bx1] -ne 0) { $code = [int]($code + 16) }
                if ($this._grid[$by2, $bx1] -ne 0) { $code = [int]($code + 32) }
                if ($this._grid[$by3, $bx1] -ne 0) { $code = [int]($code + 128) }
                
                if ($code -gt 0) {
                    $buffer.SetCell([int]($tx + $x), [int]($ty + $y), [char]($base + $code), $fg, -1, 0)
                }
            }
        }
    }
}

# --- 5. Application State ---
$menus = @("FLIGHT PLAN", "CREW MANIFEST", "CARGO", "ENGINEERING", "COMM LINK")
$tasks = @(
    @{ text="INITIATE WAKE-UP SEQUENCE"; status="executing"; id="t1" },
    @{ text="MONITOR CRYO-POD STABILITY"; status="stable"; id="t2" },
    @{ text="ANALYZE TRANSMISSION VECTOR"; status="unknown"; id="t3" },
    @{ text="UNSEAL UPPER DECK"; status="pending"; id="t4" },
    @{ text="PURGE ATMOSPHERE BUFFER"; status="pending"; id="t5" }
)

$state = @{
    SelectedIdx = 0
    DetailsOpen = $false
    DetailsAnim = 0.0 
    DetailsText = [Typewriter]::new("", 40.0)
    BlinkTime   = 0.0
    
    IntroTime   = 0.0
}

# --- 6. Main Loop Setup ---
$rawUI = $Host.UI.RawUI
try { 
    $rawUI.CursorSize = 0; 
    [Console]::CursorVisible = $false 
    # ANSI Clear
    [Console]::Write("`e[2J`e[H")
    [Console]::Clear() 
} catch {}

$w = 120; $h = 40
try { $w = $rawUI.WindowSize.Width; $h = $rawUI.WindowSize.Height } catch {}
$w = [Math]::Min($w, 150); $h = [Math]::Min($h, 50)

$front = New-NativeCellBuffer -Width $w -Height $h
$back = New-NativeCellBuffer -Width $w -Height $h
$renderer = [BrailleRenderer]::new($w, $h)

# Dirty Buffer Init
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) { 
        $front.SetCell($x, $y, [char]0, -1, -1, 0) 
    }
}

$running = $true
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$lastTime = $sw.ElapsedMilliseconds

# --- 7. Main Loop ---
while ($running) {
    # -- Input --
    if ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
            "Escape" { 
                if ($state.DetailsOpen) { $state.DetailsOpen = $false } else { $running = $false } 
            }
            "Q" { $running = $false }
            "UpArrow" { 
                $state.SelectedIdx = [Math]::Max(0, $state.SelectedIdx - 1) 
                if ($state.DetailsOpen) { 
                    $txt = "DIRECTIVE $($tasks[$state.SelectedIdx].id.PadRight(4))`n" + ("-"*30) + "`nSTATUS: " + $tasks[$state.SelectedIdx].status.ToUpper() + "`n`nANALYSIS PENDING..."
                    $state.DetailsText = [Typewriter]::new($txt, 80.0)
                }
            }
            "DownArrow" { 
                $state.SelectedIdx = [Math]::Min($tasks.Count - 1, $state.SelectedIdx + 1)
                if ($state.DetailsOpen) { 
                    $txt = "DIRECTIVE $($tasks[$state.SelectedIdx].id.PadRight(4))`n" + ("-"*30) + "`nSTATUS: " + $tasks[$state.SelectedIdx].status.ToUpper() + "`n`nANALYSIS PENDING..."
                    $state.DetailsText = [Typewriter]::new($txt, 80.0)
                }
            }
            "Enter" { 
                if (-not $state.DetailsOpen) {
                    $state.DetailsOpen = $true
                    $txt = "DIRECTIVE $($tasks[$state.SelectedIdx].id.PadRight(4))`n" + ("-"*30) + "`nSTATUS: " + $tasks[$state.SelectedIdx].status.ToUpper() + "`n`nPRIORITY: 1`nAUTH: OFFICER`n`n> UNABLE TO DECRYPT SIGNAL`n> ORIGIN: ZETA II RETICULI`n> RECOMMEND CAUTION"
                    $state.DetailsText = [Typewriter]::new($txt, 80.0)
                }
            }
        }
    }

    # -- Update --
    $now = $sw.ElapsedMilliseconds
    $dt = ($now - $lastTime) / 1000.0
    $lastTime = $now
    
    $state.IntroTime += $dt
    $state.BlinkTime += $dt
    $introP = [Math]::Min(1.0, $state.IntroTime / 1.0)
    
    # Animate Slide-out
    $targetAnim = if ($state.DetailsOpen) { 1.0 } else { 0.0 }
    $diff = $targetAnim - $state.DetailsAnim
    $state.DetailsAnim += $diff * ($dt * 5.0)
    
    [void]$state.DetailsText.Update($dt)

    # -- Draw --
    $back.Clear()
    $renderer.Clear()
    
    # Header
    if ($introP -gt 0.2) {
        $header = " WEYLAND-YUTANI CORP | USCSS NOSTROMO | " + [DateTime]::Now.ToString("HH:mm:ss")
        $back.WriteRow(2, 1, $header, @([Colors]::CRT_Norm)*$header.Length, $null, $null, 0, $w)
        $renderer.DrawLine(0, 8, $w * 2, 8) # Line under header (y=2 * 4 = 8)
    }

    $sidebarW = [int]($w * 0.20)
    $detailsMaxW = [int]($w * 0.45)
    
    # Left Menu
    if ($introP -gt 0.4) {
        for ($i=0; $i -lt $menus.Count; $i++) {
            $my = 4 + ($i * 2)
            $col = [Colors]::CRT_Dim
            if ($i -eq 1) { $col = [Colors]::CRT_Bright } # Active item hardcoded for mock
            $back.WriteRow(2, $my, $menus[$i], @($col)*20, $null, $null, 0, $w)
        }
    }

    # Center Panel (Directives)
    $listX = $sidebarW + 2
    $curDetailsW = [int]($detailsMaxW * $state.DetailsAnim)
    $listW = $w - $listX - $curDetailsW - 2

    # Draw Tech Box around List
    $renderer.DrawTechBox($listX*2, 12, ($listW*2)-1, ($h*4)-14, [AnimUtils]::EaseOut($introP))
    
    if ($introP -gt 0.6) {
        # List Header
        $back.WriteRow($listX + 2, 4, "CURRENT DIRECTIVES", @([Colors]::CRT_Norm)*18, $null, $null, 0, $w)
        
        for ($i=0; $i -lt $tasks.Count; $i++) {
            if ($i -ge ($h - 8)) { break }
            $t = $tasks[$i]
            $y = 6 + ($i * 2)
            
            $isSelected = ($i -eq $state.SelectedIdx)
            $col = if ($isSelected) { [Colors]::Black } else { [Colors]::CRT_Norm }
            $bg  = if ($isSelected) { [Colors]::CRT_Bright } else { -1 }
            
            $statusStr = $t.status.ToUpper()
            $line = "{0,-35} {1,15}" -f $t.text, $statusStr
            
            if ($line.Length -gt $listW-4) { $line = $line.Substring(0, $listW-4) }
            
            $back.WriteRow($listX + 2, $y, $line, @($col)*$line.Length, @($bg)*$line.Length, $null, 0, $w)
        }
    }

    # Slide-Out Panel
    if ($curDetailsW -gt 4) {
        $detX = $listX + $listW + 1
        $renderer.DrawTechBox($detX*2, 12, ($curDetailsW*2)-1, ($h*4)-14, 1.0)
        
        # Grid Pattern in Details
        if ($curDetailsW -gt 10) {
            for ($dy = 0; $dy -lt ($h-8); $dy+=2) {
                # Scanline background for details?
                # $back.WriteRow($detX+1, 4+$dy, "." * ($curDetailsW-2), @([Colors]::CRT_Dim)*($curDetailsW-2), $null, $null, 0, $w)
            }
            
            $visible = $state.DetailsText.GetVisibleText()
            $lines = $visible -split "`n"
            $ly = 4
            foreach ($ln in $lines) {
                if ($ly -ge ($h - 4)) { break }
                $back.WriteRow($detX + 2, $ly, $ln, @([Colors]::CRT_Bright)*$ln.Length, $null, $null, 0, $w)
                $ly++
            }
            
            # Blinking Cursor at end
            if ([int]($state.BlinkTime * 2) % 2 -eq 0) {
               $back.SetCell($detX + 2, $ly, '_', [Colors]::CRT_Bright, -1, 0)
            }
        }
    }

    # Render Graphics
    $renderer.Blit($back, 0, 0, [Colors]::CRT_Norm)
    
    # SCANLINES EFFECT (Post-Process)
    # Dim every 2nd line
    for ($y = 1; $y -lt $h; $y += 2) {
        for ($x = 0; $x -lt $w; $x++) {
            $cell = $back.GetCell($x, $y)
            if ($cell.ForegroundRgb -eq [Colors]::CRT_Norm) {
                 $back.SetCell($x, $y, $cell.Char, [Colors]::CRT_Dim, $cell.BackgroundRgb, $cell.Attributes)
            }
        }
    }

    # Swap
    [Console]::Write($back.BuildDiff($front))
    $temp=$front; $front=$back; $back=$temp

    # Frame Cap
    if ($dt -lt 0.016) { 
        $sleepMs = [int]((0.016-$dt)*1000)
        if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
    }
}

# Cleanup
[Console]::CursorVisible = $true
