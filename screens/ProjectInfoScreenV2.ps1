using namespace System.Collections.Generic
using namespace System.Text

# ProjectInfoScreenV2 - Rewrite using StandardListScreen architecture
# EXACTLY matches ProjectInfoScreen appearance but uses UniversalList + InlineEditor

Set-StrictMode -Version Latest

# Load StandardListScreen if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'StandardListScreen').Type) {
    . "$PSScriptRoot/../base/StandardListScreen.ps1"
}

<#
.SYNOPSIS
Project information screen (V2 - StandardListScreen-based)

.DESCRIPTION
Reimplementation of ProjectInfoScreen using StandardListScreen architecture:
- Inherits from StandardListScreen (gets UniversalList, InlineEditor, FilterPanel)
- Displays project fields in custom 3-column grid format (SAME as original)
- Uses InlineEditor for field editing (TaskListScreen pattern)
- Proper cursor positioning handled by StandardListScreen + UniversalList

This replaces the manual rendering + manual editing approach with the proven
StandardListScreen pattern.
#>
class ProjectInfoScreenV2 : StandardListScreen {
    # Data
    [string]$ProjectName = ""
    [object]$ProjectData = $null
    [array]$ProjectTasks = @()
    [hashtable]$ProjectStats = @{}

    # Grid layout for 3-column field display
    [bool]$EditMode = $false
    [array]$AllFields = @()  # All 57 fields for editing

    # Constructor
    ProjectInfoScreenV2() : base("ProjectInfoV2", "Project Information") {
        $this._InitializeScreen()
    }

    # Constructor with container
    ProjectInfoScreenV2([object]$container) : base("ProjectInfoV2", "Project Information", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** ProjectInfoScreenV2._InitializeScreen CALLED - CLASS LOADED ***"

        # CRITICAL FIX: Hide the UniversalList widget since we use custom 3-column grid rendering
        # The List widget from StandardListScreen overlaps our custom grid
        if ($this.List) {
            $this.List.Visible = $false
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   List.Visible set to FALSE to prevent overlap with custom grid"
        }

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Projects", "Info"))

        # Configure footer with shortcuts
        $this._UpdateFooterShortcuts()

        # Initialize project stats
        $this.ProjectStats = @{
            TotalTasks = 0
            ActiveTasks = 0
            CompletedTasks = 0
            OverdueTasks = 0
            CompletionPercent = 0
        }

        # Enable editing - Enter key will work via OnItemActivated
        $this.AllowEdit = $true
    }

    hidden [void] _UpdateFooterShortcuts() {
        $this.Footer.ClearShortcuts()
        if ($this.EditMode) {
            $this.Footer.AddShortcut("Enter", "Edit Field")
            $this.Footer.AddShortcut("E", "Save & Exit")
            $this.Footer.AddShortcut("Esc", "Cancel")
        } else {
            $this.Footer.AddShortcut("E", "Edit")
            $this.Footer.AddShortcut("T", "Tasks")
            $this.Footer.AddShortcut("D", "Delete")
            $this.Footer.AddShortcut("Esc", "Back")
        }
    }

    # REQUIRED BY StandardListScreen - Return dummy column (we override rendering anyway)
    [array] GetColumns() {
        return @(
            @{ Name = 'Label'; Label = 'Field'; Width = 0.3; Property = 'Label' }
            @{ Name = 'Value'; Label = 'Value'; Width = 0.7; Property = 'Value' }
        )
    }

    # REQUIRED BY StandardListScreen - Return fields for editing
    [array] GetEditFields($item) {
        if ($null -eq $item) { return @() }
        # Return single field definition for the item being edited
        return @(
            @{
                Name = $item.Name
                Label = $item.Label
                Type = $item.Type
                Value = $item.Value
                Required = $false
                Width = 20
            }
        )
    }

