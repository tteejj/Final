# SpeedTUI Tasks Screen - Task management with TimeScreen interaction style

# Load dependencies
. "$PSScriptRoot/../Core/Component.ps1"
. "$PSScriptRoot/../Core/PerformanceMonitor.ps1"
. "$PSScriptRoot/../Services/TaskService.ps1"
. "$PSScriptRoot/../Services/ProjectService.ps1"
. "$PSScriptRoot/../BorderHelper.ps1"
. "$PSScriptRoot/../Components/FormManager.ps1"

class TasksScreen : Component {
    [object]$TaskService
    [object]$ProjectService
    [object]$PerformanceMonitor
    [array]$Tasks = @()
    [int]$SelectedTask = 0
    [string]$ViewMode = "List"  # List, Add, Edit, Delete
    [hashtable]$NewTask = @{}
    [DateTime]$LastRefresh
    [FormManager]$AddForm
    [FormManager]$EditForm
    [hashtable]$ProjectCache = @{}
    
    TasksScreen() : base() {
        try {
            $this.Initialize()
        } catch {
            $logger = Get-Logger
            $logger.Fatal("SpeedTUI", "TasksScreen", "Constructor failed", @{
                Exception = $_.Exception.ToString()
                Message = $_.Exception.Message
            })
            throw
        }
    }
    
    [void] Initialize() {
        try {
            $this.TaskService = [TaskService]::GetInstance()
            $this.ProjectService = [ProjectService]::GetInstance()
            $this.PerformanceMonitor = Get-PerformanceMonitor
            
            # Initialize empty array to prevent null reference
            if ($null -eq $this.Tasks) {
                $this.Tasks = @()
            }
            
            # Initialize forms
            $this.InitializeForms()
            
            $this.RefreshData()
            $this.LastRefresh = [DateTime]::Now
            
            $this.PerformanceMonitor.IncrementCounter("screen.tasks.initialized", @{})
        } catch {
            $logger = Get-Logger
            $logger.Error("SpeedTUI", "TasksScreen", "Initialization failed", @{
                Exception = $_.Exception.ToString()
                Message = $_.Exception.Message
            })
            # Ensure we have at least empty collections
            if ($null -eq $this.Tasks) {
                $this.Tasks = @()
            }
        }
    }
    
    [void] InitializeForms() {
        $logger = Get-Logger
        $logger.Debug("SpeedTUI", "TasksScreen", "Initializing forms")
        
        # Create Add form
        $this.AddForm = [FormManager]::new()
        $logger.Debug("SpeedTUI", "TasksScreen", "AddForm created")
        
        # Add required fields with validation
        $titleField = [InputField]::new("Task Title", "e.g., Implement user authentication")
        $titleField.Validator = [InputValidators]::Required()
        $this.AddForm.AddField($titleField)
        
        $this.AddForm.AddTextField("Description", "Task description...")
        
        $dueDateField = [InputField]::new("Due Date", "MM/dd/yyyy")
        $dueDateField.FieldType = "date"
        $this.AddForm.AddField($dueDateField)
        
        $statusField = [InputField]::new("Status", "Pending/InProgress/Completed/Cancelled")
        $this.AddForm.AddField($statusField)
        
        $priorityField = [InputField]::new("Priority", "Low/Medium/High")
        $this.AddForm.AddField($priorityField)
        
        $this.AddForm.AddTextField("Project ID", "Associated project ID")
        
        $this.AddForm.AddTextField("Tags", "Comma-separated tags")
        
        $logger.Debug("SpeedTUI", "TasksScreen", "AddForm fields added", @{
            FieldCount = $this.AddForm.Fields.Count
        })
        
        # Create Edit form (same fields as Add form)
        $this.EditForm = [FormManager]::new()
        
        # Add required fields with validation (same as Add form)
        $editTitleField = [InputField]::new("Task Title", "e.g., Implement user authentication")
        $editTitleField.Validator = [InputValidators]::Required()
        $this.EditForm.AddField($editTitleField)
        
        $this.EditForm.AddTextField("Description", "Task description...")
        
        $editDueDateField = [InputField]::new("Due Date", "MM/dd/yyyy")
        $editDueDateField.FieldType = "date"
        $this.EditForm.AddField($editDueDateField)
        
        $editStatusField = [InputField]::new("Status", "Pending/InProgress/Completed/Cancelled")
        $this.EditForm.AddField($editStatusField)
        
        $editPriorityField = [InputField]::new("Priority", "Low/Medium/High")
        $this.EditForm.AddField($editPriorityField)
        
        $this.EditForm.AddTextField("Project ID", "Associated project ID")
        
        $this.EditForm.AddTextField("Tags", "Comma-separated tags")
    }
    
