using namespace System.Collections.Generic
using namespace System.Text

# ChecklistTemplatesFolderScreen - Manage folder-based checklist templates
# Templates are simple .txt files in checklist_templates/ folder

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ChecklistService.ps1"
. "$PSScriptRoot/../widgets/ProjectPicker.ps1"
. "$PSScriptRoot/../widgets/TextAreaEditor.ps1"

class ChecklistTemplatesFolderScreen : StandardListScreen {
    hidden [ChecklistService]$_checklistService = $null
    hidden [string]$_templatesFolder = ""
    
    # Project Picker for Import
    hidden [ProjectPicker]$_projectPicker = $null
    hidden [bool]$_showProjectPicker = $false

    # TUI Text Editor for inline editing
    hidden [TextAreaEditor]$_textEditor = $null
    hidden [bool]$_showTextEditor = $false
    hidden [string]$_editingFilePath = ""
    hidden [string]$_editingFileName = ""

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Tools', 'Checklist Templates', 'H', {
            . "$PSScriptRoot/ChecklistTemplatesFolderScreen.ps1"
            $global:PmcApp.PushScreen((New-Object -TypeName ChecklistTemplatesFolderScreen))
        }, 30)
    }

    # Constructors
    ChecklistTemplatesFolderScreen() : base("ChecklistTemplates", "Checklist Templates") {
        $this._InitializeScreen()
    }

    ChecklistTemplatesFolderScreen([object]$container) : base("ChecklistTemplates", "Checklist Templates", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        $this._checklistService = [ChecklistService]::GetInstance()
        
        # Determine templates folder (at PMC root)
        $pmcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $this._templatesFolder = Join-Path $pmcRoot "checklist_templates"

        if (-not (Test-Path $this._templatesFolder)) {
            New-Item -ItemType Directory -Path $this._templatesFolder -Force | Out-Null
        }

        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        $this.Header.SetBreadcrumb(@("Home", "Tools", "Checklist Templates"))
    }

    # === Abstract Method Implementations ===

    [string] GetEntityType() { return 'checklist_template_file' }

    [array] GetColumns() {
        return @(
            @{ Name='name'; Label='Template Name'; Width=40; Sortable=$true }
            @{ Name='item_count'; Label='Items'; Width=8; Sortable=$true; Align='right' }
            @{ Name='modified'; Label='Modified'; Width=20; Sortable=$true }
        )
    }

    [void] LoadData() {
        $items = $this.LoadItems()
        $this.List.SetData($items)
    }

    [array] LoadItems() {
        $templates = @()
        $files = Get-ChildItem -Path $this._templatesFolder -Filter "*.txt" -File -ErrorAction SilentlyContinue

        foreach ($file in $files) {
            $lineCount = 0
            try {
                $content = Get-Content -Path $file.FullName -ErrorAction Stop
                $lineCount = @($content | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
            } catch { $lineCount = 0 }

            $templates += @{
                name = $file.BaseName
                file_path = $file.FullName
                item_count = $lineCount
                modified = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            }
        }
        return $templates
    }

    [array] GetEditFields([object]$item) {
        if ($null -eq $item -or $item.Count -eq 0) {
            return @(@{ Name='name'; Type='text'; Label='Template Name'; Required=$true; Value='' })
        } else {
            return @(@{ Name='name'; Type='text'; Label='Template Name'; Required=$true; Value=$item.name })
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        try {
            if (-not $values.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($values.name)) {
                $this.SetStatusMessage("Template name is required", "error")
                return
            }

            $name = $values.name
            $fileName = "$name.txt"
            $filePath = Join-Path $this._templatesFolder $fileName

            if (Test-Path $filePath) {
                $this.SetStatusMessage("Template '$name' already exists", "error")
                return
            }

            $content = ""
            Set-Content -Path $filePath -Value $content -Encoding utf8

            $this.SetStatusMessage("Template '$name' created. Press Enter to edit.", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error creating template: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            $oldName = $(if ($item -is [hashtable]) { $item['name'] } else { $item.name })
            $oldPath = $(if ($item -is [hashtable]) { $item['file_path'] } else { $item.file_path })

            if (-not $values.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($values.name)) {
                $this.SetStatusMessage("Template name is required", "error")
                return
            }

            $newName = $values.name
            $newPath = Join-Path $this._templatesFolder "$newName.txt"

            if ($oldPath -eq $newPath) { return }

            if (Test-Path $newPath) {
                $this.SetStatusMessage("Template '$newName' already exists", "error")
                return
            }

            Move-Item -Path $oldPath -Destination $newPath -Force
            $this.SetStatusMessage("Template renamed to '$newName'", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error renaming template: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $name = $(if ($item -is [hashtable]) { $item['name'] } else { $item.name })
            $filePath = $(if ($item -is [hashtable]) { $item['file_path'] } else { $item.file_path })

            if (Test-Path $filePath) {
                Remove-Item -Path $filePath -Force
                $this.SetStatusMessage("Template '$name' deleted", "success")
                $this.LoadData()
            } else {
                $this.SetStatusMessage("Template file not found", "error")
            }
        } catch {
            $this.SetStatusMessage("Error deleting template: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemActivated($item) {
        $filePath = $(if ($item -is [hashtable]) { $item['file_path'] } else { $item.file_path })

        try {
            if (Test-Path $filePath) {
                if ($global:IsWindows -or $env:OS -match "Windows") {
                    Start-Process notepad.exe -ArgumentList $filePath
                } else {
                    # Linux: try xdg-open first, then common editors
                    $opened = $false
                    
                    # Try xdg-open (opens with system default text editor)
                    if (Get-Command xdg-open -ErrorAction SilentlyContinue) {
                        Start-Process xdg-open -ArgumentList $filePath
                        $opened = $true
                    }
                    # Fallback to common terminal editors
                    elseif (Get-Command nano -ErrorAction SilentlyContinue) {
                        # Note: This will suspend TUI - not ideal but functional
                        $this.SetStatusMessage("Opening in nano... (exit with Ctrl+X)", "info")
                        & nano $filePath
                        $opened = $true
                    }
                    elseif (Get-Command vim -ErrorAction SilentlyContinue) {
                        $this.SetStatusMessage("Opening in vim... (exit with :q)", "info")
                        & vim $filePath
                        $opened = $true
                    }
                    elseif (Get-Command vi -ErrorAction SilentlyContinue) {
                        $this.SetStatusMessage("Opening in vi... (exit with :q)", "info")
                        & vi $filePath
                        $opened = $true
                    }
                    
                    if (-not $opened) {
                        $this.SetStatusMessage("No editor found. File: $filePath", "warning")
                    }
                }
            } else {
                $this.SetStatusMessage("Template file not found", "error")
            }
        } catch {
            $this.SetStatusMessage("Error opening template: $($_.Exception.Message)", "error")
        }
    }

    [array] GetCustomActions() {
        $self = $this
        return @(
            @{
                Key = 'I'
                Label = 'Import to Project'
                Callback = {
                    $selected = $self.List.GetSelectedItem()
                    if ($selected) {
                        $self._ImportToProject($selected)
                    }
                }.GetNewClosure()
            }
            @{
                Key = 'O'
                Label = 'System Editor'
                Callback = {
                    $selected = $self.List.GetSelectedItem()
                    if ($selected) {
                        $self.OnItemActivated($selected)
                    }
                }.GetNewClosure()
            }
            @{
                Key = 'T'
                Label = 'TUI Editor'
                Callback = {
                    $selected = $self.List.GetSelectedItem()
                    if ($selected) {
                        $self._OpenInTuiEditor($selected)
                    }
                }.GetNewClosure()
            }
        )
    }

    # === TUI Text Editor ===

    hidden [void] _OpenInTuiEditor($template) {
        $filePath = $(if ($template -is [hashtable]) { $template['file_path'] } else { $template.file_path })
        $fileName = $(if ($template -is [hashtable]) { $template['name'] } else { $template.name })

        if (-not (Test-Path $filePath)) {
            $this.SetStatusMessage("Template file not found", "error")
            return
        }

        # Create editor if needed
        if (-not $this._textEditor) {
            $this._textEditor = [TextAreaEditor]::new()
        }

        # Load file content
        try {
            $content = Get-Content -Path $filePath -Raw -ErrorAction Stop
            if ($null -eq $content) { $content = "" }
            $this._textEditor.SetText($content)
        } catch {
            $this.SetStatusMessage("Error loading file: $($_.Exception.Message)", "error")
            return
        }

        $this._editingFilePath = $filePath
        $this._editingFileName = $fileName
        $this._showTextEditor = $true
        $this.NeedsClear = $true
    }

    hidden [void] _SaveAndCloseEditor() {
        if (-not $this._showTextEditor) { return }

        try {
            $content = $this._textEditor.GetText()
            Set-Content -Path $this._editingFilePath -Value $content -Encoding utf8 -NoNewline
            $this.SetStatusMessage("Saved '$($this._editingFileName)'", "success")
        } catch {
            $this.SetStatusMessage("Error saving: $($_.Exception.Message)", "error")
        }

        $this._showTextEditor = $false
        $this._editingFilePath = ""
        $this._editingFileName = ""
        $this.NeedsClear = $true
        $this.LoadData()  # Refresh list to show updated item count
    }

    hidden [void] _CancelEditor() {
        $this._showTextEditor = $false
        $this._editingFilePath = ""
        $this._editingFileName = ""
        $this.NeedsClear = $true
    }

    # === Import Feature ===

    hidden [void] _ImportToProject($template) {
        $this._projectPicker = [ProjectPicker]::new()
        $this._projectPicker.SetSize(60, 20)
        
        # Center Logic
        $pW = 60
        $pH = 20
        $this._projectPicker.SetPosition(
            [Math]::Max(0, [Math]::Floor(($this.TermWidth - $pW) / 2)),
            [Math]::Max(0, [Math]::Floor(($this.TermHeight - $pH) / 2))
        )

        $self = $this
        $this._projectPicker.OnProjectSelected = {
            param($projectName)
            if ($projectName) {
                $self._DoImport($template, $projectName)
            }
            $self._showProjectPicker = $false
            $self._projectPicker = $null
            $self.NeedsClear = $true
        }.GetNewClosure()

        $this._projectPicker.OnCancelled = {
            $self._showProjectPicker = $false
            $self._projectPicker = $null
            $self.NeedsClear = $true
        }.GetNewClosure()
        
        $this._showProjectPicker = $true
        $this.NeedsClear = $true
    }
    
    hidden [void] _DoImport($template, $projectName) {
        $filePath = if ($template -is [hashtable]) { $template.file_path } else { $template.file_path }
        if (-not (Test-Path $filePath)) { 
             $this.SetStatusMessage("Template file missing", "error")
             return 
        }
        
        try {
            $lines = Get-Content $filePath | Where-Object { 
                -not [string]::IsNullOrWhiteSpace($_) -and -not $_.Trim().StartsWith("#") 
            }
            
            if ($lines.Count -eq 0) {
                 $this.SetStatusMessage("Template is empty", "error")
                 return
            }
            
            $title = if ($template -is [hashtable]) { $template.name } else { $template.name }
            
            # Create instance
            $this._checklistService.CreateBlankInstance($title, "project", $projectName, $lines)
            $this.SetStatusMessage("Imported '$title' to project '$projectName'", "success")
        }
        catch {
            $this.SetStatusMessage("Import failed: $($_.Exception.Message)", "error")
        }
    }

    # === Render Overrides ===

    [void] RenderToEngine([object]$engine) {
        # If text editor is showing, render ONLY the editor (skip list entirely)
        if ($this._showTextEditor -and $this._textEditor) {
            # Render base chrome (Menu, Header, Footer) but NOT the list
            ([PmcScreen]$this).RenderToEngine($engine)

            # Clear content area first
            $editorY = 4  # Below menu/header
            $editorHeight = $this.TermHeight - 7  # Leave room for footer/status
            $contentBg = $this.GetThemedBgInt('Background.Row', 1, 0)
            $engine.Fill(0, $editorY - 1, $this.TermWidth, $editorHeight + 2, ' ', 0, $contentBg)

            # Position editor to fill content area
            $this._textEditor.SetPosition(1, $editorY)
            $this._textEditor.SetSize($this.TermWidth - 2, $editorHeight)
            $this._textEditor.ShowCursor = $true

            # Draw title bar
            $titleText = " Editing: $($this._editingFileName) [Ctrl+S: Save & Exit | Esc: Cancel] "
            $titleFg = $this.GetThemedInt('Foreground.Title')
            $titleBg = $this.GetThemedBgInt('Background.Header', 1, 0)
            $engine.Fill(0, $editorY - 1, $this.TermWidth, 1, ' ', $titleFg, $titleBg)
            $engine.WriteAt(1, $editorY - 1, $titleText, $titleFg, $titleBg)

            $this._textEditor.RenderToEngine($engine)
            return
        }

        # Normal list rendering via base class
        ([StandardListScreen]$this).RenderToEngine($engine)
        
        # Render Picker Overlay
        if ($this._showProjectPicker -and $this._projectPicker) {
             # Re-center if terminal resized
            $pW = 60
            $pH = 20
            $this._projectPicker.SetPosition(
                [Math]::Max(0, [Math]::Floor(($this.TermWidth - $pW) / 2)),
                [Math]::Max(0, [Math]::Floor(($this.TermHeight - $pH) / 2))
            )
            
            $this._projectPicker.RenderToEngine($engine)
        }
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # TUI Text Editor handling
        if ($this._showTextEditor -and $this._textEditor) {
            # Ctrl+S: Save and exit
            if ($keyInfo.Key -eq [ConsoleKey]::S -and ($keyInfo.Modifiers -band [ConsoleModifiers]::Control)) {
                $this._SaveAndCloseEditor()
                return $true
            }
            # Escape: Cancel without saving
            if ($keyInfo.Key -eq [ConsoleKey]::Escape) {
                $this._CancelEditor()
                return $true
            }
            # Route all other keys to the editor
            return $this._textEditor.HandleInput($keyInfo)
        }

        if ($this._showProjectPicker -and $this._projectPicker) {
            return $this._projectPicker.HandleInput($keyInfo)
        }
        
        return ([StandardListScreen]$this).HandleKeyPress($keyInfo)
    }
}