    [void] SetProject([string]$projectName) {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** SetProject CALLED with projectName='$projectName' ***"
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.SetProject: projectName='$projectName'"
        }
        $this.ProjectName = $projectName
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** SetProject END ***"
    }

    # Override OnEnter to load data
    [void] OnEnter() {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** OnEnter START - ProjectName='$($this.ProjectName)' ***"
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.OnEnter: ProjectName='$($this.ProjectName)'"
        }

        $this.IsActive = $true
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   IsActive set to true"

        # CRITICAL: Ensure InlineEditor is hidden on entry
        $this.ShowInlineEditor = $false
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   ShowInlineEditor=$($this.ShowInlineEditor)"

        # Set columns
        $columns = $this.GetColumns()
        $this.List.SetColumns($columns)
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   Columns set: $($columns.Count) columns"

        # Load data (don't call parent's LoadData - it expects different data structure)
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   Calling LoadData..."
        $this.LoadData()
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   LoadData complete - AllFields.Count=$($this.AllFields.Count)"

        # Update header breadcrumb
        if ($this.Header) {
            $this.Header.SetBreadcrumb(@("Home", "Projects", "Info"))
        }

        # Update status bar
        if ($this.StatusBar) {
            $itemCount = $(if ($this.AllFields) { $this.AllFields.Count } else { 0 })
            $this.StatusBar.SetLeftText("$itemCount fields")
        }
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** OnEnter END ***"
    }

    [void] LoadData() {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** LoadData START - ProjectName='$($this.ProjectName)' ***"
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.LoadData: ProjectName='$($this.ProjectName)' IsNullOrWhiteSpace=$([string]::IsNullOrWhiteSpace($this.ProjectName))"
        }
        if ([string]::IsNullOrWhiteSpace($this.ProjectName)) {
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   ABORT - ProjectName is empty"
            $this.ShowError("No project selected")
            return
        }

        $this.ShowStatus("Loading project information...")

        try {
            # Get all projects from TaskStore
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   Getting all projects from Store..."
            $allProjects = $this.Store.GetAllProjects()
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   Got $($allProjects.Count) projects"
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.LoadData: Got $($allProjects.Count) projects from Store"
            }

            # Find project
            $this.ProjectData = $allProjects | Where-Object {
                ($_ -is [string] -and $_ -eq $this.ProjectName) -or
                ((Get-SafeProperty $_ 'name') -eq $this.ProjectName)
            } | Select-Object -First 1

            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.LoadData: ProjectData found=$($null -ne $this.ProjectData) type=$($this.ProjectData.GetType().FullName)"
            }

            if (-not $this.ProjectData) {
                $this.ShowError("Project '$($this.ProjectName)' not found")
                return
            }

            # Get project tasks
            $allTasks = $this.Store.GetAllTasks()
            $this.ProjectTasks = @($allTasks | Where-Object { (Get-SafeProperty $_ 'project') -eq $this.ProjectName })

            # Calculate statistics
            $this.ProjectStats = @{
                TotalTasks = $this.ProjectTasks.Count
                ActiveTasks = @($this.ProjectTasks | Where-Object { (Get-SafeProperty $_ 'status') -ne 'completed' }).Count
                CompletedTasks = @($this.ProjectTasks | Where-Object { (Get-SafeProperty $_ 'status') -eq 'completed' }).Count
                OverdueTasks = 0
            }

            # Count overdue tasks
            $today = (Get-Date).Date
            foreach ($task in $this.ProjectTasks) {
                $taskStatus = Get-SafeProperty $task 'status'
                $taskDue = Get-SafeProperty $task 'due'
                if ($taskStatus -ne 'completed' -and $taskDue) {
                    try {
                        $dueDate = [DateTime]::Parse($taskDue)
                        if ($dueDate.Date -lt $today) {
                            $this.ProjectStats.OverdueTasks++
                        }
                    } catch { }
                }
            }

            # Calculate completion percentage
            if ($this.ProjectStats.TotalTasks -gt 0) {
                $this.ProjectStats.CompletionPercent = [Math]::Round(
                    ($this.ProjectStats.CompletedTasks / $this.ProjectStats.TotalTasks) * 100, 1
                )
            } else {
                $this.ProjectStats.CompletionPercent = 0
            }

            $this.ShowSuccess("Loaded project: $($this.ProjectName)")

            # Build field list for display
            try {
                $this._BuildFieldList()
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.LoadData: _BuildFieldList completed, AllFields.Count=$($this.AllFields.Count)"
                }
            } catch {
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.LoadData: ERROR in _BuildFieldList: $_"
                }
                throw
            }

            # Populate UniversalList with fields so navigation works
            try {
                $this.List.SetData($this.AllFields)
                # FIX: Select first item by default so cursor is visible
                if ($this.AllFields.Count -gt 0) {
                    $this.List.SelectIndex(0)
                }
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.LoadData: List.SetData completed"
                }
            } catch {
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.LoadData: ERROR in List.SetData: $_"
                }
                throw
            }

            # Enable edit mode so fields are displayed immediately
            $this.EditMode = $true

            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.LoadData: END - ProjectData=$($null -ne $this.ProjectData) AllFields.Count=$($this.AllFields.Count)"
            }

        } catch {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.LoadData: EXCEPTION CAUGHT - clearing ProjectData: $_"
            }
            $this.ShowError("Failed to load project: $_")
            $this.ProjectData = $null
            $this.ProjectTasks = @()
        }
    }

    hidden [void] _BuildFieldList() {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** _BuildFieldList START - ProjectData=$($null -ne $this.ProjectData) ***"
        # EXACT COPY of ProjectInfoScreen.ps1 lines 1060-1118
        # NOTE: Added 'id' property for UniversalList compatibility
        $this.AllFields = @(
            @{id='ID1'; Name='ID1'; Label='ID1'; Value=(Get-SafeProperty $this.ProjectData 'ID1')}
            @{id='ID2'; Name='ID2'; Label='ID2'; Value=(Get-SafeProperty $this.ProjectData 'ID2')}
            @{id='ProjFolder'; Name='ProjFolder'; Label='Project Folder'; Value=(Get-SafeProperty $this.ProjectData 'ProjFolder')}
            @{id='CAAName'; Name='CAAName'; Label='CAA Name'; Value=(Get-SafeProperty $this.ProjectData 'CAAName')}
            @{id='RequestName'; Name='RequestName'; Label='Request Name'; Value=(Get-SafeProperty $this.ProjectData 'RequestName')}
            @{id='T2020'; Name='T2020'; Label='T2020'; Value=(Get-SafeProperty $this.ProjectData 'T2020')}
            @{id='AssignedDate'; Name='AssignedDate'; Label='Assigned Date'; Value=(Get-SafeProperty $this.ProjectData 'AssignedDate')}
            @{id='DueDate'; Name='DueDate'; Label='Due Date'; Value=(Get-SafeProperty $this.ProjectData 'DueDate')}
            @{id='BFDate'; Name='BFDate'; Label='BF Date'; Value=(Get-SafeProperty $this.ProjectData 'BFDate')}
            @{id='RequestDate'; Name='RequestDate'; Label='Request Date'; Value=(Get-SafeProperty $this.ProjectData 'RequestDate')}
            @{id='AuditType'; Name='AuditType'; Label='Audit Type'; Value=(Get-SafeProperty $this.ProjectData 'AuditType')}
            @{id='AuditorName'; Name='AuditorName'; Label='Auditor Name'; Value=(Get-SafeProperty $this.ProjectData 'AuditorName')}
            @{id='AuditorPhone'; Name='AuditorPhone'; Label='Auditor Phone'; Value=(Get-SafeProperty $this.ProjectData 'AuditorPhone')}
            @{id='AuditorTL'; Name='AuditorTL'; Label='Auditor TL'; Value=(Get-SafeProperty $this.ProjectData 'AuditorTL')}
            @{id='AuditorTLPhone'; Name='AuditorTLPhone'; Label='Auditor TL Phone'; Value=(Get-SafeProperty $this.ProjectData 'AuditorTLPhone')}
            @{id='AuditCase'; Name='AuditCase'; Label='Audit Case'; Value=(Get-SafeProperty $this.ProjectData 'AuditCase')}
            @{id='CASCase'; Name='CASCase'; Label='CAS Case'; Value=(Get-SafeProperty $this.ProjectData 'CASCase')}
            @{id='AuditStartDate'; Name='AuditStartDate'; Label='Audit Start Date'; Value=(Get-SafeProperty $this.ProjectData 'AuditStartDate')}
            @{id='TPName'; Name='TPName'; Label='TP Name'; Value=(Get-SafeProperty $this.ProjectData 'TPName')}
            @{id='TPNum'; Name='TPNum'; Label='TP Number'; Value=(Get-SafeProperty $this.ProjectData 'TPNum')}
            @{id='Address'; Name='Address'; Label='Address'; Value=(Get-SafeProperty $this.ProjectData 'Address')}
            @{id='City'; Name='City'; Label='City'; Value=(Get-SafeProperty $this.ProjectData 'City')}
            @{id='Province'; Name='Province'; Label='Province'; Value=(Get-SafeProperty $this.ProjectData 'Province')}
            @{id='PostalCode'; Name='PostalCode'; Label='Postal Code'; Value=(Get-SafeProperty $this.ProjectData 'PostalCode')}
            @{id='Country'; Name='Country'; Label='Country'; Value=(Get-SafeProperty $this.ProjectData 'Country')}
            @{id='AuditPeriodFrom'; Name='AuditPeriodFrom'; Label='Audit Period From'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriodFrom')}
            @{id='AuditPeriodTo'; Name='AuditPeriodTo'; Label='Audit Period To'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriodTo')}
            @{id='AuditPeriod1Start'; Name='AuditPeriod1Start'; Label='Audit Period 1 Start'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod1Start')}
            @{id='AuditPeriod1End'; Name='AuditPeriod1End'; Label='Audit Period 1 End'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod1End')}
            @{id='AuditPeriod2Start'; Name='AuditPeriod2Start'; Label='Audit Period 2 Start'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod2Start')}
            @{id='AuditPeriod2End'; Name='AuditPeriod2End'; Label='Audit Period 2 End'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod2End')}
            @{id='AuditPeriod3Start'; Name='AuditPeriod3Start'; Label='Audit Period 3 Start'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod3Start')}
            @{id='AuditPeriod3End'; Name='AuditPeriod3End'; Label='Audit Period 3 End'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod3End')}
            @{id='AuditPeriod4Start'; Name='AuditPeriod4Start'; Label='Audit Period 4 Start'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod4Start')}
            @{id='AuditPeriod4End'; Name='AuditPeriod4End'; Label='Audit Period 4 End'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod4End')}
            @{id='AuditPeriod5Start'; Name='AuditPeriod5Start'; Label='Audit Period 5 Start'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod5Start')}
            @{id='AuditPeriod5End'; Name='AuditPeriod5End'; Label='Audit Period 5 End'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod5End')}
            @{id='Contact1Name'; Name='Contact1Name'; Label='Contact 1 Name'; Value=(Get-SafeProperty $this.ProjectData 'Contact1Name')}
            @{id='Contact1Phone'; Name='Contact1Phone'; Label='Contact 1 Phone'; Value=(Get-SafeProperty $this.ProjectData 'Contact1Phone')}
            @{id='Contact1Ext'; Name='Contact1Ext'; Label='Contact 1 Ext'; Value=(Get-SafeProperty $this.ProjectData 'Contact1Ext')}
            @{id='Contact1Address'; Name='Contact1Address'; Label='Contact 1 Address'; Value=(Get-SafeProperty $this.ProjectData 'Contact1Address')}
            @{id='Contact1Title'; Name='Contact1Title'; Label='Contact 1 Title'; Value=(Get-SafeProperty $this.ProjectData 'Contact1Title')}
            @{id='Contact2Name'; Name='Contact2Name'; Label='Contact 2 Name'; Value=(Get-SafeProperty $this.ProjectData 'Contact2Name')}
            @{id='Contact2Phone'; Name='Contact2Phone'; Label='Contact 2 Phone'; Value=(Get-SafeProperty $this.ProjectData 'Contact2Phone')}
            @{id='Contact2Ext'; Name='Contact2Ext'; Label='Contact 2 Ext'; Value=(Get-SafeProperty $this.ProjectData 'Contact2Ext')}
            @{id='Contact2Address'; Name='Contact2Address'; Label='Contact 2 Address'; Value=(Get-SafeProperty $this.ProjectData 'Contact2Address')}
            @{id='Contact2Title'; Name='Contact2Title'; Label='Contact 2 Title'; Value=(Get-SafeProperty $this.ProjectData 'Contact2Title')}
            @{id='AuditProgram'; Name='AuditProgram'; Label='Audit Program'; Value=(Get-SafeProperty $this.ProjectData 'AuditProgram')}
            @{id='AccountingSoftware1'; Name='AccountingSoftware1'; Label='Accounting Software 1'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware1')}
            @{id='AccountingSoftware1Other'; Name='AccountingSoftware1Other'; Label='Accounting Software 1 Other'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware1Other')}
            @{id='AccountingSoftware1Type'; Name='AccountingSoftware1Type'; Label='Accounting Software 1 Type'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware1Type')}
            @{id='AccountingSoftware2'; Name='AccountingSoftware2'; Label='Accounting Software 2'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware2')}
            @{id='AccountingSoftware2Other'; Name='AccountingSoftware2Other'; Label='Accounting Software 2 Other'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware2Other')}
            @{id='AccountingSoftware2Type'; Name='AccountingSoftware2Type'; Label='Accounting Software 2 Type'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware2Type')}
            @{id='Comments'; Name='Comments'; Label='Comments'; Value=(Get-SafeProperty $this.ProjectData 'Comments')}
            @{id='FXInfo'; Name='FXInfo'; Label='FX Info'; Value=(Get-SafeProperty $this.ProjectData 'FXInfo')}
            @{id='ShipToAddress'; Name='ShipToAddress'; Label='Ship To Address'; Value=(Get-SafeProperty $this.ProjectData 'ShipToAddress')}
        )
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** _BuildFieldList END - Built $($this.AllFields.Count) fields ***"
        if ($this.AllFields.Count -gt 0) {
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   First 3 fields: $($this.AllFields[0].Label)='$($this.AllFields[0].Value)' | $($this.AllFields[1].Label)='$($this.AllFields[1].Value)' | $($this.AllFields[2].Label)='$($this.AllFields[2].Value)'"
        }
    }

    # Override RenderContent to render 3-column grid (EXACTLY matching original)
    [string] RenderContent() {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') ========================================="
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** ProjectInfoScreenV2.RenderContent START ***"
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   AllFields.Count=$($this.AllFields.Count)"
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   ProjectData=$($null -ne $this.ProjectData)"
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   ProjectName='$($this.ProjectName)'"
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   EditMode=$($this.EditMode)"
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   ShowInlineEditor=$($this.ShowInlineEditor)"
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   List=$($null -ne $this.List)"
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   LayoutManager=$($null -ne $this.LayoutManager)"

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.RenderContent: ProjectData=$($null -ne $this.ProjectData) ProjectName='$($this.ProjectName)'"
        }

        $sb = [System.Text.StringBuilder]::new(4096)

        if (-not $this.LayoutManager) {
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** ABORT - NO LAYOUT MANAGER! ***"
            return $sb.ToString()
        }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   contentRect.X=$($contentRect.X) Y=$($contentRect.Y) W=$($contentRect.Width) H=$($contentRect.Height)"
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   TermWidth=$($this.TermWidth) TermHeight=$($this.TermHeight)"

        # Colors
        $textColor = $this.Header.GetThemedFg('Foreground.Field')
        $highlightColor = $this.Header.GetThemedFg('Foreground.FieldFocused')
        $mutedColor = $this.Header.GetThemedFg('Foreground.Muted')
        $selectColor = "`e[30;47m"  # Black on white for selection
        $reset = "`e[0m"

        $y = $contentRect.Y + 1

        if (-not $this.ProjectData) {
            # Auto-recovery: If we have a name but no data, try loading
            if (-not [string]::IsNullOrWhiteSpace($this.ProjectName)) {
                $this.LoadData()
            }
            
            # Check again
            if (-not $this.ProjectData) {
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.RenderContent: NO PROJECT DATA! Name='$($this.ProjectName)'"
                }
                $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y))
                $sb.Append($mutedColor)
                $sb.Append("No project loaded: '$($this.ProjectName)'")
                $sb.Append($reset)
                return $sb.ToString()
            }
        }

        # Compact header: Name, Status, Created on one line
        $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $y++))
        $sb.Append($highlightColor)
        $name = $(if ($this.ProjectData -is [string]) { $this.ProjectData } else { Get-SafeProperty $this.ProjectData 'name' })
        $sb.Append([string]$name)
        $sb.Append($reset)
        $sb.Append($mutedColor)
        $projectStatus = Get-SafeProperty $this.ProjectData 'status'
        if ($projectStatus) {
            $sb.Append(" | Status: ")
            $sb.Append($reset)
            $sb.Append($textColor)
            $sb.Append([string]$projectStatus)
            $sb.Append($reset)
            $sb.Append($mutedColor)
        }
        $projectCreated = Get-SafeProperty $this.ProjectData 'created'
        if ($projectCreated) {
            $sb.Append(" | Created: ")
            $sb.Append($reset)
            $sb.Append($textColor)
            $sb.Append([string]$projectCreated)
            $sb.Append($reset)
        }

        # Render 3-column grid (EXACTLY matching original layout)
        # NOTE: Grid always renders; InlineEditor overlays on top when active
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   Checking AllFields.Count > 0: $($this.AllFields.Count -gt 0)"
        if ($this.AllFields.Count -gt 0) {
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   RENDERING 3-COLUMN GRID with $($this.AllFields.Count) fields"
            $y++

            # Column positions (matching original)
            $col1X = $contentRect.X + 5
            $col2X = $col1X + 42
            $col3X = $col2X + 42
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   Column positions: col1X=$col1X col2X=$col2X col3X=$col3X"

            # Render fields in rows of 3
            $fieldIndex = 0
            $rowY = $y + 1
            $rowsRendered = 0
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   Starting grid render loop, initial rowY=$rowY"

            while ($fieldIndex -lt $this.AllFields.Count) {
                # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') === ROW $rowsRendered START: fieldIndex=$fieldIndex rowY=$rowY ==="

                # Get 3 fields for this row
                $field1 = $(if ($fieldIndex -lt $this.AllFields.Count) { $this.AllFields[$fieldIndex] } else { $null })
                $field2 = $(if ($fieldIndex + 1 -lt $this.AllFields.Count) { $this.AllFields[$fieldIndex + 1] } else { $null })
                $field3 = $(if ($fieldIndex + 2 -lt $this.AllFields.Count) { $this.AllFields[$fieldIndex + 2] } else { $null })

                $ts = Get-Date -Format 'HH:mm:ss.fff'
                # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$ts   ROW $rowsRendered - field1=$(if($field1){$field1.Label}else{'null'}) field2=$(if($field2){$field2.Label}else{'null'}) field3=$(if($field3){$field3.Label}else{'null'})"
                # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$ts   ROW $rowsRendered - values='$(if($field1){$field1.Value}else{'N/A'})' '$(if($field2){$field2.Value}else{'N/A'})' '$(if($field3){$field3.Value}else{'N/A'})'"
                # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$ts   ROW $rowsRendered - CurrentSelectedIndex=$($this.List.GetSelectedIndex())"

                # Render COL1
                if ($field1) {
                    $isSelected1 = ($fieldIndex -eq $this.List.GetSelectedIndex())
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 render start: row=$rowsRendered fieldIdx=$fieldIndex label=$($field1.Label) isSelected=$isSelected1 ShowInlineEditor=$($this.ShowInlineEditor)"

                    $moveToCode = $this.Header.BuildMoveTo($col1X, $rowY)
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 MoveTo: col1X=$col1X rowY=$rowY code='$($moveToCode.Replace("`e", '<ESC>'))'"
                    # CRITICAL: Reset ALL formatting BEFORE writing row content (clears any blinking cursor/inverse video from InlineEditor)
                    $sb.Append($reset)
                    $sb.Append($moveToCode)

                    $label1 = $field1.Label
                    if ($label1.Length -gt 20) { $label1 = $label1.Substring(0, 17) + "..." }
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 label truncated: '$label1' (original='$($field1.Label)')"

                    # Render label with selection highlight when selected (but not editing)
                    if ($isSelected1 -and -not $this.ShowInlineEditor) {
                        # Show selection highlight
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 BRANCH: SELECTED + NOT EDITING - applying highlight"
                        $beforeLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending selectColor='$($selectColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($selectColor)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending label='$label1'"
                        $sb.Append($label1)
                        $spaces = ' ' * (22 - $label1.Length)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending $($spaces.Length) spaces"
                        $sb.Append($spaces)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending reset='$($reset.Replace("`e", '<ESC>'))'"
                        $sb.Append($reset)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending highlightColor='$($highlightColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($highlightColor)
                        $afterLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 highlight complete: added=$($afterLen - $beforeLen) chars, sb.Length now=$afterLen"
                    } else {
                        # Normal rendering
                        if ($isSelected1) {
                            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 BRANCH: SELECTED + EDITING - NO highlight"
                        } else {
                            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 BRANCH: NOT SELECTED - normal render"
                        }
                        $beforeLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending mutedColor='$($mutedColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($mutedColor)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending label='$label1'"
                        $sb.Append($label1)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending reset='$($reset.Replace("`e", '<ESC>'))'"
                        $sb.Append($reset)
                        $spaces = ' ' * (22 - $label1.Length)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending $($spaces.Length) spaces"
                        $sb.Append($spaces)
                        $afterLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 normal render complete: added=$($afterLen - $beforeLen) chars"
                    }

                    # Only render value if NOT in edit mode for this field
                    if (-not ($isSelected1 -and $this.ShowInlineEditor)) {
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 rendering value (not editing this field)"
                        $beforeLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending textColor='$($textColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($textColor)
                        $val1 = $(if ($field1.Value) { [string]$field1.Value } else { $mutedColor + "(empty)" + $reset })
                        if ($val1.Length -gt 18) { $val1 = $val1.Substring(0, 15) + "..." }
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending value='$val1'"
                        $sb.Append($val1)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 appending reset"
                        $sb.Append($reset)
                        $afterLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 value render complete: added=$($afterLen - $beforeLen) chars"
                    } else {
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 SKIPPING value render (editing this field, InlineEditor will render)"
                    }
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL1 render complete for fieldIdx=$fieldIndex"
                }

                # Check if editor is active on this row (affects col2 and col3 rendering)
                $editorActiveOnThisRow = $this.ShowInlineEditor -and ($fieldIndex -eq $this.List.GetSelectedIndex() -or ($fieldIndex + 1) -eq $this.List.GetSelectedIndex() -or ($fieldIndex + 2) -eq $this.List.GetSelectedIndex())
                $ts = Get-Date -Format 'HH:mm:ss.fff'
                # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$ts   ROW $rowsRendered - editorActiveOnThisRow=$editorActiveOnThisRow (ShowInlineEditor=$($this.ShowInlineEditor) SelectedIndex=$($this.List.GetSelectedIndex()))"

                # Render COL2
                if ($field2) {
                    $isSelected2 = ($fieldIndex + 1 -eq $this.List.GetSelectedIndex())
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 render start: row=$rowsRendered fieldIdx=$($fieldIndex + 1) label=$($field2.Label) isSelected=$isSelected2 ShowInlineEditor=$($this.ShowInlineEditor)"

                    $moveToCode = $this.Header.BuildMoveTo($col2X, $rowY)
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 MoveTo: col2X=$col2X rowY=$rowY code='$($moveToCode.Replace("`e", '<ESC>'))'"
                    $sb.Append($reset)
                    $sb.Append($moveToCode)

                    $label2 = $field2.Label
                    if ($label2.Length -gt 20) { $label2 = $label2.Substring(0, 17) + "..." }
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 label truncated: '$label2' (original='$($field2.Label)')"

                    # Render label with selection highlight when selected (but not editing)
                    if ($isSelected2 -and -not $this.ShowInlineEditor) {
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 BRANCH: SELECTED + NOT EDITING - applying highlight"
                        $beforeLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending selectColor='$($selectColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($selectColor)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending label='$label2'"
                        $sb.Append($label2)
                        $spaces = ' ' * (22 - $label2.Length)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending $($spaces.Length) spaces"
                        $sb.Append($spaces)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending reset='$($reset.Replace("`e", '<ESC>'))'"
                        $sb.Append($reset)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending highlightColor='$($highlightColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($highlightColor)
                        $afterLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 highlight complete: added=$($afterLen - $beforeLen) chars"
                    } else {
                        if ($isSelected2) {
                            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 BRANCH: SELECTED + EDITING - NO highlight"
                        } else {
                            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 BRANCH: NOT SELECTED - normal render"
                        }
                        $beforeLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending mutedColor='$($mutedColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($mutedColor)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending label='$label2'"
                        $sb.Append($label2)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending reset='$($reset.Replace("`e", '<ESC>'))'"
                        $sb.Append($reset)
                        $spaces = ' ' * (22 - $label2.Length)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending $($spaces.Length) spaces"
                        $sb.Append($spaces)
                        $afterLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 normal render complete: added=$($afterLen - $beforeLen) chars"
                    }

                    # Only render value if NOT in edit mode for this field
                    if (-not ($isSelected2 -and $this.ShowInlineEditor)) {
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 rendering value (not editing this field)"
                        $beforeLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending textColor='$($textColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($textColor)
                        $val2 = $(if ($field2.Value) { [string]$field2.Value } else { $mutedColor + "(empty)" + $reset })
                        if ($val2.Length -gt 18) { $val2 = $val2.Substring(0, 15) + "..." }
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending value='$val2'"
                        $sb.Append($val2)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 appending reset"
                        $sb.Append($reset)
                        $afterLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 value render complete: added=$($afterLen - $beforeLen) chars"
                    } else {
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 SKIPPING value render (editing this field)"
                    }
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL2 render complete for fieldIdx=$($fieldIndex + 1)"
                }

                # Render COL3
                if ($field3) {
                    $isSelected3 = ($fieldIndex + 2 -eq $this.List.GetSelectedIndex())
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 render start: row=$rowsRendered fieldIdx=$($fieldIndex + 2) label=$($field3.Label) isSelected=$isSelected3 ShowInlineEditor=$($this.ShowInlineEditor)"

                    $moveToCode = $this.Header.BuildMoveTo($col3X, $rowY)
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 MoveTo: col3X=$col3X rowY=$rowY code='$($moveToCode.Replace("`e", '<ESC>'))'"
                    $sb.Append($reset)
                    $sb.Append($moveToCode)

                    $label3 = $field3.Label
                    if ($label3.Length -gt 20) { $label3 = $label3.Substring(0, 17) + "..." }
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 label truncated: '$label3' (original='$($field3.Label)')"

                    # Render label with selection highlight when selected (but not editing)
                    if ($isSelected3 -and -not $this.ShowInlineEditor) {
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 BRANCH: SELECTED + NOT EDITING - applying highlight"
                        $beforeLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending selectColor='$($selectColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($selectColor)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending label='$label3'"
                        $sb.Append($label3)
                        $spaces = ' ' * (22 - $label3.Length)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending $($spaces.Length) spaces"
                        $sb.Append($spaces)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending reset='$($reset.Replace("`e", '<ESC>'))'"
                        $sb.Append($reset)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending highlightColor='$($highlightColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($highlightColor)
                        $afterLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 highlight complete: added=$($afterLen - $beforeLen) chars"
                    } else {
                        if ($isSelected3) {
                            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 BRANCH: SELECTED + EDITING - NO highlight"
                        } else {
                            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 BRANCH: NOT SELECTED - normal render"
                        }
                        $beforeLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending mutedColor='$($mutedColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($mutedColor)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending label='$label3'"
                        $sb.Append($label3)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending reset='$($reset.Replace("`e", '<ESC>'))'"
                        $sb.Append($reset)
                        $spaces = ' ' * (22 - $label3.Length)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending $($spaces.Length) spaces"
                        $sb.Append($spaces)
                        $afterLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 normal render complete: added=$($afterLen - $beforeLen) chars"
                    }

                    # Only render value if NOT in edit mode for this field
                    if (-not ($isSelected3 -and $this.ShowInlineEditor)) {
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 rendering value (not editing this field)"
                        $beforeLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending textColor='$($textColor.Replace("`e", '<ESC>'))'"
                        $sb.Append($textColor)
                        $val3 = $(if ($field3.Value) { [string]$field3.Value } else { $mutedColor + "(empty)" + $reset })
                        if ($val3.Length -gt 18) { $val3 = $val3.Substring(0, 15) + "..." }
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending value='$val3'"
                        $sb.Append($val3)
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 appending reset"
                        $sb.Append($reset)
                        $afterLen = $sb.Length
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 value render complete: added=$($afterLen - $beforeLen) chars"
                    } else {
                        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 SKIPPING value render (editing this field)"
                    }
                    # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   COL3 render complete for fieldIdx=$($fieldIndex + 2)"
                }

                $fieldIndex += 3
                $rowY++
                $rowsRendered++
                # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') === ROW $($rowsRendered - 1) END: fieldIndex now=$fieldIndex rowY now=$rowY ==="
            }

            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   Grid render complete: $rowsRendered rows rendered"

            # Render stats section at bottom
            $rowY += 2
            $sb.Append($this.Header.BuildMoveTo($contentRect.X + 4, $rowY++))
            $sb.Append($mutedColor)
            $sb.Append("Tasks: ")
            $sb.Append($reset)
            $sb.Append($textColor)
            $sb.Append("Total: ")
            $sb.Append([string]$this.ProjectStats.TotalTasks)
            $sb.Append("  Active: ")
            $sb.Append([string]$this.ProjectStats.ActiveTasks)
            $sb.Append("  Completed: ")
            $sb.Append([string]$this.ProjectStats.CompletedTasks)
            $sb.Append("  Overdue: ")
            $sb.Append([string]$this.ProjectStats.OverdueTasks)
            $sb.Append($reset)
        } else {
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   SKIPPING grid render - AllFields.Count is 0"
        }

        # Append InlineEditor rendering if active
        # NOTE: InlineEditor renders as overlay, positioned at specific coordinates
        if ($this.ShowInlineEditor -and $null -ne $this.InlineEditor) {
            $editorOutput = $this.InlineEditor.Render()
            if ($editorOutput) {
                $sb.Append($editorOutput)
            }
        }

        $result = $sb.ToString()
        $ts = Get-Date -Format 'HH:mm:ss.fff'
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$ts *** ProjectInfoScreenV2.RenderContent END ***"
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$ts   Output length=$($result.Length) characters"
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$ts   First 200 chars - $($result.Substring(0, [Math]::Min(200, $result.Length)).Replace("`e", '<ESC>').Replace("`n", '<LF>'))"

        # Dump the area around the selected field (CAA Name at position ~450-550)
        if ($result.Length -gt 600) {
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$ts   Chars 400-600 - $($result.Substring(400, [Math]::Min(200, $result.Length - 400)).Replace("`e", '<ESC>').Replace("`n", '<LF>'))"
        }
        if ($result.Length -gt 800) {
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$ts   Chars 600-800 - $($result.Substring(600, [Math]::Min(200, $result.Length - 600)).Replace("`e", '<ESC>').Replace("`n", '<LF>'))"
        }

        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$ts ========================================="
        return $result
    }

    # Override EditItem to edit a field using InlineEditor (TaskListScreen pattern)
    [void] EditItem($field) {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** ProjectInfoScreenV2.EditItem CALLED ***"
        if ($global:PmcTuiLogFile) {
            $fieldName = $(if ($field) { $field.Name } else { 'NULL' })
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.EditItem: CALLED with field=$fieldName"
        }
        if ($null -eq $field) {
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** ProjectInfoScreenV2.EditItem field is NULL, returning ***"
            return
        }

        # Get field index
        $fieldIndex = -1
        for ($i = 0; $i -lt $this.AllFields.Count; $i++) {
            if ($this.AllFields[$i].Name -eq $field.Name) {
                $fieldIndex = $i
                break
            }
        }
        if ($fieldIndex -lt 0) { return }

        # Calculate position in 3-column grid
        $colIndex = $fieldIndex % 3
        $rowIndex = [Math]::Floor($fieldIndex / 3)

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)
        $col1X = $contentRect.X + 5
        $col2X = $col1X + 42
        $col3X = $col2X + 42
        $rowY = $contentRect.Y + 4 + $rowIndex

        # Determine column X position
        $editorX = switch ($colIndex) {
            0 { $col1X }
            1 { $col2X }
            2 { $col3X }
        }

        # Build field definition for InlineEditor
        $fieldDef = @{
            Name = $field.Name
            Label = ""
            Type = 'text'  # All fields are text type
            Value = $field.Value
            Required = $false
            Width = 18  # Match value display width from grid
        }

        # Configure InlineEditor
        $this.InlineEditor.LayoutMode = 'horizontal'
        $this.InlineEditor.SetFields(@($fieldDef))
        $this.InlineEditor.SetPosition($editorX + 22, $rowY)  # Position after label (22 chars)
        $this.InlineEditor.SetSize(18, 1)  # Width=18 to avoid overlapping next column

        # Set up save callback
        $self = $this
        $fieldName = $field.Name
        $savedIndex = $fieldIndex  # Capture the field index to restore selection
        $this.InlineEditor.OnConfirmed = {
            param($values)
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** OnConfirmed CALLBACK - fieldName=$fieldName value='$($values[$fieldName])' ***"

            # Update ProjectData
            $self.ProjectData.$fieldName = $values[$fieldName]

            # Rebuild field list to reflect the change
            $self._BuildFieldList()

            # Update the List widget's data AND restore selection to edited field
            $self.List.SetData($self.AllFields)

            # Close editor FIRST
            $self.ShowInlineEditor = $false
            $self.EditorMode = ""
            $self.CurrentEditItem = $null
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   Editor closed, ShowInlineEditor=$($self.ShowInlineEditor)"

            # THEN update selection (after editor is closed so render shows clean grid)
            $self.List.SelectIndex($savedIndex)  # Keep focus on edited field
            # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff')   Selection restored to index $savedIndex"

            $self.ShowStatus("Field updated - Press E to save all changes")
        }.GetNewClosure()

        $this.InlineEditor.OnCancelled = {
            $self.ShowInlineEditor = $false
            $self.EditorMode = ""
            $self.CurrentEditItem = $null
            $self.ShowStatus("Edit cancelled")
        }.GetNewClosure()

        # Activate InlineEditor
        $this.EditorMode = 'edit'
        $this.CurrentEditItem = $field
        $this.ShowInlineEditor = $true
    }

    # Override OnItemActivated to handle Enter key press
    [void] OnItemActivated($item) {
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** ProjectInfoScreenV2.OnItemActivated CALLED ***"
        if ($global:PmcTuiLogFile) {
            $itemName = $(if ($item) { $item.Name } else { 'NULL' })
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV2.OnItemActivated: item=$itemName"
        }
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** ProjectInfoScreenV2.OnItemActivated about to call EditItem ***"
        # Edit the selected field
        $this.EditItem($item)
        # PERF: Disabled - Add-Content -Path "$($env:TEMP)/pmc-flow-debug.log" -Value "$(Get-Date -Format 'HH:mm:ss.fff') *** ProjectInfoScreenV2.OnItemActivated EditItem returned ***"
    }

    # Override HandleKeyPress for custom 3-column grid navigation
    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # If InlineEditor is active, let StandardListScreen handle it
        if ($this.ShowInlineEditor) {
            return ([StandardListScreen]$this).HandleKeyPress($keyInfo)
        }

        $key = $keyInfo.Key
        $currentIndex = $this.List.GetSelectedIndex()

        # Custom navigation for 3-column grid
        if ($key -eq [ConsoleKey]::UpArrow) {
            # Move up one row (3 fields)
            $newIndex = $currentIndex - 3
            if ($newIndex -ge 0) {
                $this.List.SelectIndex($newIndex)
            }
            return $true
        }
        elseif ($key -eq [ConsoleKey]::DownArrow) {
            # Move down one row (3 fields)
            $newIndex = $currentIndex + 3
            if ($newIndex -lt $this.AllFields.Count) {
                $this.List.SelectIndex($newIndex)
            }
            return $true
        }
        elseif ($key -eq [ConsoleKey]::LeftArrow) {
            # Move left one field
            if ($currentIndex -gt 0) {
                $this.List.SelectIndex($currentIndex - 1)
            }
            return $true
        }
        elseif ($key -eq [ConsoleKey]::RightArrow) {
            # Move right one field
            if ($currentIndex + 1 -lt $this.AllFields.Count) {
                $this.List.SelectIndex($currentIndex + 1)
            }
            return $true
        }
        elseif ($key -eq [ConsoleKey]::Escape) {
            $global:PmcApp.PopScreen()
            return $true
        }

        # Let parent handle other keys (including Enter which calls OnItemActivated)
        return ([StandardListScreen]$this).HandleKeyPress($keyInfo)
    }

    hidden [void] _SaveAllEdits() {
        try {
            # Build update object from AllFields
            $updates = @{}
            foreach ($field in $this.AllFields) {
                $updates[$field.Name] = $field.Value
            }

            # Update the project
            $this.Store.UpdateProject($this.ProjectName, $updates)
            $this.EditMode = $false
            $this._UpdateFooterShortcuts()
            $this.ShowSuccess("Project updated successfully")
            $this.LoadData()  # Reload to get fresh data
        } catch {
            $this.ShowError("Failed to save: $_")
        }
    }
}

# Export class
Export-ModuleMember -Variable @()