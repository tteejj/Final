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
    [int]$TabWidth = 4
    [bool]$Modified = $false
    [bool]$EnableUndo = $false  # PERFORMANCE: Undo disabled by default for responsiveness

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

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)
        $engine.DefineRegion("$($this.RegionID)_Content", $this.X, $this.Y, $this.Width, $this.Height)
    }

    # Cell-based rendering for HybridRenderEngine
    [void] RenderToEngine([object]$engine) {
        $this.RegisterLayout($engine)
        
        $lineCount = $this.GetLineCount()
        
        # Colors (Ints)
        # Default colors
        $bg = $this.GetThemedColorInt('Background.Widget')
        $fg = $this.GetThemedColorInt('Foreground.Primary')
        $selBg = $this.GetThemedColorInt('Background.RowSelected') 
        $selFg = $this.GetThemedColorInt('Foreground.RowSelected')
        
        # Set clip to widget bounds
        $engine.PushClip($this.X, $this.Y, $this.Width, $this.Height)
        
        # Fill background
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)

        # Render each visible line
        for ($i = 0; $i -lt $this.Height; $i++) {
            $lineIndex = $this.ScrollOffsetY + $i
            $screenY = $this.Y + $i

            if ($lineIndex -lt $lineCount) {
                $line = $this.GetLine($lineIndex)

                # Handle horizontal scrolling
                $startCol = $this.ScrollOffsetX
                $endCol = [Math]::Min($startCol + $this.Width, $line.Length)

                # Render visible portion of line
                for ($col = $startCol; $col -lt $endCol; $col++) {
                    $screenX = $this.X + ($col - $startCol)
                    $char = $line[$col]

                    # Check if this character is in selection
                    if ($this.SelectionMode -ne [SelectionMode]::None -and
                        $this.IsCharInSelection($lineIndex, $col)) {
                        $engine.WriteAt($screenX, $screenY, $char, $selFg, $selBg)
                    }
                    else {
                        $engine.WriteAt($screenX, $screenY, $char, $fg, $bg)
                    }
                }
            }
        }

        # Position cursor
        $cursorScreenX = $this.X + $this.CursorX - $this.ScrollOffsetX
        $cursorScreenY = $this.Y + $this.CursorY - $this.ScrollOffsetY

        if ($cursorScreenX -ge $this.X -and $cursorScreenX -lt ($this.X + $this.Width) -and
            $cursorScreenY -ge $this.Y -and $cursorScreenY -lt ($this.Y + $this.Height)) {
            
            # Get char at cursor
            $charAtCursor = ' '
            $cursorLineIndex = $this.CursorY
            if ($cursorLineIndex -lt $this.GetLineCount()) {
                $line = $this.GetLine($cursorLineIndex)
                if ($this.CursorX -lt $line.Length) {
                    $charAtCursor = $line[$this.CursorX]
                }
            }

            # Invert colors for cursor (Block cursor)
            $engine.WriteAt($cursorScreenX, $cursorScreenY, $charAtCursor, $bg, $fg) # Swapped FG/BG
        }
        
        $engine.PopClip()
    }

    # Helper to check if a character is in selection
    hidden [bool] IsCharInSelection([int]$line, [int]$col) {
        if ($this.SelectionMode -eq [SelectionMode]::None) {
            return $false
        }

        $startLine = [Math]::Min($this.SelectionAnchorY, $this.SelectionEndY)
        $endLine = [Math]::Max($this.SelectionAnchorY, $this.SelectionEndY)
        $startCol = [Math]::Min($this.SelectionAnchorX, $this.SelectionEndX)
        $endCol = [Math]::Max($this.SelectionAnchorX, $this.SelectionEndX)

        if ($line -lt $startLine -or $line -gt $endLine) {
            return $false
        }

        if ($this.SelectionMode -eq [SelectionMode]::Stream) {
            # Stream selection
            if ($line -eq $startLine -and $line -eq $endLine) {
                return $col -ge $startCol -and $col -lt $endCol
            }
            elseif ($line -eq $startLine) {
                return $col -ge $startCol
            }
            elseif ($line -eq $endLine) {
                return $col -lt $endCol
            }
            else {
                return $true
            }
        }
        elseif ($this.SelectionMode -eq [SelectionMode]::Block) {
            # Block selection
            return $col -ge $startCol -and $col -lt $endCol
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

    # Editing methods using gap buffer
    [void] InsertChar([char]$char) {
        # If there's a selection, delete it first
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.DeleteSelection()
        }

        $position = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
        $this._gapBuffer.Insert($position, $char.ToString())
        $this._lineIndexDirty = $true
        $this.CursorX++
        $this.Modified = $true
        $this.EnsureCursorVisible()
    }

    [void] InsertNewLine() {
        # If there's a selection, delete it first
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.DeleteSelection()
        }

        $position = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
        $this._gapBuffer.Insert($position, "`n")
        $this._lineIndexDirty = $true
        $this.CursorY++
        $this.CursorX = 0
        $this.Modified = $true
        $this.EnsureCursorVisible()
    }

    [void] InsertTab() {
        # If there's a selection, delete it first
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.DeleteSelection()
        }

        $spaces = " " * $this.TabWidth
        $position = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
        $this._gapBuffer.Insert($position, $spaces)
        $this._lineIndexDirty = $true
        $this.CursorX += $this.TabWidth
        $this.Modified = $true
        $this.EnsureCursorVisible()
    }

    [void] Backspace() {
        # If there's a selection, delete it instead
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.DeleteSelection()
            return
        }

        if ($this.CursorX -gt 0) {
            $position = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX - 1)
            $this._gapBuffer.Delete($position, 1)
            $this._lineIndexDirty = $true
            $this.CursorX--
            $this.Modified = $true
        }
        elseif ($this.CursorY -gt 0) {
            # Join with previous line
            $this.CursorY--
            $this.CursorX = $this.GetLine($this.CursorY).Length
            $position = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
            $this._gapBuffer.Delete($position, 1)  # Delete the newline
            $this._lineIndexDirty = $true
            $this.Modified = $true
        }
        $this.EnsureCursorVisible()
    }

    [void] Delete() {
        # If there's a selection, delete it instead
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.DeleteSelection()
            return
        }

        $lineLength = $this.GetLine($this.CursorY).Length
        if ($this.CursorX -lt $lineLength) {
            $position = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
            $this._gapBuffer.Delete($position, 1)
            $this._lineIndexDirty = $true
            $this.Modified = $true
        }
        elseif ($this.CursorY -lt ($this.GetLineCount() - 1)) {
            # Join with next line
            $position = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
            $this._gapBuffer.Delete($position, 1)  # Delete the newline
            $this._lineIndexDirty = $true
            $this.Modified = $true
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
        if ($this.SelectionMode -ne [SelectionMode]::None) {
            $this.SelectionEndX = $this.CursorX
            $this.SelectionEndY = $this.CursorY
        }
    }

    [void] ClearSelection() {
        $this.SelectionMode = [SelectionMode]::None
        $this.SelectionAnchorX = 0
        $this.SelectionAnchorY = 0
        $this.SelectionEndX = 0
        $this.SelectionEndY = 0
    }

    [void] SelectAll() {
        $this.SelectionMode = [SelectionMode]::Stream
        $this.SelectionAnchorX = 0
        $this.SelectionAnchorY = 0
        $lastLine = $this.GetLineCount() - 1
        $this.SelectionEndY = $lastLine
        $this.SelectionEndX = $this.GetLine($lastLine).Length
    }

    [string] GetSelectedText() {
        if ($this.SelectionMode -eq [SelectionMode]::None) {
            return ""
        }

        $startLine = [Math]::Min($this.SelectionAnchorY, $this.SelectionEndY)
        $endLine = [Math]::Max($this.SelectionAnchorY, $this.SelectionEndY)
        $startCol = [Math]::Min($this.SelectionAnchorX, $this.SelectionEndX)
        $endCol = [Math]::Max($this.SelectionAnchorX, $this.SelectionEndX)

        if ($this.SelectionMode -eq [SelectionMode]::Stream) {
            # Stream selection (normal)
            $text = ""
            for ($line = $startLine; $line -le $endLine; $line++) {
                $lineText = $this.GetLine($line)
                if ($line -eq $startLine -and $line -eq $endLine) {
                    # Single line
                    if ($startCol -lt $lineText.Length) {
                        $length = [Math]::Min($endCol - $startCol, $lineText.Length - $startCol)
                        $text += $lineText.Substring($startCol, $length)
                    }
                }
                elseif ($line -eq $startLine) {
                    # First line
                    if ($startCol -lt $lineText.Length) {
                        $text += $lineText.Substring($startCol) + "`n"
                    }
                    else {
                        $text += "`n"
                    }
                }
                elseif ($line -eq $endLine) {
                    # Last line
                    if ($endCol -gt 0 -and $endCol -le $lineText.Length) {
                        $text += $lineText.Substring(0, $endCol)
                    }
                    elseif ($endCol -gt $lineText.Length) {
                        $text += $lineText
                    }
                }
                else {
                    # Middle lines
                    $text += $lineText + "`n"
                }
            }
            return $text
        }
        elseif ($this.SelectionMode -eq [SelectionMode]::Block) {
            # Block selection (rectangular)
            $lines = @()
            for ($line = $startLine; $line -le $endLine; $line++) {
                $lineText = $this.GetLine($line)
                if ($startCol -lt $lineText.Length) {
                    $extractEnd = [Math]::Min($endCol, $lineText.Length)
                    $lines += $lineText.Substring($startCol, $extractEnd - $startCol)
                }
                else {
                    $lines += ""
                }
            }
            return $lines -join "`n"
        }

        return ""
    }

    [void] DeleteSelection() {
        if ($this.SelectionMode -eq [SelectionMode]::None) {
            return
        }

        $startLine = [Math]::Min($this.SelectionAnchorY, $this.SelectionEndY)
        $endLine = [Math]::Max($this.SelectionAnchorY, $this.SelectionEndY)
        $startCol = [Math]::Min($this.SelectionAnchorX, $this.SelectionEndX)
        $endCol = [Math]::Max($this.SelectionAnchorX, $this.SelectionEndX)

        if ($this.SelectionMode -eq [SelectionMode]::Stream) {
            # Delete stream selection
            $startPos = $this.GetPositionFromLineCol($startLine, $startCol)
            $endPos = $this.GetPositionFromLineCol($endLine, $endCol)
            if ($startPos -ge 0 -and $endPos -ge 0 -and $endPos > $startPos) {
                $this._gapBuffer.Delete($startPos, $endPos - $startPos)
                $this._lineIndexDirty = $true

                # Move cursor to start of deleted region
                $this.CursorY = $startLine
                $this.CursorX = $startCol
            }
        }
        elseif ($this.SelectionMode -eq [SelectionMode]::Block) {
            # Delete block selection (delete from each line)
            for ($line = $endLine; $line -ge $startLine; $line--) {
                $lineText = $this.GetLine($line)
                if ($startCol -lt $lineText.Length) {
                    $deleteCount = [Math]::Min($endCol - $startCol, $lineText.Length - $startCol)
                    $pos = $this.GetPositionFromLineCol($line, $startCol)
                    if ($pos -ge 0) {
                        $this._gapBuffer.Delete($pos, $deleteCount)
                    }
                }
            }
            $this._lineIndexDirty = $true

            # Move cursor to top-left of block
            $this.CursorY = $startLine
            $this.CursorX = $startCol
        }

        $this.ClearSelection()
        $this.Modified = $true
    }

    # Copy/Paste/Cut
    [void] Copy() {
        $selectedText = $this.GetSelectedText()
        if (-not [string]::IsNullOrEmpty($selectedText)) {
            try {
                Set-Clipboard -Value $selectedText
            }
            catch {
                # Clipboard access may fail - silently ignore
            }
        }
    }

    [void] Cut() {
        $selectedText = $this.GetSelectedText()
        if (-not [string]::IsNullOrEmpty($selectedText)) {
            try {
                Set-Clipboard -Value $selectedText
                $this.DeleteSelection()
            }
            catch {
                # Clipboard access may fail - silently ignore
            }
        }
    }

    [void] Paste() {
        try {
            $clipboardText = Get-Clipboard -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrEmpty($clipboardText)) {
                # If there's a selection, delete it first
                if ($this.SelectionMode -ne [SelectionMode]::None) {
                    $this.DeleteSelection()
                }

                # Insert clipboard text at cursor
                $position = $this.GetPositionFromLineCol($this.CursorY, $this.CursorX)
                if ($position -ge 0) {
                    $this._gapBuffer.Insert($position, $clipboardText)
                    $this._lineIndexDirty = $true
                    $this.Modified = $true

                    # Move cursor to end of pasted text
                    $lines = $clipboardText -split "`n"
                    if ($lines.Count -gt 1) {
                        $this.CursorY += $lines.Count - 1
                        $this.CursorX = $lines[-1].Length
                    }
                    else {
                        $this.CursorX += $clipboardText.Length
                    }

                    $this.EnsureCursorVisible()
                }
            }
        }
        catch {
            # Clipboard access may fail - silently ignore
        }
    }

    # Undo/Redo
    [void] SaveUndoState() {
        # PERFORMANCE: Skip if undo is disabled
        if (-not $this.EnableUndo) {
            return
        }

        $state = @{
            Text    = $this._gapBuffer.GetText()
            CursorX = $this.CursorX
            CursorY = $this.CursorY
        }
        $this._undoStack.Add($state) | Out-Null
        $this._redoStack.Clear()

        # Limit undo stack size
        if ($this._undoStack.Count -gt 100) {
            $this._undoStack.RemoveAt(0)
        }
    }

    [void] Undo() {
        # PERFORMANCE: Skip if undo is disabled
        if (-not $this.EnableUndo) {
            return
        }

        if ($this._undoStack.Count -gt 0) {
            # Save current state to redo stack
            $currentState = @{
                Text    = $this._gapBuffer.GetText()
                CursorX = $this.CursorX
                CursorY = $this.CursorY
            }
            $this._redoStack.Add($currentState) | Out-Null

            # Restore previous state
            $state = $this._undoStack[$this._undoStack.Count - 1]
            $this._undoStack.RemoveAt($this._undoStack.Count - 1)

            $this.SetText($state.Text)
            $this.CursorX = $state.CursorX
            $this.CursorY = $state.CursorY
            $this.Modified = $true
            $this.EnsureCursorVisible()
        }
    }

    [void] Redo() {
        if ($this._redoStack.Count -gt 0) {
            # Save current state to undo stack
            $currentState = @{
                Text    = $this._gapBuffer.GetText()
                CursorX = $this.CursorX
                CursorY = $this.CursorY
            }
            $this._undoStack.Add($currentState) | Out-Null

            # Restore next state
            $state = $this._redoStack[$this._redoStack.Count - 1]
            $this._redoStack.RemoveAt($this._redoStack.Count - 1)

            $this.SetText($state.Text)
            $this.CursorX = $state.CursorX
            $this.CursorY = $state.CursorY
            $this.Modified = $true
            $this.EnsureCursorVisible()
        }
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

    # File operations
    [void] LoadFromFile([string]$path) {
        try {
            if (Test-Path $path) {
                $content = Get-Content -Path $path -Raw -ErrorAction Stop
                $this.SetText($content)
                $this.FilePath = $path
                $this.Modified = $false
            }
            else {
                $this.SetText("")
                $this.FilePath = $path
                $this.Modified = $false
            }
        }
        catch {
            throw "Failed to load file: $($_.Exception.Message)"
        }
    }

    [void] SaveToFile() {
        if ([string]::IsNullOrEmpty($this.FilePath)) {
            throw "No file path specified"
        }

        $this.SaveToFile($this.FilePath)
    }

    [void] SaveToFile([string]$path) {
        try {
            # Atomic save: write to temp file, then rename
            $tempFile = "$path.tmp"
            $content = $this.GetText()

            [System.IO.File]::WriteAllText($tempFile, $content, [System.Text.Encoding]::UTF8)

            # Atomic rename
            Move-Item -Path $tempFile -Destination $path -Force

            $this.FilePath = $path
            $this._originalText = $content
            $this.Modified = $false
            $this._lastSaveTime = [datetime]::Now
        }
        catch {
            # Clean up temp file if it exists
            if (Test-Path "$path.tmp") {
                Remove-Item -Path "$path.tmp" -Force -ErrorAction SilentlyContinue
            }
            throw "Failed to save file: $($_.Exception.Message)"
        }
    }

    [bool] HasUnsavedChanges() {
        if (-not $this.Modified) {
            return $false
        }

        $currentText = $this.GetText()
        return $currentText -ne $this._originalText
    }

    # Statistics for status bar
    [hashtable] GetStatistics() {
        return $this._gapBuffer.GetContentStatistics()
    }

    [int] GetWordCount() {
        return $this.GetStatistics().Words
    }
}