# ProjectInfoScreenV4.ps1 - Tabbed interface for project details
#
# Clean implementation using TabbedScreen base class
# Organizes 57 fields into 6 logical tabs:
# - Identity (4 fields)
# - Request (6 fields)
# - Audit (8 fields)
# - Location (7 fields)
# - Periods (12 fields)
# - More (20 fields - contacts, software, misc)

using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

# Load dependencies
. "$PSScriptRoot/../base/TabbedScreen.ps1"

# Lazy-load SimpleFilePicker when needed (for folder browsing)
function EnsureSimpleFilePicker {
    if ($null -eq ([Type]'SimpleFilePicker' -as [Type])) {
        . "$PSScriptRoot/../widgets/SimpleFilePicker.ps1"
    }
}

<#
.SYNOPSIS
Project information screen with tabbed interface

.DESCRIPTION
Displays and edits all project fields organized into 6 tabs:
- Identity: IDs, folder, CAA name
- Request: Request details and dates
- Audit: Auditor information and cases
- Location: Third party and address
- Periods: Audit period date ranges
- More: Contacts, software, comments

Navigation:
- Tab/Shift+Tab: Cycle through tabs
- 1-6: Jump to specific tab
- Up/Down: Navigate fields
- Enter: Edit current field
- S: Save all changes

.PARAMETER projectName
Name of project to display
#>
class ProjectInfoScreenV4 : TabbedScreen {
    # === Data ===
    [string]$ProjectName = ""
    [hashtable]$ProjectData = @{}
    [object]$Store = $null

    # === File Picker ===
    [object]$FilePicker = $null
    [bool]$ShowFilePicker = $false
    [string]$FilePickerFieldName = ""

    # === Constructor ===
    ProjectInfoScreenV4([string]$projectName) : base("ProjectInfo", "Project Information") {
        $this.ProjectName = $projectName
        $this.Store = [TaskStore]::GetInstance()
        $this._UpdateBreadcrumb()
    }

    # Constructor with container
    ProjectInfoScreenV4([object]$container) : base("ProjectInfo", "Project Information", $container) {
        $this.Store = $container.Resolve('TaskStore')
        $this._UpdateBreadcrumb()
    }

    [void] SetProject([string]$projectName) {
        $this.ProjectName = $projectName
        $this._UpdateBreadcrumb()
    }

    hidden [void] _UpdateBreadcrumb() {
        if ($this.Header) {
            $name = $(if ($this.ProjectName) { $this.ProjectName } else { "Select Project" })
            $this.Header.SetBreadcrumb(@("Home", "Projects", $name))
        }
    }

    # === Data Loading ===

    [void] LoadData() {
        if ([string]::IsNullOrWhiteSpace($this.ProjectName)) {
            if ($this.StatusBar) {
                $this.StatusBar.SetLeftText("No project selected")
                $this.StatusBar.SetRightText("")
            }
            $this.ProjectData = @{}
            $this._BuildTabs()
            return
        }

        # Load project data from store
        $project = $this.Store.GetProject($this.ProjectName)

        if ($null -eq $project) {
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("Project not found: $($this.ProjectName)")
            }
            $this.ProjectData = @{}
            $this._BuildTabs()
            return
        }

        $this.ProjectData = $project

        # DEBUG: Log available fields
        $keysDebug = @()
        if ($this.ProjectData -is [hashtable]) {
            $keysDebug = $this.ProjectData.Keys
        } else {
            $keysDebug = $this.ProjectData.PSObject.Properties.Name
        }

        # Build tabs with current data
        $this._BuildTabs()

