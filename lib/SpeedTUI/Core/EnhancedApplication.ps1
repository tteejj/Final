# SpeedTUI Enhanced Application - Flicker-free screen-based application with RenderEngine integration
# Implements EVOLUTION.md vision while maintaining compatibility with existing screen architecture

using namespace System.Collections.Generic

# Load dependencies
. "$PSScriptRoot/OptimizedRenderEngine.ps1"  # Use optimized engine for flicker-free rendering!
. "$PSScriptRoot/SimplifiedTerminal.ps1"  # Use simplified terminal for speed!
. "$PSScriptRoot/Logger.ps1"

<#
.SYNOPSIS
Enhanced SpeedTUI Application for screen-based applications with integrated RenderEngine

.DESCRIPTION
This class bridges the gap between the existing screen-based architecture and the new
RenderEngine system. It eliminates flickering by:
- Using RenderEngine for all screen output instead of Clear-Host + Write-Host
- Implementing true differential rendering
- Maintaining backward compatibility with existing screens
- Following EVOLUTION.md vision of simple APIs with hidden performance optimizations

.EXAMPLE
# Replace the main loop in SpeedTUI.ps1 with:
$app = [EnhancedApplication]::new()
$app.Run([DashboardScreen]::new())
#>
class EnhancedApplication {
    # Core systems (hidden performance layer)
    hidden [OptimizedRenderEngine]$_renderEngine
    hidden [SimplifiedTerminal]$_terminal  
    hidden [object]$_logger
    hidden [object]$_performanceMonitor
    
    # Application state 
    hidden [object]$_currentScreen
    hidden [bool]$_running = $false
    hidden [bool]$_initialized = $false
    hidden [bool]$_needsRefresh = $false
    
    # Performance tracking (transparent to developer)
    hidden [int]$_frameCount = 0
    hidden [double]$_totalFrameTime = 0
    hidden [DateTime]$_startTime = [DateTime]::MinValue
    
