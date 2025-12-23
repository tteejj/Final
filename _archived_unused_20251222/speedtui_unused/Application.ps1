# SpeedTUI Application Framework - Main application orchestrator

using namespace System.Collections.Generic

class Application {
    [string]$Title = "SpeedTUI Application"
    [Component]$RootComponent
    [RenderEngine]$RenderEngine
    [InputManager]$InputManager
    [DataStoreManager]$DataStoreManager
    [EnhancedThemeManager]$ThemeManager
    [object]$Logger
    
    # Application state
    hidden [bool]$_running = $false
    hidden [bool]$_initialized = $false
    hidden [System.Diagnostics.Stopwatch]$_frameTimer
    hidden [double]$_targetFrameTime = 16.67  # 60 FPS
    
    # Performance tracking
    hidden [int]$_frameCount = 0
    hidden [double]$_totalFrameTime = 0
    hidden [DateTime]$_startTime
    
    Application() {
        $this.Logger = Get-Logger
        $this.Logger.Info("Application", "Constructor", "Application created")

        # Initialize core services
        $this.RenderEngine = [OptimizedRenderEngine]::new()
        $this.InputManager = [InputManager]::new()
        $this.ThemeManager = Get-ThemeManager
        $this._frameTimer = [System.Diagnostics.Stopwatch]::new()
    }

    Application([string]$title) {
        $this.Title = $title
        $this.Logger = Get-Logger
        $this.Logger.Info("Application", "Constructor", "Application created with title", @{
            Title = $title
        })

        # Initialize core services
        $this.RenderEngine = [OptimizedRenderEngine]::new()
        $this.InputManager = [InputManager]::new()
        $this.ThemeManager = Get-ThemeManager
        $this._frameTimer = [System.Diagnostics.Stopwatch]::new()
    }
    
    # Set root component
    [Application] SetRoot([Component]$component) {
        [Guard]::NotNull($component, "component")
        
        $this.RootComponent = $component
        
        $this.Logger.Debug("Application", "SetRoot", "Root component set", @{
            ComponentType = $component.GetType().Name
            ComponentId = $component.Id
        })
        
        return $this
    }
    
