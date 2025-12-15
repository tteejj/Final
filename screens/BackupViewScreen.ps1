using namespace System.Collections.Generic
using namespace System.Text

# BackupViewScreen - View and manage backup files
# Shows list of backup files with dates


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Backup management screen

.DESCRIPTION
Shows automatic backups (.bak1-.bak9) and manual backups.
Supports:
- Viewing backup list with dates and sizes (Up/Down arrows)
- Creating manual backup (C key)
- Restoring from backup (R key)
- Deleting backups (D key)
#>
class BackupViewScreen : PmcScreen {
    # Data
    [array]$Backups = @()
    [int]$SelectedIndex = 0

    # Constructor
    BackupViewScreen() : base("BackupView", "Backups") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Backups"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Up/Down", "Select")
        $this.Footer.AddShortcut("C", "Create")
        $this.Footer.AddShortcut("R", "Restore")
        $this.Footer.AddShortcut("D", "Delete")
        $this.Footer.AddShortcut("Esc", "Back")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    BackupViewScreen([object]$container) : base("BackupView", "Backups", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Backups"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Up/Down", "Select")
        $this.Footer.AddShortcut("C", "Create")
        $this.Footer.AddShortcut("R", "Restore")
        $this.Footer.AddShortcut("D", "Delete")
        $this.Footer.AddShortcut("Esc", "Back")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest
    }

    [void] LoadData() {
        $this.ShowStatus("Loading backups...")

        try {
            $file = Get-PmcTaskFilePath
            $this.Backups = @()

            # Collect .bak1 through .bak9 files
            for ($i = 1; $i -le 9; $i++) {
                $bakFile = "$file.bak$i"
                if (Test-Path $bakFile) {
                    $info = Get-Item $bakFile
                    $this.Backups += [PSCustomObject]@{
                        Number   = $i
                        Name     = ".bak$i"
                        Path     = $bakFile
                        Size     = $info.Length
                        Modified = $info.LastWriteTime
                        Type     = "auto"
                    }
                }
            }

            # Collect manual backups from backups directory
            $backupDir = Join-Path (Get-PmcRootPath) "backups"
            if (Test-Path $backupDir) {
                $manualBackups = @(Get-ChildItem $backupDir -Filter "*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 10)
                foreach ($backup in $manualBackups) {
                    $this.Backups += [PSCustomObject]@{
                        Number   = $this.Backups.Count + 1
                        Name     = $backup.Name
                        Path     = $backup.FullName
                        Size     = $backup.Length
                        Modified = $backup.LastWriteTime
                        Type     = "manual"
                    }
                }
            }

            # Reset selection if out of bounds
            if ($this.SelectedIndex -ge $this.Backups.Count) {
                $this.SelectedIndex = [Math]::Max(0, $this.Backups.Count - 1)
            }

            # Update status
            if ($this.Backups.Count -eq 0) {
                $this.ShowStatus("No backups found")
            }
            else {
                $this.ShowStatus("$($this.Backups.Count) backups available")
            }

        }
        catch {
            $this.ShowError("Failed to load backups: $_")
            $this.Backups = @()
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        if ($this.Backups.Count -eq 0) {
            $this._RenderEmptyStateToEngine($engine)
            return
        }

        $this._RenderBackupListToEngine($engine)
    }

    hidden [void] _RenderEmptyStateToEngine([object]$engine) {
        # Center message
        $message = "No backups found - Press C to create one"
        $x = 4 + [Math]::Floor(($this.TermWidth - 4 - 4 - $message.Length) / 2)
        $y = 4 + [Math]::Floor(($this.TermHeight - 4 - 4) / 2)
        
        # Clamp
        $x = [Math]::Max(4, $x)
        $y = [Math]::Max(4, $y)

        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        $engine.WriteAt($x, $y, $message, $textColor, $bg)
    }

    hidden [void] _RenderBackupListToEngine([object]$engine) {
        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.Field')
        $cursorColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $x = 4
        $headerY = 4 # Adjust based on header? Header is usually top 3 lines.

        # Render column headers
        $engine.WriteAt($x, $headerY, "TYPE    ", $headerColor, $bg)
        $engine.WriteAt($x + 8, $headerY, "NAME         ", $headerColor, $bg)
        $engine.WriteAt($x + 21, $headerY, "MODIFIED            ", $headerColor, $bg)
        $engine.WriteAt($x + 41, $headerY, "SIZE", $headerColor, $bg)

        # Render backup rows
        $startY = $headerY + 2
        $maxLines = $this.TermHeight - $startY - 4 # Footer allowance

        for ($i = 0; $i -lt [Math]::Min($this.Backups.Count, $maxLines); $i++) {
            $backup = $this.Backups[$i]
            $y = $startY + $i
            $isSelected = ($i -eq $this.SelectedIndex)

            $rowBg = $(if ($isSelected) { $selectedBg } else { $bg })
            $rowFg = $(if ($isSelected) { $selectedFg } else { $textColor })
            $typeFg = $(if ($isSelected) { $selectedFg } else { $mutedColor })
            $dateFg = $(if ($isSelected) { $selectedFg } else { $mutedColor })

            # Cursor
            if ($isSelected) {
                $engine.WriteAt($x - 2, $y, ">", $cursorColor, $bg)
            }

            $currentX = $x

            # Type column
            $typeLabel = $(if ($backup.Type -eq "auto") { "[Auto]" } else { "[Manual]" })
            $engine.WriteAt($currentX, $y, $typeLabel.PadRight(8), $typeFg, $rowBg)
            $currentX += 8

            # Name column
            $engine.WriteAt($currentX, $y, $backup.Name.PadRight(13), $rowFg, $rowBg)
            $currentX += 13

            # Modified column
            $dateStr = $backup.Modified.ToString('yyyy-MM-dd HH:mm:ss').PadRight(20)
            $engine.WriteAt($currentX, $y, $dateStr, $dateFg, $rowBg)
            $currentX += 20

            # Size column
            $sizeKB = [math]::Round($backup.Size / 1KB, 2)
            $engine.WriteAt($currentX, $y, "$sizeKB KB", $rowFg, $rowBg)
        }
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this.SelectedIndex -gt 0) {
                    $this.SelectedIndex--
                    return $true
                }
            }
            'DownArrow' {
                if ($this.SelectedIndex -lt ($this.Backups.Count - 1)) {
                    $this.SelectedIndex++
                    return $true
                }
            }
        }

        switch ($keyChar) {
            'c' {
                $this._CreateBackup()
                return $true
            }
            'r' {
                $this._RestoreBackup()
                return $true
            }
            'd' {
                $this._DeleteBackup()
                return $true
            }
        }

        return $false
    }

    hidden [void] _CreateBackup() {
        try {
            $file = Get-PmcTaskFilePath
            if (Test-Path $file) {
                # Rotate backups
                for ($i = 8; $i -ge 1; $i--) {
                    $src = "$file.bak$i"
                    $dst = "$file.bak$($i+1)"
                    if (Test-Path $src) {
                        Move-Item -Force $src $dst
                    }
                }
                Copy-Item $file "$file.bak1" -Force

                $this.ShowSuccess("Backup created successfully")
                $this.LoadData()
            }
            else {
                $this.ShowError("Data file not found")
            }
        }
        catch {
            $this.ShowError("Error creating backup: $_")
        }
    }

    hidden [void] _RestoreBackup() {
        if ($this.SelectedIndex -lt 0 -or $this.SelectedIndex -ge $this.Backups.Count) {
            $this.ShowError("No backup selected")
            return
        }

        if ($this.Backups.Count -gt 0) {
            $backup = $this.Backups[$this.SelectedIndex]
            . "$PSScriptRoot/RestoreBackupScreen.ps1"
            $screen = New-Object RestoreBackupScreen -ArgumentList $backup
            # Backup object already set via constructor parameter
            $global:PmcApp.PushScreen($screen)
        }
    }

    hidden [void] _DeleteBackup() {
        if ($this.SelectedIndex -lt 0 -or $this.SelectedIndex -ge $this.Backups.Count) {
            $this.ShowError("No backup selected")
            return
        }

        $backup = $this.Backups[$this.SelectedIndex]

        try {
            if (Test-Path $backup.Path) {
                Remove-Item $backup.Path -Force -ErrorAction Stop
                $this.ShowSuccess("Backup deleted: $($backup.Name)")
                $this.LoadData()
            }
            else {
                $this.ShowError("Backup file not found")
            }
        }
        catch {
            $this.ShowError("Error deleting backup: $_")
        }
    }
}

# Entry point function for compatibility
function Show-BackupViewScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object BackupViewScreen
    $App.PushScreen($screen)
}