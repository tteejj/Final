using namespace System.Collections.Generic
using namespace System.Text

# StartScreen - Dashboard with productivity metrics
# Shows hours logged, tasks due today, overdue, and no-date counts
# Default home screen for the TUI

Set-StrictMode -Version Latest

class StartScreen : PmcScreen {
    hidden [int]$_contentY = 4
    hidden [int]$_contentHeight = 20
    hidden [object]$_store = $null

    # Dashboard Data
    [array]$UrgentTasks = @()
    [int]$OverdueCount = 0
    [int]$DueTodayCount = 0
    [int]$SelectionIndex = 0
    [int]$ListScrollOffset = 0
    
    # Hours metrics
    [decimal]$HoursToday = 0
    [decimal]$HoursWeek = 0
    [decimal]$HoursMonth = 0

    StartScreen() : base("Start", "Dashboard") {
        $this.Header.SetBreadcrumb(@("Home"))
        $this._InitFooter()
        $this._SetupMenus()
    }

    StartScreen([object]$container) : base("Start", "Dashboard", $container) {
        $this.Header.SetBreadcrumb(@("Home"))
        $this._InitFooter()
        $this._SetupMenus()
    }

    # Setup menu items using MenuRegistry (same as TaskListScreen)
    hidden [void] _SetupMenus() {
        # Get singleton MenuRegistry instance
        . "$PSScriptRoot/../services/MenuRegistry.ps1"
        $registry = [MenuRegistry]::GetInstance()

        # Load menu items from manifest (only if not already loaded)
        $tasksMenuItems = $registry.GetMenuItems('Tasks')
        if (-not $tasksMenuItems -or @($tasksMenuItems).Count -eq 0) {
            $manifestPath = Join-Path $PSScriptRoot "MenuItems.psd1"

            # Get or create the service container
            if (-not $global:PmcContainer) {
                . "$PSScriptRoot/../ServiceContainer.ps1"
                $global:PmcContainer = [ServiceContainer]::new()
            }

            # Load manifest with container
            $registry.LoadFromManifest($manifestPath, $global:PmcContainer)
        }

        # Build menus from registry
        $this._PopulateMenusFromRegistry($registry)

        # Store populated MenuBar globally for other screens to use
        $global:PmcSharedMenuBar = $this.MenuBar
    }

    # Populate MenuBar from registry
    hidden [void] _PopulateMenusFromRegistry([object]$registry) {
        $menuMapping = @{
            'Tasks'    = 0
            'Projects' = 1
            'Time'     = 2
            'Tools'    = 3
            'Options'  = 4
            'Help'     = 5
        }

        foreach ($menuName in $menuMapping.Keys) {
            $menuIndex = $menuMapping[$menuName]

            if ($null -eq $this.MenuBar -or $null -eq $this.MenuBar.Menus) {
                continue
            }

            if ($menuIndex -lt 0 -or $menuIndex -ge $this.MenuBar.Menus.Count) {
                continue
            }

            $menu = $this.MenuBar.Menus[$menuIndex]
            $items = $registry.GetMenuItems($menuName)

            if ($null -ne $items) {
                # Clear existing items to prevent duplication
                $menu.Items.Clear()

                foreach ($item in $items) {
                    if ($item -isnot [hashtable]) {
                        continue
                    }
                    $menuItem = New-Object -TypeName PmcMenuItem -ArgumentList $item['Label'], $item['Hotkey'], $item['Action']
                    $menu.Items.Add($menuItem)
                }
            }
        }
    }

    hidden [void] _InitFooter() {
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Q", "Quit")
    }

