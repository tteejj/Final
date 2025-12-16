# SpeedTUI Enhanced Button Component - Interactive button with theming and performance
# Now uses the enhanced component base with simple, clear APIs

# Enhanced components are now loaded as the base system
# No additional loading needed - Component and ThemeManager are enhanced

<#
.SYNOPSIS
Enhanced button component with theming, performance optimizations, and clear APIs

.DESCRIPTION
Provides an interactive button with:
- Simple theming with SetTheme() and SetColor()
- Automatic performance optimizations (string caching, render caching)
- Clear positioning with SetPosition() and SetSize()
- Hotkey support and keyboard navigation
- Event system integration
- Comprehensive commenting for easy development

.EXAMPLE
# Simple button creation (backward compatible)
$button = [Button]::new("OK")
$button.SetPosition(10, 5)
$button.SetSize(15, 3)

# Enhanced theming and colors
$button.SetTheme("matrix")        # Apply matrix theme (green on black)
$button.SetColor("primary")       # Use primary color from theme

# Event handling
$button.OnClick = { Write-Host "Button clicked!" }

# Performance optimization
$button.EnableRenderCaching($true)  # Cache render output for speed

# Custom colors if needed
$button.SetCustomColor(255, 100, 50)  # Custom orange color
#>
class Button : Component {
    # === Core Button Properties ===
    [string]$Text = ""                    # Button text to display
    [string]$HotKey = ""                  # Single character hotkey (Alt+key)
    [bool]$IsDefault = $false             # Responds to Enter key globally
    [bool]$IsCancel = $false              # Responds to Escape key globally
    
    # === Visual Properties ===
    [bool]$ShowBrackets = $true           # Show [ ] around button text
    [bool]$ShowFocusIndicator = $true     # Show visual focus indicator
    
    # === Legacy Color Properties (for backward compatibility) ===
    [string]$ForegroundColor = ""         # Override foreground color
    [string]$BackgroundColor = ""         # Override background color
    [string]$FocusedForegroundColor = ""  # Override focused foreground
    [string]$FocusedBackgroundColor = ""  # Override focused background
    
    <#
    .SYNOPSIS
    Create a new button instance
    
    .DESCRIPTION
    Initializes a button with enhanced features including:
    - Automatic theme application
    - Performance optimizations
    - Keyboard focus capability
    - Event system integration
    #>
    Button() : base() {
        # Enable keyboard focus for buttons
        $this.CanFocus = $true
        
        # Enable render caching by default (Praxis optimization)
        $this._renderCacheEnabled = $true
        
        # Set default size if not specified
        if ($this.Width -eq 0) { $this.Width = 10 }
        if ($this.Height -eq 0) { $this.Height = 3 }
        
        # Apply default theme
        $this.SetTheme("default")
        $this.SetColor("primary")
        
        # Pre-compute render data
        $this.PrecomputeRenderData()
        
        $this._logger.Debug("Button", "Constructor", "Enhanced button created", @{
            Id = $this.Id
            Theme = $this.GetThemeName()
            Color = $this.GetCurrentColor()
            CacheEnabled = $this._renderCacheEnabled
        })
    }
    
    <#
    .SYNOPSIS
    Create button with text
    
    .PARAMETER text
    Text to display on the button
    
    .EXAMPLE
    $button = [Button]::new("Click Me")
    #>
    Button([string]$text) : base() {
        $this.CanFocus = $true
        $this.Text = $text
        
        # Enable render caching by default (Praxis optimization)
        $this._renderCacheEnabled = $true
        
        # Auto-size based on text length
        $this.Width = [Math]::Max(10, $text.Length + 4)  # Text + brackets + padding
        $this.Height = 3
        
        # Apply default theme
        $this.SetTheme("default")
        $this.SetColor("primary")
        
        # Pre-compute render data
        $this.PrecomputeRenderData()
        
        $this._logger.Debug("Button", "Constructor", "Enhanced button created with text", @{
            Id = $this.Id
            Text = $text
            AutoWidth = $this.Width
            CacheEnabled = $this._renderCacheEnabled
        })
    }
    
