using namespace System.Collections.Generic

# SimpleFilePicker.ps1 - Simple file/folder picker that works with SpeedTUI

Set-StrictMode -Version Latest

# Ensure PmcWidget is loaded
if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

class SimpleFilePicker : PmcWidget {
    [string]$CurrentPath = ''
    [List[object]]$Items = $null
    [int]$SelectedIndex = 0
    [int]$ScrollOffset = 0
    [bool]$IsComplete = $false
    [bool]$Result = $false
    [string]$SelectedPath = ''
    [bool]$DirectoriesOnly = $false

    SimpleFilePicker([string]$startPath, [bool]$directoriesOnly) : base("SimpleFilePicker") {
        $this.Width = 60
        $this.Height = 20
        $this.DirectoriesOnly = $directoriesOnly
        $this.Items = [List[object]]::new()

        # Validate and set start path
        if ([string]::IsNullOrWhiteSpace($startPath) -or -not (Test-Path $startPath)) {
            $this.CurrentPath = [Environment]::GetFolderPath('UserProfile')
        }
        else {
            if (Test-Path -Path $startPath -PathType Leaf) {
                # If it's a file, use parent directory
                $this.CurrentPath = Split-Path -Parent $startPath
            }
            else {
                $this.CurrentPath = $startPath
            }
        }

        $this.LoadItems()
    }

    [void] LoadItems() {
        $this.Items.Clear()
        $this.SelectedIndex = 0
        $this.ScrollOffset = 0

        try {
            # Add parent directory
            $parent = Split-Path -Parent $this.CurrentPath
            if ($parent) {
                $this.Items.Add(@{
                        Name        = '..'
                        Path        = $parent
                        IsDirectory = $true
                    })
            }

            # Get directories
            $dirs = Get-ChildItem -Path $this.CurrentPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name
            foreach ($dir in $dirs) {
                $this.Items.Add(@{
                        Name        = $dir.Name
                        Path        = $dir.FullName
                        IsDirectory = $true
                    })
            }

            # Get files if not directories-only
            if (-not $this.DirectoriesOnly) {
                $files = Get-ChildItem -Path $this.CurrentPath -File -ErrorAction SilentlyContinue | Sort-Object Name
                foreach ($file in $files) {
                    $this.Items.Add(@{
                            Name        = $file.Name
                            Path        = $file.FullName
                            IsDirectory = $false
                        })
                }
            }
        }
        catch {
            # On error, go to home
            $this.CurrentPath = [Environment]::GetFolderPath('UserProfile')
            $this.LoadItems()
        }
    }

    [bool] HandleInput([ConsoleKeyInfo]$key) {
        switch ($key.Key) {
            'UpArrow' {
                if ($this.SelectedIndex -gt 0) {
                    $this.SelectedIndex--
                    # Adjust scroll if needed
                    if ($this.SelectedIndex -lt $this.ScrollOffset) {
                        $this.ScrollOffset = $this.SelectedIndex
                    }
                }
                return $true
            }
            'DownArrow' {
                if ($this.SelectedIndex -lt ($this.Items.Count - 1)) {
                    $this.SelectedIndex++
                    # Adjust scroll if needed (show 15 items at a time - or Height-5)
                    $visibleItems = $this.Height - 5
                    if ($this.SelectedIndex -ge ($this.ScrollOffset + $visibleItems)) {
                        $this.ScrollOffset = $this.SelectedIndex - $visibleItems + 1
                    }
                }
                return $true
            }
            'Enter' {
                if ($this.Items.Count -eq 0) {
                    return $true
                }

                $selected = $this.Items[$this.SelectedIndex]
                if ($selected.IsDirectory) {
                    # Navigate into directory
                    $this.CurrentPath = $selected.Path
                    $this.LoadItems()
                }
                else {
                    # Select file
                    $this.SelectedPath = $selected.Path
                    $this.Result = $true
                    $this.IsComplete = $true
                }
                return $true
            }
            'Spacebar' {
                # Select current directory
                $this.SelectedPath = $this.CurrentPath
                $this.Result = $true
                $this.IsComplete = $true
                return $true
            }
            'Escape' {
                $this.Result = $false
                $this.IsComplete = $true
                return $true
            }
        }
        return $false
    }

    # === Layout System ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)
        
        $engine.DefineRegion("$($this.RegionID)_Title", $this.X + 2, $this.Y + 1, $this.Width - 4, 1)
        $engine.DefineRegion("$($this.RegionID)_Path", $this.X + 2, $this.Y + 2, $this.Width - 4, 1)
        
        $listHeight = [Math]::Max(1, $this.Height - 6)
        $engine.DefineRegion("$($this.RegionID)_List", $this.X + 2, $this.Y + 4, $this.Width - 4, $listHeight)
        
        $engine.DefineRegion("$($this.RegionID)_Help", $this.X + 2, $this.Y + $this.Height - 2, $this.Width - 4, 1)
    }

    <#
    .SYNOPSIS
    Render directly to engine (new high-performance path)
    #>
    [void] RenderToEngine([object]$engine) {
        $this.RegisterLayout($engine)

        # Colors (Ints)
        # Colors (Ints)
        $bg = $this.GetThemedBgInt('Background.Panel', 1, 0)
        $fg = $this.GetThemedInt('Foreground.Row')
        $highlightBg = $this.GetThemedBgInt('Background.RowSelected', 1, 0)
        $highlightFg = $this.GetThemedInt('Foreground.RowSelected')
        $dirColor = $this.GetThemedInt('Foreground.Title')
        $muted = $this.GetThemedInt('Foreground.Muted')
        
        # Draw Box
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $fg, $bg)
        
        # Title
        $title = if ($this.DirectoriesOnly) { "Select Folder" } else { "Select File" }
        $engine.WriteToRegion("$($this.RegionID)_Title", "=== $title ===", $fg, $bg)
        
        # Path
        $engine.WriteToRegion("$($this.RegionID)_Path", "Current: $($this.CurrentPath)", $fg, $bg)
        
        # List
        $listRegion = "$($this.RegionID)_List"
        $bounds = $engine.GetRegionBounds($listRegion)
        
        if ($bounds) {
            $visibleCount = $bounds.Height
            
            for ($i = 0; $i -lt $visibleCount; $i++) {
                $idx = $this.ScrollOffset + $i
                if ($idx -ge $this.Items.Count) { break }
                
                $item = $this.Items[$idx]
                $isSelected = ($idx -eq $this.SelectedIndex)
                
                $iBg = if ($isSelected) { $highlightBg } else { $bg }
                $iFg = if ($isSelected) { $highlightFg } else { if ($item.IsDirectory) { $dirColor } else { $fg } }
                
                $prefix = if ($item.IsDirectory) { "[DIR]" } else { "[FILE]" }
                $text = if ($isSelected) { "> $prefix $($item.Name)" } else { "  $prefix $($item.Name)" }
                
                $engine.Fill($bounds.X, $bounds.Y + $i, $bounds.Width, 1, ' ', $iFg, $iBg)
                $engine.WriteAt($bounds.X, $bounds.Y + $i, $text, $iFg, $iBg)
            }
        }
        
        # Help
        $help = "Up/Down: Navigate | Enter: Open | Space: Select | Esc: Cancel"
        $engine.WriteToRegion("$($this.RegionID)_Help", $help, $muted, $bg)
    }

    [string] Render() { return "" }
}