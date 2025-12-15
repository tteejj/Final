# StandardDashboard.ps1 - Base class for dashboard-style screens
#
# This is the base class for screens that show multiple widgets/panels:
# - Main Dashboard (task summary + project stats + time tracking)
# - Analytics Dashboard (charts + metrics)
# - Reports Dashboard (multiple report panels)
#
# Provides:
# - Multi-widget layout (add panels dynamically)
# - Tab/Arrow key navigation between widgets
# - Focus management (one widget focused at a time)
# - TaskStore integration (auto-refresh widgets on data changes)
# - Flexible layout (auto-arrange or manual positioning)
#
# Usage:
#   class MainDashboard : StandardDashboard {
#       MainDashboard() : base("Dashboard", "PMC Dashboard") {}
#
#       [void] InitializeWidgets() {
#           # Add task summary widget
#           $taskWidget = [TaskSummaryWidget]::new()
#           $this.AddWidget($taskWidget, 0, 0, 50, 10)
#
#           # Add project stats widget
#           $projectWidget = [ProjectStatsWidget]::new()
#           $this.AddWidget($projectWidget, 52, 0, 50, 10)
#
#           # Add time tracking widget
#           $timeWidget = [TimeTrackingWidget]::new()
#           $this.AddWidget($timeWidget, 0, 12, 102, 8)
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
# . "$scriptDir/widgets/PmcWidget.ps1"
# . "$scriptDir/widgets/PmcPanel.ps1"
# . "$scriptDir/services/TaskStore.ps1"

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Base class for dashboard-style screens with multiple widgets

.DESCRIPTION
StandardDashboard provides a complete dashboard experience with:
- Multiple widget/panel support
- Tab/arrow key navigation between widgets
- Focus management (one widget active at a time)
- TaskStore integration for automatic data refresh
- Auto-layout or manual positioning
- Widget lifecycle management
- Event-driven updates

Abstract Methods (override in subclasses):
- InitializeWidgets() - Create and add dashboard widgets

Optional Overrides:
- OnWidgetFocusChanged($oldWidget, $newWidget) - Handle focus changes
- GetLayoutMode() - Return 'auto' or 'manual' (default: 'manual')
- OnDataChanged() - Handle store data changes (refresh widgets)

Widget Management:
- AddWidget($widget, $x, $y, $width, $height) - Add widget with position
- AddWidget($widget) - Add widget with auto-layout (if layout mode is 'auto')
- RemoveWidget($widget) - Remove widget
- FocusWidget($index) - Set focus to widget by index
- FocusNextWidget() - Move focus to next widget
- FocusPreviousWidget() - Move focus to previous widget

.EXAMPLE
class MainDashboard : StandardDashboard {
    MainDashboard() : base("Dashboard", "PMC Dashboard") {}

    [void] InitializeWidgets() {
        # Task summary (top-left)
        $taskWidget = [TaskSummaryWidget]::new()
        $this.AddWidget($taskWidget, 0, 3, 50, 10)

        # Project stats (top-right)
        $projectWidget = [ProjectStatsWidget]::new()
        $this.AddWidget($projectWidget, 52, 3, 50, 10)

        # Time tracking (bottom)
        $timeWidget = [TimeTrackingWidget]::new()
        $this.AddWidget($timeWidget, 0, 15, 102, 8)
    }
}
#>
class StandardDashboard : PmcScreen {
    # === Core Components ===
    [TaskStore]$Store = $null
    [List[object]]$Widgets = [List[object]]::new()

    # === State ===
    [int]$FocusedWidgetIndex = -1
    [string]$LayoutMode = "manual"  # 'auto' or 'manual'

    # === Auto-Layout State ===
    hidden [int]$_autoLayoutX = 0
    hidden [int]$_autoLayoutY = 3
    hidden [int]$_autoLayoutMaxHeight = 0

