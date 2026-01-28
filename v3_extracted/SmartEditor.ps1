# SmartEditor.ps1 - The new "InlineEditor" replacement
# Integrates with HybridRenderEngine and InputLogic to provide multi-field editing IN-PLACE.

using namespace System.Collections.Generic
using namespace System.Text

class SmartEditorField {
    [string]$Name
    [string]$Label
    [string]$Type        # Text, Number, Date, Project, Tags
    [object]$Value
    [int]$Width
    [int]$X              # Relative X offset

    # Text Input State
    [int]$CursorPos = 0
    [int]$ScrollOffset = 0
}

class SmartEditor {
    hidden [List[SmartEditorField]]$_fields
    hidden [int]$_activeFieldIndex = 0
    hidden [bool]$_isExpanded = $false # For dropdowns/calendars
    hidden [int]$_screenX
    hidden [int]$_screenY

    # Cache for external data (Projects)
    hidden [string[]]$_projectCache
    hidden [string[]]$_filteredProjects
    hidden [int]$_projectSelectionIndex = 0

    # Calendar State
    hidden [DateTime]$_calendarMonth = [DateTime]::Today

    SmartEditor() {
        $this._fields = [List[SmartEditorField]]::new()
    }

    [void] Configure([hashtable[]]$fieldDefs, [int]$x, [int]$y) {
        $this._fields.Clear()
        $this._screenX = $x
        $this._screenY = $y
        $this._activeFieldIndex = 0
        $this._isExpanded = $false

        $currentX = 0
        foreach ($def in $fieldDefs) {
            $f = [SmartEditorField]::new()
            $f.Name = $def['Name']
            $f.Label = $def['Label']
            $f.Type = $def['Type']
            $f.Value = if ($def.ContainsKey('Value')) { $def['Value'] } else { "" }
            $f.Width = $def['Width']
            $f.X = $currentX

            # Init cursor at end of value
            $valStr = if ($null -ne $f.Value) { $f.Value.ToString() } else { "" }
            $f.CursorPos = $valStr.Length

            $this._fields.Add($f)
            $currentX += $def['Width'] + 1 # +1 for spacing/separator
        }
    }

    [void] LoadProjects([array]$projects) {
        $names = @()
        foreach ($p in $projects) { $names += $p.name }
        $this._projectCache = $names
    }

    [hashtable] GetValues() {
        $result = @{}
        foreach ($f in $this._fields) {
            $val = $f.Value
            # Post-process specific types
            if ($f.Type -eq 'Date') {
                # Try to parse if it's a string, otherwise return as is
                if ($val -is [string]) {
                    $parsed = [InputLogic]::ParseDateInput($val)
                    if ($parsed -ne [DateTime]::MinValue) { $val = $parsed }
                }
            }
            $result[$f.Name] = $val
        }
        return $result
    }

    # === Rendering ===

