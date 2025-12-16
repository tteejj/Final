# SpeedTUI Project Service - Complete project management with data persistence

using module './DataService.ps1'
using module '../Models/Project.ps1'

class ProjectService : DataService {
    static [ProjectService]$Instance = $null
    [hashtable]$ProjectsByID1 = @{}
    [hashtable]$ProjectsByName = @{}
    [bool]$IndexesBuilt = $false
    
    ProjectService([string]$dataDir) : base($dataDir) {
        $this.LoadProjects()
    }
    
    static [ProjectService] GetInstance([string]$dataDir = "_ProjectData") {
        if ($null -eq [ProjectService]::Instance) {
            [ProjectService]::Instance = [ProjectService]::new($dataDir)
        }
        return [ProjectService]::Instance
    }
    
    [void] LoadProjects() {
        $this.ClearCache("projects")
        $projectData = $this.LoadData("projects")
        $this.BuildIndexes($projectData)
    }
    
    [void] SaveProjects() {
        $projects = $this.GetAllProjects($false)  # Get raw hashtable data
        $this.SaveData("projects", $projects)
    }
    
    [void] BuildIndexes([hashtable[]]$projectData) {
        $this.ProjectsByID1.Clear()
        $this.ProjectsByName.Clear()
        
        foreach ($project in $projectData) {
            if (-not $project.Deleted) {
                # Index by ID1
                if (-not [string]::IsNullOrEmpty($project.ID1)) {
                    $this.ProjectsByID1[$project.ID1] = $project
                }
                
                # Index by name (case-insensitive)
                if (-not [string]::IsNullOrEmpty($project.FullProjectName)) {
                    $nameKey = $project.FullProjectName.ToLower()
                    $this.ProjectsByName[$nameKey] = $project
                }
            }
        }
        
        $this.IndexesBuilt = $true
    }
    
    [Project[]] GetAllProjects([bool]$asObjects = $true) {
        $projectData = $this.LoadData("projects")
        
        if (-not $this.IndexesBuilt) {
            $this.BuildIndexes($projectData)
        }
        
        if ($asObjects) {
            $projects = @()
            foreach ($data in $projectData) {
                if (-not $data.Deleted) {
                    $projects += [Project]::new($data)
                }
            }
            return $projects
        } else {
            return $this.GetActiveItems($projectData)
        }
    }
    
    [Project] GetProject([string]$id) {
        $projectData = $this.LoadData("projects")
        $data = $this.FindById($projectData, $id)
        
        if ($null -eq $data -or $data.Deleted) {
            return $null
        }
        
        return [Project]::new($data)
    }
    
    [Project] GetProjectByID1([string]$id1) {
        if (-not $this.IndexesBuilt) {
            $this.LoadProjects()
        }
        
        if ($this.ProjectsByID1.ContainsKey($id1)) {
            return [Project]::new($this.ProjectsByID1[$id1])
        }
        
        return $null
    }
    
    [Project] GetProjectByName([string]$name) {
        if (-not $this.IndexesBuilt) {
            $this.LoadProjects()
        }
        
        $nameKey = $name.ToLower()
        if ($this.ProjectsByName.ContainsKey($nameKey)) {
            return [Project]::new($this.ProjectsByName[$nameKey])
        }
        
        return $null
    }
    
    [Project] CreateProject([hashtable]$projectData) {
        # Validate required fields
        if ([string]::IsNullOrEmpty($projectData.FullProjectName) -and [string]::IsNullOrEmpty($projectData.ID1)) {
            throw "Project must have either a name or ID1"
        }
        
        # Check for duplicates
        if (-not [string]::IsNullOrEmpty($projectData.ID1)) {
            $existing = $this.GetProjectByID1($projectData.ID1)
            if ($null -ne $existing) {
                throw "Project with ID1 '$($projectData.ID1)' already exists"
            }
        }
        
        if (-not [string]::IsNullOrEmpty($projectData.FullProjectName)) {
            $existing = $this.GetProjectByName($projectData.FullProjectName)
            if ($null -ne $existing) {
                throw "Project with name '$($projectData.FullProjectName)' already exists"
            }
        }
        
        # Create project object and validate
        $project = [Project]::new($projectData)
        if (-not $project.IsValid()) {
            throw "Invalid project data"
        }
        
        # Add to data store
        $allProjectData = $this.LoadData("projects")
        $allProjectData = $this.AddItem($allProjectData, $project.ToHashtable())
        $this.SaveData("projects", $allProjectData)
        
        # Rebuild indexes
        $this.BuildIndexes($allProjectData)
        
        return $project
    }
    
