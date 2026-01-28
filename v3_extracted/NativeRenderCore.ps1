# NativeRenderCore.ps1 - High-performance C# cell buffer and diff engine
# This replaces the PowerShell CellBuffer with compiled C# for ~50-100x speedup

Set-StrictMode -Version Latest

# Only compile once
if (-not ([System.Management.Automation.PSTypeName]'NativeCell').Type) {

$csharpCode = @"
using System;
using System.Text;
using System.Runtime.CompilerServices;
using System.Collections;
using System.Collections.Generic;

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

/// <summary>
/// High-performance Z-buffer for layer management.
/// Uses native int array with fast clear operations.
/// </summary>
public class NativeZBuffer
{
    private int[,] _buffer;
    private int _width;
    private int _height;

    public int Width => _width;
    public int Height => _height;

    public NativeZBuffer(int width, int height)
    {
        if (width <= 0 || height <= 0)
            throw new ArgumentException("Dimensions must be positive");

        _width = width;
        _height = height;
        _buffer = new int[height, width];
        Clear();
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public int Get(int x, int y)
    {
        if (x < 0 || x >= _width || y < 0 || y >= _height) return int.MinValue;
        return _buffer[y, x];
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void Set(int x, int y, int z)
    {
        if (x < 0 || x >= _width || y < 0 || y >= _height) return;
        _buffer[y, x] = z;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public bool TestAndSet(int x, int y, int z)
    {
        if (x < 0 || x >= _width || y < 0 || y >= _height) return false;
        if (z >= _buffer[y, x])
        {
            _buffer[y, x] = z;
            return true;
        }
        return false;
    }

    public void Clear()
    {
        // Fast clear using Array.Clear for native performance
        Array.Clear(_buffer, 0, _buffer.Length);
        // Set all to MinValue
        for (int y = 0; y < _height; y++)
        {
            for (int x = 0; x < _width; x++)
            {
                _buffer[y, x] = int.MinValue;
            }
        }
    }

    public void Resize(int newWidth, int newHeight)
    {
        if (newWidth <= 0 || newHeight <= 0)
            throw new ArgumentException("Dimensions must be positive");

        _width = newWidth;
        _height = newHeight;
        _buffer = new int[newHeight, newWidth];
        Clear();
    }
}

/// <summary>
/// Optimized task hierarchy processor.
/// Replaces PowerShell recursion with C# for performance.
/// </summary>
public class NativeTaskProcessor
{
    public static ArrayList FlattenTasks(object[] tasks, Hashtable view)
    {
        var displayTasks = new ArrayList();
        if (tasks == null) return displayTasks;

        var parentChildrenMap = new Dictionary<string, List<IDictionary>>();
        var processedIds = new HashSet<string>();
        var rootTasks = new List<IDictionary>();
        var allTasks = new List<IDictionary>();

        // Build index
        foreach (var item in tasks)
        {
            if (item is IDictionary task)
            {
                allTasks.Add(task);

                string id = task["id"] as string;
                if (string.IsNullOrEmpty(id)) continue;

                string parentId = task.Contains("parent_id") ? task["parent_id"] as string : null;

                if (!string.IsNullOrEmpty(parentId))
                {
                    if (!parentChildrenMap.ContainsKey(parentId))
                    {
                        parentChildrenMap[parentId] = new List<IDictionary>();
                    }
                    parentChildrenMap[parentId].Add(task);
                }
                else
                {
                    rootTasks.Add(task);
                }
            }
        }

        // Helper for recursion
        void ProcessTask(IDictionary parent, int depth)
        {
            string parentId = parent["id"] as string;

            // Status icon
            bool completed = parent.Contains("completed") && parent["completed"] is bool b && b;
            string statusIcon = completed ? "[X]" : "[ ]";

            // Active timer check
            if (view != null && view.Contains("ActiveTimer") && view["ActiveTimer"] is IDictionary activeTimer)
            {
                if (activeTimer.Contains("TaskId") && activeTimer["TaskId"] as string == parentId)
                {
                    statusIcon = "[R]";
                }
            }

            // Due date
            string dueStr = "";
            if (parent.Contains("due"))
            {
                try {
                    string d = parent["due"] as string;
                    if (!string.IsNullOrEmpty(d)) {
                        // Minimal parse check or just pass through if already string
                         dueStr = DateTime.Parse(d).ToString("yyyy-MM-dd");
                    }
                } catch {}
            }

            // Tags
            string tagsStr = "";
            if (parent.Contains("tags"))
            {
                var val = parent["tags"];
                if (val is IEnumerable enumTags && !(val is string))
                {
                    var list = new List<string>();
                    foreach(var t in enumTags) list.Add(t.ToString());
                    if (list.Count > 0) tagsStr = "#" + string.Join(" #", list);
                }
            }

            // Priority
            string prioStr = "";
            if (parent.Contains("priority"))
            {
                try {
                    int p = Convert.ToInt32(parent["priority"]);
                    switch(p) {
                         case 1: prioStr = "!"; break;
                         case 2: prioStr = "!!"; break;
                         case 3: prioStr = "!!!"; break;
                    }
                } catch {}
            }

            string text = parent.Contains("text") ? parent["text"] as string : "";

            var disp = new Hashtable();
            disp["id"] = parentId;
            disp["text"] = new string(' ', depth * 2) + text;
            disp["status"] = statusIcon;
            disp["prio"] = prioStr;
            disp["due"] = dueStr;
            disp["tags"] = tagsStr;
            disp["_task"] = parent;

            displayTasks.Add(disp);
            processedIds.Add(parentId);

            if (parentChildrenMap.ContainsKey(parentId))
            {
                foreach (var child in parentChildrenMap[parentId])
                {
                    ProcessTask(child, depth + 1);
                }
            }
        }

        // Process roots
        foreach(var t in rootTasks) ProcessTask(t, 0);

        // Process orphans
        foreach(var t in allTasks)
        {
            string id = t["id"] as string;
            if (!processedIds.Contains(id))
            {
                ProcessTask(t, 0);
            }
        }

        return displayTasks;
    }
}

    /// <summary>
    /// High-performance render utilities.
    /// </summary>
    public static class NativePostProcessor
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static void ApplyScanlines(NativeCellBuffer buffer)
        {
            // Dim every 2nd row to simulate CRT scanlines
            int height = buffer.Height;
            int width = buffer.Width;

            // Iterate alternating rows (1, 3, 5...)
            for (int y = 1; y < height; y += 2)
            {
                for (int x = 0; x < width; x++)
                {
                    NativeCell cell = buffer.GetCell(x, y);

                    // Skip if background is explicit, or maybe we want to dim background too?
                    // Logic is to dim the foreground color slightly or switch to dim variant
                    // Since we don't know the exact enum values here, we'll do a simple bitshift dimming
                    // if it's not black.

                    if (cell.ForegroundRgb > 0)
                    {
                        // Simple 50% dimming approx
                        int r = (cell.ForegroundRgb >> 16) & 0xFF;
                        int g = (cell.ForegroundRgb >> 8) & 0xFF;
                        int b = cell.ForegroundRgb & 0xFF;

                        // Shift right by 1 to halve intensity, mask to keep safe
                        int dimR = (r >> 1) & 0xFF;
                        int dimG = (g >> 1) & 0xFF;
                        int dimB = (b >> 1) & 0xFF;

                        int newFg = (dimR << 16) | (dimG << 8) | dimB;
                        buffer.SetCell(x, y, cell.Char, newFg, cell.BackgroundRgb, cell.Attributes);
                    }
                }
            }
        }

        // Scanline variant that maps specific colors (more robust for themes)
        public static void ApplyScanlinesMap(NativeCellBuffer buffer, int targetColor, int dimColor)
        {
             int height = buffer.Height;
             int width = buffer.Width;

             // First Pass: Force Monochrome (Enforce Phosphor Color) on ALL rows
             for (int y = 0; y < height; y++) {
                 for (int x = 0; x < width; x++) {
                     NativeCell cell = buffer.GetCell(x, y);
                     // Fix: Catch -1 (Default) AND > 0. Only ignore 0 (Black).
                     if (cell.ForegroundRgb != 0) {
                         // Check if it's "White/Gray" or "Generic" and force it to Target

                         // Optional: Allow Red for Alert? (0xFF0000)
                         // Ensure we don't treat -1 as Alert
                         bool isAlert = (cell.ForegroundRgb > 0) && (cell.ForegroundRgb & 0xFF0000) > 0x800000 && (cell.ForegroundRgb & 0x00FF00) < 0x400000;

                         if (!isAlert) {
                             buffer.SetCell(x, y, cell.Char, targetColor, cell.BackgroundRgb, cell.Attributes);
                         }
                     }
                 }
             }

             // Second Pass: Apply Scanlines (Dim alternating rows)
             for (int y = 1; y < height; y += 2)
             {
                 for (int x = 0; x < width; x++)
                 {
                     NativeCell cell = buffer.GetCell(x, y);
                     if (cell.ForegroundRgb == targetColor)
                     {
                         buffer.SetCell(x, y, cell.Char, dimColor, cell.BackgroundRgb, cell.Attributes);
                     }
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
