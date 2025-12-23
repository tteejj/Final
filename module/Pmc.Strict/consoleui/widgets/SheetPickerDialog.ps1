using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

. "$PSScriptRoot/PmcDialog.ps1"

<#
.SYNOPSIS
Sheet picker dialog for Excel sheet selection

.DESCRIPTION
Shows a list of Excel sheet names with keyboard navigation.
User can select a sheet using arrow keys and Enter.
#>
class SheetPickerDialog : PmcDialog {
    hidden [array]$_sheets = @()
    hidden [int]$_selectedIndex = 0

    [scriptblock]$OnSheetSelected = {}

    SheetPickerDialog([array]$sheets, [string]$title) : base($title, "") {
        $this._sheets = $sheets
        $this._selectedIndex = 0

        # Calculate dimensions based on sheet count
        $maxNameLength = 0
        foreach ($sheet in $sheets) {
            if ($sheet.Length -gt $maxNameLength) {
                $maxNameLength = $sheet.Length
            }
        }

        $this.Width = [Math]::Max(40, $maxNameLength + 10)
        $this.Height = [Math]::Min(25, $sheets.Count + 8)
    }

    [void] RenderToEngine([object]$engine) {
        # Render base dialog (shadow, box, title)
        ([PmcDialog]$this).RenderToEngine($engine)

        $bg = $this.GetThemedColorInt('Background.Widget')
        $fg = $this.GetThemedColorInt('Foreground.Primary')
        $selectedBg = $this.GetThemedColorInt('Background.RowSelected')
        $selectedFg = $this.GetThemedColorInt('Foreground.RowSelected')

        # Render sheet list
        $listY = $this.Y + 3
        $maxVisibleItems = $this.Height - 6

        # Calculate scroll offset if needed
        $scrollOffset = 0
        if ($this._sheets.Count -gt $maxVisibleItems) {
            if ($this._selectedIndex -ge $maxVisibleItems) {
                $scrollOffset = $this._selectedIndex - $maxVisibleItems + 1
            }
        }

        # Render visible sheets
        $visibleCount = [Math]::Min($maxVisibleItems, $this._sheets.Count)
        for ($i = 0; $i -lt $visibleCount; $i++) {
            $sheetIndex = $i + $scrollOffset
            if ($sheetIndex -ge $this._sheets.Count) { break }

            $sheet = $this._sheets[$sheetIndex]
            $isSelected = ($sheetIndex -eq $this._selectedIndex)

            $itemBg = if ($isSelected) { $selectedBg } else { $bg }
            $itemFg = if ($isSelected) { $selectedFg } else { $fg }

            $prefix = if ($isSelected) { "> " } else { "  " }
            $text = "$prefix$sheet"

            # Truncate if too long
            $maxWidth = $this.Width - 4
            if ($text.Length -gt $maxWidth) {
                $text = $text.Substring(0, $maxWidth - 3) + "..."
            }

            $engine.WriteAt($this.X + 2, $listY + $i, $text, $itemFg, $itemBg)
        }

        # Footer with instructions
        $footer = "↑↓: Navigate | Enter: Select | Esc: Cancel"
        $footerX = $this.X + [Math]::Floor(($this.Width - $footer.Length) / 2)
        $footerY = $this.Y + $this.Height - 2
        $engine.WriteAt($footerX, $footerY, $footer, $fg, $bg)

        # Scroll indicators
        if ($this._sheets.Count -gt $maxVisibleItems) {
            if ($scrollOffset -gt 0) {
                $engine.WriteAt($this.X + $this.Width - 3, $this.Y + 3, "▲", $fg, $bg)
            }
            if ($scrollOffset + $maxVisibleItems -lt $this._sheets.Count) {
                $engine.WriteAt($this.X + $this.Width - 3, $this.Y + $this.Height - 3, "▼", $fg, $bg)
            }
        }
    }

    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this._selectedIndex -gt 0) {
                    $this._selectedIndex--
                }
                return $true
            }
            'DownArrow' {
                if ($this._selectedIndex -lt ($this._sheets.Count - 1)) {
                    $this._selectedIndex++
                }
                return $true
            }
            'Enter' {
                $selectedSheet = $this._sheets[$this._selectedIndex]
                $this.Result = $true
                $this.IsComplete = $true
                if ($this.OnSheetSelected) {
                    & $this.OnSheetSelected $selectedSheet
                }
                return $true
            }
            'Escape' {
                $this.Result = $false
                $this.IsComplete = $true
                return $true
            }
            'Home' {
                $this._selectedIndex = 0
                return $true
            }
            'End' {
                $this._selectedIndex = $this._sheets.Count - 1
                return $true
            }
            'PageUp' {
                $this._selectedIndex = [Math]::Max(0, $this._selectedIndex - 10)
                return $true
            }
            'PageDown' {
                $this._selectedIndex = [Math]::Min($this._sheets.Count - 1, $this._selectedIndex + 10)
                return $true
            }
        }
        return $false
    }

    [string] GetSelectedSheet() {
        if ($this._selectedIndex -ge 0 -and $this._selectedIndex -lt $this._sheets.Count) {
            return $this._sheets[$this._selectedIndex]
        }
        return ""
    }
}
