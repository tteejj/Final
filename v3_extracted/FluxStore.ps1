# FluxStore.ps1 - The central state and dispatch engine
using namespace System.Collections.Generic

class FluxStore {
    hidden [hashtable]$_state
    hidden [List[scriptblock]]$_subscribers
    hidden [object]$_dataService
    hidden [hashtable]$_indexes = @{ tasks = @{}; projects = @{}; timelogs = @{} }

    FluxStore([object]$dataService) {
        $this._dataService = $dataService
        $this._subscribers = [List[scriptblock]]::new()

        # Initial State
        $this._state = @{
            Data = $this._dataService.LoadData()
            View = @{
                CurrentView = "Dashboard"
                FocusedPanel = "Sidebar"
                Selection = @{
                    Sidebar = 0
                    TaskList = 0
                    Details = 0
                }
                IsInsertMode = $false
                StatusMessage = "Ready"
                ActiveTimer = $null
                Editing = $null # @{ RowId="..."; Values=@{...}; IsActive=$true }
                ZoomedPanel = $null # "Sidebar", "TaskList", "Details"
                IsDetailsVisible = $false # NEW: Track if details panel is shown
            }
            Version = 0
        }

        # OPTIMIZATION: Build indexes for O(1) lookups
        $this._BuildIndexes()
    }

    hidden [void] _BuildIndexes() {
        $this._indexes = @{ tasks = @{}; projects = @{}; timelogs = @{} }

        @('tasks', 'projects', 'timelogs') | ForEach-Object {
            $type = $_
            if ($this._state.Data[$type]) {
                foreach ($item in $this._state.Data[$type]) {
                    if ($item.ContainsKey('id')) {
                        $this._indexes[$type][$item.id] = $item
                    }
                }
            }
        }
    }

    [hashtable] GetState() {
        return $this._state
    }

    [void] Subscribe([scriptblock]$callback) {
        $this._subscribers.Add($callback)
    }

