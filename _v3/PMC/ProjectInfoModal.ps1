# ProjectInfoModal.ps1 - Project details modal with 7 tabs
# Adapts OLDTUI's ProjectInfoScreenV4 for V3 architecture
# 57 fields organized into: Identity, Request, Audit, Location, Periods, More, Files

class ProjectInfoModal {
    hidden [TabbedModal]$_modal
    hidden [hashtable]$_project = $null
    hidden [FluxStore]$_store
    hidden [HybridRenderEngine]$_engine  # Need engine reference for sub-modals
    hidden [FilePicker]$_filePicker
    hidden [bool]$_filePickerActive = $false
    hidden [string]$_filePickerField = ""
    hidden [NotesModal]$_notesModal
    hidden [bool]$_notesActive = $false
    hidden [ChecklistsModal]$_checklistsModal
    hidden [bool]$_checklistsActive = $false
    
    ProjectInfoModal([FluxStore]$store) {
        $this._store = $store
        $this._modal = [TabbedModal]::new("Project Information")
        $this._filePicker = [FilePicker]::new()
        $this._notesModal = [NotesModal]::new($store)
        $this._checklistsModal = [ChecklistsModal]::new($store)
        
        $self = $this
        $this._modal.SetOnSave({
            param($fieldName, $value)
            $self._SaveField($fieldName, $value)
        }.GetNewClosure())
        
        $this._modal.SetOnAction({
            param($actionName)
            $self._HandleAction($actionName)
        }.GetNewClosure())
    }
    
    [void] Open([hashtable]$project) {
        $this._project = $project
        $this._BuildTabs()
        $this._modal.Show()
    }
    
    [void] Close() {
        $this._modal.Hide()
    }
    
    [bool] IsVisible() {
        return $this._modal.IsVisible()
    }
    
    [void] Render([HybridRenderEngine]$engine) {
        $this._engine = $engine  # Store for sub-modals
        $this._modal.Render($engine)
        
        # Render FilePicker on top if active
        if ($this._filePickerActive) {
            $this._filePicker.Render($engine)
        }
        
        # Render NotesModal on top if active
        if ($this._notesActive) {
            $this._notesModal.Render($engine)
        }
        
        # Render ChecklistsModal on top if active
        if ($this._checklistsActive) {
            $this._checklistsModal.Render($engine)
        }
    }
    
    [string] HandleInput([ConsoleKeyInfo]$key) {
        # NotesModal takes priority
        if ($this._notesActive) {
            $result = $this._notesModal.HandleInput($key, $this._engine)
            if ($result -eq "Close") {
                $this._notesActive = $false
            }
            return "Continue"
        }
        
        # ChecklistsModal takes priority
        if ($this._checklistsActive) {
            $result = $this._checklistsModal.HandleInput($key)
            if ($result -eq "Close") {
                $this._checklistsActive = $false
            }
            return "Continue"
        }
        
        # FilePicker takes priority
        if ($this._filePickerActive) {
            $result = $this._filePicker.HandleInput($key)
            
            if ($result -eq "Selected") {
                $selectedPath = $this._filePicker.GetResult()
                if ($selectedPath) {
                    # Update the field
                    $this._modal.UpdateFieldValue($this._filePickerField, $selectedPath)
                    $this._SaveField($this._filePickerField, $selectedPath)
                }
                $this._filePickerActive = $false
            }
            elseif ($result -eq "Cancelled") {
                $this._filePickerActive = $false
            }
            
            return "Continue"
        }
        
        $result = $this._modal.HandleInput($key)
        
        if ($result -eq "SaveAll") {
            $this._SaveAllFields()
        }
        
        return $result
    }
    
    hidden [object] _GetValue([string]$key) {
        if ($null -eq $this._project) { return $null }
        if ($this._project.ContainsKey($key)) {
            return $this._project[$key]
        }
        return $null
    }
    
