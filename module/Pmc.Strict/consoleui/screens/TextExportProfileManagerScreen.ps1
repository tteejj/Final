using namespace System.Collections.Generic
using namespace System.Text

# TextExportProfileManagerScreen - Manage Excel to text export profiles
# Maps Excel cells to text file output lines

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/TextExportService.ps1"

<#
.SYNOPSIS
Text export profile management screen

.DESCRIPTION
Manage Excel-to-Text export profiles for T2020 generation:
- Add/Edit/Delete profiles
- Edit cell->label mappings
#>
class TextExportProfileManagerScreen : StandardListScreen {
    hidden [TextExportService]$_exportService = $null

    # Constructor
    TextExportProfileManagerScreen() : base("TextExportProfiles", "T2020 Export Profiles") {
        $this._exportService = [TextExportService]::GetInstance()

        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        $this.Header.SetBreadcrumb(@("Home", "Tools", "T2020 Export Profiles"))

        $self = $this
        $this._exportService.OnProfilesChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    # Constructor with container
    TextExportProfileManagerScreen([object]$container) : base("TextExportProfiles", "T2020 Export Profiles", $container) {
        $this._exportService = [TextExportService]::GetInstance()

        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        $this.Header.SetBreadcrumb(@("Home", "Tools", "T2020 Export Profiles"))

        $self = $this
        $this._exportService.OnProfilesChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    [void] OnDoExit() {
        ([StandardListScreen]$this).OnDoExit()
        $this._exportService.OnProfilesChanged = $null
    }

    [string] GetEntityType() {
        return 'text_export_profile'
    }

    [array] GetColumns() {
        return @(
            @{ Name='name'; Label='Profile Name'; Width=25 }
            @{ Name='source_field'; Label='Source Field'; Width=20 }
            @{ Name='output_filename'; Label='Output File'; Width=20 }
            @{ Name='mapping_count'; Label='Mappings'; Width=10 }
        )
    }

    [void] LoadData() {
        $profiles = $this._exportService.GetAllProfiles()

        foreach ($profile in $profiles) {
            $profile['mapping_count'] = if ($profile.mappings) { $profile.mappings.Count } else { 0 }
        }

        $this.List.SetData($profiles)
    }

    [array] GetEditFields([object]$item) {
        if ($null -eq $item -or $item.Count -eq 0) {
            return @(
                @{ Name='name'; Type='text'; Label='Profile Name'; Required=$true; Value='' }
                @{ Name='description'; Type='text'; Label='Description'; Value='' }
                @{ Name='source_field'; Type='text'; Label='Source Field (CAAName/RequestName)'; Required=$true; Value='CAAName' }
                @{ Name='output_filename'; Type='text'; Label='Output Filename'; Required=$true; Value='T2020.txt' }
            )
        } else {
            return @(
                @{ Name='name'; Type='text'; Label='Profile Name'; Required=$true; Value=$item.name }
                @{ Name='description'; Type='text'; Label='Description'; Value=$item.description }
                @{ Name='source_field'; Type='text'; Label='Source Field'; Required=$true; Value=$item.source_field }
                @{ Name='output_filename'; Type='text'; Label='Output Filename'; Required=$true; Value=$item.output_filename }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        if ([string]::IsNullOrWhiteSpace($values.name)) {
            $this.SetStatusMessage("Profile name required", "error")
            return
        }

        try {
            $this._exportService.CreateProfile(
                $values.name,
                $values.description,
                $values.source_field,
                $values.output_filename
            )
            $this.SetStatusMessage("Profile created", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            $this._exportService.UpdateProfile($item.id, $values)
            $this.SetStatusMessage("Profile updated", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $this._exportService.DeleteProfile($item.id)
            $this.SetStatusMessage("Profile deleted", "success")
            $this.LoadData()
        } catch {
            $this.SetStatusMessage("Error: $_", "error")
        }
    }

    [void] OnItemActivated([object]$item) {
        if ($null -eq $item) { return }

        # Open mapping editor screen
        . "$PSScriptRoot/TextExportMappingEditorScreen.ps1"
        $editor = New-Object TextExportMappingEditorScreen -ArgumentList $item.id, $item.name
        $global:PmcApp.PushScreen($editor)
    }
}
