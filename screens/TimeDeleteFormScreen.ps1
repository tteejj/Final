using namespace System.Collections.Generic
using namespace System.Text

# TimeDeleteFormScreen - Delete time entry confirmation
# Shows entry details and asks for confirmation


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Time entry delete confirmation screen

.DESCRIPTION
Shows selected time entry details and asks for confirmation.
Supports:
- Viewing entry information
- Confirming delete (Y key)
- Canceling delete (N/Esc key)
#>
class TimeDeleteFormScreen : PmcScreen {
    # Data
    [object]$TimeEntry = $null

    # Backward compatible constructor
    TimeDeleteFormScreen() : base("TimeDeleteForm", "Delete Time Entry") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Time Entries", "Delete"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Y", "Confirm")
        $this.Footer.AddShortcut("N", "Cancel")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    # Container constructor
    TimeDeleteFormScreen([object]$container) : base("TimeDeleteForm", "Delete Time Entry", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Time Entries", "Delete"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Y", "Confirm")
        $this.Footer.AddShortcut("N", "Cancel")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    # Entry constructor (backward compatible)
    TimeDeleteFormScreen([object]$entry) : base("TimeDeleteForm", "Delete Time Entry") {
        $this.TimeEntry = $entry

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Time Entries", "Delete"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Y", "Confirm")
        $this.Footer.AddShortcut("N", "Cancel")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    [void] LoadData() {
        if (-not $this.TimeEntry) {
            $this.ShowError("No time entry selected")
            return
        }

        $this.ShowStatus("Ready to delete time entry")
    }

    [void] RenderContentToEngine([object]$engine) {
        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $warningColor = $this.Header.GetThemedColorInt('Foreground.Warning') 
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $errorColor = $this.Header.GetThemedColorInt('Foreground.Error')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $startX = 4
        $y = 4 # Start Y (Header is top)

        if (-not $this.TimeEntry) {
            # No entry selected
            $engine.WriteAt($startX, $y, "No time entry selected", $warningColor, $bg)
            return
        }

        # Entry details
        $engine.WriteAt($startX, $y, "Delete Time Entry:", $highlightColor, $bg)
        $y += 2

        $detailsX = $startX + 2

        # ID
        $entryId = $this.TimeEntry.id
        $engine.WriteAt($detailsX, $y, "ID: ", $mutedColor, $bg)
        $engine.WriteAt($detailsX + 4, $y, "$entryId", $textColor, $bg)
        $y++

        # Date
        $entryDate = $this.TimeEntry.date
        $rawDate = $(if ($entryDate) { $entryDate.ToString() } else { "" })
        $dateStr = $(if ($rawDate -eq 'today') {
                (Get-Date).ToString('yyyy-MM-dd')
            }
            elseif ($rawDate -eq 'tomorrow') {
                (Get-Date).AddDays(1).ToString('yyyy-MM-dd')
            }
            else {
                $rawDate
            })

        $engine.WriteAt($detailsX, $y, "Date: ", $mutedColor, $bg)
        $engine.WriteAt($detailsX + 6, $y, "$dateStr", $textColor, $bg)
        $y++

        # Project
        $entryProject = $this.TimeEntry.project
        $entryId1 = $this.TimeEntry.id1
        $projectStr = $(if ($entryProject) { $entryProject.ToString() } else { if ($entryId1) { "#$entryId1" } else { "" } })
        
        $engine.WriteAt($detailsX, $y, "Project: ", $mutedColor, $bg)
        $engine.WriteAt($detailsX + 9, $y, "$projectStr", $textColor, $bg)
        $y++

        # Hours
        $entryMinutes = $this.TimeEntry.minutes
        $hours = $(if ($entryMinutes) { [math]::Round($entryMinutes / 60.0, 2) } else { 0 })
        
        $engine.WriteAt($detailsX, $y, "Hours: ", $mutedColor, $bg)
        $engine.WriteAt($detailsX + 7, $y, $hours.ToString("0.00"), $highlightColor, $bg)
        $y++

        # Description
        $entryDescription = $this.TimeEntry.description
        if ($entryDescription) {
            $engine.WriteAt($detailsX, $y, "Description: ", $mutedColor, $bg)
            
            $descStr = $entryDescription.ToString()
            $maxDescWidth = $this.TermWidth - $detailsX - 15  # Avoid overflow
            if ($descStr.Length -gt $maxDescWidth) {
                $descStr = $descStr.Substring(0, $maxDescWidth - 3) + "..."
            }
            $engine.WriteAt($detailsX + 13, $y, "$descStr", $textColor, $bg)
            $y++
        }

        $y += 2

        # Warning
        $engine.WriteAt($startX, $y, "WARNING: This action cannot be undone!", $errorColor, $bg)
        $y += 2

        # Confirmation prompt
        $engine.WriteAt($startX, $y, "Press Y to confirm delete, N or Esc to cancel", $highlightColor, $bg)
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyChar) {
            'y' {
                $this._ConfirmDelete()
                return $true
            }
            'n' {
                $this._Cancel()
                return $true
            }
        }

        return $false
    }

    hidden [void] _ConfirmDelete() {
        if (-not $this.TimeEntry) {
            $this.ShowError("No time entry selected")
            return
        }

        try {
            # Load data
            $data = Get-PmcData

            # Remove entry
            $entryId = $this.TimeEntry.id
            $data.timelogs = @($data.timelogs | Where-Object { ($_.id) -ne $entryId })

            # Save
            # FIX: Use Save-PmcData instead of Set-PmcAllData
            Save-PmcData -Data $data

            $this.ShowSuccess("Time entry #$entryId deleted successfully")

            # Return to time list
            $global:PmcApp.PopScreen()
        }
        catch {
            $this.ShowError("Error deleting time entry: $_")
        }
    }

    hidden [void] _Cancel() {
        $this.ShowStatus("Delete cancelled")
        $global:PmcApp.PopScreen()
    }
}

# Entry point function for compatibility
function Show-TimeDeleteFormScreen {
    param(
        [object]$App,
        [object]$TimeEntry
    )

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object TimeDeleteFormScreen -ArgumentList $TimeEntry
    $App.PushScreen($screen)
}