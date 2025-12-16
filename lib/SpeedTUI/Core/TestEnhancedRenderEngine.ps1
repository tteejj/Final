#!/usr/bin/env pwsh
# Test script for EnhancedRenderEngine
# This validates that EnhancedRenderEngine works correctly with rendering operations

# Load dependencies using Invoke-Expression to properly load classes
$cellBufferContent = Get-Content "$PSScriptRoot/CellBuffer.ps1" -Raw
Invoke-Expression $cellBufferContent

$perfCoreContent = Get-Content "$PSScriptRoot/Internal/PerformanceCore.ps1" -Raw
Invoke-Expression $perfCoreContent

$engineContent = Get-Content "$PSScriptRoot/EnhancedRenderEngine.ps1" -Raw
Invoke-Expression $engineContent

Write-Host "=== EnhancedRenderEngine Test Suite ===" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

function Test-Assert {
    param(
        [string]$TestName,
        [bool]$Condition,
        [string]$Message = ""
    )

    if ($Condition) {
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        $script:testsPassed++
    } else {
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Yellow
        }
        $script:testsFailed++
    }
}

# Test 1: Engine creation
Write-Host "Test 1: Engine Creation" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    Test-Assert "Engine created successfully" ($null -ne $engine)
    Test-Assert "Engine has width" ($engine.Width -gt 0)
    Test-Assert "Engine has height" ($engine.Height -gt 0)
} catch {
    Test-Assert "Engine creation" $false "Exception: $_"
}

Write-Host ""

# Test 2: Initialize
Write-Host "Test 2: Initialize" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()
    $stats = $engine.GetPerformanceStats()
    Test-Assert "Engine initialized" ($stats.Initialized -eq $true)
    $engine.Cleanup()
} catch {
    Test-Assert "Engine initialize" $false "Exception: $_"
}

Write-Host ""

# Test 3: Frame lifecycle
Write-Host "Test 3: Frame Lifecycle" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    # Should succeed
    $engine.BeginFrame()
    $stats = $engine.GetPerformanceStats()
    Test-Assert "BeginFrame sets InFrame" ($stats.InFrame -eq $true)

    $engine.EndFrame()
    $stats = $engine.GetPerformanceStats()
    Test-Assert "EndFrame clears InFrame" ($stats.InFrame -eq $false)
    Test-Assert "EndFrame increments FrameCount" ($stats.FrameCount -eq 1)

    $engine.Cleanup()
} catch {
    Test-Assert "Frame lifecycle" $false "Exception: $_"
}

Write-Host ""

# Test 4: WriteAt without ANSI
Write-Host "Test 4: WriteAt Plain Text" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    $engine.BeginFrame()
    $engine.WriteAt(0, 0, "Hello World")
    # Should not throw
    $engine.EndFrame()

    Test-Assert "WriteAt plain text succeeds" $true

    $engine.Cleanup()
} catch {
    Test-Assert "WriteAt plain text" $false "Exception: $_"
}

Write-Host ""

# Test 5: WriteAt with RGB color
Write-Host "Test 5: WriteAt with RGB Color" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    $engine.BeginFrame()
    # Red foreground
    $engine.WriteAt(0, 0, "`e[38;2;255;0;0mRed Text`e[0m")
    # Green background
    $engine.WriteAt(0, 1, "`e[48;2;0;255;0mGreen BG`e[0m")
    # Both
    $engine.WriteAt(0, 2, "`e[38;2;255;255;0m`e[48;2;0;0;255mYellow on Blue`e[0m")
    $engine.EndFrame()

    Test-Assert "WriteAt with RGB color succeeds" $true

    $engine.Cleanup()
} catch {
    Test-Assert "WriteAt with RGB color" $false "Exception: $_"
}

Write-Host ""

