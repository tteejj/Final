# ExcelMappingService.ps1 - Service for managing Excel import profiles and mappings
#
# Provides CRUD operations for Excel mapping profiles
# Each profile contains field mappings (Excel cell -> Project property)
#
# Usage:
#   $service = [ExcelMappingService]::GetInstance()
#   $profile = $service.CreateProfile("My Profile", "Description")
#   $service.AddMapping($profileId, @{ display_name="Name"; excel_cell="A1"; project_property="name" })

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

class ExcelMappingService {
    # === Singleton Instance ===
    static hidden [ExcelMappingService]$_instance = $null
    static hidden [object]$_instanceLock = [object]::new()

    # === Configuration ===
    hidden [string]$_profilesFile
    hidden [string]$_activeProfileId = $null

    # === In-memory cache ===
    hidden [hashtable]$_profilesCache = @{}
    hidden [datetime]$_cacheLoadTime = [datetime]::MinValue

    # === Event Callbacks ===
    [scriptblock]$OnProfileAdded = {}
    [scriptblock]$OnProfileUpdated = {}
    [scriptblock]$OnProfileDeleted = {}
    [scriptblock]$OnProfilesChanged = {}

    # === Singleton Access ===
    static [ExcelMappingService] GetInstance() {
        if ([ExcelMappingService]::_instance -eq $null) {
            [System.Threading.Monitor]::Enter([ExcelMappingService]::_instanceLock)
            try {
                if ([ExcelMappingService]::_instance -eq $null) {
                    [ExcelMappingService]::_instance = [ExcelMappingService]::new()
                }
            } finally {
                [System.Threading.Monitor]::Exit([ExcelMappingService]::_instanceLock)
            }
        }
        return [ExcelMappingService]::_instance
    }

    # === Constructor (Private - use GetInstance) ===
    ExcelMappingService() {
        # Determine profiles file location
        # FIXED: Point to the actual location found in user's home directory
        $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        $this._profilesFile = Join-Path $root 'Data/excel-mappings.json'

        # Load profiles
        $this.LoadProfiles()
    }

