# TabbedScreen.ps1 - Base class for screens using tabbed interface

using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

if (-not ([System.Management.Automation.PSTypeName]'PmcScreen').Type) {
    . "$PSScriptRoot/../PmcScreen.ps1"
}
if (-not ([System.Management.Automation.PSTypeName]'TabPanel').Type) {
    . "$PSScriptRoot/../widgets/TabPanel.ps1"
}
if (-not ([System.Management.Automation.PSTypeName]'InlineEditor').Type) {
    . "$PSScriptRoot/../widgets/InlineEditor.ps1"
}

class TabbedScreen : PmcScreen {
    [TabPanel]$TabPanel = $null
    [InlineEditor]$InlineEditor = $null
    [bool]$ShowEditor = $false
    [object]$CurrentEditField = $null

    TabbedScreen([string]$key, [string]$title) : base($key, $title) {
        $this._InitializeComponents()
    }

    TabbedScreen([string]$key, [string]$title, [object]$container) : base($key, $title, $container) {
        $this._InitializeComponents()
    }

    hidden [void] _InitializeComponents() {
        $termSize = $this._GetTerminalSize()
        $this.TermWidth = $termSize.Width
        $this.TermHeight = $termSize.Height

        $this.TabPanel = [TabPanel]::new()
        $contentHeight = $this.TermHeight - 9
        $this.TabPanel.X = 2
        $this.TabPanel.Y = 8
        $this.TabPanel.Width = $this.TermWidth - 4
        $this.TabPanel.Height = $contentHeight

        $self = $this
        $this.TabPanel.OnTabChanged = { param($tabIndex); $self.OnTabChanged($tabIndex) }.GetNewClosure()
        $this.TabPanel.OnFieldSelected = { param($field); $self.OnFieldSelected($field) }.GetNewClosure()

        $this.InlineEditor = [InlineEditor]::new()
        $this.InlineEditor.LayoutMode = "vertical"
        $this.InlineEditor.X = [Math]::Max(1, [Math]::Floor(($termSize.Width - 60) / 2))
        $this.InlineEditor.Y = [Math]::Max(3, [Math]::Floor(($termSize.Height - 12) / 2))
        $this.InlineEditor.Width = [Math]::Min(60, $termSize.Width - 2)
        $this.InlineEditor.Height = [Math]::Min(12, $termSize.Height - 4)

        $this.Footer.AddShortcut("Enter", "Edit")
        $this.Footer.AddShortcut("S", "Save")
        $this.Footer.AddShortcut("Esc", "Back")
    }

    [void] OnEnter() {
        $this.IsActive = $true
        $this.LoadData()
        if ($this.Header) { $this.Header.SetBreadcrumb(@("Home", $this.ScreenTitle)) }
    }

    [void] OnDoExit() { $this.IsActive = $false }
    [void] LoadData() { throw "LoadData() must be implemented in subclass" }
    [void] SaveChanges() { throw "SaveChanges() must be implemented in subclass" }

