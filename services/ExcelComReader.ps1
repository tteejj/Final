# ExcelComReader.ps1 - COM automation for reading Excel files
#
# Provides COM-based Excel reading capabilities
# Can attach to running Excel instance or open files programmatically
#
# Usage:
#   $reader = [ExcelComReader]::new()
#   $reader.AttachToRunningExcel()
#   $value = $reader.ReadCell("W3")
#   $reader.Close()

using namespace System
using namespace System.Runtime.InteropServices

Set-StrictMode -Version Latest

class ExcelComReader {
    # COM objects
    hidden [object]$_excelApp = $null
    hidden [object]$_workbook = $null
    hidden [object]$_worksheet = $null
    hidden [bool]$_isAttached = $false  # Did we create Excel or attach to existing?

    # State
    [bool]$IsOpen = $false
    [string]$FilePath = ""
    [int]$ActiveSheet = 1

    # Constructor
    ExcelComReader() {
        # Nothing to initialize
    }

    # Validate Excel cell address format (e.g., "A1", "W3", "AA100", "AAA1")
    # ES-H5 FIX: Make regex case-insensitive and add null check
    # The [A-Z]+ pattern with + quantifier properly matches multi-letter columns
    hidden [bool] IsValidCellAddress([string]$address) {
        if ([string]::IsNullOrWhiteSpace($address)) {
            return $false
        }
        # Case-insensitive match: accepts A1, AA1, AAA1, a1, aa1, etc.
        return $address -match '(?i)^[A-Z]+\d+$'
    }

    # Attach to running Excel instance
    [void] AttachToRunningExcel() {
        try {
            $this._excelApp = [Marshal]::GetActiveObject("Excel.Application")

            # CRITICAL FIX ES-C2: Validate COM object is functional
            if ($null -eq $this._excelApp) {
                throw "Excel COM object is null"
            }
            # Test if Excel is responsive
            $null = $this._excelApp.Name  # Will throw if Excel is not responsive

            # LOW FIX ES-L1: Validate Excel is not in edit mode
            try {
                $isInEditMode = $this._excelApp.Interactive -eq $false
                if ($isInEditMode) {
                    Write-PmcTuiLog "Excel may be in edit mode or protected view - attempting to continue" "WARNING"
                }
            } catch {
                # If we can't check edit mode, log warning but continue
                Write-PmcTuiLog "Cannot verify Excel edit mode status: $($_.Exception.Message)" "WARNING"
            }

            $this._isAttached = $true

            # KSV2-M3 FIX: Validate Worksheets collection exists before access
            if ($this._excelApp.Workbooks.Count -gt 0) {
                $this._workbook = $this._excelApp.ActiveWorkbook
                if ($null -ne $this._workbook -and
                    $null -ne $this._workbook.Worksheets -and
                    $this._workbook.Worksheets.Count -gt 0) {
                    $this._worksheet = $this._workbook.ActiveSheet
                    $this.ActiveSheet = $this._worksheet.Index
                }
            }

            $this.IsOpen = $true
            Write-PmcTuiLog "ExcelComReader: Attached to running Excel instance" "INFO"

        } catch {
            Write-PmcTuiLog "ExcelComReader: Failed to attach to Excel - $_" "ERROR"
            throw "Excel is not running or not accessible. Please open Excel first and try again."
        }
    }

    # Open Excel file programmatically
    [void] OpenFile([string]$filePath) {
        if (-not (Test-Path $filePath)) {
            throw "File not found: $filePath"
        }

        try {
            $this._excelApp = New-Object -ComObject Excel.Application

            # CRITICAL FIX ES-C2: Validate COM object is functional
            if ($null -eq $this._excelApp) {
                throw "Excel COM object is null"
            }
            # Test if Excel is responsive
            $null = $this._excelApp.Name  # Will throw if Excel is not responsive

            $this._excelApp.Visible = $false
            $this._excelApp.DisplayAlerts = $false
            $this._isAttached = $false

            # MEDIUM FIX #16: Add file lock detection and user-friendly error handling
            try {
                $this._workbook = $this._excelApp.Workbooks.Open($filePath)
            } catch {
                # Common COM errors for file locks or permissions
                $errorMsg = $_.Exception.Message
                $lockError = $errorMsg -match 'locked|in use|permission denied|cannot access|0x800A03EC'
                if ($lockError) {
                    $this.Close()
                    throw "Cannot open file - it may be open in another program, locked by the file system, or you may not have permission to access it. Please close the file in other programs and try again."
                }
                throw
            }

            # KSV2-M3 FIX: Validate Worksheets collection exists before access
            if ($null -ne $this._workbook -and
                $null -ne $this._workbook.Worksheets -and
                $this._workbook.Worksheets.Count -gt 0) {
                $this._worksheet = $this._workbook.Worksheets.Item(1)
                $this.ActiveSheet = 1
            }

            $this.FilePath = $filePath
            $this.IsOpen = $true
            Write-PmcTuiLog "ExcelComReader: Opened file $filePath" "INFO"

        } catch {
            Write-PmcTuiLog "ExcelComReader: Failed to open file - $_" "ERROR"
            $this.Close()
            throw "Could not open Excel file: $_"
        }
    }

