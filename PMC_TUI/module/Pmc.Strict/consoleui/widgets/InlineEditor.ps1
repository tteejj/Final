using namespace System
using namespace System.Collections.Generic
using namespace System.Text

# InlineEditor.ps1 - Multi-field composer widget for inline editing
# THE KEY WIDGET - Composes multiple input types into a single editor
#
# Usage:
#   $fields = @(
#       @{ Name='text'; Label='Task'; Type='text'; Value='Buy milk'; Required=$true }
#       @{ Name='due'; Label='Due Date'; Type='date'; Value=[DateTime]::Today }
#       @{ Name='project'; Label='Project'; Type='project'; Value='personal' }
#       @{ Name='priority'; Label='Priority'; Type='number'; Value=3; Min=0; Max=5 }
#       @{ Name='tags'; Label='Tags'; Type='tags'; Value=@('urgent') }
#   )
#
#   $editor = [InlineEditor]::new()
#   $editor.SetFields($fields)
#   $editor.SetPosition(5, 5)
#   $editor.OnConfirmed = { param($values) Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [InlineEditor] Saved: $($values | ConvertTo-Json)" }
#
#   # Render loop
#   while (-not $editor.IsConfirmed -and -not $editor.IsCancelled) {
#       $ansiOutput = $editor.Render()
#       Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [InlineEditor] Rendering editor"
#       $key = [Console]::ReadKey($true)
#       $editor.HandleInput($key)
#   }

Set-StrictMode -Version Latest

# Load PmcWidget base class and field widgets
if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

# Load field widgets
. "$PSScriptRoot/TextInput.ps1"
. "$PSScriptRoot/DatePicker.ps1"
. "$PSScriptRoot/ProjectPicker.ps1"
. "$PSScriptRoot/TagEditor.ps1"

<#
.SYNOPSIS
Multi-field inline editor that composes existing widgets into a unified editor

.DESCRIPTION
Features:
- Compose multiple field types: text, date, project, number, tags
- Tab/Shift+Tab to cycle between fields
- Enter to confirm all changes (validates all fields)
- Esc to cancel
- Visual field list with labels
- Field validation with error display
- OnFieldChanged event for each field change
- OnConfirmed event with all field values
- Smart layout - fields stack vertically
- Focus indicators for active field
- Required field validation

Field Types:
- text: Single-line text input (uses TextInput widget)
- date: Date picker (uses DatePicker widget)
- project: Project picker (uses ProjectPicker widget)
- tags: Tag editor (uses TagEditor widget)
- number: Number input with visual slider (custom inline widget)

.EXAMPLE
$fields = @(
    @{ Name='text'; Label='Task'; Type='text'; Value='Buy milk'; Required=$true }
    @{ Name='due'; Label='Due Date'; Type='date'; Value=[DateTime]::Today }
    @{ Name='project'; Label='Project'; Type='project'; Value='personal' }
    @{ Name='priority'; Label='Priority'; Type='number'; Value=3; Min=0; Max=5 }
    @{ Name='tags'; Label='Tags'; Type='tags'; Value=@('urgent') }
)
$editor = [InlineEditor]::new()
$editor.SetFields($fields)
$values = $editor.GetValues()
#>
class InlineEditor : PmcWidget {
    # === Public Properties ===
    [string]$Title = "Edit"                    # Editor title
    [string]$LayoutMode = "vertical"           # "vertical" (default) or "horizontal" (compact inline mode)

    # === Event Callbacks ===
    [scriptblock]$OnFieldChanged = {}          # Called when field changes: param($fieldName, $value)
    [scriptblock]$OnConfirmed = {}             # Called when Enter pressed: param($allValues)
    [scriptblock]$OnCancelled = {}             # Called when Esc pressed
    [scriptblock]$OnValidationFailed = {}      # Called when validation fails: param($errors)

    # === State Flags ===
    [bool]$IsConfirmed = $false                # True when Enter pressed and validated
    [bool]$IsCancelled = $false                # True when Esc pressed
    [bool]$NeedsClear = $false                 # True when field widget was closed and screen needs clear
    [string]$TargetRegionID = ""               # Engine Layout Region to target (if any)

    # === Private State ===
    hidden [List[hashtable]]$_fields = [List[hashtable]]::new()      # Field definition
    hidden [hashtable]$_fieldWidgets = @{}                           # Widget instances keyed by field name
    hidden [hashtable]$_datePickerWidgets = @{}                      # DatePicker instances for date fields (kept separate from TextInput)
    hidden [int]$_currentFieldIndex = 0                              # Currently focused field
    hidden [string[]]$_validationErrors = @()                        # Current validation errors
    hidden [hashtable]$_fieldErrors = @{}                            # H-UI-3: Per-field validation errors for real-time display
    hidden [bool]$_showFieldWidgets = $false                         # Whether to show expanded field widget
    hidden [string]$_expandedFieldName = ""                          # Name of currently expanded field
    hidden [bool]$_datePickerMode = $false                           # True when DatePicker is active (not TextInput)

    # Validation debouncing
    hidden [DateTime]$_lastKeystroke = [DateTime]::MinValue
    hidden [int]$_validationDelayMs = 300                            # Wait 300ms after last keystroke before validating
    hidden [string]$_pendingValidationField = ""                     # Field pending validation

    # === Constructor ===
    InlineEditor() : base("InlineEditor") {
        $this.Width = 70
        $this.Height = 25
        $this.CanFocus = $true
    }

    # === Layout System ===

    [void] Resize([int]$width, [int]$height) {
        $this.Width = $width
        $this.Height = $height
        # Re-calculate layout if needed
    }

    # === Public API Methods ===

    <#
    .SYNOPSIS
    Configure the fields for this editor

    .PARAMETER fields
    Array of hashtables with field definitions:
    - Name: Field identifier (required)
    - Label: Display label (required)
    - Type: Field type: text, date, project, number, tags (required)
    - Value: Initial value (optional)
    - Required: Whether field is required (optional, default $false)
    - Min/Max: For number type (optional)
    - MaxLength: For text type (optional)
    - Placeholder: For text type (optional)
    #>
    [void] SetFields([hashtable[]]$fields) {
        # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.SetFields] START with $($fields.Count) fields, LayoutMode=$($this.LayoutMode) X=$($this.X) Y=$($this.Y) Width=$($this.Width) Height=$($this.Height) Visible=$($this.Visible)"
        $this._fields.Clear()
        # Note: Old widget references cleared from dictionaries
        # PowerShell GC will clean up. Widgets don't register external event handlers.
        $this._fieldWidgets.Clear()
        $this._datePickerWidgets.Clear()
        $this._currentFieldIndex = 0
        # Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.SetFields] Cleared existing fields/widgets"
        $this._validationErrors = @()
        $this._datePickerMode = $false

        # Reset state flags
        $this.IsConfirmed = $false
        $this.IsCancelled = $false

        if ($null -eq $fields -or $fields.Count -eq 0) {
            return
        }

        foreach ($fieldDef in $fields) {
            # Validate field definition
            if (-not $fieldDef.ContainsKey('Name')) {
                throw "Field definition missing 'Name' property"
            }
            if (-not $fieldDef.ContainsKey('Label')) {
                throw "Field definition missing 'Label' property"
            }
            if (-not $fieldDef.ContainsKey('Type')) {
                throw "Field definition missing 'Type' property"
            }

            # Add to fields list
            $this._fields.Add($fieldDef)
            # Write-PmcTuiLog "InlineEditor.SetFields: Added field '$($fieldDef.Name)' type=$($fieldDef.Type)" "DEBUG"

            # Create widget instance for this field
            try {
                $this._CreateFieldWidget($fieldDef)
                # Write-PmcTuiLog "InlineEditor.SetFields: Created widget for field '$($fieldDef.Name)'" "DEBUG"
            }
            catch {
                # Write-PmcTuiLog "InlineEditor.SetFields: ERROR creating widget for field '$($fieldDef.Name)': $_" "ERROR"
                throw
            }
        }

        # Add Save button as last field ONLY in vertical mode
        # In horizontal mode, Enter key saves directly, no button needed
        if ($this.LayoutMode -eq 'vertical') {
            $saveButton = @{
                Name       = '__save_button__'
                Label      = ''
                Type       = 'button'
                ButtonText = 'Save'
            }
            $this._fields.Add($saveButton)
        }

        # Calculate required height based on field count
        $this.Height = 6 + ($this._fields.Count * 3) + 3  # Header + fields + footer + padding
    }

    <#
    .SYNOPSIS
    Get all field values as hashtable

    .OUTPUTS
    Hashtable with field names as keys and current values as values
    #>
    [hashtable] GetValues() {
        # Write-PmcTuiLog "GetValues: Starting, _fields count=$($this._fields.Count)" "DEBUG"
        $values = @{}

        foreach ($field in $this._fields) {
            $fieldName = $field.Name
            $fieldType = $field.Type

            # Write-PmcTuiLog "GetValues: Processing field=$fieldName type=$fieldType" "DEBUG"

            # Skip button fields
            if ($fieldType -eq 'button') {
                continue
            }

            $value = $this._GetFieldValue($fieldName, $fieldType)
            # Write-PmcTuiLog "GetValues: Field $fieldName value=$value" "DEBUG"
            $values[$fieldName] = $value
        }

        # Write-PmcTuiLog "GetValues: Returning hashtable with $($values.Keys.Count) keys: $($values.Keys -join ', ')" "DEBUG"
        return $values
    }

    <#
    .SYNOPSIS
    Get value of a specific field

    .PARAMETER name
    Field name

    .OUTPUTS
    Field value or $null if field not found
    #>
    [object] GetField([string]$name) {
        $field = $this._fields | Where-Object { $_.Name -eq $name } | Select-Object -First 1

        if ($null -eq $field) {
            return $null
        }

        return $this._GetFieldValue($name, $field.Type)
    }

    <#
    .SYNOPSIS
    Set focus to a specific field by index

