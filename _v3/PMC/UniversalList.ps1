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
    
    [void] Render([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$w, [int]$h, [array]$items, [array]$columns, [int]$selectedIndex, [bool]$isActive) {
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
        
        # DEBUG: Print exact values being passed
        if ($null -ne $boxTitle) {
             Write-Host "UniversalList: DrawBox($x, $y, $w, $h, Border=$borderColor, Title='$boxTitle')" -ForegroundColor Magenta
        } else {
             Write-Host "UniversalList: DrawBox($x, $y, $w, $h, Border=$borderColor, NO TITLE)" -ForegroundColor Magenta
        }

        # Draw Box Standard (Avoids overload ambiguity)
        # BUG FIX: Must pass [Colors]::PanelBg instead of -1, otherwise DrawBox internal fill
        # resets the background to Terminal Default (Grey) instead of Theme (Black).
        $bg = [Colors]::PanelBg
        Write-Host "UniversalList: PanelBg Value = $bg" -ForegroundColor Magenta
        
        $engine.DrawBox([int]$x, [int]$y, [int]$w, [int]$h, [int]$borderColor, [int]$bg)
        
        # Draw Title Manually
        if ($boxTitle) {
            # Retro Styling
            if ($engine.UseRetroStyle) {
                # Format: "─ Title " matching the box border
                # Note: DrawBox draws "─" at y. We overwrite.
                # Just writing "─ Title " works because " " clears the underlying char.
                $titleStr = "─ $boxTitle "
                $engine.WriteAt($x + 1, $y, $titleStr, [Colors]::Accent, -1)
            } else {
                # Standard Styling "[ Title ]" or " Title "
                $titleStr = " $boxTitle "
                $engine.WriteAt($x + 2, $y, $titleStr, [Colors]::Accent, -1)
            }
        }
        
        if ($items.Count -eq 0) {
            $engine.WriteAt($x + 2, $y + 1, "Empty", [Colors]::Muted, [Colors]::PanelBg)
            $this._scrollOffset = 0
            return
        }
        
        # Calculate visible area
        $visibleRows = $h - 2
        
        # Adjust scroll offset to keep selection visible
        if ($selectedIndex -lt $this._scrollOffset) {
            $this._scrollOffset = $selectedIndex
        }
        if ($selectedIndex -ge $this._scrollOffset + $visibleRows) {
            $this._scrollOffset = $selectedIndex - $visibleRows + 1
        }
        # Clamp scroll offset
        $maxOffset = [Math]::Max(0, $items.Count - $visibleRows)
        $this._scrollOffset = [Math]::Max(0, [Math]::Min($this._scrollOffset, $maxOffset))
        
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
        
        # Rows (with scroll offset)
        for ($displayRow = 0; $displayRow -lt $visibleRows; $displayRow++) {
            $itemIndex = $displayRow + $this._scrollOffset
            if ($itemIndex -ge $items.Count) { break }
            
            $item = $items[$itemIndex]
            $isRowSelected = ($itemIndex -eq $selectedIndex)
            
            $rowY = $y + 1 + $displayRow
            $rowX = $x + 1
            
            $fg = if ($isRowSelected) { [Colors]::SelectionFg } else { [Colors]::Muted }
            $bg = if ($isRowSelected) { [Colors]::SelectionBg } else { [Colors]::PanelBg }
            
            foreach ($col in $columns) {
                $field = if ($col.ContainsKey('Field')) { $col['Field'] } else { "" }
                $w = if ($col.ContainsKey('Width')) { $col['Width'] } else { 10 }
                $w = [Math]::Max(0, $w)
                
                $val = if ($item.ContainsKey($field)) { [string]$item[$field] } else { "" }
                $text = $val.PadRight($w).Substring(0, $w)
                
                $engine.WriteAt($rowX, $rowY, $text, $fg, $bg)
                $rowX += $w + 1
            }
        }
        
        # Draw scrollbar if needed
        if ($items.Count -gt $visibleRows) {
            $this._DrawScrollbar($engine, $x + $w - 1, $y + 1, $visibleRows, $items.Count)
        }
    }
    
    hidden [void] _DrawScrollbar([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$height, [int]$totalItems) {
        if ($height -le 0 -or $totalItems -le 0) { return }
        
        # Calculate thumb size and position
        $thumbSize = [Math]::Max(1, [int]($height * ($height / $totalItems)))
        $maxOffset = [Math]::Max(1, $totalItems - $height)
        $thumbPos = [int](($this._scrollOffset / $maxOffset) * ($height - $thumbSize))
        
        for ($i = 0; $i -lt $height; $i++) {
            $char = if ($i -ge $thumbPos -and $i -lt $thumbPos + $thumbSize) { "█" } else { "░" }
            $engine.WriteAt($x, $y + $i, $char, [Colors]::Muted, [Colors]::PanelBg)
        }
    }
}
