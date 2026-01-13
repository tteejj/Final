using namespace System.Collections.Generic
using namespace System.Text

# ExcelCopyMappingEditorScreen - Edit cell mappings for an Excel copy profile
# List, add, edit, delete cell mappings

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ExcelCopyService.ps1"
. "$PSScriptRoot/../widgets/SheetPickerDialog.ps1"

<#
.SYNOPSIS
Excel copy mapping editor screen

.DESCRIPTION
Manage cell mappings for an Excel copy profile:
- Add/Edit/Delete mappings
- Specify source and destination sheets and cells
- View list of all mappings
#>
class ExcelCopyMappingEditorScreen : StandardListScreen {
    hidden [ExcelCopyService]$_copyService = $null
    hidden [string]$_profileId = ""
    hidden [string]$_profileName = ""

    # Constructor
    ExcelCopyMappingEditorScreen([string]$profileId, [string]$profileName) : base("ExcelCopyMappings", "Cell Mappings") {
        $this._copyService = [ExcelCopyService]::GetInstance()
        $this._profileId = $profileId
        $this._profileName = $profileName

        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        $this.Header.SetBreadcrumb(@("Home", "Tools", "Excel Copy Profiles", $profileName, "Mappings"))
    }

    # Constructor with container
    ExcelCopyMappingEditorScreen([string]$profileId, [string]$profileName, [object]$container) : base("ExcelCopyMappings", "Cell Mappings", $container) {
        $this._copyService = [ExcelCopyService]::GetInstance()
        $this._profileId = $profileId
        $this._profileName = $profileName

        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        $this.Header.SetBreadcrumb(@("Home", "Tools", "Excel Copy Profiles", $profileName, "Mappings"))
    }

    [string] GetEntityType() {
        return 'excel_copy_mapping'
    }

    [array] GetColumns() {
        return @(
            @{ Name='name'; Label='Mapping Name'; Width=20 }
            @{ Name='source_sheet'; Label='Source Sheet'; Width=18 }
            @{ Name='source_cell'; Label='Source Cell'; Width=12 }
            @{ Name='dest_sheet'; Label='Dest Sheet'; Width=18 }
            @{ Name='dest_cell'; Label='Dest Cell'; Width=12 }
        )
    }

    [void] LoadData() {
        $mappings = $this._copyService.GetMappings($this._profileId)
        $this.List.SetData($mappings)
    }

    [array] GetEditFields([object]$item) {
        if ($null -eq $item -or $item.Count -eq 0) {
            # New mapping
            return @(
                @{ Name='name'; Type='text'; Label='Mapping Name'; Required=$true; Value='' }
                @{ Name='source_sheet'; Type='text'; Label='Source Sheet'; Required=$true; Value='' }
                @{ Name='source_cell'; Type='text'; Label='Source Cell (e.g., W23)'; Required=$true; Value='' }
                @{ Name='dest_sheet'; Type='text'; Label='Dest Sheet'; Required=$true; Value='' }
                @{ Name='dest_cell'; Type='text'; Label='Dest Cell (e.g., B2)'; Required=$true; Value='' }
            )
        } else {
            # Existing mapping
            $name = Get-SafeProperty $item 'name'
            $sourceSheet = Get-SafeProperty $item 'source_sheet'
            $sourceCell = Get-SafeProperty $item 'source_cell'
            $destSheet = Get-SafeProperty $item 'dest_sheet'
            $destCell = Get-SafeProperty $item 'dest_cell'

            return @(
                @{ Name='name'; Type='text'; Label='Mapping Name'; Required=$true; Value=$name }
                @{ Name='source_sheet'; Type='text'; Label='Source Sheet'; Required=$true; Value=$sourceSheet }
                @{ Name='source_cell'; Type='text'; Label='Source Cell (e.g., W23)'; Required=$true; Value=$sourceCell }
                @{ Name='dest_sheet'; Type='text'; Label='Dest Sheet'; Required=$true; Value=$destSheet }
                @{ Name='dest_cell'; Type='text'; Label='Dest Cell (e.g., B2)'; Required=$true; Value=$destCell }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        # Validation
        if ([string]::IsNullOrWhiteSpace($values.name)) {
            $this.SetStatusMessage("Mapping name is required", "error")
            return
        }

        # Validate cell addresses (simple check)
        if (-not ($values.source_cell -match '(?i)^[A-Z]+\d+$')) {
            $this.SetStatusMessage("Invalid source cell address (expected format like 'A1' or 'W23')", "error")
            return
        }
        if (-not ($values.dest_cell -match '(?i)^[A-Z]+\d+$')) {
            $this.SetStatusMessage("Invalid destination cell address (expected format like 'B2')", "error")
            return
        }

        # Create mapping
        try {
            $this._copyService.AddMapping($this._profileId, $values)
            $this.SetStatusMessage("Mapping created", "success")
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
        # Validate cell addresses
        if ($values.ContainsKey('source_cell') -and -not ($values.source_cell -match '(?i)^[A-Z]+\d+$')) {
            $this.SetStatusMessage("Invalid source cell address", "error")
            return
        }
        if ($values.ContainsKey('dest_cell') -and -not ($values.dest_cell -match '(?i)^[A-Z]+\d+$')) {
            $this.SetStatusMessage("Invalid destination cell address", "error")
            return
        }

        # Update mapping
        try {
            $id = Get-SafeProperty $item 'id'
            $this._copyService.UpdateMapping($this._profileId, $id, $values)
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
            $id = Get-SafeProperty $item 'id'
            $this._copyService.DeleteMapping($this._profileId, $id)
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

    # Custom actions - Add sheet picker action
    [array] GetCustomActions() {
        return @(
            @{
                Label = "View Source Sheets (V)"
                Key = 'v'
                Callback = { $this.ShowSourceSheets() }.GetNewClosure()
            }
            @{
                Label = "View Dest Sheets (B)"
                Key = 'b'
                Callback = { $this.ShowDestSheets() }.GetNewClosure()
            }
        )
    }

    [void] ShowSourceSheets() {
        try {
            $sheets = $this._copyService.GetSourceSheets($this._profileId)
            if ($sheets.Count -eq 0) {
                $this.SetStatusMessage("No sheets found in source workbook", "warning")
                return
            }

            $sheetList = $sheets -join ", "
            $this.SetStatusMessage("Source sheets: $sheetList", "info")
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] ShowDestSheets() {
        try {
            $sheets = $this._copyService.GetDestSheets($this._profileId)
            if ($sheets.Count -eq 0) {
                $this.SetStatusMessage("No sheets found in destination workbook", "warning")
                return
            }

            $sheetList = $sheets -join ", "
            $this.SetStatusMessage("Dest sheets: $sheetList", "info")
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }
}
