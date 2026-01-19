# InputBox.ps1 - Modal Text Input Component
using namespace System.Text

class InputBox {
    
    static [string] Show([HybridRenderEngine]$engine, [string]$title, [string]$defaultValue) {
        $w = 60
        $h = 5
        $x = [int](($engine.Width - $w) / 2)
        $y = [int](($engine.Height - $h) / 2)
        
        $input = [StringBuilder]::new()
        if (-not [string]::IsNullOrEmpty($defaultValue)) {
            [void]$input.Append($defaultValue)
        }
        
        $cursorPos = $input.Length
        
        # Modal Loop
        while ($true) {
            # 1. Render Overlay
            $engine.BeginLayer(100) # High Z-Index for modal
            
            # Shadow
            $engine.Fill($x + 2, $y + 1, $w, $h, " ", 0, [Colors]::Black)
            
            # Box
            $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
            $engine.Fill($x + 1, $y + 1, $w - 2, $h - 2, " ", [Colors]::White, [Colors]::PanelBg)
            
            # Title
            $engine.WriteAt($x + 2, $y, " $title ", [Colors]::White, [Colors]::PanelBg)
            
            # Input Field
            $displayText = $input.ToString()
            # Handle scrolling if text is too long (simple version: clip left)
            $maxWidth = $w - 4
            $viewStart = 0
            if ($cursorPos -gt $maxWidth) {
                $viewStart = $cursorPos - $maxWidth
            }
            
            $visibleText = ""
            if ($viewStart -lt $displayText.Length) {
                $len = [Math]::Min($displayText.Length - $viewStart, $maxWidth)
                $visibleText = $displayText.Substring($viewStart, $len)
            }
            
            $engine.WriteAt($x + 2, $y + 2, $visibleText, [Colors]::White, [Colors]::DarkGray)
            
            # Draw Cursor
            $cursorScreenX = $x + 2 + ($cursorPos - $viewStart)
            if ($cursorScreenX -lt ($x + $w - 2)) {
                 $charUnderCursor = " "
                 if ($cursorPos -lt $input.Length) { $charUnderCursor = $input.ToString()[$cursorPos] }
                 $engine.WriteAt($cursorScreenX, $y + 2, $charUnderCursor, [Colors]::Black, [Colors]::White)
            }
            
            $engine.WriteAt($x + 2, $y + 3, "[Enter] Confirm  [Esc] Cancel", [Colors]::Gray, [Colors]::PanelBg)
            
            $engine.EndLayer()
            $engine.EndFrame() # Force render of this frame
            
            # 2. Input Handling (Blocking)
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                
                switch ($key.Key) {
                    'Enter' { return $input.ToString() }
                    'Escape' { return $null }
                    'Backspace' {
                        if ($cursorPos -gt 0) {
                            [void]$input.Remove($cursorPos - 1, 1)
                            $cursorPos--
                        }
                    }
                    'Delete' {
                        if ($cursorPos -lt $input.Length) {
                            [void]$input.Remove($cursorPos, 1)
                        }
                    }
                    'LeftArrow' { if ($cursorPos -gt 0) { $cursorPos-- } }
                    'RightArrow' { if ($cursorPos -lt $input.Length) { $cursorPos++ } }
                    'Home' { $cursorPos = 0 }
                    'End' { $cursorPos = $input.Length }
                    Default {
                        if (-not [char]::IsControl($key.KeyChar)) {
                            [void]$input.Insert($cursorPos, $key.KeyChar)
                            $cursorPos++
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