    # === Profile Management ===
    hidden [void] LoadProfiles() {
        # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: START - file=$($this._profilesFile)" "DEBUG"
        if (Test-Path $this._profilesFile) {
            # CRITICAL FIX ES-C3: Robust JSON parsing with null validation
            try {
                $jsonContent = Get-Content $this._profilesFile -Raw -ErrorAction Stop
                # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: Read $($jsonContent.Length) chars from file" "DEBUG"
                $json = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: JSON parsed successfully" "DEBUG"

                if ($null -eq $json) {
                    throw "JSON deserialization returned null"
                }

                # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: Checking for active_profile_id property" "DEBUG"
                if (-not $json.PSObject.Properties['active_profile_id']) {
                    throw "JSON missing 'active_profile_id' property"
                }
                $this._profilesCache = @{}
                $this._activeProfileId = $json.active_profile_id
                # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: active_profile_id=$($this._activeProfileId)" "DEBUG"

                # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: Found $($json.profiles.Count) profiles" "DEBUG"
                foreach ($profile in $json.profiles) {
                    # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: Processing profile id=$($profile.id) name=$($profile.name)" "DEBUG"

                    # Check for start_cell
                    if (-not $profile.PSObject.Properties['start_cell']) {
                        throw "Profile '$($profile.id)' missing 'start_cell' property"
                    }

                    $mappings = @()
                    # Check if mappings property exists and is not null - JSON deserialization can omit empty arrays
                    if ($profile.PSObject.Properties['mappings'] -and $null -ne $profile.mappings) {
                        # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: Profile has $($profile.mappings.Count) mappings" "DEBUG"
                        foreach ($mapping in $profile.mappings) {
                            # ES-M4 FIX: Type validation before casting JSON booleans
                            $requiredValue = $false
                            if ($mapping.PSObject.Properties['required']) {
                                try {
                                    $requiredValue = [bool]$mapping.required
                                } catch {
                                    # Write-PmcTuiLog "Invalid 'required' value for mapping $($mapping.id), defaulting to false: $_" "WARN"
                                }
                            }

                            $includeInExportValue = $true
                            if ($mapping.PSObject.Properties['include_in_export']) {
                                try {
                                    $includeInExportValue = [bool]$mapping.include_in_export
                                } catch {
                                    # Write-PmcTuiLog "Invalid 'include_in_export' value for mapping $($mapping.id), defaulting to true: $_" "WARN"
                                }
                            }

                            $sortOrderValue = 0
                            if ($mapping.PSObject.Properties['sort_order']) {
                                try {
                                    $sortOrderValue = [int]$mapping.sort_order
                                } catch {
                                    # Write-PmcTuiLog "Invalid 'sort_order' value for mapping $($mapping.id), defaulting to 0: $_" "WARN"
                                }
                            }

                            # Force type conversion for boolean and int values from JSON
                            $mappings += @{
                                id = $mapping.id
                                display_name = $mapping.display_name
                                excel_cell = $mapping.excel_cell
                                project_property = $mapping.project_property
                                required = $requiredValue
                                data_type = $mapping.data_type
                                include_in_export = $includeInExportValue
                                sort_order = $sortOrderValue
                            }
                        }
                    }

                    # Parse datetime with error handling
                    try {
                        $created = [datetime]::Parse($profile.created)
                    } catch {
                        # Write-PmcTuiLog "Failed to parse created date for profile $($profile.id), using current time: $_" "WARN"
                        $created = [datetime]::Now
                    }

                    try {
                        $modified = [datetime]::Parse($profile.modified)
                    } catch {
                        # Write-PmcTuiLog "Failed to parse modified date for profile $($profile.id), using current time: $_" "WARN"
                        $modified = [datetime]::Now
                    }

                    $this._profilesCache[$profile.id] = @{
                        id = $profile.id
                        name = $profile.name
                        description = $profile.description
                        start_cell = $profile.start_cell
                        mappings = $mappings
                        created = $created
                        modified = $modified
                    }
                    # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: Cached profile id=$($profile.id) with $($mappings.Count) mappings" "DEBUG"
                }
                $this._cacheLoadTime = [datetime]::Now
                # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: SUCCESS - loaded $($this._profilesCache.Count) profiles" "DEBUG"
            } catch {
                # Write-PmcTuiLog "Failed to load Excel profiles: $_" "ERROR"
                # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: STACK TRACE: $($_.ScriptStackTrace)" "ERROR"
                $this._profilesCache = @{}
            }
        } else {
            # Write-PmcTuiLog "ExcelMappingService.LoadProfiles: File not found: $($this._profilesFile)" "WARN"
        }
    }

    hidden [void] SaveProfiles() {
        try {
            $profiles = $this._profilesCache.Values | ForEach-Object {
                $mappings = @()
                foreach ($mapping in $_.mappings) {
                    $mappings += @{
                        id = $mapping.id
                        display_name = $mapping.display_name
                        excel_cell = $mapping.excel_cell
                        project_property = $mapping.project_property
                        required = $mapping.required
                        data_type = $mapping.data_type
                        include_in_export = $mapping.include_in_export
                        sort_order = $mapping.sort_order
                    }
                }

                @{
                    id = $_.id
                    name = $_.name
                    description = $_.description
                    start_cell = $_.start_cell
                    mappings = $mappings
                    created = $_.created.ToString("o")
                    modified = $_.modified.ToString("o")
                }
            }

            $metadata = @{
                schema_version = 1
                active_profile_id = $this._activeProfileId
                profiles = $profiles
            }

            # ES-H6 FIX: Atomic save with proper cleanup of temp file on failure
            $tempFile = "$($this._profilesFile).tmp"
            $metadata | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding utf8

            try {
                if (Test-Path $this._profilesFile) {
                    Copy-Item $this._profilesFile "$($this._profilesFile).bak" -Force
                }

                Move-Item -Path $tempFile -Destination $this._profilesFile -Force
            } catch {
                # Clean up orphaned temp file if move fails
                if (Test-Path $tempFile) {
                    try {
                        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                    } catch {
                        # Write-PmcTuiLog "Failed to clean up temp file $tempFile : $_" "WARNING"
                    }
                }
                throw
            }

        } catch {
            # Write-PmcTuiLog "Failed to save Excel profiles: $_" "ERROR"
            # Write-PmcTuiLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
            throw "Failed to save profiles: $($_.Exception.Message)"
        }
    }