    [void] Render([HybridRenderEngine]$engine) {
        # Use high Z-index to overlay on list
        $engine.BeginLayer(50)

        for ($i = 0; $i -lt $this._fields.Count; $i++) {
            $f = $this._fields[$i]
            $absX = $this._screenX + $f.X
            $isActive = ($i -eq $this._activeFieldIndex)

            # Background Color: Active = Blue, Inactive = DarkGray
            $bg = if ($isActive) { [Colors]::SelectionBg } else { [Colors]::PanelBg }
            $fg = if ($isActive) { [Colors]::SelectionFg } else { [Colors]::Muted }

            # Clear field area
            $engine.Fill($absX, $this._screenY, $f.Width, 1, " ", $fg, $bg)

            # Render Value
            $valStr = $f.Value.ToString()

            # Scroll/Clip text
            $visibleText = $valStr
            if ($f.CursorPos -ge $f.ScrollOffset + $f.Width) {
                $f.ScrollOffset = $f.CursorPos - $f.Width + 1
            }
            if ($f.CursorPos -lt $f.ScrollOffset) {
                $f.ScrollOffset = $f.CursorPos
            }

            if ($valStr.Length -gt $f.ScrollOffset) {
                $visibleText = $valStr.Substring($f.ScrollOffset)
            }
            if ($visibleText.Length -gt $f.Width) {
                $visibleText = $visibleText.Substring(0, $f.Width)
            }

            $engine.WriteAt($absX, $this._screenY, $visibleText, $fg, $bg)

            # Render Cursor (only if active)
            if ($isActive) {
                $relCursor = $f.CursorPos - $f.ScrollOffset
                if ($relCursor -ge 0 -and $relCursor -le $visibleText.Length) { # Allow cursor at end
                     $cursorChar = " "
                     if ($relCursor -lt $visibleText.Length) { $cursorChar = $visibleText[$relCursor] }
                     $engine.WriteAt($absX + $relCursor, $this._screenY, $cursorChar, [Colors]::Black, [Colors]::White)
                }

                # Render Expanded Widget (Overlay)
                if ($this._isExpanded) {
                    $this._RenderExpanded($engine, $f, $absX, $this._screenY + 1)
                }
            }
        }

        $engine.EndLayer()
    }

    hidden [void] _RenderExpanded([HybridRenderEngine]$engine, [SmartEditorField]$f, [int]$x, [int]$y) {
        $engine.BeginLayer(60) # Topmost

        if ($f.Type -eq 'Project') {
            # Render Dropdown
            $w = 30
            $h = 8
            # Bounds Check
            if ($x + $w -gt $engine.Width) { $x = $engine.Width - $w - 1 }

            $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
            $matches = [InputLogic]::FuzzySearchProjects($this._projectCache, $f.Value.ToString())
            $this._filteredProjects = $matches

            for ($i = 0; $i -lt [Math]::Min($matches.Count, 6); $i++) {
                $p = $matches[$i]
                $bg = if ($i -eq $this._projectSelectionIndex) { [Colors]::SelectionBg } else { [Colors]::PanelBg }
                $fg = if ($i -eq $this._projectSelectionIndex) { [Colors]::SelectionFg } else { [Colors]::Foreground }
                $engine.WriteAt($x + 1, $y + 1 + $i, $p.PadRight(28).Substring(0,28), $fg, $bg)
            }
        }

        elseif ($f.Type -eq 'Date') {
            # Bounds Check (Calendar W=26)
            if ($x + 26 -gt $engine.Width) { $x = $engine.Width - 26 - 1 }
            $this._RenderCalendar($engine, $f, $x, $y)
        }

        $engine.EndLayer()
    }