    <#
    .SYNOPSIS
    Create button with text and click handler
    
    .PARAMETER text
    Text to display on the button
    
    .PARAMETER onClick
    Script block to execute when clicked
    
    .EXAMPLE
    $button = [Button]::new("OK", { Write-Host "OK clicked!" })
    #>
    Button([string]$text, [scriptblock]$onClick) : base() {
        $this.CanFocus = $true
        $this.Text = $text
        $this.OnClick = $onClick
        
        # Enable render caching by default (Praxis optimization)
        $this._renderCacheEnabled = $true
        
        # Auto-size based on text length
        $this.Width = [Math]::Max(10, $text.Length + 4)
        $this.Height = 3
        
        # Apply default theme
        $this.SetTheme("default")
        $this.SetColor("primary")
        
        # Pre-compute render data
        $this.PrecomputeRenderData()
        
        $this._logger.Debug("Button", "Constructor", "Enhanced button created with text and handler", @{
            Id = $this.Id
            Text = $text
            HasClickHandler = $null -ne $onClick
            CacheEnabled = $this._renderCacheEnabled
        })
    }
    
    # === Enhanced Configuration Methods (Simple and Clear) ===
    
    <#
    .SYNOPSIS
    Set button text and auto-resize if needed
    
    .PARAMETER text
    New text for the button
    
    .EXAMPLE
    $button.SetText("Save Changes")  # Clear method name
    #>
    [void] SetText([string]$text) {
        if ($this.Text -eq $text) {
            return  # No change needed
        }
        
        $this.Text = $text
        
        # Auto-resize to fit text if current size is too small
        $requiredWidth = $text.Length + 4  # Text + brackets + padding
        if ($this.Width -lt $requiredWidth) {
            $this.SetSize($requiredWidth, $this.Height)
        }
        
        # Invalidate render cache since text changed
        $this.InvalidateRenderCache()
        $this.Invalidate()
        
        $this._logger.Debug("Button", "SetText", "Button text updated", @{
            Id = $this.Id
            NewText = $text
            AutoResized = $this.Width -eq $requiredWidth
        })
    }
    
    <#
    .SYNOPSIS
    Set hotkey for Alt+key activation
    
    .PARAMETER key
    Single character hotkey
    
    .EXAMPLE
    $button.SetHotKey("s")  # Alt+S will activate button
    #>
    [void] SetHotKey([string]$key) {
        if ([string]::IsNullOrWhiteSpace($key)) {
            $this.HotKey = ""
            return
        }
        
        # Validate single character
        if ($key.Length -ne 1) {
            throw [ArgumentException]::new("HotKey must be a single character")
        }
        
        $this.HotKey = $key.ToUpper()
        
        # Invalidate render since hotkey affects display
        $this.InvalidateRenderCache()
        $this.Invalidate()
        
        $this._logger.Debug("Button", "SetHotKey", "Hotkey set", @{
            Id = $this.Id
            HotKey = $this.HotKey
        })
    }
    
    <#
    .SYNOPSIS
    Make this button the default (responds to Enter)
    
    .PARAMETER isDefault
    Whether this is the default button
    
    .EXAMPLE
    $okButton.SetAsDefault($true)     # Enter key activates this button
    $cancelButton.SetAsDefault($false) # Remove default status
    #>
    [void] SetAsDefault([bool]$isDefault) {
        $this.IsDefault = $isDefault
        
        # Invalidate render to show default indicator
        $this.InvalidateRenderCache()
        $this.Invalidate()
        
        $this._logger.Debug("Button", "SetAsDefault", "Default status changed", @{
            Id = $this.Id
            IsDefault = $isDefault
        })
    }
    
    <#
    .SYNOPSIS
    Make this button the cancel button (responds to Escape)
    
    .PARAMETER isCancel
    Whether this is the cancel button
    
