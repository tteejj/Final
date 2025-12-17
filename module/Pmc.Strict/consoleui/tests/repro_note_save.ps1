
# tests/repro_note_save.ps1
using namespace System
using namespace System.Collections.Generic

# Setup paths
$consoleUiRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path (Split-Path -Parent $consoleUiRoot) "src"

# 1. Load Core Dependencies (mimicking Start-PmcTUI.ps1)
. "$consoleUiRoot/DepsLoader.ps1"
. "$consoleUiRoot/SpeedTUILoader.ps1"

# Load PraxisVT if available (mock if not)
if (Test-Path "$srcRoot/PraxisVT.ps1") {
    . "$srcRoot/PraxisVT.ps1"
}

# Load Core Infrastructure
. "$consoleUiRoot/ZIndex.ps1"
. "$consoleUiRoot/src/PmcThemeEngine.ps1"
. "$consoleUiRoot/theme/PmcThemeManager.ps1"
. "$consoleUiRoot/layout/PmcLayoutManager.ps1"

# Load Base Widgets
. "$consoleUiRoot/widgets/PmcWidget.ps1"
. "$consoleUiRoot/widgets/PmcDialog.ps1"

# Load Services
. "$consoleUiRoot/services/NoteService.ps1"
. "$consoleUiRoot/services/ChecklistService.ps1"

# Load Helpers
. "$consoleUiRoot/helpers/GapBuffer.ps1"
. "$consoleUiRoot/helpers/Constants.ps1"
. "$consoleUiRoot/helpers/TypeNormalization.ps1"

# Load Widgets
. "$consoleUiRoot/widgets/TextAreaEditor.ps1"
. "$consoleUiRoot/widgets/PmcHeader.ps1"
. "$consoleUiRoot/widgets/PmcFooter.ps1"
. "$consoleUiRoot/widgets/PmcStatusBar.ps1"
. "$consoleUiRoot/widgets/PmcMenuBar.ps1"
. "$consoleUiRoot/widgets/PmcPanel.ps1"

# Load Screen Base
. "$consoleUiRoot/PmcScreen.ps1"

# Load Target Screen
. "$consoleUiRoot/screens/NoteEditorScreen.ps1"

Describe "Note Editor Save Issue" {
    Context "NoteEditorScreen Logic" {
        It "Should save note on exit when modified" {
            # 1. Setup
            $noteService = [NoteService]::GetInstance()
            $note = $noteService.CreateNote("Test Note")
            $screen = [NoteEditorScreen]::new($note.id)
            
            # Mock RenderEngine
            $engine = [PSCustomObject]@{
                Width = 80
                Height = 24
                BeginLayer = { param($l) }
                Fill = { param($x,$y,$w,$h,$c,$f,$b) }
                WriteAt = { param($x,$y,$c,$f,$b) }
                PushClip = { param($x,$y,$w,$h) }
                PopClip = { }
                DefineRegion = { param($id,$x,$y,$w,$h) }
            }
            
            # Mock Container (if needed)
            $container = [PSCustomObject]@{
                Get = { param($n) return $null }
                Resolve = { param($n) return $null }
            }

            # 2. Initialize
            $screen.Initialize($engine, $container)
            $screen.OnEnter()

            # Verify Editor Bounds
            $editor = $screen.GetType().GetField("_editor", [System.Reflection.BindingFlags]"NonPublic,Instance").GetValue($screen)
            $editor.Width | Should -Be 80
            $editor.Height | Should -Be 16 # 24 - 8
            
            # 3. Simulate Input (Type "Hello")
            $keys = "Hello".ToCharArray() | ForEach-Object {
                [ConsoleKeyInfo]::new($_, [ConsoleKey]::A, $false, $false, $false)
            }
            
            foreach ($k in $keys) {
                $screen.HandleKeyPress($k) | Should -Be $true
            }

            # Verify Content in Editor
            $editor.GetText() | Should -Be "Hello"
            $editor.Modified | Should -Be $true

            # 4. Simulate Escape (Exit)
            # We need to mock PmcApp global or handle PopScreen
            $global:PmcApp = [PSCustomObject]@{
                PopScreen = { }
            }

            $esc = [ConsoleKeyInfo]::new([char]27, [ConsoleKey]::Escape, $false, $false, $false)
            $screen.HandleKeyPress($esc) | Should -Be $true

            # 5. Verify Saved Content
            $savedContent = $noteService.LoadNoteContent($note.id)
            $savedContent | Should -Be "Hello"

            # Cleanup
            $noteService.DeleteNote($note.id)
            $global:PmcApp = $null
        }
    }
}
