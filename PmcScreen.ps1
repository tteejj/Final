# PmcScreen - Base class for all PMC screens
# Provides standard screen lifecycle, layout, and widget management

using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

# NOTE: All dependencies are loaded by Start-PmcTUI.ps1
# Do not load them again here to avoid circular dependencies and duplicate loading

<#
.SYNOPSIS
Base class for all PMC screens

.DESCRIPTION
PmcScreen provides:
- Standard widget composition (MenuBar, Header, Footer, StatusBar, Content)
- Layout management integration
- Screen lifecycle (OnEnter, OnExit, LoadData)
- Input handling delegation
- Rendering orchestration
- ServiceContainer dependency injection

.EXAMPLE
# Example: Custom screen implementation with ServiceContainer
# class MyCustomScreen : PmcScreen {
#     MyCustomScreen([object]$container) : base("MyScreen", "My Screen Title", $container) {
#         $this.Header.SetBreadcrumb(@("Home", "My Screen"))
#     }
#
#     [void] LoadData() {
#         # Access services via container
#         $taskStore = $this.Container.Get('TaskStore')
#         # Load your data...
#     }
#
#     [string] RenderContent() {
#         # Render your content...
#     }
# }
#
# Example: Legacy constructor (backward compatible)
# class MyLegacyScreen : PmcScreen {
#     MyLegacyScreen() : base("MyScreen", "My Screen Title") {
#         # Works without container for backward compatibility
#     }
# }
#>
class PmcScreen {
    # === Core Properties ===
    [string]$ScreenKey = ""
    [string]$ScreenTitle = ""

    # === Service Container ===
    [object]$Container = $null

    # === Standard Widgets ===
    [object]$MenuBar = $null
    [object]$Header = $null
    [object]$Footer = $null
    [object]$StatusBar = $null
    [object]$ContentWidgets

    # === Layout ===
    [object]$LayoutManager = $null
    [int]$TermWidth = 80
    [int]$TermHeight = 24

    # === State ===
    [bool]$IsActive = $false
    [object]$RenderEngine = $null
    [bool]$NeedsClear = $false  # Request full screen clear before next render

    # === Layout Methods ===

    <#
    .SYNOPSIS
    Handle screen resizing
    #>
    [void] Resize([int]$width, [int]$height) {
        $this.TermWidth = $width
        $this.TermHeight = $height
        
        # Calculate vertical layout
        $currentY = 0
        
        # MenuBar (Top)
        if ($this.MenuBar) {
            $this.MenuBar.SetPosition(0, $currentY)
            $this.MenuBar.SetSize($width, 1)
            $currentY++
        }
        
        # Header (Below Menu)
        if ($this.Header) {
            $this.Header.SetPosition(0, $currentY)
            # Header is typically 1 line
            $this.Header.SetSize($width, 1)
            $currentY++
        }
        
        # Footer (Bottom, fixed height)
        if ($this.Footer) {
            $this.Footer.SetPosition(0, $height - 1)
            $this.Footer.SetSize($width, 1)
        }
        
        # StatusBar (Above Footer)
        if ($this.StatusBar) {
            $this.StatusBar.SetPosition(0, $height - 2)
            $this.StatusBar.SetSize($width, 1)
        }
    }

    # H-UI-4: Message queue for persistent status messages
    [System.Collections.Queue]$_messageQueue = [System.Collections.Queue]::new()
    [DateTime]$_lastMessageTime = [DateTime]::MinValue

    # === Event Handlers ===
    [scriptblock]$OnEnterHandler = $null
    [scriptblock]$OnExitHandler = $null

    # === Constructor (backward compatible - no container) ===
    PmcScreen([string]$key, [string]$title) {
        # PERF: Disabled - if ($global:PmcTuiLogFile) {
        # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PmcScreen: Legacy constructor called (key=$key, title=$title)"
        # }

        $this.ScreenKey = $key
        $this.ScreenTitle = $title
        $this.ContentWidgets = New-Object 'System.Collections.Generic.List[object]'

        # Create default widgets
        $this._CreateDefaultWidgets()
    }

