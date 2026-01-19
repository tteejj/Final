# TuiApp.ps1 - Main application loop and input handling
using namespace System.Management.Automation

class TuiApp {
    hidden [HybridRenderEngine]$_engine
    hidden [FluxStore]$_store
    hidden [Dashboard]$_dashboard
    hidden [WeeklyView]$_weeklyView
    hidden [SmartEditor]$_smartEditor
    hidden [ProjectInfoModal]$_projectInfoModal
    hidden [TimeModal]$_timeModal
    hidden [OverviewModal]$_overviewModal
    hidden [NotesModal]$_globalNotesModal
    hidden [ChecklistsModal]$_globalChecklistsModal
    hidden [CommandPalette]$_commandPalette
    hidden [ThemePicker]$_themePicker
    hidden [StatusBar]$_statusBar
    hidden [bool]$_wasModalVisible = $false
    hidden [bool]$_running
    
    TuiApp([HybridRenderEngine]$engine, [FluxStore]$store) {
        $this._engine = $engine
        $this._store = $store
        $this._dashboard = [Dashboard]::new()
        $this._weeklyView = [WeeklyView]::new()
        $this._smartEditor = [SmartEditor]::new()
        $this._projectInfoModal = [ProjectInfoModal]::new($store)
        $this._timeModal = [TimeModal]::new($store)
        $this._overviewModal = [OverviewModal]::new($store)
        $this._globalNotesModal = [NotesModal]::new($store)
        $this._globalChecklistsModal = [ChecklistsModal]::new($store)
        $this._commandPalette = [CommandPalette]::new()
        $this._themePicker = [ThemePicker]::new()
        $this._statusBar = [StatusBar]::new()
        $this._running = $false
    }
    
    # Helper to get flattened task list using shared TaskHierarchy utility
    hidden [System.Collections.ArrayList] _GetFlattenedTasks([hashtable]$state) {
        if (-not $state.Data.projects -or $state.View.Selection.Sidebar -ge @($state.Data.projects).Count) {
            return [System.Collections.ArrayList]::new()
        }
        $projId = $state.Data.projects[$state.View.Selection.Sidebar]['id']
        $filteredTasks = @()
        if ($state.Data.tasks) {
            $filteredTasks = @($state.Data.tasks | Where-Object { $_.projectId -eq $projId })
        }
        return [TaskHierarchy]::FlattenTasks($filteredTasks, $state.View)
    }
    
    # Helper to get original task at selection index
    hidden [hashtable] _GetSelectedTask([hashtable]$state) {
        $displayTasks = $this._GetFlattenedTasks($state)
        return [TaskHierarchy]::GetTaskAtIndex($displayTasks, $state.View.Selection.TaskList)
    }
    
