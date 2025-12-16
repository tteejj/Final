# SpeedTUI Task Model - Task management with status, priority, and progress tracking

# Load BaseModel if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'BaseModel').Type) {
    . "$PSScriptRoot/BaseModel.ps1"
}

enum TaskStatus {
    Pending = 0
    InProgress = 1
    Completed = 2
    Cancelled = 3
}

enum TaskPriority {
    Low = 0
    Medium = 1
    High = 2
}

class Task : BaseModel {
    [string]$Title = ""
    [string]$Description = ""
    [TaskStatus]$Status = [TaskStatus]::Pending
    [TaskPriority]$Priority = [TaskPriority]::Medium
    [int]$Progress = 0  # 0-100
    [string]$ProjectId = ""
    [string[]]$Tags = @()
    [DateTime]$DueDate
    [decimal]$EstimatedHours = 0
    [decimal]$ActualHours = 0
    [string]$AssignedTo = ""
    [string]$Category = ""
    [DateTime]$StartDate
    [DateTime]$CompletedDate
    
    Task() : base() {
        $this.DueDate = [DateTime]::Now.AddDays(7)
        $this.StartDate = [DateTime]::Now
    }
    
    Task([hashtable]$data) : base($data) {
        $this.Title = $(if ($data.Title) { $data.Title } else { "" })
        $this.Description = $(if ($data.Description) { $data.Description } else { "" })
        $this.Status = $(if ($null -ne $data.Status) { [TaskStatus]$data.Status } else { [TaskStatus]::Pending })
        $this.Priority = $(if ($null -ne $data.Priority) { [TaskPriority]$data.Priority } else { [TaskPriority]::Medium })
        $this.Progress = $(if ($null -ne $data.Progress) { [int]$data.Progress } else { 0 })
        $this.ProjectId = $(if ($data.ProjectId) { $data.ProjectId } else { "" })
        $this.Tags = $(if ($data.Tags) { $data.Tags } else { @() })
        $this.DueDate = $(if ($data.DueDate) { [DateTime]$data.DueDate } else { [DateTime]::Now.AddDays(7) })
        $this.EstimatedHours = $(if ($data.EstimatedHours) { [decimal]$data.EstimatedHours } else { 0 })
        $this.ActualHours = $(if ($data.ActualHours) { [decimal]$data.ActualHours } else { 0 })
        $this.AssignedTo = $(if ($data.AssignedTo) { $data.AssignedTo } else { "" })
        $this.Category = $(if ($data.Category) { $data.Category } else { "" })
        $this.StartDate = $(if ($data.StartDate) { [DateTime]$data.StartDate } else { [DateTime]::Now })
        $this.CompletedDate = $(if ($data.CompletedDate) { [DateTime]$data.CompletedDate } else { [DateTime]::MinValue })
    }
    
    [hashtable] ToHashtable() {
        $baseHash = ([BaseModel]$this).ToHashtable()
        
        $taskHash = @{
            Title = $this.Title
            Description = $this.Description
            Status = [int]$this.Status
            Priority = [int]$this.Priority
            Progress = $this.Progress
            ProjectId = $this.ProjectId
            Tags = $this.Tags
            DueDate = $this.DueDate
            EstimatedHours = $this.EstimatedHours
            ActualHours = $this.ActualHours
            AssignedTo = $this.AssignedTo
            Category = $this.Category
            StartDate = $this.StartDate
            CompletedDate = $this.CompletedDate
        }
        
        # Merge base and task properties
        foreach ($key in $taskHash.Keys) {
            $baseHash[$key] = $taskHash[$key]
        }
        
        return $baseHash
    }
    
    [bool] IsOverdue() {
        return $this.DueDate -lt [DateTime]::Now.Date -and $this.Status -ne [TaskStatus]::Completed -and $this.Status -ne [TaskStatus]::Cancelled
    }
    
    [int] GetDaysUntilDue() {
        return ($this.DueDate.Date - [DateTime]::Now.Date).Days
    }
    
