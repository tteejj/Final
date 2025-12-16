using namespace System
using namespace System.Collections.Generic
using namespace System.Text
using namespace System.Globalization

# DatePicker.ps1 - Production-ready date picker widget for PMC TUI
# Supports both text input (smart date parsing) and calendar mode (visual month grid)
#
# Usage:
#   $picker = [DatePicker]::new()
#   $picker.SetPosition(10, 5)
#   $picker.SetSize(35, 14)
#   $picker.SetDate([DateTime]::Today)
#
#   # Render
#   $ansiOutput = $picker.Render()
#   Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [DatePicker] Rendering date picker"
#
#   # Handle input
#   $key = [Console]::ReadKey($true)
#   $handled = $picker.HandleInput($key)
#
#   # Get result
#   if ($picker.IsConfirmed) {
#       $selected = $picker.GetSelectedDate()
#   }

Set-StrictMode -Version Latest

# Load PmcWidget base class if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

<#
.SYNOPSIS
Production-ready DatePicker widget with text and calendar modes

.DESCRIPTION
Features:
- Text mode: Smart date parsing (today, tomorrow, next friday, +7, eom, ISO dates)
- Calendar mode: Visual month grid with arrow navigation
- Full keyboard navigation
- Theme integration
- Event callbacks for date changes, confirmation, cancellation
- Automatic bounds clamping and validation

