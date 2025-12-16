# SpeedTUI Projects Screen - Project management with TimeScreen interaction style

# Load dependencies
. "$PSScriptRoot/../Core/Component.ps1"
. "$PSScriptRoot/../Core/PerformanceMonitor.ps1"
. "$PSScriptRoot/../Services/ProjectService.ps1"
. "$PSScriptRoot/../BorderHelper.ps1"
. "$PSScriptRoot/../Components/FormManager.ps1"

class ProjectsScreen : Component {
    [object]$ProjectService
    [object]$PerformanceMonitor
    [array]$Projects = @()
    [int]$SelectedProject = 0
    [string]$ViewMode = "List"  # List, Add, Edit, Delete
    [hashtable]$NewProject = @{}
    [DateTime]$LastRefresh
    [FormManager]$AddForm
    [FormManager]$EditForm
    
    ProjectsScreen() : base() {
        try {
            $this.Initialize()
        } catch {
            $logger = Get-Logger
            $logger.Fatal("SpeedTUI", "ProjectsScreen", "Constructor failed", @{
                Exception = $_.Exception.ToString()
                Message = $_.Exception.Message
            })
            throw
        }
    }
    
    [void] Initialize() {
        try {
            $this.ProjectService = [ProjectService]::GetInstance()
            $this.PerformanceMonitor = Get-PerformanceMonitor
            
            # Initialize empty array to prevent null reference
            if ($null -eq $this.Projects) {
                $this.Projects = @()
            }
            
            # Initialize forms
            $this.InitializeForms()
            
            $this.RefreshData()
            $this.LastRefresh = [DateTime]::Now
            
            $this.PerformanceMonitor.IncrementCounter("screen.projects.initialized", @{})
        } catch {
            $logger = Get-Logger
            $logger.Error("SpeedTUI", "ProjectsScreen", "Initialization failed", @{
                Exception = $_.Exception.ToString()
                Message = $_.Exception.Message
            })
            # Ensure we have at least empty collections
            if ($null -eq $this.Projects) {
                $this.Projects = @()
            }
        }
    }
    
    [void] InitializeForms() {
        $logger = Get-Logger
        $logger.Debug("SpeedTUI", "ProjectsScreen", "Initializing forms")
        
        # Create Add form
        $this.AddForm = [FormManager]::new()
        $logger.Debug("SpeedTUI", "ProjectsScreen", "AddForm created")
        
        # Add required fields with validation
        $nameField = [InputField]::new("Project Name", "e.g., Website Redesign")
        $nameField.Validator = [InputValidators]::Required()
        $this.AddForm.AddField($nameField)
        
        $this.AddForm.AddTextField("Description", "Project description...")
        
        $dueDateField = [InputField]::new("Due Date", "MM/dd/yyyy")
        $dueDateField.FieldType = "date"
        $this.AddForm.AddField($dueDateField)
        
        $this.AddForm.AddTextField("ID1", "e.g., PRJ001")
        $this.AddForm.AddTextField("ID2", "e.g., PROJ01")
        
        $logger.Debug("SpeedTUI", "ProjectsScreen", "AddForm fields added", @{
            FieldCount = $this.AddForm.Fields.Count
        })
        
        # Create Edit form (same fields as Add form)
        $this.EditForm = [FormManager]::new()
        
        # Add required fields with validation (same as Add form)
        $editNameField = [InputField]::new("Project Name", "e.g., Website Redesign")
        $editNameField.Validator = [InputValidators]::Required()
        $this.EditForm.AddField($editNameField)
        
        $this.EditForm.AddTextField("Description", "Project description...")
        
        $editDueDateField = [InputField]::new("Due Date", "MM/dd/yyyy")
        $editDueDateField.FieldType = "date"
        $this.EditForm.AddField($editDueDateField)
        
        $this.EditForm.AddTextField("ID1", "e.g., PRJ001")
        $this.EditForm.AddTextField("ID2", "e.g., PROJ01")
    }
    
