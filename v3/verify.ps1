$ErrorActionPreference = "Stop"

try {
    Write-Host "Verifying Enums..."
    . ./Enums.ps1
    
    Write-Host "Verifying PerformanceCore..."
    . ./PerformanceCore.ps1
    
    Write-Host "Verifying CellBuffer..."
    . ./CellBuffer.ps1
    
    Write-Host "Verifying RenderCache..."
    . ./RenderCache.ps1
    
    Write-Host "Verifying HybridRenderEngine..."
    . ./HybridRenderEngine.ps1
    
    Write-Host "Verifying GapBuffer..."
    . ./GapBuffer.ps1
    
    Write-Host "Verifying DataService..."
    . ./DataService.ps1
    
    Write-Host "Verifying FluxStore..."
    . ./FluxStore.ps1
    
    Write-Host "Verifying UniversalList..."
    . ./UniversalList.ps1
    
    Write-Host "Verifying Dashboard..."
    . ./Dashboard.ps1

    Write-Host "Verifying WeeklyView..."
    . ./WeeklyView.ps1

    Write-Host "Verifying InputBox..."
    . ./InputBox.ps1

    Write-Host "Verifying NoteEditor..."
    . ./NoteEditor.ps1

    Write-Host "Verifying InputLogic..."
    . ./InputLogic.ps1

    Write-Host "Verifying SmartEditor..."
    . ./SmartEditor.ps1
    
    Write-Host "Verifying TuiApp..."
    . ./TuiApp.ps1
    
    Write-Host "All files parsed successfully."
}
catch {
    Write-Error $_
    exit 1
}
