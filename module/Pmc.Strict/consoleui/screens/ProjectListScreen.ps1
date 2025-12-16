using namespace System.Collections.Generic
using namespace System.Text

# ProjectListScreen - Project list with full CRUD operations using StandardListScreen
# Uses UniversalList widget and InlineEditor for consistent UX


Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"

# LOW FIX PLS-L4, L5, L9: Define constants for magic strings
$global:DEFAULT_STATUS = 'active'
$script:ARCHIVED_STATUS = 'archived'
$script:ARRAY_SEPARATOR = ', '
$global:DATETIME_FORMAT = 'yyyy-MM-dd HH:mm:ss'
$global:DATE_FORMAT = 'yyyy-MM-dd'
$script:SUPPORTED_DATE_FORMATS = @(
    'yyyy-MM-dd'
    'yyyy-MM-dd HH:mm:ss'
    'MM/dd/yyyy'
    'M/d/yyyy'
    'dd/MM/yyyy'
    'd/M/yyyy'
)

# FIXED PLS-L8, L10: Now using global constants from Constants.ps1
# MAX_PROJECT_NAME_LENGTH = 100 (from Constants.ps1)
# MAX_DESCRIPTION_LENGTH = 4000 (from Constants.ps1)

<#
.SYNOPSIS
Project list screen with CRUD operations

.DESCRIPTION
Shows all projects with:
- Add/Edit/Delete via InlineEditor (a/e/d keys)
- Archive/Unarchive projects
- View project statistics
- Filter and search projects

