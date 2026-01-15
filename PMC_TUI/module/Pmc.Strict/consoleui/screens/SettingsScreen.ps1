using namespace System.Collections.Generic
using namespace System.Text

# SettingsScreen - PMC TUI Settings configuration
# Interactive screen for viewing and modifying PMC settings


Set-StrictMode -Version Latest

# NOTE: PmcScreen is loaded by Start-PmcTUI.ps1 - don't load again
# . "$PSScriptRoot/../PmcScreen.ps1"

# LOW FIX SS-L1, SS-L2, SS-L3: Define constants for column widths and limits
$script:SETTING_NAME_WIDTH = 20
$script:SETTING_VALUE_WIDTH = 30
$global:MIN_PRINTABLE_CHAR = 32
$global:MAX_PRINTABLE_CHAR = 126

<#
.SYNOPSIS
Settings screen for configuring PMC TUI preferences

.DESCRIPTION
Interactive settings screen showing:
- Data file location
- Default project
- Theme selection
- Auto-save settings
- Backup settings
Navigation: Up/Down to select, Enter to edit, Esc to exit
#>
class SettingsScreen : PmcScreen {
    # Data
    [array]$SettingsList = @()
    [int]$SelectedIndex = 0
    [string]$InputMode = 'none'  # 'none', 'edit'
    [string]$InputBuffer = ''
    [int]$EditingIndex = -1

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Options', 'Settings', 'S', {
            # CRITICAL FIX SS-C1: Validate file exists before dot-sourcing
            $scriptPath = "$PSScriptRoot/SettingsScreen.ps1"
            if (-not (Test-Path $scriptPath)) {
                # Write-PmcTuiLog "SettingsScreen.ps1 not found at: $scriptPath" "ERROR"
                throw "SettingsScreen.ps1 not found"
            }
            . $scriptPath
            $global:PmcApp.PushScreen((New-Object -TypeName SettingsScreen))
        }, 20)
    }

    # LOW FIX SS-L4: Extract common initialization to helper method (DRY principle)
    hidden [void] ConfigureScreen() {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Settings"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Up/Down", "Select")
        $this.Footer.AddShortcut("Enter", "Edit")
        $this.Footer.AddShortcut("Esc", "Back")

        # NOTE: _SetupMenus() removed - MenuRegistry handles menu population via static RegisterMenuItems()
        # Old pattern was adding duplicate/misplaced menu items
    }

    # Constructor
    SettingsScreen() : base("Settings", "Settings") {
        $this.ConfigureScreen()
    }

    # Constructor with container (DI-enabled)
    SettingsScreen([object]$container) : base("Settings", "Settings", $container) {
        $this.ConfigureScreen()
    }

    [void] LoadData() {
        # SS-M2 FIX: Defensive check layering documentation
        # LAYER 1: Default values are set BEFORE external function calls
        # This ensures settings always have valid values even if external functions fail
        $dataFile = "~/.pmc/data.json"
        try {
            # LAYER 2: Try to get actual value from external function
            # HIGH FIX SS-H1: Validate returned path exists and is readable
            $tempPath = Get-PmcTaskFilePath
            if ($null -ne $tempPath -and (Test-Path $tempPath)) {
                $dataFile = $tempPath
            } else {
                # Write-PmcTuiLog "SettingsScreen: Get-PmcTaskFilePath returned invalid path: $tempPath" "WARNING"
            }
        } catch {
            # LAYER 3: Silently fall back to default if function fails
            # Write-PmcTuiLog "SettingsScreen: Get-PmcTaskFilePath failed: $($_.Exception.Message)" "WARNING"
        }

        # Same defensive layering for current context
        $currentContext = "inbox"
        try {
            # HIGH FIX SS-H2: Validate returned context against safe values
            $tempContext = Get-PmcCurrentContext
            if ($null -ne $tempContext -and -not [string]::IsNullOrWhiteSpace($tempContext)) {
                $currentContext = $tempContext
            } else {
                # Write-PmcTuiLog "SettingsScreen: Get-PmcCurrentContext returned invalid value" "WARNING"
            }
        } catch {
            # Use default if Get-PmcCurrentContext fails
            # Write-PmcTuiLog "SettingsScreen: Get-PmcCurrentContext failed: $($_.Exception.Message)" "WARNING"
        }

        $this.SettingsList = @(
            @{
                name = "Data File"
                key = "dataFile"
                value = $dataFile
                editable = $false
                description = "Location of PMC data storage"
            }
            @{
                name = "Default Project"
                key = "defaultProject"
                value = $currentContext
                editable = $true
                description = "Default project for new tasks"
            }
            @{
                name = "Auto-save"
                key = "autoSave"
                value = "enabled"
                editable = $false
                description = "Automatically save changes"
            }
            @{
                name = "Theme"
                key = "theme"
                value = "default"
                editable = $false
                action = "launchThemeEditor"
                description = "UI color theme (press Enter to change)"
            }
            @{
                name = "TUI Version"
                key = "version"
                value = "1.0.0"
                editable = $false
                description = "PMC TUI version"
            }
        )

        $this.ShowStatus("$($this.SettingsList.Count) settings available")
    }

    [string] RenderContent() {
        $sb = [System.Text.StringBuilder]::new(4096)

        if (-not $this.LayoutManager) {
            return $sb.ToString()
        }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors
        $textColor = $this.Header.GetThemedFg('Foreground.Field')
        $highlightColor = $this.Header.GetThemedFg('Foreground.FieldFocused')
        $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
        $selectedBg = $this.Header.GetThemedBg('Background.FieldFocused', 80, 0)
        $selectedFg = $this.Header.GetThemedFg('Foreground.Field')
        $cursorColor = $this.Header.GetThemedAnsi('Accent', $false)
        $headerColor = $this.Header.GetThemedFg('Foreground.Muted')
        $reset = "`e[0m"

        # Column widths
        # MEDIUM FIX SS-M3: Use script-level constants for column widths
        $nameWidth = $script:SETTING_NAME_WIDTH
        $valueWidth = $script:SETTING_VALUE_WIDTH
        $descWidth = $contentRect.Width - $nameWidth - $valueWidth - 10

        # Render column headers
        $headerY = $this.Header.Y + 3
        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $headerY))
        $sb.Append($headerColor)
        $sb.Append("SETTING".PadRight($nameWidth))
        $sb.Append("VALUE".PadRight($valueWidth))
        $sb.Append("DESCRIPTION")
        $sb.Append($reset)

        # Render settings rows
        $startY = $headerY + 2
        $maxLines = $contentRect.Height - 4

        for ($i = 0; $i -lt [Math]::Min($this.SettingsList.Count, $maxLines); $i++) {
            $setting = $this.SettingsList[$i]
            $y = $startY + $i
            $isSelected = ($i -eq $this.SelectedIndex)
            $isEditing = ($i -eq $this.EditingIndex) -and ($this.InputMode -eq 'edit')

            # Cursor
            $sb.Append($this.Header.BuildMoveTo($contentRect.X + 2, $y))
            if ($isSelected) {
                $sb.Append($cursorColor)
                $cursorChar = $(if ($isEditing) { "E" } else { ">" })
                $sb.Append($cursorChar)
                $sb.Append($reset)
            } else {
                $sb.Append(" ")
            }

            # Setting name column
            $x = $contentRect.X + 4
            $sb.Append($this.Header.BuildMoveTo($x, $y))
            if ($isSelected -and -not $isEditing) {
                $sb.Append($selectedBg)
                $sb.Append($selectedFg)
            } else {
                $sb.Append($textColor)
            }
            $displayName = $setting.name
            if ($displayName.Length -gt $nameWidth) {
                $displayName = $displayName.Substring(0, $nameWidth - 3) + "..."
            }
            $sb.Append($displayName.PadRight($nameWidth))
            $sb.Append($reset)
            $x += $nameWidth

            # Value column
            $sb.Append($this.Header.BuildMoveTo($x, $y))
            if ($isEditing) {
                # Show edit buffer
                $sb.Append($cursorColor)
                $sb.Append(($this.InputBuffer + "_").PadRight($valueWidth))
                $sb.Append($reset)
            } else {
                $sb.Append($highlightColor)
                $displayValue = $setting.value
                if ($displayValue.Length -gt $valueWidth) {
                    $displayValue = $displayValue.Substring(0, $valueWidth - 3) + "..."
                }
                $sb.Append($displayValue.PadRight($valueWidth))
                $sb.Append($reset)
            }
            $x += $valueWidth

            # Description column
            $sb.Append($this.Header.BuildMoveTo($x, $y))
            $sb.Append($mutedColor)
            $displayDesc = $setting.description
            if ($displayDesc.Length -gt $descWidth) {
                $displayDesc = $displayDesc.Substring(0, $descWidth - 3) + "..."
            }
            $sb.Append($displayDesc)
            $sb.Append($reset)
        }

        return $sb.ToString()
    }

    # New engine-based rendering method
    [void] RenderContentToEngine([object]$engine) {
        if (-not $this.LayoutManager) { return }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors (using Int versions for engine)
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.Field')
        $cursorColor = $this.Header.GetThemedColorInt('Foreground.Accent')
        $headerColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')

        # Column widths
        $nameWidth = $script:SETTING_NAME_WIDTH
        $valueWidth = $script:SETTING_VALUE_WIDTH
        $descWidth = $contentRect.Width - $nameWidth - $valueWidth - 10

        # Render column headers
        $headerY = $contentRect.Y + 1
        $engine.WriteAt($contentRect.X + 4, $headerY, "SETTING".PadRight($nameWidth), $headerColor, $bg)
        $engine.WriteAt($contentRect.X + 4 + $nameWidth, $headerY, "VALUE".PadRight($valueWidth), $headerColor, $bg)
        $engine.WriteAt($contentRect.X + 4 + $nameWidth + $valueWidth, $headerY, "DESCRIPTION", $headerColor, $bg)

        # Render settings rows
        $startY = $headerY + 2
        $maxLines = $contentRect.Height - 4

        for ($i = 0; $i -lt [Math]::Min($this.SettingsList.Count, $maxLines); $i++) {
            $setting = $this.SettingsList[$i]
            $y = $startY + $i
            $isSelected = ($i -eq $this.SelectedIndex)
            $isEditing = ($i -eq $this.EditingIndex) -and ($this.InputMode -eq 'edit')

            $rowBg = $(if ($isSelected) { $selectedBg } else { $bg })
            $rowFg = $(if ($isSelected) { $selectedFg } else { $textColor })

            # Cursor
            if ($isSelected) {
                $cursorChar = $(if ($isEditing) { "E" } else { ">" })
                $engine.WriteAt($contentRect.X + 2, $y, $cursorChar, $cursorColor, $bg)
            } else {
                $engine.WriteAt($contentRect.X + 2, $y, " ", $bg, $bg)
            }

            # Setting name column
            $x = $contentRect.X + 4
            $displayName = $setting.name
            if ($displayName.Length -gt $nameWidth) {
                $displayName = $displayName.Substring(0, $nameWidth - 3) + "..."
            }
            $engine.WriteAt($x, $y, $displayName.PadRight($nameWidth), $rowFg, $rowBg)
            $x += $nameWidth

            # Value column
            if ($isEditing) {
                $editValue = ($this.InputBuffer + "_").PadRight($valueWidth)
                if ($editValue.Length -gt $valueWidth) {
                    $editValue = $editValue.Substring(0, $valueWidth)
                }
                $engine.WriteAt($x, $y, $editValue, $cursorColor, $bg)
            } else {
                $displayValue = $setting.value
                if ($displayValue.Length -gt $valueWidth) {
                    $displayValue = $displayValue.Substring(0, $valueWidth - 3) + "..."
                }
                $engine.WriteAt($x, $y, $displayValue.PadRight($valueWidth), $highlightColor, $rowBg)
            }
            $x += $valueWidth

            # Description column
            $displayDesc = $setting.description
            if ($displayDesc.Length -gt $descWidth) {
                $displayDesc = $displayDesc.Substring(0, $descWidth - 3) + "..."
            }
            $engine.WriteAt($x, $y, $displayDesc, $mutedColor, $bg)
        }
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # Handle input mode
        if ($this.InputMode -eq 'edit') {
            return $this._HandleEditMode($keyInfo)
        }

        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this.SelectedIndex -gt 0) {
                    $this.SelectedIndex--
                }
                return $true
            }
            'DownArrow' {
                if ($this.SelectedIndex -lt ($this.SettingsList.Count - 1)) {
                    $this.SelectedIndex++
                }
                return $true
            }
            'Enter' {
                if ($this.SettingsList.Count -gt 0) {
                    $this._StartEdit()
                }
                return $true
            }
            'Escape' {
                # Go back to previous screen
                if ($global:PmcApp) {
                    $global:PmcApp.PopScreen()
                }
                return $true
            }
        }
        return $false
    }

    hidden [void] _StartEdit() {
        $setting = $this.SettingsList[$this.SelectedIndex]

        # Check if this setting has a special action
        if ($setting.action) {
            switch ($setting.action) {
                'launchThemeEditor' {
                    # SS-M1 FIX: Enhanced try-catch with comprehensive error handling
                    # Lazy-load Theme Editor screen
                    try {
                        # Validate file exists before dot-sourcing
                        $themeEditorPath = "$PSScriptRoot/ThemeEditorScreen.ps1"
                        if (-not (Test-Path $themeEditorPath)) {
                            throw "ThemeEditorScreen.ps1 not found at expected path: $themeEditorPath"
                        }

                        . $themeEditorPath

                        # HIGH FIX SET-H1: Use try-catch around class instantiation instead of PSTypeName check
                        # PSTypeName check may not work reliably in all PowerShell versions
                        if ($global:PmcApp) {
                            try {
                                $themeScreen = New-Object ThemeEditorScreen
                            } catch {
                                throw "ThemeEditorScreen class not available after loading file: $_"
                            }
                            if ($null -eq $themeScreen) {
                                throw "ThemeEditorScreen constructor returned null"
                            }
                            $global:PmcApp.PushScreen($themeScreen)
                        } else {
                            throw "PmcApp global variable is not available"
                        }
                    } catch {
                        try { $this.ShowError("Failed to load theme editor: $($_.Exception.Message)") } catch { }
                        # Write-PmcTuiLog "Failed to load ThemeEditorScreen: $_" "ERROR"
                        # Write-PmcTuiLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
                    }
                    return
                }
            }
        }

        # SS-M2 FIX: Defensive check layering - verify setting is editable
        if (-not $setting.editable) {
            # LAYER 1: Try to show error to user via UI
            # LAYER 2: Catch and suppress any UI errors (ShowError might fail if screen not active)
            try { $this.ShowError("$($setting.name) is read-only") } catch { }
            return
        }

        $this.InputMode = 'edit'
        $this.EditingIndex = $this.SelectedIndex
        $this.InputBuffer = $setting.value
        # Defensive layer: Protect against ShowStatus failures
        try { $this.ShowStatus("Edit value (Enter: save, Esc: cancel)") } catch { }
    }

    hidden [bool] _HandleEditMode([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'Escape' {
                $this._CancelEdit()
                return $true
            }
            'Enter' {
                $this._SaveEdit()
                return $true
            }
            'Backspace' {
                if ($this.InputBuffer.Length > 0) {
                    $this.InputBuffer = $this.InputBuffer.Substring(0, $this.InputBuffer.Length - 1)
                }
                return $true
            }
            default {
                # EDGE FIX SS-E1: Use script-level constants for printable character range
                if ($keyInfo.KeyChar -ge $global:MIN_PRINTABLE_CHAR -and $keyInfo.KeyChar -le $global:MAX_PRINTABLE_CHAR) {
                    $this.InputBuffer += $keyInfo.KeyChar
                }
                return $true
            }
        }
        return $false  # Fallback return
    }

    hidden [void] _SaveEdit() {
        $setting = $this.SettingsList[$this.EditingIndex]
        $oldValue = $setting.value
        $newValue = $this.InputBuffer

        # CRITICAL FIX SS-C2: Validate input before assignment
        if ($null -eq $newValue) {
            # Write-PmcTuiLog "SettingsScreen: Cannot set null value for $($setting.key)" "ERROR"
            $this.ShowMessage("Invalid value", "error")
            return
        }

        # Update the setting value
        $setting.value = $newValue

        # SS-M2 FIX: Defensive check layering documentation for setting persistence
        # LAYER 1: Optimistically update in-memory value first
        # LAYER 2: Try to persist to backend based on setting type
        # LAYER 3: Revert in-memory value if persistence fails
        # LAYER 4: Show user-friendly error message
        # SS-H1 FIX: Apply the setting based on key with proper persistence for each editable setting
        switch ($setting.key) {
            'defaultProject' {
                try {
                    # Check if Set-PmcFocus command exists
                    if (-not (Get-Command -Name 'Set-PmcFocus' -ErrorAction SilentlyContinue)) {
                        throw "Set-PmcFocus command not available"
                    }
                    # Use Set-PmcFocus to change the current context
                    # Create proper PmcCommandContext with project name in FreeText
                    $context = New-Object -TypeName PmcCommandContext -ArgumentList 'focus', 'set'
                    $context.FreeText = @($newValue)
                    Set-PmcFocus -Context $context
                    $this.ShowSuccess("Default project updated to '$newValue'")
                } catch {
                    $this.ShowError("Failed to set default project: $_")
                    # Revert the value
                    $setting.value = $oldValue
                }
            }
            'autoSave' {
                # TODO: Implement persistence for auto-save setting
                # For now, show warning that this setting is not persisted
                $this.ShowError("Auto-save setting persistence not yet implemented")
                $setting.value = $oldValue
            }
            default {
                # Default case: Warn that persistence is not implemented
                # This prevents false success messages for settings without persistence logic
                $this.ShowError("Persistence not implemented for setting '$($setting.name)'. Changes will not be saved.")
                $setting.value = $oldValue
            }
        }

        # Reset edit mode
        $this.InputMode = 'none'
        $this.EditingIndex = -1
        $this.InputBuffer = ''
    }

    hidden [void] _CancelEdit() {
        $this.InputMode = 'none'
        $this.EditingIndex = -1
        $this.InputBuffer = ''
        $this.ShowStatus("Edit cancelled")
    }
}