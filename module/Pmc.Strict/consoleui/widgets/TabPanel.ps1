# TabPanel.ps1 - Tabbed interface widget for organizing fields into logical groups
#
# Usage:
#   $tabPanel = [TabPanel]::new()
#   $tabPanel.AddTab('Identity', @(
#       @{Name='ID1'; Label='ID1'; Value='12345'}
#       @{Name='ID2'; Label='ID2'; Value='ABC-2024'}
#   ))
#   $tabPanel.AddTab('Request', @(...))
#
#   # Navigation
#   $tabPanel.NextTab()       # Tab key
#   $tabPanel.PrevTab()       # Shift+Tab
#   $tabPanel.SelectTab(2)    # Number keys 1-6
#   $tabPanel.NextField()     # Down arrow
#   $tabPanel.PrevField()     # Up arrow
#
#   # Rendering
#   $output = $tabPanel.Render()

using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

# Load PmcWidget base class
if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

<#
.SYNOPSIS
Tabbed interface widget for organizing many fields into logical groups

.DESCRIPTION
TabPanel provides a tab-based navigation interface for displaying and editing
grouped fields. Perfect for forms with many fields that need organization.

Features:
- Multiple tabs with labels
- Keyboard navigation (Tab/Shift+Tab, arrow keys, number keys)
- Inline field editing
- Theme integration
- Visual tab indicators (active, inactive)
- Field highlighting and selection
- Scrolling within tabs if needed

.EXAMPLE
$tabs = [TabPanel]::new()
$tabs.AddTab('General', @(
    @{Name='name'; Label='Name'; Value='John Doe'}
    @{Name='email'; Label='Email'; Value='john@example.com'}
))
$tabs.AddTab('Details', @(...))
$output = $tabs.Render()
#>
class TabPanel : PmcWidget {
    # === Tab Structure ===
    [List[hashtable]]$Tabs = [List[hashtable]]::new()
    [int]$CurrentTabIndex = 0
    [int]$SelectedFieldIndex = 0  # Field index within current tab

    # === Display Configuration ===
    [int]$TabBarHeight = 2        # Rows for tab bar
    [int]$ContentPadding = 2      # Padding inside content area
    [int]$LabelWidth = 22         # Width for field labels
    [bool]$ShowTabNumbers = $true # Show [1] [2] [3] on tabs

    # === Events ===
    [scriptblock]$OnTabChanged = {}      # Called when tab changes: param($tabIndex)
    [scriptblock]$OnFieldSelected = {}   # Called when field selected: param($field)
    [scriptblock]$OnFieldEdit = {}       # Called when field edited: param($field, $newValue)

    # === Constructor ===
    TabPanel() : base("TabPanel") {
        $this.Width = 80
        $this.Height = 25
        $this.CanFocus = $true
    }

    # === Tab Management ===

    <#
    .SYNOPSIS
    Add a new tab with fields

    .PARAMETER name
    Tab name/label

    .PARAMETER fields
    Array of field hashtables: @{Name=''; Label=''; Value=''; Type='text'}
    #>
    [void] AddTab([string]$name, [array]$fields) {
        $tab = @{
            Name         = $name
            Fields       = $fields
            ScrollOffset = 0
        }
        $this.Tabs.Add($tab)
    }
    [void] ClearTabs() { $this.Tabs.Clear(); $this.CurrentTabIndex = 0; $this.SelectedFieldIndex = 0 }

    <#
    .SYNOPSIS
    Get current tab
    #>
    [hashtable] GetCurrentTab() {
        if ($this.Tabs.Count -eq 0) {
            return $null
        }
        return $this.Tabs[$this.CurrentTabIndex]
    }

    <#
    .SYNOPSIS
    Get currently selected field
    #>
    [hashtable] GetCurrentField() {
        $tab = $this.GetCurrentTab()
        if ($null -eq $tab -or $tab.Fields.Count -eq 0) {
            return $null
        }

        if ($this.SelectedFieldIndex -ge 0 -and $this.SelectedFieldIndex -lt $tab.Fields.Count) {
            return $tab.Fields[$this.SelectedFieldIndex]
        }

        return $null
    }