    EnhancedApplication() {
        $this._logger = Get-Logger
        $this._logger.Info("SpeedTUI", "EnhancedApplication", "Creating enhanced application with RenderEngine integration")
        
        try {
            # Initialize core systems
            $this._terminal = [SimplifiedTerminal]::GetInstance()
            $this._renderEngine = [OptimizedRenderEngine]::new()
            
            # Get performance monitor if available
            if (Get-Command "Get-PerformanceMonitor" -ErrorAction SilentlyContinue) {
                $this._performanceMonitor = Get-PerformanceMonitor
            }
            
            $this._logger.Info("SpeedTUI", "EnhancedApplication", "Enhanced application created successfully")
        } catch {
            $this._logger.Error("SpeedTUI", "EnhancedApplication", "Failed to create application", @{
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    <#
    .SYNOPSIS
    Initialize application systems
    #>
    [void] Initialize() {
        if ($this._initialized) { return }
        
        $this._logger.Debug("SpeedTUI", "EnhancedApplication", "Initializing application systems")
        
        try {
            # Initialize terminal and render engine
            $this._terminal.Initialize()
            $this._renderEngine.Initialize()
            
            # CLEAR SCREEN PROPERLY - like @praxis VT100 engine
            # Send clear screen + home position to eliminate startup messages
            Write-Host "`e[2J`e[H" -NoNewline
            [Console]::SetCursorPosition(0, 0)
            
            # Update render engine dimensions
            $this._renderEngine.UpdateDimensions()
            
            $this._initialized = $true
            $this._startTime = [DateTime]::Now
            
            $this._logger.Info("SpeedTUI", "EnhancedApplication", "Application initialized", @{
                TerminalSize = "$($this._terminal.Width)x$($this._terminal.Height)"
            })
        } catch {
            $this._logger.Error("SpeedTUI", "EnhancedApplication", "Failed to initialize", @{
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    <#
    .SYNOPSIS
    Run application with flicker-free rendering
    
    .PARAMETER startScreen
    Initial screen to display
    #>
    [void] Run([object]$startScreen) {
        $this._logger.Info("SpeedTUI", "EnhancedApplication", "Starting enhanced application", @{
            StartScreen = $startScreen.GetType().Name
        })
        
        try {
            $this.Initialize()
            $this._currentScreen = $startScreen
            $this._running = $true
            $refreshNeeded = $true
            
            # Enhanced main loop with RenderEngine integration
            while ($this._running) {
                $frameStart = [DateTime]::Now
                
                try {
                    # Render using RenderEngine (eliminates flickering)
                    if ($refreshNeeded) {
                        $this._needsRefresh = $true
                        $this.RenderScreenFlickerFree()
                        $refreshNeeded = $false
                        $this._needsRefresh = $false
                    }
                    
                    # Handle input with proper delegation
                    if ([Console]::KeyAvailable) {
                        $inputResult = $this.HandleInputEnhanced()
                        
                        # Process input results
                        switch ($inputResult) {
                            "EXIT" {
                                $this._running = $false
                                break
                            }
                            "REFRESH" {
                                $refreshNeeded = $true
                                break
                            }
                            "SWITCH_TIMETRACKING" {
                                $this._currentScreen = [TimeTrackingScreen]::new()
                                $refreshNeeded = $true
                                break  
                            }
                            "SWITCH_DASHBOARD" {
                                $this._currentScreen = [DashboardScreen]::new()
                                $refreshNeeded = $true
                                break
                            }
                            "SWITCH_MONITORING" {
                                $this._currentScreen = [MonitoringScreen]::new()
                                $refreshNeeded = $true
                                break
                            }
                            default {
                                # Any other result triggers refresh
                                if ($inputResult) {
                                    $refreshNeeded = $true
                                }
                            }
                        }
                    }
                    
                    # Performance tracking (hidden from developer)
                    $frameTime = ([DateTime]::Now - $frameStart).TotalMilliseconds
                    $this._totalFrameTime += $frameTime
                    $this._frameCount++
                    
                    # Log performance occasionally
                    if ($this._frameCount % 100 -eq 0) {
                        # Performance tracking disabled for speed
                    }
                    
                    # Frame rate limiting (60 FPS)
                    Start-Sleep -Milliseconds 16
                    
                } catch {
                    $this._logger.Error("SpeedTUI", "EnhancedApplication", "Error in main loop", @{
                        Exception = $_.Exception.Message
                        FrameCount = $this._frameCount
                    })
                    
                    # Attempt recovery
                    $refreshNeeded = $true
                    Start-Sleep -Milliseconds 100
                }
            }
            
        } catch {
            $this._logger.Fatal("SpeedTUI", "EnhancedApplication", "Critical application error", @{
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        } finally {
            $this.Cleanup()
        }
    }
    
    <#
    .SYNOPSIS
    Render current screen using RenderEngine (eliminates flickering)
    #>
    hidden [void] RenderScreenFlickerFree() {
        # Rendering screen flicker-free
        
        try {
            # Begin frame (prepares for differential rendering)
            $this._renderEngine.BeginFrame()
            
            # Request clear for screen changes
            if ($this._needsRefresh) {
                $this._renderEngine.RequestClear()
            }
            
            # Get screen content the traditional way (backward compatibility)
            $screenContent = $this._currentScreen.Render()
            
            # Render to RenderEngine buffer instead of terminal directly
            if ($screenContent -and $screenContent.Count -gt 0) {
                $lineCount = [Math]::Min($screenContent.Count, $this._terminal.Height)
                
                for ($i = 0; $i -lt $lineCount; $i++) {
                    if ($screenContent[$i]) {
                        # Write to render buffer using simplified API
                        $this._renderEngine.WriteAt(0, $i, $screenContent[$i])
                    }
                }
            }
            
            # End frame - this does the differential rendering magic!
            # Only changed characters are written to terminal
            $this._renderEngine.EndFrame()
            
            # Screen rendered successfully
            
        } catch {
            $this._logger.Error("SpeedTUI", "EnhancedApplication", "Failed to render screen", @{
                ScreenType = $this._currentScreen.GetType().Name
                Exception = $_.Exception.Message
            })
            
            # Fallback to traditional rendering if RenderEngine fails
            try {
                Clear-Host
                $screenContent = $this._currentScreen.Render()
                if ($screenContent) {
                    foreach ($line in $screenContent) {
                        Write-Host $line
                    }
                }
            } catch {
                $this._logger.Error("SpeedTUI", "EnhancedApplication", "Fallback rendering also failed", @{
                    Exception = $_.Exception.Message
                })
            }
        }
    }
    
    <#
    .SYNOPSIS
    Handle input with enhanced delegation and global key handling
    #>
    hidden [string] HandleInputEnhanced() {
        $key = [Console]::ReadKey($true)
        $keyString = $key.Key.ToString()
        
        # Add modifiers
        if ($key.Modifiers -band [ConsoleModifiers]::Control) {
            $keyString = "Ctrl+$keyString"
        }
        if ($key.Modifiers -band [ConsoleModifiers]::Alt) {
            $keyString = "Alt+$keyString"
        }
        if ($key.Modifiers -band [ConsoleModifiers]::Shift) {
            $keyString = "Shift+$keyString"
        }
        
        $this._logger.Trace("SpeedTUI", "EnhancedApplication", "Key pressed", @{
            Key = $keyString
            KeyChar = [int]$key.KeyChar
            CurrentScreen = $this._currentScreen.GetType().Name
        })
        
        # Global application keys (simple API)
        switch ($keyString) {
            "Escape" { 
                return "EXIT" 
            }
            "F5" { 
                return "REFRESH" 
            }
            "Ctrl+Q" { 
                return "EXIT" 
            }
        }
        
        # Delegate to current screen with proper error handling
        try {
            # Maintain backward compatibility with existing screens
            if ($this._currentScreen -is [DashboardScreen]) {
                $result = $this._currentScreen.HandleInput($keyString)
                
                # Map DashboardScreen results to application actions
                switch ($result) {
                    "EXIT" { return "EXIT" }
                    "REFRESH" { return "REFRESH" }
                    "TIMETRACKING" { return "SWITCH_TIMETRACKING" }
                    "MONITORING" { return "SWITCH_MONITORING" }
                    default { return $result }
                }
            }
            elseif ($this._currentScreen -is [TimeTrackingScreen]) {
                $result = $this._currentScreen.HandleInput($keyString)
                
                # Map TimeTrackingScreen results
                switch ($result) {
                    "EXIT" { return "EXIT" }
                    "BACK" { return "SWITCH_DASHBOARD" }
                    "REFRESH" { return "REFRESH" }
                    default { return $result }
                }
            }
            elseif ($this._currentScreen -is [MonitoringScreen]) {
                $result = $this._currentScreen.HandleInput($keyString)
                
                switch ($result) {
                    "EXIT" { return "EXIT" }
                    "BACK" { return "SWITCH_DASHBOARD" }
                    "REFRESH" { return "REFRESH" }
                    default { return $result }
                }
            }
            else {
                # Generic screen handling
                if ($this._currentScreen.PSObject.Methods["HandleInput"]) {
                    return $this._currentScreen.HandleInput($keyString)
                }
            }
            
        } catch {
            $this._logger.Error("SpeedTUI", "EnhancedApplication", "Error handling input", @{
                Key = $keyString
                ScreenType = $this._currentScreen.GetType().Name
                Exception = $_.Exception.Message
            })
            return "REFRESH"  # Refresh on error
        }
        
        return $null
    }
    
    <#
    .SYNOPSIS
    Clean up application resources
    #>
    [void] Cleanup() {
        $this._logger.Info("SpeedTUI", "EnhancedApplication", "Cleaning up enhanced application")
        
        try {
            # Cleanup render engine
            if ($this._renderEngine) {
                $this._renderEngine.Cleanup()
            }
            
            # Log final performance stats (transparent to developer)
            if ($this._frameCount -gt 0) {
                $totalUptime = [DateTime]::Now - $this._startTime
                $avgFrameTime = $this._totalFrameTime / $this._frameCount
                
                $this._logger.Info("SpeedTUI", "EnhancedApplication", "Final performance statistics", @{
                    TotalFrames = $this._frameCount
                    TotalUptime = $totalUptime.ToString("hh\:mm\:ss")
                    AverageFrameTime = [Math]::Round($avgFrameTime, 2)
                    AverageFPS = [Math]::Round(1000.0 / $avgFrameTime, 1)
                    RenderEngineUsed = $true
                })
            }
            
            $this._logger.Info("SpeedTUI", "EnhancedApplication", "Enhanced application cleanup completed")
        } catch {
            $this._logger.Error("SpeedTUI", "EnhancedApplication", "Error during cleanup", @{
                Exception = $_.Exception.Message
            })
        }
    }
    
    # === Simple API Methods (EVOLUTION.md: Simple by default) ===
    
    <#
    .SYNOPSIS
    Get current screen (simple API)
    #>
    [object] GetCurrentScreen() {
        return $this._currentScreen
    }
    
    <#
    .SYNOPSIS
    Switch to a different screen (simple API)
    #>
    [void] SwitchToScreen([string]$screenType) {
        switch ($screenType) {
            "Dashboard" { $this._currentScreen = [DashboardScreen]::new() }
            "TimeTracking" { $this._currentScreen = [TimeTrackingScreen]::new() }  
            "Monitoring" { $this._currentScreen = [MonitoringScreen]::new() }
            default { 
                $this._logger.Warn("SpeedTUI", "EnhancedApplication", "Unknown screen type", @{
                    ScreenType = $screenType
                })
            }
        }
    }
    
    <#
    .SYNOPSIS
    Stop application (simple API)
    #>
    [void] Stop() {
        $this._running = $false
        $this._logger.Info("SpeedTUI", "EnhancedApplication", "Application stop requested")
    }
    
    # === Advanced API Methods (EVOLUTION.md: Progressive disclosure) ===
    
    <#
    .SYNOPSIS
    Get performance statistics (advanced feature)
    #>
    [hashtable] GetPerformanceStats() {
        $uptime = $(if ($this._startTime -ne [DateTime]::MinValue) {
            [DateTime]::Now - $this._startTime
        } else {
            [TimeSpan]::Zero
        })
        
        return @{
            FrameCount = $this._frameCount
            TotalFrameTime = $this._totalFrameTime
            AverageFrameTime = $(if ($this._frameCount -gt 0) { $this._totalFrameTime / $this._frameCount } else { 0 })
            AverageFPS = $(if ($this._frameCount -gt 0) { 1000.0 / ($this._totalFrameTime / $this._frameCount) } else { 0 })
            Uptime = $uptime.ToString("hh\:mm\:ss")
            RenderEngineIntegrated = $true
            FlickerFreeRendering = $true
        }
    }
    
    <#
    .SYNOPSIS
    Get render engine for power users (advanced API)
    #>
    [OptimizedRenderEngine] GetRenderEngine() {
        return $this._renderEngine
    }
    
    <#
    .SYNOPSIS
    Enable detailed logging (developer helper)
    #>
    [void] EnableDebugMode() {
        if ($this._logger) {
            $this._logger.GlobalLevel = [LogLevel]::Trace
            $this._logger.Info("SpeedTUI", "EnhancedApplication", "Debug mode enabled - detailed logging active")
        }
    }
    
    <#
    .SYNOPSIS
    Show performance overlay (debugging helper)
    #>
    [void] ShowPerformanceOverlay([bool]$show = $true) {
        # This would show FPS and performance info on screen
        # Implementation would add a debug region to the render engine
        $this._logger.Debug("SpeedTUI", "EnhancedApplication", "Performance overlay", @{
            Enabled = $show
        })
    }
}