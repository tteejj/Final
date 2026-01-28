# TabbedModal.ps1 - Full-screen tabbed modal component for V3
# Provides tabbed interface for displaying and editing fields
# Used by ProjectInfoModal to show project details

using namespace System.Collections.Generic

class TabbedModal {
    hidden [array]$_tabs = @()              # [{ Name, Fields }]
    hidden [int]$_activeTab = 0
    hidden [int]$_activeField = 0
    hidden [int]$_scrollOffset = 0
    hidden [bool]$_editing = $false
    hidden [string]$_editBuffer = ""
    hidden [int]$_editCursor = 0
    hidden [string]$_title = ""
    hidden [bool]$_visible = $false
    hidden [object]$_onSave = $null         # Callback when field is saved
    hidden [object]$_onAction = $null       # Callback when action field is triggered

    TabbedModal([string]$title) {
        $this._title = $title
    }

    [void] AddTab([string]$name, [array]$fields) {
        $this._tabs += @{
            Name = $name
            Fields = $fields
        }
    }

    [void] ClearTabs() {
        $this._tabs = @()
        $this._activeTab = 0
        $this._activeField = 0
        $this._scrollOffset = 0
    }

    [void] Show() {
        $this._visible = $true
        $this._activeTab = 0
        $this._activeField = 0
        $this._scrollOffset = 0
        $this._editing = $false
    }

    [void] Hide() {
        $this._visible = $false
        $this._editing = $false
    }

    [bool] IsVisible() {
        return $this._visible
    }

    [void] SetOnSave([scriptblock]$callback) {
        $this._onSave = $callback
    }

    [void] SetOnAction([scriptblock]$callback) {
        $this._onAction = $callback
    }

    [void] UpdateFieldValue([string]$fieldName, [object]$value) {
        foreach ($tab in $this._tabs) {
            for ($i = 0; $i -lt $tab.Fields.Count; $i++) {
                if ($tab.Fields[$i].Name -eq $fieldName) {
                    $tab.Fields[$i].Value = $value
                    return
                }
            }
        }
    }

    [hashtable] GetAllValues() {
        $result = @{}
        foreach ($tab in $this._tabs) {
            foreach ($field in $tab.Fields) {
                if ($field.Name -and -not $field.Name.StartsWith('_')) {
                    $result[$field.Name] = $field.Value
                }
            }
        }
        return $result
    }

