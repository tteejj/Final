# FieldMappingService.ps1 - Manages Excel-to-Project field mapping profiles
# Ported from OLDTUI's ExcelMappingService for V3

using namespace System.Collections.Generic

class FieldMappingService {
    hidden [string]$_profilesFile
    hidden [hashtable]$_profilesCache = @{}
    hidden [string]$_activeProfileId = $null

    # Singleton pattern
    static hidden [FieldMappingService]$_instance = $null

    static [FieldMappingService] GetInstance([string]$dataDir) {
        if ([FieldMappingService]::_instance -eq $null) {
            [FieldMappingService]::_instance = [FieldMappingService]::new($dataDir)
        }
        return [FieldMappingService]::_instance
    }

    FieldMappingService([string]$dataDir) {
        $this._profilesFile = Join-Path $dataDir "field-mappings.json"
        $this.LoadProfiles()
    }

    # === Profile Loading ===
    hidden [void] LoadProfiles() {
        if (-not (Test-Path $this._profilesFile)) {
            # Create default profile with common mappings
            $this._CreateDefaultProfile()
            return
        }

        try {
            $json = Get-Content $this._profilesFile -Raw | ConvertFrom-Json

            if ($json.PSObject.Properties['active_profile_id']) {
                $this._activeProfileId = $json.active_profile_id
            }

            $this._profilesCache = @{}

            if ($json.PSObject.Properties['profiles'] -and $json.profiles) {
                foreach ($profile in $json.profiles) {
                    $mappings = @()
                    if ($profile.PSObject.Properties['mappings'] -and $profile.mappings) {
                        foreach ($m in $profile.mappings) {
                            $mappings += @{
                                id = $m.id
                                display_name = $m.display_name
                                excel_cell = $m.excel_cell
                                excel_sheet = if ($m.PSObject.Properties['excel_sheet']) { $m.excel_sheet } else { "Sheet1" }
                                project_property = $m.project_property
                                include_in_export = if ($m.PSObject.Properties['include_in_export']) { $m.include_in_export } else { $true }
                                sort_order = if ($m.PSObject.Properties['sort_order']) { [int]$m.sort_order } else { 0 }
                            }
                        }
                    }

                    $this._profilesCache[$profile.id] = @{
                        id = $profile.id
                        name = $profile.name
                        description = $profile.description
                        source_field = if ($profile.PSObject.Properties['source_field']) { $profile.source_field } else { "CAAName" }
                        mappings = $mappings
                    }
                }
            }

            [Logger]::Log("FieldMappingService: Loaded $($this._profilesCache.Count) profiles")

        } catch {
            [Logger]::Log("FieldMappingService: Error loading profiles - $($_.Exception.Message)")
            $this._CreateDefaultProfile()
        }
    }

