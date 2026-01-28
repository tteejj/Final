# Dashboard.ps1 - Main application view
using namespace System.Collections.Generic

# Shared utility for task hierarchy flattening - used by Dashboard and TuiApp
class TaskHierarchy {
    # Returns ArrayList of flattened display tasks with hierarchy indentation
    # Each item includes: id, text (indented), status, prio, due, tags
    static [System.Collections.ArrayList] FlattenTasks([array]$filteredTasks, [hashtable]$view) {
        $displayTasks = [System.Collections.ArrayList]::new()
        $processedIds = [HashSet[string]]::new()
        
        # Inner recursive function - uses closure to access outer variables
        $addWithChildren = $null
        $addWithChildren = {
            param($parent, $depth)
            $parentId = $parent['id']
            $children = $filteredTasks | Where-Object { $_['parent_id'] -eq $parentId }
            
            $statusIcon = if ($parent['completed']) { "[X]" } else { "[ ]" }
            if ($view.ActiveTimer -and $view.ActiveTimer.TaskId -eq $parentId) { $statusIcon = "[R]" }
            
            $dueStr = ""
            if ($parent.ContainsKey('due') -and $parent['due']) { 
                try { $dueStr = ([DateTime]::Parse($parent['due'])).ToString("yyyy-MM-dd") } catch {} 
            }
            
            $tagsStr = if ($parent.ContainsKey('tags') -and $parent['tags']) { "#" + ($parent['tags'] -join " #") } else { "" }
            
            [void]$displayTasks.Add(@{
                id = $parentId
                text = ("  " * $depth) + $parent['text']
                status = $statusIcon
                prio = switch ($parent['priority']) { 1 { "!" } 2 { "!!" } 3 { "!!!" } Default { "" } }
                due = $dueStr
                tags = $tagsStr
                _task = $parent  # Keep reference to original task
            })
            [void]$processedIds.Add($parentId)
            
            foreach ($child in $children) {
                & $addWithChildren $child ($depth + 1)
            }
        }
        
        # Process root tasks first
        foreach ($t in ($filteredTasks | Where-Object { [string]::IsNullOrEmpty($_['parent_id']) })) {
            & $addWithChildren $t 0
        }
        
        # Catch orphans (tasks with invalid parent_id)
        foreach ($t in $filteredTasks) {
            if (-not $processedIds.Contains($t.id)) {
                & $addWithChildren $t 0
            }
        }
        
        return $displayTasks
    }
    
    # Returns the original task hashtable at the given display index
    static [hashtable] GetTaskAtIndex([System.Collections.ArrayList]$displayTasks, [int]$index) {
        if ($index -ge 0 -and $index -lt $displayTasks.Count) {
            return $displayTasks[$index]._task
        }
        return $null
    }
}

class Dashboard {
    hidden [UniversalList]$_sidebar
    hidden [UniversalList]$_taskList
    hidden [UniversalList]$_details
    
    Dashboard() {
        $this._sidebar = [UniversalList]::new("Sidebar")
        $this._taskList = [UniversalList]::new("TaskList")
        $this._details = [UniversalList]::new("Details")
    }
    
    [int] GetTaskListScrollOffset() {
        return $this._taskList.GetScrollOffset()
    }
    
    hidden [object]$_projectCache = @{ Version = -1; List = [System.Collections.ArrayList]::new() }
    
