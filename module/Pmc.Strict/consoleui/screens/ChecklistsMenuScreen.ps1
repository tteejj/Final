using namespace System.Collections.Generic
using namespace System.Text

# ChecklistsMenuScreen - View and manage checklists for a project
# Shows all checklist instances, allows creating new ones

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ChecklistService.ps1"

<#
.SYNOPSIS
List and manage checklists for a project or globally

.DESCRIPTION
Shows checklist instances with title, progress, item count.
- Enter: Open checklist to view/edit items
- N: Create new blank checklist
- D: Delete checklist
#>
class ChecklistsMenuScreen : StandardListScreen {
    hidden [ChecklistService]$_checklistService = $null
    hidden [string]$_ownerType = "project"
    hidden [string]$_ownerId = ""
    hidden [string]$_ownerName = ""

    # Constructors
    ChecklistsMenuScreen([string]$ownerType, [string]$ownerId, [string]$ownerName) : base("ChecklistsMenu", "Checklists: $ownerName") {
        $this._ownerType = $ownerType
        $this._ownerId = $ownerId
        $this._ownerName = $ownerName
        $this._InitializeScreen()
    }

    ChecklistsMenuScreen([string]$ownerType, [string]$ownerId, [string]$ownerName, [object]$container) : base("ChecklistsMenu", "Checklists: $ownerName", $container) {
        $this._ownerType = $ownerType
        $this._ownerId = $ownerId
        $this._ownerName = $ownerName
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        $this._checklistService = [ChecklistService]::GetInstance()

        $this.AllowAdd = $true
        $this.AllowEdit = $false
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        $this.Header.SetBreadcrumb(@("Home", "Checklists", $this._ownerName))
    }

    # === Abstract Method Implementations ===

    [string] GetEntityType() { return 'checklist' }

    [array] GetColumns() {
        return @(
            @{ Name='title'; Label='Checklist'; Width=35; Sortable=$true }
            @{ Name='progress'; Label='Progress'; Width=12; Sortable=$true; Align='right' }
            @{ Name='items_display'; Label='Items'; Width=10; Sortable=$true; Align='right' }
            @{ Name='modified_display'; Label='Modified'; Width=18; Sortable=$true }
        )
    }

    [void] LoadData() {
        $instances = @($this._checklistService.GetInstancesByOwner($this._ownerType, $this._ownerId))

        $items = @()
        foreach ($inst in $instances) {
            $items += @{
                id = $inst.id
                title = $inst.title
                progress = "$($inst.percent_complete)%"
                items_display = "$($inst.completed_count)/$($inst.total_count)"
                modified_display = $inst.modified.ToString("yyyy-MM-dd HH:mm")
                _instance = $inst
            }
        }

        $this.List.SetData($items)

        if ($this.StatusBar) {
            $this.StatusBar.SetLeftText("$($items.Count) checklist(s)")
        }
    }

    [array] GetEditFields([object]$item) {
        # For creating new checklist
        return @(
            @{ Name='title'; Type='text'; Label='Checklist Title'; Required=$true; Value='' }
        )
    }

    [void] OnItemCreated([hashtable]$values) {
        try {
            if (-not $values.ContainsKey('title') -or [string]::IsNullOrWhiteSpace($values.title)) {
                $this.SetStatusMessage("Title is required", "error")
                return
            }

            $this._checklistService.CreateBlankInstance($values.title, $this._ownerType, $this._ownerId, @())
            $this.SetStatusMessage("Checklist '$($values.title)' created", "success")
            $this.LoadData()
            
            # Invalidate cache and request render
            if ($this.List) {
                $this.List.InvalidateCache()
            }
            if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                $global:PmcApp.RequestRender()
            }
        } catch {
            $this.SetStatusMessage("Error: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $id = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
            $title = $(if ($item -is [hashtable]) { $item['title'] } else { $item.title })

            $this._checklistService.DeleteInstance($id)
            $this.SetStatusMessage("Checklist '$title' deleted", "success")
            $this.LoadData()
            
            # Invalidate cache and request render
            if ($this.List) {
                $this.List.InvalidateCache()
            }
            if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                $global:PmcApp.RequestRender()
            }
        } catch {
            $this.SetStatusMessage("Error: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemActivated($item) {
        $id = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
        $title = $(if ($item -is [hashtable]) { $item['title'] } else { $item.title })

        # Open ChecklistViewScreen
        . "$PSScriptRoot/ChecklistViewScreen.ps1"
        $viewScreen = New-Object ChecklistViewScreen -ArgumentList $id, $title
        $global:PmcApp.PushScreen($viewScreen)
    }

    [array] GetCustomActions() {
        $self = $this
        return @(
            @{
                Key = 'O'
                Label = 'Open'
                Callback = {
                    $selected = $self.List.GetSelectedItem()
                    if ($selected) {
                        $self.OnItemActivated($selected)
                    }
                }.GetNewClosure()
            }
        )
    }
}