    hidden [void] _BuildTabs() {
        $this._modal.ClearTabs()
        
        # Tab 1: Identity
        $this._modal.AddTab('Identity', @(
            @{ Name = 'ID1'; Label = 'Project ID'; Value = $this._GetValue('ID1'); Type = 'text' }
            @{ Name = 'ID2'; Label = 'Secondary ID'; Value = $this._GetValue('ID2'); Type = 'text' }
            @{ Name = 'name'; Label = 'Project Name'; Value = $this._GetValue('name'); Type = 'text' }
            @{ Name = 'description'; Label = 'Description'; Value = $this._GetValue('description'); Type = 'text' }
        ))
        
        # Tab 2: Request
        $this._modal.AddTab('Request', @(
            @{ Name = 'RequestType'; Label = 'Request Type'; Value = $this._GetValue('RequestType'); Type = 'text' }
            @{ Name = 'Priority'; Label = 'Priority'; Value = $this._GetValue('Priority'); Type = 'text' }
            @{ Name = 'status'; Label = 'Status'; Value = $this._GetValue('status'); Type = 'text' }
            @{ Name = 'DueDate'; Label = 'Due Date'; Value = $this._GetValue('DueDate'); Type = 'date' }
            @{ Name = 'BFDate'; Label = 'BF Date'; Value = $this._GetValue('BFDate'); Type = 'date' }
            @{ Name = 'RequestDate'; Label = 'Request Date'; Value = $this._GetValue('RequestDate'); Type = 'date' }
        ))
        
        # Tab 3: Audit
        $this._modal.AddTab('Audit', @(
            @{ Name = 'AuditType'; Label = 'Audit Type'; Value = $this._GetValue('AuditType'); Type = 'text' }
            @{ Name = 'AuditorName'; Label = 'Auditor Name'; Value = $this._GetValue('AuditorName'); Type = 'text' }
            @{ Name = 'AuditorPhone'; Label = 'Auditor Phone'; Value = $this._GetValue('AuditorPhone'); Type = 'text' }
            @{ Name = 'AuditorTL'; Label = 'Auditor Team Lead'; Value = $this._GetValue('AuditorTL'); Type = 'text' }
            @{ Name = 'AuditorTLPhone'; Label = 'TL Phone'; Value = $this._GetValue('AuditorTLPhone'); Type = 'text' }
            @{ Name = 'AuditCase'; Label = 'Audit Case'; Value = $this._GetValue('AuditCase'); Type = 'text' }
            @{ Name = 'CASCase'; Label = 'CAS Case'; Value = $this._GetValue('CASCase'); Type = 'text' }
            @{ Name = 'AuditStartDate'; Label = 'Audit Start Date'; Value = $this._GetValue('AuditStartDate'); Type = 'date' }
        ))
        
        # Tab 4: Location
        $this._modal.AddTab('Location', @(
            @{ Name = 'TPName'; Label = 'Third Party Name'; Value = $this._GetValue('TPName'); Type = 'text' }
            @{ Name = 'TPNum'; Label = 'Third Party Number'; Value = $this._GetValue('TPNum'); Type = 'text' }
            @{ Name = 'Address'; Label = 'Address'; Value = $this._GetValue('Address'); Type = 'text' }
            @{ Name = 'City'; Label = 'City'; Value = $this._GetValue('City'); Type = 'text' }
            @{ Name = 'Province'; Label = 'Province'; Value = $this._GetValue('Province'); Type = 'text' }
            @{ Name = 'PostalCode'; Label = 'Postal Code'; Value = $this._GetValue('PostalCode'); Type = 'text' }
            @{ Name = 'Country'; Label = 'Country'; Value = $this._GetValue('Country'); Type = 'text' }
        ))
        
        # Tab 5: Periods
        $this._modal.AddTab('Periods', @(
            @{ Name = 'AuditPeriodFrom'; Label = 'Audit Period From'; Value = $this._GetValue('AuditPeriodFrom'); Type = 'date' }
            @{ Name = 'AuditPeriodTo'; Label = 'Audit Period To'; Value = $this._GetValue('AuditPeriodTo'); Type = 'date' }
            @{ Name = 'Period1Start'; Label = 'Period 1 Start'; Value = $this._GetValue('Period1Start'); Type = 'date' }
            @{ Name = 'Period1End'; Label = 'Period 1 End'; Value = $this._GetValue('Period1End'); Type = 'date' }
            @{ Name = 'Period2Start'; Label = 'Period 2 Start'; Value = $this._GetValue('Period2Start'); Type = 'date' }
            @{ Name = 'Period2End'; Label = 'Period 2 End'; Value = $this._GetValue('Period2End'); Type = 'date' }
            @{ Name = 'Period3Start'; Label = 'Period 3 Start'; Value = $this._GetValue('Period3Start'); Type = 'date' }
            @{ Name = 'Period3End'; Label = 'Period 3 End'; Value = $this._GetValue('Period3End'); Type = 'date' }
            @{ Name = 'Period4Start'; Label = 'Period 4 Start'; Value = $this._GetValue('Period4Start'); Type = 'date' }
            @{ Name = 'Period4End'; Label = 'Period 4 End'; Value = $this._GetValue('Period4End'); Type = 'date' }
            @{ Name = 'Period5Start'; Label = 'Period 5 Start'; Value = $this._GetValue('Period5Start'); Type = 'date' }
            @{ Name = 'Period5End'; Label = 'Period 5 End'; Value = $this._GetValue('Period5End'); Type = 'date' }
        ))
        
        # Tab 6: More (Contacts, Software, Misc)
        $this._modal.AddTab('More', @(
            # Contact 1
            @{ Name = '_separator_c1'; Label = '--- Contact 1 ---'; Value = ''; Type = 'readonly' }
            @{ Name = 'Contact1Name'; Label = 'Name'; Value = $this._GetValue('Contact1Name'); Type = 'text' }
            @{ Name = 'Contact1Title'; Label = 'Title'; Value = $this._GetValue('Contact1Title'); Type = 'text' }
            @{ Name = 'Contact1Phone'; Label = 'Phone'; Value = $this._GetValue('Contact1Phone'); Type = 'text' }
            @{ Name = 'Contact1Email'; Label = 'Email'; Value = $this._GetValue('Contact1Email'); Type = 'text' }
            @{ Name = 'Contact1Fax'; Label = 'Fax'; Value = $this._GetValue('Contact1Fax'); Type = 'text' }
            # Contact 2
            @{ Name = '_separator_c2'; Label = '--- Contact 2 ---'; Value = ''; Type = 'readonly' }
            @{ Name = 'Contact2Name'; Label = 'Name'; Value = $this._GetValue('Contact2Name'); Type = 'text' }
            @{ Name = 'Contact2Title'; Label = 'Title'; Value = $this._GetValue('Contact2Title'); Type = 'text' }
            @{ Name = 'Contact2Phone'; Label = 'Phone'; Value = $this._GetValue('Contact2Phone'); Type = 'text' }
            @{ Name = 'Contact2Email'; Label = 'Email'; Value = $this._GetValue('Contact2Email'); Type = 'text' }
            @{ Name = 'Contact2Fax'; Label = 'Fax'; Value = $this._GetValue('Contact2Fax'); Type = 'text' }
            # Software
            @{ Name = '_separator_sw'; Label = '--- Software ---'; Value = ''; Type = 'readonly' }
            @{ Name = 'Software1Name'; Label = 'Software 1'; Value = $this._GetValue('Software1Name'); Type = 'text' }
            @{ Name = 'Software1Version'; Label = 'Version'; Value = $this._GetValue('Software1Version'); Type = 'text' }
            @{ Name = 'Software2Name'; Label = 'Software 2'; Value = $this._GetValue('Software2Name'); Type = 'text' }
            @{ Name = 'Software2Version'; Label = 'Version'; Value = $this._GetValue('Software2Version'); Type = 'text' }
            # Misc
            @{ Name = '_separator_misc'; Label = '--- Miscellaneous ---'; Value = ''; Type = 'readonly' }
            @{ Name = 'AuditProgram'; Label = 'Audit Program'; Value = $this._GetValue('AuditProgram'); Type = 'text' }
            @{ Name = 'Comments'; Label = 'Comments'; Value = $this._GetValue('Comments'); Type = 'text' }
            @{ Name = 'FXInfo'; Label = 'FX Info'; Value = $this._GetValue('FXInfo'); Type = 'text' }
            @{ Name = 'ShipToAddress'; Label = 'Ship To Address'; Value = $this._GetValue('ShipToAddress'); Type = 'text' }
        ))
        
        # Tab 7: Files
        $this._modal.AddTab('Files', @(
            @{ Name = '_separator_notes'; Label = '--- Notes & Checklists ---'; Value = ''; Type = 'readonly' }
            @{ Name = '_action_notes'; Label = '> View Notes'; Value = 'Project notes'; Type = 'readonly'; IsAction = $true }
            @{ Name = '_action_checklists'; Label = '> View Checklists'; Value = 'Project checklists'; Type = 'readonly'; IsAction = $true }
            @{ Name = '_separator_files'; Label = '--- Project Files ---'; Value = ''; Type = 'readonly' }
            @{ Name = 'T2020'; Label = 'T2020 File'; Value = $this._GetValue('T2020'); Type = 'text' }
            @{ Name = '_action_t2020_browse'; Label = '> Browse T2020...'; Value = 'Select file'; Type = 'readonly'; IsAction = $true }
            @{ Name = '_action_t2020_open'; Label = '> Open T2020'; Value = 'Open in editor'; Type = 'readonly'; IsAction = $true }
            @{ Name = 'CAAName'; Label = 'CAA File'; Value = $this._GetValue('CAAName'); Type = 'text' }
            @{ Name = '_action_caa_browse'; Label = '> Browse CAA...'; Value = 'Select file'; Type = 'readonly'; IsAction = $true }
            @{ Name = '_action_caa_open'; Label = '> Open CAA'; Value = 'Open in Excel'; Type = 'readonly'; IsAction = $true }
            @{ Name = 'RequestName'; Label = 'Request File'; Value = $this._GetValue('RequestName'); Type = 'text' }
            @{ Name = '_action_request_browse'; Label = '> Browse Request...'; Value = 'Select file'; Type = 'readonly'; IsAction = $true }
            @{ Name = '_action_request_open'; Label = '> Open Request'; Value = 'Open in Excel'; Type = 'readonly'; IsAction = $true }
            @{ Name = 'ProjFolder'; Label = 'Project Folder'; Value = $this._GetValue('ProjFolder'); Type = 'text' }
            @{ Name = '_action_folder_browse'; Label = '> Browse Folder...'; Value = 'Select folder'; Type = 'readonly'; IsAction = $true }
            @{ Name = '_action_folder_open'; Label = '> Open Folder'; Value = 'Open in file manager'; Type = 'readonly'; IsAction = $true }
            @{ Name = '_separator_excel'; Label = '--- Excel Integration ---'; Value = ''; Type = 'readonly' }
            @{ Name = '_action_excel_import'; Label = '> Import from Excel'; Value = 'Fill fields from Excel'; Type = 'readonly'; IsAction = $true }
            @{ Name = '_action_text_export'; Label = '> Export to T2020.txt'; Value = 'Generate text file'; Type = 'readonly'; IsAction = $true }
        ))
    }
    