    [void] Render([HybridRenderEngine]$engine, [hashtable]$state) {
        try {
            $data = $state.Data
            $view = $state.View
        
        $w = $engine.Width
        $h = $engine.Height
        $sidebarW = [int]($w * 0.30)
        $taskListW = [int]($w * 0.35)
        $detailsW = $w - $sidebarW - $taskListW
        $detailsX = $sidebarW + $taskListW
        
        # -- 1. Sidebar (Projects) --
        
        # Optimization: Cache the project list processing (especially time totals)
        # Only rebuild if Data.Version changes
        if ($state.Version -ne $this._projectCache.Version) {
            $displayProjects = [System.Collections.ArrayList]::new()
            
            # Pre-group timelogs by project for O(N) access
            $timelogsByProject = @{}
            if ($data.timelogs) {
                foreach ($l in $data.timelogs) {
                    $projId = $l['projectId']
                    if (-not $timelogsByProject.ContainsKey($projId)) {
                        $timelogsByProject[$projId] = [System.Collections.ArrayList]::new()
                    }
                    [void]$timelogsByProject[$projId].Add($l)
                }
            }
            
            if ($data.projects) {
                foreach ($p in $data.projects) {
                    $tasksForProj = @()
                    if ($data.tasks) {
                        $tasksForProj = @($data.tasks | Where-Object { $_.projectId -eq $p.id })
                    }
                    
                    [void]$displayProjects.Add(@{
                        id = $p.id
                        name = "$($p.name) ($(@($tasksForProj).Count))"
                    })
                }
            }
            
            $this._projectCache.Version = $state.Version
            $this._projectCache.List = $displayProjects
        }
        
        $displayProjects = $this._projectCache.List
        
        $projectCols = @(
            @{ Header = "Project"; Field = "name"; Width = $sidebarW - 3 }
        )
        
        $this._sidebar.Render($engine, 0, 0, $sidebarW, $h, $displayProjects.ToArray(), $projectCols, $view.Selection.Sidebar, ($view.FocusedPanel -eq "Sidebar"))
        
        # -- 2. TaskList (Hierarchical) --
        $selectedProject = $null
        if ($data.projects -and $view.Selection.Sidebar -ge 0 -and $view.Selection.Sidebar -lt @($data.projects).Count) {
            $selectedProject = $data.projects[$view.Selection.Sidebar]
        }
        
        $filteredTasks = @()
        if ($selectedProject) {
            if ($data.tasks) {
                # Ensure we are getting the latest tasks from the state data directly
                # Force array cast to ensure Count property exists
                $filteredTasks = @($state.Data.tasks | Where-Object { $_.projectId -eq $selectedProject.id })
            }
        }
        
        [Logger]::Log("Dashboard.Render: Proj='$($selectedProject.name)' TasksFiltered=$(@($filteredTasks).Count)", 3)
        
        # Use shared hierarchy flattening
        $displayTasks = [TaskHierarchy]::FlattenTasks($filteredTasks, $view)
        
        $taskCols = @(
            @{ Header = "S"; Field = "status"; Width = 3 },
            @{ Header = "P"; Field = "prio"; Width = 3 },
            @{ Header = "Task / Tags"; Field = "text"; Width = $taskListW - 24 },
            @{ Header = "Due"; Field = "due"; Width = 12 }
        )
        
        $this._taskList.Render($engine, $sidebarW, 0, $taskListW, $h, $displayTasks.ToArray(), $taskCols, $view.Selection.TaskList, ($view.FocusedPanel -eq "TaskList"))
        
        # -- 3. Details Panel --
                # (Rest of the Render method remains similar but needs to use correct filteredTasks)
                # We need the ACTUAL task object for notes, not the display one.
                # Let's map display index back to original task.
                $selectedTask = $null
                if ($displayTasks.Count -gt 0 -and $view.Selection.TaskList -ge 0 -and $view.Selection.TaskList -lt $displayTasks.Count) {
                     $tId = $displayTasks[$view.Selection.TaskList].id
                     # Return the first match (should be unique)
                     $selectedTask = ($data.tasks | Where-Object { $_.id -eq $tId } | Select-Object -First 1)
                }
                
                # -- Notes Panel (Full Height - Status Bar) --
                $notesH = $h - 1  # Full height minus status bar
                $notesBorder = if ($view.FocusedPanel -eq "Details") { [Colors]::Accent } else { [Colors]::PanelBorder }
                $engine.DrawBox($detailsX, 0, $detailsW, $notesH, $notesBorder, [Colors]::PanelBg)
                $engine.WriteAt($detailsX + 2, 0, " Notes ", [Colors]::Title, [Colors]::PanelBg)
                
                if ($selectedTask) {
                     $desc = "(No notes. Press 'M' to add)"
                     if ($selectedTask.ContainsKey('description') -and $selectedTask['description']) {
                         $desc = $selectedTask['description']
                     }
                     # Word wrap (simple)
                     $lines = $desc -split "`n"
                     $currentY = 1
                     foreach ($line in $lines) {
                         if ($currentY -ge $notesH - 1) { break }
                         $maxLineLen = $detailsW - 4
                         if ($line.Length -gt $maxLineLen) { $line = $line.Substring(0, $maxLineLen) }
                         $engine.WriteAt($detailsX + 2, $currentY, $line, [Colors]::Foreground, [Colors]::PanelBg)
                         $currentY++
                     }
                } elseif ($selectedProject) {
                     $desc = "(No project notes)"
                     if ($selectedProject.ContainsKey('description') -and $selectedProject['description']) {
                         $desc = $selectedProject['description']
                     }
                     $engine.WriteAt($detailsX + 2, 1, $desc, [Colors]::Foreground, [Colors]::PanelBg)
                }
                
                # Status bar is rendered by TuiApp's StatusBar component
                
            } catch {
                [Logger]::Error("Dashboard.Render CRASH", $_.Exception)
                throw
            }

        }
    }