    hidden [void] _CreateDefaultProfile() {
        $profileId = [DataService]::NewGuid()

        # Default mappings matching the 57 fields from ProjectInfoScreenV4
        $defaultMappings = @(
            # Identity (from CAA cells - adjust cell refs as needed)
            @{ display_name = "Project ID"; excel_cell = "B3"; project_property = "ID1"; sort_order = 1 }
            @{ display_name = "Secondary ID"; excel_cell = "B4"; project_property = "ID2"; sort_order = 2 }
            @{ display_name = "Project Name"; excel_cell = "B5"; project_property = "name"; sort_order = 3 }
            @{ display_name = "Description"; excel_cell = "B6"; project_property = "description"; sort_order = 4 }

            # Request
            @{ display_name = "Request Type"; excel_cell = "B8"; project_property = "RequestType"; sort_order = 5 }
            @{ display_name = "Priority"; excel_cell = "B9"; project_property = "Priority"; sort_order = 6 }
            @{ display_name = "Status"; excel_cell = "B10"; project_property = "status"; sort_order = 7 }
            @{ display_name = "Due Date"; excel_cell = "B11"; project_property = "DueDate"; sort_order = 8 }
            @{ display_name = "BF Date"; excel_cell = "B12"; project_property = "BFDate"; sort_order = 9 }
            @{ display_name = "Request Date"; excel_cell = "B13"; project_property = "RequestDate"; sort_order = 10 }

            # Audit
            @{ display_name = "Audit Type"; excel_cell = "B15"; project_property = "AuditType"; sort_order = 11 }
            @{ display_name = "Auditor Name"; excel_cell = "B16"; project_property = "AuditorName"; sort_order = 12 }
            @{ display_name = "Auditor Phone"; excel_cell = "B17"; project_property = "AuditorPhone"; sort_order = 13 }
            @{ display_name = "Auditor TL"; excel_cell = "B18"; project_property = "AuditorTL"; sort_order = 14 }
            @{ display_name = "TL Phone"; excel_cell = "B19"; project_property = "AuditorTLPhone"; sort_order = 15 }
            @{ display_name = "Audit Case"; excel_cell = "B20"; project_property = "AuditCase"; sort_order = 16 }
            @{ display_name = "CAS Case"; excel_cell = "B21"; project_property = "CASCase"; sort_order = 17 }
            @{ display_name = "Audit Start Date"; excel_cell = "B22"; project_property = "AuditStartDate"; sort_order = 18 }

            # Location
            @{ display_name = "Third Party Name"; excel_cell = "B24"; project_property = "TPName"; sort_order = 19 }
            @{ display_name = "Third Party Number"; excel_cell = "B25"; project_property = "TPNum"; sort_order = 20 }
            @{ display_name = "Address"; excel_cell = "B26"; project_property = "Address"; sort_order = 21 }
            @{ display_name = "City"; excel_cell = "B27"; project_property = "City"; sort_order = 22 }
            @{ display_name = "Province"; excel_cell = "B28"; project_property = "Province"; sort_order = 23 }
            @{ display_name = "Postal Code"; excel_cell = "B29"; project_property = "PostalCode"; sort_order = 24 }
            @{ display_name = "Country"; excel_cell = "B30"; project_property = "Country"; sort_order = 25 }

            # Periods
            @{ display_name = "Audit Period From"; excel_cell = "B32"; project_property = "AuditPeriodFrom"; sort_order = 26 }
            @{ display_name = "Audit Period To"; excel_cell = "B33"; project_property = "AuditPeriodTo"; sort_order = 27 }

            # Contacts
            @{ display_name = "Contact 1 Name"; excel_cell = "B35"; project_property = "Contact1Name"; sort_order = 28 }
            @{ display_name = "Contact 1 Title"; excel_cell = "B36"; project_property = "Contact1Title"; sort_order = 29 }
            @{ display_name = "Contact 1 Phone"; excel_cell = "B37"; project_property = "Contact1Phone"; sort_order = 30 }
            @{ display_name = "Contact 1 Email"; excel_cell = "B38"; project_property = "Contact1Email"; sort_order = 31 }
            @{ display_name = "Contact 2 Name"; excel_cell = "B40"; project_property = "Contact2Name"; sort_order = 32 }
            @{ display_name = "Contact 2 Title"; excel_cell = "B41"; project_property = "Contact2Title"; sort_order = 33 }
            @{ display_name = "Contact 2 Phone"; excel_cell = "B42"; project_property = "Contact2Phone"; sort_order = 34 }
            @{ display_name = "Contact 2 Email"; excel_cell = "B43"; project_property = "Contact2Email"; sort_order = 35 }
        )

        # Add IDs and defaults to each mapping
        $mappingsWithIds = @()
        foreach ($m in $defaultMappings) {
            $mappingsWithIds += @{
                id = [DataService]::NewGuid()
                display_name = $m.display_name
                excel_cell = $m.excel_cell
                excel_sheet = "Sheet1"
                project_property = $m.project_property
                include_in_export = $true
                sort_order = $m.sort_order
            }
        }

        $this._profilesCache[$profileId] = @{
            id = $profileId
            name = "Default CAA Import"
            description = "Standard CAA file field mappings"
            source_field = "CAAName"
            mappings = $mappingsWithIds
        }

        $this._activeProfileId = $profileId
        $this.SaveProfiles()

        [Logger]::Log("FieldMappingService: Created default profile with $($mappingsWithIds.Count) mappings")
    }

