# Projects.ps1 - Project management functions
# Core project CRUD operations for PMC

function Invoke-PmcCreateProjectCore {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Description = ''
    )

    try {
        $allData = Get-PmcAllData

        if (-not $allData.projects) { $allData.projects = @() }

        # Normalize any string entries to objects to ensure consistent checks
        try {
            $normalized = @()
            foreach ($p in @($allData.projects)) {
                if ($p -is [string]) {
                    $normalized += [pscustomobject]@{
                        id = [guid]::NewGuid().ToString()
                        name = $p
                        description = ''
                        created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        status = 'active'
                        tags = @()
                    }
                } else {
                    $normalized += $p
                }
            }
            $allData.projects = $normalized
        } catch {}

        # Duplicate check (case-sensitive to match prior behavior)
        $existing = @($allData.projects | Where-Object { $_.PSObject.Properties['name'] -and $_.name -eq $Name })
        if ($existing.Count -gt 0) {
            return @{ Type='error'; Message=("Project '{0}' already exists" -f $Name) }
        }

        # Build new record matching CLI shape
        $newProject = [pscustomobject]@{
            id = [guid]::NewGuid().ToString()
            name = $Name
            description = $Description
            created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            status = 'active'
            tags = @()
        }

        $allData.projects += $newProject
        Set-PmcAllData $allData

        return @{ Type='success'; Message=("Project '{0}' created" -f $Name); Data=$newProject }
    } catch {
        return @{ Type='error'; Message=("Error creating project: {0}" -f $_) }
    }
}

function Add-PmcProject {
    param([PmcCommandContext]$Context)

    # If no arguments provided, launch the full wizard
    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Info' -Text "Launching Project Creation Wizard..."
        Start-PmcProjectWizard -Context $Context
        return
    }

    # If arguments provided, do quick project creation
    $projectName = $Context.FreeText[0]
    $description = $(if ($Context.FreeText.Count -gt 1) { ($Context.FreeText[1..($Context.FreeText.Count-1)] -join ' ') } else { "" })

    $result = Invoke-PmcCreateProjectCore -Name $projectName -Description $description
    if ($result -is [hashtable] -and $result.ContainsKey('Type') -and $result['Type'] -eq 'success') {
        Write-PmcStyled -Style 'Success' -Text ("Project '{0}' created" -f $projectName)
    } else {
        $msg = $(if ($result -is [hashtable] -and $result.ContainsKey('Message')) { [string]$result['Message'] } else { [string]$result })
        if (-not $msg) { $msg = "Failed to create project" }
        Write-PmcStyled -Style 'Error' -Text $msg
    }
}

function Show-PmcProject {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Error' -Text "Usage: project view <name>"
        return
    }

    $projectName = $Context.FreeText[0]

    try {
        $allData = Get-PmcAllData
        $project = $allData.projects | Where-Object { $_.name -eq $projectName }

        if (-not $project) {
            Write-PmcStyled -Style 'Error' -Text "Project '$projectName' not found"
            return
        }

        Write-PmcStyled -Style 'Header' -Text "`nProject: $($project.name)"
        Write-PmcStyled -Style 'Body' -Text "Description: $($project.description)"
        Write-PmcStyled -Style 'Body' -Text "Created: $($project.created)"
        Write-PmcStyled -Style 'Body' -Text "Status: $($project.status)"

        # Show related tasks
        $tasks = $allData.tasks | Where-Object { $_.project -eq $projectName }
        if ($tasks) {
            Write-PmcStyled -Style 'Header' -Text "`nTasks:"
            foreach ($task in $tasks) {
                $status = $(if ($task.completed) { "[OK]" } else { "○" })
                Write-PmcStyled -Style 'Body' -Text "  $status $($task.text)"
            }
        }

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error viewing project: $_"
    }
}