    .EXAMPLE
    $cancelButton.SetAsCancel($true)  # Escape key activates this button
    #>
    [void] SetAsCancel([bool]$isCancel) {
        $this.IsCancel = $isCancel
        
        $this._logger.Debug("Button", "SetAsCancel", "Cancel status changed", @{
            Id = $this.Id
            IsCancel = $isCancel
        })
    }
    
    <#
    .SYNOPSIS
    Configure visual appearance
    
    .PARAMETER showBrackets
    Whether to show [ ] around button text
    
    .PARAMETER showFocusIndicator
    Whether to show visual focus indicator
    
    .EXAMPLE
    $button.SetVisualStyle($false, $true)  # No brackets, show focus
    #>
    [void] SetVisualStyle([bool]$showBrackets, [bool]$showFocusIndicator) {
        $changed = $this.ShowBrackets -ne $showBrackets -or 
                  $this.ShowFocusIndicator -ne $showFocusIndicator
        
        if (-not $changed) {
            return
        }
        
        $this.ShowBrackets = $showBrackets
        $this.ShowFocusIndicator = $showFocusIndicator
        
        # Invalidate render since visual style changed
        $this.InvalidateRenderCache()
        $this.Invalidate()
    }
    
    # === Pre-computed render elements (Praxis optimization) ===
    hidden [string]$_borderTop = ""
    hidden [string]$_borderBottom = ""
    hidden [string]$_borderSides = ""
    hidden [string]$_paddingSpaces = ""
    hidden [int]$_textPadding = 0
    
    <#
    .SYNOPSIS
    Pre-compute render elements when bounds change (Praxis optimization)
    #>
    [void] PrecomputeRenderData() {
        # Call base implementation
        ([Component]$this).PrecomputeRenderData()
        
        # Pre-compute border strings if we have enough height
        if ($this.Height -ge 3 -and $this.Width -ge 3) {
            $innerWidth = $this.Width - 2
            $this._borderTop = "┌" + ([InternalStringCache]::GetSpaces($innerWidth).Replace(' ', '─')) + "┐"
            $this._borderBottom = "└" + ([InternalStringCache]::GetSpaces($innerWidth).Replace(' ', '─')) + "┘"
        }
        
        # Pre-compute padding for text centering
        $displayText = $(if ($this.ShowBrackets) { "[ $($this.Text) ]" } else { $this.Text })
        $textLength = $displayText.Length
        
        if ($this.Width -gt $textLength + 2) {
            $totalPadding = $this.Width - $textLength - 2  # -2 for borders
            $this._textPadding = [int]($totalPadding / 2)
            $this._paddingSpaces = [InternalStringCache]::GetSpaces($this._textPadding)
        } else {
            $this._textPadding = 0
            $this._paddingSpaces = ""
        }
    }
    
    <#
    .SYNOPSIS
    Override OnBoundsChanged to trigger pre-computation
    #>
    [void] OnBoundsChanged() {
        # Call base implementation which calls PrecomputeRenderData
        ([Component]$this).OnBoundsChanged()
    }
    
    # === Enhanced Rendering with Theme Integration ===
    
    <#
    .SYNOPSIS
    Render the button with theme support and performance optimization
    
