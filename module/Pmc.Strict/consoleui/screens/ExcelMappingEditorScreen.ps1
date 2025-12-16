using namespace System.Collections.Generic
using namespace System.Text

# ExcelMappingEditorScreen - Edit field mappings for a profile
# Shows list of field mappings with add/edit/delete

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ExcelMappingService.ps1"

<#
.SYNOPSIS
Excel field mapping editor screen

.DESCRIPTION
Edit field mappings for a specific Excel profile:
- Add/Edit/Delete field mappings
- Configure Excel cell, project property, data type
- Set required fields
- Manage sort order
#>
class ExcelMappingEditorScreen : StandardListScreen {
    hidden [ExcelMappingService]$_mappingService = $null
    hidden [string]$_profileId = ""
    hidden [string]$_profileName = ""

    # Constructor
    ExcelMappingEditorScreen([string]$profileId, [string]$profileName) : base("ExcelMappings", "Field Mappings") {
        $this._profileId = $profileId
        $this._profileName = $profileName
        $this._mappingService = [ExcelMappingService]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Projects", "Excel Profiles", $profileName, "Mappings"))
        $this.ScreenTitle = "Mappings - $profileName"

        # Setup event handlers
        $self = $this
        $this._mappingService.OnProfilesChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    ExcelMappingEditorScreen([string]$profileId, [string]$profileName, [object]$container) : base("ExcelMappings", "Field Mappings", $container) {
        $this._profileId = $profileId
        $this._profileName = $profileName
        $this._mappingService = [ExcelMappingService]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Projects", "Excel Profiles", $profileName, "Mappings"))
        $this.ScreenTitle = "Mappings - $profileName"

        # Setup event handlers
        $self = $this
        $this._mappingService.OnProfilesChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    [void] OnDoExit() {
        ([StandardListScreen]$this).OnDoExit()
        $this._mappingService.OnProfilesChanged = $null
    }

    # === Abstract Method Implementations ===

    [string] GetEntityType() {
        # Non-standard type, won't wire to TaskStore
        return 'field_mapping'
    }

    [array] GetColumns() {
        return @(
            @{ Name='display_name'; Label='Field Name'; Width=25 }
            @{ Name='excel_cell'; Label='Excel Cell'; Width=12 }
            @{ Name='project_property'; Label='Property'; Width=20 }
            @{ Name='data_type'; Label='Type'; Width=10 }
            @{ Name='required_display'; Label='Required'; Width=10 }
        )
    }

    [void] LoadData() {
        $items = $this.LoadItems()
        $this.List.SetData($items)
    }

    [array] LoadItems() {
        $mappings = @($this._mappingService.GetMappings($this._profileId))

        # Format for display
        foreach ($mapping in $mappings) {
            $mapping['required_display'] = $(if ($mapping['required']) { "Yes" } else { "No" })
        }

        return $mappings
    }

    [array] GetEditFields([object]$item) {
        if ($null -eq $item -or $item.Count -eq 0) {
            # New mapping
            return @(
                @{ Name='display_name'; Type='text'; Label='Display Name'; Required=$true; Value='' }
                @{ Name='excel_cell'; Type='text'; Label='Excel Cell (e.g., W3)'; Required=$true; Value='' }
                @{ Name='project_property'; Type='text'; Label='Project Property'; Required=$true; Value='' }
                @{ Name='data_type'; Type='text'; Label='Data Type (string/int/date/bool)'; Value='string' }
                @{ Name='required'; Type='text'; Label='Required (true/false)'; Value='false' }
                @{ Name='include_in_export'; Type='text'; Label='Include in Export (true/false)'; Value='true' }
                @{ Name='sort_order'; Type='text'; Label='Sort Order'; Value='1' }
            )
        } else {
            # Existing mapping - use hashtable accessor for consistency
            $displayName = $(if ($item -is [hashtable]) { $item['display_name'] } else { $item.display_name })
            $excelCell = $(if ($item -is [hashtable]) { $item['excel_cell'] } else { $item.excel_cell })
            $projectProperty = $(if ($item -is [hashtable]) { $item['project_property'] } else { $item.project_property })
            $dataType = $(if ($item -is [hashtable]) { $item['data_type'] } else { $item.data_type })
            $required = $(if ($item -is [hashtable]) { $item['required'] } else { $item.required })
            $includeInExport = $(if ($item -is [hashtable]) { $item['include_in_export'] } else { $item.include_in_export })
            $sortOrder = $(if ($item -is [hashtable]) { $item['sort_order'] } else { $item.sort_order })

            # HIGH FIX #10: Robust boolean parsing with error handling
            $requiredBool = try {
                if ($required -is [bool]) {
                    $required
                } else {
                    [bool]::Parse($required)
                }
            } catch {
                Write-PmcTuiLog "Invalid boolean value for required: '$required', defaulting to false" "WARNING"
                $false
            }

            $includeInExportBool = try {
                if ($includeInExport -is [bool]) {
                    $includeInExport
                } else {
                    [bool]::Parse($includeInExport)
                }
            } catch {
                Write-PmcTuiLog "Invalid boolean value for includeInExport: '$includeInExport', defaulting to true" "WARNING"
                $true
            }

            return @(
                @{ Name='display_name'; Type='text'; Label='Display Name'; Required=$true; Value=$displayName }
                @{ Name='excel_cell'; Type='text'; Label='Excel Cell (e.g., W3)'; Required=$true; Value=$excelCell }
                @{ Name='project_property'; Type='text'; Label='Project Property'; Required=$true; Value=$projectProperty }
                @{ Name='data_type'; Type='text'; Label='Data Type (string/int/date/bool)'; Value=$dataType }
                @{ Name='required'; Type='text'; Label='Required (true/false)'; Value=(if ($requiredBool) { 'true' } else { 'false' }) }
                @{ Name='include_in_export'; Type='text'; Label='Include in Export (true/false)'; Value=(if ($includeInExportBool) { 'true' } else { 'false' }) }
                @{ Name='sort_order'; Type='text'; Label='Sort Order'; Value=$sortOrder.ToString() }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        try {
            # Validate Excel cell address format
            if ($values.excel_cell -notmatch '^[A-Z]+\d+$') {
                $this.SetStatusMessage("Invalid Excel cell address: $($values.excel_cell). Use format like 'A1' or 'W3'", "error")
                return
            }

            # Validate data type
            $validTypes = @('string', 'int', 'date', 'bool')
            if ($values.data_type -notin $validTypes) {
                $this.SetStatusMessage("Invalid data type '$($values.data_type)'. Must be one of: $($validTypes -join ', ')", "error")
                return
            }

            # HIGH FIX #10: Parse boolean values robustly
            $required = try { [bool]::Parse($values.required) } catch { $false }
            $includeInExport = try { [bool]::Parse($values.include_in_export) } catch { $true }

            # Validate and parse sort order
            $sortOrder = 1
            if ($values.sort_order -match '^\d+$') {
                $sortOrder = [int]$values.sort_order
            } else {
                throw "Sort order must be a number"
            }

            $mappingData = @{
                display_name = $values.display_name
                excel_cell = $values.excel_cell
                project_property = $values.project_property
                data_type = $values.data_type
                required = $required
                include_in_export = $includeInExport
                sort_order = $sortOrder
            }

            $this._mappingService.AddMapping($this._profileId, $mappingData)
            $this.SetStatusMessage("Mapping '$($values.display_name)' added", "success")
        } catch {
            $this.SetStatusMessage("Error adding mapping: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })

            # Validate Excel cell address format
            if ($values.excel_cell -notmatch '^[A-Z]+\d+$') {
                $this.SetStatusMessage("Invalid Excel cell address: $($values.excel_cell). Use format like 'A1' or 'W3'", "error")
                return
            }

            # Validate data type
            $validTypes = @('string', 'int', 'date', 'bool')
            if ($values.data_type -notin $validTypes) {
                $this.SetStatusMessage("Invalid data type '$($values.data_type)'. Must be one of: $($validTypes -join ', ')", "error")
                return
            }

            # HIGH FIX #10: Parse boolean values robustly
            $required = try { [bool]::Parse($values.required) } catch { $false }
            $includeInExport = try { [bool]::Parse($values.include_in_export) } catch { $true }

            # Validate and parse sort order
            $sortOrder = 1
            if ($values.sort_order -match '^\d+$') {
                $sortOrder = [int]$values.sort_order
            } else {
                throw "Sort order must be a number"
            }

            $changes = @{
                display_name = $values.display_name
                excel_cell = $values.excel_cell
                project_property = $values.project_property
                data_type = $values.data_type
                required = $required
                include_in_export = $includeInExport
                sort_order = $sortOrder
            }

            $this._mappingService.UpdateMapping($this._profileId, $itemId, $changes)
            $this.SetStatusMessage("Mapping '$($values.display_name)' updated", "success")
        } catch {
            $this.SetStatusMessage("Error updating mapping: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
            $itemName = $(if ($item -is [hashtable]) { $item['display_name'] } else { $item.display_name })

            if ($itemId) {
                $this._mappingService.DeleteMapping($this._profileId, $itemId)
                $this.SetStatusMessage("Mapping '$itemName' deleted", "success")
            } else {
                $this.SetStatusMessage("Cannot delete mapping without ID", "error")
            }
        } catch {
            $this.SetStatusMessage("Error deleting mapping: $($_.Exception.Message)", "error")
        }
    }
}