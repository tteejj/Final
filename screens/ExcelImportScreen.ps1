using namespace System.Collections.Generic
using namespace System.Text

# ExcelImportScreen - Import project from Excel
# Multi-step wizard: Source -> Profile -> Preview -> Import

Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"
. "$PSScriptRoot/../services/ExcelComReader.ps1"
. "$PSScriptRoot/../services/ExcelMappingService.ps1"

# MEDIUM FIX ES-M4, ES-M5, ES-M7: Define constants for magic numbers
$global:MAX_PREVIEW_ROWS = 15
$script:EXCEL_ATTACH_MAX_RETRIES = 3
$script:EXCEL_ATTACH_RETRY_DELAY_MS = 500
$global:MAX_CELLS_TO_READ = 100

# LOW FIX ES-L3, ES-L4: Define constants for date validation range
$global:MIN_VALID_YEAR = 1950
$global:MAX_VALID_YEAR = 2100

<#
.SYNOPSIS
Excel import wizard screen

.DESCRIPTION
Import project data from Excel file:
- Step 1: Choose source (running Excel or file)
- Step 2: Select profile
- Step 3: Preview data
- Step 4: Confirm and import
#>
class ExcelImportScreen : PmcScreen {
    hidden [ExcelComReader]$_reader = $null
    hidden [ExcelMappingService]$_mappingService = $null
    hidden [object]$_activeProfile = $null
    hidden [hashtable]$_previewData = @{}
    hidden [int]$_step = 1
    hidden [int]$_selectedOption = 0
    hidden [string]$_errorMessage = ""
    [TaskStore]$Store = $null  # CRITICAL FIX #1: Add Store property for AddProject() call

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Projects', 'Import from Excel', 'I', {
                . "$PSScriptRoot/ExcelImportScreen.ps1"
                $global:PmcApp.PushScreen((New-Object -TypeName ExcelImportScreen))
            }, 40)
    }

    # Constructor
    ExcelImportScreen() : base("ExcelImport", "Import from Excel") {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') ========== EXCELIMPORTSCREEN CONSTRUCTOR CALLED =========="

        try {
            $this._reader = [ExcelComReader]::new()
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') EXCELIMPORTSCREEN: ExcelComReader created successfully"
        }
        catch {
            $this._errorMessage = "Excel COM not available: $($_.Exception.Message). Excel must be installed to use this feature."
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') EXCELIMPORTSCREEN: FAILED to create ExcelComReader - $($_.Exception.Message)"
            Write-PmcTuiLog "ExcelImportScreen: Failed to initialize ExcelComReader - $_" "ERROR"
        }

        $this._mappingService = [ExcelMappingService]::GetInstance()
        $this.Store = [TaskStore]::GetInstance()

        if ($null -eq $this.Store) {
            throw "Failed to initialize TaskStore singleton. Cannot proceed with Excel import."
        }

        # Configure header
        $this.Header.SetBreadcrumb(@("Projects", "Import from Excel"))

        # Configure footer
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Enter", "Next")
        $this.Footer.AddShortcut("Esc", "Cancel")
    }

    # Constructor with container
    ExcelImportScreen([object]$container) : base("ExcelImport", "Import from Excel", $container) {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') ========== EXCELIMPORTSCREEN CONTAINER CONSTRUCTOR CALLED =========="

        try {
            $this._reader = [ExcelComReader]::new()
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') EXCELIMPORTSCREEN: ExcelComReader created successfully"
        }
        catch {
            $this._errorMessage = "Excel COM not available: $($_.Exception.Message). Excel must be installed to use this feature."
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') EXCELIMPORTSCREEN: FAILED to create ExcelComReader - $($_.Exception.Message)"
            Write-PmcTuiLog "ExcelImportScreen: Failed to initialize ExcelComReader - $_" "ERROR"
        }

        $this._mappingService = [ExcelMappingService]::GetInstance()
        $this.Store = [TaskStore]::GetInstance()

        if ($null -eq $this.Store) {
            throw "Failed to initialize TaskStore singleton. Cannot proceed with Excel import."
        }

        # Configure header
        $this.Header.SetBreadcrumb(@("Projects", "Import from Excel"))

        # Configure footer
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Enter", "Next")
        $this.Footer.AddShortcut("Esc", "Cancel")
    }

    [void] OnDoExit() {
        $this.IsActive = $false
        if ($null -ne $this._reader) {
            $this._reader.Close()
        }
    }

    [string] Render() {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') EXCELIMPORTSCREEN.Render: CALLED step=$($this._step)"
        $sb = [StringBuilder]::new()

        # Render base widgets
        $output = ([PmcScreen]$this).Render()
        $sb.Append($output)

        # Calculate content area
        $contentY = 6
        $contentHeight = $this.TermHeight - 8
        $contentWidth = $this.TermWidth

        $y = $contentY + 2

        # Render based on step
        switch ($this._step) {
            1 {
                # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') EXCELIMPORTSCREEN.Render: Calling _RenderStep1"
                $this._RenderStep1($sb, $y, $contentWidth)
            }
            2 {
                # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') EXCELIMPORTSCREEN.Render: Calling _RenderStep2"
                $this._RenderStep2($sb, $y, $contentWidth)
            }
            3 {
                # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') EXCELIMPORTSCREEN.Render: Calling _RenderStep3"
                $this._RenderStep3($sb, $y, $contentWidth)
            }
            4 {
                # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') EXCELIMPORTSCREEN.Render: Calling _RenderStep4"
                $this._RenderStep4($sb, $y, $contentWidth)
            }
        }

        # Render error if any
        if (-not [string]::IsNullOrEmpty($this._errorMessage)) {
            $sb.Append($this.Header.BuildMoveTo(2, $this.TermHeight - 5))
            $sb.Append("`e[31mError: $($this._errorMessage)`e[0m")
        }

        return $sb.ToString()
    }

    hidden [void] _RenderStep1([StringBuilder]$sb, [int]$y, [int]$width) {
        # Step 1: Connect to Excel
        $sb.Append($this.Header.BuildMoveTo(2, $y))
        $sb.Append("`e[1mStep 1: Connect to Excel`e[0m")
        $y += 2

        # Check if Excel COM is available
        if ($null -eq $this._reader) {
            $sb.Append($this.Header.BuildMoveTo(4, $y))
            $sb.Append("`e[31m")  # Red text
            $sb.Append("Excel COM is not available on this system.")
            $sb.Append("`e[0m")
            $y += 2

            $sb.Append($this.Header.BuildMoveTo(4, $y))
            $sb.Append("`e[90m")  # Gray text
            $sb.Append("This feature requires Microsoft Excel to be installed.")
            $sb.Append("`e[0m")
            $y++

            $sb.Append($this.Header.BuildMoveTo(4, $y))
            $sb.Append("`e[90m")  # Gray text
            $sb.Append("Press Esc to return to the project list.")
            $sb.Append("`e[0m")
            return
        }

        # Option 1: Attach to running Excel
        $sb.Append($this.Header.BuildMoveTo(4, $y))
        if ($this._selectedOption -eq 0) {
            $sb.Append("`e[7m")  # Highlight
        }
        $sb.Append("1. Attach to running Excel instance")
        if ($this._selectedOption -eq 0) {
            $sb.Append("`e[0m")
        }
        $y++

        # Option 2: Open Excel file
        $sb.Append($this.Header.BuildMoveTo(4, $y))
        if ($this._selectedOption -eq 1) {
            $sb.Append("`e[7m")  # Highlight
        }
        $sb.Append("2. Open Excel file...")
        if ($this._selectedOption -eq 1) {
            $sb.Append("`e[0m")
        }
        $y++

        $y++
        $sb.Append($this.Header.BuildMoveTo(4, $y))
        $sb.Append("`e[90m")  # Gray text
        if ($this._selectedOption -eq 0) {
            $sb.Append("(Make sure Excel is running with your workbook open)")
        }
        else {
            $sb.Append("(Browse for an Excel file to import)")
        }
        $sb.Append("`e[0m")
    }

    hidden [void] _RenderStep2([StringBuilder]$sb, [int]$y, [int]$width) {
        # Step 2: Select profile
        $sb.Append($this.Header.BuildMoveTo(2, $y))
        $sb.Append("`e[1mStep 2: Select Import Profile`e[0m")
        $y += 2

        # HIGH FIX ES-H1: Validate GetAllProfiles() return
        $profiles = @($this._mappingService.GetAllProfiles())
        if ($null -eq $profiles) {
            throw "ExcelMappingService.GetAllProfiles() returned null. Failed to load import profiles."
        }
        if ($profiles.Count -eq 0) {
            $sb.Append($this.Header.BuildMoveTo(4, $y))
            $sb.Append("No profiles found. Please create a profile first.")
        }
        else {
            # HIGH FIX ES-H2: Validate GetActiveProfile() return before property access
            $activeProfile = $this._mappingService.GetActiveProfile()
            $activeId = $(if ($null -ne $activeProfile) {
                    if ($activeProfile -is [hashtable]) {
                        if ($activeProfile.ContainsKey('id')) { $activeProfile['id'] } else { $null }
                    }
                    else {
                        if ($activeProfile.PSObject.Properties['id']) { $activeProfile.id } else { $null }
                    }
                }
                else {
                    $null
                })

            for ($i = 0; $i -lt $profiles.Count; $i++) {
                $profile = $profiles[$i]
                # HIGH FIX ES-H3: Validate profile before string interpolation
                if ($null -eq $profile) {
                    Write-PmcTuiLog "ExcelImportScreen: Null profile at index $i" "WARNING"
                    continue
                }

                # Handle both hashtables and PSCustomObjects
                $profileId = $(if ($profile -is [hashtable]) {
                        if ($profile.ContainsKey('id')) { $profile['id'] } else { $null }
                    }
                    else {
                        if ($profile.PSObject.Properties['id']) { $profile.id } else { $null }
                    })
                $isActive = $(if ($profileId -eq $activeId) { " [ACTIVE]" } else { "" })

                $sb.Append($this.Header.BuildMoveTo(4, $y + $i))
                if ($i -eq $this._selectedOption) {
                    $sb.Append("`e[7m")
                }

                # Handle both hashtables and PSCustomObjects
                $profileName = $(if ($profile -is [hashtable]) {
                        if ($profile.ContainsKey('name')) { $profile['name'] } else { 'Unnamed' }
                    }
                    else {
                        if ($profile.PSObject.Properties['name']) { $profile.name } else { 'Unnamed' }
                    })

                $sb.Append("$($i + 1). $profileName$isActive")
                if ($i -eq $this._selectedOption) {
                    $sb.Append("`e[0m")
                }
            }
        }
    }

    hidden [void] _RenderStep3([StringBuilder]$sb, [int]$y, [int]$width) {
        # Step 3: Preview data
        $sb.Append($this.Header.BuildMoveTo(2, $y))
        $sb.Append("`e[1mStep 3: Preview Import Data`e[0m")
        $y += 2

        if ($null -eq $this._activeProfile) {
            $sb.Append($this.Header.BuildMoveTo(4, $y))
            $sb.Append("No profile selected")
            return
        }

        # HIGH FIX ES-H4: Validate profile name before string interpolation
        $profileName = $(if ($null -ne $this._activeProfile) {
                if ($this._activeProfile -is [hashtable]) {
                    if ($this._activeProfile.ContainsKey('name')) { $this._activeProfile['name'] } else { 'Unnamed Profile' }
                }
                else {
                    if ($this._activeProfile.PSObject.Properties['name']) { $this._activeProfile.name } else { 'Unnamed Profile' }
                }
            }
            else {
                'Unnamed Profile'
            })
        $sb.Append($this.Header.BuildMoveTo(4, $y))
        $sb.Append("Profile: $profileName")
        $y += 2

        # Show preview data
        # MEDIUM FIX ES-M4: Use script-level constant for max preview rows
        $maxRows = $global:MAX_PREVIEW_ROWS
        $rowCount = 0

        foreach ($mapping in $this._activeProfile['mappings']) {
            if ($rowCount -ge $maxRows) { break }

            $fieldName = $mapping['display_name']
            $value = $(if ($this._previewData.ContainsKey($mapping['excel_cell'])) {
                    $cellValue = $this._previewData[$mapping['excel_cell']]
                    if ($null -eq $cellValue -or [string]::IsNullOrWhiteSpace($cellValue)) {
                        "(empty)"
                    }
                    else {
                        $cellValue
                    }
                }
                else {
                    "(empty)"
                })

            $required = $(if ($mapping['required']) { "*" } else { " " })

            $sb.Append($this.Header.BuildMoveTo(4, $y + $rowCount))
            $sb.Append("$required$($fieldName): $value")
            $rowCount++
        }
    }

    hidden [void] _RenderStep4([StringBuilder]$sb, [int]$y, [int]$width) {
        # Step 4: Confirm
        $sb.Append($this.Header.BuildMoveTo(2, $y))
        $sb.Append("`e[1mStep 4: Import Complete`e[0m")
        $y += 2

        $sb.Append($this.Header.BuildMoveTo(4, $y))
        $sb.Append("Project imported successfully!")
        $y += 2

        $sb.Append($this.Header.BuildMoveTo(4, $y))
        $sb.Append("Press Esc to return to project list.")
    }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # CRITICAL: Call parent FIRST for MenuBar, F10, Alt+keys, content widgets
        $handled = ([PmcScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        # Clear error
        $this._errorMessage = ""

        # Up/Down for selection
        if ($keyInfo.Key -eq ([ConsoleKey]::UpArrow)) {
            if ($this._selectedOption -gt 0) {
                $this._selectedOption--
            }
            return $true
        }

        if ($keyInfo.Key -eq ([ConsoleKey]::DownArrow)) {
            $maxOptions = $this._GetMaxOptions()
            # ES-M2 FIX: Guard against invalid maxOptions (0 or negative)
            if ($maxOptions -gt 0 -and $this._selectedOption -lt $maxOptions - 1) {
                $this._selectedOption++
            }
            return $true
        }

        # Enter - Next step
        if ($keyInfo.Key -eq ([ConsoleKey]::Enter)) {
            # Don't allow proceeding if Excel COM is not available
            if ($null -eq $this._reader -and $this._step -eq 1) {
                $this._errorMessage = "Excel COM not available. Cannot proceed."
                return $true
            }
            $this._ProcessStep()
            return $true
        }

        # Escape - Cancel/Back
        if ($keyInfo.Key -eq ([ConsoleKey]::Escape)) {
            if ($this._step -eq 1) {
                $global:PmcApp.PopScreen()
            }
            else {
                $this._step--
                $this._selectedOption = 0
            }
            return $true
        }

        return $false
    }

    # KSV2-M2 FIX: Add proper bounds for steps 3 and 4
    hidden [int] _GetMaxOptions() {
        switch ($this._step) {
            1 { return 2 }  # 2 options: attach to running Excel OR open file
            2 {
                $profiles = @($this._mappingService.GetAllProfiles())
                return $profiles.Count
            }
            3 { return 1 }  # Step 3 (preview): 1 option (Enter to continue)
            4 { return 1 }  # Step 4 (complete): 1 option (Esc to exit)
            default { return 0 }
        }
        return 0  # Explicit return to satisfy PowerShell strict mode
    }

    hidden [void] _ProcessStep() {
        # Check if Excel COM is available
        if ($null -eq $this._reader -and $this._step -eq 1) {
            $this._errorMessage = "Excel COM not available. Excel must be installed to use this feature."
            Write-PmcTuiLog "ExcelImportScreen: Cannot proceed - ExcelComReader is null" "ERROR"
            return
        }

        try {
            switch ($this._step) {
                1 {
                    # Step 1: Connect to Excel
                    if ($this._selectedOption -eq 0) {
                        # Option 1: Attach to running Excel
                        # CRITICAL FIX EXS-C1 & MEDIUM FIX ES-M5: Use script-level constants for retry logic
                        $maxRetries = $script:EXCEL_ATTACH_MAX_RETRIES
                        $retryDelay = $script:EXCEL_ATTACH_RETRY_DELAY_MS
                        $attached = $false

                        for ($retry = 0; $retry -lt $maxRetries; $retry++) {
                            try {
                                $this._reader.AttachToRunningExcel()
                                # ES-M3 FIX: Validate workbook has accessible sheets
                                # CRITICAL FIX ES-C1: Cache workbook result
                                $wb = $this._reader.GetWorkbook()
                                if ($null -eq $wb -or $null -eq $wb.Sheets -or $wb.Sheets.Count -eq 0) {
                                    throw "Workbook has no accessible sheets"
                                }

                                # HIGH FIX ES-H5: Complete null validation before accessing PSObject.Properties
                                if ($null -ne $wb -and $null -ne $wb.PSObject -and $null -ne $wb.PSObject.Properties) {
                                    if ($wb.PSObject.Properties['Saved'] -and -not $wb.Saved) {
                                        Write-PmcTuiLog "Warning: Workbook has unsaved changes" "WARNING"
                                        $this._errorMessage = "Warning: Workbook has unsaved changes. Please save before importing."
                                    }
                                }

                                $attached = $true
                                break
                            }
                            catch {
                                if ($retry -lt ($maxRetries - 1)) {
                                    Write-PmcTuiLog "AttachToRunningExcel attempt $($retry + 1) failed, retrying in ${retryDelay}ms..." "WARN"
                                    Start-Sleep -Milliseconds $retryDelay
                                }
                                else {
                                    $this._errorMessage = "Failed to attach to Excel after $maxRetries attempts: $($_.Exception.Message). Make sure Excel is running and has a workbook open."
                                    Write-PmcTuiLog "AttachToRunningExcel failed after $maxRetries attempts: $_" "ERROR"
                                }
                            }
                        }

                        if ($attached) {
                            $this._step = 2
                            $this._selectedOption = 0
                            $this._errorMessage = ""
                        }
                    }
                    else {
                        # Option 2: Open Excel file
                        try {
                            $filePath = $this._ShowFilePicker()
                            # HIGH FIX ES-H6: Validate file path is not null/empty/whitespace
                            if (-not [string]::IsNullOrWhiteSpace($filePath)) {
                                $this._reader.OpenFile($filePath)
                                # ES-M3 FIX: Validate workbook has accessible sheets
                                if ($null -eq $this._reader.GetWorkbook() -or $null -eq $this._reader.GetWorkbook().Sheets -or $this._reader.GetWorkbook().Sheets.Count -eq 0) {
                                    throw "Workbook has no accessible sheets"
                                }
                                $this._step = 2
                                $this._selectedOption = 0
                                $this._errorMessage = ""
                            }
                            else {
                                $this._errorMessage = "No file selected"
                            }
                        }
                        catch {
                            $this._errorMessage = "Failed to open Excel file: $($_.Exception.Message)"
                            Write-PmcTuiLog "OpenFile failed: $_" "ERROR"
                        }
                    }
                }
                2 {
                    # Step 2: Select profile and read data
                    $profiles = @($this._mappingService.GetAllProfiles())
                    if ($this._selectedOption -lt $profiles.Count) {
                        $this._activeProfile = $profiles[$this._selectedOption]

                        # ES-M1 FIX: Validate mappings exist before iteration
                        if ($null -eq $this._activeProfile['mappings'] -or
                            $this._activeProfile['mappings'].Count -eq 0) {
                            throw "Selected profile has no field mappings configured"
                        }

                        # Read all mapped cells
                        $cellsToRead = @($this._activeProfile['mappings'] | ForEach-Object { $_['excel_cell'] })

                        # ES-M6 & ES-M7 FIX: Use script-level constant for max cells limit
                        $maxCellsToRead = $global:MAX_CELLS_TO_READ
                        if ($cellsToRead.Count -gt $maxCellsToRead) {
                            Write-PmcTuiLog "Warning: Profile has $($cellsToRead.Count) cell mappings, limiting to $maxCellsToRead to prevent performance issues" "WARN"
                            $cellsToRead = $cellsToRead | Select-Object -First $maxCellsToRead
                        }

                        $this._previewData = $this._reader.ReadCells($cellsToRead)
                        # HIGH FIX ES-H7: Validate ReadCells() return value
                        if ($null -eq $this._previewData) {
                            Write-PmcTuiLog "ExcelImportScreen: ReadCells() returned null" "WARNING"
                            $this._previewData = @{}
                        }

                        $this._step = 3
                        $this._selectedOption = 0
                    }
                }
                3 {
                    # Step 3: Validate and import
                    $this._ImportProject()
                    $this._step = 4
                    $this._selectedOption = 0
                }
                4 {
                    # Step 4: Done
                    $global:PmcApp.PopScreen()
                }
            }
        }
        catch {
            $this._errorMessage = $_.Exception.Message
            Write-PmcTuiLog "ExcelImportScreen: Error in step $($this._step) - $_" "ERROR"
        }
    }

    hidden [void] _ImportProject() {
        # Validate profile has mappings
        if ($null -eq $this._activeProfile -or
            -not $this._activeProfile.ContainsKey('mappings') -or
            $null -eq $this._activeProfile['mappings'] -or
            $this._activeProfile['mappings'].Count -eq 0) {
            throw "Active profile has no field mappings configured"
        }

        # Build project data from mappings
        $projectData = @{}

        foreach ($mapping in $this._activeProfile['mappings']) {
            # Get value with existence check
            $value = $(if ($this._previewData.ContainsKey($mapping['excel_cell'])) {
                    $this._previewData[$mapping['excel_cell']]
                }
                else {
                    $null
                })

            # Validate required fields based on data type
            $isEmpty = switch ($mapping['data_type']) {
                'string' { [string]::IsNullOrWhiteSpace($value) }
                'int' { $null -eq $value }
                'bool' { $null -eq $value }
                'date' { $null -eq $value }
                default { $null -eq $value }
            }

            if ($mapping['required'] -and $isEmpty) {
                throw "Required field '$($mapping['display_name'])' is empty"
            }

            # Type conversion with error handling - throw on failure for data integrity
            # CRITICAL FIX ES-C4: Preserve original value and type for better error context
            $convertedValue = switch ($mapping['data_type']) {
                'int' {
                    $originalValue = $value
                    $originalType = $(if ($null -eq $value) { "null" } else { $value.GetType().Name })
                    try {
                        if ($null -eq $value -or $value -eq '') {
                            0
                        }
                        else {
                            # BUG-16 FIX: Use [long] (Int64) to handle numbers > 2,147,483,647
                            # Excel can contain large numbers that exceed Int32 max value
                            [long]$value
                        }
                    }
                    catch {
                        Write-PmcTuiLog "Failed to convert '$originalValue' (type: $originalType) to int for field $($mapping['display_name']): $_" "ERROR"
                        throw "Cannot convert '$originalValue' (type: $originalType) to integer for field '$($mapping['display_name'])'"
                    }
                }
                'bool' {
                    $originalValue = $value
                    $originalType = $(if ($null -eq $value) { "null" } else { $value.GetType().Name })
                    try {
                        if ($null -eq $value -or $value -eq '') {
                            $false
                        }
                        else {
                            [bool]$value
                        }
                    }
                    catch {
                        Write-PmcTuiLog "Failed to convert '$originalValue' (type: $originalType) to bool for field $($mapping['display_name']): $_" "ERROR"
                        throw "Cannot convert '$originalValue' (type: $originalType) to boolean for field '$($mapping['display_name'])'"
                    }
                }
                'date' {
                    $originalValue = $value
                    $originalType = $(if ($null -eq $value) { "null" } else { $value.GetType().Name })
                    try {
                        if ($null -eq $value -or $value -eq '') {
                            $null
                        }
                        else {
                            $dateValue = [datetime]$value
                            # LOW FIX ES-L2, ES-L3, ES-L4: Use script-level constants for date range validation
                            if ($dateValue.Year -lt $global:MIN_VALID_YEAR -or $dateValue.Year -gt $global:MAX_VALID_YEAR) {
                                Write-PmcTuiLog "Date value '$dateValue' for field $($mapping['display_name']) is outside reasonable range ($global:MIN_VALID_YEAR-$global:MAX_VALID_YEAR)" "WARNING"
                                throw "Date '$dateValue' is outside reasonable range ($global:MIN_VALID_YEAR-$global:MAX_VALID_YEAR) for field '$($mapping['display_name'])'"
                            }
                            $dateValue
                        }
                    }
                    catch {
                        Write-PmcTuiLog "Failed to convert '$originalValue' (type: $originalType) to date for field $($mapping['display_name']): $_" "ERROR"
                        throw "Cannot convert '$originalValue' (type: $originalType) to date for field '$($mapping['display_name'])'"
                    }
                }
                default {
                    $value
                }
            }

            $projectData[$mapping['project_property']] = $convertedValue
        }

        # CRITICAL FIX #4: Validate project name exists before import
        if (-not $projectData.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($projectData['name'])) {
            throw "Project name is required but not mapped or empty. Please configure a mapping for the 'name' field."
        }

        # Use TaskStore to add project (no Get-PmcAllData bypass!)
        # TaskStore handles ID generation and timestamps automatically
        $success = $this.Store.AddProject($projectData)

        # CRITICAL FIX ES-C1: Add explicit null check for AddProject return 
        if ($null -eq $success) {
            $this._errorMessage = "Failed to add project: Store.AddProject returned null"
            Write-PmcTuiLog "ExcelImportScreen: AddProject returned null for '$($projectData['name'])'" "ERROR"
            $this._step = 3  # Stay on step 3
            throw "Failed to add project: AddProject returned null"
        }

        if ($success) {
            Write-PmcTuiLog "ExcelImportScreen: Imported project '$($projectData['name'])'" "INFO"
            # ES-M9 FIX: Check Flush() return value to ensure data is persisted
            # BUG-14 FIX: Throw error if Flush() fails instead of just logging
            $flushResult = $this.Store.Flush()
            if ($flushResult -eq $false) {
                Write-PmcTuiLog "ExcelImportScreen: CRITICAL - Flush() returned false after importing project '$($projectData['name'])'" "ERROR"
                throw "Failed to persist project data to disk. Import cancelled."
            }
        }
        else {
            # ES-H7 FIX: Check Store is not null before accessing LastError
            $errorMsg = $(if ($null -ne $this.Store) {
                    $this.Store.LastError
                }
                else {
                    "Store is null"
                })
            Write-PmcTuiLog "ExcelImportScreen: Failed to import project: $errorMsg" "ERROR"
            throw "Failed to import project: $errorMsg"
        }
    }

    hidden [string] _ShowFilePicker() {
        # LOW FIX ES-L3: Validate script sourcing path exists
        $pickerPath = "$PSScriptRoot/../widgets/PmcFilePicker.ps1"
        if (-not (Test-Path $pickerPath)) {
            Write-PmcTuiLog "PmcFilePicker.ps1 not found at: $pickerPath" "ERROR"
            throw "File picker widget not found. Please ensure PmcFilePicker.ps1 exists."
        }
        . $pickerPath

        # Start at user's home directory
        $startPath = [Environment]::GetFolderPath('UserProfile')
        $picker = [PmcFilePicker]::new($startPath, $false)  # false = allow files

        # Manual render loop
        while (-not $picker.IsComplete) {
            # ES-M8 FIX: Add null check for PmcThemeManager.GetInstance()
            $themeManager = [PmcThemeManager]::GetInstance()
            if ($null -eq $themeManager) {
                Write-PmcTuiLog "PmcThemeManager.GetInstance() returned null in file picker" "ERROR"
                $picker.IsComplete = $true
                $picker.Result = $false
                break
            }
            $theme = $themeManager.GetTheme()

            # Render picker
            $termWidth = [Console]::WindowWidth
            $termHeight = [Console]::WindowHeight
            $pickerOutput = $picker.Render($termWidth, $termHeight)
            Write-Host -NoNewline $pickerOutput

            # Handle input
            # ES-H1 FIX: Protect against non-interactive mode crash
            try {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    $picker.HandleInput($key)
                }
            }
            catch [System.InvalidOperationException] {
                # Not in interactive mode - cancel picker
                Write-PmcTuiLog "File picker cannot run in non-interactive mode" "ERROR"
                $picker.IsComplete = $true
                $picker.Result = $false
            }

            Start-Sleep -Milliseconds 50
        }

        # ES-H2 FIX: Check Result before accessing SelectedPath to avoid null reference
        if ($picker.Result -and $null -ne $picker.SelectedPath) {
            # ES-M5 FIX: Validate selection is a file, not a directory
            if (Test-Path -Path $picker.SelectedPath -PathType Container) {
                Write-PmcTuiLog "Selected path is a directory, not a file: $($picker.SelectedPath)" "ERROR"
                return ''
            }
            if (-not (Test-Path -Path $picker.SelectedPath -PathType Leaf)) {
                Write-PmcTuiLog "Selected path is not a valid file: $($picker.SelectedPath)" "ERROR"
                return ''
            }
            return $picker.SelectedPath
        }
        else {
            return ''
        }
    }
}