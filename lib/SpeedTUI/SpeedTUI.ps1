# SpeedTUI Main Application Entry Point
# A high-performance PowerShell Terminal User Interface

param(
    [switch]$Debug,
    [switch]$NoLogo,
    [string]$StartScreen = "Dashboard",
    [switch]$Monitor,
    [switch]$Version
)

# Set error handling
$ErrorActionPreference = "Stop"

# Script location setup
$SpeedTUIRoot = $PSScriptRoot
Set-Location $SpeedTUIRoot

# Version information
$SpeedTUIVersion = "1.0.0-Enhanced"
$SpeedTUIBuild = "$(Get-Date -Format 'yyyyMMdd')"

if ($Version) {
    Write-Host "SpeedTUI Enhanced Version $SpeedTUIVersion (Build $SpeedTUIBuild)" -ForegroundColor Green
    Write-Host "Features: RenderEngine Integration, Flicker-Free Rendering, Performance Optimizations" -ForegroundColor Cyan
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Green
    exit 0
}

# Display logo unless suppressed
if (-not $NoLogo) {
    $logo = @(
        "",
        "  ███████╗██████╗ ███████╗███████╗██████╗ ████████╗██╗   ██╗██╗",
        "  ██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗╚══██╔══╝██║   ██║██║",
        "  ███████╗██████╔╝█████╗  █████╗  ██║  ██║   ██║   ██║   ██║██║",
        "  ╚════██║██╔═══╝ ██╔══╝  ██╔══╝  ██║  ██║   ██║   ██║   ██║██║",
        "  ███████║██║     ███████╗███████╗██████╔╝   ██║   ╚██████╔╝██║",
        "  ╚══════╝╚═╝     ╚══════╝╚══════╝╚═════╝    ╚═╝    ╚═════╝ ╚═╝",
        "",
        "         PowerShell Terminal User Interface - ENHANCED",
        "           🚀 Flicker-Free • ⚡ Performance Optimized",
        "                       Version $SpeedTUIVersion",
        ""
    )
    
    Write-Host ($logo -join "`n") -ForegroundColor Cyan
}

# Initialize performance monitoring
Write-Host "Initializing SpeedTUI..." -ForegroundColor Green

