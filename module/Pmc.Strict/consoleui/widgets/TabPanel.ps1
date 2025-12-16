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

        Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TabPanel.RenderToEngine] START: X=$($this.X) Y=$($this.Y) Width=$($this.Width) Height=$($this.Height) TabCount=$($this.Tabs.Count) CurrentTab=$($this.CurrentTabIndex)"

        # Use Z-layer 10 for tabs to ensure they render above other content
        if ($engine.PSObject.Methods['BeginLayer']) {
            Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TabPanel] BeginLayer(10)"
            $engine.BeginLayer(10)
        }

        if ($this.Tabs.Count -eq 0) {
            Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TabPanel] No tabs, rendering empty"
            $this._RenderEmptyToEngine($engine)
            if ($engine.PSObject.Methods['EndLayer']) {
                $engine.EndLayer()
            }
            return
        }

        # Colors from theme
        $tabActiveBg = $this.GetThemedColorInt('Background.TabActive')
        $tabActiveText = $this.GetThemedColorInt('Foreground.TabActive')
        $tabInactiveBg = $this.GetThemedColorInt('Background.TabInactive')
        $tabInactiveText = $this.GetThemedColorInt('Foreground.TabInactive')
        $borderColor = $this.GetThemedColorInt('Border.Widget')
        $labelColor = $this.GetThemedColorInt('Foreground.Muted')
        $valueColor = $this.GetThemedColorInt('Foreground.Field')
        $selectBg = $this.GetThemedColorInt('Background.RowSelected')
        $selectText = $this.GetThemedColorInt('Foreground.RowSelected')
        $bg = $this.GetThemedColorInt('Background.Primary') # Default background

        # 1. Render Tab Bar (Top Row)
        $currentX = $this.X
        Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TabPanel] Rendering tab bar at Y=$($this.Y) with $($this.Tabs.Count) tabs"
        
        for ($i = 0; $i -lt $this.Tabs.Count; $i++) {
            $tab = $this.Tabs[$i]
            $isActive = ($i -eq $this.CurrentTabIndex)

            # Tab label with optional number
            $label = $(if ($this.ShowTabNumbers) { "[$($i+1)] $($tab.Name)" } else { $tab.Name })
            $tabWidth = $label.Length + 4  # Padding

            $drawBg = $(if ($isActive) { $tabActiveBg } else { $tabInactiveBg })
            $drawFg = $(if ($isActive) { $tabActiveText } else { $tabInactiveText })

            Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TabPanel] Tab $i: label='$label' at X=$currentX Y=$($this.Y) active=$isActive"
            $engine.WriteAt($currentX, $this.Y, " $label ", $drawFg, $drawBg)
            $currentX += $tabWidth
        }

        # Fill rest of tab bar line
        $remaining = $this.Width - ($currentX - $this.X)
        if ($remaining -gt 0) {
            Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TabPanel] Filling rest: X=$currentX Y=$($this.Y) width=$remaining"
            $engine.Fill($currentX, $this.Y, $remaining, 1, ' ', $tabInactiveText, $tabInactiveBg)
        }
        Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [TabPanel] Tab bar complete"

        # 2. Separator Line
        $separatorY = $this.Y + 1
        $engine.Fill($this.X, $separatorY, $this.Width, 1, '─', $borderColor, $bg)


        # 3. Render Content Area
        $tab = $this.GetCurrentTab()
        if ($null -eq $tab) { return }

        $contentY = $this.Y + $this.TabBarHeight
        $visibleRows = $this.Height - $this.TabBarHeight - 2
        
        # Calculate indices
        $startIndex = $tab.ScrollOffset
        $endIndex = [Math]::Min($startIndex + $visibleRows, $tab.Fields.Count)
        
        $row = 0
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $field = $tab.Fields[$i]
            $isSelected = ($i -eq $this.SelectedFieldIndex)

            $y = $contentY + $row + 1 # +1 for padding? Match legacy logic
            # Legacy used $contentY + $row + 1. TabBarHeight is 2. So Y is Y+2. content start is Y+3.
            # Let's trust legacy logic: $y = $contentY + $row + 1

            $x = $this.X + $this.ContentPadding

            $drawBg = $(if ($isSelected) { $selectBg } else { $bg })
            $drawFg = $(if ($isSelected) { $selectText } else { $valueColor })
            $lblColor = $(if ($isSelected) { $selectText } else { $labelColor })

            # Render Label
            $label = $field.Label
            if ($label.Length -gt $this.LabelWidth - 2) {
                $label = $label.Substring(0, $this.LabelWidth - 5) + "..."
            }
            $engine.WriteAt($x, $y, $label.PadRight($this.LabelWidth), $lblColor, $drawBg)

            # Render Value
            $maxValueWidth = $this.Width - $this.LabelWidth - ($this.ContentPadding * 2)
            $value = $(if ($null -ne $field.Value) { [string]$field.Value } else { "(empty)" })
            if ($value.Length -gt $maxValueWidth) {
                $value = $value.Substring(0, $maxValueWidth - 3) + "..."
            }

            $valX = $x + $this.LabelWidth
            Add-Content -Path "/tmp/pmc-tabpanel-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] FIELD: tab=$($tab.Name) index=$i label=$($field.Label) rawValue='$($field.Value)' displayValue='$value' x=$x y=$y valX=$valX maxValueWidth=$maxValueWidth"
            $engine.WriteAt($valX, $y, $value.PadRight($maxValueWidth), $drawFg, $drawBg)

            $row++
        }

        # Clear remaining
        for ($i = $row; $i -lt $visibleRows; $i++) {
            $y = $contentY + $i + 1
            $engine.Fill($this.X, $y, $this.Width, 1, ' ', $valueColor, $bg)
        }

        # Scroll Indicators
        if ($tab.ScrollOffset -gt 0) {
            $engine.WriteAt($this.X + $this.Width - 3, $contentY + 1, "↑", $borderColor, $bg)
        }
        if ($endIndex -lt $tab.Fields.Count) {
            # Legacy used $this.Y + $this.Height - 2
            $engine.WriteAt($this.X + $this.Width - 3, $this.Y + $this.Height - 2, "↓", $borderColor, $bg)
        }

        # End Z-layer
        if ($engine.PSObject.Methods['EndLayer']) {
            $engine.EndLayer()
        }
    }

    hidden [void] _RenderEmptyToEngine([object]$engine) {
        $msg = "No tabs configured"
        $x = $this.X + [Math]::Floor(($this.Width - $msg.Length) / 2)
        $y = $this.Y + [Math]::Floor($this.Height / 2)
        
        $mutedColor = $this.GetThemedColorInt('Foreground.Muted')
        $bg = $this.GetThemedColorInt('Background.Primary')
        
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $mutedColor, $bg)
        $engine.WriteAt($x, $y, $msg, $mutedColor, $bg)
    }

    [string] Render() { return "" }

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