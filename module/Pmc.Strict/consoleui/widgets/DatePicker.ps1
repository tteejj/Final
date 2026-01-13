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
    Render date picker to engine
    #>
    [void] RenderToEngine([object]$engine) {
        # DEBUG: Conditional logging for rendering issues
        if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [DatePicker.RenderToEngine] CALLED X=$($this.X) Y=$($this.Y) W=$($this.Width) H=$($this.Height)"
        }

        # Clamp to bounds
        $this._ClampToBounds($engine)

        # Get background color first (needed for Fill and DrawBox)
        $bg = $this.GetThemedBgInt('Background.Row', $this.Width, 0)

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

        # DEBUG: Log colors
        if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [DatePicker.RenderToEngine] Colors: bg=$bg borderFg=$borderFg"
        }

        # Draw Box (Panel Background)
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $borderFg, $bg)
        
        # Title
        $title = "Select Date"
        $pad = [Math]::Max(0, [Math]::Floor(($this.Width - 4 - $title.Length) / 2))
        $engine.WriteAt($this.X + 2 + $pad, $this.Y + 1, $title, $primaryFg, $bg)
        
        # Status
        $currentValue = "Current: " + $this._selectedDate.ToString("yyyy-MM-dd ddd")
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
        
        for ($week = 0; $week -lt 6; $week++) {
            $rowY = $this.Y + 6 + $week
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
        $engine.WriteAt($this.X + 2, $this.Y + $this.Height - 3, $this.PadText($helpText, $this.Width - 4, 'left'), $mutedFg, $bg)
        
        # Error
        if ($this._errorMessage) {
            $engine.WriteAt($this.X + 2, $this.Y + $this.Height - 1, $this.PadText($this._errorMessage, $this.Width - 4, 'left'), $errorFg, $bg)
        }
        
        # End layer elevation
        if ($engine.PSObject.Methods['EndLayer']) {
            $engine.EndLayer()
        }

        # DEBUG: Log completion
        if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [DatePicker.RenderToEngine] COMPLETE"
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
    Render the date picker widget (Legacy)
    #>
    [string] Render() {
        return ""
    }

    # === Private Helper Methods ===

    hidden [void] _ToggleMode() {
        $this._isCalendarMode = -not $this._isCalendarMode
        $this._errorMessage = ""

        if ($this._isCalendarMode) {
            $parsed = $this._ParseTextInput()
            if ($parsed) {
                $this._selectedDate = $parsed
                $this._calendarMonth = $parsed
            }
        }
        else {
            $this._textInput = $this._selectedDate.ToString("yyyy-MM-dd")
            $this._cursorPosition = $this._textInput.Length
        }
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
                $this._selectedDate = [DateTime]::new($this._selectedDate.Year, $this._selectedDate.Month, 1)
                $changed = $true
            }
            'End' {
                $daysInMonth = [DateTime]::DaysInMonth($this._selectedDate.Year, $this._selectedDate.Month)
                $this._selectedDate = [DateTime]::new($this._selectedDate.Year, $this._selectedDate.Month, $daysInMonth)
                $changed = $true
            }
        }

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
            if ($input -eq 'today') { return [DateTime]::Today }
            if ($input -eq 'tomorrow') { return [DateTime]::Today.AddDays(1) }

            if ($input -match '^([+-]?\d+)$') {
                $days = [int]$Matches[1]
                return [DateTime]::Today.AddDays($days)
            }

            if ($input -eq 'eom') {
                $today = [DateTime]::Today
                $daysInMonth = [DateTime]::DaysInMonth($today.Year, $today.Month)
                return [DateTime]::new($today.Year, $today.Month, $daysInMonth)
            }

            if ($input -match '^next\s+(\w+)') {
                $dayName = $Matches[1]
                $targetDay = $this._ParseDayOfWeek($dayName)
                if ($targetDay -ne $null) {
                    $today = [DateTime]::Today
                    $daysUntil = (([int]$targetDay - [int]$today.DayOfWeek + 7) % 7)
                    if ($daysUntil -eq 0) { $daysUntil = 7 }
                    return $today.AddDays($daysUntil)
                }
            }

            $targetDay = $this._ParseDayOfWeek($input)
            if ($targetDay -ne $null) {
                $today = [DateTime]::Today
                $daysUntil = (([int]$targetDay - [int]$today.DayOfWeek + 7) % 7)
                if ($daysUntil -eq 0) { $daysUntil = 7 }
                return $today.AddDays($daysUntil)
            }

            if ($input -match '^\d{4}-\d{2}-\d{2}$') {
                $parsed = [DateTime]::ParseExact($input, 'yyyy-MM-dd', [CultureInfo]::InvariantCulture)
                return $parsed
            }

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