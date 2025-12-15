using namespace System.Collections.Generic
using namespace System.Text

# ProjectInfoScreenV3 - Rewrite using StandardListScreen architecture
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
class ProjectInfoScreenV3 : StandardListScreen {
    # Data
    [string]$ProjectName = ""
    [object]$ProjectData = $null
    [array]$ProjectTasks = @()
    [hashtable]$ProjectStats = @{}

    # Grid layout for 3-column field display
    [bool]$EditMode = $false
    [array]$AllFields = @()  # All 57 fields for editing

    # Constructor
    ProjectInfoScreenV3() : base("ProjectInfoV2", "Project Information") {
        $this._InitializeScreen()
    }

    # Constructor with container
    ProjectInfoScreenV3([object]$container) : base("ProjectInfoV2", "Project Information", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
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
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.SetProject: projectName='$projectName'"
        }
        $this.ProjectName = $projectName
    }

    # Override OnEnter to load data
    [void] OnEnter() {
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.OnEnter: ProjectName='$($this.ProjectName)'"
        }

        $this.IsActive = $true

        # CRITICAL: Ensure InlineEditor is hidden on entry
        $this.ShowInlineEditor = $false

        # Set columns
        $columns = $this.GetColumns()
        $this.List.SetColumns($columns)

        # Load data (don't call parent's LoadData - it expects different data structure)
        $this.LoadData()

        # Update header breadcrumb
        if ($this.Header) {
            $this.Header.SetBreadcrumb(@("Home", "Projects", "Info"))
        }

        # Update status bar
        if ($this.StatusBar) {
            $itemCount = $(if ($this.AllFields) { $this.AllFields.Count } else { 0 })
            $this.StatusBar.SetLeftText("$itemCount fields")
        }
    }

    [void] LoadData() {
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.LoadData: ProjectName='$($this.ProjectName)' IsNullOrWhiteSpace=$([string]::IsNullOrWhiteSpace($this.ProjectName))"
        }
        if ([string]::IsNullOrWhiteSpace($this.ProjectName)) {
            $this.ShowError("No project selected")
            return
        }

        $this.ShowStatus("Loading project information...")

        try {
            # Get all projects from TaskStore
            $allProjects = $this.Store.GetAllProjects()
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.LoadData: Got $($allProjects.Count) projects from Store"
            }

            # Find project
            $this.ProjectData = $allProjects | Where-Object {
                ($_ -is [string] -and $_ -eq $this.ProjectName) -or
                ((Get-SafeProperty $_ 'name') -eq $this.ProjectName)
            } | Select-Object -First 1

            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.LoadData: ProjectData found=$($null -ne $this.ProjectData) type=$($this.ProjectData.GetType().FullName)"
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
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.LoadData: _BuildFieldList completed, AllFields.Count=$($this.AllFields.Count)"
                }
            } catch {
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.LoadData: ERROR in _BuildFieldList: $_"
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
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.LoadData: List.SetData completed"
                }
            } catch {
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.LoadData: ERROR in List.SetData: $_"
                }
                throw
            }

            # Enable edit mode so fields are displayed immediately
            $this.EditMode = $true

            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.LoadData: END - ProjectData=$($null -ne $this.ProjectData) AllFields.Count=$($this.AllFields.Count)"
            }

        } catch {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.LoadData: EXCEPTION CAUGHT - clearing ProjectData: $_"
            }
            $this.ShowError("Failed to load project: $_")
            $this.ProjectData = $null
            $this.ProjectTasks = @()
        }
    }

    hidden [void] _BuildFieldList() {
        # EXACT COPY of ProjectInfoScreen.ps1 lines 1060-1118
        $this.AllFields = @(
            @{Name='ID1'; Label='ID1'; Value=(Get-SafeProperty $this.ProjectData 'ID1')}
            @{Name='ID2'; Label='ID2'; Value=(Get-SafeProperty $this.ProjectData 'ID2')}
            @{Name='ProjFolder'; Label='Project Folder'; Value=(Get-SafeProperty $this.ProjectData 'ProjFolder')}
            @{Name='CAAName'; Label='CAA Name'; Value=(Get-SafeProperty $this.ProjectData 'CAAName')}
            @{Name='RequestName'; Label='Request Name'; Value=(Get-SafeProperty $this.ProjectData 'RequestName')}
            @{Name='T2020'; Label='T2020'; Value=(Get-SafeProperty $this.ProjectData 'T2020')}
            @{Name='AssignedDate'; Label='Assigned Date'; Value=(Get-SafeProperty $this.ProjectData 'AssignedDate')}
            @{Name='DueDate'; Label='Due Date'; Value=(Get-SafeProperty $this.ProjectData 'DueDate')}
            @{Name='BFDate'; Label='BF Date'; Value=(Get-SafeProperty $this.ProjectData 'BFDate')}
            @{Name='RequestDate'; Label='Request Date'; Value=(Get-SafeProperty $this.ProjectData 'RequestDate')}
            @{Name='AuditType'; Label='Audit Type'; Value=(Get-SafeProperty $this.ProjectData 'AuditType')}
            @{Name='AuditorName'; Label='Auditor Name'; Value=(Get-SafeProperty $this.ProjectData 'AuditorName')}
            @{Name='AuditorPhone'; Label='Auditor Phone'; Value=(Get-SafeProperty $this.ProjectData 'AuditorPhone')}
            @{Name='AuditorTL'; Label='Auditor TL'; Value=(Get-SafeProperty $this.ProjectData 'AuditorTL')}
            @{Name='AuditorTLPhone'; Label='Auditor TL Phone'; Value=(Get-SafeProperty $this.ProjectData 'AuditorTLPhone')}
            @{Name='AuditCase'; Label='Audit Case'; Value=(Get-SafeProperty $this.ProjectData 'AuditCase')}
            @{Name='CASCase'; Label='CAS Case'; Value=(Get-SafeProperty $this.ProjectData 'CASCase')}
            @{Name='AuditStartDate'; Label='Audit Start Date'; Value=(Get-SafeProperty $this.ProjectData 'AuditStartDate')}
            @{Name='TPName'; Label='TP Name'; Value=(Get-SafeProperty $this.ProjectData 'TPName')}
            @{Name='TPNum'; Label='TP Number'; Value=(Get-SafeProperty $this.ProjectData 'TPNum')}
            @{Name='Address'; Label='Address'; Value=(Get-SafeProperty $this.ProjectData 'Address')}
            @{Name='City'; Label='City'; Value=(Get-SafeProperty $this.ProjectData 'City')}
            @{Name='Province'; Label='Province'; Value=(Get-SafeProperty $this.ProjectData 'Province')}
            @{Name='PostalCode'; Label='Postal Code'; Value=(Get-SafeProperty $this.ProjectData 'PostalCode')}
            @{Name='Country'; Label='Country'; Value=(Get-SafeProperty $this.ProjectData 'Country')}
            @{Name='AuditPeriodFrom'; Label='Audit Period From'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriodFrom')}
            @{Name='AuditPeriodTo'; Label='Audit Period To'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriodTo')}
            @{Name='AuditPeriod1Start'; Label='Audit Period 1 Start'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod1Start')}
            @{Name='AuditPeriod1End'; Label='Audit Period 1 End'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod1End')}
            @{Name='AuditPeriod2Start'; Label='Audit Period 2 Start'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod2Start')}
            @{Name='AuditPeriod2End'; Label='Audit Period 2 End'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod2End')}
            @{Name='AuditPeriod3Start'; Label='Audit Period 3 Start'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod3Start')}
            @{Name='AuditPeriod3End'; Label='Audit Period 3 End'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod3End')}
            @{Name='AuditPeriod4Start'; Label='Audit Period 4 Start'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod4Start')}
            @{Name='AuditPeriod4End'; Label='Audit Period 4 End'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod4End')}
            @{Name='AuditPeriod5Start'; Label='Audit Period 5 Start'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod5Start')}
            @{Name='AuditPeriod5End'; Label='Audit Period 5 End'; Value=(Get-SafeProperty $this.ProjectData 'AuditPeriod5End')}
            @{Name='Contact1Name'; Label='Contact 1 Name'; Value=(Get-SafeProperty $this.ProjectData 'Contact1Name')}
            @{Name='Contact1Phone'; Label='Contact 1 Phone'; Value=(Get-SafeProperty $this.ProjectData 'Contact1Phone')}
            @{Name='Contact1Ext'; Label='Contact 1 Ext'; Value=(Get-SafeProperty $this.ProjectData 'Contact1Ext')}
            @{Name='Contact1Address'; Label='Contact 1 Address'; Value=(Get-SafeProperty $this.ProjectData 'Contact1Address')}
            @{Name='Contact1Title'; Label='Contact 1 Title'; Value=(Get-SafeProperty $this.ProjectData 'Contact1Title')}
            @{Name='Contact2Name'; Label='Contact 2 Name'; Value=(Get-SafeProperty $this.ProjectData 'Contact2Name')}
            @{Name='Contact2Phone'; Label='Contact 2 Phone'; Value=(Get-SafeProperty $this.ProjectData 'Contact2Phone')}
            @{Name='Contact2Ext'; Label='Contact 2 Ext'; Value=(Get-SafeProperty $this.ProjectData 'Contact2Ext')}
            @{Name='Contact2Address'; Label='Contact 2 Address'; Value=(Get-SafeProperty $this.ProjectData 'Contact2Address')}
            @{Name='Contact2Title'; Label='Contact 2 Title'; Value=(Get-SafeProperty $this.ProjectData 'Contact2Title')}
            @{Name='AuditProgram'; Label='Audit Program'; Value=(Get-SafeProperty $this.ProjectData 'AuditProgram')}
            @{Name='AccountingSoftware1'; Label='Accounting Software 1'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware1')}
            @{Name='AccountingSoftware1Other'; Label='Accounting Software 1 Other'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware1Other')}
            @{Name='AccountingSoftware1Type'; Label='Accounting Software 1 Type'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware1Type')}
            @{Name='AccountingSoftware2'; Label='Accounting Software 2'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware2')}
            @{Name='AccountingSoftware2Other'; Label='Accounting Software 2 Other'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware2Other')}
            @{Name='AccountingSoftware2Type'; Label='Accounting Software 2 Type'; Value=(Get-SafeProperty $this.ProjectData 'AccountingSoftware2Type')}
            @{Name='Comments'; Label='Comments'; Value=(Get-SafeProperty $this.ProjectData 'Comments')}
            @{Name='FXInfo'; Label='FX Info'; Value=(Get-SafeProperty $this.ProjectData 'FXInfo')}
            @{Name='ShipToAddress'; Label='Ship To Address'; Value=(Get-SafeProperty $this.ProjectData 'ShipToAddress')}
        )
    }

    # Override RenderContent to render 3-column grid (EXACTLY matching original)
    [string] RenderContent() {
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.RenderContent: ProjectData=$($null -ne $this.ProjectData) ProjectName='$($this.ProjectName)'"
        }

        $sb = [System.Text.StringBuilder]::new(4096)

        if (-not $this.LayoutManager) {
            return $sb.ToString()
        }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

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
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.RenderContent: NO PROJECT DATA! Name='$($this.ProjectName)'"
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
        # FIX: Always render grid if we have fields, regardless of EditMode
        if ($this.AllFields.Count -gt 0) {
            $y++

            # Column positions (matching original)
            $col1X = $contentRect.X + 5
            $col2X = $col1X + 42
            $col3X = $col2X + 42

            # Render fields in rows of 3
            $fieldIndex = 0
            $rowY = $y + 1

            while ($fieldIndex -lt $this.AllFields.Count) {
                # Get 3 fields for this row
                $field1 = $(if ($fieldIndex -lt $this.AllFields.Count) { $this.AllFields[$fieldIndex] } else { $null })
                $field2 = $(if ($fieldIndex + 1 -lt $this.AllFields.Count) { $this.AllFields[$fieldIndex + 1] } else { $null })
                $field3 = $(if ($fieldIndex + 2 -lt $this.AllFields.Count) { $this.AllFields[$fieldIndex + 2] } else { $null })

                # Render COL1
                if ($field1) {
                    $isSelected1 = ($fieldIndex -eq $this.List.GetSelectedIndex())
                    $sb.Append($this.Header.BuildMoveTo($col1X, $rowY))

                    $label1 = $field1.Label
                    if ($label1.Length -gt 20) { $label1 = $label1.Substring(0, 17) + "..." }

                    if ($isSelected1) {
                        $sb.Append($selectColor)
                        $sb.Append($label1)
                        $sb.Append(' ' * (22 - $label1.Length))
                        $sb.Append($reset)
                        $sb.Append($highlightColor)
                    } else {
                        $sb.Append($mutedColor)
                        $sb.Append($label1)
                        $sb.Append($reset)
                        $sb.Append(' ' * (22 - $label1.Length))
                        $sb.Append($textColor)
                    }

                    $val1 = $(if ($field1.Value) { [string]$field1.Value } else { $mutedColor + "(empty)" + $reset })
                    if ($val1.Length -gt 18) { $val1 = $val1.Substring(0, 15) + "..." }
                    $sb.Append($val1)
                    $sb.Append($reset)
                }

                # Render COL2
                if ($field2) {
                    $isSelected2 = ($fieldIndex + 1 -eq $this.List.GetSelectedIndex())
                    $sb.Append($this.Header.BuildMoveTo($col2X, $rowY))

                    $label2 = $field2.Label
                    if ($label2.Length -gt 20) { $label2 = $label2.Substring(0, 17) + "..." }

                    if ($isSelected2) {
                        $sb.Append($selectColor)
                        $sb.Append($label2)
                        $sb.Append(' ' * (22 - $label2.Length))
                        $sb.Append($reset)
                        $sb.Append($highlightColor)
                    } else {
                        $sb.Append($mutedColor)
                        $sb.Append($label2)
                        $sb.Append($reset)
                        $sb.Append(' ' * (22 - $label2.Length))
                        $sb.Append($textColor)
                    }

                    $val2 = $(if ($field2.Value) { [string]$field2.Value } else { $mutedColor + "(empty)" + $reset })
                    if ($val2.Length -gt 18) { $val2 = $val2.Substring(0, 15) + "..." }
                    $sb.Append($val2)
                    $sb.Append($reset)
                }

                # Render COL3
                if ($field3) {
                    $isSelected3 = ($fieldIndex + 2 -eq $this.List.GetSelectedIndex())
                    $sb.Append($this.Header.BuildMoveTo($col3X, $rowY))

                    $label3 = $field3.Label
                    if ($label3.Length -gt 20) { $label3 = $label3.Substring(0, 17) + "..." }

                    if ($isSelected3) {
                        $sb.Append($selectColor)
                        $sb.Append($label3)
                        $sb.Append(' ' * (22 - $label3.Length))
                        $sb.Append($reset)
                        $sb.Append($highlightColor)
                    } else {
                        $sb.Append($mutedColor)
                        $sb.Append($label3)
                        $sb.Append($reset)
                        $sb.Append(' ' * (22 - $label3.Length))
                        $sb.Append($textColor)
                    }

                    $val3 = $(if ($field3.Value) { [string]$field3.Value } else { $mutedColor + "(empty)" + $reset })
                    if ($val3.Length -gt 18) { $val3 = $val3.Substring(0, 15) + "..." }
                    $sb.Append($val3)
                    $sb.Append($reset)
                }

                $fieldIndex += 3
                $rowY++
            }

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
        }

        # IF IN EDIT MODE: Render InlineEditor if active
        # FIX: Render this LAST so it overlays the grid
        if ($this.ShowInlineEditor -and $null -ne $this.InlineEditor) {
            # StandardListScreen handles InlineEditor rendering
            # We just need to append it here
            $editorOutput = $this.InlineEditor.Render()
            if ($editorOutput) {
                $sb.Append($editorOutput)
            }
        }

        return $sb.ToString()
    }

    # Override EditItem to edit a field using InlineEditor (TaskListScreen pattern)
    [void] EditItem($field) {
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.EditItem: CALLED with field=$($field.Name if $field else 'NULL')"
        }
        if ($null -eq $field) { return }

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
        $rowY = $contentRect.Y + 2 + $rowIndex

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
            Type = $field.Type
            Value = $field.Value
            Required = $false
            Width = 20
        }

        # Configure InlineEditor (EXACT TaskListScreen pattern)
        $this.InlineEditor.LayoutMode = 'horizontal'
        $this.InlineEditor.SetFields(@($fieldDef))
        $this.InlineEditor.SetPosition($editorX + 22, $rowY)  # Position after label (22 chars)
        $this.InlineEditor.SetSize(20, 1)

        # Set up save callback
        $self = $this
        $fieldName = $field.Name
        $this.InlineEditor.OnConfirmed = {
            param($values)
            # Update the field value
            for ($i = 0; $i -lt $self.AllFields.Count; $i++) {
                if ($self.AllFields[$i].Name -eq $fieldName) {
                    $self.AllFields[$i].Value = $values[$fieldName]
                    break
                }
            }
            # Update ProjectData
            $self.ProjectData.$fieldName = $values[$fieldName]
            $self.ShowInlineEditor = $false
            $self.EditorMode = ""
            $self.CurrentEditItem = $null
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
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] ProjectInfoScreenV3.OnItemActivated: item=$($item.Name if $item else 'NULL')"
        }
        # Edit the selected field
        $this.EditItem($item)
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