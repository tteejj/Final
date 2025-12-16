# SpeedTUI Task Service - Complete task management with project integration

using module './DataService.ps1' 
using module '../Models/Task.ps1'

class TaskService : DataService {
    static [TaskService]$Instance = $null
    [hashtable]$TasksByProject = @{}
    [hashtable]$TasksByStatus = @{}
    [bool]$IndexesBuilt = $false
    
    TaskService([string]$dataDir) : base($dataDir) {
        $this.LoadTasks()
    }
    
    static [TaskService] GetInstance([string]$dataDir = "_ProjectData") {
        if ($null -eq [TaskService]::Instance) {
            [TaskService]::Instance = [TaskService]::new($dataDir)
        }
        return [TaskService]::Instance
    }
    
    [void] LoadTasks() {
        $this.ClearCache("tasks")
        $taskData = $this.LoadData("tasks")
        $this.BuildIndexes($taskData)
    }
    
    [void] SaveTasks() {
        $tasks = $this.GetAllTasks($false)  # Get raw hashtable data
        $this.SaveData("tasks", $tasks)
    }
    
    [void] BuildIndexes([hashtable[]]$taskData) {
        $this.TasksByProject.Clear()
        $this.TasksByStatus.Clear()
        
        foreach ($task in $taskData) {
            if (-not $task.Deleted) {
                # Index by project
                if (-not [string]::IsNullOrEmpty($task.ProjectId)) {
                    if (-not $this.TasksByProject.ContainsKey($task.ProjectId)) {
                        $this.TasksByProject[$task.ProjectId] = @()
                    }
                    $this.TasksByProject[$task.ProjectId] += $task
                }
                
                # Index by status
                $status = [TaskStatus]$task.Status
                $statusKey = $status.ToString()
                if (-not $this.TasksByStatus.ContainsKey($statusKey)) {
                    $this.TasksByStatus[$statusKey] = @()
                }
                $this.TasksByStatus[$statusKey] += $task
            }
        }
        
        $this.IndexesBuilt = $true
    }
    
    [Task[]] GetAllTasks([bool]$asObjects = $true) {
        $taskData = $this.LoadData("tasks")
        
        if (-not $this.IndexesBuilt) {
            $this.BuildIndexes($taskData)
        }
        
        if ($asObjects) {
            $tasks = @()
            foreach ($data in $taskData) {
                if (-not $data.Deleted) {
                    $tasks += [Task]::new($data)
                }
            }
            return $tasks
        } else {
            return $this.GetActiveItems($taskData)
        }
    }
    
    [Task] GetTask([string]$id) {
        $taskData = $this.LoadData("tasks")
        $data = $this.FindById($taskData, $id)
        
        if ($null -eq $data -or $data.Deleted) {
            return $null
        }
        
        return [Task]::new($data)
    }
    
    [Task] CreateTask([hashtable]$taskData) {
        # Validate required fields
        if ([string]::IsNullOrEmpty($taskData.Title)) {
            throw "Task must have a title"
        }
        
        # Create task object and validate
        $task = [Task]::new($taskData)
        if (-not $task.IsValid()) {
            throw "Invalid task data"
        }
        
        # Add to data store
        $allTaskData = $this.LoadData("tasks")
        $allTaskData = $this.AddItem($allTaskData, $task.ToHashtable())
        $this.SaveData("tasks", $allTaskData)
        
        # Rebuild indexes
        $this.BuildIndexes($allTaskData)
        
        return $task
    }
    
    [Task] AddTask([string]$title, [string]$description = "", [string]$projectId = "") {
        $taskData = @{
            Title = $title
            Description = $description
            ProjectId = $projectId
            Status = [int][TaskStatus]::Pending
            Priority = [int][TaskPriority]::Medium
            Progress = 0
        }
        
        return $this.CreateTask($taskData)
    }
    
    [Task] UpdateTask([string]$id, [hashtable]$updates) {
        $taskData = $this.LoadData("tasks")
        $existing = $this.FindById($taskData, $id)
        
        if ($null -eq $existing -or $existing.Deleted) {
            throw "Task with ID '$id' not found"
        }
        
        # Update the data
        $taskData = $this.UpdateItem($taskData, $id, $updates)
        $this.SaveData("tasks", $taskData)
        
        # Rebuild indexes
        $this.BuildIndexes($taskData)
        
        # Return updated task
        return $this.GetTask($id)
    }
    
    [void] DeleteTask([string]$id, [bool]$softDelete = $true) {
        $taskData = $this.LoadData("tasks")
        
        if (-not $this.ExistsById($taskData, $id)) {
            throw "Task with ID '$id' not found"
        }
        
        $taskData = $this.DeleteItem($taskData, $id, $softDelete)
        $this.SaveData("tasks", $taskData)
        
        # Rebuild indexes
        $this.BuildIndexes($taskData)
    }
    
    [Task[]] GetTasksByProject([string]$projectId) {
        if (-not $this.IndexesBuilt) {
            $this.LoadTasks()
        }
        
        if ($this.TasksByProject.ContainsKey($projectId)) {
            $tasks = @()
            foreach ($data in $this.TasksByProject[$projectId]) {
                $tasks += [Task]::new($data)
            }
            return $tasks
        }
        
        return @()
    }
    