    [void] Initialize([object]$renderEngine, [object]$container) {
        $this.RenderEngine = $renderEngine
        $this.Container = $container
        $this.TermWidth = $renderEngine.Width
        $this.TermHeight = $renderEngine.Height

        if (-not $this.LayoutManager) {
            $this.LayoutManager = [PmcLayoutManager]::new()
        }

        $headerRect = $this.LayoutManager.GetRegion('Header', $this.TermWidth, $this.TermHeight)
        $this.Header.X = $headerRect.X
        $this.Header.Y = $headerRect.Y
        $this.Header.Width = $headerRect.Width
        $this.Header.Height = $headerRect.Height

        $footerRect = $this.LayoutManager.GetRegion('Footer', $this.TermWidth, $this.TermHeight)
        $this.Footer.X = $footerRect.X
        $this.Footer.Y = $footerRect.Y
        $this.Footer.Width = $footerRect.Width

        $statusBarRect = $this.LayoutManager.GetRegion('StatusBar', $this.TermWidth, $this.TermHeight)
        $this.StatusBar.X = $statusBarRect.X
        $this.StatusBar.Y = $statusBarRect.Y
        $this.StatusBar.Width = $statusBarRect.Width

        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)
        $this._contentY = $contentRect.Y
        $this._contentHeight = $contentRect.Height
    }

    [void] LoadData() {
        $this.ShowStatus("Loading dashboard...")
        
        try {
            $this._store = [TaskStore]::GetInstance()
            if (-not $this._store.IsLoaded) {
                $this._store.LoadData()
            }
            $this._LoadUrgentTasks()
            $this._LoadHoursData()
            $this.ShowStatus("Dashboard ready")
        }
        catch {
            $this.ShowError("Failed to load data: $_")
        }
    }

    hidden [void] _LoadUrgentTasks() {
        $today = [datetime]::Today
        $tasks = @()
        if ($this._store -and $this._store._data.tasks) {
            $tasks = @($this._store._data.tasks)
        }
        
        $urgent = @()
        $tmpOverdue = 0
        $tmpDueToday = 0
        
        foreach ($task in $tasks) {
            $completed = Get-SafeProperty $task 'completed'
            if ($completed) { continue }

            $dueDate = $null
            $due = Get-SafeProperty $task 'due'

            if ($due -is [datetime]) {
                $dueDate = $due.Date
            } elseif ($due -is [string] -and -not [string]::IsNullOrEmpty($due)) {
                try { $dueDate = [datetime]::Parse($due).Date } catch { }
            }

            if ($dueDate) {
                if ($dueDate -lt $today) {
                    $tmpOverdue++
                    $task['status_display'] = "[!]"
                    $urgent += $task
                } elseif ($dueDate -eq $today) {
                    $tmpDueToday++
                    $task['status_display'] = "[T]"
                    $urgent += $task
                }
            }
        }
        
        # Sort by due date
        $this.UrgentTasks = $urgent | Sort-Object {
            $d = Get-SafeProperty $_ 'due'
            if ($d -is [datetime]) { $d } else { [datetime]::Parse($d) }
        }
        $this.OverdueCount = $tmpOverdue
        $this.DueTodayCount = $tmpDueToday
    }
    
    # Load hours logged (today, this week, this month)
    hidden [void] _LoadHoursData() {
        $today = [datetime]::Today
        $weekStart = $today.AddDays(-[int]$today.DayOfWeek)
        $monthStart = [datetime]::new($today.Year, $today.Month, 1)
        
        $todayMinutes = 0
        $weekMinutes = 0
        $monthMinutes = 0
        
        if ($this._store -and $this._store._data.timelogs) {
            foreach ($log in $this._store._data.timelogs) {
                $logDate = $null
                $dateVal = Get-SafeProperty $log 'date'
                $minutes = Get-SafeProperty $log 'minutes'
                
                if ($null -eq $minutes) {
                    # Try hours instead
                    $hours = Get-SafeProperty $log 'hours'
                    if ($null -ne $hours) {
                        $minutes = [decimal]$hours * 60
                    } else {
                        continue
                    }
                }
                
                if ($dateVal -is [datetime]) {
                    $logDate = $dateVal.Date
                } elseif ($dateVal -is [string] -and -not [string]::IsNullOrEmpty($dateVal)) {
                    try { $logDate = [datetime]::Parse($dateVal).Date } catch { continue }
                } else {
                    continue
                }
                
                if ($logDate -eq $today) {
                    $todayMinutes += $minutes
                }
                if ($logDate -ge $weekStart) {
                    $weekMinutes += $minutes
                }
                if ($logDate -ge $monthStart) {
                    $monthMinutes += $minutes
                }
            }
        }
        
        $this.HoursToday = [Math]::Round($todayMinutes / 60, 1)
        $this.HoursWeek = [Math]::Round($weekMinutes / 60, 1)
        $this.HoursMonth = [Math]::Round($monthMinutes / 60, 1)
    }

    # === RENDERING ===
    [void] RenderContentToEngine([object]$engine) {
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.Title')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        $borderFg = $this.Header.GetThemedColorInt('Border.Widget')
        $successColor = $this.Header.GetThemedColorInt('Foreground.Success')

        $y = $this._contentY
        
        # === HOURS LOGGED ROW (text display at top) ===
        $hoursText = "Hours Logged:  Today: $($this.HoursToday)h  |  Week: $($this.HoursWeek)h  |  Month: $($this.HoursMonth)h"
        $engine.WriteAt(2, $y, $hoursText, $successColor, $bg)
        $y += 2
        
        # Layout: 2 columns below hours
        # Left: Task List (60%)
        # Right: Calendar (40%)

        $leftWidth = [int][Math]::Floor($this.TermWidth * 0.6)
        $rightWidth = $this.TermWidth - $leftWidth

        $h = $this._contentHeight - 2  # Account for hours row

        # Draw vertical separator
        for ($i = 0; $i -lt $h; $i++) {
            $engine.WriteAt($leftWidth, $y + $i, "|", $borderFg, $bg)
        }

        # === Left Column: Urgent Tasks ===
        $leftX = 2
        $engine.WriteAt($leftX, $y, "Urgent Tasks ($($this.UrgentTasks.Count))", $headerColor, $bg)
        $engine.WriteAt($leftX + 20, $y, " [!] Overdue: $($this.OverdueCount) | [T] Today: $($this.DueTodayCount)", $mutedColor, $bg)

        $listY = $y + 2
        $listH = $h - 2

        if ($this.UrgentTasks.Count -eq 0) {
            $engine.WriteAt($leftX, $listY, "No urgent tasks.", $mutedColor, $bg)
        } else {
            $displayCount = [Math]::Min($this.UrgentTasks.Count, $listH)
            
            for ($i = 0; $i -lt $displayCount; $i++) {
                $task = $this.UrgentTasks[$i]
                $status = $task.status_display
                $text = Get-SafeProperty $task 'text'

                # Truncate text if needed
                $maxLen = $leftWidth - 10
                if ($text.Length -gt $maxLen) {
                    $text = $text.Substring(0, $maxLen) + "..."
                }

                $color = $textColor
                if ($status -eq "[!]") { $color = $this.Header.GetThemedColorInt('Foreground.Error') }
                if ($status -eq "[T]") { $color = $this.Header.GetThemedColorInt('Foreground.Warning') }

                $line = "$status $text"
                $engine.WriteAt($leftX, $listY + $i, $line, $color, $bg)
            }
        }

        # === Right Column: Calendar ===
        $rightX = $leftWidth + 2
        $engine.WriteAt($rightX, $y, "Calendar: " + [datetime]::Today.ToString("MMMM yyyy"), $headerColor, $bg)

        # Render mini calendar (adapted from CalendarScreen logic)
        $this._RenderCalendar($engine, $rightX, $y + 2)
    }

    hidden [void] _RenderCalendar([object]$engine, [int]$x, [int]$y) {
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $todayBg = $this.Header.GetThemedColorInt('Foreground.Success')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        $currentDate = [datetime]::Today

        # Day headers
        $engine.WriteAt($x, $y, "Su Mo Tu We Th Fr Sa", $mutedColor, $bg)

        # Days
        $firstOfMonth = [datetime]::new($currentDate.Year, $currentDate.Month, 1)
        $daysInMonth = [datetime]::DaysInMonth($currentDate.Year, $currentDate.Month)
        $startDayOfWeek = [int]$firstOfMonth.DayOfWeek

        $dayX = $x + ($startDayOfWeek * 3)
        $dayY = $y + 1

        for ($day = 1; $day -le $daysInMonth; $day++) {
            $date = [datetime]::new($currentDate.Year, $currentDate.Month, $day)
            $isToday = ($date.Date -eq $currentDate.Date)
            
            $dayStr = $day.ToString().PadLeft(2)
            $color = $textColor
            $bgColor = $bg

            if ($isToday) {
                $color = $bg
                $bgColor = $todayBg
            }

            $engine.WriteAt($dayX, $dayY, $dayStr, $color, $bgColor)

            $dayX += 3
            if ($date.DayOfWeek -eq [DayOfWeek]::Saturday) {
                $dayX = $x
                $dayY++
            }
        }
    }

    [string] RenderContent() { return "" }

    # === KEY HANDLING ===
    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $handled = ([PmcScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        $keyChar = [char]::ToLower($keyInfo.KeyChar)

        switch ($keyInfo.Key) {
            'Escape' {
                if ($global:PmcApp) { $global:PmcApp.RequestExit() }
                return $true
            }
        }

        switch ($keyChar) {
            'q' {
                if ($global:PmcApp) { $global:PmcApp.Stop() }
                return $true
            }
            'r' {
                $this.LoadData()
                return $true
            }
        }

        return $false
    }

    hidden [void] _NavigateToTimeList([string]$filter) {
        try {
            $screenPath = "$PSScriptRoot/TimeListScreen.ps1"
            if (Test-Path $screenPath) {
                . $screenPath
                # Pass container for proper menu bar initialization
                $screen = New-Object TimeListScreen -ArgumentList $global:PmcContainer
                # TODO: Set filter on TimeListScreen if it supports it
                $global:PmcApp.PushScreen($screen)
            } else {
                $this.ShowError("TimeListScreen not found")
            }
        }
        catch {
            $this.ShowError("Failed to open Time List: $_")
        }
    }

    hidden [void] _NavigateToTaskList([string]$filter) {
        try {
            # Use container resolution for TaskListScreen
            if ($global:PmcContainer) {
                $screen = $global:PmcContainer.Resolve('TaskListScreen')
                # TODO: Set filter on TaskListScreen if it supports it
                $global:PmcApp.PushScreen($screen)
            } else {
                $this.ShowError("Container not available")
            }
        }
        catch {
            $this.ShowError("Failed to open Task List: $_")
        }
    }
}

function Show-StartScreen {
    param([object]$App)
    if (-not $App) { throw "PmcApplication required" }
    $screen = New-Object StartScreen
    $App.PushScreen($screen)
}
