# NoteEditor.ps1 - Multiline Editor using GapBuffer with Selection Support
using namespace System.Text

class NoteEditor {
    hidden [GapBuffer]$_buffer
    hidden [int]$_cursorPos
    hidden [int]$_scrollRow
    
    # Selection State
    # -1 means no selection. If >= 0, selection is between Anchor and CursorPos
    hidden [int]$_selectionAnchor = -1
    
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
    }
    
    [void] SetAutoSavePath([string]$path) {
        $this._autoSavePath = $path
    }
    
    [string] RenderAndEdit([HybridRenderEngine]$engine, [string]$title) {
        $w = [int]($engine.Width * 0.8)
        $h = [int]($engine.Height * 0.8)
        $x = [int](($engine.Width - $w) / 2)
        $y = [int](($engine.Height - $h) / 2)
        
        while ($true) {
            $engine.BeginFrame()
            $engine.BeginLayer(150)
            
            # Draw Window
            $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
            $engine.WriteAt($x + 2, $y, " Editing: $title ", [Colors]::White, [Colors]::PanelBg)
            
            # Draw Help
            $help = "[Ctrl+S/Esc] Save & Close  [Ctrl+C/X/V/A] Clipboard"
            if ($help.Length -gt $w - 4) { $help = "[Esc] Save & Close" }
            $engine.WriteAt($x + 2, $y + $h - 1, " $help ", [Colors]::Gray, [Colors]::PanelBg)
            
            # --- Auto-Save Logic (Atomic) ---
            if ($this._dirty -and $this._autoSavePath -and ([DateTime]::Now - $this._lastSaveTime).TotalSeconds -gt 5) {
                try {
                    $content = $this._buffer.GetText()
                    $dir = Split-Path $this._autoSavePath -Parent
                    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                    
                    # Atomic Write: Write to .tmp then Move
                    $tmpPath = "$($this._autoSavePath).tmp"
                    $content | Set-Content -Path $tmpPath -Encoding utf8
                    Move-Item -Path $tmpPath -Destination $this._autoSavePath -Force
                    
                    $this._lastSaveTime = [DateTime]::Now
                    $this._dirty = $false # Mark clean until next edit
                } catch {
                    # Silent fail on auto-save is better than crashing interaction
                }
            }
            
            # --- Rendering Logic ---
            $text = $this._buffer.GetText()
            $lines = $text -split "`r?`n"
            
            # Calculate cursor row/col
            $curLine = 0
            $curCol = 0
            
            # We need a robust way to map linear index to row/col
            # Simple scan is O(N) but fine for small text notes
            $lineOffsets = @(0) # Start index of each line
            
            $scanIdx = 0
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $lineLen = $lines[$i].Length
                $scanIdx += $lineLen + 1 # +1 for newline (approx)
                if ($i -lt $lines.Count - 1) {
                   $lineOffsets += $scanIdx 
                }
            }
            
            # Re-calculate exact cursor line/col mapping
            $curLine = 0
            $curCol = 0
            $cumul = 0
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $len = $lines[$i].Length
                $lineEnd = $cumul + $len
                
                # Cursor is on this line if pos <= lineEnd (inclusive for end of line)
                # UNLESS it's the very last line and we are at the end
                if ($this._cursorPos -le $lineEnd) {
                    $curLine = $i
                    $curCol = $this._cursorPos - $cumul
                    break
                }
                
                # If we are effectively at the newline char
                if ($this._cursorPos -eq $lineEnd + 1) {
                     $curLine = $i + 1
                     $curCol = 0
                     break
                }
                
                $cumul += $len + 1 # +1 for newline
            }
            if ($curLine -ge $lines.Count) { 
                $curLine = $lines.Count - 1 
                if ($curLine -lt 0) { $curLine = 0; $curCol = 0 } # empty buffer
            }

            # Scrolling
            if ($curLine -lt $this._scrollRow) { $this._scrollRow = $curLine }
            if ($curLine -ge ($this._scrollRow + $h - 4)) { $this._scrollRow = $curLine - ($h - 5) }
            
            # Selection Range
            $selStart = -1
            $selEnd = -1
            if ($this._selectionAnchor -ne -1) {
                if ($this._cursorPos -lt $this._selectionAnchor) {
                    $selStart = $this._cursorPos
                    $selEnd = $this._selectionAnchor
                } else {
                    $selStart = $this._selectionAnchor
                    $selEnd = $this._cursorPos
                }
            }
            
            # Render visible lines
            $displayY = $y + 2
            $currentDataIdx = 0
            # Calculate start index of the first visible line
            for ($k = 0; $k -lt $this._scrollRow; $k++) {
                $currentDataIdx += $lines[$k].Length + 1
            }

            for ($i = $this._scrollRow; $i -lt $lines.Count; $i++) {
                if ($displayY -ge ($y + $h - 2)) { break }
                
                $lineText = $lines[$i]
                $lineLen = $lineText.Length
                
                # Render line character by character (to handle selection highlighting)
                $renderX = $x + 2
                $maxRenderX = $x + $w - 2
                
                for ($j = 0; $j -lt $lineLen; $j++) {
                    if ($renderX -ge $maxRenderX) { break }
                    
                    $charIdx = $currentDataIdx + $j
                    $char = $lineText[$j]
                    
                    # Determine color
                    $isSelected = ($selStart -ne -1 -and $charIdx -ge $selStart -and $charIdx -lt $selEnd)
                    $fg = if ($isSelected) { [Colors]::Black } else { [Colors]::Foreground }
                    $bg = if ($isSelected) { [Colors]::Cyan } else { [Colors]::PanelBg }
                    
                    $engine.WriteAt($renderX, $displayY, $char, $fg, $bg)
                    $renderX++
                }
                
                # Cursor rendering
                if ($i -eq $curLine) {
                    $cursorX = $x + 2 + $curCol
                    if ($cursorX -ge $x + 2 -and $cursorX -lt $maxRenderX) {
                        $charUnderCursor = if ($curCol -lt $lineLen) { $lineText[$curCol] } else { " " }
                        $engine.WriteAt($cursorX, $displayY, $charUnderCursor, [Colors]::Black, [Colors]::White)
                    }
                }
                
                $currentDataIdx += $lineLen + 1
                $displayY++
            }
            
            $engine.EndLayer()
            $engine.EndFrame()
            
            # --- Input Handling ---
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $mod = $key.Modifiers
                
                # --- Shortcuts ---
                
                # Save: Ctrl+S
                if ($key.Key -eq 'S' -and ($mod -band [ConsoleModifiers]::Control)) {
                    return $this._buffer.GetText()
                }
                
                # Select All: Ctrl+A (A is 65 (?))
                if ($key.Key -eq 'A' -and ($mod -band [ConsoleModifiers]::Control)) {
                    $this._selectionAnchor = 0
                    $this._cursorPos = $this._buffer.GetLength()
                    continue
                }
                
                # Copy: Ctrl+C
                if ($key.Key -eq 'C' -and ($mod -band [ConsoleModifiers]::Control)) {
                    if ($this._selectionAnchor -ne -1 -and $this._selectionAnchor -ne $this._cursorPos) {
                        $start = [Math]::Min($this._selectionAnchor, $this._cursorPos)
                        $len = [Math]::Abs($this._selectionAnchor - $this._cursorPos)
                        [NoteEditor]::_clipboard = $this._buffer.GetText($start, $len)
                    }
                    continue
                }

                # Cut: Ctrl+X
                if ($key.Key -eq 'X' -and ($mod -band [ConsoleModifiers]::Control)) {
                    if ($this._selectionAnchor -ne -1 -and $this._selectionAnchor -ne $this._cursorPos) {
                        $start = [Math]::Min($this._selectionAnchor, $this._cursorPos)
                        $len = [Math]::Abs($this._selectionAnchor - $this._cursorPos)
                        [NoteEditor]::_clipboard = $this._buffer.GetText($start, $len)
                        $this._buffer.Delete($start, $len)
                        $this._cursorPos = $start
                        $this._selectionAnchor = -1
                    }
                    continue
                }
                
                # Paste: Ctrl+V
                if ($key.Key -eq 'V' -and ($mod -band [ConsoleModifiers]::Control)) {
                    $content = [NoteEditor]::_clipboard
                    if (-not [string]::IsNullOrEmpty($content)) {
                        $this._DeleteSelection()
                        $this._buffer.Insert($this._cursorPos, $content)
                        $this._cursorPos += $content.Length
                    }
                    continue
                }

                # --- Navigation ---
                $isShift = ($mod -band [ConsoleModifiers]::Shift)
                
                switch ($key.Key) {
                    'Escape' {
                        # SAVE on Escape instead of Cancel
                        return $this._buffer.GetText() 
                    }
                    
                    'LeftArrow' { 
                        $this._UpdateSelection($isShift)
                        if ($mod -band [ConsoleModifiers]::Control) {
                            $this._MoveWordLeft()
                        } elseif ($this._cursorPos -gt 0) { 
                            $this._cursorPos-- 
                        }
                    }
                    'RightArrow' { 
                        $this._UpdateSelection($isShift)
                        if ($mod -band [ConsoleModifiers]::Control) {
                            $this._MoveWordRight()
                        } elseif ($this._cursorPos -lt $this._buffer.GetLength()) { 
                            $this._cursorPos++ 
                        }
                    }
                    'UpArrow' {
                        $this._UpdateSelection($isShift)
                        $this._MoveVertically(-1)
                    }
                    'DownArrow' {
                        $this._UpdateSelection($isShift)
                        $this._MoveVertically(1)
                    }
                    'Home' {
                        $this._UpdateSelection($isShift)
                        # Move to start of line
                        while ($this._cursorPos -gt 0 -and $this._buffer.GetChar($this._cursorPos - 1) -ne "`n") { $this._cursorPos-- }
                    }
                    'End' {
                        $this._UpdateSelection($isShift)
                        # Move to end of line
                        $len = $this._buffer.GetLength()
                        while ($this._cursorPos -lt $len -and $this._buffer.GetChar($this._cursorPos) -ne "`n") { $this._cursorPos++ }
                    }
                    
                    # --- Editing ---
                    'Backspace' {
                        if ($this._selectionAnchor -ne -1) {
                            $this._DeleteSelection()
                            $this._dirty = $true
                        } elseif ($this._cursorPos -gt 0) {
                            $this._cursorPos--
                            $this._buffer.Delete($this._cursorPos, 1)
                            $this._dirty = $true
                        }
                    }
                    'Delete' {
                        if ($this._selectionAnchor -ne -1) {
                            $this._DeleteSelection()
                            $this._dirty = $true
                        } elseif ($this._cursorPos -lt $this._buffer.GetLength()) {
                            $this._buffer.Delete($this._cursorPos, 1)
                            $this._dirty = $true
                        }
                    }
                    'Enter' {
                        $this._DeleteSelection()
                        $this._buffer.Insert($this._cursorPos, "`n")
                        $this._cursorPos++
                        $this._dirty = $true
                    }
                    
                    Default {
                        if (-not [char]::IsControl($key.KeyChar)) {
                            $this._DeleteSelection()
                            $this._buffer.Insert($this._cursorPos, $key.KeyChar)
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
    
    hidden [void] _UpdateSelection([bool]$keepSelection) {
        if ($keepSelection) {
            if ($this._selectionAnchor -eq -1) {
                $this._selectionAnchor = $this._cursorPos
            }
        } else {
            $this._selectionAnchor = -1
        }
    }
    
    hidden [void] _DeleteSelection() {
        if ($this._selectionAnchor -ne -1 -and $this._selectionAnchor -ne $this._cursorPos) {
            $start = [Math]::Min($this._selectionAnchor, $this._cursorPos)
            $len = [Math]::Abs($this._selectionAnchor - $this._cursorPos)
            $this._buffer.Delete($start, $len)
            $this._cursorPos = $start
            $this._selectionAnchor = -1
        }
    }
    
    hidden [void] _MoveVertically([int]$direction) {
        # This is a simplified vertical movement that tries to preserve column
        # Ideally we'd calculate current column, find matching column in next/prev line
        
        # 1. Find Start/End of current line
        $c = $this._cursorPos
        $len = $this._buffer.GetLength()
        
        $lineStart = $c
        while ($lineStart -gt 0 -and $this._buffer.GetChar($lineStart - 1) -ne "`n") { $lineStart-- }
        
        $lineEnd = $c
        while ($lineEnd -lt $len -and $this._buffer.GetChar($lineEnd) -ne "`n") { $lineEnd++ }
        
        $currentCol = $c - $lineStart
        
        if ($direction -lt 0) {
            # Up
            if ($lineStart -gt 0) {
                # Find prev line
                $prevEnd = $lineStart - 1
                $prevStart = $prevEnd
                while ($prevStart -gt 0 -and $this._buffer.GetChar($prevStart - 1) -ne "`n") { $prevStart-- }
                
                $prevLen = $prevEnd - $prevStart
                $newCol = [Math]::Min($currentCol, $prevLen)
                $this._cursorPos = $prevStart + $newCol
            }
        } else {
            # Down
            if ($lineEnd -lt $len) {
                # Find next line
                $nextStart = $lineEnd + 1
                $nextEnd = $nextStart
                while ($nextEnd -lt $len -and $this._buffer.GetChar($nextEnd) -ne "`n") { $nextEnd++ }
                
                $nextLen = $nextEnd - $nextStart
                $newCol = [Math]::Min($currentCol, $nextLen)
                $this._cursorPos = $nextStart + $newCol
            }
        }
    }
    
    # Word Movement (Ctrl+Arrow) - Like MS Word
    hidden [void] _MoveWordLeft() {
        if ($this._cursorPos -eq 0) { return }
        
        $pos = $this._cursorPos
        
        # Skip any whitespace/punctuation immediately to the left
        while ($pos -gt 0) {
            $c = $this._buffer.GetChar($pos - 1)
            if ($c -match '[\w]') { break }
            $pos--
        }
        
        # Skip the word characters
        while ($pos -gt 0) {
            $c = $this._buffer.GetChar($pos - 1)
            if ($c -notmatch '[\w]') { break }
            $pos--
        }
        
        $this._cursorPos = $pos
    }
    
    hidden [void] _MoveWordRight() {
        $len = $this._buffer.GetLength()
        if ($this._cursorPos -ge $len) { return }
        
        $pos = $this._cursorPos
        
        # Skip word characters first
        while ($pos -lt $len) {
            $c = $this._buffer.GetChar($pos)
            if ($c -notmatch '[\w]') { break }
            $pos++
        }
        
        # Skip any whitespace/punctuation
        while ($pos -lt $len) {
            $c = $this._buffer.GetChar($pos)
            if ($c -match '[\w]') { break }
            $pos++
        }
        
        $this._cursorPos = $pos
    }
}
