# OverviewModal.ps1 - Dashboard overview stats
# Shows hours logged, task counts, and daily/weekly progress

class OverviewModal {
    hidden [bool]$_visible = $false
    hidden [FluxStore]$_store
    
    OverviewModal([FluxStore]$store) {
        $this._store = $store
    }
    
    [void] Open() {
        $this._visible = $true
    }
    
    [void] Close() {
        $this._visible = $false
    }
    
    [bool] IsVisible() {
        return $this._visible
    }
    
    [void] Render([HybridRenderEngine]$engine) {
        if (-not $this._visible) { return }
        
        $engine.BeginLayer(110)
        
        $w = $engine.Width - 10
        $h = $engine.Height - 6
        $x = 5
        $y = 3
        
        # Background
        $engine.Fill($x, $y, $w, $h, " ", [Colors]::Foreground, [Colors]::Background)
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::Background)
        
        # Title
        $engine.WriteAt($x + 2, $y, " Overview ", [Colors]::White, [Colors]::Accent)
        
        $state = $this._store.GetState()
        
        # Calculate stats
        $today = [DateTime]::Today
        $startOfWeek = $today.AddDays(-[int]$today.DayOfWeek + 1)
        if ($today.DayOfWeek -eq [DayOfWeek]::Sunday) { $startOfWeek = $startOfWeek.AddDays(-7) }
        
        $todayHours = 0.0
        $weekHours = 0.0
        
        if ($state.Data.ContainsKey('timelogs') -and $state.Data.timelogs) {
            foreach ($log in $state.Data.timelogs) {
                if (-not $log['date']) { continue }
                try {
                    $logDate = [DateTime]::Parse($log['date'])
                    if ($logDate.Date -eq $today) {
                        $todayHours += [double]$log['hours']
                    }
                    if ($logDate -ge $startOfWeek -and $logDate -lt $startOfWeek.AddDays(7)) {
                        $weekHours += [double]$log['hours']
                    }
                } catch {}
            }
        }
        
        # Tasks stats
        $tasksToday = @()
        $unassignedTasks = @()
        $completedToday = 0
        
        if ($state.Data.ContainsKey('tasks') -and $state.Data.tasks) {
            foreach ($task in $state.Data.tasks) {
                $isUnassigned = -not $task['projectId'] -or [string]::IsNullOrWhiteSpace($task['projectId'])
                if ($isUnassigned) {
                    $unassignedTasks += $task
                }
                
                # Check if due today or has activity today
                if ($task['dueDate']) {
                    try {
                        $dueDate = [DateTime]::Parse($task['dueDate'])
                        if ($dueDate.Date -eq $today) {
                            $tasksToday += $task
                        }
                    } catch {}
                }
                
                if ($task['status'] -eq 'done' -and $task['modified']) {
                    try {
                        $modDate = [DateTime]::Parse($task['modified'])
                        if ($modDate.Date -eq $today) {
                            $completedToday++
                        }
                    } catch {}
                }
            }
        }
        
        # === Render Stats ===
        $contentY = $y + 2
        $halfW = [int](($w - 4) / 2)
        
        # Today Box
        $this._RenderBox($engine, $x + 2, $contentY, $halfW, 5, "Today")
        $todayPct = [Math]::Min(100, ($todayHours / 7.5) * 100)
        $engine.WriteAt($x + 4, $contentY + 2, ("Hours: {0:N1} / 7.5  ({1:N0}%)" -f $todayHours, $todayPct), [Colors]::Foreground, [Colors]::Background)
        $barW = $halfW - 6
        $filledW = [int](($todayPct / 100) * $barW)
        $bar = ("█" * $filledW) + ("░" * ($barW - $filledW))
        $barColor = if ($todayPct -ge 100) { [Colors]::Success } elseif ($todayPct -ge 50) { [Colors]::Warning } else { [Colors]::Error }
        $engine.WriteAt($x + 4, $contentY + 3, $bar, $barColor, [Colors]::Background)
        
