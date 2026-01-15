# TextExportService.ps1 - Service for exporting Excel data to text files
#
# Maps Excel cells to text file output lines with labels
# Output format: "Label: Value" per line
# Saves to project folder
#
# Usage:
#   $service = [TextExportService]::GetInstance()
#   $profile = $service.CreateProfile("T2020 Export", "Generate T2020 from CAA", "CAAName")
#   $service.AddMapping($profileId, @{ source_sheet="Sheet1"; source_cell="B5"; label="Third Party"; line_number=1 })
#   $result = $service.ExecuteExport($profileId, "MyProject", $taskStore)

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

. "$PSScriptRoot/ExcelComReader.ps1"

class TextExportService {
    # === Singleton Instance ===
    static hidden [TextExportService]$_instance = $null
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
    static [TextExportService] GetInstance() {
        if ([TextExportService]::_instance -eq $null) {
            [System.Threading.Monitor]::Enter([TextExportService]::_instanceLock)
            try {
                if ([TextExportService]::_instance -eq $null) {
                    [TextExportService]::_instance = [TextExportService]::new()
                }
            } finally {
                [System.Threading.Monitor]::Exit([TextExportService]::_instanceLock)
            }
        }
        return [TextExportService]::_instance
    }

    # === Constructor ===
    TextExportService() {
        # Determine data directory relative to PMC root
        $pmcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $dataDir = Join-Path $pmcRoot "Data"
        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        $this._profilesFile = Join-Path $dataDir "text-export-profiles.json"
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
                                label = $mapping.label
                                source_sheet = $mapping.source_sheet
                                source_cell = $mapping.source_cell
                                line_number = $(if ($mapping.PSObject.Properties['line_number']) { [int]$mapping.line_number } else { 0 })
                            }
                        }
                    }

                    $this._profilesCache[$profile.id] = @{
                        id = $profile.id
                        name = $profile.name
                        description = $profile.description
                        source_field = $profile.source_field
                        output_filename = $(if ($profile.PSObject.Properties['output_filename']) { $profile.output_filename } else { "T2020.txt" })
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
                        label = $mapping.label
                        source_sheet = $mapping.source_sheet
                        source_cell = $mapping.source_cell
                        line_number = $mapping.line_number
                    }
                }

                @{
                    id = $_.id
                    name = $_.name
                    description = $_.description
                    source_field = $_.source_field
                    output_filename = $_.output_filename
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

    [object] CreateProfile([string]$name, [string]$description, [string]$sourceField, [string]$outputFilename) {
        $existing = @($this._profilesCache.Values | Where-Object { $_['name'] -eq $name })
        if ($existing.Count -gt 0) {
            throw "Profile with name '$name' already exists"
        }

        $profileId = [guid]::NewGuid().ToString()

        $profile = @{
            id = $profileId
            name = $name
            description = $description
            source_field = $sourceField
            output_filename = $(if ([string]::IsNullOrWhiteSpace($outputFilename)) { "T2020.txt" } else { $outputFilename })
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
        if ($changes.ContainsKey('output_filename')) { $profile.output_filename = $changes.output_filename }

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
            label = $mappingData.label
            source_sheet = $mappingData.source_sheet
            source_cell = $mappingData.source_cell
            line_number = $(if ($mappingData.ContainsKey('line_number')) { $mappingData.line_number } else { $profile.mappings.Count + 1 })
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

        if ($changes.ContainsKey('label')) { $mapping.label = $changes.label }
        if ($changes.ContainsKey('source_sheet')) { $mapping.source_sheet = $changes.source_sheet }
        if ($changes.ContainsKey('source_cell')) { $mapping.source_cell = $changes.source_cell }
        if ($changes.ContainsKey('line_number')) { $mapping.line_number = $changes.line_number }

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
        return @($profile.mappings | Sort-Object -Property line_number)
    }

    # === Source field options ===
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

    # === Export Execution ===
    [object] ExecuteExport([string]$profileId, [string]$projectName, [object]$taskStore) {
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
            successful_exports = 0
            failed_exports = 0
            errors = @()
            output_path = $null
            exported_values = @{}
        }

        # Get project data
        $project = $taskStore.GetProject($projectName)
        if ($null -eq $project) {
            $result.errors += @{
                label = "N/A"
                error_type = "ProjectNotFound"
                error_message = "Project not found: $projectName"
            }
            $result.completed = [datetime]::Now
            return $result
        }

        # Get Excel path from source_field
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
                label = "N/A"
                error_type = "NoSourceFile"
                error_message = "Project field '$($profile.source_field)' is empty"
            }
            $result.completed = [datetime]::Now
            return $result
        }

        if (-not (Test-Path $excelPath)) {
            $result.errors += @{
                label = "N/A"
                error_type = "FileNotFound"
                error_message = "Excel file not found: $excelPath"
            }
            $result.completed = [datetime]::Now
            return $result
        }

        # Get project folder for output
        $projFolder = $null
        if ($project -is [hashtable]) {
            if ($project.ContainsKey('ProjFolder')) {
                $projFolder = $project['ProjFolder']
            }
        } elseif ($project.PSObject.Properties['ProjFolder']) {
            $projFolder = $project.ProjFolder
        }

        if ([string]::IsNullOrWhiteSpace($projFolder)) {
            # Fallback to same folder as Excel file
            $projFolder = Split-Path $excelPath -Parent
        }

        if (-not (Test-Path $projFolder)) {
            try {
                New-Item -ItemType Directory -Path $projFolder -Force | Out-Null
            } catch {
                $result.errors += @{
                    label = "N/A"
                    error_type = "FolderCreateFailed"
                    error_message = "Cannot create folder: $projFolder"
                }
                $result.completed = [datetime]::Now
                return $result
            }
        }

        # Build output lines from Excel
        $outputLines = @{}
        $reader = $null

        try {
            $reader = [ExcelComReader]::new()
            $reader.OpenFile($excelPath)

            foreach ($mapping in $profile.mappings) {
                try {
                    $reader.SetActiveSheetByName($mapping.source_sheet)
                    $value = $reader.ReadCell($mapping.source_cell)

                    # Format: "Label: Value"
                    $line = "$($mapping.label): $value"
                    $outputLines[$mapping.line_number] = $line
                    $result.exported_values[$mapping.label] = $value
                    $result.successful_exports++

                } catch {
                    $result.errors += @{
                        label = $mapping.label
                        error_type = "ReadFailed"
                        error_message = $_.Exception.Message
                    }
                    $result.failed_exports++
                    # Still add the line with error note
                    $outputLines[$mapping.line_number] = "$($mapping.label): [ERROR]"
                }
            }

        } finally {
            if ($null -ne $reader) {
                try { $reader.Close() } catch { }
            }
        }

        # Generate output file
        $outputPath = Join-Path $projFolder $profile.output_filename
        try {
            $sortedLines = $outputLines.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value }
            $sortedLines | Set-Content -Path $outputPath -Encoding utf8
            $result.output_path = $outputPath
        } catch {
            $result.errors += @{
                label = "N/A"
                error_type = "WriteFailed"
                error_message = "Failed to write output file: $($_.Exception.Message)"
            }
        }

        $result.completed = [datetime]::Now
        return $result
    }
}
