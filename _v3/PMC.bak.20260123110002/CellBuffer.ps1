# SpeedTUI CellBuffer - 2D Cell-Based Terminal Buffer
# This provides a high-performance cell-based buffer for terminal rendering
# with support for RGB colors and text attributes

using namespace System.Collections.Generic

<#
.SYNOPSIS
Represents a single cell in the terminal buffer

.DESCRIPTION
A Cell contains:
- Character (char): The displayed character
- ForegroundRgb (int): Packed RGB foreground color (R<<16 | G<<8 | B)
- BackgroundRgb (int): Packed RGB background color (R<<16 | G<<8 | B)
- Attributes (byte): Bitfield for bold/underline/etc

This struct-like class is designed for minimal memory overhead and fast comparison.
#>
class Cell {
    [char]$Char = ' '           # Character to display
    [int]$ForegroundRgb = -1    # Packed RGB: (R<<16)|(G<<8)|B, -1 = default
    [int]$BackgroundRgb = -1    # Packed RGB: (R<<16)|(G<<8)|B, -1 = default
    [byte]$Attributes = 0       # Bit 0: Bold, Bit 1: Underline, Bit 2: Italic

    # Attribute bit flags
    static [byte]$ATTR_BOLD = 0x01
    static [byte]$ATTR_UNDERLINE = 0x02
    static [byte]$ATTR_ITALIC = 0x04

    <#
    .SYNOPSIS
    Creates a new Cell with default values (space, default colors)
    #>
    Cell() {
        $this.Char = ' '
        $this.ForegroundRgb = -1
        $this.BackgroundRgb = -1
        $this.Attributes = 0
    }

    <#
    .SYNOPSIS
    Creates a new Cell with specified values

    .PARAMETER char
    Character to display

    .PARAMETER fg
    Packed foreground RGB (-1 for default)

    .PARAMETER bg
    Packed background RGB (-1 for default)

    .PARAMETER attr
    Attributes bitfield
    #>
    Cell([char]$char, [int]$fg, [int]$bg, [byte]$attr) {
        $this.Char = $char
        $this.ForegroundRgb = $fg
        $this.BackgroundRgb = $bg
        $this.Attributes = $attr
    }

    <#
    .SYNOPSIS
    Check if this cell equals another cell

    .DESCRIPTION
    Two cells are equal if all their properties match. This is used
    for differential rendering to skip unchanged cells.

    .PARAMETER other
    Other Cell to compare with (passed as [object] due to PowerShell limitations)

    .OUTPUTS
    Boolean indicating equality
    #>
    [bool] Equals([object]$other) {
        if ($null -eq $other) { return $false }
        return $this.Char -eq $other.Char -and
               $this.ForegroundRgb -eq $other.ForegroundRgb -and
               $this.BackgroundRgb -eq $other.BackgroundRgb -and
               $this.Attributes -eq $other.Attributes
    }

    <#
    .SYNOPSIS
    Copy values from another cell into this cell

    .PARAMETER source
    Source Cell to copy from (passed as [object] due to PowerShell limitations)
    #>
    [void] CopyFrom([object]$source) {
        $this.Char = $source.Char
        $this.ForegroundRgb = $source.ForegroundRgb
        $this.BackgroundRgb = $source.BackgroundRgb
        $this.Attributes = $source.Attributes
    }

    <#
    .SYNOPSIS
    Reset cell to default values (space, default colors, no attributes)
    #>
    [void] Reset() {
        $this.Char = ' '
        $this.ForegroundRgb = -1
        $this.BackgroundRgb = -1
        $this.Attributes = 0
    }
}

<#
.SYNOPSIS
2D cell buffer for terminal rendering with differential updates

.DESCRIPTION
CellBuffer maintains a 2D array of Cell objects representing the terminal screen.
It provides:
- Fast O(1) random access to any cell
- Efficient differential rendering (BuildDiff)
- Automatic resize handling
- ANSI sequence parsing and emission

Design rationale:
- Cell-based approach is more memory-efficient than string-based for sparse updates
- Packed RGB integers reduce memory overhead (4 bytes vs 3 bytes + padding)
- Differential rendering minimizes actual terminal writes (the bottleneck)
- ANSI sequence grouping reduces escape code overhead

