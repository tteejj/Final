# Curated help content for standalone ConsoleUI

Set-StrictMode -Version Latest

$Script:PmcHelpContent = @{
    'Quick Tasks' = @{
        Description = 'Common task management commands'
        Items = @(
            @{ Type='View'; Command='today'; Description='Tasks due today' }
            @{ Type='View'; Command='overdue'; Description='Overdue tasks' }
            @{ Type='View'; Command='agenda'; Description='Agenda view' }
            @{ Type='Add'; Command='add "Task text" @project p1 due:today'; Description='Add new task' }
            @{ Type='Edit'; Command='edit 123'; Description='Edit task by ID' }
            @{ Type='Complete'; Command='done 123'; Description='Mark task complete' }
        )
    }
    'Projects' = @{
        Description = 'Project management commands'
        Items = @(
            @{ Type='View'; Command='projects'; Description='List all projects' }
            @{ Type='Add'; Command='project add "Project Name"'; Description='Create new project' }
            @{ Type='View'; Command='project show webapp'; Description='Show project details' }
            @{ Type='Edit'; Command='project edit webapp'; Description='Edit project settings' }
        )
    }
    'Query Language' = @{
        Description = 'Filter, sort, and display tasks'
        Items = @(
            @{ Type='Basic'; Command='q tasks'; Description='Show all tasks' }
            @{ Type='Filter'; Command='q tasks due:today'; Description='Tasks due today' }
            @{ Type='Filter'; Command='q tasks @webapp'; Description='Project filter' }
            @{ Type='View'; Command='q tasks group:status'; Description='Group by status' }
            @{ Type='View'; Command='q tasks cols:id,text,due'; Description='Custom columns' }
            @{ Type='Sort'; Command='q tasks sort:due+'; Description='Sort by due date asc' }
        )
    }
}

function Get-PmcHelpData {
    param()
    $helpCategories = @()
    if ($Script:PmcHelpContent -and $Script:PmcHelpContent.Count -gt 0) {
        $id = 1
        foreach ($categoryEntry in $Script:PmcHelpContent.GetEnumerator()) {
            $helpCategories += [PSCustomObject]@{
                id = $id++
                Category = $categoryEntry.Key
                CommandCount = $categoryEntry.Value.Items.Count
                Description = $categoryEntry.Value.Description
            }
        }
    }
    return $helpCategories
}