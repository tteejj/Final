# ChecklistTemplatePickerScreen.ps1 - Simple picker to select a checklist template to create instance for project/task

using namespace System.Collections.Generic

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"

class ChecklistTemplatePickerScreen : StandardListScreen {
    hidden [array]$_templates = @()
    hidden [string]$_targetName = ""
    [scriptblock]$OnTemplateSelected = $null

    # Constructor
    ChecklistTemplatePickerScreen([array]$templates, [string]$targetName) : base("ChecklistTemplatePicker", "Select Checklist Template") {
        $this._templates = $templates
        $this._targetName = $targetName

        # Configure capabilities
        $this.AllowAdd = $false
        $this.AllowEdit = $false
        $this.AllowDelete = $false
        $this.AllowFilter = $false
        $this.AllowSearch = $true

        # Update header
        $this.Header.SetBreadcrumb(@("Projects", $targetName, "Create Checklist"))
        $this.ScreenTitle = "Select Template - $targetName"
    }

    [void] LoadData() {
        $this.List.SetData($this._templates)
    }

    [array] GetColumns() {
        return @(
            @{Name='name'; Label='Template'; Width=40; Sortable=$true; Searchable=$true}
            @{Name='description'; Label='Description'; Width=50; Sortable=$true}
            @{Name='category'; Label='Category'; Width=15}
        )
    }

    [array] GetEditFields([object]$item) {
        return @()
    }

    [void] OnItemActivated([object]$item) {
        # Get template ID
        $templateId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })

        if ($null -ne $templateId -and $null -ne $this.OnTemplateSelected) {
            # Invoke callback
            & $this.OnTemplateSelected $templateId

            # Pop this screen
            $global:PmcApp.PopScreen()
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        # Not used
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        # Not used
    }

    [void] OnItemDeleted([object]$item) {
        # Not used
    }
}