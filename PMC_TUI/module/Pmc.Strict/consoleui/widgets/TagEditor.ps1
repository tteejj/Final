using namespace System
using namespace System.Collections.Generic
using namespace System.Text

# TagEditor.ps1 - Multi-select tag editor with autocomplete chips
#
# Usage:
#   $editor = [TagEditor]::new()
#   $editor.SetPosition(5, 10)
#   $editor.SetSize(60, 5)
#   $editor.SetTags(@("work", "urgent"))
#
#   # Render
#   $ansiOutput = $editor.Render()
#   Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TagEditor] Rendering tag editor"
#
#   # Handle input
#   $key = [Console]::ReadKey($true)
#   $handled = $editor.HandleInput($key)
#
#   # Get result
#   $tags = $editor.GetTags()

Set-StrictMode -Version Latest

# Load PmcWidget base class if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

<#
.SYNOPSIS
Multi-select tag editor with autocomplete chips

.DESCRIPTION
Features:
- Display selected tags as colored chips: [work] [urgent] [bug]
- Type to add tags with autocomplete from existing tags
- Backspace to remove last tag or edit current input
- Tab/Enter to confirm current input as tag
- Arrow keys to select chips for removal (future enhancement)
- OnTagsChanged event callback
- Visual chip layout with color coding
- Max tags limit (configurable, default 10)
- Load existing tags from all tasks for autocomplete
- Validation: No duplicate tags, no empty tags
- Color-coded chips (hash tag name to consistent color)

.EXAMPLE
$editor = [TagEditor]::new()
$editor.SetPosition(5, 10)
$editor.SetSize(60, 5)
$editor.SetTags(@("work", "urgent"))
$editor.MaxTags = 5
$ansiOutput = $editor.Render()
#>
class TagEditor : PmcWidget {
    # === Public Properties ===
    [string]$Label = "Tags"                # Widget title
    [int]$MaxTags = 10                     # Maximum number of tags
    [bool]$AllowNewTags = $true            # Allow creating tags not in autocomplete list

    # === Event Callbacks ===
    [scriptblock]$OnTagsChanged = {}       # Called when tags change: param($tags)
    [scriptblock]$OnConfirmed = {}         # Called when Enter pressed: param($tags)
    [scriptblock]$OnCancelled = {}         # Called when Esc pressed

    # === State Flags ===
    [bool]$IsConfirmed = $false            # True when Enter pressed
    [bool]$IsCancelled = $false            # True when Esc pressed

    # === Private State ===
    hidden [List[string]]$_selectedTags = [List[string]]::new()     # Currently selected tags
    hidden [string]$_inputText = ""                                  # Current input text
    hidden [int]$_cursorPosition = 0                                 # Cursor position in input
    hidden [string[]]$_allKnownTags = @()                           # All tags from tasks (for autocomplete)
    hidden [string[]]$_autocompleteMatches = @()                    # Current autocomplete suggestions
    hidden [int]$_selectedAutocompleteIndex = 0                     # Selected autocomplete item
    hidden [bool]$_showAutocomplete = $false                        # Show autocomplete dropdown
    hidden [string]$_errorMessage = ""                              # Error message to display
    hidden [DateTime]$_lastTagRefresh = [DateTime]::MinValue       # Last time tags were loaded

    # Color palette for tag chips (cycling through these)
    hidden [string[]]$_chipColors = @(
        '#3498db'  # Blue
        '#2ecc71'  # Green
        '#e74c3c'  # Red
        '#f39c12'  # Orange
        '#9b59b6'  # Purple
        '#1abc9c'  # Teal
        '#e67e22'  # Dark orange
        '#16a085'  # Dark teal
    )

    # === Constructor ===
    TagEditor() : base("TagEditor") {
        $this.Width = 60
        $this.Height = 5
        $this.CanFocus = $true
        $this._LoadKnownTags()
    }

    # === Public API Methods ===

    <#
    .SYNOPSIS
    Set the tags collection

    .PARAMETER tags
    Array of tag strings
    #>
    [void] SetTags([string[]]$tags) {
        $this._selectedTags.Clear()

        if ($null -ne $tags -and $tags.Count -gt 0) {
            foreach ($tag in $tags) {
                if (-not [string]::IsNullOrWhiteSpace($tag)) {
                    $cleanTag = $tag.Trim()
                    if (-not $this._selectedTags.Contains($cleanTag)) {
                        $this._selectedTags.Add($cleanTag)
                    }
                }
            }
        }

        $this._InvokeCallback($this.OnTagsChanged, $this.GetTags())
    }

