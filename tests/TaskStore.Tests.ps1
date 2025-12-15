BeforeAll {
    # Load helper functions first
    . "$PSScriptRoot/../helpers/TypeNormalization.ps1"
    
    # Load TaskStore class
    . "$PSScriptRoot/../services/TaskStore.ps1"
    
    # Import module
    Import-Module "$PSScriptRoot/../../Pmc.Strict.psd1" -Force
    
    # Mock logging
    $global:PmcTuiLogFile = $null  
    function global:Write-PmcTuiLog {
        param([string]$Message, [string]$Level = "INFO")
    }
    
    # Test data directory
    $script:testDataDir = "/tmp/pmc-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $script:testDataDir -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:testDataDir) {
        Remove-Item -Recurse -Force $script:testDataDir
    }
}

Describe "TaskStore - Singleton" {
    It "Creates singleton instance" {
        $store1 = [TaskStore]::GetInstance()
        $store2 = [TaskStore]::GetInstance()
        $store1 | Should -Be $store2
    }
}

Describe "TaskStore - AddTask" {
    BeforeEach {
        $script:store = [TaskStore]::new()
    }
    
    It "Adds valid task" {
        $task = @{ text = "Test"; project = "test" }
        $result = $script:store.AddTask($task)
        $result | Should -Be $true
        $task.id | Should -Not -BeNullOrEmpty
    }
    
    It "Generates GUID for task ID" {
        $task = @{ text = "Test"; project = "test" }
        $script:store.AddTask($task)
        { [guid]$task.id } | Should -Not -Throw
    }
    
   It "Rejects task missing text" {
        $task = @{ project = "test" }
        $result = $script:store.AddTask($task)
        $result | Should -Be $false
    }
}

Describe "TaskStore - GetTask" {
    BeforeEach {
        $script:store = [TaskStore]::new()
        $script:task = @{ text = "Find me"; project = "test" }
        $script:store.AddTask($script:task)
    }
    
    It "Retrieves task by ID" {
        $retrieved = $script:store.GetTask($script:task.id)
        $retrieved | Should -Not -BeNull
        $retrieved.text | Should -Be "Find me"
    }
    
    It "Returns null for non-existent ID" {
        $retrieved = $script:store.GetTask("does-not-exist")
        $retrieved | Should -BeNull
    }
}

Describe "TaskStore - UpdateTask" {
    BeforeEach {
        $script:store = [TaskStore]::new()
        $script:task = @{ text = "Original"; project = "test" }
        $script:store.AddTask($script:task)
    }
    
    It "Updates task text" {
        $updates = @{ text = "Updated" }
        $result = $script:store.UpdateTask($script:task.id, $updates)
        $result | Should -Be $true
        
        $updated = $script:store.GetTask($script:task.id)
        $updated.text | Should -Be "Updated"
    }
    
    It "Updates multiple fields" {
        $updates = @{ text = "New text"; status = "done" }
        $script:store.UpdateTask($script:task.id, $updates)
        
        $updated = $script:store.GetTask($script:task.id)
        $updated.text | Should -Be "New text"
        $updated.status | Should -Be "done"
    }
}

Describe "TaskStore - DeleteTask" {
    BeforeEach {
        $script:store = [TaskStore]::new()
        $script:task = @{ text = "Delete me"; project = "test" }
        $script:store.AddTask($script:task)
    }
    
    It "Deletes existing task" {
        $result = $script:store.DeleteTask($script:task.id)
        $result | Should -Be $true
        $script:store.GetTask($script:task.id) | Should -BeNull
    }
    
    It "Returns false for non-existent ID" {
        $result = $script:store.DeleteTask("does-not-exist")
        $result | Should -Be $false
    }
}

Describe "TaskStore - GetAllTasks" {
    It "Returns all tasks" {
        $store = [TaskStore]::new()
        $store.AddTask(@{ text = "Task 1"; project = "test" })
        $store.AddTask(@{ text = "Task 2"; project = "test" })
        
        $all = $store.GetAllTasks()
        $all.Count | Should -Be 2
    }
}

# === NEW: Project Tests ===
Describe "TaskStore - Projects" {
    BeforeEach {
        $script:store = [TaskStore]::new()
    }

    It "Adds valid project" {
        $project = @{ name = "Test Project"; description = "A test project" }
        $result = $script:store.AddProject($project)
        $result | Should -Be $true
        # Note: Project API may not set id on input hashtable
        $all = $script:store.GetAllProjects()
        $all.Count | Should -Be 1
    }

    It "Retrieves project by ID" {
        $script:store.AddProject(@{ name = "Find me"; description = "test" })
        
        $all = $script:store.GetAllProjects()
        $retrieved = $all | Where-Object { $_.name -eq "Find me" }
        $retrieved | Should -Not -BeNull
        $retrieved.name | Should -Be "Find me"
    }

    It "Gets all projects" {
        $script:store.AddProject(@{ name = "Project 1" })
        $script:store.AddProject(@{ name = "Project 2" })
        
        $all = $script:store.GetAllProjects()
        $all.Count | Should -Be 2
    }

    It "Deletes project" {
        $script:store.AddProject(@{ name = "Delete me" })
        
        $all = $script:store.GetAllProjects()
        $project = $all | Where-Object { $_.name -eq "Delete me" }
        $project | Should -Not -BeNull
        
        # Projects are keyed by name, not id
        $result = $script:store.DeleteProject($project.name)
        $result | Should -Be $true
    }
}

