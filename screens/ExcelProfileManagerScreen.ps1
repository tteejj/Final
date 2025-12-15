using namespace System.Collections.Generic
using namespace System.Text

# ExcelProfileManagerScreen - Manage Excel import profiles
# List, add, edit, delete mapping profiles

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ExcelMappingService.ps1"

<#
.SYNOPSIS
Excel profile management screen

.DESCRIPTION
Manage Excel import mapping profiles:
- Add/Edit/Delete profiles
- Set active profile
- Edit field mappings (opens ExcelMappingEditorScreen)
#>
class ExcelProfileManagerScreen : StandardListScreen {
    hidden [ExcelMappingService]$_mappingService = $null

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Projects', 'Excel Profiles', 'M', {
            . "$PSScriptRoot/ExcelProfileManagerScreen.ps1"
            $global:PmcApp.PushScreen((New-Object -TypeName ExcelProfileManagerScreen))
        }, 50)
    }

    # Constructor
    ExcelProfileManagerScreen() : base("ExcelProfiles", "Excel Import Profiles") {

        # Initialize service
        $this._mappingService = [ExcelMappingService]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Projects", "Excel Profiles"))

        # Setup event handlers
        $self = $this
        $this._mappingService.OnProfilesChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    # Constructor with container
    ExcelProfileManagerScreen([object]$container) : base("ExcelProfiles", "Excel Import Profiles", $container) {

        # Initialize service
        $this._mappingService = [ExcelMappingService]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Projects", "Excel Profiles"))

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
        return 'excel_profile'
    }

    [array] GetColumns() {
        return @(
            @{ Name='name'; Label='Profile Name'; Width=30 }
            @{ Name='description'; Label='Description'; Width=40 }
            @{ Name='mapping_count'; Label='Fields'; Width=8 }
            @{ Name='is_active'; Label='Active'; Width=8 }
        )
    }

    [void] LoadData() {
        try {
            $items = $this.LoadItems()
            $this.List.SetData($items)
        } catch {
            throw
        }
    }

    # Helper method - not part of StandardListScreen contract
    [array] LoadItems() {
        $profiles = @($this._mappingService.GetAllProfiles())
        Write-PmcTuiLog "ExcelProfileManagerScreen.LoadItems: Got $($profiles.Count) profiles from service" "DEBUG"

        $activeProfile = $this._mappingService.GetActiveProfile()
        $activeId = $(if ($activeProfile) { $activeProfile['id'] } else { $null })

        # Format for display
        foreach ($profile in $profiles) {
            if ($null -ne $profile) {
                Write-PmcTuiLog "ExcelProfileManagerScreen.LoadItems: Processing profile - type=$($profile.GetType().Name) isHashtable=$($profile -is [hashtable])" "DEBUG"
                if ($profile -is [hashtable]) {
                    Write-PmcTuiLog "ExcelProfileManagerScreen.LoadItems: Profile keys: $($profile.Keys -join ', ')" "DEBUG"
                    Write-PmcTuiLog "ExcelProfileManagerScreen.LoadItems: Profile name='$($profile['name'])' desc='$($profile['description'])'" "DEBUG"
                }

                $profile['mapping_count'] = $(if ($profile['mappings']) { $profile['mappings'].Count } else { 0 })
                $profile['is_active'] = $(if ($profile['id'] -eq $activeId) { "Yes" } else { "No" })

                Write-PmcTuiLog "ExcelProfileManagerScreen.LoadItems: After formatting - mapping_count=$($profile['mapping_count']) is_active=$($profile['is_active'])" "DEBUG"
            } else {
                Write-PmcTuiLog "ExcelProfileManagerScreen.LoadItems: Null profile in list" "DEBUG"
            }
        }

        return $profiles
    }

    [array] GetEditFields([object]$item) {
        if ($null -eq $item -or $item.Count -eq 0) {
            # New profile
            return @(
                @{ Name='name'; Type='text'; Label='Profile Name'; Required=$true; Value='' }
                @{ Name='description'; Type='text'; Label='Description'; Value='' }
                @{ Name='start_cell'; Type='text'; Label='Start Cell'; Value='A1' }
            )
        } else {
            # Existing profile - use hashtable accessor for consistency
            $name = $(if ($item -is [hashtable]) { $item['name'] } else { $item.name })
            $description = $(if ($item -is [hashtable]) { $item['description'] } else { $item.description })
            $startCell = $(if ($item -is [hashtable]) { $item['start_cell'] } else { $item.start_cell })

            return @(
                @{ Name='name'; Type='text'; Label='Profile Name'; Required=$true; Value=$name }
                @{ Name='description'; Type='text'; Label='Description'; Value=$description }
                @{ Name='start_cell'; Type='text'; Label='Start Cell'; Value=$startCell }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        try {
            # ENDEMIC FIX: Safe value access and validation
            $name = $(if ($values.ContainsKey('name')) { $values.name } else { '' })
            $description = $(if ($values.ContainsKey('description')) { $values.description } else { '' })
            $startCell = $(if ($values.ContainsKey('start_cell')) { $values.start_cell } else { '' })

            if ([string]::IsNullOrWhiteSpace($name)) {
                $this.SetStatusMessage("Profile name is required", "error")
                return
            }

            $this._mappingService.CreateProfile($name, $description, $startCell)

            $this.SetStatusMessage("Profile '$name' created", "success")
        } catch {
            $this.SetStatusMessage("Error creating profile: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })

            # ENDEMIC FIX: Safe value access
            $changes = @{
                name = $(if ($values.ContainsKey('name')) { $values.name } else { '' })
                description = $(if ($values.ContainsKey('description')) { $values.description } else { '' })
                start_cell = $(if ($values.ContainsKey('start_cell')) { $values.start_cell } else { '' })
            }

            # Validate required fields
            if ([string]::IsNullOrWhiteSpace($changes.name)) {
                $this.SetStatusMessage("Profile name is required", "error")
                return
            }

            $this._mappingService.UpdateProfile($itemId, $changes)
            $this.SetStatusMessage("Profile '$($changes.name)' updated", "success")
        } catch {
            $this.SetStatusMessage("Error updating profile: $($_.Exception.Message)", "error")
        }
    }

    [void] OnItemDeleted([object]$item) {
        try {
            $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
            $itemName = $(if ($item -is [hashtable]) { $item['name'] } else { $item.name })

            if ($itemId) {
                $this._mappingService.DeleteProfile($itemId)
                $this.SetStatusMessage("Profile '$itemName' deleted", "success")
            } else {
                $this.SetStatusMessage("Cannot delete profile without ID", "error")
            }
        } catch {
            $this.SetStatusMessage("Error deleting profile: $($_.Exception.Message)", "error")
        }
    }

    # Override OnItemActivated to open mapping editor
    [void] OnItemActivated([object]$item) {
        if ($null -eq $item) {
            return
        }

        $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
        $itemName = $(if ($item -is [hashtable]) { $item['name'] } else { $item.name })

        if ($itemId) {
            . "$PSScriptRoot/ExcelMappingEditorScreen.ps1"
            $editorScreen = New-Object ExcelMappingEditorScreen -ArgumentList $itemId, $itemName
            $global:PmcApp.PushScreen($editorScreen)
        }
    }

    # Custom action: Set as active profile
    [void] SetActiveProfile() {
        $selectedItem = $this.List.GetSelectedItem()
        if ($null -eq $selectedItem) {
            $this.SetStatusMessage("No profile selected", "error")
            return
        }

        $itemId = $(if ($selectedItem -is [hashtable]) { $selectedItem['id'] } else { $selectedItem.id })
        $itemName = $(if ($selectedItem -is [hashtable]) { $selectedItem['name'] } else { $selectedItem.name })

        try {
            $this._mappingService.SetActiveProfile($itemId)
            $this.SetStatusMessage("Active profile set to '$itemName'", "success")
            $this.LoadData()
        } catch {
            Write-PmcTuiLog "SetActiveProfile: Error setting active profile '$itemName' - $_" "ERROR"
            $this.SetStatusMessage("Error setting active profile: $($_.Exception.Message)", "error")
        }
    }

    [array] GetCustomActions() {
        return @(
            @{
                Label = "Set Active (S)"
                Key = 's'
                Callback = {
                    $this.SetActiveProfile()
                }.GetNewClosure()
            }
        )
    }
}
