#!/usr/bin/env pwsh
# Build simple but effective obfuscated PMC TUI installer

param(
    [string]$ZipFile = "pmctui-portable-new.zip",
    [string]$OutputFile = "pmctui.ps1"
)

Write-Host "Building simple obfuscated installer..." -ForegroundColor Cyan

# Read ZIP and convert to base64
$zipBytes = [System.IO.File]::ReadAllBytes($ZipFile)
$base64 = [Convert]::ToBase64String($zipBytes)

# Split into chunks (7KB each)
$chunkSize = 7000
$chunks = @()
for ($i = 0; $i -lt $base64.Length; $i += $chunkSize) {
    $len = [Math]::Min($chunkSize, $base64.Length - $i)
    $chunks += $base64.Substring($i, $len)
}

Write-Host "  ZIP size: $($zipBytes.Length) bytes"
Write-Host "  Base64 size: $($base64.Length) chars"
Write-Host "  Chunks: $($chunks.Count)"

# Build obfuscated installer
$sb = [System.Text.StringBuilder]::new()

# Header
[void]$sb.AppendLine(@'
<#
.SYNOPSIS
PMC TUI Application Configuration and Deployment Module

.DESCRIPTION
This PowerShell module handles the deployment and configuration of the
PMC TUI (Terminal User Interface) application. It contains all necessary
application resources in an optimized encoded format.

The deployment process:
1. Validates the target installation directory
2. Extracts application resources from embedded data
3. Initializes the directory structure
4. Configures runtime environment

.PARAMETER InstallPath
Target directory for application deployment (required).
Must be an absolute path.

.PARAMETER Force
If specified, overwrites existing installation.

.EXAMPLE
.\pmctui.ps1 -InstallPath "C:\Applications\PMCTUI"

.EXAMPLE
.\pmctui.ps1 -InstallPath "C:\PMCTUI" -Force

.NOTES
Version: 2.0.1
Platform: PowerShell 5.1+ / PowerShell Core 7+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallPath,

    [switch]$Force
)

# Configuration
$script:AppName = "PMC TUI"
$script:AppVersion = "2.0.1"

# Encoded application package (base64 data segments)
'@)

# Add chunks
[void]$sb.AppendLine('$script:PackageData = @(')
for ($i = 0; $i -lt $chunks.Count; $i++) {
    $chunk = $chunks[$i]
    [void]$sb.AppendLine("    @'")
    [void]$sb.AppendLine($chunk)
    [void]$sb.Append("'@")
    if ($i -lt $chunks.Count - 1) {
        [void]$sb.AppendLine(",")
    } else {
        [void]$sb.AppendLine()
    }
}
[void]$sb.AppendLine(")")
[void]$sb.AppendLine()

# Add deployment logic (simpler, no reflection)
[void]$sb.AppendLine(@'
function Deploy-Application {
    param([string]$Path, [bool]$Replace)

    Write-Host "$script:AppName Installer v$script:AppVersion" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan

    if (Test-Path $Path) {
        if (-not $Replace) {
            Write-Host "ERROR: Directory exists: $Path" -ForegroundColor Red
            Write-Host "       Use -Force to overwrite" -ForegroundColor Yellow
            return $false
        }
        Write-Host "Removing existing installation..." -ForegroundColor Yellow
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    Write-Host "Extracting application files..." -ForegroundColor Green

    try {
        # Reassemble and decode package
        $encoded = $script:PackageData -join ''
        $decoded = [Convert]::FromBase64String($encoded)

        # Write to temp file
        $tempDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMP) { $env:TMP } else { '/tmp' }
        $tempPkg = Join-Path $tempDir "pmc-$([guid]::NewGuid().ToString('N')).zip"
        [System.IO.File]::WriteAllBytes($tempPkg, $decoded)

        try {
            # Extract using .NET
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($tempPkg, $Path)

            # Create data dirs
            @('data', 'data/logs', 'data/backups') | ForEach-Object {
                $dir = Join-Path $Path $_
                if (-not (Test-Path $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
            }

            Write-Host ""
            Write-Host "Installation successful!" -ForegroundColor Green
            Write-Host "Location: $Path" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "To start:" -ForegroundColor Yellow
            Write-Host "  cd $Path" -ForegroundColor White
            Write-Host "  pwsh ./start.ps1" -ForegroundColor White
            Write-Host ""

            return $true
        }
        finally {
            if (Test-Path $tempPkg) {
                Remove-Item $tempPkg -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Host ""
        Write-Host "ERROR: $_" -ForegroundColor Red
        Write-Host ""
        return $false
    }
}

try {
    $result = Deploy-Application -Path $InstallPath -Replace:$Force
    exit $(if ($result) { 0 } else { 1 })
}
catch {
    Write-Host "FATAL: $_" -ForegroundColor Red
    exit 1
}
'@)

# Write output
[System.IO.File]::WriteAllText($OutputFile, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))

$size = (Get-Item $OutputFile).Length
Write-Host ""
Write-Host "Installer created!" -ForegroundColor Green
Write-Host "  File: $OutputFile"
Write-Host "  Size: $([Math]::Round($size / 1MB, 2)) MB"
Write-Host "  Chunks: $($chunks.Count)"
Write-Host ""
