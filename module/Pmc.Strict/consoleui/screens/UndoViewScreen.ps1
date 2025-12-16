using namespace System.Collections.Generic
using namespace System.Text

# UndoViewScreen - Undo last action
# Shows last action details and allows undoing


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Undo last action screen

.DESCRIPTION
Shows last action details.
Supports:
- Viewing last action
- Confirming undo (U key)
- Canceling (Esc key)
#>
class UndoViewScreen : PmcScreen {
    # Data
    [object]$UndoStatus = $null

    # Legacy constructor (backward compatible)
    UndoViewScreen() : base("UndoView", "Undo Last Action") {
        $this._InitializeScreen()
    }

    # Container constructor
    UndoViewScreen([object]$container) : base("UndoView", "Undo Last Action", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Undo"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("U", "Undo")
        $this.Footer.AddShortcut("Esc", "Cancel")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    [void] LoadData() {
        $this.ShowStatus("Loading undo status...")

        try {
            $this.UndoStatus = Get-PmcUndoStatus

            if ($this.UndoStatus.UndoAvailable) {
                $this.ShowStatus("Press U to undo last action")
            }
            else {
                $this.ShowStatus("No changes available to undo")
            }
        }
        catch {
            $this.ShowError("Failed to load undo status: $_")
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
        $title = " Undo Last Change "
        $titleX = $x + [Math]::Floor(($this.TermWidth - $x - $title.Length) / 2)
        # Simplify centering roughly
        $titleX = [Math]::Max($x, [Math]::Floor(($this.TermWidth - $title.Length) / 2))
        
        $engine.WriteAt($titleX, $y, $title, $highlightColor, $bg)
        $y += 2

        if ($null -eq $this.UndoStatus) {
            $engine.WriteAt($x, $y, "Error loading undo status", $warningColor, $bg)
        }
        elseif ($this.UndoStatus.UndoAvailable) {
            # Show undo stack info
            $engine.WriteAt($x, $y, "Undo stack has $($this.UndoStatus.UndoCount) change(s) available", $successColor, $bg)
            $y += 2

            # Show last action
            $engine.WriteAt($x, $y, "Last action: $($this.UndoStatus.LastAction)", $textColor, $bg)
            $y++

            $y += 2
            $engine.WriteAt($x, $y, "Press 'U' to undo the last change", $warningColor, $bg)
        }
        else {
            # No undo available
            $engine.WriteAt($x, $y, "No changes available to undo", $warningColor, $bg)
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
            'u' {
                if ($this.UndoStatus -and $this.UndoStatus.UndoAvailable) {
                    $this._PerformUndo()
                    return $true
                }
            }
        }

        return $false
    }

    hidden [void] _PerformUndo() {
        try {
            Invoke-PmcUndo
            $this.ShowSuccess("Undo successful")
            $this.App.PopScreen()
        }
        catch {
            $this.ShowError("Failed to undo: $_")
        }
    }
}

# Entry point function for compatibility
function Show-UndoViewScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object UndoViewScreen
    $App.PushScreen($screen)
}