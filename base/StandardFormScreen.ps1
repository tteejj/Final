# StandardFormScreen.ps1 - Base class for form-based screens
#
# This is the base class for screens that present a single form for data entry:
# - Add Task Screen
# - Add Project Screen
# - Settings Screen
# - Edit Configuration Screen
#
# Provides:
# - InlineEditor integration (multi-field form)
# - TaskStore integration (save data on submit)
# - Validation before submission
# - Cancel/Back navigation
# - Success/Error feedback
#
# Usage:
#   class AddTaskScreen : StandardFormScreen {
#       AddTaskScreen() : base("AddTask", "Add New Task") {}
#
#       [array] GetFields() {
#           return @(
#               @{ Name='text'; Type='text'; Label='Task'; Required=$true }
#               @{ Name='due'; Type='date'; Label='Due Date' }
#               @{ Name='priority'; Type='number'; Label='Priority'; Min=0; Max=5; Value=3 }
#           )
#       }
#
#       [void] OnSubmit($values) {
#           $this.Store.AddTask($values)
#           $this.NavigateBack()
#       }
#   }

using namespace System
using namespace System.Collections.Generic
using namespace System.Text

# Load dependencies
# NOTE: These are now loaded by the launcher script in the correct order.
# Commenting out to avoid circular dependency issues.
# $scriptDir = Split-Path -Parent $PSScriptRoot
# . "$scriptDir/PmcScreen.ps1"
# . "$scriptDir/widgets/InlineEditor.ps1"
# . "$scriptDir/services/TaskStore.ps1"

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Base class for form-based screens in PMC TUI

.DESCRIPTION
StandardFormScreen provides a complete form-entry experience with:
- InlineEditor widget for multi-field forms
- TaskStore integration for data persistence
- Validation before submission
- Success/error feedback
- Cancel/back navigation
- Event-driven callbacks

Abstract Methods (override in subclasses):
- GetFields() - Define form field configuration
- OnSubmit($values) - Handle form submission

Optional Overrides:
- OnCancel() - Handle form cancellation (default: navigate back)
- OnValidationFailed($errors) - Handle validation errors
- GetEntityType() - Return 'task', 'project', or 'timelog' for store operations
- GetSubmitLabel() - Return label for submit action (default: "Save")

.EXAMPLE
class AddTaskScreen : StandardFormScreen {
    AddTaskScreen() : base("AddTask", "Add New Task") {}

    [array] GetFields() {
        return @(
            @{ Name='text'; Type='text'; Label='Task'; Required=$true }
            @{ Name='due'; Type='date'; Label='Due Date' }
        )
    }

    [void] OnSubmit($values) {
        if ($this.Store.AddTask($values)) {
            $this.StatusBar.SetLeftText("Task added successfully")
            Start-Sleep -Milliseconds 500
            $this.NavigateBack()
        } else {
            $this.StatusBar.SetLeftText("Failed to add task: $($this.Store.LastError)")
        }
    }
}
#>
class StandardFormScreen : PmcScreen {
    # === Core Components ===
    [InlineEditor]$Editor = $null
    [TaskStore]$Store = $null

    # === State ===
    [bool]$IsSubmitting = $false
    [string[]]$ValidationErrors = @()

    # === Configuration ===
    [bool]$AllowCancel = $true
    [string]$SubmitLabel = "Save"

    # === Constructor (backward compatible - no container) ===
    StandardFormScreen([string]$key, [string]$title) : base($key, $title) {
        # Initialize components
        $this._InitializeComponents()
    }

    # === Constructor (with ServiceContainer) ===
    StandardFormScreen([string]$key, [string]$title, [object]$container) : base($key, $title, $container) {
        # Initialize components
        $this._InitializeComponents()
    }

    # === Abstract Methods (MUST override) ===

    <#
    .SYNOPSIS
    Get form field configuration (ABSTRACT - must override)

    .OUTPUTS
    Array of field hashtables for InlineEditor
    #>
    [array] GetFields() {
        throw "GetFields() must be implemented in subclass"
    }

    <#
    .SYNOPSIS
    Handle form submission (ABSTRACT - must override)

    .PARAMETER values
    Hashtable of field values from form
    #>
    [void] OnSubmit($values) {
        throw "OnSubmit() must be implemented in subclass"
    }

