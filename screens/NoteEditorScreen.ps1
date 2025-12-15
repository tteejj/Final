# NoteEditorScreen.ps1 - Screen wrapper for TextAreaEditor
#
# Provides a full-screen note editing experience with:
# - TextAreaEditor widget for content editing
# - Breadcrumb header showing note title
# - Status bar showing stats and keyboard shortcuts
# - Auto-save on exit
#
# Usage:
#   $screen = [NoteEditorScreen]::new($noteId)
#   $global:PmcApp.PushScreen($screen)

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

class NoteEditorScreen : PmcScreen {
    # === Configuration ===
    hidden [string]$_noteId = ""
    hidden [object]$_note = $null
    hidden [NoteService]$_noteService = $null
    hidden [TextAreaEditor]$_editor = $null
    hidden [bool]$_saveOnExit = $true

    # === Constructor ===
    NoteEditorScreen([string]$noteId) : base("NoteEditor", "Note Editor") {
        Write-PmcTuiLog "NoteEditorScreen: Constructor called for noteId=$noteId" "INFO"

        $this._noteId = $noteId
        $this._noteService = [NoteService]::GetInstance()

        # Load note metadata
        Write-PmcTuiLog "NoteEditorScreen: Loading note metadata" "DEBUG"
        $this._note = $this._noteService.GetNote($noteId)
        if (-not $this._note) {
            Write-PmcTuiLog "NoteEditorScreen: Note not found: $noteId" "ERROR"
            throw "Note not found: $noteId"
        }

        # Update screen title
        $this.ScreenTitle = $this._note.title
        Write-PmcTuiLog "NoteEditorScreen: Title set to '$($this._note.title)'" "DEBUG"

        # Create TextAreaEditor widget
        Write-PmcTuiLog "NoteEditorScreen: Creating TextAreaEditor" "DEBUG"
        $this._editor = [TextAreaEditor]::new()

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest

        Write-PmcTuiLog "NoteEditorScreen: Constructor complete" "INFO"
    }

    NoteEditorScreen([string]$noteId, [object]$container) : base("NoteEditor", "Note Editor", $container) {
        Write-PmcTuiLog "NoteEditorScreen: Constructor called for noteId=$noteId" "INFO"

        $this._noteId = $noteId
        $this._noteService = [NoteService]::GetInstance()

        # Load note metadata
        Write-PmcTuiLog "NoteEditorScreen: Loading note metadata" "DEBUG"
        $this._note = $this._noteService.GetNote($noteId)
        if (-not $this._note) {
            Write-PmcTuiLog "NoteEditorScreen: Note not found: $noteId" "ERROR"
            throw "Note not found: $noteId"
        }

        # Update screen title
        $this.ScreenTitle = $this._note.title
        Write-PmcTuiLog "NoteEditorScreen: Title set to '$($this._note.title)'" "DEBUG"

        # Create TextAreaEditor widget
        Write-PmcTuiLog "NoteEditorScreen: Creating TextAreaEditor" "DEBUG"
        $this._editor = [TextAreaEditor]::new()

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via manifest

        Write-PmcTuiLog "NoteEditorScreen: Constructor complete" "INFO"
    }

    # === Lifecycle Methods ===

    [void] Initialize([object]$renderEngine) {
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Called" "INFO"

        $this.RenderEngine = $renderEngine

        # Get terminal size
        $this.TermWidth = $renderEngine.Width
        $this.TermHeight = $renderEngine.Height
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Terminal size $($this.TermWidth)x$($this.TermHeight)" "DEBUG"

        # Configure footer shortcuts AFTER initialization
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Configuring footer shortcuts" "DEBUG"
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Ctrl+S", "Save")
        $this.Footer.AddShortcut("Ctrl+L", "Checklist")
        $this.Footer.AddShortcut("Esc", "Back")
        # PERFORMANCE: Undo/Redo removed - disabled for responsiveness
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Footer shortcuts configured" "DEBUG"

        # Update header breadcrumb and position
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Setting Header.Y to 1 (was $($this.Header.Y))" "DEBUG"
        $this.Header.Y = 1  # Header starts at row 1 (after MenuBar at row 0)
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Header.Y is now $($this.Header.Y)" "DEBUG"
        $this.Header.SetBreadcrumb(@("Notes", $this._note.title))
        Write-PmcTuiLog "NoteEditorScreen.Initialize: After SetBreadcrumb, Header.Y is $($this.Header.Y)" "DEBUG"

        # Initialize layout manager
        if (-not $this.LayoutManager) {
            $this.LayoutManager = [PmcLayoutManager]::new()
        }

        # Calculate editor bounds
        # Layout: MenuBar (row 0) + Header (rows 1-5: title, blank, breadcrumb, blank, separator) + Editor + Footer + StatusBar
        # Header actually uses 5 rows: Y, Y+1(blank), Y+2(breadcrumb), Y+3(blank), Y+4(separator)
        $editorY = 6  # After menubar (row 0) and header (rows 1-5)
        $editorHeight = $this.TermHeight - 8  # Subtract menubar(1), header(5), footer(1), statusbar(1)
        $editorX = 0
        $editorWidth = $this.TermWidth

        Write-PmcTuiLog "NoteEditorScreen.Initialize: Setting editor bounds X=$editorX Y=$editorY W=$editorWidth H=$editorHeight" "DEBUG"
        $this._editor.SetBounds($editorX, $editorY, $editorWidth, $editorHeight)

        # NOTE: LoadData() removed from Initialize - it's called via OnEnter()
        # This prevents duplicate loading and follows proper lifecycle pattern

        Write-PmcTuiLog "NoteEditorScreen.Initialize: Complete" "INFO"
    }

