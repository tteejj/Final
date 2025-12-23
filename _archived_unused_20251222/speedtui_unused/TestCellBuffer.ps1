#!/usr/bin/env pwsh
# Test script for CellBuffer class
# This validates that CellBuffer works correctly with cell-based operations

# Define the classes inline for testing
using namespace System.Collections.Generic

# Cell class
class Cell {
    [char]$Char = ' '
    [int]$ForegroundRgb = -1
    [int]$BackgroundRgb = -1
    [byte]$Attributes = 0

    static [byte]$ATTR_BOLD = 0x01
    static [byte]$ATTR_UNDERLINE = 0x02
    static [byte]$ATTR_ITALIC = 0x04

    Cell() {
        $this.Char = ' '
        $this.ForegroundRgb = -1
        $this.BackgroundRgb = -1
        $this.Attributes = 0
    }

    Cell([char]$char, [int]$fg, [int]$bg, [byte]$attr) {
        $this.Char = $char
        $this.ForegroundRgb = $fg
        $this.BackgroundRgb = $bg
        $this.Attributes = $attr
    }

    [bool] Equals([Cell]$other) {
        if ($null -eq $other) { return $false }
        return $this.Char -eq $other.Char -and
               $this.ForegroundRgb -eq $other.ForegroundRgb -and
               $this.BackgroundRgb -eq $other.BackgroundRgb -and
               $this.Attributes -eq $other.Attributes
    }

    [void] CopyFrom([Cell]$source) {
        $this.Char = $source.Char
        $this.ForegroundRgb = $source.ForegroundRgb
        $this.BackgroundRgb = $source.BackgroundRgb
        $this.Attributes = $source.Attributes
    }

    [void] Reset() {
        $this.Char = ' '
        $this.ForegroundRgb = -1
        $this.BackgroundRgb = -1
        $this.Attributes = 0
    }
}

# CellBuffer class
class CellBuffer {
    [int]$Width
    [int]$Height
    hidden [Cell[][]]$_cells

    CellBuffer([int]$width, [int]$height) {
        if ($width -le 0 -or $height -le 0) {
            throw "CellBuffer dimensions must be positive"
        }

        $this.Width = $width
        $this.Height = $height
        $this._cells = [Cell[][]]::new($height)

        for ($y = 0; $y -lt $height; $y++) {
            $this._cells[$y] = [Cell[]]::new($width)
            for ($x = 0; $x -lt $width; $x++) {
                $this._cells[$y][$x] = [Cell]::new()
            }
        }
    }

    [void] SetCell([int]$x, [int]$y, [char]$char, [int]$fg, [int]$bg, [byte]$attr) {
        if ($x -lt 0 -or $x -ge $this.Width -or $y -lt 0 -or $y -ge $this.Height) {
            return
        }

        $cell = $this._cells[$y][$x]
        $cell.Char = $char
        $cell.ForegroundRgb = $fg
        $cell.BackgroundRgb = $bg
        $cell.Attributes = $attr
    }

    [Cell] GetCell([int]$x, [int]$y) {
        if ($x -lt 0 -or $x -ge $this.Width -or $y -lt 0 -or $y -ge $this.Height) {
            return $null
        }
        return $this._cells[$y][$x]
    }

    [void] Clear() {
        for ($y = 0; $y -lt $this.Height; $y++) {
            for ($x = 0; $x -lt $this.Width; $x++) {
                $this._cells[$y][$x].Reset()
            }
        }
    }

    [void] Resize([int]$newWidth, [int]$newHeight) {
        if ($newWidth -le 0 -or $newHeight -le 0) {
            throw "CellBuffer dimensions must be positive"
        }

        $newCells = [Cell[][]]::new($newHeight)
        for ($y = 0; $y -lt $newHeight; $y++) {
            $newCells[$y] = [Cell[]]::new($newWidth)
            for ($x = 0; $x -lt $newWidth; $x++) {
                $newCells[$y][$x] = [Cell]::new()
            }
        }

        $copyHeight = [Math]::Min($this.Height, $newHeight)
        $copyWidth = [Math]::Min($this.Width, $newWidth)

        for ($y = 0; $y -lt $copyHeight; $y++) {
            for ($x = 0; $x -lt $copyWidth; $x++) {
                $newCells[$y][$x].CopyFrom($this._cells[$y][$x])
            }
        }

        $this.Width = $newWidth
        $this.Height = $newHeight
        $this._cells = $newCells
    }