    [string[]] Render() {
        $timing = Start-PerformanceTiming "TasksScreen.Render"
        $logger = Get-Logger
        
        $logger.Trace("SpeedTUI", "TasksScreen", "Render start", @{
            ViewMode = $this.ViewMode
            TasksCount = $(if ($this.Tasks) { $this.Tasks.Count } else { 0 })
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
                    $lines += $this.RenderTasksList()
                }
                "Add" {
                    $lines += $this.RenderAddTask()
                }
                "Edit" {
                    $lines += $this.RenderEditTask()
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
        
        # Get task statistics
        $totalTasks = $this.Tasks.Count
        $pendingTasks = ($this.Tasks | Where-Object { $_.Status -eq "Pending" }).Count
        $inProgressTasks = ($this.Tasks | Where-Object { $_.Status -eq "InProgress" }).Count
        $completedTasks = ($this.Tasks | Where-Object { $_.Status -eq "Completed" }).Count
        
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::ContentLine("TASK MANAGEMENT".PadLeft(([Console]::WindowWidth - 35) / 2 + 15))
        $lines += [BorderHelper]::ContentLine("Total: $($totalTasks.ToString().PadLeft(2)) │ Pending: $($pendingTasks.ToString().PadLeft(2)) │ In Progress: $($inProgressTasks.ToString().PadLeft(2)) │ Completed: $($completedTasks.ToString().PadLeft(2))")
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string[]] RenderTasksList() {
        $lines = @()
        
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::ContentLine("Tasks List                                            ↑↓ to navigate")
        $lines += [BorderHelper]::MiddleBorder()
        
        if ($this.Tasks.Count -eq 0) {
            $lines += [BorderHelper]::ContentLine("No tasks found. Press 'A' to add a task.")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::EmptyLine()
        } else {
            $lines += [BorderHelper]::ContentLine("S │ P │ Task Title                         │ Project          │ Due Date │ Tags")
            $lines += [BorderHelper]::MiddleBorder()
            
            # Show tasks
            $index = 0
            foreach ($task in $this.Tasks) {
                $marker = $(if ($index -eq $this.SelectedTask) { "►" } else { " " })
                
                # Format status
                $status = switch ($task.Status) {
                    "Pending" { "P" }
                    "InProgress" { "W" }
                    "Completed" { "D" }
                    "Cancelled" { "X" }
                    default { "?" }
                }
                
                # Format priority
                $priority = switch ($task.Priority) {
                    "High" { "H" }
                    "Medium" { "M" }
                    "Low" { "L" }
                    default { " " }
                }
                
                # Format title
                $titleStr = "$marker$($task.Title)".PadRight(35)
                if ($titleStr.Length -gt 35) { $titleStr = $titleStr.Substring(0, 32) + "..." }
                
                # Format project name (cached lookup)
                $projectStr = ""
                if ($task.ProjectId) {
                    if (-not $this.ProjectCache.ContainsKey($task.ProjectId)) {
                        try {
                            $project = $this.ProjectService.GetProject($task.ProjectId)
                            if ($project) {
                                $this.ProjectCache[$task.ProjectId] = $project.FullProjectName
                            } else {
                                $this.ProjectCache[$task.ProjectId] = ""
                            }
                        } catch {
                            $this.ProjectCache[$task.ProjectId] = ""
                        }
                    }
                    $projectStr = $this.ProjectCache[$task.ProjectId]
                }
                $projectStr = $projectStr.PadRight(16)
                if ($projectStr.Length -gt 16) { $projectStr = $projectStr.Substring(0, 16) }
                
                # Format due date
                $dueDateStr = $(if ($task.DueDate -and $task.DueDate -ne [DateTime]::MinValue) { 
                    $task.DueDate.ToString("MM/dd/yy").PadRight(8) 
                } else { 
                    "".PadRight(8) 
                })
                
                # Format tags
                $tagsStr = $(if ($task.Tags -and $task.Tags.Count -gt 0) {
                    ($task.Tags -join ",").PadRight(12)
                } else {
                    "".PadRight(12)
                })
                if ($tagsStr.Length -gt 12) { $tagsStr = $tagsStr.Substring(0, 12) }
                
                $lines += [BorderHelper]::ContentLine("$status │ $priority │ $titleStr │ $projectStr │ $dueDateStr │ $tagsStr")
                $index++
            }
            
            # Fill remaining lines to maintain consistent height
            while ($index -lt 10) {
                $lines += [BorderHelper]::EmptyLine()
                $index++
            }
        }
        
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string[]] RenderAddTask() {
        $lines = @()
        $lines += "┌─ Add New Task " + ("─" * ([Console]::WindowWidth - 17)) + "┐"
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
    
    [string[]] RenderEditTask() {
        $lines = @()
        $lines += "┌─ Edit Task " + ("─" * ([Console]::WindowWidth - 14)) + "┐"
        $lines += [BorderHelper]::EmptyLine()
        
        # Show which task is being edited
        if ($this.SelectedTask -lt $this.Tasks.Count) {
            $task = $this.Tasks[$this.SelectedTask]
            $lines += [BorderHelper]::ContentLine("Editing: $($task.Title)")
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
        $lines += "┌─ Delete Task " + ("─" * ([Console]::WindowWidth - 16)) + "┐"
        $lines += [BorderHelper]::EmptyLine()
        
        # Show which task will be deleted
        if ($this.SelectedTask -lt $this.Tasks.Count) {
            $task = $this.Tasks[$this.SelectedTask]
            $lines += [BorderHelper]::ContentLine("[WARN]️  WARNING: You are about to delete this task:")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("   Task: $($task.Title)")
            $lines += [BorderHelper]::ContentLine("   Status: $($task.Status)     Priority: $($task.Priority)")
            if ($task.DueDate -and $task.DueDate -ne [DateTime]::MinValue) {
                $lines += [BorderHelper]::ContentLine("   Due Date: $($task.DueDate.ToString('MM/dd/yyyy'))")
            }
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("❗ This action cannot be undone!")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("Are you sure you want to delete this task?")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("Press Y to confirm deletion, or any other key to cancel")
        } else {
            $lines += [BorderHelper]::ContentLine("No task selected for deletion")
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
                $lines += [BorderHelper]::ContentLine("A - Add │ E - Edit │ D - Delete │ S - Cycle Status │ P - Cycle Priority │ ↑↓ Select │ B - Back │ Q - Quit")
            }
            "Add" {
                $lines += [BorderHelper]::ContentLine("S - Save Task │ C - Cancel │ Tab - Next Field │ Shift+Tab - Previous Field")
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
        $timing = Start-PerformanceTiming "TasksScreen.HandleInput" @{ key = $key }
        
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
                $this.InitializeNewTask()
                return "REFRESH"
            }
            'E' {
                if ($this.Tasks.Count -gt 0) {
                    $this.ViewMode = "Edit"
                    $this.InitializeEditTask()
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'D' {
                if ($this.Tasks.Count -gt 0) {
                    $this.ViewMode = "Delete"
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'S' {
                if ($this.Tasks.Count -gt 0) {
                    $this.CycleStatus()
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'P' {
                if ($this.Tasks.Count -gt 0) {
                    $this.CyclePriority()
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
                if ($this.SelectedTask -gt 0) {
                    $this.SelectedTask--
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'DownArrow' {
                if ($this.SelectedTask -lt ($this.Tasks.Count - 1)) {
                    $this.SelectedTask++
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
                $this.SaveNewTask()
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
        $logger.Debug("SpeedTUI", "TasksScreen", "Delete confirmation input", @{
            Key = $key
            SelectedTask = $this.SelectedTask
        })
        
        switch ($key.ToUpper()) {
            'Y' {
                # Confirm deletion
                $this.ConfirmDeleteSelectedTask()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            default {
                # Cancel deletion
                $logger.Debug("SpeedTUI", "TasksScreen", "Delete cancelled by user")
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
                $this.SaveEditedTask()
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
    
    [void] InitializeNewTask() {
        $this.NewTask = @{
            Title = ""
            Description = ""
            DueDate = [DateTime]::MinValue
            Status = "Pending"
            Priority = "Medium"
            ProjectId = ""
            Tags = @()
        }
        
        # Clear and activate the form
        $this.AddForm.Clear()
        $this.AddForm.Activate()
        
        # Set default values
        $this.AddForm.SetFieldValue("Status", "Pending")
        $this.AddForm.SetFieldValue("Priority", "Medium")
    }
    
    [void] InitializeEditTask() {
        if ($this.SelectedTask -ge $this.Tasks.Count) {
            return
        }
        
        $task = $this.Tasks[$this.SelectedTask]
        
        # Clear and activate the edit form
        $this.EditForm.Clear()
        $this.EditForm.Activate()
        
        # Populate form with existing data
        $this.EditForm.SetFieldValue("Task Title", $task.Title)
        $this.EditForm.SetFieldValue("Description", $task.Description)
        $this.EditForm.SetFieldValue("Status", $task.Status)
        $this.EditForm.SetFieldValue("Priority", $task.Priority)
        $this.EditForm.SetFieldValue("Project ID", $task.ProjectId)
        
        # Format the due date
        if ($task.DueDate -and $task.DueDate -ne [DateTime]::MinValue) {
            $this.EditForm.SetFieldValue("Due Date", $task.DueDate.ToString("MM/dd/yyyy"))
        }
        
        # Format tags
        if ($task.Tags -and $task.Tags.Count -gt 0) {
            $this.EditForm.SetFieldValue("Tags", ($task.Tags -join ","))
        }
        
        $logger = Get-Logger
        $logger.Debug("SpeedTUI", "TasksScreen", "Edit task initialized", @{
            TaskId = $task.Id
            TaskTitle = $task.Title
            SelectedIndex = $this.SelectedTask
        })
    }
    
    [void] SaveNewTask() {
        try {
            # Get form data
            $formData = $this.AddForm.GetFormData()
            
            if ($null -eq $formData -or $formData.Count -eq 0) {
                throw "No form data available"
            }
            
            # Create new task
            $task = [Task]::new()
            $task.Title = $formData["Task Title"]
            $task.Description = $formData["Description"]
            $task.Status = $(if ($formData["Status"]) { $formData["Status"] } else { "Pending" })
            $task.Priority = $(if ($formData["Priority"]) { $formData["Priority"] } else { "Medium" })
            $task.ProjectId = $formData["Project ID"]
            
            # Parse due date
            $dueDateText = $formData["Due Date"]
            if (-not [string]::IsNullOrWhiteSpace($dueDateText)) {
                $dueDate = [DateTime]::MinValue
                if ([DateTime]::TryParse($dueDateText, [ref]$dueDate)) {
                    $task.DueDate = $dueDate
                }
            }
            
            # Parse tags
            $tagsText = $formData["Tags"]
            if (-not [string]::IsNullOrWhiteSpace($tagsText)) {
                $task.Tags = @($tagsText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            
            $task.CreatedAt = [DateTime]::Now
            $task.UpdatedAt = [DateTime]::Now
            $task.Deleted = $false
            
            # Save the task
            $this.TaskService.CreateTask($task.ToHashtable())
            $this.RefreshData()
            
            # Clear form
            $this.AddForm.Clear()
            $this.AddForm.Deactivate()
            
            Write-Host "Task saved successfully!" -ForegroundColor Green
            $this.PerformanceMonitor.IncrementCounter("screen.tasks.task_added", @{})
        } catch {
            Write-Host "Error saving task: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] SaveEditedTask() {
        try {
            if ($this.SelectedTask -ge $this.Tasks.Count) {
                throw "No task selected for editing"
            }
            
            # Get form data
            $formData = $this.EditForm.GetFormData()
            
            if ($null -eq $formData -or $formData.Count -eq 0) {
                throw "No form data available"
            }
            
            # Get the existing task
            $task = $this.Tasks[$this.SelectedTask]
            
            # Update the task with new values
            $task.Title = $formData["Task Title"]
            $task.Description = $formData["Description"]
            $task.Status = $(if ($formData["Status"]) { $formData["Status"] } else { "Pending" })
            $task.Priority = $(if ($formData["Priority"]) { $formData["Priority"] } else { "Medium" })
            $task.ProjectId = $formData["Project ID"]
            
            # Parse due date
            $dueDateText = $formData["Due Date"]
            if (-not [string]::IsNullOrWhiteSpace($dueDateText)) {
                $dueDate = [DateTime]::MinValue
                if ([DateTime]::TryParse($dueDateText, [ref]$dueDate)) {
                    $task.DueDate = $dueDate
                } else {
                    $task.DueDate = [DateTime]::MinValue
                }
            } else {
                $task.DueDate = [DateTime]::MinValue
            }
            
            # Parse tags
            $tagsText = $formData["Tags"]
            if (-not [string]::IsNullOrWhiteSpace($tagsText)) {
                $task.Tags = @($tagsText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            } else {
                $task.Tags = @()
            }
            
            $task.UpdatedAt = [DateTime]::Now
            
            # Update the task in the service
            $this.TaskService.UpdateTask($task.Id, $task.ToHashtable())
            $this.RefreshData()
            
            # Clear form
            $this.EditForm.Clear()
            $this.EditForm.Deactivate()
            
            $logger = Get-Logger
            $logger.Debug("SpeedTUI", "TasksScreen", "Task updated successfully", @{
                TaskId = $task.Id
                TaskTitle = $task.Title
            })
            
            $this.PerformanceMonitor.IncrementCounter("screen.tasks.task_updated", @{})
        } catch {
            $logger = Get-Logger
            $logger.Error("SpeedTUI", "TasksScreen", "Error updating task", @{
                Exception = $_.Exception.Message
                SelectedTask = $this.SelectedTask
            })
            # Don't clear form on error so user can fix validation issues
        }
    }
    
    [void] CycleStatus() {
        if ($this.SelectedTask -ge $this.Tasks.Count) {
            return
        }
        
        $task = $this.Tasks[$this.SelectedTask]
        
        # Cycle through status values
        $newStatus = switch ($task.Status) {
            "Pending" { "InProgress" }
            "InProgress" { "Completed" }
            "Completed" { "Cancelled" }
            "Cancelled" { "Pending" }
            default { "Pending" }
        }
        
        $task.Status = $newStatus
        $task.UpdatedAt = [DateTime]::Now
        
        $this.TaskService.UpdateTask($task.Id, $task.ToHashtable())
        $this.RefreshData()
        
        Write-Host "Task status changed to: $newStatus" -ForegroundColor Green
    }
    
    [void] CyclePriority() {
        if ($this.SelectedTask -ge $this.Tasks.Count) {
            return
        }
        
        $task = $this.Tasks[$this.SelectedTask]
        
        # Cycle through priority values
        $newPriority = switch ($task.Priority) {
            "Low" { "Medium" }
            "Medium" { "High" }
            "High" { "Low" }
            default { "Medium" }
        }
        
        $task.Priority = $newPriority
        $task.UpdatedAt = [DateTime]::Now
        
        $this.TaskService.UpdateTask($task.Id, $task.ToHashtable())
        $this.RefreshData()
        
        Write-Host "Task priority changed to: $newPriority" -ForegroundColor Green
    }
    
    [void] RefreshData() {
        try {
            $this.Tasks = $this.TaskService.GetAllTasks()
            $this.LastRefresh = [DateTime]::Now
            # Clear project cache to ensure fresh lookups
            $this.ProjectCache.Clear()
            $this.PerformanceMonitor.IncrementCounter("screen.tasks.refresh", @{})
        } catch {
            Write-Host "Error refreshing tasks: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] ConfirmDeleteSelectedTask() {
        if ($this.Tasks.Count -eq 0 -or $this.SelectedTask -ge $this.Tasks.Count) {
            return
        }
        
        try {
            $task = $this.Tasks[$this.SelectedTask]
            $logger = Get-Logger
            
            $logger.Debug("SpeedTUI", "TasksScreen", "Deleting task", @{
                TaskId = $task.Id
                TaskTitle = $task.Title
                SelectedIndex = $this.SelectedTask
            })
            
            $this.TaskService.DeleteTask($task.Id)
            $this.RefreshData()
            
            # Adjust selection if needed
            if ($this.SelectedTask -ge $this.Tasks.Count -and $this.Tasks.Count -gt 0) {
                $this.SelectedTask = $this.Tasks.Count - 1
            }
            
            $logger.Debug("SpeedTUI", "TasksScreen", "Task deleted successfully", @{
                TaskId = $task.Id
                RemainingTasks = $this.Tasks.Count
            })
            $this.PerformanceMonitor.IncrementCounter("screen.tasks.task_deleted", @{})
        } catch {
            $logger = Get-Logger
            $logger.Error("SpeedTUI", "TasksScreen", "Error deleting task", @{
                Exception = $_.Exception.Message
                SelectedTask = $this.SelectedTask
            })
        }
    }
}