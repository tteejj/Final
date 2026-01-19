
$ErrorActionPreference = "Stop"

function Test-Load($path) {
    Write-Host "Testing $path..." -NoNewline
    try {
        . $path
        Write-Host " OK" -ForegroundColor Green
    } catch {
        Write-Host " FAIL" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        exit 1
    }
}

$scriptDir = $PSScriptRoot
. "$scriptDir/Logger.ps1"
[Logger]::Initialize("$scriptDir/debug_crash.log", 3)

# Load Dependencies manually
Test-Load "$scriptDir/Enums.ps1"
Test-Load "$scriptDir/PerformanceCore.ps1"
Test-Load "$scriptDir/CellBuffer.ps1"
Test-Load "$scriptDir/RenderCache.ps1"
Test-Load "$scriptDir/HybridRenderEngine.ps1"
Test-Load "$scriptDir/GapBuffer.ps1"
Test-Load "$scriptDir/DataService.ps1"
Test-Load "$scriptDir/FluxStore.ps1"
Test-Load "$scriptDir/NoteEditor.ps1"
Test-Load "$scriptDir/UniversalList.ps1"
Test-Load "$scriptDir/Dashboard.ps1"
Test-Load "$scriptDir/WeeklyView.ps1"
Test-Load "$scriptDir/InputLogic.ps1"
Test-Load "$scriptDir/SmartEditor.ps1"
Test-Load "$scriptDir/FilePicker.ps1"
Test-Load "$scriptDir/TabbedModal.ps1"

# Suspects
Test-Load "$scriptDir/NotesModal.ps1"
Test-Load "$scriptDir/ChecklistsModal.ps1"
Test-Load "$scriptDir/FieldMappingService.ps1"
Test-Load "$scriptDir/TextExportService.ps1"
Test-Load "$scriptDir/ProjectInfoModal.ps1"
Test-Load "$scriptDir/TimeModal.ps1"
Test-Load "$scriptDir/OverviewModal.ps1"
Test-Load "$scriptDir/StatusBar.ps1"

# Final Suspect
Test-Load "$scriptDir/TuiApp.ps1"

Write-Host "All files loaded successfully." -ForegroundColor Cyan