    # === Navigation ===

    [void] NextTab() {
        if ($this.Tabs.Count -eq 0) { return }

        $oldIndex = $this.CurrentTabIndex
        $this.CurrentTabIndex = ($this.CurrentTabIndex + 1) % $this.Tabs.Count
        $this.SelectedFieldIndex = 0  # Reset to first field in new tab

        if ($oldIndex -ne $this.CurrentTabIndex) {
            $this._InvokeCallback($this.OnTabChanged, $this.CurrentTabIndex)
        }
    }

    [void] PrevTab() {
        if ($this.Tabs.Count -eq 0) { return }

        $oldIndex = $this.CurrentTabIndex
        $this.CurrentTabIndex--
        if ($this.CurrentTabIndex -lt 0) {
            $this.CurrentTabIndex = $this.Tabs.Count - 1
        }
        $this.SelectedFieldIndex = 0

        if ($oldIndex -ne $this.CurrentTabIndex) {
            $this._InvokeCallback($this.OnTabChanged, $this.CurrentTabIndex)
        }
    }

    [void] SelectTab([int]$index) {
        if ($index -ge 0 -and $index -lt $this.Tabs.Count) {
            $oldIndex = $this.CurrentTabIndex
            $this.CurrentTabIndex = $index
            $this.SelectedFieldIndex = 0

            if ($oldIndex -ne $this.CurrentTabIndex) {
                $this._InvokeCallback($this.OnTabChanged, $this.CurrentTabIndex)
            }
        }
    }

    [void] NextField() {
        $tab = $this.GetCurrentTab()
        if ($null -eq $tab -or $tab.Fields.Count -eq 0) { return }

        $this.SelectedFieldIndex++
        if ($this.SelectedFieldIndex -ge $tab.Fields.Count) {
            $this.SelectedFieldIndex = $tab.Fields.Count - 1
        }

        # Auto-scroll if needed
        $this._EnsureFieldVisible()

        $field = $this.GetCurrentField()
        if ($field) {
            $this._InvokeCallback($this.OnFieldSelected, $field)
        }
    }

    [void] PrevField() {
        $tab = $this.GetCurrentTab()
        if ($null -eq $tab -or $tab.Fields.Count -eq 0) { return }

        $this.SelectedFieldIndex--
        if ($this.SelectedFieldIndex -lt 0) {
            $this.SelectedFieldIndex = 0
        }

        # Auto-scroll if needed
        $this._EnsureFieldVisible()

        $field = $this.GetCurrentField()
        if ($field) {
            $this._InvokeCallback($this.OnFieldSelected, $field)
        }
    }

    hidden [void] _EnsureFieldVisible() {
        $tab = $this.GetCurrentTab()
        if ($null -eq $tab) { return }

        $visibleRows = $this.Height - $this.TabBarHeight - 4  # Tab bar + padding

        # If selected field is above visible area
        if ($this.SelectedFieldIndex -lt $tab.ScrollOffset) {
            $tab.ScrollOffset = $this.SelectedFieldIndex
        }

        # If selected field is below visible area
        if ($this.SelectedFieldIndex -ge ($tab.ScrollOffset + $visibleRows)) {
            $tab.ScrollOffset = $this.SelectedFieldIndex - $visibleRows + 1
        }
    }

    # === Input Handling ===

    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        if ($keyInfo.Key -eq 'Tab') {
            if ($keyInfo.Modifiers -band [ConsoleModifiers]::Shift) {
                $this.PrevTab()
            }
            else {
                $this.NextTab()
            }
            return $true
        }

        # Left/Right arrows cycle through tabs
        if ($keyInfo.Key -eq 'LeftArrow') {
            $this.PrevTab()
            return $true
        }

        if ($keyInfo.Key -eq 'RightArrow') {
            $this.NextTab()
            return $true
        }

