using namespace System.Collections.Generic
using namespace System.Text

# ExcelImportScreen - Import project from Excel
# Multi-step wizard: Source -> Profile -> Preview -> Import

Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"
. "$PSScriptRoot/../services/ExcelComReader.ps1"
. "$PSScriptRoot/../services/ExcelMappingService.ps1"
. "$PSScriptRoot/../widgets/PmcFilePicker.ps1"

# Constants
$global:MAX_PREVIEW_ROWS = 15
$script:EXCEL_ATTACH_MAX_RETRIES = 3
$script:EXCEL_ATTACH_RETRY_DELAY_MS = 500
$global:MAX_CELLS_TO_READ = 100
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
    [TaskStore]$Store = $null

    # File Picker State
    hidden [PmcFilePicker]$_filePicker = $null
    hidden [bool]$_showFilePicker = $false

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Projects', 'Import from Excel', 'I', {
                . "$PSScriptRoot/ExcelImportScreen.ps1"
                $global:PmcApp.PushScreen((New-Object -TypeName ExcelImportScreen))
            }, 40)
    }

    # Constructor
    ExcelImportScreen() : base("ExcelImport", "Import from Excel") {
        $this._Initialize()
    }

    # Constructor with container
    ExcelImportScreen([object]$container) : base("ExcelImport", "Import from Excel", $container) {
        $this._Initialize()
    }

    hidden [void] _Initialize() {
        try {
            $this._reader = [ExcelComReader]::new()
        }
        catch {
            $this._errorMessage = "Excel COM not available: $($_.Exception.Message). Excel must be installed."
        }

        $this._mappingService = [ExcelMappingService]::GetInstance()
        $this.Store = [TaskStore]::GetInstance()

        if ($null -eq $this.Store) {
            throw "Failed to initialize TaskStore singleton."
        }

        # Configure header
        $this.Header.SetBreadcrumb(@("Projects", "Import from Excel"))

        # Configure footer
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Enter", "Next")
        $this.Footer.AddShortcut("Backspace", "Back")
        $this.Footer.AddShortcut("Esc", "Cancel")
    }

    [void] OnDoExit() {
        $this.IsActive = $false
        if ($null -ne $this._reader) {
            $this._reader.Close()
        }
    }

    # === Rendering ===

    [void] RenderContentToEngine([object]$engine) {
        # Calculate content area
        $contentY = 6
        $contentWidth = $this.TermWidth
        $y = $contentY + 2

        # Render based on step
        switch ($this._step) {
            1 { $this._RenderStep1Engine($engine, $y, $contentWidth) }
            2 { $this._RenderStep2Engine($engine, $y, $contentWidth) }
            3 { $this._RenderStep3Engine($engine, $y, $contentWidth) }
            4 { $this._RenderStep4Engine($engine, $y, $contentWidth) }
        }

        # Render error if any
        if (-not [string]::IsNullOrEmpty($this._errorMessage)) {
            $errorFg = $this.GetThemedInt('Foreground.Error')
            $textBg = $this.GetThemedInt('Background.Field')
            $engine.WriteAt(2, $this.TermHeight - 5, "Error: $($this._errorMessage)", $errorFg, $textBg)
        }

        # Render File Picker Overlay
        if ($this._showFilePicker -and $this._filePicker) {
            # Center the picker
            $pickerWidth = [Math]::Min(70, $this.TermWidth - 4)
            $pickerHeight = [Math]::Min(20, $this.TermHeight - 4)
            $pickerX = [Math]::Floor(($this.TermWidth - $pickerWidth) / 2)
            $pickerY = [Math]::Floor(($this.TermHeight - $pickerHeight) / 2)

            $this._filePicker.X = $pickerX
            $this._filePicker.Y = $pickerY
            $this._filePicker.Width = $pickerWidth
            $this._filePicker.Height = $pickerHeight

            # Ensure z-index is top
            $engine.BeginLayer(100)
            $this._filePicker.RenderToEngine($engine)
        }
    }

    hidden [void] _RenderStep1Engine([object]$engine, [int]$y, [int]$width) {
        $titleFg = $this.GetThemedInt('Foreground.Title')
        $errorFg = $this.GetThemedInt('Foreground.Error')
        $mutedFg = $this.GetThemedInt('Foreground.Muted')
        $selFg = $this.GetThemedInt('Foreground.RowSelected')
        $selBg = $this.GetThemedInt('Background.RowSelected')
        $textBg = $this.GetThemedInt('Background.Field')

        $engine.WriteAt(2, $y, "Step 1: Connect to Excel", $titleFg, $textBg)
        $y += 2

        if ($null -eq $this._reader) {
            $engine.WriteAt(4, $y, "Excel COM is not available on this system.", $errorFg, $textBg)
            $y += 2
            $engine.WriteAt(4, $y, "This feature requires Microsoft Excel to be installed.", $mutedFg, $textBg)
            $y++
            $engine.WriteAt(4, $y, "Press Esc to return to the project list.", $mutedFg, $textBg)
            return
        }

        # Option 1
        $fg1 = $(if ($this._selectedOption -eq 0) { $selFg } else { $mutedFg })
        $bg1 = $(if ($this._selectedOption -eq 0) { $selBg } else { $textBg })
        $engine.WriteAt(4, $y, "1. Attach to running Excel instance", $fg1, $bg1)
        $y++

        # Option 2
        $fg2 = $(if ($this._selectedOption -eq 1) { $selFg } else { $mutedFg })
        $bg2 = $(if ($this._selectedOption -eq 1) { $selBg } else { $textBg })
        $engine.WriteAt(4, $y, "2. Open Excel file...", $fg2, $bg2)
        $y += 2

        $hint = $(if ($this._selectedOption -eq 0) { "(Make sure Excel is running with your workbook open)" } else { "(Browse for an Excel file to import)" })
        $engine.WriteAt(4, $y, $hint, $mutedFg, $textBg)
    }

    hidden [void] _RenderStep2Engine([object]$engine, [int]$y, [int]$width) {
        $titleFg = $this.GetThemedInt('Foreground.Title')
        $selFg = $this.GetThemedInt('Foreground.RowSelected')
        $selBg = $this.GetThemedInt('Background.RowSelected')
        $textFg = $this.GetThemedInt('Foreground.Field')
        $textBg = $this.GetThemedInt('Background.Field')

        $engine.WriteAt(2, $y, "Step 2: Select Import Profile", $titleFg, $textBg)
        $y += 2

        $profiles = @($this._mappingService.GetAllProfiles())
        if ($null -eq $profiles -or $profiles.Count -eq 0) {
            $engine.WriteAt(4, $y, "No profiles found. Please create a profile first.", $textFg, $textBg)
            return
        }

        $activeProfile = $this._mappingService.GetActiveProfile()
        $activeId = $null
        if ($null -ne $activeProfile) {
            if ($activeProfile -is [hashtable] -and $activeProfile.ContainsKey('id')) { $activeId = $activeProfile['id'] }
            elseif ($activeProfile.PSObject.Properties['id']) { $activeId = $activeProfile.id }
        }

        for ($i = 0; $i -lt $profiles.Count; $i++) {
            $profile = $profiles[$i]
            if ($null -eq $profile) { continue }

            $profileId = $null
            $profileName = 'Unnamed'
            if ($null -ne $profile) {
                $profileId = Get-SafeProperty $profile 'id'
                $profileName = Get-SafeProperty $profile 'name'
            }

            $isActive = $(if ($profileId -eq $activeId) { " [ACTIVE]" } else { "" })
            $text = "$($i + 1). $profileName$isActive"

            $fg = $(if ($i -eq $this._selectedOption) { $selFg } else { $textFg })
            $bg = $(if ($i -eq $this._selectedOption) { $selBg } else { $textBg })
            $engine.WriteAt(4, $y + $i, $text, $fg, $bg)
        }
    }

    hidden [void] _RenderStep3Engine([object]$engine, [int]$y, [int]$width) {
        $titleFg = $this.GetThemedInt('Foreground.Title')
        $textFg = $this.GetThemedInt('Foreground.Field')
        $textBg = $this.GetThemedInt('Background.Field')

        $engine.WriteAt(2, $y, "Step 3: Preview Import Data", $titleFg, $textBg)
        $y += 2

        if ($null -eq $this._activeProfile) {
            $engine.WriteAt(4, $y, "No profile selected", $textFg, $textBg)
            return
        }

        $profileName = 'Unnamed Profile'
        if ($null -ne $this._activeProfile) {
            $val = Get-SafeProperty $this._activeProfile 'name'
            if ($val) { $profileName = $val }
        }

        $engine.WriteAt(4, $y, "Profile: $profileName", $textFg, $textBg)
        $y += 2

        $maxRows = $global:MAX_PREVIEW_ROWS
        $rowCount = 0

        $mappings = Get-SafeProperty $this._activeProfile 'mappings'
        foreach ($mapping in $mappings) {
            if ($rowCount -ge $maxRows) { break }

            $fieldName = Get-SafeProperty $mapping 'display_name'
            $value = "(empty)"
            if ($this._previewData.ContainsKey($mapping['excel_cell'])) {
                $cellValue = $this._previewData[$mapping['excel_cell']]
                if (-not [string]::IsNullOrWhiteSpace($cellValue)) { $value = $cellValue }
            }

            $required = $(if ($mapping['required']) { "*" } else { " " })
            $engine.WriteAt(4, $y + $rowCount, "$required$($fieldName): $value", $textFg, $textBg)
            $rowCount++
        }
    }

    hidden [void] _RenderStep4Engine([object]$engine, [int]$y, [int]$width) {
        $titleFg = $this.GetThemedInt('Foreground.Title')
        $textFg = $this.GetThemedInt('Foreground.Field')
        $textBg = $this.GetThemedInt('Background.Field')

        $engine.WriteAt(2, $y, "Step 4: Import Complete", $titleFg, $textBg)
        $y += 2
        $engine.WriteAt(4, $y, "Project imported successfully!", $textFg, $textBg)
        $y += 2
        $engine.WriteAt(4, $y, "Press Esc to return to project list.", $textFg, $textBg)
    }

    # === Input Handling ===

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # Phase B: Active modal gets priority
        if ($this.HandleModalInput($keyInfo)) {
            # Check if file picker completed
            if ($this._activeModal -eq $this._filePicker -and $this._filePicker.IsComplete) {
                if ($this._filePicker.Result) {
                    $this._OpenFile($this._filePicker.SelectedPath)
                }
                # Close picker
                $this._showFilePicker = $false
                $this._filePicker = $null
                $this._activeModal = $null # Clear active modal
                $this.NeedsClear = $true
            }
            return $true
        }

        # 2. Call parent for standard shortcuts (F10, Alt+Keys)
        $handled = ([PmcScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        # 3. Wizard Navigation
        $this._errorMessage = ""

        # Up/Down
        if ($keyInfo.Key -eq ([ConsoleKey]::UpArrow)) {
            if ($this._selectedOption -gt 0) {
                $this._selectedOption--
            }
            return $true
        }

        if ($keyInfo.Key -eq ([ConsoleKey]::DownArrow)) {
            $maxOptions = $this._GetMaxOptions()
            if ($maxOptions -gt 0 -and $this._selectedOption -lt $maxOptions - 1) {
                $this._selectedOption++
            }
            return $true
        }

        # Enter - Next Step / Action
        if ($keyInfo.Key -eq ([ConsoleKey]::Enter)) {
            $this._ProcessStep()
            return $true
        }

        # Backspace - Go back one step
        if ($keyInfo.Key -eq ([ConsoleKey]::Backspace)) {
            if ($this._step -gt 1) {
                $this._step--
                $this._selectedOption = 0
            }
            return $true
        }

        # Escape - Back / Cancel
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

    hidden [int] _GetMaxOptions() {
        switch ($this._step) {
            1 { return 2 }
            2 { return @($this._mappingService.GetAllProfiles()).Count }
            3 { return 1 }
            4 { return 1 }
            default { return 0 }
        }
        return 0
    }

    hidden [void] _ProcessStep() {
        # Pre-checks
        if ($null -eq $this._reader -and $this._step -eq 1) {
            $this._errorMessage = "Excel COM not available."
            return
        }

        try {
            switch ($this._step) {
                1 { # Connect
                    if ($this._selectedOption -eq 0) {
                        # Attach to running Excel
                        $this._AttachToExcel()
                    } else {
                        # Open File Picker
                        $this._InitFilePicker()
                    }
                }
                2 { # Select Profile
                    $this._SelectProfile()
                }
                3 { # Validate & Import
                    $this._ImportProject()
                    $this._step = 4
                    $this._selectedOption = 0
                }
                4 { # Done
                    $global:PmcApp.PopScreen()
                }
            }
        }
        catch {
            $this._errorMessage = $_.Exception.Message
        }
    }

    # === Helper Methods ===

    hidden [void] _InitFilePicker() {
        $startPath = [Environment]::GetFolderPath('UserProfile')
        $this._filePicker = [PmcFilePicker]::new($startPath, $false)
        $this._showFilePicker = $true
        $this._activeModal = $this._filePicker # Phase B: Set active modal
        $this.NeedsClear = $true
    }

    hidden [void] _OpenFile([string]$path) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            try {
                $this._reader.OpenFile($path)
                $this._CheckWorkbook()
                $this._step = 2
                $this._selectedOption = 0
            } catch {
                $this._errorMessage = "Failed to open file: $($_.Exception.Message)"
            }
        }
    }

    hidden [void] _AttachToExcel() {
        $maxRetries = $script:EXCEL_ATTACH_MAX_RETRIES
        $retryDelay = $script:EXCEL_ATTACH_RETRY_DELAY_MS
        
        for ($retry = 0; $retry -lt $maxRetries; $retry++) {
            try {
                $this._reader.AttachToRunningExcel()
                $this._CheckWorkbook()
                
                # Success
                $this._step = 2
                $this._selectedOption = 0
                return
            }
            catch {
                if ($retry -lt ($maxRetries - 1)) {
                    Start-Sleep -Milliseconds $retryDelay
                }
            }
        }
        throw "Failed to attach to Excel. Make sure it is running with a workbook open."
    }

    hidden [void] _CheckWorkbook() {
        $wb = $this._reader.GetWorkbook()
        if ($null -eq $wb -or $null -eq $wb.Sheets -or $wb.Sheets.Count -eq 0) {
            throw "Workbook has no accessible sheets"
        }
    }

    hidden [void] _SelectProfile() {
        $profiles = @($this._mappingService.GetAllProfiles())
        if ($this._selectedOption -lt $profiles.Count) {
            $this._activeProfile = $profiles[$this._selectedOption]

            $mappings = Get-SafeProperty $this._activeProfile 'mappings'
            if ($null -eq $mappings -or $mappings.Count -eq 0) {
                throw "Profile has no mappings"
            }

            # Read Preview
            $cellsToRead = @($mappings | ForEach-Object { Get-SafeProperty $_ 'excel_cell' })
            if ($cellsToRead.Count -gt $global:MAX_CELLS_TO_READ) {
                $cellsToRead = $cellsToRead | Select-Object -First $global:MAX_CELLS_TO_READ
            }

            $this._previewData = $this._reader.ReadCells($cellsToRead)
            if ($null -eq $this._previewData) { $this._previewData = @{} }

            $this._step = 3
            $this._selectedOption = 0
        }
    }

    hidden [void] _ImportProject() {
        if ($null -eq $this._activeProfile) { throw "No profile" }

        $projectData = @{}
        
        $mappings = Get-SafeProperty $this._activeProfile 'mappings'
        foreach ($mapping in $mappings) {
            $cell = Get-SafeProperty $mapping 'excel_cell'
            $val = if ($this._previewData.ContainsKey($cell)) { $this._previewData[$cell] } else { $null }

            # Type Conversion
            $converted = $val
            $dataType = Get-SafeProperty $mapping 'data_type'
            switch ($dataType) {
                'int' { 
                    try { $converted = if ($val) { [long]$val } else { 0 } } catch { throw "Invalid int: $val" }
                }
                'bool' {
                    try { $converted = if ($val) { [bool]$val } else { $false } } catch { throw "Invalid bool: $val" }
                }
                'date' {
                    try { 
                        if ($val) {
                            $d = [datetime]$val
                            if ($d.Year -lt $global:MIN_VALID_YEAR -or $d.Year -gt $global:MAX_VALID_YEAR) {
                                throw "Date out of range"
                            }
                            $converted = $d
                        } else { $converted = $null }
                    } catch { throw "Invalid date: $val" }
                }
            }
            
            # Required check
            $req = Get-SafeProperty $mapping 'required'
            if ($req -and $null -eq $converted) {
                $dispName = Get-SafeProperty $mapping 'display_name'
                throw "Field '$dispName' is required"
            }

            $projProp = Get-SafeProperty $mapping 'project_property'
            $projectData[$projProp] = $converted
        }

        if (-not $projectData['name']) { throw "Project name is required" }

        $success = $this.Store.AddProject($projectData)
        if (-not $success) { throw "Store add failed: $($this.Store.LastError)" }
        
        if (-not $this.Store.Flush()) { throw "Save to disk failed" }
    }
}