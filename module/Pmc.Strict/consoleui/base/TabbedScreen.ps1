# TabbedScreen.ps1 - Base class for screens using tabbed interface
#
# Usage:
#   class MyScreen : TabbedScreen {
#       MyScreen() : base("MyScreen", "My Title") {
#           $this._InitializeTabs()
#       }
#
#       hidden [void] _InitializeTabs() {
#           $this.TabPanel.AddTab('General', $this.GetGeneralFields())
#           $this.TabPanel.AddTab('Details', $this.GetDetailFields())
#       }
#
#       [array] GetGeneralFields() {
#           return @(
#               @{Name='name'; Label='Name'; Value=$this.Data.name}
#               @{Name='email'; Label='Email'; Value=$this.Data.email}
#           )
#       }
#
#       [void] SaveChanges() {
#           $values = $this.TabPanel.GetAllValues()
#           # Save to store
#       }
#   }

using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

# Load dependencies
if (-not ([System.Management.Automation.PSTypeName]'PmcScreen').Type) {
    . "$PSScriptRoot/../PmcScreen.ps1"
}

if (-not ([System.Management.Automation.PSTypeName]'TabPanel').Type) {
    . "$PSScriptRoot/../widgets/TabPanel.ps1"
}

if (-not ([System.Management.Automation.PSTypeName]'InlineEditor').Type) {
    . "$PSScriptRoot/../widgets/InlineEditor.ps1"
}

<#
.SYNOPSIS
Base class for screens using tabbed interface to organize many fields

.DESCRIPTION
TabbedScreen provides a complete tabbed interface experience:
- TabPanel widget for tab navigation
- InlineEditor for field editing (vertical popup mode)
- Automatic keyboard navigation (Tab, arrows, numbers)
- Edit mode with save/cancel
- Theme integration
- Extensible via abstract methods

Abstract Methods (override in subclasses):
- LoadData() - Load data for fields
- SaveChanges() - Save field values

Optional Overrides:
- OnTabChanged($tabIndex) - Handle tab change
- OnFieldSelected($field) - Handle field selection
- OnFieldEdited($field, $newValue) - Handle field edit

.EXAMPLE
class SettingsScreen : TabbedScreen {
    SettingsScreen() : base("Settings", "Application Settings") {
        $this.TabPanel.AddTab('General', @(
            @{Name='theme'; Label='Theme'; Value='dark'}
            @{Name='fontSize'; Label='Font Size'; Value=12}
        ))
        $this.TabPanel.AddTab('Advanced', @(...))
    }

    [void] SaveChanges() {
        $values = $this.TabPanel.GetAllValues()
        $this.Store.UpdateSettings($values)
    }
}
#>
class TabbedScreen : PmcScreen {
    # === Core Components ===
    [TabPanel]$TabPanel = $null
    [InlineEditor]$InlineEditor = $null

    # === Component State ===
    [bool]$ShowEditor = $false
    [object]$CurrentEditField = $null

    # === Constructor (no container) ===
    TabbedScreen([string]$key, [string]$title) : base($key, $title) {
        $this._InitializeComponents()
    }

    # === Constructor (with container) ===
    TabbedScreen([string]$key, [string]$title, [object]$container) : base($key, $title, $container) {
        $this._InitializeComponents()
    }

    # === Initialization ===