        if ($keyInfo.Key -eq 'UpArrow') {
            $this.PrevField()
            return $true
        }

        if ($keyInfo.Key -eq 'DownArrow') {
            $this.NextField()
            return $true
        }

        if ($keyInfo.Key -eq 'PageDown') {
            # Jump 10 fields down
            for ($i = 0; $i -lt 10; $i++) {
                $this.NextField()
            }
            return $true
        }

        if ($keyInfo.Key -eq 'PageUp') {
            # Jump 10 fields up
            for ($i = 0; $i -lt 10; $i++) {
                $this.PrevField()
            }
            return $true
        }

        if ($keyInfo.Key -eq 'Home') {
            $this.SelectedFieldIndex = 0
            $tab = $this.GetCurrentTab()
            if ($tab) {
                $tab.ScrollOffset = 0
            }
            return $true
        }

        if ($keyInfo.Key -eq 'End') {
            $tab = $this.GetCurrentTab()
            if ($tab -and $tab.Fields.Count -gt 0) {
                $this.SelectedFieldIndex = $tab.Fields.Count - 1
                $this._EnsureFieldVisible()
            }
            return $true
        }

        # Number keys 1-9 to jump to tabs
        if ($this.ShowTabNumbers -and $keyInfo.KeyChar -match '[1-9]') {
            $tabNum = [int]$keyInfo.KeyChar - [int][char]'1'  # 0-based index
            $this.SelectTab($tabNum)
            return $true
        }