    hidden [void] _SaveField([string]$fieldName, [object]$value) {
        if ($null -eq $this._project) { return }
        
        # Update in-memory project
        $this._project[$fieldName] = $value
        
        # Dispatch update to store
        $this._store.Dispatch([ActionType]::UPDATE_ITEM, @{
            Type = "projects"
            Id = $this._project['id']
            Changes = @{ $fieldName = $value }
        })
        
        [Logger]::Log("ProjectInfoModal: Saved field $fieldName = $value")
    }
    
    hidden [void] _SaveAllFields() {
        $values = $this._modal.GetAllValues()
        
        foreach ($key in $values.Keys) {
            $this._project[$key] = $values[$key]
        }
        
        $this._store.Dispatch([ActionType]::UPDATE_ITEM, @{
            Type = "projects"
            Id = $this._project['id']
            Changes = $values
        })
        
        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
        [Logger]::Log("ProjectInfoModal: Saved all fields")
    }
    
    hidden [void] _HandleAction([string]$actionName) {
        [Logger]::Log("ProjectInfoModal: Action triggered - $actionName")
        
        switch ($actionName) {
            '_action_notes' {
                $this._notesModal.Open($this._project['id'], $this._project['name'])
                $this._notesActive = $true
            }
            '_action_checklists' {
                $this._checklistsModal.Open($this._project['id'], $this._project['name'])
                $this._checklistsActive = $true
            }
            # Browse actions
            '_action_t2020_browse' {
                $this._BrowseFile('T2020', $false, 'Select T2020 File')
            }
            '_action_caa_browse' {
                $this._BrowseFile('CAAName', $false, 'Select CAA File')
            }
            '_action_request_browse' {
                $this._BrowseFile('RequestName', $false, 'Select Request File')
            }
            '_action_folder_browse' {
                $this._BrowseFile('ProjFolder', $true, 'Select Project Folder')
            }
            # Open actions
            '_action_t2020_open' {
                $path = $this._GetValue('T2020')
                $this._OpenFile($path)
            }
            '_action_caa_open' {
                $path = $this._GetValue('CAAName')
                $this._OpenFile($path)
            }
            '_action_request_open' {
                $path = $this._GetValue('RequestName')
                $this._OpenFile($path)
            }
            '_action_folder_open' {
                $path = $this._GetValue('ProjFolder')
                $this._OpenFolder($path)
            }
            '_action_excel_import' {
                # Excel import requires COM automation (Windows only)
                $isWin = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
                if (-not $isWin) {
                    [Logger]::Log("ProjectInfoModal: Excel import requires Windows (COM automation)")
                } else {
                    [Logger]::Log("ProjectInfoModal: Excel import - profile system not yet ported")
                }
            }
            '_action_text_export' {
                $this._ExportToTextFile()
            }
        }
    }
    