    [string[]] Render() {
        $timing = Start-PerformanceTiming "ProjectsScreen.Render"
        $logger = Get-Logger
        
        $logger.Trace("SpeedTUI", "ProjectsScreen", "Render start", @{
            ViewMode = $this.ViewMode
            ProjectsCount = $(if ($this.Projects) { $this.Projects.Count } else { 0 })
            AddFormExists = $null -ne $this.AddForm
            EditFormExists = $null -ne $this.EditForm
        })
        
        try {
            $lines = @()
            
            # Header
            $lines += $this.RenderHeader()
            $lines += ""
            
            switch ($this.ViewMode) {
                "List" {
                    $lines += $this.RenderProjectsList()
                }
                "Add" {
                    $lines += $this.RenderAddProject()
                }
                "Edit" {
                    $lines += $this.RenderEditProject()
                }
                "Delete" {
                    $lines += $this.RenderDeleteConfirmation()
                }
            }
            
            $lines += ""
            $lines += $this.RenderControls()
            
            return $lines
            
        } finally {
            Stop-PerformanceTiming $timing
        }
    }
    
    [string[]] RenderHeader() {
        $lines = @()
        
        # Get project totals
        $totalProjects = $this.Projects.Count
        $activeProjects = ($this.Projects | Where-Object { -not $_.ClosedDate -or $_.ClosedDate -eq [DateTime]::MinValue }).Count
        $completedProjects = ($this.Projects | Where-Object { $_.ClosedDate -and $_.ClosedDate -ne [DateTime]::MinValue }).Count
        
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::ContentLine("PROJECT MANAGEMENT".PadLeft(([Console]::WindowWidth - 35) / 2 + 18))
        $lines += [BorderHelper]::ContentLine("Total Projects: $($totalProjects.ToString().PadLeft(2)) │ Active: $($activeProjects.ToString().PadLeft(2)) │ Completed: $($completedProjects.ToString().PadLeft(2))")
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string[]] RenderProjectsList() {
        $lines = @()
        
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::ContentLine("Projects List                                         ↑↓ to navigate")
        $lines += [BorderHelper]::MiddleBorder()
        
        if ($this.Projects.Count -eq 0) {
            $lines += [BorderHelper]::ContentLine("No projects found. Press 'A' to add a project.")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::EmptyLine()
        } else {
            $lines += [BorderHelper]::ContentLine("Status │ Project Name                        │ ID1      │ ID2      │ Due Date")
            $lines += [BorderHelper]::MiddleBorder()
            
            # Show projects
            $index = 0
            foreach ($project in $this.Projects) {
                $marker = $(if ($index -eq $this.SelectedProject) { "►" } else { " " })
                
                # Format status
                $status = $(if ($project.ClosedDate -and $project.ClosedDate -ne [DateTime]::MinValue) { "[[OK]]" } else { "[ ]" })
                
                # Format name
                $nameStr = "$marker$($project.FullProjectName)".PadRight(36)
                if ($nameStr.Length -gt 36) { $nameStr = $nameStr.Substring(0, 33) + "..." }
                
                # Format IDs
                $id1Str = $(if ($project.ID1) { $project.ID1.PadRight(8) } else { "".PadRight(8) })
                if ($id1Str.Length -gt 8) { $id1Str = $id1Str.Substring(0, 8) }
                $id2Str = $(if ($project.ID2) { $project.ID2.PadRight(8) } else { "".PadRight(8) })
                if ($id2Str.Length -gt 8) { $id2Str = $id2Str.Substring(0, 8) }
                
                # Format due date
                $dueDateStr = $(if ($project.DateDue -and $project.DateDue -ne [DateTime]::MinValue) { 
                    $project.DateDue.ToString("MM/dd/yy").PadRight(8) 
                } else { 
                    "".PadRight(8) 
                })
                
                $lines += [BorderHelper]::ContentLine("$status │ $nameStr │ $id1Str │ $id2Str │ $dueDateStr")
                $index++
            }
            
            # Fill remaining lines to maintain consistent height
            while ($index -lt 8) {
                $lines += [BorderHelper]::EmptyLine()
                $index++
            }
        }
        
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string[]] RenderAddProject() {
        $lines = @()
        $lines += "┌─ Add New Project " + ("─" * ([Console]::WindowWidth - 20)) + "┐"
        $lines += [BorderHelper]::EmptyLine()
        
        # Render the form with null check
        if ($null -ne $this.AddForm) {
            try {
                $width = [Math]::Max(40, [Console]::WindowWidth - 6)
                $formLines = $this.AddForm.Render($width)
                foreach ($line in $formLines) {
                    $lines += [BorderHelper]::ContentLine($line)
                }
            } catch {
                $lines += [BorderHelper]::ContentLine("Error rendering form: $($_.Exception.Message)")
            }
        } else {
            $lines += [BorderHelper]::ContentLine("Form not initialized")
        }
        
        $lines += [BorderHelper]::EmptyLine()
        $lines += [BorderHelper]::ContentLine("Tab/Shift+Tab: Navigate fields | Enter: Save | Esc: Cancel")
        $lines += [BorderHelper]::EmptyLine()
        $lines += "└" + ("─" * ([Console]::WindowWidth - 2)) + "┘"
        
        return $lines
    }
    