    # === Optional Override Methods ===

    <#
    .SYNOPSIS
    Get entity type for store operations ('task', 'project', 'timelog', 'custom')

    .OUTPUTS
    Entity type string
    #>
    [string] GetEntityType() {
        # Default to 'custom' - override if using task/project/timelog directly
        return 'custom'
    }

    <#
    .SYNOPSIS
    Handle form cancellation (optional override)
    #>
    [void] OnCancel() {
        # Default: navigate back
        $this.NavigateBack()
    }

    <#
    .SYNOPSIS
    Handle validation failure (optional override)

    .PARAMETER errors
    Array of validation error messages
    #>
    [void] OnValidationFailed($errors) {
        # Default: show first error in status bar
        if ($this.StatusBar -and $errors.Count -gt 0) {
            $this.StatusBar.SetLeftText("Validation error: $($errors[0])")
        }
    }

    <#
    .SYNOPSIS
    Get submit button label (optional override)

    .OUTPUTS
    Submit button label string
    #>
    [string] GetSubmitLabel() {
        return $this.SubmitLabel
    }

    # === Component Initialization ===

    <#
    .SYNOPSIS
    Initialize all components
    #>
    hidden [void] _InitializeComponents() {
        # Get terminal size
        $termSize = $this._GetTerminalSize()
        $this.TermWidth = $termSize.Width
        $this.TermHeight = $termSize.Height

        # Initialize TaskStore singleton
        $this.Store = [TaskStore]::GetInstance()

        # Initialize InlineEditor
        $this.Editor = [InlineEditor]::new()
        $editorWidth = [Math]::Min(80, $this.TermWidth - 10)
        $editorHeight = [Math]::Min(30, $this.TermHeight - 8)
        $editorX = [Math]::Floor(($this.TermWidth - $editorWidth) / 2)
        $editorY = 4
        $this.Editor.SetPosition($editorX, $editorY)
        $this.Editor.SetSize($editorWidth, $editorHeight)
        $this.Editor.Title = $this.ScreenTitle

        # Wire up editor events
        $this.Editor.OnConfirmed = {
            param($values)
            $this._HandleSubmit($values)
        }

        $this.Editor.OnCancelled = {
            $this._HandleCancel()
        }

        $this.Editor.OnValidationFailed = {
            param($errors)
            $this.ValidationErrors = $errors
            $this.OnValidationFailed($errors)
        }
    }

    # === Lifecycle Methods ===

    <#
    .SYNOPSIS
    Called when screen enters view
    #>
    [void] OnEnter() {
        $this.IsActive = $true

        # Set form fields
        $fields = $this.GetFields()
        $this.Editor.SetFields($fields)

        # Update header breadcrumb
        if ($this.Header) {
            $this.Header.SetBreadcrumb(@("Home", $this.ScreenTitle))
        }

        # Update status bar
        if ($this.StatusBar) {
            $submitLabelText = $this.GetSubmitLabel()
            $this.StatusBar.SetLeftText("Fill out the form and press Enter to $submitLabelText")
        }

        # Reset state
        $this.IsSubmitting = $false
        $this.ValidationErrors = @()
    }

    <#
    .SYNOPSIS
    Called when screen exits view
    #>
    [void] OnDoExit() {
        $this.IsActive = $false
    }

    # === Form Submission ===

    <#
    .SYNOPSIS
    Handle form submission

    .PARAMETER values
    Field values from InlineEditor
    #>
    hidden [void] _HandleSubmit($values) {
        if ($this.IsSubmitting) {
            # Prevent double-submit
            return
        }

        $this.IsSubmitting = $true

        try {
            # Clear previous errors
            $this.ValidationErrors = @()

            # Show submitting status
            if ($this.StatusBar) {
                $this.StatusBar.SetLeftText("Submitting...")
            }

            # Call subclass implementation
            $this.OnSubmit($values)
        }
        finally {
            $this.IsSubmitting = $false
        }
    }

    <#
    .SYNOPSIS
    Handle form cancellation
    #>
    hidden [void] _HandleCancel() {
        if (-not $this.AllowCancel) {
            # Cancel not allowed
            if ($this.StatusBar) {
                $this.StatusBar.SetLeftText("Cannot cancel this form")
            }
            return
        }

        # Call subclass implementation
        $this.OnCancel()
    }

