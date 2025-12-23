# ExcelCopyService.ps1 - Service for managing Excel-to-Excel copy profiles and mappings
#
# Provides CRUD operations for Excel copy profiles
# Each profile contains cell mappings (source sheet/cell -> dest sheet/cell)
#
# Usage:
#   $service = [ExcelCopyService]::GetInstance()
#   $profile = $service.CreateProfile("My Profile", "Description", "/path/to/source.xlsx", "/path/to/dest.xlsx")
#   $service.AddMapping($profileId, @{ name="Field1"; source_sheet="Sheet1"; source_cell="A1"; dest_sheet="Output"; dest_cell="B2" })

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

. "$PSScriptRoot/ExcelComReader.ps1"

class ExcelCopyService {
    # === Singleton Instance ===
    static hidden [ExcelCopyService]$_instance = $null
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
    static [ExcelCopyService] GetInstance() {
        if ([ExcelCopyService]::_instance -eq $null) {
            [System.Threading.Monitor]::Enter([ExcelCopyService]::_instanceLock)
            try {
                if ([ExcelCopyService]::_instance -eq $null) {
                    [ExcelCopyService]::_instance = [ExcelCopyService]::new()
                }
            } finally {
                [System.Threading.Monitor]::Exit([ExcelCopyService]::_instanceLock)
            }
        }
        return [ExcelCopyService]::_instance
    }

    # === Constructor (Private - use GetInstance) ===
    ExcelCopyService() {
        # Determine profiles file location
        $this._profilesFile = "/home/teej/_tui/praxis-main/simpletaskpro/Data/excel-copy-profiles.json"

        # Load profiles
        $this.LoadProfiles()
    }

    # === Profile Management ===
    hidden [void] LoadProfiles() {
        if (Test-Path $this._profilesFile) {
            try {
                $jsonContent = Get-Content $this._profilesFile -Raw -ErrorAction Stop
                $json = $jsonContent | ConvertFrom-Json -ErrorAction Stop

                if ($null -eq $json) {
                    throw "JSON deserialization returned null"
                }

                if (-not $json.PSObject.Properties['active_profile_id']) {
                    throw "JSON missing 'active_profile_id' property"
                }
                $this._profilesCache = @{}
                $this._activeProfileId = $json.active_profile_id

                foreach ($profile in $json.profiles) {
                    $mappings = @()
                    if ($profile.PSObject.Properties['mappings'] -and $null -ne $profile.mappings) {
                        foreach ($mapping in $profile.mappings) {
                            $sortOrderValue = 0
                            if ($mapping.PSObject.Properties['sort_order']) {
                                try {
                                    $sortOrderValue = [int]$mapping.sort_order
                                } catch { }
                            }

                            $mappings += @{
                                id = $mapping.id
                                name = $mapping.name
                                source_sheet = $mapping.source_sheet
                                source_cell = $mapping.source_cell
                                dest_sheet = $mapping.dest_sheet
                                dest_cell = $mapping.dest_cell
                                sort_order = $sortOrderValue
                            }
                        }
                    }

                    # Parse datetime with error handling
                    try {
                        $created = [datetime]::Parse($profile.created)
                    } catch {
                        $created = [datetime]::Now
                    }

                    try {
                        $modified = [datetime]::Parse($profile.modified)
                    } catch {
                        $modified = [datetime]::Now
                    }

                    $this._profilesCache[$profile.id] = @{
                        id = $profile.id
                        name = $profile.name
                        description = $profile.description
                        source_workbook_path = $profile.source_workbook_path
                        dest_workbook_path = $profile.dest_workbook_path
                        mappings = $mappings
                        created = $created
                        modified = $modified
                    }
                }
                $this._cacheLoadTime = [datetime]::Now
            } catch {
                $this._profilesCache = @{}
            }
        }
    }