    [string[]] RenderEditProject() {
        $lines = @()
        $lines += "┌─ Edit Project " + ("─" * ([Console]::WindowWidth - 17)) + "┐"
        $lines += [BorderHelper]::EmptyLine()
        
        # Show which project is being edited
        if ($this.SelectedProject -lt $this.Projects.Count) {
            $project = $this.Projects[$this.SelectedProject]
            $lines += [BorderHelper]::ContentLine("Editing: $($project.FullProjectName)")
            $lines += [BorderHelper]::EmptyLine()
        }
        
        # Render the edit form with null check
        if ($null -ne $this.EditForm) {
            try {
                $width = [Math]::Max(40, [Console]::WindowWidth - 6)
                $formLines = $this.EditForm.Render($width)
                foreach ($line in $formLines) {
                    $lines += [BorderHelper]::ContentLine($line)
                }
            } catch {
                $lines += [BorderHelper]::ContentLine("Error rendering form: $($_.Exception.Message)")
            }
        } else {
            $lines += [BorderHelper]::ContentLine("Edit form not initialized")
        }
        
        $lines += [BorderHelper]::EmptyLine()
        $lines += [BorderHelper]::ContentLine("Tab/Shift+Tab: Navigate fields | Enter: Save | Esc: Cancel")
        $lines += [BorderHelper]::EmptyLine()
        $lines += "└" + ("─" * ([Console]::WindowWidth - 2)) + "┘"
        
        return $lines
    }
    
    [string[]] RenderDeleteConfirmation() {
        $lines = @()
        $lines += "┌─ Delete Project " + ("─" * ([Console]::WindowWidth - 19)) + "┐"
        $lines += [BorderHelper]::EmptyLine()
        
        # Show which project will be deleted
        if ($this.SelectedProject -lt $this.Projects.Count) {
            $project = $this.Projects[$this.SelectedProject]
            $lines += [BorderHelper]::ContentLine("[WARN]️  WARNING: You are about to delete this project:")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("   Project: $($project.FullProjectName)")
            $lines += [BorderHelper]::ContentLine("   ID1: $($project.ID1)     ID2: $($project.ID2)")
            if ($project.DateDue -and $project.DateDue -ne [DateTime]::MinValue) {
                $lines += [BorderHelper]::ContentLine("   Due Date: $($project.DateDue.ToString('MM/dd/yyyy'))")
            }
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("❗ This action cannot be undone!")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("Are you sure you want to delete this project?")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("Press Y to confirm deletion, or any other key to cancel")
        } else {
            $lines += [BorderHelper]::ContentLine("No project selected for deletion")
        }
        
        $lines += [BorderHelper]::EmptyLine()
        $lines += "└" + ("─" * ([Console]::WindowWidth - 2)) + "┘"
        
        return $lines
    }
    
