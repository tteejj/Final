
$ErrorActionPreference = "Stop"

$script:PmcAppRoot = "/home/teej/ztest"
$global:PmcAppRoot = $script:PmcAppRoot

$mockEngine = [PSCustomObject]@{
    Width = 80
    Height = 24
}
$mockEngine | Add-Member -MemberType ScriptMethod -Name "WriteAt" -Value { param($x, $y, $s, $f, $b) }
$mockEngine | Add-Member -MemberType ScriptMethod -Name "Fill" -Value { param($x, $y, $w, $h, $c, $f, $b) }
$mockEngine | Add-Member -MemberType ScriptMethod -Name "SetCursorPosition" -Value { param($x, $y) }
$mockEngine | Add-Member -MemberType ScriptMethod -Name "RequestClear" -Value { }

# Mock Global App object
$global:PmcApp = [PSCustomObject]@{
    RenderEngine = $mockEngine
    CurrentScreen = [PSCustomObject]@{ 
        NeedsClear = $false 
        Header = [PSCustomObject]@{ _themeInitialized = $true }
        Footer = [PSCustomObject]@{ _themeInitialized = $true }
        StatusBar = [PSCustomObject]@{ _themeInitialized = $true }
    }
}
$global:PmcApp | Add-Member -MemberType ScriptMethod -Name "RequestRender" -Value { }
$global:PmcApp | Add-Member -MemberType ScriptMethod -Name "PopScreen" -Value { }

function Export-ModuleMember { param([Parameter(ValueFromRemainingArguments=$true)]$args) }

try {
    Write-Host "Loading dependencies..."
    $moduleRoot = Join-Path $PmcAppRoot "module/Pmc.Strict/consoleui"
    
    # Load minimal dependencies
    # Load SpeedTUI framework
    . "$moduleRoot/../Core/PmcCache.ps1"
    . "$moduleRoot/SpeedTUILoader.ps1"
    
    . "$moduleRoot/services/DataService.ps1"
    . "$moduleRoot/ZIndex.ps1"
    . "$moduleRoot/theme/PmcThemeManager.ps1"
    . "$moduleRoot/src/PmcThemeEngine.ps1"
    . "$moduleRoot/layout/PmcLayoutManager.ps1"
    . "$moduleRoot/widgets/PmcWidget.ps1"
    . "$moduleRoot/widgets/PmcPanel.ps1"
    # PmcWaitSpinner removed (not used/not found)
    
    # helper needed
    . "$moduleRoot/helpers/ThemeLoader.ps1"
    . "$moduleRoot/helpers/ThemeHelper.ps1"
    . "$moduleRoot/widgets/PmcFooter.ps1"
    . "$moduleRoot/widgets/PmcHeader.ps1"
    . "$moduleRoot/widgets/PmcMenuBar.ps1"
    . "$moduleRoot/widgets/PmcStatusBar.ps1"

    . "$moduleRoot/PmcScreen.ps1"

    Write-Host "Loading ThemeEditorScreen..."
    . "$moduleRoot/screens/ThemeEditorScreen.ps1"
    
    Write-Host "Instantiating ThemeEditorScreen..."
    $screen = [ThemeEditorScreen]::new()
    
    Write-Host "Initializing ThemeEditorScreen..."
    $screen.Initialize($global:PmcApp.RenderEngine, $null)
    
    Write-Host "Loading Data..."
    $screen.LoadData()
    
    Write-Host "Rendering ThemeEditorScreen..."
    $screen.RenderContentToEngine($global:PmcApp.RenderEngine)
    
    Write-Host "Simulating Enter Key (Apply Theme)..."
    $keyInfo = [ConsoleKeyInfo]::new([char]13, [ConsoleKey]::Enter, $false, $false, $false)
    $screen.HandleKeyPress($keyInfo)
    
    Write-Host "SUCCESS: ThemeEditorScreen rendered and applied theme."
    
} catch {
    Write-Host "CRITICAL FAILURE: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}
