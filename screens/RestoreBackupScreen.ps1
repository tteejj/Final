using namespace System.Collections.Generic
using namespace System.Text

# RestoreBackupScreen - Confirm and restore from backup
# Shows backup details and asks for confirmation


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Backup restore confirmation screen

.DESCRIPTION
Shows selected backup details and asks for confirmation.
Supports:
- Viewing backup information
- Confirming restore (Y key)
- Canceling restore (N/Esc key)
#>
class RestoreBackupScreen : PmcScreen {
    # Data
    [object]$Backup = $null
    [string]$InputBuffer = ""
    [bool]$ShowConfirm = $true

    # Constructor
    RestoreBackupScreen() : base("RestoreBackup", "Restore Backup") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Backups", "Restore"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Y", "Confirm")
        $this.Footer.AddShortcut("N", "Cancel")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    RestoreBackupScreen([object]$backup) : base("RestoreBackup", "Restore Backup") {
        $this.Backup = $backup

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Backups", "Restore"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Y", "Confirm")
        $this.Footer.AddShortcut("N", "Cancel")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    RestoreBackupScreen([object]$backup, [object]$container) : base("RestoreBackup", "Restore Backup", $container) {
        $this.Backup = $backup

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Backups", "Restore"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Y", "Confirm")
        $this.Footer.AddShortcut("N", "Cancel")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    [void] LoadData() {
        if (-not $this.Backup) {
            $this.ShowError("No backup selected")
            return
        }

        # Validate backup file exists
        if (-not (Test-Path $this.Backup.Path)) {
            $this.ShowError("Backup file not found: $($this.Backup.Path)")
            return
        }

        $this.ShowStatus("Ready to restore backup")
    }

    [void] RenderContentToEngine([object]$engine) {
        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $warningColor = $this.Header.GetThemedColorInt('Foreground.Warning') 
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $y = 4
        $x = 4

        if (-not $this.Backup) {
            # No backup selected
            $engine.WriteAt($x, $y, "No backup selected", $warningColor, $bg)
            return
        }

        # Backup details
        $engine.WriteAt($x, $y, "Restore Backup Details:", $highlightColor, $bg)
        $y += 2

        $detailsX = $x + 2

        # Name
        $engine.WriteAt($detailsX, $y, "Name: ", $mutedColor, $bg)
        $engine.WriteAt($detailsX + 6, $y, $this.Backup.Name, $textColor, $bg)
        $y++

        # Type
        $engine.WriteAt($detailsX, $y, "Type: ", $mutedColor, $bg)
        $typeLabel = $(if ($this.Backup.Type -eq "auto") { "Automatic" } else { "Manual" })
        $engine.WriteAt($detailsX + 6, $y, $typeLabel, $textColor, $bg)
        $y++

        # Modified
        $engine.WriteAt($detailsX, $y, "Date: ", $mutedColor, $bg)
        $engine.WriteAt($detailsX + 6, $y, $this.Backup.Modified.ToString('yyyy-MM-dd HH:mm:ss'), $textColor, $bg)
        $y++

        # Size
        $engine.WriteAt($detailsX, $y, "Size: ", $mutedColor, $bg)
        $sizeKB = [math]::Round($this.Backup.Size / 1KB, 2)
        $engine.WriteAt($detailsX + 6, $y, "$sizeKB KB", $textColor, $bg)
        $y++

        # Path
        $engine.WriteAt($detailsX, $y, "Path: ", $mutedColor, $bg)
        $engine.WriteAt($detailsX + 6, $y, $this.Backup.Path, $mutedColor, $bg)
        $y += 2

        # Warning
        $engine.WriteAt($x, $y, "WARNING: This will overwrite your current data!", $warningColor, $bg)
        $y += 2

        # Confirmation prompt
        if ($this.ShowConfirm) {
            $engine.WriteAt($x, $y, "Press Y to confirm restore, N or Esc to cancel", $highlightColor, $bg)
        }
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyChar) {
            'y' {
                $this._ConfirmRestore()
                return $true
            }
            'n' {
                $this._Cancel()
                return $true
            }
        }

        return $false
    }

    hidden [void] _ConfirmRestore() {
        if (-not $this.Backup) {
            $this.ShowError("No backup selected")
            return
        }

        try {
            # Load backup data
            $data = Get-Content $this.Backup.Path -Raw | ConvertFrom-Json -Depth 10

            # Save as current data
            # FIX: Use Save-PmcData instead of Set-PmcAllData
            Save-PmcData -Data $data

            $this.ShowSuccess("Data restored successfully from $($this.Backup.Name)")

            # Return to backup list
            $global:PmcApp.PopScreen()
        }
        catch {
            $this.ShowError("Error restoring backup: $_")
        }
    }

    hidden [void] _Cancel() {
        $this.ShowStatus("Restore cancelled")
        $global:PmcApp.PopScreen()
    }
}

# Entry point function for compatibility
function Show-RestoreBackupScreen {
    param(
        [object]$App,
        [object]$Backup
    )

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object RestoreBackupScreen -ArgumentList $Backup
    $App.PushScreen($screen)
}