    [string[]] RenderControls() {
        $lines = @()
        $lines += "┌─ Controls " + ("─" * ([Console]::WindowWidth - 13)) + "┐"
        
        switch ($this.ViewMode) {
            "List" {
                $lines += [BorderHelper]::ContentLine("A - Add │ E - Edit │ D - Delete │ V - View Details │ ↑↓ Select Project │ B - Back │ Q - Quit")
            }
            "Add" {
                $lines += [BorderHelper]::ContentLine("S - Save Project │ C - Cancel │ Tab - Next Field │ Shift+Tab - Previous Field")
            }
            "Edit" {
                $lines += [BorderHelper]::ContentLine("S - Save Changes │ C - Cancel │ Tab - Next Field │ Shift+Tab - Previous Field")
            }
            "Delete" {
                $lines += [BorderHelper]::ContentLine("Y - Confirm Delete │ Any other key - Cancel and return to list")
            }
        }
        
        $lines += "└" + ("─" * ([Console]::WindowWidth - 2)) + "┘"
        
        return $lines
    }
    
    [string] HandleInput([string]$key) {
        $timing = Start-PerformanceTiming "ProjectsScreen.HandleInput" @{ key = $key }
        
        try {
            switch ($this.ViewMode) {
                "List" {
                    return $this.HandleListInput($key)
                }
                "Add" {
                    return $this.HandleAddInput($key)
                }
                "Edit" {
                    return $this.HandleEditInput($key)
                }
                "Delete" {
                    return $this.HandleDeleteInput($key)
                }
            }
        } finally {
            Stop-PerformanceTiming $timing
        }
        return "CONTINUE"
    }
    
    [string] HandleKey([System.ConsoleKeyInfo]$keyInfo) {
        # Direct key handling for forms
        switch ($this.ViewMode) {
            "Add" {
                return $this.HandleAddInputKey($keyInfo)
            }
            "Edit" {
                return $this.HandleEditInputKey($keyInfo)
            }
            default {
                # For list mode, use string-based handling
                $keyString = $keyInfo.Key.ToString()
                if ($keyInfo.Modifiers -band [ConsoleModifiers]::Control) {
                    $keyString = "Ctrl+$keyString"
                }
                return $this.HandleInput($keyString)
            }
        }
        return "CONTINUE"
    }
    
