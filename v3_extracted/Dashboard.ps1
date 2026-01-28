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

    # Text wrapping helper - wraps text to fit within specified width
    hidden [string[]] WrapText([string]$text, [int]$maxWidth) {
        if ([string]::IsNullOrEmpty($text)) { return @("") }
        if ($maxWidth -le 0) { return @($text) }

        $lines = @()
        $currentLine = ""
        $words = $text -split ' '

        foreach ($word in $words) {
            if ($currentLine.Length -eq 0) {
                $currentLine = $word
            } elseif (($currentLine + " " + $word).Length -le $maxWidth) {
                $currentLine += " " + $word
            } else {
                $lines += $currentLine
                $currentLine = $word
            }
        }
        if ($currentLine) { $lines += $currentLine }
        return $lines
    }

    # Calculate optimal column dimensions (widths AND heights) based on content
    # Calculate optimal column dimensions (widths AND heights) based on content
    hidden [hashtable] CalculateOptimalDimensions([int]$totalWidth, [int]$totalHeight, [array]$displayProjects, [array]$displayTasks, [bool]$isDetailsVisible, [string]$focusedPanel, [bool]$isAddingProject, [bool]$isAddingTask) {
        # Width constraints
        $minSidebar = 20
        $maxSidebar = [int]($totalWidth * 0.40)
        $minTaskList = 30
        $maxTaskList = [int]($totalWidth * 0.50)
        $minDetails = 30

        # Height constraints (minimum of 10 lines per column)
        $minHeight = 10
        $headerHeight = 1

        # --- SIDEBAR CALCULATIONS ---
        $sidebarW = $minSidebar
        if ($displayProjects.Count -gt 0) {
            $maxNameLen = 0
            foreach ($p in $displayProjects) {
                $nameLen = if ($p.ContainsKey('name')) { $p.name.Length } else { 0 }
                if ($nameLen -gt $maxNameLen) { $maxNameLen = $nameLen }
            }
            $sidebarW = $maxNameLen + 6  # +6 for padding/count
        }
        $sidebarW = [Math]::Max($minSidebar, [Math]::Min($maxSidebar, $sidebarW))

        # Calculate sidebar height based on content
        # Strictly Count + 2 (Top Border + Bottom Border + Content)
        $contentCount = $displayProjects.Count
        if ($isAddingProject) { $contentCount++ }

        $sidebarH = $contentCount + 2
        $sidebarH = [Math]::Max(3, $sidebarH)
        $sidebarH = [Math]::Min($sidebarH, $totalHeight - 1)  # Don't exceed screen

        # --- TASKLIST CALCULATIONS ---
        # --- TASKLIST CALCULATIONS ---
        # TaskList logic: Hide if focused on Sidebar (Drill-down behavior)
        if ($focusedPanel -eq 'Sidebar') {
             $taskListW = 0
             $taskListH = 0
        } else {
             # Standard TaskList Layout
             # TaskList has: Status(3) + Prio(3) + Text + Due(12)
        $maxTaskLen = 0
        if ($displayTasks.Count -gt 0) {
            foreach ($t in $displayTasks) {
                $textLen = if ($t.ContainsKey('text')) { $t.text.Length } else { 0 }
                if ($textLen -gt $maxTaskLen) { $maxTaskLen = $textLen }
            }
        }
        # 3+3+1+12 = 19 for fixed columns
        $taskListW = 19 + $maxTaskLen
        $taskListW = [Math]::Max($minTaskList, [Math]::Min($maxTaskList, $taskListW))

        # Calculate tasklist height based on wrapped content
        $taskListH = $headerHeight
        foreach ($t in $displayTasks) {
            $text = if ($t.ContainsKey('text')) { $t.text } else { "" }
            # Calculate available width for text column
            $textColWidth = $taskListW - 19
            $wrappedLines = $this.WrapText($text, $textColWidth)
             $taskListH += $wrappedLines.Count  # Each line is a row
             }

             if ($isAddingTask) { $taskListH++ }

             # Add borders (+2)
             $taskListH += 2
             $taskListH = [Math]::Max(3, $taskListH)
             $taskListH = [Math]::Min($taskListH, $totalHeight - 1)
        }

        # --- DETAILS CALCULATIONS ---
        if ($isDetailsVisible) {
            $detailsW = $totalWidth - $sidebarW - $taskListW
            $detailsH = $totalHeight - 1  # Full height minus status bar

            # Enforce minimum details width
            if ($detailsW -lt $minDetails) {
                # Shrink tasklist first, then sidebar
                $excess = $minDetails - $detailsW
                $taskListAvailable = $taskListW - $minTaskList
                $taskReduction = [Math]::Min($taskListAvailable, $excess)
                $taskListW -= $taskReduction
                $detailsW = $totalWidth - $sidebarW - $taskListW

                if ($detailsW -lt $minDetails) {
                    # Still need space, shrink sidebar
                    $sidebarExcess = $minDetails - $detailsW
                    $sidebarAvailable = $sidebarW - $minSidebar
                    $sidebarReduction = [Math]::Min($sidebarAvailable, $sidebarExcess)
                    $sidebarW -= $sidebarReduction
                    $detailsW = $totalWidth - $sidebarW - $taskListW
                }
            }
        } else {
            # Details hidden - tasklist can expand
            $detailsW = 0
            $detailsH = 0
            $taskListW = $totalWidth - $sidebarW
        }

        return @{
            Sidebar = @{ Width = $sidebarW; Height = $sidebarH }
            TaskList = @{ Width = $taskListW; Height = $taskListH }
            Details = @{ Width = $detailsW; Height = $detailsH }
        }
    }

    # Get current column widths (for SmartEditor positioning)
    hidden [hashtable] GetColumnWidths() {
        return @{
            Sidebar = if ($this._currentDimensions) { $this._currentDimensions.Sidebar.Width } else { 20 }
            SidebarHeight = if ($this._currentDimensions) { $this._currentDimensions.Sidebar.Height } else { 0 }
            TaskList = if ($this._currentDimensions) { $this._currentDimensions.TaskList.Width } else { 35 }
            TaskListHeight = if ($this._currentDimensions) { $this._currentDimensions.TaskList.Height } else { 0 }
            Details = if ($this._currentDimensions) { $this._currentDimensions.Details.Width } else { 0 }
        }
    }

    hidden [hashtable]$_currentDimensions = $null

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

        # Get display projects and tasks (before calculating dimensions)
        # ... (project cache logic from existing code) ...
        if ($state.Version -ne $this._projectCache.Version) {
            $displayProjects = [System.Collections.ArrayList]::new()

            $this._tasksById = @{}
            if ($data.tasks) {
                foreach ($t in $data.tasks) {
                    $this._tasksById[$t.id] = $t
                }
            }

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
            $this._taskCache.Version = -1
        }

        $displayProjects = $this._projectCache.List

        # Get selected project and build task list
        $selectedProject = $null
        if ($data.projects -and $view.Selection.Sidebar -ge 0 -and $view.Selection.Sidebar -lt @($data.projects).Count) {
            $selectedProject = $data.projects[$view.Selection.Sidebar]
        }

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

        # Get display tasks with hierarchy
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

        # Calculate optimal dimensions based on content and Details visibility
        # Detect Editing State for resize
        # SIMPLER SOLUTION: Use IsInsertMode + FocusedPanel
        # This expands height for BOTH Add and Edit, but ensures space is always available.
        $isModeActive = if ($view.IsInsertMode) { $view.IsInsertMode } else { $false }

        $isAddingProject = ($isModeActive -and $view.FocusedPanel -eq 'Sidebar')
        $isAddingTask = ($isModeActive -and $view.FocusedPanel -eq 'TaskList')

        $isDetailsVisible = if ($view.ContainsKey('IsDetailsVisible')) { $view.IsDetailsVisible } else { $false }
        $dimensions = $this.CalculateOptimalDimensions($w, $h, $displayProjects.ToArray(), $displayTasks.ToArray(), $isDetailsVisible, $view.FocusedPanel, $isAddingProject, $isAddingTask)

        # Store for external access (SmartEditor positioning)
        $this._currentDimensions = $dimensions

        $sidebarW = $dimensions.Sidebar.Width
        $sidebarH = $dimensions.Sidebar.Height
        $taskListW = $dimensions.TaskList.Width
        $taskListH = $dimensions.TaskList.Height
        $detailsW = $dimensions.Details.Width
        $detailsH = $dimensions.Details.Height
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

        $this._sidebar.Render($engine, 0, 0, $sidebarW, $sidebarH, $displayProjects.ToArray(), $projectCols, $view.Selection.Sidebar, ($view.FocusedPanel -eq "Sidebar"), $null)

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

        # Calculate row heights for task list (based on wrapped text)
        $taskRowHeights = @()
        foreach ($t in $displayTasks) {
            $text = if ($t.ContainsKey('text')) { $t.text } else { "" }
            $textColWidth = $taskListW - 19  # 3+3+1+12 = 19 fixed columns
            $wrappedLines = $this.WrapText($text, $textColWidth)
            $taskRowHeights += $wrappedLines.Count
        }

        $taskCols = @(
            @{ Header = "S"; Field = "status"; Width = 3 },
            @{ Header = "P"; Field = "prio"; Width = 3 },
            @{ Header = "Task / Tags"; Field = "text"; Width = $taskListW - 25 },
            @{ Header = "Due"; Field = "due"; Width = 12 }
        )

        $this._taskList.Render($engine, $sidebarW, 0, $taskListW, $taskListH, $displayTasks.ToArray(), $taskCols, $view.Selection.TaskList, ($view.FocusedPanel -eq "TaskList"), $taskRowHeights)

        # -- 3. Details Panel (Conditional) --
        if ($isDetailsVisible) {
            $selectedTask = $null
            if ($displayTasks -and $displayTasks.Count -gt 0 -and $view.Selection.TaskList -ge 0 -and $view.Selection.TaskList -lt $displayTasks.Count) {
                 $tId = $displayTasks[$view.Selection.TaskList].id
                 # OPTIMIZATION: O(1) lookup instead of O(N) Where-Object
                 $selectedTask = if ($this._tasksById.ContainsKey($tId)) { $this._tasksById[$tId] } else { $null }
            }

            # -- Notes Panel (Full Height - Status Bar) --
            $notesBorder = if ($view.FocusedPanel -eq "Details") { [Colors]::Accent } else { [Colors]::PanelBorder }
            $engine.DrawBox($detailsX, 0, $detailsW, $detailsH, $notesBorder, [Colors]::PanelBg)
            $engine.WriteAt($detailsX + 2, 0, " Notes ", [Colors]::Header, [Colors]::PanelBg)

            if ($selectedTask) {
                  $desc = if ($selectedTask.ContainsKey('description')) { $selectedTask['description'] } else { "(No notes. Press 'M' to add)" }
                  # Word wrap (simple)
                  $lines = $desc -split "`n"
                  $currentY = 1
                  foreach ($line in $lines) {
                      if ($currentY -ge $detailsH - 1) { break }
                      $maxLineLen = $detailsW - 4
                      if ($line.Length -gt $maxLineLen) { $line = $line.Substring(0, $maxLineLen) }
                      $engine.WriteAt($detailsX + 2, $currentY, $line, [Colors]::Foreground, [Colors]::PanelBg)
                      $currentY++
                  }
            } elseif ($selectedProject) {
                  $desc = if ($selectedProject.ContainsKey('description')) { $selectedProject['description'] } else { "(No project notes)" }
                  $engine.WriteAt($detailsX + 2, 1, $desc, [Colors]::Foreground, [Colors]::PanelBg)
            }
        }

        # Status bar is rendered by TuiApp's StatusBar component

        } catch {
            [Logger]::Error("Dashboard.Render CRASH", $_.Exception)
            throw
        }
    }
    }