    # === Constructor (with ServiceContainer) ===
    PmcScreen([string]$key, [string]$title, [object]$container) {
        # PERF: Disabled - if ($global:PmcTuiLogFile) {
        # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PmcScreen: Constructor called with ServiceContainer (key=$key, title=$title, container=$($null -ne $container))"
        # }

        $this.ScreenKey = $key
        $this.ScreenTitle = $title
        $this.Container = $container
        $this.ContentWidgets = New-Object 'System.Collections.Generic.List[object]'

        # PERF: Disabled - if ($global:PmcTuiLogFile) {

        # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PmcScreen: ServiceContainer stored (available=$($null -ne $this.Container))"
        # }

        # Create default widgets
        $this._CreateDefaultWidgets()
    }

    hidden [void] _CreateDefaultWidgets() {
        Add-Content -Path "$(Join-Path ([System.IO.Path]::GetTempPath()) 'pmc_debug.txt')" -Value "[$(Get-Date)] PmcScreen._CreateDefaultWidgets: START. Screen=$($this.ScreenKey)"

        # Menu bar - use shared MenuBar if available (populated by TaskListScreen)
        # CRITICAL: Check if variable exists AND is not null
        if ((Get-Variable -Name PmcSharedMenuBar -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcSharedMenuBar) {
            $this.MenuBar = $global:PmcSharedMenuBar
        }
        else {
            # Create default empty MenuBar (will be populated by TaskListScreen)
            $this.MenuBar = New-Object PmcMenuBar

            $this.MenuBar.AddMenu("Tasks", 'T', @())
            $this.MenuBar.AddMenu("Projects", 'P', @())
            $this.MenuBar.AddMenu("Time", 'M', @())
            $this.MenuBar.AddMenu("Tools", 'L', @())
            $this.MenuBar.AddMenu("Options", 'O', @())
            $this.MenuBar.AddMenu("Help", '?', @())
        }

        # Header
        $this.Header = New-Object PmcHeader -ArgumentList $this.ScreenTitle

        # Footer with standard shortcuts
        $this.Footer = New-Object PmcFooter
        $this.Footer.AddShortcut("Esc", "Back")
        $this.Footer.AddShortcut("F10", "Menu")

        # Status bar
        $this.StatusBar = New-Object PmcStatusBar
        $this.StatusBar.SetLeftText("Ready")
    }

    # === Lifecycle Methods ===

    <#
    .SYNOPSIS
    Called when screen becomes active

    .DESCRIPTION
    Override to perform initialization when screen is displayed
    #>
    [void] OnEnter() {
        # PERF: Disabled - if ($global:PmcTuiLogFile) {
        # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [LIFECYCLE] PmcScreen.OnEnter() - Screen='$($this.ScreenKey)' entering"
        # }
        $this.IsActive = $true
        $this.LoadData()

        if ($this.OnEnterHandler) {
            & $this.OnEnterHandler $this
        }
        # PERF: Disabled - if ($global:PmcTuiLogFile) {
        # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [LIFECYCLE] PmcScreen.OnEnter() - Screen='$($this.ScreenKey)' entered successfully"
        # }
    }

    <#
    .SYNOPSIS
    Called when screen becomes inactive

    .DESCRIPTION
    Override to perform cleanup when leaving screen
    #>
    [void] OnDoExit() {
        # PERF: Disabled - if ($global:PmcTuiLogFile) {
        # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [LIFECYCLE] PmcScreen.OnDoExit() - Screen='$($this.ScreenKey)' exiting"
        # }
        $this.IsActive = $false

        if ($this.OnExitHandler) {
            & $this.OnExitHandler $this
        }
        # PERF: Disabled - if ($global:PmcTuiLogFile) {
        # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [LIFECYCLE] PmcScreen.OnDoExit() - Screen='$($this.ScreenKey)' exited successfully"
        # }
    }

    <#
    .SYNOPSIS
    Load data for this screen

    .DESCRIPTION
    Override to load screen-specific data
    #>
    [void] LoadData() {
        # PERF: Disabled - if ($global:PmcTuiLogFile) {
        # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [LIFECYCLE] PmcScreen.LoadData() - Screen='$($this.ScreenKey)' (base class - no-op)"
        # }
        # Override in subclass
    }

    # === Layout Management ===

    <#
    .SYNOPSIS
    Apply layout to all widgets

    .PARAMETER layoutManager
    Layout manager instance

    .PARAMETER termWidth
    Terminal width

    .PARAMETER termHeight
    Terminal height
    #>
    [void] ApplyLayout([object]$layoutManager, [int]$termWidth, [int]$termHeight) {
        try {
            Write-Host "DEBUG: PmcScreen.ApplyLayout: START Screen=$($this.ScreenKey) W=$termWidth H=$termHeight"
            $this.LayoutManager = $layoutManager
            $this.TermWidth = $termWidth
            $this.TermHeight = $termHeight

            # Apply layout to standard widgets
            if ($this.MenuBar) {
                Write-Host "DEBUG: PmcScreen.ApplyLayout: Formatting MenuBar"
                $rect = $layoutManager.GetRegion('MenuBar', $termWidth, $termHeight)
                $this.MenuBar.SetPosition($rect.X, $rect.Y)
                $this.MenuBar.SetSize($rect.Width, $rect.Height)
            }

            if ($this.Header) {
                Write-Host "DEBUG: PmcScreen.ApplyLayout: Formatting Header"
                $rect = $layoutManager.GetRegion('Header', $termWidth, $termHeight)
                $this.Header.SetPosition($rect.X, $rect.Y)
                $this.Header.SetSize($rect.Width, $rect.Height)
            }

            if ($this.Footer) {
                $rect = $layoutManager.GetRegion('Footer', $termWidth, $termHeight)
                $this.Footer.SetPosition($rect.X, $rect.Y)
                $this.Footer.SetSize($rect.Width, $rect.Height)
            }

            if ($this.StatusBar) {
                $rect = $layoutManager.GetRegion('StatusBar', $termWidth, $termHeight)
                $this.StatusBar.SetPosition($rect.X, $rect.Y)
                $this.StatusBar.SetSize($rect.Width, $rect.Height)
            }

            # Apply layout to content widgets
            Write-Host "DEBUG: PmcScreen.ApplyLayout: Calling ApplyContentLayout"
            $this.ApplyContentLayout($layoutManager, $termWidth, $termHeight)
            Write-Host "DEBUG: PmcScreen.ApplyLayout: COMPLETE"
        }
        catch {
            Write-Host "FATAL ERROR PmcScreen.ApplyLayout: $_"
            Write-Host "Stack: $($_.ScriptStackTrace)"
            throw
        }
    }


    <#
    .SYNOPSIS
    Apply layout to content area widgets

    .DESCRIPTION
    Override to position custom content widgets
    #>
    [void] ApplyContentLayout([PmcLayoutManager]$layoutManager, [int]$termWidth, [int]$termHeight) {
        # Override in subclass to position content widgets
    }

    <#
    .SYNOPSIS
    Handle terminal resize

    .PARAMETER newWidth
    New terminal width

    .PARAMETER newHeight
    New terminal height
    #>
    [void] OnTerminalResize([int]$newWidth, [int]$newHeight) {
        if ($this.LayoutManager) {
            $this.ApplyLayout($this.LayoutManager, $newWidth, $newHeight)
        }
    }

    # === Rendering ===

    <#
    .SYNOPSIS
    Initialize widgets with render engine

    .PARAMETER renderEngine
    SpeedTUI render engine instance
    #>
    # Initialize with render engine only (backward compatible)
    [void] Initialize([object]$renderEngine) {
        $this.Initialize($renderEngine, $null)
    }

    # Initialize with render engine and container (new pattern)
    [void] Initialize([object]$renderEngine, [object]$container) {
        $this.RenderEngine = $renderEngine

        # Store container if provided
        if ($container) {
            $this.Container = $container
            # PERF: Disabled - if ($global:PmcTuiLogFile) {
            # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PmcScreen.Initialize: Container set for screen '$($this.ScreenKey)'"
            # }
        }

        # Initialize standard widgets
        if ($this.MenuBar) {
            $this.MenuBar.Initialize($renderEngine)
        }
        if ($this.Header) {
            $this.Header.Initialize($renderEngine)
        }
        if ($this.Footer) {
            $this.Footer.Initialize($renderEngine)
        }
        if ($this.StatusBar) {
            $this.StatusBar.Initialize($renderEngine)
        }

        # Initialize content widgets
        foreach ($widget in $this.ContentWidgets) {
            $widget.Initialize($renderEngine)
        }
    }

    <#
    .SYNOPSIS
    Legacy Render method - DEPRECATED
    
    .DESCRIPTION
    This method has been removed to enforce native rendering.
    All rendering must now be done via RenderToEngine().
    #>
    [string] Render() {
        throw "LEGACY RENDER CALLED: All screens must implement RenderToEngine(). This method is deprecated and removed."
    }

    <#
    .SYNOPSIS
    Legacy RenderContent method - DEPRECATED
    #>
    [string] RenderContent() {
        return ""
    }

    <#
    .SYNOPSIS
    Render directly to engine

    .PARAMETER engine
    RenderEngine instance to write to

    .DESCRIPTION
    Renders screen by calling widget Render() methods and writing ANSI output to engine.
    Widgets use SpeedTUI's Render() → OnRender() pattern which returns ANSI strings.
    We parse those ANSI strings and write them to the engine using WriteAt().
    #>
    [void] RenderToEngine([object]$engine) {
        # Z-INDEX LAYER RENDERING
        # All rendering now uses explicit layers for proper z-ordering.

        # Layer 50: Header
        $engine.BeginLayer([ZIndex]::Header)
        if ($this.Header) {
            try {
                if ($this.Header.PSObject.Methods['RenderToEngine']) {
                    $this.Header.RenderToEngine($engine)
                }
            }
            catch {
                $this._HandleWidgetRenderError("Header", $_, $engine, 1)
            }
        }

        # Layer 10: Content (main screen content)
        $engine.BeginLayer([ZIndex]::Content)
        try {
            if ($this.PSObject.Methods['RenderContentToEngine'] -and
                $this.GetType().GetMethod('RenderContentToEngine').DeclaringType.Name -ne 'PmcScreen') {
                $this.RenderContentToEngine($engine)
            }
        }
        catch {
            $this._HandleWidgetRenderError("RenderContent", $_, $engine, 5)
        }

        # Layer 20: Panel (content widgets like FilterPanel, DatePicker, etc.)
        $engine.BeginLayer([ZIndex]::Panel)
        $widgetRow = 10
        # Write-PmcTuiLog "PmcScreen.RenderToEngine: Rendering $($this.ContentWidgets.Count) content widgets" "DEBUG"
        foreach ($widget in $this.ContentWidgets) {
            $widgetName = $(if ($widget.Name) { $widget.Name } else { $widget.GetType().Name })
            try {
                if ($widget.PSObject.Methods['RenderToEngine']) {
                    Write-PmcTuiLog "PmcScreen: Calling RenderToEngine on $widgetName" "DEBUG"
                    $widget.RenderToEngine($engine)
                }
                else {
                    Write-PmcTuiLog "PmcScreen: Widget $widgetName missing RenderToEngine method" "WARN"
                }
            }
            catch {
                $this._HandleWidgetRenderError($widgetName, $_, $engine, $widgetRow)
                $widgetRow += 2
            }
        }

        # Layer 55: Footer
        $engine.BeginLayer([ZIndex]::Footer)
        if ($this.Footer) {
            try {
                if ($this.Footer.PSObject.Methods['RenderToEngine']) {
                    $this.Footer.RenderToEngine($engine)
                }
            }
            catch {
                $footerRow = [Math]::Max(20, $this.TermHeight - 4)
                $this._HandleWidgetRenderError("Footer", $_, $engine, $footerRow)
            }
        }

        # Layer 65: StatusBar
        $engine.BeginLayer([ZIndex]::StatusBar)
        if ($this.StatusBar) {
            try {
                if ($this.StatusBar.PSObject.Methods['RenderToEngine']) {
                    $this.StatusBar.RenderToEngine($engine)
                }
            }
            catch {
                $statusRow = [Math]::Max(22, $this.TermHeight - 2)
                $this._HandleWidgetRenderError("StatusBar", $_, $engine, $statusRow)
            }
        }

        # Layer 100: Dropdown (MenuBar with dropdowns)
        # CRITICAL: Render MenuBar LAST with highest z-index
        $engine.BeginLayer([ZIndex]::Dropdown)
        if ($this.MenuBar) {
            try {
                if ($this.MenuBar.PSObject.Methods['RenderToEngine']) {
                    $this.MenuBar.RenderToEngine($engine)
                }
            }
            catch {
                $this._HandleWidgetRenderError("MenuBar", $_, $engine, 0)
            }
        }
    }


    <#
    .SYNOPSIS
    Handle widget render errors gracefully

    .DESCRIPTION
    Shows error inline without crashing the app, logs the error,
    and allows the rest of the UI to continue rendering.
    #>
    hidden [void] _HandleWidgetRenderError([string]$widgetName, [object]$error, [object]$engine, [int]$row) {
        $errorMsg = "$widgetName render failed: $($error.Exception.Message)"
        $stackTrace = $error.ScriptStackTrace

        # Log error details
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] Widget render error: $errorMsg"
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] Stack: $stackTrace"
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] TargetObject: $($error.TargetObject)"
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] InvocationInfo: $($error.InvocationInfo.Line)"
        }

        # Show error inline where widget would have rendered
        try {
            $engine.WriteAt(2, $row, "`e[1;31m[!] $widgetName Error: $($error.Exception.Message -replace "`n", " ")`e[0m")

            # If status bar is available, also show error there
            if ($this.StatusBar) {
                $this.SetStatusMessage("$widgetName render failed - see logs", "error")
            }
        }
        catch {
            # If we can't even write the error, just log it
            # PERF: Disabled - if ($global:PmcTuiLogFile) {
            # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [FATAL] Could not write error to screen: $_"
            # }
        }
    }



    <#
    .SYNOPSIS
    Render content area directly to engine

    .PARAMETER engine
    RenderEngine instance

    .DESCRIPTION
    Override in subclass to render screen-specific content directly
    to the engine without ANSI string building.
    #>
    [void] RenderContentToEngine([object]$engine) {
        # Override in subclass for direct engine rendering
        # This is the new high-performance path
    }

    # === Input Handling ===

    <#
    .SYNOPSIS
    Handle keyboard input

    .PARAMETER keyInfo
    Console key info

    .OUTPUTS
    Boolean indicating if input was handled
    #>
    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # MenuBar gets priority (if active)
        if ($this.MenuBar -and $this.MenuBar.IsActive) {
            if ($this.MenuBar.HandleKeyPress($keyInfo)) {
                return $true
            }
        }

        # F10 activates menu bar
        if ($keyInfo.Key -eq 'F10' -and $this.MenuBar) {
            $this.MenuBar.Activate()
            return $true
        }

        # Pass to content widgets FIRST (in reverse order for z-index)
        # CRITICAL FIX #5: Check widgets before menu Alt-keys to prevent conflicts with focused editors
        for ($i = $this.ContentWidgets.Count - 1; $i -ge 0; $i--) {
            $widget = $this.ContentWidgets[$i]
            if ($widget.PSObject.Methods['HandleKeyPress']) {
                if ($widget.HandleKeyPress($keyInfo)) {
                    return $true
                }
            }
        }

        # Alt+letter hotkeys activate menu bar (only if no widget handled it)
        # CRITICAL FIX #5: Moved AFTER widget handling to prevent conflicts
        if ($this.MenuBar -and ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt)) {
            if ($this.MenuBar.HandleKeyPress($keyInfo)) {
                return $true
            }
        }

        # Pass to subclass
        return $this.HandleInput($keyInfo)
    }

    <#
    .SYNOPSIS
    Handle screen-specific input

    .DESCRIPTION
    Override in subclass to handle custom input

    .PARAMETER keyInfo
    Console key info

    .OUTPUTS
    Boolean indicating if input was handled
    #>
    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        # Override in subclass
        return $false
    }

    # === Widget Management ===

    <#
    .SYNOPSIS
    Add a widget to the content area

    .PARAMETER widget
    Widget to add
    #>
    [void] AddContentWidget([PmcWidget]$widget) {
        Write-PmcTuiLog "PmcScreen.AddContentWidget: Adding $($widget.GetType().Name) (Total: $($this.ContentWidgets.Count + 1))" "DEBUG"
        $this.ContentWidgets.Add($widget)

        # Initialize if render engine available
        if ($this.RenderEngine) {
            $widget.Initialize($this.RenderEngine)
        }
    }

    <#
    .SYNOPSIS
    Remove a widget from the content area

    .PARAMETER widget
    Widget to remove
    #>
    [void] RemoveContentWidget([PmcWidget]$widget) {
        $this.ContentWidgets.Remove($widget)
    }

    # === Service Container Methods ===

    <#
    .SYNOPSIS
    Get a service from the container

    .PARAMETER serviceName
    Name of the service to retrieve

    .OUTPUTS
    Service instance or $null if container not available or service not found

    .EXAMPLE
    $taskStore = $this.GetService('TaskStore')
    #>
    [object] GetService([string]$serviceName) {
        if ($null -eq $this.Container) {
            # PERF: Disabled - if ($global:PmcTuiLogFile) {
            # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PmcScreen.GetService: Container not available (service=$serviceName)"
            # }
            return $null
        }

        try {
            $service = $this.Container.Get($serviceName)
            # PERF: Disabled - if ($global:PmcTuiLogFile) {
            # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PmcScreen.GetService: Retrieved service (name=$serviceName, found=$($null -ne $service))"
            # }
            return $service
        }
        catch {
            # PERF: Disabled - if ($global:PmcTuiLogFile) {
            # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PmcScreen.GetService: Error retrieving service (name=$serviceName, error=$($_.Exception.Message))"
            # }
            return $null
        }
    }

    <#
    .SYNOPSIS
    Check if a service is available in the container

    .PARAMETER serviceName
    Name of the service to check

    .OUTPUTS
    Boolean indicating if service is available

    .EXAMPLE
    if ($this.HasService('TaskStore')) { ... }
    #>
    [bool] HasService([string]$serviceName) {
        if ($null -eq $this.Container) {
            return $false
        }

        try {
            return $this.Container.Has($serviceName)
        }
        catch {
            # PERF: Disabled - if ($global:PmcTuiLogFile) {
            # PERF: Disabled -     Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] PmcScreen.HasService: Error checking service (name=$serviceName, error=$($_.Exception.Message))"
            # }
            return $false
        }
    }

    # === Utility Methods ===

    <#
    .SYNOPSIS
    Show a message in the status bar

    .PARAMETER message
    Message to display
    #>
    [void] ShowStatus([string]$message) {
        if ($this.StatusBar) {
            # H-UI-4: Queue message with timestamp for persistence
            $this._messageQueue.Enqueue(@{ Message = $message; Type = 'info'; Time = [DateTime]::Now })
            $this._lastMessageTime = [DateTime]::Now
            $this.StatusBar.SetLeftText($message)
        }
    }

    <#
    .SYNOPSIS
    Show an error in the status bar

    .PARAMETER message
    Error message
    #>
    [void] ShowError([string]$message) {
        if ($this.StatusBar) {
            $this.StatusBar.ShowError($message)
        }
    }

    <#
    .SYNOPSIS
    Show a success message in the status bar

    .PARAMETER message
    Success message

    .PARAMETER autoSaved
    L-POL-6: If true, append "Saved." to indicate auto-save occurred
    #>
    [void] ShowSuccess([string]$message) {
        $this.ShowSuccess($message, $false)
    }

    [void] ShowSuccess([string]$message, [bool]$autoSaved) {
        if ($this.StatusBar) {
            # L-POL-6: Append "Saved." indicator when auto-save is active
            $displayMessage = $(if ($autoSaved) {
                    "$message Saved."
                }
                else {
                    $message
                })
            $this.StatusBar.ShowSuccess($displayMessage)
        }
    }

    <#
    .SYNOPSIS
    L-POL-3: Show loading message with consistent format

    .PARAMETER itemType
    Type of items being loaded (e.g., "tasks", "projects", "notes")
    #>
    [void] ShowLoading([string]$itemType) {
        $this.ShowStatus("Loading $itemType...")
    }

    <#
    .SYNOPSIS
    L-POL-3: Show loaded message with count

    .PARAMETER itemType
    Type of items loaded (e.g., "tasks", "projects", "notes")

    .PARAMETER count
    Number of items loaded
    #>
    [void] ShowLoaded([string]$itemType, [int]$count) {
        $this.ShowStatus("Loaded $count $itemType")
    }

    <#
    .SYNOPSIS
    L-POL-3: Show ready message after loading complete

    .PARAMETER itemType
    Optional type of items ready (defaults to "Ready")
    #>
    [void] ShowReady() {
        $this.ShowReady("")
    }

    [void] ShowReady([string]$itemType) {
        $message = $(if ([string]::IsNullOrWhiteSpace($itemType)) {
                "Ready"
            }
            else {
                "$itemType ready"
            })
        $this.ShowStatus($message)
    }
}

# Classes exported automatically in PowerShell 5.1+