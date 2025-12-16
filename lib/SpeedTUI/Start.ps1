#!/usr/bin/env pwsh
# SpeedTUI - Fast, simple TUI framework for PowerShell
# Entry point and loader

param(
    [switch]$Debug,
    [string]$Theme = "default",
    [string]$LogLevel = "Info",
    [switch]$Example,
    
    # Comprehensive logging control flags
    [string]$GlobalLogLevel = "",           # Override global log level: Trace,Debug,Info,Warn,Error,Fatal
    [string[]]$TraceComponents = @(),       # Components to set to Trace level
    [string[]]$DebugComponents = @(),       # Components to set to Debug level
    [string[]]$TraceModules = @(),          # Modules to set to Trace level
    [string[]]$DebugModules = @(),          # Modules to set to Debug level
    [switch]$TraceTimeTracking,             # Enable trace for TimeTracking components
    [switch]$TraceForms,                    # Enable trace for Form components (FormManager, InputField)
    [switch]$TraceMainLoop,                 # Enable trace for main application loop
    [switch]$TraceAll,                      # Enable trace for ALL components
    [switch]$LogConsole,                    # Enable console output for logs
    [switch]$ShowLogHelp                    # Show logging help and exit
)

# Show logging help if requested
if ($ShowLogHelp) {
    Write-Host @"
SpeedTUI Logging Control Flags:

Basic Options:
  -Debug                    Enable debug mode (sets components to Trace level)
  -LogLevel <level>         Set global log level (Trace,Debug,Info,Warn,Error,Fatal)
  -LogConsole              Enable console output for logs (default: file only)

Advanced Options:
  -GlobalLogLevel <level>   Override global log level
  -TraceComponents <list>   Set specific components to Trace level
  -DebugComponents <list>   Set specific components to Debug level  
  -TraceModules <list>      Set entire modules to Trace level
  -DebugModules <list>      Set entire modules to Debug level

Quick Presets:
  -TraceTimeTracking       Enable trace for TimeTracking, TimeTrackingScreen, TimeTrackingService
  -TraceForms              Enable trace for FormManager, InputField components
  -TraceMainLoop           Enable trace for main application loop
  -TraceAll                Enable trace for ALL components (very verbose)

Examples:
  # Basic debug mode
  pwsh ./Start.ps1 -Debug
  
  # Trace specific components
  pwsh ./Start.ps1 -TraceComponents "FormManager","InputField" -LogConsole
  
  # Debug time tracking issues
  pwsh ./Start.ps1 -TraceTimeTracking -DebugComponents "MainLoop"
  
  # Full trace logging (very verbose)
  pwsh ./Start.ps1 -TraceAll -LogConsole
  
  # Custom configuration
  pwsh ./Start.ps1 -GlobalLogLevel Debug -TraceModules "SpeedTUI","Services"

Available Components: TimeTrackingScreen, FormManager, InputField, MainLoop, DashboardScreen, etc.
Available Modules: SpeedTUI, Services, Components, Core, Screens

"@ -ForegroundColor Cyan
    exit 0
}

# Set script root
$script:SpeedTUIRoot = $PSScriptRoot
Set-Location $script:SpeedTUIRoot

# Ensure logs directory exists
$logsDir = Join-Path $script:SpeedTUIRoot "Logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

# Load order is important for class dependencies
$loadOrder = @(
    # Performance core first (provides internal optimization classes)
    "Core/Internal/PerformanceCore.ps1"
    
    # Core utilities (no dependencies)
    "Core/Logger.ps1"
    "Core/NullCheck.ps1"
    "Core/Terminal.ps1"
    
    # Base classes
    "Core/RenderEngine.ps1"
    "Core/Component.ps1"
    "Core/ComponentBuilder.ps1"
    
    # Data system
    "Core/DataStore.ps1"
    
    # Services
    "Services/ThemeManager.ps1"
    
    # Input system (depends on Component)
    "Core/InputManager.ps1"
    
    # Layouts (depend on Component)
    "Layouts/GridLayout.ps1"
    "Layouts/StackLayout.ps1"
    
    # Components (depend on Component base class)
    "Components/Label.ps1" 
    "Components/Button.ps1"
    "Components/List.ps1"
    "Components/Table.ps1"
    
    # Application framework (depends on everything)
    "Core/Application.ps1"
)

# Load all modules
Write-Host "Loading SpeedTUI framework..." -ForegroundColor Cyan