    .DESCRIPTION
    Renders the button using:
    - Pre-computed render elements
    - Current theme colors  
    - Cached ANSI sequences for performance
    - Focus indicators
    - Hotkey highlighting
    - Custom color overrides
    #>
    [string] OnRender() {
        # Skip rendering if no text
        if ([string]::IsNullOrEmpty($this.Text)) { 
            return ""
        }
        
        # Build render output using pooled StringBuilder
        $sb = Get-PooledStringBuilder 512
        
        # Get theme manager for color resolution
        $themeManager = Get-ThemeManager
        
        # Determine colors based on theme and state
        $colors = $this.GetRenderColors($themeManager)
        $style = $colors.Foreground + $colors.Background
        $reset = [InternalVT100]::Reset()
        
        # Render button border if showing focus indicator
        if ($this.HasFocus -and $this.ShowFocusIndicator -and $this.Height -ge 3) {
            # Use pre-computed border elements
            $sb.Append($this.GetCachedPosition())
            $sb.Append($style)
            $sb.Append($this._borderTop)
            $sb.Append($reset)
            
            # Render middle line with text
            $sb.Append([InternalVT100]::MoveTo($this.X, $this.Y + 1))
            $sb.Append($style)
            $sb.Append("│")
            
            # Render button text with padding
            $sb.Append($this._paddingSpaces)
            
            # Handle hotkey highlighting
            if (-not [string]::IsNullOrEmpty($this.HotKey)) {
                $sb.Append($this.RenderTextWithHotkey($style, $reset))
            } else {
                $sb.Append($this.Text)
            }
            
            $sb.Append($this._paddingSpaces)
            $sb.Append("│")
            $sb.Append($reset)
            
            # Render bottom border
            $sb.Append([InternalVT100]::MoveTo($this.X, $this.Y + 2))
            $sb.Append($style)
            $sb.Append($this._borderBottom)
            $sb.Append($reset)
        } else {
            # Simple button without border
            $displayText = $(if ($this.ShowBrackets) { "[ $($this.Text) ]" } else { $this.Text })
            
            # Center the text
            $textX = [Math]::Max(0, [int](($this.Width - $displayText.Length) / 2))
            $textY = [Math]::Max(0, [int]($this.Height / 2))
            
            $sb.Append([InternalVT100]::MoveTo($this.X + $textX, $this.Y + $textY))
            $sb.Append($style)
            
            # Handle hotkey highlighting
            if (-not [string]::IsNullOrEmpty($this.HotKey)) {
                $sb.Append($this.RenderTextWithHotkey($style, $reset))
            } else {
                $sb.Append($displayText)
            }
            
            $sb.Append($reset)
        }
        
        # Draw default button indicator if applicable
        if ($this.IsDefault) {
            # Add a bullet or marker to indicate default
            $sb.Append([InternalVT100]::MoveTo($this.X + $this.Width - 2, $this.Y))
            $sb.Append($style)
            $sb.Append("•")
            $sb.Append($reset)
        }
        
        $result = $sb.ToString()
        Return-PooledStringBuilder $sb
        
        # Cache the result if caching is enabled
        if ($this._renderCacheEnabled) {
            $this._cachedRenderResult = $result
        }
        
        return $result
    }
    
    <#
    .SYNOPSIS
    Get appropriate colors for current button state
    
    .PARAMETER themeManager
    Theme manager instance
    
    .OUTPUTS
    Hashtable with Foreground and Background colors
    
    .DESCRIPTION
    Resolves colors in this priority:
    1. Custom component colors (SetCustomColor)
    2. Theme colors based on current color role
    3. Legacy color properties (backward compatibility)
    4. Default colors
    #>
    hidden [hashtable] GetRenderColors([object]$themeManager) {
        $colors = @{
            Foreground = ""
            Background = ""
        }
        
        # Check for custom colors first (highest priority)
        if ($this._customColors.ContainsKey("foreground")) {
            $colors.Foreground = $this._customColors["foreground"]
            if ($this._customColors.ContainsKey("background")) {
                $colors.Background = $this._customColors["background"]
            }
            return $colors
        }
        
        # Use theme colors based on current state
        $colorRole = $this.GetCurrentColor()
        if ([string]::IsNullOrEmpty($colorRole)) {
            $colorRole = "primary"  # Default for buttons
        }
        
        # Get theme color with focus modification
        if ($this.HasFocus) {
            # Try to get focus variant first
            $themeColor = $themeManager.GetColor("${colorRole}.focus")
            if ($null -eq $themeColor -or $themeColor.Foreground -eq [Colors]::Default) {
                # Fallback to regular color with focus styling
                $themeColor = $themeManager.GetColor($colorRole)
                $colors.Foreground = [InternalVT100]::Bold() + $themeColor.Foreground
                $colors.Background = $themeColor.Background
            } else {
                $colors.Foreground = $themeColor.Foreground
                $colors.Background = $themeColor.Background
            }
        } else {
            # Normal state
            $themeColor = $themeManager.GetColor($colorRole)
            $colors.Foreground = $themeColor.Foreground
            $colors.Background = $themeColor.Background
        }
        
        # Legacy color override support (backward compatibility)
        if (-not [string]::IsNullOrEmpty($this.ForegroundColor)) {
            $colors.Foreground = $this.ForegroundColor
        }
        if (-not [string]::IsNullOrEmpty($this.BackgroundColor)) {
            $colors.Background = $this.BackgroundColor
        }
        
        # Focused color overrides
        if ($this.HasFocus) {
            if (-not [string]::IsNullOrEmpty($this.FocusedForegroundColor)) {
                $colors.Foreground = $this.FocusedForegroundColor
            }
            if (-not [string]::IsNullOrEmpty($this.FocusedBackgroundColor)) {
                $colors.Background = $this.FocusedBackgroundColor
            }
        }
        
        return $colors
    }
    
