
try {
    Write-Host "Loading HybridRenderEngine.ps1..."
    . ./HybridRenderEngine.ps1
    $engine = [HybridRenderEngine]::new()
    Write-Host "HybridRenderEngine loaded successfully." -ForegroundColor Green
} catch {
    Write-Host "CRASHED:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}
