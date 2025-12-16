# ExcelT2020.ps1 - Excel T2020 integration for PMC
# Restored from working ExcelT2020.psm1 functionality

# =============================
# Editable Configuration Section
# =============================

# Global configuration variables (user-editable)
$Global:ExcelT2020_SourceFolder = Join-Path $PSScriptRoot 'excel_input'
$Global:ExcelT2020_DestinationPath = Join-Path $PSScriptRoot 'excel_output.xlsm'
$Global:ExcelT2020_DestSheetName = 'Output'
$Global:ExcelT2020_SourceSheetName = 'SVI-CAS'

# Field mappings: copy from SourceSheet:SourceCell to DestSheet:DestCell
$Global:ExcelT2020_Mappings = @(
    @{ Field='RequestDate';    SourceCell='W23'; DestCell='B2'  }
    @{ Field='AuditType';      SourceCell='W78'; DestCell='B3'  }
    @{ Field='AuditorName';    SourceCell='W10'; DestCell='B4'  }
    @{ Field='TPName';         SourceCell='W3';  DestCell='B5'  }
    @{ Field='TPEmailAddress'; SourceCell='X3';  DestCell='B6'  }
    @{ Field='TPPhoneNumber';  SourceCell='Y3';  DestCell='B7'  }
    @{ Field='TaxID';          SourceCell='W13'; DestCell='B8'  }
    @{ Field='CASNumber';      SourceCell='G17'; DestCell='B9'  }
)

# Logging and summary storage
$Global:ExcelT2020_LogPath = Join-Path $PSScriptRoot 'excel_t2020.log'
$Global:ExcelT2020_SummaryPath = Join-Path $PSScriptRoot 'excel_t2020_summary.json'

# =============================
# Excel COM Management
# =============================

$script:ExcelApp = $null

function New-ExcelApp {
    if ($script:ExcelApp -ne $null) { return $script:ExcelApp }
    try {
        $app = New-Object -ComObject Excel.Application
        $app.Visible = $false
        $app.DisplayAlerts = $false
        $script:ExcelApp = $app
        return $script:ExcelApp
    } catch {
        throw "Excel COM is not available. Ensure Excel is installed. Error: $_"
    }
}

function Close-ExcelApp {
    if ($script:ExcelApp -ne $null) {
        try { $script:ExcelApp.Quit() } catch {}
        try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($script:ExcelApp) } catch {}
        $script:ExcelApp = $null
    }
}

function Open-Workbook {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [switch]$ReadOnly
    )
    $app = New-ExcelApp
    if (-not (Test-Path $Path)) { throw "Workbook not found: $Path" }
    try { return $app.Workbooks.Open($Path, $false, [bool]$ReadOnly) } catch { throw "Failed to open workbook '$Path': $_" }
}

function Save-Workbook {
    param([Parameter(Mandatory)] $Workbook)
    try { $Workbook.Save() } catch { throw "Failed to save workbook: $_" }
}

function Close-Workbook {
    param([Parameter(Mandatory)] $Workbook)
    try { $Workbook.Close($false) } catch {}
}

function Get-Worksheet {
    param(
        [Parameter(Mandatory)] $Workbook,
        [Parameter(Mandatory)] [string]$Name
    )
    try { return $Workbook.Worksheets.Item($Name) } catch { throw "Worksheet '$Name' not found in '$($Workbook.Name)'." }
}

# =============================
# Core T2020 Operations
# =============================

function Copy-CellValue {
    param(
        [Parameter(Mandatory)] $SourceSheet,
        [Parameter(Mandatory)] [string]$SourceCell,
        [Parameter(Mandatory)] $DestSheet,
        [Parameter(Mandatory)] [string]$DestCell
    )
    $srcRange = $SourceSheet.Range($SourceCell)
    $dstRange = $DestSheet.Range($DestCell)

    $val = $srcRange.Value2
    if ($null -eq $val -or $val -eq '') {
        $dstRange.Value2 = ''
    } else {
        $srcRange.Copy() | Out-Null
        $dstRange.PasteSpecial(-4163) | Out-Null  # xlPasteValues
        (New-ExcelApp).CutCopyMode = 0
    }
}

function Extract-T2020Fields {
    param(
        [Parameter(Mandatory)] [string]$SourcePath,
        [string]$SourceSheetName = $Global:ExcelT2020_SourceSheetName,
        [array] $Mappings        = $Global:ExcelT2020_Mappings
    )
    $srcWb = $null
    try {
        $srcWb = Open-Workbook -Path $SourcePath -ReadOnly
        $wsSrc = Get-Worksheet -Workbook $srcWb -Name $SourceSheetName
        $data = [ordered]@{}
        foreach ($m in $Mappings) {
            $val = $wsSrc.Range($m.SourceCell).Value2
            $data[$m.Field] = $val
        }
        return @{ Success=$true; Data=$data }
    } catch {
        return @{ Success=$false; Error="Extract failed: $_" }
    } finally {
        if ($srcWb) { Close-Workbook -Workbook $srcWb }
    }
}

