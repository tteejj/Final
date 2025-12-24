# PmcApplication - Main application wrapper integrating PMC widgets with SpeedTUI
# Handles rendering engine, event loop, and screen management

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

# NOTE: SpeedTUI, widgets, layout, and theme are loaded by Start-PmcTUI.ps1
# Do not load them again here to avoid circular dependencies and duplicate loading

<#
.SYNOPSIS
Main application class for PMC TUI

.DESCRIPTION
PmcApplication manages:
- SpeedTUI rendering engine (OptimizedRenderEngine)
- Screen stack and navigation
- Event loop and input handling
- Layout management
- Theme management

.EXAMPLE
$container = [ServiceContainer]::new()
$app = [PmcApplication]::new($container)
$app.PushScreen($taskScreen)
$app.Run()
#>
class PmcApplication {
    # === Core Components ===
    [object]$RenderEngine
    [object]$LayoutManager
    [object]$ThemeManager
    [object]$Container        # ServiceContainer for dependency injection

    # === Screen Management ===
    [object]$ScreenStack      # Stack of PmcScreen objects
    [object]$CurrentScreen = $null   # Currently active screen

    # === Terminal State ===
    [int]$TermWidth = 80
    [int]$TermHeight = 24
    [bool]$Running = $false

    # === Rendering State ===
    [bool]$IsDirty = $true  # Dirty flag - true when redraw needed
    [int]$RenderErrorCount = 0  # Track consecutive render errors for recovery
    [datetime]$LastRenderError = [datetime]::MinValue  # Track last error time for time-based reset

    # === Automation Support ===
    [string]$AutomationCommandFile = ""  # Path to command file for automation
    [string]$AutomationOutputFile = ""   # Path to output capture file
    [System.Collections.Queue]$CommandQueue = $null  # Queue of simulated key presses
    [bool]$AutomationMode = $false       # Enable automation features

    # === Event Handlers ===
    [scriptblock]$OnTerminalResize = $null
    [scriptblock]$OnError = $null

    # === Constructor ===
    PmcApplication([object]$container) {
        # Store container for passing to screens
        $this.Container = $container
        # Initialize render engine (HybridRenderEngine with Layout System)
        try {
            $this.RenderEngine = New-Object HybridRenderEngine
            if ($null -eq $this.RenderEngine) {
                throw "Failed to create HybridRenderEngine instance"
            }
            $this.RenderEngine.Initialize()
        }
        catch {
            # Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcApplication] FATAL: Failed to initialize RenderEngine: $($_.Exception.Message)"
            throw
        }

        # Initialize layout manager
        $this.LayoutManager = New-Object PmcLayoutManager

        # Initialize theme manager
        $this.ThemeManager = $container.Resolve('ThemeManager')

        # Initialize screen stack
        $this.ScreenStack = New-Object "System.Collections.Generic.Stack[object]"

        # Get terminal size
        $this._UpdateTerminalSize()
    }

    # === Screen Management ===

    <#
    .SYNOPSIS
    Push a screen onto the stack and make it active

    .PARAMETER screen
    Screen object to push (should have Render() and HandleInput() methods)
    #>
    [void] PushScreen([object]$screen) {
        # Deactivate current screen
        if ($this.CurrentScreen) {
            if ($this.CurrentScreen.PSObject.Methods['OnExit']) {
                $this.CurrentScreen.OnDoExit()
            }
        }

        # DIFFERENTIAL RENDERING: Do NOT clear screen - let the new screen
        # overwrite the old content naturally. This prevents flicker.

        # Push new screen
        $this.ScreenStack.Push($screen)
        $this.CurrentScreen = $screen


        # }

        # Initialize screen with render engine and container
        if ($screen.PSObject.Methods['Initialize']) {
            $screen.Initialize($this.RenderEngine, $this.Container)
        }

        # Apply layout if screen has widgets
        if ($screen.PSObject.Methods['ApplyLayout']) {
            $screen.ApplyLayout($this.LayoutManager, $this.TermWidth, $this.TermHeight)
        }

        # Activate screen
        if ($screen.PSObject.Methods['OnEnter']) {
            $screen.OnEnter()
        }

        # Mark dirty for render
        $this.IsDirty = $true

    }

    <#
    .SYNOPSIS
    Pop current screen and return to previous

