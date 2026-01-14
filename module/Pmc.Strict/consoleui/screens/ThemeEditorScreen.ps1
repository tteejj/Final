using namespace System.Collections.Generic
using namespace System.Text

# ThemeEditorScreen - Theme selection and preview
# Allows users to view available themes and apply them
# STANDALONE: Uses DataService instead of module functions

Set-StrictMode -Version Latest

class ThemeEditorScreen : PmcScreen {
    [array]$Themes = @()
    [int]$SelectedIndex = 0
    [string]$CurrentTheme = "Default"
    hidden [int]$_scrollOffset = 0
    hidden [int]$_contentY = 8
    hidden [int]$_contentHeight = 13

    ThemeEditorScreen() : base("ThemeEditor", "Theme Editor") {
        $this.Header.SetBreadcrumb(@("Home", "Options", "Themes"))
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Up/Down", "Select")
        $this.Footer.AddShortcut("Enter", "Apply")
        $this.Footer.AddShortcut("T", "Test")
        $this.Footer.AddShortcut("Esc", "Back")
    }

    ThemeEditorScreen([object]$container) : base("ThemeEditor", "Theme Editor", $container) {
        $this.Header.SetBreadcrumb(@("Home", "Options", "Themes"))
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Up/Down", "Select")
        $this.Footer.AddShortcut("Enter", "Apply")
        $this.Footer.AddShortcut("T", "Test")
        $this.Footer.AddShortcut("Esc", "Back")
    }