function Copy-T2020ForFile {
    param(
        [Parameter(Mandatory)] [string]$SourcePath,
        [Parameter(Mandatory)] [string]$DestinationPath,
        [string]$SourceSheetName = $Global:ExcelT2020_SourceSheetName,
        [string]$DestSheetName   = $Global:ExcelT2020_DestSheetName,
        [array] $Mappings        = $Global:ExcelT2020_Mappings
    )
    $srcWb = $null; $dstWb = $null
    try {
        $srcWb = Open-Workbook -Path $SourcePath -ReadOnly
        $dstWb = Open-Workbook -Path $DestinationPath

        $wsSrc = Get-Worksheet -Workbook $srcWb -Name $SourceSheetName
        $wsDst = Get-Worksheet -Workbook $dstWb -Name $DestSheetName

        foreach ($m in $Mappings) {
            Copy-CellValue -SourceSheet $wsSrc -SourceCell $m.SourceCell -DestSheet $wsDst -DestCell $m.DestCell
        }

        Save-Workbook -Workbook $dstWb
        return @{ Success=$true; Message="Copied $($Mappings.Count) fields from '$SourcePath' to '$DestinationPath'" }
    } catch {
        return @{ Success=$false; Error="Copy failed: $_" }
    } finally {
        if ($srcWb) { Close-Workbook -Workbook $srcWb }
        if ($dstWb) { Close-Workbook -Workbook $dstWb }
    }
}

function Invoke-T2020Batch {
    param(
        [string]$SourceFolder = $Global:ExcelT2020_SourceFolder,
        [string]$DestinationPath = $Global:ExcelT2020_DestinationPath,
        [string]$SourcePattern = '*.xlsm',
        [switch]$WhatIf
    )
    if (-not (Test-Path $SourceFolder)) { throw "Source folder not found: $SourceFolder" }
    $files = Get-ChildItem -Path $SourceFolder -Filter $SourcePattern -File | Sort-Object Name
    if ($files.Count -eq 0) { return @{ Success=$true; Message='No files found'; Processed=0 } }

    $processed = 0
    $summary = @()
    foreach ($f in $files) {
        if ($WhatIf) {
            Write-Host "Would copy from '$($f.FullName)' to '$DestinationPath'" -ForegroundColor Yellow
            continue
        }
        $extract = Extract-T2020Fields -SourcePath $f.FullName
        $res = Copy-T2020ForFile -SourcePath $f.FullName -DestinationPath $DestinationPath
        $ok = ($res.Success -and $extract.Success)
        $processed += [int]$ok
        $record = [ordered]@{
            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Source    = $f.FullName
            Destination = $DestinationPath
            Count     = $Global:ExcelT2020_Mappings.Count
            Success   = $ok
            Error     = $(if ($ok) { '' } else { $(if ($null -ne $res.Error) { $res.Error } else { $extract.Error }) })
            Fields    = $(if ($extract.Success) { $extract.Data } else { @{} })
        }
        $summary += $record
        try {
            "$($record.Timestamp) | $($record.Source) -> $($record.Destination) | Count=$($record.Count) | Success=$($record.Success) | $($record.Error)" | Add-Content -Path $Global:ExcelT2020_LogPath -Encoding UTF8
        } catch {}
    }
    # Persist JSON summary (append)
    try {
        $existing = @()
        if (Test-Path $Global:ExcelT2020_SummaryPath) {
            $existing = Get-Content $Global:ExcelT2020_SummaryPath -Raw | ConvertFrom-Json
        }
        $all = @()
        if ($existing) { $all += $existing }
        $all += $summary
        ($all | ConvertTo-Json -Depth 10) | Set-Content -Path $Global:ExcelT2020_SummaryPath -Encoding UTF8
    } catch {}
    return @{ Success=$true; Processed=$processed; Summary=$summary }
}

