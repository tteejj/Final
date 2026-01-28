# KanbanBoard.ps1 - Kanban-style board view for tasks
using namespace System.Collections.Generic

# Required dependencies - must load in correct order:
# 1. Logger.ps1
# 2. ThemeService.ps1
# 3. Enums.ps1
# 4. PerformanceCore.ps1
# 5. CellBuffer.ps1
# 6. RenderCache.ps1
# 7. HybridRenderEngine.Dependencies.ps1
# 8. HybridRenderEngine.ps1
# 9. DataService.ps1
# 10. FluxStore.ps1

class KanbanBoard {
    hidden [string[]]$_columns = @("TODO", "IN PROGRESS", "DONE")
    hidden [hashtable]$_scrollOffsets = @{ "TODO" = 0; "IN PROGRESS" = 0; "DONE" = 0 }
    hidden [hashtable]$_selectedIndices = @{ "TODO" = -1; "IN PROGRESS" = -1; "DONE" = -1 }
    hidden [int]$_focusedColumn = 0

    # Optimization: Cache column task lists
    hidden [object]$_cache = @{ Version = -1; Columns = @{} }

    [void] MoveFocus([string]$direction) {
        if ($direction -eq "Right") {
            $this._focusedColumn = [Math]::Min($this._columns.Count - 1, $this._focusedColumn + 1)
        } elseif ($direction -eq "Left") {
            $this._focusedColumn = [Math]::Max(0, $this._focusedColumn - 1)
        }
    }

    [void] MoveSelection([string]$direction, [hashtable]$state) {
        $colName = $this._columns[$this._focusedColumn]
        $tasks = $this._GetTasksForColumn($state, $colName)
        $maxIdx = $tasks.Count - 1

        if ($direction -eq "Up") {
            if ($this._selectedIndices[$colName] -gt 0) {
                $this._selectedIndices[$colName]--
            }
        } elseif ($direction -eq "Down") {
            if ($this._selectedIndices[$colName] -lt $maxIdx) {
                $this._selectedIndices[$colName]++
            }
        }

        # Ensure selection is valid (handle empty lists or bounds)
        if ($tasks.Count -eq 0) {
             $this._selectedIndices[$colName] = -1
        }
    }

    [void] MoveTask([string]$direction, [FluxStore]$store, [hashtable]$state) {
        $colName = $this._columns[$this._focusedColumn]
        $idx = $this._selectedIndices[$colName]
        $tasks = $this._GetTasksForColumn($state, $colName)

        if ($idx -ge 0 -and $idx -lt $tasks.Count) {
            $task = $tasks[$idx]
            $currentStatus = if ($task.ContainsKey('status')) { $task.status } else { "todo" }
            $newStatus = if ($direction -eq "Right") {
                switch ($colName) {
                    "TODO" { "in-progress" }
                    "IN PROGRESS" { "done" }
                    "DONE" { "done" }
                }
            } else {
                switch ($colName) {
                    "IN PROGRESS" { "todo" }
                    "DONE" { "in-progress" }
                    "TODO" { "todo" }
                }
            }

            if ($newStatus -ne $currentStatus) {
                # Fix: Explicitly handle 'completed' flag for consistency
                $completed = ($newStatus -eq "done")

                $store.Dispatch([ActionType]::UPDATE_ITEM, @{
                    Type = "tasks"
                    Id = $task.id
                    Changes = @{
                        status = $newStatus
                        completed = $completed
                    }
                })

                # Selection logic: Try to keep selection index or clamp
                # (The list size will shrink by 1, so the current index might point to the next item, which is desired)
            }
        }
    }

    [hashtable] GetSelectedTask([hashtable]$state) {
        $colName = $this._columns[$this._focusedColumn]
        $idx = $this._selectedIndices[$colName]
        $tasks = $this._GetTasksForColumn($state, $colName)

        if ($idx -ge 0 -and $idx -lt $tasks.Count) {
            return $tasks[$idx]
        }
        return $null
    }

    hidden [array] _GetTasksForColumn([hashtable]$state, [string]$column) {
        # Optimization: Use cache if version matches
        if ($state.Version -ne $this._cache.Version) {
            $this._cache.Version = $state.Version
            $this._cache.Columns = @{}
        }
        if ($this._cache.Columns.ContainsKey($column)) {
            return $this._cache.Columns[$column]
        }

        $statusMap = @{
            "TODO" = @("todo", "pending", "")
            "IN PROGRESS" = @("in-progress")
            "DONE" = @("done", "completed") # Added 'completed' for safety
        }

        if ($state.Data.tasks) {
            $targetStatuses = $statusMap[$column]

            # Simple Filter
            $tasks = @($state.Data.tasks | Where-Object {
                $taskStatus = if ($_.ContainsKey('status')) { $_.status } else { "" }
                $taskStatus -in $targetStatuses
            })

            # Cache result
            $this._cache.Columns[$column] = $tasks
            return $tasks
        }
        return @()
    }