    hidden [void] SaveProfiles() {
        try {
            # Ensure directory exists
            $dir = Split-Path $this._profilesFile -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }

            $profiles = $this._profilesCache.Values | ForEach-Object {
                $mappings = @()
                foreach ($mapping in $_.mappings) {
                    $mappings += @{
                        id = $mapping.id
                        name = $mapping.name
                        source_sheet = $mapping.source_sheet
                        source_cell = $mapping.source_cell
                        dest_sheet = $mapping.dest_sheet
                        dest_cell = $mapping.dest_cell
                        sort_order = $mapping.sort_order
                    }
                }

                @{
                    id = $_.id
                    name = $_.name
                    description = $_.description
                    source_workbook_path = $_.source_workbook_path
                    dest_workbook_path = $_.dest_workbook_path
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

            # Atomic save with temp file
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
                    } catch { }
                }
                throw
            }

        } catch {
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

    [object] CreateProfile([string]$name, [string]$description, [string]$sourceWorkbookPath, [string]$destWorkbookPath) {
        # Check for duplicate name
        $existing = @($this._profilesCache.Values | Where-Object { $_['name'] -eq $name })
        if ($existing.Count -gt 0) {
            throw "Profile with name '$name' already exists"
        }

        $profileId = [guid]::NewGuid().ToString()

        $profile = @{
            id = $profileId
            name = $name
            description = $description
            source_workbook_path = $sourceWorkbookPath
            dest_workbook_path = $destWorkbookPath
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
            $existing = @($this._profilesCache.Values | Where-Object { $_['name'] -eq $changes.name -and $_['id'] -ne $profileId })
            if ($existing.Count -gt 0) {
                throw "Profile with name '$($changes.name)' already exists"
            }
        }

        if ($changes.ContainsKey('name')) { $profile.name = $changes.name }
        if ($changes.ContainsKey('description')) { $profile.description = $changes.description }
        if ($changes.ContainsKey('source_workbook_path')) { $profile.source_workbook_path = $changes.source_workbook_path }
        if ($changes.ContainsKey('dest_workbook_path')) { $profile.dest_workbook_path = $changes.dest_workbook_path }

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
            name = $mappingData.name
            source_sheet = $mappingData.source_sheet
            source_cell = $mappingData.source_cell
            dest_sheet = $mappingData.dest_sheet
            dest_cell = $mappingData.dest_cell
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
        $matchingMappings = @($profile.mappings | Where-Object { $_.id -eq $mappingId })
        if ($matchingMappings.Count -eq 0) {
            throw "Mapping not found: $mappingId"
        }
        $mapping = $matchingMappings[0]

        if ($changes.ContainsKey('name')) { $mapping.name = $changes.name }
        if ($changes.ContainsKey('source_sheet')) { $mapping.source_sheet = $changes.source_sheet }
        if ($changes.ContainsKey('source_cell')) { $mapping.source_cell = $changes.source_cell }
        if ($changes.ContainsKey('dest_sheet')) { $mapping.dest_sheet = $changes.dest_sheet }
        if ($changes.ContainsKey('dest_cell')) { $mapping.dest_cell = $changes.dest_cell }
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

    # === Sheet Discovery ===

    [array] GetSourceSheets([string]$profileId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            return @()
        }

        $profile = $this._profilesCache[$profileId]
        if ([string]::IsNullOrWhiteSpace($profile.source_workbook_path)) {
            return @()
        }

        if (-not (Test-Path $profile.source_workbook_path)) {
            throw "Source workbook not found: $($profile.source_workbook_path)"
        }

        $reader = [ExcelComReader]::new()
        try {
            $reader.OpenFile($profile.source_workbook_path)
            return $reader.GetSheetNames()
        } finally {
            $reader.Close()
        }
    }

    [array] GetDestSheets([string]$profileId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            return @()
        }

        $profile = $this._profilesCache[$profileId]
        if ([string]::IsNullOrWhiteSpace($profile.dest_workbook_path)) {
            return @()
        }

        if (-not (Test-Path $profile.dest_workbook_path)) {
            throw "Destination workbook not found: $($profile.dest_workbook_path)"
        }

        $reader = [ExcelComReader]::new()
        try {
            $reader.OpenFile($profile.dest_workbook_path)
            return $reader.GetSheetNames()
        } finally {
            $reader.Close()
        }
    }

    # === Execution Engine ===

    [object] ExecuteCopy([string]$profileId) {
        $profile = $this.GetProfile($profileId)
        if ($null -eq $profile) {
            throw "Profile not found: $profileId"
        }

        $result = @{
            profile_id = $profileId
            profile_name = $profile.name
            started = [datetime]::Now
            completed = $null
            total_mappings = $profile.mappings.Count
            successful_mappings = 0
            failed_mappings = 0
            errors = @()
            source_path = $profile.source_workbook_path
            dest_path = $profile.dest_workbook_path
        }

        # Validate workbooks exist
        if (-not (Test-Path $profile.source_workbook_path)) {
            $result.errors += @{
                mapping_name = "N/A"
                error_type = "FileAccess"
                error_message = "Source workbook not found: $($profile.source_workbook_path)"
                timestamp = [datetime]::Now
            }
            $result.completed = [datetime]::Now
            return $result
        }

        if (-not (Test-Path $profile.dest_workbook_path)) {
            $result.errors += @{
                mapping_name = "N/A"
                error_type = "FileAccess"
                error_message = "Destination workbook not found: $($profile.dest_workbook_path)"
                timestamp = [datetime]::Now
            }
            $result.completed = [datetime]::Now
            return $result
        }

        # Create ExcelComReader instances
        $sourceReader = $null
        $destReader = $null

        try {
            $sourceReader = [ExcelComReader]::new()
            $destReader = [ExcelComReader]::new()

            # Open workbooks
            try {
                $sourceReader.OpenFile($profile.source_workbook_path)
            } catch {
                $result.errors += @{
                    mapping_name = "N/A"
                    error_type = "FileAccess"
                    error_message = "Failed to open source workbook: $_"
                    timestamp = [datetime]::Now
                }
                $result.completed = [datetime]::Now
                return $result
            }

            try {
                $destReader.OpenFile($profile.dest_workbook_path)
            } catch {
                $result.errors += @{
                    mapping_name = "N/A"
                    error_type = "FileAccess"
                    error_message = "Failed to open destination workbook: $_"
                    timestamp = [datetime]::Now
                }
                $result.completed = [datetime]::Now
                return $result
            }

            # Process each mapping
            foreach ($mapping in $profile.mappings) {
                $mappingSuccess = $true

                try {
                    # Set source sheet
                    try {
                        $sourceReader.SetActiveSheetByName($mapping.source_sheet)
                    } catch {
                        $result.errors += @{
                            mapping_name = $mapping.name
                            error_type = "SheetNotFound"
                            error_message = "Source sheet not found: $($mapping.source_sheet)"
                            source_sheet = $mapping.source_sheet
                            timestamp = [datetime]::Now
                        }
                        $mappingSuccess = $false
                        continue
                    }

                    # Read source cell
                    $value = $null
                    try {
                        $value = $sourceReader.ReadCell($mapping.source_cell)
                    } catch {
                        $result.errors += @{
                            mapping_name = $mapping.name
                            error_type = "ReadFailed"
                            error_message = "Failed to read cell $($mapping.source_cell): $_"
                            source_sheet = $mapping.source_sheet
                            source_cell = $mapping.source_cell
                            timestamp = [datetime]::Now
                        }
                        $mappingSuccess = $false
                        continue
                    }

                    # Set dest sheet
                    try {
                        $destReader.SetActiveSheetByName($mapping.dest_sheet)
                    } catch {
                        $result.errors += @{
                            mapping_name = $mapping.name
                            error_type = "SheetNotFound"
                            error_message = "Destination sheet not found: $($mapping.dest_sheet)"
                            dest_sheet = $mapping.dest_sheet
                            timestamp = [datetime]::Now
                        }
                        $mappingSuccess = $false
                        continue
                    }

                    # Write dest cell
                    try {
                        $destReader.WriteCell($mapping.dest_cell, $value)
                    } catch {
                        $result.errors += @{
                            mapping_name = $mapping.name
                            error_type = "WriteFailed"
                            error_message = "Failed to write cell $($mapping.dest_cell): $_"
                            dest_sheet = $mapping.dest_sheet
                            dest_cell = $mapping.dest_cell
                            timestamp = [datetime]::Now
                        }
                        $mappingSuccess = $false
                        continue
                    }

                } catch {
                    # Unexpected error
                    $result.errors += @{
                        mapping_name = $mapping.name
                        error_type = "UnexpectedError"
                        error_message = "Unexpected error: $_"
                        timestamp = [datetime]::Now
                    }
                    $mappingSuccess = $false
                }

                if ($mappingSuccess) {
                    $result.successful_mappings++
                } else {
                    $result.failed_mappings++
                }
            }

            # Save destination workbook
            try {
                $destReader.SaveWorkbook()
            } catch {
                $result.errors += @{
                    mapping_name = "N/A"
                    error_type = "SaveFailed"
                    error_message = "Failed to save destination workbook: $_"
                    timestamp = [datetime]::Now
                }
            }

        } finally {
            # Close workbooks
            if ($null -ne $sourceReader) {
                try { $sourceReader.Close() } catch { }
            }
            if ($null -ne $destReader) {
                try { $destReader.Close() } catch { }
            }
        }

        $result.completed = [datetime]::Now
        return $result
    }
}
