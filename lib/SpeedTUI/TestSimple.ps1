#!/usr/bin/env pwsh
# Simple test to get SpeedTUI working

# Load SpeedTUI
. ./Start.ps1

# Create a simple label
$label = [Label]::new("Hello SpeedTUI!")
$label.SetBounds(5, 5, 50, 3)

# Create application
$app = [Application]::new("Simple Test")
$app.SetRoot($label)

# Run
Write-Host "Starting simple test..." -ForegroundColor Green
$app.Run()