    [void] LoadData() {
        Write-PmcTuiLog "NoteEditorScreen.LoadData: Loading note $($this._noteId)" "DEBUG"

        try {
            # Load content from file
            $content = $this._noteService.LoadNoteContent($this._noteId)

            # Set in editor
            $this._editor.SetText($content)

            Write-PmcTuiLog "NoteEditorScreen.LoadData: Loaded $($content.Length) characters" "DEBUG"

        }
        catch {
            Write-PmcTuiLog "NoteEditorScreen.LoadData: Error - $_" "ERROR"
            $this._editor.SetText("")
        }
    }

    [void] OnEnter() {
        # Call parent to ensure proper lifecycle (sets IsActive, calls LoadData, executes OnEnterHandler)
        ([PmcScreen]$this).OnEnter()

        # Additional screen-specific logic
        $this.UpdateStatusBar()
        # Force full screen clear for editor
        $this.NeedsClear = $true
    }

    [void] OnDoExit() {
        $this.IsActive = $false

        # Save on exit if modified
        if ($this._saveOnExit -and $this._editor.Modified) {
            $this.SaveNote()
        }
    }

    # === Rendering ===

    [void] RenderToEngine([object]$engine) {
        # Write-PmcTuiLog "NoteEditorScreen.RenderToEngine: Called - Header.Y=$($this.Header.Y)" "DEBUG"

        # FORCE Header.Y back to 1 since something keeps resetting it
        $this.Header.Y = 1
        
        # Render MenuBar (Layer 100)
        $engine.BeginLayer([ZIndex]::Dropdown)
        if ($this.MenuBar) {
            $this.MenuBar.RenderToEngine($engine)
        }

        # Render Header (Layer 50)
        $engine.BeginLayer([ZIndex]::Header)
        if ($this.Header) {
            $this.Header.RenderToEngine($engine)
        }

        # Render TextAreaEditor directly to engine (Layer 20 - Panel)
        $engine.BeginLayer([ZIndex]::Panel)
        $this._editor.RenderToEngine($engine)

        # Render Footer (Layer 55)
        $engine.BeginLayer([ZIndex]::Footer)
        if ($this.Footer) {
            $this.Footer.RenderToEngine($engine)
        }

        # Render StatusBar (Layer 65)
        $engine.BeginLayer([ZIndex]::StatusBar)
        if ($this.StatusBar) {
            $this.StatusBar.RenderToEngine($engine)
        }
    }

    # === Input Handling ===

    [bool] HandleKeyPress([ConsoleKeyInfo]$key) {
        # CRITICAL: Call parent FIRST for MenuBar, F10, Alt+keys, content widgets
        $handled = ([PmcScreen]$this).HandleKeyPress($key)
        if ($handled) { return $true }

        Write-PmcTuiLog "NoteEditorScreen.HandleKeyPress: Key=$($key.Key) Char=$($key.KeyChar) Modifiers=$($key.Modifiers)" "INFO"

        # Handle screen-level shortcuts first
        $ctrl = $key.Modifiers -band [ConsoleModifiers]::Control
        Write-PmcTuiLog "NoteEditorScreen.HandleKeyPress: Ctrl pressed=$ctrl" "INFO"

        # Ctrl+S - Save
        if ($ctrl -and $key.Key -eq [ConsoleKey]::S) {
            Write-PmcTuiLog "NoteEditorScreen: CTRL+S DETECTED - Saving" "INFO"
            $this.SaveNote()
            return $true
        }

        # Ctrl+L - Convert to Checklist
        if ($ctrl -and $key.Key -eq [ConsoleKey]::L) {
            Write-PmcTuiLog "NoteEditorScreen: CTRL+L DETECTED - Converting to checklist" "INFO"
            $this.ConvertToChecklist()
            return $true
        }

        # Escape - Go back (auto-save if modified)
        if ($key.Key -eq [ConsoleKey]::Escape) {
            if ($this._editor.Modified) {
                # Auto-save on exit - modern UX pattern
                $this.SaveNote()
                $this.SetStatusMessage("Note saved automatically", "info")
            }
            $global:PmcApp.PopScreen()
            return $true
        }

        # F10 - Menu
        if ($key.Key -eq [ConsoleKey]::F10) {
            if ($this.MenuBar) {
                $this.MenuBar.Activate()
                return $true
            }
        }

        # Delegate to editor
        Write-PmcTuiLog "NoteEditorScreen.HandleKeyPress: Delegating to editor" "DEBUG"
        $handled = $this._editor.HandleInput($key)
        Write-PmcTuiLog "NoteEditorScreen.HandleKeyPress: Editor returned handled=$handled" "DEBUG"

        # Update status bar after editor handles input
        if ($handled) {
            $this.UpdateStatusBar()
        }

        return $handled
    }

