#!/usr/bin/env pwsh
# RetroSciFiScreen.ps1 - Standalone 80s Sci-Fi Test Screen
# Usage: ./RetroSciFiScreen.ps1

using namespace System.Collections.Generic

Set-StrictMode -Version Latest

# --- 1. Load Dependencies (Minimal) ---
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = "." }

# Load NativeRenderCore for high-perf CellBuffer
$nativeCorePath = Join-Path $scriptDir "NativeRenderCore.ps1"
if (-not (Test-Path $nativeCorePath)) {
    Write-Error "Error: NativeRenderCore.ps1 not found in $scriptDir"
    exit 1
}
. $nativeCorePath

# Mock Colors if Enums.ps1 missing, otherwise try load
$enumsPath = Join-Path $scriptDir "Enums.ps1"
if (Test-Path $enumsPath) {
    . $enumsPath
} else {
    class Colors {
        static [int] $Black = 0x000000
        static [int] $Green = 0x00FF00
        static [int] $Red = 0xFF0000
    }
}

# --- 2. Braille Renderer Class ---
class BrailleCanvas {
    hidden [int[,]]$_grid
    hidden [int]$WidgetWidth
    hidden [int]$WidgetHeight
    hidden [int]$GridWidth
    hidden [int]$GridHeight

    BrailleCanvas([int]$w, [int]$h) {
        $this.WidgetWidth = $w
        $this.WidgetHeight = $h
        # Braille is 2x4 subpixels per char
        $this.GridWidth = $w * 2
        $this.GridHeight = $h * 4
        $this._grid = [int[,]]::new($this.GridHeight, $this.GridWidth)
    }

    [void] Clear() {
        [Array]::Clear($this._grid, 0, $this._grid.Length)
    }

    # Set a subpixel
    [void] Plot([int]$px, [int]$py) {
        if ($px -ge 0 -and $px -lt $this.GridWidth -and $py -ge 0 -and $py -lt $this.GridHeight) {
            $this._grid[$py, $px] = 1
        }
    }

    # Bresenham Line
    [void] DrawLine([int]$x0, [int]$y0, [int]$x1, [int]$y1) {
        $dx = [Math]::Abs($x1 - $x0)
        $dy = -[Math]::Abs($y1 - $y0)
        $sx = if ($x0 -lt $x1) { 1 } else { -1 }
        $sy = if ($y0 -lt $y1) { 1 } else { -1 }
        $err = $dx + $dy
        
        while ($true) {
            $this.Plot($x0, $y0)
            if ($x0 -eq $x1 -and $y0 -eq $y1) { break }
            $e2 = 2 * $err
            if ($e2 -ge $dy) { $err += $dy; $x0 += $sx }
            if ($e2 -le $dx) { $err += $dx; $y0 += $sy }
        }
    }

    # Render to NativeCellBuffer
    [void] Blit([object]$bufferObj, [int]$targetX, [int]$targetY, [int]$fgColor) {
        $buffer = $bufferObj
        for ($y = 0; $y -lt $this.WidgetHeight; $y++) {
            for ($x = 0; $x -lt $this.WidgetWidth; $x++) {
                
                $bx = [int]($x * 2)
                $by = [int]($y * 4)
                
                # Pre-calculate Y indices to avoid math in array access
                $by0 = $by
                $by1 = $by + 1
                $by2 = $by + 2
                $by3 = $by + 3
                
                $bx0 = $bx
                $bx1 = $bx + 1
                
                [int]$code = 0
                
                # Column 0
                if ($this._grid[$by0, $bx0] -ne 0) { $code = $code + 0x1 }
                if ($this._grid[$by1, $bx0] -ne 0) { $code = $code + 0x2 }
                if ($this._grid[$by2, $bx0] -ne 0) { $code = $code + 0x4 }
                if ($this._grid[$by3, $bx0] -ne 0) { $code = $code + 0x40 }
                
                # Column 1
                if ($this._grid[$by0, $bx1] -ne 0) { $code = $code + 0x8 }
                if ($this._grid[$by1, $bx1] -ne 0) { $code = $code + 0x10 }
                if ($this._grid[$by2, $bx1] -ne 0) { $code = $code + 0x20 }
                if ($this._grid[$by3, $bx1] -ne 0) { $code = $code + 0x80 }

                if ($code -gt 0) {
                     $char = [char](0x2800 + $code)
                     $buffer.SetCell($targetX + $x, $targetY + $y, $char, $fgColor, -1, 0)
                }
            }
        }
    }
}

