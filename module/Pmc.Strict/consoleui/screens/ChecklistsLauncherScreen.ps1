using namespace System.Collections.Generic
using namespace System.Text

# ChecklistsLauncherScreen - Select project to view checklists
# Simple project picker that then opens ChecklistsMenuScreen for selected project

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"

<#
.SYNOPSIS
Checklist launcher - select project to view its checklists

.DESCRIPTION
Shows list of all projects. Selecting a project opens ChecklistsMenuScreen for that project.
#>
class ChecklistsLauncherScreen : StandardListScreen {
    hidden [TaskStore]$_store = $null

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Tools', 'Checklists', 'C', {
            . "$PSScriptRoot/ChecklistsLauncherScreen.ps1"
            $global:PmcApp.PushScreen((New-Object -TypeName ChecklistsLauncherScreen))
        }, 25)
    }

    # Legacy constructor
    ChecklistsLauncherScreen() : base("ChecklistsLauncher", "Select Project for Checklists") {
        $this._InitializeScreen()
    }

    # Container constructor
    ChecklistsLauncherScreen([object]$container) : base("ChecklistsLauncher", "Select Project for Checklists", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        $this._store = [TaskStore]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $false
        $this.AllowEdit = $false
        $this.AllowDelete = $false
        $this.AllowFilter = $false

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tools", "Checklists"))
    }

    # === Abstract Method Implementations ===

    [string] GetEntityType() {
        return 'project'
    }

    [array] GetColumns() {
        return @(
            @{ Name='name'; Label='Project Name'; Width=60; Sortable=$true }
        )
    }

    [void] LoadData() {
        $projects = @($this._store.GetAllProjects())

        # Convert to array of hashtables with name
        $items = @()
        foreach ($project in $projects) {
            if ($project -is [string]) {
                $items += @{ name = $project }
            } elseif ($project -is [hashtable]) {
                $items += @{ name = $project['name'] }
            } else {
                $items += @{ name = $project.name }
            }
        }

        $this.List.SetData($items)
    }

    [array] GetEditFields([object]$item) {
        # Not used
        return @()
    }

    [void] OnItemActivated($item) {
        # Get project name
        $projectName = $(if ($item -is [hashtable]) { $item['name'] } else { $item.name })

        if ([string]::IsNullOrWhiteSpace($projectName)) {
            $this.SetStatusMessage("Invalid project", "error")
            return
        }

        # Open ChecklistsMenuScreen for this project
        . "$PSScriptRoot/ChecklistsMenuScreen.ps1"
        $checklistsScreen = New-Object ChecklistsMenuScreen -ArgumentList "project", $projectName, $projectName
        $global:PmcApp.PushScreen($checklistsScreen)
    }

    [array] GetCustomActions() {
        $self = $this
        return @(
            @{
                Key = 'O'
                Label = 'Open'
                Callback = {
                    $selected = $self.List.GetSelectedItem()
                    if ($selected) {
                        $self.OnItemActivated($selected)
                    }
                }.GetNewClosure()
            }
        )
    }
}