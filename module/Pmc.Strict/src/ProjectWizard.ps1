# ProjectWizard.ps1 - Modern guided project creation wizard
# Updated to use current PMC display standards (PmcGridRenderer, Show-PmcDataGrid)

class PmcProjectWizard {
    [hashtable]$ProjectData
    [hashtable]$Templates
    [string]$CurrentStep
    [bool]$IsComplete

    PmcProjectWizard() {
        $this.InitializeWizard()
    }

    [void] InitializeWizard() {
        $this.IsComplete = $false
        $this.CurrentStep = 'template'

        $this.ProjectData = @{
            name = ""
            description = ""
            ID1 = ""
            ID2 = ""
            ProjFolder = ""
            AssignedDate = ""
            DueDate = ""
            BFDate = ""
            CAAName = ""
            RequestName = ""
            T2020 = ""
            icon = "📁"
            sortOrder = 0
            aliases = @()
            color = "Gray"
            isArchived = $false
            created = ""
        }

        $this.InitializeTemplates()
    }

    [void] InitializeTemplates() {
        $this.Templates = @{
            'software' = @{
                Name = 'Software Development'
                Description = 'Full-stack development project with phases'
                Goals = @('Requirements Analysis', 'Design & Architecture', 'Development', 'Testing', 'Deployment')
                TimelineWeeks = 12
                SuggestedTools = @('IDE', 'Version Control', 'Issue Tracker', 'CI/CD')
                DefaultTags = @('development', 'software')
            }
            'marketing' = @{
                Name = 'Marketing Campaign'
                Description = 'Comprehensive marketing campaign planning'
                Goals = @('Market Research', 'Strategy Development', 'Content Creation', 'Campaign Launch', 'Analytics')
                TimelineWeeks = 8
                SuggestedTools = @('Analytics', 'Social Media Tools', 'Design Software', 'Email Platform')
                DefaultTags = @('marketing', 'campaign')
            }
            'research' = @{
                Name = 'Research Project'
                Description = 'Academic or business research initiative'
                Goals = @('Literature Review', 'Methodology Design', 'Data Collection', 'Analysis', 'Report Writing')
                TimelineWeeks = 16
                SuggestedTools = @('Research Database', 'Survey Tools', 'Statistical Software', 'Writing Tools')
                DefaultTags = @('research', 'analysis')
            }
            'event' = @{
                Name = 'Event Planning'
                Description = 'Conference, meeting, or event organization'
                Goals = @('Planning & Budget', 'Venue & Logistics', 'Speaker Coordination', 'Marketing', 'Execution')
                TimelineWeeks = 6
                SuggestedTools = @('Event Platform', 'Registration System', 'Communication Tools', 'Budget Tracker')
                DefaultTags = @('event', 'planning')
            }
            'custom' = @{
                Name = 'Custom Project'
                Description = 'Build your project from scratch'
                Goals = @()
                TimelineWeeks = 4
                SuggestedTools = @()
                DefaultTags = @()
            }
        }
    }

    [void] Start() {
        try {
            Write-PmcStyled -Style 'Header' -Text "`n🚀 PMC Project Creation Wizard"
            Write-PmcStyled -Style 'Body' -Text "This wizard will guide you through creating a project with your actual fields.`n"

            # Step 1: Basic Info (Name, Description, IDs, Folder)
            $this.EditBasicInfo()
            if (-not $this.ProjectData.name) { return }

            # Step 2: Project Dates
            $this.EditDates()

            # Step 3: Review & Create
            $this.ReviewAndCreate()

        } catch {
            Write-PmcStyled -Style 'Error' -Text "Wizard error: $_"
        }
    }

