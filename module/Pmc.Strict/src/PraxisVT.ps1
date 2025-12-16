# VT100/ANSI Core - Stolen directly from Praxis with minimal changes for PMC

class PraxisVT {
    # Cursor movement
    static [string] MoveTo([int]$x, [int]$y) {
        return "`e[$($y+1);$($x+1)H"  # Convert 0-based to 1-based for ANSI
    }
    static [string] SavePos() { return "`e[s" }
    static [string] RestorePos() { return "`e[u" }

    # Cursor visibility
    static [string] Hide() { return "`e[?25l" }
    static [string] Show() { return "`e[?25h" }
    static [string] HideCursor() { return "`e[?25l" }
    static [string] ShowCursor() { return "`e[?25h" }

    # Cursor movement methods
    static [string] MoveUp([int]$n) { return "`e[$($n)A" }
    static [string] MoveDown([int]$n) { return "`e[$($n)B" }
    static [string] MoveRight([int]$n) { return "`e[$($n)C" }
    static [string] MoveLeft([int]$n) { return "`e[$($n)D" }

    # Screen control
    static [string] Clear() { return "`e[2J`e[H" }  # Clear screen and home
    static [string] ClearLine() { return "`e[2K" }  # Clear entire line
    static [string] Home() { return "`e[H" }      # Just home position
    static [string] ClearToDoEnd() { return "`e[J" }  # Clear from cursor to end

    # Basic styles
    static [string] Reset() { return "`e[0m" }
    static [string] Bold() { return "`e[1m" }
    static [string] Dim() { return "`e[2m" }
    static [string] Italic() { return "`e[3m" }
    static [string] Underline() { return "`e[4m" }
    static [string] NoUnderline() { return "`e[24m" }

    # 24-bit True Color
    static [string] RGB([int]$r, [int]$g, [int]$b) {
        return "`e[38;2;$r;$g;$($b)m"
    }
    static [string] RGBBG([int]$r, [int]$g, [int]$b) {
        return "`e[48;2;$r;$g;$($b)m"
    }

    # 256-color support
    static [string] Color256Fg([int]$color) {
        return "`e[38;5;$($color)m"
    }
    static [string] Color256Bg([int]$color) {
        return "`e[48;5;$($color)m"
    }

    # Box drawing - single lines for speed
    static [string] TL() { return "┌" }     # Top left
    static [string] TR() { return "┐" }     # Top right
    static [string] BL() { return "└" }     # Bottom left
    static [string] BR() { return "┘" }     # Bottom right
    static [string] H() { return "─" }      # Horizontal
    static [string] V() { return "│" }      # Vertical
    static [string] Cross() { return "┼" }  # Cross
    static [string] T() { return "┬" }      # T down
    static [string] B() { return "┴" }      # T up
    static [string] L() { return "├" }      # T right
    static [string] R() { return "┤" }      # T left
}

# Layout measurement helpers - stolen from Praxis
class PraxisMeasure {
    static [int] TextWidth([string]$text) {
        # Remove ANSI sequences for accurate measurement
        $clean = $text -replace '\x1b\[[0-9;]*m', ''
        return $clean.Length
    }

    static [string] Truncate([string]$text, [int]$maxWidth) {
        $clean = $text -replace '\x1b\[[0-9;]*m', ''
        if ($clean.Length -le $maxWidth) { return $text }
        return $clean.Substring(0, $maxWidth - 3) + "..."
    }

    static [string] Pad([string]$text, [int]$width, [string]$align = "Left") {
        $textWidth = [PraxisMeasure]::TextWidth($text)
        if ($textWidth -ge $width) { return [PraxisMeasure]::Truncate($text, $width) }

        $padding = $width - $textWidth
        switch ($align) {
            "Left" { return $text + (' ' * $padding) }
            "Right" { return (' ' * $padding) + $text }
            "Center" {
                $left = [int]($padding / 2)
                $right = $padding - $left
                return (' ' * $left) + $text + (' ' * $right)
            }
        }
        return $text
    }
}

# String cache for performance - stolen from Praxis
class PraxisStringCache {
    static [hashtable]$_cache = @{}

    static [string] GetSpaces([int]$count) {
        if ($count -le 0) { return "" }
        if (-not [PraxisStringCache]::_cache.ContainsKey($count)) {
            [PraxisStringCache]::_cache[$count] = ' ' * $count
        }
        return [PraxisStringCache]::_cache[$count]
    }

    static [string] GetChar([char]$c, [int]$count) {
        $key = "$c-$count"
        if (-not [PraxisStringCache]::_cache.ContainsKey($key)) {
            [PraxisStringCache]::_cache[$key] = [string]$c * $count
        }
        return [PraxisStringCache]::_cache[$key]
    }
}