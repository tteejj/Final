using namespace System
using namespace System.Collections.Generic

<#
.SYNOPSIS
Modern File/Directory Picker Widget for PmcTUI
Fully integrated with SpeedTUI render engine, proper Z-layering, theme support
#>

if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

class PmcFilePicker : PmcWidget {
    # === Public Properties ===
    [string]$CurrentPath = ''
    [array]$Items = @()
    [int]$SelectedIndex = 0
    [int]$ScrollOffset = 0
    [bool]$DirectoriesOnly = $true
    [string]$SelectedPath = ''
    [bool]$IsComplete = $false
    [bool]$Result = $false

    # === Event Callbacks ===
    [scriptblock]$OnConfirmed = {}       # Called when selection confirmed: param($path)
    [scriptblock]$OnCancelled = {}       # Called when cancelled

    # === Private State ===
    hidden [int]$_minWidth = 50
    hidden [int]$_minHeight = 15
    hidden [int]$_contentPadding = 2
    hidden [int]$_headerHeight = 3      # Title + separator + blank
    hidden [int]$_footerHeight = 2      # Blank + footer text

    PmcFilePicker([string]$startPath, [bool]$directoriesOnly) {
        $this.DirectoriesOnly = $directoriesOnly
        $this.Width = 70
        $this.Height = 22

        # Set start path
        if ([string]::IsNullOrWhiteSpace($startPath) -or -not (Test-Path $startPath)) {
            $this.CurrentPath = [Environment]::GetFolderPath('UserProfile')
        } else {
            $this.CurrentPath = $startPath
        }

        $this._LoadItems()
    }

    # === Item Management ===

    hidden [void] _LoadItems() {
        $this.Items = @()
        $this.SelectedIndex = 0
        $this.ScrollOffset = 0

        try {
            # Add parent directory (..)
            $parent = Split-Path -Parent $this.CurrentPath
            if ($parent -and $parent -ne $this.CurrentPath) {
                $this.Items += @{ Name = '..'; Path = $parent; IsDirectory = $true }
            }

            # Get directories
            $dirs = @(Get-ChildItem -Path $this.CurrentPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
            foreach ($dir in $dirs) {
                $this.Items += @{ Name = $dir.Name; Path = $dir.FullName; IsDirectory = $true }
            }

            # Get files if not DirectoriesOnly
            if (-not $this.DirectoriesOnly) {
                $files = @(Get-ChildItem -Path $this.CurrentPath -File -ErrorAction SilentlyContinue | Sort-Object Name)
                foreach ($file in $files) {
                    $this.Items += @{ Name = $file.Name; Path = $file.FullName; IsDirectory = $false }
                }
            }
        } catch {
            # Fall back to home directory
            $this.CurrentPath = [Environment]::GetFolderPath('UserProfile')
            $this._LoadItems()
        }
    }

    # === Layout ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)

        # Ensure minimum dimensions
        if ($this.Width -lt $this._minWidth) { $this.Width = $this._minWidth }
        if ($this.Height -lt $this._minHeight) { $this.Height = $this._minHeight }

        # Center on screen if not positioned
        if ($this.X -le 0) {
            $this.X = [Math]::Max(1, [Math]::Floor(($engine.Width - $this.Width) / 2))
        }
        if ($this.Y -le 0) {
            $this.Y = [Math]::Max(1, [Math]::Floor(($engine.Height - $this.Height) / 2))
        }

        # Define regions
        $contentHeight = $this.Height - $this._headerHeight - $this._footerHeight
        $engine.DefineRegion("$($this.RegionID)_Header", $this.X + 1, $this.Y + 1, $this.Width - 2, 1)
        $engine.DefineRegion("$($this.RegionID)_Path", $this.X + 1, $this.Y + 2, $this.Width - 2, 1)
        $engine.DefineRegion("$($this.RegionID)_Items", $this.X + 1, $this.Y + 3, $this.Width - 2, $contentHeight)
        $engine.DefineRegion("$($this.RegionID)_Footer", $this.X + 1, $this.Y + $this.Height - 1, $this.Width - 2, 1)
    }

    # === Rendering ===

