# TextExportService.ps1 - Export project fields to text file
# Uses FieldMappingService profile to determine which fields to export

class TextExportService {
    hidden [string]$_dataDir
    hidden [FieldMappingService]$_mappingService
    
    TextExportService([string]$dataDir) {
        $this._dataDir = $dataDir
        $this._mappingService = [FieldMappingService]::GetInstance($dataDir)
    }
    
    [hashtable] ExportProject([hashtable]$project, [string]$filename) {
        $result = @{
            success = $false
            output_path = $null
            error = $null
            exported_fields = 0
        }
        
        try {
            # Get active profile
            $profile = $this._mappingService.GetActiveProfile()
            if ($null -eq $profile) {
                $result.error = "No mapping profile configured"
                return $result
            }
            
            # Determine output directory
            $outputDir = $this._dataDir
            if ($project.ContainsKey('ProjFolder') -and $project['ProjFolder'] -and (Test-Path $project['ProjFolder'])) {
                $outputDir = $project['ProjFolder']
            }
            
            if (-not (Test-Path $outputDir)) {
                New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            }
            
            $outputPath = Join-Path $outputDir $filename
            
            # Build output lines from profile mappings (only those with include_in_export)
            $lines = @()
            $lines += "=" * 60
            $lines += "PROJECT EXPORT: $($project['name'])"
            $lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $lines += "Profile: $($profile.name)"
            $lines += "=" * 60
            $lines += ""
            
            # Get mappings sorted by sort_order
            $mappings = @($profile.mappings | Where-Object { $_.include_in_export -eq $true } | Sort-Object { $_.sort_order })
            
            foreach ($mapping in $mappings) {
                $fieldName = $mapping.project_property
                $displayName = $mapping.display_name
                $value = ""
                
                if ($project.ContainsKey($fieldName)) {
                    $value = $project[$fieldName]
                }
                
                $lines += "$displayName`: $value"
                $result.exported_fields++
            }
            
            # Add file paths section
            $lines += ""
            $lines += "-" * 40
            $lines += "PROJECT FILES"
            $lines += "-" * 40
            $lines += "T2020 File: $($project['T2020'])"
            $lines += "CAA File: $($project['CAAName'])"
            $lines += "Request File: $($project['RequestName'])"
            $lines += "Project Folder: $($project['ProjFolder'])"
            
            # Write file
            $lines | Set-Content -Path $outputPath -Encoding utf8
            
            $result.success = $true
            $result.output_path = $outputPath
            
            [Logger]::Log("TextExportService: Exported $($result.exported_fields) fields to $outputPath")
            
        } catch {
            $result.error = $_.Exception.Message
            [Logger]::Log("TextExportService: Export failed - $($_.Exception.Message)")
        }
        
        return $result
    }
    
    # Quick export - exports ALL project fields (not just mapped ones)
    [hashtable] ExportAllFields([hashtable]$project, [string]$filename) {
        $result = @{
            success = $false
            output_path = $null
            error = $null
            exported_fields = 0
        }
        
        try {
            # Determine output directory
            $outputDir = $this._dataDir
            if ($project.ContainsKey('ProjFolder') -and $project['ProjFolder'] -and (Test-Path $project['ProjFolder'])) {
                $outputDir = $project['ProjFolder']
            }
            
            if (-not (Test-Path $outputDir)) {
                New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            }
            
            $outputPath = Join-Path $outputDir $filename
            
            # Build output lines for ALL fields
            $lines = @()
            $lines += "=" * 60
            $lines += "FULL PROJECT EXPORT: $($project['name'])"
            $lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $lines += "=" * 60
            $lines += ""
            
            # Get all project fields
            $allFields = $this._mappingService.GetProjectFields()
            
            foreach ($field in $allFields) {
                $fieldName = $field.name
                $displayName = $field.label
                $value = ""
                
                if ($project.ContainsKey($fieldName)) {
                    $value = $project[$fieldName]
                }
                
                $lines += "$displayName`: $value"
                $result.exported_fields++
            }
            
            # Add file paths section
            $lines += ""
            $lines += "-" * 40
            $lines += "PROJECT FILES"
            $lines += "-" * 40
            $lines += "T2020 File: $($project['T2020'])"
            $lines += "CAA File: $($project['CAAName'])"
            $lines += "Request File: $($project['RequestName'])"
            $lines += "Project Folder: $($project['ProjFolder'])"
            
            # Write file
            $lines | Set-Content -Path $outputPath -Encoding utf8
            
            $result.success = $true
            $result.output_path = $outputPath
            
            [Logger]::Log("TextExportService: Exported $($result.exported_fields) fields to $outputPath")
            
        } catch {
            $result.error = $_.Exception.Message
            [Logger]::Log("TextExportService: Export failed - $($_.Exception.Message)")
        }
        
        return $result
    }
}
