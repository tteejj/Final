using namespace System.Collections.Generic
using namespace System.Text

# RedoViewScreen - Redo last undone action
# Shows last undone action and allows redoing


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Redo last undone action screen

.DESCRIPTION
Shows last undone action details.
Supports:
- Viewing redo stack
- Confirming redo (R key)
- Canceling (Esc key)
#>
class RedoViewScreen : PmcScreen {
    # Data
    [object]$UndoStatus = $null

    # Legacy constructor (backward compatible)
    RedoViewScreen() : base("RedoView", "Redo Last Action") {
        $this._InitializeScreen()
    }

    # Container constructor
    RedoViewScreen([object]$container) : base("RedoView", "Redo Last Action", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Redo"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("R", "Redo")
        $this.Footer.AddShortcut("Esc", "Cancel")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    [void] LoadData() {
        $this.ShowStatus("Loading redo status...")

        try {
            $this.UndoStatus = Get-PmcUndoStatus

            if ($this.UndoStatus.RedoAvailable) {
                $this.ShowStatus("Press R to redo last undone action")
            }
            else {
                $this.ShowStatus("No changes available to redo")
            }
        }
        catch {
            $this.ShowError("Failed to load redo status: $_")
            $this.UndoStatus = $null
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
        $title = " Redo Last Undone Change "
        $titleX = $x + [Math]::Floor(($this.TermWidth - $x - $title.Length) / 2)
        $titleX = [Math]::Max($x, [Math]::Floor(($this.TermWidth - $title.Length) / 2))
        
        $engine.WriteAt($titleX, $y, $title, $highlightColor, $bg)
        $y += 2

        if ($null -eq $this.UndoStatus) {
            $engine.WriteAt($x, $y, "Error loading redo status", $warningColor, $bg)
        }
        elseif ($this.UndoStatus.RedoAvailable) {
            # Show redo stack info
            $engine.WriteAt($x, $y, "Redo stack has $($this.UndoStatus.RedoCount) change(s) available", $successColor, $bg)
            $y += 2

            $engine.WriteAt($x, $y, "Press 'R' to redo the last undone change", $warningColor, $bg)
        }
        else {
            # No redo available
            $engine.WriteAt($x, $y, "No changes available to redo", $warningColor, $bg)
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
            'r' {
                if ($this.UndoStatus -and $this.UndoStatus.RedoAvailable) {
                    $this._PerformRedo()
                    return $true
                }
            }
        }

        return $false
    }

    hidden [void] _PerformRedo() {
        try {
            Invoke-PmcRedo
            $this.ShowSuccess("Redo successful")
            $this.App.PopScreen()
        }
        catch {
            $this.ShowError("Failed to redo: $_")
        }
    }
}

# Entry point function for compatibility
function Show-RedoViewScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object RedoViewScreen
    $App.PushScreen($screen)
}