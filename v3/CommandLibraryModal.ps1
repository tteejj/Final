# CommandLibraryModal.ps1 - Command Library / Snippet Manager
# Allows storing and copying text snippets to clipboard

using namespace System.Collections.Generic

class CommandLibraryModal {
    hidden [bool]$_visible = $false
    hidden [FluxStore]$_store
    hidden [array]$_commands = @()
    hidden [int]$_selectedIndex = 0
    hidden [int]$_scrollOffset = 0
    hidden [HybridRenderEngine]$_engine

    CommandLibraryModal([FluxStore]$store) {
        $this._store = $store
    }

    [void] Open() {
        $this._visible = $true
        $this._selectedIndex = 0
        $this._scrollOffset = 0
        $this._LoadCommands()
    }

    [void] Close() {
        $this._visible = $false
    }

    [bool] IsVisible() {
        return $this._visible
    }

    hidden [void] _LoadCommands() {
        $state = $this._store.GetState()
        if ($state.Data.ContainsKey('commands') -and $state.Data.commands) {
            $this._commands = @($state.Data.commands)
        } else {
            $this._commands = @()
        }
    }

    [void] Render([HybridRenderEngine]$engine) {
        $this._engine = $engine
        if (-not $this._visible) { return }

        $engine.BeginLayer(150)

        $w = $engine.Width - 8
        $h = $engine.Height - 6
        $x = 4
        $y = 3

        # Background
        $engine.Fill($x, $y, $w, $h, " ", [Colors]::Foreground, [Colors]::Background)
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::Background)

        # Title
        $title = " Command Library (Snippets) "
        $engine.WriteAt($x + 2, $y, $title, [Colors]::Bright, [Colors]::Accent)

        $listY = $y + 2
        $listH = $h - 5

        if ($this._commands.Count -eq 0) {
            $engine.WriteAt($x + 4, $listY, "(No commands. Press N to add)", [Colors]::Muted, [Colors]::Background)
        } else {
            for ($displayRow = 0; $displayRow -lt $listH; $displayRow++) {
                $idx = $displayRow + $this._scrollOffset
                if ($idx -ge $this._commands.Count) { break }

                $cmd = $this._commands[$idx]
                $rowY = $listY + $displayRow
                $isSelected = ($idx -eq $this._selectedIndex)

                $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
                $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::Background }

                $text = if ($cmd['text']) { $cmd['text'] } else { "" }
                # Truncate
                if ($text.Length -gt $w - 6) { $text = $text.Substring(0, $w - 9) + "..." }

                $engine.WriteAt($x + 3, $rowY, $text.PadRight($w - 6), $fg, $bg)
            }
        }

        # Status bar
        $statusY = $y + $h - 2
        $engine.Fill($x, $statusY, $w, 1, " ", [Colors]::Foreground, [Colors]::SelectionBg)
        $statusText = " [N] New  [Enter] Copy to Clipboard  [Delete] Remove  [Esc] Close"
        $engine.WriteAt($x, $statusY, $statusText, [Colors]::Bright, [Colors]::SelectionBg)

        $engine.EndLayer()
    }

    [string] HandleInput([ConsoleKeyInfo]$key) {
        if (-not $this._visible) { return "Continue" }

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
                if ($this._selectedIndex -lt $this._commands.Count - 1) {
                    $this._selectedIndex++
                }
                return "Continue"
            }
            'N' {
                $this._AddCommand()
                return "Continue"
            }
            'Enter' {
                if ($this._commands.Count -gt 0) {
                    $cmd = $this._commands[$this._selectedIndex]
                    if ($cmd['text']) {
                        Set-Clipboard -Value $cmd['text'] | Out-Null
                        # Maybe show toast?
                        # Using Console.Beep for feedback
                        [Console]::Beep(1000, 200)
                    }
                }
                return "Continue"
            }
            'Delete' {
                if ($this._commands.Count -gt 0) {
                    $this._DeleteCommand()
                }
                return "Continue"
            }
        }
        return "Continue"
    }

    hidden [void] _AddCommand() {
        if ($null -eq $this._engine) { return }

        try {
            $editor = [NoteEditor]::new("")
            $text = $editor.RenderAndEdit($this._engine, "Enter Command Snippet")

            if ($null -ne $text -and $text.Trim().Length -gt 0) {
                 $newCmd = @{
                     id = [DataService]::NewGuid()
                     text = $text.Trim()
                     created = [DataService]::Timestamp()
                 }

                 $state = $this._store.GetState()
                 if (-not $state.Data.ContainsKey('commands')) {
                     $state.Data.commands = @()
                 }
                 $state.Data.commands += $newCmd

                 $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
                 $this._LoadCommands()
                 $this._selectedIndex = $this._commands.Count - 1
            }
        } catch {
             [Logger]::Error("CommandLibraryModal._AddCommand: Error", $_)
        }
    }

    hidden [void] _DeleteCommand() {
        if ($this._selectedIndex -ge $this._commands.Count) { return }

        $cmd = $this._commands[$this._selectedIndex]

        $state = $this._store.GetState()
        $state.Data.commands = @($state.Data.commands | Where-Object { $_['id'] -ne $cmd['id'] })

        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
        $this._LoadCommands()

        if ($this._selectedIndex -ge $this._commands.Count -and $this._selectedIndex -gt 0) {
            $this._selectedIndex--
        }
    }
}
