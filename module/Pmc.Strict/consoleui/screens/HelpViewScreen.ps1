using namespace System.Collections.Generic
using namespace System.Text

# HelpViewScreen - PMC TUI Help documentation
# Static help screen showing keyboard shortcuts and commands


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Help screen showing PMC TUI keyboard shortcuts and commands

.DESCRIPTION
Static help documentation screen showing:
- Global keyboard shortcuts
- Task list commands
- Multi-select mode keys
- Quick add syntax
- Feature overview
No navigation needed, just Esc to exit.
#>
class HelpViewScreen : PmcScreen {
    HelpViewScreen() : base('Help', 'Help') {
    }



    # === Layout System ===

    [void] Resize([int]$width, [int]$height) {
        $this.TermWidth = $width
        $this.TermHeight = $height
        
        # Resize standard components
        if ($this.MenuBar) { $this.MenuBar.SetSize($width, 1) }
        if ($this.Header) { $this.Header.SetSize($width, 3) }
        if ($this.Footer) { 
            $this.Footer.SetPosition(0, $height - 1)
            $this.Footer.SetSize($width, 1)
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        if (-not $this.LayoutManager) { return }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)
        $engine.BeginLayer([ZIndex]::Content)

        # Colors (Ints)
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        $y = $contentRect.Y
        $indent = $contentRect.X + 4
        $subIndent = $contentRect.X + 6

        # Helper to simplify writing lines
        $writeLine = {
            param($x, $text, $color)
            $engine.WriteAt($x, $y, $text, $color, $bg)
            # Access variable from parent scope using Get-Variable or assume scope inherited in scriptblock
        }

        # Global Keys
        $engine.WriteAt($indent, $y, "Global Keys:", $headerColor, $bg)
        $y++

        $globalKeys = @(
            "?         - Show this help screen"
            "F10       - Open menu bar"
            "Esc       - Back / Close menus / Exit"
            "R         - Refresh current view"
            "F         - Filter panel (when available)"
            "Alt+X     - Quick exit PMC"
            "Alt+T     - Open task list"
            "Alt+A     - Add new task"
            "Alt+P     - Project list"
        )
        foreach ($line in $globalKeys) {
            $engine.WriteAt($subIndent, $y, $line, $textColor, $bg)
            $y++
        }
        $y++

        # Task List Keys
        $engine.WriteAt($indent, $y, "Task List Keys:", $headerColor, $bg)
        $y++

        $taskKeys = @(
            "Up/Down   - Navigate tasks"
            "PgUp/PgDn - Scroll page"
            "Enter     - View task details"
            "A         - Add new task"
            "E         - Edit task"
            "C         - Complete task"
            "D         - Delete task"
            "X         - Clone task"
            "S         - Add subtask to selected"
            "H         - Toggle show completed"
            "Tab       - Next field (when editing)"
            "/         - Search tasks"
            "1-6       - View filters (All, Active, Completed, Overdue, Today, Week)"
        )
        foreach ($line in $taskKeys) {
            $engine.WriteAt($subIndent, $y, $line, $textColor, $bg)
            $y++
        }
        $y++

        # Multi-Select Mode
        if ($y -lt $contentRect.Y + $contentRect.Height - 10) {
            $engine.WriteAt($indent, $y, "Multi-Select Mode:", $headerColor, $bg)
            $y++

            $multiKeys = @(
                "Space     - Toggle task selection"
                "A         - Select all visible tasks"
                "N         - Clear all selections"
                "D         - Complete selected tasks"
                "X         - Delete selected tasks"
            )
            foreach ($line in $multiKeys) {
                $engine.WriteAt($subIndent, $y, $line, $textColor, $bg)
                $y++
            }
            $y++
        }

        # Project List Keys
        if ($y -lt $contentRect.Y + $contentRect.Height - 12) {
            $engine.WriteAt($indent, $y, "Project List Keys:", $headerColor, $bg)
            $y++

            $projectKeys = @(
                "A         - Add new project"
                "E         - Edit project"
                "D         - Delete project"
                "R         - Archive/Unarchive project"
                "V         - View project details"
            )
            foreach ($line in $projectKeys) {
                $engine.WriteAt($subIndent, $y, $line, $textColor, $bg)
                $y++
            }
            $y++
        }

        # Time Tracking Keys
        if ($y -lt $contentRect.Y + $contentRect.Height - 10) {
            $engine.WriteAt($indent, $y, "Time Tracking Keys:", $headerColor, $bg)
            $y++

            $timeKeys = @(
                "A         - Add time entry"
                "E         - Edit time entry"
                "D         - Delete time entry"
                "Enter     - View entry details"
                "W         - Weekly time report"
                "G         - Generate time report"
                "Arrows    - Navigate weeks (in week view)"
            )
            foreach ($line in $timeKeys) {
                $engine.WriteAt($subIndent, $y, $line, $textColor, $bg)
                $y++
            }
            $y++
        }

        # Quick Add Syntax
        if ($y -lt $contentRect.Y + $contentRect.Height - 8) {
            $engine.WriteAt($indent, $y, "Quick Add Syntax:", $headerColor, $bg)
            $y++

            $quickAdd = @(
                "@project  - Set project (e.g., 'Fix bug @work')"
                "#priority - Set priority: #high #medium #low or #h #m #l"
                "!due      - Set due date: !today !tomorrow !+7 (days)"
            )
            foreach ($line in $quickAdd) {
                $engine.WriteAt($subIndent, $y, $line, $mutedColor, $bg)
                $y++
            }
            $y++
        }
    }
    
    [string] RenderContent() { return "" }
    
    # Remove old RenderToEngine that used ParseAnsi

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # Let MenuBar handle its keys first (F10, menu navigation, etc.)
        if ($null -ne $this.MenuBar -and $this.MenuBar.HandleKeyPress($keyInfo)) {
            return $true
        }

        # All other keys are ignored on help screen
        return $false
    }

    hidden [void] _ShowAbout() {
        $this.ShowStatus("PMC TUI v1.0 - Project Management Console")
    }

    hidden [void] _ShowVersion() {
        $this.ShowStatus("Version 1.0.0")
    }
}

# Entry point function for compatibility
function Show-HelpViewScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object HelpViewScreen
    $App.PushScreen($screen)
}