    [void] Initialize([object]$renderEngine, [object]$container) {
        $this.RenderEngine = $renderEngine
        $this.Container = $container
        $this.TermWidth = $renderEngine.Width
        $this.TermHeight = $renderEngine.Height

        if (-not $this.LayoutManager) {
            $this.LayoutManager = [PmcLayoutManager]::new()
        }

        $headerRect = $this.LayoutManager.GetRegion('Header', $this.TermWidth, $this.TermHeight)
        $this.Header.X = $headerRect.X
        $this.Header.Y = $headerRect.Y
        $this.Header.Width = $headerRect.Width
        $this.Header.Height = $headerRect.Height

        $footerRect = $this.LayoutManager.GetRegion('Footer', $this.TermWidth, $this.TermHeight)
        $this.Footer.X = $footerRect.X
        $this.Footer.Y = $footerRect.Y
        $this.Footer.Width = $footerRect.Width

        $statusBarRect = $this.LayoutManager.GetRegion('StatusBar', $this.TermWidth, $this.TermHeight)
        $this.StatusBar.X = $statusBarRect.X
        $this.StatusBar.Y = $statusBarRect.Y
        $this.StatusBar.Width = $statusBarRect.Width

        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)
        # CRITICAL FIX: Ensure content starts BELOW the header (Header Height is 5)
        # LayoutManager default Content.Y=3 overlaps with Header (Y=3, H=5)
        $this._contentY = $this.Header.Y + $this.Header.Height + 1
        $this._contentHeight = $contentRect.Height - ($this._contentY - $contentRect.Y)
    }

    # === GRADIENT RENDERING ===
    hidden [void] _RenderGradientText([object]$engine, [int]$x, [int]$y, [string]$text, [string]$startHex, [string]$endHex, [object]$bgColor) {
        if ([string]::IsNullOrEmpty($text)) { return }

        $sHex = $startHex.TrimStart('#')
        $sR = [Convert]::ToInt32($sHex.Substring(0, 2), 16)
        $sG = [Convert]::ToInt32($sHex.Substring(2, 2), 16)
        $sB = [Convert]::ToInt32($sHex.Substring(4, 2), 16)

        $eHex = $endHex.TrimStart('#')
        $eR = [Convert]::ToInt32($eHex.Substring(0, 2), 16)
        $eG = [Convert]::ToInt32($eHex.Substring(2, 2), 16)
        $eB = [Convert]::ToInt32($eHex.Substring(4, 2), 16)

        $len = $text.Length
        for ($i = 0; $i -lt $len; $i++) {
            $t = if ($len -eq 1) { 0 } else { $i / ($len - 1) }
            $r = [int]($sR + ($eR - $sR) * $t)
            $g = [int]($sG + ($eG - $sG) * $t)
            $b = [int]($sB + ($eB - $sB) * $t)
            $r = [Math]::Max(0, [Math]::Min(255, $r))
            $g = [Math]::Max(0, [Math]::Min(255, $g))
            $b = [Math]::Max(0, [Math]::Min(255, $b))
            $fg = ($r -shl 16) -bor ($g -shl 8) -bor $b
            $char = $text[$i]
            $engine.WriteAt($x + $i, $y, [string]$char, $fg, $bgColor)
        }
    }

    [void] LoadData() {
        $this.ShowStatus("Loading themes...")

        try {
            # Load themes from theme files
            $this.Themes = Get-AvailableThemes
            
            # Get current theme name from config
            # STANDALONE: Use DataService instead of module function
            try {
                $cfg = [DataService]::LoadConfig()
                if ($cfg -and $cfg.Display -and $cfg.Display.Theme -and $cfg.Display.Theme.Active) {
                    $activeTheme = $cfg.Display.Theme.Active
                    foreach ($theme in $this.Themes) {
                        if ($theme.Name.ToLower() -eq $activeTheme.ToLower()) {
                            $this.CurrentTheme = $theme.Name
                            break
                        }
                    }
                }
            } catch { }

            $count = $(if ($this.Themes) { $this.Themes.Count } else { 0 })
            $this.ShowSuccess("$count themes available")
        }
        catch {
            $this.ShowError("Failed to load themes: $_")
            $this.Themes = @()
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.Field')
        $cursorColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $y = $this._contentY
        
        $engine.WriteAt($this.Header.X + 4, $y, "THEME NAME", $headerColor, $bg)
        $engine.WriteAt($this.Header.X + 19, $y, "DESCRIPTION", $headerColor, $bg)
        $engine.WriteAt($this.Header.X + 55, $y, "STATUS", $headerColor, $bg)
        $y++

        $startY = $y + 1
        $maxLines = $this._contentHeight - 8
        
        # Apply scroll offset for scrolling support
        $visibleCount = [Math]::Min($this.Themes.Count - $this._scrollOffset, $maxLines)
        for ($i = 0; $i -lt $visibleCount; $i++) {
            $themeIndex = $i + $this._scrollOffset
            $theme = $this.Themes[$themeIndex]
            $rowY = $startY + $i
            $isSelected = ($themeIndex -eq $this.SelectedIndex)
            $isCurrent = ($theme.Name -eq $this.CurrentTheme)
            
            $rowBg = $(if ($isSelected) { $selectedBg } else { $bg })
            $rowFg = $(if ($isSelected) { $selectedFg } else { $textColor })

            if ($isSelected) {
                $engine.WriteAt($this.Header.X + 2, $rowY, ">", $cursorColor, $bg)
            }

            $x = $this.Header.X + 4

            if ($theme.Name -eq "Synthwave") {
                $this._RenderGradientText($engine, $x, $rowY, $theme.Name.PadRight(15), "#ff00ff", "#00ffff", $rowBg)
                $x += 15
                $this._RenderGradientText($engine, $x, $rowY, $theme.Description.PadRight(36), "#ff00ff", "#00ffff", $rowBg)
                $x += 36
            }
            else {
                $engine.WriteAt($x, $rowY, $theme.Name.PadRight(15), $rowFg, $rowBg)
                $x += 15
                $descFg = $(if ($isSelected) { $selectedFg } else { $mutedColor })
                $engine.WriteAt($x, $rowY, $theme.Description.PadRight(36), $descFg, $rowBg)
                $x += 36
            }

            if ($isCurrent) {
                $statusColor = $this.Header.GetThemedColorInt('Foreground.Success')
                $engine.WriteAt($x, $rowY, "[CURRENT]", $statusColor, $bg)
            }
        }

        # Show color preview for selected theme
        if ($this.SelectedIndex -ge 0 -and $this.SelectedIndex -lt $this.Themes.Count) {
            $theme = $this.Themes[$this.SelectedIndex]
            $previewY = $startY + [Math]::Min($this.Themes.Count, $maxLines) + 2

            if ($previewY -lt $this.Footer.Y - 2) {
                $engine.WriteAt($this.Header.X + 4, $previewY, [string]::new([char]0x2501, 50), $headerColor, $bg)
                $previewY++

                $engine.WriteAt($this.Header.X + 4, $previewY, "Selected: ", $textColor, $bg)
                
                if ($theme.Name -eq "Synthwave") {
                    $this._RenderGradientText($engine, $this.Header.X + 14, $previewY, $theme.Name, "#ff00ff", "#00ffff", $bg)
                }
                else {
                    $engine.WriteAt($this.Header.X + 14, $previewY, $theme.Name, $this.Header.GetThemedColorInt('Foreground.FieldFocused'), $bg)
                }
                $previewY++
                
                $engine.WriteAt($this.Header.X + 4, $previewY, "Hex Code: ", $mutedColor, $bg)
                $engine.WriteAt($this.Header.X + 14, $previewY, $theme.Hex, $this.Header.GetThemedColorInt('Foreground.Success'), $bg)
                $previewY++
                
                $engine.WriteAt($this.Header.X + 4, $previewY, "Description: ", $mutedColor, $bg)
                if ($theme.Name -eq "Synthwave") {
                    $this._RenderGradientText($engine, $this.Header.X + 17, $previewY, $theme.Description, "#ff00ff", "#00ffff", $bg)
                }
                else {
                    $engine.WriteAt($this.Header.X + 17, $previewY, $theme.Description, $textColor, $bg)
                }
                $previewY += 2
                
                $engine.WriteAt($this.Header.X + 4, $previewY, "Press Enter to apply, T to test, Esc to cancel", $headerColor, $bg)
            }
        }
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        $handled = ([PmcScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        $keyChar = [char]::ToLower($keyInfo.KeyChar)
        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this.SelectedIndex -gt 0) {
                    $this.SelectedIndex--
                    # Scroll up if needed
                    $maxLines = $this._contentHeight - 8
                    if ($this.SelectedIndex -lt $this._scrollOffset) {
                        $this._scrollOffset = $this.SelectedIndex
                    }
                    return $true
                }
            }
            'DownArrow' {
                if ($this.SelectedIndex -lt ($this.Themes.Count - 1)) {
                    $this.SelectedIndex++
                    # Scroll down if needed
                    $maxLines = $this._contentHeight - 8
                    if ($this.SelectedIndex -ge ($this._scrollOffset + $maxLines)) {
                        $this._scrollOffset = $this.SelectedIndex - $maxLines + 1
                    }
                    return $true
                }
            }
            'Enter' { $this._ApplyTheme(); return $true }
            'Escape' { if ($global:PmcApp) { $global:PmcApp.PopScreen() }; return $true }
        }

        switch ($keyChar) {
            't' { $this._TestTheme(); return $true }
        }

        return $false
    }

    hidden [void] _ApplyTheme() {
        if ($this.SelectedIndex -lt 0 -or $this.SelectedIndex -ge $this.Themes.Count) { return }
        $theme = $this.Themes[$this.SelectedIndex]

        try {
            $this.CurrentTheme = $theme.Name
            $reloadSuccess = Invoke-ThemeHotReload $theme.Name
            
            if (-not $reloadSuccess) {
                Start-Sleep -Milliseconds 800
                if ($global:PmcApp) {
                    $global:PmcApp.RenderEngine.RequestClear()
                    $global:PmcApp.PopScreen()
                }
            }
        }
        catch {
            try { $this.ShowError("Failed to apply theme: $_") } catch { }
        }
    }

    hidden [void] _TestTheme() {
        if ($this.SelectedIndex -lt 0 -or $this.SelectedIndex -ge $this.Themes.Count) { return }
        $theme = $this.Themes[$this.SelectedIndex]
        $this.ShowStatus("Testing theme: $($theme.Name) - Press any key to return")
    }

    hidden [void] _ResetTheme() {
        $this.CurrentTheme = "Default"
        $this.SelectedIndex = 0
        $this.ShowSuccess("Reset to default theme")
    }
}

function Show-ThemeEditorScreen {
    param([object]$App)
    if (-not $App) { throw "PmcApplication required" }
    $screen = New-Object ThemeEditorScreen
    $App.PushScreen($screen)
}