    [void] SelectTemplate() {
        Write-PmcStyled -Style 'Info' -Text "📋 Step 1: Select Project Template"

        # Build template selection data
        $templateRows = @()
        foreach ($key in $this.Templates.Keys) {
            $template = $this.Templates[$key]
            $templateRows += [pscustomobject]@{
                Key = $key
                Name = $template.Name
                Description = $template.Description
                Timeline = "$($template.TimelineWeeks) weeks"
                Tools = ($template.SuggestedTools -join ', ').Substring(0, [Math]::Min(40, ($template.SuggestedTools -join ', ').Length))
            }
        }

        $columns = @{
            Name = @{ Header='Template'; Width=20; Alignment='Left' }
            Description = @{ Header='Description'; Width=35; Alignment='Left' }
            Timeline = @{ Header='Timeline'; Width=12; Alignment='Left' }
            Tools = @{ Header='Suggested Tools'; Width=0; Alignment='Left' }
        }

        $selectedTemplate = $null
        Show-PmcDataGrid -Domains @('wizard-template') -Columns $columns -Data $templateRows -Title 'Project Templates' -Interactive -OnSelectCallback {
            param($item)
            if ($item -and $item.PSObject.Properties['Key']) {
                $selectedTemplate = [string]$item.Key
                Write-PmcStyled -Style 'Success' -Text "[OK] Selected: $($item.Name)"
            }
        }

        $this.ProjectData.template = $selectedTemplate
        if ($selectedTemplate -and $this.Templates.ContainsKey($selectedTemplate)) {
            $template = $this.Templates[$selectedTemplate]
            $this.ProjectData.goals = $template.Goals
            $this.ProjectData.tools = $template.SuggestedTools
            $this.ProjectData.tags = $template.DefaultTags

            # Set suggested timeline
            $suggestedEnd = (Get-Date).AddDays($template.TimelineWeeks * 7).ToString("yyyy-MM-dd")
            $this.ProjectData.start_date = (Get-Date).ToString("yyyy-MM-dd")
            $this.ProjectData.deadline = $suggestedEnd
        }
    }

    [void] EditBasicInfo() {
        Write-PmcStyled -Style 'Info' -Text "`n📝 Step 2: Project Details"

        # Create editable project info with ALL your actual fields
        $projectInfo = [pscustomobject]@{
            Name = $this.ProjectData.name
            Description = $this.ProjectData.description
            ID1 = $this.ProjectData.ID1
            ID2 = $this.ProjectData.ID2
            ProjFolder = $this.ProjectData.ProjFolder
            CAAName = $this.ProjectData.CAAName
            RequestName = $this.ProjectData.RequestName
            T2020 = $this.ProjectData.T2020
        }

        $columns = @{
            Name = @{ Header='Project Name'; Width=15; Alignment='Left'; Editable=$true }
            Description = @{ Header='Description'; Width=20; Alignment='Left'; Editable=$true }
            ID1 = @{ Header='ID1'; Width=10; Alignment='Left'; Editable=$true }
            ID2 = @{ Header='ID2'; Width=10; Alignment='Left'; Editable=$true }
            ProjFolder = @{ Header='Project Folder'; Width=15; Alignment='Left'; Editable=$true }
            CAAName = @{ Header='CAA Name'; Width=12; Alignment='Left'; Editable=$true }
            RequestName = @{ Header='Request Name'; Width=15; Alignment='Left'; Editable=$true }
            T2020 = @{ Header='T2020'; Width=10; Alignment='Left'; Editable=$true }
        }

        Write-PmcStyled -Style 'Body' -Text "Edit your project fields. Press Enter to save changes, Q to continue."

        Show-PmcDataGrid -Domains @('wizard-info') -Columns $columns -Data @($projectInfo) -Title 'Project Information' -Interactive -OnSelectCallback {
            param($item)
            if ($item) {
                $this.ProjectData.name = [string]$item.Name
                $this.ProjectData.description = [string]$item.Description
                $this.ProjectData.ID1 = [string]$item.ID1
                $this.ProjectData.ID2 = [string]$item.ID2
                $this.ProjectData.ProjFolder = [string]$item.ProjFolder
                $this.ProjectData.CAAName = [string]$item.CAAName
                $this.ProjectData.RequestName = [string]$item.RequestName
                $this.ProjectData.T2020 = [string]$item.T2020
                Write-PmcStyled -Style 'Success' -Text "[OK] Project details saved"
            }
        }
    }