    <#
    .SYNOPSIS
    Render text with hotkey highlighting (returns string)
    
    .PARAMETER style
    Base style ANSI sequence
    
    .PARAMETER reset
    Reset ANSI sequence
    
    .OUTPUTS
    String with hotkey highlighted
    #>
    hidden [string] RenderTextWithHotkey([string]$style, [string]$reset) {
        $displayText = $(if ($this.ShowBrackets) { "[ $($this.Text) ]" } else { $this.Text })
        
        # Find hotkey position in display text (case insensitive)
        $hotkeyIndex = $displayText.IndexOf($this.HotKey, [StringComparison]::OrdinalIgnoreCase)
        
        if ($hotkeyIndex -ge 0) {
            # Split text around hotkey
            $before = $displayText.Substring(0, $hotkeyIndex)
            $hotkeyChar = $displayText.Substring($hotkeyIndex, 1)
            $after = $displayText.Substring($hotkeyIndex + 1)
            
            # Build with underlined hotkey
            $underlineStyle = $style + [InternalVT100]::Underline()
            return "$before$underlineStyle$hotkeyChar$style$after"
        } else {
            # Hotkey not found in text
            return $displayText
        }
    }
    
    <#
    .SYNOPSIS
    Render button text with hotkey highlighting
    
    .PARAMETER x
    X position for text
    
    .PARAMETER y
    Y position for text
    
    .PARAMETER displayText
    Text to display
    
    .PARAMETER style
    Base style ANSI sequence
    
    .PARAMETER reset
    Reset ANSI sequence
    #>
    hidden [void] RenderWithHotkey([int]$x, [int]$y, [string]$displayText, [string]$style, [string]$reset) {
        # Find hotkey position in display text (case insensitive)
        $hotkeyIndex = $displayText.IndexOf($this.HotKey, [StringComparison]::OrdinalIgnoreCase)
        
        if ($hotkeyIndex -ge 0) {
            # Split text around hotkey
            $before = $displayText.Substring(0, $hotkeyIndex)
            $hotkeyChar = $displayText.Substring($hotkeyIndex, 1)
            $after = $displayText.Substring($hotkeyIndex + 1)
            
            # Render with underlined hotkey (using cached ANSI sequences)
            $underlineStyle = $style + [InternalVT100]::Underline()
            $renderText = "$style$before$underlineStyle$hotkeyChar$style$after$reset"
            
            $this.WriteAt($x, $y, $renderText)
        } else {
            # Hotkey not found in text, render normally
            $this.WriteAt($x, $y, "$style$displayText$reset")
        }
    }
    
    <#
    .SYNOPSIS
    Draw focus indicator around button
    