    # === Profile Save ===
    hidden [void] SaveProfiles() {
        try {
            $dir = Split-Path $this._profilesFile -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }

            $output = @{
                schema_version = 1
                active_profile_id = $this._activeProfileId
                profiles = @($this._profilesCache.Values)
            }

            $output | ConvertTo-Json -Depth 10 | Set-Content -Path $this._profilesFile -Encoding utf8

        } catch {
            [Logger]::Log("FieldMappingService: Error saving profiles - $($_.Exception.Message)")
        }
    }

    # === Profile CRUD ===
    [array] GetAllProfiles() {
        return @($this._profilesCache.Values | Sort-Object { $_.name })
    }

    [object] GetProfile([string]$profileId) {
        if ($this._profilesCache.ContainsKey($profileId)) {
            return $this._profilesCache[$profileId]
        }
        return $null
    }

    [object] GetActiveProfile() {
        if ($this._activeProfileId -and $this._profilesCache.ContainsKey($this._activeProfileId)) {
            return $this._profilesCache[$this._activeProfileId]
        }
        # Return first profile if no active
        if ($this._profilesCache.Count -gt 0) {
            return $this._profilesCache.Values | Select-Object -First 1
        }
        return $null
    }

    [void] SetActiveProfile([string]$profileId) {
        if ($this._profilesCache.ContainsKey($profileId)) {
            $this._activeProfileId = $profileId
            $this.SaveProfiles()
        }
    }

    [object] CreateProfile([string]$name, [string]$description, [string]$sourceField) {
        $profileId = [DataService]::NewGuid()

        $profile = @{
            id = $profileId
            name = $name
            description = $description
            source_field = $sourceField
            mappings = @()
        }

        $this._profilesCache[$profileId] = $profile
        $this.SaveProfiles()

        return $profile
    }

    [void] DeleteProfile([string]$profileId) {
        if ($this._profilesCache.ContainsKey($profileId)) {
            $this._profilesCache.Remove($profileId)

            if ($this._activeProfileId -eq $profileId) {
                $remaining = $this._profilesCache.Keys
                $this._activeProfileId = if ($remaining.Count -gt 0) { $remaining[0] } else { $null }
            }

            $this.SaveProfiles()
        }
    }

    # === Mapping CRUD ===
    [object] AddMapping([string]$profileId, [hashtable]$mappingData) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]

        $mapping = @{
            id = [DataService]::NewGuid()
            display_name = $mappingData.display_name
            excel_cell = $mappingData.excel_cell
            excel_sheet = if ($mappingData.ContainsKey('excel_sheet')) { $mappingData.excel_sheet } else { "Sheet1" }
            project_property = $mappingData.project_property
            include_in_export = if ($mappingData.ContainsKey('include_in_export')) { $mappingData.include_in_export } else { $true }
            sort_order = if ($mappingData.ContainsKey('sort_order')) { $mappingData.sort_order } else { $profile.mappings.Count + 1 }
        }

        $profile.mappings += $mapping
        $this.SaveProfiles()

        return $mapping
    }

    [void] UpdateMapping([string]$profileId, [string]$mappingId, [hashtable]$changes) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]
        $mapping = $profile.mappings | Where-Object { $_.id -eq $mappingId } | Select-Object -First 1

        if ($mapping) {
            if ($changes.ContainsKey('display_name')) { $mapping.display_name = $changes.display_name }
            if ($changes.ContainsKey('excel_cell')) { $mapping.excel_cell = $changes.excel_cell }
            if ($changes.ContainsKey('excel_sheet')) { $mapping.excel_sheet = $changes.excel_sheet }
            if ($changes.ContainsKey('project_property')) { $mapping.project_property = $changes.project_property }
            if ($changes.ContainsKey('include_in_export')) { $mapping.include_in_export = $changes.include_in_export }
            if ($changes.ContainsKey('sort_order')) { $mapping.sort_order = $changes.sort_order }

            $this.SaveProfiles()
        }
    }

    [void] DeleteMapping([string]$profileId, [string]$mappingId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]
        $profile.mappings = @($profile.mappings | Where-Object { $_.id -ne $mappingId })
        $this.SaveProfiles()
    }

    [array] GetMappings([string]$profileId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            return @()
        }

        $profile = $this._profilesCache[$profileId]
        return @($profile.mappings | Sort-Object { $_.sort_order })
    }

    # === Get available project fields (for mapping editor) ===
    [array] GetProjectFields() {
        return @(
            @{ name = 'ID1'; label = 'Project ID' }
            @{ name = 'ID2'; label = 'Secondary ID' }
            @{ name = 'name'; label = 'Project Name' }
            @{ name = 'description'; label = 'Description' }
            @{ name = 'RequestType'; label = 'Request Type' }
            @{ name = 'Priority'; label = 'Priority' }
            @{ name = 'status'; label = 'Status' }
            @{ name = 'DueDate'; label = 'Due Date' }
            @{ name = 'BFDate'; label = 'BF Date' }
            @{ name = 'RequestDate'; label = 'Request Date' }
            @{ name = 'AuditType'; label = 'Audit Type' }
            @{ name = 'AuditorName'; label = 'Auditor Name' }
            @{ name = 'AuditorPhone'; label = 'Auditor Phone' }
            @{ name = 'AuditorTL'; label = 'Auditor Team Lead' }
            @{ name = 'AuditorTLPhone'; label = 'TL Phone' }
            @{ name = 'AuditCase'; label = 'Audit Case' }
            @{ name = 'CASCase'; label = 'CAS Case' }
            @{ name = 'AuditStartDate'; label = 'Audit Start Date' }
            @{ name = 'TPName'; label = 'Third Party Name' }
            @{ name = 'TPNum'; label = 'Third Party Number' }
            @{ name = 'Address'; label = 'Address' }
            @{ name = 'City'; label = 'City' }
            @{ name = 'Province'; label = 'Province' }
            @{ name = 'PostalCode'; label = 'Postal Code' }
            @{ name = 'Country'; label = 'Country' }
            @{ name = 'AuditPeriodFrom'; label = 'Audit Period From' }
            @{ name = 'AuditPeriodTo'; label = 'Audit Period To' }
            @{ name = 'Period1Start'; label = 'Period 1 Start' }
            @{ name = 'Period1End'; label = 'Period 1 End' }
            @{ name = 'Period2Start'; label = 'Period 2 Start' }
            @{ name = 'Period2End'; label = 'Period 2 End' }
            @{ name = 'Period3Start'; label = 'Period 3 Start' }
            @{ name = 'Period3End'; label = 'Period 3 End' }
            @{ name = 'Period4Start'; label = 'Period 4 Start' }
            @{ name = 'Period4End'; label = 'Period 4 End' }
            @{ name = 'Period5Start'; label = 'Period 5 Start' }
            @{ name = 'Period5End'; label = 'Period 5 End' }
            @{ name = 'Contact1Name'; label = 'Contact 1 Name' }
            @{ name = 'Contact1Title'; label = 'Contact 1 Title' }
            @{ name = 'Contact1Phone'; label = 'Contact 1 Phone' }
            @{ name = 'Contact1Email'; label = 'Contact 1 Email' }
            @{ name = 'Contact1Fax'; label = 'Contact 1 Fax' }
            @{ name = 'Contact2Name'; label = 'Contact 2 Name' }
            @{ name = 'Contact2Title'; label = 'Contact 2 Title' }
            @{ name = 'Contact2Phone'; label = 'Contact 2 Phone' }
            @{ name = 'Contact2Email'; label = 'Contact 2 Email' }
            @{ name = 'Contact2Fax'; label = 'Contact 2 Fax' }
            @{ name = 'Software1Name'; label = 'Software 1' }
            @{ name = 'Software1Version'; label = 'Software 1 Version' }
            @{ name = 'Software2Name'; label = 'Software 2' }
            @{ name = 'Software2Version'; label = 'Software 2 Version' }
            @{ name = 'AuditProgram'; label = 'Audit Program' }
            @{ name = 'Comments'; label = 'Comments' }
            @{ name = 'FXInfo'; label = 'FX Info' }
            @{ name = 'ShipToAddress'; label = 'Ship To Address' }
        )
    }
}
