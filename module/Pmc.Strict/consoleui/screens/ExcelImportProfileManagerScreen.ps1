using namespace System.Collections.Generic
using namespace System.Text

# ExcelImportProfileManagerScreen - Manage Excel import profiles
# Maps Excel cells to Project Info fields

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ExcelImportService.ps1"

<#
.SYNOPSIS
Excel import profile management screen

.DESCRIPTION
Manage Excel-to-Project-Info import profiles:
- Add/Edit/Delete profiles
- Edit cell->field mappings
#>
class ExcelImportProfileManagerScreen : StandardListScreen {
    hidden [ExcelImportService]$_importService = $null

    # Constructor
    ExcelImportProfileManagerScreen() : base("ExcelImportProfiles", "Excel Import Profiles") {
        $this._importService = [ExcelImportService]::GetInstance()

        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        $this.Header.SetBreadcrumb(@("Home", "Tools", "Excel Import Profiles"))

        $self = $this
        $this._importService.OnProfilesChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    # Constructor with container
    ExcelImportProfileManagerScreen([object]$container) : base("ExcelImportProfiles", "Excel Import Profiles", $container) {
        $this._importService = [ExcelImportService]::GetInstance()

        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        $this.Header.SetBreadcrumb(@("Home", "Tools", "Excel Import Profiles"))

        $self = $this
        $this._importService.OnProfilesChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    [void] OnDoExit() {
        ([StandardListScreen]$this).OnDoExit()
        $this._importService.OnProfilesChanged = $null
    }

    [string] GetEntityType() {
        return 'excel_import_profile'
    }

    [array] GetColumns() {
        return @(
            @{ Name='name'; Label='Profile Name'; Width=25 }
            @{ Name='source_field'; Label='Source Field'; Width=20 }
            @{ Name='mapping_count'; Label='Mappings'; Width=10 }
        )
    }

    [void] LoadData() {
        $profiles = $this._importService.GetAllProfiles()

        foreach ($profile in $profiles) {
            $profile['mapping_count'] = if ($profile.mappings) { $profile.mappings.Count } else { 0 }
        }

        $this.List.SetData($profiles)
    }

    [array] GetEditFields([object]$item) {
        $sourceOptions = $this._importService.GetSourceFieldOptions()
        $optionLabels = $sourceOptions | ForEach-Object { $_.label }

        if ($null -eq $item -or $item.Count -eq 0) {
            return @(
                @{ Name='name'; Type='text'; Label='Profile Name'; Required=$true; Value='' }
                @{ Name='description'; Type='text'; Label='Description'; Value='' }
                @{ Name='source_field'; Type='text'; Label='Source Field (CAAName/RequestName/T2020)'; Required=$true; Value='CAAName' }
            )
        } else {
            return @(
                @{ Name='name'; Type='text'; Label='Profile Name'; Required=$true; Value=$item.name }
                @{ Name='description'; Type='text'; Label='Description'; Value=$item.description }
                @{ Name='source_field'; Type='text'; Label='Source Field'; Required=$true; Value=$item.source_field }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        if ([string]::IsNullOrWhiteSpace($values.name)) {
            $this.SetStatusMessage("Profile name is required", "error")
            return
        }

        try {
            $this._importService.CreateProfile(
                $values.name,
                $values.description,
                $values.source_field
            )
            $this.SetStatusMessage("Profile created", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            $this._importService.UpdateProfile($item.id, $values)
            $this.SetStatusMessage("Profile updated", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $this._importService.DeleteProfile($item.id)
            $this.SetStatusMessage("Profile deleted", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] OnItemActivated([object]$item) {
        if ($null -eq $item) { return }

        # Open mapping editor screen
        . "$PSScriptRoot/ExcelImportMappingEditorScreen.ps1"
        $editor = New-Object ExcelImportMappingEditorScreen -ArgumentList $item.id, $item.name
        $global:PmcApp.PushScreen($editor)
    }
}