    .PARAMETER colors
    Current color configuration
    #>
    hidden [void] DrawFocusIndicator([hashtable]$colors) {
        # Draw a subtle border or indicator
        # Implementation depends on available space and theme
        if ($this.Width -ge 3 -and $this.Height -ge 3) {
            # Draw thin border using box drawing characters
            $borderStyle = $colors.Foreground
            $this.WriteAt(0, 0, "${borderStyle}┌$([InternalVT100]::GetSpaces($this.Width - 2))┐")
            $this.WriteAt(0, $this.Height - 1, "${borderStyle}└$([InternalVT100]::GetSpaces($this.Width - 2))┘")
            
            # Draw sides
            for ($i = 1; $i -lt $this.Height - 1; $i++) {
                $this.WriteAt(0, $i, "${borderStyle}│")
                $this.WriteAt($this.Width - 1, $i, "${borderStyle}│")
            }
        }
    }
    
    <#
    .SYNOPSIS
    Draw default button indicator
    
    .PARAMETER colors
    Current color configuration
    #>
    hidden [void] DrawDefaultIndicator([hashtable]$colors) {
        # Draw double border or thick border for default button
        if ($this.Width -ge 5 -and $this.Height -ge 3) {
            $borderStyle = $colors.Foreground + [InternalVT100]::Bold()
            # Use double-line box drawing characters
            $this.WriteAt(0, 0, "${borderStyle}╔$([InternalVT100]::GetSpaces($this.Width - 2))╗")
            $this.WriteAt(0, $this.Height - 1, "${borderStyle}╚$([InternalVT100]::GetSpaces($this.Width - 2))╝")
        }
    }
    
    # === Enhanced Input Handling ===
    
    <#
    .SYNOPSIS
    Handle keyboard input with hotkey support
    
    .PARAMETER keyInfo
    Console key information
    
    .OUTPUTS
    Boolean indicating if key was handled
    
    .DESCRIPTION
    Handles these key combinations:
    - Space/Enter when focused: Activate button
    - Enter globally: Activate if default button
    - Escape globally: Activate if cancel button
    - Alt+HotKey: Activate via hotkey
    #>
    [bool] HandleKeyPress([System.ConsoleKeyInfo]$keyInfo) {
        $activate = $false
        
        # Space or Enter when focused
        if ($this.HasFocus -and ($keyInfo.Key -eq [System.ConsoleKey]::Spacebar -or 
                                 $keyInfo.Key -eq [System.ConsoleKey]::Enter)) {
            $activate = $true
            $this._logger.Trace("Button", "HandleKeyPress", "Activated by space/enter", @{
                Id = $this.Id
                Key = $keyInfo.Key
            })
        }
        
        # Enter for default button (global)
        elseif ($this.IsDefault -and $keyInfo.Key -eq [System.ConsoleKey]::Enter) {
            $activate = $true
            $this._logger.Trace("Button", "HandleKeyPress", "Activated as default button", @{
                Id = $this.Id
            })
        }
        
        # Escape for cancel button (global)
        elseif ($this.IsCancel -and $keyInfo.Key -eq [System.ConsoleKey]::Escape) {
            $activate = $true
            $this._logger.Trace("Button", "HandleKeyPress", "Activated as cancel button", @{
                Id = $this.Id
            })
        }
        
        # Hotkey activation (Alt + key)
        elseif (-not [string]::IsNullOrEmpty($this.HotKey) -and 
                $keyInfo.Modifiers -eq [System.ConsoleModifiers]::Alt -and
                [char]::ToUpper($keyInfo.KeyChar) -eq $this.HotKey[0]) {
            $activate = $true
            $this._logger.Trace("Button", "HandleKeyPress", "Activated by hotkey", @{
                Id = $this.Id
                HotKey = $this.HotKey
            })
        }
        
        if ($activate) {
            $this.Click()
            return $true
        }
        
        # Let base class handle other keys
        return ([Component]$this).HandleKeyPress($keyInfo)
    }
    
    <#
    .SYNOPSIS
    Execute button click action
    