    [void] RenderToEngine([object]$engine) {
        $this.RegisterLayout($engine)

        Add-Content -Path "/tmp/pmc-filepicker-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] === FilePicker.RenderToEngine START === X=$($this.X) Y=$($this.Y) Width=$($this.Width) Height=$($this.Height) engineWidth=$($engine.Width) engineHeight=$($engine.Height)"

        # Begin Z-layer (above content, below dialogs)
        if ($engine.PSObject.Methods['BeginLayer']) {
            Add-Content -Path "/tmp/pmc-filepicker-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] BeginLayer(20) called"
            $engine.BeginLayer(20)
        }
        else {
            Add-Content -Path "/tmp/pmc-filepicker-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] WARNING: BeginLayer method not available"
        }

        # Theme colors
        $primaryBg = $this.GetThemedColorInt('Background.Primary')
        $primaryFg = $this.GetThemedColorInt('Foreground.Field')
        $borderFg = $this.GetThemedColorInt('Border.Widget')
        $titleFg = $this.GetThemedColorInt('Foreground.Title')
        $selectedBg = $this.GetThemedColorInt('Background.RowSelected')
        $selectedFg = $this.GetThemedColorInt('Foreground.RowSelected')
        $mutedFg = $this.GetThemedColorInt('Foreground.Muted')

        # Draw background and border
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $primaryFg, $primaryBg)

        # Draw top and bottom border
        $engine.Fill($this.X, $this.Y, $this.Width, 1, '─', $borderFg, $primaryBg)
        $engine.Fill($this.X, $this.Y + $this.Height - 1, $this.Width, 1, '─', $borderFg, $primaryBg)

        # Draw left and right borders
        for ($i = $this.Y; $i -lt ($this.Y + $this.Height); $i++) {
            $engine.WriteAt($this.X, $i, '│', $borderFg, $primaryBg)
            $engine.WriteAt($this.X + $this.Width - 1, $i, '│', $borderFg, $primaryBg)
        }

        # Draw corners
        $engine.WriteAt($this.X, $this.Y, '┌', $borderFg, $primaryBg)
        $engine.WriteAt($this.X + $this.Width - 1, $this.Y, '┐', $borderFg, $primaryBg)
        $engine.WriteAt($this.X, $this.Y + $this.Height - 1, '└', $borderFg, $primaryBg)
        $engine.WriteAt($this.X + $this.Width - 1, $this.Y + $this.Height - 1, '┘', $borderFg, $primaryBg)

        # Draw header
        $headerText = "📁 Select Directory"
        $headerPadded = $headerText.PadRight($this.Width - 2)
        $engine.WriteAt($this.X + 1, $this.Y + 1, $headerPadded.Substring(0, $this.Width - 2), $titleFg, $primaryBg)

        # Draw path
        $pathDisplay = $this.CurrentPath
        if ($pathDisplay.Length -gt ($this.Width - 4)) {
            $pathDisplay = "..." + $pathDisplay.Substring($pathDisplay.Length - ($this.Width - 7))
        }
        $pathPadded = $pathDisplay.PadRight($this.Width - 2)
        $engine.WriteAt($this.X + 1, $this.Y + 2, $pathPadded.Substring(0, $this.Width - 2), $mutedFg, $primaryBg)

        # Draw items
        $listY = $this.Y + 3
        $contentHeight = $this.Height - $this._headerHeight - $this._footerHeight

        # Ensure selection is visible
        if ($this.SelectedIndex -lt $this.ScrollOffset) {
            $this.ScrollOffset = $this.SelectedIndex
        }
        if ($this.SelectedIndex -ge ($this.ScrollOffset + $contentHeight)) {
            $this.ScrollOffset = $this.SelectedIndex - $contentHeight + 1
        }

        # Render items
        $row = 0
        $itemCount = $this.Items.Count
        for ($i = $this.ScrollOffset; $i -lt [Math]::Min($this.ScrollOffset + $contentHeight, $itemCount); $i++) {
            $item = $this.Items[$i]
            $isSelected = ($i -eq $this.SelectedIndex)
            $itemBg = if ($isSelected) { $selectedBg } else { $primaryBg }
            $itemFg = if ($isSelected) { $selectedFg } else { if ($item.IsDirectory) { $titleFg } else { $primaryFg } }

            # Item text
            $icon = if ($item.IsDirectory) { "📁" } else { "📄" }
            $displayName = $item.Name
            $maxNameLen = $this.Width - 6
            if ($displayName.Length -gt $maxNameLen) {
                $displayName = $displayName.Substring(0, $maxNameLen - 3) + "..."
            }

            $itemText = " $icon $displayName"
            $itemTextPadded = $itemText.PadRight($this.Width - 2)

            $engine.Fill($this.X + 1, $listY + $row, $this.Width - 2, 1, ' ', $itemFg, $itemBg)
            $engine.WriteAt($this.X + 1, $listY + $row, $itemTextPadded.Substring(0, $this.Width - 2), $itemFg, $itemBg)

            $row++
        }