    # === Configuration ===
    [bool]$AllowWidgetNavigation = $true
    [int]$WidgetPadding = 2  # Padding between widgets in auto-layout

    # === Constructors ===

    # Legacy constructor
    StandardDashboard([string]$key, [string]$title) : base($key, $title) {
        # Initialize components
        $this._InitializeComponents()
    }

    # Container constructor
    StandardDashboard([string]$key, [string]$title, [object]$container) : base($key, $title, $container) {
        # Initialize components
        $this._InitializeComponents()
    }

    # === Abstract Methods (MUST override) ===

    <#
    .SYNOPSIS
    Initialize dashboard widgets (ABSTRACT - must override)
    #>
    [void] InitializeWidgets() {
        throw "InitializeWidgets() must be implemented in subclass"
    }

    # === Optional Override Methods ===

    <#
    .SYNOPSIS
    Get layout mode ('auto' or 'manual')

    .OUTPUTS
    Layout mode string
    #>
    [string] GetLayoutMode() {
        return $this.LayoutMode
    }

    <#
    .SYNOPSIS
    Handle widget focus change (optional override)

    .PARAMETER oldWidget
    Previously focused widget

    .PARAMETER newWidget
    Newly focused widget
    #>
    [void] OnWidgetFocusChanged($oldWidget, $newWidget) {
        # Default: update status bar
        if ($null -ne $newWidget -and $this.StatusBar) {
            $widgetName = $(if ($newWidget.PanelTitle) { $newWidget.PanelTitle } else { "Widget" })
            $this.StatusBar.SetLeftText("Focused: $widgetName")
        }
    }

    <#
    .SYNOPSIS
    Handle data changes from store (optional override)
    #>
    [void] OnDataChanged() {
        # Default: refresh all widgets
        $this.RefreshAllWidgets()
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

        # Wire up store events for auto-refresh
        $this.Store.OnDataChanged = {
            $this.OnDataChanged()
        }

        # Set layout mode
        $this.LayoutMode = $this.GetLayoutMode()
    }

    # === Lifecycle Methods ===

    <#
    .SYNOPSIS
    Called when screen enters view
    #>
    [void] OnEnter() {
        $this.IsActive = $true

        # Clear existing widgets
        $this.Widgets.Clear()
        $this.FocusedWidgetIndex = -1

        # Reset auto-layout state
        $this._autoLayoutX = 0
        $this._autoLayoutY = 3
        $this._autoLayoutMaxHeight = 0

        # Initialize widgets (subclass implementation)
        $this.InitializeWidgets()

        # Focus first widget if any exist
        if ($this.Widgets.Count -gt 0) {
            $this.FocusWidget(0)
        }

        # Update header breadcrumb
        if ($this.Header) {
            $this.Header.SetBreadcrumb(@("Home", $this.ScreenTitle))
        }

        # Update status bar
        if ($this.StatusBar) {
            $widgetCount = $this.Widgets.Count
            $this.StatusBar.SetLeftText("$widgetCount widgets | Tab: Next widget")
        }
    }

    <#
    .SYNOPSIS
    Called when screen exits view
    #>
    [void] OnDoExit() {
        $this.IsActive = $false

        # Cleanup widget resources
        foreach ($widget in $this.Widgets) {
            if ($widget.PSObject.Methods['Dispose']) {
                $widget.Dispose()
            }
        }

        $this.Widgets.Clear()
        $this.FocusedWidgetIndex = -1
    }

    # === Widget Management ===

    <#
    .SYNOPSIS
    Add a widget to the dashboard

    .PARAMETER widget
    Widget instance (must inherit from PmcWidget or PmcPanel)

    .PARAMETER x
    X position (optional, required for manual layout)

    .PARAMETER y
    Y position (optional, required for manual layout)

    .PARAMETER width
    Widget width (optional, required for manual layout)

