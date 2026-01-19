
$ErrorActionPreference = "Stop"
Write-Host "Diagnostic Start..." -ForegroundColor Cyan

function Test-Syntax($path) {
    Write-Host "Checking $path ... " -NoNewline
    if (-not (Test-Path $path)) {
        Write-Host "MISSING" -ForegroundColor Red
        return
    }
    
    try {
        $content = Get-Content $path -Raw
        [void][System.Management.Automation.PSParser]::Tokenize($content, [ref]$null)
        Write-Host "OK" -ForegroundColor Green
    } catch {
        Write-Host "SYNTAX ERROR" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        exit 1
    }
}

$root = $PSScriptRoot
Test-Syntax "$root/Enums.ps1"
Test-Syntax "$root/Logger.ps1"
Test-Syntax "$root/PerformanceCore.ps1"
Test-Syntax "$root/CellBuffer.ps1"
Test-Syntax "$root/GapBuffer.ps1"
Test-Syntax "$root/RenderCache.ps1"
Test-Syntax "$root/HybridRenderEngine.ps1"
Test-Syntax "$root/DataService.ps1"
Test-Syntax "$root/FluxStore.ps1"
Test-Syntax "$root/NoteEditor.ps1"
Test-Syntax "$root/SmartEditor.ps1"
Test-Syntax "$root/ProjectInfoModal.ps1"
Test-Syntax "$root/TimeModal.ps1"
Test-Syntax "$root/OverviewModal.ps1"
Test-Syntax "$root/NotesModal.ps1"
Test-Syntax "$root/ChecklistsModal.ps1"
Test-Syntax "$root/StatusBar.ps1"
Test-Syntax "$root/TuiApp.ps1"
Test-Syntax "$root/start-v3.ps1"

Write-Host "ALL CHECKS PASSED." -ForegroundColor Cyan