Performance characteristics:
- SetCell: O(1)
- GetCell: O(1)
- Clear: O(width * height) - unavoidable, must touch all cells
- BuildDiff: O(width * height) - but skips unchanged cells early
- Memory: ~12 bytes per cell (char=2, int=4, int=4, byte=1, padding)

.EXAMPLE
$buffer = [CellBuffer]::new(80, 24)
$buffer.SetCell(10, 5, 'X', 0xFF0000, -1, [Cell]::ATTR_BOLD)
$buffer.GetCell(10, 5)
#>
class CellBuffer {
    # Buffer dimensions
    [int]$Width
    [int]$Height

    # 2D array of cells: [row][col]
    # We use row-major order for better cache locality when building diff by rows
    # NOTE: Using [object] instead of [Cell[][]] due to PowerShell limitations with nested custom class arrays
    hidden [object]$_cells

    <#
    .SYNOPSIS
    Creates a new CellBuffer with specified dimensions

    .PARAMETER width
    Width in columns

    .PARAMETER height
    Height in rows
    #>
    CellBuffer([int]$width, [int]$height) {
        if ($width -le 0 -or $height -le 0) {
            throw "CellBuffer dimensions must be positive"
        }

        $this.Width = $width
        $this.Height = $height
        $this._cells = [object[]]::new($height)

        # Pre-allocate all cells to avoid null checks
        for ($y = 0; $y -lt $height; $y++) {
            $this._cells[$y] = [object[]]::new($width)
            for ($x = 0; $x -lt $width; $x++) {
                $this._cells[$y][$x] = [Cell]::new()
            }
        }
    }

    <#
    .SYNOPSIS
    Set a cell at the specified position

    .DESCRIPTION
    Sets the character, colors, and attributes for a cell. Out-of-bounds
    coordinates are silently ignored (defensive programming for resize races).

    .PARAMETER x
    X coordinate (0-based)

    .PARAMETER y
    Y coordinate (0-based)

    .PARAMETER char
    Character to display

    .PARAMETER fg
    Packed foreground RGB, or -1 for default

    .PARAMETER bg
    Packed background RGB, or -1 for default

    .PARAMETER attr
    Attributes bitfield (bold, underline, italic)
    #>
    [void] SetCell([int]$x, [int]$y, [char]$char, [int]$fg, [int]$bg, [byte]$attr) {
        # Bounds check - silently ignore out of bounds (defensive)
        if ($x -lt 0 -or $x -ge $this.Width -or $y -lt 0 -or $y -ge $this.Height) {
            return
        }

        $cell = $this._cells[$y][$x]
        $cell.Char = $char
        $cell.ForegroundRgb = $fg
        $cell.BackgroundRgb = $bg
        $cell.Attributes = $attr
    }

    <#
    .SYNOPSIS
    Get a cell at the specified position

    .PARAMETER x
    X coordinate (0-based)

    .PARAMETER y
    Y coordinate (0-based)

    .OUTPUTS
    Cell object, or $null if out of bounds
    #>
    [Cell] GetCell([int]$x, [int]$y) {
        if ($x -lt 0 -or $x -ge $this.Width -or $y -lt 0 -or $y -ge $this.Height) {
            return $null
        }
        return $this._cells[$y][$x]
    }

    <#
    .SYNOPSIS
    Clear the entire buffer to default state

    .DESCRIPTION
    Resets all cells to space character with default colors and no attributes.
    This is O(width*height) but unavoidable - we must touch every cell.
    #>
    [void] Clear() {
        for ($y = 0; $y -lt $this.Height; $y++) {
            for ($x = 0; $x -lt $this.Width; $x++) {
                $this._cells[$y][$x].Reset()
            }
        }
    }

    <#
    .SYNOPSIS
    Resize the buffer to new dimensions

    .DESCRIPTION
    Creates a new buffer with the specified dimensions. Old content is
    preserved where it fits, new areas are initialized to default cells.

    This is called when terminal is resized. We allocate a fresh buffer
    to avoid complex reallocation logic.

    .PARAMETER newWidth
    New width in columns