    .DESCRIPTION
    Fires the click event and executes the OnClick handler.
    Also integrates with the event system for broader event handling.
    #>
    [void] Click() {
        $this._logger.Debug("Button", "Click", "Button clicked", @{
            Id = $this.Id
            Text = $this.Text
            Theme = $this.GetThemeName()
        })
        
        # Fire event through event system if available
        try {
            $eventManager = Get-EventManager -ErrorAction SilentlyContinue
            if ($null -ne $eventManager) {
                $eventManager.Fire("button.clicked", @{
                    ButtonId = $this.Id
                    ButtonText = $this.Text
                    Position = @{ X = $this.X; Y = $this.Y }
                    Theme = $this.GetThemeName()
                    Color = $this.GetCurrentColor()
                }, "Button")
            }
        } catch {
            # Event system not available, continue without it
        }
        
        # Execute click handler
        if ($this.OnClick) {
            try {
                & $this.OnClick $this
            } catch {
                $this._logger.Error("Button", "Click", "Click handler failed", @{
                    Id = $this.Id
                    Exception = $_.Exception.Message
                })
                throw
            }
        }
    }
    
    # === Legacy Builder Methods (for backward compatibility) ===
    
    [Button] WithText([string]$text) {
        $this.SetText($text)
        return $this
    }
    
    [Button] WithHotKey([string]$key) {
        $this.SetHotKey($key)
        return $this
    }
    
    [Button] AsDefault() {
        $this.SetAsDefault($true)
        return $this
    }
    
    [Button] AsCancel() {
        $this.SetAsCancel($true)
        return $this
    }
    
    [Button] WithColors([string]$foreground, [string]$background) {
        $this.ForegroundColor = $foreground
        $this.BackgroundColor = $background
        $this.InvalidateRenderCache()
        $this.Invalidate()
        return $this
    }
    
    [Button] WithFocusColors([string]$foreground, [string]$background) {
        $this.FocusedForegroundColor = $foreground
        $this.FocusedBackgroundColor = $background
        $this.InvalidateRenderCache()
        $this.Invalidate()
        return $this
    }
    
    [Button] WithOnClick([scriptblock]$handler) {
        [Guard]::NotNull($handler, "handler")
        $this.OnClick = $handler
        return $this
    }
}

# === Enhanced Helper Functions ===

<#
.SYNOPSIS
Create a themed button with automatic sizing

.PARAMETER text
Button text

.PARAMETER theme
Theme name (matrix, amber, electric, etc.)

.PARAMETER colorRole
Color role (primary, secondary, success, etc.)

.OUTPUTS
Configured Button instance

.EXAMPLE
$saveBtn = New-ThemedButton "Save" "matrix" "success"
$saveBtn.SetPosition(10, 5)
#>
function New-ThemedButton {
    param(
        [string]$text,
        [string]$theme = "default",
        [string]$colorRole = "primary"
    )
    
    $button = [Button]::new($text)
    $button.SetTheme($theme)
    $button.SetColor($colorRole)
    
    return $button
}

<#
.SYNOPSIS
Create OK/Cancel button pair with proper theming

.PARAMETER okText
Text for OK button

.PARAMETER cancelText
Text for Cancel button

.PARAMETER theme
Theme to apply

.OUTPUTS
Hashtable with OK and Cancel buttons

.EXAMPLE
$buttons = New-OKCancelButtons "Save" "Cancel" "amber"
$buttons.OK.SetPosition(10, 15)
$buttons.Cancel.SetPosition(30, 15)
#>
function New-OKCancelButtons {
    param(
        [string]$okText = "OK",
        [string]$cancelText = "Cancel",
        [string]$theme = "default"
    )
    
    $okButton = [Button]::new($okText)
    $okButton.SetTheme($theme)
    $okButton.SetColor("success")
    $okButton.SetAsDefault($true)
    
    $cancelButton = [Button]::new($cancelText)
    $cancelButton.SetTheme($theme)
    $cancelButton.SetColor("secondary")
    $cancelButton.SetAsCancel($true)
    
    return @{
        OK = $okButton
        Cancel = $cancelButton
    }
}

# Helper functions are available when this file is dot-sourced