        # Week Box
        $this._RenderBox($engine, $x + 2 + $halfW + 1, $contentY, $halfW, 5, "This Week")
        $weekPct = [Math]::Min(100, ($weekHours / 37.5) * 100)
        $engine.WriteAt($x + 4 + $halfW + 1, $contentY + 2, ("Hours: {0:N1} / 37.5  ({1:N0}%)" -f $weekHours, $weekPct), [Colors]::Foreground, [Colors]::Background)
        $filledW = [int](($weekPct / 100) * $barW)
        $bar = ("█" * $filledW) + ("░" * ($barW - $filledW))
        $barColor = if ($weekPct -ge 100) { [Colors]::Success } elseif ($weekPct -ge 50) { [Colors]::Warning } else { [Colors]::Error }
        $engine.WriteAt($x + 4 + $halfW + 1, $contentY + 3, $bar, $barColor, [Colors]::Background)
        
        # Today's Tasks
        $tasksY = $contentY + 6
        $this._RenderBox($engine, $x + 2, $tasksY, $w - 4, 6, "Today's Tasks ($($tasksToday.Count))")
        
        if ($tasksToday.Count -eq 0) {
            $engine.WriteAt($x + 4, $tasksY + 2, "(No tasks due today)", [Colors]::Muted, [Colors]::Background)
        } else {
            for ($i = 0; $i -lt [Math]::Min(4, $tasksToday.Count); $i++) {
                $task = $tasksToday[$i]
                $icon = if ($task['status'] -eq 'done') { "✓" } else { "○" }
                $name = if ($task['name']) { $task['name'] } else { "(Untitled)" }
                if ($name.Length -gt $w - 12) { $name = $name.Substring(0, $w - 15) + "..." }
                $fg = if ($task['status'] -eq 'done') { [Colors]::Muted } else { [Colors]::Foreground }
                $engine.WriteAt($x + 4, $tasksY + 2 + $i, "$icon $name", $fg, [Colors]::Background)
            }
        }
        
        # Unassigned Tasks
        $unassignedY = $tasksY + 7
        $this._RenderBox($engine, $x + 2, $unassignedY, $w - 4, 5, "Unassigned Tasks ($($unassignedTasks.Count))")
        
        if ($unassignedTasks.Count -eq 0) {
            $engine.WriteAt($x + 4, $unassignedY + 2, "(No unassigned tasks)", [Colors]::Muted, [Colors]::Background)
        } else {
            for ($i = 0; $i -lt [Math]::Min(3, $unassignedTasks.Count); $i++) {
                $task = $unassignedTasks[$i]
                $name = if ($task['name']) { $task['name'] } else { "(Untitled)" }
                if ($name.Length -gt $w - 12) { $name = $name.Substring(0, $w - 15) + "..." }
                $engine.WriteAt($x + 4, $unassignedY + 2 + $i, "• $name", [Colors]::Warning, [Colors]::Background)
            }
        }
        
        # Status bar
        $statusY = $y + $h - 2
        $engine.Fill($x, $statusY, $w, 1, " ", [Colors]::Foreground, [Colors]::SelectionBg)
        $engine.WriteAt($x, $statusY, " [Esc] Close  [R] Refresh", [Colors]::White, [Colors]::SelectionBg)
        
        $engine.EndLayer()
    }
    
    hidden [void] _RenderBox([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$w, [int]$h, [string]$title) {
        # Simple box with title
        $engine.WriteAt($x, $y, "┌" + ("─" * ($w - 2)) + "┐", [Colors]::PanelBorder, [Colors]::Background)
        for ($i = 1; $i -lt $h - 1; $i++) {
            $engine.WriteAt($x, $y + $i, "│", [Colors]::PanelBorder, [Colors]::Background)
            $engine.WriteAt($x + $w - 1, $y + $i, "│", [Colors]::PanelBorder, [Colors]::Background)
        }
        $engine.WriteAt($x, $y + $h - 1, "└" + ("─" * ($w - 2)) + "┘", [Colors]::PanelBorder, [Colors]::Background)
        
        # Title
        $engine.WriteAt($x + 2, $y, " $title ", [Colors]::Accent, [Colors]::Background)
    }
    
    [string] HandleInput([ConsoleKeyInfo]$key) {
        if (-not $this._visible) { return "Continue" }
        
        switch ($key.Key) {
            'Escape' {
                $this.Close()
                return "Close"
            }
            'R' {
                # Refresh (just re-render)
                return "Continue"
            }
        }
        return "Continue"
    }
}
