
# repro_manual.ps1
$ErrorActionPreference = "Stop"

# Mock Get-PmcState (missing from module)
function Get-PmcState { param($Section) return $null }
function Get-PmcColorPalette { return @{} }

# Mock Write-PmcTuiLog (defined in Start-PmcTUI.ps1)
    function Write-PmcTuiLog {
        param($Message, $Level="INFO")
        # Add-Content -Path "repro.log" -Value "[$Level] $Message"
    }

try {
    $consoleUiRoot = $PSScriptRoot
    $srcRoot = Join-Path (Split-Path -Parent $consoleUiRoot) "src"

    Write-Host "Loading Dependencies..."
    . "$consoleUiRoot/DepsLoader.ps1"
    . "$consoleUiRoot/SpeedTUILoader.ps1"
    . "$consoleUiRoot/src/PmcThemeEngine.ps1"
    . "$consoleUiRoot/layout/PmcLayoutManager.ps1"
    . "$consoleUiRoot/widgets/PmcWidget.ps1"
    . "$consoleUiRoot/widgets/PmcDialog.ps1"
    . "$consoleUiRoot/services/NoteService.ps1"
    . "$consoleUiRoot/services/ChecklistService.ps1"
    . "$consoleUiRoot/helpers/GapBuffer.ps1"
    . "$consoleUiRoot/helpers/Constants.ps1"
    . "$consoleUiRoot/helpers/TypeNormalization.ps1"
    . "$consoleUiRoot/widgets/TextAreaEditor.ps1"
    . "$consoleUiRoot/widgets/PmcHeader.ps1"
    . "$consoleUiRoot/widgets/PmcFooter.ps1"
    . "$consoleUiRoot/widgets/PmcStatusBar.ps1"
    . "$consoleUiRoot/widgets/PmcMenuBar.ps1"
    . "$consoleUiRoot/widgets/PmcPanel.ps1"
    . "$consoleUiRoot/PmcScreen.ps1"
    . "$consoleUiRoot/screens/NoteEditorScreen.ps1"

    Write-Host "Starting Test..."

    # 1. Setup
    $noteService = [NoteService]::GetInstance()
    $note = $noteService.CreateNote("Test Note Manual")
    Write-Host "Created Note: $($note.id)"
    
    $screen = [NoteEditorScreen]::new($note.id)
    
    # Mock RenderEngine with ScriptMethods
    $global:renderCalls = [System.Collections.ArrayList]::new()
    $engine = [PSCustomObject]@{
        Width = 80
        Height = 24
    }
    
    $engine | Add-Member -MemberType ScriptMethod -Name "BeginLayer" -Value { param($l) }
    $engine | Add-Member -MemberType ScriptMethod -Name "DrawBox" -Value { param($x, $y, $w, $h, $s) Write-Host "DrawBox: $x,$y ${w}x${h}" }
    # FillRect and DrawString removed to match HybridRenderEngine
    $engine | Add-Member -MemberType ScriptMethod -Name "Fill" -Value { param($x,$y,$w,$h,$c,$f,$b) }
    $engine | Add-Member -MemberType ScriptMethod -Name "WriteAt" -Value { param($x,$y,$c,$f,$b) 
        $global:renderCalls.Add("WriteAt: '$c' at $x,$y") 
    }
    $engine | Add-Member -MemberType ScriptMethod -Name "PushClip" -Value { param($x,$y,$w,$h) }
    $engine | Add-Member -MemberType ScriptMethod -Name "PopClip" -Value { }
    $engine | Add-Member -MemberType ScriptMethod -Name "DefineRegion" -Value { param($id,$x,$y,$w,$h) }
    $engine | Add-Member -MemberType ScriptMethod -Name "WriteToRegion" -Value { param($id,$x,$y,$c,$f,$b) 
        $global:renderCalls.Add("WriteToRegion: '$c' at $x,$y in $id") 
    }
    $engine | Add-Member -MemberType ScriptMethod -Name "GetRegionBounds" -Value { param($id) 
        return [PSCustomObject]@{ X=0; Y=0; Width=80; Height=1 }
    }
    
    # Mock Container
    $container = [PSCustomObject]@{
        Get = { param($n) return $null }
        Resolve = { param($n) return $null }
    }

    # 2. Initialize
    $screen.Initialize($engine, $container)
    $screen.OnEnter()

    # Verify Editor Bounds
    $editor = $screen._editor
    Write-Host "Editor Bounds: X=$($editor.X) Y=$($editor.Y) W=$($editor.Width) H=$($editor.Height)"
    
    if ($editor.Width -ne 80 -or $editor.Height -ne 16) {
        Write-Error "Incorrect Editor Bounds"
    }
    
    # 3. Simulate Resize
    Write-Host "Simulating Resize to 100x30..."
    $screen.OnTerminalResize(100, 30)
    
    Write-Host "New Editor Bounds: X=$($editor.X) Y=$($editor.Y) W=$($editor.Width) H=$($editor.Height)"
    if ($editor.Width -ne 100 -or $editor.Height -ne 22) { # 30 - 8 = 22
        Write-Error "Incorrect Editor Bounds after resize. Expected 100x22, got $($editor.Width)x$($editor.Height)"
    } else {
        Write-Host "Resize logic verified."
    }

    # 4. Simulate Input (Type "Hello")
    $keys = "Hello".ToCharArray() | ForEach-Object {
        [ConsoleKeyInfo]::new($_, [ConsoleKey]::A, $false, $false, $false)
    }
    
    foreach ($k in $keys) {
        $handled = $screen.HandleKeyPress($k)
        if (-not $handled) { Write-Error "Key not handled: $($k.KeyChar)" }
    }

    # Verify Content in Editor
    $text = $editor.GetText()
    Write-Host "Editor Text: '$text'"
    
    if ($text -notmatch "Hello") {
        Write-Error "Editor text mismatch. Expected '...Hello', got '$text'"
    }
    
    # 5. Verify Rendering
    Write-Host "Rendering Screen..."
    $screen.RenderToEngine($engine)
    
    Write-Host "Render Calls: $($global:renderCalls.Count)"
    if ($global:renderCalls.Count -eq 0) {
        Write-Error "No render calls made! Screen is blank."
    } else {
        # Check if "Hello" was rendered
        $renderedText = $global:renderCalls | Where-Object { $_ -match "Hello" }
        if (-not $renderedText) {
            Write-Warning "Text 'Hello' not found in render calls. Maybe rendered char by char?"
            # Check for individual chars
            $h = $global:renderCalls | Where-Object { $_ -match "WriteAt: 'H'" }
            if (-not $h) {
                Write-Error "Character 'H' not found in render calls."
            } else {
                Write-Host "Found rendered characters."
            }
        } else {
            Write-Host "Found rendered text."
        }
    }

    # 6. Simulate Escape (Exit)
    # Mock PmcApp global with ScriptMethod
    $global:PmcApp = [PSCustomObject]@{}
    $global:PmcApp | Add-Member -MemberType ScriptMethod -Name "PopScreen" -Value { Write-Host "PopScreen called" }

    Write-Host "Pressing Escape..."
    $esc = [ConsoleKeyInfo]::new([char]27, [ConsoleKey]::Escape, $false, $false, $false)
    $screen.HandleKeyPress($esc)

    # 7. Verify Saved Content
    $savedContent = $noteService.LoadNoteContent($note.id)
    Write-Host "Saved Content: '$savedContent'"
    
    if ($savedContent -notmatch "Hello") {
        Write-Error "Saved content mismatch. Expected '...Hello', got '$savedContent'"
    } else {
        Write-Host "TEST PASSED: Note saved successfully."
    }

    # Cleanup
    $noteService.DeleteNote($note.id)
    $global:PmcApp = $null
    $global:renderCalls = $null

} catch {
    Write-Host "TEST FAILED: $_"
    Write-Host "Stack: $($_.ScriptStackTrace)"
}
