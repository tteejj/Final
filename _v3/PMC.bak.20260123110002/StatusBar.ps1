# StatusBar.ps1 - Dynamic context-aware status bar
# Renders at bottom with actions based on current focus/modal

class StatusBar {
    hidden [hashtable]$_contexts = @{}
    hidden [string]$_message = ""
    hidden [DateTime]$_messageTime = [DateTime]::MinValue
    hidden [string]$_messageType = "Info" # Info, Success, Error
    
    StatusBar() {
        $this._InitContexts()
    }
    
    hidden [void] _InitContexts() {
        # Main dashboard contexts
        $this._contexts["Dashboard.Sidebar"] = @(
            @{ Key = "Q"; Action = "Quit" }
            @{ Key = "V"; Action = "Project Info" }
            @{ Key = "T"; Action = "Time" }
            @{ Key = "O"; Action = "Overview" }
            @{ Key = "Tab"; Action = "Switch Panel" }
            @{ Key = "O"; Action = "Overview" }
            @{ Key = "Tab"; Action = "Switch Panel" }
            @{ Key = "N"; Action = "New Project" }
            @{ Key = "F"; Action = "Open Folder" }
        )
        

        
        $this._contexts["Dashboard.TaskList"] = @(
            @{ Key = "Q"; Action = "Quit" }
            @{ Key = "Tab"; Action = "Switch Panel" }
            @{ Key = "Tab"; Action = "Switch Panel" }
            @{ Key = "N"; Action = "New Task" }
            @{ Key = "S"; Action = "Subtask" }
            @{ Key = "E"; Action = "Edit" }
            @{ Key = "Enter"; Action = "Toggle" }
            @{ Key = "Del"; Action = "Delete" }
        )
        
        $this._contexts["Dashboard.Details"] = @(
            @{ Key = "Q"; Action = "Quit" }
            @{ Key = "Tab"; Action = "Switch Panel" }
            @{ Key = "E"; Action = "Edit Note" }
        )
        
        # Modal contexts
        $this._contexts["ProjectInfoModal"] = @(
            @{ Key = "Esc"; Action = "Close" }
            @{ Key = "Tab"; Action = "Switch Tab" }
            @{ Key = "Enter"; Action = "Edit/Action" }
            @{ Key = "Ctrl+S"; Action = "Save All" }
        )
        
        $this._contexts["TimeModal.Entries"] = @(
            @{ Key = "Esc"; Action = "Close" }
            @{ Key = "Tab"; Action = "Weekly View" }
            @{ Key = "N"; Action = "New Entry" }
            @{ Key = "Del"; Action = "Delete" }
        )
        
        $this._contexts["TimeModal.Weekly"] = @(
            @{ Key = "Esc"; Action = "Close" }
            @{ Key = "Tab"; Action = "Entries" }
            @{ Key = "←/→"; Action = "Change Week" }
        )
        
        $this._contexts["OverviewModal"] = @(
            @{ Key = "Esc"; Action = "Close" }
            @{ Key = "R"; Action = "Refresh" }
        )
        
        $this._contexts["FilePicker"] = @(
            @{ Key = "Esc"; Action = "Cancel" }
            @{ Key = "Enter"; Action = "Open Folder" }
            @{ Key = "Space"; Action = "Select" }
            @{ Key = "Backspace"; Action = "Parent" }
        )
        
        $this._contexts["NotesModal"] = @(
            @{ Key = "Esc"; Action = "Close" }
            @{ Key = "N"; Action = "New Note" }
            @{ Key = "Enter"; Action = "Edit" }
            @{ Key = "Del"; Action = "Delete" }
        )
        
        $this._contexts["ChecklistsModal"] = @(
            @{ Key = "Esc"; Action = "Close" }
            @{ Key = "N"; Action = "New" }
            @{ Key = "Space"; Action = "Toggle" }
        )
        
        $this._contexts["NoteEditor"] = @(
            @{ Key = "Esc"; Action = "Cancel" }
            @{ Key = "Ctrl+S"; Action = "Save" }
        )
        
        $this._contexts["Editing"] = @(
            @{ Key = "Esc"; Action = "Cancel" }
            @{ Key = "Enter"; Action = "Save" }
        )
    }

    [void] ShowMessage([string]$text, [string]$type) {
        $this._message = $text
        $this._messageType = $type
        $this._messageTime = [DateTime]::Now.AddSeconds(3)
    }
    
    [void] Render([HybridRenderEngine]$engine, [string]$context) {
        $y = $engine.Height - 1
        $w = $engine.Width
        
        # Clear status bar
        $engine.Fill(0, $y, $w, 1, " ", [Colors]::White, [Colors]::SelectionBg)
        
        # Get actions for context
        $actions = $this._contexts[$context]
        if (-not $actions) {
            $actions = $this._contexts["Dashboard.Sidebar"]  # Default
        }
        
        # Build status text
        $parts = @()
        foreach ($a in $actions) {
            $parts += "[$($a.Key)] $($a.Action)"
        }
        
        $statusText = " " + ($parts -join "  ")
        
        if ($statusText.Length -gt $w - 2) {
            $statusText = $statusText.Substring(0, $w - 5) + "..."
        }
        
        $engine.WriteAt(0, $y, $statusText, [Colors]::White, [Colors]::SelectionBg)
        
        # Render Toast Message (Right Aligned)
        if ($this._message -and [DateTime]::Now -lt $this._messageTime) {
            $msgColor = switch ($this._messageType) {
                "Success" { [Colors]::Success }
                "Error"   { [Colors]::Error }
                Default   { [Colors]::White }
            }
            $msgText = " " + $this._message + " "
            $msgX = $w - $msgText.Length - 1
            if ($msgX -gt $statusText.Length + 2) {
                $engine.WriteAt($msgX, $y, $msgText, [Colors]::Black, $msgColor)
            }
        }
    }
    
    [string] GetContext([hashtable]$state, [hashtable]$modals) {
        # Check modals first (in priority order)
        if ($modals.ContainsKey('NoteEditor') -and $modals['NoteEditor']) {
            return "NoteEditor"
        }
        if ($modals.ContainsKey('FilePicker') -and $modals['FilePicker']) {
            return "FilePicker"
        }
        if ($modals.ContainsKey('NotesModal') -and $modals['NotesModal']) {
            return "NotesModal"
        }
        if ($modals.ContainsKey('ChecklistsModal') -and $modals['ChecklistsModal']) {
            return "ChecklistsModal"
        }
        if ($modals.ContainsKey('TimeModal') -and $modals['TimeModal']) {
            $tab = if ($modals['TimeModalTab'] -eq 1) { "Weekly" } else { "Entries" }
            return "TimeModal.$tab"
        }
        if ($modals.ContainsKey('ProjectInfoModal') -and $modals['ProjectInfoModal']) {
            return "ProjectInfoModal"
        }
        if ($modals.ContainsKey('OverviewModal') -and $modals['OverviewModal']) {
            return "OverviewModal"
        }
        
        # Check edit mode
        if ($state.View.Editing) {
            return "Editing"
        }
        
        # Default to dashboard panel
        $panel = $state.View.FocusedPanel
        return "Dashboard.$panel"
    }
}
