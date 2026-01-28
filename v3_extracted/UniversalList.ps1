# UniversalList.ps1 - Generic high-performance list component with virtual scrolling
using namespace System.Collections.Generic

class UniversalList {
    [string]$Id
    hidden [int]$_scrollOffset = 0

    UniversalList([string]$id) {
        $this.Id = $id
    }

    [int] GetScrollOffset() {
        return $this._scrollOffset
    }

    [void] Render([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$w, [int]$h, [array]$items, [array]$columns, [int]$selectedIndex, [bool]$isActive, [int[]]$rowHeights = $null) {
        if ($w -le 0 -or $h -le 0) { return }
        # Draw Border
        $borderColor = if ($isActive) { [Colors]::Accent } else { [Colors]::PanelBorder }
        # Fill background first to clear potential artifacts
        $engine.Fill($x, $y, $w, $h, " ", [Colors]::Foreground, [Colors]::PanelBg)
        # Decide if we can use the native Box Title (Cleaner for single column)
        $boxTitle = ""
        if ($columns.Count -eq 1) {
            # Single column: Use its header as the Box Title
            $col = $columns[0]
            if ($col.ContainsKey('Header')) { $boxTitle = $col['Header'] }
        }

        # Draw Box Standard (Avoids overload ambiguity)
        # BUG FIX: Must pass [Colors]::PanelBg instead of -1, otherwise DrawBox internal fill
        # resets the background to Terminal Default (Grey) instead of Theme (Black).
        $bg = [Colors]::PanelBg

        $engine.DrawBox([int]$x, [int]$y, [int]$w, [int]$h, [int]$borderColor, [int]$bg)

        # Draw Title Manually
        if ($boxTitle) {
            # Retro Styling
            if ($engine.UseRetroStyle) {
                # Format: "─ Title " matching the box border
                # Note: DrawBox draws "─" at y. We overwrite.
                # Just writing "─ Title " works because " " clears the underlying char.
                $titleStr = "─ $boxTitle "
                $engine.WriteAt($x + 1, $y, $titleStr, [Colors]::Header, [Colors]::PanelBg)
            } else {
                # Standard Styling "[ Title ]" or " Title "
                $titleStr = " $boxTitle "
                $engine.WriteAt($x + 2, $y, $titleStr, [Colors]::Header, [Colors]::PanelBg)
            }
        }

        if ($items.Count -eq 0) {
            $engine.WriteAt($x + 2, $y + 1, "Empty", [Colors]::Muted, [Colors]::PanelBg)
            $this._scrollOffset = 0
            return
        }

        # Calculate visible area and row heights
        $visibleRows = $h - 2

        # If rowHeights not provided, assume uniform height of 1
        if ($null -eq $rowHeights -or $rowHeights.Count -eq 0) {
            $rowHeights = @(1) * $items.Count
        }

        # Calculate cumulative heights for scrolling
        $cumulativeHeights = [List[int]]::new()
        $cumulative = 0
        foreach ($height in $rowHeights) {
            $cumulativeHeights.Add($cumulative)
            $cumulative += $height
        }

        # Calculate maxOffset for header scroll indicator (how many rows can we scroll?)
        $totalHeight = 0
        foreach ($height in $rowHeights) {
            $totalHeight += $height
        }
        $maxOffset = [Math]::Max(0, $totalHeight - $visibleRows)

        # Adjust scroll offset to keep selection visible (based on cumulative heights)
        $selectionY = if ($selectedIndex -ge 0 -and $selectedIndex -lt $cumulativeHeights.Count) { $cumulativeHeights[$selectedIndex] } else { 0 }
        $visibleHeight = 0
        for ($i = $this._scrollOffset; $i -lt $items.Count; $i++) {
            if ($visibleHeight + $rowHeights[$i] -gt $visibleRows) { break }
            $visibleHeight += $rowHeights[$i]
        }

        if ($selectionY -lt $cumulativeHeights[$this._scrollOffset]) {
            # Find first row where cumulative height >= selectionY
            for ($i = 0; $i -lt $items.Count; $i++) {
                if ($cumulativeHeights[$i] -gt $selectionY) {
                    $this._scrollOffset = $i
                    break
                }
            }
        }

        $endVisibleY = if ($this._scrollOffset -lt $items.Count) { $cumulativeHeights[$this._scrollOffset] + $visibleRows } else { 0 }
        if ($selectionY -ge $endVisibleY) {
            # Find first row where visible area includes selection
            for ($i = $this._scrollOffset; $i -lt $items.Count; $i++) {
                if ($cumulativeHeights[$i] + $rowHeights[$i] -gt $endVisibleY - $rowHeights[$i]) {
                    $this._scrollOffset = $i
                    break
                }
            }
        }

        # Calculate total height for scrollbar
        $totalHeight = 0
        foreach ($height in $rowHeights) {
            $totalHeight += $height
        }

        # Clamp scroll offset
        $this._scrollOffset = [Math]::Max(0, [Math]::Min($this._scrollOffset, $items.Count - 1))

        # Calculate maxOffset for header scroll indicator
        $maxOffset = if ($totalHeight -gt $visibleRows) { $totalHeight - $visibleRows } else { 0 }

        # Header (Only if multiple columns, otherwise Title handled it)

        # Header (Only if multiple columns, otherwise Title handled it)
        if ($columns.Count -gt 1) {
            $currentColX = $x + 1
            foreach ($col in $columns) {
                $hTxt = if ($col.ContainsKey('Header')) { $col['Header'] } else { "" }
                $colW = if ($col.ContainsKey('Width')) { $col['Width'] } else { 10 }
                $colW = [Math]::Max(0, $colW)

                # Standard Logic
                $header = $hTxt.PadRight($colW).Substring(0, $colW)
                $engine.WriteAt($currentColX, $y, $header, [Colors]::Header, [Colors]::PanelBg)
                # Separator
                $engine.WriteAt($currentColX + $colW, $y, " ", [Colors]::Background, [Colors]::PanelBg)
                $currentColX += $colW + 1
            }
        }

        # Scrollbar indicator in header if needed
        if ($items.Count -gt $visibleRows) {
            $scrollPct = if ($maxOffset -gt 0) { [int](($this._scrollOffset / $maxOffset) * 100) } else { 0 }
            $scrollInfo = " $($this._scrollOffset + 1)-$([Math]::Min($this._scrollOffset + $visibleRows, $items.Count))/$($items.Count)"
            $engine.WriteAt($x + $w - $scrollInfo.Length - 1, $y, $scrollInfo, [Colors]::Muted, [Colors]::PanelBg)
        }

        # Rows (with scroll offset and variable heights)
        $currentY = $y + 1
        for ($itemIndex = $this._scrollOffset; $itemIndex -lt $items.Count; $itemIndex++) {
            $rowHeight = if ($itemIndex -lt $rowHeights.Count) { $rowHeights[$itemIndex] } else { 1 }

            # Check if this row will fit in visible area
            if ($currentY + $rowHeight - 1 -gt $y + $visibleRows) { break }

            $item = $items[$itemIndex]
            $isRowSelected = ($itemIndex -eq $selectedIndex)

            $rowX = $x + 1
            $fg = if ($isRowSelected) { [Colors]::SelectionFg } else { [Colors]::Muted }
            $bg = if ($isRowSelected) { [Colors]::SelectionBg } else { [Colors]::PanelBg }

            # Draw selection background across entire row height if selected
            if ($isRowSelected) {
                $engine.Fill($x + 1, $currentY, $w - 2, $rowHeight, " ", $fg, $bg)
            }

            foreach ($col in $columns) {
                $field = if ($col.ContainsKey('Field')) { $col['Field'] } else { "" }
                $w = if ($col.ContainsKey('Width')) { $col['Width'] } else { 10 }
                $w = [Math]::Max(0, $w)

                $val = if ($item.ContainsKey($field)) { [string]$item[$field] } else { "" }
                $text = $val.PadRight($w).Substring(0, $w)

                $engine.WriteAt($rowX, $currentY, $text, $fg, $bg)
                $rowX += $w + 1
            }

            $currentY += $rowHeight
        }

        # Draw scrollbar if needed (with variable height support)
        $totalHeight = 0
        foreach ($height in $rowHeights) {
            $totalHeight += $height
        }

        # Calculate visible height
        $visibleHeight = 0
        for ($i = $this._scrollOffset; $i -lt $items.Count; $i++) {
            if ($visibleHeight + $rowHeights[$i] -gt $visibleRows) { break }
            $visibleHeight += $rowHeights[$i]
        }

        if ($totalHeight -gt $visibleRows) {
            $this._DrawScrollbar($engine, $x + $w - 1, $y + 1, $visibleRows, $totalHeight, $this._scrollOffset)
        }
    }

    hidden [void] _DrawScrollbar([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$visibleHeight, [int]$totalHeight, [int]$scrollOffset) {
        if ($visibleHeight -le 0 -or $totalHeight -le 0) { return }

        # Calculate thumb size and position
        $thumbSize = [Math]::Max(1, [int]($visibleHeight * ($visibleHeight / $totalHeight)))
        $maxOffset = $totalHeight - $visibleHeight
        if ($maxOffset -le 0) { return }

        $thumbPos = [int](($scrollOffset / $maxOffset) * ($visibleHeight - $thumbSize))

        for ($i = 0; $i -lt $visibleHeight; $i++) {
            $char = if ($i -ge $thumbPos -and $i -lt $thumbPos + $thumbSize) { "█" } else { "░" }
            $engine.WriteAt($x, $y + $i, $char, [Colors]::Muted, [Colors]::PanelBg)
        }
    }
}
