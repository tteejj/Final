# Dashboard.ps1 - Main application view
using namespace System.Collections.Generic

# Shared utility for task hierarchy flattening - used by Dashboard and TuiApp
class TaskHierarchy {
    # Returns ArrayList of flattened display tasks with hierarchy indentation
    # Each item includes: id, text (indented), status, prio, due, tags
    static [System.Collections.ArrayList] FlattenTasks([array]$filteredTasks, [hashtable]$view) {
        $displayTasks = [System.Collections.ArrayList]::new()
        $processedIds = [HashSet[string]]::new()
        
        # OPTIMIZATION: Build parent-to-children index once (O(N))
        $parentChildrenMap = @{}
        foreach ($task in $filteredTasks) {
            $parentId = $task['parent_id']
            if ([string]::IsNullOrEmpty($parentId)) { continue }
            
            if (-not $parentChildrenMap.ContainsKey($parentId)) {
                $parentChildrenMap[$parentId] = [System.Collections.ArrayList]::new()
            }
            [void]$parentChildrenMap[$parentId].Add($task)
        }
        
        # Inner recursive function - uses closure to access outer variables
        $addWithChildren = $null
        $addWithChildren = {
            param($parent, $depth)
            $parentId = $parent['id']
            
            # OPTIMIZATION: O(1) lookup instead of O(N) Where-Object
            $children = if ($parentChildrenMap.ContainsKey($parentId)) { $parentChildrenMap[$parentId] } else { @() }
            
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
        if ($displayTasks -and $index -ge 0 -and $index -lt $displayTasks.Count) {
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
    hidden [object]$_taskCache = @{ Version = -1; ProjectId = ""; List = @() }
    hidden [object]$_displayCache = @{ Version = -1; ProjectId = ""; TaskId = ""; List = $null }
    hidden [hashtable]$_tasksById = @{}
    
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
            
            # OPTIMIZATION: Build tasksById index for O(1) lookups
            $this._tasksById = @{}
            if ($data.tasks) {
                foreach ($t in $data.tasks) {
                    $this._tasksById[$t.id] = $t
                }
            }
            
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
            
            # Invalidate task cache when data version changes
            $this._taskCache.Version = -1
        }
        
        $displayProjects = $this._projectCache.List
        
        $projectCols = @(
            @{ Header = "Project"; Field = "name"; Width = $sidebarW - 3 }
        )
        
        $this._sidebar.Render($engine, 0, 0, $sidebarW, $h - 1, $displayProjects.ToArray(), $projectCols, $view.Selection.Sidebar, ($view.FocusedPanel -eq "Sidebar"))
        
        # -- 2. TaskList (Hierarchical) --
        $selectedProject = $null
        if ($data.projects -and $view.Selection.Sidebar -ge 0 -and $view.Selection.Sidebar -lt @($data.projects).Count) {
            $selectedProject = $data.projects[$view.Selection.Sidebar]
        }
        
        # OPTIMIZATION: Cache filtered task list per project
        $selectedProjId = if ($selectedProject) { $selectedProject.id } else { "" }
        if ($state.Version -ne $this._taskCache.Version -or $selectedProjId -ne $this._taskCache.ProjectId) {
            $filteredTasks = @()
            if ($selectedProject) {
                if ($data.tasks) {
                    $filteredTasks = @($data.tasks | Where-Object { $_.projectId -eq $selectedProject.id })
                }
            }
            $this._taskCache.Version = $state.Version
            $this._taskCache.ProjectId = $selectedProjId
            $this._taskCache.List = $filteredTasks
        } else {
            $filteredTasks = $this._taskCache.List
        }
        
        $projName = if ($selectedProject) { $selectedProject.name } else { "(none)" }
        [Logger]::Log("Dashboard.Render: Proj='$projName' TasksFiltered=$(@($filteredTasks).Count)", 3)
        
        # Use shared hierarchy flattening with Caching & Native Optimization
        $activeTaskId = if ($view.ActiveTimer) { $view.ActiveTimer.TaskId } else { "" }
        
        if ($state.Version -ne $this._displayCache.Version -or 
            $selectedProjId -ne $this._displayCache.ProjectId -or 
            $activeTaskId -ne $this._displayCache.TaskId) {
            
            if ("NativeTaskProcessor" -as [type]) {
                 $displayTasks = [NativeTaskProcessor]::FlattenTasks($filteredTasks, $view)
            } else {
                 $displayTasks = [TaskHierarchy]::FlattenTasks($filteredTasks, $view)
            }
            
            $this._displayCache.Version = $state.Version
            $this._displayCache.ProjectId = $selectedProjId
            $this._displayCache.TaskId = $activeTaskId
            $this._displayCache.List = $displayTasks
        } else {
            $displayTasks = $this._displayCache.List
        }
        
        $taskCols = @(
            @{ Header = "S"; Field = "status"; Width = 3 },
            @{ Header = "P"; Field = "prio"; Width = 3 },
            @{ Header = "Task / Tags"; Field = "text"; Width = $taskListW - 25 },
            @{ Header = "Due"; Field = "due"; Width = 12 }
        )
        
        $this._taskList.Render($engine, $sidebarW, 0, $taskListW, $h - 1, $displayTasks.ToArray(), $taskCols, $view.Selection.TaskList, ($view.FocusedPanel -eq "TaskList"))
        
        # -- 3. Details Panel --
                # (Rest of the Render method remains similar but needs to use correct filteredTasks)
                # We need the ACTUAL task object for notes, not the display one.
                # Let's map display index back to original task.
                 $selectedTask = $null
                 if ($displayTasks -and $displayTasks.Count -gt 0 -and $view.Selection.TaskList -ge 0 -and $view.Selection.TaskList -lt $displayTasks.Count) {
                      $tId = $displayTasks[$view.Selection.TaskList].id
                      # OPTIMIZATION: O(1) lookup instead of O(N) Where-Object
                      $selectedTask = if ($this._tasksById.ContainsKey($tId)) { $this._tasksById[$tId] } else { $null }
                 }
                
                # -- Notes Panel (Full Height - Status Bar) --
                $notesH = $h - 1  # Full height minus status bar
                $notesBorder = if ($view.FocusedPanel -eq "Details") { [Colors]::Accent } else { [Colors]::PanelBorder }
                $engine.DrawBox($detailsX, 0, $detailsW, $notesH, $notesBorder, [Colors]::PanelBg)
                $engine.WriteAt($detailsX + 2, 0, " Notes ", [Colors]::Header, [Colors]::PanelBg)
                
                if ($selectedTask) {
                     $desc = if ($selectedTask.ContainsKey('description') -and $selectedTask['description']) { $selectedTask['description'] } else { "(No notes. Press 'M' to add)" }
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
                     $desc = if ($selectedProject.ContainsKey('description') -and $selectedProject['description']) { $selectedProject['description'] } else { "(No project notes)" }
                     $engine.WriteAt($detailsX + 2, 1, $desc, [Colors]::Foreground, [Colors]::PanelBg)
                }
                
                # Status bar is rendered by TuiApp's StatusBar component
                
            } catch {
                [Logger]::Error("Dashboard.Render CRASH", $_.Exception)
                throw
            }

        }
    }
