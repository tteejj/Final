# SpeedTUI Button Component - Interactive button with keyboard support

class Button : Component {
    [string]$Text = ""
    [scriptblock]$OnClick = {}
    [string]$HotKey = ""  # Single character hotkey
    [bool]$IsDefault = $false  # Responds to Enter
    [bool]$IsCancel = $false   # Responds to Escape
    
    # Visual properties
    [string]$ForegroundColor = [Colors]::White
    [string]$BackgroundColor = ""
    [string]$FocusedForegroundColor = [Colors]::Black
    [string]$FocusedBackgroundColor = [Colors]::White
    [bool]$ShowBrackets = $true
    
    Button() : base() {
        $this.CanFocus = $true
        $this._logger.Debug("Button", "Constructor", "Button created")
    }
    
    Button([string]$text) : base() {
        $this.CanFocus = $true
        $this.Text = $text
        $this._logger.Debug("Button", "Constructor", "Button created with text", @{
            Text = $text
        })
    }
    
    Button([string]$text, [scriptblock]$onClick) : base() {
        $this.CanFocus = $true
        $this.Text = $text
        $this.OnClick = $onClick
        $this._logger.Debug("Button", "Constructor", "Button created with text and handler", @{
            Text = $text
        })
    }
    
    # Builder methods
    [Button] WithText([string]$text) {
        $this.Text = $text
        $this.Invalidate()
        return $this
    }
    
    [Button] WithHotKey([string]$key) {
        [Guard]::Condition($key.Length -eq 1, "HotKey must be a single character")
        $this.HotKey = $key
        return $this
    }
    
    [Button] AsDefault() {
        $this.IsDefault = $true
        return $this
    }
    
    [Button] AsCancel() {
        $this.IsCancel = $true
        return $this
    }
    
    [Button] WithColors([string]$foreground, [string]$background) {
        $this.ForegroundColor = $foreground
        $this.BackgroundColor = $background
        $this.Invalidate()
        return $this
    }
    
    [Button] WithFocusColors([string]$foreground, [string]$background) {
        $this.FocusedForegroundColor = $foreground
        $this.FocusedBackgroundColor = $background
        $this.Invalidate()
        return $this
    }
    
    [Button] WithOnClick([scriptblock]$handler) {
        [Guard]::NotNull($handler, "handler")
        $this.OnClick = $handler
        return $this
    }
    
    [void] OnRender() {
        if ([string]::IsNullOrEmpty($this.Text)) { return }
        
        # Prepare text
        $displayText = $this.Text
        if ($this.ShowBrackets) {
            $displayText = "[ $displayText ]"
        }
        
        # Calculate position (center the button)
        $x = ($this.Width - $displayText.Length) / 2
        $y = $this.Height / 2
        $x = [Math]::Max(0, [int]$x)
        $y = [Math]::Max(0, [int]$y)
        
        # Build style
        $style = ""
        $reset = [Colors]::Reset
        
        if ($this.HasFocus) {
            $style = $this.FocusedForegroundColor + $this.FocusedBackgroundColor
        } else {
            $style = $this.ForegroundColor
            if ($this.BackgroundColor) {
                $style += $this.BackgroundColor
            }
        }
        
        # Highlight hotkey if present
        if (-not [string]::IsNullOrEmpty($this.HotKey)) {
            $hotkeyIndex = $displayText.IndexOf($this.HotKey, [StringComparison]::OrdinalIgnoreCase)
            if ($hotkeyIndex -ge 0) {
                # Split text around hotkey
                $before = $displayText.Substring(0, $hotkeyIndex)
                $hotkeyChar = $displayText.Substring($hotkeyIndex, 1)
                $after = $displayText.Substring($hotkeyIndex + 1)
                
                # Render with underlined hotkey
                $hotkeyStyle = $style + [Colors]::Underline
                $this.WriteAt($x, $y, "$style$before$hotkeyStyle$hotkeyChar$style$after$reset")
                return
            }
        }
        
        # Normal render
        $this.WriteAt($x, $y, "$style$displayText$reset")
    }
    
    [bool] HandleKeyPress([System.ConsoleKeyInfo]$keyInfo) {
        # Check for activation keys
        $activate = $false
        
        # Space or Enter activates when focused
        if ($this.HasFocus -and ($keyInfo.Key -eq [System.ConsoleKey]::Spacebar -or 
                                 $keyInfo.Key -eq [System.ConsoleKey]::Enter)) {
            $activate = $true
        }
        
        # Enter for default button (even without focus)
        elseif ($this.IsDefault -and $keyInfo.Key -eq [System.ConsoleKey]::Enter) {
            $activate = $true
        }
        
        # Escape for cancel button (even without focus)
        elseif ($this.IsCancel -and $keyInfo.Key -eq [System.ConsoleKey]::Escape) {
            $activate = $true
        }
        
        # Hotkey activation (Alt + key)
        elseif (-not [string]::IsNullOrEmpty($this.HotKey) -and 
                $keyInfo.Modifiers -eq [System.ConsoleModifiers]::Alt -and
                $keyInfo.KeyChar -eq $this.HotKey[0]) {
            $activate = $true
        }
        
        if ($activate) {
            $this.Click()
            return $true
        }
        
        return $false
    }
    
    [void] Click() {
        $this._logger.Debug("Button", "Click", "Button clicked", @{
            Text = $this.Text
            Id = $this.Id
        })
        
        if ($this.OnClick) {
            & $this.OnClick $this
        }
    }
}

# Button builder for fluent API
class ButtonBuilder : ComponentBuilder {
    ButtonBuilder() : base([Button]::new()) { }
    
    ButtonBuilder([string]$text) : base([Button]::new($text)) { }
    
    [ButtonBuilder] Text([string]$text) {
        ([Button]$this._component).Text = $text
        return $this
    }
    
    [ButtonBuilder] HotKey([string]$key) {
        ([Button]$this._component).HotKey = $key
        return $this
    }
    
    [ButtonBuilder] Default() {
        ([Button]$this._component).IsDefault = $true
        return $this
    }
    
    [ButtonBuilder] Cancel() {
        ([Button]$this._component).IsCancel = $true
        return $this
    }
    
    [ButtonBuilder] OnClick([scriptblock]$handler) {
        ([Button]$this._component).OnClick = $handler
        return $this
    }
    
    [ButtonBuilder] Colors([string]$foreground, [string]$background) {
        ([Button]$this._component).ForegroundColor = $foreground
        ([Button]$this._component).BackgroundColor = $background
        return $this
    }
    
    [ButtonBuilder] FocusColors([string]$foreground, [string]$background) {
        ([Button]$this._component).FocusedForegroundColor = $foreground
        ([Button]$this._component).FocusedBackgroundColor = $background
        return $this
    }
    
    [ButtonBuilder] NoBrackets() {
        ([Button]$this._component).ShowBrackets = $false
        return $this
    }
}