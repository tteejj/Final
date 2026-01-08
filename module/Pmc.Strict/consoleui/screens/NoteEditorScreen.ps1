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

# Ensure TextAreaEditor is loaded
if (-not ([System.Management.Automation.PSTypeName]'TextAreaEditor').Type) {
    . "$PSScriptRoot/../widgets/TextAreaEditor.ps1"
}

class NoteEditorScreen : PmcScreen {
    # === Configuration ===
    hidden [string]$_noteId = ""
    hidden [object]$_note = $null
    hidden [FileNoteService]$_noteService = $null
    hidden [TextAreaEditor]$_editor = $null
    hidden [bool]$_saveOnExit = $true

    # === Constructor ===
    NoteEditorScreen([string]$noteId) : base("NoteEditor", "Note Editor") {
        Write-PmcTuiLog "NoteEditorScreen: Constructor called for noteId=$noteId" "INFO"

        $this._noteId = $noteId
        $this._noteService = [FileNoteService]::GetInstance()

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

        Write-PmcTuiLog "NoteEditorScreen: Constructor complete" "INFO"
    }

    NoteEditorScreen([string]$noteId, [object]$container) : base("NoteEditor", "Note Editor", $container) {
        Write-PmcTuiLog "NoteEditorScreen: Constructor called for noteId=$noteId" "INFO"

        $this._noteId = $noteId
        $this._noteService = [FileNoteService]::GetInstance()

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

        Write-PmcTuiLog "NoteEditorScreen: Constructor complete" "INFO"
    }

    # === Lifecycle Methods ===

    [void] Initialize([object]$renderEngine, [object]$container) {
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Called with renderEngine and container" "INFO"

        $this.RenderEngine = $renderEngine
        $this.Container = $container

        # Get terminal size
        $this.TermWidth = $renderEngine.Width
        $this.TermHeight = $renderEngine.Height
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Terminal size $($this.TermWidth)x$($this.TermHeight)" "DEBUG"

        # Initialize layout manager
        if (-not $this.LayoutManager) {
            $this.LayoutManager = [PmcLayoutManager]::new()
        }

        # Configure footer shortcuts
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Configuring footer" "DEBUG"
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Ctrl+S", "Save")
        $this.Footer.AddShortcut("Ctrl+L", "Checklist")
        $this.Footer.AddShortcut("Esc", "Back")
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Footer shortcuts configured" "DEBUG"

        # Use layout manager for Header positioning
        $headerRect = $this.LayoutManager.GetRegion('Header', $this.TermWidth, $this.TermHeight)
        $this.Header.X = $headerRect.X
        $this.Header.Y = $headerRect.Y
        $this.Header.Width = $headerRect.Width
        $this.Header.Height = $headerRect.Height
        $this.Header.SetBreadcrumb(@("Notes", $this._note.title))
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Header via LayoutManager - X=$($headerRect.X) Y=$($headerRect.Y) W=$($headerRect.Width) H=$($headerRect.Height)" "DEBUG"

        # Use layout manager for Footer positioning
        $footerRect = $this.LayoutManager.GetRegion('Footer', $this.TermWidth, $this.TermHeight)
        $this.Footer.X = $footerRect.X
        $this.Footer.Y = $footerRect.Y
        $this.Footer.Width = $footerRect.Width
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Footer via LayoutManager - X=$($footerRect.X) Y=$($footerRect.Y) W=$($footerRect.Width)" "DEBUG"

        # Use layout manager for StatusBar positioning
        $statusBarRect = $this.LayoutManager.GetRegion('StatusBar', $this.TermWidth, $this.TermHeight)
        $this.StatusBar.X = $statusBarRect.X
        $this.StatusBar.Y = $statusBarRect.Y
        $this.StatusBar.Width = $statusBarRect.Width
        Write-PmcTuiLog "NoteEditorScreen.Initialize: StatusBar via LayoutManager - X=$($statusBarRect.X) Y=$($statusBarRect.Y) W=$($statusBarRect.Width)" "DEBUG"

        # Use layout manager for Content (editor) positioning
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)
        $this._editor.SetBounds($contentRect.X, $contentRect.Y, $contentRect.Width, $contentRect.Height)
        Write-PmcTuiLog "NoteEditorScreen.Initialize: Editor via LayoutManager - X=$($contentRect.X) Y=$($contentRect.Y) W=$($contentRect.Width) H=$($contentRect.Height)" "DEBUG"

