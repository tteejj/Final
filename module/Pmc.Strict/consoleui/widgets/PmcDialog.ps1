using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Dialog system for PMC TUI

.DESCRIPTION
Provides reusable dialog components:
- ConfirmDialog: Yes/No confirmation
- TextInputDialog: Single line text input
- MessageDialog: Display message with OK button
#>

class PmcDialog {
    [string]$Title
    [string]$Message
    [int]$Width
    [int]$Height
    [int]$X = 0
    [int]$Y = 0
    [bool]$IsComplete = $false
    [bool]$Result = $false
    [string]$TextResult = ''

    [int] GetThemedColorInt([string]$key) {
        # Use PmcThemeEngine directly for integer colors
        $engine = [PmcThemeEngine]::GetInstance()
        if ($engine) {
            return $engine.GetThemeColorInt($key)
        }
        return -1
    }

    PmcDialog([string]$title, [string]$message) {
        $this.Title = $title
        $this.Message = $message
        $this.Width = [Math]::Max(60, [Math]::Max($title.Length + 10, $message.Length + 10))
        $this.Height = 10
    }

    [string] Render([int]$termWidth, [int]$termHeight, [hashtable]$theme) {
        # Legacy render stub
        return ""
    }

    <#
    .SYNOPSIS
    Render directly to engine (new high-performance path)
    #>
    [void] RenderToEngine([object]$engine) {
        # Calculate centered position if not set (or if we want to force center)
        # But Widgets usually have X/Y set. 
        # Dialogs often need re-centering on resize.
        # Let's assume layout manager or caller sets X/Y.
        
        # Colors (Ints)
        # Colors (Themed)
        $bg = $this.GetThemedColorInt('Background.Widget')
        $fg = $this.GetThemedColorInt('Foreground.Primary')
        $borderFg = $this.GetThemedColorInt('Border.Widget')
        $highlightFg = $this.GetThemedColorInt('Foreground.Title')
        
        # Shadow (Offset 2,1)
        $shadowBg = [HybridRenderEngine]::_PackRGB(0, 0, 0)
        $engine.Fill($this.X + 2, $this.Y + 1, $this.Width, $this.Height, ' ', -1, $shadowBg)
        
        # Main Box
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $borderFg, $bg)
        
        # Title
        $titleX = $this.X + [Math]::Floor(($this.Width - $this.Title.Length) / 2)
        $engine.WriteAt($titleX, $this.Y + 1, $this.Title, $highlightFg, $bg)
        
        # Message
        if ($this.Message) {
            $msgX = $this.X + [Math]::Floor(($this.Width - $this.Message.Length) / 2)
            $engine.WriteAt($msgX, $this.Y + 3, $this.Message, $fg, $bg)
        }
    }

    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        # Override in derived classes
        return $false
    }
}

class ConfirmDialog : PmcDialog {
    [int]$SelectedButton = 0  # 0 = Yes, 1 = No

    ConfirmDialog([string]$title, [string]$message) : base($title, $message) {
    }

    [void] RenderToEngine([object]$engine) {
        ([PmcDialog]$this).RenderToEngine($engine)
        
        $bg = $this.GetThemedColorInt('Background.Widget')
        $fg = $this.GetThemedColorInt('Foreground.Primary')
        $highlightBg = $this.GetThemedColorInt('Background.RowSelected')
        
        # Buttons
        $yesText = " Yes "
        $noText = " No "
        $gap = 4
        $totalW = $yesText.Length + $noText.Length + $gap
        
        $btnX = $this.X + [Math]::Floor(($this.Width - $totalW) / 2)
        $btnY = $this.Y + 6
        
        # Yes
        $yesBg = if ($this.SelectedButton -eq 0) { $highlightBg } else { $bg }
        $engine.WriteAt($btnX, $btnY, $yesText, $fg, $yesBg)
        
        # No
        $noBg = if ($this.SelectedButton -eq 1) { $highlightBg } else { $bg }
        $engine.WriteAt($btnX + $yesText.Length + $gap, $btnY, $noText, $fg, $noBg)
    }

