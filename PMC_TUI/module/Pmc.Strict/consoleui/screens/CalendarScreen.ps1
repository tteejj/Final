using namespace System.Collections.Generic
using namespace System.Text

# CalendarScreen - Calendar with Alberta civic holidays
# Read-only calendar with multiple view modes and navigation
# Holidays highlighted for 2026-2035

Set-StrictMode -Version Latest

class CalendarScreen : PmcScreen {
    [datetime]$SelectedDate = [datetime]::Today
    [datetime]$ViewDate = [datetime]::Today
    [string]$ViewMode = 'month'  # 'month', '3month', 'year'
    [hashtable]$Holidays = @{}
    hidden [int]$_contentY = 4
    hidden [int]$_contentHeight = 20

    CalendarScreen() : base("Calendar", "Calendar") {
        $this.Header.SetBreadcrumb(@("Home", "Tools", "Calendar"))
        $this._InitFooter()
        $this._InitHolidays()
    }

    CalendarScreen([object]$container) : base("Calendar", "Calendar", $container) {
        $this.Header.SetBreadcrumb(@("Home", "Tools", "Calendar"))
        $this._InitFooter()
        $this._InitHolidays()
    }

    hidden [void] _InitFooter() {
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Arrows", "Navigate")
        $this.Footer.AddShortcut("[]", "Period")
        $this.Footer.AddShortcut("1/2/3", "View")
        $this.Footer.AddShortcut("Home", "Today")
        $this.Footer.AddShortcut("Esc", "Back")
    }

    # === HOLIDAY INITIALIZATION ===
    hidden [void] _InitHolidays() {
        # Pre-calculate all Alberta civic holidays for 2026-2035
        for ($year = 2026; $year -le 2035; $year++) {
            # Static holidays
            $this._AddHoliday($year, 1, 1, "New Year's Day")
            $this._AddHoliday($year, 7, 1, "Canada Day")
            $this._AddHoliday($year, 11, 11, "Remembrance Day")
            $this._AddHoliday($year, 12, 25, "Christmas Day")

            # Family Day - 3rd Monday of February
            $familyDay = $this._GetNthDayOfMonth($year, 2, [DayOfWeek]::Monday, 3)
            $this._AddHolidayDate($familyDay, "Family Day")

            # Good Friday - Friday before Easter Sunday
            $easter = $this._CalculateEaster($year)
            $goodFriday = $easter.AddDays(-2)
            $this._AddHolidayDate($goodFriday, "Good Friday")

            # Victoria Day - Monday before May 25
            $victoriaDay = $this._GetMondayBeforeDate($year, 5, 25)
            $this._AddHolidayDate($victoriaDay, "Victoria Day")

            # Heritage Day - 1st Monday of August (Alberta)
            $heritageDay = $this._GetNthDayOfMonth($year, 8, [DayOfWeek]::Monday, 1)
            $this._AddHolidayDate($heritageDay, "Heritage Day")

            # Labour Day - 1st Monday of September
            $labourDay = $this._GetNthDayOfMonth($year, 9, [DayOfWeek]::Monday, 1)
            $this._AddHolidayDate($labourDay, "Labour Day")

            # Thanksgiving - 2nd Monday of October
            $thanksgiving = $this._GetNthDayOfMonth($year, 10, [DayOfWeek]::Monday, 2)
            $this._AddHolidayDate($thanksgiving, "Thanksgiving")
        }
    }

    hidden [void] _AddHoliday([int]$year, [int]$month, [int]$day, [string]$name) {
        $date = [datetime]::new($year, $month, $day)
        $key = $date.ToString("yyyy-MM-dd")
        $this.Holidays[$key] = $name
    }

    hidden [void] _AddHolidayDate([datetime]$date, [string]$name) {
        $key = $date.ToString("yyyy-MM-dd")
        $this.Holidays[$key] = $name
    }

    hidden [datetime] _GetNthDayOfMonth([int]$year, [int]$month, [DayOfWeek]$dayOfWeek, [int]$n) {
        $firstDay = [datetime]::new($year, $month, 1)
        $daysUntil = (([int]$dayOfWeek - [int]$firstDay.DayOfWeek + 7) % 7)
        $result = $firstDay.AddDays($daysUntil + (($n - 1) * 7))
        return $result
    }

    hidden [datetime] _GetMondayBeforeDate([int]$year, [int]$month, [int]$day) {
        $targetDate = [datetime]::new($year, $month, $day)
        $daysBack = (([int]$targetDate.DayOfWeek - [int][DayOfWeek]::Monday + 7) % 7)
        if ($daysBack -eq 0) { $daysBack = 7 }
        return $targetDate.AddDays(-$daysBack)
    }