    [Project] UpdateProject([string]$id, [hashtable]$updates) {
        $projectData = $this.LoadData("projects")
        $existing = $this.FindById($projectData, $id)
        
        if ($null -eq $existing -or $existing.Deleted) {
            throw "Project with ID '$id' not found"
        }
        
        # Check for duplicate ID1 or name if being updated
        if ($updates.ContainsKey('ID1') -and -not [string]::IsNullOrEmpty($updates.ID1)) {
            $existingByID1 = $this.GetProjectByID1($updates.ID1)
            if ($null -ne $existingByID1 -and $existingByID1.Id -ne $id) {
                throw "Project with ID1 '$($updates.ID1)' already exists"
            }
        }
        
        if ($updates.ContainsKey('FullProjectName') -and -not [string]::IsNullOrEmpty($updates.FullProjectName)) {
            $existingByName = $this.GetProjectByName($updates.FullProjectName)
            if ($null -ne $existingByName -and $existingByName.Id -ne $id) {
                throw "Project with name '$($updates.FullProjectName)' already exists"
            }
        }
        
        # Update the data
        $projectData = $this.UpdateItem($projectData, $id, $updates)
        $this.SaveData("projects", $projectData)
        
        # Rebuild indexes
        $this.BuildIndexes($projectData)
        
        # Return updated project
        return $this.GetProject($id)
    }
    
    [void] DeleteProject([string]$id, [bool]$softDelete = $true) {
        $projectData = $this.LoadData("projects")
        
        if (-not $this.ExistsById($projectData, $id)) {
            throw "Project with ID '$id' not found"
        }
        
        $projectData = $this.DeleteItem($projectData, $id, $softDelete)
        $this.SaveData("projects", $projectData)
        
        # Rebuild indexes
        $this.BuildIndexes($projectData)
    }
    
    [Project[]] SearchProjects([string]$searchTerm) {
        $projectData = $this.LoadData("projects")
        $searchFields = @('FullProjectName', 'ID1', 'ID2', 'AuditorName', 'ClientID', 'Status', 'Note', 'Comments')
        
        $results = $this.SearchItems($projectData, $searchTerm, $searchFields)
        $results = $this.GetActiveItems($results)
        
        $projects = @()
        foreach ($data in $results) {
            $projects += [Project]::new($data)
        }
        
        return $projects
    }
    
    [Project[]] GetProjectsByStatus([string]$status) {
        $projects = $this.GetAllProjects()
        return $projects | Where-Object { $_.Status -eq $status }
    }
    
    [Project[]] GetOverdueProjects() {
        $projects = $this.GetAllProjects()
        return $projects | Where-Object { $_.IsOverdue() }
    }
    
    [Project[]] GetProjectsByDateRange([DateTime]$startDate, [DateTime]$endDate) {
        $projects = $this.GetAllProjects()
        return $projects | Where-Object { 
            $_.DateAssigned -ge $startDate -and $_.DateAssigned -le $endDate 
        }
    }
    
    [Project[]] GetProjectsByAuditor([string]$auditorName) {
        $projects = $this.GetAllProjects()
        return $projects | Where-Object { 
            $_.AuditorName -like "*$auditorName*" -or $_.AuditorTL -like "*$auditorName*" 
        }
    }
    
