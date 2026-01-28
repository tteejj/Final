# CommandPalette.ps1 - Searchable command palette modal
# Shows all available commands with filtering and execution

class CommandPalette {
    hidden [bool]$_visible = $false
    hidden [array]$_commands = @()
    hidden [array]$_filtered = @()
    hidden [string]$_filter = ""
    hidden [int]$_selectedIndex = 0
    hidden [int]$_scrollOffset = 0
    hidden [string]$_context = ""

    CommandPalette() {
        $this._BuildCommands()
    }

    hidden [void] _BuildCommands() {
        # Define all commands with categories
        $this._commands = @(
            @{ Key = "Q"; Category = "Global"; Name = "Quit"; Description = "Exit application" }
            @{ Key = "H"; Category = "Global"; Name = "Global Notes"; Description = "Open general notes" }
            @{ Key = "K"; Category = "Global"; Name = "Global Checklists"; Description = "Open global checklists" }
            @{ Key = "L"; Category = "Global"; Name = "Log Time (General)"; Description = "Log non-project time" }
            @{ Key = "O"; Category = "Global"; Name = "Overview"; Description = "Open overview dashboard" }
            @{ Key = "W"; Category = "Global"; Name = "Weekly Report"; Description = "View weekly time report" }
            @{ Key = "D"; Category = "Global"; Name = "Toggle Kanban"; Description = "Switch to Kanban board view" }
            @{ Key = "?"; Category = "Global"; Name = "Command Palette"; Description = "This menu" }
            @{ Key = "Ctrl+S"; Category = "Global"; Name = "Save"; Description = "Save all data" }
            @{ Key = "Tab"; Category = "Navigation"; Name = "Next Panel"; Description = "Move focus to next panel" }
            @{ Key = "Arrows"; Category = "Navigation"; Name = "Navigate"; Description = "Move between panels/items" }
            @{ Key = "N"; Category = "Sidebar"; Name = "New Project"; Description = "Create new project" }
            @{ Key = "V"; Category = "Sidebar"; Name = "Project Info"; Description = "View project details" }
            @{ Key = "T"; Category = "Sidebar"; Name = "Time Entries"; Description = "Open time modal for project" }
            @{ Key = "M"; Category = "Sidebar"; Name = "Edit Notes"; Description = "Edit project notes" }
            @{ Key = "F"; Category = "Sidebar"; Name = "Open Folder"; Description = "Open project folder" }
            @{ Key = "Delete"; Category = "Sidebar"; Name = "Delete Project"; Description = "Delete selected project" }
            @{ Key = "N"; Category = "TaskList"; Name = "New Task"; Description = "Create new task" }
            @{ Key = "S"; Category = "TaskList"; Name = "New Subtask"; Description = "Create subtask under selected" }
            @{ Key = "E"; Category = "TaskList"; Name = "Edit Task"; Description = "Edit selected task" }
            @{ Key = "M"; Category = "TaskList"; Name = "Edit Notes"; Description = "Edit task notes" }
            @{ Key = "Enter"; Category = "TaskList"; Name = "Toggle Complete"; Description = "Mark task complete/incomplete" }
            @{ Key = "Delete"; Category = "TaskList"; Name = "Delete Task"; Description = "Delete selected task" }
            @{ Key = "N"; Category = "TimeModal"; Name = "New Entry"; Description = "Add new time entry" }
            @{ Key = "Enter"; Category = "TimeModal"; Name = "Edit Entry"; Description = "Edit selected entry" }
            @{ Key = "Delete"; Category = "TimeModal"; Name = "Delete Entry"; Description = "Delete selected entry" }
            @{ Key = "Tab"; Category = "TimeModal"; Name = "Switch Tab"; Description = "Toggle Entries/Weekly view" }
            @{ Key = "Esc"; Category = "TimeModal"; Name = "Close"; Description = "Close time modal" }
            @{ Key = "D"; Category = "Kanban"; Name = "Close View"; Description = "Return to Dashboard" }
            @{ Key = "←→"; Category = "Kanban"; Name = "Move Columns"; Description = "Navigate between columns" }
            @{ Key = "↑↓"; Category = "Kanban"; Name = "Select Task"; Description = "Select tasks in column" }
            @{ Key = "Shift+←→"; Category = "Kanban"; Name = "Move Task"; Description = "Move task between columns" }
            @{ Key = "Enter"; Category = "Kanban"; Name = "Advance Task"; Description = "Move task to next column" }
        )
        $this._filtered = $this._commands
    }