    hidden [void] _InitializeComponents() {
        # Get terminal size
        $termSize = $this._GetTerminalSize()
        $this.TermWidth = $termSize.Width
        $this.TermHeight = $termSize.Height

        # Initialize TabPanel
        $this.TabPanel = [TabPanel]::new()

        # Position and size TabPanel to fit in content area
        # Account for header (title=1 + breadcrumb=1 + separator=1 = 3 rows), footer (2 rows), menu (1 row)
        # TabPanel Y must be AFTER header separator
        # Header: Y=2 (title), Y=4 (breadcrumb), Y=6 (separator)
        # TabPanel starts at Y=7
        $contentHeight = $this.TermHeight - 9  # header(3) + footer(2) + menu(1) + TabPanel tabs(2) + padding(1)

        $this.TabPanel.X = 2
        $this.TabPanel.Y = 7  # After header separator at Y=6
        $this.TabPanel.Width = $this.TermWidth - 4
        $this.TabPanel.Height = $contentHeight

        # Wire up TabPanel events
        $self = $this
        $this.TabPanel.OnTabChanged = {
            param($tabIndex)
            $self.OnTabChanged($tabIndex)
        }.GetNewClosure()

        $this.TabPanel.OnFieldSelected = {
            param($field)
            $self.OnFieldSelected($field)
        }.GetNewClosure()

        # Initialize InlineEditor (for editing fields)
        $this.InlineEditor = [InlineEditor]::new()
        $this.InlineEditor.LayoutMode = "vertical"  # Popup mode
        $termSize = $this._GetTerminalSize()
        $this.InlineEditor.X = [Math]::Max(1, [Math]::Floor(($termSize.Width - 60) / 2))
        $this.InlineEditor.Y = [Math]::Max(3, [Math]::Floor(($termSize.Height - 12) / 2))
        $this.InlineEditor.Width = [Math]::Min(60, $termSize.Width - 2)
        $this.InlineEditor.Height = [Math]::Min(12, $termSize.Height - 4)

        # Wire up InlineEditor events
        $this.InlineEditor.OnConfirmed = {
            param($values)
            $self._SaveEditedField($values)
        }.GetNewClosure()

        $this.InlineEditor.OnCancelled = {
            $self.ShowEditor = $false
            $self.CurrentEditField = $null
        }.GetNewClosure()

        # Configure footer shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Tab", "Next Tab")
        $this.Footer.AddShortcut("↑↓", "Navigate")
        $this.Footer.AddShortcut("Enter", "Edit")
        $this.Footer.AddShortcut("S", "Save")
        $this.Footer.AddShortcut("Esc", "Back")
    }

    # === Lifecycle Methods ===

    [void] OnEnter() {
        $this.IsActive = $true

        # Load data
        $this.LoadData()

        # Update header breadcrumb
        if ($this.Header) {
            $this.Header.SetBreadcrumb(@("Home", $this.ScreenTitle))
        }
    }

    [void] OnDoExit() {
        $this.IsActive = $false
    }

    # === Abstract Methods (MUST override) ===

    <#
    .SYNOPSIS
    Load data and populate tabs (ABSTRACT - must override)
    #>
    [void] LoadData() {
        throw "LoadData() must be implemented in subclass"
    }

    <#
    .SYNOPSIS
    Save changes from all field values (ABSTRACT - must override)
    #>
    [void] SaveChanges() {
        throw "SaveChanges() must be implemented in subclass"
    }

    # === Optional Override Methods ===

    <#
    .SYNOPSIS
    Handle tab change (optional override)
    #>
    [void] OnTabChanged([int]$tabIndex) {
        if ($global:PmcTuiLogFile) {
            $tab = $this.TabPanel.GetCurrentTab()
            $tabName = $(if ($tab) { $tab.Name } else { "null" })
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ========== TabbedScreen.OnTabChanged: Switched to tab $tabIndex '$tabName' =========="
        }

        # Surgically invalidate TabPanel content region to clear old tab content
        # Calculate Y range: contentY to contentY + max visible rows
        # contentY = TabPanel.Y + TabBarHeight (2 rows for tabs)
        # We need to clear the entire possible field rendering area
        $contentY = $this.TabPanel.Y + $this.TabPanel.TabBarHeight
        $maxRows = $this.TabPanel.Height  # Clear entire content area
        $minY = $contentY
        $maxY = $contentY + $maxRows

        if ($this.RenderEngine) {
            $this.RenderEngine.InvalidateCachedRegion($minY, $maxY)
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.OnTabChanged: Invalidated cache region Y=$minY-$maxY (no flicker)"
            }
        }

        # Force full redraw to clear old tab content
        $this.TabPanel.Invalidate()