    .PARAMETER newHeight
    New height in rows
    #>
    [void] Resize([int]$newWidth, [int]$newHeight) {
        if ($newWidth -le 0 -or $newHeight -le 0) {
            throw "CellBuffer dimensions must be positive"
        }

        # Create new buffer
        $newCells = [object[]]::new($newHeight)
        for ($y = 0; $y -lt $newHeight; $y++) {
            $newCells[$y] = [object[]]::new($newWidth)
            for ($x = 0; $x -lt $newWidth; $x++) {
                $newCells[$y][$x] = [Cell]::new()
            }
        }

        # Copy old content where it fits
        $copyHeight = [Math]::Min($this.Height, $newHeight)
        $copyWidth = [Math]::Min($this.Width, $newWidth)

        for ($y = 0; $y -lt $copyHeight; $y++) {
            for ($x = 0; $x -lt $copyWidth; $x++) {
                $newCells[$y][$x].CopyFrom($this._cells[$y][$x])
            }
        }

        # Update dimensions and replace buffer
        $this.Width = $newWidth
        $this.Height = $newHeight
        $this._cells = $newCells
    }

    <#
    .SYNOPSIS
    Build minimal ANSI output representing differences between this buffer and another

    .DESCRIPTION
    This is the core of differential rendering. It compares this buffer (back buffer)
    with the previous buffer (front buffer) and emits only the ANSI sequences needed
    to transform the front buffer into the back buffer.

    Optimization strategies:
    1. Skip unchanged cells entirely (most common case)
    2. Group adjacent cells with same colors to reduce escape codes
    3. Pack RGB values for fast integer comparison
    4. Use cursor positioning only when needed (track cursor position)
    5. Emit reset only when colors actually change

    Why this is faster than string-based:
    - String-based: Must parse ANSI in every string, hard to optimize groups
    - Cell-based: Cells already parsed, colors already integers, trivial to group

    .PARAMETER previousBuffer
    The previous CellBuffer state (front buffer)