# Test 6: WriteAt with attributes
Write-Host "Test 6: WriteAt with Attributes" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    $engine.BeginFrame()
    $engine.WriteAt(0, 0, "`e[1mBold`e[0m")
    $engine.WriteAt(0, 1, "`e[4mUnderline`e[0m")
    $engine.WriteAt(0, 2, "`e[3mItalic`e[0m")
    $engine.WriteAt(0, 3, "`e[1m`e[4mBold Underline`e[0m")
    $engine.EndFrame()

    Test-Assert "WriteAt with attributes succeeds" $true

    $engine.Cleanup()
} catch {
    Test-Assert "WriteAt with attributes" $false "Exception: $_"
}

Write-Host ""

# Test 7: Clear operations
Write-Host "Test 7: Clear Operations" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    $engine.BeginFrame()
    $engine.Clear(10, 10, 20, 5)
    $engine.ClearLine(15)
    $engine.EndFrame()

    Test-Assert "Clear operations succeed" $true

    $engine.Cleanup()
} catch {
    Test-Assert "Clear operations" $false "Exception: $_"
}

Write-Host ""

# Test 8: DrawBox
Write-Host "Test 8: DrawBox" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    $engine.BeginFrame()
    $engine.DrawBox(5, 5, 20, 10, "Single")
    $engine.DrawBox(30, 5, 20, 10, "Double", "`e[38;2;255;0;0m")
    $engine.DrawBox(55, 5, 20, 10, "Rounded")
    $engine.EndFrame()

    Test-Assert "DrawBox succeeds" $true

    $engine.Cleanup()
} catch {
    Test-Assert "DrawBox" $false "Exception: $_"
}

Write-Host ""

# Test 9: Differential rendering
Write-Host "Test 9: Differential Rendering" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    # First frame - write content
    $engine.BeginFrame()
    $engine.WriteAt(0, 0, "Frame 1")
    $engine.EndFrame()

    # Second frame - same content (should produce minimal diff)
    $engine.BeginFrame()
    $engine.WriteAt(0, 0, "Frame 1")
    $engine.EndFrame()

    # Third frame - different content
    $engine.BeginFrame()
    $engine.WriteAt(0, 0, "Frame 2")
    $engine.EndFrame()

    $stats = $engine.GetPerformanceStats()
    Test-Assert "Differential rendering tracked frames" ($stats.FrameCount -eq 3)

    $engine.Cleanup()
} catch {
    Test-Assert "Differential rendering" $false "Exception: $_"
}

Write-Host ""

# Test 10: RequestClear
Write-Host "Test 10: RequestClear" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    $engine.BeginFrame()
    $engine.WriteAt(0, 0, "Some content")
    $engine.EndFrame()

    # Request clear
    $engine.RequestClear()

    $engine.BeginFrame()
    $engine.WriteAt(0, 0, "New content after clear")
    $engine.EndFrame()

    Test-Assert "RequestClear succeeds" $true

    $engine.Cleanup()
} catch {
    Test-Assert "RequestClear" $false "Exception: $_"
}

Write-Host ""

# Test 11: Error handling - WriteAt before BeginFrame
Write-Host "Test 11: Error Handling" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    $errorCaught = $false
    try {
        $engine.WriteAt(0, 0, "Should fail")
    } catch {
        $errorCaught = $true
    }

    Test-Assert "WriteAt before BeginFrame throws" $errorCaught

    $engine.Cleanup()
} catch {
    Test-Assert "Error handling" $false "Exception: $_"
}

Write-Host ""

# Test 12: UpdateDimensions
Write-Host "Test 12: UpdateDimensions" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $initialWidth = $engine.Width
    $initialHeight = $engine.Height

    # UpdateDimensions should read from console
    $engine.UpdateDimensions()

    # Width and height should be reasonable
    Test-Assert "UpdateDimensions sets valid width" ($engine.Width -gt 0)
    Test-Assert "UpdateDimensions sets valid height" ($engine.Height -gt 0)

} catch {
    Test-Assert "UpdateDimensions" $false "Exception: $_"
}

Write-Host ""