    # === Profile CRUD Operations ===

    [array] GetAllProfiles() {
        return @($this._profilesCache.Values | Sort-Object -Property name)
    }

    [object] GetProfile([string]$profileId) {
        if ($this._profilesCache.ContainsKey($profileId)) {
            return $this._profilesCache[$profileId]
        }
        return $null
    }

    [object] GetActiveProfile() {
        if ($null -ne $this._activeProfileId -and $this._profilesCache.ContainsKey($this._activeProfileId)) {
            return $this._profilesCache[$this._activeProfileId]
        }
        return $null
    }

    [void] SetActiveProfile([string]$profileId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $this._activeProfileId = $profileId
        $this.SaveProfiles()

        if ($this.OnProfilesChanged) {
            & $this.OnProfilesChanged
        }
    }

    [object] CreateProfile([string]$name, [string]$description) {
        return $this.CreateProfile($name, $description, "A1")
    }

    [object] CreateProfile([string]$name, [string]$description, [string]$startCell) {
        # ES-H3 FIX: Check for duplicate name with proper count validation
        $existing = @($this._profilesCache.Values | Where-Object { $_['name'] -eq $name })
        if ($existing.Count -gt 0) {
            throw "Profile with name '$name' already exists"
        }

        $profileId = [guid]::NewGuid().ToString()

        $profile = @{
            id = $profileId
            name = $name
            description = $description
            start_cell = $startCell
            mappings = @()
            created = [datetime]::Now
            modified = [datetime]::Now
        }

        $this._profilesCache[$profileId] = $profile

        # Set as active if this is the first profile
        if ($this._profilesCache.Count -eq 1) {
            $this._activeProfileId = $profileId
        }

        $this.SaveProfiles()

        if ($this.OnProfileAdded) {
            & $this.OnProfileAdded $profile
        }
        if ($this.OnProfilesChanged) {
            & $this.OnProfilesChanged
        }

        return $profile
    }