    [Task[]] GetTasksByStatus([TaskStatus]$status) {
        if (-not $this.IndexesBuilt) {
            $this.LoadTasks()
        }
        
        $statusKey = $status.ToString()
        if ($this.TasksByStatus.ContainsKey($statusKey)) {
            $tasks = @()
            foreach ($data in $this.TasksByStatus[$statusKey]) {
                $tasks += [Task]::new($data)
            }
            return $tasks
        }
        
        return @()
    }
    
    [Task[]] GetOverdueTasks() {
        $tasks = $this.GetAllTasks()
        return $tasks | Where-Object { $_.IsOverdue() }
    }
    
    [Task[]] GetTasksByPriority([TaskPriority]$priority) {
        $tasks = $this.GetAllTasks()
        return $tasks | Where-Object { $_.Priority -eq $priority }
    }
    
    [Task[]] GetTasksByTag([string]$tag) {
        $tasks = $this.GetAllTasks()
        return $tasks | Where-Object { $_.HasTag($tag) }
    }
    
    [Task[]] GetTasksByAssignee([string]$assignedTo) {
        $tasks = $this.GetAllTasks()
        return $tasks | Where-Object { $_.AssignedTo -like "*$assignedTo*" }
    }
    
    [Task[]] GetTasksByCategory([string]$category) {
        $tasks = $this.GetAllTasks()
        return $tasks | Where-Object { $_.Category -eq $category }
    }
    
    [Task[]] SearchTasks([string]$searchTerm) {
        $taskData = $this.LoadData("tasks")
        $searchFields = @('Title', 'Description', 'AssignedTo', 'Category', 'Tags')
        
        $results = $this.SearchItems($taskData, $searchTerm, $searchFields)
        $results = $this.GetActiveItems($results)
        
        $tasks = @()
        foreach ($data in $results) {
            $tasks += [Task]::new($data)
        }
        
        return $tasks
    }
    
    [Task[]] GetTasksDueWithin([int]$days) {
        $tasks = $this.GetAllTasks()
        $cutoffDate = [DateTime]::Now.AddDays($days)
        
        return $tasks | Where-Object { 
            $_.DueDate -le $cutoffDate -and 
            $_.Status -ne [TaskStatus]::Completed -and 
            $_.Status -ne [TaskStatus]::Cancelled 
        }
    }
    
    [Task[]] GetRecentTasks([int]$count = 10) {
        $tasks = $this.GetAllTasks()
        return $tasks | Sort-Object UpdatedAt -Descending | Select-Object -First $count
    }
    
    [Task[]] GetActiveTasks() {
        return $this.GetTasksByStatus([TaskStatus]::InProgress)
    }
    
    [Task[]] GetPendingTasks() {
        return $this.GetTasksByStatus([TaskStatus]::Pending)
    }
    
    [Task[]] GetCompletedTasks() {
        return $this.GetTasksByStatus([TaskStatus]::Completed)
    }
    
    [void] CompleteTask([string]$id) {
        $updates = @{
            Status = [int][TaskStatus]::Completed
            Progress = 100
            CompletedDate = [DateTime]::Now
        }
        $this.UpdateTask($id, $updates) | Out-Null
    }
    
    [void] StartTask([string]$id) {
        $updates = @{
            Status = [int][TaskStatus]::InProgress
            StartDate = [DateTime]::Now
        }
        $this.UpdateTask($id, $updates) | Out-Null
    }
    
    [void] CancelTask([string]$id) {
        $updates = @{
            Status = [int][TaskStatus]::Cancelled
        }
        $this.UpdateTask($id, $updates) | Out-Null
    }
    
    [void] UpdateTaskProgress([string]$id, [int]$progress) {
        if ($progress -lt 0) { $progress = 0 }
        if ($progress -gt 100) { $progress = 100 }
        
        $updates = @{ Progress = $progress }
        
        # Auto-update status based on progress
        if ($progress -eq 100) {
            $updates.Status = [int][TaskStatus]::Completed
            $updates.CompletedDate = [DateTime]::Now
        } elseif ($progress -gt 0) {
            $task = $this.GetTask($id)
            if ($null -ne $task -and $task.Status -eq [TaskStatus]::Pending) {
                $updates.Status = [int][TaskStatus]::InProgress
                $updates.StartDate = [DateTime]::Now
            }
        }
        
        $this.UpdateTask($id, $updates) | Out-Null
    }
    
    [void] AddTaskTag([string]$id, [string]$tag) {
        $task = $this.GetTask($id)
        if ($null -eq $task) {
            throw "Task with ID '$id' not found"
        }
        
        if (-not $task.HasTag($tag)) {
            $newTags = @($task.Tags) + @($tag)
            $updates = @{ Tags = $newTags }
            $this.UpdateTask($id, $updates) | Out-Null
        }
    }
    