        return $false
    }

    # === Layout System ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)

        $engine.DefineRegion("$($this.RegionID)_Tabs", $this.X, $this.Y, $this.Width, 1)
        $engine.DefineRegion("$($this.RegionID)_Separator", $this.X, $this.Y + 1, $this.Width, 1)

        $contentHeight = $this.Height - 2
        $engine.DefineRegion("$($this.RegionID)_Content", $this.X, $this.Y + 2, $this.Width, $contentHeight)
    }


    # === Rendering ===

    [void] RenderToEngine([object]$engine) {
        $this.RegisterLayout($engine)

        # Use Z-layer 10 for tabs to ensure they render above other content
        if ($engine.PSObject.Methods['BeginLayer']) {
            $engine.BeginLayer(10)
        }

        if ($this.Tabs.Count -eq 0) {
            # Render empty state
            $fgSec = $this.GetThemedInt("Foreground.Secondary"); $engine.WriteAt($this.X, $this.Y, "No tabs defined", $fgSec, -1)
            if ($engine.PSObject.Methods['EndLayer']) {
                $engine.EndLayer()
            }
            return
        }

        # 1. Render Tab Bar
        $currentX = $this.X
        for ($i = 0; $i -lt $this.Tabs.Count; $i++) {
            $tab = $this.Tabs[$i]
            $isCurrent = ($i -eq $this.CurrentTabIndex)
            
            $label = $tab.Name
            if ($this.ShowTabNumbers) {
                $label = "[$($i+1)] $label"
            }
            
            # Add padding
            $label = " $label "
            
            if ($isCurrent) {
                # Active Tab
                $bg = $this.GetThemedInt("Background.Accent")
                $fg = $this.GetThemedInt("Foreground.Primary")
                $engine.WriteAt($currentX, $this.Y, $label, $fg, $bg)
            } else {
                # Inactive Tab
                $bg = $this.GetThemedInt("Background.Panel")
                $fg = $this.GetThemedInt("Foreground.Secondary")
                $engine.WriteAt($currentX, $this.Y, $label, $fg, $bg)
            }
            
            $currentX += $label.Length + 1
        }

        # 2. Render Separator
        $sepColor = $this.GetThemedInt("Foreground.Border")
        $line = [string]::new([char]0x2500, $this.Width); $engine.WriteAt($this.X, $this.Y + 1, $line, $sepColor, -1)

        # 3. Render Content (Fields)
        $tab = $this.GetCurrentTab()
        if ($tab) {
            $startY = $this.Y + 2
            $fields = $tab.Fields
            
            # Handle scrolling
            if (-not $tab.ContainsKey('ScrollOffset')) { $tab.ScrollOffset = 0 }
            
            $visibleRows = $this.Height - 2 - 1 # Height - TabBar - Separator
            
            for ($i = 0; $i -lt $visibleRows; $i++) {
                $fieldIndex = $tab.ScrollOffset + $i
                if ($fieldIndex -ge $fields.Count) { break }
                
                $field = $fields[$fieldIndex]
                $isSelected = ($fieldIndex -eq $this.SelectedFieldIndex)
                $rowY = $startY + $i
                
                # Render Label
                if ($isSelected) {
                    $labelBg = $this.GetThemedInt("Background.Selection"); $labelFg = $this.GetThemedInt("Foreground.Selection")
                } else {
                    $labelBg = $this.GetThemedInt("Background.Primary"); $labelFg = $this.GetThemedInt("Foreground.Secondary")
                }
                $engine.WriteAt($this.X + 2, $rowY, $field.Label.PadRight($this.LabelWidth), $labelFg, $labelBg)
                
                # Render Value
                $valueX = $this.X + 2 + $this.LabelWidth + 1
                $valueWidth = $this.Width - ($valueX - $this.X) - 2
                $displayValue = if ($field.Value) { $field.Value.ToString() } else { "" }
                
                if ($displayValue.Length -gt $valueWidth) {
                    $displayValue = $displayValue.Substring(0, $valueWidth - 3) + "..."
                }
                
                if ($isSelected) {
                    $bg = $this.GetThemedInt("Background.Selection")
                    $fg = $this.GetThemedInt("Foreground.Selection")
                    $engine.WriteAt($valueX, $rowY, $displayValue.PadRight($valueWidth), $fg, $bg)
                } else {
                    $fg = $this.GetThemedInt("Foreground.Primary")
                    $engine.WriteAt($valueX, $rowY, $displayValue, $fg, -1)
                }
            }
            
            # Scroll indicators if needed
            if ($tab.ScrollOffset -gt 0) {
                $fgAcc = $this.GetThemedInt("Foreground.Accent"); $engine.WriteAt($this.X + $this.Width - 1, $startY, "^", $fgAcc, -1)
            }
            if (($tab.ScrollOffset + $visibleRows) -lt $fields.Count) {
                $fgAcc2 = $this.GetThemedInt("Foreground.Accent"); $engine.WriteAt($this.X + $this.Width - 1, $startY + $visibleRows - 1, "v", $fgAcc2, -1)
            }
        }

        if ($engine.PSObject.Methods['EndLayer']) {
            $engine.EndLayer()
        }
    }

    # === Helper Methods ===

    hidden [void] _InvokeCallback([scriptblock]$callback, $arg) {
        if ($null -ne $callback -and $callback -ne {}) {
            try {
                if ($null -ne $arg) {
                    & $callback $arg
                }
                else {
                    & $callback
                }
            }
            catch {
                # Silently ignore callback errors
            }
        }
    }

    <#
    .SYNOPSIS
    Update a field value
    #>
    [void] UpdateFieldValue([string]$fieldName, $newValue) {
        $tab = $this.GetCurrentTab()
        if ($null -eq $tab) { return }

        foreach ($field in $tab.Fields) {
            if ($field.Name -eq $fieldName) {
                $oldValue = $field.Value
                $field.Value = $newValue
                $this._InvokeCallback($this.OnFieldEdit, @($field, $newValue))
                break
            }
        }
    }

    <#
    .SYNOPSIS
    Get all field values from all tabs as hashtable
    #>
    [hashtable] GetAllValues() {
        $values = @{}

        foreach ($tab in $this.Tabs) {
            foreach ($field in $tab.Fields) {
                $values[$field.Name] = $field.Value
            }
        }

        return $values
    }
}

# Export
Export-ModuleMember -Variable @()