    [string] GetStatusDisplay() {
        if ($this.Status -eq [TaskStatus]::Pending) {
            return "Pending"
        } elseif ($this.Status -eq [TaskStatus]::InProgress) {
            return "In Progress"
        } elseif ($this.Status -eq [TaskStatus]::Completed) {
            return "Completed"
        } elseif ($this.Status -eq [TaskStatus]::Cancelled) {
            return "Cancelled"
        } else {
            return "Unknown"
        }
    }
    
    [string] GetPriorityDisplay() {
        if ($this.Priority -eq [TaskPriority]::Low) {
            return "Low"
        } elseif ($this.Priority -eq [TaskPriority]::Medium) {
            return "Medium"
        } elseif ($this.Priority -eq [TaskPriority]::High) {
            return "High"
        } else {
            return "Unknown"
        }
    }
    
    [string] GetProgressBar([int]$width = 10) {
        $filledChars = [Math]::Floor($width * $this.Progress / 100)
        $emptyChars = $width - $filledChars
        
        $filled = "█" * $filledChars
        $empty = "░" * $emptyChars
        
        return "[$filled$empty] $($this.Progress)%"
    }
    
    [void] UpdateProgress([int]$newProgress) {
        if ($newProgress -lt 0) { $newProgress = 0 }
        if ($newProgress -gt 100) { $newProgress = 100 }
        
        $this.Progress = $newProgress
        $this.Touch()
        
        # Auto-update status based on progress
        if ($newProgress -eq 100 -and $this.Status -ne [TaskStatus]::Completed) {
            $this.Status = [TaskStatus]::Completed
            $this.CompletedDate = [DateTime]::Now
        } elseif ($newProgress -gt 0 -and $this.Status -eq [TaskStatus]::Pending) {
            $this.Status = [TaskStatus]::InProgress
        }
    }
    
    [void] MarkCompleted() {
        $this.Status = [TaskStatus]::Completed
        $this.Progress = 100
        $this.CompletedDate = [DateTime]::Now
        $this.Touch()
    }
    
    [void] MarkCancelled() {
        $this.Status = [TaskStatus]::Cancelled
        $this.Touch()
    }
    
    [void] AddTag([string]$tag) {
        if (-not [string]::IsNullOrEmpty($tag) -and $tag -notin $this.Tags) {
            $this.Tags += $tag
            $this.Touch()
        }
    }
    
    [void] RemoveTag([string]$tag) {
        if ($tag -in $this.Tags) {
            $this.Tags = $this.Tags | Where-Object { $_ -ne $tag }
            $this.Touch()
        }
    }
    
    [string] GetTagsDisplay() {
        if ($this.Tags.Count -eq 0) {
            return ""
        }
        return ($this.Tags -join ", ")
    }
    
    [bool] HasTag([string]$tag) {
        return $tag -in $this.Tags
    }
    
    [decimal] GetHoursVariance() {
        if ($this.EstimatedHours -eq 0) {
            return 0
        }
        return $this.ActualHours - $this.EstimatedHours
    }
    
    [double] GetHoursVariancePercent() {
        if ($this.EstimatedHours -eq 0) {
            return 0
        }
        return (($this.ActualHours - $this.EstimatedHours) / $this.EstimatedHours) * 100
    }
    
    [bool] IsValid() {
        $baseValid = ([BaseModel]$this).IsValid()
        $hasTitle = -not [string]::IsNullOrEmpty($this.Title)
        
        return $baseValid -and $hasTitle
    }
    
    [string] GetDisplaySummary() {
        $statusText = $this.GetStatusDisplay()
        $priorityText = $this.GetPriorityDisplay()
        $progressText = "$($this.Progress)%"
        
        $summary = "$($this.Title) [$statusText] [$priorityText] [$progressText]"
        
        if ($this.IsOverdue()) {
            $daysOverdue = [Math]::Abs($this.GetDaysUntilDue())
            $summary += " [OVERDUE: $daysOverdue days]"
        }
        
        return $summary
    }
}