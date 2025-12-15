using namespace System.Collections.Generic
using namespace System.Text

# TimerStopScreen - Stop running timer
# Shows current timer info and allows stopping/logging time


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Stop timer screen with confirmation

.DESCRIPTION
Shows current running timer information.
Supports:
- Viewing timer status (running/stopped)
- Stopping timer and logging time (S key)
- Canceling (Esc key)
#>
class TimerStopScreen : PmcScreen {
    # Data
    [object]$TimerStatus = $null
    [bool]$IsConfirming = $false

    # Legacy constructor (backward compatible)
    TimerStopScreen() : base("TimerStop", "Stop Timer") {
        $this._InitializeScreen()
    }

    # Container constructor
    TimerStopScreen([object]$container) : base("TimerStop", "Stop Timer", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Timer", "Stop"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("S", "Stop & Log")
        $this.Footer.AddShortcut("Esc", "Cancel")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    [void] LoadData() {
        $this.ShowStatus("Loading timer status...")

        try {
            $this.TimerStatus = Get-PmcTimerStatus

            if ($this.TimerStatus.Running) {
                $this.ShowStatus("Timer is running - Press S to stop and log time")
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
        $title = " Stop Timer "
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
            $engine.WriteAt($x, $y, "Press 'S' to stop and log this time", $warningColor, $bg)
        }
        else {
            # Timer not running
            $engine.WriteAt($x, $y, "Timer is not running", $warningColor, $bg)
            $y += 2

            $engine.WriteAt($x, $y, "There is nothing to stop.", $mutedColor, $bg)
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
                    $this._StopTimer()
                    return $true
                }
            }
        }

        return $false
    }

    hidden [void] _StopTimer() {
        try {
            Stop-PmcTimer
            $this.ShowSuccess("Timer stopped and time logged")
            $this.App.PopScreen()
        }
        catch {
            $this.ShowError("Failed to stop timer: $_")
        }
    }
}

# Entry point function for compatibility
function Show-TimerStopScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object TimerStopScreen
    $App.PushScreen($screen)
}