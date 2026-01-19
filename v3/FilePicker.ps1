# FilePicker.ps1 - File/Folder browser modal for V3
# Used by ProjectInfoModal for Browse actions

using namespace System.Collections.Generic
using namespace System.IO

class FilePicker {
    hidden [string]$_currentPath
    hidden [bool]$_directoriesOnly
    hidden [array]$_items = @()
    hidden [int]$_selectedIndex = 0
    hidden [int]$_scrollOffset = 0
    hidden [bool]$_visible = $false
    hidden [bool]$_completed = $false
    hidden [string]$_result = $null
    hidden [string]$_title = "Select File"
    hidden [string]$_filter = ""  # Optional file filter
    
    FilePicker() {
        $this._currentPath = [Environment]::GetFolderPath('UserProfile')
    }
    
    [void] Open([string]$startPath, [bool]$directoriesOnly, [string]$title) {
        $this._directoriesOnly = $directoriesOnly
        $this._title = $title
        $this._visible = $true
        $this._completed = $false
        $this._result = $null
        $this._selectedIndex = 0
        $this._scrollOffset = 0
        
        if ([string]::IsNullOrWhiteSpace($startPath)) {
            $startPath = [Environment]::GetFolderPath('UserProfile')
        }
        
        # If startPath is a file, use its directory
        if (Test-Path $startPath -PathType Leaf) {
            $startPath = Split-Path $startPath -Parent
        }
        
        if (-not (Test-Path $startPath)) {
            $startPath = [Environment]::GetFolderPath('UserProfile')
        }
        
        $this._currentPath = $startPath
        $this._LoadDirectory()
    }
    
    [void] Close() {
        $this._visible = $false
    }
    
    [bool] IsVisible() {
        return $this._visible
    }
    
    [bool] IsCompleted() {
        return $this._completed
    }
    
    [string] GetResult() {
        return $this._result
    }
    
    hidden [void] _LoadDirectory() {
        $this._items = @()
        $this._selectedIndex = 0
        $this._scrollOffset = 0
        
        try {
            # Add parent directory entry
            $parent = Split-Path $this._currentPath -Parent
            if ($parent) {
                $this._items += @{
                    Name = ".."
                    FullPath = $parent
                    IsDirectory = $true
                    Size = ""
                    Modified = ""
                }
            }
            
            # Get directories
            $dirs = Get-ChildItem -Path $this._currentPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name
            foreach ($d in $dirs) {
                $this._items += @{
                    Name = $d.Name
                    FullPath = $d.FullName
                    IsDirectory = $true
                    Size = "<DIR>"
                    Modified = $d.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                }
            }
            
            # Get files (unless directories only)
            if (-not $this._directoriesOnly) {
                $files = Get-ChildItem -Path $this._currentPath -File -ErrorAction SilentlyContinue | Sort-Object Name
                foreach ($f in $files) {
                    # Format size
                    $sizeStr = if ($f.Length -ge 1MB) { 
                        "{0:N1} MB" -f ($f.Length / 1MB) 
                    } elseif ($f.Length -ge 1KB) { 
                        "{0:N1} KB" -f ($f.Length / 1KB) 
                    } else { 
                        "$($f.Length) B" 
                    }
                    
                    $this._items += @{
                        Name = $f.Name
                        FullPath = $f.FullName
                        IsDirectory = $false
                        Size = $sizeStr
                        Modified = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    }
                }
            }
        } catch {
            [Logger]::Log("FilePicker: Error loading directory - $($_.Exception.Message)")
        }
    }
    
    [void] Render([HybridRenderEngine]$engine) {
        if (-not $this._visible) { return }
        
        $engine.BeginLayer(120)
        
        $w = $engine.Width - 4
        $h = $engine.Height - 4
        $x = 2
        $y = 2
        
        # Background
        $engine.Fill($x, $y, $w, $h, " ", [Colors]::Foreground, [Colors]::Background)
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::Background)
        
        # Title
        $engine.WriteAt($x + 2, $y, " $($this._title) ", [Colors]::White, [Colors]::Accent)
        
        # Current path
        $pathDisplay = $this._currentPath
        if ($pathDisplay.Length -gt $w - 6) {
            $pathDisplay = "..." + $pathDisplay.Substring($pathDisplay.Length - ($w - 9))
        }
        $engine.WriteAt($x + 2, $y + 1, $pathDisplay, [Colors]::Cyan, [Colors]::Background)
        
        # Separator
        $engine.WriteAt($x + 1, $y + 2, ("─" * ($w - 2)), [Colors]::PanelBorder, [Colors]::Background)
        
        # Column headers
        $nameWidth = $w - 35
        $engine.WriteAt($x + 2, $y + 3, "Name".PadRight($nameWidth), [Colors]::Gray, [Colors]::Background)
        $engine.WriteAt($x + 2 + $nameWidth, $y + 3, "Size".PadRight(12), [Colors]::Gray, [Colors]::Background)
        $engine.WriteAt($x + 2 + $nameWidth + 12, $y + 3, "Modified", [Colors]::Gray, [Colors]::Background)
        