# --- 3. 3D Math Helper ---
class Vector3 {
    [float]$x; [float]$y; [float]$z
    Vector3($x,$y,$z) { $this.x=$x; $this.y=$y; $this.z=$z }
}

class Engine3D {
    hidden [float]$_angle = 0
    
    [Vector3[]] Rotate([Vector3[]]$points, [float]$angleX, [float]$angleY, [float]$angleZ) {
        $result = @()
        foreach ($p in $points) {
            # Basic rotation logic (simplified for immediate fun)
            # Rotate Y
            $cos = [Math]::Cos($angleY)
            $sin = [Math]::Sin($angleY)
            $rx = $p.x * $cos - $p.z * $sin
            $rz = $p.x * $sin + $p.z * $cos
            
            # Rotate X
            $cosX = [Math]::Cos($angleX)
            $sinX = [Math]::Sin($angleX)
            $ry = $p.y * $cosX - $rz * $sinX
            $rz = $p.y * $sinX + $rz * $cosX
            
            $result += [Vector3]::new($rx, $ry, $rz)
        }
        return $result
    }

    [Vector3] Project([Vector3]$p, [int]$w, [int]$h, [float]$fov, [float]$dist) {
        $factor = $fov / ($dist + $p.z)
        $x = $p.x * $factor + ($w / 2)
        $y = $p.y * $factor + ($h / 2)
        return [Vector3]::new($x, $y, $p.z)
    }
}

# --- 4. Main App Loop ---

# Setup Term
# Setup Term
$rawUI = $Host.UI.RawUI
$prevCursor = 25
try { $prevCursor = $rawUI.CursorSize } catch {}

try { $rawUI.CursorSize = 0 } catch {} # Hide cursor
try { [Console]::CursorVisible = $false } catch {}

$w = 80
$h = 24
try {
    $w = $rawUI.WindowSize.Width
    $h = $rawUI.WindowSize.Height
} catch {
    # Fallback for non-interactive shells
    $w = 120
    $h = 40
}

# Optimize for faster redraw
$w = [Math]::Min($w, 120)
$h = [Math]::Min($h, 40)

$front = New-NativeCellBuffer -Width $w -Height $h
$back = New-NativeCellBuffer -Width $w -Height $h

# App State
$running = $true
$frame = 0
$radarAngle = 0.0

# 3D Cube
$cubePoints = @(
    [Vector3]::new(-1,-1,-1), [Vector3]::new(1,-1,-1), [Vector3]::new(1,1,-1), [Vector3]::new(-1,1,-1),
    [Vector3]::new(-1,-1,1), [Vector3]::new(1,-1,1), [Vector3]::new(1,1,1), [Vector3]::new(-1,1,1)
)
$cubeEdges = @(
    # Front
    @{a=0;b=1}, @{a=1;b=2}, @{a=2;b=3}, @{a=3;b=0},
    # Back
    @{a=4;b=5}, @{a=5;b=6}, @{a=6;b=7}, @{a=7;b=4},
    # Connect
    @{a=0;b=4}, @{a=1;b=5}, @{a=2;b=6}, @{a=3;b=7}
)
$engine3D = [Engine3D]::new()
$braille = [BrailleCanvas]::new(40, 20) # 40x20 char widget (80x80 subpixels)

# Colors
$c_Dim = 0x444400 # Dim Amber
$c_Bri = 0xFFAA00 # Bright Amber
$c_Crt = 0x111100 # Dark CRT BG
$c_CrtFake = 0x1A1000 
$c_Red = 0xFF0000 # Red Alert 

Clear-Host
Write-Host "Initializing Retro Display..." -ForegroundColor DarkYellow

# Stopwatch for delta time
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$lastTime = $sw.ElapsedMilliseconds

