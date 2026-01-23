Param(
    [int]$DebugLevel = 1
)

# start-v3.ps1 - V3 Bootstrapper
$ErrorActionPreference = "Stop"

# 1. Define Paths
$scriptDir = $PSScriptRoot
$moduleDir = "$scriptDir/module/Pmc.Strict"
$logFile = "$scriptDir/pmc_v3.log"

# 2. Key Binding Manifest (for StatusBar)
$manifest = @{
    "F1" = @{ Menu = "Main"; Label = "Help" }
    "F5" = @{ Menu = "Main"; Label = "Refresh" }
    "Q" = @{ Menu = "Global"; Label = "Quit" }
    "V" = @{ Menu = "Project"; Label = "Project Info" }
    "T" = @{ Menu = "Project"; Label = "Time" }
    "O" = @{ Menu = "Global"; Label = "Overview" }
    "M" = @{ Menu = "Details"; Label = "Add Note" }
    "N" = @{ Menu = "List"; Label = "New" }
}

# 3. Load Dependencies in strict order
$files = @(
    "Logger.ps1",
    "ThemeService.ps1",
    "Enums.ps1",
    "PerformanceCore.ps1",
    "NativeRenderCore.ps1",   # C# NativeCellBuffer - high performance rendering
    "RenderCache.ps1",
    "HybridRenderEngine.Dependencies.ps1",
    "HybridRenderEngine.ps1",
    "GapBuffer.ps1",
    "DataService.ps1",
    "FluxStore.ps1",
    "UniversalList.ps1",
    "Dashboard.ps1",
    "WeeklyView.ps1",
    "KanbanBoard.ps1",
    "NoteEditor.ps1",
    "InputLogic.ps1",
    "SmartEditor.ps1",
    "FilePicker.ps1",
    "TabbedModal.ps1",
    "NotesModal.ps1",
    "ChecklistsModal.ps1",
    "FieldMappingService.ps1",
    "TextExportService.ps1",
    "ProjectInfoModal.ps1",
    "TimeModal.ps1",
    "OverviewModal.ps1",
    "CommandPalette.ps1",
    "ThemeSelectorModal.ps1",
    "StatusBar.ps1",
    "TuiApp.ps1"
)

try {
    # Logging first
    . "$scriptDir/Logger.ps1"
    [Logger]::Initialize($logFile, $DebugLevel)
    
    foreach ($file in $files) {
        $filePath = Join-Path $scriptDir $file
        Write-Host "DEBUG: Checking $file..." -ForegroundColor DarkGray
        if (Test-Path $filePath) {
            Write-Host "DEBUG: Loading $file..." -ForegroundColor Yellow
            try {
                . $filePath
                Write-Host "DEBUG: Loaded $file OK." -ForegroundColor Green
            } catch {
                Write-Host "DEBUG: FAILED to load $file" -ForegroundColor Red
                Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
                throw $_
            }
        } else {
            throw "Missing required file: $file at $filePath"
        }
    }

    # 4. Initialize
    [ThemeService]::Initialize()
    [ThemeService]::LoadTheme(@{}) # Load default
    [Colors]::Sync()
    
    $dataService = [DataService]::new((Join-Path $scriptDir "tasks.json"))
    $store = [FluxStore]::new($dataService)
    
    # Apply Persisted Theme (if saved)
    $state = $store.GetState()
    if ($state.Data.settings['Theme']) {
         $presets = [ThemeService]::GetPresets()
         $saved = $presets | Where-Object { $_.Name -eq $state.Data.settings['Theme'] } | Select-Object -First 1
         if ($saved) {
             [ThemeService]::LoadTheme($saved.Data)
             [Colors]::Sync()
         }
    }
    
    $engine = [HybridRenderEngine]::new()

    $app = [TuiApp]::new($engine, $store)

    # 5. Start
    Write-Host "Starting FluxTUI V3..." -ForegroundColor Cyan
    $app.Run()

} catch {
    [Logger]::Log("Fatal Error (Trapped): $($_.Exception.Message)", 3)
    [Logger]::Log($_.ScriptStackTrace, 3)
    # Don't Write-Error as it corrupts TUI. 
    # If StatusBar existed globally here we could use it, but safe to just log.e-Error "Stack Trace: $($_.ScriptStackTrace)"
    if ([Logger]) {
        [Logger]::Error("Fatal crash in bootstrapper", $_.Exception)
    }
}
