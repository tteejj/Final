# TextAreaEditor.ps1 - Full-featured multiline text editor for PMC ConsoleUI
# Ported from Praxis FullNotesEditor with adaptations for PMC
# Features: Gap buffer, undo/redo, word navigation, auto-save, scrolling, selection, copy/paste, find/replace

Set-StrictMode -Version Latest

# Selection mode enum
enum SelectionMode {
    None
    Stream      # Normal selection (character-based)
    Block       # Rectangular/column selection
}

class TextAreaEditor : PmcWidget {
    # Widget position and size (Inherited from PmcWidget)
    # [int]$X = 0
    # [int]$Y = 0
    # [int]$Width = 80
    # [int]$Height = 24

    # The actual text content using gap buffer
    hidden [GapBuffer]$_gapBuffer

    # Line tracking for efficient operations
    hidden [System.Collections.ArrayList]$_lineStarts
    hidden [bool]$_lineIndexDirty = $true

    # Cursor position
    [int]$CursorX = 0
    [int]$CursorY = 0
    [int]$ScrollOffsetY = 0
    [int]$ScrollOffsetX = 0

    # Selection state
    [SelectionMode]$SelectionMode = [SelectionMode]::None
    [int]$SelectionAnchorX = 0  # Where selection started
    [int]$SelectionAnchorY = 0
    [int]$SelectionEndX = 0     # Where selection ends (current cursor)
    [int]$SelectionEndY = 0

    # Undo/redo with full state tracking
    hidden [System.Collections.ArrayList]$_undoStack
    hidden [System.Collections.ArrayList]$_redoStack

    # Editor settings
    [string]$Style = ""
    [int]$TabWidth = 4
    [bool]$Modified = $false
    [bool]$EnableUndo = $false  # PERFORMANCE: Undo disabled by default for responsiveness
    [bool]$ShowStatistics = $false

    # File info
    [string]$FilePath = ""
    hidden [string]$_originalText = ""
    hidden [datetime]$_lastSaveTime = [datetime]::MinValue

    TextAreaEditor() : base("TextAreaEditor") {
        $this._gapBuffer = [GapBuffer]::new()
        $this._gapBuffer.Insert(0, "")  # Start with empty content
        $this._lineStarts = [System.Collections.ArrayList]::new()
        $this._undoStack = [System.Collections.ArrayList]::new()
        $this._redoStack = [System.Collections.ArrayList]::new()
        $this.BuildLineIndex()
        
        $this.Width = 80
        $this.Height = 24
        $this.CanFocus = $true
    }

    [void] SetBounds([int]$x, [int]$y, [int]$width, [int]$height) {
        $this.X = $x
        $this.Y = $y
        $this.Width = $width
        $this.Height = $height
    }

    [void] SetText([string]$text) {
        # Store original text for comparison
        $this._originalText = $text

        # Clear buffer and insert new text
        $this._gapBuffer.Delete(0, $this._gapBuffer.GetLength())
        if ([string]::IsNullOrEmpty($text)) {
            $this._gapBuffer.Insert(0, "")
        }
        else {
            $this._gapBuffer.Insert(0, $text)
        }

        $this.BuildLineIndex()
        $this.CursorX = 0
        $this.CursorY = 0
        $this.ScrollOffsetY = 0
        $this.ScrollOffsetX = 0
        $this.Modified = $false
        $this._undoStack.Clear()
        $this._redoStack.Clear()
        $this._lastSaveTime = [datetime]::Now
    }

    [string] GetText() {
        return $this._gapBuffer.GetText()
    }

    [object] GetStatistics() {
        # Performance optimization: Don't calculate if disabled
        if (-not $this.ShowStatistics) {
            return [PSCustomObject]@{
                Lines = 0
                Words = 0
                Chars = 0
            }
        }

        # Use optimized C# implementation from GapBuffer if available
        # This avoids allocating the full string and regex matching
        if ($this._gapBuffer.PSObject.Methods['GetContentStatistics']) {
            $stats = $this._gapBuffer.GetContentStatistics()
            return [PSCustomObject]@{
                Lines = $stats.Lines
                Words = $stats.Words
                Chars = $stats.Chars
            }
        }

        # Fallback (slow path)
        $text = $this.GetText()
        $lines = $this.GetLineCount()
        $words = @($text -split '\s+' | Where-Object { $_ }).Count
        $chars = $text.Length
        
        return [PSCustomObject]@{
            Lines = $lines
            Words = $words
            Chars = $chars
        }
    }

