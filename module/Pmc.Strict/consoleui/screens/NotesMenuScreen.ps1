# NotesMenuScreen.ps1 - List all notes with add/edit/delete capabilities
#
# Displays a list of all notes using StandardListScreen base class
# Allows creating new notes, editing existing notes, and deleting notes
#
# Usage:
#   $screen = New-Object NotesMenuScreen
#   $global:PmcApp.PushScreen($screen)

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"

class NotesMenuScreen : StandardListScreen {
    # === Configuration ===
    hidden [FileNoteService]$_noteService = $null
    hidden [string]$_ownerType = "global"
    hidden [string]$_ownerId = $null
    hidden [string]$_ownerName = ""

    # === Constructor ===
    # Legacy constructor (backward compatible)
    NotesMenuScreen() : base("NotesList", "Notes") {
        $this._InitializeScreen("global", $null, "")
    }

    # Container constructor
    NotesMenuScreen([object]$container) : base("NotesList", "Notes", $container) {
        $this._InitializeScreen("global", $null, "")
    }

    # Legacy constructor with owner parameters
    NotesMenuScreen([string]$ownerType, [string]$ownerId, [string]$ownerName) : base("NotesList", "Notes") {
        $this._InitializeScreen($ownerType, $ownerId, $ownerName)
    }

    # Container constructor with owner parameters
    NotesMenuScreen([string]$ownerType, [string]$ownerId, [string]$ownerName, [object]$container) : base("NotesList", "Notes", $container) {
        $this._InitializeScreen($ownerType, $ownerId, $ownerName)
    }

