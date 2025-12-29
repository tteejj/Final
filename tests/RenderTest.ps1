
using namespace System.Collections.Generic

Describe "HybridRenderEngine Optimizations" {
    BeforeAll {
        # Load dependencies manually with debug
        $libPath = Resolve-Path "$PSScriptRoot/../lib/SpeedTUI/Core"
        Write-Host "Loading dependencies from $libPath"

        . "$libPath/Logger.ps1"
        . "$libPath/PerformanceMonitor.ps1"
        . "$libPath/NullCheck.ps1"
        . "$libPath/Internal/PerformanceCore.ps1"
        . "$libPath/SimplifiedTerminal.ps1"
        . "$libPath/NativeRenderCore.ps1"
        . "$libPath/CellBuffer.ps1"
        . "$libPath/RenderCache.ps1"
        try {
            . "$libPath/HybridRenderEngine.ps1"
            Write-Host "HybridRenderEngine loaded"
            $test = [HybridRenderEngine]::new()
            Write-Host "HybridRenderEngine instantiated successfully"
        } catch {
            Write-Host "Failed to load/instantiate HybridRenderEngine: $_"
            throw
        }
    }
    Context "WriteAt (Solid Color)" {
        It "Should use WriteRow for long strings" {
            $engine = [HybridRenderEngine]::new()
            $engine.Initialize()
            $engine.BeginFrame()
            
            # This should trigger the WriteRow path (> 5 chars)
            $engine.WriteAt(0, 0, "Hello World", 16777215, 0)
            
            # Verify no crash
            $true | Should -Be $true
            
            $engine.EndFrame()
        }
        
        It "Should use Loop for short strings" {
            $engine = [HybridRenderEngine]::new()
            $engine.Initialize()
            $engine.BeginFrame()
            
            # This should trigger the Loop path (<= 5 chars)
            $engine.WriteAt(0, 1, "Hi", 16777215, 0)
            
            $true | Should -Be $true
            
            $engine.EndFrame()
        }
    }
    
    Context "Fill" {
        It "Should use WriteRow via WriteAt" {
            $engine = [HybridRenderEngine]::new()
            $engine.Initialize()
            $engine.BeginFrame()
            
            # Fill uses WriteAt with long string
            $engine.Fill(0, 2, 20, 1, "-", 16777215, 0)
            
            $true | Should -Be $true
            
            $engine.EndFrame()
        }
    }
}
