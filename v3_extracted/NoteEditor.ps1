# NoteEditor.ps1 - Multiline Editor using GapBuffer with Selection Support
using namespace System.Text
using namespace System.Collections.Generic

class EditorState {
    [string] $Text
    [int] $CursorPos
}

class NoteEditor {
    hidden [GapBuffer]$_buffer
    hidden [int]$_cursorPos
    hidden [int]$_scrollRow

    # Selection State
    # -1 means no selection. If >= 0, selection is between Anchor and CursorPos
    hidden [int]$_selectionAnchor = -1

    # Undo/Redo Stacks
    hidden [Stack[EditorState]]$_undoStack
    hidden [Stack[EditorState]]$_redoStack

    # Auto-Save State
    hidden [string]$_autoSavePath = $null
    hidden [datetime]$_lastSaveTime = [DateTime]::MinValue
    hidden [bool]$_dirty = $false

    # Internal Clipboard (Shared across all editor instances)
    static hidden [string]$_clipboard = ""

    NoteEditor([string]$text) {
        $this._buffer = [GapBuffer]::new($text)
        $this._cursorPos = $text.Length
        $this._scrollRow = 0
        $this._lastSaveTime = [DateTime]::Now

        $this._undoStack = [Stack[EditorState]]::new()
        $this._redoStack = [Stack[EditorState]]::new()
    }

    [void] SetAutoSavePath([string]$path) {
        $this._autoSavePath = $path
    }

    [void] _SaveUndoState() {
        # Create lightweight snapshot
        $state = [EditorState]::new()
        $state.Text = $this._buffer.GetText()
        $state.CursorPos = $this._cursorPos

        $this._undoStack.Push($state)

        # Limit stack depth to prevent infinite memory growth
        if ($this._undoStack.Count -gt 50) {
            # Stack doesn't support RemoveLast easily.
            # For now, we accept 50 steps deep.
        }

        # New action invalidates Redo history
        $this._redoStack.Clear()
    }

    [void] _Undo() {
        if ($this._undoStack.Count -gt 0) {
            # Save current state to Redo
            $current = [EditorState]::new()
            $current.Text = $this._buffer.GetText()
            $current.CursorPos = $this._cursorPos
            $this._redoStack.Push($current)

            # Apply Undo
            $prev = $this._undoStack.Pop()
            $this._buffer = [GapBuffer]::new($prev.Text)
            $this._cursorPos = $prev.CursorPos
            $this._dirty = $true
        }
    }

    [void] _Redo() {
        if ($this._redoStack.Count -gt 0) {
            # Save current state to Undo
            $current = [EditorState]::new()
            $current.Text = $this._buffer.GetText()
            $current.CursorPos = $this._cursorPos
            $this._undoStack.Push($current)

            # Apply Redo
            $next = $this._redoStack.Pop()
            $this._buffer = [GapBuffer]::new($next.Text)
            $this._cursorPos = $next.CursorPos
            $this._dirty = $true
        }
    }

    [void] _MoveWordLeft([bool]$select) {
        if ($select) {
            if ($this._selectionAnchor -eq -1) { $this._selectionAnchor = $this._cursorPos }
        } else {
            $this._selectionAnchor = -1
        }

        $text = $this._buffer.GetText()
        if ($this._cursorPos -gt 0) {
            $pos = $this._cursorPos
            # Skip current whitespace
            while ($pos -gt 0 -and [char]::IsWhiteSpace($text[$pos - 1])) { $pos-- }
            # Skip current word
            while ($pos -gt 0 -and -not [char]::IsWhiteSpace($text[$pos - 1])) { $pos-- }
            $this._cursorPos = $pos
        }
    }

    [void] _MoveWordRight([bool]$select) {
        if ($select) {
            if ($this._selectionAnchor -eq -1) { $this._selectionAnchor = $this._cursorPos }
        } else {
            $this._selectionAnchor = -1
        }

        $text = $this._buffer.GetText()
        $len = $text.Length
        if ($this._cursorPos -lt $len) {
            $pos = $this._cursorPos
            # Skip current word
            while ($pos -lt $len -and -not [char]::IsWhiteSpace($text[$pos])) { $pos++ }
            # Skip current whitespace
            while ($pos -lt $len -and [char]::IsWhiteSpace($text[$pos])) { $pos++ }
            $this._cursorPos = $pos
        }
    }