    .PARAMETER height
    Widget height (optional, required for manual layout)
    #>
    [void] AddWidget($widget, [int]$x = -1, [int]$y = -1, [int]$width = -1, [int]$height = -1) {
        if ($null -eq $widget) {
            return
        }

        # Set position and size based on layout mode
        if ($this.LayoutMode -eq 'manual') {
            if ($x -ge 0 -and $y -ge 0 -and $width -gt 0 -and $height -gt 0) {
                $widget.SetPosition($x, $y)
                $widget.SetSize($width, $height)
            }
            else {
                throw "Manual layout requires x, y, width, height parameters"
            }
        }
        elseif ($this.LayoutMode -eq 'auto') {
            # Auto-layout: place widgets left-to-right, wrap to next row
            $this._AutoLayoutWidget($widget, $width, $height)
        }

        # Add to widgets list
        $this.Widgets.Add($widget)
    }

    <#
    .SYNOPSIS
    Auto-layout a widget

    .PARAMETER widget
    Widget instance

    .PARAMETER width
    Widget width (required for auto-layout)

    .PARAMETER height
    Widget height (required for auto-layout)
    #>
    hidden [void] _AutoLayoutWidget($widget, [int]$width, [int]$height) {
        if ($width -le 0 -or $height -le 0) {
            throw "Auto-layout requires width and height parameters"
        }

        # Check if widget fits in current row
        if ($this._autoLayoutX + $width -gt $this.TermWidth) {
            # Wrap to next row
            $this._autoLayoutX = 0
            $this._autoLayoutY += $this._autoLayoutMaxHeight + $this.WidgetPadding
            $this._autoLayoutMaxHeight = 0
        }

        # Position widget
        $widget.SetPosition($this._autoLayoutX, $this._autoLayoutY)
        $widget.SetSize($width, $height)

        # Update auto-layout state
        $this._autoLayoutX += $width + $this.WidgetPadding
        $this._autoLayoutMaxHeight = [Math]::Max($this._autoLayoutMaxHeight, $height)
    }

    <#
    .SYNOPSIS
    Remove a widget from the dashboard

    .PARAMETER widget
    Widget instance to remove
    #>
    [void] RemoveWidget($widget) {
        if ($null -eq $widget) {
            return
        }

        $index = $this.Widgets.IndexOf($widget)
        if ($index -ge 0) {
            $this.Widgets.RemoveAt($index)

            # Adjust focused widget index
            if ($this.FocusedWidgetIndex -eq $index) {
                if ($this.Widgets.Count -gt 0) {
                    $this.FocusWidget(0)
                }
                else {
                    $this.FocusedWidgetIndex = -1
                }
            }
            elseif ($this.FocusedWidgetIndex -gt $index) {
                $this.FocusedWidgetIndex--
            }

            # Cleanup widget
            if ($widget.PSObject.Methods['Dispose']) {
                $widget.Dispose()
            }
        }
    }

    <#
    .SYNOPSIS
    Get widget by index

    .PARAMETER index
    Widget index

    .OUTPUTS
    Widget instance or $null if index out of range
    #>
    [object] GetWidget([int]$index) {
        if ($index -ge 0 -and $index -lt $this.Widgets.Count) {
            return $this.Widgets[$index]
        }
        return $null
    }

    <#
    .SYNOPSIS
    Get currently focused widget

    .OUTPUTS
    Focused widget instance or $null if no widget focused
    #>
    [object] GetFocusedWidget() {
        return $this.GetWidget($this.FocusedWidgetIndex)
    }

    # === Focus Management ===

    <#
    .SYNOPSIS
    Set focus to widget by index