    hidden [void] _RenderCalendar([HybridRenderEngine]$engine, [SmartEditorField]$f, [int]$x, [int]$y) {
        # Calendar Dimensions: 24h x 10h (approx)
        $w = 26
        $h = 10

        # Ensure Month is valid (or init from value)
        if ($this._calendarMonth -eq [DateTime]::MinValue) {
             $val = [InputLogic]::ParseDateInput($f.Value.ToString())
             if ($val -eq [DateTime]::MinValue) { $val = [DateTime]::Today }
             $this._calendarMonth = $val
        }

        # Current Selection (parsed from field)
        $selectedDate = [InputLogic]::ParseDateInput($f.Value.ToString())
        if ($selectedDate -eq [DateTime]::MinValue) { $selectedDate = [DateTime]::Today }

        # Draw Box
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
        $bg = [Colors]::PanelBg
        $fg = [Colors]::Foreground

        # Header (Month Year)
        $title = $this._calendarMonth.ToString("MMMM yyyy")
        $pad = [Math]::Max(0, [Math]::Floor(($w - 2 - $title.Length) / 2))
        $engine.WriteAt($x + 1 + $pad, $y + 1, $title, [Colors]::Header, $bg)

        # Days Header
        $engine.WriteAt($x + 2, $y + 2, "Su Mo Tu We Th Fr Sa", [Colors]::Muted, $bg)

        # Grid
        $firstDay = [DateTime]::new($this._calendarMonth.Year, $this._calendarMonth.Month, 1)
        $daysInMonth = [DateTime]::DaysInMonth($this._calendarMonth.Year, $this._calendarMonth.Month)
        $startDayOfWeek = [int]$firstDay.DayOfWeek
        $today = [DateTime]::Today

        for ($week = 0; $week -lt 6; $week++) {
            $rowY = $y + 3 + $week
            $startX = $x + 2

            for ($dow = 0; $dow -lt 7; $dow++) {
                $dayNum = ($week * 7 + $dow) - $startDayOfWeek + 1
                $cellX = $startX + ($dow * 3)

                if ($dayNum -ge 1 -and $dayNum -le $daysInMonth) {
                    $thisDate = [DateTime]::new($this._calendarMonth.Year, $this._calendarMonth.Month, $dayNum)
                    $dayStr = $dayNum.ToString().PadLeft(2)

                    $isSelected = ($thisDate.Date -eq $selectedDate.Date)
                    $isToday = ($thisDate.Date -eq $today)

                    $cBg = $bg
                    $cFg = $fg

                    if ($isSelected) {
                        $cBg = [Colors]::SelectionBg
                        $cFg = [Colors]::SelectionFg
                    }
                    elseif ($isToday) {
                        $cFg = [Colors]::Success
                    }

                    $engine.WriteAt($cellX, $rowY, $dayStr, $cFg, $cBg)
                }
            }
        }
    }

    # === Input Handling ===

    # Returns: "Continue", "Save", "Cancel"
    [string] HandleInput([ConsoleKeyInfo]$key) {
        $f = $this._fields[$this._activeFieldIndex]

        if ($this._isExpanded) {
            if ($f.Type -eq 'Project') {
                return $this._HandleProjectExpanded($key, $f)
            }
            elseif ($f.Type -eq 'Date') {
                return $this._HandleDateExpanded($key, $f)
            }
        }

        switch ($key.Key) {
            'Escape' { return "Cancel" }
            'Enter' {
                if ($key.Modifiers -band [ConsoleModifiers]::Control) { return "Save" } # Ctrl+Enter always saves
                if ($this._activeFieldIndex -lt $this._fields.Count - 1) {
                    $this._activeFieldIndex++
                    return "Continue"
                } else {
                    return "Save"
                }
            }
            'Tab' {
                if ($key.Modifiers -band [ConsoleModifiers]::Shift) {
                    if ($this._activeFieldIndex -gt 0) { $this._activeFieldIndex-- }
                } else {
                    if ($this._activeFieldIndex -lt $this._fields.Count - 1) {
                        $this._activeFieldIndex++
                    } else {
                        # Loop or stay? Stay for now.
                    }
                }
                return "Continue"
            }
            'F2' {
                $this._isExpanded = -not $this._isExpanded
                return "Continue"
            }
            'LeftArrow' {
                if ($f.Type -eq 'Number') {
                    $f.Value = [InputLogic]::AdjustTime([double]$f.Value, 'Down', 0.25, 24.0)
                } elseif ($f.CursorPos -gt 0) {
                    $f.CursorPos--
                }
                return "Continue"
            }
            'RightArrow' {
                if ($f.Type -eq 'Number') {
                    $f.Value = [InputLogic]::AdjustTime([double]$f.Value, 'Up', 0.25, 24.0)
                } elseif ($f.CursorPos -lt $f.Value.ToString().Length) {
                    $f.CursorPos++
                }
                return "Continue"
            }
            'Backspace' {
                if ($f.CursorPos -gt 0) {
                    $val = $f.Value.ToString()
                    $f.Value = $val.Remove($f.CursorPos - 1, 1)
                    $f.CursorPos--
                    # Auto-expand project on edit
                    if ($f.Type -eq 'Project') { $this._isExpanded = $true }
                }
                return "Continue"
            }
            Default {
                if (-not [char]::IsControl($key.KeyChar)) {
                    $val = $f.Value.ToString()
                    $f.Value = $val.Insert($f.CursorPos, $key.KeyChar.ToString())
                    $f.CursorPos++
                    # Auto-expand project
                    if ($f.Type -eq 'Project') { $this._isExpanded = $true }
                    # Auto-expand Date on typing? Maybe not. Let explicit DownArrow do it.
                }
                return "Continue"
            }
            'DownArrow' {
                # General DownArrow handling to expand widgets
                 if ($f.Type -eq 'Project' -or $f.Type -eq 'Date') {
                    $this._isExpanded = $true
                    # Init logic
                    if ($f.Type -eq 'Date') {
                         $val = [InputLogic]::ParseDateInput($f.Value.ToString())
                         if ($val -eq [DateTime]::MinValue) { $val = [DateTime]::Today }
                         $this._calendarMonth = $val
                    }
                    return "Continue"
                }
            }
        }
        return "Continue"
    }

