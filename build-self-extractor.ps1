
$ErrorActionPreference = "Stop"

$sourceDir = "/home/teej/ztest"
$buildDir = Join-Path $sourceDir "build_temp"
$outputScript = Join-Path $sourceDir "install_pmc.ps1"

# 1. Prepare Build Directory
if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
New-Item -ItemType Directory -Path $buildDir | Out-Null

Write-Host "Copying files..."

# Helper to copy with exclusion
function Copy-ToBuild {
    param($Path)
    $dest = Join-Path $buildDir $Path
    if (Test-Path "$sourceDir/$Path") {
        Copy-Item -Path "$sourceDir/$Path" -Destination $dest -Recurse -Container
    }
}

# ==== CORE APPLICATION FILES ====
Copy-ToBuild "lib"          # SpeedTUI library
Copy-ToBuild "module"       # PMC module code
Copy-ToBuild "themes"       # All theme JSON files
Copy-ToBuild "docs"         # Documentation

# Entry point
Copy-Item "$sourceDir/start.ps1" "$buildDir/"

# ==== CONFIG FILES ====
# Default config (theme settings, display options)
$defaultConfig = @'
{
  "Display": {
    "Icons": {
      "Mode": "ascii"
    },
    "Theme": {
      "Active": "default",
      "Hex": "#4488ff"
    }
  }
}
'@
Set-Content -Path "$buildDir/config.json" -Value $defaultConfig

# ==== DATA DIRECTORY STRUCTURE ====
New-Item -ItemType Directory -Path "$buildDir/data" -Force | Out-Null
New-Item -ItemType Directory -Path "$buildDir/data/logs" -Force | Out-Null
New-Item -ItemType Directory -Path "$buildDir/data/backups" -Force | Out-Null

# Empty tasks.json template (NO user data)
$emptyTasksJson = @'
{
  "tasks": [],
  "projects": [],
  "timelogs": [],
  "notes": [],
  "checklists": [],
  "commands": []
}
'@
Set-Content -Path "$buildDir/data/tasks.json" -Value $emptyTasksJson

# Excel config files (empty defaults)
$emptyMappings = @'
{
  "mappings": [],
  "lastUsed": null
}
'@
Set-Content -Path "$buildDir/data/excel-mappings.json" -Value $emptyMappings

$emptyCopyProfiles = @'
{
  "profiles": [],
  "activeProfileId": null
}
'@
Set-Content -Path "$buildDir/data/excel-copy-profiles.json" -Value $emptyCopyProfiles

# ==== CLEANUP ====
# Remove unwanted files from build dir
Get-ChildItem $buildDir -Recurse -Filter "*.log" | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $buildDir -Recurse -Include ".DS_Store", "*.bak*", "*.undo", ".git*" | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
Get-ChildItem $buildDir -Recurse -Filter "Test*.ps1" | Remove-Item -Force -ErrorAction SilentlyContinue

# 2. Compress
Write-Host "Compressing..."
$zipPath = Join-Path $sourceDir "pmc_package.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$buildDir/*" -DestinationPath $zipPath -Force

# 3. Encode
Write-Host "Encoding..."
$bytes = [System.IO.File]::ReadAllBytes($zipPath)
$base64 = [Convert]::ToBase64String($bytes)

# 4. Generate Self-Extractor
Write-Host "Generating installer..."
$installerContent = @"
# PMC TUI Self-Extracting Installer
# Generated: $(Get-Date)

`$base64 = "$base64"

`$zipPath = Join-Path `$PSScriptRoot "pmc_install.zip"
`$installDir = Join-Path `$PSScriptRoot "PMC_TUI"

Write-Host "Extracting PMC TUI..." -ForegroundColor Cyan

# Decode
`$bytes = [Convert]::FromBase64String(`$base64)
[System.IO.File]::WriteAllBytes(`$zipPath, `$bytes)

# Extract
if (Test-Path `$installDir) { Remove-Item `$installDir -Recurse -Force }
Expand-Archive -Path `$zipPath -DestinationPath `$installDir -Force

# Cleanup
Remove-Item `$zipPath -Force

Write-Host "Installation complete at: `$installDir" -ForegroundColor Green
Write-Host "Starting PMC TUI..." -ForegroundColor Cyan

# Run
Set-Location `$installDir
if (Test-Path "./start.ps1") {
    ./start.ps1
} else {
    Write-Error "start.ps1 not found in extraction!"
}
"@

Set-Content -Path $outputScript -Value $installerContent

# Cleanup build artifacts
Remove-Item $buildDir -Recurse -Force
Remove-Item $zipPath -Force

Write-Host "SUCCESS: Installer created at $outputScript" -ForegroundColor Green
