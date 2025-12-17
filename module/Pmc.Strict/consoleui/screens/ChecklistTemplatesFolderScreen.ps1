using namespace System.Collections.Generic
using namespace System.Text

# ChecklistTemplatesFolderScreen - Manage folder-based checklist templates
# Templates are simple .txt files in checklist_templates/ folder
# Each line in file = checkbox item when imported

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ChecklistService.ps1"

<#
.SYNOPSIS
Folder-based checklist template management

.DESCRIPTION
Simple template system:
- Templates are .txt files in checklist_templates/ folder
- Each line in file becomes a checklist item
- Create new template = create new .txt file
- Edit template = open in default text editor
- Import template into project/task
#>
class ChecklistTemplatesFolderScreen : StandardListScreen {
    hidden [ChecklistService]$_checklistService = $null
    hidden [string]$_templatesFolder = ""

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Tools', 'Checklist Templates', 'H', {
            . "$PSScriptRoot/ChecklistTemplatesFolderScreen.ps1"
            $global:PmcApp.PushScreen((New-Object -TypeName ChecklistTemplatesFolderScreen))
        }, 30)
    }

    # Legacy constructor
    ChecklistTemplatesFolderScreen() : base("ChecklistTemplates", "Checklist Templates") {
        $this._InitializeScreen()
    }

    # Container constructor
    ChecklistTemplatesFolderScreen([object]$container) : base("ChecklistTemplates", "Checklist Templates", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        # Initialize service
        $this._checklistService = [ChecklistService]::GetInstance()

        # Determine templates folder (at PMC root)
        $pmcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $this._templatesFolder = Join-Path $pmcRoot "checklist_templates"

        # Ensure folder exists
        if (-not (Test-Path $this._templatesFolder)) {
            New-Item -ItemType Directory -Path $this._templatesFolder -Force | Out-Null
        }

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tools", "Checklist Templates"))
    }

    # === Abstract Method Implementations ===

    [string] GetEntityType() {
        return 'checklist_template_file'
    }

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

        # Get all .txt files in templates folder
        $files = Get-ChildItem -Path $this._templatesFolder -Filter "*.txt" -File -ErrorAction SilentlyContinue

        foreach ($file in $files) {
            # Count lines in file
            $lineCount = 0
            try {
                $content = Get-Content -Path $file.FullName -ErrorAction Stop
                $lineCount = @($content | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
            } catch {
                $lineCount = 0
            }

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
            # New template
            return @(
                @{ Name='name'; Type='text'; Label='Template Name'; Required=$true; Value='' }
            )
        } else {
            # Existing template - just name for rename
            return @(
                @{ Name='name'; Type='text'; Label='Template Name'; Required=$true; Value=$item.name }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        try {
            # Validate name
            if (-not $values.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($values.name)) {
                $this.SetStatusMessage("Template name is required", "error")
                return
            }

            $name = $values.name
            $fileName = "$name.txt"
            $filePath = Join-Path $this._templatesFolder $fileName

            # Check if file already exists
            if (Test-Path $filePath) {
                $this.SetStatusMessage("Template '$name' already exists", "error")
                return
            }

            # Create empty template file with instructions
            $content = "# Checklist template: $name`n# Each line will become a checklist item`n# Delete these comment lines and add your items below`n`n"
            Set-Content -Path $filePath -Value $content -Encoding utf8

            $this.SetStatusMessage("Template '$name' created. Press Enter to edit.", "success")

            # Reload list
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error creating template: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            # Rename template file
            $oldName = $(if ($item -is [hashtable]) { $item['name'] } else { $item.name })
            $oldPath = $(if ($item -is [hashtable]) { $item['file_path'] } else { $item.file_path })

            if (-not $values.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($values.name)) {
                $this.SetStatusMessage("Template name is required", "error")
                return
            }

            $newName = $values.name
            $newPath = Join-Path $this._templatesFolder "$newName.txt"

            if ($oldPath -eq $newPath) {
                $this.SetStatusMessage("Name unchanged", "info")
                return
            }

            if (Test-Path $newPath) {
                $this.SetStatusMessage("Template '$newName' already exists", "error")
                return
            }

            Move-Item -Path $oldPath -Destination $newPath -Force
            $this.SetStatusMessage("Template renamed to '$newName'", "success")

            # Reload list
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

                # Reload list
                $this.LoadData()
            } else {
                $this.SetStatusMessage("Template file not found", "error")
            }
        } catch {
            $this.SetStatusMessage("Error deleting template: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemActivated($item) {
        # Open template file in default text editor
        $filePath = $(if ($item -is [hashtable]) { $item['file_path'] } else { $item.file_path })

        try {
            if (Test-Path $filePath) {
                # Open in default text editor (notepad on Windows, nano/vim on Linux)
                if ($IsWindows -or $env:OS -match "Windows") {
                    Start-Process notepad.exe -ArgumentList $filePath
                } else {
                    # For Linux, we need to launch in background and not block TUI
                    $editor = $(if (Get-Command nano -ErrorAction SilentlyContinue) { "nano" }
                              elseif (Get-Command vim -ErrorAction SilentlyContinue) { "vim" }
                              else { "vi" })

                    # Can't easily launch terminal editor from TUI without blocking
                    # Instead, show file path and instructions
                    $this.SetStatusMessage("Edit: $filePath (use external editor)", "info")
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
                Label = 'Open/Edit'
                Callback = {
                    $selected = $self.List.GetSelectedItem()
                    if ($selected) {
                        $self.OnItemActivated($selected)
                    }
                }.GetNewClosure()
            }
        )
    }

    hidden [void] _ImportToProject($template) {
        # TODO: Show project picker, then import template as checklist instance
        # For now, just show message
        $name = $(if ($template -is [hashtable]) { $template['name'] } else { $template.name })
        $this.SetStatusMessage("Import '$name': Select project first (TODO: implement project picker)", "info")
    }
}