function Set-PmcProject {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -lt 2) {
        Write-PmcStyled -Style 'Error' -Text "Usage: project update <name> <field> <value>"
        return
    }

    $projectName = $Context.FreeText[0]
    $field = $Context.FreeText[1]
    $value = $(if ($Context.FreeText.Count -gt 2) { ($Context.FreeText[2..($Context.FreeText.Count-1)] -join ' ') } else { "" })

    try {
        $allData = Get-PmcAllData
        $project = $allData.projects | Where-Object { $_.name -eq $projectName }

        if (-not $project) {
            Write-PmcStyled -Style 'Error' -Text "Project '$projectName' not found"
            return
        }

        switch ($field.ToLower()) {
            'description' { $project.description = $value }
            'status' { $project.status = $value }
            default {
                Write-PmcStyled -Style 'Error' -Text "Unknown field '$field'. Available: description, status"
                return
            }
        }

        Set-PmcAllData $allData
        Write-PmcStyled -Style 'Success' -Text "[OK] Project '$projectName' updated"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error updating project: $_"
    }
}

function Edit-PmcProject {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Error' -Text "Usage: project edit <name>"
        return
    }

    $projectName = $Context.FreeText[0]

    try {
        $allData = Get-PmcAllData
        $project = $allData.projects | Where-Object { $_.name -eq $projectName }

        if (-not $project) {
            Write-PmcStyled -Style 'Error' -Text "Project '$projectName' not found"
            return
        }

        # Create editable project data
        $editableProject = [pscustomobject]@{
            Name = $project.name
            Description = $project.description
            Status = $project.status
        }

        $columns = @{
            Name = @{ Header='Project Name'; Width=25; Alignment='Left'; Editable=$true }
            Description = @{ Header='Description'; Width=45; Alignment='Left'; Editable=$true }
            Status = @{ Header='Status'; Width=15; Alignment='Left'; Editable=$true }
        }

        Write-PmcStyled -Style 'Info' -Text "Edit project details. Press Enter to save changes, Q to finish."

        Show-PmcDataGrid -Domains @('project-edit') -Columns $columns -Data @($editableProject) -Title "Edit Project: $projectName" -Interactive -OnSelectCallback {
            param($item)
            if ($item) {
                # Update project with edited values
                $project.name = [string]$item.Name
                $project.description = [string]$item.Description
                $project.status = [string]$item.Status

                Set-PmcAllData $allData
                Write-PmcStyled -Style 'Success' -Text "[OK] Project '$projectName' updated"
            }
        }

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error editing project: $_"
    }
}

function Rename-PmcProject {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -lt 2) {
        Write-PmcStyled -Style 'Error' -Text "Usage: project rename <old-name> <new-name>"
        return
    }

    $oldName = $Context.FreeText[0]
    $newName = $Context.FreeText[1]

    try {
        $allData = Get-PmcAllData
        $project = $allData.projects | Where-Object { $_.name -eq $oldName }

        if (-not $project) {
            Write-PmcStyled -Style 'Error' -Text "Project '$oldName' not found"
            return
        }

        # Check if new name already exists
        $existing = $allData.projects | Where-Object { $_.name -eq $newName }
        if ($existing) {
            Write-PmcStyled -Style 'Error' -Text "Project '$newName' already exists"
            return
        }

        # Update project name
        $project.name = $newName

        # Update all tasks with this project
        $allData.tasks | Where-Object { $_.project -eq $oldName } | ForEach-Object { $_.project = $newName }

        Set-PmcAllData $allData
        Write-PmcStyled -Style 'Success' -Text "[OK] Project renamed from '$oldName' to '$newName'"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error renaming project: $_"
    }
}

function Remove-PmcProject {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Error' -Text "Usage: project remove <name>"
        return
    }

    $projectName = $Context.FreeText[0]

    try {
        $allData = Get-PmcAllData
        $project = $allData.projects | Where-Object { $_.name -eq $projectName }

        if (-not $project) {
            Write-PmcStyled -Style 'Error' -Text "Project '$projectName' not found"
            return
        }

        # Check for tasks in this project
        $tasks = $allData.tasks | Where-Object { $_.project -eq $projectName }
        if ($tasks) {
            Write-PmcStyled -Style 'Warning' -Text "Project '$projectName' has $($tasks.Count) tasks. Remove tasks first or use project archive."
            return
        }

        # Remove project
        $allData.projects = $allData.projects | Where-Object { $_.name -ne $projectName }

        Set-PmcAllData $allData
        Write-PmcStyled -Style 'Success' -Text "[OK] Project '$projectName' removed"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error removing project: $_"
    }
}

