using namespace System.Collections.Generic
using namespace System.Text

# TextExportMappingEditorScreen - Edit cell->label mappings for export profile
# Maps Excel cells to text output lines

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/TextExportService.ps1"

class TextExportMappingEditorScreen : StandardListScreen {
    hidden [TextExportService]$_exportService = $null
    hidden [string]$_profileId = ""
    hidden [string]$_profileName = ""

    TextExportMappingEditorScreen([string]$profileId, [string]$profileName) : base("TextExportMappings", "Export Mappings: $profileName") {
        $this._profileId = $profileId
        $this._profileName = $profileName
        $this._exportService = [TextExportService]::GetInstance()

        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        $this.Header.SetBreadcrumb(@("Home", "Tools", "T2020 Export", $profileName))
    }

    [string] GetEntityType() {
        return 'text_export_mapping'
    }

    [array] GetColumns() {
        return @(
            @{ Name='label'; Label='Label'; Width=25 }
            @{ Name='source_sheet'; Label='Sheet'; Width=15 }
            @{ Name='source_cell'; Label='Cell'; Width=10 }
            @{ Name='line_number'; Label='Line #'; Width=8 }
        )
    }

    [void] LoadData() {
        $mappings = $this._exportService.GetMappings($this._profileId)
        $this.List.SetData($mappings)
    }

    [array] GetEditFields([object]$item) {
        if ($null -eq $item -or $item.Count -eq 0) {
            return @(
                @{ Name='label'; Type='text'; Label='Label (shown in output)'; Required=$true; Value='' }
                @{ Name='source_sheet'; Type='text'; Label='Source Sheet Name'; Required=$true; Value='Sheet1' }
                @{ Name='source_cell'; Type='text'; Label='Source Cell (e.g. A1)'; Required=$true; Value='' }
                @{ Name='line_number'; Type='text'; Label='Line Number'; Required=$true; Value='1' }
            )
        } else {
            return @(
                @{ Name='label'; Type='text'; Label='Label'; Required=$true; Value=$item.label }
                @{ Name='source_sheet'; Type='text'; Label='Source Sheet Name'; Required=$true; Value=$item.source_sheet }
                @{ Name='source_cell'; Type='text'; Label='Source Cell'; Required=$true; Value=$item.source_cell }
                @{ Name='line_number'; Type='text'; Label='Line Number'; Required=$true; Value=[string]$item.line_number }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        if ([string]::IsNullOrWhiteSpace($values.label)) {
            $this.SetStatusMessage("Label required", "error")
            return
        }

        try {
            $values.line_number = [int]$values.line_number
        } catch {
            $values.line_number = 1
        }

        try {
            $this._exportService.AddMapping($this._profileId, $values)
            $this.SetStatusMessage("Mapping added", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            $values.line_number = [int]$values.line_number
        } catch {
            $values.line_number = $item.line_number
        }

        try {
            $this._exportService.UpdateMapping($this._profileId, $item.id, $values)
            $this.SetStatusMessage("Mapping updated", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $this._exportService.DeleteMapping($this._profileId, $item.id)
            $this.SetStatusMessage("Mapping deleted", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }
}