    [void] OnTabChanged([int]$tabIndex) {
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.OnTabChanged: tabIndex=$tabIndex"
        }
        if ($this.StatusBar) {
            $tab = $this.TabPanel.GetCurrentTab()
            if ($tab) { $this.StatusBar.SetLeftText("Tab: $($tab.Name)") }
        }
    }

    [void] OnFieldSelected($field) {
        if ($global:PmcTuiLogFile) {
            $fname = if ($field) { $field.Name } else { "null" }
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.OnFieldSelected: field=$fname"
        }
        if ($this.StatusBar -and $field) {
            $this.StatusBar.SetLeftText("$($field.Label)")
        }
    }

    [void] OnFieldEdited($field, $newValue) {
        if ($global:PmcTuiLogFile) {
            $fname = if ($field) { $field.Name } else { "null" }
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.OnFieldEdited (BASE): field=$fname value='$newValue'"
        }
        # Default: subclass can override
    }

    [void] EditCurrentField() {
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.EditCurrentField: ENTRY"
        }
        
        $field = $this.TabPanel.GetCurrentField()
        if ($null -eq $field) { 
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.EditCurrentField: No current field, returning"
            }
            return 
        }

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.EditCurrentField: field='$($field.Name)' Type='$(if ($field.ContainsKey('Type')) { $field.Type } else { 'text' })'"
        }

        if ($field.ContainsKey('IsAction') -and $field.IsAction) {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.EditCurrentField: IsAction=true, calling OnFieldEdited"
            }
            $this.OnFieldEdited($field, $null)
            return
        }

        $fieldType = $(if ($field.ContainsKey('Type')) { $field.Type } else { 'text' })
        if ($fieldType -eq 'readonly') { 
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.EditCurrentField: readonly field, returning"
            }
            return 
        }

        $this.CurrentEditField = $field
        $fieldDef = @{
            Name = $field.Name; Label = ''; Type = $fieldType; Value = $field.Value
            Required = $(if ($field.ContainsKey('Required')) { $field.Required } else { $false })
            Width = $this.TabPanel.Width - $this.TabPanel.LabelWidth - ($this.TabPanel.ContentPadding * 2) - 2
        }
        if ($fieldType -eq 'number') {
            if ($field.ContainsKey('Min')) { $fieldDef.Min = $field.Min }
            if ($field.ContainsKey('Max')) { $fieldDef.Max = $field.Max }
        }

        $tab = $this.TabPanel.GetCurrentTab()
        $fieldIndex = $this.TabPanel.SelectedFieldIndex
        $visibleIndex = $fieldIndex - $tab.ScrollOffset
        $editorX = $this.TabPanel.X + $this.TabPanel.ContentPadding + $this.TabPanel.LabelWidth
        $editorY = $this.TabPanel.Y + $this.TabPanel.TabBarHeight + $visibleIndex

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.EditCurrentField: Setting up InlineEditor at X=$editorX Y=$editorY Width=$($fieldDef.Width)"
        }

        $this.InlineEditor.LayoutMode = "horizontal"
        $this.InlineEditor.Title = ""
        $this.InlineEditor.X = $editorX
        $this.InlineEditor.Y = $editorY
        $this.InlineEditor.Width = $fieldDef.Width
        $this.InlineEditor.Height = 1
        $this.InlineEditor.SetFields(@($fieldDef))
        $this.ShowEditor = $true
        
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.EditCurrentField: ShowEditor=$($this.ShowEditor) DONE"
        }
    }

    hidden [void] _SaveEditedField($values) {
        if ($global:PmcTuiLogFile) {
            $valStr = try { $values | ConvertTo-Json -Compress -Depth 1 } catch { "(serialize error)" }
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: ENTRY values=$valStr"
        }
        
        if ($null -eq $this.CurrentEditField) { 
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: CurrentEditField is NULL, returning"
            }
            return 
        }

        $fieldName = $this.CurrentEditField.Name
        $newValue = $values[$fieldName]
        $editedField = $this.CurrentEditField

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: fieldName='$fieldName' newValue='$newValue'"
        }

        # Update TabPanel
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: Calling TabPanel.UpdateFieldValue..."
        }
        $this.TabPanel.UpdateFieldValue($fieldName, $newValue)
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: TabPanel.UpdateFieldValue DONE"
        }

        # Close editor FIRST
        $this.ShowEditor = $false
        $this.CurrentEditField = $null
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: Editor closed (ShowEditor=false)"
        }

        if ($this.RenderEngine -and $this.InlineEditor) {
            $editorY = $this.InlineEditor.Y
            $this.RenderEngine.InvalidateCachedRegion($editorY, $editorY + 3)
        }

        # Call subclass hook
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: Calling OnFieldEdited..."
        }
        $this.OnFieldEdited($editedField, $newValue)
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: OnFieldEdited DONE"
        }

        if ($this.StatusBar) {
            $this.StatusBar.SetRightText("Field updated")
        }
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen._SaveEditedField: COMPLETE"
        }
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: Key=$($keyInfo.Key) Char='$($keyInfo.KeyChar)' ShowEditor=$($this.ShowEditor)"
        }
        
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt) {
            if ($null -ne $this.MenuBar -and $this.MenuBar.HandleKeyPress($keyInfo)) {
                return $true
            }
        }

        if ($null -ne $this.MenuBar -and $this.MenuBar.IsActive) {
            # Menu active - fall through
        }

        # If InlineEditor is showing, route input to it FIRST
        if ($this.ShowEditor -and $this.InlineEditor) {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: Routing to InlineEditor..."
            }
            $handled = $this.InlineEditor.HandleInput($keyInfo)
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: InlineEditor returned handled=$handled IsConfirmed=$($this.InlineEditor.IsConfirmed) IsCancelled=$($this.InlineEditor.IsCancelled)"
            }
            
            if ($this.InlineEditor.IsConfirmed) {
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: IsConfirmed=true, getting values..."
                }
                $values = $this.InlineEditor.GetValues()
                if ($global:PmcTuiLogFile) {
                    $valStr = try { $values | ConvertTo-Json -Compress -Depth 1 } catch { "(serialize error)" }
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: Got values=$valStr, calling _SaveEditedField..."
                }
                $this._SaveEditedField($values)
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: _SaveEditedField returned, resetting flags..."
                }
                $this.InlineEditor.IsConfirmed = $false
                $this.InlineEditor.IsCancelled = $false
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: Confirm flow COMPLETE"
                }
                return $true
            }
            
            if ($this.InlineEditor.IsCancelled) {
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: IsCancelled=true, closing editor"
                }
                $this.ShowEditor = $false
                $this.CurrentEditField = $null
                $this.InlineEditor.IsConfirmed = $false
                $this.InlineEditor.IsCancelled = $false
                if ($this.StatusBar) { $this.StatusBar.SetRightText("Edit cancelled") }
                return $true
            }
            
            if ($handled) { return $true }
        }

        if ($keyInfo.Key -eq 'Enter') {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: Enter pressed (editor not showing), calling EditCurrentField"
            }
            $this.EditCurrentField()
            return $true
        }

        if ($keyInfo.KeyChar -eq 's' -or $keyInfo.KeyChar -eq 'S') {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: S pressed, calling SaveChanges..."
            }
            $this.SaveChanges()
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: SaveChanges DONE"
            }
            if ($this.StatusBar) { $this.StatusBar.SetRightText("Changes saved") }
            return $true
        }

        if ($keyInfo.Key -eq 'Escape') {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] TabbedScreen.HandleKeyPress: Escape pressed, popping screen"
            }
            $global:PmcApp.PopScreen()
            return $true
        }

        $handled = $this.TabPanel.HandleInput($keyInfo)
        if ($handled) { return $true }

        return $false
    }

    [void] RenderContentToEngine([object]$engine) {
        if (-not $this.TabPanel) { return }
        $this.TabPanel.RenderToEngine($engine)
        if ($this.ShowEditor -and $this.InlineEditor) {
            $this.InlineEditor.RenderToEngine($engine)
        }
    }

    [string] RenderContent() { return "" }

    hidden [hashtable] _GetTerminalSize() {
        return @{ Width = [Console]::WindowWidth; Height = [Console]::WindowHeight }
    }
}

Export-ModuleMember -Variable @()