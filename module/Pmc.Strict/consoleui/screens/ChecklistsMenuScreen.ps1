using namespace System.Collections.Generic
using namespace System.Text

# ChecklistsMenuScreen - List checklists for a project/task
# Shows checklist instances owned by a specific entity

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ChecklistService.ps1"

<#
.SYNOPSIS
Checklists menu screen for viewing checklists attached to project/task

.DESCRIPTION
Shows all checklist instances for a given owner:
- View checklist progress
- Open checklist editor
- Add from template
- Create blank checklist
- Delete checklist
#>
class ChecklistsMenuScreen : StandardListScreen {
    hidden [ChecklistService]$_checklistService = $null
    hidden [string]$_ownerType = ""
    hidden [string]$_ownerId = ""
    hidden [string]$_ownerName = ""

    # Constructor
    ChecklistsMenuScreen([string]$ownerType, [string]$ownerId, [string]$ownerName) : base("ChecklistsMenu", "Checklists") {
        $this._ownerType = $ownerType
        $this._ownerId = $ownerId
        $this._ownerName = $ownerName
        $this._checklistService = [ChecklistService]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $false  # Use Enter to open editor instead
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        # Configure header
        $ownerLabel = $(if ($ownerType -eq "project") { "Project" } elseif ($ownerType -eq "task") { "Task" } else { "Global" })
        $this.Header.SetBreadcrumb(@($ownerLabel, $ownerName, "Checklists"))

        # Update screen title
        $this.ScreenTitle = "Checklists - $ownerName"

        # Setup event handlers
        $self = $this
        $this._checklistService.OnChecklistsChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    ChecklistsMenuScreen([string]$ownerType, [string]$ownerId, [string]$ownerName, [object]$container) : base("ChecklistsMenu", "Checklists", $container) {
        $this._ownerType = $ownerType
        $this._ownerId = $ownerId
        $this._ownerName = $ownerName
        $this._checklistService = [ChecklistService]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $false  # Use Enter to open editor instead
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        # Configure header
        $ownerLabel = $(if ($ownerType -eq "project") { "Project" } elseif ($ownerType -eq "task") { "Task" } else { "Global" })
        $this.Header.SetBreadcrumb(@($ownerLabel, $ownerName, "Checklists"))

        # Update screen title
        $this.ScreenTitle = "Checklists - $ownerName"

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
        return 'checklist'
    }

    [array] GetColumns() {
        return @(
            @{ Name='title'; Label='Checklist'; Width=40 }
            @{ Name='progress_display'; Label='Progress'; Width=20 }
            @{ Name='percent_complete'; Label='%'; Width=5 }
            @{ Name='modified_display'; Label='Modified'; Width=12 }
        )
    }

    [void] LoadData() {
        $items = $this.LoadItems()
        $this.List.SetData($items)
    }

    [array] LoadItems() {
        Write-PmcTuiLog "ChecklistsMenuScreen.LoadItems: Loading checklists for owner type=$($this._ownerType) id=$($this._ownerId)" "INFO"
        $checklists = @($this._checklistService.GetInstancesByOwner($this._ownerType, $this._ownerId))
        Write-PmcTuiLog "ChecklistsMenuScreen.LoadItems: Loaded $($checklists.Count) checklists" "INFO"

        # Format for display
        foreach ($checklist in $checklists) {
            # Progress display
            $checklist['progress_display'] = "[$($checklist.completed_count)/$($checklist.total_count)]"

            # Modified date
            if ($checklist.ContainsKey('modified') -and $checklist.modified -is [DateTime]) {
                $checklist['modified_display'] = $checklist.modified.ToString('yyyy-MM-dd')
            } else {
                $checklist['modified_display'] = ''
            }
        }

        return $checklists
    }

    [array] GetEditFields([object]$item) {
        # For adding new checklist
        return @(
            @{ Name='title'; Type='text'; Label='Checklist Title'; Required=$true; Value='' }
            @{ Name='template_id'; Type='text'; Label='Template ID (leave blank for blank checklist)'; Value='' }
            @{ Name='items'; Type='text'; Label='Items (comma-separated, if blank checklist)'; Value=''; MaxLength=1000 }
        )
    }

    [void] OnItemCreated([hashtable]$values) {
        try {
            # SAVE FIX: Safe property access
            if ($values.ContainsKey('template_id') -and -not [string]::IsNullOrWhiteSpace($values.template_id)) {
                # Create from template
                $instance = $this._checklistService.CreateInstanceFromTemplate(
                    $values.template_id,
                    $this._ownerType,
                    $this._ownerId
                )
                $instanceTitle = $(if ($instance -and $instance.PSObject.Properties['title']) { $instance.title } else { 'Checklist' })
                $this.SetStatusMessage("Checklist '$instanceTitle' created from template", "success")
            } else {
                # Create blank checklist - validate title
                if (-not $values.ContainsKey('title') -or [string]::IsNullOrWhiteSpace($values.title)) {
                    $this.SetStatusMessage("Checklist title is required", "error")
                    return
                }

                $itemTexts = @()
                if ($values.ContainsKey('items') -and -not [string]::IsNullOrWhiteSpace($values.items)) {
                    $itemTexts = @($values.items -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                }

                if ($itemTexts.Count -eq 0) {
                    $this.SetStatusMessage("Blank checklist must have at least one item", "error")
                    return
                }

                $instance = $this._checklistService.CreateBlankInstance(
                    $values.title,
                    $this._ownerType,
                    $this._ownerId,
                    $itemTexts
                )
                $instanceTitle = $(if ($instance -and $instance.PSObject.Properties['title']) { $instance.title } else { 'Checklist' })
                $this.SetStatusMessage("Checklist '$instanceTitle' created", "success")
            }
        } catch {
            $this.SetStatusMessage("Error creating checklist: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        # Not used - we open editor instead
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
            $itemTitle = $(if ($item -is [hashtable]) { $item['title'] } else { $item.title })

            if ($itemId) {
                $this._checklistService.DeleteInstance($itemId)
                $this.SetStatusMessage("Checklist '$itemTitle' deleted", "success")
            } else {
                $this.SetStatusMessage("Cannot delete checklist without ID", "error")
            }
        } catch {
            $this.SetStatusMessage("Error deleting checklist: $($_.Exception.Message)", "error")
        }
    }

    # Override OnItemActivated to open editor
    [void] OnItemActivated([object]$item) {
        if ($null -eq $item) {
            return
        }

        $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
        if ($itemId) {
            . "$PSScriptRoot/ChecklistEditorScreen.ps1"
            $editorScreen = New-Object ChecklistEditorScreen -ArgumentList $itemId
            $global:PmcApp.PushScreen($editorScreen)
        }
    }

    # Custom action: Show template picker
    [void] ShowTemplatePicker() {
        . "$PSScriptRoot/ChecklistTemplatesFolderScreen.ps1"
        $templateScreen = New-Object ChecklistTemplatesFolderScreen
        $global:PmcApp.PushScreen($templateScreen)
    }

    [array] GetCustomActions() {
        return @(
            @{
                Label = "Templates (T)"
                Key = 't'
                Callback = {
                    $this.ShowTemplatePicker()
                }.GetNewClosure()
            }
        )
    }
}