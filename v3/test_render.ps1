# test_render.ps1 - Runtime verification of the Render loop
$ErrorActionPreference = "Stop"

try {
    Write-Host "Loading dependencies..."
    . "$PSScriptRoot/Logger.ps1"
    [Logger]::Init((Join-Path $PSScriptRoot "debug.log"))
    [Logger]::Log("Starting Test Render")

    [Logger]::Log("Loading Enums")
    . "$PSScriptRoot/Enums.ps1"
    [Logger]::Log("Loading PerformanceCore")
    . "$PSScriptRoot/PerformanceCore.ps1"
    [Logger]::Log("Loading CellBuffer")
    . "$PSScriptRoot/CellBuffer.ps1"
    [Logger]::Log("Loading RenderCache")
    . "$PSScriptRoot/RenderCache.ps1"
    [Logger]::Log("Loading HybridRenderEngine")
    . "$PSScriptRoot/HybridRenderEngine.ps1"
    [Logger]::Log("Loading GapBuffer")
    . "$PSScriptRoot/GapBuffer.ps1"
    [Logger]::Log("Loading DataService")
    . "$PSScriptRoot/DataService.ps1"
    [Logger]::Log("Loading FluxStore")
    . "$PSScriptRoot/FluxStore.ps1"
    [Logger]::Log("Loading UniversalList")
    . "$PSScriptRoot/UniversalList.ps1"
    [Logger]::Log("Loading Dashboard")
    . "$PSScriptRoot/Dashboard.ps1"
    [Logger]::Log("Loading WeeklyView")
    . "$PSScriptRoot/WeeklyView.ps1"
    [Logger]::Log("Loading InputBox")
    . "$PSScriptRoot/InputBox.ps1"
    [Logger]::Log("Loading NoteEditor")
    . "$PSScriptRoot/NoteEditor.ps1"
    [Logger]::Log("Loading InputLogic")
    . "$PSScriptRoot/InputLogic.ps1"
    [Logger]::Log("Loading SmartEditor")
    . "$PSScriptRoot/SmartEditor.ps1"
    [Logger]::Log("Loading TuiApp")
    . "$PSScriptRoot/TuiApp.ps1"
    [Logger]::Log("Dependencies loaded")

    Write-Host "Initializing Core Services..."
    # Initialize DataService with the actual file
    $dataService = [DataService]::new((Join-Path $PSScriptRoot "tasks.json"))
    
    # Initialize Store (loads data)
    $store = [FluxStore]::new($dataService)
    $state = $store.GetState()
    
    Write-Host "Data Loaded:"
    Write-Host "  Projects: $($state.Data.projects.Count)"
    Write-Host "  Tasks:    $($state.Data.tasks.Count)"
    Write-Host "  Timelogs: $($state.Data.timelogs.Count)"

    Write-Host "Initializing Engine..."
    $engine = [HybridRenderEngine]::new()
    $engine.Initialize()
    # Mock dimensions to avoid console errors if running headless
    $engine.Resize(120, 40)
    
    Write-Host "Initializing Dashboard..."
    $dashboard = [Dashboard]::new()

    Write-Host "Testing Dashboard.Render()..."
    # This will trigger the calculation logic that failed previously
    $engine.BeginFrame()
    [Logger]::Log("Calling Dashboard.Render")
    try {
        $dashboard.Render($engine, $state)
    } catch {
        [Logger]::Error("Dashboard.Render failed", $_.Exception)
        throw
    }
    [Logger]::Log("Dashboard.Render returned")
    $engine.EndFrame()
    
    Write-Host "Dashboard Render Successful!"
    
    Write-Host "Testing WeeklyView.Render()..."
    $weekly = [WeeklyView]::new()
    $engine.BeginFrame()
    $weekly.Render($engine, $state)
    $engine.EndFrame()
    
    Write-Host "WeeklyView Render Successful!"
    
} catch {
    [Logger]::Error("Main Test Loop Failed", $_.Exception)
    Write-Error "RUNTIME ERROR: $_"
    Write-Error "StackTrace: $($_.ScriptStackTrace)"
    exit 1
}
