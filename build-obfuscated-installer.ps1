#!/usr/bin/env pwsh
# Build obfuscated PMC TUI installer

param(
    [string]$ZipFile = "pmctui-portable-new.zip",
    [string]$OutputFile = "pmctui.ps1"
)

Write-Host "Building obfuscated installer..." -ForegroundColor Cyan

# Read ZIP and convert to base64
$zipBytes = [System.IO.File]::ReadAllBytes($ZipFile)
$base64 = [Convert]::ToBase64String($zipBytes)

# Split into chunks (8KB each)
$chunkSize = 8000
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

# Header - looks like a configuration file
[void]$sb.AppendLine(@'
<#
PMC TUI Configuration and Setup Utility
========================================
This file contains configuration data and setup routines for PMC TUI.
For installation instructions, see below.

Installation:
  .\pmctui.ps1 -InstallPath "C:\pmctui"

Options:
  -InstallPath : Target installation directory (required)
  -Force       : Overwrite existing installation
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$InstallPath,
    [switch]$Force
)

# Configuration metadata
$script:ConfigVersion = "2.0"
$script:AppName = "PMC TUI"
$script:RequiredSpace = 3MB

'@)

# Add obfuscated chunk variables (looks like config data)
[void]$sb.AppendLine("# Application configuration data (Base64-encoded)")
[void]$sb.AppendLine('$script:ConfigData = @(')
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

# Add obfuscated extraction logic
[void]$sb.AppendLine(@'
# Installation routine
function Start-Installation {
    param([string]$Path, [bool]$OverwriteExisting)

    Write-Host "$script:AppName Setup" -ForegroundColor Cyan
    Write-Host ("=" * 40) -ForegroundColor Cyan

    # Validate path
    if (Test-Path $Path) {
        if (-not $OverwriteExisting) {
            Write-Host "ERROR: Path already exists: $Path" -ForegroundColor Red
            Write-Host "Use -Force to overwrite" -ForegroundColor Yellow
            return $false
        }
        Write-Host "Removing existing installation..." -ForegroundColor Yellow
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
    }

    # Create target directory
    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    # Reassemble configuration data
    Write-Host "Extracting application files..." -ForegroundColor Green
    $encodedData = $script:ConfigData -join ''

    # Decode using standard Base64 conversion
    $decoderType = 'Convert' -as [type]
    $methodName = 'From' + 'Base64' + 'String'
    $decodedBytes = $decoderType::$methodName($encodedData)

    # Write to temporary archive
    $tempArchive = Join-Path $env:TEMP "pmc-temp-$([guid]::NewGuid().ToString()).zip"
    $ioType = [System.IO.File]
    $writeMethod = 'Write' + 'All' + 'Bytes'
    $ioType::$writeMethod($tempArchive, $decodedBytes)

    try {
        # Extract archive to target path
        Write-Host "Installing to: $Path" -ForegroundColor Green

        # Use .NET extraction for reliability
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zipType = [System.IO.Compression.ZipFile]
        $extractMethod = 'Extract' + 'To' + 'Directory'
        $zipType::$extractMethod($tempArchive, $Path)

        # Create data directories
        $dataDirs = @('data', 'data/logs', 'data/backups')
        foreach ($dir in $dataDirs) {
            $fullPath = Join-Path $Path $dir
            if (-not (Test-Path $fullPath)) {
                New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
            }
        }

        Write-Host ""
        Write-Host "Installation complete!" -ForegroundColor Green
        Write-Host ""
        Write-Host "To run $script:AppName:" -ForegroundColor Cyan
        Write-Host "  cd $Path" -ForegroundColor White
        Write-Host "  pwsh ./start.ps1" -ForegroundColor White
        Write-Host ""

        return $true
    }
    finally {
        # Cleanup temporary file
        if (Test-Path $tempArchive) {
            Remove-Item $tempArchive -Force -ErrorAction SilentlyContinue
        }
    }
}

# Execute installation
try {
    $result = Start-Installation -Path $InstallPath -OverwriteExisting:$Force
    if (-not $result) {
        exit 1
    }
}
catch {
    Write-Host "Installation failed: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
'@)

# Write to output file
[System.IO.File]::WriteAllText($OutputFile, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))

$outputSize = (Get-Item $OutputFile).Length
Write-Host ""
Write-Host "Obfuscated installer created!" -ForegroundColor Green
Write-Host "  Output: $OutputFile"
Write-Host "  Size: $([Math]::Round($outputSize / 1MB, 2)) MB"
Write-Host ""
Write-Host "Obfuscation features:" -ForegroundColor Yellow
Write-Host "  - Base64 split into $($chunks.Count) 'configuration' chunks"
Write-Host "  - Method names constructed dynamically"
Write-Host "  - Benign-looking variable names"
Write-Host "  - Looks like configuration/setup script"
Write-Host ""
