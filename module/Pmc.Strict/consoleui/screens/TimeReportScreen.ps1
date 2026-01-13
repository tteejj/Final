using namespace System.Collections.Generic
using namespace System.Text

# TimeReportScreen - Time report summary
# Shows summary by project: total hours, task breakdown


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Time report summary screen

.DESCRIPTION
Shows time summary grouped by project.
Displays:
- Total hours per project
- Number of entries per project
- Overall total
No navigation, just view (read-only).
#>
class TimeReportScreen : PmcScreen {
    # Data
    [array]$ProjectSummaries = @()
    [int]$TotalMinutes = 0
    [double]$TotalHours = 0

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Time', 'Time Report', 'R', {
                . "$PSScriptRoot/TimeReportScreen.ps1"
                $global:PmcApp.PushScreen((New-Object -TypeName TimeReportScreen))
            }, 20)
    }

    # Constructor
    TimeReportScreen() : base("TimeReport", "Time Report") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Time Entries", "Report"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("W", "Weekly")
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Esc", "Back")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via static RegisterMenuItems()
        # Old pattern was adding duplicate/misplaced menu items
    }

    # Constructor with container (DI-enabled)
    TimeReportScreen([object]$container) : base("TimeReport", "Time Report", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Time Entries", "Report"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("W", "Weekly")
        $this.Footer.AddShortcut("R", "Refresh")
        $this.Footer.AddShortcut("Esc", "Back")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via static RegisterMenuItems()
        # Old pattern was adding duplicate/misplaced menu items
    }

    [void] OnEnter() {
        # Call parent to ensure proper lifecycle (sets IsActive, calls LoadData, executes OnEnterHandler)
        ([PmcScreen]$this).OnEnter()
    }

    [void] LoadData() {
        $this.ShowStatus("Loading time report...")

        try {
            # Use TaskStore singleton instead of loading from disk
            $timelogs = $this.Store.GetAllTimeLogs()

            # CRITICAL FIX: Add null check for GetAllTimeLogs()
            if ($null -eq $timelogs) {
                $timelogs = @()
            }

            # TS-M8 FIX: Add better feedback for empty state
            if ($timelogs.Count -eq 0) {
                $this.ProjectSummaries = @()
                $this.TotalMinutes = 0
                $this.TotalHours = 0
                # Enhanced feedback to guide user on what to do next
                $this.ShowStatus("No time entries found. Press 'T' to add time entries in Time Tracking screen.")
                # Write-PmcTuiLog "TimeReportScreen: No time entries found for report" "INFO"
                return
            }

            # TS-M7 FIX: Group by project ID if available, otherwise by name
            # Create grouping key for each entry: use id1 if present, otherwise project name
            $groupedData = @{}
            foreach ($log in $timelogs) {
                # Use Get-SafeProperty for all data access
                $id1     = Get-SafeProperty $log 'id1'
                $project = Get-SafeProperty $log 'project'

                # Determine grouping key (prefer ID over name)
                $groupKey = ''
                $projectDisplay = ''
                
                if ($id1) {
                    $groupKey = "ID:$id1"
                    $projectDisplay = if ($project) { "$project [#$id1]" } else { "#$id1" }
                }
                else {
                    $projectVal = if ($project) { $project } else { 'Unknown' }
                    $groupKey = "NAME:$projectVal"
                    $projectDisplay = $projectVal
                }

                # Initialize group if needed
                if (-not $groupedData.ContainsKey($groupKey)) {
                    $groupedData[$groupKey] = @{
                        DisplayName = $projectDisplay
                        Entries     = @()
                    }
                }

                $groupedData[$groupKey].Entries += $log
            }

            $this.ProjectSummaries = @()
            $this.TotalMinutes = 0
            # LOW FIX TS-L2: Accumulate hours to avoid redundant calculation
            $totalHoursAccumulated = 0.0

            foreach ($key in ($groupedData.Keys | Sort-Object)) {
                $group = $groupedData[$key]
                $minutes = ($group.Entries | Measure-Object -Property minutes -Sum).Sum
                $hours = [Math]::Round($minutes / 60.0, 2)
                $this.TotalMinutes += $minutes
                $totalHoursAccumulated += $hours

                $this.ProjectSummaries += [PSCustomObject]@{
                    Project    = $group.DisplayName
                    EntryCount = $group.Entries.Count
                    Minutes    = $minutes
                    Hours      = $hours
                }
            }

            # Use accumulated hours (sum of rounded values) instead of recalculating
            $this.TotalHours = $totalHoursAccumulated

            $this.ShowStatus("Report generated: $($this.ProjectSummaries.Count) projects, $($this.TotalHours) hours total")

        }
        catch {
            $this.ShowError("Failed to load time report: $_")
            $this.ProjectSummaries = @()
            $this.TotalMinutes = 0
            $this.TotalHours = 0
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
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        # Main message
        $message = "No time entries to report"
        $x = $contentRect.X + [Math]::Floor(($contentRect.Width - $message.Length) / 2)
        $y = $contentRect.Y + [Math]::Floor($contentRect.Height / 2) - 1
        $engine.WriteAt($x, $y, $message, $textColor, $bg)

        # Helpful guidance
        $hint = "Press 'T' to add time entries in Time Tracking screen"
        $hintX = $contentRect.X + [Math]::Floor(($contentRect.Width - $hint.Length) / 2)
        $engine.WriteAt($hintX, $y + 2, $hint, $mutedColor, $bg)
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

        # Title
        $engine.WriteAt($contentRect.X + 4, $y, "Time Summary by Project", $highlightColor, $bg)
        $y += 2

        # Column headers
        $headerY = $y
        $headers = "PROJECT                     ENTRIES  MINUTES      HOURS"
        $engine.WriteAt($contentRect.X + 4, $headerY, $headers, $headerColor, $bg)
        $y++

        # Separator line
        $sepLen = $contentRect.Width - 4
        $engine.WriteAt($contentRect.X + 2, $y, "-" * $sepLen, $mutedColor, $bg)
        $y++

        # Project rows
        $maxLines = $contentRect.Height - 8
        $displayCount = [Math]::Min($this.ProjectSummaries.Count, $maxLines)

        for ($i = 0; $i -lt $displayCount; $i++) {
            $summary = $this.ProjectSummaries[$i]

            $x = $contentRect.X + 4

            # Project name
            $projectName = $summary.Project
            if ($projectName.Length -gt 26) {
                $projectName = $projectName.Substring(0, 23) + "..."
            }
            $engine.WriteAt($x, $y, $projectName.PadRight(28), $textColor, $bg)
            $x += 28

            # Entry count
            $engine.WriteAt($x, $y, $summary.EntryCount.ToString().PadRight(9), $mutedColor, $bg)
            $x += 9

            # Minutes
            $engine.WriteAt($x, $y, $summary.Minutes.ToString().PadRight(13), $warningColor, $bg)
            $x += 13

            # Hours
            $engine.WriteAt($x, $y, $summary.Hours.ToString("0.00"), $successColor, $bg)

            $y++
        }

        # Separator line
        $y++
        $engine.WriteAt($contentRect.X + 2, $y, "-" * $sepLen, $mutedColor, $bg)
        $y++

        # Total row
        $x = $contentRect.X + 4
        
        $engine.WriteAt($x, $y, "TOTAL:".PadRight(28), $highlightColor, $bg)
        $x += 28

        # Total entries
        $totalEntries = ($this.ProjectSummaries | Measure-Object -Property EntryCount -Sum).Sum
        $engine.WriteAt($x, $y, $totalEntries.ToString().PadRight(9), $mutedColor, $bg)
        $x += 9

        # Total minutes
        $engine.WriteAt($x, $y, $this.TotalMinutes.ToString().PadRight(13), $warningColor, $bg)
        $x += 13

        # Total hours
        $engine.WriteAt($x, $y, $this.TotalHours.ToString("0.00"), $successColor, $bg)
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # CRITICAL: Call parent FIRST for MenuBar, F10, Alt+keys, content widgets
        $handled = ([PmcScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        # F10 - Menu
        if ($keyInfo.Key -eq ([ConsoleKey]::F10)) {
            if ($this.MenuBar) {
                $this.MenuBar.Activate()
                return $true
            }
        }

        # Escape - Go back
        if ($keyInfo.Key -eq ([ConsoleKey]::Escape)) {
            $global:PmcApp.PopScreen()
            return $true
        }

        # Ctrl+Q - Quit
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Control -and $keyInfo.Key -eq ([ConsoleKey]::Q)) {
            $global:PmcApp.Quit()
            return $true
        }

        # Refresh on R key
        if ($keyInfo.Key -eq ([ConsoleKey]::R)) {
            $this.LoadData()
            return $true
        }

        # Weekly report on W key
        if ($keyInfo.Key -eq ([ConsoleKey]::W)) {
            . "$PSScriptRoot/WeeklyTimeReportScreen.ps1"
            $screen = New-Object WeeklyTimeReportScreen
            $global:PmcApp.PushScreen($screen)
            return $true
        }

        return $false
    }
}

# Entry point function for compatibility
function Show-TimeReportScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object TimeReportScreen
    $App.PushScreen($screen)
}