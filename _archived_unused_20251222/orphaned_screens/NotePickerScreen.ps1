# NotePickerScreen.ps1 - Simple picker to select a note to assign to project/task

using namespace System.Collections.Generic

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"

class NotePickerScreen : StandardListScreen {
    hidden [array]$_notes = @()
    hidden [string]$_targetName = ""
    [scriptblock]$OnNoteSelected = $null

    # Constructor
    NotePickerScreen([array]$notes, [string]$targetName) : base("NotePicker", "Select Note to Assign") {
        $this._notes = $notes
        $this._targetName = $targetName

        # Configure capabilities
        $this.AllowAdd = $false
        $this.AllowEdit = $false
        $this.AllowDelete = $false
        $this.AllowFilter = $false
        $this.AllowSearch = $true

        # Update header
        $this.Header.SetBreadcrumb(@("Projects", $targetName, "Assign Note"))
        $this.ScreenTitle = "Select Note - $targetName"
    }

    [void] LoadData() {
        $this.List.SetData($this._notes)
    }

    [array] GetColumns() {
        return @(
            @{Name='title'; Label='Note'; Width=50; Sortable=$true; Searchable=$true}
            @{Name='modified'; Label='Modified'; Width=20; Sortable=$true; Formatter={
                param($value)
                if ($value -is [datetime]) {
                    return $value.ToString("yyyy-MM-dd HH:mm")
                }
                return ""
            }}
            @{Name='owner_type'; Label='Owner'; Width=15}
        )
    }

    [array] GetEditFields([object]$item) {
        return @()
    }

    [void] OnItemActivated([object]$item) {
        # Get note ID
        $noteId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })

        if ($null -ne $noteId -and $null -ne $this.OnNoteSelected) {
            # Invoke callback
            & $this.OnNoteSelected $noteId

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