.EXAMPLE
$picker = [DatePicker]::new()
$picker.SetPosition(10, 5)
$picker.SetSize(35, 14)
$picker.SetDate([DateTime]::Today)
$picker.OnDateChanged = { param($newDate) Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [DatePicker] Date changed to: $newDate" }
$picker.OnConfirmed = { param($date) Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [DatePicker] Confirmed: $date" }
$ansiOutput = $picker.Render()
#>
class DatePicker : PmcWidget {
    # === Public Properties ===
    [bool]$IsConfirmed = $false      # True when user presses Enter
    [bool]$IsCancelled = $false      # True when user presses Esc

    # === Event Callbacks ===
    [scriptblock]$OnDateChanged = {}  # Called when date changes: param($newDate)
    [scriptblock]$OnConfirmed = {}    # Called when Enter pressed: param($finalDate)
    [scriptblock]$OnCancelled = {}    # Called when Esc pressed

    # === Private State ===
    hidden [DateTime]$_selectedDate = [DateTime]::Today
    hidden [DateTime]$_calendarMonth = [DateTime]::Today  # Month being displayed in calendar
    hidden [bool]$_isCalendarMode = $false                # False = text mode, True = calendar mode
    hidden [string]$_textInput = ""                       # Text mode input buffer
    hidden [string]$_errorMessage = ""                    # Error message to display
    hidden [int]$_cursorPosition = 0                      # Text cursor position

    # === Constructor ===
    # NOTE: This widget shows ONLY the calendar mode for visual date selection.
    # For text-based date entry (parsing "today", "next friday", etc.), use DateTextEntry widget.
    # DatePicker is designed for inline display at column positions in list views.
    DatePicker() : base("DatePicker") {
        $this.Width = 35
        $this.Height = 14
        $this._selectedDate = [DateTime]::Today
        $this._calendarMonth = [DateTime]::Today
        $this._textInput = $this._selectedDate.ToString("yyyy-MM-dd")
        $this.CanFocus = $true
        $this._isCalendarMode = $true  # ALWAYS start in calendar mode
    }

    # === Public API Methods ===

    <#
    .SYNOPSIS
    Set the currently selected date

    .PARAMETER date
    DateTime to set as selected
    #>
    [void] SetDate([DateTime]$date) {
        $this._selectedDate = $date
        $this._calendarMonth = $date
        $this._textInput = $date.ToString("yyyy-MM-dd")
        $this._errorMessage = ""
        $this._InvokeCallback($this.OnDateChanged, $date)
    }

    <#
    .SYNOPSIS
    Get the currently selected date

    .OUTPUTS
    DateTime object
    #>
    [DateTime] GetSelectedDate() {
        return $this._selectedDate
    }

    <#
    .SYNOPSIS
    Handle keyboard input

    .PARAMETER keyInfo
    ConsoleKeyInfo from [Console]::ReadKey($true)

    .OUTPUTS
    True if input was handled, False otherwise
    #>
    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        # Global keys
        if ($keyInfo.Key -eq 'Enter') {
            $this.IsConfirmed = $true
            $this._InvokeCallback($this.OnConfirmed, $this._selectedDate)
            return $true
        }

        if ($keyInfo.Key -eq 'Escape') {
            $this.IsCancelled = $true
            $this._InvokeCallback($this.OnCancelled, $null)
            return $true
        }

        # Always handle as calendar mode
        return $this._HandleCalendarInput($keyInfo)
    }

    # === Layout System ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)
        # Regions removed - using direct WriteAt in RenderToEngine for reliability
    }

    <#
    .SYNOPSIS
    Render directly to engine (new high-performance path)
    #>
    [void] RenderToEngine([object]$engine) {
        $this.RegisterLayout($engine)

        # Colors (Ints)
        # Use Panel background (usually dark/black) instead of MenuBar (often colored) to avoid "giant block" look
        $bg = $this.GetThemedBgInt('Background.Panel', 1, 0)
        if ($bg -eq -1) { $bg = [HybridRenderEngine]::_PackRGB(30, 30, 30) }
        
        # Clamp bounds immediately before drawing
        $this._ClampToBounds($engine)
        
        # === LAYER ELEVATION ===
        # Ensure Popup is drawn ABOVE everything else
        if ($engine.PSObject.Methods['BeginLayer']) {
            $engine.BeginLayer(100)
        }

        $fg = $this.GetThemedInt('Foreground.Row')
        $borderFg = $this.GetThemedInt('Border.Widget')
        $primaryFg = $this.GetThemedInt('Foreground.Title')
        $mutedFg = $this.GetThemedInt('Foreground.Muted')
        $errorFg = $this.GetThemedInt('Foreground.Error')
        $successFg = $this.GetThemedInt('Foreground.Success')
        $highlightBg = $this.GetThemedBgInt('Background.RowSelected', 1, 0)
        $highlightFg = $this.GetThemedInt('Foreground.RowSelected')

        # Draw Box (Panel Background)
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $borderFg, $bg)
        
        # Title
        $title = "Select Date"
        $pad = [Math]::Max(0, [Math]::Floor(($this.Width - 4 - $title.Length) / 2))
        $engine.WriteAt($this.X + 2 + $pad, $this.Y + 1, $title, $primaryFg, $bg)
        
        # Status
        # Status
        $currentValue = "Current: " + $this._selectedDate.ToString("yyyy-MM-dd ddd")
        # Pad to ensure line clearing
        $engine.WriteAt($this.X + 2, $this.Y + 2, $this.PadText($currentValue, $this.Width - 4, 'left'), $fg, $bg)
        
        # Calendar Header
        $monthYear = $this._calendarMonth.ToString("MMMM yyyy")
        $pad = [Math]::Max(0, [Math]::Floor(($this.Width - 4 - $monthYear.Length) / 2))
        $engine.WriteAt($this.X + 2 + $pad, $this.Y + 4, $monthYear, $primaryFg, $bg)
        
        # Day Names
        $dayNames = "Su Mo Tu We Th Fr Sa"
        $pad = [Math]::Max(0, [Math]::Floor(($this.Width - 4 - $dayNames.Length) / 2))
        $engine.WriteAt($this.X + 2 + $pad, $this.Y + 5, $dayNames, $primaryFg, $bg)
        
        # Grid
        $firstDay = [DateTime]::new($this._calendarMonth.Year, $this._calendarMonth.Month, 1)
        $daysInMonth = [DateTime]::DaysInMonth($this._calendarMonth.Year, $this._calendarMonth.Month)
        $startDayOfWeek = [int]$firstDay.DayOfWeek
        $today = [DateTime]::Today
        
        # Manually calculate grid positions since it's a specialized layout
        for ($week = 0; $week -lt 6; $week++) {
            $rowY = $this.Y + 6 + $week
            # Calculate X offset to center the grid (approx 20 chars wide: "Su Mo Tu We Th Fr Sa")
            # Day Names string is 20 chars wide.
            # Align center similar to day names pad
            $padGrid = [Math]::Max(0, [Math]::Floor(($this.Width - 4 - 20) / 2))
            $startX = $this.X + 2 + $padGrid
            
            for ($dow = 0; $dow -lt 7; $dow++) {
                $dayNum = ($week * 7 + $dow) - $startDayOfWeek + 1
                $cellX = $startX + ($dow * 3)
                
                if ($dayNum -ge 1 -and $dayNum -le $daysInMonth) {
                    $thisDate = [DateTime]::new($this._calendarMonth.Year, $this._calendarMonth.Month, $dayNum)
                    $dayStr = $dayNum.ToString().PadLeft(2)
                    
                    $isSelected = ($thisDate.Date -eq $this._selectedDate.Date)
                    $isToday = ($thisDate.Date -eq $today)
                    
                    $cBg = $bg
                    $cFg = $fg
                    
                    if ($isSelected) {
                        $cBg = $highlightBg
                        $cFg = $highlightFg
                    }
                    elseif ($isToday) {
                        $cFg = $primaryFg
                    }
                    
                    $engine.WriteAt($cellX, $rowY, $dayStr, $cFg, $cBg)
                }
            }
        }
        
        # Help
        $helpText = "Enter: Select"
        # Pad help text to clear any potential artifacts from previous renders
        $engine.WriteAt($this.X + 2, $this.Y + $this.Height - 3, $this.PadText($helpText, $this.Width - 4, 'left'), $mutedFg, $bg)
        
        # Error
        if ($this._errorMessage) {
            $engine.WriteAt($this.X + 2, $this.Y + $this.Height - 1, $this.PadText($this._errorMessage, $this.Width - 4, 'left'), $errorFg, $bg)
        }
        
        # === END LAYER ELEVATION ===
        if ($engine.PSObject.Methods['BeginLayer']) {
            $engine.BeginLayer(0)
        }
    }

    <#
    .SYNOPSIS
    Ensure widget stays within screen bounds (Engine Viewport)
    #>
    hidden [void] _ClampToBounds([object]$engine) {
        # Check Engine bounds first (Authoritative Viewport)
        if ($engine -and $engine.PSObject.Properties['Width']) {
            $termWidth = $engine.Width
            $termHeight = $engine.Height
        }
        else {
            # Fallback to console (but verify console availability)
            try {
                $termWidth = [Console]::WindowWidth
                $termHeight = [Console]::WindowHeight
            }
            catch {
                $termWidth = 80
                $termHeight = 24
            }
        }
        
        # Clamp X
        if ($this.X + $this.Width -ge $termWidth) {
            $this.X = [Math]::Max(0, $termWidth - $this.Width)
        }
        
        # Clamp Y
        if ($this.Y + $this.Height -ge $termHeight) {
            $this.Y = [Math]::Max(0, $termHeight - $this.Height)
        }
    }

    <#
    .SYNOPSIS
    Render the date picker widget

    .OUTPUTS
    ANSI string ready for display
    #>
    <#
    .SYNOPSIS
    Render the date picker widget (Legacy)
    #>
    [string] Render() {
        return ""
    }

    # === Private Helper Methods ===

    hidden [void] _ToggleMode() {
        $this._isCalendarMode = -not $this._isCalendarMode
        $this._errorMessage = ""

        # When switching to calendar mode, parse text input first
        if ($this._isCalendarMode) {
            $parsed = $this._ParseTextInput()
            if ($parsed) {
                $this._selectedDate = $parsed
                $this._calendarMonth = $parsed
            }
        }
        else {
            # Switching to text mode - populate with current selected date
            $this._textInput = $this._selectedDate.ToString("yyyy-MM-dd")
            $this._cursorPosition = $this._textInput.Length
        }
    }

    hidden [void] _RenderTextMode([StringBuilder]$sb, [string]$borderColor, [string]$textColor, [string]$primaryColor, [string]$errorColor, [string]$reset) {
        # Instructions (row 2)
        $instructions = "Type: today, tomorrow, next fri, +7, eom, YYYY-MM-DD"
        $sb.Append($this.BuildMoveTo($this.X, $this.Y + 2))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))
        $sb.Append($textColor)
        $sb.Append(" " + $this.TruncateText($instructions, $this.Width - 3))
        $sb.Append($borderColor)
        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $this.Y + 2))
        $sb.Append($this.GetBoxChar('single_vertical'))

        # Input field (row 4)
        $sb.Append($this.BuildMoveTo($this.X, $this.Y + 4))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))
        $sb.Append($primaryColor)
        $sb.Append(" Input: ")
        $sb.Append($textColor)

        # Show input with cursor
        $displayInput = $this._textInput
        $maxInputWidth = $this.Width - 11
        if ($displayInput.Length -gt $maxInputWidth) {
            $displayInput = $displayInput.Substring($displayInput.Length - $maxInputWidth)
        }
        $sb.Append($displayInput)
        $sb.Append("_")  # Cursor
        $sb.Append(" " * [Math]::Max(0, $maxInputWidth - $displayInput.Length - 1))

        $sb.Append($borderColor)
        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $this.Y + 4))
        $sb.Append($this.GetBoxChar('single_vertical'))

        # Examples (rows 6-10)
        $examples = @(
            "Examples:",
            "  today, tomorrow",
            "  next monday, next fri",
            "  +7 (7 days from now)",
            "  eom (end of month)",
            "  2025-03-15"
        )

        for ($i = 0; $i -lt $examples.Count; $i++) {
            $row = $this.Y + 6 + $i
            $sb.Append($this.BuildMoveTo($this.X, $row))
            $sb.Append($borderColor)
            $sb.Append($this.GetBoxChar('single_vertical'))
            $sb.Append($textColor)
            $sb.Append(" " + $this.PadText($examples[$i], $this.Width - 3, 'left'))
            $sb.Append($borderColor)
            $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $row))
            $sb.Append($this.GetBoxChar('single_vertical'))
        }
    }

    hidden [void] _RenderCalendar([StringBuilder]$sb, [string]$borderColor, [string]$textColor, [string]$primaryColor, [string]$mutedColor, [string]$successColor, [string]$reset) {
        # Month/Year header (row 2)
        $monthYear = $this._calendarMonth.ToString("MMMM yyyy")
        $sb.Append($this.BuildMoveTo($this.X, $this.Y + 2))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))
        $sb.Append($primaryColor)
        $sb.Append(" " + $this.PadText($monthYear, $this.Width - 3, 'center'))
        $sb.Append($borderColor)
        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $this.Y + 2))
        $sb.Append($this.GetBoxChar('single_vertical'))

        # Day names (row 3)
        $dayNames = "Su Mo Tu We Th Fr Sa"
        $sb.Append($this.BuildMoveTo($this.X, $this.Y + 3))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))
        $sb.Append($primaryColor)
        $sb.Append(" " + $this.PadText($dayNames, $this.Width - 3, 'center'))
        $sb.Append($borderColor)
        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $this.Y + 3))
        $sb.Append($this.GetBoxChar('single_vertical'))

        # Calendar grid (rows 4-9, 6 weeks max)
        $firstDay = [DateTime]::new($this._calendarMonth.Year, $this._calendarMonth.Month, 1)
        $daysInMonth = [DateTime]::DaysInMonth($this._calendarMonth.Year, $this._calendarMonth.Month)
        $startDayOfWeek = [int]$firstDay.DayOfWeek  # 0 = Sunday

        $today = [DateTime]::Today

        for ($week = 0; $week -lt 6; $week++) {
            $row = $this.Y + 4 + $week
            $sb.Append($this.BuildMoveTo($this.X, $row))
            $sb.Append($borderColor)
            $sb.Append($this.GetBoxChar('single_vertical'))

            $line = " "
            for ($dow = 0; $dow -lt 7; $dow++) {
                $dayNum = ($week * 7 + $dow) - $startDayOfWeek + 1

                if ($dayNum -ge 1 -and $dayNum -le $daysInMonth) {
                    $thisDate = [DateTime]::new($this._calendarMonth.Year, $this._calendarMonth.Month, $dayNum)
                    $dayStr = $dayNum.ToString().PadLeft(2)

                    # Highlight logic
                    $isSelected = ($thisDate.Date -eq $this._selectedDate.Date)
                    $isToday = ($thisDate.Date -eq $today)

                    if ($isSelected) {
                        $line += $successColor + "[$dayStr]" + $textColor
                    }
                    elseif ($isToday) {
                        $line += $primaryColor + " $dayStr " + $textColor
                    }
                    else {
                        $line += " $dayStr "
                    }
                }
                else {
                    $line += "    "
                }
            }

            $sb.Append($textColor)
            # Don't pad/truncate calendar lines - they contain ANSI codes that confuse length calculation
            $sb.Append($line)
            # Pad with spaces to fill remaining width (calendar is fixed format, no ANSI in padding)
            $visibleLength = ($line -replace '\e\[[0-9;]*m', '').Length
            $padding = [Math]::Max(0, $this.Width - 3 - $visibleLength)
            $sb.Append(' ' * $padding)
            $sb.Append($borderColor)
            $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $row))
            $sb.Append($this.GetBoxChar('single_vertical'))
        }

        # Navigation hints (row 10)
        $hints = "Arrows: Navigate | PgUp/Dn: Month | Home/End: Month edges"
        $sb.Append($this.BuildMoveTo($this.X, $this.Y + 10))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))
        $sb.Append($mutedColor)
        $sb.Append(" " + $this.TruncateText($hints, $this.Width - 3))
        $sb.Append($borderColor)
        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $this.Y + 10))
        $sb.Append($this.GetBoxChar('single_vertical'))
    }

    hidden [bool] _HandleTextInput([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'Backspace' {
                if ($this._textInput.Length -gt 0) {
                    $this._textInput = $this._textInput.Substring(0, $this._textInput.Length - 1)
                    $this._errorMessage = ""
                }
                return $true
            }
            'Delete' {
                # Clear entire input
                $this._textInput = ""
                $this._errorMessage = ""
                return $true
            }
            default {
                # Add printable characters
                if ($keyInfo.KeyChar -ge 32 -and $keyInfo.KeyChar -le 126) {
                    $this._textInput += $keyInfo.KeyChar
                    $this._errorMessage = ""
                }
                return $true
            }
        }
        return $false
    }

    hidden [bool] _HandleCalendarInput([ConsoleKeyInfo]$keyInfo) {
        $changed = $false

        switch ($keyInfo.Key) {
            'LeftArrow' {
                $this._selectedDate = $this._selectedDate.AddDays(-1)
                $changed = $true
            }
            'RightArrow' {
                $this._selectedDate = $this._selectedDate.AddDays(1)
                $changed = $true
            }
            'UpArrow' {
                $this._selectedDate = $this._selectedDate.AddDays(-7)
                $changed = $true
            }
            'DownArrow' {
                $this._selectedDate = $this._selectedDate.AddDays(7)
                $changed = $true
            }
            'PageUp' {
                $this._selectedDate = $this._selectedDate.AddMonths(-1)
                $this._calendarMonth = $this._selectedDate
                $changed = $true
            }
            'PageDown' {
                $this._selectedDate = $this._selectedDate.AddMonths(1)
                $this._calendarMonth = $this._selectedDate
                $changed = $true
            }
            'Home' {
                # Start of month
                $this._selectedDate = [DateTime]::new($this._selectedDate.Year, $this._selectedDate.Month, 1)
                $changed = $true
            }
            'End' {
                # End of month
                $daysInMonth = [DateTime]::DaysInMonth($this._selectedDate.Year, $this._selectedDate.Month)
                $this._selectedDate = [DateTime]::new($this._selectedDate.Year, $this._selectedDate.Month, $daysInMonth)
                $changed = $true
            }
        }

        # Update calendar month if selected date moved to different month
        if ($changed) {
            if ($this._selectedDate.Month -ne $this._calendarMonth.Month -or
                $this._selectedDate.Year -ne $this._calendarMonth.Year) {
                $this._calendarMonth = $this._selectedDate
            }
            $this._InvokeCallback($this.OnDateChanged, $this._selectedDate)
        }

        return $changed
    }

    hidden [object] _ParseTextInput() {
        $input = $this._textInput.Trim().ToLower()

        if ([string]::IsNullOrWhiteSpace($input)) {
            $this._errorMessage = "Empty input"
            return $null
        }

        try {
            # Today
            if ($input -eq 'today') {
                return [DateTime]::Today
            }

            # Tomorrow
            if ($input -eq 'tomorrow') {
                return [DateTime]::Today.AddDays(1)
            }

            # Relative days (+N or -N)
            if ($input -match '^([+-]?\d+)$') {
                $days = [int]$Matches[1]
                return [DateTime]::Today.AddDays($days)
            }

            # End of month
            if ($input -eq 'eom') {
                $today = [DateTime]::Today
                $daysInMonth = [DateTime]::DaysInMonth($today.Year, $today.Month)
                return [DateTime]::new($today.Year, $today.Month, $daysInMonth)
            }

            # Next [day of week]
            if ($input -match '^next\s+(\w+)') {
                $dayName = $Matches[1]
                $targetDay = $this._ParseDayOfWeek($dayName)

                if ($targetDay -ne $null) {
                    $today = [DateTime]::Today
                    $daysUntil = (([int]$targetDay - [int]$today.DayOfWeek + 7) % 7)
                    if ($daysUntil -eq 0) { $daysUntil = 7 }  # Next week if today
                    return $today.AddDays($daysUntil)
                }
            }

            # Just day of week (next occurrence)
            $targetDay = $this._ParseDayOfWeek($input)
            if ($targetDay -ne $null) {
                $today = [DateTime]::Today
                $daysUntil = (([int]$targetDay - [int]$today.DayOfWeek + 7) % 7)
                if ($daysUntil -eq 0) { $daysUntil = 7 }  # Next week if today
                return $today.AddDays($daysUntil)
            }

            # Month day (e.g., "jan 15", "march 3")
            if ($input -match '^(\w+)\s+(\d+)') {
                $monthName = $Matches[1]
                $day = [int]$Matches[2]
                $month = $this._ParseMonth($monthName)

                if ($month -gt 0 -and $day -ge 1 -and $day -le 31) {
                    $year = [DateTime]::Today.Year
                    # If date has passed this year, use next year
                    $testDate = [DateTime]::new($year, $month, $day)
                    if ($testDate -lt [DateTime]::Today) {
                        $year++
                    }
                    return [DateTime]::new($year, $month, $day)
                }
            }

            # ISO date format (YYYY-MM-DD)
            if ($input -match '^\d{4}-\d{2}-\d{2}$') {
                $parsed = [DateTime]::ParseExact($input, 'yyyy-MM-dd', [CultureInfo]::InvariantCulture)
                return $parsed
            }

            # Try general DateTime parse
            $parsed = [DateTime]::Parse($input, [CultureInfo]::InvariantCulture)
            return $parsed

        }
        catch {
            $this._errorMessage = "Invalid date: $input"
            return $null
        }

        $this._errorMessage = "Unrecognized format: $input"
        return $null
    }

    hidden [object] _ParseDayOfWeek([string]$name) {
        $name = $name.ToLower()

        switch -Regex ($name) {
            '^su(n|nday)?$' { return [DayOfWeek]::Sunday }
            '^mo(n|nday)?$' { return [DayOfWeek]::Monday }
            '^tu(e|es|esday)?$' { return [DayOfWeek]::Tuesday }
            '^we(d|dnesday)?$' { return [DayOfWeek]::Wednesday }
            '^th(u|ursday)?$' { return [DayOfWeek]::Thursday }
            '^fr(i|iday)?$' { return [DayOfWeek]::Friday }
            '^sa(t|turday)?$' { return [DayOfWeek]::Saturday }
        }

        return $null
    }

    hidden [int] _ParseMonth([string]$name) {
        $name = $name.ToLower()

        switch -Regex ($name) {
            '^jan(uary)?$' { return 1 }
            '^feb(ruary)?$' { return 2 }
            '^mar(ch)?$' { return 3 }
            '^apr(il)?$' { return 4 }
            '^may$' { return 5 }
            '^jun(e)?$' { return 6 }
            '^jul(y)?$' { return 7 }
            '^aug(ust)?$' { return 8 }
            '^sep(tember)?$' { return 9 }
            '^oct(ober)?$' { return 10 }
            '^nov(ember)?$' { return 11 }
            '^dec(ember)?$' { return 12 }
        }

        return 0
    }

    hidden [void] _InvokeCallback([scriptblock]$callback, $arg) {
        if ($callback -and $callback -ne {}) {
            try {
                if ($arg -ne $null) {
                    & $callback $arg
                }
                else {
                    & $callback
                }
            }
            catch {
                # Silently ignore callback errors
            }
        }
    }
}