    hidden [void] _ExportToTextFile() {
        if ($null -eq $this._project) {
            [Logger]::Log("ProjectInfoModal: No project to export")
            return
        }
        
        try {
            $exportService = [TextExportService]::new($PSScriptRoot)
            $result = $exportService.ExportProject($this._project, "T2020.txt")
            
            if ($result.success) {
                [Logger]::Log("ProjectInfoModal: Exported to $($result.output_path)")
                # Open the exported file
                Start-Process $result.output_path
            } else {
                [Logger]::Log("ProjectInfoModal: Export failed - $($result.error)")
            }
        } catch {
            [Logger]::Log("ProjectInfoModal: Export error - $($_.Exception.Message)")
        }
    }
    
    hidden [void] _BrowseFile([string]$fieldName, [bool]$directoriesOnly, [string]$title) {
        $startPath = $this._GetValue($fieldName)
        $this._filePicker.Open($startPath, $directoriesOnly, $title)
        $this._filePickerActive = $true
        $this._filePickerField = $fieldName
    }
    
    hidden [void] _OpenFile([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            [Logger]::Log("ProjectInfoModal: Cannot open - path is empty")
            return
        }
        
        if (-not (Test-Path $path)) {
            [Logger]::Log("ProjectInfoModal: Cannot open - file not found: $path")
            return
        }
        
        try {
            Start-Process $path
            [Logger]::Log("ProjectInfoModal: Opened file: $path")
        } catch {
            [Logger]::Log("ProjectInfoModal: Error opening file: $($_.Exception.Message)")
        }
    }
    
    hidden [void] _OpenFolder([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            [Logger]::Log("ProjectInfoModal: Cannot open folder - path is empty")
            return
        }
        
        if (-not (Test-Path $path)) {
            [Logger]::Log("ProjectInfoModal: Cannot open folder - not found: $path")
            return
        }
        
        try {
            $isWin = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
            if ($isWin) {
                Start-Process explorer.exe -ArgumentList $path
            } else {
                Start-Process xdg-open -ArgumentList $path
            }
            [Logger]::Log("ProjectInfoModal: Opened folder: $path")
        } catch {
            [Logger]::Log("ProjectInfoModal: Error opening folder: $($_.Exception.Message)")
        }
    }
}
