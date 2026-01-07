using namespace System.Collections.Generic
using namespace System.Text

# ExcelImportMappingEditorScreen - Edit cell->field mappings for import profile
# Maps Excel cells to Project Info field names

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ExcelImportService.ps1"

class ExcelImportMappingEditorScreen : StandardListScreen {
    hidden [ExcelImportService]$_importService = $null
    hidden [string]$_profileId = ""
    hidden [string]$_profileName = ""

    ExcelImportMappingEditorScreen([string]$profileId, [string]$profileName) : base("ExcelImportMappings", "Import Mappings: $profileName") {
        $this._profileId = $profileId
        $this._profileName = $profileName
        $this._importService = [ExcelImportService]::GetInstance()

        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        $this.Header.SetBreadcrumb(@("Home", "Tools", "Excel Import", $profileName))
    }

    [string] GetEntityType() {
        return 'excel_import_mapping'
    }

    [array] GetColumns() {
        return @(
            @{ Name='name'; Label='Name'; Width=20 }
            @{ Name='source_sheet'; Label='Sheet'; Width=15 }
            @{ Name='source_cell'; Label='Cell'; Width=10 }
            @{ Name='dest_field'; Label='Project Field'; Width=20 }
        )
    }

    [void] LoadData() {
        $mappings = $this._importService.GetMappings($this._profileId)
        $this.List.SetData($mappings)
    }

    [array] GetEditFields([object]$item) {
        if ($null -eq $item -or $item.Count -eq 0) {
            return @(
                @{ Name='name'; Type='text'; Label='Mapping Name'; Required=$true; Value='' }
                @{ Name='source_sheet'; Type='text'; Label='Source Sheet Name'; Required=$true; Value='Sheet1' }
                @{ Name='source_cell'; Type='text'; Label='Source Cell (e.g. A1)'; Required=$true; Value='' }
                @{ Name='dest_field'; Type='text'; Label='Dest Project Field'; Required=$true; Value='' }
            )
        } else {
            return @(
                @{ Name='name'; Type='text'; Label='Mapping Name'; Required=$true; Value=$item.name }
                @{ Name='source_sheet'; Type='text'; Label='Source Sheet Name'; Required=$true; Value=$item.source_sheet }
                @{ Name='source_cell'; Type='text'; Label='Source Cell'; Required=$true; Value=$item.source_cell }
                @{ Name='dest_field'; Type='text'; Label='Dest Project Field'; Required=$true; Value=$item.dest_field }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        if ([string]::IsNullOrWhiteSpace($values.name)) {
            $this.SetStatusMessage("Mapping name required", "error")
            return
        }

        try {
            $this._importService.AddMapping($this._profileId, $values)
            $this.SetStatusMessage("Mapping added", "success")
            $this.LoadData()
            
            # Invalidate cache and request render
            if ($this.List) {
                $this.List.InvalidateCache()
            }
            if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                $global:PmcApp.RequestRender()
            }
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            $this._importService.UpdateMapping($this._profileId, $item.id, $values)
            $this.SetStatusMessage("Mapping updated", "success")
            $this.LoadData()
            
            # Invalidate cache and request render
            if ($this.List) {
                $this.List.InvalidateCache()
            }
            if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                $global:PmcApp.RequestRender()
            }
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $this._importService.DeleteMapping($this._profileId, $item.id)
            $this.SetStatusMessage("Mapping deleted", "success")
            $this.LoadData()
            
            # Invalidate cache and request render
            if ($this.List) {
                $this.List.InvalidateCache()
            }
            if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                $global:PmcApp.RequestRender()
            }
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }
}