    [void] Open([string]$context) {
        [Logger]::Log("CommandPalette.Open: context=$context", 2)
        $this._visible = $true
        $this._context = $context
        $this._filter = ""
        $this._selectedIndex = 0
        $this._scrollOffset = 0
        $this._ApplyFilter()
    }

    [void] Close() {
        [Logger]::Log("CommandPalette.Close", 2)
        $this._visible = $false
    }

    [bool] IsVisible() {
        return $this._visible
    }

    hidden [void] _ApplyFilter() {
        try {
            if ([string]::IsNullOrEmpty($this._filter)) {
                $this._filtered = $this._commands
            } else {
                $pattern = "*$($this._filter)*"
                $this._filtered = @($this._commands | Where-Object {
                    $_.Name -like $pattern -or $_.Description -like $pattern -or $_.Key -like $pattern -or $_.Category -like $pattern
                })
            }

            # Prioritize context-relevant commands
            if (-not [string]::IsNullOrEmpty($this._context)) {
                $contextCmds = @($this._filtered | Where-Object { $_.Category -eq $this._context -or $_.Category -eq "Global" })
                $otherCmds = @($this._filtered | Where-Object { $_.Category -ne $this._context -and $_.Category -ne "Global" })
                $this._filtered = $contextCmds + $otherCmds
            }

            # Clamp selection
            $this._selectedIndex = [Math]::Max(0, [Math]::Min($this._selectedIndex, $this._filtered.Count - 1))
            $this._scrollOffset = 0
        } catch {
            [Logger]::Error("CommandPalette._ApplyFilter failed", $_)
        }
    }