    <#
    .SYNOPSIS
    Get the current tags as array

    .OUTPUTS
    String array of tags
    #>
    [string[]] GetTags() {
        return $this._selectedTags.ToArray()
    }

    <#
    .SYNOPSIS
    Add a tag to the collection

    .PARAMETER tag
    Tag to add

    .OUTPUTS
    True if added, False if duplicate or invalid
    #>
    [bool] AddTag([string]$tag) {
        if ([string]::IsNullOrWhiteSpace($tag)) {
            return $false
        }

        $cleanTag = $tag.Trim()

        if ($this._selectedTags.Contains($cleanTag)) {
            $this._errorMessage = "Tag already added"
            return $false
        }

        if ($this._selectedTags.Count -ge $this.MaxTags) {
            $this._errorMessage = "Maximum $($this.MaxTags) tags allowed"
            return $false
        }

        $this._selectedTags.Add($cleanTag)
        $this._InvokeCallback($this.OnTagsChanged, $this.GetTags())
        return $true
    }

    <#
    .SYNOPSIS
    Remove a tag from the collection

    .PARAMETER tag
    Tag to remove

    .OUTPUTS
    True if removed, False if not found
    #>
    [bool] RemoveTag([string]$tag) {
        $result = $this._selectedTags.Remove($tag)
        if ($result) {
            $this._InvokeCallback($this.OnTagsChanged, $this.GetTags())
        }
        return $result
    }

