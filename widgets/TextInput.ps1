using namespace System
using namespace System.Collections.Generic
using namespace System.Text

# TextInput.ps1 - Single-line text input widget with validation and cursor support
#
# Usage:
#   $input = [TextInput]::new()
#   $input.SetPosition(5, 5)
#   $input.SetSize(40, 3)
#   $input.Placeholder = "Enter task text..."
#   $input.MaxLength = 200
#   $input.Validator = { param($text) $text.Length -gt 0 }
#
#   # Render
#   $ansiOutput = $input.Render()
#   Write-Host $ansiOutput -NoNewline
#
#   # Handle input
#   $key = [Console]::ReadKey($true)
#   $handled = $input.HandleInput($key)
#
#   # Get result
#   $text = $input.GetText()

Set-StrictMode -Version Latest

# Load PmcWidget base class if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

<#
.SYNOPSIS
Single-line text input widget with cursor, validation, and event callbacks

.DESCRIPTION
Features:
- Single-line text input with cursor position tracking
- Left/Right arrow navigation, Home/End keys
- Backspace/Delete character editing
- Character insertion with MaxLength enforcement
- Visual cursor indicator (inverted colors)
- Placeholder text with ANSI color support
- Validation with custom scriptblock
- OnTextChanged event callback
- Theme integration with border and colors
- Horizontal scrolling for long text

.EXAMPLE
$input = [TextInput]::new()
$input.SetPosition(5, 5)
$input.SetSize(40, 3)
$input.Text = "Initial value"
$input.Placeholder = "Type something..."
$input.MaxLength = 100
$input.Validator = { param($text) $text.Length -ge 3 }
$input.OnTextChanged = { param($newText) Write-Host "Changed: $newText" }
$ansiOutput = $input.Render()
#>
class TextInput : PmcWidget {
    # === Public Properties ===
    [string]$Text = ""                      # Current text content
    [string]$Placeholder = ""               # Placeholder shown when empty
    [int]$MaxLength = 500                   # Maximum text length
    [scriptblock]$Validator = $null         # Validation function: param($text) -> bool
    [string]$Label = ""                     # Optional label above input

    # === Event Callbacks ===
    [scriptblock]$OnTextChanged = {}        # Called when text changes: param($newText)
    [scriptblock]$OnValidationFailed = {}   # Called when validation fails: param($text, $error)
    [scriptblock]$OnConfirmed = {}          # Called when Enter pressed: param($text)
    [scriptblock]$OnCancelled = {}          # Called when Esc pressed

    # === State Flags ===
    [bool]$IsConfirmed = $false             # True when Enter pressed
    [bool]$IsCancelled = $false             # True when Esc pressed
    [bool]$IsValid = $true                  # Current validation state

    # === Private State ===
    hidden [int]$_cursorPosition = 0        # Cursor position (0-based index)
    hidden [int]$_scrollOffset = 0          # Horizontal scroll offset for long text
    hidden [string]$_validationError = ""   # Last validation error message
    hidden [bool]$_showCursor = $true       # Cursor blink state
    hidden [int]$_blinkFrameCount = 0       # Frame counter for blink (more efficient than DateTime)
    hidden [int]$_blinkFrameInterval = 30   # Blink every 30 frames (at 60fps = 500ms)

    # === Constructor ===
    TextInput() : base("TextInput") {
        $this.Width = 40
        $this.Height = 3
        $this.CanFocus = $true
        $this._cursorPosition = 0
    }

    # === Public API Methods ===

    <#
    .SYNOPSIS
    Set the text content programmatically

    .PARAMETER text
    Text to set
    #>
    [void] SetText([string]$text) {
        $newText = $text
        if ($newText.Length -gt $this.MaxLength) {
            $newText = $newText.Substring(0, $this.MaxLength)
        }

        $oldText = $this.Text
        $this.Text = $newText
        $this._cursorPosition = $text.Length
        $this._AdjustScrollOffset()

        # Validate and trigger event if changed
        if ($oldText -ne $text) {
            $this._ValidateText()
            $this._InvokeCallback($this.OnTextChanged, $text)
        }
    }

    <#
    .SYNOPSIS
    Get the current text content

    .OUTPUTS
    String content
    #>
    [string] GetText() {
        return $this.Text
    }

