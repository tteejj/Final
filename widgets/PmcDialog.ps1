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
    [bool]$IsComplete = $false
    [bool]$Result = $false
    [string]$TextResult = ''

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

<#
.SYNOPSIS
Multi-field project form dialog
#>
class ProjectFormDialog : PmcDialog {
    [hashtable]$Fields = @{
        name        = ''
        description = ''
        path        = ''
        aliases     = ''
    }
    [string]$CurrentField = 'name'
    [array]$FieldOrder = @('name', 'description', 'path', 'aliases')
    [hashtable]$FieldLabels = @{
        name        = 'Name'
        description = 'Description'
        path        = 'Path'
        aliases     = 'Aliases'
    }
    [bool]$IsEditMode = $false
    [string]$OriginalName = ''

    # Constructor for new project
    ProjectFormDialog() : base("Add Project", "Enter project details") {
        $this.Width = 70
        $this.Height = 16
        $this.IsEditMode = $false
    }

    # Constructor for editing existing project
    ProjectFormDialog([hashtable]$existingProject) : base("Edit Project", "Modify project details") {
        $this.Width = 70
        $this.Height = 16
        $this.IsEditMode = $true
        $this.OriginalName = $existingProject.name

        # Populate fields from existing project
        $this.Fields.name = $existingProject.name
        $this.Fields.description = $(if ($existingProject.description) { $existingProject.description } else { '' })
        $this.Fields.path = $(if ($existingProject.path) { $existingProject.path } else { '' })
        $this.Fields.aliases = $(if ($existingProject.aliases -and $existingProject.aliases.Count -gt 0) {
                $existingProject.aliases -join ', '
            }
            else {
                ''
            })
    }

    [void] RenderToEngine([object]$engine) {
        # Base renders Frame + Title
        ([PmcDialog]$this).RenderToEngine($engine)
        
        $bg = $this.GetThemedColorInt('Background.Widget')
        $fg = $this.GetThemedColorInt('Foreground.Primary')
        $highlight = $this.GetThemedColorInt('Foreground.RowSelected')
        $accentBg = $this.GetThemedColorInt('Background.RowSelected')
        $muted = $this.GetThemedColorInt('Foreground.Muted')
        
        # Override base BG for form? Or match it. Base uses 45,55,72. 
        # This form used 30,30,30. Let's use Base colors for consistency if possible, 
        # or stick to its own palette. 
        # Let's stick to its own palette for now to minimize visual change risk.
        # But we need to redraw base box with these colors if we want consistency.
        # Let's re-draw background/border using Form colors.
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $fg, $bg)
        $engine.WriteAt($this.X + 2, $this.Y + 1, $this.Title, $highlight, $bg)
        
        $fieldY = $this.Y + 3
        $labelX = $this.X + 4
        $inputX = $this.X + 18
        $inputWidth = $this.Width - 22
        
        foreach ($fieldName in $this.FieldOrder) {
            $isCurrent = ($fieldName -eq $this.CurrentField)
            $label = $this.FieldLabels[$fieldName]
            $value = $this.Fields[$fieldName]
            
            # Label
            $lFg = if ($isCurrent) { $highlight } else { $muted }
            $engine.WriteAt($labelX, $fieldY, $label.PadRight(12), $lFg, $bg)
            
            # Input
            $iBg = if ($isCurrent) { $accentBg } else { $bg }
            $iFg = $fg
            
            $disp = $value
            if ($disp.Length -gt $inputWidth) { $disp = $disp.Substring(0, $inputWidth - 3) + "..." }
            
            $engine.Fill($inputX, $fieldY, $inputWidth, 1, ' ', $iFg, $iBg)
            $engine.WriteAt($inputX, $fieldY, $disp, $iFg, $iBg)
            
            if ($isCurrent) {
                $cursorX = $inputX + [Math]::Min($value.Length, $inputWidth - 1)
                $engine.WriteAt($cursorX, $fieldY, "_", $highlight, $accentBg)
            }
            
            $fieldY += 2
        }
        
