# ZIndex.ps1 - Z-index constants for layer rendering
#
# Defines standard z-index values for UI elements.
# Higher values render on top of lower values.
#
# Usage:
#   $engine.BeginLayer([ZIndex]::Dropdown)
#   $engine.WriteAt(10, 5, "Popup content")

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Z-index constants for layered rendering

.DESCRIPTION
Defines standard z-index values used throughout the PMC TUI.
These constants ensure consistent layering behavior across all screens and widgets.

Z-index ranges:
- 0-49: Base content (background, main content, panels)
- 50-99: Chrome (header, footer, menu bar)
- 100-199: Overlays (dropdowns, tooltips)
- 200-299: Modals (dialogs, popups)
- 300+: Critical UI (errors, notifications)

.EXAMPLE
$engine.BeginLayer([ZIndex]::Content)
# Render main content

$engine.BeginLayer([ZIndex]::Dropdown)
# Render dropdown (will appear on top)
#>
class ZIndex {
    # Base layer (default if no BeginLayer called)
    static [int]$Default = 0

    # Background elements
    static [int]$Background = 0

    # Main content area
    static [int]$Content = 10

    # Panels and widgets within content
    static [int]$Panel = 20
    static [int]$Widget = 25

    # Chrome elements (always on top of content)
    static [int]$Header = 50
    static [int]$Footer = 55
    static [int]$MenuBar = 60
    static [int]$StatusBar = 65

    # Overlays (temporary UI elements)
    static [int]$Dropdown = 100
    static [int]$Tooltip = 110
    static [int]$ContextMenu = 120

    # Modals (block interaction with content below)
    static [int]$Dialog = 200
    static [int]$Modal = 210
    static [int]$Popup = 220

    # Critical UI (highest priority)
    static [int]$ErrorOverlay = 300
    static [int]$Notification = 310
    static [int]$DebugOverlay = 320
}

# Export for module usage
Export-ModuleMember -Variable ZIndex