    [void] UpdateProfile([string]$profileId, [hashtable]$changes) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]

        # Check for duplicate name if name is being changed
        if ($changes.ContainsKey('name') -and $changes.name -ne $profile['name']) {
            # ES-M7 FIX: Validate Where-Object returns expected result count
            $existing = @($this._profilesCache.Values | Where-Object { $_['name'] -eq $changes.name -and $_['id'] -ne $profileId })
            if ($existing.Count -gt 0) {
                throw "Profile with name '$($changes.name)' already exists"
            }
        }

        if ($changes.ContainsKey('name')) { $profile.name = $changes.name }
        if ($changes.ContainsKey('description')) { $profile.description = $changes.description }
        if ($changes.ContainsKey('start_cell')) { $profile.start_cell = $changes.start_cell }

        $profile.modified = [datetime]::Now

        $this.SaveProfiles()

        if ($this.OnProfileUpdated) {
            & $this.OnProfileUpdated $profile
        }
        if ($this.OnProfilesChanged) {
            & $this.OnProfilesChanged
        }
    }

    [void] DeleteProfile([string]$profileId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]
        $this._profilesCache.Remove($profileId)

        # Clear active profile if it was deleted
        if ($this._activeProfileId -eq $profileId) {
            # Set to first remaining profile, or null
            $remaining = $this._profilesCache.Keys
            $this._activeProfileId = $(if ($remaining.Count -gt 0) { $remaining[0] } else { $null })
        }

        $this.SaveProfiles()

        if ($this.OnProfileDeleted) {
            & $this.OnProfileDeleted $profile
        }
        if ($this.OnProfilesChanged) {
            & $this.OnProfilesChanged
        }
    }

    # === Mapping CRUD Operations ===

    [object] AddMapping([string]$profileId, [hashtable]$mappingData) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]
        $mappingId = [guid]::NewGuid().ToString()

        # Determine sort order
        $sortOrder = $(if ($mappingData.ContainsKey('sort_order')) {
            $mappingData.sort_order
        } else {
            $profile.mappings.Count + 1
        })

        $mapping = @{
            id = $mappingId
            display_name = $mappingData.display_name
            excel_cell = $mappingData.excel_cell
            project_property = $mappingData.project_property
            required = $(if ($mappingData.ContainsKey('required')) { $mappingData.required } else { $false })
            data_type = $(if ($mappingData.ContainsKey('data_type')) { $mappingData.data_type } else { "string" })
            include_in_export = $(if ($mappingData.ContainsKey('include_in_export')) { $mappingData.include_in_export } else { $true })
            sort_order = $sortOrder
        }

        $profile.mappings += $mapping
        $profile.modified = [datetime]::Now

        $this.SaveProfiles()

        if ($this.OnProfileUpdated) {
            & $this.OnProfileUpdated $profile
        }
        if ($this.OnProfilesChanged) {
            & $this.OnProfilesChanged
        }

        return $mapping
    }

    [void] UpdateMapping([string]$profileId, [string]$mappingId, [hashtable]$changes) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]
        # ES-M7 FIX: Validate Where-Object returns exactly one result
        $matchingMappings = @($profile.mappings | Where-Object { $_.id -eq $mappingId })
        if ($matchingMappings.Count -eq 0) {
            throw "Mapping not found: $mappingId"
        }
        if ($matchingMappings.Count -gt 1) {
            # Write-PmcTuiLog "WARNING: Multiple mappings found with ID $mappingId in profile $profileId. Using first match." "WARN"
        }
        $mapping = $matchingMappings[0]

        if ($changes.ContainsKey('display_name')) { $mapping.display_name = $changes.display_name }
        if ($changes.ContainsKey('excel_cell')) { $mapping.excel_cell = $changes.excel_cell }
        if ($changes.ContainsKey('project_property')) { $mapping.project_property = $changes.project_property }
        if ($changes.ContainsKey('required')) { $mapping.required = $changes.required }
        if ($changes.ContainsKey('data_type')) { $mapping.data_type = $changes.data_type }
        if ($changes.ContainsKey('include_in_export')) { $mapping.include_in_export = $changes.include_in_export }
        if ($changes.ContainsKey('sort_order')) { $mapping.sort_order = $changes.sort_order }

        $profile.modified = [datetime]::Now

        $this.SaveProfiles()

        if ($this.OnProfileUpdated) {
            & $this.OnProfileUpdated $profile
        }
        if ($this.OnProfilesChanged) {
            & $this.OnProfilesChanged
        }
    }

    [void] DeleteMapping([string]$profileId, [string]$mappingId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]
        # @() wrapper ensures array type even with 0 or 1 results
        $profile.mappings = @($profile.mappings | Where-Object { $_.id -ne $mappingId })
        $profile.modified = [datetime]::Now

        $this.SaveProfiles()

        if ($this.OnProfileUpdated) {
            & $this.OnProfileUpdated $profile
        }
        if ($this.OnProfilesChanged) {
            & $this.OnProfilesChanged
        }
    }

    [array] GetMappings([string]$profileId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            return @()
        }

        $profile = $this._profilesCache[$profileId]
        return @($profile.mappings | Sort-Object -Property sort_order)
    }
}