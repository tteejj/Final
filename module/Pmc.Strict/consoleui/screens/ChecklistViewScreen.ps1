using namespace System.Collections.Generic
using namespace System.Text

# ChecklistViewScreen - View and edit checklist items
# Shows items with checkboxes, toggle completion, add/edit/delete items

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ChecklistService.ps1"

<#
.SYNOPSIS
View and edit a single checklist's items

.DESCRIPTION
Shows checklist items with completion status.
- Space/Enter: Toggle item completion
- A: Add new item
- E: Edit item text
- D: Delete item
#>
class ChecklistViewScreen : StandardListScreen {
    hidden [ChecklistService]$_checklistService = $null
    hidden [string]$_instanceId = ""
    hidden [object]$_instance = $null

    # Constructors
    ChecklistViewScreen([string]$instanceId, [string]$title) : base("ChecklistView", "Checklist: $title") {
        $this._instanceId = $instanceId
        $this._InitializeScreen()
    }

    ChecklistViewScreen([string]$instanceId, [string]$title, [object]$container) : base("ChecklistView", "Checklist: $title", $container) {
        $this._instanceId = $instanceId
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        $this._checklistService = [ChecklistService]::GetInstance()
        $this._instance = $this._checklistService.GetInstance($this._instanceId)

        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false
        $this.AllowMultiSelect = $false  # Disable multi-select - Space key is used for toggle

        if ($this._instance) {
            $this.Header.SetBreadcrumb(@("Home", "Checklists", $this._instance.title))
        }
    }

    # === Abstract Method Implementations ===

    [string] GetEntityType() { return 'checklist_item' }

    [array] GetColumns() {
        return @(
            @{ Name='checkbox'; Label=' '; Width=3; Sortable=$false }
            @{ Name='text'; Label='Item'; Width=60; Sortable=$false }
        )
    }

    [void] LoadData() {
        $this._instance = $this._checklistService.GetInstance($this._instanceId)

        if (-not $this._instance) {
            $this.List.SetData(@())
            $this.SetStatusMessage("Checklist not found", "error")
            return
        }

        $items = @()
        $index = 0
        foreach ($item in $this._instance.items) {
            $checkbox = $(if ($item.completed) { "[x]" } else { "[ ]" })
            $items += @{
                _index = $index
                checkbox = $checkbox
                text = $item.text
                completed = $item.completed
                _item = $item
            }
            $index++
        }

        $this.List.SetData($items)

        # Update status with progress
        if ($this.StatusBar) {
            $pct = $this._instance.percent_complete
            $done = $this._instance.completed_count
            $total = $this._instance.total_count
            $this.StatusBar.SetLeftText("Progress: $done/$total ($pct%)")
        }
    }

    [array] GetEditFields([object]$item) {
        if ($null -eq $item -or $item.Count -eq 0) {
            # New item
            return @(
                @{ Name='text'; Type='text'; Label='Item Text'; Required=$true; Value='' }
            )
        } else {
            # Edit existing
            $text = $(if ($item -is [hashtable]) { $item['text'] } else { $item.text })
            return @(
                @{ Name='text'; Type='text'; Label='Item Text'; Required=$true; Value=$text }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        try {
            if (-not $values.ContainsKey('text') -or [string]::IsNullOrWhiteSpace($values.text)) {
                $this.SetStatusMessage("Item text is required", "error")
                return
            }

            # Add item to instance
            $newItem = @{
                text = $values.text
                completed = $false
                completed_date = $null
                order = $this._instance.items.Count + 1
            }
            $this._instance.items += $newItem

            # Update via service
            $this._checklistService.UpdateInstance($this._instanceId, @{ items = $this._instance.items })

            $this.SetStatusMessage("Item added", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            $index = $(if ($item -is [hashtable]) { $item['_index'] } else { $item._index })

            if (-not $values.ContainsKey('text') -or [string]::IsNullOrWhiteSpace($values.text)) {
                $this.SetStatusMessage("Item text is required", "error")
                return
            }

            # Update item text
            $this._instance.items[$index].text = $values.text

            # Save via service
            $this._checklistService.UpdateInstance($this._instanceId, @{ items = $this._instance.items })

            $this.SetStatusMessage("Item updated", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $index = $(if ($item -is [hashtable]) { $item['_index'] } else { $item._index })
            $text = $(if ($item -is [hashtable]) { $item['text'] } else { $item.text })

            # Remove item from array
            $newItems = @()
            for ($i = 0; $i -lt $this._instance.items.Count; $i++) {
                if ($i -ne $index) {
                    $newItems += $this._instance.items[$i]
                }
            }
            $this._instance.items = $newItems

            # Renumber orders
            for ($i = 0; $i -lt $this._instance.items.Count; $i++) {
                $this._instance.items[$i].order = $i + 1
            }

            # Save via service
            $this._checklistService.UpdateInstance($this._instanceId, @{ items = $this._instance.items })

            $this.SetStatusMessage("Item deleted", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemActivated($item) {
        # Toggle completion on Enter/Space
        $this._ToggleItem($item)
    }

    hidden [void] _ToggleItem($item) {
        try {
            $index = $(if ($item -is [hashtable]) { $item['_index'] } else { $item._index })

            $this._checklistService.ToggleItem($this._instanceId, $index)

            # Refresh
            $this.LoadData()

            $completed = $this._instance.items[$index].completed
            $status = $(if ($completed) { "completed" } else { "uncompleted" })
            $this.SetStatusMessage("Item marked $status", "success")
        } catch {
            $this.SetStatusMessage("Error: $($_.Exception.Message)", "error")
        }
    }

    [array] GetCustomActions() {
        $self = $this
        return @(
            @{
                Key = ' '
                Label = 'Toggle'
                Callback = {
                    $selected = $self.List.GetSelectedItem()
                    if ($selected) {
                        $self._ToggleItem($selected)
                    }
                }.GetNewClosure()
            }
        )
    }

    # Override key handling for Space toggle
    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        if ($keyInfo.Key -eq [ConsoleKey]::Spacebar) {
            $selected = $this.List.GetSelectedItem()
            if ($selected) {
                $this._ToggleItem($selected)
                return $true
            }
        }

        return ([StandardListScreen]$this).HandleKeyPress($keyInfo)
    }
}