while ($running) {
    if ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq "Escape" -or $k.Key -eq "Q") { $running = $false }
    }

    $now = $sw.ElapsedMilliseconds
    $dt = ($now - $lastTime) / 1000.0
    $lastTime = $now

    # Update State
    $frame++
    $radarAngle += 2.0 * $dt 
    
    # --- RENDER ---
    $back.Clear()
    
    # 1. Background Grid (Infinite Trench)
    $horizon = [int]($h / 2)
    # Floor lines (Horizontal)
    for ($z = 1; $z -lt 10; $z++) {
        $offset = ($frame * 0.5) % 8
        $lineY = $horizon + ($z * 2) + $offset
        if ($lineY -lt $h - 2) {
             # Simple horizontal line using WriteRow
             # Fade color by distance?
             $col = if ($z -gt 6) { $c_Bri } else { $c_Dim }
             $back.Fill(0, [int]$lineY, $w, 1, '-', $col, -1, 0)
        }
    }
    # Perspective lines (Vertical)
    $centerX = $w / 2
    for ($i = -5; $i -le 5; $i++) {
        $xBase = $centerX + ($i * 12)
        # Naive line drawing for perspective
        # Just drawing points for speed in PS loop
        for ($py = $horizon; $py -lt $h; $py++) {
            $depth = ($py - $horizon) / ($h/2)
            $px = $centerX + ($i * 40 * $depth)
            if ($px -ge 0 -and $px -lt $w) {
                $back.SetCell([int]$px, $py, '|', $c_Dim, -1, 0)
            }
        }
    }

    # 2. 3D Cube (Center)
    $braille.Clear()
    $rotY = $frame * 0.05
    $rotX = $frame * 0.02
    $rotZ = $frame * 0.01
    
    $rotated = $engine3D.Rotate($cubePoints, $rotX, $rotY, $rotZ)
    $projected = @()
    foreach ($p in $rotated) { 
        $projected += $engine3D.Project($p, $braille.GridWidth, $braille.GridHeight, 60.0, 4.0) 
    }
    
    foreach ($e in $cubeEdges) {
        $p1 = $projected[$e.a]
        $p2 = $projected[$e.b]
        $braille.DrawLine([int]$p1.x, [int]$p1.y, [int]$p2.x, [int]$p2.y)
    }
    
    # Blit Cube to Center
    $cubeX = ($w - 40) / 2
    $cubeY = ($h - 20) / 2
    $braille.Blit($back, [int]$cubeX, [int]$cubeY, $c_Bri)

    # 3. Radar (Bottom Left)
    $radarX = 4
    $radarY = $h - 12
    $radarS = 10
    
    # Draw Circle (Approximated)
    # Using chars for low-fi look
    for ($y = -$radarS; $y -le $radarS; $y++) {
        for ($x = -$radarS*2; $x -le $radarS*2; $x++) {
            $dist = [Math]::Sqrt(($x*$x/4) + ($y*$y))
            if ([Math]::Abs($dist - $radarS) -lt 0.8) {
                $back.SetCell($radarX + 10 + $x, $radarY + 10 + $y, '.', $c_Dim, -1, 0)
            }
        }
    }
    # Sweep
    $sweepX = [Math]::Cos($radarAngle) * $radarS * 2
    $sweepY = [Math]::Sin($radarAngle) * $radarS
    $back.SetCell([int]($radarX + 10 + $sweepX), [int]($radarY + 10 + $sweepY), '*', $c_Bri, -1, 0)
    $back.SetCell($radarX + 10, $radarY + 10, '+', $c_Bri, -1, 0)
    
    # 4. Data Hex Dump (Right)
    $dumpX = $w - 20
    $dumpY = 4
    for ($i = 0; $i -lt 15; $i++) {
        $val1 = Get-Random -Min 0 -Max 255
        $val2 = Get-Random -Min 0 -Max 255
        $hex = "{0:X2} {1:X2} ." -f $val1, $val2
        if ($i % 3 -eq 0) {
            $back.WriteRow($dumpX, $dumpY + $i, $hex, @($c_Bri)*6, $null, $null, 0, $w)
        } else {
            $back.WriteRow($dumpX, $dumpY + $i, $hex, @($c_Dim)*6, $null, $null, 0, $w)
        }
    }

    # 5. UI Overlays
    $back.WriteRow(2, 1, "[SYSTEM ONLINE]", @($c_Bri)*15, $null, $null, 0, $w)
    $back.WriteRow($w - 20, 1, "[TGT: LOCKED]", @($c_Red)*13, $null, $null, 0, $w)

    # Output
    $diff = $back.BuildDiff($front)
    [Console]::Write($diff)
    
    # Swap
    $temp = $front
    $front = $back
    $back = $temp
    
    # VSpy
    if ($dt -lt 0.016) {
        $sleepMs = [int]((0.016 - $dt) * 1000)
        Start-Sleep -Milliseconds $sleepMs
    }
}

# Cleanup
[Console]::CursorVisible = $true
try { $rawUI.CursorSize = $prevCursor } catch {}
Write-Host "`nTerminated."