    [string] BuildDiff([CellBuffer]$previousBuffer) {
        $sb = [System.Text.StringBuilder]::new(4096)

        $currentFg = -1
        $currentBg = -1
        $currentAttr = [byte]0
        $cursorX = -1
        $cursorY = -1

        for ($y = 0; $y -lt $this.Height; $y++) {
            $x = 0
            while ($x -lt $this.Width) {
                $cell = $this._cells[$y][$x]

                $prevCell = $(if ($previousBuffer -and
                              $y -lt $previousBuffer.Height -and
                              $x -lt $previousBuffer.Width) {
                    $previousBuffer._cells[$y][$x]
                } else {
                    $null
                })

                if ($prevCell -and $cell.Equals($prevCell)) {
                    $x++
                    continue
                }

                if ($cursorX -ne $x -or $cursorY -ne $y) {
                    [void]$sb.Append("`e[$($y + 1);$($x + 1)H")
                    $cursorX = $x
                    $cursorY = $y
                }

                $runLength = 1
                while (($x + $runLength) -lt $this.Width) {
                    $nextCell = $this._cells[$y][$x + $runLength]

                    if ($nextCell.ForegroundRgb -eq $cell.ForegroundRgb -and
                        $nextCell.BackgroundRgb -eq $cell.BackgroundRgb -and
                        $nextCell.Attributes -eq $cell.Attributes) {

                        $nextPrevCell = $(if ($previousBuffer -and
                                          $y -lt $previousBuffer.Height -and
                                          ($x + $runLength) -lt $previousBuffer.Width) {
                            $previousBuffer._cells[$y][$x + $runLength]
                        } else {
                            $null
                        })

                        if (-not $nextPrevCell -or -not $nextCell.Equals($nextPrevCell)) {
                            $runLength++
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                }

                if ($cell.Attributes -ne $currentAttr) {
                    if ($currentAttr -ne 0) {
                        [void]$sb.Append("`e[0m")
                        $currentFg = -1
                        $currentBg = -1
                    }

                    if ($cell.Attributes -band [Cell]::ATTR_BOLD) {
                        [void]$sb.Append("`e[1m")
                    }
                    if ($cell.Attributes -band [Cell]::ATTR_UNDERLINE) {
                        [void]$sb.Append("`e[4m")
                    }
                    if ($cell.Attributes -band [Cell]::ATTR_ITALIC) {
                        [void]$sb.Append("`e[3m")
                    }

                    $currentAttr = $cell.Attributes
                }

                if ($cell.ForegroundRgb -ne $currentFg) {
                    if ($cell.ForegroundRgb -eq -1) {
                        [void]$sb.Append("`e[39m")
                    } else {
                        $r = ($cell.ForegroundRgb -shr 16) -band 0xFF
                        $g = ($cell.ForegroundRgb -shr 8) -band 0xFF
                        $b = $cell.ForegroundRgb -band 0xFF
                        [void]$sb.Append("`e[38;2;$r;$g;${b}m")
                    }
                    $currentFg = $cell.ForegroundRgb
                }

                if ($cell.BackgroundRgb -ne $currentBg) {
                    if ($cell.BackgroundRgb -eq -1) {
                        [void]$sb.Append("`e[49m")
                    } else {
                        $r = ($cell.BackgroundRgb -shr 16) -band 0xFF
                        $g = ($cell.BackgroundRgb -shr 8) -band 0xFF
                        $b = $cell.BackgroundRgb -band 0xFF
                        [void]$sb.Append("`e[48;2;$r;$g;${b}m")
                    }
                    $currentBg = $cell.BackgroundRgb
                }

                for ($i = 0; $i -lt $runLength; $i++) {
                    [void]$sb.Append($this._cells[$y][$x + $i].Char)
                }

                $cursorX = $x + $runLength
                $x += $runLength
            }
        }

        return $sb.ToString()
    }

    [void] CopyFrom([CellBuffer]$source) {
        if ($source.Width -ne $this.Width -or $source.Height -ne $this.Height) {
            throw "Cannot copy from buffer with different dimensions"
        }

        for ($y = 0; $y -lt $this.Height; $y++) {
            for ($x = 0; $x -lt $this.Width; $x++) {
                $this._cells[$y][$x].CopyFrom($source._cells[$y][$x])
            }
        }
    }

    [void] Fill([int]$x, [int]$y, [int]$width, [int]$height, [char]$char, [int]$fg, [int]$bg, [byte]$attr) {
        $endX = [Math]::Min($x + $width, $this.Width)
        $endY = [Math]::Min($y + $height, $this.Height)

        for ($row = [Math]::Max(0, $y); $row -lt $endY; $row++) {
            for ($col = [Math]::Max(0, $x); $col -lt $endX; $col++) {
                $this.SetCell($col, $row, $char, $fg, $bg, $attr)
            }
        }
    }
}

function Pack-RGB {
    param(
        [Parameter(Mandatory)][int]$r,
        [Parameter(Mandatory)][int]$g,
        [Parameter(Mandatory)][int]$b
    )

    $r = [Math]::Max(0, [Math]::Min(255, $r))
    $g = [Math]::Max(0, [Math]::Min(255, $g))
    $b = [Math]::Max(0, [Math]::Min(255, $b))

    return ($r -shl 16) -bor ($g -shl 8) -bor $b
}

function Unpack-RGB {
    param([Parameter(Mandatory)][int]$packed)

    return @{
        R = ($packed -shr 16) -band 0xFF
        G = ($packed -shr 8) -band 0xFF
        B = $packed -band 0xFF
    }
}

Write-Host "=== CellBuffer Test Suite ===" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

function Test-Assert {
    param(
        [string]$TestName,
        [bool]$Condition,
        [string]$Message = ""
    )

    if ($Condition) {
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        $script:testsPassed++
    } else {
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Yellow
        }
        $script:testsFailed++
    }
}

# Test 1: Cell creation and equality
Write-Host "Test 1: Cell Creation and Equality" -ForegroundColor Yellow
$cell1 = [Cell]::new()
Test-Assert "Cell default char is space" ($cell1.Char -eq ' ')
Test-Assert "Cell default fg is -1" ($cell1.ForegroundRgb -eq -1)
Test-Assert "Cell default bg is -1" ($cell1.BackgroundRgb -eq -1)
Test-Assert "Cell default attr is 0" ($cell1.Attributes -eq 0)

$cell2 = [Cell]::new('X', 0xFF0000, 0x00FF00, [Cell]::ATTR_BOLD)
Test-Assert "Cell custom char" ($cell2.Char -eq 'X')
Test-Assert "Cell custom fg" ($cell2.ForegroundRgb -eq 0xFF0000)
Test-Assert "Cell custom bg" ($cell2.BackgroundRgb -eq 0x00FF00)
Test-Assert "Cell custom attr" ($cell2.Attributes -eq [Cell]::ATTR_BOLD)

$cell3 = [Cell]::new('X', 0xFF0000, 0x00FF00, [Cell]::ATTR_BOLD)
Test-Assert "Equal cells are equal" ($cell2.Equals($cell3))

$cell4 = [Cell]::new('Y', 0xFF0000, 0x00FF00, [Cell]::ATTR_BOLD)
Test-Assert "Different cells are not equal" (-not $cell2.Equals($cell4))

Write-Host ""

# Test 2: Cell operations
Write-Host "Test 2: Cell Operations" -ForegroundColor Yellow
$cell5 = [Cell]::new()
$cell5.CopyFrom($cell2)
Test-Assert "CopyFrom copies char" ($cell5.Char -eq 'X')
Test-Assert "CopyFrom copies fg" ($cell5.ForegroundRgb -eq 0xFF0000)
Test-Assert "CopyFrom copies bg" ($cell5.BackgroundRgb -eq 0x00FF00)
Test-Assert "CopyFrom copies attr" ($cell5.Attributes -eq [Cell]::ATTR_BOLD)

$cell5.Reset()
Test-Assert "Reset sets char to space" ($cell5.Char -eq ' ')
Test-Assert "Reset sets fg to -1" ($cell5.ForegroundRgb -eq -1)
Test-Assert "Reset sets bg to -1" ($cell5.BackgroundRgb -eq -1)
Test-Assert "Reset sets attr to 0" ($cell5.Attributes -eq 0)

Write-Host ""

# Test 3: CellBuffer creation
Write-Host "Test 3: CellBuffer Creation" -ForegroundColor Yellow
$buffer = [CellBuffer]::new(80, 24)
Test-Assert "Buffer width correct" ($buffer.Width -eq 80)
Test-Assert "Buffer height correct" ($buffer.Height -eq 24)

$cell = $buffer.GetCell(0, 0)
Test-Assert "Buffer cells initialized" ($null -ne $cell)
Test-Assert "Buffer cells start empty" ($cell.Char -eq ' ')

Write-Host ""

# Test 4: SetCell and GetCell
Write-Host "Test 4: SetCell and GetCell" -ForegroundColor Yellow
$buffer.SetCell(10, 5, 'A', 0xFF0000, -1, [Cell]::ATTR_BOLD)
$cell = $buffer.GetCell(10, 5)
Test-Assert "SetCell sets char" ($cell.Char -eq 'A')
Test-Assert "SetCell sets fg" ($cell.ForegroundRgb -eq 0xFF0000)
Test-Assert "SetCell sets bg" ($cell.BackgroundRgb -eq -1)
Test-Assert "SetCell sets attr" ($cell.Attributes -eq [Cell]::ATTR_BOLD)

# Test out of bounds (should not crash)
$buffer.SetCell(-1, 0, 'X', -1, -1, 0)
$buffer.SetCell(0, -1, 'X', -1, -1, 0)
$buffer.SetCell(1000, 0, 'X', -1, -1, 0)
$buffer.SetCell(0, 1000, 'X', -1, -1, 0)
$cellOOB = $buffer.GetCell(1000, 1000)
Test-Assert "Out of bounds GetCell returns null" ($null -eq $cellOOB)

Write-Host ""

# Test 5: Clear
Write-Host "Test 5: Clear" -ForegroundColor Yellow
$buffer.SetCell(10, 10, 'Z', 0xFF0000, 0x00FF00, [Cell]::ATTR_BOLD)
$buffer.Clear()
$cell = $buffer.GetCell(10, 10)
Test-Assert "Clear resets char" ($cell.Char -eq ' ')
Test-Assert "Clear resets fg" ($cell.ForegroundRgb -eq -1)
Test-Assert "Clear resets bg" ($cell.BackgroundRgb -eq -1)
Test-Assert "Clear resets attr" ($cell.Attributes -eq 0)

Write-Host ""

# Test 6: Fill
Write-Host "Test 6: Fill" -ForegroundColor Yellow
$buffer.Clear()
$buffer.Fill(5, 5, 10, 3, 'X', 0xFF0000, 0x0000FF, [Cell]::ATTR_UNDERLINE)

# Check filled region
$cellInside = $buffer.GetCell(7, 6)
Test-Assert "Fill sets cells inside region" ($cellInside.Char -eq 'X' -and
                                             $cellInside.ForegroundRgb -eq 0xFF0000 -and
                                             $cellInside.BackgroundRgb -eq 0x0000FF -and
                                             $cellInside.Attributes -eq [Cell]::ATTR_UNDERLINE)

# Check outside region
$cellOutside = $buffer.GetCell(4, 5)
Test-Assert "Fill doesn't affect cells outside region" ($cellOutside.Char -eq ' ')

Write-Host ""

# Test 7: Resize
Write-Host "Test 7: Resize" -ForegroundColor Yellow
$buffer = [CellBuffer]::new(10, 10)
$buffer.SetCell(5, 5, 'K', 0xFF00FF, -1, 0)

# Resize larger
$buffer.Resize(20, 20)
Test-Assert "Resize updates width" ($buffer.Width -eq 20)
Test-Assert "Resize updates height" ($buffer.Height -eq 20)

# Check old content preserved
$cellOld = $buffer.GetCell(5, 5)
Test-Assert "Resize preserves old content" ($cellOld.Char -eq 'K' -and
                                            $cellOld.ForegroundRgb -eq 0xFF00FF)

# Check new region initialized
$cellNew = $buffer.GetCell(15, 15)
Test-Assert "Resize initializes new region" ($cellNew.Char -eq ' ')

# Resize smaller
$buffer.Resize(8, 8)
Test-Assert "Resize smaller updates width" ($buffer.Width -eq 8)
Test-Assert "Resize smaller updates height" ($buffer.Height -eq 8)

Write-Host ""

# Test 8: CopyFrom
Write-Host "Test 8: CopyFrom" -ForegroundColor Yellow
$buffer1 = [CellBuffer]::new(10, 10)
$buffer1.SetCell(3, 3, 'M', 0xFFFF00, 0xFF00FF, [Cell]::ATTR_BOLD)

$buffer2 = [CellBuffer]::new(10, 10)
$buffer2.CopyFrom($buffer1)

$cell = $buffer2.GetCell(3, 3)
Test-Assert "CopyFrom copies cells" ($cell.Char -eq 'M' -and
                                     $cell.ForegroundRgb -eq 0xFFFF00 -and
                                     $cell.BackgroundRgb -eq 0xFF00FF -and
                                     $cell.Attributes -eq [Cell]::ATTR_BOLD)

Write-Host ""

# Test 9: BuildDiff - No changes
Write-Host "Test 9: BuildDiff - No Changes" -ForegroundColor Yellow
$buffer1 = [CellBuffer]::new(10, 10)
$buffer2 = [CellBuffer]::new(10, 10)

$diff = $buffer2.BuildDiff($buffer1)
Test-Assert "No changes produces empty diff" ($diff.Length -eq 0)

Write-Host ""

# Test 10: BuildDiff - Single cell change
Write-Host "Test 10: BuildDiff - Single Cell Change" -ForegroundColor Yellow
$buffer1 = [CellBuffer]::new(10, 10)
$buffer2 = [CellBuffer]::new(10, 10)
$buffer2.SetCell(5, 5, 'X', -1, -1, 0)

$diff = $buffer2.BuildDiff($buffer1)
Test-Assert "Single change produces non-empty diff" ($diff.Length -gt 0)
Test-Assert "Diff contains cursor positioning" ($diff -match '\[6;6H')  # 1-based coords
Test-Assert "Diff contains character" ($diff -match 'X')

Write-Host ""

# Test 11: BuildDiff - Color change
Write-Host "Test 11: BuildDiff - Color Change" -ForegroundColor Yellow
$buffer1 = [CellBuffer]::new(10, 10)
$buffer2 = [CellBuffer]::new(10, 10)
$buffer2.SetCell(2, 2, 'R', 0xFF0000, -1, 0)  # Red text

$diff = $buffer2.BuildDiff($buffer1)
Test-Assert "Color change produces diff with color code" ($diff -match '38;2;255;0;0')
Test-Assert "Color change diff contains character" ($diff -match 'R')

Write-Host ""

# Test 12: Pack-RGB and Unpack-RGB
Write-Host "Test 12: Pack-RGB and Unpack-RGB" -ForegroundColor Yellow
$packed = Pack-RGB 255 128 64
Test-Assert "Pack-RGB produces correct value" ($packed -eq 0xFF8040)

$unpacked = Unpack-RGB $packed
Test-Assert "Unpack-RGB extracts R" ($unpacked.R -eq 255)
Test-Assert "Unpack-RGB extracts G" ($unpacked.G -eq 128)
Test-Assert "Unpack-RGB extracts B" ($unpacked.B -eq 64)

# Test clamping
$packed2 = Pack-RGB 300 -10 128
Test-Assert "Pack-RGB clamps R to 255" ((Unpack-RGB $packed2).R -eq 255)
Test-Assert "Pack-RGB clamps negative to 0" ((Unpack-RGB $packed2).G -eq 0)

Write-Host ""

# Test 13: BuildDiff - Multiple cells with same color (grouping)
Write-Host "Test 13: BuildDiff - Grouping" -ForegroundColor Yellow
$buffer1 = [CellBuffer]::new(10, 10)
$buffer2 = [CellBuffer]::new(10, 10)

# Write multiple cells with same color in a row
for ($x = 2; $x -le 5; $x++) {
    $buffer2.SetCell($x, 3, 'A', 0xFF0000, -1, 0)
}

$diff = $buffer2.BuildDiff($buffer1)
# Should have one cursor move, one color sequence, then all chars
$colorCount = ([regex]::Matches($diff, '38;2;255;0;0')).Count
Test-Assert "Grouping uses single color sequence" ($colorCount -eq 1)
Test-Assert "Grouping includes all characters" ($diff -match 'AAAA')

Write-Host ""

# Summary
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed." -ForegroundColor Red
    exit 1
}