    .OUTPUTS
    The popped screen object
    #>
    [object] PopScreen() {
        if ($this.ScreenStack.Count -eq 0) {
            return $null
        }

        # Exit current screen
        $poppedScreen = $this.ScreenStack.Pop()
        if ($poppedScreen.PSObject.Methods['OnExit']) {
            $poppedScreen.OnDoExit()
        }

        # DIFFERENTIAL RENDERING: Do NOT clear screen - let the previous screen
        # overwrite the popped content naturally. This prevents flicker.

        # Restore previous screen
        if ($this.ScreenStack.Count -gt 0) {
            $this.CurrentScreen = $this.ScreenStack.Peek()

            # Re-enter previous screen
            if ($this.CurrentScreen.PSObject.Methods['OnEnter']) {
                $this.CurrentScreen.OnEnter()
            }

            # Mark dirty for render
            $this.IsDirty = $true
        }
        else {
            $this.CurrentScreen = $null
        }

        return $poppedScreen
    }

    <#
    .SYNOPSIS
    Clear screen stack and set a new root screen

    .PARAMETER screen
    New root screen
    #>
    [void] SetRootScreen([object]$screen) {
        # Clear stack
        while ($this.ScreenStack.Count -gt 0) {
            $this.PopScreen()
        }

        # Push new root
        $this.PushScreen($screen)
    }

    # === Rendering ===