    .PARAMETER fieldIndex
    Zero-based field index
    #>
    [void] SetFocus([int]$fieldIndex) {
        if ($fieldIndex -ge 0 -and $fieldIndex -lt $this._fields.Count) {
            $this._currentFieldIndex = $fieldIndex
            $this._showFieldWidgets = $false
            $this._expandedFieldName = ""
            $this._datePickerMode = $false
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
        # Write-PmcTuiLog "InlineEditor.HandleInput: Key=$($keyInfo.Key) Expanded=$($this._expandedFieldName)" "DEBUG"
        Write-PmcTuiLog "InlineEditor.HandleInput: ENTRY - Key=$($keyInfo.Key)" "DEBUG"
        Write-PmcTuiLog "InlineEditor.HandleInput: ENTRY Key=$($keyInfo.Key)" "INFO"
        # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] START Key=$($keyInfo.Key) Expanded=$($this._expandedFieldName) ShowFieldWidgets=$($this._showFieldWidgets) CurrentFieldIndex=$($this._currentFieldIndex) FieldsCount=$($this._fields.Count) LayoutMode=$($this.LayoutMode)"

        # If a field widget is expanded, route input to it
        if ($this._showFieldWidgets -and -not [string]::IsNullOrWhiteSpace($this._expandedFieldName)) {
            # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] Widget is expanded, routing input to field widget"
            # Safety: Allow Escape to force-close expanded widget even if widget doesn't handle it
            if ($keyInfo.Key -eq 'Escape') {
                # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] ESC pressed on expanded widget, collapsing"
                $this._showFieldWidgets = $false
                $this._expandedFieldName = ""
                $this._datePickerMode = $false
                return $true
            }

            # Get the appropriate widget based on mode
            $widget = $null
            $field = $this._fields | Where-Object { $_.Name -eq $this._expandedFieldName } | Select-Object -First 1

            # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] Field type: $($field.Type) Mode: $($this._datePickerMode)"
            if ($field.Type -eq 'date' -and $this._datePickerMode) {
                # Use DatePicker when in DatePicker mode
                $widget = $this._datePickerWidgets[$this._expandedFieldName]
            }
            else {
                # Use normal widget
                $widget = $this._fieldWidgets[$this._expandedFieldName]
            }

            # Check for widget-specific completion
            # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] Calling widget.HandleInput() for field $($this._expandedFieldName)"
            $handled = $widget.HandleInput($keyInfo)
            # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] widget.HandleInput() returned: $handled"

            # Check if widget confirmed or cancelled
            # PmcFilePicker uses IsComplete instead of IsConfirmed/IsCancelled
            $isComplete = $false
            if ($widget.PSObject.Properties['IsComplete']) {
                $isComplete = $widget.IsComplete
                # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] Widget has IsComplete property: $isComplete"
            }
            elseif ($widget.PSObject.Properties['IsConfirmed']) {
                $isComplete = $widget.IsConfirmed -or $widget.IsCancelled
                # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] Widget has IsConfirmed property: IsConfirmed=$($widget.IsConfirmed) IsCancelled=$($widget.IsCancelled) isComplete=$isComplete"
            }

            if ($isComplete) {
                # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] Widget marked complete, collapsing"
                # For date fields in DatePicker mode, update TextInput with selected date
                if ($field.Type -eq 'date' -and $this._datePickerMode) {
                    # Get selected date from DatePicker
                    $selectedDate = $(if ($widget.IsConfirmed) { $widget.GetSelectedDate() } else { $null })

                    if ($selectedDate) {
                        # Update the TextInput widget (which is still stored in _fieldWidgets)
                        $textWidget = $this._fieldWidgets[$this._expandedFieldName]
                        $textWidget.SetText($selectedDate.ToString('yyyy-MM-dd'))
                        # Update field value
                        $field.Value = $selectedDate
                    }
                }

                # For folder fields, update TextInput with selected path
                if ($field.Type -eq 'folder' -and $widget.PSObject.Properties['IsComplete'] -and $widget.IsComplete) {
                    # Write-PmcTuiLog "InlineEditor: Folder picker complete - Result=$($widget.Result) SelectedPath='$($widget.SelectedPath)'" "DEBUG"
                    # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] Folder picker complete"

                    # Get selected path from FilePicker
                    $selectedPath = $(if ($widget.Result) { $widget.SelectedPath } else { '' })

                    # Write-PmcTuiLog "InlineEditor: Setting folder field value to '$selectedPath'" "DEBUG"

                    # Recreate TextInput and restore it
                    $textWidget = [TextInput]::new()
                    $textWidget.MaxLength = 255
                    $textWidget.Placeholder = 'Press Enter to browse...'
                    $textWidget.SetText($selectedPath)

                    # Restore TextInput in place of FilePicker
                    $this._fieldWidgets[$this._expandedFieldName] = $textWidget

                    # Update field value
                    $field.Value = $selectedPath

                    # Write-PmcTuiLog "InlineEditor: Folder field updated - field.Value='$($field.Value)'" "DEBUG"
                }

                # Collapse widget
                # Add-Content -Path "$($env:TEMP)\pmc-widget-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') [InlineEditor.HandleInput] Collapsing widget, setting _showFieldWidgets=false and NeedsClear=true"
                $this._showFieldWidgets = $false
                $this._datePickerMode = $false
                # DO NOT set NeedsClear - widget will be hidden naturally on next render

                # Get value from widget and update field BEFORE collapsing
                # Only for widgets that have IsConfirmed property (not PmcFilePicker which uses Result)
                if ($widget.PSObject.Properties['IsConfirmed'] -and $widget.IsConfirmed) {
                    # For tags, get tags directly from TagEditor
                    if ($field.Type -eq 'tags') {
                        $field.Value = $widget.GetTags()
                    }
                    # For project, get selected project and update field value
                    elseif ($field.Type -eq 'project') {
                        $selectedProject = $widget.GetSelectedProject()
                        $field.Value = $selectedProject

                        # CRITICAL: Restore the original TextInput widget with selected value
                        # In horizontal mode, project field uses TextInput (which was temporarily replaced by ProjectPicker)
                        $textWidget = [TextInput]::new()
                        $textWidget.MaxLength = 100
                        $textWidget.Placeholder = 'Project name'
                        $textWidget.SetText([string]$selectedProject)
                        $this._fieldWidgets[$this._expandedFieldName] = $textWidget
                    }

                    $this._InvokeCallback($this.OnFieldChanged, @($this._expandedFieldName, $field.Value))
                }

                # For PmcFilePicker, trigger callback if Result is true
                if ($field.Type -eq 'folder' -and $widget.PSObject.Properties['Result'] -and $widget.Result) {
                    $this._InvokeCallback($this.OnFieldChanged, @($this._expandedFieldName, $field.Value))
                }

                $this._expandedFieldName = ""
                return $true
            }

            return $handled
        }

        # Enter key behavior depends on current field
        if ($keyInfo.Key -eq 'Enter') {
            Write-PmcTuiLog "InlineEditor.HandleInput: Enter key at line 416, _currentFieldIndex=$($this._currentFieldIndex)" "DEBUG"
            # Write-PmcTuiLog "InlineEditor.HandleKeyPress: Enter key pressed - currentFieldIndex=$($this._currentFieldIndex)" "DEBUG"
            # Check current field type
            if ($this._currentFieldIndex -ge 0 -and $this._currentFieldIndex -lt $this._fields.Count) {
                $currentField = $this._fields[$this._currentFieldIndex]
                # Write-PmcTuiLog "InlineEditor.HandleKeyPress: Current field type: $($currentField.Type)" "DEBUG"

                # For Button type - validate and save
                if ($currentField.Type -eq 'button') {
                    if ($this._ValidateAllFields()) {
                        # Write-PmcTuiLog "InlineEditor: Save button pressed - Saving form" "DEBUG"
                        $this.IsConfirmed = $true
                        $values = $this.GetValues()
                        $this._InvokeCallback($this.OnConfirmed, $values)
                        return $true
                    }
                    else {
                        # Write-PmcTuiLog "InlineEditor: Validation FAILED - Errors: $($this._validationErrors -join ', ')" "ERROR"
                        $this._InvokeCallback($this.OnValidationFailed, $this._validationErrors)
                        return $true
                    }
                }

                # For Date/Project/Folder fields - Enter expands the widget
                if ($currentField.Type -eq 'date' -or $currentField.Type -eq 'project' -or $currentField.Type -eq 'folder') {
                    # Write-PmcTuiLog "InlineEditor: Enter on $($currentField.Type) field - expanding widget" "DEBUG"
                    $this._ExpandCurrentField()
                    return $true
                }

                # For all fields (in horizontal mode) or other field types - Enter ALWAYS validates and saves
                if ($this._ValidateAllFields()) {
                    # Write-PmcTuiLog "InlineEditor: Validation passed, confirming" "DEBUG"
                    $this.IsConfirmed = $true
                    $values = $this.GetValues()
                    $this._InvokeCallback($this.OnConfirmed, $values)
                    Write-PmcTuiLog "InlineEditor.HandleInput: Validation passed, calling OnConfirmed" "INFO"
                    return $true
                }
                else {
                    # Validation failed - show errors and stay open
                    # Write-PmcTuiLog "InlineEditor: Validation FAILED - Errors: $($this._validationErrors -join ', ')" "ERROR"
                    $this._InvokeCallback($this.OnValidationFailed, $this._validationErrors)
                    return $true
                }
            }

            # No field selected - validate and confirm
            if ($this._ValidateAllFields()) {
                $this.IsConfirmed = $true
                $values = $this.GetValues()
                $this._InvokeCallback($this.OnConfirmed, $values)
                return $true
            }
            return $true
        }

        if ($keyInfo.Key -eq 'Escape') {
            $this.IsCancelled = $true
            $this.NeedsClear = $true  # Request full screen clear to remove partial entry
            $this._InvokeCallback($this.OnCancelled, $null)
            return $true
        }

        # Tab - navigate between fields
        if ($keyInfo.Key -eq 'Tab') {
            if ($keyInfo.Modifiers -band [ConsoleModifiers]::Shift) {
                # Shift+Tab - navigate to previous field
                $this._MoveToPreviousField()
            }
            else {
                # Tab - navigate to next field (in horizontal mode, Tab ALWAYS navigates, never expands)
                # In vertical mode, Tab could expand widgets, but in horizontal mode we keep it simple
                $this._MoveToNextField()
            }
            return $true
        }

        # Up/Down arrows - navigate fields
        if ($keyInfo.Key -eq 'UpArrow') {
            $this._MoveToPreviousField()
            return $true
        }

        if ($keyInfo.Key -eq 'DownArrow') {
            $this._MoveToNextField()
            return $true
        }

        # Left/Right arrows - adjust number fields inline
        if ($this._currentFieldIndex -ge 0 -and $this._currentFieldIndex -lt $this._fields.Count) {
            $currentField = $this._fields[$this._currentFieldIndex]

            if ($currentField.Type -eq 'number') {
                $min = $(if ($currentField.ContainsKey('Min')) { $currentField.Min } else { 0 })
                $max = $(if ($currentField.ContainsKey('Max')) { $currentField.Max } else { 10 })
                $step = $(if ($currentField.ContainsKey('Step')) { $currentField.Step } else { 1 })
                $currentValue = $this._GetFieldValue($currentField.Name, 'number')
                if ($null -eq $currentValue) { $currentValue = $min }

                if ($keyInfo.Key -eq 'LeftArrow' -and $currentValue -gt $min) {
                    $this._SetFieldValue($currentField.Name, $currentValue - $step)
                    return $true
                }

                if ($keyInfo.Key -eq 'RightArrow' -and $currentValue -lt $max) {
                    $this._SetFieldValue($currentField.Name, $currentValue + $step)
                    return $true
                }
            }
        }

        # F2 - expand current field widget (DatePicker, ProjectPicker, etc.)
        # Note: Spacebar is handled below for non-text fields to allow typing spaces
        if ($keyInfo.Key -eq 'F2') {
            $this._ExpandCurrentField()
            return $true
        }

        # For all fields with widgets, allow direct typing (inline editing)
        if ($this._currentFieldIndex -ge 0 -and $this._currentFieldIndex -lt $this._fields.Count) {
            $currentField = $this._fields[$this._currentFieldIndex]
            # Write-PmcTuiLog "InlineEditor.HandleInput: Current field index=$($this._currentFieldIndex) name=$($currentField.Name) type=$($currentField.Type)" "DEBUG"

            # Text, Textarea, Date, Tags, Project AND Number fields - pass input to widget
            if ($currentField.Type -eq 'text' -or $currentField.Type -eq 'textarea' -or $currentField.Type -eq 'date' -or $currentField.Type -eq 'tags' -or $currentField.Type -eq 'project' -or $currentField.Type -eq 'number') {
                # Don't pass navigation keys to widget - let InlineEditor handle them
                # NOTE: Enter is NOT in this list - it's already handled above at line 383
                if ($keyInfo.Key -eq 'Tab' -or $keyInfo.Key -eq 'UpArrow' -or $keyInfo.Key -eq 'DownArrow') {
                    return $false  # Let InlineEditor handle navigation
                }

                # Clear validation errors when user starts editing a field
                # This prevents stale error messages from appearing while the user is actively typing
                # Skip for navigation and submission keys
                if ($keyInfo.Key -ne 'Enter') {
                    $this._validationErrors = @()
                }

                if (-not $this._fieldWidgets.ContainsKey($currentField.Name)) {
                    # Write-PmcTuiLog "InlineEditor.HandleInput: ERROR - Widget not found for field '$($currentField.Name)'. Available widgets: $($this._fieldWidgets.Keys -join ', ')" "ERROR"
                    return $false
                }

                $widget = $this._fieldWidgets[$currentField.Name]
                # Write-PmcTuiLog "InlineEditor.HandleInput: Routing input to widget type=$($widget.GetType().Name)" "DEBUG"
                # Handle input for TextInput
                if ($widget.GetType().Name -eq 'TextInput') {
                    # DEBUG: Detailed trace
                    # Add-Content -Path "/tmp/pmc-input-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] InlineEditor: Before TextInput.HandleInput - Key=$($keyInfo.Key) Char='$($keyInfo.KeyChar)' Text='$($widget.Text)'"
                    # Write-PmcTuiLog "InlineEditor.HandleInput: Calling TextInput.HandleInput() with key=$($keyInfo.Key) char=$($keyInfo.KeyChar)" "DEBUG"
                    $textBefore = $widget.Text
                    $handled = $widget.HandleInput($keyInfo)
                    $textAfter = $widget.Text
                    # Add-Content -Path "/tmp/pmc-input-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] InlineEditor: After TextInput.HandleInput - handled=$handled Text before='$textBefore' after='$textAfter'"
                    # Write-PmcTuiLog "InlineEditor.HandleInput: TextInput.HandleInput() returned - Text before='$textBefore' after='$textAfter' handled=$handled" "DEBUG"

                    # CRITICAL FIX: If TextInput confirmed (Enter pressed), validate and confirm ENTIRE form
                    if ($widget.PSObject.Properties['IsConfirmed'] -and $widget.IsConfirmed) {
                        Write-PmcTuiLog "InlineEditor.HandleInput: TextInput.IsConfirmed=true at line 574, setting InlineEditor.IsConfirmed=true" "DEBUG"
                        if ($this._ValidateAllFields()) {
                            $this.IsConfirmed = $true
                            $values = $this.GetValues()
                            $this._InvokeCallback($this.OnConfirmed, $values)
                            return $true
                        }
                        else {
                            # Validation failed - show errors, reset TextInput confirmation, stay open
                            $widget.IsConfirmed = $false
                            $this._InvokeCallback($this.OnValidationFailed, $this._validationErrors)
                            return $true
                        }
                    }

                    # H-UI-3: Real-time validation with debouncing
                    # Instead of validating immediately, queue validation for later
                    if ($handled -and $keyInfo.Key -ne 'Enter' -and $keyInfo.Key -ne 'Escape') {
                        $this._lastKeystroke = [DateTime]::Now
                        $this._pendingValidationField = $currentField.Name
                        # Validation will happen in Update() method after delay
                    }

                    return $handled
                }
                return $false
            }

            # For non-text fields (Folder, File, etc.) allow Spacebar to expand
            if ($keyInfo.Key -eq 'Spacebar') {
                $this._ExpandCurrentField()
                return $true
            }
        }

        return $false
    }

    # === Rendering ===

    [void] RenderToEngine([object]$engine) {
        # Process debounced validation first
        $this._ProcessDebouncedValidation()


        # Use Z-layer for popup effect (Editor is always on top)
        # CRITICAL FIX: Base panels render at Z=20. We must be higher.
        # using 100 (Dropdown/Overlay level) ensures we are visible.
        if ($engine.PSObject.Methods['BeginLayer']) {
            $engine.BeginLayer(100)
        }

        # CRITICAL FIX: Lock rendering coordinates to prevent column misalignment
        # Some rendering systems modify X/Width during render, causing 1-pixel shifts
        # Cache values at render start and use these locked values throughout
        $lockedX = $this.X
        $lockedWidth = $this.Width
        $lockedY = $this.Y

        # LAYOUT SYSTEM: Render fields horizontally

        $currentX = $lockedX

        # Colors (Int)
        $focusBg = $this.GetThemedColorInt('Background.FieldFocused')
        $focusFg = $this.GetThemedColorInt('Foreground.FieldFocused')
        $normalBg = $this.GetThemedColorInt('Background.Field')
        $normalFg = $this.GetThemedColorInt('Foreground.Field')


        for ($i = 0; $i -lt $this._fields.Count; $i++) {
            $field = $this._fields[$i]
            $isFocused = ($i -eq $this._currentFieldIndex)
            $fieldWidth = $(if ($field.ContainsKey('Width')) { $field.Width } else { 20 })

            # Determine colors
            $fg = $(if ($isFocused) { $focusFg } else { $normalFg })
            $bg = $(if ($isFocused) { $focusBg } else { $normalBg })

            # Get display value
            $val = $this._GetFieldValuePreview($field)
            $displayText = $val


            # PREVENT DOUBLE BORDER ARTIFACTS:
            # If this field is currently expanded with a "Replacement" widget (Project/Tags),
            # we must BLANK OUT the underlying area to erase the List Grid lines.
            # But we skip drawing the text content to avoid "text bleeding" at the edges.
            if ($isFocused -and $this._showFieldWidgets -and $this._expandedFieldName -eq $field.Name) {
                if ($field.Type -eq 'project' -or $field.Type -eq 'tags') {
                    # Erase the entire field area with opaque background
                    # This hides the underlying List Grid / Separators
                    $engine.Fill($currentX, $lockedY, $fieldWidth, 1, ' ', $fg, $bg)
                    
                    # Advance X and skip drawing text/cursor (replaced by widget)
                    $currentX += $fieldWidth
                    continue
                }
            }
            
            # Text Input Handling (Cursor logic)
            $isEditableType = ($field.Type -eq 'text' -or $field.Type -eq 'textarea' -or $field.Type -eq 'date' -or $field.Type -eq 'tags' -or $field.Type -eq 'project')
            $hasWidget = $this._fieldWidgets.ContainsKey($field.Name)
            if ($isFocused -and $isEditableType -and $hasWidget) {
                $widget = $this._fieldWidgets[$field.Name]
                if ($widget.GetType().Name -eq 'TextInput') {
                    $text = $widget.GetText()

                    # Ensure widget width logic
                    $widget.Width = $fieldWidth + 4
                    
                    $cursorPos = $widget._cursorPosition
                    $scrollOffset = $widget._scrollOffset
                     
                    # Scroll logic 
                    if ($cursorPos -lt $scrollOffset) { $scrollOffset = $cursorPos }
                    if ($cursorPos -gt ($scrollOffset + $fieldWidth - 1)) { $scrollOffset = $cursorPos - $fieldWidth + 1 }
                    if ($scrollOffset -lt 0) { $scrollOffset = 0 }
                    $widget._scrollOffset = $scrollOffset # Update widget state
                    
                    $visibleText = ""
                    if ($scrollOffset -lt $text.Length) {
                        $visibleText = $text.Substring($scrollOffset)
                    }
                    if ($visibleText.Length -gt $fieldWidth) {
                        $visibleText = $visibleText.Substring(0, $fieldWidth)
                    }
                    $displayText = $visibleText
                    
                    # Render Field Background & Text
                    $engine.Fill($currentX, $lockedY, $fieldWidth, 1, ' ', $fg, $bg)
                    $engine.WriteAt($currentX, $lockedY, $displayText, $fg, $bg)

                    # Render Cursor
                    $relCursor = $cursorPos - $scrollOffset
                    if ($relCursor -ge 0 -and $relCursor -le $fieldWidth) {
                        # Draw cursor (Inverted BG/FG usually)
                        $cursorChar = " "
                        if ($relCursor -lt $displayText.Length) {
                            $cursorChar = $displayText[$relCursor]
                        }
                        # Swap FG/BG for cursor
                        $engine.WriteAt($currentX + $relCursor, $lockedY, $cursorChar, $bg, $fg)
                    }
                }
                else {
                    # Non-TextInput widget focused
                    $engine.Fill($currentX, $lockedY, $fieldWidth, 1, ' ', $fg, $bg)
                    $engine.WriteAt($currentX, $lockedY, $displayText, $fg, $bg)
                }
            }
            else {
                # Normal Field
                $engine.Fill($currentX, $lockedY, $fieldWidth, 1, ' ', $fg, $bg)
                $engine.WriteAt($currentX, $lockedY, $displayText, $fg, $bg)
            }
            
            # Advance X position
            $currentX += $fieldWidth
        }
        
        # Handle Expanded Widget Mode (Overlay)
        if ($this._showFieldWidgets -and -not [string]::IsNullOrWhiteSpace($this._expandedFieldName)) {
            $field = $this._fields | Where-Object { $_.Name -eq $this._expandedFieldName } | Select-Object -First 1
            if ($null -ne $field) {
                $widget = $null
                if ($field.Type -eq 'date' -and $this._datePickerMode -and $this._datePickerWidgets.ContainsKey($field.Name)) {
                    $widget = $this._datePickerWidgets[$field.Name]
                }
                elseif ($this._fieldWidgets.ContainsKey($field.Name)) {
                    $widget = $this._fieldWidgets[$field.Name]
                }

                if ($null -ne $widget) {
                    $fieldXOffset = 0
                    foreach ($f in $this._fields) {
                        if ($f.Name -eq $field.Name) { break }
                        $w = $(if ($f.ContainsKey('Width')) { $f.Width } else { 20 })
                        $fieldXOffset += $w
                    }
                    
                    $widget.X = $this.X + $fieldXOffset
                    $widget.Y = $this.Y
                    if ($widget.PSObject.Properties['Width']) {
                        if ($field.Type -eq 'date') { $widget.Width = 26 }
                        else { 
                            # Cap width at 60 to prevent massive dropdowns on wide screens
                            $calcWidth = [Math]::Max(20, $this.Width - 4)
                            $widget.Width = [Math]::Min(60, $calcWidth)
                        }
                    }
                    
                    if ($widget.PSObject.Methods['RenderToEngine']) {
                        $widget.RenderToEngine($engine)
                    }
                    else {
                        $out = $widget.Render()
                        if ($out) { $engine.WriteAt($widget.X, $widget.Y, $out) }
                    }
                }
            }
        }
        
        if ($engine.PSObject.Methods['EndLayer']) {
            $engine.EndLayer()
        }
    }

    <#
    .SYNOPSIS
    Render the inline editor

    .OUTPUTS
    ANSI string ready for display
    #>
    [string] Render() {
        # Process debounced validation
        $this._ProcessDebouncedValidation()

        # Dispatch based on layout mode
        # Write-PmcTuiLog "InlineEditor.Render: LayoutMode='$($this.LayoutMode)'" "DEBUG"
        if ($this.LayoutMode -eq 'horizontal') {
            return $this._RenderHorizontal()
        }
        else {
            # Write-PmcTuiLog "InlineEditor.Render: Calling _RenderVertical because LayoutMode is not 'horizontal'" "ERROR"
            return $this._RenderVertical()
        }
    }

    <#
    .SYNOPSIS
    Process debounced validation - called every frame
    #>
    hidden [void] _ProcessDebouncedValidation() {
        # Check if validation is pending and enough time has passed
        if (-not [string]::IsNullOrEmpty($this._pendingValidationField) -and
            $this._lastKeystroke -ne [DateTime]::MinValue) {

            $elapsed = ([DateTime]::Now - $this._lastKeystroke).TotalMilliseconds

            if ($elapsed -ge $this._validationDelayMs) {
                # Time to validate
                $field = $this._fields | Where-Object { $_.Name -eq $this._pendingValidationField } | Select-Object -First 1

                if ($null -ne $field) {
                    $this._ValidateFieldRealtime($field)
                }

                # Clear pending state
                $this._pendingValidationField = ""
                $this._lastKeystroke = [DateTime]::MinValue
            }
        }
    }

    <#
    .SYNOPSIS
    Render fields horizontally (inline mode)
    #>
    hidden [string] _RenderHorizontal() {
        $sb = [StringBuilder]::new(2048)

        # NEW THEME API - delegate to theme engine
        $reset = "`e[0m"

        # DEBUG: Always render SOMETHING visible
        if ($this._fields.Count -eq 0) {
            $sb.Append($this.BuildMoveTo($this.X, $this.Y))
            $sb.Append("`e[41m NO FIELDS CONFIGURED `e[0m")
            return $sb.ToString()
        }

        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [EDIT] InlineEditor._RenderHorizontal() called"
        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [EDIT] _showFieldWidgets=$($this._showFieldWidgets) _expandedFieldName='$($this._expandedFieldName)'"
        # }

        # If a widget is expanded, render it instead
        if ($this._showFieldWidgets -and -not [string]::IsNullOrWhiteSpace($this._expandedFieldName)) {
            # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [EDIT] WIDGET EXPANDED - field='$($this._expandedFieldName)'"
            # }
            $field = $this._fields | Where-Object { $_.Name -eq $this._expandedFieldName } | Select-Object -First 1
            if ($null -ne $field) {
                # CRITICAL FIX: For date fields in DatePicker mode, use DatePicker NOT TextInput
                $widget = $null
                if ($field.Type -eq 'date' -and $this._datePickerMode -and $this._datePickerWidgets.ContainsKey($field.Name)) {
                    $widget = $this._datePickerWidgets[$field.Name]
                    # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [EDIT] Found DatePicker in _datePickerWidgets: $($widget.GetType().Name)"
                    # }
                }
                elseif ($this._fieldWidgets.ContainsKey($field.Name)) {
                    $widget = $this._fieldWidgets[$field.Name]
                    # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [EDIT] Found widget in _fieldWidgets: $($widget.GetType().Name)"
                    # }
                }

                if ($null -ne $widget) {
                    # Widget types that render themselves
                    if ($widget.GetType().Name -in @('DatePicker', 'ProjectPicker', 'TagEditor')) {
                        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [EDIT] Rendering expanded widget: $($widget.GetType().Name)"
                        # }
                        # NOTE: NeedsClear NOT set - widgets render as overlays without clearing screen
                        $widgetOutput = $widget.Render()
                        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [EDIT] Widget rendered, output length=$($widgetOutput.Length)"
                        # }
                        return $widgetOutput
                    }
                }
            }
        }

        # CRITICAL: NO row background in edit mode - only focused field gets background
        # This keeps the row clean and highlights only the active field
        $reset = "`e[0m"

        # Move to start of row (no background color applied)
        $sb.Append($this.BuildMoveTo($this.X, $this.Y))

        # DEBUG: Show that we're rendering
        # $sb.Append("`e[42m[EDIT]`e[0m ")

        # Render fields side-by-side with absolute positioning
        $currentX = $this.X

        for ($i = 0; $i -lt $this._fields.Count; $i++) {
            $field = $this._fields[$i]
            $isFocused = ($i -eq $this._currentFieldIndex)

            # Calculate field width (use Width from field definition or default)
            $fieldWidth = $(if ($field.ContainsKey('Width')) { $field.Width } else { 20 })

            # CRITICAL: Position each field explicitly at its X coordinate
            # This prevents wrapping and ensures precise alignment
            $sb.Append($this.BuildMoveTo($currentX, $this.Y))

            # Get field value
            $value = $this._GetFieldValuePreview($field)

            # For focused text fields with TextInput widget, show with cursor
            if ($isFocused -and ($field.Type -eq 'text' -or $field.Type -eq 'textarea' -or $field.Type -eq 'date' -or $field.Type -eq 'tags' -or $field.Type -eq 'project') -and $this._fieldWidgets.ContainsKey($field.Name)) {
                $widget = $this._fieldWidgets[$field.Name]
                if ($widget.GetType().Name -eq 'TextInput') {
                    # FIX: Update widget width to match field width for correct scroll calculation in HandleInput
                    $widget.Width = $fieldWidth + 4

                    $text = $widget.GetText()
                    $cursorPos = $widget._cursorPosition

                    # Calculate scroll offset locally to ensure immediate responsiveness to width changes
                    # Use existing offset as starting point if possible, but clamp to new width
                    $scrollOffset = $widget._scrollOffset

                    # Recalculate scroll offset to ensure cursor is visible within fieldWidth
                    if ($cursorPos -lt $scrollOffset) {
                        $scrollOffset = $cursorPos
                    }
                    if ($cursorPos -gt ($scrollOffset + $fieldWidth - 1)) {
                        $scrollOffset = $cursorPos - $fieldWidth + 1
                    }
                    if ($scrollOffset -lt 0) {
                        $scrollOffset = 0
                    }

                    # Get visible text
                    $visibleText = ""
                    if ($scrollOffset -lt $text.Length) {
                        $visibleText = $text.Substring($scrollOffset)
                    }
                    if ($visibleText.Length -gt $fieldWidth) {
                        $visibleText = $visibleText.Substring(0, $fieldWidth)
                    }

                    # Pad to field width + 2 to match column padding
                    $paddedText = $visibleText.PadRight($fieldWidth + 2)

                    # Calculate cursor position relative to visible text
                    $relCursorPos = $cursorPos - $scrollOffset

                    # CRITICAL FIX: Use theme colors for focused field
                    $focusBg = $this.GetThemedBg('Background.FieldFocused', $fieldWidth, 0)
                    $focusFg = $this.GetThemedFg('Foreground.FieldFocused')

                    # Render with highlighting and blinking cursor
                    $renderWidth = $fieldWidth + 2
                    for ($charIdx = 0; $charIdx -lt $renderWidth; $charIdx++) {
                        if ($charIdx -eq $relCursorPos) {
                            # Cursor position - invert colors and blink
                            $sb.Append("`e[7m`e[5m" + $focusBg + $focusFg + $paddedText[$charIdx] + "`e[25m`e[27m")
                            # Restore focus colors after cursor
                            if ($charIdx -lt ($renderWidth - 1)) {
                                $sb.Append($focusBg + $focusFg)
                            }
                        }
                        else {
                            $sb.Append($focusBg + $focusFg + $paddedText[$charIdx])
                        }
                    }

                    # Reset after focused field
                    $sb.Append($reset)
                }
                else {
                    # Widget field (date/project/tags) that isn't TextInput - show preview with focus
                    $renderWidth = $fieldWidth + 2
                    $displayValue = $value.PadRight($renderWidth)
                    if ($displayValue.Length -gt $renderWidth) {
                        $displayValue = $displayValue.Substring(0, $renderWidth)
                    }

                    # Use theme colors for focused widget fields
                    $focusBg = $this.GetThemedBg('Background.FieldFocused', $renderWidth, 0)
                    $focusFg = $this.GetThemedFg('Foreground.FieldFocused')
                    $sb.Append($focusBg + $focusFg + $displayValue)
                    # Reset after focused field
                    $sb.Append($reset)
                }
            }
            else {
                # Non-focused field - show value without special highlighting
                # For date/project fields, show TextInput content if available
                $displayValue = $value
                if (($field.Type -eq 'date' -or $field.Type -eq 'project') -and $this._fieldWidgets.ContainsKey($field.Name)) {
                    $widget = $this._fieldWidgets[$field.Name]
                    if ($widget.GetType().Name -eq 'TextInput') {
                        $displayValue = $widget.GetText()
                    }
                }

                $renderWidth = $fieldWidth + 2
                $displayValue = $displayValue.PadRight($renderWidth)
                if ($displayValue.Length -gt $renderWidth) {
                    $displayValue = $displayValue.Substring(0, $renderWidth)
                }
                # CRITICAL: Non-focused fields ALSO get background highlighting in edit mode
                $unfocusedBg = $this.GetThemedBg('Background.Field', $renderWidth, 0)
                $unfocusedFg = $this.GetThemedFg('Foreground.Field')
                $sb.Append($unfocusedBg + $unfocusedFg + $displayValue)
                # Reset after non-focused field
                $sb.Append($reset)
            }

            # CRITICAL FIX: Match UniversalList column spacing exactly
            # UniversalList uses: currentX += colWidth (no extra padding)
            # We must match to avoid cumulative column misalignment in Edit mode
            $currentX += $fieldWidth
        }

        # CRITICAL FIX: Reset colors THEN clear to EOL (ensures no background bleeds into padding)
        $sb.Append($reset)  # Reset colors first
        $sb.Append("`e[K")  # Then clear to end of line

        # DO NOT clear line below in horizontal mode - InlineEditor is rendering WITHIN the grid
        # Clearing the line below would erase grid content

        return $sb.ToString()
    }

    <#
    .SYNOPSIS
    Render fields vertically (popup mode)
    #>
    hidden [string] _RenderVertical() {
        $sb = [StringBuilder]::new(4096)

        # Colors from theme (NEW API)
        $borderColor = $this.GetThemedFg('Border.Widget')
        $textColor = $this.GetThemedFg('Foreground.Field')
        $primaryColor = $this.GetThemedFg('Foreground.FieldFocused')
        $mutedColor = $this.GetThemedFg('Foreground.Muted')
        $errorColor = $this.GetThemedFg('Foreground.Error')
        $successColor = $this.GetThemedFg('Foreground.Success')
        $highlightBg = $this.GetThemedBg('Background.RowSelected', 80, 0)
        $reset = "`e[0m"

        # If a field widget is expanded, render it instead of the form
        if ($this._showFieldWidgets -and -not [string]::IsNullOrWhiteSpace($this._expandedFieldName)) {
            # Get the appropriate widget based on mode
            $field = $this._fields | Where-Object { $_.Name -eq $this._expandedFieldName } | Select-Object -First 1

            $widget = $null
            if ($field.Type -eq 'date' -and $this._datePickerMode) {
                # Render DatePicker when in DatePicker mode
                if ($this._datePickerWidgets.ContainsKey($this._expandedFieldName)) {
                    $widget = $this._datePickerWidgets[$this._expandedFieldName]
                }
            }
            else {
                # Render normal widget
                if ($this._fieldWidgets.ContainsKey($this._expandedFieldName)) {
                    $widget = $this._fieldWidgets[$this._expandedFieldName]
                }
            }

            if ($null -ne $widget) {
                # Check if widget is PmcFilePicker (needs terminal dimensions)
                if ($widget.GetType().Name -eq 'PmcFilePicker') {
                    # Get terminal size
                    try {
                        $termWidth = [Console]::WindowWidth
                        $termHeight = [Console]::WindowHeight
                    }
                    catch {
                        $termWidth = 120
                        $termHeight = 40
                    }


                    # }

                    # NOTE: NeedsClear NOT set - FilePicker renders as overlay without clearing screen
                    $output = $widget.Render($termWidth, $termHeight)


                    # }

                    return $output
                }
                else {
                    return $widget.Render()
                }
            }

            # Widget doesn't exist - fall through to render normal form
            $this._showFieldWidgets = $false
            $this._expandedFieldName = ""
        }

        # Draw top border
        $sb.Append($this.BuildMoveTo($this.X, $this.Y))
        $sb.Append($borderColor)
        $sb.Append($this.BuildBoxBorder($this.Width, 'top', 'single'))

        # Title
        $titleText = " $($this.Title) "
        $titlePos = 2
        $sb.Append($this.BuildMoveTo($this.X + $titlePos, $this.Y))
        $sb.Append($primaryColor)
        $sb.Append($titleText)

        # Field count
        $countText = "($($this._fields.Count) fields)"
        $sb.Append($this.BuildMoveTo($this.X + $this.Width - $countText.Length - 2, $this.Y))
        $sb.Append($mutedColor)
        $sb.Append($countText)

        $currentRow = 1

        # Render each field
        for ($i = 0; $i -lt $this._fields.Count; $i++) {
            $field = $this._fields[$i]
            $isFocused = ($i -eq $this._currentFieldIndex)

            # Field row
            $rowY = $this.Y + $currentRow

            # Label row
            $sb.Append($this.BuildMoveTo($this.X, $rowY))
            # H-UI-3: Show red border if field has validation error
            $hasError = $this._fieldErrors.ContainsKey($field.Name)
            if ($hasError) {
                $sb.Append($errorColor)
            }
            else {
                $sb.Append($borderColor)
            }
            $sb.Append($this.GetBoxChar('single_vertical'))

            # Label
            $label = $field.Label
            $isRequired = $(if ($field.ContainsKey('Required')) { $field.Required } else { $false })
            if ($isRequired) {
                $label += " *"
            }

            $sb.Append($this.BuildMoveTo($this.X + 2, $rowY))
            if ($hasError) {
                # H-UI-3: Red text for invalid field label
                $sb.Append($errorColor)
            }
            elseif ($isFocused) {
                $sb.Append($primaryColor)
            }
            else {
                $sb.Append($mutedColor)
            }
            $sb.Append($this.PadText($label + ":", 20, 'left'))

            # Value display - for text/date fields, render the TextInput widget inline
            $sb.Append($this.BuildMoveTo($this.X + 22, $rowY))

            if (($field.Type -eq 'text' -or $field.Type -eq 'textarea' -or $field.Type -eq 'date' -or $field.Type -eq 'tags') -and $isFocused -and $this._fieldWidgets.ContainsKey($field.Name)) {
                # Render TextInput widget inline for focused text/textarea/date/tags fields
                $widget = $this._fieldWidgets[$field.Name]
                if ($widget.GetType().Name -eq 'TextInput') {
                    $sb.Append($textColor)
                    $text = $widget.GetText()
                    $cursorPos = $widget._cursorPosition

                    # Show text with cursor
                    if ($cursorPos -le $text.Length) {
                        $beforeCursor = $text.Substring(0, $cursorPos)
                        $atCursor = $(if ($cursorPos -lt $text.Length) { $text.Substring($cursorPos, 1) } else { " " })
                        $afterCursor = $(if ($cursorPos -lt $text.Length - 1) { $text.Substring($cursorPos + 1) } else { "" })

                        $sb.Append($beforeCursor)
                        $sb.Append($highlightBg)
                        $sb.Append($textColor)  # Use Body text color, not hardcoded black
                        $sb.Append($atCursor)
                        $sb.Append($reset)
                        $sb.Append($textColor)
                        $sb.Append($afterCursor)
                    }
                    else {
                        $sb.Append($text)
                    }
                    $sb.Append($reset)
                }
                else {
                    # Not a TextInput, show preview
                    if ($isFocused) {
                        $sb.Append($highlightBg)
                        $sb.Append($textColor)  # Use Body text color, not hardcoded black
                    }
                    else {
                        $sb.Append($textColor)
                    }
                    $valuePreview = $this._GetFieldValuePreview($field)
                    $sb.Append($this.PadText($valuePreview, $this.Width - 24, 'left'))
                    if ($isFocused) {
                        $sb.Append($reset)
                    }
                }
            }
            else {
                # Not focused or not text/date field - show preview
                if ($isFocused) {
                    $sb.Append($highlightBg)
                    $sb.Append($textColor)  # Use Body text color, not hardcoded black
                }
                else {
                    $sb.Append($textColor)
                }

                $valuePreview = $this._GetFieldValuePreview($field)
                $sb.Append($this.PadText($valuePreview, $this.Width - 24, 'left'))

                if ($isFocused) {
                    $sb.Append($reset)
                }
            }

            # Right border
            $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $rowY))
            if ($hasError) {
                $sb.Append($errorColor)
            }
            else {
                $sb.Append($borderColor)
            }
            $sb.Append($this.GetBoxChar('single_vertical'))

            $currentRow++

            # Spacing row (H-UI-3: show error message below field if invalid)
            $sb.Append($this.BuildMoveTo($this.X, $this.Y + $currentRow))
            if ($hasError) {
                $sb.Append($errorColor)
            }
            else {
                $sb.Append($borderColor)
            }
            $sb.Append($this.GetBoxChar('single_vertical'))

            # H-UI-3: Display per-field error message
            if ($hasError) {
                $errorMsg = $this._fieldErrors[$field.Name]
                $sb.Append($this.BuildMoveTo($this.X + 2, $this.Y + $currentRow))
                $sb.Append($errorColor)
                $sb.Append($this.TruncateText($errorMsg, $this.Width - 4))
            }
            else {
                $sb.Append(" " * ($this.Width - 2))
            }

            $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $this.Y + $currentRow))
            if ($hasError) {
                $sb.Append($errorColor)
            }
            else {
                $sb.Append($borderColor)
            }
            $sb.Append($this.GetBoxChar('single_vertical'))

            $currentRow++
        }

        # Help text row
        $helpRowY = $this.Y + $currentRow
        $sb.Append($this.BuildMoveTo($this.X, $helpRowY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        $sb.Append($this.BuildMoveTo($this.X + 2, $helpRowY))
        $sb.Append($mutedColor)
        $helpText = "Tab: Next | Enter on Save button | Esc: Cancel"
        $sb.Append($this.TruncateText($helpText, $this.Width - 4))

        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $helpRowY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        $currentRow++

        # Validation errors row
        $errorRowY = $this.Y + $currentRow
        $sb.Append($this.BuildMoveTo($this.X, $errorRowY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        if ($this._validationErrors.Count -gt 0) {
            $sb.Append($this.BuildMoveTo($this.X + 2, $errorRowY))
            $sb.Append($errorColor)
            $errorMsg = $this._validationErrors[0]  # Show first error
            $sb.Append($this.TruncateText($errorMsg, $this.Width - 4))
        }
        else {
            $sb.Append(" " * ($this.Width - 2))
        }

        $sb.Append($this.BuildMoveTo($this.X + $this.Width - 1, $errorRowY))
        $sb.Append($borderColor)
        $sb.Append($this.GetBoxChar('single_vertical'))

        $currentRow++

        # Bottom border
        $sb.Append($this.BuildMoveTo($this.X, $this.Y + $currentRow))
        $sb.Append($borderColor)
        $sb.Append($this.BuildBoxBorder($this.Width, 'bottom', 'single'))

        $sb.Append($reset)
        return $sb.ToString()
    }

    # === Private Helper Methods ===

    <#
    .SYNOPSIS
    Create widget instance for a field
    #>
    hidden [void] _CreateFieldWidget([hashtable]$fieldDef) {
        $fieldName = $fieldDef.Name
        $fieldType = $fieldDef.Type
        $value = $(if ($fieldDef.ContainsKey('Value')) { $fieldDef.Value } else { $null })

        $widget = $null

        switch ($fieldType) {
            'text' {
                $widget = [TextInput]::new()
                # Use properties, not methods
                $widget.X = $this.X + 5
                $widget.Y = $this.Y + 5
                $widget.Width = 60
                $widget.Height = 3
                $widget.Label = $fieldDef.Label

                if ($value) {
                    $widget.SetText($value)
                }

                if ($fieldDef.ContainsKey('MaxLength')) {
                    $widget.MaxLength = $fieldDef.MaxLength
                }

                if ($fieldDef.ContainsKey('Placeholder')) {
                    $widget.Placeholder = $fieldDef.Placeholder
                }
            }

            'textarea' {
                # Use TextInput with larger size for multi-line text (inline editing)
                # For full-featured editing, users can open dedicated TextAreaEditor screen
                # Future enhancement: Add modal TextAreaEditor dialog for complex text editing
                $widget = [TextInput]::new()
                # Use properties, not methods
                $widget.X = $this.X + 5
                $widget.Y = $this.Y + 5
                $widget.Width = 60
                $widget.Height = 5  # Taller than regular text input
                $widget.Label = $fieldDef.Label

                if ($value) {
                    # Replace newlines with a visible separator for single-line display
                    $displayValue = $value.ToString() -replace "`n", " | "
                    $widget.SetText($displayValue)
                }

                if ($fieldDef.ContainsKey('MaxLength')) {
                    $widget.MaxLength = $fieldDef.MaxLength
                }
                else {
                    $widget.MaxLength = 5000  # Default larger limit for textarea
                }

                $widget.Placeholder = 'Separate items with  | '
            }

            'date' {
                # For inline editing, use TextInput (user can type dates like "2025-11-15" or "+3")
                # DatePicker is created on-demand when user presses Enter
                $widget = [TextInput]::new()
                $widget.MaxLength = 20

                if ($value) {
                    if ($value -is [DateTime]) {
                        $widget.SetText($value.ToString('yyyy-MM-dd'))
                    }
                    else {
                        $widget.SetText($value.ToString())
                    }
                }
                else {
                    $widget.SetText('')
                }

                $widget.Placeholder = 'yyyy-MM-dd or +days'

                # Wire up text change callback to update field value
                $editor = $this
                $field = $fieldDef
                $widget.OnTextChanged = {
                    param($newText)
                    # Update the field value when text changes
                    $editor._SetFieldValue($field.Name, $newText)
                }
            }

            'project' {
                # In horizontal mode, use TextInput for inline typing
                # In vertical mode, use ProjectPicker for full selection UI
                if ($this.LayoutMode -eq 'horizontal') {
                    $widget = [TextInput]::new()
                    $widget.MaxLength = 100
                    $widget.Placeholder = 'Project name'
                    if ($value) {
                        $widget.SetText($value.ToString())
                    }
                    else {
                        $widget.SetText('')
                    }
                }
                else {
                    $widget = [ProjectPicker]::new()
                    # Use properties, not methods
                    $widget.X = $this.X + 5
                    $widget.Y = $this.Y + 5
                    $widget.Width = 35
                    $widget.Height = 12
                    $widget.Label = $fieldDef.Label
                    if ($value) {
                        $widget.SetSearchText($value)
                    }
                }
            }

            'tags' {
                # Tags use simple text input with comma-separated values
                $widget = [TextInput]::new()
                $widget.MaxLength = 100
                $widget.Placeholder = 'tag1, tag2, tag3'

                if ($value -and $value -is [array]) {
                    # Convert array to comma-separated string
                    $widget.SetText($value -join ', ')
                }
                elseif ($value) {
                    $widget.SetText($value.ToString())
                }
                else {
                    $widget.SetText('')
                }

                # Wire up callback to save changes
                $editor = $this
                $field = $fieldDef
                $widget.OnTextChanged = {
                    param($newText)
                    $editor._SetFieldValue($field.Name, $newText)
                }
            }

            'folder' {
                # Folder picker - use TextInput for inline display
                $widget = [TextInput]::new()
                $widget.MaxLength = 255
                $widget.Placeholder = 'Press Enter to browse...'

                if ($value) {
                    $widget.SetText($value.ToString())
                }
                else {
                    $widget.SetText('')
                }

                # Wire up callback
                $editor = $this
                $field = $fieldDef
                $widget.OnTextChanged = {
                    param($newText)
                    $editor._SetFieldValue($field.Name, $newText)
                }
            }

            'file' {
                # File picker - use TextInput for inline display
                $widget = [TextInput]::new()
                $widget.MaxLength = 255
                $widget.Placeholder = 'Press Enter to browse...'

                if ($value) {
                    $widget.SetText($value.ToString())
                }
                else {
                    $widget.SetText('')
                }

                # Wire up callback
                $editor = $this
                $field = $fieldDef
                $widget.OnTextChanged = {
                    param($newText)
                    $editor._SetFieldValue($field.Name, $newText)
                }
            }

            'number' {
                # Number fields use TextInput for direct entry AND arrow keys for increment/decrement
                $widget = [TextInput]::new()
                $widget.X = $this.X + 5
                $widget.Y = $this.Y + 5
                $widget.Width = 20
                $widget.Height = 3
                $widget.Label = $fieldDef.Label
                
                # Set initial value
                if ($value) {
                    $widget.SetText($value.ToString())
                } else {
                    $min = $(if ($fieldDef.ContainsKey('Min')) { $fieldDef.Min } else { 0 })
                    $widget.SetText($min.ToString())
                }
                
                # Validate input is numeric
                $widget.OnTextChanged = {
                    param($newText)
                    if ([string]::IsNullOrWhiteSpace($newText)) { return }
                    if ($newText -notmatch '^-?\d*\.?\d*$') {
                        # Revert invalid char? (TextInput doesn't support revert easily, rely on validation)
                    }
                }
            }

            'button' {
                # Button is handled inline (no separate widget)
            }

            default {
                throw "Unsupported field type: $fieldType"
            }
        }

        if ($widget) {
            $this._fieldWidgets[$fieldName] = $widget
            # Write-PmcTuiLog "InlineEditor._CreateFieldWidget: Stored widget for field '$fieldName' (type=$fieldType) - widget.Text='$(if ($widget.GetType().Name -eq 'TextInput') { $widget.Text } else { 'N/A' })'" "DEBUG"
        }
        else {
            # Write-PmcTuiLog "InlineEditor._CreateFieldWidget: WARNING - widget is null for field '$fieldName' (type=$fieldType)" "WARNING"
        }
    }

    <#
    .SYNOPSIS
    Get current value of a field
    #>
    hidden [object] _GetFieldValue([string]$fieldName, [string]$fieldType) {
        switch ($fieldType) {
            'text' {
                if (-not $this._fieldWidgets.ContainsKey($fieldName)) {
                    # Write-PmcTuiLog "ERROR: No widget for text field '$fieldName'" "ERROR"
                    return ""
                }
                $widget = $this._fieldWidgets[$fieldName]
                if (-not $widget) {
                    # Write-PmcTuiLog "ERROR: Widget is null for text field '$fieldName'" "ERROR"
                    return ""
                }
                $value = $widget.GetText()
                # Write-PmcTuiLog "InlineEditor._GetFieldValue: text field '$fieldName' -> value='$value' (widget.Text='$($widget.Text)')" "DEBUG"
                return $value
            }

            'textarea' {
                $widget = $this._fieldWidgets[$fieldName]
                # Convert pipe-separated items back to newline-separated
                $text = $widget.GetText()
                return $text -replace '\s*\|\s*', "`n"
            }

            'date' {
                $widget = $this._fieldWidgets[$fieldName]
                # Date fields use TextInput for inline editing
                if ($widget.GetType().Name -eq 'TextInput') {
                    $dateText = $widget.GetText().Trim().ToLower()
                    if ([string]::IsNullOrWhiteSpace($dateText)) {
                        return $null
                    }

                    # Parse relative dates like "+7" or "-3"
                    if ($dateText -match '^([+-])(\d+)$') {
                        $sign = $matches[1]
                        $days = [int]$matches[2]
                        if ($sign -eq '+') {
                            return [DateTime]::Now.AddDays($days)
                        }
                        else {
                            return [DateTime]::Now.AddDays(-$days)
                        }
                    }

                    # Special keywords
                    if ($dateText -eq 'today' -or $dateText -eq 't') {
                        return [DateTime]::Today
                    }
                    if ($dateText -eq 'tomorrow' -or $dateText -eq 'tom') {
                        return [DateTime]::Today.AddDays(1)
                    }
                    if ($dateText -eq 'yesterday') {
                        return [DateTime]::Today.AddDays(-1)
                    }
                    if ($dateText -eq 'eom') {
                        # End of current month
                        $now = [DateTime]::Now
                        return [DateTime]::new($now.Year, $now.Month, [DateTime]::DaysInMonth($now.Year, $now.Month))
                    }
                    if ($dateText -eq 'eoy') {
                        # End of current year
                        return [DateTime]::new([DateTime]::Now.Year, 12, 31)
                    }
                    if ($dateText -eq 'som') {
                        # Start of current month
                        $now = [DateTime]::Now
                        return [DateTime]::new($now.Year, $now.Month, 1)
                    }

                    # Parse YYYYMMDD format (20251125)
                    if ($dateText -match '^\d{8}$') {
                        try {
                            $year = [int]$dateText.Substring(0, 4)
                            $month = [int]$dateText.Substring(4, 2)
                            $day = [int]$dateText.Substring(6, 2)
                            return [DateTime]::new($year, $month, $day)
                        }
                        catch {
                            # Invalid date, fall through
                        }
                    }

                    # Parse YYMMDD format (251125)
                    if ($dateText -match '^\d{6}$') {
                        try {
                            $year = 2000 + [int]$dateText.Substring(0, 2)
                            $month = [int]$dateText.Substring(2, 2)
                            $day = [int]$dateText.Substring(4, 2)
                            return [DateTime]::new($year, $month, $day)
                        }
                        catch {
                            # Invalid date, fall through
                        }
                    }

                    # Parse absolute dates (standard formats)
                    try {
                        return [DateTime]::Parse($dateText)
                    }
                    catch {
                        return $null
                    }
                }
                else {
                    # DatePicker (if still using old approach)
                    return $widget.GetSelectedDate()
                }
            }

            'project' {
                $widget = $this._fieldWidgets[$fieldName]
                # In horizontal mode, project uses TextInput for inline typing
                if ($widget.GetType().Name -eq 'TextInput') {
                    return $widget.GetText()
                }
                else {
                    return $widget.GetSelectedProject()
                }
            }

            'tags' {
                # Tags are stored as comma-separated text in TextInput
                $widget = $this._fieldWidgets[$fieldName]
                $tagsText = $widget.GetText()

                if ([string]::IsNullOrWhiteSpace($tagsText)) {
                    return @()
                }

                # Split by comma and trim
                $tags = $tagsText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                # H-VAL-5: Validate tags match pattern ^[a-zA-Z0-9_-]+$
                $validTags = @()
                foreach ($tag in $tags) {
                    if ($tag -match '^[a-zA-Z0-9_-]+$') {
                        $validTags += $tag
                    }
                    else {
                        # Write-PmcTuiLog "InlineEditor: Invalid tag '$tag' - must contain only letters, numbers, underscore, or hyphen" "WARNING"
                    }
                }

                return @($validTags)
            }

            'folder' {
                # Folder path stored as text in TextInput (or PmcFilePicker if still expanded)
                $widget = $this._fieldWidgets[$fieldName]
                if ($widget.GetType().Name -eq 'PmcFilePicker') {
                    # Still showing picker - return current path
                    return $widget.CurrentPath
                }
                else {
                    # TextInput - return text
                    return $widget.GetText()
                }
            }

            'file' {
                # File path stored as text in TextInput (or PmcFilePicker if still expanded)
                $widget = $this._fieldWidgets[$fieldName]
                if ($widget.GetType().Name -eq 'PmcFilePicker') {
                    # Still showing picker - return current path
                    return $widget.CurrentPath
                }
                else {
                    # TextInput - return text
                    return $widget.GetText()
                }
            }

            'number' {
                if ($this._fieldWidgets.ContainsKey($fieldName)) {
                    $widget = $this._fieldWidgets[$fieldName]
                    $textVal = $widget.GetText()
                    if ([string]::IsNullOrWhiteSpace($textVal)) {
                        return 0
                    }
                    try {
                        return [double]$textVal
                    } catch {
                        return 0
                    }
                }
                
                $field = $this._fields | Where-Object { $_.Name -eq $fieldName } | Select-Object -First 1
                if ($field.ContainsKey('Value')) {
                    return $field.Value
                }
                else {
                    return 0
                }
            }

            'button' {
                return $null
            }

            default {
                return $null
            }
        }
        # Fallback (should never reach here)
        return $null
    }

    <#
    .SYNOPSIS
    Set field value (for inline editing)
    #>
    hidden [void] _SetFieldValue([string]$fieldName, [object]$value) {
        # Find the field
        $field = $this._fields | Where-Object { $_.Name -eq $fieldName } | Select-Object -First 1
        if ($null -eq $field) {
            return
        }

        # Update the field's Value property
        $field.Value = $value

        # CRITICAL FIX: Also update the widget if it exists
        # This is required for "number" fields where arrow keys update the value via this method,
        # but the UI (TextInput) wouldn't update because _GetFieldValue prioritizes reading from the widget.
        if ($this._fieldWidgets.ContainsKey($fieldName)) {
            $widget = $this._fieldWidgets[$fieldName]
            
            # Handle TextInput (used for text, number, date, project-inline)
            if ($widget.GetType().Name -eq 'TextInput') {
                $newText = if ($null -ne $value) { $value.ToString() } else { "" }
                $currentText = $widget.GetText()
                
                # Only update if different to avoid infinite loops with OnTextChanged
                # and to preserve cursor position when typing
                if ($newText -ne $currentText) {
                    $widget.SetText($newText)
                }
            }
        }
    }

    <#
    .SYNOPSIS
    Get preview string for a field (for list view)
    #>
    hidden [string] _GetFieldValuePreview([hashtable]$field) {
        $fieldName = $field.Name
        $fieldType = $field.Type
        $value = $this._GetFieldValue($fieldName, $fieldType)

        switch ($fieldType) {
            'text' {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    return "(empty)"
                }
                return $value
            }

            'date' {
                if ($value -is [DateTime]) {
                    return $value.ToString("yyyy-MM-dd (ddd)")
                }
                # Show raw text from TextInput if it exists
                if ($this._fieldWidgets.ContainsKey($fieldName)) {
                    $widget = $this._fieldWidgets[$fieldName]
                    if ($widget.GetType().Name -eq 'TextInput') {
                        $text = $widget.GetText()
                        if (-not [string]::IsNullOrWhiteSpace($text)) {
                            return $text
                        }
                    }
                }
                return "(no date)"
            }

            'project' {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    return "(no project)"
                }
                return $value
            }

            'tags' {
                if ($null -eq $value -or $value.Count -eq 0) {
                    return "(no tags)"
                }
                return "[" + ($value -join "] [") + "]"
            }

            'number' {
                $min = $(if ($field.ContainsKey('Min')) { $field.Min } else { 0 })
                $max = $(if ($field.ContainsKey('Max')) { $field.Max } else { 10 })
                $val = $(if ($null -ne $value) { $value } else { $min })

                # Build visual slider
                $range = $max - $min
                $position = $(if ($range -gt 0) { [Math]::Floor(($val - $min) / $range * 10) } else { 0 })
                $slider = "[" + ("-" * $position) + "●" + ("-" * (10 - $position)) + "] $val"
                return $slider
            }

            'button' {
                $buttonText = $(if ($field.ContainsKey('ButtonText')) { $field.ButtonText } else { 'Button' })
                return "[ $buttonText ]"
            }

            'folder' {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    return "(no folder)"
                }
                return $value
            }

            default {
                return "(unknown)"
            }
        }
        # Fallback (should never reach here)
        return "(unknown)"
    }

    <#
    .SYNOPSIS
    Move to next field
    #>
    hidden [void] _MoveToNextField() {
        if ($this._currentFieldIndex -lt ($this._fields.Count - 1)) {
            $this._currentFieldIndex++
            $this._validationErrors = @()
        }
        else {
            # Wrap to first field
            $this._currentFieldIndex = 0
        }
    }

    <#
    .SYNOPSIS
    Move to previous field
    #>
    hidden [void] _MoveToPreviousField() {
        if ($this._currentFieldIndex -gt 0) {
            $this._currentFieldIndex--
            $this._validationErrors = @()
        }
        else {
            # Wrap to last field
            $this._currentFieldIndex = $this._fields.Count - 1
        }
    }

    <#
    .SYNOPSIS
    Expand current field's widget
    #>
    hidden [void] _ExpandCurrentField() {
        if ($this._currentFieldIndex -ge 0 -and $this._currentFieldIndex -lt $this._fields.Count) {
            $field = $this._fields[$this._currentFieldIndex]

            # Text, Textarea, Tags, Number, and Button fields are handled inline (no expansion)
            # Tags are comma-separated text input, no widget needed
            if ($field.Type -eq 'text' -or $field.Type -eq 'textarea' -or $field.Type -eq 'tags' -or $field.Type -eq 'number' -or $field.Type -eq 'button') {
                return
            }

            # For folder fields, create PmcFilePicker on demand
            if ($field.Type -eq 'folder') {
                # Load PmcFilePicker if not already loaded
                . "$PSScriptRoot/PmcFilePicker.ps1"

                # Get current value from TextInput widget
                $textWidget = $this._fieldWidgets[$field.Name]
                $currentPath = $textWidget.GetText()

                # Create FilePicker using Add-Type to avoid parse-time type dependency
                $filePickerType = 'PmcFilePicker' -as [Type]
                $filePicker = $filePickerType::new($currentPath, $true)  # true = directories only
                $filePicker.Width = 70
                $filePicker.Height = 20

                # Replace the TextInput with FilePicker temporarily
                $this._fieldWidgets[$field.Name] = $filePicker

                $this._expandedFieldName = $field.Name
                $this._showFieldWidgets = $true
                # NOTE: NeedsClear NOT set - widget renders as overlay without clearing screen

                $filePicker.IsComplete = $false
                $filePicker.Result = $false
                return
            }

            # For date fields, create fresh DatePicker each time
            if ($field.Type -eq 'date') {
                # Get current value from TextInput widget (which stays in _fieldWidgets)
                $textWidget = $this._fieldWidgets[$field.Name]
                $currentText = $textWidget.GetText()

                # ALWAYS create a fresh DatePicker (don't reuse old instances)
                $datePicker = [DatePicker]::new()
                $datePicker.SetPosition($this.X + 5, $this.Y + 5)
                $datePicker.SetSize(35, 14)

                # Force calendar mode (not text input mode)
                $datePicker._isCalendarMode = $true

                # Parse current text value to DateTime if possible
                if (-not [string]::IsNullOrWhiteSpace($currentText)) {
                    try {
                        $parsedDate = [DateTime]::Parse($currentText)
                        $datePicker.SetDate($parsedDate)
                    }
                    catch {
                        # Invalid date, use today
                        $datePicker.SetDate([DateTime]::Now)
                    }
                }
                else {
                    # No text, use today
                    $datePicker.SetDate([DateTime]::Now)
                }

                # Store fresh DatePicker
                $this._datePickerWidgets[$field.Name] = $datePicker

                # Set mode to DatePicker
                $this._datePickerMode = $true

                # Fresh picker has IsConfirmed/IsCancelled already false
                $this._expandedFieldName = $field.Name
                $this._showFieldWidgets = $true
                # NOTE: NeedsClear NOT set - widget renders as overlay without clearing screen
                return
            }

            # For project fields, create fresh ProjectPicker each time
            if ($field.Type -eq 'project') {
                # Load ProjectPicker if not already loaded
                if (-not ([System.Management.Automation.PSTypeName]'ProjectPicker').Type) {
                    . "$PSScriptRoot/ProjectPicker.ps1"
                }

                # ALWAYS create a fresh ProjectPicker (don't reuse old instances)
                $projectPicker = [ProjectPicker]::new()
                $projectPicker.SetPosition($this.X + 5, $this.Y + 3)
                $projectPicker.SetSize(40, 15)

                # Get current value from TextInput widget
                $textWidget = $this._fieldWidgets[$field.Name]
                $currentProject = $textWidget.GetText()
                if (-not [string]::IsNullOrWhiteSpace($currentProject)) {
                    $projectPicker._searchText = $currentProject
                }

                # Store fresh ProjectPicker
                $this._fieldWidgets[$field.Name] = $projectPicker

                $this._expandedFieldName = $field.Name
                $this._showFieldWidgets = $true
                # NOTE: NeedsClear NOT set - widget renders as overlay without clearing screen
                return
            }

            $this._expandedFieldName = $field.Name
            $this._showFieldWidgets = $true

            # Reset widget state for non-date/project fields
            if ($field.Type -ne 'date' -and $field.Type -ne 'project') {
                $widget = $this._fieldWidgets[$field.Name]
                $widget.IsConfirmed = $false
                $widget.IsCancelled = $false
            }
        }
    }

    <#
    .SYNOPSIS
    Validate all fields

    .OUTPUTS
    True if all fields valid, False otherwise
    #>
    hidden [bool] _ValidateAllFields() {
        # Write-PmcTuiLog "InlineEditor._ValidateAllFields CALLED - field count: $($this._fields.Count)" "DEBUG"
        $this._validationErrors = @()

        foreach ($field in $this._fields) {
            $fieldName = $field.Name
            $fieldType = $field.Type
            $isRequired = $(if ($field.ContainsKey('Required')) { $field.Required } else { $false })

            $value = $this._GetFieldValue($fieldName, $fieldType)
            # Write-PmcTuiLog "InlineEditor._ValidateAllFields - Field: $fieldName, Type: $fieldType, Required: $isRequired, Value: '$value'" "DEBUG"

            # Check required fields
            if ($isRequired) {
                $isEmpty = $false

                switch ($fieldType) {
                    'text' {
                        $isEmpty = [string]::IsNullOrWhiteSpace($value)
                    }
                    'date' {
                        $isEmpty = ($null -eq $value)
                    }
                    'project' {
                        $isEmpty = [string]::IsNullOrWhiteSpace($value)
                    }
                    'tags' {
                        $isEmpty = ($null -eq $value -or $value.Count -eq 0)
                    }
                    'number' {
                        $isEmpty = ($null -eq $value)
                    }
                }

                if ($isEmpty) {
                    $err = "$($field.Label) is required"
                    # Write-PmcTuiLog "InlineEditor._ValidateAllFields - VALIDATION ERROR: $err" "ERROR"
                    $this._validationErrors += $err
                }
            }

            # Type-specific validation
            if ($fieldType -eq 'number' -and $null -ne $value) {
                $min = $(if ($field.ContainsKey('Min')) { $field.Min } else { [int]::MinValue })
                $max = $(if ($field.ContainsKey('Max')) { $field.Max } else { [int]::MaxValue })

                if ($value -lt $min) {
                    $err = "$($field.Label) must be >= $min"
                    # Write-PmcTuiLog "InlineEditor._ValidateAllFields - VALIDATION ERROR: $err" "ERROR"
                    $this._validationErrors += $err
                }

                if ($value -gt $max) {
                    $err = "$($field.Label) must be <= $max"
                    # Write-PmcTuiLog "InlineEditor._ValidateAllFields - VALIDATION ERROR: $err" "ERROR"
                    $this._validationErrors += $err
                }
            }
        }

        $isValid = $this._validationErrors.Count -eq 0
        # Write-PmcTuiLog "InlineEditor._ValidateAllFields RESULT: isValid=$isValid, errorCount=$($this._validationErrors.Count)" "DEBUG"
        return $isValid
    }

    <#
    .SYNOPSIS
    H-UI-3: Validate a single field in real-time (as user types)
    #>
    hidden [void] _ValidateFieldRealtime([hashtable]$field) {
        $fieldName = $field.Name
        $fieldType = $field.Type
        $isRequired = $(if ($field.ContainsKey('Required')) { $field.Required } else { $false })

        # Get current value
        $value = $this._GetFieldValue($fieldName, $fieldType)

        # Check required fields
        if ($isRequired) {
            $isEmpty = $false

            switch ($fieldType) {
                'text' {
                    $isEmpty = [string]::IsNullOrWhiteSpace($value)
                }
                'date' {
                    $isEmpty = ($null -eq $value)
                }
                'project' {
                    $isEmpty = [string]::IsNullOrWhiteSpace($value)
                }
                'tags' {
                    $isEmpty = ($null -eq $value -or $value.Count -eq 0)
                }
                'number' {
                    $isEmpty = ($null -eq $value)
                }
            }

            if ($isEmpty) {
                $this._fieldErrors[$fieldName] = "$($field.Label) is required"
                return
            }
        }

        # Type-specific validation
        if ($fieldType -eq 'number' -and $null -ne $value) {
            $min = $(if ($field.ContainsKey('Min')) { $field.Min } else { [int]::MinValue })
            $max = $(if ($field.ContainsKey('Max')) { $field.Max } else { [int]::MaxValue })

            if ($value -lt $min) {
                $this._fieldErrors[$fieldName] = "$($field.Label) must be >= $min"
                return
            }

            if ($value -gt $max) {
                $this._fieldErrors[$fieldName] = "$($field.Label) must be <= $max"
                return
            }
        }

        # Field is valid - remove error
        $this._fieldErrors.Remove($fieldName)
    }

    <#
    .SYNOPSIS
    Invoke callback safely
    #>
    hidden [void] _InvokeCallback([scriptblock]$callback, $arg) {
        if ($null -ne $callback) {
            # Check if callback has actual code (not just empty braces)
            $callbackText = $callback.ToString().Trim()
            # Match {} or { } or {  } etc (braces with only whitespace inside)
            if ([string]::IsNullOrWhiteSpace($callbackText) -or $callbackText -match '^\{\s*\}$') {
                # Write-PmcTuiLog "InlineEditor._InvokeCallback: Callback is null/empty, skipping" "DEBUG"
                return
            }

            # if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
            #     Write-PmcTuiLog "InlineEditor._InvokeCallback: Invoking callback with arg type=$($arg.GetType().Name)" "DEBUG"
            # }
            try {
                if ($null -ne $arg) {
                    # Use Invoke-Command with -ArgumentList to pass single arg without array wrapping
                    Invoke-Command -ScriptBlock $callback -ArgumentList (, $arg)
                }
                else {
                    & $callback
                }
                # if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
                #     Write-PmcTuiLog "InlineEditor._InvokeCallback: Callback completed successfully" "DEBUG"
                # }
            }
            catch {
                # Log callback errors but DON'T rethrow - callbacks must never crash the app
                # ENABLED: Log callback errors for debugging
                Write-PmcTuiLog "InlineEditor callback error: $($_.Exception.Message)" "ERROR"
                Write-PmcTuiLog "Callback code: $($callback.ToString().Substring(0, [Math]::Min(200, $callback.ToString().Length)))" "ERROR"
                Write-PmcTuiLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
                # Show error to user in status bar if possible
                if ($global:PmcApp -and $global:PmcApp.CurrentScreen -and $global:PmcApp.CurrentScreen.StatusBar) {
                    $global:PmcApp.CurrentScreen.StatusBar.SetLeftText("Error: $($_.Exception.Message)")
                }
                # DON'T rethrow - form submission callbacks must not crash
            }
        }
    }
}
