# ThemeSelectorModal.ps1
using namespace System.Collections.Generic

class ThemeSelectorModal {
    hidden [bool]$_visible = $false
    hidden [int]$_selectedIndex = 0
    hidden [array]$_themes # Initialized in Open()
    hidden [FluxStore]$_store

    ThemeSelectorModal([FluxStore]$store) {
        $this._store = $store
    }

    [void] Open() {
        $this._themes = [ThemeService]::GetPresets()
        $this._visible = $true
    }

    [void] Close() {
        $this._visible = $false
    }

    [bool] IsVisible() {
        return $this._visible
    }

    [void] Render([HybridRenderEngine]$engine) {
        if (-not $this._visible) { return }

        $w = 40
        $h = 14
        $x = [int](($engine.Width - $w) / 2)
        $y = [int](($engine.Height - $h) / 2)

        $engine.BeginLayer(200) # Topmost

        # Draw Box
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
        $engine.WriteAt($x + 2, $y, " Select Theme ", [Colors]::White, [Colors]::Accent)

        $listY = $y + 2
        for ($i = 0; $i -lt $this._themes.Count; $i++) {
            $t = $this._themes[$i]
            $isSelected = ($i -eq $this._selectedIndex)

            $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
            $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::PanelBg }
            $prefix = if ($isSelected) { " > " } else { "   " }

            # Draw full row
            $engine.Fill($x + 1, $listY + $i, $w - 2, 1, " ", $fg, $bg)
            $engine.WriteAt($x + 1, $listY + $i, "$prefix$($t.Name)", $fg, $bg)
        }

        $footer = "[Enter] Select  [Esc] Close"
        $engine.WriteAt($x + 2, $y + $h - 1, $footer, [Colors]::Muted, [Colors]::PanelBg)

        $engine.EndLayer()
    }

    [string] HandleInput([ConsoleKeyInfo]$key) {
        if (-not $this._visible) { return "Continue" }

        switch ($key.Key) {
            'Escape' { $this._visible = $false; return "Handled" }
            'UpArrow' {
                if ($this._selectedIndex -gt 0) { $this._selectedIndex-- }
                return "Handled"
            }
            'DownArrow' {
                if ($this._selectedIndex -lt $this._themes.Count - 1) { $this._selectedIndex++ }
                return "Handled"
            }
            'Enter' {
                $theme = $this._themes[$this._selectedIndex]
                [ThemeService]::LoadTheme($theme.Data)
                [Colors]::Sync()

                # Persist
                $this._store.Dispatch([ActionType]::UPDATE_SETTINGS, @{
                    Changes = @{ Theme = $theme.Name }
                })

                $this._visible = $false
                return "Handled"
            }
        }

        return "Handled"
    }
}