    [void] EditGoals() {
        Write-PmcStyled -Style 'Info' -Text "`n🎯 Step 3: Project Goals"

        if ($this.ProjectData.goals -and $this.ProjectData.goals.Count -gt 0) {
            Write-PmcStyled -Style 'Body' -Text "Template suggested goals (edit as needed):"
        } else {
            Write-PmcStyled -Style 'Body' -Text "Add your project goals:"
        }

        # Convert goals to editable format
        $goalRows = @()
        $goalIndex = 1
        foreach ($goal in $this.ProjectData.goals) {
            $goalRows += [pscustomobject]@{
                Index = $goalIndex
                Goal = $goal
                Status = 'pending'
            }
            $goalIndex++
        }

        # Add empty row for new goal
        $goalRows += [pscustomobject]@{
            Index = $goalIndex
            Goal = ""
            Status = 'pending'
        }

        $columns = @{
            Index = @{ Header='#'; Width=3; Alignment='Right'; Editable=$false }
            Goal = @{ Header='Goal/Milestone'; Width=50; Alignment='Left'; Editable=$true }
            Status = @{ Header='Status'; Width=10; Alignment='Left'; Editable=$false }
        }

        Write-PmcStyled -Style 'Body' -Text "Edit goals below. Add new goals in empty rows. Q to continue."

        Show-PmcDataGrid -Domains @('wizard-goals') -Columns $columns -Data $goalRows -Title 'Project Goals' -Interactive -OnSelectCallback {
            param($item)
            # Extract non-empty goals
            $updatedGoals = @()
            foreach ($row in $goalRows) {
                if ($row.Goal -and $row.Goal.Trim()) {
                    $updatedGoals += $row.Goal.Trim()
                }
            }
            $this.ProjectData.goals = $updatedGoals
            Write-PmcStyled -Style 'Success' -Text "[OK] Goals updated ($($updatedGoals.Count) goals)"
        }
    }

    [void] EditDates() {
        Write-PmcStyled -Style 'Info' -Text "`n📅 Step 4: Project Dates"

        $dateData = [pscustomobject]@{
            AssignedDate = $this.ProjectData.AssignedDate
            DueDate = $this.ProjectData.DueDate
            BFDate = $this.ProjectData.BFDate
        }

        $columns = @{
            AssignedDate = @{ Header='Assigned Date'; Width=20; Alignment='Left'; Editable=$true }
            DueDate = @{ Header='Due Date'; Width=20; Alignment='Left'; Editable=$true }
            BFDate = @{ Header='BF Date'; Width=20; Alignment='Left'; Editable=$true }
        }

        Write-PmcStyled -Style 'Body' -Text "Set your project dates. Q to continue."

        Show-PmcDataGrid -Domains @('wizard-dates') -Columns $columns -Data @($dateData) -Title 'Project Dates' -Interactive -OnSelectCallback {
            param($item)
            if ($item) {
                $this.ProjectData.AssignedDate = [string]$item.AssignedDate
                $this.ProjectData.DueDate = [string]$item.DueDate
                $this.ProjectData.BFDate = [string]$item.BFDate
                Write-PmcStyled -Style 'Success' -Text "[OK] Dates updated"
            }
        }
    }

