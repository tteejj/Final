using namespace System.Collections.Generic
using namespace System.Text

# ChecklistTemplatesScreen - Manage checklist templates
# Templates are reusable checklist definitions

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ChecklistService.ps1"

<#
.SYNOPSIS
Checklist template management screen

.DESCRIPTION
Manage reusable checklist templates:
- Add/Edit/Delete templates
- View template items
- Create instances from templates
- Category organization
#>
class ChecklistTemplatesScreen : StandardListScreen {
    hidden [ChecklistService]$_checklistService = $null

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Tools', 'Checklist Templates', 'H', {
            . "$PSScriptRoot/ChecklistTemplatesScreen.ps1"
            $global:PmcApp.PushScreen((New-Object -TypeName ChecklistTemplatesScreen))
        }, 30)
    }

    # Legacy constructor (backward compatible)
    ChecklistTemplatesScreen() : base("ChecklistTemplates", "Checklist Templates") {
        $this._InitializeScreen()
    }

    # Container constructor
    ChecklistTemplatesScreen([object]$container) : base("ChecklistTemplates", "Checklist Templates", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        # Initialize service
        $this._checklistService = [ChecklistService]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tools", "Checklist Templates"))

        # Setup event handlers
        $self = $this
        $this._checklistService.OnChecklistsChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    # === Abstract Method Implementations ===

    [string] GetEntityType() {
        return 'checklist_template'
    }

    [array] GetColumns() {
        return @(
            @{ Name='name'; Label='Template Name'; Width=30 }
            @{ Name='category'; Label='Category'; Width=20 }
            @{ Name='item_count'; Label='Items'; Width=8 }
            @{ Name='description'; Label='Description'; Width=50 }
        )
    }

    [void] LoadData() {
        $items = $this.LoadItems()
        $this.List.SetData($items)
    }

    [array] LoadItems() {
        $templates = @($this._checklistService.GetAllTemplates())

        # Format for display
        foreach ($template in $templates) {
            if ($template.ContainsKey('items')) {
                $template['item_count'] = $template.items.Count
            } else {
                $template['item_count'] = 0
            }
        }

        return $templates
    }

    [array] GetEditFields([object]$item) {
        if ($null -eq $item -or $item.Count -eq 0) {
            # New template - empty fields
            return @(
                @{ Name='name'; Type='text'; Label='Template Name'; Required=$true; Value='' }
                @{ Name='category'; Type='text'; Label='Category'; Value='General' }
                @{ Name='description'; Type='text'; Label='Description'; Value='' }
                @{ Name='items'; Type='textarea'; Label='Items (pipe-separated)'; Value=''; MaxLength=5000 }
            )
        } else {
            # Existing template - populate from item
            $itemsText = ''
            if ($item.ContainsKey('items') -and $item.items) {
                $itemTexts = @($item.items | ForEach-Object { $_.text })
                $itemsText = $itemTexts -join " | "
            }

            return @(
                @{ Name='name'; Type='text'; Label='Template Name'; Required=$true; Value=$item.name }
                @{ Name='category'; Type='text'; Label='Category'; Value=$item.category }
                @{ Name='description'; Type='text'; Label='Description'; Value=$item.description }
                @{ Name='items'; Type='textarea'; Label='Items (pipe-separated)'; Value=$itemsText; MaxLength=5000 }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        try {
            # SAVE FIX: Validate and safe access
            if (-not $values.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($values.name)) {
                $this.SetStatusMessage("Template name is required", "error")
                return
            }

            # Parse items (newline-separated)
            $itemTexts = @()
            if ($values.ContainsKey('items') -and -not [string]::IsNullOrWhiteSpace($values.items)) {
                $itemTexts = @($values.items -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }

            if ($itemTexts.Count -eq 0) {
                $this.SetStatusMessage("Template must have at least one item", "error")
                return
            }

            $name = $values.name
            $description = $(if ($values.ContainsKey('description')) { $values.description } else { '' })
            $category = $(if ($values.ContainsKey('category')) { $values.category } else { '' })

            $this._checklistService.CreateTemplate($name, $description, $category, $itemTexts)

            $this.SetStatusMessage("Template '$name' created", "success")
        } catch {
            $this.SetStatusMessage("Error creating template: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })

            # Parse items (newline-separated)
            $itemTexts = @()
            if ($values.ContainsKey('items') -and -not [string]::IsNullOrWhiteSpace($values.items)) {
                $itemTexts = @($values.items -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }

            if ($itemTexts.Count -eq 0) {
                $this.SetStatusMessage("Template must have at least one item", "error")
                return
            }

            # Convert to item objects
            $items = @()
            $order = 1
            foreach ($text in $itemTexts) {
                $items += @{
                    text = $text
                    order = $order++
                }
            }

            # ENDEMIC FIX: Safe value access
            $changes = @{
                name = $(if ($values.ContainsKey('name')) { $values.name } else { '' })
                category = $(if ($values.ContainsKey('category')) { $values.category } else { '' })
                description = $(if ($values.ContainsKey('description')) { $values.description } else { '' })
                items = $items
            }

            if ([string]::IsNullOrWhiteSpace($changes.name)) {
                $this.SetStatusMessage("Template name is required", "error")
                return
            }

            $this._checklistService.UpdateTemplate($itemId, $changes)
            $this.SetStatusMessage("Template '$($changes.name)' updated", "success")
        } catch {
            $this.SetStatusMessage("Error updating template: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
            $itemName = $(if ($item -is [hashtable]) { $item['name'] } else { $item.name })

            if ($itemId) {
                $this._checklistService.DeleteTemplate($itemId)
                $this.SetStatusMessage("Template '$itemName' deleted", "success")
            } else {
                $this.SetStatusMessage("Cannot delete template without ID", "error")
            }
        } catch {
            $this.SetStatusMessage("Error deleting template: $($_.Exception.Message)", "error")
        }
    }
}