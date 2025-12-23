# debug_header_theme.ps1
$ErrorActionPreference = "Stop"

# 1. Load Dependencies
$global:PmcDebug = $false
$global:PmcTuiLogFile = $null
$moduleRoot = "$PSScriptRoot/module/Pmc.Strict"
. "$moduleRoot/consoleui/src/PmcThemeEngine.ps1"

# 2. Load Config
$configPath = "$PSScriptRoot/config.json"
$json = Get-Content $configPath -Raw | ConvertFrom-Json
$props = $json.Display.Theme.Properties

# Convert PSCustomObject to Hashtable for the engine
$propHash = @{}
$props.PSObject.Properties | ForEach-Object {
    $propHash[$_.Name] = $_.Value
}

# 3. Configure Engine
$engine = [PmcThemeEngine]::GetInstance()
$engine.Configure($propHash, @{})

# 4. Test Properties
Write-Host "Testing Theme Engine Configuration..." -ForegroundColor Cyan

# Test Foreground.Title (Gradient)
$titleGradient = $engine.GetGradientInfo('Foreground.Title')
if ($titleGradient) {
    Write-Host "Foreground.Title: GRADIENT FOUND" -ForegroundColor Green
    Write-Host "  Start: $($titleGradient.Start)"
    Write-Host "  End:   $($titleGradient.End)"
} else {
    Write-Host "Foreground.Title: GRADIENT MISSING (Got null)" -ForegroundColor Red
}

# Test Background.Header (Solid)
$headerBg = $engine.GetThemeColorInt('Background.Header')
Write-Host "Background.Header: $headerBg" -ForegroundColor Gray

# Test Background.Footer (Solid)
$footerBg = $engine.GetThemeColorInt('Background.Footer')
Write-Host "Background.Footer: $footerBg" -ForegroundColor Gray

# Test Border.Widget (Solid)
$border = $engine.GetThemeColorInt('Border.Widget')
Write-Host "Border.Widget: $border" -ForegroundColor Gray