    <#
    .SYNOPSIS
    Clear the input text

    .PARAMETER keepFocus
    If true, maintains focus after clearing
    #>
    [void] Clear([bool]$keepFocus = $true) {
        $this.Text = ""
        $this._cursorPosition = 0
        $this._scrollOffset = 0
        $this.IsConfirmed = $false
        $this.IsCancelled = $false
        $this._validationError = ""
        $this.IsValid = $true

        if ($keepFocus) {
            $this.HasFocus = $true
        }
    }

    <#
    .SYNOPSIS
    Handle keyboard input

    .PARAMETER keyInfo
    ConsoleKeyInfo from [Console]::ReadKey($true)

    .OUTPUTS
    True if input was handled, False otherwise
    #>
    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        # DEBUG: Log all input
        Write-PmcTuiLog "TextInput.HandleInput: ENTRY - Key=$($keyInfo.Key) Char='$($keyInfo.KeyChar)' CurrentText='$($this.Text)'" "DEBUG"

        # Enter - confirm input
        if ($keyInfo.Key -eq 'Enter') {
            if ($this._ValidateText()) {
                $this.IsConfirmed = $true
                $this._InvokeCallback($this.OnConfirmed, $this.Text)
                return $true
            }
            else {
                # Validation failed, don't confirm
                $this._InvokeCallback($this.OnValidationFailed, @($this.Text, $this._validationError))
                return $true
            }
        }

        # Escape - cancel input
        if ($keyInfo.Key -eq 'Escape') {
            $this.IsCancelled = $true
            $this._InvokeCallback($this.OnCancelled, $null)
            return $true
        }

        # Navigation keys
        if ($keyInfo.Key -eq 'LeftArrow') {
            $this._MoveCursorLeft()
            return $true
        }

        if ($keyInfo.Key -eq 'RightArrow') {
            $this._MoveCursorRight()
            return $true
        }

        if ($keyInfo.Key -eq 'Home') {
            $this._cursorPosition = 0
            $this._AdjustScrollOffset()
            return $true
        }

        if ($keyInfo.Key -eq 'End') {
            $this._cursorPosition = $this.Text.Length
            $this._AdjustScrollOffset()
            return $true
        }

        # Editing keys
        if ($keyInfo.Key -eq 'Backspace') {
            $this._DeleteCharBefore()
            return $true
        }

        if ($keyInfo.Key -eq 'Delete') {
            $this._DeleteCharAt()
            return $true
        }