    [void] Run() {
        $this._engine.Initialize()
        $this._running = $true
        
        # Performance: Only redraw if state changes
        $lastVersion = -1
        
        # Pre-load projects for autocomplete
        $this._smartEditor.LoadProjects($this._store.GetState().Data.projects)
        
        while ($this._running) {
            # DEBUG: Log every tick to ensure it's alive (optional, remove later if spammy)
            # "DEBUG: Loop Tick" | Out-File "/tmp/tui_tick.log" -Append

            # 1. Process Input (Non-blocking)
            if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    $this._HandleInput($key)
            }
            
            # 2. Render
            $state = $this._store.GetState()
            
            # Force render if in edit mode, view changed, or modal visible
            $modalVisible = $this._projectInfoModal.IsVisible() -or $this._timeModal.IsVisible() -or $this._overviewModal.IsVisible() -or $this._globalNotesModal.IsVisible() -or $this._globalChecklistsModal.IsVisible() -or $this._commandPalette.IsVisible() -or $this._themePicker.IsVisible()
            
            # Detect if a modal just closed (State transition from Visible -> Not Visible)
            $modalJustClosed = $this._wasModalVisible -and -not $modalVisible
            $modalJustOpened = -not $this._wasModalVisible -and $modalVisible
            if ($modalJustClosed -or $modalJustOpened) {
                $this._engine.RequestClear()
            }
            $this._wasModalVisible = $modalVisible
            
            $needsRender = $state.View.Editing -or $state.Version -ne $lastVersion -or $modalVisible -or $modalJustClosed
            
            if ($needsRender) {
                $this._engine.BeginFrame()
                
                # Render View - SKIP when modal visible to prevent ghost text
                if (-not $modalVisible) {
                    if ($state.View.CurrentView -eq "WeeklyReport") {
                        $this._weeklyView.Render($this._engine, $state)
                    } else {
                        $this._dashboard.Render($this._engine, $state)
                    }
                }
                
                # Render SmartEditor Overlay if active
                if ($state.View.Editing) {
                    $this._smartEditor.Render($this._engine)
                }
                
                # Render modals (in z-order)
                if ($this._projectInfoModal.IsVisible()) {
                    $this._projectInfoModal.Render($this._engine)
                }
                if ($this._timeModal.IsVisible()) {
                    $this._timeModal.Render($this._engine)
                }
                if ($this._overviewModal.IsVisible()) {
                    $this._overviewModal.Render($this._engine)
                }
                if ($this._globalNotesModal.IsVisible()) {
                    $this._globalNotesModal.Render($this._engine)
                }
                if ($this._globalChecklistsModal.IsVisible()) {
                    $this._globalChecklistsModal.Render($this._engine)
                }
                if ($this._commandPalette.IsVisible()) {
                    $this._commandPalette.Render($this._engine)
                }
                if ($this._themePicker.IsVisible()) {
                    $this._themePicker.Render($this._engine)
                }
                
                # Render dynamic status bar - ONLY if no modal is open
                if (-not $modalVisible) {
                    $context = $this._GetStatusContext($state)
                    $this._statusBar.Render($this._engine, $context)
                }
                
                $this._engine.EndFrame()
                $lastVersion = $state.Version
            }
            
            # 3. Cap CPU
            Start-Sleep -Milliseconds 16 # ~60 FPS
        }
        