    # Set active worksheet by index (1-based)
    [void] SetActiveSheet([int]$sheetIndex) {
        if (-not $this.IsOpen -or $null -eq $this._workbook) {
            throw "No workbook is open"
        }

        # KSV2-M3 FIX: Validate Worksheets collection exists before access
        if ($null -eq $this._workbook.Worksheets) {
            throw "Workbook has no Worksheets collection"
        }

        if ($sheetIndex -lt 1 -or $sheetIndex -gt $this._workbook.Worksheets.Count) {
            throw "Sheet index out of range: $sheetIndex (workbook has $($this._workbook.Worksheets.Count) sheets)"
        }

        $this._worksheet = $this._workbook.Worksheets.Item($sheetIndex)
        $this.ActiveSheet = $sheetIndex
    }

    # Set active worksheet by name
    [void] SetActiveSheetByName([string]$sheetName) {
        if (-not $this.IsOpen -or $null -eq $this._workbook) {
            throw "No workbook is open"
        }

        # KSV2-M3 FIX: Validate Worksheets collection exists before access
        if ($null -eq $this._workbook.Worksheets) {
            throw "Workbook has no Worksheets collection"
        }

        try {
            $this._worksheet = $this._workbook.Worksheets.Item($sheetName)
            $this.ActiveSheet = $this._worksheet.Index
        } catch {
            throw "Sheet not found: $sheetName"
        }
    }

    # Read single cell value
    [object] ReadCell([string]$cellAddress) {
        if (-not $this.IsOpen -or $null -eq $this._worksheet) {
            throw "No worksheet is active"
        }

        if (-not $this.IsValidCellAddress($cellAddress)) {
            throw "Invalid Excel cell address: $cellAddress (expected format like 'A1' or 'W3')"
        }

        $cell = $null
        try {
            $cell = $this._worksheet.Range($cellAddress)
            $value = $cell.Value2
            return $value
        } catch {
            Write-PmcTuiLog "ExcelComReader: Error reading cell $cellAddress - $_" "ERROR"
            return $null
        } finally {
            if ($null -ne $cell) {
                [Marshal]::ReleaseComObject($cell) | Out-Null
            }

            # CRITICAL FIX ES-C5: Aggressive COM cleanup to prevent memory leaks
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
        }
    }

    # Read range of cells (returns hashtable of address => value)
    [hashtable] ReadRange([string]$startCell, [string]$endCell) {
        if (-not $this.IsOpen -or $null -eq $this._worksheet) {
            throw "No worksheet is active"
        }

        if (-not $this.IsValidCellAddress($startCell)) {
            throw "Invalid Excel cell address: $startCell (expected format like 'A1' or 'W3')"
        }
        if (-not $this.IsValidCellAddress($endCell)) {
            throw "Invalid Excel cell address: $endCell (expected format like 'A1' or 'W3')"
        }

        $cellData = @{}
        $range = $null
        $cells = $null  # CRITICAL FIX #2: Track Cells collection COM object
        $cellsToRelease = [System.Collections.ArrayList]::new()

        try {
            $range = $this._worksheet.Range("$startCell`:$endCell")

            if ($null -ne $range) {
                # CRITICAL FIX #2: Get Cells collection explicitly for proper COM cleanup
                $cells = $range.Cells
                if ($null -ne $cells) {
                    foreach ($cell in $cells) {
                        $address = $cell.Address($false, $false)  # Get address like "W3"
                        $cellData[$address] = $cell.Value2
                        [void]$cellsToRelease.Add($cell)
                    }
                }
            }

            return $cellData

        } catch {
            Write-PmcTuiLog "ExcelComReader: Error reading range $startCell`:$endCell - $_" "ERROR"
            return $cellData
        } finally {
            # Release all cell COM objects
            foreach ($cell in $cellsToRelease) {
                try {
                    [Marshal]::ReleaseComObject($cell) | Out-Null
                } catch {
                    Write-PmcTuiLog "Failed to release COM object (cell): $($_.Exception.Message)" "WARNING"
                }
            }
            # CRITICAL FIX #2: Release Cells collection COM object
            if ($null -ne $cells) {
                try {
                    [Marshal]::ReleaseComObject($cells) | Out-Null
                } catch {
                    Write-PmcTuiLog "Failed to release COM object (cells collection): $($_.Exception.Message)" "WARNING"
                }
            }
            # Release range COM object
            if ($null -ne $range) {
                try {
                    [Marshal]::ReleaseComObject($range) | Out-Null
                } catch {
                    Write-PmcTuiLog "Failed to release COM object (range): $($_.Exception.Message)" "WARNING"
                }
            }
        }
    }

