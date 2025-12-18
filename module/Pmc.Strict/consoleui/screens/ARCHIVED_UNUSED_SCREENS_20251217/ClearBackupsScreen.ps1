using namespace System.Collections.Generic
using namespace System.Text

# ClearBackupsScreen - Clear all backup files
# Shows count of backups and asks for confirmation


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Clear backups confirmation screen

.DESCRIPTION
Shows count of automatic and manual backups and asks for confirmation.
Supports:
- Confirming delete all (Y key)
- Canceling (N/Esc key)
#>
class ClearBackupsScreen : PmcScreen {
    # Data
    [int]$AutoBackupCount = 0
    [int]$ManualBackupCount = 0
    [long]$AutoTotalSize = 0
    [long]$ManualTotalSize = 0
    [string]$BackupDir = ""
    [string]$MainFile = ""

    # Constructor
    ClearBackupsScreen() : base("ClearBackups", "Clear All Backups") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Backups", "Clear All"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("A", "Auto Only")
        $this.Footer.AddShortcut("M", "Manual Only")
        $this.Footer.AddShortcut("B", "Both")
        $this.Footer.AddShortcut("Esc", "Cancel")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    ClearBackupsScreen([object]$container) : base("ClearBackups", "Clear All Backups", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Backups", "Clear All"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("A", "Auto Only")
        $this.Footer.AddShortcut("M", "Manual Only")
        $this.Footer.AddShortcut("B", "Both")
        $this.Footer.AddShortcut("Esc", "Cancel")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    [void] LoadData() {
        $this.ShowStatus("Loading backup information...")

        try {
            $this.MainFile = Get-PmcTaskFilePath
            $this.BackupDir = Join-Path (Get-PmcRootPath) "backups"

            # Count automatic backups
            $this.AutoBackupCount = 0
            $this.AutoTotalSize = 0
            for ($i = 1; $i -le 9; $i++) {
                $bakFile = "$($this.MainFile).bak$i"
                if (Test-Path $bakFile) {
                    $this.AutoBackupCount++
                    $this.AutoTotalSize += (Get-Item $bakFile).Length
                }
            }

            # Count manual backups
            $this.ManualBackupCount = 0
            $this.ManualTotalSize = 0
            if (Test-Path $this.BackupDir) {
                $manualBackups = @(Get-ChildItem $this.BackupDir -Filter "*.json")
                $this.ManualBackupCount = $manualBackups.Count
                if ($manualBackups.Count -gt 0) {
                    $this.ManualTotalSize = ($manualBackups | Measure-Object -Property Length -Sum).Sum
                }
            }

            $totalCount = $this.AutoBackupCount + $this.ManualBackupCount
            $this.ShowStatus("$totalCount total backups found")

        }
        catch {
            $this.ShowError("Failed to load backup information: $_")
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $warningColor = $this.Header.GetThemedColorInt('Foreground.Warning') 
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $errorColor = $this.Header.GetThemedColorInt('Foreground.Error')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $y = 4
        $x = 4

        # Title
        $engine.WriteAt($x, $y, "Clear Backup Files", $highlightColor, $bg)
        $y += 2

        # Automatic backups section
        $engine.WriteAt($x, $y, "Automatic backups (.bak1 - .bak9):", $mutedColor, $bg)
        $y++

        $engine.WriteAt($x + 2, $y, "Count: $($this.AutoBackupCount) files", $textColor, $bg)
        $y++

        $autoSizeMB = [math]::Round($this.AutoTotalSize / 1MB, 2)
        $engine.WriteAt($x + 2, $y, "Total size: $autoSizeMB MB", $textColor, $bg)
        $y += 2

        # Manual backups section
        $engine.WriteAt($x, $y, "Manual backups (backups directory):", $mutedColor, $bg)
        $y++

        $engine.WriteAt($x + 2, $y, "Count: $($this.ManualBackupCount) files", $textColor, $bg)
        $y++

        $manualSizeMB = [math]::Round($this.ManualTotalSize / 1MB, 2)
        $engine.WriteAt($x + 2, $y, "Total size: $manualSizeMB MB", $textColor, $bg)
        $y += 2

        # Warning
        $engine.WriteAt($x, $y, "WARNING: This action cannot be undone!", $errorColor, $bg)
        $y += 2

        # Options
        if ($this.AutoBackupCount -gt 0) {
            $engine.WriteAt($x, $y, "Press 'A' to clear automatic backups (.bak files)", $warningColor, $bg)
            $y++
        }

        if ($this.ManualBackupCount -gt 0) {
            $engine.WriteAt($x, $y, "Press 'M' to clear manual backups (backups directory)", $warningColor, $bg)
            $y++
        }

        if ($this.AutoBackupCount -gt 0 -and $this.ManualBackupCount -gt 0) {
            $engine.WriteAt($x, $y, "Press 'B' to clear BOTH", $errorColor, $bg)
            $y++
        }

        if ($this.AutoBackupCount -eq 0 -and $this.ManualBackupCount -eq 0) {
            $y++
            $engine.WriteAt($x, $y, "No backups to clear", $mutedColor, $bg)
        }
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyChar) {
            'a' {
                $this._ClearAutoBackups()
                return $true
            }
            'm' {
                $this._ClearManualBackups()
                return $true
            }
            'b' {
                $this._ClearBothBackups()
                return $true
            }
            'n' {
                $this._Cancel()
                return $true
            }
        }

        return $false
    }

    hidden [void] _ClearAutoBackups() {
        if ($this.AutoBackupCount -eq 0) {
            $this.ShowStatus("No automatic backups to clear")
            return
        }

        try {
            $deleted = 0
            for ($i = 1; $i -le 9; $i++) {
                $bakFile = "$($this.MainFile).bak$i"
                if (Test-Path $bakFile) {
                    Remove-Item $bakFile -Force -ErrorAction Stop
                    $deleted++
                }
            }

            $this.ShowSuccess("Deleted $deleted automatic backup files")
            $this.LoadData()
        }
        catch {
            $this.ShowError("Error clearing automatic backups: $_")
        }
    }

    hidden [void] _ClearManualBackups() {
        if ($this.ManualBackupCount -eq 0) {
            $this.ShowStatus("No manual backups to clear")
            return
        }

        try {
            if (Test-Path $this.BackupDir) {
                $files = Get-ChildItem $this.BackupDir -Filter "*.json"
                $deleted = 0
                foreach ($file in $files) {
                    Remove-Item $file.FullName -Force -ErrorAction Stop
                    $deleted++
                }

                $this.ShowSuccess("Deleted $deleted manual backup files")
                $this.LoadData()
            }
        }
        catch {
            $this.ShowError("Error clearing manual backups: $_")
        }
    }

    hidden [void] _ClearBothBackups() {
        if ($this.AutoBackupCount -eq 0 -and $this.ManualBackupCount -eq 0) {
            $this.ShowStatus("No backups to clear")
            return
        }

        try {
            $totalDeleted = 0

            # Clear automatic backups
            for ($i = 1; $i -le 9; $i++) {
                $bakFile = "$($this.MainFile).bak$i"
                if (Test-Path $bakFile) {
                    Remove-Item $bakFile -Force -ErrorAction Stop
                    $totalDeleted++
                }
            }

            # Clear manual backups
            if (Test-Path $this.BackupDir) {
                $files = Get-ChildItem $this.BackupDir -Filter "*.json"
                foreach ($file in $files) {
                    Remove-Item $file.FullName -Force -ErrorAction Stop
                    $totalDeleted++
                }
            }

            $this.ShowSuccess("Deleted $totalDeleted backup files")
            $this.LoadData()
        }
        catch {
            $this.ShowError("Error clearing backups: $_")
        }
    }

    hidden [void] _Cancel() {
        $this.ShowStatus("Clear cancelled")
        $global:PmcApp.PopScreen()
    }
}

# Entry point function for compatibility
function Show-ClearBackupsScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object ClearBackupsScreen
    $App.PushScreen($screen)
}