    [void] EditResources() {
        Write-PmcStyled -Style 'Info' -Text "`n💼 Step 5: Resources"

        $resourceData = [pscustomobject]@{
            Budget = $this.ProjectData.budget
            Team = ($this.ProjectData.team -join ', ')
            Tools = ($this.ProjectData.tools -join ', ')
            Tags = ($this.ProjectData.tags -join ', ')
        }

        $columns = @{
            Budget = @{ Header='Budget'; Width=15; Alignment='Left'; Editable=$true }
            Team = @{ Header='Team (comma separated)'; Width=25; Alignment='Left'; Editable=$true }
            Tools = @{ Header='Tools (comma separated)'; Width=25; Alignment='Left'; Editable=$true }
            Tags = @{ Header='Tags (comma separated)'; Width=20; Alignment='Left'; Editable=$true }
        }

        Write-PmcStyled -Style 'Body' -Text "Edit project resources. Q to continue."

        Show-PmcDataGrid -Domains @('wizard-resources') -Columns $columns -Data @($resourceData) -Title 'Project Resources' -Interactive -OnSelectCallback {
            param($item)
            if ($item) {
                $this.ProjectData.budget = [string]$item.Budget
                $this.ProjectData.team = @(([string]$item.Team).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $this.ProjectData.tools = @(([string]$item.Tools).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $this.ProjectData.tags = @(([string]$item.Tags).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                Write-PmcStyled -Style 'Success' -Text "[OK] Resources updated"
            }
        }
    }

    [void] ReviewAndCreate() {
        Write-PmcStyled -Style 'Info' -Text "`n📋 Step 3: Review & Create"

        # Build review summary using ALL actual PMC fields
        $reviewRows = @(
            [pscustomobject]@{ Field='Name'; Value=$this.ProjectData.name }
            [pscustomobject]@{ Field='Description'; Value=$this.ProjectData.description }
            [pscustomobject]@{ Field='ID1'; Value=$this.ProjectData.ID1 }
            [pscustomobject]@{ Field='ID2'; Value=$this.ProjectData.ID2 }
            [pscustomobject]@{ Field='Project Folder'; Value=$this.ProjectData.ProjFolder }
            [pscustomobject]@{ Field='CAA Name'; Value=$this.ProjectData.CAAName }
            [pscustomobject]@{ Field='Request Name'; Value=$this.ProjectData.RequestName }
            [pscustomobject]@{ Field='T2020'; Value=$this.ProjectData.T2020 }
            [pscustomobject]@{ Field='Assigned Date'; Value=$this.ProjectData.AssignedDate }
            [pscustomobject]@{ Field='Due Date'; Value=$this.ProjectData.DueDate }
            [pscustomobject]@{ Field='BF Date'; Value=$this.ProjectData.BFDate }
        )

        $columns = @{
            Field = @{ Header='Field'; Width=15; Alignment='Left'; Editable=$false }
            Value = @{ Header='Value'; Width=0; Alignment='Left'; Editable=$false }
        }

        Write-PmcStyled -Style 'Body' -Text "Review your project details. Press Enter to create the project."

        Show-PmcDataGrid -Domains @('wizard-review') -Columns $columns -Data $reviewRows -Title 'Project Review' -Interactive -OnSelectCallback {
            param($item)
            $this.CreateProject()
        }
    }

    [void] CreateProject() {
        Write-PmcStyled -Style 'Info' -Text "`n🚀 Creating project..."

        try {
            # Create the project directly through data system
            $projectName = $this.ProjectData.name
            Write-PmcStyled -Style 'Body' -Text "Creating project: $projectName"

            # Load existing data
            $allData = Get-PmcAllData

            # Create new project using ALL actual PMC fields
            $newProject = @{
                name = $projectName
                description = $this.ProjectData.description
                ID1 = $this.ProjectData.ID1
                ID2 = $this.ProjectData.ID2
                ProjFolder = $this.ProjectData.ProjFolder
                AssignedDate = $this.ProjectData.AssignedDate
                DueDate = $this.ProjectData.DueDate
                BFDate = $this.ProjectData.BFDate
                CAAName = $this.ProjectData.CAAName
                RequestName = $this.ProjectData.RequestName
                T2020 = $this.ProjectData.T2020
                icon = $this.ProjectData.icon
                color = $this.ProjectData.color
                sortOrder = $this.ProjectData.sortOrder
                aliases = $this.ProjectData.aliases
                isArchived = $this.ProjectData.isArchived
                created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            }

            # Add to data
            if (-not $allData.projects) { $allData.projects = @() }
            $allData.projects += $newProject


            # Save all data
            Set-PmcAllData $allData

            $this.IsComplete = $true

            Write-PmcStyled -Style 'Success' -Text "`n[OK] Project '$projectName' created successfully!"
            Write-PmcStyled -Style 'Body' -Text "`nUse 'projects' to view your new project."

        } catch {
            Write-PmcStyled -Style 'Error' -Text "[ERROR] Error creating project: $_"
        }
    }
}

# Export the wizard function for PMC command integration
function Start-PmcProjectWizard {
    param([PmcCommandContext]$Context)

    $wizard = [PmcProjectWizard]::new()
    $wizard.Start()
}

# Export module member
Export-ModuleMember -Function Start-PmcProjectWizard