        # File list area
        $listY = $y + 4
        $listH = $h - 7
        
        # Adjust scroll
        if ($this._selectedIndex -lt $this._scrollOffset) {
            $this._scrollOffset = $this._selectedIndex
        }
        if ($this._selectedIndex -ge $this._scrollOffset + $listH) {
            $this._scrollOffset = $this._selectedIndex - $listH + 1
        }
        
        for ($displayRow = 0; $displayRow -lt $listH; $displayRow++) {
            $itemIdx = $displayRow + $this._scrollOffset
            if ($itemIdx -ge $this._items.Count) { break }
            
            $item = $this._items[$itemIdx]
            $rowY = $listY + $displayRow
            $isSelected = ($itemIdx -eq $this._selectedIndex)
            
            $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
            $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::Background }
            
            # Icon
            $icon = if ($item.IsDirectory) { "📁 " } else { "📄 " }
            if ($item.Name -eq "..") { $icon = "⬆️ " }
            
            # Name
            $name = $item.Name
            $maxName = $nameWidth - 3
            if ($name.Length -gt $maxName) { $name = $name.Substring(0, $maxName - 3) + "..." }
            $nameDisplay = ($icon + $name).PadRight($nameWidth)
            
            $engine.WriteAt($x + 2, $rowY, $nameDisplay, $fg, $bg)
            $engine.WriteAt($x + 2 + $nameWidth, $rowY, $item.Size.PadRight(12), $fg, $bg)
            $engine.WriteAt($x + 2 + $nameWidth + 12, $rowY, $item.Modified.PadRight(16), $fg, $bg)
        }
        
        # Scrollbar
        if ($this._items.Count -gt $listH) {
            $thumbSize = [Math]::Max(1, [int]($listH * ($listH / $this._items.Count)))
            $maxOffset = [Math]::Max(1, $this._items.Count - $listH)
            $thumbPos = [int](($this._scrollOffset / $maxOffset) * ($listH - $thumbSize))
            
            for ($i = 0; $i -lt $listH; $i++) {
                $char = if ($i -ge $thumbPos -and $i -lt $thumbPos + $thumbSize) { "█" } else { "░" }
                $engine.WriteAt($x + $w - 2, $listY + $i, $char, [Colors]::Gray, [Colors]::Background)
            }
        }
        
        # Status bar
        $statusY = $y + $h - 2
        $engine.Fill($x, $statusY, $w, 1, " ", [Colors]::Foreground, [Colors]::SelectionBg)
        
        $statusText = " [Space] Select  [Enter] Open Folder  [Esc] Cancel  [Backspace] Parent"
        $engine.WriteAt($x, $statusY, $statusText, [Colors]::White, [Colors]::SelectionBg)
        
        $engine.EndLayer()
    }
    
    # Returns: "Continue", "Selected", "Cancelled"
    [string] HandleInput([ConsoleKeyInfo]$key) {
        if (-not $this._visible) { return "Continue" }
        
        switch ($key.Key) {
            'Escape' {
                $this._completed = $true
                $this._result = $null
                $this._visible = $false
                return "Cancelled"
            }
            'UpArrow' {
                if ($this._selectedIndex -gt 0) {
                    $this._selectedIndex--
                }
                return "Continue"
            }
            'DownArrow' {
                if ($this._selectedIndex -lt $this._items.Count - 1) {
                    $this._selectedIndex++
                }
                return "Continue"
            }
            'PageUp' {
                $this._selectedIndex = [Math]::Max(0, $this._selectedIndex - 10)
                return "Continue"
            }
            'PageDown' {
                $this._selectedIndex = [Math]::Min($this._items.Count - 1, $this._selectedIndex + 10)
                return "Continue"
            }
            'Home' {
                $this._selectedIndex = 0
                return "Continue"
            }
            'End' {
                $this._selectedIndex = $this._items.Count - 1
                return "Continue"
            }
            'Backspace' {
                # Go to parent
                $parent = Split-Path $this._currentPath -Parent
                if ($parent) {
                    $this._currentPath = $parent
                    $this._LoadDirectory()
                }
                return "Continue"
            }
            'Enter' {
                # Enter always navigates into directories
                if ($this._items.Count -eq 0) { return "Continue" }
                
                $selected = $this._items[$this._selectedIndex]
                
                if ($selected.IsDirectory) {
                    # Navigate into directory (including ..)
                    $this._currentPath = $selected.FullPath
                    $this._LoadDirectory()
                }
                # For files, Enter does nothing - use Space to select
                return "Continue"
            }
            'Spacebar' {
                # Space selects the current item
                if ($this._items.Count -eq 0) { return "Continue" }
                
                $selected = $this._items[$this._selectedIndex]
                
                # Don't allow selecting ".."
                if ($selected.Name -eq "..") { return "Continue" }
                
                # Select the file or folder
                $this._completed = $true
                $this._result = $selected.FullPath
                $this._visible = $false
                return "Selected"
            }
        }
        return "Continue"
    }
}