    [void] Render([HybridRenderEngine]$engine) {
        if (-not $this._visible -or $this._tabs.Count -eq 0) { return }

        $engine.BeginLayer(100)

        $w = $engine.Width
        $h = $engine.Height

        # Draw background box (full screen)
        $engine.Fill(0, 0, $w, $h, " ", [Colors]::Foreground, [Colors]::Background)
        $engine.DrawBox(0, 0, $w, $h, [Colors]::Accent, [Colors]::Background)

        # Title bar
        $engine.WriteAt(2, 0, " $($this._title) ", [Colors]::White, [Colors]::Accent)

        # Tab bar (row 1)
        $tabX = 2
        for ($t = 0; $t -lt $this._tabs.Count; $t++) {
            $tabName = $this._tabs[$t].Name
            $isActive = ($t -eq $this._activeTab)

            $fg = if ($isActive) { [Colors]::White } else { [Colors]::Muted }
            $bg = if ($isActive) { [Colors]::SelectionBg } else { [Colors]::Background }

            $label = " $($t + 1):$tabName "
            $engine.WriteAt($tabX, 1, $label, $fg, $bg)
            $tabX += $label.Length + 1
        }

        # Separator
        $engine.WriteAt(1, 2, ("─" * ($w - 2)), [Colors]::PanelBorder, [Colors]::Background)

        # Fields area
        $fieldsY = 3
        $fieldsH = $h - 5  # Leave room for status bar
        $currentTab = $this._tabs[$this._activeTab]
        $fields = $currentTab.Fields

        # Adjust scroll to keep selection visible
        if ($this._activeField -lt $this._scrollOffset) {
            $this._scrollOffset = $this._activeField
        }
        if ($this._activeField -ge $this._scrollOffset + $fieldsH) {
            $this._scrollOffset = $this._activeField - $fieldsH + 1
        }

        $labelWidth = 20
        $valueWidth = $w - $labelWidth - 6

        for ($displayRow = 0; $displayRow -lt $fieldsH; $displayRow++) {
            $fieldIdx = $displayRow + $this._scrollOffset
            if ($fieldIdx -ge $fields.Count) { break }

            $field = $fields[$fieldIdx]
            $y = $fieldsY + $displayRow
            $isSelected = ($fieldIdx -eq $this._activeField)

            # Check if this is a separator
            if ($field.Name -and $field.Name.StartsWith('_separator')) {
                $engine.WriteAt(2, $y, $field.Label, [Colors]::Muted, [Colors]::Background)
                continue
            }

            # Check if this is an action
            $isAction = $field.ContainsKey('IsAction') -and $field.IsAction

            $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
            $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::Background }

            # Label
            $label = $field.Label
            if ($label.Length -gt $labelWidth) { $label = $label.Substring(0, $labelWidth) }
            $label = $label.PadRight($labelWidth)
            $engine.WriteAt(2, $y, $label, $fg, $bg)

            # Value
            $value = if ($field.Value) { [string]$field.Value } else { "" }
            if ($value.Length -gt $valueWidth) { $value = $value.Substring(0, $valueWidth - 3) + "..." }

            # If editing this field, show edit buffer
            if ($this._editing -and $isSelected) {
                $editDisplay = $this._editBuffer
                if ($editDisplay.Length -gt $valueWidth) { $editDisplay = $editDisplay.Substring(0, $valueWidth) }
                $engine.WriteAt($labelWidth + 3, $y, $editDisplay.PadRight($valueWidth), [Colors]::Black, [Colors]::White)

                # Cursor
                $cursorX = $labelWidth + 3 + $this._editCursor
                if ($cursorX -lt $w - 2) {
                    $cursorChar = if ($this._editCursor -lt $this._editBuffer.Length) { $this._editBuffer[$this._editCursor] } else { " " }
                    $engine.WriteAt($cursorX, $y, $cursorChar, [Colors]::White, [Colors]::Accent)
                }
            } else {
                $valueFg = if ($isAction) { [Colors]::Accent } else { $fg }
                $engine.WriteAt($labelWidth + 3, $y, $value.PadRight($valueWidth), $valueFg, $bg)
            }
        }

        # Scrollbar if needed
        if ($fields.Count -gt $fieldsH) {
            $thumbSize = [Math]::Max(1, [int]($fieldsH * ($fieldsH / $fields.Count)))
            $maxOffset = [Math]::Max(1, $fields.Count - $fieldsH)
            $thumbPos = [int](($this._scrollOffset / $maxOffset) * ($fieldsH - $thumbSize))

            for ($i = 0; $i -lt $fieldsH; $i++) {
                $char = if ($i -ge $thumbPos -and $i -lt $thumbPos + $thumbSize) { "█" } else { "░" }
                $engine.WriteAt($w - 2, $fieldsY + $i, $char, [Colors]::Muted, [Colors]::Background)
            }
        }

        # Status bar
        $statusY = $h - 2
        $engine.Fill(0, $statusY, $w, 1, " ", [Colors]::Foreground, [Colors]::SelectionBg)

        if ($this._editing) {
            $statusText = " [Enter] Save  [Esc] Cancel"
        } else {
            $statusText = " [Tab/←→] Next Tab  [1-7] Jump  [↑↓] Navigate  [Enter] Edit  [Esc] Close  [Ctrl+S] Save All"
        }
        $engine.WriteAt(0, $statusY, $statusText, [Colors]::White, [Colors]::SelectionBg)

