# ExcelImportService.ps1 - Service for importing Excel data into Project Info fields
#
# Maps Excel cells to project fields and imports values
# Global profiles - reusable across multiple projects
#
# Usage:
#   $service = [ExcelImportService]::GetInstance()
#   $profile = $service.CreateProfile("CAA Import", "Import from CAA file", "CAAName")
#   $service.AddMapping($profileId, @{ source_sheet="Sheet1"; source_cell="B5"; dest_field="TPName"; name="Third Party" })
#   $result = $service.ExecuteImport($profileId, "MyProject")

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

. "$PSScriptRoot/ExcelComReader.ps1"

class ExcelImportService {
    # === Singleton Instance ===
    static hidden [ExcelImportService]$_instance = $null
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
    static [ExcelImportService] GetInstance() {
        if ([ExcelImportService]::_instance -eq $null) {
            [System.Threading.Monitor]::Enter([ExcelImportService]::_instanceLock)
            try {
                if ([ExcelImportService]::_instance -eq $null) {
                    [ExcelImportService]::_instance = [ExcelImportService]::new()
                }
            } finally {
                [System.Threading.Monitor]::Exit([ExcelImportService]::_instanceLock)
            }
        }
        return [ExcelImportService]::_instance
    }

    # === Constructor ===
    ExcelImportService() {
        # Determine data directory relative to PMC root
        $pmcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $dataDir = Join-Path $pmcRoot "Data"
        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        $this._profilesFile = Join-Path $dataDir "excel-import-profiles.json"
        $this.LoadProfiles()
    }

    # === Profile Management ===
    hidden [void] LoadProfiles() {
        if (Test-Path $this._profilesFile) {
            try {
                $jsonContent = Get-Content $this._profilesFile -Raw -ErrorAction Stop
                $json = $jsonContent | ConvertFrom-Json -ErrorAction Stop

                if ($null -eq $json) { throw "JSON null" }

                $this._profilesCache = @{}
                if ($json.PSObject.Properties['active_profile_id']) {
                    $this._activeProfileId = $json.active_profile_id
                }

                foreach ($profile in $json.profiles) {
                    $mappings = @()
                    if ($profile.PSObject.Properties['mappings'] -and $null -ne $profile.mappings) {
                        foreach ($mapping in $profile.mappings) {
                            $mappings += @{
                                id = $mapping.id
                                name = $mapping.name
                                source_sheet = $mapping.source_sheet
                                source_cell = $mapping.source_cell
                                dest_field = $mapping.dest_field
                                sort_order = $(if ($mapping.PSObject.Properties['sort_order']) { [int]$mapping.sort_order } else { 0 })
                            }
                        }
                    }

                    $this._profilesCache[$profile.id] = @{
                        id = $profile.id
                        name = $profile.name
                        description = $profile.description
                        source_field = $profile.source_field  # Project field containing Excel path
                        mappings = $mappings
                        created = $(try { [datetime]::Parse($profile.created) } catch { [datetime]::Now })
                        modified = $(try { [datetime]::Parse($profile.modified) } catch { [datetime]::Now })
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
                        dest_field = $mapping.dest_field
                        sort_order = $mapping.sort_order
                    }
                }

                @{
                    id = $_.id
                    name = $_.name
                    description = $_.description
                    source_field = $_.source_field
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

            $tempFile = "$($this._profilesFile).tmp"
            $metadata | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding utf8

            if (Test-Path $this._profilesFile) {
                Copy-Item $this._profilesFile "$($this._profilesFile).bak" -Force
            }
            Move-Item -Path $tempFile -Destination $this._profilesFile -Force

        } catch {
            throw "Failed to save profiles: $($_.Exception.Message)"
        }
    }

    # === Profile CRUD ===

    [array] GetAllProfiles() {
        return @($this._profilesCache.Values | Sort-Object -Property name)
    }

    [object] GetProfile([string]$profileId) {
        if ($this._profilesCache.ContainsKey($profileId)) {
            return $this._profilesCache[$profileId]
        }
        return $null
    }

    [object] CreateProfile([string]$name, [string]$description, [string]$sourceField) {
        $existing = @($this._profilesCache.Values | Where-Object { $_['name'] -eq $name })
        if ($existing.Count -gt 0) {
            throw "Profile with name '$name' already exists"
        }

        $profileId = [guid]::NewGuid().ToString()

        $profile = @{
            id = $profileId
            name = $name
            description = $description
            source_field = $sourceField  # e.g., "CAAName", "RequestName"
            mappings = @()
            created = [datetime]::Now
            modified = [datetime]::Now
        }

        $this._profilesCache[$profileId] = $profile

        if ($this._profilesCache.Count -eq 1) {
            $this._activeProfileId = $profileId
        }

        $this.SaveProfiles()

        if ($this.OnProfileAdded) { & $this.OnProfileAdded $profile }
        if ($this.OnProfilesChanged) { & $this.OnProfilesChanged }

        return $profile
    }

    [void] UpdateProfile([string]$profileId, [hashtable]$changes) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]

        if ($changes.ContainsKey('name') -and $changes.name -ne $profile['name']) {
            $existing = @($this._profilesCache.Values | Where-Object { $_['name'] -eq $changes.name -and $_['id'] -ne $profileId })
            if ($existing.Count -gt 0) {
                throw "Profile with name '$($changes.name)' already exists"
            }
        }

        if ($changes.ContainsKey('name')) { $profile.name = $changes.name }
        if ($changes.ContainsKey('description')) { $profile.description = $changes.description }
        if ($changes.ContainsKey('source_field')) { $profile.source_field = $changes.source_field }

        $profile.modified = [datetime]::Now

        $this.SaveProfiles()

        if ($this.OnProfileUpdated) { & $this.OnProfileUpdated $profile }
        if ($this.OnProfilesChanged) { & $this.OnProfilesChanged }
    }