    [string] HandleListInput([string]$key) {
        switch ($key.ToUpper()) {
            'A' {
                $this.ViewMode = "Add"
                $this.InitializeNewProject()
                return "REFRESH"
            }
            'E' {
                if ($this.Projects.Count -gt 0) {
                    $this.ViewMode = "Edit"
                    $this.InitializeEditProject()
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'D' {
                if ($this.Projects.Count -gt 0) {
                    $this.ViewMode = "Delete"
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'V' {
                if ($this.Projects.Count -gt 0) {
                    $this.ViewProjectDetails()
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'R' {
                $this.RefreshData()
                return "REFRESH"
            }
            'B' {
                return "DASHBOARD"
            }
            'Q' {
                return "EXIT"
            }
            'UpArrow' {
                if ($this.SelectedProject -gt 0) {
                    $this.SelectedProject--
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'DownArrow' {
                if ($this.SelectedProject -lt ($this.Projects.Count - 1)) {
                    $this.SelectedProject++
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            default {
                return "CONTINUE"
            }
        }
        return "CONTINUE"
    }
    
    [string] HandleAddInput([string]$key) {
        # Handle special navigation keys first
        switch ($key) {
            'Escape' {
                $this.AddForm.Clear()
                $this.AddForm.Deactivate()
                $this.ViewMode = "List"
                return "REFRESH"
            }
        }
        
        # For now, return refresh to show typed characters
        return "REFRESH"
    }
    
    [string] HandleAddInputKey([System.ConsoleKeyInfo]$keyInfo) {
        # This is the proper handler for form input
        $result = $this.AddForm.HandleInput($keyInfo)
        
        switch ($result) {
            "SUBMIT" {
                $this.SaveNewProject()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            "CANCEL" {
                $this.AddForm.Clear()
                $this.AddForm.Deactivate()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            "REFRESH" {
                return "REFRESH"
            }
            default {
                return "CONTINUE"
            }
        }
        return "CONTINUE"
    }
    
    [string] HandleEditInput([string]$key) {
        switch ($key.ToUpper()) {
            'S' {
                $this.ViewMode = "List"
                return "REFRESH"
            }
            'C' {
                $this.ViewMode = "List"
                return "REFRESH"
            }
            default {
                return "CONTINUE"
            }
        }
        return "CONTINUE"
    }
    
    [string] HandleDeleteInput([string]$key) {
        $logger = Get-Logger
        $logger.Debug("SpeedTUI", "ProjectsScreen", "Delete confirmation input", @{
            Key = $key
            SelectedProject = $this.SelectedProject
        })
        
        switch ($key.ToUpper()) {
            'Y' {
                # Confirm deletion
                $this.ConfirmDeleteSelectedProject()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            default {
                # Cancel deletion
                $logger.Debug("SpeedTUI", "ProjectsScreen", "Delete cancelled by user")
                $this.ViewMode = "List"
                return "REFRESH"
            }
        }
        return "CONTINUE"
    }
    
    [string] HandleEditInputKey([System.ConsoleKeyInfo]$keyInfo) {
        # This is the proper handler for edit form input
        $result = $this.EditForm.HandleInput($keyInfo)
        
        switch ($result) {
            "SUBMIT" {
                $this.SaveEditedProject()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            "CANCEL" {
                $this.EditForm.Clear()
                $this.EditForm.Deactivate()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            "REFRESH" {
                return "REFRESH"
            }
            default {
                return "CONTINUE"
            }
        }
        return "CONTINUE"
    }
    
    [void] InitializeNewProject() {
        $this.NewProject = @{
            FullProjectName = ""
            Description = ""
            DateDue = [DateTime]::MinValue
            ID1 = ""
            ID2 = ""
        }
        
        # Clear and activate the form
        $this.AddForm.Clear()
        $this.AddForm.Activate()
    }
    
    [void] InitializeEditProject() {
        if ($this.SelectedProject -ge $this.Projects.Count) {
            return
        }
        
        $project = $this.Projects[$this.SelectedProject]
        
        # Clear and activate the edit form
        $this.EditForm.Clear()
        $this.EditForm.Activate()
        
        # Populate form with existing data
        $this.EditForm.SetFieldValue("Project Name", $project.FullProjectName)
        $this.EditForm.SetFieldValue("Description", $project.Note)
        $this.EditForm.SetFieldValue("ID1", $project.ID1)
        $this.EditForm.SetFieldValue("ID2", $project.ID2)
        
        # Format the due date
        if ($project.DateDue -and $project.DateDue -ne [DateTime]::MinValue) {
            $this.EditForm.SetFieldValue("Due Date", $project.DateDue.ToString("MM/dd/yyyy"))
        }
        
        $logger = Get-Logger
        $logger.Debug("SpeedTUI", "ProjectsScreen", "Edit project initialized", @{
            ProjectId = $project.Id
            ProjectName = $project.FullProjectName
            SelectedIndex = $this.SelectedProject
        })
    }
    
    [void] SaveNewProject() {
        try {
            # Get form data
            $formData = $this.AddForm.GetFormData()
            
            if ($null -eq $formData -or $formData.Count -eq 0) {
                throw "No form data available"
            }
            
            # Create new project
            $project = [Project]::new()
            $project.FullProjectName = $formData["Project Name"]
            $project.Note = $formData["Description"]
            $project.ID1 = $formData["ID1"]
            $project.ID2 = $formData["ID2"]
            
            # Parse due date
            $dueDateText = $formData["Due Date"]
            if (-not [string]::IsNullOrWhiteSpace($dueDateText)) {
                $dueDate = [DateTime]::MinValue
                if ([DateTime]::TryParse($dueDateText, [ref]$dueDate)) {
                    $project.DateDue = $dueDate
                }
            }
            
            $project.DateAssigned = [DateTime]::Now
            $project.Deleted = $false
            
            # Save the project
            $this.ProjectService.CreateProject($project.ToHashtable())
            $this.RefreshData()
            
            # Clear form
            $this.AddForm.Clear()
            $this.AddForm.Deactivate()
            
            Write-Host "Project saved successfully!" -ForegroundColor Green
            $this.PerformanceMonitor.IncrementCounter("screen.projects.project_added", @{})
        } catch {
            Write-Host "Error saving project: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] SaveEditedProject() {
        try {
            if ($this.SelectedProject -ge $this.Projects.Count) {
                throw "No project selected for editing"
            }
            
            # Get form data
            $formData = $this.EditForm.GetFormData()
            
            if ($null -eq $formData -or $formData.Count -eq 0) {
                throw "No form data available"
            }
            
            # Get the existing project
            $project = $this.Projects[$this.SelectedProject]
            
            # Update the project with new values
            $project.FullProjectName = $formData["Project Name"]
            $project.Note = $formData["Description"]
            $project.ID1 = $formData["ID1"]
            $project.ID2 = $formData["ID2"]
            
            # Parse due date
            $dueDateText = $formData["Due Date"]
            if (-not [string]::IsNullOrWhiteSpace($dueDateText)) {
                $dueDate = [DateTime]::MinValue
                if ([DateTime]::TryParse($dueDateText, [ref]$dueDate)) {
                    $project.DateDue = $dueDate
                } else {
                    $project.DateDue = [DateTime]::MinValue
                }
            } else {
                $project.DateDue = [DateTime]::MinValue
            }
            
            # Update the project in the service
            $this.ProjectService.UpdateProject($project.Id, $project.ToHashtable())
            $this.RefreshData()
            
            # Clear form
            $this.EditForm.Clear()
            $this.EditForm.Deactivate()
            
            $logger = Get-Logger
            $logger.Debug("SpeedTUI", "ProjectsScreen", "Project updated successfully", @{
                ProjectId = $project.Id
                ProjectName = $project.FullProjectName
            })
            
            $this.PerformanceMonitor.IncrementCounter("screen.projects.project_updated", @{})
        } catch {
            $logger = Get-Logger
            $logger.Error("SpeedTUI", "ProjectsScreen", "Error updating project", @{
                Exception = $_.Exception.Message
                SelectedProject = $this.SelectedProject
            })
            # Don't clear form on error so user can fix validation issues
        }
    }
    
    [void] ViewProjectDetails() {
        if ($this.SelectedProject -ge $this.Projects.Count) {
            return
        }
        
        $project = $this.Projects[$this.SelectedProject]
        
        # For now, just show a simple message - in a full implementation this would navigate to a detail screen
        Write-Host "Project Details: $($project.FullProjectName)" -ForegroundColor Cyan
        Write-Host "Description: $($project.Note)" -ForegroundColor Gray
        if ($project.DateDue -and $project.DateDue -ne [DateTime]::MinValue) {
            Write-Host "Due Date: $($project.DateDue.ToString('MM/dd/yyyy'))" -ForegroundColor Gray
        }
    }
    
    [void] RefreshData() {
        try {
            $this.Projects = $this.ProjectService.GetAllProjects()
            $this.LastRefresh = [DateTime]::Now
            $this.PerformanceMonitor.IncrementCounter("screen.projects.refresh", @{})
        } catch {
            Write-Host "Error refreshing projects: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] ConfirmDeleteSelectedProject() {
        if ($this.Projects.Count -eq 0 -or $this.SelectedProject -ge $this.Projects.Count) {
            return
        }
        
        try {
            $project = $this.Projects[$this.SelectedProject]
            $logger = Get-Logger
            
            $logger.Debug("SpeedTUI", "ProjectsScreen", "Deleting project", @{
                ProjectId = $project.Id
                ProjectName = $project.FullProjectName
                SelectedIndex = $this.SelectedProject
            })
            
            $this.ProjectService.DeleteProject($project.Id)
            $this.RefreshData()
            
            # Adjust selection if needed
            if ($this.SelectedProject -ge $this.Projects.Count -and $this.Projects.Count -gt 0) {
                $this.SelectedProject = $this.Projects.Count - 1
            }
            
            $logger.Debug("SpeedTUI", "ProjectsScreen", "Project deleted successfully", @{
                ProjectId = $project.Id
                RemainingProjects = $this.Projects.Count
            })
            $this.PerformanceMonitor.IncrementCounter("screen.projects.project_deleted", @{})
        } catch {
            $logger = Get-Logger
            $logger.Error("SpeedTUI", "ProjectsScreen", "Error deleting project", @{
                Exception = $_.Exception.Message
                SelectedProject = $this.SelectedProject
            })
        }
    }
}