        # Instructions
        $inst = "Tab: Next | Enter: Save | Esc: Cancel"
        $instX = $this.X + [Math]::Floor(($this.Width - $inst.Length) / 2)
        $engine.WriteAt($instX, $this.Y + $this.Height - 3, $inst, $muted, $bg)
    }

    [string] Render([int]$termWidth, [int]$termHeight, [hashtable]$theme) { return "" }

    # REMOVED: UpdateFieldDisplay() - Dead code that was never called
    # This method used [Console]::Write() which bypassed the render engine layer system.
    # If field-by-field updates are needed in the future, they should use the render engine
    # with BeginLayer([ZIndex]::Dialog) instead of direct console writes.

    # File picker integration
    [string]$FilePicker = ''  # Signal to caller to show file picker

    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'Enter' {
                # Check if we're on path field - open file picker
                if ($this.CurrentField -eq 'path') {
                    $this.FilePicker = 'show'
                    return $true
                }

                # Otherwise validate and save
                if ([string]::IsNullOrWhiteSpace($this.Fields.name)) {
                    # Name is required - don't close
                    return $true
                }
                $this.Result = $true
                $this.IsComplete = $true
                return $true
            }
            'Escape' {
                $this.Result = $false
                $this.IsComplete = $true
                return $true
            }
            'Tab' {
                # Move to next field - NEEDS FULL REDRAW
                $currentIndex = $this.FieldOrder.IndexOf($this.CurrentField)
                if ($keyInfo.Modifiers -eq [ConsoleModifiers]::Shift) {
                    # Shift+Tab: previous field
                    $currentIndex--
                    if ($currentIndex -lt 0) {
                        $currentIndex = $this.FieldOrder.Count - 1
                    }
                }
                else {
                    # Tab: next field
                    $currentIndex++
                    if ($currentIndex -ge $this.FieldOrder.Count) {
                        $currentIndex = 0
                    }
                }
                $this.CurrentField = $this.FieldOrder[$currentIndex]
                return $true  # Caller must re-render
            }
            'UpArrow' {
                # Move to previous field - NEEDS FULL REDRAW
                $currentIndex = $this.FieldOrder.IndexOf($this.CurrentField)
                $currentIndex--
                if ($currentIndex -lt 0) {
                    $currentIndex = $this.FieldOrder.Count - 1
                }
                $this.CurrentField = $this.FieldOrder[$currentIndex]
                return $true  # Caller must re-render
            }
            'DownArrow' {
                # Move to next field - NEEDS FULL REDRAW
                $currentIndex = $this.FieldOrder.IndexOf($this.CurrentField)
                $currentIndex++
                if ($currentIndex -ge $this.FieldOrder.Count) {
                    $currentIndex = 0
                }
                $this.CurrentField = $this.FieldOrder[$currentIndex]
                return $true  # Caller must re-render
            }
            'Backspace' {
                # Delete character from current field - UPDATE CURRENT FIELD ONLY
                if ($this.Fields[$this.CurrentField].Length -gt 0) {
                    $this.Fields[$this.CurrentField] = $this.Fields[$this.CurrentField].Substring(0, $this.Fields[$this.CurrentField].Length - 1)
                }
                return $false  # No full redraw needed
            }
            default {
                # Add character to current field - UPDATE CURRENT FIELD ONLY
                if ($keyInfo.KeyChar -ge 32 -and $keyInfo.KeyChar -le 126) {
                    $this.Fields[$this.CurrentField] += $keyInfo.KeyChar
                }
                return $false  # No full redraw needed
            }
        }
        return $false
    }

    # Get the project hashtable result
    [hashtable] GetProject() {
        # Parse aliases from comma-separated string
        $aliasesArray = @()
        if (-not [string]::IsNullOrWhiteSpace($this.Fields.aliases)) {
            $aliasesArray = @($this.Fields.aliases -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        return @{
            name        = $this.Fields.name
            description = $this.Fields.description
            path        = $this.Fields.path
            aliases     = $aliasesArray
        }
    }
}