    [void] Render([HybridRenderEngine]$engine) {
        if (-not $this._visible) { return }

        try {
            $w = 70
            $h = 20
            $x = [Math]::Max(0, [int](($engine.Width - $w) / 2))
            $y = [Math]::Max(0, [int](($engine.Height - $h) / 2))

            $engine.BeginLayer(200)

            # Fill and draw box
            $engine.Fill($x, $y, $w, $h, ' ', [Colors]::Foreground, [Colors]::PanelBg)
            $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
            $engine.WriteAt($x + 2, $y, " Command Palette ", [Colors]::Header, [Colors]::PanelBg)

            # Filter input
            $filterY = $y + 2
            $engine.WriteAt($x + 2, $filterY, ">", [Colors]::Header, [Colors]::PanelBg)
            $filterDisplay = $this._filter
            if ($filterDisplay.Length -gt $w - 8) { $filterDisplay = $filterDisplay.Substring(0, $w - 8) }
            $engine.WriteAt($x + 4, $filterY, $filterDisplay.PadRight($w - 8), [Colors]::Foreground, [Colors]::PanelBg)
            $cursorX = $x + 4 + $filterDisplay.Length
            $engine.WriteAt($cursorX, $filterY, "_", [Colors]::Header, [Colors]::PanelBg)

            # Separator
            $engine.WriteAt($x + 1, $filterY + 1, ("─" * ($w - 2)), [Colors]::PanelBorder, [Colors]::PanelBg)

            # Results
            $listY = $filterY + 2
            $listH = $h - 6

            $count = $this._filtered.Count
            if ($count -eq 0) {
                $engine.WriteAt($x + 4, $listY, "No commands match filter", [Colors]::Muted, [Colors]::PanelBg)
            } else {
                # Scroll adjustment with clamping
                $this._scrollOffset = [Math]::Max(0, [Math]::Min($this._scrollOffset, [Math]::Max(0, $count - $listH)))
                if ($this._selectedIndex -lt $this._scrollOffset) {
                    $this._scrollOffset = $this._selectedIndex
                }
                if ($this._selectedIndex -ge $this._scrollOffset + $listH) {
                    $this._scrollOffset = $this._selectedIndex - $listH + 1
                }

                for ($i = 0; $i -lt $listH; $i++) {
                    $idx = $i + $this._scrollOffset
                    if ($idx -ge $count) { break }

                    $cmd = $this._filtered[$idx]
                    $isSelected = ($idx -eq $this._selectedIndex)

                    $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
                    $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::PanelBg }

                    # Clear row
                    $engine.Fill($x + 2, $listY + $i, $w - 4, 1, " ", $fg, $bg)

                    # Key
                    $keyStr = "[$($cmd.Key)]".PadRight(12)
                    $engine.WriteAt($x + 2, $listY + $i, $keyStr, [Colors]::Header, $bg)

                    # Name
                    $nameStr = $cmd.Name
                    if ($nameStr.Length -gt 18) { $nameStr = $nameStr.Substring(0, 15) + "..." }
                    $engine.WriteAt($x + 14, $listY + $i, $nameStr.PadRight(18), $fg, $bg)

                    # Description
                    $descWidth = $w - 36
                    $descStr = $cmd.Description
                    if ($descStr.Length -gt $descWidth) { $descStr = $descStr.Substring(0, $descWidth - 3) + "..." }
                    $engine.WriteAt($x + 33, $listY + $i, $descStr, [Colors]::Muted, $bg)
                }
            }

            # Footer
            $footerY = $y + $h - 2
            $engine.WriteAt($x + 2, $footerY, "Type to filter  Up/Down Navigate  Esc Close", [Colors]::Muted, [Colors]::PanelBg)

            $engine.EndLayer()
        } catch {
            [Logger]::Error("CommandPalette.Render failed", $_)
        }
    }

    [hashtable] HandleInput([ConsoleKeyInfo]$key) {
        if (-not $this._visible) { return @{ Action = "None" } }

        try {
            switch ($key.Key) {
                'Escape' {
                    [Logger]::Log("CommandPalette: Escape - closing", 2)
                    $this._visible = $false
                    return @{ Action = "Close" }
                }
                'Enter' {
                    if ($this._filtered.Count -gt 0 -and $this._selectedIndex -ge 0 -and $this._selectedIndex -lt $this._filtered.Count) {
                        $cmd = $this._filtered[$this._selectedIndex]
                        [Logger]::Log("CommandPalette: Execute $($cmd.Name)", 2)
                        $this._visible = $false
                        return @{ Action = "Execute"; Command = $cmd }
                    }
                    return @{ Action = "None" }
                }
                'UpArrow' {
                    if ($this._selectedIndex -gt 0) {
                        $this._selectedIndex--
                    }
                    return @{ Action = "None" }
                }
                'DownArrow' {
                    $maxIdx = $this._filtered.Count - 1
                    if ($maxIdx -ge 0 -and $this._selectedIndex -lt $maxIdx) {
                        $this._selectedIndex++
                    }
                    return @{ Action = "None" }
                }
                'Backspace' {
                    if ($this._filter.Length -gt 0) {
                        $this._filter = $this._filter.Substring(0, $this._filter.Length - 1)
                        $this._ApplyFilter()
                    }
                    return @{ Action = "None" }
                }
                Default {
                    if (-not [char]::IsControl($key.KeyChar)) {
                        $this._filter += $key.KeyChar
                        $this._ApplyFilter()
                    }
                    return @{ Action = "None" }
                }
            }
        } catch {
            [Logger]::Error("CommandPalette.HandleInput failed", $_)
        }
        return @{ Action = "None" }
    }
}