# Test 13: Performance stats
Write-Host "Test 13: Performance Stats" -ForegroundColor Yellow
try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    $stats = $engine.GetPerformanceStats()

    Test-Assert "Stats has FrameCount" ($null -ne $stats.FrameCount)
    Test-Assert "Stats has Width" ($null -ne $stats.Width)
    Test-Assert "Stats has Height" ($null -ne $stats.Height)
    Test-Assert "Stats has TotalCells" ($null -ne $stats.TotalCells)
    Test-Assert "Stats has BufferMemoryKB" ($null -ne $stats.BufferMemoryKB)
    Test-Assert "Stats has Initialized" ($null -ne $stats.Initialized)
    Test-Assert "Stats has InFrame" ($null -ne $stats.InFrame)

    Test-Assert "TotalCells calculated correctly" ($stats.TotalCells -eq ($stats.Width * $stats.Height))

    $engine.Cleanup()
} catch {
    Test-Assert "Performance stats" $false "Exception: $_"
}

Write-Host ""

# Test 14: Visual test (optional - requires manual observation)
Write-Host "Test 14: Visual Test (Manual)" -ForegroundColor Yellow
Write-Host "Starting visual test in 2 seconds..." -ForegroundColor Gray
Start-Sleep -Seconds 2

try {
    $engine = [EnhancedRenderEngine]::new()
    $engine.Initialize()

    # Draw a simple UI
    $engine.BeginFrame()
    $engine.DrawBox(0, 0, $engine.Width, $engine.Height, "Single", "`e[38;2;100;149;237m")
    $engine.WriteAt(2, 1, "`e[1m`e[38;2;255;255;0mEnhancedRenderEngine Visual Test`e[0m")
    $engine.WriteAt(2, 3, "`e[38;2;0;255;0mGreen text`e[0m")
    $engine.WriteAt(2, 4, "`e[38;2;255;0;0mRed text`e[0m")
    $engine.WriteAt(2, 5, "`e[38;2;0;0;255mBlue text`e[0m")
    $engine.WriteAt(2, 6, "`e[1mBold`e[0m `e[4mUnderline`e[0m `e[3mItalic`e[0m")
    $engine.WriteAt(2, 8, "`e[48;2;255;0;0m  Red BG  `e[0m `e[48;2;0;255;0m  Green BG  `e[0m `e[48;2;0;0;255m  Blue BG  `e[0m")

    # Draw a progress bar animation
    for ($i = 0; $i -le 50; $i++) {
        $engine.WriteAt(2, 10, "Progress: [")
        $filled = [Math]::Floor($i / 2)
        $empty = 25 - $filled
        $bar = "`e[48;2;0;200;0m" + (" " * $filled) + "`e[0m" + (" " * $empty)
        $engine.WriteAt(14, 10, $bar)
        $engine.WriteAt(40, 10, "] $i/50")

        $engine.EndFrame()

        if ($i -lt 50) {
            Start-Sleep -Milliseconds 50
            $engine.BeginFrame()
            # Redraw static content
            $engine.DrawBox(0, 0, $engine.Width, $engine.Height, "Single", "`e[38;2;100;149;237m")
            $engine.WriteAt(2, 1, "`e[1m`e[38;2;255;255;0mEnhancedRenderEngine Visual Test`e[0m")
            $engine.WriteAt(2, 3, "`e[38;2;0;255;0mGreen text`e[0m")
            $engine.WriteAt(2, 4, "`e[38;2;255;0;0mRed text`e[0m")
            $engine.WriteAt(2, 5, "`e[38;2;0;0;255mBlue text`e[0m")
            $engine.WriteAt(2, 6, "`e[1mBold`e[0m `e[4mUnderline`e[0m `e[3mItalic`e[0m")
            $engine.WriteAt(2, 8, "`e[48;2;255;0;0m  Red BG  `e[0m `e[48;2;0;255;0m  Green BG  `e[0m `e[48;2;0;0;255m  Blue BG  `e[0m")
        }
    }

    $engine.WriteAt(2, 12, "`e[38;2;0;255;0mVisual test complete! Press Enter to continue...`e[0m")
    $engine.EndFrame()

    Read-Host

    $engine.Cleanup()

    Test-Assert "Visual test completed" $true
} catch {
    Test-Assert "Visual test" $false "Exception: $_"
}

Write-Host ""

# Summary
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed." -ForegroundColor Red
    exit 1
}