        # Fill remaining rows
        while ($row -lt $contentHeight) {
            $engine.Fill($this.X + 1, $listY + $row, $this.Width - 2, 1, ' ', $primaryFg, $primaryBg)
            $row++
        }

        # Draw scroll indicators
        if ($this.ScrollOffset -gt 0) {
            $engine.WriteAt($this.X + $this.Width - 2, $listY, "▲", $mutedFg, $primaryBg)
        }
        if (($this.ScrollOffset + $contentHeight) -lt $itemCount) {
            $engine.WriteAt($this.X + $this.Width - 2, $listY + $contentHeight - 1, "▼", $mutedFg, $primaryBg)
        }

        # Draw footer
        $footerText = "↑↓: Navigate | Enter: Select | Space: Use Path | Esc: Cancel"
        if ($footerText.Length -gt ($this.Width - 2)) {
            $footerText = $footerText.Substring(0, $this.Width - 5) + "..."
        }
        $footerPadded = $footerText.PadRight($this.Width - 2)
        $engine.WriteAt($this.X + 1, $this.Y + $this.Height - 1, $footerPadded.Substring(0, $this.Width - 2), $mutedFg, $primaryBg)

        # End Z-layer
        if ($engine.PSObject.Methods['EndLayer']) {
            Add-Content -Path "/tmp/pmc-filepicker-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] EndLayer() called"
            $engine.EndLayer()
        }
        Add-Content -Path "/tmp/pmc-filepicker-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] === FilePicker.RenderToEngine END ==="
    }

    # === Input Handling ===

    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this.SelectedIndex -gt 0) {
                    $this.SelectedIndex--
                }
                return $true
            }
            'DownArrow' {
                if ($this.SelectedIndex -lt ($this.Items.Count - 1)) {
                    $this.SelectedIndex++
                }
                return $true
            }
            'PageUp' {
                $this.SelectedIndex = [Math]::Max(0, $this.SelectedIndex - 10)
                return $true
            }
            'PageDown' {
                $this.SelectedIndex = [Math]::Min($this.Items.Count - 1, $this.SelectedIndex + 10)
                return $true
            }
            'Home' {
                $this.SelectedIndex = 0
                return $true
            }
            'End' {
                if ($this.Items.Count -gt 0) {
                    $this.SelectedIndex = $this.Items.Count - 1
                }
                return $true
            }
            'Enter' {
                if ($this.Items.Count -eq 0) {
                    return $true
                }
                $selected = $this.Items[$this.SelectedIndex]
                if ($selected.IsDirectory) {
                    $this.CurrentPath = $selected.Path
                    $this._LoadItems()
                } else {
                    $this.SelectedPath = $selected.Path
                    $this.Result = $true
                    $this.IsComplete = $true
                    $this._InvokeCallback($this.OnConfirmed, $this.SelectedPath)
                }
                return $true
            }
            'Spacebar' {
                # Select current path
                $this.SelectedPath = $this.CurrentPath
                $this.Result = $true
                $this.IsComplete = $true
                $this._InvokeCallback($this.OnConfirmed, $this.SelectedPath)
                return $true
            }
            'Escape' {
                $this.Result = $false
                $this.IsComplete = $true
                $this._InvokeCallback($this.OnCancelled, $null)
                return $true
            }
        }
        return $false
    }

    # === Callbacks ===

    hidden [void] _InvokeCallback([scriptblock]$callback, [object]$arg) {
        if ($callback -and $callback -ne $null) {
            try {
                & $callback $arg
            } catch {
                # Callback error - log but don't crash
            }
        }
    }

    # === Legacy Render method (for compatibility) ===

    [string] Render() {
        return ""
    }
}