    # Read multiple specific cells (returns hashtable of address => value)
    [hashtable] ReadCells([array]$cellAddresses) {
        if (-not $this.IsOpen -or $null -eq $this._worksheet) {
            throw "No worksheet is active"
        }

        $cellData = @{}

        foreach ($address in $cellAddresses) {
            try {
                $value = $this.ReadCell($address)
                $cellData[$address] = $value
            } catch {
                Write-PmcTuiLog "ExcelComReader: Error reading cell $address - $_" "WARN"
                $cellData[$address] = $null
            }
        }

        return $cellData
    }

    # Get worksheet names
    [array] GetSheetNames() {
        if (-not $this.IsOpen -or $null -eq $this._workbook) {
            return @()
        }

        # KSV2-M3 FIX: Validate Worksheets collection exists before access
        if ($null -eq $this._workbook.Worksheets) {
            Write-PmcTuiLog "Workbook has no Worksheets collection" "WARNING"
            return @()
        }

        $names = @()
        $sheets = $null
        try {
            $sheets = $this._workbook.Worksheets
            foreach ($sheet in $sheets) {
                # LOW FIX ES-L4: Add null check in GetSheetNames loop
                if ($null -ne $sheet -and $null -ne $sheet.Name) {
                    $names += $sheet.Name
                }
                try {
                    if ($null -ne $sheet) {
                        [Marshal]::ReleaseComObject($sheet) | Out-Null
                    }
                } catch {
                    Write-PmcTuiLog "Failed to release COM object (sheet): $($_.Exception.Message)" "WARNING"
                }
            }
        } finally {
            if ($null -ne $sheets) {
                try {
                    [Marshal]::ReleaseComObject($sheets) | Out-Null
                } catch {
                    Write-PmcTuiLog "Failed to release COM object (sheets collection): $($_.Exception.Message)" "WARNING"
                }
            }
        }
        return $names
    }

    # Close and cleanup
    # NOTE: Caller MUST call Close() explicitly - PowerShell classes do not support finalizers
    [void] Close() {
        if ($this.IsOpen) {
            # Isolate each cleanup operation to prevent cascading failures

            # Release worksheet COM object
            if ($null -ne $this._worksheet) {
                try {
                    [Marshal]::ReleaseComObject($this._worksheet) | Out-Null
                } catch {
                    Write-PmcTuiLog "ExcelComReader: Error releasing worksheet COM object - $_" "WARN"
                }
                $this._worksheet = $null
            }

            # Close and release workbook
            if ($null -ne $this._workbook) {
                if (-not $this._isAttached) {
                    try {
                        $this._workbook.Close($false)  # Don't save changes
                    } catch {
                        Write-PmcTuiLog "ExcelComReader: Error closing workbook - $_" "WARN"
                    }
                }
                try {
                    [Marshal]::ReleaseComObject($this._workbook) | Out-Null
                } catch {
                    Write-PmcTuiLog "ExcelComReader: Error releasing workbook COM object - $_" "WARN"
                }
                $this._workbook = $null
            }

            # Quit and release Excel app
            if ($null -ne $this._excelApp) {
                if (-not $this._isAttached) {
                    try {
                        $this._excelApp.Quit()
                    } catch {
                        Write-PmcTuiLog "ExcelComReader: Error quitting Excel - $_" "WARN"
                    }
                }
                try {
                    [Marshal]::ReleaseComObject($this._excelApp) | Out-Null
                } catch {
                    Write-PmcTuiLog "ExcelComReader: Error releasing Excel COM object - $_" "WARN"
                }
                $this._excelApp = $null
            }

            $this.IsOpen = $false

            # CRITICAL FIX ES-C5: Aggressive COM cleanup to ensure all resources are released
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()

            Write-PmcTuiLog "ExcelComReader: Closed" "INFO"
        }
    }
}