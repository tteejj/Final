using namespace System.Collections.Generic
using namespace System.Text

# ChecklistEditorScreen - Edit checklist instance
# Shows items with completion checkboxes using UniversalList

Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"
. "$PSScriptRoot/../services/ChecklistService.ps1"
. "$PSScriptRoot/../widgets/UniversalList.ps1"

<#
.SYNOPSIS
Checklist editor screen for managing checklist instance items

.DESCRIPTION
Edit checklist instance:
- Toggle item completion (Space/Enter)
- View progress
- Navigate with arrow keys
#>
class ChecklistEditorScreen : PmcScreen {
    hidden [ChecklistService]$_checklistService = $null
    hidden [string]$_instanceId = ""
    hidden [object]$_instance = $null
    
    [UniversalList]$List = $null

    # Constructors
    ChecklistEditorScreen([string]$instanceId) : base("ChecklistEditor", "Checklist") {
        $this._InitializeScreen($instanceId)
    }

    ChecklistEditorScreen([string]$instanceId, [object]$container) : base("ChecklistEditor", "Checklist", $container) {
        $this._InitializeScreen($instanceId)
    }

    hidden [void] _InitializeScreen([string]$instanceId) {
        $this._instanceId = $instanceId
        $this._checklistService = [ChecklistService]::GetInstance()
        
        # Initialize UniversalList
        $this.List = [UniversalList]::new()
        
        # Configure columns
        $this.List.SetColumns(@(
            @{Name='completed_display'; Label='Done'; Width=6; Align='center'}
            @{Name='text'; Label='Item'; Width=60}
        ))
        
        # Add spacebar toggle action (using ' ' char)
        $self = $this
        $this.List.AddAction(' ', 'Toggle', { 
            $item = $self.List.GetSelectedItem()
            if ($item) { $self._ToggleItem($item) }
        }.GetNewClosure())
        
        # Add widget to content widgets list (for automatic lifecycle if PmcScreen supports it)
        # But we'll manually position/render in RenderContentToEngine to be safe
        $this.AddContentWidget($this.List)

        # Configure Footer
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Space", "Toggle")
        $this.Footer.AddShortcut("Esc", "Back")
    }

    [void] LoadData() {
        # Load instance
        $this._instance = $this._checklistService.GetInstance($this._instanceId)
        if (-not $this._instance) {
            $this.SetStatusMessage("Checklist not found", "error")
            return
        }
        
        $this.ScreenTitle = $this._instance.title
        $this.Header.SetBreadcrumb(@("Checklists", $this._instance.title))

        # Map items to list format
        $listItems = @()
        $index = 0
        foreach ($item in $this._instance.items) {
            $listItems += @{
                _index = $index  # Keep track of original index for toggle
                text = $item.text
                completed = $item.completed
                completed_display = if ($item.completed) { "[X]" } else { "[ ]" }
            }
            $index++
        }
        $this.List.SetData($listItems)
        
        # Update progress in Status Bar
        $prog = "Progress: $($this._instance.completed_count)/$($this._instance.total_count) ($($this._instance.percent_complete)%)"
        if ($this.StatusBar) { 
            $this.StatusBar.SetRightText($prog)
        }
    }

    hidden [void] _ToggleItem($item) {
        if ($null -eq $item) { return }
        try {
            $this._checklistService.ToggleItem($this._instanceId, $item._index)
            $this.LoadData()
            $this.SetStatusMessage("Item toggled", "success")
        }
        catch {
            $this.SetStatusMessage("Error: $($_.Exception.Message)", "error")
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        # Position the list to fill the content area
        # X=0, Y=6 (standard header height)
        # Width=TermWidth, Height=TermHeight - 8 (Header+Footer+Status)
        
        $this.List.X = 0
        $this.List.Y = 6
        $this.List.Width = $this.TermWidth
        $this.List.Height = [Math]::Max(5, $this.TermHeight - 8)
        
        # Render list
        $this.List.RenderToEngine($engine)
    }
    
    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # 1. Base PmcScreen (MenuBar, F10, etc.)
        if (([PmcScreen]$this).HandleKeyPress($keyInfo)) { return $true }
        
        # 2. UniversalList
        if ($this.List.HandleInput($keyInfo)) { return $true }
        
        # 3. Global Screen Shortcuts
        
        # Esc - Back
        if ($keyInfo.Key -eq 'Escape') {
            $global:PmcApp.PopScreen()
            return $true
        }
        
        # Manual Space toggle (redundancy in case action fails)
        if ($keyInfo.Key -eq 'Spacebar') {
             $item = $this.List.GetSelectedItem()
             if ($item) { 
                $this._ToggleItem($item) 
                return $true
             }
        }
        
        return $false
    }
}