    # === Helper Methods ===

    hidden [void] SaveNote() {
        Write-PmcTuiLog "NoteEditorScreen.SaveNote: Saving note $($this._noteId)" "DEBUG"

        try {
            Write-PmcTuiLog "NoteEditorScreen.SaveNote: Getting text from editor" "DEBUG"
            $content = $this._editor.GetText()
            $contentLen = $(if ($null -eq $content) { "NULL" } else { $content.Length })
            Write-PmcTuiLog "NoteEditorScreen.SaveNote: Got content, length=$contentLen" "DEBUG"

            Write-PmcTuiLog "NoteEditorScreen.SaveNote: Calling SaveNoteContent" "DEBUG"
            $this._noteService.SaveNoteContent($this._noteId, $content)

            # Mark as not modified
            $this._editor.Modified = $false

            # Update status bar
            $this.UpdateStatusBar()

            Write-PmcTuiLog "NoteEditorScreen.SaveNote: Saved successfully" "INFO"
        }
        catch {
            Write-PmcTuiLog "NoteEditorScreen.SaveNote: Error - $_" "ERROR"
            $this.SetStatusMessage("Failed to save note: $($_.Exception.Message)", "error")
        }
    }

    hidden [void] ConvertToChecklist() {
        Write-PmcTuiLog "NoteEditorScreen.ConvertToChecklist: Starting conversion" "INFO"

        try {
            # Get note content
            $content = $this._editor.GetText()
            if ([string]::IsNullOrWhiteSpace($content)) {
                $this.SetStatusMessage("Note is empty - cannot convert to checklist", "warning")
                return
            }

            # Split by newlines and filter out empty lines
            $lines = @($content -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })

            if ($lines.Count -eq 0) {
                $this.SetStatusMessage("Note has no content lines", "warning")
                return
            }

            # Create checklist using ChecklistService
            . "$PSScriptRoot/../services/ChecklistService.ps1"
            $checklistService = [ChecklistService]::GetInstance()

            # Create checklist instance from note
            $title = $this._note.title + " (Checklist)"
            $instance = $checklistService.CreateBlankInstance($title, "note", $this._noteId, $lines)

            Write-PmcTuiLog "NoteEditorScreen.ConvertToChecklist: Created checklist $($instance.id)" "INFO"

            # Open checklist editor
            . "$PSScriptRoot/ChecklistEditorScreen.ps1"
            # Use New-Object to avoid parse-time type resolution
            $checklistScreen = New-Object ChecklistEditorScreen -ArgumentList $instance.id
            $global:PmcApp.PushScreen($checklistScreen)

            $this.SetStatusMessage("Converted to checklist with $($lines.Count) items", "success")

        }
        catch {
            Write-PmcTuiLog "NoteEditorScreen.ConvertToChecklist: ERROR - $($_.Exception.Message)" "ERROR"
            $this.SetStatusMessage("Failed to convert: $($_.Exception.Message)", "error")
        }
    }

    hidden [void] UpdateStatusBar() {
        if (-not $this.StatusBar) {
            return
        }

        try {
            # Optimized: Get stats directly from buffer
            $stats = $this._editor.GetStatistics()
            $lines = $stats.Lines
            $words = $stats.Words
            $chars = $stats.Chars

            # Build status message
            $modifiedFlag = $(if ($this._editor.Modified) { "*" } else { "" })
            $cursorPos = "Ln $($this._editor.CursorY + 1), Col $($this._editor.CursorX + 1)"
            $stats = "$lines lines, $words words, $chars chars"

            $this.StatusBar.SetLeftText("$modifiedFlag$cursorPos")
            $this.StatusBar.SetRightText($stats)
        }
        catch {
            Write-PmcTuiLog "NoteEditorScreen.UpdateStatusBar: Error - $_" "ERROR"
            # Set fallback status
            $this.StatusBar.SetLeftText("Ln 1, Col 1")
            $this.StatusBar.SetRightText("Ready")
        }
    }
}