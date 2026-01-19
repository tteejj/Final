# ChecklistsModal.ps1 - Checklists management modal for V3
# Displays and manages checklists for a project

using namespace System.Collections.Generic

class ChecklistsModal {
    hidden [bool]$_visible = $false
    hidden [FluxStore]$_store
    hidden [string]$_projectId = ""
    hidden [string]$_projectName = ""
    hidden [array]$_checklists = @()
    hidden [int]$_selectedIndex = 0
    hidden [int]$_scrollOffset = 0
    hidden [bool]$_viewingChecklist = $false
    hidden [object]$_currentChecklist = $null
    hidden [int]$_checklistItemIndex = 0
    hidden [HybridRenderEngine]$_engine
    
    ChecklistsModal([FluxStore]$store) {
        $this._store = $store
    }
    
    [void] Open([string]$projectId, [string]$projectName) {
        $this._projectId = $projectId
        $this._projectName = $projectName
        $this._visible = $true
        $this._selectedIndex = 0
        $this._scrollOffset = 0
        $this._viewingChecklist = $false
        $this._LoadChecklists()
    }
    
    [void] Close() {
        $this._visible = $false
        $this._viewingChecklist = $false
    }
    
    [bool] IsVisible() {
        return $this._visible
    }
    
    hidden [void] _LoadChecklists() {
        $state = $this._store.GetState()
        
        # Get checklists from state (stored in Data.checklists array)
        if ($state.Data.ContainsKey('checklists') -and $state.Data.checklists) {
            $this._checklists = @($state.Data.checklists | Where-Object { $_['projectId'] -eq $this._projectId })
        } else {
            $this._checklists = @()
        }
    }
    
    [void] Render([HybridRenderEngine]$engine) {
        $this._engine = $engine
        if (-not $this._visible) { return }
        
        $engine.BeginLayer(110)
        
        $w = $engine.Width - 8
        $h = $engine.Height - 6
        $x = 4
        $y = 3
        
        # Background
        $engine.Fill($x, $y, $w, $h, " ", [Colors]::Foreground, [Colors]::Background)
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::Background)
        
        if ($this._viewingChecklist -and $this._currentChecklist) {
            $this._RenderChecklistItems($engine, $x, $y, $w, $h)
        } else {
            $this._RenderChecklistList($engine, $x, $y, $w, $h)
        }
        
