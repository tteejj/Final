# NativeRenderCore.ps1 - High-performance C# cell buffer and diff engine
# This replaces the PowerShell CellBuffer with compiled C# for ~50-100x speedup

Set-StrictMode -Version Latest

# Only compile once
if (-not ([System.Management.Automation.PSTypeName]'NativeCell').Type) {

$csharpCode = @"
using System;
using System.Text;
using System.Runtime.CompilerServices;

/// <summary>
/// Represents a single cell in the terminal buffer.
/// Struct for stack allocation and cache-friendly memory layout.
/// </summary>
public struct NativeCell : IEquatable<NativeCell>
{
    public char Char;
    public int ForegroundRgb;  // Packed RGB: (R<<16)|(G<<8)|B, -1 = default
    public int BackgroundRgb;  // Packed RGB: (R<<16)|(G<<8)|B, -1 = default
    public byte Attributes;    // Bit 0: Bold, Bit 1: Underline, Bit 2: Italic

    public const byte ATTR_BOLD = 0x01;
    public const byte ATTR_UNDERLINE = 0x02;
    public const byte ATTR_ITALIC = 0x04;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public bool Equals(NativeCell other)
    {
        return Char == other.Char &&
               ForegroundRgb == other.ForegroundRgb &&
               BackgroundRgb == other.BackgroundRgb &&
               Attributes == other.Attributes;
    }

    public void Reset()
    {
        Char = ' ';
        ForegroundRgb = -1;
        BackgroundRgb = -1;
        Attributes = 0;
    }
}

/// <summary>
/// High-performance cell buffer with optimized differential rendering.
/// All hot paths are in C# for maximum performance on large terminals.
/// </summary>
public class NativeCellBuffer
{
    private NativeCell[,] _cells;
    private int _width;
    private int _height;

    public int Width => _width;
    public int Height => _height;

    public NativeCellBuffer(int width, int height)
    {
        if (width <= 0 || height <= 0)
            throw new ArgumentException("Dimensions must be positive");

        _width = width;
        _height = height;
        _cells = new NativeCell[height, width];
        Clear();
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void SetCell(int x, int y, char c, int fg, int bg, byte attr)
    {
        if (x < 0 || x >= _width || y < 0 || y >= _height) return;
        
        ref NativeCell cell = ref _cells[y, x];
        cell.Char = c;
        cell.ForegroundRgb = fg;
        cell.BackgroundRgb = bg;
        cell.Attributes = attr;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public NativeCell GetCell(int x, int y)
    {
        if (x < 0 || x >= _width || y < 0 || y >= _height)
            return new NativeCell { Char = ' ', ForegroundRgb = -1, BackgroundRgb = -1, Attributes = 0 };
        return _cells[y, x];
    }

    public void Clear()
    {
        for (int y = 0; y < _height; y++)
        {
            for (int x = 0; x < _width; x++)
            {
                _cells[y, x].Reset();
            }
        }
    }

    public void Resize(int newWidth, int newHeight)
    {
        if (newWidth <= 0 || newHeight <= 0)
            throw new ArgumentException("Dimensions must be positive");

        var newCells = new NativeCell[newHeight, newWidth];
        
        // Initialize new cells
        for (int y = 0; y < newHeight; y++)
        {
            for (int x = 0; x < newWidth; x++)
            {
                newCells[y, x].Reset();
            }
        }

        // Copy existing content
        int copyWidth = Math.Min(_width, newWidth);
        int copyHeight = Math.Min(_height, newHeight);
        
        for (int y = 0; y < copyHeight; y++)
        {
            for (int x = 0; x < copyWidth; x++)
            {
                newCells[y, x] = _cells[y, x];
            }
        }

        _cells = newCells;
        _width = newWidth;
        _height = newHeight;
    }

    public void CopyFrom(NativeCellBuffer source)
    {
        if (source._width != _width || source._height != _height)
            throw new ArgumentException("Buffer dimensions must match");

        Array.Copy(source._cells, _cells, _cells.Length);
    }

    public void Fill(int x, int y, int width, int height, char c, int fg, int bg, byte attr)
    {
        int endX = Math.Min(x + width, _width);
        int endY = Math.Min(y + height, _height);
        int startX = Math.Max(0, x);
        int startY = Math.Max(0, y);

        for (int row = startY; row < endY; row++)
        {
            for (int col = startX; col < endX; col++)
            {
                ref NativeCell cell = ref _cells[row, col];
                cell.Char = c;
                cell.ForegroundRgb = fg;
                cell.BackgroundRgb = bg;
                cell.Attributes = attr;
            }
        }
    }

    public void WriteRow(int x, int y, string text, int[] fg, int[] bg, byte[] attr, int clipMinX, int clipMaxX)
    {
        if (y < 0 || y >= _height) return;
        if (string.IsNullOrEmpty(text)) return;

        int len = text.Length;
        
        // Calculate effective bounds
        int startX = Math.Max(0, x);
        int endX = Math.Min(x + len, _width);
        
        // Apply clipping
        startX = Math.Max(startX, clipMinX);
        endX = Math.Min(endX, clipMaxX);
        
        if (startX >= endX) return;

        for (int col = startX; col < endX; col++)
        {
            int i = col - x;
            ref NativeCell cell = ref _cells[y, col];
            cell.Char = text[i];
            
            if (fg != null && i < fg.Length) cell.ForegroundRgb = fg[i];
            if (bg != null && i < bg.Length) cell.BackgroundRgb = bg[i];
            if (attr != null && i < attr.Length) cell.Attributes = attr[i];
        }
    }

    /// <summary>
    /// Build minimal ANSI output representing differences between this buffer and another.
    /// This is the CORE of differential rendering - the hottest path.
    /// Optimizations:
    /// 1. Skip unchanged cells immediately
    /// 2. Run-length encoding for same-color sequences
    /// 3. Cursor position tracking to minimize movement codes
    /// 4. StringBuilder pre-sized to reduce allocations
    /// </summary>
    public string BuildDiff(NativeCellBuffer previousBuffer)
    {
        // Pre-size for typical diff (assume 20% changes = good estimate)
        var sb = new StringBuilder(_width * _height / 5 * 20);

        int currentFg = -1;
        int currentBg = -1;
        byte currentAttr = 0;
        int cursorX = -1;
        int cursorY = -1;

        for (int y = 0; y < _height; y++)
        {
            int x = 0;
            while (x < _width)
            {
                ref NativeCell cell = ref _cells[y, x];

                // Check if cell changed from previous
                bool changed = true;
                if (previousBuffer != null && 
                    y < previousBuffer._height && 
                    x < previousBuffer._width)
                {
                    changed = !cell.Equals(previousBuffer._cells[y, x]);
                }

                if (!changed)
                {
                    x++;
                    continue;
                }

                // Cell changed - need to update
                // Move cursor if needed
                if (cursorX != x || cursorY != y)
                {
                    sb.Append("\x1b[");
                    sb.Append(y + 1);
                    sb.Append(';');
                    sb.Append(x + 1);
                    sb.Append('H');
                    cursorX = x;
                    cursorY = y;
                }

                // Run-length encoding: find consecutive cells with same colors/attrs
                int runLength = 1;
                while ((x + runLength) < _width)
                {
                    ref NativeCell nextCell = ref _cells[y, x + runLength];
                    
                    // Can group if colors and attributes match
                    if (nextCell.ForegroundRgb == cell.ForegroundRgb &&
                        nextCell.BackgroundRgb == cell.BackgroundRgb &&
                        nextCell.Attributes == cell.Attributes)
                    {
                        // Also check if changed from previous
                        bool nextChanged = true;
                        if (previousBuffer != null &&
                            y < previousBuffer._height &&
                            (x + runLength) < previousBuffer._width)
                        {
                            nextChanged = !nextCell.Equals(previousBuffer._cells[y, x + runLength]);
                        }

                        if (nextChanged)
                        {
                            runLength++;
                        }
                        else
                        {
                            break;
                        }
                    }
                    else
                    {
                        break;
                    }
                }

                // Emit attributes if changed
                if (cell.Attributes != currentAttr)
                {
                    if (currentAttr != 0)
                    {
                        sb.Append("\x1b[0m");
                        currentFg = -1;
                        currentBg = -1;
                    }

                    if ((cell.Attributes & NativeCell.ATTR_BOLD) != 0)
                        sb.Append("\x1b[1m");
                    if ((cell.Attributes & NativeCell.ATTR_UNDERLINE) != 0)
                        sb.Append("\x1b[4m");
                    if ((cell.Attributes & NativeCell.ATTR_ITALIC) != 0)
                        sb.Append("\x1b[3m");

                    currentAttr = cell.Attributes;
                }

                // Emit foreground color if changed
                if (cell.ForegroundRgb != currentFg)
                {
                    if (cell.ForegroundRgb == -1)
                    {
                        sb.Append("\x1b[39m");
                    }
                    else
                    {
                        int r = (cell.ForegroundRgb >> 16) & 0xFF;
                        int g = (cell.ForegroundRgb >> 8) & 0xFF;
                        int b = cell.ForegroundRgb & 0xFF;
                        sb.Append("\x1b[38;2;");
                        sb.Append(r);
                        sb.Append(';');
                        sb.Append(g);
                        sb.Append(';');
                        sb.Append(b);
                        sb.Append('m');
                    }
                    currentFg = cell.ForegroundRgb;
                }

                // Emit background color if changed
                if (cell.BackgroundRgb != currentBg)
                {
                    if (cell.BackgroundRgb == -1)
                    {
                        sb.Append("\x1b[49m");
                    }
                    else
                    {
                        int r = (cell.BackgroundRgb >> 16) & 0xFF;
                        int g = (cell.BackgroundRgb >> 8) & 0xFF;
                        int b = cell.BackgroundRgb & 0xFF;
                        sb.Append("\x1b[48;2;");
                        sb.Append(r);
                        sb.Append(';');
                        sb.Append(g);
                        sb.Append(';');
                        sb.Append(b);
                        sb.Append('m');
                    }
                    currentBg = cell.BackgroundRgb;
                }

                // Emit the characters for this run
                for (int i = 0; i < runLength; i++)
                {
                    sb.Append(_cells[y, x + i].Char);
                }

                cursorX = x + runLength;
                x += runLength;
            }
        }

        return sb.ToString();
    }

    /// <summary>
    /// Invalidate a row range by resetting it in the previous buffer comparison.
    /// Used when forcing a redraw of specific areas.
    /// </summary>
    public void InvalidateRows(int minY, int maxY)
    {
        minY = Math.Max(0, minY);
        maxY = Math.Min(_height - 1, maxY);

        for (int y = minY; y <= maxY; y++)
        {
            for (int x = 0; x < _width; x++)
            {
                // Set to null char to ensure it differs from any real content
                _cells[y, x].Char = '\0';
            }
        }
    }
}
"@

    Add-Type -TypeDefinition $csharpCode -Language CSharp -ErrorAction Stop
    Write-Verbose "NativeRenderCore: C# types compiled successfully"
}

<#
.SYNOPSIS
Create a new native cell buffer with specified dimensions

.PARAMETER Width
Width in columns

.PARAMETER Height  
Height in rows

.OUTPUTS
NativeCellBuffer instance
#>
function New-NativeCellBuffer {
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )
    return [NativeCellBuffer]::new($Width, $Height)
}

# Export for module use
#Export-ModuleMember -Function New-NativeCellBuffer