    [void] RemoveTaskTag([string]$id, [string]$tag) {
        $task = $this.GetTask($id)
        if ($null -eq $task) {
            throw "Task with ID '$id' not found"
        }
        
        if ($task.HasTag($tag)) {
            $newTags = $task.Tags | Where-Object { $_ -ne $tag }
            $updates = @{ Tags = $newTags }
            $this.UpdateTask($id, $updates) | Out-Null
        }
    }
    
    [void] AssignTask([string]$id, [string]$assignedTo) {
        $updates = @{ AssignedTo = $assignedTo }
        $this.UpdateTask($id, $updates) | Out-Null
    }
    
    [void] SetTaskPriority([string]$id, [TaskPriority]$priority) {
        $updates = @{ Priority = [int]$priority }
        $this.UpdateTask($id, $updates) | Out-Null
    }
    
    [void] SetTaskDueDate([string]$id, [DateTime]$dueDate) {
        $updates = @{ DueDate = $dueDate }
        $this.UpdateTask($id, $updates) | Out-Null
    }
    
    [hashtable] GetTaskStatistics() {
        $tasks = $this.GetAllTasks()
        $baseStats = $this.GetStatistics($this.LoadData("tasks"))
        
        $statusCounts = @{}
        $priorityCounts = @{}
        $categoryCounts = @{}
        $assigneeCounts = @{}
        $overdueCount = 0
        $totalProgress = 0
        $completedCount = 0
        
        foreach ($task in $tasks) {
            # Status counts
            $statusKey = $task.GetStatusDisplay()
            if ($statusCounts.ContainsKey($statusKey)) {
                $statusCounts[$statusKey]++
            } else {
                $statusCounts[$statusKey] = 1
            }
            
            # Priority counts
            $priorityKey = $task.GetPriorityDisplay()
            if ($priorityCounts.ContainsKey($priorityKey)) {
                $priorityCounts[$priorityKey]++
            } else {
                $priorityCounts[$priorityKey] = 1
            }
            
            # Category counts
            if (-not [string]::IsNullOrEmpty($task.Category)) {
                if ($categoryCounts.ContainsKey($task.Category)) {
                    $categoryCounts[$task.Category]++
                } else {
                    $categoryCounts[$task.Category] = 1
                }
            }
            
            # Assignee counts
            if (-not [string]::IsNullOrEmpty($task.AssignedTo)) {
                if ($assigneeCounts.ContainsKey($task.AssignedTo)) {
                    $assigneeCounts[$task.AssignedTo]++
                } else {
                    $assigneeCounts[$task.AssignedTo] = 1
                }
            }
            
            # Overdue count
            if ($task.IsOverdue()) {
                $overdueCount++
            }
            
            # Progress tracking
            $totalProgress += $task.Progress
            if ($task.Status -eq [TaskStatus]::Completed) {
                $completedCount++
            }
        }
        
        $baseStats.StatusCounts = $statusCounts
        $baseStats.PriorityCounts = $priorityCounts
        $baseStats.CategoryCounts = $categoryCounts
        $baseStats.AssigneeCounts = $assigneeCounts
        $baseStats.OverdueCount = $overdueCount
        $baseStats.CompletedCount = $completedCount
        $baseStats.AverageProgress = $(if ($tasks.Count -gt 0) { $totalProgress / $tasks.Count } else { 0 })
        $baseStats.CompletionRate = $(if ($tasks.Count -gt 0) { ($completedCount / $tasks.Count) * 100 } else { 0 })
        
        return $baseStats
    }
    
    [string[]] GetUniqueCategories() {
        $tasks = $this.GetAllTasks()
        return ($tasks | Where-Object { -not [string]::IsNullOrEmpty($_.Category) } | 
                Select-Object -ExpandProperty Category | Sort-Object -Unique)
    }
    
    [string[]] GetUniqueAssignees() {
        $tasks = $this.GetAllTasks()
        return ($tasks | Where-Object { -not [string]::IsNullOrEmpty($_.AssignedTo) } | 
                Select-Object -ExpandProperty AssignedTo | Sort-Object -Unique)
    }
    
    [string[]] GetAllTags() {
        $tasks = $this.GetAllTasks()
        $allTags = @()
        
        foreach ($task in $tasks) {
            foreach ($tag in $task.Tags) {
                if ($tag -notin $allTags) {
                    $allTags += $tag
                }
            }
        }
        
        return ($allTags | Sort-Object)
    }
    
    [void] BulkUpdateTasks([string[]]$taskIds, [hashtable]$updates) {
        foreach ($id in $taskIds) {
            try {
                $this.UpdateTask($id, $updates) | Out-Null
            } catch {
                Write-Warning "Failed to update task $id : $_"
            }
        }
    }
    
    [void] BulkDeleteTasks([string[]]$taskIds, [bool]$softDelete = $true) {
        foreach ($id in $taskIds) {
            try {
                $this.DeleteTask($id, $softDelete)
            } catch {
                Write-Warning "Failed to delete task $id : $_"
            }
        }
    }
    
    [Task[]] GetTasksForProjectReport([string]$projectId) {
        $tasks = $this.GetTasksByProject($projectId)
        return $tasks | Sort-Object Priority -Descending, DueDate
    }
}