    [void] DeleteProfile([string]$profileId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]
        $this._profilesCache.Remove($profileId)

        if ($this._activeProfileId -eq $profileId) {
            $remaining = $this._profilesCache.Keys
            $this._activeProfileId = $(if ($remaining.Count -gt 0) { $remaining[0] } else { $null })
        }

        $this.SaveProfiles()

        if ($this.OnProfileDeleted) { & $this.OnProfileDeleted $profile }
        if ($this.OnProfilesChanged) { & $this.OnProfilesChanged }
    }

    # === Mapping CRUD ===

    [object] AddMapping([string]$profileId, [hashtable]$mappingData) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]
        $mappingId = [guid]::NewGuid().ToString()

        $mapping = @{
            id = $mappingId
            name = $mappingData.name
            source_sheet = $mappingData.source_sheet
            source_cell = $mappingData.source_cell
            dest_field = $mappingData.dest_field
            sort_order = $(if ($mappingData.ContainsKey('sort_order')) { $mappingData.sort_order } else { $profile.mappings.Count + 1 })
        }

        $profile.mappings += $mapping
        $profile.modified = [datetime]::Now

        $this.SaveProfiles()

        if ($this.OnProfileUpdated) { & $this.OnProfileUpdated $profile }
        if ($this.OnProfilesChanged) { & $this.OnProfilesChanged }

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
        if ($changes.ContainsKey('dest_field')) { $mapping.dest_field = $changes.dest_field }
        if ($changes.ContainsKey('sort_order')) { $mapping.sort_order = $changes.sort_order }

        $profile.modified = [datetime]::Now

        $this.SaveProfiles()

        if ($this.OnProfileUpdated) { & $this.OnProfileUpdated $profile }
        if ($this.OnProfilesChanged) { & $this.OnProfilesChanged }
    }

    [void] DeleteMapping([string]$profileId, [string]$mappingId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            throw "Profile not found: $profileId"
        }

        $profile = $this._profilesCache[$profileId]
        $profile.mappings = @($profile.mappings | Where-Object { $_.id -ne $mappingId })
        $profile.modified = [datetime]::Now

        $this.SaveProfiles()

        if ($this.OnProfileUpdated) { & $this.OnProfileUpdated $profile }
        if ($this.OnProfilesChanged) { & $this.OnProfilesChanged }
    }

    [array] GetMappings([string]$profileId) {
        if (-not $this._profilesCache.ContainsKey($profileId)) {
            return @()
        }
        $profile = $this._profilesCache[$profileId]
        return @($profile.mappings | Sort-Object -Property sort_order)
    }

    # === Get available project fields ===
    [array] GetProjectFields() {
        # Return list of project fields that can be mapped
        return @(
            @{ name = 'ID1'; label = 'Project ID' }
            @{ name = 'ID2'; label = 'Secondary ID' }
            @{ name = 'Name'; label = 'Project Name' }
            @{ name = 'Description'; label = 'Description' }
            @{ name = 'RequestType'; label = 'Request Type' }
            @{ name = 'Priority'; label = 'Priority' }
            @{ name = 'Status'; label = 'Status' }
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
            @{ name = 'Contact1Name'; label = 'Contact 1 Name' }
            @{ name = 'Contact1Title'; label = 'Contact 1 Title' }
            @{ name = 'Contact1Phone'; label = 'Contact 1 Phone' }
            @{ name = 'Contact1Email'; label = 'Contact 1 Email' }
            @{ name = 'Contact2Name'; label = 'Contact 2 Name' }
            @{ name = 'Contact2Title'; label = 'Contact 2 Title' }
            @{ name = 'Contact2Phone'; label = 'Contact 2 Phone' }
            @{ name = 'Contact2Email'; label = 'Contact 2 Email' }
        )
    }

    # === Get source field options (project fields that contain Excel paths) ===
    [array] GetSourceFieldOptions() {
        return @(
            @{ name = 'CAAName'; label = 'CAA File' }
            @{ name = 'RequestName'; label = 'Request File' }
            @{ name = 'T2020'; label = 'T2020 File' }
        )
    }

    # === Sheet Discovery ===
    [array] GetSheetsFromFile([string]$filePath) {
        if ([string]::IsNullOrWhiteSpace($filePath)) { return @() }
        if (-not (Test-Path $filePath)) { throw "File not found: $filePath" }

        $reader = [ExcelComReader]::new()
        try {
            $reader.OpenFile($filePath)
            return $reader.GetSheetNames()
        } finally {
            $reader.Close()
        }
    }

    # === Import Execution ===
    [object] ExecuteImport([string]$profileId, [string]$projectName, [object]$taskStore) {
        $profile = $this.GetProfile($profileId)
        if ($null -eq $profile) {
            throw "Profile not found: $profileId"
        }

        $result = @{
            profile_id = $profileId
            profile_name = $profile.name
            project_name = $projectName
            started = [datetime]::Now
            completed = $null
            total_mappings = $profile.mappings.Count
            successful_imports = 0
            failed_imports = 0
            errors = @()
            imported_values = @{}
        }

        # Get project data to find the Excel source file
        $project = $taskStore.GetProject($projectName)
        if ($null -eq $project) {
            $result.errors += @{
                mapping_name = "N/A"
                error_type = "ProjectNotFound"
                error_message = "Project not found: $projectName"
            }
            $result.completed = [datetime]::Now
            return $result
        }

        # Get Excel file path from the source_field
        $excelPath = $null
        if ($project -is [hashtable]) {
            if ($project.ContainsKey($profile.source_field)) {
                $excelPath = $project[$profile.source_field]
            }
        } elseif ($project.PSObject.Properties[$profile.source_field]) {
            $excelPath = $project.($profile.source_field)
        }

        if ([string]::IsNullOrWhiteSpace($excelPath)) {
            $result.errors += @{
                mapping_name = "N/A"
                error_type = "NoSourceFile"
                error_message = "Project field '$($profile.source_field)' is empty"
            }
            $result.completed = [datetime]::Now
            return $result
        }

        if (-not (Test-Path $excelPath)) {
            $result.errors += @{
                mapping_name = "N/A"
                error_type = "FileNotFound"
                error_message = "Excel file not found: $excelPath"
            }
            $result.completed = [datetime]::Now
            return $result
        }

        # Read values from Excel
        $reader = $null
        $fieldUpdates = @{}

        try {
            $reader = [ExcelComReader]::new()
            $reader.OpenFile($excelPath)

            foreach ($mapping in $profile.mappings) {
                try {
                    $reader.SetActiveSheetByName($mapping.source_sheet)
                    $value = $reader.ReadCell($mapping.source_cell)

                    $fieldUpdates[$mapping.dest_field] = $value
                    $result.imported_values[$mapping.name] = $value
                    $result.successful_imports++

                } catch {
                    $result.errors += @{
                        mapping_name = $mapping.name
                        error_type = "ReadFailed"
                        error_message = $_.Exception.Message
                    }
                    $result.failed_imports++
                }
            }

        } finally {
            if ($null -ne $reader) {
                try { $reader.Close() } catch { }
            }
        }

        # Update project with imported values
        if ($fieldUpdates.Count -gt 0) {
            try {
                $taskStore.UpdateProject($projectName, $fieldUpdates)
                $taskStore.SaveData()
            } catch {
                $result.errors += @{
                    mapping_name = "N/A"
                    error_type = "UpdateFailed"
                    error_message = "Failed to save project: $($_.Exception.Message)"
                }
            }
        }

        $result.completed = [datetime]::Now
        return $result
    }
}
