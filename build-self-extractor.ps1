
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

# Copy structure
Copy-ToBuild "lib"
Copy-ToBuild "module"
Copy-ToBuild "themes"
Copy-ToBuild "docs"
Copy-Item "$sourceDir/start.ps1" "$buildDir/"
if (Test-Path "$sourceDir/config.json") { Copy-Item "$sourceDir/config.json" "$buildDir/" }
if (Test-Path "$sourceDir/tasks.json") { Copy-Item "$sourceDir/tasks.json" "$buildDir/" }

# Clean up excluded items from build dir (e.g. if inside copied folders)
Get-ChildItem $buildDir -Recurse -Filter "*.log" | Remove-Item -Force
Get-ChildItem $buildDir -Recurse -Include ".DS_Store" | Remove-Item -Force

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
