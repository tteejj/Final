using namespace System.Collections.Generic
using namespace System.Text

# FocusStatusScreen - Show focus status
# Displays current focused project with task statistics


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Focus status display screen

.DESCRIPTION
Shows the current focused project or "No focus set".
Displays task count statistics for the focused project:
- Total active tasks
- Overdue tasks (if any)
Supports:
- Esc to exit
#>
class FocusStatusScreen : PmcScreen {
    # Data
    [string]$CurrentFocus = ""
    [int]$ActiveTaskCount = 0
    [int]$OverdueTaskCount = 0

    # Constructor
    FocusStatusScreen() : base("FocusStatus", "Focus Status") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Focus", "Status"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Esc", "Exit")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    # Constructor with container
    FocusStatusScreen([object]$container) : base("FocusStatus", "Focus Status", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Focus", "Status"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Esc", "Exit")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    [void] LoadData() {
        $this.ShowStatus("Loading focus status...")

        try {
            # Get PMC data
            $data = Get-PmcData

            # Get current focus
            $this.CurrentFocus = $(if ($data.PSObject.Properties['currentContext']) {
                    $data.currentContext
                }
                else {
                    'inbox'
                })

            # Count tasks if focus is set
            if ($this.CurrentFocus -and $this.CurrentFocus -ne 'inbox') {
                # Count active tasks
                $contextTasks = @($data.tasks | Where-Object {
                        $_.project -eq $this.CurrentFocus -and -not $_.completed
                    })
                $this.ActiveTaskCount = $contextTasks.Count

                # Count overdue tasks
                $today = (Get-Date).Date
                $this.OverdueTaskCount = @($contextTasks | Where-Object {
                        if (-not $_.due) { return $false }
                        try {
                            $dueDate = [DateTime]::Parse($_.due)
                            return ($dueDate.Date -lt $today)
                        }
                        catch {
                            return $false
                        }
                    }).Count
            }
            else {
                $this.ActiveTaskCount = 0
                $this.OverdueTaskCount = 0
            }

            $this.ShowStatus("Focus: $($this.CurrentFocus)")

        }
        catch {
            $this.ShowError("Failed to load focus status: $_")
            $this.CurrentFocus = ""
            $this.ActiveTaskCount = 0
            $this.OverdueTaskCount = 0
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
        
        # Center content vertically
        $y = 4 + [Math]::Floor(($this.TermHeight - 4) / 3)
        $x = 4

        # Show current focus
        $engine.WriteAt($x, $y, "Current Focus:", $mutedColor, $bg)
        $y++

        if ($this.CurrentFocus -eq 'inbox' -or -not $this.CurrentFocus) {
            $engine.WriteAt($x + 2, $y, "No focus set", $highlightColor, $bg)
        }
        else {
            $engine.WriteAt($x + 2, $y, $this.CurrentFocus, $highlightColor, $bg)
        }
        $y += 3

        # Show task statistics if focus is set
        if ($this.CurrentFocus -and $this.CurrentFocus -ne 'inbox') {
            $engine.WriteAt($x, $y, "Active Tasks:", $mutedColor, $bg)
            $engine.WriteAt($x + 14, $y, "$($this.ActiveTaskCount)", $textColor, $bg)
            $y += 2

            # Show overdue count if any
            if ($this.OverdueTaskCount -gt 0) {
                $engine.WriteAt($x, $y, "Overdue:", $warningColor, $bg)
                $engine.WriteAt($x + 9, $y, "$($this.OverdueTaskCount)", $warningColor, $bg)
                $y += 2
            }
        }

        # Show hint
        $y += 2
        $engine.WriteAt($x, $y, "Press Esc to exit", $mutedColor, $bg)
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # No special input handling needed
        # Esc is handled by base class
        return $false
    }
}

# Entry point function for compatibility
function Show-FocusStatusScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object FocusStatusScreen
    $App.PushScreen($screen)
}