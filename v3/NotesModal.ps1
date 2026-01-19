# NotesModal.ps1 - Notes management modal for V3
# Displays and manages notes for a project

using namespace System.Collections.Generic

class NotesModal {
    hidden [bool]$_visible = $false
    hidden [FluxStore]$_store
    hidden [string]$_projectId = ""
    hidden [string]$_projectName = ""
    hidden [array]$_notes = @()
    hidden [int]$_selectedIndex = 0
    hidden [int]$_scrollOffset = 0
    hidden [bool]$_editing = $false
    hidden [object]$_noteEditor = $null
    
    NotesModal([FluxStore]$store) {
        $this._store = $store
    }
    
    [void] Open([string]$projectId, [string]$projectName) {
        $this._projectId = $projectId
        $this._projectName = $projectName
        $this._visible = $true
        $this._selectedIndex = 0
        $this._scrollOffset = 0
        $this._editing = $false
        $this._LoadNotes()
    }
    
    [void] Close() {
        $this._visible = $false
        $this._editing = $false
    }
    
    [bool] IsVisible() {
        return $this._visible
    }
    
    hidden [void] _LoadNotes() {
        $state = $this._store.GetState()
        
        # Get notes from state (stored in Data.notes array)
        if ($state.Data.ContainsKey('notes') -and $state.Data.notes) {
            $this._notes = @($state.Data.notes | Where-Object { $_['projectId'] -eq $this._projectId })
        } else {
            $this._notes = @()
        }
    }
    
    [void] Render([HybridRenderEngine]$engine) {
        if (-not $this._visible) { return }
        
        # If editing a note, the NoteEditor handles its own rendering
        if ($this._editing -and $this._noteEditor) {
            return
        }
        
        $engine.BeginLayer(110)
        
        $w = $engine.Width - 8
        $h = $engine.Height - 6
        $x = 4
        $y = 3
        
        # Background
        $engine.Fill($x, $y, $w, $h, " ", [Colors]::Foreground, [Colors]::Background)
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::Background)
        
        # Title
        $title = " Notes: $($this._projectName) "
        $engine.WriteAt($x + 2, $y, $title, [Colors]::White, [Colors]::Accent)
        
        # Notes list
        $listY = $y + 2
        $listH = $h - 5
        