    [hashtable] GetProjectStatistics() {
        $projects = $this.GetAllProjects()
        $baseStats = $this.GetStatistics($this.LoadData("projects"))
        
        $statusCounts = @{}
        $auditorCounts = @{}
        $overdueCount = 0
        $totalHours = 0
        
        foreach ($project in $projects) {
            # Status counts
            if ($statusCounts.ContainsKey($project.Status)) {
                $statusCounts[$project.Status]++
            } else {
                $statusCounts[$project.Status] = 1
            }
            
            # Auditor counts
            if (-not [string]::IsNullOrEmpty($project.AuditorName)) {
                if ($auditorCounts.ContainsKey($project.AuditorName)) {
                    $auditorCounts[$project.AuditorName]++
                } else {
                    $auditorCounts[$project.AuditorName] = 1
                }
            }
            
            # Overdue count
            if ($project.IsOverdue()) {
                $overdueCount++
            }
            
            # Total hours
            $totalHours += $project.CumulativeHrs
        }
        
        $baseStats.StatusCounts = $statusCounts
        $baseStats.AuditorCounts = $auditorCounts
        $baseStats.OverdueCount = $overdueCount
        $baseStats.TotalHours = $totalHours
        $baseStats.AverageHours = $(if ($projects.Count -gt 0) { $totalHours / $projects.Count } else { 0 })
        
        return $baseStats
    }
    
    [string[]] GetUniqueStatuses() {
        $projects = $this.GetAllProjects()
        return ($projects | Select-Object -ExpandProperty Status | Sort-Object -Unique)
    }
    
    [string[]] GetUniqueAuditors() {
        $projects = $this.GetAllProjects()
        $auditors = @()
        
        foreach ($project in $projects) {
            if (-not [string]::IsNullOrEmpty($project.AuditorName) -and $project.AuditorName -notin $auditors) {
                $auditors += $project.AuditorName
            }
            if (-not [string]::IsNullOrEmpty($project.AuditorTL) -and $project.AuditorTL -notin $auditors) {
                $auditors += $project.AuditorTL
            }
        }
        
        return ($auditors | Sort-Object)
    }
    
    [void] UpdateCumulativeHours([string]$projectId, [decimal]$hours) {
        $updates = @{ CumulativeHrs = $hours }
        $this.UpdateProject($projectId, $updates) | Out-Null
    }
    
    [void] CloseProject([string]$projectId) {
        $updates = @{ 
            Status = "Closed"
            ClosedDate = [DateTime]::Now
        }
        $this.UpdateProject($projectId, $updates) | Out-Null
    }
    
    [void] ReopenProject([string]$projectId) {
        $updates = @{ 
            Status = "Active"
            ClosedDate = [DateTime]::MinValue
        }
        $this.UpdateProject($projectId, $updates) | Out-Null
    }
    
    [Project[]] GetRecentProjects([int]$count = 10) {
        $projects = $this.GetAllProjects()
        return $projects | Sort-Object UpdatedAt -Descending | Select-Object -First $count
    }
    
    [Project[]] GetActiveProjects() {
        return $this.GetProjectsByStatus("Active")
    }
    
    [bool] ValidateProjectCode([string]$id1, [string]$id2 = "") {
        # Check if ID1 already exists
        if (-not [string]::IsNullOrEmpty($id1)) {
            $existing = $this.GetProjectByID1($id1)
            return $null -eq $existing
        }
        
        return $true
    }
    
    [void] ImportProjects([hashtable[]]$projectDataArray) {
        $imported = 0
        $skipped = 0
        $errors = @()
        
        foreach ($projectData in $projectDataArray) {
            try {
                # Check if project already exists
                $exists = $false
                if (-not [string]::IsNullOrEmpty($projectData.ID1)) {
                    $exists = $null -ne $this.GetProjectByID1($projectData.ID1)
                }
                
                if (-not $exists -and -not [string]::IsNullOrEmpty($projectData.FullProjectName)) {
                    $exists = $null -ne $this.GetProjectByName($projectData.FullProjectName)
                }
                
                if ($exists) {
                    $skipped++
                    continue
                }
                
                # Create the project
                $this.CreateProject($projectData) | Out-Null
                $imported++
                
            } catch {
                $errors += "Failed to import project '$($projectData.FullProjectName)': $_"
            }
        }
        
        Write-Host "Import completed: $imported imported, $skipped skipped, $($errors.Count) errors"
        if ($errors.Count -gt 0) {
            Write-Warning "Import errors occurred:"
            foreach ($error in $errors) {
                Write-Warning "  $error"
            }
        }
    }
}