function Set-PmcProjectArchived {
    param([PmcCommandContext]$Context)

    if (-not $Context -or $Context.FreeText.Count -eq 0) {
        Write-PmcStyled -Style 'Error' -Text "Usage: project archive <name>"
        return
    }

    $projectName = $Context.FreeText[0]

    try {
        $allData = Get-PmcAllData
        $project = $allData.projects | Where-Object { $_.name -eq $projectName }

        if (-not $project) {
            Write-PmcStyled -Style 'Error' -Text "Project '$projectName' not found"
            return
        }

        $project.status = 'archived'

        Set-PmcAllData $allData
        Write-PmcStyled -Style 'Success' -Text "[OK] Project '$projectName' archived"

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error archiving project: $_"
    }
}

function Set-PmcProjectFields {
    param([PmcCommandContext]$Context)
    Write-PmcStyled -Style 'Info' -Text "Project fields: name, description, status, created, tags"
}

function Show-PmcProjectFields {
    param([PmcCommandContext]$Context)
    Set-PmcProjectFields -Context $Context
}

function Get-PmcProjectStats {
    param([PmcCommandContext]$Context)

    try {
        $allData = Get-PmcAllData
        $projects = $allData.projects
        $tasks = $allData.tasks

        if (-not $projects) {
            Write-PmcStyled -Style 'Info' -Text "No projects found"
            return
        }

        Write-PmcStyled -Style 'Header' -Text "`nProject Statistics"
        Write-PmcStyled -Style 'Body' -Text "Total Projects: $($projects.Count)"

        $active = $projects | Where-Object { $_.status -eq 'active' }
        $archived = $projects | Where-Object { $_.status -eq 'archived' }

        Write-PmcStyled -Style 'Body' -Text "Active: $($active.Count)"
        Write-PmcStyled -Style 'Body' -Text "Archived: $($archived.Count)"

        if ($tasks) {
            Write-PmcStyled -Style 'Header' -Text "`nTask Distribution"
            foreach ($project in $projects) {
                $projectTasks = $tasks | Where-Object { $_.project -eq $project.name }
                if ($projectTasks) {
                    Write-PmcStyled -Style 'Body' -Text "$($project.name): $($projectTasks.Count) tasks"
                }
            }
        }

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error getting project stats: $_"
    }
}

function Show-PmcProjectInfo {
    param([PmcCommandContext]$Context)
    Show-PmcProject -Context $Context
}

function Get-PmcRecentProjects {
    param([PmcCommandContext]$Context)

    try {
        $allData = Get-PmcAllData
        $projects = $allData.projects | Sort-Object created -Descending | Select-Object -First 5

        if (-not $projects) {
            Write-PmcStyled -Style 'Info' -Text "No projects found"
            return
        }

        Write-PmcStyled -Style 'Header' -Text "`nRecent Projects"
        foreach ($project in $projects) {
            Write-PmcStyled -Style 'Body' -Text "$($project.name) - $($project.created)"
        }

    } catch {
        Write-PmcStyled -Style 'Error' -Text "Error getting recent projects: $_"
    }
}

# Export all project functions
Export-ModuleMember -Function Invoke-PmcCreateProjectCore, Add-PmcProject, Show-PmcProject, Set-PmcProject, Edit-PmcProject, Rename-PmcProject, Remove-PmcProject, Set-PmcProjectArchived, Set-PmcProjectFields, Show-PmcProjectFields, Get-PmcProjectStats, Show-PmcProjectInfo, Get-PmcRecentProjects