    <#
    .SYNOPSIS
    Clear all tags
    #>
    [void] ClearTags() {
        $this._selectedTags.Clear()
        $this._inputText = ""
        $this._cursorPosition = 0
        $this._showAutocomplete = $false
        $this._errorMessage = ""
        $this._InvokeCallback($this.OnTagsChanged, $this.GetTags())
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
        # Refresh known tags periodically
        if (([DateTime]::Now - $this._lastTagRefresh).TotalSeconds -gt 10) {
            $this._LoadKnownTags()
        }

        # Enter - confirm tags or add current input
        if ($keyInfo.Key -eq 'Enter') {
            if (-not [string]::IsNullOrWhiteSpace($this._inputText)) {
                # Add current input as tag first
                $this._AddCurrentInputAsTag()
            }

            $this.IsConfirmed = $true
            $this._InvokeCallback($this.OnConfirmed, $this.GetTags())
            return $true
        }

        # Escape - cancel
        if ($keyInfo.Key -eq 'Escape') {
            $this.IsCancelled = $true
            $this._InvokeCallback($this.OnCancelled, $null)
            return $true
        }

        # Tab - autocomplete or add current input
        if ($keyInfo.Key -eq 'Tab') {
            if ($this._showAutocomplete -and $this._autocompleteMatches.Count -gt 0) {
                # Use selected autocomplete suggestion
                $selected = $this._autocompleteMatches[$this._selectedAutocompleteIndex]
                $this._inputText = $selected
                $this._cursorPosition = $selected.Length
                $this._AddCurrentInputAsTag()
            }
            elseif (-not [string]::IsNullOrWhiteSpace($this._inputText)) {
                # Add current input as tag
                $this._AddCurrentInputAsTag()
            }
            return $true
        }

        # Comma - treat as tag separator
        if ($keyInfo.KeyChar -eq ',') {
            if (-not [string]::IsNullOrWhiteSpace($this._inputText)) {
                $this._AddCurrentInputAsTag()
            }
            return $true
        }

        # Backspace - remove last tag if input is empty, otherwise edit input
        if ($keyInfo.Key -eq 'Backspace') {
            if ([string]::IsNullOrEmpty($this._inputText)) {
                # Remove last tag
                if ($this._selectedTags.Count -gt 0) {
                    $this._selectedTags.RemoveAt($this._selectedTags.Count - 1)
                    $this._InvokeCallback($this.OnTagsChanged, $this.GetTags())
                }
            }
            else {
                # Remove character from input
                if ($this._cursorPosition -gt 0) {
                    $before = $this._inputText.Substring(0, $this._cursorPosition - 1)
                    $after = $(if ($this._cursorPosition -lt $this._inputText.Length) {
                            $this._inputText.Substring($this._cursorPosition)
                        }
                        else { "" })
                    $this._inputText = $before + $after
                    $this._cursorPosition--
                    $this._UpdateAutocomplete()
                }
            }
            return $true
        }

        # Delete - delete character at cursor
        if ($keyInfo.Key -eq 'Delete') {
            if ($this._cursorPosition -lt $this._inputText.Length) {
                $before = $this._inputText.Substring(0, $this._cursorPosition)
                $after = $(if ($this._cursorPosition + 1 -lt $this._inputText.Length) {
                        $this._inputText.Substring($this._cursorPosition + 1)
                    }
                    else { "" })
                $this._inputText = $before + $after
                $this._UpdateAutocomplete()
            }
            return $true
        }

        # Arrow keys for autocomplete navigation
        if ($keyInfo.Key -eq 'UpArrow') {
            if ($this._showAutocomplete -and $this._autocompleteMatches.Count -gt 0) {
                if ($this._selectedAutocompleteIndex -gt 0) {
                    $this._selectedAutocompleteIndex--
                }
            }
            return $true
        }

        if ($keyInfo.Key -eq 'DownArrow') {
            if ($this._showAutocomplete -and $this._autocompleteMatches.Count -gt 0) {
                if ($this._selectedAutocompleteIndex -lt ($this._autocompleteMatches.Count - 1)) {
                    $this._selectedAutocompleteIndex++
                }
            }
            return $true
        }

        # Left/Right arrow for cursor movement
        if ($keyInfo.Key -eq 'LeftArrow') {
            if ($this._cursorPosition -gt 0) {
                $this._cursorPosition--
            }
            return $true
        }

        if ($keyInfo.Key -eq 'RightArrow') {
            if ($this._cursorPosition -lt $this._inputText.Length) {
                $this._cursorPosition++
            }
            return $true
        }

        # Home/End
        if ($keyInfo.Key -eq 'Home') {
            $this._cursorPosition = 0
            return $true
        }

        if ($keyInfo.Key -eq 'End') {
            $this._cursorPosition = $this._inputText.Length
            return $true
        }

        # Regular character input
        if ($keyInfo.KeyChar -ge 32 -and $keyInfo.KeyChar -le 126 -and $keyInfo.KeyChar -ne ',') {
            $before = $this._inputText.Substring(0, $this._cursorPosition)
            $after = $(if ($this._cursorPosition -lt $this._inputText.Length) {
                    $this._inputText.Substring($this._cursorPosition)
                }
                else { "" })
            $this._inputText = $before + $keyInfo.KeyChar + $after
            $this._cursorPosition++
            $this._UpdateAutocomplete()
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
        # Use Panel background
        $bg = $this.GetThemedBgInt('Background.Panel', 1, 0)
        # Fallback removed - strict theme enforcement

        $fg = $this.GetThemedInt('Foreground.Row')
        $borderFg = $this.GetThemedInt('Border.Widget')
        $primaryFg = $this.GetThemedInt('Foreground.Title')
        $mutedFg = $this.GetThemedInt('Foreground.Muted')
        $errorFg = $this.GetThemedInt('Foreground.Error')
        $highlightBg = $this.GetThemedBgInt('Background.RowSelected', 1, 0)
        $highlightFg = $this.GetThemedInt('Foreground.RowSelected')
        
        # Draw Box
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $borderFg, $bg)
        
        # Title
        $title = " $($this.Label) "
        $pad = [Math]::Max(0, [Math]::Floor(($this.Width - 4 - $title.Length) / 2))
        $engine.WriteAt($this.X + 2 + $pad, $this.Y + 1, $title, $primaryFg, $bg)
        
        # Count
        $countText = "($($this._selectedTags.Count)/$($this.MaxTags))"
        $countX = $this.X + $this.Width - $countText.Length - 2
        if ($countX -gt $this.X + 2) {
            $engine.WriteAt($countX, $this.Y + 1, $countText, $mutedFg, $bg)
        }
        
        # Chips & Input Area
        $chipsX = $this.X + 2
        $chipsY = $this.Y + 2
        $chipsWidth = $this.Width - 4
        $chipsHeight = 2
        
        $currentX = $chipsX
        $currentY = $chipsY
        $maxX = $chipsX + $chipsWidth
        $maxY = $chipsY + $chipsHeight
        
        # Draw Chips
        foreach ($tag in $this._selectedTags) {
            $chipText = "[$tag]"
            $chipLen = $tag.Length + 2
            
            if ($currentX + $chipLen + 1 -gt $maxX) {
                $currentX = $chipsX
                $currentY++
            }
            
            if ($currentY -ge $maxY) { break }
            
            # Get chip color (Int)
            $ansiColor = $this._GetChipColor($tag)
            $chipFg = [HybridRenderEngine]::AnsiColorToInt($ansiColor)
            
            $engine.WriteAt($currentX, $currentY, $chipText, $chipFg, $bg)
            $currentX += $chipLen + 1
        }
        
        # Draw Input
        if ($currentY -lt $maxY) {
            $inputSpace = $maxX - $currentX
            if ($inputSpace -lt 15) {
                # Need new line?
                $currentX = $chipsX
                $currentY++
            }
            
            if ($currentY -lt $maxY) {
                $prefix = if ([string]::IsNullOrEmpty($this._inputText)) { "type tag..." } else { $this._inputText }
                $pColor = if ([string]::IsNullOrEmpty($this._inputText)) { $mutedFg } else { $fg }
                
                # Highlight cursor
                if ([string]::IsNullOrEmpty($this._inputText)) {
                    $engine.WriteAt($currentX, $currentY, $prefix, $pColor, $bg)
                }
                else {
                    # Simple cursor
                    $engine.WriteAt($currentX, $currentY, $prefix, $pColor, $bg)
                    if ($this._cursorPosition -lt $prefix.Length) {
                        $char = $prefix[$this._cursorPosition]
                        $engine.WriteAt($currentX + $this._cursorPosition, $currentY, "$char", $bg, $pColor) # Invert
                    }
                    elseif ($this._cursorPosition -eq $prefix.Length) {
                        $engine.WriteAt($currentX + $this._cursorPosition, $currentY, " ", $bg, $pColor)
                    }
                }
            }
        }
        
        # Autocomplete (Overlay)
        if ($this._showAutocomplete -and $this._autocompleteMatches.Count -gt 0) {
            $acX = $this.X + 4
            $acY = $this.Y + 3
            if ($acY -ge $this.Y + $this.Height) { $acY = $this.Y + $this.Height - 1 } # Clamp/Adjust?
            # Actually Autocomplete usually floats.
            
            $acWidth = $this.Width - 8
            $acHeight = [Math]::Min(3, $this._autocompleteMatches.Count) + 2
            
            # Using BeginLayer to ensure popup is on top (if engine supports it, but we are inside widget)
            # We can just draw over since we render last?
            
            $engine.Fill($acX, $acY, $acWidth, $acHeight, ' ', $fg, $bg)
            $engine.DrawBox($acX, $acY, $acWidth, $acHeight, $borderFg, $bg)
            
            for ($i = 0; $i -lt [Math]::Min(3, $this._autocompleteMatches.Count); $i++) {
                $tag = $this._autocompleteMatches[$i]
                $isSel = ($i -eq $this._selectedAutocompleteIndex)
                $itemFg = if ($isSel) { $highlightFg } else { $mutedFg }
                $itemBg = if ($isSel) { $highlightBg } else { $bg }
                
                $engine.Fill($acX + 1, $acY + 1 + $i, $acWidth - 2, 1, ' ', $itemFg, $itemBg)
                $engine.WriteAt($acX + 1, $acY + 1 + $i, $tag, $itemFg, $itemBg)
            }
        }
        
        # Help
        $helpText = "Tab/Enter=Add | Backspace=Remove | Esc=Cancel"
        $engine.WriteAt($this.X + 2, $this.Y + $this.Height - 2, $this.PadText($helpText, $this.Width - 4, 'left'), $mutedFg, $bg)
        
        # Error
        if ($this._errorMessage) {
            $engine.WriteAt($this.X + 2, $this.Y + $this.Height - 1, $this._errorMessage, $errorFg, $bg)
        }
    }