        # Check preferences for statistics
        $prefs = [PreferencesService]::GetInstance()
        $showStats = $prefs.GetPreference('showEditorStatistics', $false)
        $this._editor.ShowStatistics = $showStats
        $this._editor.ShowCursor = $true  # Enable cursor visibility

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
    }

    [void] RenderToEngine([object]$engine) {
        # BACKGROUND FILL: Render themed background first (Layer 0)
        $engine.BeginLayer([ZIndex]::Background)
        $bgColor = $this.GetThemedInt('Background.Primary')
        for ($y = 0; $y -lt $this.TermHeight; $y++) {
            $engine.WriteAt(0, $y, (' ' * $this.TermWidth), $bgColor, $bgColor)
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

        # Render MenuBar (Layer 100 - Dropdown)
        # CRITICAL: Render MenuBar LAST with highest z-index
        $engine.BeginLayer([ZIndex]::Dropdown)
        if ($this.MenuBar) {
            $this.MenuBar.RenderToEngine($engine)
        }
    }

    # === Input Handling ===

    [bool] HandleKeyPress([ConsoleKeyInfo]$key) {
        # Handle screen-level shortcuts FIRST before parent or editor
        $ctrl = $key.Modifiers -band [ConsoleModifiers]::Control

        # Escape - Go back with auto-save
        if ($key.Key -eq [ConsoleKey]::Escape) {
            Write-PmcTuiLog "NoteEditorScreen: ESCAPE DETECTED - Auto-saving and exiting" "INFO"
            if ($this._editor.Modified) {
                try {
                    $this.SaveNote()
                    Write-PmcTuiLog "NoteEditorScreen: Note saved successfully" "INFO"
                }
                catch {
                    Write-PmcTuiLog "NoteEditorScreen: ERROR during auto-save - $_" "ERROR"
                    # Continue with exit even if save fails
                }
            }
            $global:PmcApp.PopScreen()
            return $true
        }

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

        # CRITICAL: Call parent for MenuBar, F10, Alt+keys, content widgets
        $handled = ([PmcScreen]$this).HandleKeyPress($key)
        if ($handled) { return $true }

        # F10 - Menu
        if ($key.Key -eq [ConsoleKey]::F10) {
            if ($this.MenuBar) {
                $this.MenuBar.Activate()
                return $true
            }
        }

        # Delegate to editor
        $handled = $this._editor.HandleInput($key)

        # Update status bar after editor handles input
        if ($handled) {
            $this.UpdateStatusBar()
        }

        return $handled
    }

    [void] SaveNote() {
        Write-PmcTuiLog "NoteEditorScreen.SaveNote: Saving note $($this._noteId)" "INFO"
        
        $content = $this._editor.GetText()
        Write-PmcTuiLog "NoteEditorScreen.SaveNote: Content length = $($content.Length)" "DEBUG"
        
        $this._noteService.SaveNoteContent($this._noteId, $content)
        $this._editor.Modified = $false
        
        $this.ShowSuccess("Note saved", $false)
        $this.UpdateStatusBar()
    }

    [void] ConvertToChecklist() {
        try {
            # Get note content
            $content = $this._editor.GetText()
            if ([string]::IsNullOrWhiteSpace($content)) {
                Write-PmcTuiLog "NoteEditorScreen.ConvertToChecklist: Note is empty" "WARN"
                return
            }

            # Split by newlines and filter out empty lines
            $lines = @($content -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })

            if ($lines.Count -eq 0) {
                Write-PmcTuiLog "NoteEditorScreen.ConvertToChecklist: No content lines" "WARN"
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

            Write-PmcTuiLog "NoteEditorScreen.ConvertToChecklist: Converted to checklist with $($lines.Count) items" "INFO"

        }
        catch {
            Write-PmcTuiLog "NoteEditorScreen.ConvertToChecklist: ERROR - $($_.Exception.Message)" "ERROR"
            Write-PmcTuiLog "NoteEditorScreen.ConvertToChecklist: Stack trace - $($_.ScriptStackTrace)" "ERROR"
        }
    }

    hidden [void] UpdateStatusBar() {
        if (-not $this.StatusBar) {
            return
        }

        try {
            # Build status message
            $modifiedFlag = $(if ($this._editor.Modified) { "*" } else { "" })
            $cursorPos = "Ln $($this._editor.CursorY + 1), Col $($this._editor.CursorX + 1)"
            
            # Optimized: Only get stats if enabled
            if ($this._editor.ShowStatistics) {
                $stats = $this._editor.GetStatistics()
                $lines = $stats.Lines
                $words = $stats.Words
                $chars = $stats.Chars
                $statsText = "$lines lines, $words words, $chars chars"
            } else {
                $statsText = ""
            }

            $this.StatusBar.SetLeftText("$modifiedFlag$cursorPos")
            $this.StatusBar.SetRightText($statsText)
        }
        catch {
            Write-PmcTuiLog "NoteEditorScreen.UpdateStatusBar: Error - $_" "ERROR"
            # Set fallback status
            $this.StatusBar.SetLeftText("Ln 1, Col 1")
            $this.StatusBar.SetRightText("Ready")
        }
    }
}