    [string] Render([int]$termWidth, [int]$termHeight, [hashtable]$theme) { return "" }

    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'LeftArrow' {
                $this.SelectedButton = 0
                return $true
            }
            'RightArrow' {
                $this.SelectedButton = 1
                return $true
            }
            'Tab' {
                $this.SelectedButton = 1 - $this.SelectedButton
                return $true
            }
            'Enter' {
                $this.Result = ($this.SelectedButton -eq 0)
                $this.IsComplete = $true
                return $true
            }
            'Escape' {
                $this.Result = $false
                $this.IsComplete = $true
                return $true
            }
            'Y' {
                $this.Result = $true
                $this.IsComplete = $true
                return $true
            }
            'N' {
                $this.Result = $false
                $this.IsComplete = $true
                return $true
            }
        }
        return $false
    }
}

class TextInputDialog : PmcDialog {
    [string]$InputBuffer = ''
    [string]$Prompt

    TextInputDialog([string]$title, [string]$prompt, [string]$defaultValue) : base($title, $prompt) {
        $this.Prompt = $prompt
        $this.InputBuffer = $defaultValue
    }

    [void] RenderToEngine([object]$engine) {
        ([PmcDialog]$this).RenderToEngine($engine)
        
        $bg = $this.GetThemedColorInt('Background.Widget')
        $fg = $this.GetThemedColorInt('Foreground.Primary')
        $inputBg = $this.GetThemedColorInt('Background.Field')
        $cursorFg = $this.GetThemedColorInt('Foreground.Muted')
        
        $inputWidth = $this.Width - 8
        $inputX = $this.X + 4
        $inputY = $this.Y + 5
        
        $display = $this.InputBuffer
        if ($display.Length -gt $inputWidth - 2) {
            $display = $display.Substring($display.Length - $inputWidth + 2)
        }
        
        $engine.Fill($inputX, $inputY, $inputWidth, 1, ' ', $fg, $inputBg)
        $engine.WriteAt($inputX + 1, $inputY, $display, $fg, $inputBg)
        $engine.WriteAt($inputX + 1 + $display.Length, $inputY, "_", $cursorFg, $inputBg)
        
        # Hint
        $hint = "Enter: OK | Esc: Cancel"
        $hintX = $this.X + [Math]::Floor(($this.Width - $hint.Length) / 2)
        $engine.WriteAt($hintX, $this.Y + 7, $hint, $cursorFg, $bg)
    }

    [string] Render([int]$termWidth, [int]$termHeight, [hashtable]$theme) { return "" }

    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'Enter' {
                $this.TextResult = $this.InputBuffer
                $this.Result = $true
                $this.IsComplete = $true
                return $true
            }
            'Escape' {
                $this.Result = $false
                $this.IsComplete = $true
                return $true
            }
            'Backspace' {
                if ($this.InputBuffer.Length > 0) {
                    $this.InputBuffer = $this.InputBuffer.Substring(0, $this.InputBuffer.Length - 1)
                }
                return $true
            }
            default {
                if ($keyInfo.KeyChar -ge 32 -and $keyInfo.KeyChar -le 126) {
                    $this.InputBuffer += $keyInfo.KeyChar
                }
                return $true
            }
        }
        return $false
    }
}

class MessageDialog : PmcDialog {
    MessageDialog([string]$title, [string]$message) : base($title, $message) {
    }

    [void] RenderToEngine([object]$engine) {
        ([PmcDialog]$this).RenderToEngine($engine)
        
        $bg = $this.GetThemedColorInt('Background.Widget')
        $fg = $this.GetThemedColorInt('Foreground.Primary')
        $highlightBg = $this.GetThemedColorInt('Background.RowSelected')
        
        $ok = " OK "
        $okX = $this.X + [Math]::Floor(($this.Width - $ok.Length) / 2)
        
        $engine.WriteAt($okX, $this.Y + 6, $ok, $fg, $highlightBg)
    }

    [string] Render([int]$termWidth, [int]$termHeight, [hashtable]$theme) { return "" }

    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'Enter' {
                $this.Result = $true
                $this.IsComplete = $true
                return $true
            }
            'Escape' {
                $this.Result = $true
                $this.IsComplete = $true
                return $true
            }
        }
        return $false
    }
}