    <#
    .SYNOPSIS
    Render the tag editor widget

    .OUTPUTS
    ANSI string ready for display
    #>
    [string] Render() {
        $sb = [StringBuilder]::new(2048)

        # Colors from new theme system
        $borderColor = $this.GetThemedFg('Border.Widget')
        $textColor = $this.GetThemedFg('Foreground.Row')
        $primaryColor = $this.GetThemedFg('Foreground.Title')
        $mutedColor = $this.GetThemedFg('Foreground.Muted')
        $errorColor = $this.GetThemedFg('Foreground.Error')
        $successColor = $this.GetThemedFg('Foreground.Success')
        $highlightBg = $this.GetThemedBg('Background.RowSelected', 1, 0)
        $highlightFg = $this.GetThemedFg('Foreground.RowSelected')
        $reset = "`e[0m"

        # Reset any inherited formatting from parent
        $sb.Append($reset)

        # Draw top border
        $sb.Append($this.BuildMoveTo($this.X, $this.Y))
        $sb.Append($borderColor)
        $sb.Append($this.BuildBoxBorder($this.Width, 'top', 'single'))

        # Title
        $title = " $($this.Label) "
        $titlePos = 2
        $sb.Append($this.BuildMoveTo($this.X + $titlePos, $this.Y))
        $sb.Append($primaryColor)
        $sb.Append($title)

        # Tag count
        $countText = "($($this._selectedTags.Count)/$($this.MaxTags))"
        $sb.Append($this.BuildMoveTo($this.X + $this.Width - $countText.Length - 2, $this.Y))
        $sb.Append($mutedColor)
        $sb.Append($countText)

        # Chips and input area (rows 1-2)
        $chipRow1Y = $this.Y + 1
        $chipRow2Y = $this.Y + 2

        # Build chip display
        $chipsText = $this._BuildChipsDisplay()

        # Render chips across two rows if needed
        $sb.Append($this.BuildMoveTo($this.X, $chipRow1Y))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        $innerWidth = $this.Width - 4
        $currentX = 0
        $currentY = 0

        # Render chips
        foreach ($tag in $this._selectedTags) {
            $chipText = $this._FormatChip($tag)
            $chipDisplayLen = $tag.Length + 3  # [tag] length

            # Check if we need to wrap to next row
            if ($currentX + $chipDisplayLen -gt $innerWidth) {
                # Fill rest of current row
                $padding = $innerWidth - $currentX
                $sb.Append(" " * $padding)

                # Move to next row
                $currentY++
                $currentX = 0

                if ($currentY -ge 2) {
                    # Out of space, stop rendering chips
                    break
                }

                # Draw border for new row
                $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $chipRow1Y + $currentY - 1))
                $sb.Append($borderColor)
                $sb.Append($this.GetBoxChar('single_vertical'))

                $sb.Append($this.BuildMoveTo($this.X, $chipRow1Y + $currentY))
                $sb.Append($borderColor)
                $sb.Append($this.GetBoxChar('single_vertical'))
            }

