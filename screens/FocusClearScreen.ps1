using namespace System.Collections.Generic
using namespace System.Text

# FocusClearScreen - Clear focus confirmation
# Shows current focus and asks for confirmation to clear


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Focus clear confirmation screen

.DESCRIPTION
Shows the current focus and prompts for confirmation to clear it.
The focus is reset to 'inbox' when cleared.
Supports:
- Y to confirm clear
- N/Esc to cancel
#>
class FocusClearScreen : PmcScreen {
    # Data
    [string]$CurrentFocus = ""
    [string]$InputBuffer = ""
    [bool]$InConfirm = $false

    # Constructor
    FocusClearScreen() : base("FocusClear", "Clear Focus") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Focus", "Clear"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Y", "Confirm")
        $this.Footer.AddShortcut("N/Esc", "Cancel")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    # Constructor with container
    FocusClearScreen([object]$container) : base("FocusClear", "Clear Focus", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Focus", "Clear"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Y", "Confirm")
        $this.Footer.AddShortcut("N/Esc", "Cancel")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    [void] LoadData() {
        $this.ShowStatus("Loading focus...")

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

            if ($this.CurrentFocus -eq 'inbox') {
                $this.ShowStatus("No focus set")
            }
            else {
                $this.ShowStatus("Focus: $($this.CurrentFocus)")
            }

        }
        catch {
            $this.ShowError("Failed to load focus: $_")
            $this.CurrentFocus = ""
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $warningColor = $this.Header.GetThemedColorInt('Foreground.Warning') 
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        # Center content vertically
        $y = 4 + [Math]::Floor(($this.TermHeight - 4) / 3)
        $x = 4

        # Show current focus
        $engine.WriteAt($x, $y, "Current focus: ", $textColor, $bg)
        $engine.WriteAt($x + 15, $y, $this.CurrentFocus, $highlightColor, $bg)
        $y += 3

        # Show confirmation prompt
        if ($this.CurrentFocus -eq 'inbox') {
            $engine.WriteAt($x, $y, "No focus is currently set.", $mutedColor, $bg)
            $y += 2
            $engine.WriteAt($x, $y, "Press Esc to return", $mutedColor, $bg)
        }
        else {
            $engine.WriteAt($x, $y, "Clear this focus and return to 'inbox'?", $warningColor, $bg)
            $y += 3

            $engine.WriteAt($x, $y, "Press Y to confirm, N or Esc to cancel", $textColor, $bg)
        }
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyChar) {
            'y' {
                if ($this.CurrentFocus -ne 'inbox') {
                    $this._ClearFocus()
                }
                return $true
            }
            'n' {
                $this.ShowStatus("Cancelled")
                Start-Sleep -Milliseconds 300
                $this.RequestDoExit()
                return $true
            }
        }

        return $false
    }

    hidden [void] _ClearFocus() {
        try {
            $data = Get-PmcData

            # Clear focus (set to inbox)
            if (-not $data.PSObject.Properties['currentContext']) {
                $data | Add-Member -NotePropertyName currentContext -NotePropertyValue 'inbox' -Force
            }
            else {
                $data.currentContext = 'inbox'
            }

            Save-PmcData -Data $data -Action "Cleared focus"

            $this.ShowSuccess("Focus cleared")

            # Exit screen
            Start-Sleep -Milliseconds 500
            $this.RequestDoExit()

        }
        catch {
            $this.ShowError("Failed to clear focus: $_")
        }
    }
}

# Entry point function for compatibility
function Show-FocusClearScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object FocusClearScreen
    $App.PushScreen($screen)
}