    # === Navigation ===

    <#
    .SYNOPSIS
    Navigate back to previous screen
    #>
    [void] NavigateBack() {
        # This will be implemented by NavigationManager integration
        # For now, set a flag that the application can check
        $this.IsActive = $false
    }

    # === Input Handling ===

    <#
    .SYNOPSIS
    Handle keyboard input

    .PARAMETER keyInfo
    ConsoleKeyInfo from [Console]::ReadKey($true)

    .OUTPUTS
    True if input was handled, False otherwise
    #>
    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # Route all input to editor
        return $this.Editor.HandleInput($keyInfo)
    }

    # === Rendering ===

    <#
    .SYNOPSIS
    Render the screen content area

    .OUTPUTS
    ANSI string ready for display
    #>
    <#
    .SYNOPSIS
    Render content area directly to engine
    #>
    [void] RenderContentToEngine([object]$engine) {
        if ($null -ne $this.Editor) {
            $this.Editor.RenderToEngine($engine)
        }

        # Render validation errors
        if ($this.ValidationErrors.Count -gt 0) {
            $errorY = $this.Editor.Y + $this.Editor.Height + 1
            $errorX = $this.Editor.X
            
            # Colors
            $errorFg = $this.Header.GetThemedColorInt('Foreground.Error')
            $bg = $this.Header.GetThemedColorInt('Background.Primary')
            
            $engine.WriteAt($errorX, $errorY, "Validation Errors:", $errorFg, $bg)
            
            for ($i = 0; $i -lt [Math]::Min(3, $this.ValidationErrors.Count); $i++) {
                $errorMsgY = $errorY + $i + 1
                $engine.WriteAt($errorX, $errorMsgY, "  - $($this.ValidationErrors[$i])", $errorFg, $bg)
            }
            
            if ($this.ValidationErrors.Count -gt 3) {
                $moreY = $errorY + 4
                $engine.WriteAt($errorX, $moreY, "  ... and $($this.ValidationErrors.Count - 3) more errors", $errorFg, $bg)
            }
        }
    }

    [string] Render() { return "" }
    [string] RenderContent() { return "" }

    # === Helper Methods ===

    <#
    .SYNOPSIS
    Get terminal size

    .OUTPUTS
    Hashtable with Width and Height properties
    #>
    hidden [hashtable] _GetTerminalSize() {
        try {
            $width = [Console]::WindowWidth
            $height = [Console]::WindowHeight
            return @{ Width = $width; Height = $height }
        }
        catch {
            # Default size if console not available
            return @{ Width = 120; Height = 40 }
        }
    }

    # === Utility Methods for Subclasses ===

    <#
    .SYNOPSIS
    Show success message and navigate back after delay

    .PARAMETER message
    Success message to display

    .PARAMETER delayMs
    Delay in milliseconds before navigating back (default 1000)
    #>
    [void] ShowSuccessAndNavigateBack([string]$message, [int]$delayMs = 1000) {
        if ($this.StatusBar) {
            $successColor = "`e[32m"  # Green
            $reset = "`e[0m"
            $this.StatusBar.SetLeftText("$successColor$message$reset")
        }

        Start-Sleep -Milliseconds $delayMs
        $this.NavigateBack()
    }

    <#
    .SYNOPSIS
    Show error message

    .PARAMETER message
    Error message to display
    #>
    [void] ShowError([string]$message) {
        if ($this.StatusBar) {
            $errorColor = "`e[31m"  # Red
            $reset = "`e[0m"
            $this.StatusBar.SetLeftText("$errorColor$message$reset")
        }
    }

    <#
    .SYNOPSIS
    Get current field values from editor

    .OUTPUTS
    Hashtable of current field values
    #>
    [hashtable] GetCurrentValues() {
        return $this.Editor.GetValues()
    }

    <#
    .SYNOPSIS
    Set field value in editor

    .PARAMETER fieldName
    Field name

    .PARAMETER value
    New value
    #>
    [void] SetFieldValue([string]$fieldName, $value) {
        # This requires modifying the field definition and re-setting fields
        $fields = $this.GetFields()
        $field = $fields | Where-Object { $_.Name -eq $fieldName } | Select-Object -First 1

        if ($null -ne $field) {
            $field.Value = $value
            $this.Editor.SetFields($fields)
        }
    }
}