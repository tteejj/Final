
# debug_load.ps1
$ErrorActionPreference = "Stop"
try {
    $consoleUiRoot = $PSScriptRoot
    $srcRoot = Join-Path (Split-Path -Parent $consoleUiRoot) "src"

    Write-Host "Loading DepsLoader..."
    . "$consoleUiRoot/DepsLoader.ps1"
    
    Write-Host "Loading SpeedTUILoader..."
    . "$consoleUiRoot/SpeedTUILoader.ps1"
    
    Write-Host "Loading PmcThemeEngine..."
    . "$consoleUiRoot/src/PmcThemeEngine.ps1"
    
    Write-Host "Loading PmcLayoutManager..."
    . "$consoleUiRoot/layout/PmcLayoutManager.ps1"
    
    Write-Host "Loading PmcWidget..."
    . "$consoleUiRoot/widgets/PmcWidget.ps1"
    
    Write-Host "Loading GapBuffer..."
    . "$consoleUiRoot/helpers/GapBuffer.ps1"
    
    Write-Host "Loading TextAreaEditor..."
    . "$consoleUiRoot/widgets/TextAreaEditor.ps1"
    
    Write-Host "Loading PmcHeader..."
    . "$consoleUiRoot/widgets/PmcHeader.ps1"
    
    Write-Host "Loading PmcFooter..."
    . "$consoleUiRoot/widgets/PmcFooter.ps1"
    
    Write-Host "Loading PmcStatusBar..."
    . "$consoleUiRoot/widgets/PmcStatusBar.ps1"
    
    Write-Host "Loading PmcMenuBar..."
    . "$consoleUiRoot/widgets/PmcMenuBar.ps1"
    
    Write-Host "Loading PmcScreen..."
    . "$consoleUiRoot/PmcScreen.ps1"
    
    Write-Host "Loading NoteService..."
    . "$consoleUiRoot/services/NoteService.ps1"
    
    Write-Host "Testing NoteService..."
    $svc = [NoteService]::GetInstance()
    Write-Host "NoteService instance: $svc"
    
    Write-Host "Loading ChecklistService..."
    . "$consoleUiRoot/services/ChecklistService.ps1"

    Write-Host "Loading NoteEditorScreen..."
    . "$consoleUiRoot/screens/NoteEditorScreen.ps1"
    
    Write-Host "Success!"
} catch {
    Write-Host "Error: $_"
    Write-Host "Stack: $($_.ScriptStackTrace)"
}