    [void] Render([HybridRenderEngine]$engine, [hashtable]$state) {
        $w = $engine.Width
        $h = $engine.Height - 2
        $colW = [int](($w - 4) / $this._columns.Count)
        $colGap = 1

        $engine.Fill(0, 0, $w, 2, " ", [Colors]::Background, [Colors]::Background)
        $engine.WriteAt(0, 0, " Kanban Board ", [Colors]::Accent, [Colors]::Background)
        $engine.WriteAt($w - 45, 0, " Q:Quit D:Dash ←→:Col Shift+←→:MoveTask ", [Colors]::Muted, [Colors]::Background)

        for ($i = 0; $i -lt $this._columns.Count; $i++) {
            $colName = $this._columns[$i]
            $x = 2 + $i * ($colW + $colGap)
            $colH = $h - 1
            $listH = $colH - 2 # Height available for list items

            $isFocused = ($i -eq $this._focusedColumn)
            # Enhanced Visuals: Double border for focused
            $borderStyle = if ($isFocused) { "Double" } else { "Single" }
            $borderColor = if ($isFocused) { [Colors]::Accent } else { [Colors]::PanelBorder }
            $headerBg = if ($isFocused) { [Colors]::SelectionBg } else { [Colors]::PanelBg }
            $headerFg = if ($isFocused) { [Colors]::SelectionFg } else { [Colors]::Foreground }

             # Draw Box manually or use engine helper if supports style. Assuming simple box for now but with color.
            $engine.DrawBox($x, 1, $colW, $colH, $borderColor, [Colors]::PanelBg)

            $tasks = $this._GetTasksForColumn($state, $colName)
            $countStr = "($($tasks.Count))"
            $headerText = " [$i] $colName $countStr "
            # Center header if possible, or left align
            $engine.WriteAt($x + 2, 1, $headerText, $headerFg, $headerBg)

            # --- AUTO SCROLLING LOGIC ---
            $selectedIdx = $this._selectedIndices[$colName]
            # Initialize selection if -1 and items exist
            if ($selectedIdx -eq -1 -and $tasks.Count -gt 0) {
                 $selectedIdx = 0
                 $this._selectedIndices[$colName] = 0
            }

            # Clamp selection
            if ($selectedIdx -ge $tasks.Count) {
                $selectedIdx = $tasks.Count - 1
                $this._selectedIndices[$colName] = $selectedIdx
            }

            # Calculate Scroll Offset
            if ($selectedIdx -lt $this._scrollOffsets[$colName]) {
                $this._scrollOffsets[$colName] = $selectedIdx
            } elseif ($selectedIdx -ge ($this._scrollOffsets[$colName] + $listH)) {
                $this._scrollOffsets[$colName] = $selectedIdx - $listH + 1
            }

            # Ensure scroll offset is valid (don't scroll past end if not needed)
            if ($this._scrollOffsets[$colName] -gt ($tasks.Count - $listH) -and $tasks.Count -gt $listH) {
                 $this._scrollOffsets[$colName] = $tasks.Count - $listH
            }
            if ($this._scrollOffsets[$colName] -lt 0) { $this._scrollOffsets[$colName] = 0 }

            $scrollIdx = $this._scrollOffsets[$colName]
            # ----------------------------

            if ($tasks.Count -eq 0) {
                $engine.WriteAt($x + 2, 3, "(No tasks)", [Colors]::Muted, [Colors]::PanelBg)
            }

            for ($j = 0; $j -lt $listH; $j++) {
                $taskIdx = $scrollIdx + $j
                $y = 3 + $j # Start at Y=3 (Border=1, Header=2)

                if ($taskIdx -lt $tasks.Count) {
                    $task = $tasks[$taskIdx]

                    # --- MINI CARD RENDER ---
                    $isSelected = ($taskIdx -eq $selectedIdx)

                    # Colors
                    $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
                    $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::PanelBg }
                    if ($isSelected -eq $false -and $i -eq 2) { $fg = [Colors]::Muted } # Dim completed tasks

                    # Priority Indicator - SAFE ACCESS
                    $prio = if ($task.ContainsKey('priority')) { $task.priority } else { 0 }
                    $prioStr = switch ($prio) { 1 { "!" } 2 { "!!" } 3 { "!!!" } Default { "" } }
                    $prioColor = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Error }

                    # Truncate Text - SAFE ACCESS
                    $maxTextLen = $colW - 4 - $prioStr.Length
                    $text = if ($task.ContainsKey('text')) { $task.text } else { "(no text)" }
                    if ($text.Length -gt $maxTextLen) { $text = $text.Substring(0, $maxTextLen - 2) + ".." }

                    # Draw Line
                    $engine.Fill($x + 1, $y, $colW - 2, 1, " ", $fg, $bg)

                    $currentX = $x + 2
                    if ($prioStr) {
                         $engine.WriteAt($currentX, $y, $prioStr, $prioColor, $bg)
                         $currentX += $prioStr.Length + 1
                    }
                    $engine.WriteAt($currentX, $y, $text, $fg, $bg)

                    # Optional: Show 'Due' or 'Tag' if space permits on right?
                    # Keep it simple for now to avoid clutter on narrow columns
                }
            }
        }
    }
}