    [void] Dispatch([ActionType]$actionType, [hashtable]$payload) {
        # High-verbosity logging
        $payloadSummary = ""
        if ($payload) {
            $payloadSummary = " | PayloadKeys=$($payload.Keys -join ',')"
        }
        [Logger]::Log("FluxStore.Dispatch: Action=$actionType$payloadSummary", 3)

        $newState = $this._state
        $changed = $false
        $shouldSave = $false

        switch ($actionType) {
            ([ActionType]::TOGGLE_ZOOM) {
                if ($newState.View.ZoomedPanel) {
                    $newState.View.ZoomedPanel = $null
                } else {
                    $newState.View.ZoomedPanel = $newState.View.FocusedPanel
                }
                $changed = $true
            }

            ([ActionType]::START_EDIT) {
                $newState.View.Editing = @{
                    RowId = $payload.RowId
                    Type = $payload.Type # 'task', 'project'
                    Values = $payload.Values
                    IsActive = $true
                }
                $newState.View.IsInsertMode = $true
                $changed = $true
            }

            ([ActionType]::CANCEL_EDIT) {
                $newState.View.Editing = $null
                $newState.View.IsInsertMode = $false
                $changed = $true
            }

            ([ActionType]::ADD_ITEM) {
                $type = $payload.Type # projects, tasks, timelogs
                $item = $payload.Data
                $item.id = [DataService]::NewGuid()
                $item.created = [DataService]::Timestamp()
                $item.modified = $item.created

                $newState.Data[$type] += $item
                # OPTIMIZATION: Update index
                if ($this._indexes.ContainsKey($type)) {
                    $this._indexes[$type][$item.id] = $item
                }
                $changed = $true
                $shouldSave = $true
            }

            ([ActionType]::UPDATE_ITEM) {
                $type = $payload.Type
                $id = $payload.Id
                $changes = $payload.Changes

                # OPTIMIZATION: O(1) lookup instead of O(N) Where-Object
                $item = if ($this._indexes.ContainsKey($type) -and $this._indexes[$type].ContainsKey($id)) { $this._indexes[$type][$id] } else { $null }
                if ($item) {
                    foreach ($key in $changes.Keys) {
                        $item[$key] = $changes[$key]
                    }
                    $item.modified = [DataService]::Timestamp()
                    $changed = $true
                    $shouldSave = $true
                }
            }

            ([ActionType]::DELETE_ITEM) {
                $type = $payload.Type
                $id = $payload.Id
                # OPTIMIZATION: O(N) filter is still needed for array, but we can rebuild indexes
                $newState.Data[$type] = $newState.Data[$type] | Where-Object { $_.id -ne $id }
                # Update index
                if ($this._indexes.ContainsKey($type) -and $this._indexes[$type].ContainsKey($id)) {
                    [void]$this._indexes[$type].Remove($id)
                }
                $changed = $true
                $shouldSave = $true
            }

            ([ActionType]::UPDATE_SETTINGS) {
                 foreach ($key in $payload.Changes.Keys) {
                     $newState.Data.settings[$key] = $payload.Changes[$key]
                 }
                 $changed = $true
                 $shouldSave = $true
            }

            ([ActionType]::SAVE_DATA) {
                $this._dataService.SaveData($newState.Data)
                $newState.View.StatusMessage = "Saved at $(Get-Date -Format 'HH:mm:ss')"
            }

            ([ActionType]::SET_FOCUS) {
                $newState.View.FocusedPanel = $payload.PanelName
                $changed = $true
            }

            ([ActionType]::SET_VIEW) {
                $newState.View.CurrentView = $payload.ViewName
                $changed = $true
            }

            ([ActionType]::SET_SELECTION) {
                $panel = $payload.PanelName
                $newState.View.Selection[$panel] = $payload.Index
                $changed = $true
            }

            ([ActionType]::TOGGLE_MODE) {
                $newState.View.IsInsertMode = -not $newState.View.IsInsertMode
                $changed = $true
            }

            ([ActionType]::START_TIMER) {
                if ($null -eq $newState.View.ActiveTimer) {
                    $newState.View.ActiveTimer = @{
                        TaskId = $payload.TaskId
                        StartTime = (Get-Date)
                    }
                    $newState.View.StatusMessage = "Timer Started"
                    $changed = $true
                }
            }

            ([ActionType]::NEXT_PANEL) {
                $panels = @("Sidebar", "TaskList", "Details")
                $current = $newState.View.FocusedPanel
                $idx = $panels.IndexOf($current)
                $nextIdx = ($idx + 1) % $panels.Count
                $newState.View.FocusedPanel = $panels[$nextIdx]
                $changed = $true
            }

            ([ActionType]::PREV_PANEL) {
                $panels = @("Sidebar", "TaskList", "Details")
                $current = $newState.View.FocusedPanel
                $idx = $panels.IndexOf($current)
                $prevIdx = ($idx - 1 + $panels.Count) % $panels.Count
                $newState.View.FocusedPanel = $panels[$prevIdx]
                $changed = $true
            }

            ([ActionType]::TOGGLE_DETAILS) {
                $newState.View.IsDetailsVisible = -not $newState.View.IsDetailsVisible
                $changed = $true
            }

            ([ActionType]::STOP_TIMER) {
                if ($null -ne $newState.View.ActiveTimer) {
                    $start = $newState.View.ActiveTimer.StartTime
                    $end = (Get-Date)
                    $span = $end - $start
                    $mins = [Math]::Max(1, [int]$span.TotalMinutes)

                    # Find Task to get ProjectId
                    $taskId = $newState.View.ActiveTimer.TaskId
                    $task = $newState.Data.tasks | Where-Object { $_.id -eq $taskId }

                    if ($task) {
                        # Create Timelog
                        $log = @{
                            id = [DataService]::NewGuid()
                            projectId = $task.projectId
                            taskId = $taskId
                            minutes = $mins
                            created = [DataService]::Timestamp()
                            date = $end.ToString("yyyy-MM-ddTHH:mm:ss")
                        }
                        $newState.Data.timelogs += $log
                        $newState.View.StatusMessage = "Timer Stopped: ${mins}m recorded"
                    }

                    $newState.View.ActiveTimer = $null
                    $changed = $true
                    $shouldSave = $true
                }
            }
        }

        if ($shouldSave) {
            $this._dataService.SaveData($newState.Data)
            # Optional: Update status message? Or kept silent?
            # User wants it done. Silence is golden, or maybe a subtle indicator handled by UI.
            # But let's log it.
            [Logger]::Log("FluxStore.AutoSave: Data saved.", 3)
        }

        if ($changed) {
            $this._state.Version++
            # Notify subscribers
            foreach ($sub in $this._subscribers) {
                & $sub $this._state
            }
        }
    }
}