            # Position for chip
            if ($currentX -eq 0) {
                $sb.Append($this.BuildMoveTo($this.X + 2, $chipRow1Y + $currentY))
            }

            # Render chip
            $chipColor = $this._GetChipColor($tag)
            $sb.Append($chipColor)
            $sb.Append($chipText)
            $sb.Append($reset)
            $sb.Append(" ")

            $currentX += $chipDisplayLen + 1  # +1 for space
        }

        # Input field on same row or next row
        $inputFieldY = $chipRow1Y + $currentY
        $inputStartX = $currentX

        # Check if we need new row for input
        $inputSpaceNeeded = 15  # Minimum space for input
        if ($inputStartX + $inputSpaceNeeded -gt $innerWidth) {
            # Move input to next row
            $currentY++
            $inputFieldY = $chipRow1Y + $currentY
            $inputStartX = 0

            # Fill rest of current row
            if ($currentX -lt $innerWidth) {
                $padding = $innerWidth - $currentX
                $sb.Append(" " * $padding)
            }

            # Draw border for current row
            $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $chipRow1Y + $currentY - 1))
            $sb.Append($borderColor)
            $sb.Append($this.GetBoxChar('single_vertical'))

            # Start new row
            $sb.Append($this.BuildMoveTo($this.X, $inputFieldY))
            $sb.Append($borderColor)
            $sb.Append($this.GetBoxChar('single_vertical'))
        }

        # Render input field
        if ($inputFieldY -lt $chipRow2Y + 1) {
            $sb.Append($this.BuildMoveTo($this.X + 2 + $inputStartX, $inputFieldY))

            if ([string]::IsNullOrEmpty($this._inputText)) {
                $sb.Append($mutedColor)
                $sb.Append("type tag...")
                $inputDisplayLen = 11
            }
            else {
                $sb.Append($textColor)

                # Render text with cursor
                $displayText = $this._inputText
                $maxInputWidth = $innerWidth - $inputStartX

                if ($displayText.Length -gt $maxInputWidth) {
                    $displayText = $displayText.Substring(0, $maxInputWidth)
                }

                # Text before cursor
                if ($this._cursorPosition -gt 0 -and $this._cursorPosition -le $displayText.Length) {
                    $sb.Append($displayText.Substring(0, $this._cursorPosition))
                }

                # Cursor and text after
                if ($this._cursorPosition -lt $displayText.Length) {
                    # Cursor on character
                    $sb.Append("`e[7m")
                    $sb.Append($displayText[$this._cursorPosition])
                    $sb.Append("`e[27m")

                    # Text after cursor
                    if ($this._cursorPosition + 1 -lt $displayText.Length) {
                        $sb.Append($displayText.Substring($this._cursorPosition + 1))
                    }
                }
                else {
                    # Cursor at end - show block cursor
                    $sb.Append("`e[7m `e[27m")
                }

                $inputDisplayLen = $displayText.Length + 1
            }

            # Padding for input row
            $remainingSpace = $innerWidth - $inputStartX - $inputDisplayLen
            if ($remainingSpace -gt 0) {
                $sb.Append(" " * $remainingSpace)
            }
        }

        # Complete all rows with borders
        for ($row = 0; $row -le 1; $row++) {
            $rowY = $chipRow1Y + $row

            # Right border
            $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $rowY))
            $sb.Append($borderColor)
            $sb.Append($this.GetBoxChar('single_vertical'))
        }

        # Autocomplete dropdown (if shown)
        if ($this._showAutocomplete -and $this._autocompleteMatches.Count -gt 0) {
            $acRow = $chipRow2Y + 1
            $maxAcItems = [Math]::Min(3, $this._autocompleteMatches.Count)

            for ($i = 0; $i -lt $maxAcItems; $i++) {
                $acY = $acRow + $i
                if ($acY -ge $this.Y + $this.Height - 1) {
                    break
                }

                $sb.Append($this.BuildMoveTo($this.X, $acY))
                $sb.Append($borderColor)
                $sb.Append($this.GetBoxChar('single_vertical'))

                $sb.Append($this.BuildMoveTo($this.X + 4, $acY))

                $tag = $this._autocompleteMatches[$i]
                if ($i -eq $this._selectedAutocompleteIndex) {
                    $sb.Append($highlightBg)
                    $sb.Append($highlightFg)
                }
                else {
                    $sb.Append($mutedColor)
                }

                $sb.Append($this.TruncateText($tag, $this.Width - 6))
                $sb.Append($reset)

                $displayLen = [Math]::Min($tag.Length, $this.Width - 6)
                $padding = $this.Width - 6 - $displayLen
                if ($padding -gt 0) {
                    $sb.Append(" " * $padding)
                }

                $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $acY))
                $sb.Append($borderColor)
                $sb.Append($this.GetBoxChar('single_vertical'))
            }
        }

        # Help/status row
        $helpRowY = $this.Y + $this.Height - 2
        $sb.Append($this.BuildMoveTo($this.X, $helpRowY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        $sb.Append($this.BuildMoveTo($this.X + 2, $helpRowY))
        $sb.Append($mutedColor)
        $helpText = "Tab/Enter=Add | Backspace=Remove | Esc=Done"
        $sb.Append($this.TruncateText($helpText, $this.Width - 4))

        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $helpRowY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        # Bottom border
        $sb.Append($this.BuildMoveTo($this.X, $this.Y + $this.Height - 1))
        $sb.Append($borderColor)
        $sb.Append($this.BuildBoxBorder($this.Width, 'bottom', 'single'))

        # Error message in bottom border
        if (-not [string]::IsNullOrWhiteSpace($this._errorMessage)) {
            $errorMsg = " $($this._errorMessage) "
            $sb.Append($this.BuildMoveTo($this.X + 2, $this.Y + $this.Height - 1))
            $sb.Append($errorColor)
            $sb.Append($this.TruncateText($errorMsg, $this.Width - 4))
        }

        $sb.Append($reset)
        return $sb.ToString()
    }

    # === Private Helper Methods ===

    <#
    .SYNOPSIS
    Load known tags from all tasks in PMC data
    #>
    hidden [void] _LoadKnownTags() {
        try {
            $data = Get-PmcData
            $tagSet = [HashSet[string]]::new()

            if ($null -ne $data.tasks) {
                foreach ($task in $data.tasks) {
                    if ($null -ne $task.tags -and $task.tags.Count -gt 0) {
                        foreach ($tag in $task.tags) {
                            if (-not [string]::IsNullOrWhiteSpace($tag)) {
                                [void]$tagSet.Add($tag.ToString().Trim())
                            }
                        }
                    }
                }
            }

            $this._allKnownTags = @($tagSet | Sort-Object)
            $this._lastTagRefresh = [DateTime]::Now
        }
        catch {
            # Failed to load tags - use empty array
            $this._allKnownTags = @()
        }
    }

    <#
    .SYNOPSIS
    Update autocomplete suggestions based on current input
    #>
    hidden [void] _UpdateAutocomplete() {
        if ([string]::IsNullOrWhiteSpace($this._inputText)) {
            $this._showAutocomplete = $false
            $this._autocompleteMatches = @()
            return
        }

        $inputLower = $this._inputText.ToLower()
        $matches = @()

        foreach ($tag in $this._allKnownTags) {
            # Skip already selected tags
            if ($this._selectedTags.Contains($tag)) {
                continue
            }

            # Match tags starting with input
            if ($tag.ToLower().StartsWith($inputLower)) {
                $matches += $tag
            }
        }

        $this._autocompleteMatches = $matches
        $this._showAutocomplete = $matches.Count -gt 0
        $this._selectedAutocompleteIndex = 0
    }

    <#
    .SYNOPSIS
    Add current input text as a tag
    #>
    hidden [void] _AddCurrentInputAsTag() {
        $tagText = $this._inputText.Trim()

        if ([string]::IsNullOrWhiteSpace($tagText)) {
            return
        }

        if ($this._selectedTags.Contains($tagText)) {
            $this._errorMessage = "Tag already added"
            $this._inputText = ""
            $this._cursorPosition = 0
            $this._showAutocomplete = $false
            return
        }

        if ($this._selectedTags.Count -ge $this.MaxTags) {
            $this._errorMessage = "Max $($this.MaxTags) tags"
            return
        }

        # Check if tag exists in known tags or if we allow new tags
        $isKnown = $this._allKnownTags -contains $tagText
        if (-not $isKnown -and -not $this.AllowNewTags) {
            $this._errorMessage = "Unknown tag (use existing tags)"
            return
        }

        $this._selectedTags.Add($tagText)
        $this._inputText = ""
        $this._cursorPosition = 0
        $this._showAutocomplete = $false
        $this._errorMessage = ""

        $this._InvokeCallback($this.OnTagsChanged, $this.GetTags())
    }

    <#
    .SYNOPSIS
    Build display string for all chips

    .OUTPUTS
    String containing all chip representations
    #>
    hidden [string] _BuildChipsDisplay() {
        $sb = [StringBuilder]::new()

        foreach ($tag in $this._selectedTags) {
            $sb.Append($this._FormatChip($tag))
            $sb.Append(" ")
        }

        return $sb.ToString()
    }

    <#
    .SYNOPSIS
    Format a single chip with color

    .PARAMETER tag
    Tag text

    .OUTPUTS
    ANSI-colored chip string
    #>
    hidden [string] _FormatChip([string]$tag) {
        return "[$tag]"
    }

    <#
    .SYNOPSIS
    Get color for a tag chip (consistent color based on tag name)

    .PARAMETER tag
    Tag text

    .OUTPUTS
    ANSI color sequence
    #>
    hidden [string] _GetChipColor([string]$tag) {
        # Hash tag name to get consistent color
        $hash = 0
        foreach ($char in $tag.ToCharArray()) {
            $hash = ($hash * 31 + [int]$char) % 2147483647
        }

        $colorIndex = $hash % $this._chipColors.Count
        $hex = $this._chipColors[$colorIndex]

        # Convert hex to RGB
        $hex = $hex.TrimStart('#')
        $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)

        return "`e[38;2;${r};${g};${b}m"
    }

    <#
    .SYNOPSIS
    Invoke a callback scriptblock safely

    .PARAMETER callback
    Scriptblock to invoke

    .PARAMETER args
    Arguments to pass
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