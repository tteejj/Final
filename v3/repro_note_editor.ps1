
$ErrorActionPreference = "Stop"

# Load Dependencies
. "$PSScriptRoot/Enums.ps1"
. "$PSScriptRoot/Validation.ps1"
. "$PSScriptRoot/PerformanceCore.ps1"
. "$PSScriptRoot/CellBuffer.ps1"
. "$PSScriptRoot/RenderCache.ps1"
. "$PSScriptRoot/HybridRenderEngine.Dependencies.ps1"
. "$PSScriptRoot/HybridRenderEngine.ps1"
. "$PSScriptRoot/GapBuffer.ps1"
. "$PSScriptRoot/NoteEditor.ps1"

# Initialize Engine
$engine = [HybridRenderEngine]::new()
$engine.Initialize()

try {
    $engine.BeginFrame()
    $engine.DrawBox(0, 0, 80, 24, [Colors]::White, [Colors]::Background)
    $engine.WriteAt(2, 2, "Test Background", [Colors]::Gray, [Colors]::Background)
    $engine.EndFrame()

    # Launch Note Editor
    $editor = [NoteEditor]::new("Start Content")
    
    # We can't verify 'Interactive' behavior easily in script, 
    # but we can check if Render throws.
    
    $engine.BeginFrame()
    $editor.Render($engine)
    $engine.EndFrame()
    
    Start-Sleep -Seconds 1
    
} catch {
    Write-Host "CRASH: $_"
    exit 1
} finally {
    $engine.Cleanup()
}

Write-Host "NoteEditor Rendered Successfully"