        # Ctrl+A - select all (move to beginning for now)
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Control -and $keyInfo.Key -eq 'A') {
            $this._cursorPosition = 0
            $this._AdjustScrollOffset()
            return $true
        }

        # Ctrl+E - end (like Emacs)
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Control -and $keyInfo.Key -eq 'E') {
            $this._cursorPosition = $this.Text.Length
            $this._AdjustScrollOffset()
            return $true
        }

        # Ctrl+U - clear line
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Control -and $keyInfo.Key -eq 'U') {
            $this.Text = ""
            $this._cursorPosition = 0
            $this._scrollOffset = 0
            $this._ValidateText()
            $this._InvokeCallback($this.OnTextChanged, $this.Text)
            return $true
        }

        # L-POL-11: Ctrl+C - copy to clipboard
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Control -and $keyInfo.Key -eq 'C') {
            # FIX: Access $PSVersionTable via Get-Variable to work in strict mode class methods
            $psVersion = (Get-Variable -Name PSVersionTable -ValueOnly -ErrorAction SilentlyContinue)
            if ($null -ne $psVersion -and $psVersion.PSVersion.Major -ge 7 -and -not [string]::IsNullOrEmpty($this.Text)) {
                try {
                    Set-Clipboard -Value $this.Text
                }
                catch {
                    # Clipboard access may fail - silently ignore
                }
            }
            return $true
        }

        # L-POL-11: Ctrl+V - paste from clipboard
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Control -and $keyInfo.Key -eq 'V') {
            # FIX: Access $PSVersionTable via Get-Variable to work in strict mode class methods
            $psVersion = (Get-Variable -Name PSVersionTable -ValueOnly -ErrorAction SilentlyContinue)
            if ($null -ne $psVersion -and $psVersion.PSVersion.Major -ge 7) {
                try {
                    $clipText = Get-Clipboard -Raw
                    if (-not [string]::IsNullOrEmpty($clipText)) {
                        # Remove newlines from pasted text (single-line input)
                        $clipText = $clipText -replace '[\r\n]+', ' '

                        # Insert at cursor position
                        $before = $this.Text.Substring(0, $this._cursorPosition)
                        $after = $this.Text.Substring($this._cursorPosition)
                        $newText = $before + $clipText + $after

                        # Enforce max length
                        if ($newText.Length -gt $this.MaxLength) {
                            $newText = $newText.Substring(0, $this.MaxLength)
                        }

                        $this.Text = $newText
                        $this._cursorPosition = [Math]::Min($this._cursorPosition + $clipText.Length, $this.Text.Length)
                        $this._AdjustScrollOffset()
                        $this._ValidateText()
                        $this._InvokeCallback($this.OnTextChanged, $this.Text)
                    }
                }
                catch {
                    # Clipboard access may fail - silently ignore
                }
            }
            return $true
        }

        # Regular character input
        if ($keyInfo.KeyChar -ge 32 -and $keyInfo.KeyChar -le 126) {
            $this._InsertChar($keyInfo.KeyChar)
            return $true
        }

        # Space
        if ($keyInfo.Key -eq 'Spacebar') {
            $this._InsertChar(' ')
            return $true
        }

        return $false
    }

    # === Layout System ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)
        # Regions removed - using direct WriteAt in RenderToEngine
    }

    <#
    .SYNOPSIS
    Render directly to engine (new high-performance path)
    #>
    [void] RenderToEngine([object]$engine) {
        $this._blinkFrameCount++
        if ($this._blinkFrameCount -ge $this._blinkFrameInterval) {
            $this._showCursor = -not $this._showCursor
            $this._blinkFrameCount = 0
        }

        $this.RegisterLayout($engine)

        # Colors (Ints)
        # using Panel background for consistency with other inputs
        $bg = $this.GetThemedBgInt('Background.Panel', 1, 0)
        if ($bg -eq -1) { $bg = [HybridRenderEngine]::_PackRGB(30, 30, 30) }

        $fg = $this.GetThemedInt('Foreground.Row')
        $borderFg = $this.GetThemedInt('Border.Widget')
        $primaryFg = $this.GetThemedInt('Foreground.Title')
        $mutedFg = $this.GetThemedInt('Foreground.Muted')
        $errorFg = $this.GetThemedInt('Foreground.Error')
        
        # Border Color
        $activeBorderFg = if (-not $this.IsValid) { $errorFg } elseif ($this.HasFocus) { $primaryFg } else { $borderFg }

        # Draw Box
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $activeBorderFg, $bg)
        
        # Title
        if ($this.Label) {
            $engine.WriteAt($this.X + 2, $this.Y, " $($this.Label) ", $primaryFg, $bg)
        }
        
        # Input Area logic
        $inputX = $this.X + 2
        $inputY = $this.Y + 1
        $inputWidth = $this.Width - 4
        
        $displayText = ""
        if ([string]::IsNullOrEmpty($this.Text)) {
            if (-not $this.HasFocus) {
                # Placeholder
                $displayText = $this.Placeholder
                if ($displayText.Length -gt $inputWidth) { $displayText = $displayText.Substring(0, $inputWidth) }
                $engine.WriteAt($inputX, $inputY, $displayText, $mutedFg, $bg)
            }
            else {
                # Focused but empty - show cursor at 0
                if ($this._showCursor) {
                    $engine.WriteAt($inputX, $inputY, " ", $bg, $fg) # Inverse space
                }
                if ($this.Placeholder) {
                    # Show placeholder starting at 1? Or overwrite cursor?
                    # Generally placeholders disappear when typing starts, but here we are empty.
                    # If cursor is at 0, we can show placeholder starting at 1 if valid?
                    # Or just show cursor.
                    # Previous logic showed placeholder at X+1.
                    if ($inputWidth -gt 1) {
                        $ph = $this.Placeholder
                        if ($ph.Length -gt ($inputWidth - 1)) { $ph = $ph.Substring(0, $inputWidth - 1) }
                        $engine.WriteAt($inputX + 1, $inputY, $ph, $mutedFg, $bg)
                    }
                }
            }
        }
        else {
            # Visible Text
            $visibleText = $this.Text.Substring($this._scrollOffset)
            if ($visibleText.Length -gt $inputWidth) {
                $visibleText = $visibleText.Substring(0, $inputWidth)
            }
            
            $cursorOffset = $this._cursorPosition - $this._scrollOffset
            
            # Simple rendering: just write text
            $engine.WriteAt($inputX, $inputY, $visibleText, $fg, $bg)
            
            # Overwrite cursor char if focused and visible
            if ($this.HasFocus -and $this._showCursor -and $cursorOffset -ge 0 -and $cursorOffset -le $visibleText.Length) {
                
                $char = if ($cursorOffset -lt $visibleText.Length) { $visibleText[$cursorOffset] } else { ' ' }
                $engine.WriteAt($inputX + $cursorOffset, $inputY, "$char", $bg, $fg) # Inverse
            }
        }
        
        # Error
        if (-not $this.IsValid -and $this._validationError) {
            # Truncate error to width
            $err = " $($this._validationError) "
            if ($err.Length -gt $inputWidth) { $err = $err.Substring(0, $inputWidth) }
            $engine.WriteAt($this.X + 2, $this.Y + 2, $err, $errorFg, $bg)
        }
    }

    <#
    .SYNOPSIS
    Render the text input widget

    .OUTPUTS
    ANSI string ready for display
    #>
    [string] Render() {
        $sb = [StringBuilder]::new(1024)

        # Update cursor blink using frame counter (more efficient than DateTime)
        $this._blinkFrameCount++
        if ($this._blinkFrameCount -ge $this._blinkFrameInterval) {
            $this._showCursor = -not $this._showCursor
            $this._blinkFrameCount = 0
        }

        # Colors from new theme system
        $borderColor = $this.GetThemedFg('Border.Widget')
        $textColor = $this.GetThemedFg('Foreground.Row')
        $primaryColor = $this.GetThemedFg('Foreground.Title')
        $mutedColor = $this.GetThemedFg('Foreground.Muted')
        $errorColor = $this.GetThemedFg('Foreground.Error')
        $successColor = $this.GetThemedFg('Foreground.Success')
        $reset = "`e[0m"

        # Choose border color based on validation state
        $activeBorderColor = $(if (-not $this.IsValid) { $errorColor } elseif ($this.HasFocus) { $primaryColor } else { $borderColor })

        # Draw top border
        $sb.Append($this.BuildMoveTo($this.X, $this.Y))
        $sb.Append($activeBorderColor)
        $sb.Append($this.BuildBoxBorder($this.Width, 'top', 'single'))

        # Label in top border if provided
        if (-not [string]::IsNullOrWhiteSpace($this.Label)) {
            $labelText = " $($this.Label) "
            $labelPos = 2
            $sb.Append($this.BuildMoveTo($this.X + $labelPos, $this.Y))
            $sb.Append($primaryColor)
            $sb.Append($labelText)
        }

        # Draw middle row (text input area)
        $rowY = $this.Y + 1
        $sb.Append($this.BuildMoveTo($this.X, $rowY))
        $sb.Append($activeBorderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        # Calculate visible text area
        $innerWidth = $this.Width - 4  # Leave 2 chars padding on each side
        $displayText = ""
        $cursorDisplayPos = -1

        if ([string]::IsNullOrEmpty($this.Text)) {
            # Show placeholder
            $displayText = $this.Placeholder
            $sb.Append($this.BuildMoveTo($this.X + 2, $rowY))
            $sb.Append($mutedColor)
            $sb.Append($this.TruncateText($displayText, $innerWidth))

            # Cursor at beginning if focused
            if ($this.HasFocus -and $this._showCursor) {
                $cursorDisplayPos = 0
            }
        }
        else {
            # Show actual text with scroll offset
            $visibleText = $this.Text.Substring($this._scrollOffset)
            if ($visibleText.Length -gt $innerWidth) {
                $visibleText = $visibleText.Substring(0, $innerWidth)
            }

            $displayText = $visibleText
            $sb.Append($this.BuildMoveTo($this.X + 2, $rowY))
            $sb.Append($textColor)

            # Calculate cursor position in visible area
            $cursorOffsetPos = $this._cursorPosition - $this._scrollOffset

            # Render text with cursor highlighting
            if ($this.HasFocus -and $cursorOffsetPos -ge 0 -and $cursorOffsetPos -le $displayText.Length -and $this._showCursor) {
                # Text before cursor
                if ($cursorOffsetPos -gt 0) {
                    $sb.Append($displayText.Substring(0, $cursorOffsetPos))
                }

                # Cursor character (inverted)
                $cursorChar = $(if ($cursorOffsetPos -lt $displayText.Length) {
                        $displayText[$cursorOffsetPos]
                    }
                    else {
                        ' '
                    })
                $sb.Append("`e[7m")  # Invert colors
                $sb.Append($cursorChar)
                $sb.Append("`e[27m")  # Normal colors

                # Text after cursor
                if ($cursorOffsetPos + 1 -lt $displayText.Length) {
                    $sb.Append($displayText.Substring($cursorOffsetPos + 1))
                }
            }
            else {
                # No cursor, just render text
                $sb.Append($displayText)
            }
        }

        # Pad remaining space
        $textLen = $(if ($displayText) { $displayText.Length } else { 0 })
        $padding = $innerWidth - $textLen
        if ($padding -gt 0) {
            $sb.Append(" " * $padding)
        }

        # Right border for middle row
        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $rowY))
        $sb.Append($activeBorderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        # Draw bottom border
        $sb.Append($this.BuildMoveTo($this.X, $this.Y + 2))
        $sb.Append($activeBorderColor)
        $sb.Append($this.BuildBoxBorder($this.Width, 'bottom', 'single'))

        # Validation error or status message
        if (-not $this.IsValid -and -not [string]::IsNullOrWhiteSpace($this._validationError)) {
            $errorMsg = " $($this._validationError) "
            $errorPos = 2
            $sb.Append($this.BuildMoveTo($this.X + $errorPos, $this.Y + 2))
            $sb.Append($errorColor)
            $sb.Append($this.TruncateText($errorMsg, $this.Width - 4))
        }

        $sb.Append($reset)
        return $sb.ToString()
    }

    # === Private Helper Methods ===

    <#
    .SYNOPSIS
    Move cursor left by one position
    #>
    hidden [void] _MoveCursorLeft() {
        if ($this._cursorPosition -gt 0) {
            $this._cursorPosition--
            $this._AdjustScrollOffset()
        }
    }

    <#
    .SYNOPSIS
    Move cursor right by one position
    #>
    hidden [void] _MoveCursorRight() {
        if ($this._cursorPosition -lt $this.Text.Length) {
            $this._cursorPosition++
            $this._AdjustScrollOffset()
        }
    }

    <#
    .SYNOPSIS
    Insert a character at cursor position
    #>
    hidden [void] _InsertChar([char]$ch) {
        # DEBUG: Log insertion attempt
        Write-PmcTuiLog "TextInput._InsertChar: ENTRY - ch='$ch' CurrentText='$($this.Text)' Length=$($this.Text.Length) MaxLength=$($this.MaxLength)" "DEBUG"

        # Check length limit
        if ($this.Text.Length -ge $this.MaxLength) {
            Write-PmcTuiLog "TextInput._InsertChar: REJECTED - Text length ($($this.Text.Length)) >= MaxLength ($($this.MaxLength))" "DEBUG"
            return
        }

        # Basic input sanitization - reject control characters and null bytes
        $charCode = [int]$ch
        if ($charCode -lt 32 -and $charCode -ne 9) {
            # Allow tab (9) but reject other control chars
            return
        }
        if ($charCode -eq 0) {
            # Null byte
            return
        }
        if ($charCode -eq 127) {
            # DEL control char
            return
        }

        # Insert character
        if ($this._cursorPosition -eq $this.Text.Length) {
            # Append
            $this.Text += $ch
            Write-PmcTuiLog "TextInput._InsertChar: Appended '$ch' -> Text='$($this.Text)'" "DEBUG"
        }
        else {
            # Insert in middle
            $before = $this.Text.Substring(0, $this._cursorPosition)
            $after = $this.Text.Substring($this._cursorPosition)
            $this.Text = $before + $ch + $after
            Write-PmcTuiLog "TextInput._InsertChar: Inserted '$ch' at position $($this._cursorPosition) -> Text='$($this.Text)'" "DEBUG"
        }

        $this._cursorPosition++
        $this._AdjustScrollOffset()
        $this._ValidateText()
        $this._InvokeCallback($this.OnTextChanged, $this.Text)
        Write-PmcTuiLog "TextInput._InsertChar: EXIT - Text='$($this.Text)'" "DEBUG"
    }

    <#
    .SYNOPSIS
    Delete character before cursor (Backspace)
    #>
    hidden [void] _DeleteCharBefore() {
        if ($this._cursorPosition -eq 0) {
            return
        }

        # Delete character before cursor
        if ($this._cursorPosition -eq $this.Text.Length) {
            # Delete last char
            $this.Text = $this.Text.Substring(0, $this.Text.Length - 1)
        }
        else {
            # Delete in middle
            $before = $this.Text.Substring(0, $this._cursorPosition - 1)
            $after = $this.Text.Substring($this._cursorPosition)
            $this.Text = $before + $after
        }

        $this._cursorPosition--
        $this._AdjustScrollOffset()
        $this._ValidateText()
        $this._InvokeCallback($this.OnTextChanged, $this.Text)
    }

    <#
    .SYNOPSIS
    Delete character at cursor position (Delete key)
    #>
    hidden [void] _DeleteCharAt() {
        if ($this._cursorPosition -ge $this.Text.Length) {
            return
        }

        # Delete character at cursor
        if ($this._cursorPosition -eq 0 -and $this.Text.Length -eq 1) {
            $this.Text = ""
        }
        else {
            $before = $this.Text.Substring(0, $this._cursorPosition)
            $after = $(if ($this._cursorPosition + 1 -lt $this.Text.Length) {
                    $this.Text.Substring($this._cursorPosition + 1)
                }
                else {
                    ""
                })
            $this.Text = $before + $after
        }

        $this._AdjustScrollOffset()
        $this._ValidateText()
        $this._InvokeCallback($this.OnTextChanged, $this.Text)
    }

    <#
    .SYNOPSIS
    Adjust scroll offset to keep cursor visible
    #>
    hidden [void] _AdjustScrollOffset() {
        $innerWidth = $this.Width - 4

        # If cursor is before visible area, scroll left
        if ($this._cursorPosition -lt $this._scrollOffset) {
            $this._scrollOffset = $this._cursorPosition
        }

        # If cursor is after visible area, scroll right
        if ($this._cursorPosition -gt ($this._scrollOffset + $innerWidth - 1)) {
            $this._scrollOffset = $this._cursorPosition - $innerWidth + 1
        }

        # Clamp scroll offset
        if ($this._scrollOffset -lt 0) {
            $this._scrollOffset = 0
        }
    }

    <#
    .SYNOPSIS
    Validate current text using the Validator scriptblock

    .OUTPUTS
    True if valid, False if invalid
    #>
    hidden [bool] _ValidateText() {
        if ($null -eq $this.Validator) {
            $this.IsValid = $true
            $this._validationError = ""
            return $true
        }

        try {
            $result = & $this.Validator $this.Text
            if ($result -is [bool]) {
                $this.IsValid = $result
                if (-not $result) {
                    $this._validationError = "Invalid input"
                }
                else {
                    $this._validationError = ""
                }
                return $result
            }
            elseif ($result -is [hashtable] -and $result.ContainsKey('Valid')) {
                $this.IsValid = $result.Valid
                $this._validationError = $(if ($result.ContainsKey('Message')) { $result.Message } else { "" })
                return $result.Valid
            }
            else {
                # Assume valid if validator returns non-bool
                $this.IsValid = $true
                $this._validationError = ""
                return $true
            }
        }
        catch {
            # Validator threw exception - treat as invalid
            $this.IsValid = $false
            $this._validationError = "Validation error: $_"
            return $false
        }
    }

    <#
    .SYNOPSIS
    Invoke a callback scriptblock safely

    .PARAMETER callback
    Scriptblock to invoke

    .PARAMETER args
    Arguments to pass to scriptblock
    #>
    hidden [void] _InvokeCallback([scriptblock]$callback, $args) {
        if ($null -ne $callback) {
            try {
                if ($null -ne $args) {
                    & $callback $args
                }
                else {
                    & $callback
                }
            }
            catch {
                # Callback failed - log but don't crash widget
            }
        }
    }
}