    # Initialize application
    [void] Initialize() {
        if ($this._initialized) { return }
        
        $this.Logger.Info("Application", "Initialize", "Initializing application", @{
            Title = $this.Title
        })
        
        try {
            # Initialize render engine
            $this.RenderEngine.Initialize()
            
            # Initialize root component
            if ($null -eq $this.RootComponent) {
                throw [InvalidOperationException]::new("No root component set")
            }
            
            # Set root bounds to full terminal
            $this.RootComponent.SetBounds(0, 0, $this.RenderEngine._terminal.Width, $this.RenderEngine._terminal.Height)
            
            # Initialize component tree
            $this.RootComponent.Initialize($this.RenderEngine)
            
            # Start input manager
            $this.InputManager.Start()
            
            # Register focusable components
            $this.InputManager.GetFocusManager().RefreshFocusableList($this.RootComponent)
            
            # Set application title
            [Console]::Title = $this.Title
            
            $this._initialized = $true
            $this._startTime = [DateTime]::Now
            
            $this.Logger.Info("Application", "Initialize", "Application initialized successfully")
            
        } catch {
            $this.Logger.Fatal("Application", "Initialize", "Failed to initialize application", @{
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    # Main run loop
    [void] Run() {
        if (-not $this._initialized) {
            $this.Initialize()
        }
        
        $this._running = $true
        $this.Logger.Info("Application", "Run", "Starting main loop")
        
        try {
            $loopCount = 0
            while ($this._running) {
                $this._frameTimer.Restart()
                
                # Process input
                $this.ProcessInput()
                
                # Update data bindings
                $this.UpdateBindings()
                
                # Render frame
                $this.Render()
                
                # Frame timing
                $this.WaitForNextFrame()
                
                # Update performance metrics
                $this.UpdatePerformanceMetrics()
                
                # Safety check - stop after 30 seconds if no input
                $loopCount++
                if ($loopCount -gt 1800) {  # 60 FPS * 30 seconds
                    $this.Logger.Info("Application", "Run", "Auto-stopping after 30 seconds")
                    $this.Stop()
                }
            }
        } catch {
            $this.Logger.Error("Application", "Run", "Error in main loop", @{
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        } finally {
            $this.Cleanup()
        }
    }
    
    # Stop application
    [void] Stop() {
        $this.Logger.Info("Application", "Stop", "Stopping application")
        $this._running = $false
    }
    
    # Process input
    hidden [void] ProcessInput() {
        # Check for window resize
        $this.CheckWindowResize()

        # Process input - check for exit keys first
        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                # Ctrl+Q to quit (check before InputManager)
                if ($key.Key -eq [System.ConsoleKey]::Q -and
                    $key.Modifiers -eq [System.ConsoleModifiers]::Control) {
                    $this.Stop()
                    return
                }

                # Route input to component tree first
                # Component tree includes screens, widgets, and editors
                # If they don't handle it, fall through to global shortcuts
                $this.RootComponent.HandleKeyPress($key)
            }
        } catch {
            # KeyAvailable might not work in all environments - that's okay
            $this.Logger.Trace("Application", "ProcessInput", "KeyAvailable not supported", @{
                Error = $_.Exception.Message
            })
        }
    }
    
    # Check for terminal resize
    hidden [void] CheckWindowResize() {
        $currentWidth = [Console]::WindowWidth
        $currentHeight = [Console]::WindowHeight
        
        if ($currentWidth -ne $this.RenderEngine._terminal.Width -or 
            $currentHeight -ne $this.RenderEngine._terminal.Height) {
            
            $this.Logger.Info("Application", "CheckWindowResize", "Terminal resized", @{
                OldSize = "$($this.RenderEngine._terminal.Width)x$($this.RenderEngine._terminal.Height)"
                NewSize = "${currentWidth}x${currentHeight}"
            })
            
            # Update terminal dimensions
            $this.RenderEngine._terminal.UpdateDimensions()
            
            # Recreate render buffer
            $this.RenderEngine._buffer = [RenderBuffer]::new($currentWidth, $currentHeight)
            
            # Update root component bounds
            $this.RootComponent.SetBounds(0, 0, $currentWidth, $currentHeight)
            
            # Refresh focusable components
            $this.InputManager.GetFocusManager().RefreshFocusableList($this.RootComponent)
        }
    }
    
    # Update data bindings
    hidden [void] UpdateBindings() {
        # This is where reactive data updates would be processed
        # For now, it's a placeholder for future implementation
    }
    
    # Render frame
    hidden [void] Render() {
        $timer = $this.Logger.MeasurePerformance("Application", "RenderFrame")
        
        try {
            $this.RenderEngine.BeginFrame()
            
            # Render component tree
            $this.RootComponent.Render()
            
            # Show FPS counter if debug mode
            if ($this.Logger.GlobalLevel -le [LogLevel]::Debug) {
                $this.RenderDebugInfo()
            }
            
            $this.RenderEngine.EndFrame()
            
        } finally {
            $timer.Dispose()
        }
    }
    
    # Render debug information
    hidden [void] RenderDebugInfo() {
        $fps = $(if ($this._frameCount -gt 0) {
            [Math]::Round(1000.0 / ($this._totalFrameTime / $this._frameCount), 1)
        } else { 0 })
        
        $uptime = [DateTime]::Now - $this._startTime
        $uptimeStr = "{0:D2}:{1:D2}:{2:D2}" -f $uptime.Hours, $uptime.Minutes, $uptime.Seconds
        
        $debugInfo = "FPS: $fps | Frame: $($this._frameCount) | Uptime: $uptimeStr"
        
        # Draw in top-right corner
        $x = $this.RenderEngine._terminal.Width - $debugInfo.Length - 2
        $y = 0
        
        if ($x -gt 0) {
            $this.RenderEngine._terminal.WriteAt($x, $y, $debugInfo, [Colors]::BrightBlack, "")
        }
    }
    
    # Wait for next frame
    hidden [void] WaitForNextFrame() {
        $elapsed = $this._frameTimer.Elapsed.TotalMilliseconds
        $sleepTime = $this._targetFrameTime - $elapsed
        
        if ($sleepTime -gt 0) {
            [System.Threading.Thread]::Sleep([int]$sleepTime)
        }
    }
    
    # Update performance metrics
    hidden [void] UpdatePerformanceMetrics() {
        $frameTime = $this._frameTimer.Elapsed.TotalMilliseconds
        $this._frameCount++
        $this._totalFrameTime += $frameTime
        
        # Log performance every 60 frames
        if ($this._frameCount % 60 -eq 0) {
            $avgFrameTime = $this._totalFrameTime / 60
            $fps = 1000.0 / $avgFrameTime
            
            $this.Logger.Debug("Application", "Performance", "Frame statistics", @{
                AverageFrameMs = [Math]::Round($avgFrameTime, 2)
                FPS = [Math]::Round($fps, 1)
                TotalFrames = $this._frameCount
            })
            
            # Reset for next batch
            $this._totalFrameTime = 0
        }
    }
    
    # Cleanup
    hidden [void] Cleanup() {
        $this.Logger.Info("Application", "Cleanup", "Cleaning up application")
        
        try {
            # Stop input manager
            $this.InputManager.Stop()
            
            # Cleanup render engine
            $this.RenderEngine.Cleanup()
            
            # Log final statistics
            $totalUptime = [DateTime]::Now - $this._startTime
            $this.Logger.Info("Application", "Cleanup", "Application statistics", @{
                TotalFrames = $this._frameCount
                TotalUptime = $totalUptime.ToString()
                Title = $this.Title
            })
            
            # Dispose logger
            $this.Logger.Dispose()
            
        } catch {
            Write-Error "Cleanup failed: $_"
        }
    }
}

# Application builder for fluent API
class ApplicationBuilder {
    hidden [Application]$_app
    
    ApplicationBuilder() {
        $this._app = [Application]::new()
    }
    
    ApplicationBuilder([string]$title) {
        $this._app = [Application]::new($title)
    }
    
    [ApplicationBuilder] Title([string]$title) {
        $this._app.Title = $title
        return $this
    }
    
    [ApplicationBuilder] Root([Component]$component) {
        $this._app.SetRoot($component)
        return $this
    }
    
    [ApplicationBuilder] Theme([string]$themeName) {
        $this._app.ThemeManager.SetTheme($themeName)
        return $this
    }
    
    [ApplicationBuilder] LogLevel([LogLevel]$level) {
        $this._app.Logger.GlobalLevel = $level
        return $this
    }
    
    [ApplicationBuilder] LogToConsole() {
        $this._app.Logger.EnableConsole = $true
        return $this
    }
    
    [ApplicationBuilder] Configure([scriptblock]$configBlock) {
        & $configBlock $this._app
        return $this
    }
    
    [Application] Build() {
        return $this._app
    }
    
    [void] Run() {
        $this._app.Run()
    }
}

# Helper function for creating applications
function New-SpeedTUIApp {
    param(
        [string]$Title = "SpeedTUI Application",
        [scriptblock]$AppDefinition
    )
    
    $builder = [ApplicationBuilder]::new($Title)
    
    if ($AppDefinition) {
        $result = & $AppDefinition $builder
        # Ensure we return the builder, not whatever the scriptblock returned
        if ($result -is [ApplicationBuilder]) {
            return $result
        }
    }
    
    return $builder
}