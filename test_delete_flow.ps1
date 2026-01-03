#!/usr/bin/env pwsh
# Direct test to simulate CommandLibraryScreen delete flow

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$AppRoot = "/home/teej/ztest"
$env:PMC_APP_ROOT = $AppRoot

# Load all required files
Write-Host "Loading files..." -ForegroundColor Cyan
. "$AppRoot/module/Pmc.Strict/consoleui/services/CommandService.ps1"

function Write-PmcTuiLog($msg, $level) {
    Write-Host "[$level] $msg" -ForegroundColor $(if ($level -eq 'ERROR') { 'Red' } elseif ($level -eq 'WARNING') { 'Yellow' } else { 'Gray' })
}

Write-Host "=== Test: CommandService Delete Flow ===" -ForegroundColor Cyan

# Get singleton instance
$service1 = [CommandService]::GetInstance()
Write-Host "Instance1: $($service1.GetHashCode())"

# Create test command
$testCmd = $service1.CreateCommand("TestCmd", "echo test", "Test", "", @())
Write-Host "Created command: $($testCmd.id)"

# Get all commands
$before = $service1.GetAllCommands()
Write-Host "Commands BEFORE delete: $($before.Count)"

# Get a SECOND reference to the service (simulating what LoadItems does)
$service2 = [CommandService]::GetInstance()
Write-Host "Instance2: $($service2.GetHashCode())"
Write-Host "Same instance? $($service1 -eq $service2)"

# Delete via service1
Write-Host "Deleting via service1..."
$service1.DeleteCommand($testCmd.id)

# Check service1 immediately
$afterService1 = $service1.GetAllCommands()
Write-Host "service1.GetAllCommands() AFTER delete: $($afterService1.Count)"

# Check service2 (simulating what LoadItems would see)
$afterService2 = $service2.GetAllCommands()
Write-Host "service2.GetAllCommands() AFTER delete: $($afterService2.Count)"

if ($afterService1.Count -eq 0 -and $afterService2.Count -eq 0) {
    Write-Host "SUCCESS: Both service references see 0 commands" -ForegroundColor Green
} else {
    Write-Host "FAILURE: Cache not properly shared!" -ForegroundColor Red
}

# Cleanup test file
$metaFile = "$AppRoot/module/commands/commands_metadata.json"
Write-Host "`nMetadata file contents:"
Get-Content $metaFile | Write-Host

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