        # Default: update status bar
        if ($this.StatusBar) {
            $tab = $this.TabPanel.GetCurrentTab()
            if ($tab) {
                $this.StatusBar.SetLeftText("Tab: $($tab.Name) ($($tab.Fields.Count) fields)")
            }
        }
    }

    <#
    .SYNOPSIS
    Handle field selection (optional override)
    #>
    [void] OnFieldSelected($field) {
        # Default: update status bar
        if ($this.StatusBar -and $field) {
            $value = $(if ($field.Value) { $field.Value } else { "(empty)" })
            $this.StatusBar.SetLeftText("$($field.Label): $value")
        }
    }

    <#
    .SYNOPSIS
    Handle field edit (optional override)
    #>
    [void] OnFieldEdited($field, $newValue) {
        # Default: just update the field
        # Subclass can override to add validation, logging, etc.
    }

    # === Field Editing ===

    [void] EditCurrentField() {
        $field = $this.TabPanel.GetCurrentField()
        if ($null -eq $field) { return }

        # Check if this is an action field (readonly with IsAction flag)
        if ($field.ContainsKey('IsAction') -and $field.IsAction) {
            # Trigger action callback instead of editing
            $this.OnFieldEdited($field, $null)
            return
        }

        # Check if readonly but not an action - skip editing
        $fieldType = $(if ($field.ContainsKey('Type')) { $field.Type } else { 'text' })
        if ($fieldType -eq 'readonly') {
            # Skip editing readonly fields that aren't actions
            return
        }

        $this.CurrentEditField = $field

        # Build field definition for InlineEditor
        $fieldDef = @{
            Name     = $field.Name
            Label    = ''  # No label for inline editing
            Type     = $fieldType
            Value    = $field.Value
            Required = $(if ($field.ContainsKey('Required')) { $field.Required } else { $false })
            Width    = $this.TabPanel.Width - $this.TabPanel.LabelWidth - ($this.TabPanel.ContentPadding * 2) - 2
        }

        # Add type-specific properties
        if ($fieldType -eq 'number') {
            if ($field.ContainsKey('Min')) { $fieldDef.Min = $field.Min }
            if ($field.ContainsKey('Max')) { $fieldDef.Max = $field.Max }
        }

        # Calculate position for inline editor
        # It should be over the value part of the field
        $tab = $this.TabPanel.GetCurrentTab()
        $fieldIndex = $this.TabPanel.SelectedFieldIndex
        $visibleIndex = $fieldIndex - $tab.ScrollOffset

        # Calculate absolute position
        # X: TabPanel X + Padding + LabelWidth (align with value column)
        $editorX = $this.TabPanel.X + $this.TabPanel.ContentPadding + $this.TabPanel.LabelWidth
        # Y: Match TabPanel._RenderContent calculation exactly
        # contentY = TabPanel.Y + TabBarHeight (Y+2)
        # field Y = contentY + row + 1
        # For first field (row=0): Y+2+0+1 = Y+3
        # For visibleIndex N: Y + TabBarHeight + N + 1
        $contentY = $this.TabPanel.Y + $this.TabPanel.TabBarHeight
        $editorY = $contentY + $visibleIndex + 1

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.EditCurrentField: field='$($field.Name)' fieldIndex=$fieldIndex visibleIndex=$visibleIndex"
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.EditCurrentField: TabPanel.Y=$($this.TabPanel.Y) TabBarHeight=$($this.TabPanel.TabBarHeight) contentY=$contentY"
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.EditCurrentField: Calculated editor position: X=$editorX Y=$editorY"
        }

        # CRITICAL: Set LayoutMode BEFORE SetFields() because SetFields() adds Save button based on LayoutMode
        $this.InlineEditor.LayoutMode = "horizontal"  # No Save button in horizontal mode
        $this.InlineEditor.Title = ""  # No title for inline editing
        $this.InlineEditor.X = $editorX
        $this.InlineEditor.Y = $editorY
        $this.InlineEditor.Width = $fieldDef.Width
        $this.InlineEditor.Height = 1  # Single line

        # SetFields() must be called AFTER LayoutMode is set
        $this.InlineEditor.SetFields(@($fieldDef))

        $this.ShowEditor = $true
    }

    hidden [void] _SaveEditedField($values) {
        if ($null -eq $this.CurrentEditField) { return }

        $fieldName = $this.CurrentEditField.Name
        $newValue = $values[$fieldName]

        # Update TabPanel field value
        $this.TabPanel.UpdateFieldValue($fieldName, $newValue)

        # Call subclass hook
        $this.OnFieldEdited($this.CurrentEditField, $newValue)

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: Closing editor, field='$fieldName' newValue='$newValue'"
        }

        # Close editor
        $this.ShowEditor = $false
        $this.CurrentEditField = $null

        # Surgically invalidate editor region to clear artifacts
        # InlineEditor in horizontal mode may render validation messages, borders, etc.
        # Invalidate the field line AND next 3 lines to ensure all editor artifacts are cleared
        if ($this.RenderEngine -and $this.InlineEditor) {
            $editorY = $this.InlineEditor.Y
            $editorHeight = 4  # Field + potential validation message + padding
            $this.RenderEngine.InvalidateCachedRegion($editorY, $editorY + $editorHeight - 1)
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: Invalidated editor region Y=$editorY-$($editorY + $editorHeight - 1) (no flicker)"
            }
        }

        # Force TabPanel to invalidate and redraw
        $this.TabPanel.Invalidate()

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: Editor closed, TabPanel invalidated"
        }

        # Show success message
        if ($this.StatusBar) {
            $this.StatusBar.SetRightText("Field updated")
        }
    }

    # === Input Handling ===

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # Check Alt+key for menu bar first (before editor)
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt) {
            if ($null -ne $this.MenuBar -and $this.MenuBar.HandleKeyPress($keyInfo)) {
                return $true
            }
        }

        # If menu is active, route all keys to it FIRST (including Esc to close)
        if ($null -ne $this.MenuBar -and $this.MenuBar.IsActive) {
            if ($this.MenuBar.HandleKeyPress($keyInfo)) {
                return $true
            }
        }

        # If editor is showing, route to it next
        if ($this.ShowEditor) {
            $handled = $this.InlineEditor.HandleInput($keyInfo)

            # Check if editor closed
            if ($this.InlineEditor.IsConfirmed -or $this.InlineEditor.IsCancelled) {
                $this.ShowEditor = $false
                $this.CurrentEditField = $null
                return $true
            }

            if ($handled) {
                return $true
            }
            # FIX: If editor didn't handle key, still consume it to prevent fall-through
            # This prevents Enter from triggering EditCurrentField while editor is open
            return $true
        }

        # Enter key - edit current field (ONLY when editor is NOT showing)
        if ($keyInfo.Key -eq 'Enter') {
            $this.EditCurrentField()
            return $true
        }

        # S key - save all changes
        if ($keyInfo.KeyChar -eq 's' -or $keyInfo.KeyChar -eq 'S') {
            try {
                $this.SaveChanges()
                if ($this.StatusBar) {
                    $this.StatusBar.SetRightText("Changes saved")
                }
            }
            catch {
                if ($this.StatusBar) {
                    $this.StatusBar.SetRightText("Save failed: $_")
                }
            }
            return $true
        }

        # Escape - go back
        if ($keyInfo.Key -eq 'Escape') {
            $global:PmcApp.PopScreen()
            return $true
        }

        # Route to TabPanel
        $handled = $this.TabPanel.HandleInput($keyInfo)
        if ($handled) {
            return $true
        }

        # Not handled by TabPanel - return false so it bubbles up to app (for menu shortcuts, etc)
        return $false
    }

    # === Rendering ===

    [void] RenderContentToEngine([object]$engine) {
        Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TabbedScreen.RenderContentToEngine] START"

        if (-not $this.TabPanel) {
            Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TabbedScreen.RenderContentToEngine] ERROR: TabPanel is null!"
            return
        }

        # Render TabPanel
        # It handles its own layout and colors
        Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TabbedScreen.RenderContentToEngine] Calling TabPanel.RenderToEngine"
        $this.TabPanel.RenderToEngine($engine)

        # If editor is showing, render it on top (Z-Index is handled by widget or engine order)
        if ($this.ShowEditor -and $this.InlineEditor) {
            # InlineEditor uses Z-layer 10 in its RenderToEngine
            $this.InlineEditor.RenderToEngine($engine)
        }
    }

    # Legacy Stub
    [string] RenderContent() { return "" }

    # === Helper Methods ===

    hidden [hashtable] _GetTerminalSize() {
        $width = [Console]::WindowWidth
        $height = [Console]::WindowHeight
        return @{ Width = $width; Height = $height }
    }
}

# Export
Export-ModuleMember -Variable @()