function Set-ExcelT2020Config {
    param(
        [string]$SourceFolder,
        [string]$DestinationPath,
        [string]$SourceSheetName,
        [string]$DestSheetName
    )
    if ($PSBoundParameters.ContainsKey('SourceFolder'))     { $Global:ExcelT2020_SourceFolder = $SourceFolder }
    if ($PSBoundParameters.ContainsKey('DestinationPath'))  { $Global:ExcelT2020_DestinationPath = $DestinationPath }
    if ($PSBoundParameters.ContainsKey('SourceSheetName'))  { $Global:ExcelT2020_SourceSheetName = $SourceSheetName }
    if ($PSBoundParameters.ContainsKey('DestSheetName'))    { $Global:ExcelT2020_DestSheetName = $DestSheetName }
}

# =============================
# PMC Excel Command Functions
# =============================

function Import-PmcFromExcel {
    [CmdletBinding()]
    param([PmcCommandContext]$Context)

    try {
        $result = Invoke-T2020Batch -WhatIf:$Context.Args.ContainsKey('whatif')

        if (-not $result.Success) {
            Write-PmcStyled -Style 'Error' -Text ("Excel import failed: {0}" -f $result.Error)
            return
        }

        # Simple display
        Write-PmcStyled -Style 'Success' -Text ("Excel T2020 import completed: {0} files processed" -f $result.Processed)

        # Store import history
        $data = Get-PmcData
        if (-not $data.excelImports) {
            $data | Add-Member -NotePropertyName excelImports -NotePropertyValue @() -Force
        }
        $data.excelImports += $result.Summary

        # Keep only last 50 imports
        if ($data.excelImports.Count -gt 50) {
            $data.excelImports = $data.excelImports[-50..-1]
        }

        Save-PmcData -Data $data

    } catch {
        Write-PmcStyled -Style 'Error' -Text ("Excel import error: {0}" -f $_)
    } finally {
        Close-ExcelApp
    }
}

# Wrappers to align with CommandMap function names
function Import-PmcExcelData { param([PmcCommandContext]$Context) Import-PmcFromExcel -Context $Context }
function Show-PmcExcelPreview { param([PmcCommandContext]$Context) Show-PmcExcelData -Context $Context }
function Get-PmcLatestExcelFile { param([PmcCommandContext]$Context) Get-PmcLatestExcelData -Context $Context }

function Show-PmcExcelData {
    param([PmcCommandContext]$Context)
    try {
        if (-not (Test-Path $Global:ExcelT2020_SourceFolder)) {
            Write-PmcStyled -Style 'Error' -Text "Source folder not found: $Global:ExcelT2020_SourceFolder"
            return
        }
        $files = Get-ChildItem -Path $Global:ExcelT2020_SourceFolder -Filter '*.xlsm' -File
        if ($files.Count -eq 0) {
            Write-PmcStyled -Style 'Warning' -Text "No Excel files found in: $Global:ExcelT2020_SourceFolder"
            return
        }
        $extract = Extract-T2020Fields -SourcePath $files[0].FullName
        if ($extract.Success) {
            Write-PmcStyled -Style 'Info' -Text "Excel T2020 Preview ($($files.Count) files found):"
            foreach ($field in $extract.Data.GetEnumerator()) {
                $value = $(if ($field.Value -and $field.Value.ToString().Length -gt 30) { $field.Value.ToString().Substring(0, 27) + "..." } else { $field.Value })
                Write-Host "  $($field.Key): $value"
            }
        } else {
            Write-PmcStyled -Style 'Error' -Text "Failed to preview: $($extract.Error)"
        }
    } catch {
        Write-PmcStyled -Style 'Error' -Text "Excel view error: $_"
    } finally {
        Close-ExcelApp
    }
}

function Get-PmcLatestExcelData {
    param([PmcCommandContext]$Context)
    try {
        $data = Get-PmcData
        $imports = @($data.excelImports)
        if ($imports.Count -eq 0) {
            Write-PmcStyled -Style 'Warning' -Text "No Excel imports found. Run 'excel import' first."
            return
        }
        $recent = $imports | Select-Object -Last 10
        Write-PmcStyled -Style 'Info' -Text "Recent Excel Imports:"
        foreach ($import in $recent) {
            $status = $(if ($import.Success) { '[OK]' } else { '[ERROR]' })
            Write-Host "  $($import.Timestamp) $($import.Source) $status"
        }
    } catch {
        Write-PmcStyled -Style 'Error' -Text "Excel latest error: $_"
    }
}

#Export-ModuleMember -Function New-ExcelApp, Close-ExcelApp, Open-Workbook, Save-Workbook, Close-Workbook, Get-Worksheet, Copy-CellValue, Extract-T2020Fields, Copy-T2020ForFile, Invoke-T2020Batch, Set-ExcelT2020Config, Import-PmcFromExcel, Import-PmcExcelData, Show-PmcExcelPreview, Get-PmcLatestExcelFile, Show-PmcExcelData, Get-PmcLatestExcelData