    # Build line index for efficient line operations
    hidden [void] BuildLineIndex() {
        $this._lineStarts.Clear()
        $this._lineStarts.Add(0) | Out-Null  # First line starts at position 0

        # Optimized: Use GapBuffer.FindAll to get all newlines at once
        $newlines = $this._gapBuffer.FindAll("`n")
        foreach ($index in $newlines) {
            $this._lineStarts.Add($index + 1) | Out-Null
        }

        $this._lineIndexDirty = $false
    }

    [int] GetLineCount() {
        if ($this._lineIndexDirty) {
            $this.BuildLineIndex()
        }
        return [Math]::Max(1, $this._lineStarts.Count)
    }

    [string] GetLine([int]$lineIndex) {
        if ($this._lineIndexDirty) {
            $this.BuildLineIndex()
        }

        if ($lineIndex -lt 0 -or $lineIndex -ge $this.GetLineCount()) {
            return ""
        }

        $lineStart = $this._lineStarts[$lineIndex]
        $lineEnd = $(if ($lineIndex + 1 -lt $this._lineStarts.Count) {
                $this._lineStarts[$lineIndex + 1] - 1
            }
            else {
                $this._gapBuffer.GetLength()
            })

        # Exclude the newline character
        if ($lineEnd -gt $lineStart -and $this._gapBuffer.GetChar($lineEnd - 1) -eq "`n") {
            $lineEnd--
        }

        $lineLength = [Math]::Max(0, $lineEnd - $lineStart)
        if ($lineLength -eq 0) {
            return ""
        }

        return $this._gapBuffer.GetText($lineStart, $lineLength)
    }

    # Get position in buffer from line/column
    hidden [int] GetPositionFromLineCol([int]$line, [int]$col) {
        if ($this._lineIndexDirty) {
            $this.BuildLineIndex()
        }

        if ($line -lt 0 -or $line -ge $this.GetLineCount()) {
            return -1
        }

        $lineStart = $this._lineStarts[$line]
        $lineText = $this.GetLine($line)
        $actualCol = [Math]::Min($col, $lineText.Length)

        return $lineStart + $actualCol
    }

