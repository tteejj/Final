using namespace System.Collections.Generic
using namespace System.Text

# WeeklyTimeReportScreen - Weekly time tracking report
# Shows time entries grouped by project with daily breakdown (Mon-Fri)
# Matches the old renderer's weekly report functionality


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Weekly time tracking report screen

.DESCRIPTION
Shows time summary grouped by project with daily breakdown.
Displays:
- Hours per day (Mon-Fri) for each project
- Total hours per project
- Grand total
- Week navigation (=/-keys)
Based on the old renderer's DrawWeeklyReport implementation.
#>
class WeeklyTimeReportScreen : PmcScreen {
    # Data
    [hashtable]$ProjectSummaries = @{}
    [double]$GrandTotal = 0
    [int]$WeekOffset = 0
    [DateTime]$WeekStart
    [DateTime]$WeekEnd
    [string]$WeekHeader = ""
    [string]$WeekIndicator = ""
    [TaskStore]$Store = $null

    # TS-M4/TS-M5 FIX: Make week days configurable
    # Set to 7 for full week (Mon-Sun), or 5 for business week (Mon-Fri)
    [int]$WeekDays = 7
    [bool]$IncludeWeekends = $true

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Time', 'Weekly Report', 'W', {
                . "$PSScriptRoot/WeeklyTimeReportScreen.ps1"
                $global:PmcApp.PushScreen((New-Object -TypeName WeeklyTimeReportScreen))
            }, 10)
    }

    # Constructor
    WeeklyTimeReportScreen() : base("WeeklyTimeReport", "Weekly Time Report") {
        # Initialize TaskStore
        $this.Store = [TaskStore]::GetInstance()

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Time Entries", "Weekly Report"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("=", "Next Week")
        $this.Footer.AddShortcut("-", "Prev Week")
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Esc", "Back")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via static RegisterMenuItems()
        # Old pattern was adding duplicate/misplaced menu items
    }

    # Constructor with container (DI-enabled)
    WeeklyTimeReportScreen([object]$container) : base("WeeklyTimeReport", "Weekly Time Report", $container) {
        # Initialize TaskStore
        $this.Store = [TaskStore]::GetInstance()

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Time Entries", "Weekly Report"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("=", "Next Week")
        $this.Footer.AddShortcut("-", "Prev Week")
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Esc", "Back")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via static RegisterMenuItems()
        # Old pattern was adding duplicate/misplaced menu items
    }

    # OnEnter - Load data when screen becomes active (consistent with other screens)
    [void] OnEnter() {
        # Call parent to ensure proper lifecycle (sets IsActive, calls LoadData, executes OnEnterHandler)
        ([PmcScreen]$this).OnEnter()
    }

    [void] LoadData() {
        $this.ShowStatus("Loading weekly time report...")

        try {
            # Calculate week start (Monday) and end (Friday or Sunday based on config)
            $today = Get-Date
            $daysFromMonday = ($today.DayOfWeek.value__ + 6) % 7
            $thisMonday = $today.AddDays(-$daysFromMonday).Date
            $this.WeekStart = $thisMonday.AddDays($this.WeekOffset * 7)
            # TS-M4/TS-M5 FIX: Week end depends on configured week length
            $this.WeekEnd = $this.WeekStart.AddDays($this.WeekDays - 1)

            # Format week header
            $this.WeekHeader = "Week of {0} - {1}" -f $this.WeekStart.ToString('MMM dd'), $this.WeekEnd.ToString('MMM dd, yyyy')

            # Add indicator for current/past/future week
            if ($this.WeekOffset -eq 0) {
                $this.WeekIndicator = ' (This Week)'
            }
            elseif ($this.WeekOffset -lt 0) {
                $weeks = [Math]::Abs($this.WeekOffset)
                $plural = $(if ($weeks -gt 1) { 's' } else { '' })
                $this.WeekIndicator = " ($weeks week$plural ago)"
            }
            else {
                $plural = $(if ($this.WeekOffset -gt 1) { 's' } else { '' })
                $this.WeekIndicator = " ($($this.WeekOffset) week$plural from now)"
            }

            # Use TaskStore singleton instead of loading from disk
            $logs = $this.Store.GetAllTimeLogs()

            # TS-M4/TS-M5 FIX: Filter logs for the week (configurable: Mon-Fri or Mon-Sun)
            $weekLogs = @()
            for ($d = 0; $d -lt $this.WeekDays; $d++) {
                $dayDate = $this.WeekStart.AddDays($d).ToString('yyyy-MM-dd')
                $dayLogs = $logs | Where-Object {
                    $dateStr = $(if ($_.date -is [DateTime]) {
                            $_.date.ToString('yyyy-MM-dd')
                        }
                        else {
                            $_.date
                        })
                    $dateStr -eq $dayDate
                }
                $weekLogs += $dayLogs
            }

            # Group by project/id1
            $this.ProjectSummaries = @{}
            $this.GrandTotal = 0

            foreach ($log in $weekLogs) {
                # Determine grouping key
                $key = ''
                if ($log.ContainsKey('id1') -and $log.id1) {
                    $key = "#$($log.id1)"
                }
                else {
                    $name = $(if ($log.ContainsKey('project')) { $log.project } else { '' })
                    if (-not $name) { $name = 'Unknown' }
                    $key = $name
                }

                # Initialize project entry if needed
                if (-not $this.ProjectSummaries.ContainsKey($key)) {
                    $name = ''
                    $id1 = ''
                    if ($log.ContainsKey('id1') -and $log.id1) {
                        $id1 = $log.id1
                        $name = $(if ($log.ContainsKey('project')) { $log.project } else { '' })
                        if (-not $name) { $name = '' }
                    }
                    else {
                        $name = $(if ($log.ContainsKey('project')) { $log.project } else { '' })
                        if (-not $name) { $name = 'Unknown' }
                    }

                    # TS-M4/TS-M5 FIX: Include Sat/Sun columns
                    $this.ProjectSummaries[$key] = @{
                        Name  = $name
                        ID1   = $id1
                        Mon   = 0.0
                        Tue   = 0.0
                        Wed   = 0.0
                        Thu   = 0.0
                        Fri   = 0.0
                        Sat   = 0.0
                        Sun   = 0.0
                        Total = 0.0
                    }
                }

                # Add hours to appropriate day
                # TS-H3 FIX: Add error handling for unsafe DateTime cast
                if (-not $log.ContainsKey('date')) {
                    # Write-PmcTuiLog "WeeklyTimeReportScreen: Log entry missing date field" "WARNING"
                    continue
                }
                $logDate = $null
                try {
                    $logDate = $(if ($log.date -is [DateTime]) {
                            $log.date
                        }
                        else {
                            [datetime]::Parse($log.date)
                        })
                }
                catch {
                    # Write-PmcTuiLog "WeeklyTimeReportScreen: Failed to parse date '$($log.date)': $_" "WARNING"
                    continue  # Skip this log entry
                }

                if (-not $log.ContainsKey('minutes')) {
                    # Write-PmcTuiLog "WeeklyTimeReportScreen: Log entry missing minutes field" "WARNING"
                    continue
                }
                $dayIndex = ($logDate.DayOfWeek.value__ + 6) % 7  # 0=Mon, 1=Tue, ..., 5=Sat, 6=Sun
                $hours = [Math]::Round($log.minutes / 60.0, 1)

                # TS-M4/TS-M5 FIX: Handle all 7 days including Saturday and Sunday
                switch ($dayIndex) {
                    0 { $this.ProjectSummaries[$key].Mon += $hours }
                    1 { $this.ProjectSummaries[$key].Tue += $hours }
                    2 { $this.ProjectSummaries[$key].Wed += $hours }
                    3 { $this.ProjectSummaries[$key].Thu += $hours }
                    4 { $this.ProjectSummaries[$key].Fri += $hours }
                    5 { $this.ProjectSummaries[$key].Sat += $hours }
                    6 { $this.ProjectSummaries[$key].Sun += $hours }
                    default {
                        # Write-PmcTuiLog "WeeklyTimeReportScreen: Unexpected day index $dayIndex" "WARNING"
                    }
                }
                $this.ProjectSummaries[$key].Total += $hours
                $this.GrandTotal += $hours
            }

            # Update status
            if ($weekLogs.Count -eq 0) {
                $this.ShowStatus("No time entries for this week")
            }
            else {
                $this.ShowStatus("$($this.ProjectSummaries.Count) projects, $($this.GrandTotal.ToString('0.0')) hours total")
            }

        }
        catch {
            $this.ShowError("Failed to load weekly time report: $_")
            $this.ProjectSummaries = @{}
            $this.GrandTotal = 0
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        if (-not $this.LayoutManager) { return }

        if ($this.ProjectSummaries.Count -eq 0) {
            $this._RenderEmptyStateToEngine($engine)
        }
        else {
            $this._RenderReportToEngine($engine)
        }
    }
    
    [string] RenderContent() { return "" }

    hidden [void] _RenderEmptyStateToEngine([object]$engine) {
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        # Week header
        $y = $contentRect.Y + 2
        
        $headerText = "$($this.WeekHeader)$($this.WeekIndicator)"
        $engine.WriteAt($contentRect.X + 4, $y, $headerText, $highlightColor, $bg)
        $y += 2

        # No entries message
        $message = "No time entries for this week"
        $engine.WriteAt($contentRect.X + 4, $y, $message, $textColor, $bg)
    }

    hidden [void] _RenderReportToEngine([object]$engine) {
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $successColor = $this.Header.GetThemedColorInt('Foreground.Success')
        $warningColor = $this.Header.GetThemedColorInt('Warning')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $y = $contentRect.Y + 1

        # Week header
        $headerText = "$($this.WeekHeader)$($this.WeekIndicator)"
        $engine.WriteAt($contentRect.X + 4, $y, $headerText, $highlightColor, $bg)
        $y += 2

        # Column headers
        $headerY = $y
        $headers = ""
        if ($this.IncludeWeekends) {
            $headers = "Name                 ID1   Mon    Tue    Wed    Thu    Fri    Sat    Sun    Total"
        }
        else {
            $headers = "Name                 ID1   Mon    Tue    Wed    Thu    Fri    Total"
        }
        $engine.WriteAt($contentRect.X + 4, $headerY, $headers, $headerColor, $bg)
        $y++

        # Separator line
        $sepLen = if ($this.IncludeWeekends) { 89 } else { 75 }
        $engine.WriteAt($contentRect.X + 4, $y, "-" * $sepLen, $mutedColor, $bg)
        $y++

        # Project rows - sorted by key
        $sortedProjects = $this.ProjectSummaries.GetEnumerator() | Sort-Object Key

        foreach ($entry in $sortedProjects) {
            $d = $entry.Value
            
            $x = $contentRect.X + 4

            # Name (20 chars, left-aligned)
            $name = $d.Name
            if ($name.Length -gt 20) {
                $name = $name.Substring(0, 17) + "..."
            }
            $engine.WriteAt($x, $y, $name.PadRight(20), $textColor, $bg)
            $x += 21 # 20 + 1 space

            # ID1 (5 chars, left-aligned)
            $id1Display = "$($d.ID1)"
            if ($id1Display.Length -gt 5) {
                $id1Display = $id1Display.Substring(0, 5)
            }
            $engine.WriteAt($x, $y, $id1Display.PadRight(5), $textColor, $bg)
            $x += 6 # 5 + 1 space

            # Day columns (6 chars each, right-aligned with 1 decimal)
            $days = @($d.Mon, $d.Tue, $d.Wed, $d.Thu, $d.Fri)
            if ($this.IncludeWeekends) { 
                $days += $d.Sat
                $days += $d.Sun 
            }
            
            foreach ($dayVal in $days) {
                $engine.WriteAt($x, $y, $dayVal.ToString("0.0").PadLeft(6), $successColor, $bg)
                $x += 7 # 6 + 1 space
            }

            # Total (8 chars, right-aligned with 1 decimal)
            $engine.WriteAt($x, $y, $d.Total.ToString("0.0").PadLeft(8), $warningColor, $bg)
            
            $y++
        }

        # Footer separator
        $y++
        $engine.WriteAt($contentRect.X + 4, $y, "-" * $sepLen, $mutedColor, $bg)
        $y++

        # Total row
        $x = $contentRect.X + 4
        $padding = if ($this.IncludeWeekends) { 72 } else { 58 }
        $x += $padding
        
        $engine.WriteAt($x, $y, "Total: ", $highlightColor, $bg)
        $x += 7
        
        $engine.WriteAt($x, $y, $this.GrandTotal.ToString("0.0").PadLeft(8), $highlightColor, $bg)
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # CRITICAL: Call parent FIRST for MenuBar, F10, Alt+keys, content widgets
        $handled = ([PmcScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        # Week navigation with arrow keys
        if ($keyInfo.Key -eq 'LeftArrow') {
            $this.WeekOffset--
            $this.NeedsClear = $true  # Force full screen clear to prevent duplication
            $this.LoadData()
            return $true
        }

        if ($keyInfo.Key -eq 'RightArrow') {
            $this.WeekOffset++
            $this.NeedsClear = $true  # Force full screen clear to prevent duplication
            $this.LoadData()
            return $true
        }

        # Week navigation with = and - keys
        if ($keyInfo.KeyChar -eq '=') {
            $this.WeekOffset++
            $this.NeedsClear = $true  # Force full screen clear to prevent duplication
            $this.LoadData()
            return $true
        }

        if ($keyInfo.KeyChar -eq '-') {
            $this.WeekOffset--
            $this.NeedsClear = $true  # Force full screen clear to prevent duplication
            $this.LoadData()
            return $true
        }

        # Refresh
        if ($keyInfo.KeyChar -eq 'r' -or $keyInfo.KeyChar -eq 'R') {
            $this.LoadData()
            return $true
        }

        return $false
    }
}

# Entry point function for compatibility
function Show-WeeklyTimeReportScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object WeeklyTimeReportScreen
    $App.PushScreen($screen)
}