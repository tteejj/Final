using namespace System.Collections.Generic
using namespace System.Text

# StartScreen - Dashboard with productivity metrics
# Shows hours logged, tasks due today, overdue, and no-date counts
# Default home screen for the TUI

Set-StrictMode -Version Latest

class StartScreen : PmcScreen {
    [int]$SelectedCard = 0
    [array]$Cards = @()
    hidden [int]$_contentY = 4
    hidden [int]$_contentHeight = 20
    hidden [object]$_store = $null

    StartScreen() : base("Start", "Dashboard") {
        $this.Header.SetBreadcrumb(@("Home"))
        $this._InitFooter()
        $this._InitCards()
    }

    StartScreen([object]$container) : base("Start", "Dashboard", $container) {
        $this.Header.SetBreadcrumb(@("Home"))
        $this._InitFooter()
        $this._InitCards()
    }

    hidden [void] _InitFooter() {
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Left/Right", "Select")
        $this.Footer.AddShortcut("Enter", "Open")
        $this.Footer.AddShortcut("Q", "Quit")
    }

    hidden [void] _InitCards() {
        $this.Cards = @(
            @{ Id = 'hoursToday'; Label = 'Hours Today'; Value = '0.0 / 7.5'; Icon = '⏱' }
            @{ Id = 'hoursWeek'; Label = 'Hours This Week'; Value = '0.0 / 37.5'; Icon = '📅' }
            @{ Id = 'dueToday'; Label = 'Tasks Due Today'; Value = '0'; Icon = '📋' }
            @{ Id = 'overdue'; Label = 'Overdue Tasks'; Value = '0'; Icon = '⚠' }
            @{ Id = 'noDate'; Label = 'No Due Date'; Value = '0'; Icon = '❓' }
        )
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
            $this._UpdateCardValues()
            $this.ShowStatus("Dashboard ready - Press Enter to open selected card")
        }
        catch {
            $this.ShowError("Failed to load data: $_")
        }
    }

    hidden [void] _UpdateCardValues() {
        $today = [datetime]::Today
        $weekStart = $today.AddDays(-[int]$today.DayOfWeek)
        
        # Get time logs
        $timelogs = @()
        if ($this._store -and $this._store._data.timelogs) {
            $timelogs = @($this._store._data.timelogs)
        }
        
        # Hours today
        $hoursToday = 0.0
        foreach ($log in $timelogs) {
            $logDate = $null
            if ($log.date -is [datetime]) {
                $logDate = $log.date.Date
            } elseif ($log.date -is [string] -and -not [string]::IsNullOrEmpty($log.date)) {
                try { $logDate = [datetime]::Parse($log.date).Date } catch { }
            }
            if ($logDate -eq $today) {
                $minutes = 0
                if ($log.minutes -is [int]) { $minutes = $log.minutes }
                elseif ($log.minutes) { try { $minutes = [int]$log.minutes } catch { } }
                $hoursToday += $minutes / 60.0
            }
        }
        $this.Cards[0].Value = "{0:F1} / 7.5" -f $hoursToday
        
        # Hours this week
        $hoursWeek = 0.0
        foreach ($log in $timelogs) {
            $logDate = $null
            if ($log.date -is [datetime]) {
                $logDate = $log.date.Date
            } elseif ($log.date -is [string] -and -not [string]::IsNullOrEmpty($log.date)) {
                try { $logDate = [datetime]::Parse($log.date).Date } catch { }
            }
            if ($logDate -ge $weekStart -and $logDate -le $today) {
                $minutes = 0
                if ($log.minutes -is [int]) { $minutes = $log.minutes }
                elseif ($log.minutes) { try { $minutes = [int]$log.minutes } catch { } }
                $hoursWeek += $minutes / 60.0
            }
        }
        $this.Cards[1].Value = "{0:F1} / 37.5" -f $hoursWeek
        
        # Get tasks
        $tasks = @()
        if ($this._store -and $this._store._data.tasks) {
            $tasks = @($this._store._data.tasks)
        }
        
        # Tasks due today
        $dueToday = 0
        foreach ($task in $tasks) {
            $dueDate = $null
            $due = Get-SafeProperty $task 'due'
            if ($due -is [datetime]) {
                $dueDate = $due.Date
            } elseif ($due -is [string] -and -not [string]::IsNullOrEmpty($due)) {
                try { $dueDate = [datetime]::Parse($due).Date } catch { }
            }
            $completed = Get-SafeProperty $task 'completed'
            if ($dueDate -eq $today -and -not $completed) {
                $dueToday++
            }
        }
        $this.Cards[2].Value = $dueToday.ToString()
        
        # Overdue tasks
        $overdue = 0
        foreach ($task in $tasks) {
            $dueDate = $null
            $due = Get-SafeProperty $task 'due'
            if ($due -is [datetime]) {
                $dueDate = $due.Date
            } elseif ($due -is [string] -and -not [string]::IsNullOrEmpty($due)) {
                try { $dueDate = [datetime]::Parse($due).Date } catch { }
            }
            $completed = Get-SafeProperty $task 'completed'
            if ($dueDate -and $dueDate -lt $today -and -not $completed) {
                $overdue++
            }
        }
        $this.Cards[3].Value = $overdue.ToString()
        
        # Tasks with no due date
        $noDate = 0
        foreach ($task in $tasks) {
            $due = Get-SafeProperty $task 'due'
            $completed = Get-SafeProperty $task 'completed'
            if ([string]::IsNullOrEmpty($due) -and -not $completed) {
                $noDate++
            }
        }
        $this.Cards[4].Value = $noDate.ToString()
    }

    # === RENDERING ===
    [void] RenderContentToEngine([object]$engine) {
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.Title')
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $successColor = $this.Header.GetThemedColorInt('Foreground.Success')
        $warningColor = $this.Header.GetThemedColorInt('Foreground.Warning')
        $errorColor = $this.Header.GetThemedColorInt('Foreground.Error')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        $y = $this._contentY
        $startX = $this.Header.X + 2

        # Welcome message
        $engine.WriteAt($startX, $y, "Welcome to PMC", $headerColor, $bg)
        $engine.WriteAt($startX + 15, $y, " - " + [datetime]::Today.ToString("dddd, MMMM d, yyyy"), $mutedColor, $bg)
        $y += 2

        # Calculate card dimensions
        $cardWidth = 18
        $cardHeight = 5
        $cardSpacing = 2
        $cardsPerRow = 5

        # Render cards
        for ($i = 0; $i -lt $this.Cards.Count; $i++) {
            $card = $this.Cards[$i]
            $isSelected = ($i -eq $this.SelectedCard)
            
            $cardX = $startX + ($i * ($cardWidth + $cardSpacing))
            $cardY = $y

            # Card colors
            $cardBg = $bg
            $cardFg = $textColor
            $valueFg = $headerColor
            
            if ($isSelected) {
                $cardBg = $selectedBg
                $cardFg = $selectedFg
                $valueFg = $selectedFg
            }
            
            # Special colors for certain cards
            if ($card.Id -eq 'overdue' -and [int]$card.Value -gt 0) {
                $valueFg = $errorColor
            } elseif ($card.Id -eq 'dueToday' -and [int]$card.Value -gt 0) {
                $valueFg = $warningColor
            }

            # Draw card box with UNICODE rounded corners
            # Normal: ╭─╮ │ │ ╰─╯
            # Selected: ┏━┓ ┃ ┃ ┗━┛ (double lines)
            if ($isSelected) {
                $topBorder = "┏" + [string]::new('━', $cardWidth - 2) + "┓"
                $midBorder = "┃" + [string]::new(' ', $cardWidth - 2) + "┃"
                $botBorder = "┗" + [string]::new('━', $cardWidth - 2) + "┛"
            } else {
                $topBorder = "╭" + [string]::new('─', $cardWidth - 2) + "╮"
                $midBorder = "│" + [string]::new(' ', $cardWidth - 2) + "│"
                $botBorder = "╰" + [string]::new('─', $cardWidth - 2) + "╯"
            }

            $engine.WriteAt($cardX, $cardY, $topBorder, $cardFg, $cardBg)
            $engine.WriteAt($cardX, $cardY + 1, $midBorder, $cardFg, $cardBg)
            $engine.WriteAt($cardX, $cardY + 2, $midBorder, $cardFg, $cardBg)
            $engine.WriteAt($cardX, $cardY + 3, $midBorder, $cardFg, $cardBg)
            $engine.WriteAt($cardX, $cardY + 4, $botBorder, $cardFg, $cardBg)

            # Card label (centered)
            $label = $card.Label
            if ($label.Length -gt $cardWidth - 4) {
                $label = $label.Substring(0, $cardWidth - 4)
            }
            $labelX = $cardX + 1 + [Math]::Floor((($cardWidth - 2) - $label.Length) / 2)
            $engine.WriteAt($labelX, $cardY + 1, $label, $cardFg, $cardBg)

            # Card value (centered, larger)
            $value = $card.Value.ToString()
            $valueX = $cardX + 1 + [Math]::Floor((($cardWidth - 2) - $value.Length) / 2)
            $engine.WriteAt($valueX, $cardY + 3, $value, $valueFg, $cardBg)
        }

        # Instructions
        $y += $cardHeight + 2
        $engine.WriteAt($startX, $y, "Use Left/Right arrows to select, Enter to open", $mutedColor, $bg)
    }

    [string] RenderContent() { return "" }

    # === KEY HANDLING ===
    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $handled = ([PmcScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        $keyChar = [char]::ToLower($keyInfo.KeyChar)

        switch ($keyInfo.Key) {
            'LeftArrow' {
                if ($this.SelectedCard -gt 0) {
                    $this.SelectedCard--
                    $this._ShowCardInfo()
                }
                return $true
            }
            'RightArrow' {
                if ($this.SelectedCard -lt ($this.Cards.Count - 1)) {
                    $this.SelectedCard++
                    $this._ShowCardInfo()
                }
                return $true
            }
            'Enter' {
                $this._OpenSelectedCard()
                return $true
            }
            'Escape' {
                if ($global:PmcApp) { $global:PmcApp.RequestExit() }
                return $true
            }
        }

        switch ($keyChar) {
            'q' {
                if ($global:PmcApp) { $global:PmcApp.RequestExit() }
                return $true
            }
            'r' {
                $this.LoadData()
                return $true
            }
        }

        return $false
    }

    hidden [void] _ShowCardInfo() {
        $card = $this.Cards[$this.SelectedCard]
        $this.ShowStatus("$($card.Label): $($card.Value) - Press Enter to open")
    }

    hidden [void] _OpenSelectedCard() {
        $card = $this.Cards[$this.SelectedCard]
        
        if (-not $global:PmcApp) {
            $this.ShowError("Application not available")
            return
        }

        switch ($card.Id) {
            'hoursToday' {
                $this._NavigateToTimeList('today')
            }
            'hoursWeek' {
                $this._NavigateToTimeList('week')
            }
            'dueToday' {
                $this._NavigateToTaskList('today')
            }
            'overdue' {
                $this._NavigateToTaskList('overdue')
            }
            'noDate' {
                $this._NavigateToTaskList('nodate')
            }
        }
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