    .PARAMETER index
    Widget index
    #>
    [void] FocusWidget([int]$index) {
        if ($index -lt 0 -or $index -ge $this.Widgets.Count) {
            return
        }

        $oldWidget = $this.GetFocusedWidget()
        $this.FocusedWidgetIndex = $index
        $newWidget = $this.GetFocusedWidget()

        # Update widget focus states
        if ($null -ne $oldWidget -and $oldWidget.PSObject.Properties['IsFocused']) {
            $oldWidget.IsFocused = $false
        }

        if ($null -ne $newWidget -and $newWidget.PSObject.Properties['IsFocused']) {
            $newWidget.IsFocused = $true
        }

        # Fire focus change event
        $this.OnWidgetFocusChanged($oldWidget, $newWidget)
    }

    <#
    .SYNOPSIS
    Move focus to next widget (Tab)
    #>
    [void] FocusNextWidget() {
        if ($this.Widgets.Count -eq 0) {
            return
        }

        $nextIndex = ($this.FocusedWidgetIndex + 1) % $this.Widgets.Count
        $this.FocusWidget($nextIndex)
    }

    <#
    .SYNOPSIS
    Move focus to previous widget (Shift+Tab)
    #>
    [void] FocusPreviousWidget() {
        if ($this.Widgets.Count -eq 0) {
            return
        }

        $prevIndex = $this.FocusedWidgetIndex - 1
        if ($prevIndex -lt 0) {
            $prevIndex = $this.Widgets.Count - 1
        }
        $this.FocusWidget($prevIndex)
    }

    # === Widget Refresh ===

    <#
    .SYNOPSIS
    Refresh all widgets (reload data)
    #>
    [void] RefreshAllWidgets() {
        foreach ($widget in $this.Widgets) {
            if ($widget.PSObject.Methods['Refresh']) {
                $widget.Refresh()
            }
        }
    }

    <#
    .SYNOPSIS
    Refresh a specific widget by index

    .PARAMETER index
    Widget index
    #>
    [void] RefreshWidget([int]$index) {
        $widget = $this.GetWidget($index)
        if ($null -ne $widget -and $widget.PSObject.Methods['Refresh']) {
            $widget.Refresh()
        }
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
        # Tab navigation between widgets
        if ($keyInfo.Key -eq 'Tab') {
            if ($keyInfo.Modifiers -band [ConsoleModifiers]::Shift) {
                $this.FocusPreviousWidget()
            }
            else {
                $this.FocusNextWidget()
            }
            return $true
        }

        # Arrow key navigation between widgets (optional)
        if ($keyInfo.Key -eq 'RightArrow' -and $this.AllowWidgetNavigation) {
            $this.FocusNextWidget()
            return $true
        }

        if ($keyInfo.Key -eq 'LeftArrow' -and $this.AllowWidgetNavigation) {
            $this.FocusPreviousWidget()
            return $true
        }

        # Refresh shortcut
        if ($keyInfo.Key -eq 'R') {
            $this.RefreshAllWidgets()
            return $true
        }

        # Route input to focused widget
        $focusedWidget = $this.GetFocusedWidget()
        if ($null -ne $focusedWidget) {
            if ($focusedWidget.PSObject.Methods['HandleInput']) {
                return $focusedWidget.HandleInput($keyInfo)
            }
        }

        return $false
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
        foreach ($widget in $this.Widgets) {
            # Check if widget supports native rendering
            if ($widget.PSObject.Methods['RenderToEngine']) {
                $widget.RenderToEngine($engine)
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
    Create a simple text panel widget

    .PARAMETER title
    Panel title

    .PARAMETER content
    Panel content (text or array of lines)

    .OUTPUTS
    PmcPanel widget instance
    #>
    [object] CreateTextPanel([string]$title, $content) {
        $panel = [PmcPanel]::new()
        $panel.PanelTitle = $title

        if ($content -is [array]) {
            $panel.SetContent($content)
        }
        else {
            $panel.SetContent(@($content.ToString()))
        }

        return $panel
    }

    <#
    .SYNOPSIS
    Get widget count

    .OUTPUTS
    Number of widgets in dashboard
    #>
    [int] GetWidgetCount() {
        return $this.Widgets.Count
    }
}