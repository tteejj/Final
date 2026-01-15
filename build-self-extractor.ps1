
$ErrorActionPreference = "Stop"

$sourceDir = $PSScriptRoot
$buildDir = Join-Path $sourceDir "build_temp"
$outputScript = Join-Path $sourceDir "install_pmc.ps1"

# 1. Prepare Build Directory
if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
New-Item -ItemType Directory -Path $buildDir | Out-Null

Write-Host "Copying files..."

# Helper to copy files/folders
function Copy-ItemSafe {
    param($Path, $Destination)
    $src = Join-Path $sourceDir $Path
    if (Test-Path $src) {
        $destPath = Join-Path $buildDir $Destination
        $parent = Split-Path $destPath -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -Path $src -Destination $destPath -Recurse -Force
    } else {
        Write-Warning "Source not found: $Path"
    }
}

# ==== CORE APPLICATION FILES ====
Copy-ItemSafe "lib/SpeedTUI" "lib/SpeedTUI"
Copy-ItemSafe "module/Pmc.Strict" "module/Pmc.Strict"
Copy-ItemSafe "themes" "themes"
# Include checklist templates if they exist (factory defaults)
Copy-ItemSafe "module/checklist_templates" "module/checklist_templates"

# Entry point
Copy-ItemSafe "start.ps1" "start.ps1"

# ==== CONFIG FILES ====
# Copy default config if it exists, otherwise create default
$configPath = Join-Path $sourceDir "config.json"
if (Test-Path $configPath) {
    Copy-ItemSafe "config.json" "config.json"
} else {
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
}

# ==== DATA DIRECTORY STRUCTURE ====
New-Item -ItemType Directory -Path "$buildDir/data" -Force | Out-Null
New-Item -ItemType Directory -Path "$buildDir/data/logs" -Force | Out-Null
New-Item -ItemType Directory -Path "$buildDir/data/backups" -Force | Out-Null

# Copy Excel configs if they exist
Copy-ItemSafe "data/excel-mappings.json" "data/excel-mappings.json"
Copy-ItemSafe "data/excel-copy-profiles.json" "data/excel-copy-profiles.json"

# Tasks.json - Create empty if not exists (don't overwrite user data in installer, but for self-extractor we package default)
# The installer script (generated below) logic handles not overwriting if exists on target.
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

# ==== CLEANUP ====
# Remove unwanted files from build dir (just in case they were copied recursively)
Get-ChildItem $buildDir -Recurse -Filter "*.log" | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $buildDir -Recurse -Include ".DS_Store", "*.bak*", "*.undo", ".git*", ".pmc-data", "ISSUES_FOUND.md", "*.tmp" | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
# Remove test files from module
Get-ChildItem "$buildDir/module" -Recurse -Filter "Test*.ps1" | Remove-Item -Force -ErrorAction SilentlyContinue
# Remove repro scripts
Get-ChildItem "$buildDir/module" -Recurse -Filter "repro*.ps1" | Remove-Item -Force -ErrorAction SilentlyContinue

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
if (Test-Path `$installDir) {
    Write-Host "Backing up existing installation..."
    `$backupDir = "`$installDir.bak.`$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Rename-Item `$installDir `$backupDir
}
Expand-Archive -Path `$zipPath -DestinationPath `$installDir -Force

# Restore Data if exists (Upgrade scenario)
# We need to be careful not to overwrite user data with defaults if they exist in the backup
# But here we just extract to a fresh dir.
# If the user runs this in a folder where they want to install, it creates PMC_TUI.

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