    [string] RenderAndEdit([HybridRenderEngine]$engine, [string]$title) {
        $w = [int]($engine.Width * 0.8)
        $h = [int]($engine.Height * 0.8)
        $x = [int](($engine.Width - $w) / 2)
        $y = [int](($engine.Height - $h) / 2)

        # Ensure scroll is reset on entry if logic requires it, OR keep it if persisting editor instance

        while ($true) {
            $engine.BeginFrame()
            # Render on High Z-Layer for Modal effect
            $engine.BeginLayer(150)

            # Use Theme Colors (Native V3 Access)
            $pnlBg = [Colors]::PanelBg
            $pnlFg = [Colors]::Foreground
            $selBg = [Colors]::SelectionBg
            $selFg = [Colors]::SelectionFg

            # Draw Window
            $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, $pnlBg)
            $engine.WriteAt($x + 2, $y, " Editing: $title ", [Colors]::Header, $pnlBg)

            # Draw Help
            $help = "[Ctrl+S/Esc] Save  [Ctrl+Z] Undo  [Arrows] Nav  [Shift] Select"
            if ($help.Length -gt $w - 4) { $help = "[Esc] Save" }
            $engine.WriteAt($x + 2, $y + $h - 1, " $help ", [Colors]::Muted, $pnlBg)

            # --- Auto-Save Logic (Atomic) ---
            if ($this._dirty -and $this._autoSavePath -and ([DateTime]::Now - $this._lastSaveTime).TotalSeconds -gt 5) {
                try {
                    $content = $this._buffer.GetText()
                    $dir = Split-Path $this._autoSavePath -Parent
                    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

                    # Atomic Write
                    $tmpPath = "$($this._autoSavePath).tmp"
                    $content | Set-Content -Path $tmpPath -Encoding utf8
                    Move-Item -Path $tmpPath -Destination $this._autoSavePath -Force

                    $this._lastSaveTime = [DateTime]::Now
                    $this._dirty = $false
                } catch {
                    [Logger]::Error("NoteEditor auto-save failed", $_)
                }
            }

            # --- Rendering Content ---
            $text = $this._buffer.GetText()
            # Split lines manually or via regex, here simplicity wins for small notes
            $allLines = $text -split "`r?`n"

            # Rebuild line map for precise cursor/selection calculations
            # O(L) is cheap
            $lineOffsets = [System.Collections.Generic.List[int]]::new()
            $cumul = 0
            foreach ($line in $allLines) {
                $lineOffsets.Add($cumul)
                $cumul += $line.Length + 1 # +1 for newline
            }
            if ($text.EndsWith("`n")) { $lineOffsets.Add($cumul) }

            # Find Cursor Line
            $curLineIdx = 0
            $curColIdx = 0
            for ($i = 0; $i -lt $lineOffsets.Count; $i++) {
                $start = $lineOffsets[$i]
                $len = if ($i -lt $allLines.Count) { $allLines[$i].Length } else { 0 }
                $end = $start + $len

                if ($this._cursorPos -ge $start -and $this._cursorPos -le $end) {
                    $curLineIdx = $i
                    $curColIdx = $this._cursorPos - $start
                    break
                }
            }

            # Auto-Scroll
            $viewH = $h - 2
            $viewW = $w - 2

            if ($curLineIdx -lt $this._scrollRow) { $this._scrollRow = $curLineIdx }
            if ($curLineIdx -ge ($this._scrollRow + $viewH)) { $this._scrollRow = $curLineIdx - $viewH + 1 }

            # Render Lines
            for ($r = 0; $r -lt $viewH; $r++) {
                $lineIdx = $this._scrollRow + $r
                if ($lineIdx -ge $allLines.Count) { break }

                $lineText = $allLines[$lineIdx]
                $lineStartAbs = $lineOffsets[$lineIdx]

                # Render Loop for this line
                # Optimized: We draw the whole string IF no selection
                # But with selection, we have to split

                $screenY = $y + 1 + $r
                $screenX = $x + 1

                # Calculate Selection Range Intersection
                if ($this._selectionAnchor -ne -1) {
                    $selStart = [Math]::Min($this._selectionAnchor, $this._cursorPos)
                    $selEnd = [Math]::Max($this._selectionAnchor, $this._cursorPos)

                    # Intersect([lineStart, lineEnd], [selStart, selEnd])
                    $lStart = $lineStartAbs
                    $lEnd = $lStart + $lineText.Length

                    # Map to local string coords
                    $localSelStart = [Math]::Max(0, $selStart - $lStart)
                    $localSelEnd = [Math]::Min($lineText.Length, $selEnd - $lStart)

                    if ($localSelStart -lt $localSelEnd) {
                        # We have a selection on this line!
                        # Part 1: Pre-selection
                        if ($localSelStart -gt 0) {
                            $sub = $lineText.Substring(0, $localSelStart)
                            if ($sub.Length -gt $viewW) { $sub = $sub.Substring(0, $viewW) }
                            $engine.WriteAt($screenX, $screenY, $sub, $pnlFg, $pnlBg)
                        }

                        # Part 2: Selected
                        $len = $localSelEnd - $localSelStart
                        $drawX = $screenX + $localSelStart
                        if ($drawX -lt ($x + 1 + $viewW)) {
                            $sub = $lineText.Substring($localSelStart, $len)
                            # Clip to view
                            $avail = ($x + 1 + $viewW) - $drawX
                            if ($sub.Length -gt $avail) { $sub = $sub.Substring(0, $avail) }
                            $engine.WriteAt($drawX, $screenY, $sub, $selFg, $selBg)
                        }

                        # Part 3: Post-selection
                        $drawX = $screenX + $localSelEnd
                        if ($drawX -lt ($x + 1 + $viewW)) {
                             $sub = $lineText.Substring($localSelEnd)
                             $avail = ($x + 1 + $viewW) - $drawX
                             if ($sub.Length -gt $avail) { $sub = $sub.Substring(0, $avail) }
                             $engine.WriteAt($drawX, $screenY, $sub, $pnlFg, $pnlBg)
                        }
                    } else {
                        # No selection intersection, plain draw
                        if ($lineText.Length -gt $viewW) { $lineText = $lineText.Substring(0, $viewW) }
                        $engine.WriteAt($screenX, $screenY, $lineText, $pnlFg, $pnlBg)
                    }
                } else {
                    # No selection active anywhere
                    if ($lineText.Length -gt $viewW) { $lineText = $lineText.Substring(0, $viewW) }
                    $engine.WriteAt($screenX, $screenY, $lineText, $pnlFg, $pnlBg)
                }
            }

            # Draw Cursor
            $engine.SetCursor($x + 1 + $curColIdx, $y + 1 + ($curLineIdx - $this._scrollRow))
            $engine.ShowCursor()

            $engine.EndLayer()
            $engine.EndFrame()

            # --- Input Handling ---
            if ($engine.PSObject.Properties['TestInputMock'] -and $engine.TestInputMock) {
                 # Test Shim
                 break
            }

            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                # Check Modifiers
                $ctrl = ($key.Modifiers -band [ConsoleModifiers]::Control)
                $shift = ($key.Modifiers -band [ConsoleModifiers]::Shift)

                if ($key.Key -eq 'Escape') {
                    return $this._buffer.GetText() # Save & Exit
                }

                # Save (Ctrl+S)
                if ($ctrl -and $key.Key -eq 'S') {
                    $this._dirty = $true # Force save logic next frame
                    continue
                }

                # Undo (Ctrl+Z)
                if ($ctrl -and $key.Key -eq 'Z') {
                    $this._Undo()
                    continue
                }

                # Redo (Ctrl+Y)
                if ($ctrl -and $key.Key -eq 'Y') {
                    $this._Redo()
                    continue
                }

                # Select All (Ctrl+A)
                if ($ctrl -and $key.Key -eq 'A') {
                    $this._selectionAnchor = 0
                    $this._cursorPos = $this._buffer.GetLength()
                    continue
                }

                # Copy (Ctrl+C)
                if ($ctrl -and $key.Key -eq 'C') {
                    if ($this._selectionAnchor -ne -1 -and $this._selectionAnchor -ne $this._cursorPos) {
                        $start = [Math]::Min($this._selectionAnchor, $this._cursorPos)
                        $len = [Math]::Abs($this._selectionAnchor - $this._cursorPos)
                        [NoteEditor]::_clipboard = $this._buffer.GetText($start, $len)
                    }
                    continue
                }

                # Cut (Ctrl+X)
                if ($ctrl -and $key.Key -eq 'X') {
                    if ($this._selectionAnchor -ne -1 -and $this._selectionAnchor -ne $this._cursorPos) {
                        $this._SaveUndoState()
                        $start = [Math]::Min($this._selectionAnchor, $this._cursorPos)
                        $len = [Math]::Abs($this._selectionAnchor - $this._cursorPos)
                        [NoteEditor]::_clipboard = $this._buffer.GetText($start, $len)
                        $this._buffer.Delete($start, $len)
                        $this._cursorPos = $start
                        $this._selectionAnchor = -1
                        $this._dirty = $true
                    }
                    continue
                }

                # Paste (Ctrl+V)
                if ($ctrl -and $key.Key -eq 'V') {
                    $clip = [NoteEditor]::_clipboard
                    if (-not [string]::IsNullOrEmpty($clip)) {
                        $this._SaveUndoState()

                        # Replace Selection if active
                        if ($this._selectionAnchor -ne -1) {
                            $start = [Math]::Min($this._selectionAnchor, $this._cursorPos)
                            $len = [Math]::Abs($this._selectionAnchor - $this._cursorPos)
                            $this._buffer.Delete($start, $len)
                            $this._cursorPos = $start
                            $this._selectionAnchor = -1
                        }

                        $this._buffer.Insert($this._cursorPos, $clip)
                        $this._cursorPos += $clip.Length
                        $this._dirty = $true
                    }
                    continue
                }

                # Navigation Keys
                switch ($key.Key) {
                    'LeftArrow' {
                        if ($ctrl) { $this._MoveWordLeft($shift) }
                        else {
                            if ($shift) {
                                if ($this._selectionAnchor -eq -1) { $this._selectionAnchor = $this._cursorPos }
                            } elseif ($this._selectionAnchor -ne -1) {
                                $this._selectionAnchor = -1 # Clear Select
                            }

                            if ($this._cursorPos -gt 0) { $this._cursorPos-- }
                        }
                    }
                    'RightArrow' {
                        if ($ctrl) { $this._MoveWordRight($shift) }
                        else {
                            if ($shift) {
                                if ($this._selectionAnchor -eq -1) { $this._selectionAnchor = $this._cursorPos }
                            } elseif ($this._selectionAnchor -ne -1) {
                                $this._selectionAnchor = -1
                            }

                            if ($this._cursorPos -lt $this._buffer.Length) { $this._cursorPos++ }
                        }
                    }
                    'UpArrow' {
                        if ($shift) { if ($this._selectionAnchor -eq -1) { $this._selectionAnchor = $this._cursorPos } }
                        else { $this._selectionAnchor = -1 }

                        # Move up a line logic (simplified)
                        if ($curLineIdx -gt 0) {
                             $targetLine = $curLineIdx - 1
                             $targetOffset = [Math]::Min($curColIdx, $allLines[$targetLine].Length)
                             $this._cursorPos = $lineOffsets[$targetLine] + $targetOffset
                        }
                    }
                    'DownArrow' {
                        if ($shift) { if ($this._selectionAnchor -eq -1) { $this._selectionAnchor = $this._cursorPos } }
                        else { $this._selectionAnchor = -1 }

                        if ($curLineIdx -lt $allLines.Count - 1) {
                             $targetLine = $curLineIdx + 1
                             $targetOffset = [Math]::Min($curColIdx, $allLines[$targetLine].Length)
                             $this._cursorPos = $lineOffsets[$targetLine] + $targetOffset
                        }
                    }
                    'Backspace' {
                        if ($this._selectionAnchor -ne -1) {
                            $this._SaveUndoState()
                            # Delete Range
                            $start = [Math]::Min($this._selectionAnchor, $this._cursorPos)
                            $len = [Math]::Abs($this._selectionAnchor - $this._cursorPos)
                            $this._buffer.Delete($start, $len)
                            $this._cursorPos = $start
                            $this._selectionAnchor = -1
                            $this._dirty = $true
                        }
                        elseif ($this._cursorPos -gt 0) {
                            $this._SaveUndoState()
                            $this._buffer.Delete($this._cursorPos - 1, 1)
                            $this._cursorPos--
                            $this._dirty = $true
                        }
                    }
                    'Delete' {
                        # Similar logic for forward delete
                        if ($this._selectionAnchor -ne -1) {
                            $this._SaveUndoState()
                            $start = [Math]::Min($this._selectionAnchor, $this._cursorPos)
                            $len = [Math]::Abs($this._selectionAnchor - $this._cursorPos)
                            $this._buffer.Delete($start, $len)
                            $this._cursorPos = $start
                            $this._selectionAnchor = -1
                            $this._dirty = $true
                        }
                        elseif ($this._cursorPos -lt $this._buffer.Length) {
                            $this._SaveUndoState()
                            $this._buffer.Delete($this._cursorPos, 1)
                            $this._dirty = $true
                        }
                    }
                    'Enter' {
                        $this._SaveUndoState()
                        $this._buffer.Insert($this._cursorPos, "`n")
                        $this._cursorPos++
                        $this._dirty = $true
                    }
                    Default {
                        if (-not $ctrl -and $key.KeyChar -ne 0) {
                            $this._SaveUndoState()

                            # Replace Selection if active
                            if ($this._selectionAnchor -ne -1) {
                                $start = [Math]::Min($this._selectionAnchor, $this._cursorPos)
                                $len = [Math]::Abs($this._selectionAnchor - $this._cursorPos)
                                $this._buffer.Delete($start, $len)
                                $this._cursorPos = $start
                                $this._selectionAnchor = -1
                            }

                            $this._buffer.Insert($this._cursorPos, [string]$key.KeyChar)
                            $this._cursorPos++
                            $this._dirty = $true
                        }
                    }
                }
            } else {
                Start-Sleep -Milliseconds 10
            }
        }
        return $null
    }
}