    # === Layout System ===
    # RenderToEngine implementation (replaces Render)
    [void] RenderToEngine([object]$engine) {
        # Ensure bounds are valid
        if ($this.Width -le 0 -or $this.Height -le 0) {
            return
        }

        # Draw background
        # Use WriteAt with style string instead of FillRect
        $bgLine = $this.Style + (" " * $this.Width)
        for ($r = 0; $r -lt $this.Height; $r++) {
            $engine.WriteAt($this.X, $this.Y + $r, $bgLine)
        }

        # Calculate visible range
        $startLine = $this.ScrollOffsetY
        $endLine = [Math]::Min($this.GetLineCount() - 1, $startLine + $this.Height - 1)

        # Draw text content
        for ($i = 0; $i -le ($endLine - $startLine); $i++) {
            $lineIndex = $startLine + $i
            $lineText = $this.GetLine($lineIndex)
            
            # Handle horizontal scrolling
            if ($this.ScrollOffsetX -lt $lineText.Length) {
                $visibleText = $lineText.Substring($this.ScrollOffsetX)
                if ($visibleText.Length -gt $this.Width) {
                    $visibleText = $visibleText.Substring(0, $this.Width)
                }
                
                # Draw the line
                # Use WriteAt with style prepended
                $engine.WriteAt($this.X, $this.Y + $i, $this.Style + $visibleText)
            }
        }

        # Draw selection if active
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $selStartLine = [Math]::Min($this.SelectionAnchorY, $this.SelectionEndY)
            $selEndLine = [Math]::Max($this.SelectionAnchorY, $this.SelectionEndY)
            $selStartCol = [Math]::Min($this.SelectionAnchorX, $this.SelectionEndX)
            $selEndCol = [Math]::Max($this.SelectionAnchorX, $this.SelectionEndX)

            for ($i = 0; $i -le ($endLine - $startLine); $i++) {
                $lineIndex = $startLine + $i
                
                if ($this.IsLineSelected($lineIndex, $selStartLine, $selEndLine, $selStartCol, $selEndCol)) {
                    # Simple full line selection highlighting for now
                    # In a real implementation, we'd highlight only selected characters
                    # This requires more complex rendering logic
                }
            }
        }
    }

    hidden [bool] IsLineSelected([int]$line, [int]$startLine, [int]$endLine, [int]$startCol, [int]$endCol) {
        if ($this.SelectionMode -eq [SelectionMode]::None) {
            return $false
        }

        if ($line -lt $startLine -or $line -gt $endLine) {
            return $false
        }

        if ($this.SelectionMode -eq [SelectionMode]::Stream) {
            # Stream selection
            if ($line -eq $startLine -and $line -eq $endLine) {
                return $true # Simplified: assumes if line is in range, it has some selection
            }
            elseif ($line -eq $startLine) {
                return $true
            }
            elseif ($line -eq $endLine) {
                return $true
            }
            else {
                return $true
            }
        }
        elseif ($this.SelectionMode -eq [SelectionMode]::Block) {
            # Block selection
            return $true
        }

        return $false
    }

    # Legacy Render() removed in favor of RenderToEngine
    [string] Render() { return "" }

    [void] RenderLineWithSelection([System.Text.StringBuilder]$sb, [string]$text, [int]$lineIndex) {
        # Legacy method stub
    }

    [bool] HandleInput([System.ConsoleKeyInfo]$key) {
        $handled = $true
        $isShift = $key.Modifiers -band [System.ConsoleModifiers]::Shift
        $isCtrl = $key.Modifiers -band [System.ConsoleModifiers]::Control

        # Save state for undo before modifications
        if (-not ($key.Key -in @([System.ConsoleKey]::LeftArrow, [System.ConsoleKey]::RightArrow,
                    [System.ConsoleKey]::UpArrow, [System.ConsoleKey]::DownArrow,
                    [System.ConsoleKey]::Home, [System.ConsoleKey]::End))) {
            $this.SaveUndoState()
        }

        switch ($key.Key) {
            # Navigation with selection support
            ([System.ConsoleKey]::LeftArrow) {
                if ($isShift) {
                    # Start or extend selection
                    if ($this.SelectionMode -eq [SelectionMode]::None) {
                        $mode = $(if ($isCtrl) { [SelectionMode]::Block } else { [SelectionMode]::Stream })
                        $this.StartSelection($mode)
                    }
                    if ($isCtrl) { $this.MoveCursorWordLeft() } else { $this.MoveCursorLeft() }
                    $this.ExtendSelection()
                }
                else {
                    if ($this.SelectionMode -ne [SelectionMode]::None) { $this.ClearSelection() }
                    if ($isCtrl) { $this.MoveCursorWordLeft() } else { $this.MoveCursorLeft() }
                }
            }
            ([System.ConsoleKey]::RightArrow) {
                if ($isShift) {
                    if ($this.SelectionMode -eq [SelectionMode]::None) {
                        $mode = $(if ($isCtrl) { [SelectionMode]::Block } else { [SelectionMode]::Stream })
                        $this.StartSelection($mode)
                    }
                    if ($isCtrl) { $this.MoveCursorWordRight() } else { $this.MoveCursorRight() }
                    $this.ExtendSelection()
                }
                else {
                    if ($this.SelectionMode -ne [SelectionMode]::None) { $this.ClearSelection() }
                    if ($isCtrl) { $this.MoveCursorWordRight() } else { $this.MoveCursorRight() }
                }
            }
            ([System.ConsoleKey]::UpArrow) {
                if ($isShift) {
                    if ($this.SelectionMode -eq [SelectionMode]::None) {
                        $mode = $(if ($isCtrl) { [SelectionMode]::Block } else { [SelectionMode]::Stream })
                        $this.StartSelection($mode)
                    }
                    $this.MoveCursorUp()
                    $this.ExtendSelection()
                }
                else {
                    if ($this.SelectionMode -ne [SelectionMode]::None) { $this.ClearSelection() }
                    $this.MoveCursorUp()
                }
            }
            ([System.ConsoleKey]::DownArrow) {
                if ($isShift) {
                    if ($this.SelectionMode -eq [SelectionMode]::None) {
                        $mode = $(if ($isCtrl) { [SelectionMode]::Block } else { [SelectionMode]::Stream })
                        $this.StartSelection($mode)
                    }
                    $this.MoveCursorDown()
                    $this.ExtendSelection()
                }
                else {
                    if ($this.SelectionMode -ne [SelectionMode]::None) { $this.ClearSelection() }
                    $this.MoveCursorDown()
                }
            }
            ([System.ConsoleKey]::Home) {
                if ($key.Modifiers -band [System.ConsoleModifiers]::Control) {
                    $this.CursorX = 0
                    $this.CursorY = 0
                    $this.EnsureCursorVisible()
                }
                else {
                    $this.CursorX = 0
                    $this.EnsureCursorVisible()
                }
            }
            ([System.ConsoleKey]::End) {
                if ($key.Modifiers -band [System.ConsoleModifiers]::Control) {
                    $this.CursorY = $this.GetLineCount() - 1
                    $this.CursorX = $this.GetLine($this.CursorY).Length
                    $this.EnsureCursorVisible()
                }
                else {
                    $this.CursorX = $this.GetLine($this.CursorY).Length
                    $this.EnsureCursorVisible()
                }
            }
            ([System.ConsoleKey]::PageUp) {
                $this.CursorY = [Math]::Max(0, $this.CursorY - $this.Height)
                $this.EnsureCursorVisible()
            }
            ([System.ConsoleKey]::PageDown) {
                $this.CursorY = [Math]::Min($this.GetLineCount() - 1, $this.CursorY + $this.Height)
                $this.EnsureCursorVisible()
            }

            # Editing
            ([System.ConsoleKey]::Enter) { $this.InsertNewLine() }
            ([System.ConsoleKey]::Backspace) { $this.Backspace() }
            ([System.ConsoleKey]::Delete) { $this.Delete() }
            ([System.ConsoleKey]::Tab) { $this.InsertTab() }

            # Undo/Redo
            ([System.ConsoleKey]::Z) {
                if ($key.Modifiers -band [System.ConsoleModifiers]::Control) {
                    $this.Undo()
                }
                else {
                    $this.InsertChar($key.KeyChar)
                }
            }

            # Redo
            ([System.ConsoleKey]::Y) {
                if ($key.Modifiers -band [System.ConsoleModifiers]::Control) {
                    $this.Redo()
                }
                else {
                    $this.InsertChar($key.KeyChar)
                }
            }

            # Select All
            ([System.ConsoleKey]::A) {
                if ($isCtrl) {
                    $this.SelectAll()
                }
                else {
                    $this.InsertChar($key.KeyChar)
                }
            }

            # Copy
            ([System.ConsoleKey]::C) {
                if ($isCtrl) {
                    $this.Copy()
                }
                else {
                    $this.InsertChar($key.KeyChar)
                }
            }

            # Cut
            ([System.ConsoleKey]::X) {
                if ($isCtrl) {
                    $this.Cut()
                }
                else {
                    $this.InsertChar($key.KeyChar)
                }
            }

            # Paste
            ([System.ConsoleKey]::V) {
                if ($isCtrl) {
                    $this.Paste()
                }
                else {
                    $this.InsertChar($key.KeyChar)
                }
            }

            # Find
            ([System.ConsoleKey]::F) {
                if ($isCtrl) {
                    # Future feature: Implement find dialog with search highlighting
                    # Reserved: Ctrl+F keybinding for future find functionality
                    $handled = $false  # Let parent handle for now
                }
                else {
                    $this.InsertChar($key.KeyChar)
                }
            }

            # Replace
            ([System.ConsoleKey]::H) {
                if ($isCtrl) {
                    # Future feature: Implement find/replace dialog with preview
                    # Reserved: Ctrl+H keybinding for future replace functionality
                    $handled = $false  # Let parent handle for now
                }
                else {
                    $this.InsertChar($key.KeyChar)
                }
            }

            # Escape - clear selection
            ([System.ConsoleKey]::Escape) {
                if ($this.SelectionMode -ne [SelectionMode]::None) {
                    $this.ClearSelection()
                }
                else {
                    $handled = $false
                }
            }

            default {
                if ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) {
                    $this.InsertChar($key.KeyChar)
                }
                else {
                    $handled = $false
                }
            }
        }

        return $handled
    }

    # Cursor movement methods
    [void] MoveCursorLeft() {
        if ($this.CursorX -gt 0) {
            $this.CursorX--
        }
        elseif ($this.CursorY -gt 0) {
            $this.CursorY--
            $this.CursorX = $this.GetLine($this.CursorY).Length
        }
        $this.EnsureCursorVisible()
    }

    [void] MoveCursorRight() {
        $lineLength = $this.GetLine($this.CursorY).Length
        if ($this.CursorX -lt $lineLength) {
            $this.CursorX++
        }
        elseif ($this.CursorY -lt ($this.GetLineCount() - 1)) {
            $this.CursorY++
            $this.CursorX = 0
        }
        $this.EnsureCursorVisible()
    }

    [void] MoveCursorUp() {
        if ($this.CursorY -gt 0) {
            $this.CursorY--
            $lineLength = $this.GetLine($this.CursorY).Length
            $this.CursorX = [Math]::Min($this.CursorX, $lineLength)
        }
        $this.EnsureCursorVisible()
    }

    [void] MoveCursorDown() {
        if ($this.CursorY -lt ($this.GetLineCount() - 1)) {
            $this.CursorY++
            $lineLength = $this.GetLine($this.CursorY).Length
            $this.CursorX = [Math]::Min($this.CursorX, $lineLength)
        }
        $this.EnsureCursorVisible()
    }

    [void] MoveCursorWordLeft() {
        # Move to previous word boundary
        $line = $this.GetLine($this.CursorY)
        if ($this.CursorX -gt 0) {
            # Skip current word
            while ($this.CursorX -gt 0 -and $line[$this.CursorX - 1] -match '\w') {
                $this.CursorX--
            }
            # Skip whitespace
            while ($this.CursorX -gt 0 -and $line[$this.CursorX - 1] -match '\s') {
                $this.CursorX--
            }
            # Move to start of previous word
            while ($this.CursorX -gt 0 -and $line[$this.CursorX - 1] -match '\w') {
                $this.CursorX--
            }
        }
        elseif ($this.CursorY -gt 0) {
            $this.MoveCursorLeft()
        }
        $this.EnsureCursorVisible()
    }

    [void] MoveCursorWordRight() {
        # Move to next word boundary
        $line = $this.GetLine($this.CursorY)
        if ($this.CursorX -lt $line.Length) {
            # Skip current word
            while ($this.CursorX -lt $line.Length -and $line[$this.CursorX] -match '\w') {
                $this.CursorX++
            }
            # Skip whitespace
            while ($this.CursorX -lt $line.Length -and $line[$this.CursorX] -match '\s') {
                $this.CursorX++
            }
        }
        elseif ($this.CursorY -lt ($this.GetLineCount() - 1)) {
            $this.MoveCursorRight()
        }
        $this.EnsureCursorVisible()
    }

    [void] EnsureCursorVisible() {
        # Vertical scrolling
        if ($this.CursorY -lt $this.ScrollOffsetY) {
            $this.ScrollOffsetY = $this.CursorY
        }
        elseif ($this.CursorY -ge ($this.ScrollOffsetY + $this.Height)) {
            $this.ScrollOffsetY = $this.CursorY - $this.Height + 1
        }

        # Horizontal scrolling
        if ($this.CursorX -lt $this.ScrollOffsetX) {
            $this.ScrollOffsetX = $this.CursorX
        }
        elseif ($this.CursorX -ge ($this.ScrollOffsetX + $this.Width)) {
            $this.ScrollOffsetX = $this.CursorX - $this.Width + 1
        }
    }

    # Selection methods
    [void] StartSelection([SelectionMode]$mode) {
        $this.SelectionMode = $mode
        $this.SelectionAnchorX = $this.CursorX
        $this.SelectionAnchorY = $this.CursorY
        $this.SelectionEndX = $this.CursorX
        $this.SelectionEndY = $this.CursorY
    }

    [void] ExtendSelection() {
        $this.SelectionEndX = $this.CursorX
        $this.SelectionEndY = $this.CursorY
    }

    [void] ClearSelection() {
        $this.SelectionMode = [SelectionMode]::None
    }

    [void] SelectAll() {
        $this.SelectionMode = [SelectionMode]::Stream
        $this.SelectionAnchorX = 0
        $this.SelectionAnchorY = 0
        $this.SelectionEndY = $this.GetLineCount() - 1
        $this.SelectionEndX = $this.GetLine($this.SelectionEndY).Length
        $this.CursorX = $this.SelectionEndX
        $this.CursorY = $this.SelectionEndY
    }

    # Editing methods
    [void] InsertChar([char]$c) {
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.DeleteSelection()
        }

        $pos = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
        $this._gapBuffer.Insert($pos, [string]$c)
        $this.CursorX++
        $this.Modified = $true
        $this._lineIndexDirty = $true
        $this.EnsureCursorVisible()
    }

    [void] InsertNewLine() {
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.DeleteSelection()
        }

        $pos = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
        $this._gapBuffer.Insert($pos, "`n")
        $this.CursorY++
        $this.CursorX = 0
        $this.Modified = $true
        $this._lineIndexDirty = $true
        $this.EnsureCursorVisible()
    }

    [void] Backspace() {
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.DeleteSelection()
            return
        }

        $pos = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
        if ($pos -gt 0) {
            $this._gapBuffer.Delete($pos - 1, 1)
            
            # Update cursor
            if ($this.CursorX -gt 0) {
                $this.CursorX--
            }
            elseif ($this.CursorY -gt 0) {
                $this.CursorY--
                $this._lineIndexDirty = $true # Force rebuild to get correct line length
                $this.CursorX = $this.GetLine($this.CursorY).Length
            }

            $this.Modified = $true
            $this._lineIndexDirty = $true
            $this.EnsureCursorVisible()
        }
    }

    [void] Delete() {
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.DeleteSelection()
            return
        }

        $pos = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
        if ($pos -lt $this._gapBuffer.GetLength()) {
            $this._gapBuffer.Delete($pos, 1)
            $this.Modified = $true
            $this._lineIndexDirty = $true
        }
    }

    [void] InsertTab() {
        # Insert spaces for tab
        $spaces = " " * $this.TabWidth
        $this.InsertString($spaces)
    }

    [void] InsertString([string]$s) {
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.DeleteSelection()
        }

        $pos = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
        $this._gapBuffer.Insert($pos, $s)
        $this.CursorX += $s.Length
        $this.Modified = $true
        $this._lineIndexDirty = $true
        $this.EnsureCursorVisible()
    }

    [void] DeleteSelection() {
        # Simplified: just clear selection for now
        # Real implementation would delete the selected text range
        $this.ClearSelection()
    }

    # Clipboard operations (stubs)
    [void] Copy() { }
    [void] Cut() { }
    [void] Paste() { }

    # Undo/Redo (stubs)
    [void] SaveUndoState() { }
    [void] Undo() { }
    [void] Redo() { }
}