    .OUTPUTS
    String containing minimal ANSI sequences to update the terminal
    #>
    [string] BuildDiff([object]$previousBuffer) {
        $sb = [System.Text.StringBuilder]::new(4096)

        # Track current state to minimize escape sequences
        $currentFg = -1
        $currentBg = -1
        $currentAttr = [byte]0
        $cursorX = -1
        $cursorY = -1

        for ($y = 0; $y -lt $this.Height; $y++) {
            $x = 0
            while ($x -lt $this.Width) {
                $cell = $this._cells[$y][$x]

                # Check if cell changed
                $prevCell = $(if ($previousBuffer -and
                              $y -lt $previousBuffer.Height -and
                              $x -lt $previousBuffer.Width) {
                    $previousBuffer._cells[$y][$x]
                } else {
                    $null
                })

                # Skip if unchanged
                if ($prevCell -and $cell.Equals($prevCell)) {
                    $x++
                    continue
                }

                # Cell changed - need to update
                # First, move cursor if needed
                if ($cursorX -ne $x -or $cursorY -ne $y) {
                    [void]$sb.Append("`e[$($y + 1);$($x + 1)H")
                    $cursorX = $x
                    $cursorY = $y
                }

                # Look ahead to group cells with same attributes
                $runLength = 1
                while (($x + $runLength) -lt $this.Width) {
                    $nextCell = $this._cells[$y][$x + $runLength]

                    # Can group if colors and attributes match
                    if ($nextCell.ForegroundRgb -eq $cell.ForegroundRgb -and
                        $nextCell.BackgroundRgb -eq $cell.BackgroundRgb -and
                        $nextCell.Attributes -eq $cell.Attributes) {

                        # Also check if changed from previous
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

                # Emit attributes if changed
                if ($cell.Attributes -ne $currentAttr) {
                    # Reset first if we had attributes
                    if ($currentAttr -ne 0) {
                        [void]$sb.Append("`e[0m")
                        $currentFg = -1
                        $currentBg = -1
                    }

                    # Apply new attributes
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

                # Emit foreground color if changed
                if ($cell.ForegroundRgb -ne $currentFg) {
                    if ($cell.ForegroundRgb -eq -1) {
                        [void]$sb.Append("`e[39m")  # Default foreground
                    } else {
                        $r = ($cell.ForegroundRgb -shr 16) -band 0xFF
                        $g = ($cell.ForegroundRgb -shr 8) -band 0xFF
                        $b = $cell.ForegroundRgb -band 0xFF
                        [void]$sb.Append("`e[38;2;$r;$g;${b}m")
                    }
                    $currentFg = $cell.ForegroundRgb
                }

                # Emit background color if changed
                if ($cell.BackgroundRgb -ne $currentBg) {
                    if ($cell.BackgroundRgb -eq -1) {
                        [void]$sb.Append("`e[49m")  # Default background
                    } else {
                        $r = ($cell.BackgroundRgb -shr 16) -band 0xFF
                        $g = ($cell.BackgroundRgb -shr 8) -band 0xFF
                        $b = $cell.BackgroundRgb -band 0xFF
                        [void]$sb.Append("`e[48;2;$r;$g;${b}m")
                    }
                    $currentBg = $cell.BackgroundRgb
                }

                # Emit the characters for this run
                for ($i = 0; $i -lt $runLength; $i++) {
                    [void]$sb.Append($this._cells[$y][$x + $i].Char)
                }

                # Update cursor position
                $cursorX = $x + $runLength
                $x += $runLength
            }
        }

        return $sb.ToString()
    }

    <#
    .SYNOPSIS
    Copy entire contents from another buffer

    .DESCRIPTION
    This is used to swap buffers efficiently. Instead of swapping references
    (which breaks encapsulation), we copy cell contents.

    .PARAMETER source
    Source CellBuffer to copy from
    #>
    [void] CopyFrom([object]$source) {
        if ($source.Width -ne $this.Width -or $source.Height -ne $this.Height) {
            throw "Cannot copy from buffer with different dimensions"
        }

        for ($y = 0; $y -lt $this.Height; $y++) {
            for ($x = 0; $x -lt $this.Width; $x++) {
                $this._cells[$y][$x].CopyFrom($source._cells[$y][$x])
            }
        }
    }

    <#
    .SYNOPSIS
    Fill a rectangular region with a character and colors

    .DESCRIPTION
    Utility method for filling regions (useful for clearing areas or backgrounds)

    .PARAMETER x
    Starting X coordinate

    .PARAMETER y
    Starting Y coordinate

    .PARAMETER width
    Width of region

    .PARAMETER height
    Height of region

    .PARAMETER char
    Character to fill with

    .PARAMETER fg
    Foreground color (packed RGB or -1)

    .PARAMETER bg
    Background color (packed RGB or -1)

    .PARAMETER attr
    Attributes bitfield
    #>
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

<#
.SYNOPSIS
Pack RGB components into a single integer

.DESCRIPTION
Packs red, green, blue components (0-255 each) into a single 32-bit integer.
Format: 0x00RRGGBB

This reduces memory overhead and makes color comparison a single integer
comparison instead of three byte comparisons.

.PARAMETER r
Red component (0-255)

.PARAMETER g
Green component (0-255)

.PARAMETER b
Blue component (0-255)

.OUTPUTS
Packed integer representing RGB color

.EXAMPLE
$color = Pack-RGB 255 128 64  # Returns 0x00FF8040
#>
function Pack-RGB {
    param(
        [Parameter(Mandatory)][int]$r,
        [Parameter(Mandatory)][int]$g,
        [Parameter(Mandatory)][int]$b
    )

    # Clamp to valid range
    $r = [Math]::Max(0, [Math]::Min(255, $r))
    $g = [Math]::Max(0, [Math]::Min(255, $g))
    $b = [Math]::Max(0, [Math]::Min(255, $b))

    return ($r -shl 16) -bor ($g -shl 8) -bor $b
}

<#
.SYNOPSIS
Unpack RGB integer into components

.DESCRIPTION
Extracts red, green, blue components from a packed RGB integer.

.PARAMETER packed
Packed RGB integer (format: 0x00RRGGBB)

.OUTPUTS
Hashtable with R, G, B keys

.EXAMPLE
$rgb = Unpack-RGB 0x00FF8040  # Returns @{R=255; G=128; B=64}
#>
function Unpack-RGB {
    param([Parameter(Mandatory)][int]$packed)

    return @{
        R = ($packed -shr 16) -band 0xFF
        G = ($packed -shr 8) -band 0xFF
        B = $packed -band 0xFF
    }
}