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

            # Write-PmcTuiLog "NotesMenuScreen.OnAddItem: Created note, checking for id..." "DEBUG"
            $noteId = $(if ($note -is [hashtable]) { $note['id'] } else { $note.id })
            # Write-PmcTuiLog "NotesMenuScreen.OnAddItem: Note ID = $noteId" "INFO"

            # Refresh list (will happen automatically via event callback)
            # Open the new note in editor
            $this.OnItemActivated($note)

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
        # SAVE FIX: Safe property access
        $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
        # Write-PmcTuiLog "NotesMenuScreen.OnEditItem: Updating note $itemId" "DEBUG"

        try {
            # Validate title
            if (-not $data.ContainsKey('title') -or [string]::IsNullOrWhiteSpace($data.title)) {
                $this.SetStatusMessage("Note title is required", "error")
                return
            }

            # Parse tags
            $tags = @()
            if ($data.ContainsKey('tags') -and $data.tags -and $data.tags.Trim() -ne "") {
                $tags = $data.tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }

            # Update note metadata
            $changes = @{
                title = $data.title
                tags = $tags
            }

            $this._noteService.UpdateNoteMetadata($itemId, $changes)

            # Write-PmcTuiLog "NotesMenuScreen.OnEditItem: Updated note $($item.id)" "INFO"

            # Refresh list explicitly
            $this.LoadData()
            if ($this.List) {
                $this.List.InvalidateCache()
            }
            if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                $global:PmcApp.RequestRender()
            }

        } catch {
            # Write-PmcTuiLog "NotesMenuScreen.OnEditItem: Error - $_" "ERROR"
            $this.SetStatusMessage("Failed to update note: $($_.Exception.Message)", "error")
        }
    }

    <#
    .SYNOPSIS
    Handle delete note (called by StandardListScreen)
    #>
    [void] OnItemDeleted($item) {
        $this.OnDeleteItem($item)
    }

    <#
    .SYNOPSIS
    Handle delete note
    #>
    [void] OnDeleteItem($item) {
        # Write-PmcTuiLog "NotesMenuScreen.OnDeleteItem: Deleting note $($item.id)" "DEBUG"

        try {
            $this._noteService.DeleteNote($item.id)

            # Write-PmcTuiLog "NotesMenuScreen.OnDeleteItem: Deleted note $($item.id)" "INFO"

            # Refresh list (will happen automatically via event callback)

        } catch {
            # Write-PmcTuiLog "NotesMenuScreen.OnDeleteItem: Error - $_" "ERROR"
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
        # Show project picker and reassign note
        $noteId = $(if ($note -is [hashtable]) { $note['id'] } else { $note.id })
        $noteTitle = $(if ($note -is [hashtable]) { $note['title'] } else { $note.title })

        # Use ProjectPicker widget
        . "$PSScriptRoot/../widgets/ProjectPicker.ps1"
        $picker = [ProjectPicker]::new()

        $selectedProject = $picker.Show()
        
        if ($null -eq $selectedProject) {
            $this.SetStatusMessage("Assignment cancelled", "info")
            return
        }

        # Get project name from selected project
        $projectName = $(if ($selectedProject -is [hashtable]) { $selectedProject['name'] } else { $selectedProject.name })

        # Reassign note
        try {
            $changes = @{
                owner_type = "project"
                owner_id = $projectName
            }
            $this._noteService.UpdateNoteMetadata($noteId, $changes)
            $this.SetStatusMessage("Note assigned to '$projectName'", "success")

            # Refresh list
            $this.LoadData()
            if ($this.List) {
                $this.List.InvalidateCache()
            }
            if ($global:PmcApp -and $global:PmcApp.PSObject.Methods['RequestRender']) {
                $global:PmcApp.RequestRender()
            }
        } catch {
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