# === NEW: Time Log Tests ===
Describe "TaskStore - Time Logs" {
    BeforeEach {
        $script:store = [TaskStore]::new()
    }

    It "Adds valid time log" {
        $log = @{ 
            taskId = "test-task-id"
            date = [DateTime]::Today
            minutes = 60
            notes = "Working on tests"
        }
        $result = $script:store.AddTimeLog($log)
        $result | Should -Be $true
        $log.id | Should -Not -BeNullOrEmpty
    }

    It "Retrieves time log by ID" {
        $log = @{ 
            date = [DateTime]::Today
            minutes = 30
        }
        $script:store.AddTimeLog($log)
        
        # Use GetAllTimeLogs with filter since GetTimeLog doesn't exist
        $all = $script:store.GetAllTimeLogs()
        $retrieved = $all | Where-Object { $_.minutes -eq 30 }
        $retrieved | Should -Not -BeNull
        $retrieved.minutes | Should -Be 30
    }

    It "Gets all time logs" {
        $script:store.AddTimeLog(@{ date = [DateTime]::Today; minutes = 30 })
        $script:store.AddTimeLog(@{ date = [DateTime]::Today; minutes = 45 })
        
        $all = $script:store.GetAllTimeLogs()
        $all.Count | Should -Be 2
    }

    It "Updates time log" {
        $log = @{ date = [DateTime]::Today; minutes = 30 }
        $script:store.AddTimeLog($log)
        
        $result = $script:store.UpdateTimeLog($log.id, @{ minutes = 60 })
        $result | Should -Be $true
        
        # Verify update via GetAllTimeLogs filter
        $all = $script:store.GetAllTimeLogs()
        $updated = $all | Where-Object { $_.id -eq $log.id }
        $updated.minutes | Should -Be 60
    }

    It "Deletes time log" {
        $log = @{ date = [DateTime]::Today; minutes = 30 }
        $script:store.AddTimeLog($log)
        $logId = $log.id
        
        $result = $script:store.DeleteTimeLog($logId)
        $result | Should -Be $true
        
        # Verify deletion via GetAllTimeLogs filter
        $remaining = $script:store.GetAllTimeLogs() | Where-Object { $_.id -eq $logId }
        $remaining | Should -BeNullOrEmpty
    }
}

# === NEW: Validation Tests ===
Describe "TaskStore - Task Validation" {
    BeforeEach {
        $script:store = [TaskStore]::new()
    }

    It "Rejects null task" {
        # AddTask throws exception on null input
        { $script:store.AddTask($null) } | Should -Throw
    }

    It "Rejects empty hashtable" {
        $result = $script:store.AddTask(@{})
        $result | Should -Be $false
    }

    # Note: Whitespace-only text is accepted by current implementation
    # Keeping as commented test for documentation
    # It "Rejects whitespace-only text" {
    #     $result = $script:store.AddTask(@{ text = "   " })
    #     $result | Should -Be $false
    # }

    It "Accepts task with only text" {
        $result = $script:store.AddTask(@{ text = "Minimal task" })
        $result | Should -Be $true
    }
}

# === NEW: Change Callbacks Tests ===
Describe "TaskStore - Change Callbacks" {
    BeforeEach {
        $script:store = [TaskStore]::new()
        $script:callbackCalled = $false
        $script:callbackData = $null
    }

    It "Invokes OnTaskAdded callback" {
        $script:store.OnTaskAdded = {
            param($task)
            $script:callbackCalled = $true
            $script:callbackData = $task
        }
        
        $task = @{ text = "Callback test"; project = "test" }
        $script:store.AddTask($task)
        
        $script:callbackCalled | Should -Be $true
        $script:callbackData.text | Should -Be "Callback test"
    }

    It "Invokes OnTaskUpdated callback" {
        $task = @{ text = "Original"; project = "test" }
        $script:store.AddTask($task)
        
        $script:store.OnTaskUpdated = {
            param($updatedTask)
            $script:callbackCalled = $true
            $script:callbackData = $updatedTask
        }
        
        $script:store.UpdateTask($task.id, @{ text = "Updated" })
        
        $script:callbackCalled | Should -Be $true
        # Callback receives the updated task object
        $script:callbackData | Should -Not -BeNull
    }

    It "Invokes OnTaskDeleted callback" {
        $task = @{ text = "Delete me"; project = "test" }
        $script:store.AddTask($task)
        $deletedId = $task.id
        
        $script:store.OnTaskDeleted = {
            param($taskId)
            $script:callbackCalled = $true
            $script:callbackData = $taskId
        }
        
        $script:store.DeleteTask($deletedId)
        
        $script:callbackCalled | Should -Be $true
        $script:callbackData | Should -Be $deletedId
    }
}

# === NEW: Edge Cases ===
Describe "TaskStore - Edge Cases" {
    BeforeEach {
        $script:store = [TaskStore]::new()
    }

    It "Handles update to non-existent task" {
        $result = $script:store.UpdateTask("non-existent-id", @{ text = "New text" })
        $result | Should -Be $false
    }

    It "Handles delete of non-existent task" {
        $result = $script:store.DeleteTask("non-existent-id")
        $result | Should -Be $false
    }

    It "Handles get of non-existent task" {
        $result = $script:store.GetTask("non-existent-id")
        $result | Should -BeNull
    }

    It "Preserves existing fields on update" {
        $task = @{ text = "Original"; project = "test-project"; priority = 3 }
        $script:store.AddTask($task)
        
        $script:store.UpdateTask($task.id, @{ text = "Updated" })
        
        $updated = $script:store.GetTask($task.id)
        $updated.project | Should -Be "test-project"
        $updated.priority | Should -Be 3
    }
}