try {
    # Load core components IN CORRECT ORDER
    Write-Host "Loading enhanced core components..." -ForegroundColor Gray
    . "$SpeedTUIRoot/Core/Logger.ps1"
    . "$SpeedTUIRoot/Core/PerformanceMonitor.ps1"
    . "$SpeedTUIRoot/Core/NullCheck.ps1"
    
    # Load performance optimizations first
    . "$SpeedTUIRoot/Core/Internal/PerformanceCore.ps1"
    . "$SpeedTUIRoot/Core/SimplifiedTerminal.ps1"  # Use simplified terminal for speed!
    . "$SpeedTUIRoot/Core/OptimizedRenderEngine.ps1"  # Use optimized engine for flicker-free rendering!
    
    # Load base components and helpers
    . "$SpeedTUIRoot/Core/Component.ps1"  # Use enhanced component with caching!
    . "$SpeedTUIRoot/BorderHelper.ps1"
    
    # Load base classes and models  
    Write-Host "Loading data models..." -ForegroundColor Gray
    . "$SpeedTUIRoot/Models/BaseModel.ps1"
    . "$SpeedTUIRoot/Models/TimeEntry.ps1"
    . "$SpeedTUIRoot/Models/Command.ps1"
    . "$SpeedTUIRoot/Models/Project.ps1"
    . "$SpeedTUIRoot/Models/Task.ps1"
    . "$SpeedTUIRoot/Core/DataStore.ps1"
    
    # Load services
    Write-Host "Loading services..." -ForegroundColor Gray
    . "$SpeedTUIRoot/Services/DataService.ps1"  
    . "$SpeedTUIRoot/Services/ConfigurationService.ps1"
    . "$SpeedTUIRoot/Services/TimeTrackingService.ps1"
    . "$SpeedTUIRoot/Services/CommandService.ps1"
    
    # Load components
    Write-Host "Loading components..." -ForegroundColor Gray
    . "$SpeedTUIRoot/Components/InputField.ps1"
    . "$SpeedTUIRoot/Components/FormManager.ps1"
    
    # Initialize performance monitoring
    $global:perfMonitor = Get-PerformanceMonitor
    $global:perfMonitor.Enable()
    
    # Create logger
    $global:logger = [object]::GetInstance()
    $global:perfMonitor.SetLogger($global:logger)
    
    # Configure logging based on debug mode
    if ($Debug) {
        $global:logger.GlobalLevel = [LogLevel]::Trace
        # Set specific module levels for detailed debugging
        $global:logger.SetModuleLevel("SpeedTUI", [LogLevel]::Trace)
        $global:logger.SetComponentLevel("SpeedTUI", "TimeTrackingScreen", [LogLevel]::Trace)
        $global:logger.SetComponentLevel("SpeedTUI", "FormManager", [LogLevel]::Trace)
        $global:logger.SetComponentLevel("SpeedTUI", "InputField", [LogLevel]::Trace)
        
        $global:logger.Debug("SpeedTUI", "Startup", "Debug logging enabled with modular levels")
    }
    
    # Record startup timing
    $startupTiming = Start-PerformanceTiming "Application.Startup"
    
    $global:logger.Info("SpeedTUI", "Startup", "SpeedTUI $SpeedTUIVersion starting up")
    
    # Load screens
    Write-Host "Loading screens..." -ForegroundColor Gray
    . "$SpeedTUIRoot/Screens/DashboardScreen.ps1"
    . "$SpeedTUIRoot/Screens/MonitoringScreen.ps1"
    . "$SpeedTUIRoot/Screens/TimeTrackingScreen.ps1"
    
    # Load ENHANCED APPLICATION
    Write-Host "Loading enhanced application..." -ForegroundColor Gray
    . "$SpeedTUIRoot/Core/EnhancedApplication.ps1"
    
    # Initialize configuration
    Write-Host "Loading configuration..." -ForegroundColor Gray
    $global:configService = [ConfigurationService]::new()
    
    # Set debug mode if requested
    if ($Debug) {
        $global:configService.EnableDebugMode()
        $global:logger.Info("SpeedTUI", "Startup", "Debug mode enabled")
    }
    
    # Create ENHANCED APPLICATION (no more flickering!)
    Write-Host "Creating enhanced application..." -ForegroundColor Green
    $app = [EnhancedApplication]::new()
    
    # Enable debug mode if requested
    if ($Debug) {
        $app.EnableDebugMode()
        Write-Host "🔍 Debug mode enabled" -ForegroundColor Yellow
    }
    
    # Create starting screen (using global scope due to PowerShell variable assignment quirk)
    Write-Host "Creating starting screen..." -ForegroundColor Gray
    try {
        $global:applicationStartScreen = switch ($StartScreen.ToLower()) {
            "monitor" { [MonitoringScreen]::new() }
            "timetracking" { [TimeTrackingScreen]::new() }
            default { [DashboardScreen]::new() }
        }
        Write-Host "Screen created: $($global:applicationStartScreen.GetType().Name)" -ForegroundColor Green
    } catch {
        Write-Host "ERROR creating screen: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
    
    # Override with monitor if requested
    if ($Monitor) {
        $global:applicationStartScreen = [MonitoringScreen]::new()
        Write-Host "Overriding with MonitoringScreen" -ForegroundColor Gray
    }
    
    Stop-PerformanceTiming $startupTiming
    $global:logger.Info("SpeedTUI", "Startup", "Enhanced application startup completed")
    
    # Show enhancement info
    Write-Host "🚀 Enhanced Features Active:" -ForegroundColor Yellow
    Write-Host "   • RenderEngine Integration (eliminates flickering)" -ForegroundColor Green
    Write-Host "   • Performance Optimizations" -ForegroundColor Green
    Write-Host "   • Differential Rendering" -ForegroundColor Green
    Write-Host ""
    Write-Host "🎉 Starting flicker-free application..." -ForegroundColor Green
    
    # CLEAR SCREEN AFTER STARTUP MESSAGES - like @praxis does
    Start-Sleep -Milliseconds 1000  # Let user see the messages briefly
    [Console]::Clear()
    [Console]::SetCursorPosition(0, 0)
    
    # RUN THE ENHANCED APPLICATION (flicker-free!)
    try {
        $app.Run($global:applicationStartScreen)
    } catch {
        Write-Host ""
        Write-Host "❌ Enhanced application error:" -ForegroundColor Red
        Write-Host "   $($_.Exception.Message)" -ForegroundColor Red
        
        if ($Debug) {
            Write-Host ""
            Write-Host "🔍 Debug Information:" -ForegroundColor Yellow
            Write-Host "   Exception: $($_.Exception.GetType().Name)" -ForegroundColor Gray
            Write-Host "   Stack Trace:" -ForegroundColor Gray
            Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        }
        
        $global:logger.Error("SpeedTUI", "EnhancedApp", "Enhanced application error", @{
            Exception = $_.Exception.Message
            StackTrace = $_.ScriptStackTrace
        })
    }
    
    # Shutdown  
    Write-Host "`n🛑 Shutting down Enhanced SpeedTUI..." -ForegroundColor Yellow
    
    # Record shutdown metrics
    $global:perfMonitor.IncrementCounter("application.shutdown", @{})
    
    # Generate final performance report if in debug mode
    if ($global:configService.IsDebugMode()) {
        Write-Host "Generating performance report..." -ForegroundColor Gray
        $report = $global:perfMonitor.GenerateReport()
        
        $reportFile = "Logs/SpeedTUI_Final_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        
        # Ensure directory exists
        $dir = Split-Path $reportFile -Parent
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
        
        Set-Content -Path $reportFile -Value $report
        Write-Host "Performance report saved to: $reportFile" -ForegroundColor Green
    }
    
    $global:logger.Info("SpeedTUI", "Shutdown", "Enhanced application shutdown completed")
    
    Write-Host "🎉 Thank you for using Enhanced SpeedTUI!" -ForegroundColor Green
    
} catch {
    Write-Host "Fatal error during startup: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace:" -ForegroundColor Red
    Write-Host $_.Exception.StackTrace -ForegroundColor Red
    
    if ($global:logger) {
        $global:logger.Fatal("SpeedTUI", "Startup", "Fatal startup error: $($_.Exception.Message)")
    }
    
    exit 1
} finally {
    # Cleanup
    if ($global:perfMonitor) {
        $global:perfMonitor.Disable()
    }
}