    hidden [datetime] _CalculateEaster([int]$year) {
        # Anonymous Gregorian algorithm
        $a = $year % 19
        $b = [Math]::Floor($year / 100)
        $c = $year % 100
        $d = [Math]::Floor($b / 4)
        $e = $b % 4
        $f = [Math]::Floor(($b + 8) / 25)
        $g = [Math]::Floor(($b - $f + 1) / 3)
        $h = (19 * $a + $b - $d - $g + 15) % 30
        $i = [Math]::Floor($c / 4)
        $k = $c % 4
        $l = (32 + 2 * $e + 2 * $i - $h - $k) % 7
        $m = [Math]::Floor(($a + 11 * $h + 22 * $l) / 451)
        $month = [Math]::Floor(($h + $l - 7 * $m + 114) / 31)
        $day = (($h + $l - 7 * $m + 114) % 31) + 1
        return [datetime]::new($year, $month, $day)
    }

    [string] _GetHolidayName([datetime]$date) {
        $key = $date.ToString("yyyy-MM-dd")
        if ($this.Holidays.ContainsKey($key)) {
            return $this.Holidays[$key]
        }
        return $null
    }

    # === INITIALIZATION ===
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
        $this.SelectedDate = [datetime]::Today
        $this.ViewDate = [datetime]::Today
        $holiday = $this._GetHolidayName($this.SelectedDate)
        if ($holiday) {
            $this.ShowStatus("Today: $holiday")
        } else {
            $this.ShowStatus("Calendar loaded")
        }
    }

    # === RENDERING ===
    [void] RenderContentToEngine([object]$engine) {
        switch ($this.ViewMode) {
            'month' { $this._RenderMonthView($engine) }
            '3month' { $this._Render3MonthView($engine) }
            'year' { $this._RenderYearView($engine) }
        }
    }

    hidden [void] _RenderMonthView([object]$engine) {
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.Title')
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $holidayBg = $this.Header.GetThemedColorInt('Foreground.Error')
        $todayBg = $this.Header.GetThemedColorInt('Foreground.Success')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        $y = $this._contentY
        $startX = $this.Header.X + 4

        # Month/Year header with legend
        $monthName = $this.ViewDate.ToString("MMMM yyyy")
        $engine.WriteAt($startX, $y, $monthName, $headerColor, $bg)
        # Legend on same line
        $engine.WriteAt($startX + 20, $y, "Legend:", $mutedColor, $bg)
        $engine.WriteAt($startX + 28, $y, " H ", $bg, $holidayBg)
        $engine.WriteAt($startX + 32, $y, "Holiday ", $mutedColor, $bg)
        $engine.WriteAt($startX + 40, $y, " T ", $bg, $todayBg)
        $engine.WriteAt($startX + 44, $y, "Today ", $mutedColor, $bg)
        $engine.WriteAt($startX + 50, $y, " S ", $selectedFg, $selectedBg)
        $engine.WriteAt($startX + 54, $y, "Selected", $mutedColor, $bg)
        $y += 2

        # Day headers with spacing
        $days = @("Su", "Mo", "Tu", "We", "Th", "Fr", "Sa")
        $x = $startX
        foreach ($day in $days) {
            $engine.WriteAt($x, $y, $day, $mutedColor, $bg)
            $engine.WriteAt($x + 2, $y, " ", $bg, $bg)  # Separator
            $x += 3
        }
        $y += 1

        # Days grid
        $firstOfMonth = [datetime]::new($this.ViewDate.Year, $this.ViewDate.Month, 1)
        $daysInMonth = [datetime]::DaysInMonth($this.ViewDate.Year, $this.ViewDate.Month)
        $startDayOfWeek = [int]$firstOfMonth.DayOfWeek

        $x = $startX + ($startDayOfWeek * 3)
        $today = [datetime]::Today

        for ($day = 1; $day -le $daysInMonth; $day++) {
            $currentDate = [datetime]::new($this.ViewDate.Year, $this.ViewDate.Month, $day)
            $isSelected = ($currentDate.Date -eq $this.SelectedDate.Date)
            $isToday = ($currentDate.Date -eq $today.Date)
            $holidayName = $this._GetHolidayName($currentDate)
            $isHoliday = (-not [string]::IsNullOrEmpty($holidayName))
            $isWeekend = ($currentDate.DayOfWeek -eq [DayOfWeek]::Saturday -or $currentDate.DayOfWeek -eq [DayOfWeek]::Sunday)

            # Default colors
            $dayFg = $textColor
            $dayBg = $bg

            # Weekend - muted text
            if ($isWeekend) {
                $dayFg = $mutedColor
            }
            # Holiday - red block
            if ($isHoliday) {
                $dayFg = $bg
                $dayBg = $holidayBg
            }
            # Today - green block (overrides holiday for visibility)
            if ($isToday) {
                $dayFg = $bg
                $dayBg = $todayBg
            }
            # Selected - selection block (highest priority)
            if ($isSelected) {
                $dayFg = $selectedFg
                $dayBg = $selectedBg
            }

            $dayStr = $day.ToString().PadLeft(2)
            $engine.WriteAt($x, $y, $dayStr, $dayFg, $dayBg)
            # Write separator space with NORMAL background
            $engine.WriteAt($x + 2, $y, " ", $bg, $bg)

            $x += 3
            if ($currentDate.DayOfWeek -eq [DayOfWeek]::Saturday) {
                $x = $startX
                $y++
            }
        }

        # Show selected date info
        $infoY = $this._contentY + 10
        $engine.WriteAt($startX, $infoY, "Selected: " + $this.SelectedDate.ToString("dddd, MMMM d, yyyy"), $textColor, $bg)
        $selectedHoliday = $this._GetHolidayName($this.SelectedDate)
        if (-not [string]::IsNullOrEmpty($selectedHoliday)) {
            $infoY++
            $engine.WriteAt($startX, $infoY, "Holiday: ", $mutedColor, $bg)
            $engine.WriteAt($startX + 9, $infoY, $selectedHoliday, $bg, $holidayBg)
        }
    }

    hidden [void] _Render3MonthView([object]$engine) {
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.Title')
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $holidayBg = $this.Header.GetThemedColorInt('Foreground.Error')
        $todayBg = $this.Header.GetThemedColorInt('Foreground.Success')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        $baseY = $this._contentY
        $startX = $this.Header.X + 2

        # Legend at top
        $engine.WriteAt($startX, $baseY, "Legend:", $mutedColor, $bg)
        $engine.WriteAt($startX + 8, $baseY, " H ", $bg, $holidayBg)
        $engine.WriteAt($startX + 12, $baseY, "Holiday ", $mutedColor, $bg)
        $engine.WriteAt($startX + 20, $baseY, " T ", $bg, $todayBg)
        $engine.WriteAt($startX + 24, $baseY, "Today ", $mutedColor, $bg)
        $engine.WriteAt($startX + 30, $baseY, " S ", $selectedFg, $selectedBg)
        $engine.WriteAt($startX + 34, $baseY, "Selected", $mutedColor, $bg)
        $baseY += 2

        # Render 3 months side by side with better spacing
        $prevMonth = $this.ViewDate.AddMonths(-1)
        $nextMonth = $this.ViewDate.AddMonths(1)

        $this._RenderMiniMonth($engine, $startX, $baseY, $prevMonth, $textColor, $mutedColor, $headerColor, $selectedBg, $selectedFg, $holidayBg, $todayBg, $bg)
        $this._RenderMiniMonth($engine, $startX + 26, $baseY, $this.ViewDate, $textColor, $mutedColor, $headerColor, $selectedBg, $selectedFg, $holidayBg, $todayBg, $bg)
        $this._RenderMiniMonth($engine, $startX + 52, $baseY, $nextMonth, $textColor, $mutedColor, $headerColor, $selectedBg, $selectedFg, $holidayBg, $todayBg, $bg)

        # Show selected date info at bottom
        $infoY = $baseY + 9
        $engine.WriteAt($startX, $infoY, "Selected: " + $this.SelectedDate.ToString("dddd, MMMM d, yyyy"), $textColor, $bg)
        $selectedHoliday = $this._GetHolidayName($this.SelectedDate)
        if (-not [string]::IsNullOrEmpty($selectedHoliday)) {
            $engine.WriteAt($startX + 40, $infoY, "Holiday: ", $mutedColor, $bg)
            $engine.WriteAt($startX + 49, $infoY, $selectedHoliday, $bg, $holidayBg)
        }
    }

    hidden [void] _RenderMiniMonth([object]$engine, [int]$x, [int]$y, [datetime]$monthDate, [int]$textColor, [int]$mutedColor, [int]$headerColor, [int]$selectedBg, [int]$selectedFg, [int]$holidayBg, [int]$todayColor, [int]$bg) {
        # Month header
        $monthName = $monthDate.ToString("MMM yyyy")
        $engine.WriteAt($x, $y, $monthName.PadRight(22), $headerColor, $bg)
        $y++

        # Day headers
        $engine.WriteAt($x, $y, "Su Mo Tu We Th Fr Sa  ", $mutedColor, $bg)
        $y++

        # Days
        $firstOfMonth = [datetime]::new($monthDate.Year, $monthDate.Month, 1)
        $daysInMonth = [datetime]::DaysInMonth($monthDate.Year, $monthDate.Month)
        $startDayOfWeek = [int]$firstOfMonth.DayOfWeek
        $today = [datetime]::Today

        $dayX = $x + ($startDayOfWeek * 3)
        for ($day = 1; $day -le $daysInMonth; $day++) {
            $currentDate = [datetime]::new($monthDate.Year, $monthDate.Month, $day)
            $isSelected = ($currentDate.Date -eq $this.SelectedDate.Date)
            $isToday = ($currentDate.Date -eq $today.Date)
            
            # Proper null check for holiday
            $holidayName = $this._GetHolidayName($currentDate)
            $isHoliday = (-not [string]::IsNullOrEmpty($holidayName))

            # Default colors
            $dayFg = $textColor
            $dayBg = $bg
            
            # Apply styling in priority order (lowest to highest)
            # Holiday - red block
            if ($isHoliday) { 
                $dayFg = $bg
                $dayBg = $holidayBg
            }
            # Today - green block
            if ($isToday) { 
                $dayFg = $bg
                $dayBg = $todayColor
            }
            # Selected - use BRACKETS for high visibility cursor
            if ($isSelected) { 
                $dayFg = $selectedFg
                $dayBg = $selectedBg
            }

            # Write day
            $dayStr = $day.ToString().PadLeft(2)
            if ($isSelected) {
                # SELECTED: Write with brackets for high visibility [XX]
                # Write opening bracket
                if ($dayX -gt $x) {
                    $engine.WriteAt($dayX - 1, $y, "[", $selectedFg, $bg)
                }
                $engine.WriteAt($dayX, $y, $dayStr, $selectedFg, $selectedBg)
                $engine.WriteAt($dayX + 2, $y, "]", $selectedFg, $bg)
            } else {
                $engine.WriteAt($dayX, $y, $dayStr, $dayFg, $dayBg)
                # Write space separator with NORMAL background
                $engine.WriteAt($dayX + 2, $y, " ", $bg, $bg)
            }

            $dayX += 3
            if ($currentDate.DayOfWeek -eq [DayOfWeek]::Saturday) {
                $dayX = $x
                $y++
            }
        }
    }

    hidden [void] _RenderYearView([object]$engine) {
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.Title')
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $holidayBg = $this.Header.GetThemedColorInt('Foreground.Error')
        $todayBg = $this.Header.GetThemedColorInt('Foreground.Success')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        $baseY = $this._contentY
        $startX = $this.Header.X + 2

        # Year header
        $engine.WriteAt($startX, $baseY, $this.ViewDate.Year.ToString(), $headerColor, $bg)
        
        # Legend on same line
        $engine.WriteAt($startX + 10, $baseY, "Legend:", $mutedColor, $bg)
        $engine.WriteAt($startX + 18, $baseY, " H ", $bg, $holidayBg)
        $engine.WriteAt($startX + 22, $baseY, "Holiday", $mutedColor, $bg)
        $engine.WriteAt($startX + 30, $baseY, " T ", $bg, $todayBg)
        $engine.WriteAt($startX + 34, $baseY, "Today", $mutedColor, $bg)
        $engine.WriteAt($startX + 40, $baseY, "[S]", $selectedFg, $selectedBg)
        $engine.WriteAt($startX + 44, $baseY, "Selected", $mutedColor, $bg)
        $baseY++
        
        # SELECTED DATE AND HOLIDAY NAME - dedicated visible line
        $engine.WriteAt($startX, $baseY, ">>> Selected: " + $this.SelectedDate.ToString("dddd, MMMM d, yyyy"), $selectedFg, $bg)
        $selectedHoliday = $this._GetHolidayName($this.SelectedDate)
        if (-not [string]::IsNullOrEmpty($selectedHoliday)) {
            $engine.WriteAt($startX + 50, $baseY, "HOLIDAY: ", $holidayBg, $bg)
            $engine.WriteAt($startX + 59, $baseY, $selectedHoliday, $bg, $holidayBg)
        } else {
            # Clear the holiday area if no holiday
            $engine.WriteAt($startX + 50, $baseY, "                                ", $bg, $bg)
        }
        $baseY++

        # 4x3 grid of months
        for ($row = 0; $row -lt 3; $row++) {
            for ($col = 0; $col -lt 4; $col++) {
                $monthNum = ($row * 4) + $col + 1
                $monthDate = [datetime]::new($this.ViewDate.Year, $monthNum, 1)
                $monthX = $startX + ($col * 24)
                $monthY = $baseY + ($row * 9)
                $this._RenderMiniMonth($engine, $monthX, $monthY, $monthDate, $textColor, $mutedColor, $headerColor, $selectedBg, $selectedFg, $holidayBg, $todayBg, $bg)
            }
        }
    }

    [string] RenderContent() { return "" }

    # === KEY HANDLING ===
    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        $keyChar = $keyInfo.KeyChar

        switch ($keyInfo.Key) {
            'LeftArrow' {
                $this.SelectedDate = $this.SelectedDate.AddDays(-1)
                $this._UpdateViewForSelection()
                return $true
            }
            'RightArrow' {
                $this.SelectedDate = $this.SelectedDate.AddDays(1)
                $this._UpdateViewForSelection()
                return $true
            }
            'UpArrow' {
                $this.SelectedDate = $this.SelectedDate.AddDays(-7)
                $this._UpdateViewForSelection()
                return $true
            }
            'DownArrow' {
                $this.SelectedDate = $this.SelectedDate.AddDays(7)
                $this._UpdateViewForSelection()
                return $true
            }
            'Home' {
                $this.SelectedDate = [datetime]::Today
                $this.ViewDate = [datetime]::Today
                $this._ShowSelectedInfo()
                return $true
            }
            'Escape' {
                if ($global:PmcApp) { $global:PmcApp.PopScreen() }
                return $true
            }
        }

        switch ($keyChar) {
            '[' {
                # Previous period
                switch ($this.ViewMode) {
                    'month' { $this.ViewDate = $this.ViewDate.AddMonths(-1) }
                    '3month' { $this.ViewDate = $this.ViewDate.AddMonths(-1) }
                    'year' { $this.ViewDate = $this.ViewDate.AddYears(-1) }
                }
                return $true
            }
            ']' {
                # Next period
                switch ($this.ViewMode) {
                    'month' { $this.ViewDate = $this.ViewDate.AddMonths(1) }
                    '3month' { $this.ViewDate = $this.ViewDate.AddMonths(1) }
                    'year' { $this.ViewDate = $this.ViewDate.AddYears(1) }
                }
                return $true
            }
            '1' {
                $this.ViewMode = 'month'
                $this.ShowStatus("Month view")
                return $true
            }
            '2' {
                $this.ViewMode = '3month'
                $this.ShowStatus("3-month view")
                return $true
            }
            '3' {
                $this.ViewMode = 'year'
                $this.ShowStatus("Year view")
                return $true
            }
        }

        return $false
    }

    hidden [void] _MoveToSameDayInMonth([int]$monthOffset) {
        # Move to same day number in target month, clamping if target month has fewer days
        $targetMonth = $this.SelectedDate.AddMonths($monthOffset)
        $targetDay = $this.SelectedDate.Day
        $daysInTargetMonth = [datetime]::DaysInMonth($targetMonth.Year, $targetMonth.Month)
        
        # Clamp day to last day of target month if necessary
        if ($targetDay -gt $daysInTargetMonth) {
            $targetDay = $daysInTargetMonth
        }
        
        $this.SelectedDate = [datetime]::new($targetMonth.Year, $targetMonth.Month, $targetDay)
        
        # Update ViewDate year if we've moved to a different year in year view
        if ($this.ViewMode -eq 'year' -and $this.SelectedDate.Year -ne $this.ViewDate.Year) {
            $this.ViewDate = [datetime]::new($this.SelectedDate.Year, 1, 1)
        }
    }

    hidden [void] _UpdateViewForSelection() {
        # Keep ViewDate in sync with selection for month view
        if ($this.ViewMode -eq 'month') {
            if ($this.SelectedDate.Month -ne $this.ViewDate.Month -or $this.SelectedDate.Year -ne $this.ViewDate.Year) {
                $this.ViewDate = [datetime]::new($this.SelectedDate.Year, $this.SelectedDate.Month, 1)
            }
        }
        $this._ShowSelectedInfo()
    }

    hidden [void] _ShowSelectedInfo() {
        $holiday = $this._GetHolidayName($this.SelectedDate)
        if ($holiday) {
            $this.ShowStatus($this.SelectedDate.ToString("MMM d, yyyy") + " - " + $holiday)
        } else {
            $this.ShowStatus($this.SelectedDate.ToString("dddd, MMMM d, yyyy"))
        }
    }
}

function Show-CalendarScreen {
    param([object]$App)
    if (-not $App) { throw "PmcApplication required" }
    $screen = New-Object CalendarScreen
    $App.PushScreen($screen)
}
