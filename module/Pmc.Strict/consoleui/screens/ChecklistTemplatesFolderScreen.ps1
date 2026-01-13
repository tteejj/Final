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
        # Refresh service cache to ensure we see latest files
        $this._checklistService.ReloadTemplates()
        
        $items = $this.LoadItems()
        $this.List.SetData($items)
    }

    [array] LoadItems() {
        $templates = @()
        
        # Use service as source of truth
        $serviceTemplates = $this._checklistService.GetAllTemplates()

        foreach ($tmpl in $serviceTemplates) {
            $name = Get-SafeProperty $tmpl 'name'
            $path = Get-SafeProperty $tmpl 'file_path'
            $items = Get-SafeProperty $tmpl 'items'
            $mod = Get-SafeProperty $tmpl 'modified'

            $count = if ($items) { $items.Count } else { 0 }
            $modStr = if ($mod -is [datetime]) { $mod.ToString("yyyy-MM-dd HH:mm") } else { "$mod" }

            $templates += @{
                name = $name
                file_path = $path
                item_count = $count
                modified = $modStr
            }
        }
        return $templates
    }

    [void] OnAdd() {
        # Create a new file via editor
        $this._editingFileName = "New Template.txt"
        $this._editingFilePath = Join-Path $this._templatesFolder $this._editingFileName
        
        # Ensure unique name
        $counter = 1
        while (Test-Path $this._editingFilePath) {
            $this._editingFileName = "New Template $counter.txt"
            $this._editingFilePath = Join-Path $this._templatesFolder $this._editingFileName
            $counter++
        }

        # Create empty file
        "" | Set-Content -Path $this._editingFilePath -Encoding utf8

        $this._OpenEditor($this._editingFilePath)
    }

    [void] OnEdit() {
        $item = $this.List.GetSelectedItem()
        if ($item) {
            $path = Get-SafeProperty $item 'file_path'
            $this._OpenEditor($path)
        }
    }

    [void] OnDelete() {
        $item = $this.List.GetSelectedItem()
        if ($item) {
            $name = Get-SafeProperty $item 'name'
            $this.ShowConfirmation("Delete Template", "Are you sure you want to delete '$name'?", {
                try {
                    # Use service to delete
                    $this._checklistService.DeleteTemplate($name)
                    $this.SetStatusMessage("Deleted template '$name'", "success")
                    $this.LoadData()
                } catch {
                    $this.SetStatusMessage("Failed to delete: $_", "error")
                }
            })
        }
    }

    # === Custom Actions ===

    [void] _ConfigureListActions() {
        # Call base to setup standard actions
        ([StandardListScreen]$this)._ConfigureListActions()

        # Capture $this for closures
        $self = $this

        # OVERRIDE: Replace 'a' action to use custom OnAdd() instead of InlineEditor
        $addOverride = { $self.OnAdd() }.GetNewClosure()
        $this.List.AddAction('a', 'Add', $addOverride)
        
        # OVERRIDE: Replace 'e' action to use custom OnEdit() instead of InlineEditor
        $editOverride = { $self.OnEdit() }.GetNewClosure()
        $this.List.AddAction('e', 'Edit', $editOverride)

        # Add Import Action
        $importAction = {
            $item = $self.List.GetSelectedItem()
            if ($item) { $self._ImportToProject($item) }
        }.GetNewClosure()
        $this.List.AddAction('i', 'Import to Project', $importAction)
        
        # 't' is redundant if we map 'e', but keeping for compatibility if users are used to it
        $tuiEditAction = { $self.OnEdit() }.GetNewClosure()
        $this.List.AddAction('t', 'Edit Template', $tuiEditAction)

        # Add Open in External Editor Action
        $openAction = {
            $item = $self.List.GetSelectedItem()
            if ($item) { 
                $path = Get-SafeProperty $item 'file_path'
                $self._OpenInExternalEditor($path) 
            }
        }.GetNewClosure()
        $this.List.AddAction('o', 'Open External', $openAction)
        
        # Update Footer
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut('A', 'Add')
        $this.Footer.AddShortcut('E', 'Edit')
        $this.Footer.AddShortcut('D', 'Delete')
        $this.Footer.AddShortcut('I', 'Import')
        $this.Footer.AddShortcut('O', 'Open External')
        $this.Footer.AddShortcut('Esc', 'Back')
    }

    # Handle "Enter" key
    [void] OnItemActivated($item) {
        $this.OnEdit()
    }

    # === TUI Editor Logic ===

    hidden [void] _OpenEditor($filePath) {
        $this._editingFilePath = $filePath
        $this._editingFileName = Split-Path $filePath -Leaf
        
        $content = ""
        if (Test-Path $filePath) {
            $content = Get-Content -Path $filePath -Raw -Encoding utf8
        }

        if (-not $this._textEditor) {
            $this._textEditor = [TextAreaEditor]::new()
        }

        $this._textEditor.SetText($content)
        $this._textEditor.SetTitle("Editing: $($this._editingFileName)")
        $this._textEditor.SetSize($this.TermWidth, $this.TermHeight - 4) # Leave room for header/footer
        $this._textEditor.SetPosition(0, 3) # Below header
        
        $this._showTextEditor = $true
        $this._activeModal = $this._textEditor  # Phase B: Set active modal
        $this.NeedsClear = $true
    }

    hidden [void] _SaveAndCloseEditor() {
        try {
            $content = $this._textEditor.GetText()
            Set-Content -Path $this._editingFilePath -Value $content -Encoding utf8 -NoNewline
            
            # Refresh service
            $this._checklistService.ReloadTemplates()
            
            $this.SetStatusMessage("Saved '$($this._editingFileName)'", "success")
        } catch {
            $this.SetStatusMessage("Error saving: $($_.Exception.Message)", "error")
        }

        $this._showTextEditor = $false
        $this._activeModal = $null  # Phase B: Clear active modal
        $this._editingFilePath = ""
        $this._editingFileName = ""
        $this.NeedsClear = $true
        $this.LoadData()
    }

    hidden [void] _CancelEditor() {
        $this._showTextEditor = $false
        $this._activeModal = $null  # Phase B: Clear active modal
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
            $self._activeModal = $null  # Phase B: Clear active modal
            $self._projectPicker = $null
            $self.NeedsClear = $true
        }.GetNewClosure()

        $this._projectPicker.OnCancelled = {
            $self._showProjectPicker = $false
            $self._activeModal = $null  # Phase B: Clear active modal
            $self._projectPicker = $null
            $self.NeedsClear = $true
        }.GetNewClosure()
        
        $this._showProjectPicker = $true
        $this._activeModal = $this._projectPicker  # Phase B: Set active modal
        $this.NeedsClear = $true
    }
    
    hidden [void] _DoImport($template, $projectName) {
        try {
            # Use service to create instance from template ID (which is the name)
            $name = Get-SafeProperty $template 'name'
            $this._checklistService.CreateInstanceFromTemplate($name, "project", $projectName)
            $this.SetStatusMessage("Imported '$name' to project '$projectName'", "success")
        }
        catch {
            $this.SetStatusMessage("Import failed: $($_.Exception.Message)", "error")
        }
    }

    # === External Editor ===
    
    hidden [void] _OpenInExternalEditor($filePath) {
        if ($global:IsWindows) {
            Start-Process "notepad.exe" -ArgumentList $filePath
        } else {
            if (Get-Command "xdg-open" -ErrorAction SilentlyContinue) {
                Start-Process "xdg-open" -ArgumentList $filePath
            } elseif (Get-Command "nano" -ErrorAction SilentlyContinue) {
                # This blocks the UI, which is tricky. For now, just try to open
                Start-Process "nano" -ArgumentList $filePath -Wait
            } else {
                $this.SetStatusMessage("No external editor found", "error")
            }
        }
        
        # Reload after external edit
        $this._checklistService.ReloadTemplates()
        $this.LoadData()
    }

    # === Rendering & Input ===

    [void] RenderToEngine([object]$engine) {
        # If editor is showing, ONLY render chrome + editor
        if ($this._showTextEditor) {
            # Render base chrome (Header/Footer) but NOT the list
            ([PmcScreen]$this).RenderToEngine($engine)
            
            # Reset to content layer to avoid overwriting menu dropdown
            $engine.BeginLayer([ZIndex]::Content)
            
            # Clear content area
            $bg = $this.Theme.GetColor('Background.Row') # Use Row bg as it's usually neutral
            $engine.Fill(0, 3, $this.TermWidth, $this.TermHeight - 4, ' ', $this.Theme.GetColor('Text.Primary'), $bg)
            
            # Render Editor
            $this._textEditor.RenderToEngine($engine)
            return
        }
        
        # If project picker is showing
        if ($this._showProjectPicker) {
            # Render underlying list first
            ([StandardListScreen]$this).RenderToEngine($engine)
            # Then picker
            $this._projectPicker.RenderToEngine($engine)
            return
        }

        # Normal render
        ([StandardListScreen]$this).RenderToEngine($engine)
    }

    [void] HandleKeyPress([ConsoleKeyInfo]$key) {
        # Phase B: Use HandleModalInput for all modals
        if ($this.HandleModalInput($key)) {
            return
        }
        
        # Special handling for Editor shortcuts that the widget didn't handle
        if ($this._activeModal -eq $this._textEditor) {
            # Check for Ctrl+S (Save)
            if ($key.Key -eq 'S' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                $this._SaveAndCloseEditor()
                return
            }
            # Check for Esc (Cancel) - if widget didn't handle it (e.g. no selection)
            if ($key.Key -eq 'Escape') {
                $this._CancelEditor()
                return
            }
            
            # CRITICAL: Consume all other input while editor is active to prevent list navigation
            return
        }
        
        # If no modal is active, let base class handle standard list input
        ([StandardListScreen]$this).HandleKeyPress($key)
    }
}