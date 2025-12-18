using namespace System.Collections.Generic
using namespace System.Text

# TimerStatusScreen - View timer status
# Shows current timer status: running/stopped, task, elapsed time


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Timer status display screen

.DESCRIPTION
Shows current timer status.
Supports:
- Viewing timer status (running/stopped)
- Viewing elapsed time
- Stopping timer if running (S key)
- Exiting (Esc key)
#>
class TimerStatusScreen : PmcScreen {
    # Data
    [object]$TimerStatus = $null

    # Legacy constructor (backward compatible)
    TimerStatusScreen() : base("TimerStatus", "Timer Status") {
        $this._InitializeScreen()
    }

    # Container constructor
    TimerStatusScreen([object]$container) : base("TimerStatus", "Timer Status", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Timer", "Status"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("S", "Stop Timer")
        $this.Footer.AddShortcut("Esc", "Back")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    [void] LoadData() {
        $this.ShowStatus("Loading timer status...")

        try {
            $this.TimerStatus = Get-PmcTimerStatus

            if ($this.TimerStatus.Running) {
                $this.ShowStatus("Timer is running")
            }
            else {
                $this.ShowStatus("Timer is not running")
            }
        }
        catch {
            $this.ShowError("Failed to load timer status: $_")
            $this.TimerStatus = $null
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $successColor = $this.Header.GetThemedColorInt('Foreground.Success')
        $warningColor = $this.Header.GetThemedColorInt('Foreground.Warning') 
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $y = 4
        $x = 4

        # Title
        $title = " Timer Status "
        $titleX = $x + [Math]::Floor(($this.TermWidth - $x - $title.Length) / 2)
        $titleX = [Math]::Max($x, [Math]::Floor(($this.TermWidth - $title.Length) / 2))
        
        $engine.WriteAt($titleX, $y, $title, $highlightColor, $bg)
        $y += 2

        if ($null -eq $this.TimerStatus) {
            $engine.WriteAt($x, $y, "Error loading timer status", $warningColor, $bg)
        }
        elseif ($this.TimerStatus.Running) {
            # Show timer is running
            $engine.WriteAt($x, $y, "Timer is RUNNING", $successColor, $bg)
            $y += 2

            # Show details
            $engine.WriteAt($x, $y, "Started: $($this.TimerStatus.StartTime)", $textColor, $bg)
            $y++

            $engine.WriteAt($x, $y, "Elapsed: $($this.TimerStatus.Elapsed)h", $textColor, $bg)
            $y++

            if ($this.TimerStatus.Task) {
                $y++
                $engine.WriteAt($x, $y, "Task: $($this.TimerStatus.Task)", $textColor, $bg)
                $y++
            }

            if ($this.TimerStatus.Project) {
                $engine.WriteAt($x, $y, "Project: $($this.TimerStatus.Project)", $textColor, $bg)
                $y++
            }

            $y += 2
            $engine.WriteAt($x, $y, "Press 'S' to stop timer", $mutedColor, $bg)
        }
        else {
            # Timer not running
            $engine.WriteAt($x, $y, "Timer is not running", $warningColor, $bg)

            if ($this.TimerStatus.LastElapsed) {
                $y += 2
                $engine.WriteAt($x, $y, "Last session: $($this.TimerStatus.LastElapsed)h", $mutedColor, $bg)
            }
        }
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyInfo.Key) {
            'Escape' {
                $this.App.PopScreen()
                return $true
            }
        }

        switch ($keyChar) {
            's' {
                if ($this.TimerStatus -and $this.TimerStatus.Running) {
                    try {
                        Stop-PmcTimer
                        $this.ShowSuccess("Timer stopped")
                        $this.LoadData()
                        return $true
                    }
                    catch {
                        $this.ShowError("Failed to stop timer: $_")
                    }
                }
            }
        }

        return $false
    }
}

# Entry point function for compatibility
function Show-TimerStatusScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object TimerStatusScreen
    $App.PushScreen($screen)
}