        if ($this.StatusBar) {
            $this.StatusBar.SetLeftText("Project: $($this.ProjectName)")
        }
    }

    hidden [object] _GetValue([string]$key) {
        # Handle both hashtable and PSCustomObject
        if ($this.ProjectData -is [hashtable]) {
            if ($this.ProjectData.ContainsKey($key)) {
                return $this.ProjectData[$key]
            }
        }
        elseif ($this.ProjectData.PSObject.Properties[$key]) {
            return $this.ProjectData.$key
        }
        return $null
    }

    hidden [void] _BuildTabs() {
        # Clear existing tabs
        $this.TabPanel.Tabs.Clear()

        # Tab 1: Identity (removed ProjFolder and CAAName - they're in Files tab)
        $this.TabPanel.AddTab('Identity', @(
                @{Name = 'ID1'; Label = 'ID1'; Value = $this._GetValue('ID1'); Type = 'text' }
                @{Name = 'ID2'; Label = 'ID2'; Value = $this._GetValue('ID2'); Type = 'text' }
            ))

        # Tab 2: Request (removed RequestName and T2020 - they're in Files tab)
        $this.TabPanel.AddTab('Request', @(
                @{Name = 'AssignedDate'; Label = 'Assigned Date'; Value = $this._GetValue('AssignedDate'); Type = 'date' }
                @{Name = 'DueDate'; Label = 'Due Date'; Value = $this._GetValue('DueDate'); Type = 'date' }
                @{Name = 'BFDate'; Label = 'BF Date'; Value = $this._GetValue('BFDate'); Type = 'date' }
                @{Name = 'RequestDate'; Label = 'Request Date'; Value = $this._GetValue('RequestDate'); Type = 'date' }
            ))

        # Tab 3: Audit
        $this.TabPanel.AddTab('Audit', @(
                @{Name = 'AuditType'; Label = 'Audit Type'; Value = $this._GetValue('AuditType'); Type = 'text' }
                @{Name = 'AuditorName'; Label = 'Auditor Name'; Value = $this._GetValue('AuditorName'); Type = 'text' }
                @{Name = 'AuditorPhone'; Label = 'Auditor Phone'; Value = $this._GetValue('AuditorPhone'); Type = 'text' }
                @{Name = 'AuditorTL'; Label = 'Auditor Team Lead'; Value = $this._GetValue('AuditorTL'); Type = 'text' }
                @{Name = 'AuditorTLPhone'; Label = 'TL Phone'; Value = $this._GetValue('AuditorTLPhone'); Type = 'text' }
                @{Name = 'AuditCase'; Label = 'Audit Case'; Value = $this._GetValue('AuditCase'); Type = 'text' }
                @{Name = 'CASCase'; Label = 'CAS Case'; Value = $this._GetValue('CASCase'); Type = 'text' }
                @{Name = 'AuditStartDate'; Label = 'Audit Start Date'; Value = $this._GetValue('AuditStartDate'); Type = 'date' }
            ))

        # Tab 4: Location
        $this.TabPanel.AddTab('Location', @(
                @{Name = 'TPName'; Label = 'Third Party Name'; Value = $this._GetValue('TPName'); Type = 'text' }
                @{Name = 'TPNum'; Label = 'Third Party Number'; Value = $this._GetValue('TPNum'); Type = 'text' }
                @{Name = 'Address'; Label = 'Address'; Value = $this._GetValue('Address'); Type = 'text' }
                @{Name = 'City'; Label = 'City'; Value = $this._GetValue('City'); Type = 'text' }
                @{Name = 'Province'; Label = 'Province'; Value = $this._GetValue('Province'); Type = 'text' }
                @{Name = 'PostalCode'; Label = 'Postal Code'; Value = $this._GetValue('PostalCode'); Type = 'text' }
                @{Name = 'Country'; Label = 'Country'; Value = $this._GetValue('Country'); Type = 'text' }
            ))

        # Tab 5: Periods
        $this.TabPanel.AddTab('Periods', @(
                @{Name = 'AuditPeriodFrom'; Label = 'Audit Period From'; Value = $this._GetValue('AuditPeriodFrom'); Type = 'date' }
                @{Name = 'AuditPeriodTo'; Label = 'Audit Period To'; Value = $this._GetValue('AuditPeriodTo'); Type = 'date' }
                @{Name = 'Period1Start'; Label = 'Period 1 Start'; Value = $this._GetValue('Period1Start'); Type = 'date' }
                @{Name = 'Period1End'; Label = 'Period 1 End'; Value = $this._GetValue('Period1End'); Type = 'date' }
                @{Name = 'Period2Start'; Label = 'Period 2 Start'; Value = $this._GetValue('Period2Start'); Type = 'date' }
                @{Name = 'Period2End'; Label = 'Period 2 End'; Value = $this._GetValue('Period2End'); Type = 'date' }
                @{Name = 'Period3Start'; Label = 'Period 3 Start'; Value = $this._GetValue('Period3Start'); Type = 'date' }
                @{Name = 'Period3End'; Label = 'Period 3 End'; Value = $this._GetValue('Period3End'); Type = 'date' }
                @{Name = 'Period4Start'; Label = 'Period 4 Start'; Value = $this._GetValue('Period4Start'); Type = 'date' }
                @{Name = 'Period4End'; Label = 'Period 4 End'; Value = $this._GetValue('Period4End'); Type = 'date' }
                @{Name = 'Period5Start'; Label = 'Period 5 Start'; Value = $this._GetValue('Period5Start'); Type = 'date' }
                @{Name = 'Period5End'; Label = 'Period 5 End'; Value = $this._GetValue('Period5End'); Type = 'date' }
            ))

        # Tab 6: More (Contacts, Software, Misc)
        $this.TabPanel.AddTab('More', @(
                # Contact 1
                @{Name = 'Contact1Name'; Label = 'Contact 1 Name'; Value = $this._GetValue('Contact1Name'); Type = 'text' }
                @{Name = 'Contact1Title'; Label = 'Contact 1 Title'; Value = $this._GetValue('Contact1Title'); Type = 'text' }
                @{Name = 'Contact1Phone'; Label = 'Contact 1 Phone'; Value = $this._GetValue('Contact1Phone'); Type = 'text' }
                @{Name = 'Contact1Email'; Label = 'Contact 1 Email'; Value = $this._GetValue('Contact1Email'); Type = 'text' }
                @{Name = 'Contact1Fax'; Label = 'Contact 1 Fax'; Value = $this._GetValue('Contact1Fax'); Type = 'text' }
                # Contact 2
                @{Name = 'Contact2Name'; Label = 'Contact 2 Name'; Value = $this._GetValue('Contact2Name'); Type = 'text' }
                @{Name = 'Contact2Title'; Label = 'Contact 2 Title'; Value = $this._GetValue('Contact2Title'); Type = 'text' }
                @{Name = 'Contact2Phone'; Label = 'Contact 2 Phone'; Value = $this._GetValue('Contact2Phone'); Type = 'text' }
                @{Name = 'Contact2Email'; Label = 'Contact 2 Email'; Value = $this._GetValue('Contact2Email'); Type = 'text' }
                @{Name = 'Contact2Fax'; Label = 'Contact 2 Fax'; Value = $this._GetValue('Contact2Fax'); Type = 'text' }
                # Software 1
                @{Name = 'Software1Name'; Label = 'Software 1 Name'; Value = $this._GetValue('Software1Name'); Type = 'text' }
                @{Name = 'Software1Version'; Label = 'Software 1 Version'; Value = $this._GetValue('Software1Version'); Type = 'text' }
                @{Name = 'Software1Vendor'; Label = 'Software 1 Vendor'; Value = $this._GetValue('Software1Vendor'); Type = 'text' }
                # Software 2
                @{Name = 'Software2Name'; Label = 'Software 2 Name'; Value = $this._GetValue('Software2Name'); Type = 'text' }
                @{Name = 'Software2Version'; Label = 'Software 2 Version'; Value = $this._GetValue('Software2Version'); Type = 'text' }
                @{Name = 'Software2Vendor'; Label = 'Software 2 Vendor'; Value = $this._GetValue('Software2Vendor'); Type = 'text' }
                # Misc
                @{Name = 'AuditProgram'; Label = 'Audit Program'; Value = $this._GetValue('AuditProgram'); Type = 'text' }
                @{Name = 'Comments'; Label = 'Comments'; Value = $this._GetValue('Comments'); Type = 'text' }
                @{Name = 'FXInfo'; Label = 'FX Info'; Value = $this._GetValue('FXInfo'); Type = 'text' }
                @{Name = 'ShipToAddress'; Label = 'Ship To Address'; Value = $this._GetValue('ShipToAddress'); Type = 'text' }
            ))

        # Tab 7: Files (Notes, Checklists, Project Files)
        $this.TabPanel.AddTab('Files', @(
                @{Name = '_action_notes'; Label = '> Notes'; Value = 'View and manage project notes'; Type = 'readonly'; IsAction = $true }
                @{Name = '_action_assign_note'; Label = '> Assign Note'; Value = 'Assign existing note to project'; Type = 'readonly'; IsAction = $true }
                @{Name = '_action_checklists'; Label = '> Checklists'; Value = 'View and manage project checklists'; Type = 'readonly'; IsAction = $true }
                @{Name = '_action_assign_checklist'; Label = '> Assign Checklist'; Value = 'Assign existing checklist to project'; Type = 'readonly'; IsAction = $true }
                @{Name = '_separator1'; Label = '--- Project Files ---'; Value = ''; Type = 'readonly' }
                @{Name = 'T2020'; Label = 'T2020 File'; Value = $this._GetValue('T2020'); Type = 'text'; Hint = 'Path to T2020 file (press B to browse)' }
                @{Name = '_action_t2020_browse'; Label = '> Browse T2020'; Value = 'Select file'; Type = 'readonly'; IsAction = $true }
                @{Name = '_action_t2020_open'; Label = '> Open T2020'; Value = 'Open in Notepad'; Type = 'readonly'; IsAction = $true }
                @{Name = '_separator2'; Label = ''; Value = ''; Type = 'readonly' }
                @{Name = 'CAAName'; Label = 'CAA File'; Value = $this._GetValue('CAAName'); Type = 'text'; Hint = 'Path to CAA file (press B to browse)' }
                @{Name = '_action_caa_browse'; Label = '> Browse CAA'; Value = 'Select file'; Type = 'readonly'; IsAction = $true }
                @{Name = '_action_caa_open'; Label = '> Open CAA'; Value = 'Open in Excel'; Type = 'readonly'; IsAction = $true }
                @{Name = '_separator3'; Label = ''; Value = ''; Type = 'readonly' }
                @{Name = 'RequestName'; Label = 'Request File'; Value = $this._GetValue('RequestName'); Type = 'text'; Hint = 'Path to Request file (press B to browse)' }
                @{Name = '_action_request_browse'; Label = '> Browse Request'; Value = 'Select file'; Type = 'readonly'; IsAction = $true }
                @{Name = '_action_request_open'; Label = '> Open Request'; Value = 'Open in Excel'; Type = 'readonly'; IsAction = $true }
                @{Name = '_separator4'; Label = ''; Value = ''; Type = 'readonly' }
                @{Name = 'ProjFolder'; Label = 'Project Folder'; Value = $this._GetValue('ProjFolder'); Type = 'text'; Hint = 'Path to project folder (press B to browse)' }
                @{Name = '_action_folder_browse'; Label = '> Browse Folder'; Value = 'Select folder'; Type = 'readonly'; IsAction = $true }
                @{Name = '_action_folder_open'; Label = '> Open Folder'; Value = 'Open in File Explorer'; Type = 'readonly'; IsAction = $true }
            ))
    }

    # === Saving ===

    [void] SaveChanges() {
        # Get all field values from TabPanel
        $values = $this.TabPanel.GetAllValues()

        if ($global:PmcTuiLogFile) {
            # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: START - project='$($this.ProjectName)' fields=$($values.Count)"
            # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: Field values: $($values.Keys -join ', ')"
            # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: Store.AutoSave=$($this.Store.AutoSave)"
        }

        # Get project BEFORE update to compare
        $projectBefore = $this.Store.GetProject($this.ProjectName)
        if ($global:PmcTuiLogFile -and $projectBefore) {
            # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: BEFORE update - ID1='$($projectBefore.ID1)'"
        }

        # Update project in store (this updates in-memory but doesn't persist)
        $success = $this.Store.UpdateProject($this.ProjectName, $values)

        if ($success) {
            # Get project AFTER update to verify
            $projectAfter = $this.Store.GetProject($this.ProjectName)
            if ($global:PmcTuiLogFile -and $projectAfter) {
                # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: AFTER UpdateProject - ID1='$($projectAfter.ID1)'"
            }

            # FORCE persist to disk (UpdateProject already persists if AutoSave is true)
            # But we double-check by explicitly calling SaveData
            if (-not $this.Store.SaveData()) {
                if ($this.StatusBar) {
                    $this.StatusBar.SetRightText("Save to disk failed: $($this.Store.LastError)")
                }
                if ($global:PmcTuiLogFile) {
                    # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: SaveData FAILED - $($this.Store.LastError)"
                }
                return
            }

            # Verify file on disk
            if ($global:PmcTuiLogFile) {
                # Get actual task file path from Pmc module
                $pmcModule = Get-Module -Name 'Pmc.Strict'
                $taskFile = & $pmcModule { Get-PmcTaskFilePath }
                # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: Verifying tasks file: $taskFile"
                if (Test-Path $taskFile) {
                    try {
                        $fileContent = Get-Content $taskFile -Raw | ConvertFrom-Json
                        $savedProject = $fileContent.projects | Where-Object { $_.name -eq $this.ProjectName } | Select-Object -First 1
                        if ($savedProject) {
                            # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: File verification SUCCESS - project found, ID1='$($savedProject.ID1)'"
                        }
                        else {
                            # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: File verification FAILED - PROJECT NOT FOUND (projects count=$($fileContent.projects.Count))"
                        }
                    }
                    catch {
                        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: File verification ERROR - $_"
                    }
                }
                else {
                    # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: File verification FAILED - FILE DOES NOT EXIST at $taskFile"
                }
            }

            # Update status
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("Saved")
            }
            if ($global:PmcTuiLogFile) {
                # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: SUCCESS - persisted to disk"
            }
        }
        else {
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("Save failed: $($this.Store.LastError)")
            }
            if ($global:PmcTuiLogFile) {
                # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.SaveChanges: UpdateProject FAILED - $($this.Store.LastError)"
            }
        }
    }

    # === Event Handlers ===

    [void] OnTabChanged([int]$tabIndex) {
        # Call base implementation
        ([TabbedScreen]$this).OnTabChanged($tabIndex)

        # Custom handling - could add tab-specific logic here
    }

    [void] OnFieldEdited($field, $newValue) {
        # Check if this is an action field (Files tab actions)
        if ($field.Name -match '^_action_') {
            $this._HandleFileAction($field.Name)
            return
        }

        # Auto-save on each field edit
        if ($global:PmcTuiLogFile) {
            # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4.OnFieldEdited: field=$($field.Name) value='$newValue' - auto-saving"
        }
        $this.SaveChanges()
        # $this.SaveChanges()

        # Or just log the change
        # Write-PmcTuiLog "Field '$($field.Name)' changed to: $newValue" "DEBUG"
    }

    # === File Actions ===

    hidden [void] _HandleFileAction([string]$action) {
        # Write-PmcTuiLog "ProjectInfoScreenV4._HandleFileAction: action=$action ProjectName='$($this.ProjectName)'" "INFO"
        switch ($action) {
            '_action_notes' {
                # Open NotesMenuScreen for this project
                # Write-PmcTuiLog "ProjectInfoScreenV4._HandleFileAction: Opening NotesMenuScreen for project='$($this.ProjectName)'" "INFO"
                . "$PSScriptRoot/NotesMenuScreen.ps1"
                $notesScreen = New-Object NotesMenuScreen -ArgumentList "project", $this.ProjectName, $this.ProjectName
                $global:PmcApp.PushScreen($notesScreen)
            }
            '_action_assign_note' {
                # Show picker to assign existing note to this project
                $this._AssignNote()
            }
            '_action_checklists' {
                # Open ChecklistsMenuScreen for this project
                # Write-PmcTuiLog "ProjectInfoScreenV4._HandleFileAction: Opening ChecklistsMenuScreen for project='$($this.ProjectName)'" "INFO"
                . "$PSScriptRoot/ChecklistsMenuScreen.ps1"
                $checklistsScreen = New-Object ChecklistsMenuScreen -ArgumentList "project", $this.ProjectName, $this.ProjectName
                $global:PmcApp.PushScreen($checklistsScreen)
            }
            '_action_assign_checklist' {
                # Show picker to create checklist instance from template for this project
                $this._AssignChecklist()
            }
            '_action_t2020_browse' {
                $this._BrowseForFile('T2020', $false)
            }
            '_action_t2020_open' {
                $path = $this._GetValue('T2020')
                $this._OpenFile($path, 'notepad')
            }
            '_action_caa_browse' {
                $this._BrowseForFile('CAAName', $false)
            }
            '_action_caa_open' {
                $path = $this._GetValue('CAAName')
                $this._OpenFile($path, 'excel')
            }
            '_action_request_browse' {
                $this._BrowseForFile('RequestName', $false)
            }
            '_action_request_open' {
                $path = $this._GetValue('RequestName')
                $this._OpenFile($path, 'excel')
            }
            '_action_folder_browse' {
                $this._BrowseForFile('ProjFolder', $true)
            }
            '_action_folder_open' {
                $path = $this._GetValue('ProjFolder')
                $this._OpenFolder($path)
            }
        }
    }

    hidden [void] _BrowseForFile([string]$fieldName, [bool]$directoriesOnly) {
        # Get current value as starting path
        $startPath = $this._GetValue($fieldName)
        if ([string]::IsNullOrWhiteSpace($startPath)) {
            $startPath = [Environment]::GetFolderPath('UserProfile')
        }

        # Create and show file picker
        $this.FilePicker = [PmcFilePicker]::new($startPath, $directoriesOnly)
        $this.ShowFilePicker = $true
        $this.FilePickerFieldName = $fieldName
    }

    hidden [void] _OpenFile([string]$path, [string]$app) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("File path not set")
            }
            return
        }

        if (-not (Test-Path $path)) {
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("File not found: $path")
            }
            return
        }

        try {
            $isWin = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

            if ($app -eq 'notepad') {
                if ($isWin) {
                    Start-Process notepad.exe -ArgumentList $path
                }
                else {
                    Start-Process xdg-open -ArgumentList $path
                }
            }
            elseif ($app -eq 'excel') {
                if ($isWin) {
                    # Try to find Excel
                    if (Get-Command excel.exe -ErrorAction SilentlyContinue) {
                        Start-Process excel.exe -ArgumentList $path
                    }
                    else {
                        # Fallback to default handler
                        Start-Process $path
                    }
                }
                else {
                    # Try LibreOffice Calc or default handler
                    if (Get-Command libreoffice -ErrorAction SilentlyContinue) {
                        Start-Process libreoffice -ArgumentList "--calc", $path
                    }
                    else {
                        Start-Process xdg-open -ArgumentList $path
                    }
                }
            }
            else {
                # Default handler
                Start-Process $path
            }

            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("Opened: $path")
            }
        }
        catch {
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("Error opening file: $($_.Exception.Message)")
            }
        }
    }

    hidden [void] _OpenFolder([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("Folder path not set")
            }
            return
        }

        if (-not (Test-Path $path)) {
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("Folder not found: $path")
            }
            return
        }

        try {
            $isWin = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

            if ($isWin) {
                Start-Process explorer.exe -ArgumentList $path
            }
            else {
                Start-Process xdg-open -ArgumentList $path
            }

            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("Opened folder: $path")
            }
        }
        catch {
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("Error opening folder: $($_.Exception.Message)")
            }
        }
    }

    hidden [void] _AssignNote() {
        # Load NoteService to get all notes
        . "$PSScriptRoot/../services/NoteService.ps1"
        $noteService = [NoteService]::GetInstance()

        # Get all notes
        $allNotes = @($noteService.GetAllNotes())

        if ($allNotes.Count -eq 0) {
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("No notes available to assign")
            }
            return
        }

        # Create a simple picker screen to select a note
        . "$PSScriptRoot/NotePickerScreen.ps1"
        $pickerScreen = New-Object NotePickerScreen -ArgumentList $allNotes, $this.ProjectName

        # Set callback for when note is selected
        $self = $this
        $pickerScreen.OnNoteSelected = {
            param($noteId)
            # Reassign the note to this project
            $noteService.UpdateNoteMetadata($noteId, @{
                    owner_type = "project"
                    owner_id   = $self.ProjectName
                })

            if ($self.StatusBar) {
                $self.StatusBar.SetRightText("Note assigned to project: $($self.ProjectName)")
            }
        }.GetNewClosure()

        $global:PmcApp.PushScreen($pickerScreen)
    }

    hidden [void] _AssignChecklist() {
        # Load ChecklistService to get all templates
        . "$PSScriptRoot/../services/ChecklistService.ps1"
        $checklistService = [ChecklistService]::GetInstance()

        # Get all templates
        $templates = @($checklistService.GetAllTemplates())

        if ($templates.Count -eq 0) {
            if ($this.StatusBar) {
                $this.StatusBar.SetRightText("No checklist templates available")
            }
            return
        }

        # Create a simple picker screen to select a template
        . "$PSScriptRoot/ChecklistTemplatePickerScreen.ps1"
        $pickerScreen = New-Object ChecklistTemplatePickerScreen -ArgumentList $templates, $this.ProjectName

        # Set callback for when template is selected
        $self = $this
        $pickerScreen.OnTemplateSelected = {
            param($templateId)
            # Create instance from template for this project
            $instance = $checklistService.CreateInstanceFromTemplate($templateId, "project", $self.ProjectName)

            if ($self.StatusBar) {
                $instanceTitle = $(if ($instance -and $instance.PSObject.Properties['title']) { $instance.title } else { 'Checklist' })
                $self.StatusBar.SetRightText("Checklist '$instanceTitle' created for project: $($self.ProjectName)")
            }
        }.GetNewClosure()

        $global:PmcApp.PushScreen($pickerScreen)
    }

    # === Rendering Override ===
    [void] RenderContentToEngine([object]$engine) {
        # Always render base tabbed screen
        ([TabbedScreen]$this).RenderContentToEngine($engine)

        # File picker as overlay widget on top
        if ($this.ShowFilePicker -and $null -ne $this.FilePicker) {
            # Position as centered dialog widget
            $this.FilePicker.X = [Math]::Max(1, [Math]::Floor(($engine.Width - 70) / 2))
            $this.FilePicker.Y = [Math]::Max(1, [Math]::Floor(($engine.Height - 22) / 2))
            $this.FilePicker.Width = 70
            $this.FilePicker.Height = 22

            # Render on top layer
            if ($engine.PSObject.Methods['BeginLayer']) {
                $engine.BeginLayer(20)
            }

            # Render the file picker widget
            if ($this.FilePicker.PSObject.Methods['RenderToEngine']) {
                $this.FilePicker.RenderToEngine($engine)
            }

            if ($engine.PSObject.Methods['EndLayer']) {
                $engine.EndLayer()
            }
        }
    }

    # === Input Override ===
    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # CRITICAL: Handle file picker BEFORE calling parent to prevent Enter key from being intercepted
        if ($this.ShowFilePicker -and $null -ne $this.FilePicker) {
            if ($global:PmcTuiLogFile) {
                # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4: File picker active, routing key=$($keyInfo.Key) to picker"
            }

            # Route input to file picker
            $handled = $this.FilePicker.HandleInput($keyInfo)

            if ($global:PmcTuiLogFile) {
                # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4: After HandleInput - handled=$handled IsComplete=$($this.FilePicker.IsComplete)"
            }

            # Check if file picker completed
            if ($this.FilePicker.IsComplete) {
                if ($global:PmcTuiLogFile) {
                    # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4: File picker completed - Result=$($this.FilePicker.Result) SelectedPath='$($this.FilePicker.SelectedPath)' FieldName='$($this.FilePickerFieldName)'"
                }

                if ($this.FilePicker.Result) {
                    # User selected something
                    $selectedPath = $this.FilePicker.SelectedPath

                    if ($global:PmcTuiLogFile) {
                        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4: Updating field '$($this.FilePickerFieldName)' with value '$selectedPath'"
                    }

                    $this.TabPanel.UpdateFieldValue($this.FilePickerFieldName, $selectedPath)

                    if ($global:PmcTuiLogFile) {
                        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4: Field updated successfully, saving changes..."
                    }

                    # Save the changes to disk
                    try {
                        $this.SaveChanges()
                        if ($this.StatusBar) {
                            $this.StatusBar.SetRightText("Selected and saved: $selectedPath")
                        }
                    }
                    catch {
                        if ($this.StatusBar) {
                            $this.StatusBar.SetRightText("Selected but save failed: $_")
                        }
                        if ($global:PmcTuiLogFile) {
                            # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4: SaveChanges failed - $_"
                        }
                    }
                }
                else {
                    if ($global:PmcTuiLogFile) {
                        # Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ProjectInfoScreenV4: File picker cancelled"
                    }
                    if ($this.StatusBar) {
                        $this.StatusBar.SetRightText("Cancelled")
                    }
                }
                # Close file picker
                $this.ShowFilePicker = $false
                $this.FilePicker = $null
                $this.FilePickerFieldName = ""

                # Force full screen re-render to clear file picker overlay
                $this.NeedsClear = $true
                if ($global:PmcApp) {
                    $global:PmcApp.IsDirty = $true
                }
            }

            # IMPORTANT: Return true to prevent parent from handling the key
            # This ensures Enter goes to the file picker, not TabbedScreen.EditCurrentField()
            return $true
        }

        # Otherwise, call parent handler
        return ([TabbedScreen]$this).HandleKeyPress($keyInfo)
    }
}

# Export
Export-ModuleMember -Variable @()