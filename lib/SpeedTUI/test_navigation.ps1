# Quick test of arrow key navigation
param([switch]$Debug)

$SpeedTUIRoot = $PSScriptRoot
Set-Location $SpeedTUIRoot

# Load minimal components for testing
. "$SpeedTUIRoot/Core/Logger.ps1"
. "$SpeedTUIRoot/Core/PerformanceMonitor.ps1"
. "$SpeedTUIRoot/Core/NullCheck.ps1"
. "$SpeedTUIRoot/Core/Internal/PerformanceCore.ps1"
. "$SpeedTUIRoot/Core/Terminal.ps1"
. "$SpeedTUIRoot/Core/RenderEngine.ps1"
. "$SpeedTUIRoot/Core/Component.ps1"
. "$SpeedTUIRoot/BorderHelper.ps1"
. "$SpeedTUIRoot/Models/BaseModel.ps1"
. "$SpeedTUIRoot/Models/TimeEntry.ps1"
. "$SpeedTUIRoot/Models/Command.ps1"
. "$SpeedTUIRoot/Models/Project.ps1"
. "$SpeedTUIRoot/Models/Task.ps1"
. "$SpeedTUIRoot/Core/DataStore.ps1"
. "$SpeedTUIRoot/Services/DataService.ps1"
. "$SpeedTUIRoot/Services/ConfigurationService.ps1"
. "$SpeedTUIRoot/Services/TimeTrackingService.ps1"
. "$SpeedTUIRoot/Services/CommandService.ps1"
. "$SpeedTUIRoot/Components/InputField.ps1"
. "$SpeedTUIRoot/Components/FormManager.ps1"
. "$SpeedTUIRoot/Screens/DashboardScreen.ps1"
. "$SpeedTUIRoot/Core/EnhancedApplication.ps1"

# Create logger
$global:logger = [object]::GetInstance()
if ($Debug) {
    $global:logger.GlobalLevel = [LogLevel]::Trace
}

try {
    Write-Host "Creating test application..." -ForegroundColor Green
    
    # Create app and screen
    $app = [EnhancedApplication]::new()
    $screen = [DashboardScreen]::new()
    
    Write-Host "Testing screen render..." -ForegroundColor Green
    $content = $screen.Render()
    Write-Host "Screen rendered $($content.Count) lines" -ForegroundColor Green
    
    Write-Host "Starting app for 5 seconds..." -ForegroundColor Green
    Write-Host "Try pressing arrow keys..." -ForegroundColor Yellow
    
    # Start app in background job to test
    $job = Start-Job -ScriptBlock {
        param($app, $screen)
        $app.Run($screen)
    } -ArgumentList $app, $screen
    
    # Wait and then stop
    Start-Sleep -Seconds 5
    Stop-Job $job -Force
    Remove-Job $job -Force
    
    Write-Host "Test completed" -ForegroundColor Green
    
} catch {
    Write-Host "Test failed: $($_.Exception.Message)" -ForegroundColor Red
}