        $engine.EndLayer()
    }

    # Returns: "Continue", "Close", "SaveAll"
    [string] HandleInput([ConsoleKeyInfo]$key) {
        if (-not $this._visible) { return "Continue" }

        $currentTab = $this._tabs[$this._activeTab]
        $fields = $currentTab.Fields

        # === EDIT MODE ===
        if ($this._editing) {
            switch ($key.Key) {
                'Escape' {
                    $this._editing = $false
                    return "Continue"
                }
                'Enter' {
                    # Save the edit
                    $field = $fields[$this._activeField]
                    $field.Value = $this._editBuffer
                    $this._editing = $false

                    if ($this._onSave) {
                        & $this._onSave $field.Name $this._editBuffer
                    }
                    return "Continue"
                }
                'Backspace' {
                    if ($this._editCursor -gt 0) {
                        $this._editBuffer = $this._editBuffer.Remove($this._editCursor - 1, 1)
                        $this._editCursor--
                    }
                    return "Continue"
                }
                'Delete' {
                    if ($this._editCursor -lt $this._editBuffer.Length) {
                        $this._editBuffer = $this._editBuffer.Remove($this._editCursor, 1)
                    }
                    return "Continue"
                }
                'LeftArrow' {
                    if ($this._editCursor -gt 0) { $this._editCursor-- }
                    return "Continue"
                }
                'RightArrow' {
                    if ($this._editCursor -lt $this._editBuffer.Length) { $this._editCursor++ }
                    return "Continue"
                }
                'Home' {
                    $this._editCursor = 0
                    return "Continue"
                }
                'End' {
                    $this._editCursor = $this._editBuffer.Length
                    return "Continue"
                }
                Default {
                    if (-not [char]::IsControl($key.KeyChar)) {
                        $this._editBuffer = $this._editBuffer.Insert($this._editCursor, $key.KeyChar)
                        $this._editCursor++
                    }
                    return "Continue"
                }
            }
        }

        # === NORMAL MODE ===
        switch ($key.Key) {
            'Escape' {
                $this.Hide()
                return "Close"
            }
            'Tab' {
                if ($key.Modifiers -band [ConsoleModifiers]::Shift) {
                    $this._activeTab = ($this._activeTab - 1 + $this._tabs.Count) % $this._tabs.Count
                } else {
                    $this._activeTab = ($this._activeTab + 1) % $this._tabs.Count
                }
                $this._activeField = 0
                $this._scrollOffset = 0
                return "Continue"
            }
            'LeftArrow' {
                $this._activeTab = ($this._activeTab - 1 + $this._tabs.Count) % $this._tabs.Count
                $this._activeField = 0
                $this._scrollOffset = 0
                return "Continue"
            }
            'RightArrow' {
                $this._activeTab = ($this._activeTab + 1) % $this._tabs.Count
                $this._activeField = 0
                $this._scrollOffset = 0
                return "Continue"
            }
            'UpArrow' {
                if ($this._activeField -gt 0) {
                    $this._activeField--
                    # Skip separators
                    while ($this._activeField -gt 0 -and $fields[$this._activeField].Name.StartsWith('_separator')) {
                        $this._activeField--
                    }
                }
                return "Continue"
            }
            'DownArrow' {
                if ($this._activeField -lt $fields.Count - 1) {
                    $this._activeField++
                    # Skip separators
                    while ($this._activeField -lt $fields.Count - 1 -and $fields[$this._activeField].Name.StartsWith('_separator')) {
                        $this._activeField++
                    }
                }
                return "Continue"
            }
            'Enter' {
                $field = $fields[$this._activeField]

                # Skip separators
                if ($field.Name.StartsWith('_separator')) {
                    return "Continue"
                }

                # Check if action
                if ($field.ContainsKey('IsAction') -and $field.IsAction) {
                    if ($this._onAction) {
                        & $this._onAction $field.Name
                    }
                    return "Continue"
                }

                # Check if readonly
                if ($field.ContainsKey('Type') -and $field.Type -eq 'readonly') {
                    return "Continue"
                }

                # Start editing
                $this._editing = $true
                $this._editBuffer = if ($field.Value) { [string]$field.Value } else { "" }
                $this._editCursor = $this._editBuffer.Length
                return "Continue"
            }
            'S' {
                if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                    return "SaveAll"
                }
                return "Continue"
            }
            Default {
                # Number keys 1-7 for tab switching
                $num = [int][char]$key.KeyChar - [int][char]'0'
                if ($num -ge 1 -and $num -le $this._tabs.Count) {
                    $this._activeTab = $num - 1
                    $this._activeField = 0
                    $this._scrollOffset = 0
                }
                return "Continue"
            }
        }
        return "Continue"
    }
}