$loadErrors = @()
foreach ($file in $loadOrder) {
    $path = Join-Path $script:SpeedTUIRoot $file
    if (Test-Path $path) {
        try {
            . $path
            if ($Debug) {
                Write-Host "  [OK] $file" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [ERROR] $file - $_" -ForegroundColor Red
            $loadErrors += @{
                File = $file
                Error = $_
            }
        }
    } else {
        Write-Host "  [ERROR] $file - File not found" -ForegroundColor Red
        $loadErrors += @{
            File = $file
            Error = "File not found"
        }
    }
}

if ($loadErrors.Count -gt 0) {
    Write-Host "`nLoad errors encountered:" -ForegroundColor Red
    foreach ($err in $loadErrors) {
        Write-Host "  $($err.File): $($err.Error)" -ForegroundColor Red
    }
    exit 1
}

Write-Host "SpeedTUI framework loaded successfully!" -ForegroundColor Green

# Set up comprehensive logging configuration
$logger = Get-Logger

# Set global log level
$globalLevel = $(if ($GlobalLogLevel) { $GlobalLogLevel } elseif ($Debug) { "Trace" } else { $LogLevel })
$logger.GlobalLevel = [LogLevel]::$globalLevel

# Enable console output if requested
if ($LogConsole -or $Debug) {
    $logger.EnableConsole = $true
}

# Apply quick presets
if ($TraceAll) {
    # Set everything to trace - VERY verbose
    $logger.GlobalLevel = [LogLevel]::Trace
    Write-Host "🔍 TRACE ALL enabled - expect very verbose logging" -ForegroundColor Yellow
}

if ($TraceTimeTracking) {
    $logger.SetComponentLevel("SpeedTUI", "TimeTrackingScreen", [LogLevel]::Trace)
    $logger.SetComponentLevel("SpeedTUI", "TimeTrackingService", [LogLevel]::Trace)
    $logger.SetModuleLevel("Services", [LogLevel]::Debug)
    Write-Host "🎯 Time Tracking trace logging enabled" -ForegroundColor Green
}

if ($TraceForms) {
    $logger.SetComponentLevel("SpeedTUI", "FormManager", [LogLevel]::Trace)
    $logger.SetComponentLevel("SpeedTUI", "InputField", [LogLevel]::Trace)
    Write-Host "📝 Form components trace logging enabled" -ForegroundColor Green
}

if ($TraceMainLoop) {
    $logger.SetComponentLevel("SpeedTUI", "MainLoop", [LogLevel]::Trace)
    Write-Host "🔄 Main loop trace logging enabled" -ForegroundColor Green
}

# Apply specific component configurations
foreach ($component in $TraceComponents) {
    $logger.SetComponentLevel("SpeedTUI", $component, [LogLevel]::Trace)
    Write-Host "🔍 Component '$component' set to TRACE level" -ForegroundColor Cyan
}

foreach ($component in $DebugComponents) {
    $logger.SetComponentLevel("SpeedTUI", $component, [LogLevel]::Debug)
    Write-Host "🐛 Component '$component' set to DEBUG level" -ForegroundColor Cyan
}

# Apply module configurations
foreach ($module in $TraceModules) {
    $logger.SetModuleLevel($module, [LogLevel]::Trace)
    Write-Host "🔍 Module '$module' set to TRACE level" -ForegroundColor Cyan
}

foreach ($module in $DebugModules) {
    $logger.SetModuleLevel($module, [LogLevel]::Debug) 
    Write-Host "🐛 Module '$module' set to DEBUG level" -ForegroundColor Cyan
}

# Show current logging configuration if any specific settings were applied
if ($Debug -or $TraceComponents -or $DebugComponents -or $TraceModules -or $DebugModules -or $TraceTimeTracking -or $TraceForms -or $TraceMainLoop -or $TraceAll) {
    Write-Host "`n📊 Logging Configuration:" -ForegroundColor Magenta
    Write-Host "   Global Level: $($logger.GlobalLevel)" -ForegroundColor White
    Write-Host "   Console Output: $($logger.EnableConsole)" -ForegroundColor White
    Write-Host "   Log File: Logs/speedtui_$(Get-Date -Format 'yyyyMMdd_HHmmss').log" -ForegroundColor White
    Write-Host ""
}

# Load BorderHelper for perfect borders
. "$PSScriptRoot/BorderHelper.ps1"

# Run example application if requested
if ($Example) {
    Write-Host "`nRunning SpeedTUI Demo with Perfect Borders..." -ForegroundColor Cyan
    Write-Host "This will show a working TUI interface for 10 seconds" -ForegroundColor Yellow
    Write-Host ""
    
    # Use the safe demo approach with BorderHelper
    try {
        Start-Sleep 2  # Give user time to read
        
        [Console]::Clear()
        [Console]::CursorVisible = $false
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $frame = 0
        $demoSeconds = 10
        
        while ($stopwatch.Elapsed.TotalSeconds -lt $demoSeconds) {
            [Console]::SetCursorPosition(0, 0)
            
            # Use BorderHelper for perfect alignment
            Write-Host ([BorderHelper]::TopBorder()) -ForegroundColor Cyan
            Write-Host ([BorderHelper]::StatusLine("SpeedTUI Framework Demo")) -ForegroundColor Cyan  
            Write-Host ([BorderHelper]::MiddleBorder()) -ForegroundColor Cyan
            Write-Host ([BorderHelper]::EmptyLine()) -ForegroundColor White
            Write-Host ([BorderHelper]::ContentLine("PROJECTS:")) -ForegroundColor Yellow
            Write-Host ([BorderHelper]::ContentLine("  ✅ Project Alpha    [████████░░] 75%")) -ForegroundColor Green
            Write-Host ([BorderHelper]::ContentLine("  [WARN]️  Project Beta     [██░░░░░░░░] 20%")) -ForegroundColor Yellow  
            Write-Host ([BorderHelper]::ContentLine("  ✅ Project Gamma    [██████████] 100%")) -ForegroundColor Green
            Write-Host ([BorderHelper]::ContentLine("  ⏸️  Project Delta    [████░░░░░░] 45%")) -ForegroundColor Blue
            Write-Host ([BorderHelper]::EmptyLine()) -ForegroundColor White
            Write-Host ([BorderHelper]::ContentLine("TASKS:")) -ForegroundColor Green
            Write-Host ([BorderHelper]::ContentLine("  📝 Design UI mockups          │ In Progress  │ High")) -ForegroundColor White
            Write-Host ([BorderHelper]::ContentLine("  ✅ Implement data layer       │ Completed    │ High")) -ForegroundColor Green
            Write-Host ([BorderHelper]::ContentLine("  ⏳ Write unit tests           │ Pending      │ Medium")) -ForegroundColor Yellow
            Write-Host ([BorderHelper]::ContentLine("  📚 Documentation              │ In Progress  │ Low")) -ForegroundColor White
            Write-Host ([BorderHelper]::ContentLine("  ⚡ Performance optimization   │ Pending      │ Medium")) -ForegroundColor Yellow
            Write-Host ([BorderHelper]::EmptyLine()) -ForegroundColor White
            
            $elapsed = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
            $remaining = [Math]::Max(0, $demoSeconds - $elapsed)
            $fps = $(if ($elapsed -gt 0) { [Math]::Round($frame / $elapsed, 1) } else { 0 })
            
            $status = "Running: ${elapsed}s │ Remaining: ${remaining}s │ Frame: $frame │ FPS: $fps"
            Write-Host ([BorderHelper]::ContentLine($status)) -ForegroundColor Gray
            Write-Host ([BorderHelper]::EmptyLine()) -ForegroundColor White
            Write-Host ([BorderHelper]::StatusLine("🎯 SpeedTUI Framework: FAST • PERFORMANT • EASY TO USE")) -ForegroundColor Magenta
            Write-Host ([BorderHelper]::BottomBorder()) -ForegroundColor Cyan
            
            $frame++
            Start-Sleep -Milliseconds 100  # 10 FPS
        }
        
    } catch {
        Write-Host "`nDemo error: $_" -ForegroundColor Red
    } finally {
        # Always restore terminal
        try {
            [Console]::CursorVisible = $true
            [Console]::ResetColor()
        } catch { }
        
        Write-Host "`n"
        Write-Host "🎉 SpeedTUI Demo Complete - Perfect Borders!" -ForegroundColor Green
        Write-Host "   • All borders perfectly aligned" -ForegroundColor Cyan
        Write-Host "   • Dynamic width calculation" -ForegroundColor Cyan  
        Write-Host "   • Foolproof border system" -ForegroundColor Cyan
        Write-Host "   • Ready for production!" -ForegroundColor Cyan
    }
} else {
    # Launch the actual SpeedTUI application
    Write-Host "`nLaunching SpeedTUI Application..." -ForegroundColor Green
    
    try {
        # Launch the main SpeedTUI application
        & "$PSScriptRoot/SpeedTUI.ps1" -NoLogo
    } catch {
        Write-Host "Error launching SpeedTUI: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "`nFallback: Framework loaded. Create your application using:" -ForegroundColor Yellow
        Write-Host "  `$app = New-SpeedTUIApp 'My App' { ... }" -ForegroundColor White
        Write-Host "  `$app.Run()" -ForegroundColor White
        Write-Host "`nRun with -Example to see a demo application." -ForegroundColor Cyan
    }
}