    hidden [void] _RenderCurrentScreen() {
        # }

        if (-not $this.CurrentScreen) {
            # }
            return
        }


        # }

        try {
            # }

            # Check if screen requests full clear
            if ($this.CurrentScreen.NeedsClear) {
                # }
                $this.RenderEngine.RequestClear()
                $this.CurrentScreen.NeedsClear = $false
            }


            # }

            # USE SPEEDTUI PROPERLY - BeginFrame/WriteAt/EndFrame
            $this.RenderEngine.BeginFrame()


            # }

            # Get screen output (ANSI strings with position info)
            # Get screen output (ANSI strings with position info)
            # Get screen output (ANSI strings with position info)
            if ($this.CurrentScreen.PSObject.Methods['RenderToEngine']) {

                # }
                # New method: screen writes directly to engine
                $this.CurrentScreen.RenderToEngine($this.RenderEngine)
                # }
            }
            else {
                # Legacy fallback removed - all screens must support RenderToEngine
                throw "Screen type '$($this.CurrentScreen.GetType().Name)' does not implement RenderToEngine"
            }


            # }

            # EndFrame does differential rendering
            $this.RenderEngine.EndFrame()


            # }

            # Clear dirty flag after successful render
            $this.IsDirty = $false


            # }

        }
        catch {
            # RENDER ERROR - Try to recover gracefully
            $errorMsg = "Render error: $_"
            $errorLocation = "$($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"

            # Log to file if available
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] $errorMsg"
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] Location: $errorLocation"
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] Line: $($_.InvocationInfo.Line)"
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] Stack: $($_.ScriptStackTrace)"
            }

            # FIX 4.2: Time-based error count reset - clear counter if no errors for 5 seconds
            if ((Get-Date) - $this.LastRenderError -gt [TimeSpan]::FromSeconds(5)) {
                $this.RenderErrorCount = 0
            }
            $this.RenderErrorCount++
            $this.LastRenderError = Get-Date

            # If too many errors, then we need to fail
            if ($this.RenderErrorCount -gt 10) {
                # Too many errors - give up
                [Console]::Clear()
                [Console]::CursorVisible = $true
                [Console]::SetCursorPosition(0, 0)
                # Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcApplication] TOO MANY RENDER ERRORS - EXITING"
                # Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcApplication] Error: $errorMsg"
                # Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcApplication] Location: $errorLocation"
                # Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcApplication] The application experienced too many render errors."
                # Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcApplication] Please restart the application."

                [Console]::ReadKey($true) | Out-Null
                $this.Stop()
                return
            }

            # Try to show error in a minimal way and continue
            try {
                # Clear screen and show error message
                [Console]::Clear()
                [Console]::SetCursorPosition(0, 0)
                # Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcApplication] Render Error Occurred"
                # Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcApplication] Error: $($_.Exception.Message)"

                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'Escape') {
                    $this.Stop()
                    return
                }

                # Try to recover by requesting full clear and redraw
                $this.RenderEngine.RequestClear()
                $this.IsDirty = $true

                # If current screen is problematic, try to go back
                if ($this.ScreenStack.Count -gt 1 -and $this.RenderErrorCount -gt 3) {
                    # Write-PmcDebugLog "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcApplication] Returning to previous screen due to errors..."
                    Start-Sleep -Milliseconds 500
                    $this.PopScreen()
                    $this.RenderErrorCount = 0  # Reset counter after navigation
                }

            }
            catch {
                # Can't even show the error message - now we really need to exit
                # }
                $this.Stop()
            }

            # Call error handler if registered
            if ($this.OnError) {
                try {
                    & $this.OnError $_
                }
                catch {
                    # Error handler failed, log it but continue
                    # }
                }
            }
        }
    }



    # === Event Loop ===

    <#
    .SYNOPSIS
    Start the application event loop

    .DESCRIPTION
    Runs until Stop() is called or screen stack is empty
    #>
    [void] Run() {
        $this.Running = $true

        # Hide cursor
        [Console]::CursorVisible = $false

        # Track iterations for terminal size check optimization
        $iteration = 0

        try {
            # Event loop - render only when dirty
            # }


            while ($this.Running -and $this.ScreenStack.Count -gt 0) {
                $hadInput = $false

                # Check for automation commands
                if ($this.AutomationMode) {
                    $this._ProcessAutomationCommands()
                }

                # Process queued automation commands first
                if ($this.AutomationMode -and $this.CommandQueue.Count -gt 0) {
                    $cmdString = $this.CommandQueue.Dequeue()
                    # }

                    try {
                        $key = $this._ParseCommand($cmdString)

                        # Global keys - Ctrl+Q to exit
                        if ($key.Modifiers -eq [ConsoleModifiers]::Control -and $key.Key -eq 'Q') {
                            $this.Stop()
                        }
                        elseif ($this.CurrentScreen -and $this.CurrentScreen.PSObject.Methods['HandleKeyPress']) {
                            $handled = $this.CurrentScreen.HandleKeyPress($key)
                            if ($handled) {
                                $hadInput = $true
                            }
                        }

                        # Capture screen after command
                        $this._CaptureScreen()
                    }
                    catch {
                        # }
                    }
                }

                # OPTIMIZATION: Drain ALL available input before rendering
                # This eliminates input lag from sleep delays
                try {
                    while ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)

                        # Global keys - Ctrl+Q to exit
                        if ($key.Modifiers -eq [ConsoleModifiers]::Control -and $key.Key -eq 'Q') {
                            $this.Stop()
                            break
                        }

                        # Pass to current screen (screen handles its own menu)
                        if ($this.CurrentScreen) {
                            if ($this.CurrentScreen.PSObject.Methods['HandleKeyPress']) {
                                # }
                                $handled = $this.CurrentScreen.HandleKeyPress($key)
                                if ($handled) {
                                    $hadInput = $true
                                }
                            }
                            else {
                                # }
                            }
                        }
                    }
                }
                catch {
                    # Console input is redirected or unavailable - skip input processing
                    # This happens when running in non-interactive mode (e.g., piped input, automated tests)
                    # }
                }

                # Mark dirty if we processed input
                if ($hadInput) {
                    $this.IsDirty = $true
                }

                # Capture dirty state before rendering
                $wasActive = $this.IsDirty

                # OPTIMIZATION: Use centralized terminal service for resize detection
                # Only checks actual console every 100ms (cached)
                if ((-not $this.IsDirty) -or ($iteration % 10 -eq 0)) {
                    if (($this.RenderEngine.Width -ne [Console]::WindowWidth -or $this.RenderEngine.Height -ne [Console]::WindowHeight)) {
                        $dims = @{ Width = [Console]::WindowWidth; Height = [Console]::WindowHeight }
                        $this._HandleTerminalResize($dims.Width, $dims.Height)
                    }
                }

                if ($this.IsDirty) {
                    # Reset iteration counter when rendering
                    $iteration = 0
                }

                $iteration++

                # Only render when dirty (state changed)
                if ($this.IsDirty) {
                    # }
                    $this._RenderCurrentScreen()
                    $iteration = 0  # Reset counter after render
                }

                # Sleep longer when idle (no render) vs active
                if ($wasActive) {
                    Start-Sleep -Milliseconds 1  # ~1000 FPS max, instant response to input
                }
                else {
                    Start-Sleep -Milliseconds 50  # ~20 FPS when idle, reduced from 100ms for better responsiveness
                }
            }

        }
        finally {
            # FIX 7.1: Use Dispose for proper cleanup
            try {
                $this.Dispose()
            }
            catch {
                # Fallback cleanup if Dispose fails
                [Console]::CursorVisible = $true
            }
            [Console]::Clear()
        }
    }

    <#
    .SYNOPSIS
    Stop the application event loop
    #>
    [void] Stop() {
        $this.Running = $false

        # Flush any pending TaskStore changes before exit
        try {
            $store = [TaskStore]::GetInstance()
            if ($null -ne $store -and $store.HasPendingChanges) {
                $store.Flush()
            }
        }
        catch {
            # TaskStore might not be available during shutdown - safe to ignore
            if (Get-Command Write-PmcTuiLog -ErrorAction SilentlyContinue) {
                # Write-PmcTuiLog "Stop: Could not flush TaskStore: $($_.Exception.Message)" "WARNING"
            }
        }
    }

    # === Automation Methods ===

    <#
    .SYNOPSIS
    Enable automation mode with command file and output capture

    .PARAMETER CommandFile
    Path to file containing commands (one per line)

    .PARAMETER OutputFile
    Path to file for capturing screen output
    #>
    [void] EnableAutomation([string]$CommandFile, [string]$OutputFile) {
        $this.AutomationMode = $true
        $this.AutomationCommandFile = $CommandFile
        $this.AutomationOutputFile = $OutputFile
        $this.CommandQueue = New-Object System.Collections.Queue


        # }
    }

    <#
    .SYNOPSIS
    Check for new commands and queue them
    #>
    hidden [void] _ProcessAutomationCommands() {
        if (-not $this.AutomationMode -or -not (Test-Path $this.AutomationCommandFile)) {
            return
        }

        try {
            $commands = Get-Content $this.AutomationCommandFile -ErrorAction SilentlyContinue
            if ($commands) {
                foreach ($cmd in $commands) {
                    if ($cmd -and $cmd.Trim() -ne '') {
                        $this.CommandQueue.Enqueue($cmd.Trim())
                    }
                }
                # Clear the command file after reading
                Clear-Content $this.AutomationCommandFile -ErrorAction SilentlyContinue


                # }
            }
        }
        catch {
            # }
        }
    }

    <#
    .SYNOPSIS
    Convert command string to ConsoleKeyInfo
    #>
    hidden [System.ConsoleKeyInfo] _ParseCommand([string]$command) {
        # Parse commands like "j", "k", "Enter", "Ctrl+Q", "Escape"
        $parts = $command -split '\+'
        $modifiers = [ConsoleModifiers]::None
        $keyName = $parts[-1]

        # Parse modifiers
        foreach ($part in $parts[0..($parts.Length - 2)]) {
            switch ($part.ToLower()) {
                'ctrl' { $modifiers = $modifiers -bor [ConsoleModifiers]::Control }
                'alt' { $modifiers = $modifiers -bor [ConsoleModifiers]::Alt }
                'shift' { $modifiers = $modifiers -bor [ConsoleModifiers]::Shift }
            }
        }

        # Parse key
        $key = [ConsoleKey]::A
        $keyChar = [char]0

        switch ($keyName.ToLower()) {
            'enter' { $key = [ConsoleKey]::Enter; $keyChar = "`r" }
            'escape' { $key = [ConsoleKey]::Escape; $keyChar = [char]27 }
            'esc' { $key = [ConsoleKey]::Escape; $keyChar = [char]27 }
            'tab' { $key = [ConsoleKey]::Tab; $keyChar = "`t" }
            'space' { $key = [ConsoleKey]::Spacebar; $keyChar = ' ' }
            'up' { $key = [ConsoleKey]::UpArrow; $keyChar = [char]0 }
            'down' { $key = [ConsoleKey]::DownArrow; $keyChar = [char]0 }
            'left' { $key = [ConsoleKey]::LeftArrow; $keyChar = [char]0 }
            'right' { $key = [ConsoleKey]::RightArrow; $keyChar = [char]0 }
            default {
                # Single character
                if ($keyName.Length -eq 1) {
                    $keyChar = $keyName[0]
                    $key = [ConsoleKey]::($keyName.ToUpper())
                }
            }
        }

        return New-Object System.ConsoleKeyInfo($keyChar, $key, ($modifiers -band [ConsoleModifiers]::Shift) -ne 0, ($modifiers -band [ConsoleModifiers]::Alt) -ne 0, ($modifiers -band [ConsoleModifiers]::Control) -ne 0)
    }

    <#
    .SYNOPSIS
    Capture current screen to output file
    #>
    hidden [void] _CaptureScreen() {
        if (-not $this.AutomationMode -or -not $this.AutomationOutputFile) {
            return
        }

        try {
            # Capture screen state information
            $screenInfo = @"
=== Screen Capture $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===
Current Screen: $($this.CurrentScreen.GetType().Name)
Terminal Size: $($this.TermWidth)x$($this.TermHeight)
Screen Stack Depth: $($this.ScreenStack.Count)

"@
            # Try to capture current screen's rendered content
            if ($this.CurrentScreen -and $this.CurrentScreen.PSObject.Properties['LastRenderedContent']) {
                $screenInfo += "Last Rendered Content:`n"
                $screenInfo += $this.CurrentScreen.LastRenderedContent
                $screenInfo += "`n"
            }

            Add-Content -Path $this.AutomationOutputFile -Value $screenInfo
        }
        catch {
            # }
        }
    }

    # === Terminal Management ===

    hidden [void] _UpdateTerminalSize() {
        # Use centralized terminal service (cached, optimized)
        $dims = @{ Width = [Console]::WindowWidth; Height = [Console]::WindowHeight }
        $this.TermWidth = $dims.Width
        $this.TermHeight = $dims.Height
    }

    hidden [void] _HandleTerminalResize([int]$newWidth, [int]$newHeight) {
        $this.TermWidth = $newWidth
        $this.TermHeight = $newHeight

        # Notify current screen
        if ($this.CurrentScreen) {
            if ($this.CurrentScreen.PSObject.Methods['OnTerminalResize']) {
                $this.CurrentScreen.OnTerminalResize($newWidth, $newHeight)
            }

            # Reapply layout
            if ($this.CurrentScreen.PSObject.Methods['ApplyLayout']) {
                $this.CurrentScreen.ApplyLayout($this.LayoutManager, $newWidth, $newHeight)
            }
        }

        # Fire event
        if ($this.OnTerminalResize) {
            & $this.OnTerminalResize $newWidth $newHeight
        }

        # Mark dirty for render
        $this.IsDirty = $true
    }

    # === Utility Methods ===

    <#
    .SYNOPSIS
    Get current terminal size

    .OUTPUTS
    Hashtable with Width and Height properties
    #>
    [hashtable] GetTerminalSize() {
        return @{
            Width  = $this.TermWidth
            Height = $this.TermHeight
        }
    }

    <#
    .SYNOPSIS
    Request a render on next frame

    .DESCRIPTION
    Schedules a re-render of the current screen by setting dirty flag
    #>
    [void] RequestRender() {
        if ($global:PmcTuiLogFile) {
            $caller = (Get-PSCallStack)[1]
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] RequestRender called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
        }
        $this.IsDirty = $true
    }

    <#
    .SYNOPSIS
    Clean up resources on application shutdown

    .DESCRIPTION
    FIX 7.1: Explicit disposal pattern for:
    - Flushing pending data
    - Clearing event handlers
    - Resetting singletons for clean restart
    - Restoring terminal state
    #>
    [void] Dispose() {
        # Flush pending data
        try {
            $store = [TaskStore]::GetInstance()
            if ($null -ne $store -and $store.HasPendingChanges) {
                $store.Flush()
            }
        }
        catch {
            # Log but continue cleanup
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [WARNING] Dispose: Could not flush TaskStore: $_"
            }
        }

        # Clear event handlers to break reference cycles
        $this.OnTerminalResize = $null
        $this.OnError = $null

        # Reset singletons to allow clean restart
        $global:PmcApp = $null
        $global:PmcContainer = $null
        $global:PmcSharedMenuBar = $null

        # Reset theme singletons
        try {
            [PmcThemeManager]::_instance = $null
            [PmcThemeEngine]::_instance = $null
        }
        catch {
            # May fail if classes not loaded - safe to ignore
        }

        # Restore terminal state
        [Console]::CursorVisible = $true
    }
}

# Classes exported automatically in PowerShell 5.1+