        if ($this._notes.Count -eq 0) {
            $engine.WriteAt($x + 4, $listY, "(No notes. Press N to create one)", [Colors]::Gray, [Colors]::Background)
        } else {
            # Adjust scroll
            if ($this._selectedIndex -lt $this._scrollOffset) {
                $this._scrollOffset = $this._selectedIndex
            }
            if ($this._selectedIndex -ge $this._scrollOffset + $listH) {
                $this._scrollOffset = $this._selectedIndex - $listH + 1
            }
            
            for ($displayRow = 0; $displayRow -lt $listH; $displayRow++) {
                $noteIdx = $displayRow + $this._scrollOffset
                if ($noteIdx -ge $this._notes.Count) { break }
                
                $note = $this._notes[$noteIdx]
                $rowY = $listY + $displayRow
                $isSelected = ($noteIdx -eq $this._selectedIndex)
                
                $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
                $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::Background }
                
                # Format: Title (date) - first line preview
                $title = if ($note['title']) { $note['title'] } else { "(Untitled)" }
                $date = ""
                if ($note['created']) {
                    try { $date = ([DateTime]::Parse($note['created'])).ToString("yyyy-MM-dd") } catch {}
                }
                
                $preview = ""
                if ($note['content']) {
                    $lines = $note['content'] -split "`n"
                    if ($lines.Count -gt 0) {
                        $preview = $lines[0]
                        if ($preview.Length -gt 40) { $preview = $preview.Substring(0, 37) + "..." }
                    }
                }
                
                $display = "$title ($date)"
                $maxWidth = $w - 6
                if ($display.Length -gt $maxWidth) { $display = $display.Substring(0, $maxWidth - 3) + "..." }
                
                $engine.WriteAt($x + 3, $rowY, $display.PadRight($maxWidth), $fg, $bg)
            }
        }
        
        # Status bar
        $statusY = $y + $h - 2
        $engine.Fill($x, $statusY, $w, 1, " ", [Colors]::Foreground, [Colors]::SelectionBg)
        $statusText = " [N] New  [Enter] Edit  [Delete] Remove  [Esc] Close"
        $engine.WriteAt($x, $statusY, $statusText, [Colors]::White, [Colors]::SelectionBg)
        
        $engine.EndLayer()
    }
    
    [string] HandleInput([ConsoleKeyInfo]$key, [HybridRenderEngine]$engine) {
        if (-not $this._visible) { return "Continue" }
        
        # If editing, NoteEditor handles input
        if ($this._editing -and $this._noteEditor) {
            # The edit loop happens in _EditNote, so this shouldn't be reached
            return "Continue"
        }
        
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
                if ($this._selectedIndex -lt $this._notes.Count - 1) {
                    $this._selectedIndex++
                }
                return "Continue"
            }
            'N' {
                $this._CreateNote($engine)
                return "Continue"
            }
            'Enter' {
                if ($this._notes.Count -gt 0) {
                    $this._EditNote($engine)
                }
                return "Continue"
            }
            'Delete' {
                if ($this._notes.Count -gt 0) {
                    $this._DeleteNote()
                }
                return "Continue"
            }
            'E' {
                if ($this._notes.Count -gt 0) {
                    $this._RenameNote($engine)
                }
                return "Continue"
            }
        }
        return "Continue"
    }
    
    hidden [void] _CreateNote([HybridRenderEngine]$engine) {
        # Create new note
        $newNote = @{
            id = [DataService]::NewGuid()
            projectId = $this._projectId
            title = "New Note"
            content = ""
            created = [DataService]::Timestamp()
            modified = [DataService]::Timestamp()
        }
        
        # Add to state
        $state = $this._store.GetState()
        if (-not $state.Data.ContainsKey('notes')) {
            $state.Data.notes = @()
        }
        $state.Data.notes += $newNote
        
        # Save
        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
        $this._LoadNotes()
        
        # Select and edit the new note
        $this._selectedIndex = $this._notes.Count - 1
        $this._EditNote($engine)
    }
    
    hidden [void] _EditNote([HybridRenderEngine]$engine) {
        if ($this._selectedIndex -ge $this._notes.Count) { return }
        
        try {
            $note = $this._notes[$this._selectedIndex]
            $content = if ($note['content']) { $note['content'] } else { "" }
            $title = if ($note['title']) { $note['title'] } else { "Note" }
            
            # Use the existing NoteEditor
            $editor = [NoteEditor]::new($content)
            
            # Configure Auto-Save
            $autosaveDir = Join-Path (Get-Location) "autosave"
            if (-not (Test-Path $autosaveDir)) { New-Item -ItemType Directory -Path $autosaveDir -Force | Out-Null }
            $autosavePath = Join-Path $autosaveDir "note_$($note.id).bak"
            
            # --- CRASH RECOVERY ---
            # If a backup exists, it means we exited uncleanly (or crash). Recover it.
            if (Test-Path $autosavePath) {
                try {
                    $recovered = Get-Content -Path $autosavePath -Raw -Encoding utf8
                    if (-not [string]::IsNullOrEmpty($recovered)) {
                        $content = $recovered
                        # Optionally notify user? For now, silent recovery is seamless.
                        # [Logger]::Log("Recovered note $($note.id) from backup")
                    }
                } catch {
                    [Logger]::Error("Failed to recover backup for note $($note.id)", $_)
                }
            }
            
            $editor = [NoteEditor]::new($content)
            $editor.SetAutoSavePath($autosavePath)
            
            $newContent = $editor.RenderAndEdit($engine, $title)
            
            # Clean up autosave if successful
            if ($null -ne $newContent -and (Test-Path $autosavePath)) {
                Remove-Item $autosavePath -Force -ErrorAction SilentlyContinue
            }
            
            if ($null -ne $newContent) {
                # Find and update the note in state
                $state = $this._store.GetState()
                foreach ($n in $state.Data.notes) {
                    if ($n['id'] -eq $note['id']) {
                        $n['content'] = $newContent
                        $n['modified'] = [DataService]::Timestamp()
                        break
                    }
                }
                $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
                $this._LoadNotes()
            }
        } catch {
            [Logger]::Error("NotesModal._EditNote: Crash detected!", $_)
            $engine.EndFrame() # Ensure frame is closed if crash happened mid-render
        }
    }
    
    hidden [void] _RenameNote([HybridRenderEngine]$engine) {
        if ($this._selectedIndex -ge $this._notes.Count) { return }
        $note = $this._notes[$this._selectedIndex]
        
        # Use simple InputBox (if available) or makeshift one
        # Ideally we'd have a reusable InputBox class?
        # For now, let's use a simple blocking read loop or just hacked logic
        # Actually, let's use the SmartEditor for a single line? Or just Read-Host style?
        # Read-Host is blocking and bypasses TUI. Bad.
        
        # Let's try to infer if we can assume InputLogic or similar exists.
        # Check TuiApp usage of SmartEditor...
        # For simplicity in this crunch time, let's just default to "Untitled" -> "Note <Date>"
        # OR: modify the title based on the first line of content?
        # User explicitly asked to "name" it.
        
        # HACK: Use NoteEditor on the title string itself!
        # It's a bit heavy but works.
        try {
            $editor = [NoteEditor]::new($note['title'])
            $newTitle = $editor.RenderAndEdit($engine, "Rename Note")
            if ($null -ne $newTitle) {
                # Update State
                $state = $this._store.GetState()
                foreach ($n in $state.Data.notes) {
                    if ($n['id'] -eq $note['id']) {
                        $n['title'] = $newTitle.Trim()
                        $n['modified'] = [DataService]::Timestamp()
                        break
                    }
                }
                $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
                $this._LoadNotes()
            }
        } catch {
             [Logger]::Error("NotesModal._RenameNote: Error", $_)
        }
    }

    hidden [void] _DeleteNote() {
        if ($this._selectedIndex -ge $this._notes.Count) { return }
        
        $note = $this._notes[$this._selectedIndex]
        
        # Remove from state
        $state = $this._store.GetState()
        $state.Data.notes = @($state.Data.notes | Where-Object { $_['id'] -ne $note['id'] })
        
        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
        $this._LoadNotes()
        
        # Adjust selection
        if ($this._selectedIndex -ge $this._notes.Count -and $this._selectedIndex -gt 0) {
            $this._selectedIndex--
        }
    }
}
