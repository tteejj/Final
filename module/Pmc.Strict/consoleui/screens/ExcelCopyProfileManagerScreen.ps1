using namespace System.Collections.Generic
using namespace System.Text

# ExcelCopyProfileManagerScreen - Manage Excel copy profiles
# List, add, edit, delete copy profiles, execute copies

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/ExcelCopyService.ps1"

<#
.SYNOPSIS
Excel copy profile management screen

.DESCRIPTION
Manage Excel-to-Excel copy profiles:
- Add/Edit/Delete profiles
- Set active profile
- Edit cell mappings (opens ExcelCopyMappingEditorScreen)
- Execute copy operation
#>
class ExcelCopyProfileManagerScreen : StandardListScreen {
    hidden [ExcelCopyService]$_copyService = $null

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Tools', 'Excel Copy Profiles', 'C', {
            . "$PSScriptRoot/ExcelCopyProfileManagerScreen.ps1"
            $global:PmcApp.PushScreen((New-Object -TypeName ExcelCopyProfileManagerScreen))
        }, 60)
    }

    # Constructor
    ExcelCopyProfileManagerScreen() : base("ExcelCopyProfiles", "Excel Copy Profiles") {

        # Initialize service
        $this._copyService = [ExcelCopyService]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tools", "Excel Copy Profiles"))

        # Setup event handlers
        $self = $this
        $this._copyService.OnProfilesChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    # Constructor with container
    ExcelCopyProfileManagerScreen([object]$container) : base("ExcelCopyProfiles", "Excel Copy Profiles", $container) {

        # Initialize service
        $this._copyService = [ExcelCopyService]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $false

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tools", "Excel Copy Profiles"))

        # Setup event handlers
        $self = $this
        $this._copyService.OnProfilesChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    [void] OnDoExit() {
        ([StandardListScreen]$this).OnDoExit()
        $this._copyService.OnProfilesChanged = $null
    }

    # === Abstract Method Implementations ===

    [string] GetEntityType() {
        # Non-standard type, won't wire to TaskStore
        return 'excel_copy_profile'
    }

    [array] GetColumns() {
        return @(
            @{ Name='name'; Label='Profile Name'; Width=25 }
            @{ Name='source_file'; Label='Source'; Width=25 }
            @{ Name='dest_file'; Label='Destination'; Width=25 }
            @{ Name='mapping_count'; Label='Mappings'; Width=10 }
            @{ Name='is_active'; Label='Active'; Width=8 }
        )
    }

    [void] LoadData() {
        $profiles = $this._copyService.GetAllProfiles()
        $activeProfile = $this._copyService.GetActiveProfile()
        $activeId = if($activeProfile) { $activeProfile.id } else { $null }

        # Format for display
        # Format for display
        foreach ($profile in $profiles) {
            $srcPath = Get-SafeProperty $profile 'source_workbook_path'
            $dstPath = Get-SafeProperty $profile 'dest_workbook_path'
            $mappings = Get-SafeProperty $profile 'mappings'
            $pId = Get-SafeProperty $profile 'id'

            $srcFile = if ($srcPath) { Split-Path -Leaf $srcPath } else { "" }
            $dstFile = if ($dstPath) { Split-Path -Leaf $dstPath } else { "" }
            $mapCount = if ($mappings) { $mappings.Count } else { 0 }
            $isActive = if($pId -eq $activeId) { "Yes" } else { "No" }

            if ($profile -is [hashtable]) {
                $profile['source_file'] = $srcFile
                $profile['dest_file'] = $dstFile
                $profile['mapping_count'] = $mapCount
                $profile['is_active'] = $isActive
            } else {
                try {
                    $profile | Add-Member -MemberType NoteProperty -Name 'source_file' -Value $srcFile -Force
                    $profile | Add-Member -MemberType NoteProperty -Name 'dest_file' -Value $dstFile -Force
                    $profile | Add-Member -MemberType NoteProperty -Name 'mapping_count' -Value $mapCount -Force
                    $profile | Add-Member -MemberType NoteProperty -Name 'is_active' -Value $isActive -Force
                } catch { }
            }
        }

        $this.List.SetData($profiles)
    }

    [array] GetEditFields([object]$item) {
        if ($null -eq $item -or $item.Count -eq 0) {
            # New profile
            return @(
                @{ Name='name'; Type='text'; Label='Profile Name'; Required=$true; Value='' }
                @{ Name='description'; Type='text'; Label='Description'; Value='' }
                @{ Name='source_workbook_path'; Type='text'; Label='Source Workbook Path'; Required=$true; Value=''; Hint='Full path to source .xlsx file' }
                @{ Name='dest_workbook_path'; Type='text'; Label='Dest Workbook Path'; Required=$true; Value=''; Hint='Full path to destination .xlsx file' }
            )
        } else {
            # Existing profile
            $name = Get-SafeProperty $item 'name'
            $desc = Get-SafeProperty $item 'description'
            $src = Get-SafeProperty $item 'source_workbook_path'
            $dst = Get-SafeProperty $item 'dest_workbook_path'

            return @(
                @{ Name='name'; Type='text'; Label='Profile Name'; Required=$true; Value=$name }
                @{ Name='description'; Type='text'; Label='Description'; Value=$desc }
                @{ Name='source_workbook_path'; Type='text'; Label='Source Workbook Path'; Required=$true; Value=$src; Hint='Full path to source .xlsx file' }
                @{ Name='dest_workbook_path'; Type='text'; Label='Dest Workbook Path'; Required=$true; Value=$dst; Hint='Full path to destination .xlsx file' }
            )
        }
    }

    [void] OnItemCreated([hashtable]$values) {
        # Validation
        if ([string]::IsNullOrWhiteSpace($values.name)) {
            $this.SetStatusMessage("Profile name is required", "error")
            return
        }

        # Create profile
        try {
            $this._copyService.CreateProfile(
                $values.name,
                $values.description,
                $values.source_workbook_path,
                $values.dest_workbook_path
            )
            $this.SetStatusMessage("Profile created", "success")
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
        # Update profile
        try {
            $id = Get-SafeProperty $item 'id'
            $this._copyService.UpdateProfile($id, $values)
            $this.SetStatusMessage("Profile updated", "success")
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
            $this._copyService.DeleteProfile($id)
            $this.SetStatusMessage("Profile deleted", "success")
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

    # Override OnItemActivated to open mapping editor
    [void] OnItemActivated([object]$item) {
        if ($null -eq $item) { return }

        # Open mapping editor screen
        . "$PSScriptRoot/ExcelCopyMappingEditorScreen.ps1"
        $id = Get-SafeProperty $item 'id'
        $name = Get-SafeProperty $item 'name'
        $editor = New-Object ExcelCopyMappingEditorScreen -ArgumentList $id, $name
        $global:PmcApp.PushScreen($editor)
    }

    # Custom actions
    [array] GetCustomActions() {
        return @(
            @{
                Label = "Set Active (S)"
                Key = 's'
                Callback = { $this.SetActiveProfile() }.GetNewClosure()
            }
            @{
                Label = "Execute Copy (X)"
                Key = 'x'
                Callback = { $this.ExecuteCopy() }.GetNewClosure()
            }
        )
    }

    [void] SetActiveProfile() {
        $item = $this.List.GetSelectedItem()
        if ($null -eq $item) {
            $this.SetStatusMessage("No profile selected", "error")
            return
        }

        try {
            $id = Get-SafeProperty $item 'id'
            $this._copyService.SetActiveProfile($id)
            $this.SetStatusMessage("Active profile set", "success")
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

    [void] ExecuteCopy() {
        $item = $this.List.GetSelectedItem()
        if ($null -eq $item) {
            $this.SetStatusMessage("No profile selected", "error")
            return
        }

        # Validate profile has mappings
        $mapCount = Get-SafeProperty $item 'mapping_count'
        if ($mapCount -eq 0) {
            $this.SetStatusMessage("Profile has no mappings to copy", "error")
            return
        }

        # Execute copy operation
        try {
            $this.SetStatusMessage("Executing copy operation...", "info")
            $id = Get-SafeProperty $item 'id'
            $result = $this._copyService.ExecuteCopy($id)

            # Display result
            if ($result.failed_mappings -eq 0) {
                $this.SetStatusMessage("Copy successful: $($result.successful_mappings) mappings copied", "success")
            } else {
                $msg = "Copy completed: $($result.successful_mappings) succeeded, $($result.failed_mappings) failed"
                $this.SetStatusMessage($msg, "warning")

                # Show first few errors
                if ($result.errors.Count -gt 0) {
                    $errorMsg = "Errors: "
                    $maxErrors = [Math]::Min(3, $result.errors.Count)
                    for ($i = 0; $i -lt $maxErrors; $i++) {
                        $error = $result.errors[$i]
                        $errorMsg += "$($error.mapping_name): $($error.error_message). "
                    }
                    if ($result.errors.Count -gt 3) {
                        $errorMsg += "... and $($result.errors.Count - 3) more."
                    }
                    # Log full error details
                    # Write-PmcTuiLog $errorMsg "WARNING"
                }
            }
        } catch {
            $this.SetStatusMessage("Execution failed: $_", "error")
        }
    }
}
