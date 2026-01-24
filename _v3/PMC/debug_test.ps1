
try {
    . /home/teej/ztest/_v3/PMC/HybridRenderEngine.Dependencies.ps1 # Class dependency?
    # Dependency order matters. HybridRenderEngine depends on NativeRenderCore?
    . /home/teej/ztest/_v3/PMC/NativeRenderCore.ps1
    . /home/teej/ztest/_v3/PMC/HybridRenderEngine.ps1
    Write-Host "Loaded OK"
} catch {
    Write-Host "LOAD ERROR: $_"
    Write-Host $_.ScriptStackTrace
}