    hidden [void] _InitializeScreen([string]$ownerType, [string]$ownerId, [string]$ownerName) {
        $this._ownerType = $ownerType
        $this._ownerId = $ownerId
        $this._ownerName = $ownerName

        # Get note service instance
        $this._noteService = [FileNoteService]::GetInstance()

        # Subscribe to note changes
        # Note: Callback may be invoked when screen is not active, so check first
        $self = $this
        $this._noteService.OnNotesChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
                if ($self.List) {
                    $self.List.InvalidateCache()
                }
                if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                    $global:PmcApp.RequestRender()
                }
            }
        }.GetNewClosure()

        # Configure screen
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $true
        $this.AllowSearch = $true

        # Update screen title and breadcrumb based on owner
        if ($this._ownerType -ne "global") {
            $ownerLabel = $(if ($ownerType -eq "project") { "Project" } elseif ($ownerType -eq "task") { "Task" } else { "Global" })
            $this.ScreenTitle = "Notes - $ownerName"
            $this.Header.SetBreadcrumb(@($ownerLabel, $ownerName, "Notes"))
        }
    }

    # === Abstract Methods Implementation ===

    <#
    .SYNOPSIS
    Load notes data into the list
    #>
    [void] LoadData() {
        # Write-PmcTuiLog "NotesMenuScreen.LoadData: Loading notes for owner=$($this._ownerType):$($this._ownerId)" "INFO"

        try {
            # Get notes from service (filtered by owner if specified)
            if ($this._ownerType -eq "global" -or $null -eq $this._ownerId) {
                # Write-PmcTuiLog "NotesMenuScreen.LoadData: Getting all notes (global)" "INFO"
                $notes = $this._noteService.GetAllNotes()
            } else {
                # Write-PmcTuiLog "NotesMenuScreen.LoadData: Getting notes by owner type=$($this._ownerType) id=$($this._ownerId)" "INFO"
                $notes = $this._noteService.GetNotesByOwner($this._ownerType, $this._ownerId)
            }

            # Ensure we have an array
            if ($null -eq $notes) {
                $notes = @()
            } elseif ($notes -isnot [array]) {
                $notes = @($notes)
            }

            # Write-PmcTuiLog "NotesMenuScreen.LoadData: Loaded $($notes.Count) notes" "INFO"

            # Set data in list
            $this.List.SetData($notes)

        } catch {
            # Write-PmcTuiLog "NotesMenuScreen.LoadData: Error - $_" "ERROR"
            $this.List.SetData(@())
        }
    }

    <#
    .SYNOPSIS
    Define columns for the notes list
    #>
    [array] GetColumns() {
        return @(
            @{
                Name = 'title'
                Label = 'Title'
                Width = 40
                Sortable = $true
                Searchable = $true
            }
            @{
                Name = 'modified'
                Label = 'Modified'
                Width = 20
                Sortable = $true
                Formatter = {
                    param($value)
                    if ($value -is [datetime]) {
                        return $value.ToString("yyyy-MM-dd HH:mm")
                    }
                    return ""
                }
            }
            @{
                Name = 'line_count'
                Label = 'Lines'
                Width = 8
                Sortable = $true
                Align = 'right'
            }
            @{
                Name = 'word_count'
                Label = 'Words'
                Width = 8
                Sortable = $true
                Align = 'right'
            }
            @{
                Name = 'tags'
                Label = 'Tags'
                Width = 20
                Formatter = {
                    param($value)
                    if ($value -and $value.Count -gt 0) {
                        return ($value -join ", ")
                    }
                    return ""
                }
            }
        )
    }

    <#
    .SYNOPSIS
    Define fields for the add/edit inline editor
    #>
    [array] GetEditFields($item) {
        $title = ""
        $tags = ""

        if ($item) {
            if ($item -is [hashtable]) {
                $title = $(if ($item.ContainsKey('title')) { $item['title'] } else { "" })
                $tags = $(if ($item.ContainsKey('tags') -and $item['tags']) { ($item['tags'] -join ", ") } else { "" })
            } else {
                $title = $(if ($item.title) { $item.title } else { "" })
                $tags = $(if ($item.tags) { ($item.tags -join ", ") } else { "" })
            }
        }

        return @(
            @{
                Name = 'title'
                Type = 'text'
                Label = 'Title'
                Value = $title
                Required = $true
                MaxLength = 100
            }
            @{
                Name = 'tags'
                Type = 'text'
                Label = 'Tags (comma-separated)'
                Value = $tags
                Required = $false
                MaxLength = 200
            }
        )
    }

    # === Event Handlers ===

    <#
    .SYNOPSIS
    Handle item activation (Enter key) - open note editor
    #>
    [void] OnItemActivated($item) {
        # Get ID from item (handle both hashtable and object)
        $noteId = $null
        if ($item) {
            if ($item -is [hashtable]) {
                $noteId = $item['id']
            } else {
                $noteId = $item.id
            }
        }

        if ($noteId) {
            # Write-PmcTuiLog "NotesMenuScreen.OnItemActivated: Opening note $noteId" "INFO"

            # Load NoteEditorScreen
            $editorScreenPath = Join-Path $PSScriptRoot "NoteEditorScreen.ps1"
            # Write-PmcTuiLog "NotesMenuScreen.OnItemActivated: Editor path: $editorScreenPath" "DEBUG"

            if (Test-Path $editorScreenPath) {
                # Write-PmcTuiLog "NotesMenuScreen.OnItemActivated: Loading NoteEditorScreen.ps1" "DEBUG"
                . $editorScreenPath

                # Write-PmcTuiLog "NotesMenuScreen.OnItemActivated: Creating NoteEditorScreen instance" "DEBUG"
                $editorScreen = New-Object NoteEditorScreen -ArgumentList $noteId

                # Write-PmcTuiLog "NotesMenuScreen.OnItemActivated: Pushing screen to app" "DEBUG"
                $global:PmcApp.PushScreen($editorScreen)

                # Write-PmcTuiLog "NotesMenuScreen.OnItemActivated: Screen pushed successfully" "INFO"
            } else {
                # Write-PmcTuiLog "NotesMenuScreen.OnItemActivated: NoteEditorScreen.ps1 not found at $editorScreenPath" "ERROR"
            }
        } else {
            # Write-PmcTuiLog "NotesMenuScreen.OnItemActivated: No noteId found in item" "ERROR"
        }
    }

    <#
    .SYNOPSIS
    Handle add new note (called by StandardListScreen)
    #>
    [void] OnItemCreated([hashtable]$data) {
        $this.OnAddItem($data)
    }

    <#
    .SYNOPSIS
    Handle add new note
    #>
    [void] OnAddItem([hashtable]$data) {
        # SAVE FIX: Safe property access and validation
        $title = $(if ($data.ContainsKey('title')) { $data.title } else { '' })
        # Write-PmcTuiLog "NotesMenuScreen.OnAddItem: Creating note '$title'" "DEBUG"

        try {
            # Validate title
            if ([string]::IsNullOrWhiteSpace($title)) {
                $this.SetStatusMessage("Note title is required", "error")
                return
            }

            # Parse tags
            $tags = @()
            if ($data.ContainsKey('tags') -and -not [string]::IsNullOrWhiteSpace($data.tags)) {
                $tags = $data.tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }

            # Create note with owner info
            # Write-PmcTuiLog "NotesMenuScreen.OnAddItem: Calling CreateNote with title='$title' tags=$($tags.Count) owner=$($this._ownerType):$($this._ownerId)" "DEBUG"
            $note = $this._noteService.CreateNote($title, $tags, $this._ownerType, $this._ownerId)

            if ($null -eq $note) {
                # Write-PmcTuiLog "NotesMenuScreen.OnAddItem: CreateNote returned null!" "ERROR"
                return
            }

            # Success message
            $noteId = $(if ($note -is [hashtable]) { $note['id'] } else { $note.id })
            $this.SetStatusMessage("Note created: $title", "success")

            # CRITICAL FIX: DO NOT auto-open the note editor here!
            # When we push NoteEditorScreen, this screen becomes inactive (IsActive=false)
            # This prevents the FileNoteService.OnNotesChanged callback from refreshing the list
            # because it checks: if ($self.IsActive)
            # Instead, let the callback refresh the list, and let the user press Enter to open the note
            
            # Refresh list manually to ensure new note appears immediately
            # (The callback should also trigger, but this ensures immediate feedback)
            $this.LoadData()
            if ($this.List) {
                $this.List.InvalidateCache()
            }
            if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                $global:PmcApp.RequestRender()
            }

        } catch {
            # Write-PmcTuiLog "NotesMenuScreen.OnAddItem: Error - $_" "ERROR"
            # Write-PmcTuiLog "NotesMenuScreen.OnAddItem: Stack trace - $($_.ScriptStackTrace)" "ERROR"
        }
    }

    <#
    .SYNOPSIS
    Handle edit note metadata (called by StandardListScreen)
    #>
    [void] OnItemUpdated($item, [hashtable]$data) {
        $this.OnEditItem($item, $data)
    }

    <#
    .SYNOPSIS
    Handle edit note metadata
    #>
    [void] OnEditItem($item, [hashtable]$data) {
        Write-PmcTuiLog "========== OnEditItem START ==========" "INFO"
        
        # Get note ID from item
        $noteId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
        Write-PmcTuiLog "OnEditItem: noteId = $noteId" "INFO"
        
        if (-not $noteId) {
            Write-PmcTuiLog "OnEditItem: ERROR - No noteId!" "ERROR"
            $this.SetStatusMessage("Cannot edit note: ID not found", "error")
            return
        }

        try {
            # SAVE FIX: Safe property access and validation
            $title = $(if ($data.ContainsKey('title')) { $data.title } else { '' })
            Write-PmcTuiLog "OnEditItem: New title = '$title'" "INFO"
            
            # Validate title
            if ([string]::IsNullOrWhiteSpace($title)) {
                Write-PmcTuiLog "OnEditItem: ERROR - Title is empty!" "ERROR"
                $this.SetStatusMessage("Note title is required", "error")
                return
            }

            # Parse tags
            $tags = @()
            if ($data.ContainsKey('tags') -and -not [string]::IsNullOrWhiteSpace($data.tags)) {
                $tags = $data.tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }

            # Prepare changes hashtable
            $changes = @{
                title = $title
                tags = $tags
            }

            # Update note metadata (may rename file if title changed)
            Write-PmcTuiLog "OnEditItem: Calling UpdateNoteMetadata..." "DEBUG"
            $this._noteService.UpdateNoteMetadata($noteId, $changes)
            Write-PmcTuiLog "OnEditItem: UpdateNoteMetadata DONE" "DEBUG"
            
            $this.SetStatusMessage("Note updated: $title", "success")

            # CRITICAL: Explicitly reload and SET the data
            Write-PmcTuiLog "OnEditItem: Loading fresh data..." "DEBUG"
            $notes = $null
            if ($this._ownerType -eq "global" -or $null -eq $this._ownerId) {
                $notes = $this._noteService.GetAllNotes()
            } else {
                $notes = $this._noteService.GetNotesByOwner($this._ownerType, $this._ownerId)
            }
            
            Write-PmcTuiLog "OnEditItem: Loaded $($notes.Count) notes" "INFO"
            
            # Ensure array
            if ($null -eq $notes) { $notes = @() }
            elseif ($notes -isnot [array]) { $notes = @($notes) }
            
            # FORCE the list to take the new data
            if ($this.List) {
                Write-PmcTuiLog "OnEditItem: Calling SetData with $($notes.Count) notes..." "DEBUG"
                $this.List.SetData($notes)
                Write-PmcTuiLog "OnEditItem: SetData DONE" "DEBUG"
                
                Write-PmcTuiLog "OnEditItem: Invalidating cache..." "DEBUG"
                $this.List.InvalidateCache()
                Write-PmcTuiLog "OnEditItem: InvalidateCache DONE" "DEBUG"
                
                # Re-select renamed item by title
                if ($changes.title -ne $noteId) {
                    Write-PmcTuiLog "OnEditItem: Title changed, re-selecting item with title='$title'" "INFO"
                    $allItems = $this.List._filteredData
                    Write-PmcTuiLog "OnEditItem: Got $($allItems.Count) items from _filteredData" "DEBUG"
                    for ($i = 0; $i -lt $allItems.Count; $i++) {
                        $item = $allItems[$i]
                        $itemTitle = $(if ($item -is [hashtable]) { $item['title'] } else { $item.title })
                        if ($itemTitle -eq $title) {
                            Write-PmcTuiLog "OnEditItem: Found at index $i, selecting..." "DEBUG"
                            $this.List.SelectIndex($i)
                            break
                        }
                    }
                }
            } else {
                Write-PmcTuiLog "OnEditItem: ERROR - this.List is NULL!" "ERROR"
            }

            Write-PmcTuiLog "========== OnEditItem END ==========" "INFO"

        } catch {
            Write-PmcTuiLog "OnEditItem: EXCEPTION - $_" "ERROR"
            Write-PmcTuiLog "OnEditItem: Stack trace - $($_.ScriptStackTrace)" "ERROR"
            $this.SetStatusMessage("Failed to update note: $($_.Exception.Message)", "error")
        }
    }

    <#
    .SYNOPSIS
    Handle delete note (called by StandardListScreen)
    #>
    [void] OnItemDeleted($item) {
        # Get note ID from item
        $noteId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
        $noteTitle = $(if ($item -is [hashtable]) { $item['title'] } else { $item.title })
        
        if (-not $noteId) {
            $this.SetStatusMessage("Cannot delete note: ID not found", "error")
            return
        }

        try {
            # Delete the note
            $this._noteService.DeleteNote($noteId)
            $this.SetStatusMessage("Note deleted: $noteTitle", "success")

            # CRITICAL: Force full screen refresh after delete
            $this.NeedsClear = $true
            $this.LoadData()
            if ($this.List) {
                $this.List.InvalidateCache()
            }
            
            # Invalidate render cache to force redraw
            if ($this.RenderEngine) {
                $this.RenderEngine.InvalidateCachedRegion(0, $this.TermHeight)
            }
            
            if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                $global:PmcApp.RequestRender()
            }

        } catch {
            $this.SetStatusMessage("Failed to delete note: $($_.Exception.Message)", "error")
        }
    }

    # === Custom Actions ===

    <#
    .SYNOPSIS
    Add custom keyboard shortcuts
    #>
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
            },
            @{
                Key = 'p'
                Label = 'Assign Project'
                Callback = {
                    $selected = $self.List.GetSelectedItem()
                    if ($selected) {
                        $self._AssignToProject($selected)
                    }
                }.GetNewClosure()
            }
        )
    }

    hidden [void] _AssignToProject($note) {
        Write-PmcTuiLog "========== _AssignToProject START ==========" "INFO"
        
        # Show project picker and reassign note
        $noteId = $(if ($note -is [hashtable]) { $note['id'] } else { $note.id })
        $noteTitle = $(if ($note -is [hashtable]) { $note['title'] } else { $note.title })
        Write-PmcTuiLog "_AssignToProject: noteId=$noteId, noteTitle=$noteTitle" "INFO"

        # Use ProjectPickerDialog widget (has Show method)
        # CRITICAL: Must dot-source and use New-Object to avoid parse-time type resolution
        Write-PmcTuiLog "_AssignToProject: Loading ProjectPickerDialog..." "DEBUG"
        . "$PSScriptRoot/../widgets/ProjectPickerDialog.ps1"
        
        # Get all projects
        . "$PSScriptRoot/../services/TaskStore.ps1"
        $store = [TaskStore]::GetInstance()
        $allProjects = $store.GetAllProjects()
        
        Write-PmcTuiLog "_AssignToProject: Creating dialog with $($allProjects.Count) projects..." "DEBUG"
        $dialog = New-Object -TypeName ProjectPickerDialog -ArgumentList @($allProjects), "Select Project"

        Write-PmcTuiLog "_AssignToProject: Showing dialog..." "DEBUG"
        $selectedProject = $dialog.Show()
        
        if ($null -eq $selectedProject) {
            Write-PmcTuiLog "_AssignToProject: User cancelled" "INFO"
            $this.SetStatusMessage("Assignment cancelled", "info")
            return
        }

        # Get project name from selected project
        $projectName = $(if ($selectedProject -is [hashtable]) { $selectedProject['name'] } else { $selectedProject.name })
        Write-PmcTuiLog "_AssignToProject: Selected project = $projectName" "INFO"

        # Reassign note
        try {
            $changes = @{
                owner_type = "project"
                owner_id = $projectName
            }
            Write-PmcTuiLog "_AssignToProject: Calling UpdateNoteMetadata..." "DEBUG"
            $this._noteService.UpdateNoteMetadata($noteId, $changes)
            Write-PmcTuiLog "_AssignToProject: UpdateNoteMetadata DONE" "DEBUG"
            
            $this.SetStatusMessage("Note assigned to '$projectName'", "success")

            # Refresh list with fresh data
            Write-PmcTuiLog "_AssignToProject: Loading fresh data..." "DEBUG"
            $notes = $null
            if ($this._ownerType -eq "global" -or $null -eq $this._ownerId) {
                $notes = $this._noteService.GetAllNotes()
            } else {
                $notes = $this._noteService.GetNotesByOwner($this._ownerType, $this._ownerId)
            }
            
            Write-PmcTuiLog "_AssignToProject: Loaded $($notes.Count) notes" "INFO"
            
            if ($null -eq $notes) { $notes = @() }
            elseif ($notes -isnot [array]) { $notes = @($notes) }
            
            if ($this.List) {
                Write-PmcTuiLog "_AssignToProject: Calling SetData..." "DEBUG"
                $this.List.SetData($notes)
                Write-PmcTuiLog "_AssignToProject: Calling InvalidateCache..." "DEBUG"
                $this.List.InvalidateCache()
                Write-PmcTuiLog "_AssignToProject: List updated" "DEBUG"
            } else {
                Write-PmcTuiLog "_AssignToProject: ERROR - this.List is NULL!" "ERROR"
            }
            
            if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                Write-PmcTuiLog "_AssignToProject: Calling RequestRender..." "DEBUG"
                $global:PmcApp.RequestRender()
                Write-PmcTuiLog "_AssignToProject: RequestRender DONE" "DEBUG"
            }
            
            Write-PmcTuiLog "========== _AssignToProject END ==========" "INFO"
        } catch {
            Write-PmcTuiLog "_AssignToProject: EXCEPTION - $_" "ERROR"
            Write-PmcTuiLog "_AssignToProject: Stack trace - $($_.ScriptStackTrace)" "ERROR"
            $this.SetStatusMessage("Failed to assign note: $($_.Exception.Message)", "error")
        }
    }

    # === Menu Registration ===

    # H-MEM-2: Cleanup event subscriptions when screen exits
    <#
    .SYNOPSIS
    Called when the screen is about to be exited
    #>
    [void] OnDoExit() {
        # Unsubscribe from note service events to prevent memory leaks
        if ($this._noteService) {
            $this._noteService.OnNotesChanged = $null
        }
        # Write-PmcTuiLog "NotesMenuScreen.OnExit: Cleaned up event subscriptions" "DEBUG"
    }

    <#
    .SYNOPSIS
    Register menu items for this screen
    #>
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Tools', 'Notes', 'N', {
            . "$PSScriptRoot/NotesMenuScreen.ps1"
            $global:PmcApp.PushScreen((New-Object -TypeName NotesMenuScreen))
        }, 20)
    }
}