NOTE: Uses lazy-loaded PmcFilePicker widget for folder browsing
#>
class ProjectListScreen : StandardListScreen {
    # LOW FIX PLS-L1: File picker and flag for overlay display (lazy-loaded for performance)
    [object]$FilePicker = $null
    [bool]$ShowFilePicker = $false

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Projects', 'Project List', 'L', {
                . "$PSScriptRoot/ProjectListScreen.ps1"
                $global:PmcApp.PushScreen((New-Object -TypeName ProjectListScreen))
            }, 10)
    }

    # LOW FIX PLS-L3: Extract common initialization to helper method
    hidden [void] ConfigureCapabilities() {
        # Write-PmcTuiLog "!!! ProjectListScreen.ConfigureCapabilities CALLED !!!" "INFO"
        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $true

        # Configure inline editor layout mode for horizontal (inline) editing
        $this.InlineEditor.LayoutMode = 'horizontal'

        # Configure header
        if ($this.Header) {
            $this.Header.SetBreadcrumb(@("Home", "Projects"))
        }

        # Configure list actions (Add/Edit/Delete + custom actions like V key)
        # Write-PmcTuiLog "!!! About to call _ConfigureListActions !!!" "INFO"
        try {
            $this._ConfigureListActions()
            # Write-PmcTuiLog "!!! _ConfigureListActions completed successfully !!!" "INFO"
        }
        catch {
            Write-PmcTuiLog "!!! ERROR in _ConfigureListActions: $_" "ERROR"
            Write-PmcTuiLog "!!! Stack: $($_.ScriptStackTrace)" "ERROR"
        }

        # Currently uses default columns from UniversalList (works as expected)
        # Future enhancement: Add ConfigureColumns() method to StandardListScreen for custom column layouts
    }

    # LOW FIX PLS-L6: Extract duplicate parseArrayField helper to class method
    hidden [array] ParseArrayField([hashtable]$values, [string]$fieldName) {
        if ($values.ContainsKey($fieldName) -and $null -ne $values.$fieldName -and $values.$fieldName.Trim()) {
            return @($values.$fieldName -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        return @()
    }

    # LOW FIX PLS-L6: Extract duplicate formatDate helper to class method
    hidden [object] FormatDateField([hashtable]$values, [string]$fieldName) {
        if ($values.ContainsKey($fieldName) -and $values.$fieldName -is [DateTime]) {
            return $values.$fieldName
        }
        return $null
    }

    # Constructor
    ProjectListScreen() : base("ProjectList", "Projects") {
        # Write-PmcTuiLog "!!! ProjectListScreen() constructor (no container) called !!!" "INFO"
        $this.ConfigureCapabilities()
        # Write-PmcTuiLog "!!! ProjectListScreen() constructor complete !!!" "INFO"
    }

    # Constructor with container (DI-enabled)
    ProjectListScreen([object]$container) : base("ProjectList", "Projects", $container) {
        # Write-PmcTuiLog "!!! ProjectListScreen(container) constructor called !!!" "INFO"
        $this.ConfigureCapabilities()
        # Write-PmcTuiLog "!!! ProjectListScreen(container) constructor complete !!!" "INFO"
    }

    # === Abstract Method Implementations ===

    # Get entity type for store operations
    [string] GetEntityType() {
        return 'project'
    }

    # Load data and refresh list (required by StandardListScreen)
    [void] LoadData() {
        $items = $this.LoadItems()
        $this.List.SetData($items)
    }

    # Load items from data store
    [array] LoadItems() {
        # CRITICAL FIX PLS-C1: Add null check on GetAllProjects()
        $projects = $this.Store.GetAllProjects()
        if ($null -eq $projects) {
            Write-PmcTuiLog "ProjectListScreen.LoadItems: GetAllProjects() returned null" "ERROR"
            $projects = @()
        }

        # PERFORMANCE FIX: Load all tasks once and build hashtable index - O(n) instead of O(n*m)
        # CRITICAL FIX PLS-C2: Add null check on GetAllTasks()
        $allTasks = $this.Store.GetAllTasks()
        if ($null -eq $allTasks) {
            Write-PmcTuiLog "ProjectListScreen.LoadItems: GetAllTasks() returned null" "WARNING"
            $allTasks = @()
        }
        $tasksByProject = @{}
        # CRITICAL FIX PLS-C3: Ensure $allTasks is array
        foreach ($task in @($allTasks)) {
            # HIGH FIX PLS-H3: Validate before using as hashtable key
            $projName = Get-SafeProperty $task 'project'
            if ($projName -and -not [string]::IsNullOrWhiteSpace($projName)) {
                if (-not $tasksByProject.ContainsKey($projName)) {
                    $tasksByProject[$projName] = 0
                }
                $tasksByProject[$projName]++
            }
        }

        # Add computed fields with O(1) lookup
        # CRITICAL FIX PLS-C4: Ensure $projects is array
        foreach ($project in @($projects)) {
            # Count tasks in this project using hashtable lookup
            $projName = Get-SafeProperty $project 'name'
            $project['task_count'] = $(if ($tasksByProject.ContainsKey($projName)) {
                    $tasksByProject[$projName]
                }
                else { 0 })

            # PS-M3 FIX: Don't always default status to 'active' for existing projects
            # Only add status if it's missing (preserve archived, etc.)
            # If status is genuinely missing, leave it empty rather than assuming 'active'
            if (-not $project.ContainsKey('status') -or $null -eq $project['status']) {
                $project['status'] = ''
            }
        }

        return $projects
    }

    # Define columns for list display
    [array] GetColumns() {
        # Use fixed widths that match the visual layout
        return @(
            @{ Name = 'name'; Label = 'Project'; Width = 41; Align = 'left' }
            @{ Name = 'status'; Label = 'Status'; Width = 19; Align = 'left' }
            @{ Name = 'task_count'; Label = 'Tasks'; Width = 10; Align = 'center' }
            @{ Name = 'description'; Label = 'Description'; Width = 62; Align = 'left' }
        )
    }

    # Define edit fields for InlineEditor (only core fields for quick add/edit)
    # Full field editing is available via the Project Detail view (V action)
    [array] GetEditFields([object]$item) {
        try {
            # CRITICAL: Edit fields must match the full visual layout of GetColumns()
            # GetColumns displays: name=41, status=19, task_count=10, description=62 (total 132)
            # For inline editing, span the full width with only name and description editable
            # Status and task_count are read-only, so we skip them and give their space to name and description

            # Match the column widths exactly - this is what the user sees on screen
            $nameWidth = 41
            $statusWidth = 19    # Not editable - read-only
            $taskCountWidth = 10 # Not editable - read-only
            $descWidth = 62

            if ($null -eq $item -or $item.Count -eq 0) {
                # New project
                Write-PmcTuiLog "ProjectListScreen.GetEditFields: Creating NEW project fields" "DEBUG"
                return @(
                    @{ Name = 'name'; Type = 'text'; Label = 'Project'; Required = $true; Value = ''; MaxLength = $global:MAX_PROJECT_NAME_LENGTH; Width = $nameWidth }
                    @{ Name = 'description'; Type = 'text'; Label = 'Description'; Value = ''; Width = $descWidth }
                )
            }
            else {
                # Existing project
                Write-PmcTuiLog "ProjectListScreen.GetEditFields: Editing existing project '$($item.name)'" "DEBUG"
                return @(
                    @{ Name = 'name'; Type = 'text'; Label = 'Project'; Required = $true; Value = (Get-SafeProperty $item 'name'); MaxLength = $global:MAX_PROJECT_NAME_LENGTH; Width = $nameWidth }
                    @{ Name = 'description'; Type = 'text'; Label = 'Description'; Value = (Get-SafeProperty $item 'description'); Width = $descWidth }
                )
            }
        }
        catch {
            Write-PmcTuiLog "ProjectListScreen.GetEditFields: ERROR - $_" "ERROR"
            Write-PmcTuiLog "Stack: $($_.ScriptStackTrace)" "ERROR"
            return @()
        }
    }

    # Handle item creation
    [void] OnItemCreated([hashtable]$values) {
        if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
            Write-PmcTuiLog "ProjectListScreen.OnItemCreated: CALLED with values: $($values | ConvertTo-Json -Compress)" "DEBUG"
        }
        try {
            # Validate required field
            if (-not $values.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($values.name)) {
                Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Name validation failed" "DEBUG"
                $this.SetStatusMessage("Project name is required", "error")
                return
            }
            Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Name validation passed" "DEBUG"

            # Validate name length
            # HIGH FIX PLS-H1 & PLS-H2: Add null check before .Length access
            # MEDIUM FIX PLS-M4: Use constant for max length validation
            if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
                Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Checking name length: '$($values.name)' (len=$($values.name.Length)) vs max=$global:MAX_PROJECT_NAME_LENGTH" "DEBUG"
            }
            if ($null -ne $values.name -and $values.name.Length -gt $global:MAX_PROJECT_NAME_LENGTH) {
                Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Name too long" "DEBUG"
                $this.SetStatusMessage("Project name must be $global:MAX_PROJECT_NAME_LENGTH characters or less", "error")
                return
            }

            # Validate description length if provided
            # MEDIUM FIX PLS-M5: Use constant for max description length validation
            if ($values.ContainsKey('description') -and $values.description -and $values.description.Length -gt $global:MAX_DESCRIPTION_LENGTH) {
                Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Description too long" "DEBUG"
                $this.SetStatusMessage("Description must be $global:MAX_DESCRIPTION_LENGTH characters or less", "error")
                return
            }

            Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Parsing tags..." "DEBUG"
            # LOW FIX PLS-L6: Use class-level helper methods instead of inline closures
            # Parse tags
            $tags = $this.ParseArrayField($values, 'tags')

            Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Getting existing projects..." "DEBUG"
            # Check for duplicate project name before creating
            # CRITICAL FIX PLS-C5: Add null check on GetAllProjects()
            $existingProjects = $this.Store.GetAllProjects()
            if ($null -eq $existingProjects) { $existingProjects = @() }

            Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Building projectData..." "DEBUG"
            $projectData = @{
                id                       = [guid]::NewGuid().ToString()
                name                     = $values.name
                description              = $(if ($values.ContainsKey('description')) { $values.description } else { '' })
                # CRITICAL FIX: Use datetime object, not string (validation expects datetime type)
                created                  = Get-Date
                # MEDIUM FIX PLS-M3: Use script-level constant for default status
                status                   = $(if ($values.ContainsKey('status')) { $values.status } else { $global:DEFAULT_STATUS })
                tags                     = $tags

                # ID fields
                ID1                      = $(if ($values.ContainsKey('ID1')) { $values.ID1 } else { '' })
                ID2                      = $(if ($values.ContainsKey('ID2')) { $values.ID2 } else { '' })

                # Path fields
                ProjFolder               = $(if ($values.ContainsKey('ProjFolder')) { $values.ProjFolder } else { '' })
                CAAName                  = $(if ($values.ContainsKey('CAAName')) { $values.CAAName } else { '' })
                RequestName              = $(if ($values.ContainsKey('RequestName')) { $values.RequestName } else { '' })
                T2020                    = $(if ($values.ContainsKey('T2020')) { $values.T2020 } else { '' })

                # Date fields
                AssignedDate             = $this.FormatDateField($values, 'AssignedDate')
                DueDate                  = $this.FormatDateField($values, 'DueDate')
                BFDate                   = $this.FormatDateField($values, 'BFDate')

                # Project Info (9 fields)
                RequestDate              = $this.FormatDateField($values, 'RequestDate')
                AuditType                = $(if ($values.ContainsKey('AuditType')) { $values.AuditType } else { '' })
                AuditorName              = $(if ($values.ContainsKey('AuditorName')) { $values.AuditorName } else { '' })
                AuditorPhone             = $(if ($values.ContainsKey('AuditorPhone')) { $values.AuditorPhone } else { '' })
                AuditorTL                = $(if ($values.ContainsKey('AuditorTL')) { $values.AuditorTL } else { '' })
                AuditorTLPhone           = $(if ($values.ContainsKey('AuditorTLPhone')) { $values.AuditorTLPhone } else { '' })
                AuditCase                = $(if ($values.ContainsKey('AuditCase')) { $values.AuditCase } else { '' })
                CASCase                  = $(if ($values.ContainsKey('CASCase')) { $values.CASCase } else { '' })
                AuditStartDate           = $this.FormatDateField($values, 'AuditStartDate')

                # Contact Details (10 fields)
                TPName                   = $(if ($values.ContainsKey('TPName')) { $values.TPName } else { '' })
                TPNum                    = $(if ($values.ContainsKey('TPNum')) { $values.TPNum } else { '' })
                Address                  = $(if ($values.ContainsKey('Address')) { $values.Address } else { '' })
                City                     = $(if ($values.ContainsKey('City')) { $values.City } else { '' })
                Province                 = $(if ($values.ContainsKey('Province')) { $values.Province } else { '' })
                PostalCode               = $(if ($values.ContainsKey('PostalCode')) { $values.PostalCode } else { '' })
                Country                  = $(if ($values.ContainsKey('Country')) { $values.Country } else { '' })

                # Audit Periods (10 fields)
                AuditPeriodFrom          = $this.FormatDateField($values, 'AuditPeriodFrom')
                AuditPeriodTo            = $this.FormatDateField($values, 'AuditPeriodTo')
                AuditPeriod1Start        = $this.FormatDateField($values, 'AuditPeriod1Start')
                AuditPeriod1End          = $this.FormatDateField($values, 'AuditPeriod1End')
                AuditPeriod2Start        = $this.FormatDateField($values, 'AuditPeriod2Start')
                AuditPeriod2End          = $this.FormatDateField($values, 'AuditPeriod2End')
                AuditPeriod3Start        = $this.FormatDateField($values, 'AuditPeriod3Start')
                AuditPeriod3End          = $this.FormatDateField($values, 'AuditPeriod3End')
                AuditPeriod4Start        = $this.FormatDateField($values, 'AuditPeriod4Start')
                AuditPeriod4End          = $this.FormatDateField($values, 'AuditPeriod4End')
                AuditPeriod5Start        = $this.FormatDateField($values, 'AuditPeriod5Start')
                AuditPeriod5End          = $this.FormatDateField($values, 'AuditPeriod5End')

                # Contacts (10 fields)
                Contact1Name             = $(if ($values.ContainsKey('Contact1Name')) { $values.Contact1Name } else { '' })
                Contact1Phone            = $(if ($values.ContainsKey('Contact1Phone')) { $values.Contact1Phone } else { '' })
                Contact1Ext              = $(if ($values.ContainsKey('Contact1Ext')) { $values.Contact1Ext } else { '' })
                Contact1Address          = $(if ($values.ContainsKey('Contact1Address')) { $values.Contact1Address } else { '' })
                Contact1Title            = $(if ($values.ContainsKey('Contact1Title')) { $values.Contact1Title } else { '' })
                Contact2Name             = $(if ($values.ContainsKey('Contact2Name')) { $values.Contact2Name } else { '' })
                Contact2Phone            = $(if ($values.ContainsKey('Contact2Phone')) { $values.Contact2Phone } else { '' })
                Contact2Ext              = $(if ($values.ContainsKey('Contact2Ext')) { $values.Contact2Ext } else { '' })
                Contact2Address          = $(if ($values.ContainsKey('Contact2Address')) { $values.Contact2Address } else { '' })
                Contact2Title            = $(if ($values.ContainsKey('Contact2Title')) { $values.Contact2Title } else { '' })

                # System Info (7 fields)
                AuditProgram             = $(if ($values.ContainsKey('AuditProgram')) { $values.AuditProgram } else { '' })
                AccountingSoftware1      = $(if ($values.ContainsKey('AccountingSoftware1')) { $values.AccountingSoftware1 } else { '' })
                AccountingSoftware1Other = $(if ($values.ContainsKey('AccountingSoftware1Other')) { $values.AccountingSoftware1Other } else { '' })
                AccountingSoftware1Type  = $(if ($values.ContainsKey('AccountingSoftware1Type')) { $values.AccountingSoftware1Type } else { '' })
                AccountingSoftware2      = $(if ($values.ContainsKey('AccountingSoftware2')) { $values.AccountingSoftware2 } else { '' })
                AccountingSoftware2Other = $(if ($values.ContainsKey('AccountingSoftware2Other')) { $values.AccountingSoftware2Other } else { '' })
                AccountingSoftware2Type  = $(if ($values.ContainsKey('AccountingSoftware2Type')) { $values.AccountingSoftware2Type } else { '' })
                Comments                 = $(if ($values.ContainsKey('Comments')) { $values.Comments } else { '' })

                # Additional (2 fields)
                FXInfo                   = $(if ($values.ContainsKey('FXInfo')) { $values.FXInfo } else { '' })
                ShipToAddress            = $(if ($values.ContainsKey('ShipToAddress')) { $values.ShipToAddress } else { '' })
            }

            # Use ValidationHelper for comprehensive validation (already loaded by ClassLoader)
            Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Calling Test-ProjectValid..." "DEBUG"
            $validationResult = Test-ProjectValid $projectData -existingProjects $existingProjects
            Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Validation result IsValid=$($validationResult.IsValid)" "DEBUG"

            if (-not $validationResult.IsValid) {
                # Show ALL validation errors
                $errorMsg = $(if ($validationResult.Errors.Count -gt 0) {
                        $validationResult.Errors -join '; '
                    }
                    else {
                        "Validation failed"
                    })
                $this.SetStatusMessage($errorMsg, "error")
                Write-PmcTuiLog "Project validation failed: $($validationResult.Errors -join ', ')" "ERROR"
                return
            }

            Write-PmcTuiLog "ProjectListScreen.OnItemCreated: Calling Store.AddProject..." "DEBUG"
            $success = $this.Store.AddProject($projectData)
            Write-PmcTuiLog "ProjectListScreen.OnItemCreated: AddProject returned success=$success" "DEBUG"
            if ($success) {
                $this.SetStatusMessage("Project created: $($projectData.name)", "success")
            }
            else {
                $this.SetStatusMessage("Failed to create project: $($this.Store.LastError)", "error")
            }
        }
        catch {
            Write-PmcTuiLog "OnItemCreated exception: $_" "ERROR"
            $this.SetStatusMessage("Unexpected error: $($_.Exception.Message)", "error")
        }
    }

    # Handle item update
    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            # ENDEMIC FIX: Validate required field
            if (-not $values.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($values.name)) {
                $this.SetStatusMessage("Project name is required", "error")
                return
            }

            # LOW FIX PLS-L6: Use class-level helper methods instead of inline closures
            # Parse tags
            $tags = $this.ParseArrayField($values, 'tags')

            # PS-M3 FIX: Preserve existing status if not being changed
            $statusValue = $(if ($values.ContainsKey('status') -and -not [string]::IsNullOrWhiteSpace($values.status)) {
                    $values.status
                }
                else {
                    # Preserve existing status from item
                    Get-SafeProperty $item 'status'
                })

            $changes = @{
                name                     = $values.name
                description              = $(if ($values.ContainsKey('description')) { $values.description } else { '' })
                status                   = $statusValue
                tags                     = $tags

                # ID fields
                ID1                      = $(if ($values.ContainsKey('ID1')) { $values.ID1 } else { '' })
                ID2                      = $(if ($values.ContainsKey('ID2')) { $values.ID2 } else { '' })

                # Path fields
                ProjFolder               = $(if ($values.ContainsKey('ProjFolder')) { $values.ProjFolder } else { '' })
                CAAName                  = $(if ($values.ContainsKey('CAAName')) { $values.CAAName } else { '' })
                RequestName              = $(if ($values.ContainsKey('RequestName')) { $values.RequestName } else { '' })
                T2020                    = $(if ($values.ContainsKey('T2020')) { $values.T2020 } else { '' })

                # Date fields
                AssignedDate             = $this.FormatDateField($values, 'AssignedDate')
                DueDate                  = $this.FormatDateField($values, 'DueDate')
                BFDate                   = $this.FormatDateField($values, 'BFDate')

                # Project Info (9 fields)
                RequestDate              = $this.FormatDateField($values, 'RequestDate')
                AuditType                = $(if ($values.ContainsKey('AuditType')) { $values.AuditType } else { '' })
                AuditorName              = $(if ($values.ContainsKey('AuditorName')) { $values.AuditorName } else { '' })
                AuditorPhone             = $(if ($values.ContainsKey('AuditorPhone')) { $values.AuditorPhone } else { '' })
                AuditorTL                = $(if ($values.ContainsKey('AuditorTL')) { $values.AuditorTL } else { '' })
                AuditorTLPhone           = $(if ($values.ContainsKey('AuditorTLPhone')) { $values.AuditorTLPhone } else { '' })
                AuditCase                = $(if ($values.ContainsKey('AuditCase')) { $values.AuditCase } else { '' })
                CASCase                  = $(if ($values.ContainsKey('CASCase')) { $values.CASCase } else { '' })
                AuditStartDate           = $this.FormatDateField($values, 'AuditStartDate')

                # Contact Details (10 fields)
                TPName                   = $(if ($values.ContainsKey('TPName')) { $values.TPName } else { '' })
                TPNum                    = $(if ($values.ContainsKey('TPNum')) { $values.TPNum } else { '' })
                Address                  = $(if ($values.ContainsKey('Address')) { $values.Address } else { '' })
                City                     = $(if ($values.ContainsKey('City')) { $values.City } else { '' })
                Province                 = $(if ($values.ContainsKey('Province')) { $values.Province } else { '' })
                PostalCode               = $(if ($values.ContainsKey('PostalCode')) { $values.PostalCode } else { '' })
                Country                  = $(if ($values.ContainsKey('Country')) { $values.Country } else { '' })

                # Audit Periods (10 fields)
                AuditPeriodFrom          = $this.FormatDateField($values, 'AuditPeriodFrom')
                AuditPeriodTo            = $this.FormatDateField($values, 'AuditPeriodTo')
                AuditPeriod1Start        = $this.FormatDateField($values, 'AuditPeriod1Start')
                AuditPeriod1End          = $this.FormatDateField($values, 'AuditPeriod1End')
                AuditPeriod2Start        = $this.FormatDateField($values, 'AuditPeriod2Start')
                AuditPeriod2End          = $this.FormatDateField($values, 'AuditPeriod2End')
                AuditPeriod3Start        = $this.FormatDateField($values, 'AuditPeriod3Start')
                AuditPeriod3End          = $this.FormatDateField($values, 'AuditPeriod3End')
                AuditPeriod4Start        = $this.FormatDateField($values, 'AuditPeriod4Start')
                AuditPeriod4End          = $this.FormatDateField($values, 'AuditPeriod4End')
                AuditPeriod5Start        = $this.FormatDateField($values, 'AuditPeriod5Start')
                AuditPeriod5End          = $this.FormatDateField($values, 'AuditPeriod5End')

                # Contacts (10 fields)
                Contact1Name             = $(if ($values.ContainsKey('Contact1Name')) { $values.Contact1Name } else { '' })
                Contact1Phone            = $(if ($values.ContainsKey('Contact1Phone')) { $values.Contact1Phone } else { '' })
                Contact1Ext              = $(if ($values.ContainsKey('Contact1Ext')) { $values.Contact1Ext } else { '' })
                Contact1Address          = $(if ($values.ContainsKey('Contact1Address')) { $values.Contact1Address } else { '' })
                Contact1Title            = $(if ($values.ContainsKey('Contact1Title')) { $values.Contact1Title } else { '' })
                Contact2Name             = $(if ($values.ContainsKey('Contact2Name')) { $values.Contact2Name } else { '' })
                Contact2Phone            = $(if ($values.ContainsKey('Contact2Phone')) { $values.Contact2Phone } else { '' })
                Contact2Ext              = $(if ($values.ContainsKey('Contact2Ext')) { $values.Contact2Ext } else { '' })
                Contact2Address          = $(if ($values.ContainsKey('Contact2Address')) { $values.Contact2Address } else { '' })
                Contact2Title            = $(if ($values.ContainsKey('Contact2Title')) { $values.Contact2Title } else { '' })

                # System Info (7 fields)
                AuditProgram             = $(if ($values.ContainsKey('AuditProgram')) { $values.AuditProgram } else { '' })
                AccountingSoftware1      = $(if ($values.ContainsKey('AccountingSoftware1')) { $values.AccountingSoftware1 } else { '' })
                AccountingSoftware1Other = $(if ($values.ContainsKey('AccountingSoftware1Other')) { $values.AccountingSoftware1Other } else { '' })
                AccountingSoftware1Type  = $(if ($values.ContainsKey('AccountingSoftware1Type')) { $values.AccountingSoftware1Type } else { '' })
                AccountingSoftware2      = $(if ($values.ContainsKey('AccountingSoftware2')) { $values.AccountingSoftware2 } else { '' })
                AccountingSoftware2Other = $(if ($values.ContainsKey('AccountingSoftware2Other')) { $values.AccountingSoftware2Other } else { '' })
                AccountingSoftware2Type  = $(if ($values.ContainsKey('AccountingSoftware2Type')) { $values.AccountingSoftware2Type } else { '' })
                Comments                 = $(if ($values.ContainsKey('Comments')) { $values.Comments } else { '' })

                # Additional (2 fields)
                FXInfo                   = $(if ($values.ContainsKey('FXInfo')) { $values.FXInfo } else { '' })
                ShipToAddress            = $(if ($values.ContainsKey('ShipToAddress')) { $values.ShipToAddress } else { '' })
            }

            # PS-M1 FIX: Add validation before Store.UpdateProject()
            # Validate name length
            # HIGH FIX PLS-H1 & PLS-H2: Add null check before .Length access
            # MEDIUM FIX PLS-M4: Use constant for max length validation
            if ($null -ne $values.name -and $values.name.Length -gt $global:MAX_PROJECT_NAME_LENGTH) {
                $this.SetStatusMessage("Project name must be $global:MAX_PROJECT_NAME_LENGTH characters or less", "error")
                return
            }

            # Validate description length if provided
            # MEDIUM FIX PLS-M5: Use constant for max description length validation
            if ($values.ContainsKey('description') -and $values.description -and $values.description.Length -gt $global:MAX_DESCRIPTION_LENGTH) {
                $this.SetStatusMessage("Description must be $global:MAX_DESCRIPTION_LENGTH characters or less", "error")
                return
            }

            # Validate that original project exists
            $originalName = Get-SafeProperty $item 'name'
            if ([string]::IsNullOrWhiteSpace($originalName)) {
                $this.SetStatusMessage("Cannot update project: original project name is missing", "error")
                return
            }

            # If name is changing, check for duplicate name
            # HIGH FIX PLS-H3: Use case-insensitive comparison to prevent "Project1" and "project1"
            if ($values.name -ne $originalName) {
                # CRITICAL FIX PLS-C6: Add null check
                $existingProjects = $this.Store.GetAllProjects()
                if ($null -eq $existingProjects) { $existingProjects = @() }
                $duplicate = $existingProjects | Where-Object {
                    $existingName = Get-SafeProperty $_ 'name'
                    $null -ne $existingName -and $existingName -ieq $values.name
                }
                if ($duplicate) {
                    $this.SetStatusMessage("Project name '$($values.name)' already exists (case-insensitive)", "error")
                    return
                }
            }

            $success = $this.Store.UpdateProject($originalName, $changes)
            if ($success) {
                $this.SetStatusMessage("Project updated: $($values.name)", "success")
            }
            else {
                $this.SetStatusMessage("Failed to update project: $($this.Store.LastError)", "error")
            }
        }
        catch {
            Write-PmcTuiLog "OnItemUpdated exception: $_" "ERROR"
            $this.SetStatusMessage("Unexpected error: $($_.Exception.Message)", "error")
        }
    }

    # Handle item deletion
    [void] OnItemDeleted([object]$item) {
        # Check if project has tasks
        $itemName = Get-SafeProperty $item 'name'

        # PS-H1 FIX: Use hashtable approach for O(1) lookup instead of O(n) filtering
        # BUG-1 FIX: Move null check AFTER GetAllTasks() call
        $allTasks = $this.Store.GetAllTasks()
        if ($null -eq $allTasks) { $allTasks = @() }
        $tasksByProject = @{}
        foreach ($task in $allTasks) {
            $projName = Get-SafeProperty $task 'project'
            if ($projName) {
                if (-not $tasksByProject.ContainsKey($projName)) {
                    $tasksByProject[$projName] = 0
                }
                $tasksByProject[$projName]++
            }
        }

        $taskCount = $(if ($tasksByProject.ContainsKey($itemName)) {
                $tasksByProject[$itemName]
            }
            else { 0 })

        if ($taskCount -gt 0) {
            # H-UI-8: Better error message with actionable guidance
            $this.SetStatusMessage("Cannot delete project with $taskCount tasks. Reassign or delete tasks first.", "error")
            return
        }

        $success = $this.Store.DeleteProject($itemName)
        if ($success) {
            $this.SetStatusMessage("Project deleted: $itemName", "success")
        }
        else {
            $this.SetStatusMessage("Failed to delete project: $($this.Store.LastError)", "error")
        }
    }

    # === Custom Actions ===

    # Ensure PmcFilePicker is loaded (lazy loading pattern)
    hidden [void] EnsureFilePicker() {
        if ($null -eq ([Type]'PmcFilePicker' -as [Type])) {
            Write-PmcTuiLog "ProjectListScreen: Lazy-loading PmcFilePicker widget" "DEBUG"
            . "$PSScriptRoot/../widgets/PmcFilePicker.ps1"
        }
    }

    # Import projects from Excel spreadsheet
    [void] ImportFromExcel() {
        # IMPLEMENTATION: Launch the full Excel Import wizard screen
        # This provides profile-based mapping, preview, and validation
        try {
            . "$PSScriptRoot/ExcelImportScreen.ps1"
            $importScreen = New-Object ExcelImportScreen
            $this.App.PushScreen($importScreen)
        }
        catch {
            $this.SetStatusMessage("Failed to launch Excel import wizard: $($_.Exception.Message)", "error")
            Write-PmcTuiLog "ImportFromExcel failed: $_" "ERROR"
        }
    }

    # Archive/unarchive project
    # MEDIUM FIX PLS-M9: Use script-level constants for status values
    [void] ToggleProjectArchive([object]$project) {
        if ($null -eq $project) { return }

        $projectStatus = Get-SafeProperty $project 'status'
        $projectName = Get-SafeProperty $project 'name'
        $newStatus = $(if ($projectStatus -eq $script:ARCHIVED_STATUS) { $global:DEFAULT_STATUS } else { $script:ARCHIVED_STATUS })
        $this.Store.UpdateProject($projectName, @{ status = $newStatus })

        $action = $(if ($newStatus -eq $script:ARCHIVED_STATUS) { "archived" } else { "activated" })
        $this.SetStatusMessage("Project ${action}: $projectName", "success")
    }

    # === Input Handling ===

    # Open project folder
    [void] OpenProjectFolder([object]$project) {
        $this.EnsureFilePicker()

        if ($null -eq $project) { return }

        $folderPath = Get-SafeProperty $project 'ProjFolder'
        if ([string]::IsNullOrWhiteSpace($folderPath)) {
            $this.SetStatusMessage("Project has no folder path set", "warning")
            return
        }

        # H-SEC-1: Sanitize and validate file path before use
        try {
            # Resolve to absolute path and validate it's a directory
            $resolvedPath = Resolve-Path -Path $folderPath -ErrorAction Stop
            if (-not (Test-Path -Path $resolvedPath -PathType Container)) {
                $this.SetStatusMessage("Path is not a directory: $folderPath", "error")
                return
            }

            # HIGH FIX PLS-H4: Check read permissions before accessing
            try {
                $null = Get-ChildItem -Path $resolvedPath -ErrorAction Stop | Select-Object -First 1
            }
            catch [System.UnauthorizedAccessException] {
                $this.SetStatusMessage("Access denied to folder: $folderPath", "error")
                return
            }

            $folderPath = $resolvedPath.Path
        }
        catch {
            $this.SetStatusMessage("Invalid or inaccessible folder path: $folderPath", "error")
            return
        }

        try {
            # Show integrated file picker to browse the project folder
            $this.FilePicker = [PmcFilePicker]::new($folderPath, $true)
            $this.ShowFilePicker = $true
            $this.SetStatusMessage("Browsing folder: $folderPath", "info")
        }
        catch {
            $this.SetStatusMessage("Failed to open file picker: $($_.Exception.Message)", "error")
        }
    }

    # Called by StandardListScreen when inline editing is cancelled
    [void] OnInlineEditCancelled() {
        # This method is called when inline edit is cancelled (e.g., Escape key)
        # ProjectListScreen relies on the base StandardListScreen behavior
        Write-PmcTuiLog "OnInlineEditCancelled called" "DEBUG"
        # No-op: StandardListScreen handles the UI updates
    }

    # Get custom actions for footer display
    [array] GetCustomActions() {
        $self = $this
        return @(
            @{ Key = 'r'; Label = 'Archive'; Callback = {
                    $selected = $self.List.GetSelectedItem()
                    $self.ToggleProjectArchive($selected)
                }.GetNewClosure()
            },
            @{ Key = 'v'; Label = 'View'; Callback = {
                    # Write-PmcTuiLog "!!! GetCustomActions V KEY CALLBACK FIRED !!!" "INFO"
                    $selected = $self.List.GetSelectedItem()
                    # Write-PmcTuiLog "Selected: $($selected | ConvertTo-Json -Compress)" "INFO"
                    if ($selected) {
                        $projectName = Get-SafeProperty $selected 'name'
                        # Write-PmcTuiLog "Project name: $projectName" "INFO"
                        # Use container to resolve screen (avoids type resolution at parse time)
                        if (-not $global:PmcContainer.IsRegistered('ProjectInfoScreenV4')) {
                            # Write-PmcTuiLog "Registering ProjectInfoScreenV4" "INFO"
                            $screenPath = "$PSScriptRoot/ProjectInfoScreenV4.ps1"
                            $global:PmcContainer.Register('ProjectInfoScreenV4', {
                                    param($c)
                                    . $screenPath
                                    return New-Object ProjectInfoScreenV4 -ArgumentList $c
                                }.GetNewClosure(), $false)
                        }
                        # Write-PmcTuiLog "Resolving screen" "INFO"
                        $screen = $global:PmcContainer.Resolve('ProjectInfoScreenV4')
                        # Write-PmcTuiLog "Setting project: $projectName" "INFO"
                        $screen.SetProject($projectName)
                        # Write-PmcTuiLog "Pushing screen" "INFO"
                        $global:PmcApp.PushScreen($screen)
                        # Write-PmcTuiLog "Screen pushed!" "INFO"
                    }
                    else {
                        Write-PmcTuiLog "NO SELECTED ITEM" "ERROR"
                    }
                }.GetNewClosure()
            },
            @{ Key = 'o'; Label = 'Open Folder'; Callback = {
                    $selected = $self.List.GetSelectedItem()
                    $self.OpenProjectFolder($selected)
                }.GetNewClosure()
            },
            @{ Key = 'i'; Label = 'Import Excel'; Callback = {
                    # Check if Excel is available before attempting import
                    $excelAvailable = $false
                    try {
                        if ($PSVersionTable.PSVersion.Major -ge 6) {
                            # PowerShell Core - check for Excel COM object on Windows
                            if ($IsWindows) {
                                $excelAvailable = $null -ne (Get-Command excel.exe -ErrorAction SilentlyContinue)
                            }
                        }
                        else {
                            # Windows PowerShell - check for Excel COM
                            $excelAvailable = $null -ne (New-Object -ComObject Excel.Application -ErrorAction SilentlyContinue)
                        }
                    }
                    catch {
                        $excelAvailable = $false
                    }

                    if ($excelAvailable) {
                        $self.ImportFromExcel()
                    }
                    else {
                        $self.SetStatusMessage("Excel is not installed or not available", "error")
                    }
                }.GetNewClosure()
            }
        )
    }

    # Override Render to show file picker overlay
    # Override RenderContentToEngine to show file picker overlay
    [void] RenderContentToEngine([object]$engine) {
        # Base render (List + standard overlays)
        ([StandardListScreen]$this).RenderContentToEngine($engine)

        # Render file picker overlay if showing
        if ($this.ShowFilePicker -and $null -ne $this.FilePicker) {
            # FilePicker has RenderToEngine
            $this.FilePicker.RenderToEngine($engine)
        }
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # CRITICAL: Call StandardListScreen parent FIRST - it handles inline editor, filter panel, menu bar, etc.
        # DO NOT skip to PmcScreen - that bypasses the inline editor input handling!
        $handled = ([StandardListScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        # Handle custom project keys after StandardListScreen (ONLY when editor/filter NOT showing!)
        if (-not $this.ShowInlineEditor -and -not $this.ShowFilterPanel) {
            # Custom key: Enter = View project details (user preference over standard edit behavior)
            if ($keyInfo.Key -eq ([ConsoleKey]::Enter)) {
                $selected = $this.List.GetSelectedItem()
                if ($selected) {
                    $this.ViewProjectDetails($selected)
                }
                return $true
            }

            # Custom key: E = Edit selected project
            if ($keyInfo.KeyChar -eq 'e' -or $keyInfo.KeyChar -eq 'E') {
                if ($this.AllowEdit) {
                    $selected = $this.List.GetSelectedItem()
                    if ($selected) {
                        $this.EditItem($selected)
                    }
                }
                return $true
            }

            # Custom key: V = View project details/stats
            if ($keyInfo.KeyChar -eq 'v' -or $keyInfo.KeyChar -eq 'V') {
                # Defensive check: ensure List exists
                if ($null -eq $this.List) {
                    Write-PmcTuiLog "ERROR: List is null when V pressed" "ERROR"
                    $this.SetStatusMessage("Internal error: List not initialized", "error")
                    return $true
                }

                $selected = $this.List.GetSelectedItem()

                if ($null -eq $selected) {
                    Write-PmcTuiLog "No project selected when V pressed" "WARNING"
                    $this.SetStatusMessage("No project selected", "warning")
                    return $true
                }

                try {
                    $projectName = Get-SafeProperty $selected 'name'
                    $screen = New-Object ProjectInfoScreenV4 -ArgumentList $this.Container
                    $screen.SetProject($projectName)
                    $global:PmcApp.PushScreen($screen)
                    $this.SetStatusMessage("Viewing project: $projectName", "success")
                }
                catch {
                    $errorMsg = "Failed to open project view: $($_.Exception.Message)"
                    Write-PmcTuiLog "!!! EXCEPTION: $errorMsg" "ERROR"
                    Write-PmcTuiLog "!!! Stack trace: $($_.ScriptStackTrace)" "ERROR"
                    $this.SetStatusMessage($errorMsg, "error")
                }
                return $true
            }

            # Custom key: R = Archive/Unarchive
            if ($keyInfo.KeyChar -eq 'r' -or $keyInfo.KeyChar -eq 'R') {
                $selected = $this.List.GetSelectedItem()
                $this.ToggleProjectArchive($selected)
                return $true
            }

            # Custom key: O = Open project folder
            if ($keyInfo.KeyChar -eq 'o' -or $keyInfo.KeyChar -eq 'O') {
                $selected = $this.List.GetSelectedItem()
                $this.OpenProjectFolder($selected)
                return $true
            }

            # Custom key: I = Import from Excel
            if ($keyInfo.KeyChar -eq 'i' -or $keyInfo.KeyChar -eq 'I') {
                $this.ImportFromExcel()
                return $true
            }
        }  # End of editor/filter check

        # If file picker is showing, route input to it
        if ($this.ShowFilePicker -and $null -ne $this.FilePicker) {
            $handled = $this.FilePicker.HandleInput($keyInfo)

            # Check if file picker completed
            if ($this.FilePicker.IsComplete) {
                if ($this.FilePicker.Result) {
                    # User selected a folder
                    $selectedPath = $this.FilePicker.SelectedPath
                    $this.SetStatusMessage("Selected: $selectedPath", "success")
                }
                else {
                    $this.SetStatusMessage("Folder browsing cancelled", "info")
                }
                # Close file picker
                $this.ShowFilePicker = $false
                $this.FilePicker = $null
            }

            return $true
        }

        return $false
    }
}

# REMAINING FIXES DOCUMENTED (non-critical):
# HIGH: PLS-H1 (line 335), H2 (line 604), H4 (line 349), H5 (line 494) - String.Length null checks
# MEDIUM: 9 issues - Error handling, validation improvements
# LOW: 11 issues - Code quality, constants, DRY principle
# All CRITICAL safety issues FIXED (7/7)