        $engine.EndLayer()
    }
    
    hidden [void] _RenderChecklistList([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$w, [int]$h) {
        # Title
        $title = " Checklists: $($this._projectName) "
        $engine.WriteAt($x + 2, $y, $title, [Colors]::Bright, [Colors]::Accent)
        
        $listY = $y + 2
        $listH = $h - 5
        
        if ($this._checklists.Count -eq 0) {
            $engine.WriteAt($x + 4, $listY, "(No checklists. Press N to create one)", [Colors]::Muted, [Colors]::Background)
        } else {
            for ($displayRow = 0; $displayRow -lt $listH; $displayRow++) {
                $idx = $displayRow + $this._scrollOffset
                if ($idx -ge $this._checklists.Count) { break }
                
                $checklist = $this._checklists[$idx]
                $rowY = $listY + $displayRow
                $isSelected = ($idx -eq $this._selectedIndex)
                
                $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
                $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::Background }
                
                $title = if ($checklist['title']) { $checklist['title'] } else { "(Untitled)" }
                $items = if ($checklist['items']) { $checklist['items'] } else { @() }
                if ($null -eq $items) { $items = @() }
                $completed = @($items | Where-Object { $_['checked'] }).Count
                $total = $items.Count
                
                $display = "$title [$completed/$total]"
                $maxWidth = $w - 6
                if ($display.Length -gt $maxWidth) { $display = $display.Substring(0, $maxWidth - 3) + "..." }
                
                $engine.WriteAt($x + 3, $rowY, $display.PadRight($maxWidth), $fg, $bg)
            }
        }
        
        # Status bar
        $statusY = $y + $h - 2
        $engine.Fill($x, $statusY, $w, 1, " ", [Colors]::Foreground, [Colors]::SelectionBg)
        $statusText = " [N] New  [Enter] View/Edit  [Delete] Remove  [Esc] Close"
        $engine.WriteAt($x, $statusY, $statusText, [Colors]::Bright, [Colors]::SelectionBg)
    }
    
    hidden [void] _RenderChecklistItems([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$w, [int]$h) {
        # Title
        $title = " Checklist: $($this._currentChecklist['title']) "
        $engine.WriteAt($x + 2, $y, $title, [Colors]::Bright, [Colors]::Accent)
        
        $items = if ($this._currentChecklist['items']) { $this._currentChecklist['items'] } else { @() }
        if ($null -eq $items) { $items = @() }
        
        $listY = $y + 2
        $listH = $h - 5
        $maxWidth = $w - 6
        
        # Clear the entire list area first
        $engine.Fill($x + 2, $listY, $w - 4, $listH, " ", [Colors]::Foreground, [Colors]::Background)
        
        if ($items.Count -eq 0) {
            $engine.WriteAt($x + 4, $listY, "(No items. Press A to add one)", [Colors]::Muted, [Colors]::Background)
        } else {
            for ($displayRow = 0; $displayRow -lt $listH; $displayRow++) {
                $idx = $displayRow
                if ($idx -ge $items.Count) { break }
                
                $item = $items[$idx]
                $rowY = $listY + $displayRow
                $isSelected = ($idx -eq $this._checklistItemIndex)
                
                $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
                $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::Background }
                
                $checkBox = if ($item['checked']) { "[X]" } else { "[ ]" }
                $text = if ($item['text']) { $item['text'] } else { "" }
                
                $display = "$checkBox $text"
                if ($display.Length -gt $maxWidth) { $display = $display.Substring(0, $maxWidth - 3) + "..." }
                
                $engine.WriteAt($x + 3, $rowY, $display.PadRight($maxWidth), $fg, $bg)
            }
        }
        
        # Progress bar
        $completed = @($items | Where-Object { $_['checked'] }).Count
        $total = $items.Count
        $pct = if ($total -gt 0) { [int](($completed / $total) * 100) } else { 0 }
        $progressY = $y + $h - 3
        $barWidth = $w - 16
        $filledWidth = [int](($pct / 100) * $barWidth)
        $bar = ("█" * $filledWidth) + ("░" * ($barWidth - $filledWidth))
        $engine.WriteAt($x + 3, $progressY, "Progress: $bar $pct%", [Colors]::Title, [Colors]::Background)
        
        # Status bar
        $statusY = $y + $h - 2
        $engine.Fill($x, $statusY, $w, 1, " ", [Colors]::Foreground, [Colors]::SelectionBg)
        $statusText = " [Space] Toggle  [A] Add Item  [Delete] Remove  [Esc] Back"
        $engine.WriteAt($x, $statusY, $statusText, [Colors]::Bright, [Colors]::SelectionBg)
    }
    
    [string] HandleInput([ConsoleKeyInfo]$key) {
        if (-not $this._visible) { return "Continue" }
        
        if ($this._viewingChecklist) {
            return $this._HandleChecklistItemInput($key)
        } else {
            return $this._HandleChecklistListInput($key)
        }
    }
    
    hidden [string] _HandleChecklistListInput([ConsoleKeyInfo]$key) {
        switch ($key.Key) {
            'Escape' {
                $this.Close()
                return "Close"
            }
            'UpArrow' {
                if ($this._selectedIndex -gt 0) {
                    $this._selectedIndex--
                }
                return "Continue"
            }
            'DownArrow' {
                if ($this._selectedIndex -lt $this._checklists.Count - 1) {
                    $this._selectedIndex++
                }
                return "Continue"
            }
            'N' {
                $this._CreateChecklist()
                return "Continue"
            }
            'Enter' {
                if ($this._checklists.Count -gt 0) {
                    $this._currentChecklist = $this._checklists[$this._selectedIndex]
                    $this._viewingChecklist = $true
                    $this._checklistItemIndex = 0
                }
                return "Continue"
            }
            'Delete' {
                if ($this._checklists.Count -gt 0) {
                    $this._DeleteChecklist()
                }
                return "Continue"
            }
            'E' {
                if ($this._checklists.Count -gt 0) {
                     $this._RenameChecklist()
                }
                return "Continue"
            }
        }
        return "Continue"
    }
    
    hidden [string] _HandleChecklistItemInput([ConsoleKeyInfo]$key) {
        $items = if ($this._currentChecklist['items']) { $this._currentChecklist['items'] } else { @() }
        if ($null -eq $items) { $items = @() }
        
        switch ($key.Key) {
            'Escape' {
                $this._viewingChecklist = $false
                $this._currentChecklist = $null
                return "Continue"
            }
            'UpArrow' {
                if ($this._checklistItemIndex -gt 0) {
                    $this._checklistItemIndex--
                }
                return "Continue"
            }
            'DownArrow' {
                if ($this._checklistItemIndex -lt $items.Count - 1) {
                    $this._checklistItemIndex++
                }
                return "Continue"
            }
            'Spacebar' {
                if ($items.Count -gt 0 -and $this._checklistItemIndex -lt $items.Count) {
                    $items[$this._checklistItemIndex]['checked'] = -not $items[$this._checklistItemIndex]['checked']
                    $this._SaveChecklist()
                }
                return "Continue"
            }
            'A' {
                $this._AddChecklistItem()
                return "Continue"
            }
            'Delete' {
                if ($items.Count -gt 0) {
                    $this._DeleteChecklistItem()
                }
                return "Continue"
            }
        }
        return "Continue"
    }
    
    hidden [void] _CreateChecklist() {
        $newChecklist = @{
            id = [DataService]::NewGuid()
            projectId = $this._projectId
            title = "New Checklist"
            items = @()
            created = [DataService]::Timestamp()
            modified = [DataService]::Timestamp()
        }
        
        $state = $this._store.GetState()
        if (-not $state.Data.ContainsKey('checklists')) {
            $state.Data.checklists = @()
        }
        $state.Data.checklists += $newChecklist
        
        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
        $this._LoadChecklists()
        $this._selectedIndex = $this._checklists.Count - 1
    }
    
    hidden [void] _DeleteChecklist() {
        if ($this._selectedIndex -ge $this._checklists.Count) { return }
        
        $checklist = $this._checklists[$this._selectedIndex]
        
        $state = $this._store.GetState()
        $state.Data.checklists = @($state.Data.checklists | Where-Object { $_['id'] -ne $checklist['id'] })
        
        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
        $this._LoadChecklists()
        
        if ($this._selectedIndex -ge $this._checklists.Count -and $this._selectedIndex -gt 0) {
            $this._selectedIndex--
        }
    }
    
    hidden [void] _AddChecklistItem() {
        if ($null -eq $this._currentChecklist) { return }
        if ($null -eq $this._engine) { return }
        
        try {
            # Use NoteEditor - each line becomes an item
            $editor = [NoteEditor]::new("")
            $text = $editor.RenderAndEdit($this._engine, "Add Items (one per line)")
            
            if ($null -ne $text -and $text.Trim().Length -gt 0) {
                if (-not $this._currentChecklist['items']) {
                    $this._currentChecklist['items'] = @()
                }
                
                # Parse lines - each non-empty line becomes an item
                $lines = $text -split "`n"
                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ($trimmed.Length -gt 0) {
                        $newItem = @{
                            id = [DataService]::NewGuid()
                            text = $trimmed
                            checked = $false
                        }
                        $this._currentChecklist['items'] += $newItem
                    }
                }
                
                $this._SaveChecklist()
                $this._checklistItemIndex = $this._currentChecklist['items'].Count - 1
            }
        } catch {
            [Logger]::Error("ChecklistsModal._AddChecklistItem: Error", $_)
        }
    }
    
    hidden [void] _DeleteChecklistItem() {
        if ($null -eq $this._currentChecklist) { return }
        $items = $this._currentChecklist['items']
        if ($null -eq $items -or $items.Count -eq 0) { return }
        if ($this._checklistItemIndex -ge $items.Count) { return }
        
        $itemToRemove = $items[$this._checklistItemIndex]
        $this._currentChecklist['items'] = @($items | Where-Object { $_['id'] -ne $itemToRemove['id'] })
        
        $this._SaveChecklist()
        
        if ($this._checklistItemIndex -ge $this._currentChecklist['items'].Count -and $this._checklistItemIndex -gt 0) {
            $this._checklistItemIndex--
        }
    }
    
    hidden [void] _SaveChecklist() {
        $this._currentChecklist['modified'] = [DataService]::Timestamp()
        
        # Find and update in state
        $state = $this._store.GetState()
        for ($i = 0; $i -lt $state.Data.checklists.Count; $i++) {
            if ($state.Data.checklists[$i]['id'] -eq $this._currentChecklist['id']) {
                $state.Data.checklists[$i] = $this._currentChecklist
                break
            }
        }
        
        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
        $this._LoadChecklists()
    }

    hidden [void] _RenameChecklist() {
        if ($this._selectedIndex -ge $this._checklists.Count) { return }
        $checklist = $this._checklists[$this._selectedIndex]
        
        try {
            $editor = [NoteEditor]::new($checklist['title'])
            $newTitle = $editor.RenderAndEdit($this._engine, "Rename Checklist")
            if ($null -ne $newTitle) {
                # Update State
                $state = $this._store.GetState()
                for ($i = 0; $i -lt $state.Data.checklists.Count; $i++) {
                    if ($state.Data.checklists[$i]['id'] -eq $checklist['id']) {
                        $state.Data.checklists[$i]['title'] = $newTitle.Trim()
                        $state.Data.checklists[$i]['modified'] = [DataService]::Timestamp()
                        break
                    }
                }
                $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
                $this._LoadChecklists()
            }
        } catch {
             [Logger]::Error("ChecklistsModal._RenameChecklist: Error", $_)
        }
    }
}