        $this._engine.Cleanup()
    }
    
    hidden [void] _HandleInput([ConsoleKeyInfo]$key) {
        $state = $this._store.GetState()

        # === EDIT MODE HANDLER (HIGHEST PRIORITY) ===
        if ($state.View.Editing) {
            $result = $this._smartEditor.HandleInput($key)
            
            if ($result -eq "Save") {
                $values = $this._smartEditor.GetValues()
                $editInfo = $state.View.Editing
                
                # MERGE UI values with Hidden values from editInfo context
                if ($editInfo.Values) {
                    foreach ($k in $editInfo.Values.Keys) {
                        if (-not $values.ContainsKey($k)) {
                            $values[$k] = $editInfo.Values[$k]
                        }
                    }
                }
                
                if ($editInfo.RowId -eq "NEW") {
                    # Create New
                    $this._store.Dispatch([ActionType]::ADD_ITEM, @{
                        Type = $editInfo.Type
                        Data = $values
                    })
                } else {
                    # Update Existing
                    $this._store.Dispatch([ActionType]::UPDATE_ITEM, @{
                        Type = $editInfo.Type
                        Id = $editInfo.RowId
                        Changes = $values
                    })
                }
                $this._store.Dispatch([ActionType]::CANCEL_EDIT, @{})
            }
            elseif ($result -eq "Cancel") {
                $this._store.Dispatch([ActionType]::CANCEL_EDIT, @{})
            }
            return
        }
        
        # === THEME PICKER HANDLER ===
        if ($this._themePicker.IsVisible()) {
            $result = $this._themePicker.HandleInput($key)
            if ($result -eq "Restart") {
                # Save all data first
                $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
                # Request restart
                $this._running = $false
                $global:PmcRestartRequested = $true
            }
            return
        }
        
        # === COMMAND PALETTE HANDLER (TOP PRIORITY MODAL) ===
        if ($this._commandPalette.IsVisible()) {
            $result = $this._commandPalette.HandleInput($key)
            if ($result.Action -eq "Execute") {
                $cmd = $result.Command
                # Actually execute the command by simulating key
                $this._ExecuteCommandKey($cmd.Key)
            }
            return
        }
        
        # === GLOBAL CHECKLISTS MODAL HANDLER ===
        if ($this._globalChecklistsModal.IsVisible()) {
            $result = $this._globalChecklistsModal.HandleInput($key)
            if ($result -eq "Close") {
                $this._store.Dispatch([ActionType]::SET_FOCUS, @{ PanelName = $state.View.FocusedPanel })
            }
            return
        }

        # === GLOBAL NOTES MODAL HANDLER ===
        if ($this._globalNotesModal.IsVisible()) {
            $result = $this._globalNotesModal.HandleInput($key, $this._engine)
            if ($result -eq "Close") {
                $this._store.Dispatch([ActionType]::SET_FOCUS, @{ PanelName = $state.View.FocusedPanel })
            }
            return
        }
        
        # === OVERVIEW MODAL HANDLER ===
        if ($this._overviewModal.IsVisible()) {
            $result = $this._overviewModal.HandleInput($key)
            if ($result -eq "Close") {
                $this._store.Dispatch([ActionType]::SET_FOCUS, @{ PanelName = $state.View.FocusedPanel })
            }
            return
        }
        
        # === TIME MODAL HANDLER ===
        if ($this._timeModal.IsVisible()) {
            $result = $this._timeModal.HandleInput($key)
            if ($result -eq "Close") {
                $this._store.Dispatch([ActionType]::SET_FOCUS, @{ PanelName = $state.View.FocusedPanel })
            }
            return
        }
        # === INPUT DEBUGGING ===
        # [Logger]::Log("Key: $($key.Key) KeyChar: '$($key.KeyChar)' Mod: $($key.Modifiers)", 1)
        
        # === GLOBAL SHORTCUTS ===
        # Global Notes (H)
        if ($key.Key -eq 'H') {
             [Logger]::Log("Global Shortcut: H (Notes) Detected", 2)
             try {
                 $this._globalNotesModal.Open("GLOBAL_NOTES", "General Notes")
             } catch {
                 [Logger]::Error("Failed to open Global Notes", $_)
             }
             return
        }
        
        # Global Checklists (K)
        if ($key.Key -eq 'K') {
             [Logger]::Log("Global Shortcut: K (Checklists) Detected", 2)
             try {
                 $this._globalChecklistsModal.Open("GLOBAL_CHECKLISTS", "Global Checklists")
             } catch {
                 [Logger]::Error("Failed to open Global Checklists", $_)
             }
             return
        }
        
        # Global Time (L) - Non-project time logging
        if ($key.Key -eq 'L') {
             [Logger]::Log("Global Shortcut: L (General Time) Detected", 2)
             try {
                 $this._timeModal.Open("", "General Time")
             } catch {
                 [Logger]::Error("Failed to open General Time Modal", $_)
             }
             return
        }
        
        # Theme Picker (0)
        if ($key.KeyChar -eq '0') {
             [Logger]::Log("Global Shortcut: 0 (Theme Picker) Detected", 2)
             $this._themePicker.Open()
             return
        }
        
        # Command Palette (?)
        if ($key.KeyChar -eq '?') {
             [Logger]::Log("Global Shortcut: ? (Command Palette) Detected", 2)
             $context = $state.View.FocusedPanel
             $this._commandPalette.Open($context)
             return
        }
        
        # === PROJECT INFO MODAL HANDLER ===
        if ($this._projectInfoModal.IsVisible()) {
            $result = $this._projectInfoModal.HandleInput($key)
            if ($result -eq "Close") {
                # Modal closed, force refresh
                $this._store.Dispatch([ActionType]::SET_FOCUS, @{ PanelName = $state.View.FocusedPanel })
            }
            return
        }
        

        
        # === WEEKLY VIEW HANDLER ===
        if ($state.View.CurrentView -eq "WeeklyReport") {
            $handled = $this._weeklyView.HandleInput($key)
            if (-not $handled) {
                # Exit view on Escape (handled returns false)
                $this._store.Dispatch([ActionType]::SET_VIEW, @{ ViewName = "Dashboard" })
            }
            return
        }
        
        # === STANDARD MODE HANDLER ===
        $panel = $state.View.FocusedPanel
        
        switch ($key.Key) {
            'Q' { $this._running = $false }
            'W' { $this._store.Dispatch([ActionType]::SET_VIEW, @{ ViewName = "WeeklyReport" }) }
            'V' {
                # Open ProjectInfo modal for selected project
                if ($panel -eq "Sidebar" -and $state.Data.projects.Count -gt 0) {
                    $proj = $state.Data.projects[$state.View.Selection.Sidebar]
                    if ($proj) {
                        $this._projectInfoModal.Open($proj)
                    }
                }
            }
            'T' {
                # Open Time modal for selected project
                if ($panel -eq "Sidebar" -and $state.Data.projects.Count -gt 0) {
                    $proj = $state.Data.projects[$state.View.Selection.Sidebar]
                    if ($proj) {
                        $this._timeModal.Open($proj['id'], $proj['name'])
                    }
                }
            }
            'O' {
                # Open Overview modal
                $this._overviewModal.Open()
            }
            'Tab' {
                # Switch Panel Focus
                if ($key.Modifiers -band [ConsoleModifiers]::Shift) {
                     $this._store.Dispatch([ActionType]::PREV_PANEL, @{})
                } else {
                     $this._store.Dispatch([ActionType]::NEXT_PANEL, @{})
                }
            }
            'LeftArrow' {
                if ($panel -eq "Sidebar") {
                    # No left panel
                } elseif ($panel -eq "TaskList") {
                    $this._store.Dispatch([ActionType]::SET_FOCUS, @{ PanelName = "Sidebar" })
                } elseif ($panel -eq "Details") {
                    $this._store.Dispatch([ActionType]::SET_FOCUS, @{ PanelName = "TaskList" })
                }
            }
            'RightArrow' {
                 if ($panel -eq "Sidebar") {
                    $this._store.Dispatch([ActionType]::SET_FOCUS, @{ PanelName = "TaskList" })
                } elseif ($panel -eq "TaskList") {
                    $this._store.Dispatch([ActionType]::SET_FOCUS, @{ PanelName = "Details" })
                }
            }
            'UpArrow' {
                $currIdx = $state.View.Selection[$panel]
                if ($currIdx -gt 0) {
                    $this._store.Dispatch([ActionType]::SET_SELECTION, @{ PanelName = $panel; Index = $currIdx - 1 })
                }
            }
            'DownArrow' {
                $currIdx = $state.View.Selection[$panel]
                # Bound check based on actual data
                $max = 0
                if ($panel -eq "Sidebar") { 
                    $max = $state.Data.projects.Count 
                }
                elseif ($panel -eq "TaskList") { 
                    $displayTasks = $this._GetFlattenedTasks($state)
                    $max = $displayTasks.Count
                }
                
                if ($currIdx -lt ($max - 1)) {
                    $this._store.Dispatch([ActionType]::SET_SELECTION, @{ PanelName = $panel; Index = $currIdx + 1 })
                }
            }
            'S' {
                if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                    $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
                    $this._statusBar.ShowMessage("Saved successfully", "Success")
                } elseif ($panel -eq "TaskList") {
                    # New Subtask
                    $projId = $state.Data.projects[$state.View.Selection.Sidebar]['id']
                    $parentId = ""
                    $parentTask = $this._GetSelectedTask($state)
                    if ($parentTask) {
                        $parentId = $parentTask['id']
                    }
                    
                    $fields = @(
                        @{ Name="text"; Label=""; Type="Text"; Width=40 }
                        @{ Name="due"; Label="Due"; Type="Date"; Value=(Get-Date).AddDays(1).ToString("yyyy-MM-dd"); Width=10 }
                        # Status/Prio defaults handled silently
                    )
                    
                    # Calculate visual Y position for Inline Input
                    # Dashboard renders TaskList Header at Y=0 relative to top. 
                    # Row 0 is at Y=1.
                    # So Input for Row 0 should be at Y=2.
                    # Base Y = 2 (Header(1) + TopPadding(1?)). Let's try Base=2.
                    $listBaseY = 2 
                    $scrollOffset = $this._dashboard.GetTaskListScrollOffset()
                    $visualRow = $state.View.Selection.TaskList - $scrollOffset
                    
                    # Ensure positive visual row
                    if ($visualRow -lt 0) { $visualRow = 0 }
                    
                    # Place input ONE line below the selected task
                    $inputY = $listBaseY + $visualRow + 1
                    
                    # Clamp to screen height (minus help bar)
                    $inputY = [Math]::Min($this._engine.Height - 5, $inputY)
                    
                    # Align X with Task Text Column
                    # Sidebar Width + Status(3+1) + Prio(3+1) = Sidebar + 8.
                    # Let's use Sidebar + 9 to be safe and indent slightly? universal list spacing is +1.
                    # Col1(3) -> +1 -> Col2(3) -> +1 -> Col3(Text).
                    # Total offset = 3+1+3+1 = 8 relative to sidebar.
                    $sidebarW = [int]($this._engine.Width * 0.30)
                    $inputX = $sidebarW + 9
                    
                    $this._smartEditor.Configure($fields, $inputX, $inputY)
                    $values = @{ projectId=$projId }
                    if ($parentId) { $values['parent_id'] = $parentId }
                    
                    $this._store.Dispatch([ActionType]::START_EDIT, @{ RowId="NEW"; Type="tasks"; Values=$values })
                }
            }
            'O' {
                # Open Linked File (T2020)
                if ($panel -eq "Sidebar") {
                    $proj = $state.Data.projects[$state.View.Selection.Sidebar]
                    if ($proj -and $proj.ContainsKey('T2020') -and $proj.T2020 -and (Test-Path $proj.T2020)) {
                        # Open with default app
                        Start-Process $proj.T2020
                    } else {
                        $this._statusBar.ShowMessage("No T2020 file found", "Error")
                    }
                }
            }
            'M' {
                # Edit Memo/Notes (Description) using NoteEditor (Multiline)
                # Redirect 'M' to the specific handlers below.
                # Keeping this block for backward compat or specific 'M' key usage.
                # Logic merged into Enter/M handling below.
            }
            'F' {
               if ($panel -eq "Sidebar") {
                    $proj = $state.Data.projects[$state.View.Selection.Sidebar]
                    if ($proj -and $proj.ContainsKey('T2020') -and $proj.T2020) {
                         $path = $proj.T2020
                         if (Test-Path $path) {
                             if ((Get-Item $path) -is [System.IO.FileInfo]) {
                                 $path = Split-Path $path -Parent
                             }
                             Start-Process $path
                         }
                    } else {
                        $this._statusBar.ShowMessage("No T2020 folder found", "Error")
                    }
               }
            }
            'Enter' {
                # CRUD: Toggle completion if on TaskList
                if ($panel -eq "TaskList") {
                    $task = $this._GetSelectedTask($state)
                    if ($task) {
                        $this._store.Dispatch([ActionType]::UPDATE_ITEM, @{ 
                            Type = "tasks"; 
                            Id = $task['id']; 
                            Changes = @{ completed = -not $task['completed']; status = if ($task['completed']) { "todo" } else { "completed" } } 
                        })
                    }
                }
                # Edit Notes if on Details or Sidebar
                elseif ($panel -eq "Details" -or ($panel -eq "Sidebar" -and $key.Modifiers -band [ConsoleModifiers]::Alt)) {
                    # Determine context
                    $desc = ""
                    $title = ""
                    $targetId = ""
                    $type = ""
                    
                    if ($state.View.FocusedPanel -eq "Details") {
                        # Usually context is selected task
                        $task = $this._GetSelectedTask($state)
                        if ($task) {
                            $targetId = $task['id']
                            $type = "tasks"
                            $desc = if ($task.ContainsKey('description')) { $task['description'] } else { "" }
                            $title = $task['text']
                        } elseif ($state.View.Selection.Sidebar -ge 0) {
                            # Fallback to project description
                            $proj = $state.Data.projects[$state.View.Selection.Sidebar]
                            $targetId = $proj['id']
                            $type = "projects"
                            $desc = $proj['description']
                            $title = $proj['name']
                        }
                    }
                    
                    if ($targetId) {
                         $editor = [NoteEditor]::new($desc)
                         
                         # Auto-Save Configuration
                         $autosaveDir = Join-Path (Get-Location) "autosave"
                         if (-not (Test-Path $autosaveDir)) { New-Item -ItemType Directory -Path $autosaveDir -Force | Out-Null }
                         $prefix = if ($type -eq "tasks") { "task" } else { "proj" }
                         $autosavePath = Join-Path $autosaveDir "${prefix}_${targetId}.bak"
                         
                         # Crash Recovery
                         if (Test-Path $autosavePath) {
                             try {
                                 $rec = Get-Content -Path $autosavePath -Raw -Encoding utf8
                                 if ($rec) { $editor = [NoteEditor]::new($rec) }
                             } catch {}
                         }
                         
                         $editor.SetAutoSavePath($autosavePath)
                         $newDesc = $editor.RenderAndEdit($this._engine, $title)
                         
                         if ($newDesc -ne $null) {
                             $this._store.Dispatch([ActionType]::UPDATE_ITEM, @{
                                 Type = $type; Id = $targetId; Changes = @{ description = $newDesc }
                             })
                             # Cleanup
                             if (Test-Path $autosavePath) { Remove-Item $autosavePath -Force -ErrorAction SilentlyContinue }
                         }
                    }
                }
            }
            'T' {
                # Timer Toggle
                if ($panel -eq "TaskList") {
                    $task = $this._GetSelectedTask($state)
                    if ($task) {
                        if ($state.View.ActiveTimer -and $state.View.ActiveTimer.TaskId -eq $task['id']) {
                            $this._store.Dispatch([ActionType]::STOP_TIMER, @{})
                        } else {
                            if ($state.View.ActiveTimer) {
                                # Stop previous first
                                $this._store.Dispatch([ActionType]::STOP_TIMER, @{})
                            }
                            $this._store.Dispatch([ActionType]::START_TIMER, @{ TaskId = $task['id'] })
                        }
                    }
                }
            }
            'M' {
                # Edit Memo/Notes (Description) using NoteEditor (Multiline)
                if ($panel -eq "TaskList") {
                    $task = $this._GetSelectedTask($state)
                    if ($task) {
                        $desc = if ($task.ContainsKey('description')) { $task['description'] } else { "" }
                        $text = if ($task.ContainsKey('text')) { $task['text'] } else { "" }
                        $editor = [NoteEditor]::new($desc)
                        
                        # Auto-Save Configuration
                        $autosaveDir = Join-Path (Get-Location) "autosave"
                        if (-not (Test-Path $autosaveDir)) { New-Item -ItemType Directory -Path $autosaveDir -Force | Out-Null }
                        $autosavePath = Join-Path $autosaveDir "task_$($task['id']).bak"
                        
                        if (Test-Path $autosavePath) {
                             try {
                                 $rec = Get-Content -Path $autosavePath -Raw -Encoding utf8
                                 if ($rec) { $editor = [NoteEditor]::new($rec) }
                             } catch {}
                        }
                        $editor.SetAutoSavePath($autosavePath)
                        
                        $newDesc = $editor.RenderAndEdit($this._engine, $text)
                        
                        if ($newDesc -ne $null) {
                            $this._store.Dispatch([ActionType]::UPDATE_ITEM, @{
                                Type = "tasks"; Id = $task['id']; Changes = @{ description = $newDesc }
                            })
                            if (Test-Path $autosavePath) { Remove-Item $autosavePath -Force -ErrorAction SilentlyContinue }
                        }
                    }
                }
                elseif ($panel -eq "Sidebar") {
                    $proj = $state.Data.projects[$state.View.Selection.Sidebar]
                    if ($proj) {
                        $editor = [NoteEditor]::new($proj.description)
                        $newDesc = $editor.RenderAndEdit($this._engine, $proj.name)
                        if ($newDesc -ne $null) {
                            $this._store.Dispatch([ActionType]::UPDATE_ITEM, @{
                                Type = "projects"; Id = $proj['id']; Changes = @{ description = $newDesc }
                            })
                        }
                    }
                }
            }
            'N' {
                # New Item - Using SmartEditor
                if ($panel -eq "Sidebar") {
                    # New Project - Name Only (Inline)
                    $sidebarW = [int]($this._engine.Width * 0.30)
                    $safeWidth = [Math]::Max(10, $sidebarW - 4)
                    
                    $fields = @(
                        @{ Name="name"; Label="Project Name"; Type="Text"; Width=$safeWidth }
                        # Status/Desc default to active/empty automatically
                    )
                    
                    # Caculate Y position: Header(2) + Count + Padding
                    $listY = 3
                    $projCount = if ($state.Data.projects) { $state.Data.projects.Count } else { 0 }
                    $inputY = [Math]::Min($this._engine.Height - 5, $listY + $projCount)
                    
                    $this._smartEditor.Configure($fields, 2, $inputY)
                    $this._store.Dispatch([ActionType]::START_EDIT, @{ RowId="NEW"; Type="projects"; Values=@{ status="active"; description="" } })
                }
                elseif ($panel -eq "TaskList") {
                    # New Task
                    $projId = $state.Data.projects[$state.View.Selection.Sidebar]['id']
                    
                    # Normal New Task (Top Level)
                    # Subtasks are now handled by 'S'
                    
                    $fields = @(
                        @{ Name="text"; Label=""; Type="Text"; Width=40 }
                        @{ Name="due"; Label="Due"; Type="Date"; Value=(Get-Date).AddDays(1).ToString("yyyy-MM-dd"); Width=10 }
                    )
                    
                    # Align X with Task Text Column
                    $sidebarW = [int]($this._engine.Width * 0.30)
                    $inputX = $sidebarW + 9
                    
                    $this._smartEditor.Configure($fields, $inputX, $this._engine.Height - 5)
                    # Pass projectId only (Top Level)
                    # Include defaults for S/P/Due
                    $defaults = @{ projectId=$projId; status="todo"; priority=1; due=(Get-Date).AddDays(1).ToString("yyyy-MM-dd") }
                    $this._store.Dispatch([ActionType]::START_EDIT, @{ RowId="NEW"; Type="tasks"; Values=$defaults })
                }
                elseif ($panel -eq "Details") {
                    # New Timelog
                    $fields = @(
                        @{ Name="date"; Label="Date"; Type="Date"; Value=(Get-Date).ToString("yyyy-MM-dd"); Width=12 }
                        @{ Name="minutes"; Label="Mins"; Type="Number"; Value=30; Width=5 }
                        @{ Name="id1"; Label="ID1"; Type="Text"; Width=8 }
                        @{ Name="id2"; Label="ID2"; Type="Text"; Width=8 }
                    )
                    $projId = $state.Data.projects[$state.View.Selection.Sidebar]['id']
                    $this._smartEditor.Configure($fields, 60, $this._engine.Height - 5)
                    $this._store.Dispatch([ActionType]::START_EDIT, @{ RowId="NEW"; Type="timelogs"; Values=@{ projectId=$projId } })
                }
            }
            'E' {
                # Edit Item - Using SmartEditor
                if ($panel -eq "TaskList") {
                    $task = $this._GetSelectedTask($state)
                    if ($task) {
                        $fields = @(
                            @{ Name="status"; Label="S"; Type="Text"; Value=$task['status']; Width=5 }
                            @{ Name="priority"; Label="P"; Type="Number"; Value=$task['priority']; Width=3 }
                            @{ Name="text"; Label="Task"; Type="Text"; Value=$task['text']; Width=40 }
                            @{ Name="due"; Label="Due"; Type="Date"; Value=$task['due']; Width=12 }
                            @{ Name="tags"; Label="Tags"; Type="Text"; Value=$(if ($task.ContainsKey('tags') -and $task['tags']) { $task['tags'] -join ", " } else { "" }); Width=20 }
                        )
                        $this._smartEditor.Configure($fields, 30, $this._engine.Height - 5)
                        $this._store.Dispatch([ActionType]::START_EDIT, @{ RowId=$task['id']; Type="tasks"; Values=@{} })
                    }
                }
            }
            'Delete' {
                # Delete Item
                if ($panel -eq "Sidebar") {
                    $proj = $state.Data.projects[$state.View.Selection.Sidebar]
                    # Confirmation? For now just do it.
                    if ($proj) {
                        $this._store.Dispatch([ActionType]::DELETE_ITEM, @{ Type = "projects"; Id = $proj['id'] })
                        # Reset selection
                        $this._store.Dispatch([ActionType]::SET_SELECTION, @{ PanelName = "Sidebar"; Index = 0 })
                    }
                }
                elseif ($panel -eq "TaskList") {
                    $task = $this._GetSelectedTask($state)
                    if ($task) {
                        $this._store.Dispatch([ActionType]::DELETE_ITEM, @{ Type = "tasks"; Id = $task['id'] })
                        $this._store.Dispatch([ActionType]::SET_SELECTION, @{ PanelName = "TaskList"; Index = 0 })
                    }
                }
            }
        }
    }
    
    hidden [string] _GetStatusContext([hashtable]$state) {
        # Determine context for status bar
        if ($this._overviewModal.IsVisible()) { return "OverviewModal" }
        if ($this._timeModal.IsVisible()) {
            $tab = $this._timeModal._activeTab
            if ($tab -eq 1) { return "TimeModal.Weekly" } else { return "TimeModal.Entries" }
        }
        if ($this._projectInfoModal.IsVisible()) { return "ProjectInfoModal" }
        if ($state.View.Editing) { return "Editing" }
        
        return "Dashboard.$($state.View.FocusedPanel)"
    }
    
    # Execute a command from the command palette by key string
    hidden [void] _ExecuteCommandKey([string]$keyStr) {
        $state = $this._store.GetState()
        
        switch ($keyStr) {
            "Q" { $this._running = $false }
            "H" { $this._globalNotesModal.Open("GLOBAL_NOTES", "General Notes") }
            "K" { $this._globalChecklistsModal.Open("GLOBAL_CHECKLISTS", "Global Checklists") }
            "L" { $this._timeModal.Open("", "General Time") }
            "O" { $this._overviewModal.Open() }
            "W" { $this._store.Dispatch([ActionType]::SET_VIEW, @{ ViewName = "WeeklyReport" }) }
            "?" { $this._commandPalette.Open($state.View.FocusedPanel) }
            "0" { $this._themePicker.Open() }
            "V" {
                if ($state.View.FocusedPanel -eq "Sidebar" -and $state.Data.projects.Count -gt 0) {
                    $proj = $state.Data.projects[$state.View.Selection.Sidebar]
                    if ($proj) { $this._projectInfoModal.Open($proj) }
                }
            }
            "T" {
                if ($state.Data.projects.Count -gt 0) {
                    $proj = $state.Data.projects[$state.View.Selection.Sidebar]
                    # If All Projects (virtual) is selected? (Need to check if Selection.Sidebar yields a valid project)
                    # Assuming Selection.Sidebar is an index into state.Data.projects
                    if ($proj) { $this._timeModal.Open($proj['id'], $proj['name']) }
                }
            }
            "Ctrl+S" { 
                $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
                $this._statusBar.ShowMessage("Saved successfully", "Success")
            }
            default {
                $this._statusBar.ShowMessage("Command '$keyStr' - use key directly", "Info")
            }
        }
    }
}

