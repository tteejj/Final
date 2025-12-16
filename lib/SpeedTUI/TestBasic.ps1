#!/usr/bin/env pwsh
# Basic terminal test without full TUI

# Load the core classes
. ./Core/Logger.ps1
. ./Core/NullCheck.ps1
. ./Core/Terminal.ps1

Write-Host "Testing basic terminal functionality..." -ForegroundColor Cyan

$terminal = [Terminal]::GetInstance()
$terminal.Initialize()

# Test basic drawing
$terminal.BeginFrame()
$terminal.WriteAt(5, 2, "Hello from SpeedTUI!", [Colors]::Green, "")
$terminal.WriteAt(5, 4, "This is a basic test", [Colors]::Yellow, "")
$terminal.DrawBox(2, 1, 40, 8, "Single")
$terminal.EndFrame()

Write-Host "Terminal test complete - you should see a box with text" -ForegroundColor Green
Write-Host "Press any key to cleanup..."
Read-Host

$terminal.Cleanup()