    hidden [string] _HandleProjectExpanded([ConsoleKeyInfo]$key, [SmartEditorField]$f) {
        switch ($key.Key) {
            'UpArrow' {
                if ($this._projectSelectionIndex -gt 0) { $this._projectSelectionIndex-- }
                return "Continue"
            }
            'DownArrow' {
                if ($this._projectSelectionIndex -lt ($this._filteredProjects.Count - 1)) {
                    $this._projectSelectionIndex++
                }
                return "Continue"
            }
            'Enter' {
                if ($this._filteredProjects.Count -gt 0) {
                    $f.Value = $this._filteredProjects[$this._projectSelectionIndex]
                    $f.CursorPos = $f.Value.Length
                }
                $this._isExpanded = $false
                return "Continue"
            }
            'Escape' {
                $this._isExpanded = $false
                return "Continue"
            }
        }
        # Pass-through other keys (typing) to main handler but keep expanded
        $res = $this.HandleInput($key) # Recurse? No, manual handling or refactor.
        # Simple fix: Let default handler modify text, then we re-filter in Render
        return "Continue"

    }

    hidden [string] _HandleDateExpanded([ConsoleKeyInfo]$key, [SmartEditorField]$f) {
        # Current Selection
        $current = [InputLogic]::ParseDateInput($f.Value.ToString())
        if ($current -eq [DateTime]::MinValue) { $current = [DateTime]::Today }

        $newDate = $current
        $changed = $false

        switch ($key.Key) {
            'LeftArrow' { $newDate = $current.AddDays(-1); $changed = $true }
            'RightArrow' { $newDate = $current.AddDays(1); $changed = $true }
            'UpArrow' { $newDate = $current.AddDays(-7); $changed = $true }
            'DownArrow' { $newDate = $current.AddDays(7); $changed = $true }
            'PageUp' { $newDate = $current.AddMonths(-1); $changed = $true }
            'PageDown' { $newDate = $current.AddMonths(1); $changed = $true }
            'Home' { $newDate = [DateTime]::new($current.Year, $current.Month, 1); $changed = $true }
            'End' { $newDate = [DateTime]::new($current.Year, $current.Month, [DateTime]::DaysInMonth($current.Year, $current.Month)); $changed = $true }
            'Enter' {
                $this._isExpanded = $false
                return "Continue"
            }
            'Escape' {
                $this._isExpanded = $false
                return "Continue"
            }
        }

        if ($changed) {
            $f.Value = $newDate.ToString("yyyy-MM-dd")
            $f.CursorPos = $f.Value.Length
            # Sync calendar month if we moved out of view
            if ($newDate.Month -ne $this._calendarMonth.Month -or $newDate.Year -ne $this._calendarMonth.Year) {
                $this._calendarMonth = $newDate
            }
        }
        return "Continue"
    }
}
