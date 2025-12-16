using namespace System
using namespace System.Collections.Generic
using namespace System.Text

# ProjectPicker.ps1 - Project selection widget with fuzzy search and inline create
#
# Usage:
#   $picker = [ProjectPicker]::new()
#   $picker.SetPosition(10, 5)
#   $picker.SetSize(35, 12)
#   $picker.OnProjectSelected = { param($project) Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [ProjectPicker] Selected: $project" }
#
#   # Render
#   $picker.RenderToEngine($engine)
#
#   # Handle input
#   $key = [Console]::ReadKey($true)
#   $handled = $picker.HandleInput($key)
#
#   # Get result
#   if ($picker.IsConfirmed) {
#       $selected = $picker.GetSelectedProject()
#   }

Set-StrictMode -Version Latest

# Load PmcWidget base class if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

<#
.SYNOPSIS
Project selection widget with fuzzy search and inline project creation

.DESCRIPTION
Features:
- Load projects from Get-PmcData
- Type-ahead fuzzy filtering (matches substrings and initials)
- Arrow key navigation through filtered list
- Enter to select project
- Alt+N to create new project inline (switches to TextInput mode)
- Recent projects shown at top
- Project count display
- OnProjectSelected event callback
- Visual list with scroll indicators
- Empty state handling

.EXAMPLE
$picker = [ProjectPicker]::new()
$picker.SetPosition(10, 5)
$picker.SetSize(35, 12)
$picker.OnProjectSelected = { param($projectName) Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [ProjectPicker] Selected: $projectName" }
$picker.OnProjectCreated = { param($projectName) Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [ProjectPicker] Created: $projectName" }
$picker.RenderToEngine($engine)
#>
class ProjectPicker : PmcWidget {
    # === Public Properties ===
    [string]$Label = "Select Project"      # Widget title
    [bool]$ShowRecentFirst = $true         # Show recent projects at top

    # === Event Callbacks ===
    [scriptblock]$OnProjectSelected = {}   # Called when project selected: param($projectName)
    [scriptblock]$OnProjectCreated = {}    # Called when new project created: param($projectName)
    [scriptblock]$OnCancelled = {}         # Called when Esc pressed

    # === State Flags ===
    [bool]$IsConfirmed = $false            # True when project selected
    [bool]$IsCancelled = $false            # True when Esc pressed

    # === Private State ===
    hidden [string[]]$_allProjects = @()           # All available projects
    hidden [string[]]$_filteredProjects = @()      # Filtered project list
    hidden [string]$_searchText = ""               # Current search filter
    hidden [int]$_selectedIndex = 0                # Selected item index in filtered list
    hidden [int]$_scrollOffset = 0                 # Scroll offset for long lists
    hidden [bool]$_isCreateMode = $false           # True when creating new project
    hidden [string]$_createText = ""               # Text for new project name
    hidden [int]$_createCursorPos = 0              # Cursor position in create mode
    hidden [string]$_errorMessage = ""             # Error message to display
    hidden [DateTime]$_lastRefresh = [DateTime]::MinValue

    # === Constructor ===
    ProjectPicker() : base("ProjectPicker") {
        $this.Width = 35
        $this.Height = 12
        $this.CanFocus = $true
        $this._LoadProjects()
    }

    # === Public API Methods ===

    <#
    .SYNOPSIS
    Refresh project list from data source
    #>
    [void] RefreshProjects() {
        $this._LoadProjects()
        $this._ApplyDoFilter()
    }

    <#
    .SYNOPSIS
    Get the currently selected project name

    .OUTPUTS
    String project name or empty string if none selected
    #>
    [string] GetSelectedProject() {
        if ($this._filteredProjects.Count -eq 0) {
            return ""
        }

        if ($this._selectedIndex -ge 0 -and $this._selectedIndex -lt $this._filteredProjects.Count) {
            $selected = $this._filteredProjects[$this._selectedIndex]
            if ($selected -eq "(No Project)") { return "" }
            return $selected
        }

        return ""
    }

    <#
    .SYNOPSIS
    Set initial search filter text
    #>
    [void] SetSearchText([string]$text) {
        $this._searchText = $text
        $this._ApplyDoFilter()
    }

    <#
    .SYNOPSIS
    Set the selected project by name (without filtering)
    #>
    [void] SetSelectedProject([string]$projectName) {
        # Find the project in the full list
        for ($i = 0; $i -lt $this._filteredProjects.Count; $i++) {
            if ($this._filteredProjects[$i] -eq $projectName) {
                $this._selectedIndex = $i
                $this._AdjustScrollOffset()
                return
            }
        }
        # Not found - select first item
        $this._selectedIndex = 0
        $this._AdjustScrollOffset()
    }

    <#
    .SYNOPSIS
    Handle keyboard input
    #>
    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        # Check if we need to refresh projects (every 5 seconds)
        if (([DateTime]::Now - $this._lastRefresh).TotalSeconds -gt 5) {
            $this._LoadProjects()
            $this._ApplyDoFilter()
        }

        # Create mode has different input handling
        if ($this._isCreateMode) {
            return $this._HandleCreateModeInput($keyInfo)
        }

        # Enter - select current project
        if ($keyInfo.Key -eq 'Enter') {
            $selected = $this.GetSelectedProject()
            $this.IsConfirmed = $true
            # Callback with selected project (empty string if No Project)
            $this._InvokeCallback($this.OnProjectSelected, $selected)
            return $true
        }

        # Escape - cancel
        if ($keyInfo.Key -eq 'Escape') {
            $this.IsCancelled = $true
            $this._InvokeCallback($this.OnCancelled, $null)
            return $true
        }

        # Alt+N - create new project
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt -and $keyInfo.Key -eq 'N') {
            $this._EnterCreateMode()
            return $true
        }

        # Navigation
        if ($keyInfo.Key -eq 'UpArrow') {
            $this._MoveSelectionUp()
            return $true
        }

        if ($keyInfo.Key -eq 'DownArrow') {
            $this._MoveSelectionDown()
            return $true
        }

        if ($keyInfo.Key -eq 'PageUp') {
            $this._MoveSelectionUp()
            $this._MoveSelectionUp()
            $this._MoveSelectionUp()
            return $true
        }

        if ($keyInfo.Key -eq 'PageDown') {
            $this._MoveSelectionDown()
            $this._MoveSelectionDown()
            $this._MoveSelectionDown()
            return $true
        }

        if ($keyInfo.Key -eq 'Home') {
            $this._selectedIndex = 0
            $this._AdjustScrollOffset()
            return $true
        }

        if ($keyInfo.Key -eq 'End') {
            $this._selectedIndex = [Math]::Max(0, $this._filteredProjects.Count - 1)
            $this._AdjustScrollOffset()
            return $true
        }

        # Backspace - remove character from search
        if ($keyInfo.Key -eq 'Backspace') {
            if ($this._searchText.Length -gt 0) {
                $this._searchText = $this._searchText.Substring(0, $this._searchText.Length - 1)
                $this._ApplyDoFilter()
            }
            return $true
        }

        # Ctrl+U - clear search
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Control -and $keyInfo.Key -eq 'U') {
            $this._searchText = ""
            $this._ApplyDoFilter()
            return $true
        }

        # Regular character - add to search
        if ($keyInfo.KeyChar -ge 32 -and $keyInfo.KeyChar -le 126) {
            $this._searchText += $keyInfo.KeyChar
            $this._ApplyDoFilter()
            return $true
        }

        # Space
        if ($keyInfo.Key -eq 'Spacebar') {
            $this._searchText += ' '
            $this._ApplyDoFilter()
            return $true
        }

        return $false
    }

    # === Layout System ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)
        # Regions removed - using direct WriteAt in RenderToEngine
    }

    <#
    .SYNOPSIS
    Render directly to engine (new high-performance path)
    #>
    [void] RenderToEngine([object]$engine) {
        $this.RegisterLayout($engine)


        # Colors (Ints)
        # Use Panel background but ensure it is OPAQUE
        $bg = $this.GetThemedBgInt('Background.Panel', 1, 0)
        
        # DOUBLE BORDER FIX: Force opaque background. 
        # If theme returns -1 (Transparent), use hardcoded Black (0,0,0) packed int.
        if ($bg -eq -1) { 
            # 0xFF000000 (Alpha=255) if engine supports it, or just 0 for Black RGB packed?
            # HybridRenderEngine uses packed RGB. 0 = Black.
            # Let's use a dark gray to be safe and visible: RGB(10,10,10)
            $bg = [HybridRenderEngine]::_PackRGB(10, 10, 10) 
        }
        
        # Force strict bounding box for visual stability
        if ($this.Width -lt 20) { $this.Width = 20 }

        # Clamp AFTER size adjustments to prevent growing off-screen
        $this._ClampToBounds($engine)
        
        # === LAYER ELEVATION ===
        # DOUBLE BORDER FIX: Ensure Popup is drawn ABOVE everything else (e.g. List Borders)
        # by explicitly setting a high Z-Index layer.
        if ($engine.PSObject.Methods['BeginLayer']) {
            $engine.BeginLayer(100) # Arbitrary high number
        }

        $fg = $this.GetThemedInt('Foreground.Row')
        $borderFg = $this.GetThemedInt('Border.Widget')
        $primaryFg = $this.GetThemedInt('Foreground.Title')
        $mutedFg = $this.GetThemedInt('Foreground.Muted')
        $errorFg = $this.GetThemedInt('Foreground.Error')
        $highlightBg = $this.GetThemedBgInt('Background.RowSelected', 1, 0)
        $highlightFg = $this.GetThemedInt('Foreground.RowSelected')
        
        # 1. Fill Background (Strict Opaque)
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)
        
        # 2. Draw Box (Strict single border)
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $borderFg, $bg)
        
        # Title
        $title = if ($this._isCreateMode) { "Create New Project" } else { $this.Label }
        $pad = [Math]::Max(0, [Math]::Floor(($this.Width - 4 - $title.Length) / 2))
        $titleX = $this.X + 2 + $pad
        # Ensure title fits
        if ($title.Length -gt ($this.Width - 4)) {
            $title = $title.Substring(0, $this.Width - 4)
            $titleX = $this.X + 2
        }
        $engine.WriteAt($titleX, $this.Y + 1, $title, $primaryFg, $bg)
        
        # Count (if not in create mode)
        if (-not $this._isCreateMode) {
            $countStr = "($($this._filteredProjects.Count))"
            $engine.WriteAt($this.X + $this.Width - $countStr.Length - 2, $this.Y + 1, $countStr, $mutedFg, $bg)
        }
        
        # Separator line under title
        $engine.Fill($this.X + 1, $this.Y + 2, $this.Width - 2, 1, '─', $borderFg, $bg)
        
        # Search Box or List...
        
        # (Rest of rendering logic)
        


        if ($this._isCreateMode) {
            # Create Input at Y+3
            $inputY = $this.Y + 3
            
            # Input Prompt/border
            $engine.WriteAt($this.X, $inputY, [char]0x2502, $borderFg, $bg) # Left border
            $engine.WriteAt($this.X + $this.Width - 1, $inputY, [char]0x2502, $borderFg, $bg) # Right border
            
            # Input content
            $inputStr = $this._createText
            $innerWidth = $this.Width - 4
            
            if ([string]::IsNullOrEmpty($inputStr)) {
                $engine.WriteAt($this.X + 2, $inputY, "Enter project name...", $mutedFg, $bg)
            }
            else {
                # Simple rendering without complex scrolling for now
                $display = $inputStr
                if ($display.Length -gt $innerWidth) { $display = $display.Substring($display.Length - $innerWidth) }
                $engine.WriteAt($this.X + 2, $inputY, $display, $fg, $bg)
            }
            
            # Help at Y+5
            $helpText = "Enter=Create | Esc=Cancel"
            $engine.WriteAt($this.X + 2, $this.Y + 5, $this.PadText($helpText, $this.Width - 4, 'left'), $mutedFg, $bg)
        }
        else {
            # Count
            $countText = "($($this._filteredProjects.Count))"
            $countX = $this.X + $this.Width - $countText.Length - 2
            if ($countX -gt $this.X + 2) {
                $engine.WriteAt($countX, $this.Y + 1, $countText, $mutedFg, $bg)
            }
            
            # Search at Y+2
            $searchText = if ([string]::IsNullOrWhiteSpace($this._searchText)) { "Type to filter..." } else { $this._searchText }
            $searchFg = if ([string]::IsNullOrWhiteSpace($this._searchText)) { $mutedFg } else { $primaryFg }
            $engine.WriteAt($this.X + 2, $this.Y + 2, $this.PadText($searchText, $this.Width - 4, 'left'), $searchFg, $bg)
            
            # List at Y+3
            $listY = $this.Y + 3
            $listHeight = [Math]::Max(1, $this.Height - 5)
            $visibleProjects = @()
            if ($this._filteredProjects.Count -gt 0) {
                $endIndex = [Math]::Min($this._scrollOffset + $listHeight, $this._filteredProjects.Count)
                for ($i = $this._scrollOffset; $i -lt $endIndex; $i++) {
                    $visibleProjects += $this._filteredProjects[$i]
                }
            }
            
            for ($i = 0; $i -lt $listHeight; $i++) {
                $currentY = $listY + $i
                if ($currentY -ge $this.Y + $this.Height - 1) { break } # Safety
                
                if ($i -lt $visibleProjects.Count) {
                    $projectName = $visibleProjects[$i]
                    $isSelected = ($this._scrollOffset + $i) -eq $this._selectedIndex
                    
                    $iBg = if ($isSelected) { $highlightBg } else { $bg }
                    $iFg = if ($isSelected) { $highlightFg } else { $fg }
                    
                    $taskCount = $this._GetTaskCountForProject($projectName)
                    $displayName = if ($taskCount -ge 0) { "$projectName ($taskCount)" } else { $projectName }
                    
                    # Manual fill for row background
                    $engine.Fill($this.X + 1, $currentY, $this.Width - 2, 1, ' ', $iFg, $iBg)
                    $engine.WriteAt($this.X + 2, $currentY, $this.TruncateText($displayName, $this.Width - 4), $iFg, $iBg)
                }
                else {
                    # Empty row
                    $engine.Fill($this.X + 1, $currentY, $this.Width - 2, 1, ' ', $fg, $bg)
                }
            }

            # Help
            $helpText = "Enter=Select | Alt+N=Create"
            $engine.WriteAt($this.X + 2, $this.Y + $this.Height - 2, $this.PadText($helpText, $this.Width - 4, 'left'), $mutedFg, $bg)
        }
        
        if ($this._errorMessage) {
            $engine.WriteAt($this.X + 2, $this.Y + $this.Height - 1, $this.PadText($this._errorMessage, $this.Width - 4, 'left'), $errorFg, $bg)
        }
        
        # === END LAYER ELEVATION ===
        if ($engine.PSObject.Methods['BeginLayer']) {
            $engine.BeginLayer(0)
        }
    }

    <#
    .SYNOPSIS
    Ensure widget stays within screen bounds
    #>
    <#
    .SYNOPSIS
    Ensure widget stays within screen bounds (Engine Viewport)
    #>
    hidden [void] _ClampToBounds([object]$engine) {
        # Check Engine bounds first (Authoritative Viewport)
        if ($engine -and $engine.PSObject.Properties['Width']) {
            $termWidth = $engine.Width
            $termHeight = $engine.Height
        }
        else {
            # Fallback to console (but verify console availability)
            try {
                $termWidth = [Console]::WindowWidth
                $termHeight = [Console]::WindowHeight
            }
            catch {
                $termWidth = 80
                $termHeight = 24
            }
        }
        
        # Clamp X: ensure widget fits within right edge (0-indexed, so -1 for right boundary)
        if ($this.X + $this.Width -gt $termWidth) {
            $this.X = [Math]::Max(0, $termWidth - $this.Width)
        }

        # Clamp Y: ensure widget fits within bottom edge
        if ($this.Y + $this.Height -gt $termHeight) {
            $this.Y = [Math]::Max(0, $termHeight - $this.Height)
        }
    }

    # === Private Helper Methods ===

    <#
    .SYNOPSIS
    Load projects from PMC data
    #>
    hidden [void] _LoadProjects() {
        try {
            . "$PSScriptRoot/../services/TaskStore.ps1"
            $store = [TaskStore]::GetInstance()
            $projectsData = $store.GetAllProjects()

            # FIX: Always include "(No Project)" option at the beginning
            $projects = @("(No Project)")

            if ($null -ne $projectsData -and $projectsData.Count -gt 0) {
                foreach ($proj in $projectsData) {
                    if ($null -ne $proj.name -and -not [string]::IsNullOrWhiteSpace($proj.name)) {
                        $projects += $proj.name.ToString()
                    }
                }
            }

            $this._allProjects = $projects
            $this._lastRefresh = [DateTime]::Now
        }
        catch {
            # Failed to load projects - use "(No Project)" only
            $this._allProjects = @("(No Project)")
        }

        # Apply filter to refresh filtered list
        $this._ApplyDoFilter()
    }

    <#
    .SYNOPSIS
    Apply fuzzy search filter to project list
    #>
    hidden [void] _ApplyDoFilter() {
        if ([string]::IsNullOrWhiteSpace($this._searchText)) {
            $this._filteredProjects = $this._allProjects
        }
        else {
            $searchLower = $this._searchText.ToLower()
            $filtered = @()

            foreach ($project in $this._allProjects) {
                $projectLower = $project.ToLower()

                # Exact substring match
                if ($projectLower.Contains($searchLower)) {
                    $filtered += $project
                    continue
                }

                # Fuzzy match - initials or character sequence
                if ($this._FuzzyMatch($projectLower, $searchLower)) {
                    $filtered += $project
                }
            }

            $this._filteredProjects = $filtered
        }

        # Ensure filtered projects is initialized
        if ($null -eq $this._filteredProjects) {
            $this._filteredProjects = @()
        }

        # Reset selection if out of bounds
        if ($this._selectedIndex -ge $this._filteredProjects.Count) {
            $this._selectedIndex = [Math]::Max(0, $this._filteredProjects.Count - 1)
        }

        $this._AdjustScrollOffset()
    }

    <#
    .SYNOPSIS
    Fuzzy match algorithm - matches initials and subsequences

    .PARAMETER text
    Text to search in (lowercase)

    .PARAMETER pattern
    Pattern to match (lowercase)

    .OUTPUTS
    True if pattern matches text
    #>
    hidden [bool] _FuzzyMatch([string]$text, [string]$pattern) {
        $patternIdx = 0
        $textIdx = 0

        while ($patternIdx -lt $pattern.Length -and $textIdx -lt $text.Length) {
            if ($pattern[$patternIdx] -eq $text[$textIdx]) {
                $patternIdx++
            }
            $textIdx++
        }

        return $patternIdx -eq $pattern.Length
    }

    <#
    .SYNOPSIS
    Move selection up
    #>
    hidden [void] _MoveSelectionUp() {
        if ($this._selectedIndex -gt 0) {
            $this._selectedIndex--
            $this._AdjustScrollOffset()
        }
    }

    <#
    .SYNOPSIS
    Move selection down
    #>
    hidden [void] _MoveSelectionDown() {
        if ($this._selectedIndex -lt ($this._filteredProjects.Count - 1)) {
            $this._selectedIndex++
            $this._AdjustScrollOffset()
        }
    }

    <#
    .SYNOPSIS
    Adjust scroll offset to keep selection visible
    #>
    hidden [void] _AdjustScrollOffset() {
        $maxVisibleItems = $this.Height - 4

        # If selected item is above visible area, scroll up
        if ($this._selectedIndex -lt $this._scrollOffset) {
            $this._scrollOffset = $this._selectedIndex
        }

        # If selected item is below visible area, scroll down
        if ($this._selectedIndex -ge ($this._scrollOffset + $maxVisibleItems)) {
            $this._scrollOffset = $this._selectedIndex - $maxVisibleItems + 1
        }

        # Clamp scroll offset
        if ($this._scrollOffset -lt 0) {
            $this._scrollOffset = 0
        }

        $maxScroll = [Math]::Max(0, $this._filteredProjects.Count - $maxVisibleItems)
        if ($this._scrollOffset -gt $maxScroll) {
            $this._scrollOffset = $maxScroll
        }
    }

    <#
    .SYNOPSIS
    Enter create mode for new project
    #>
    hidden [void] _EnterCreateMode() {
        $this._isCreateMode = $true
        $this._createText = ""
        $this._createCursorPos = 0
        $this._errorMessage = ""
    }

    <#
    .SYNOPSIS
    Handle input in create mode

    .PARAMETER keyInfo
    ConsoleKeyInfo

    .OUTPUTS
    True if handled
    #>
    hidden [bool] _HandleCreateModeInput([ConsoleKeyInfo]$keyInfo) {
        # Enter - create project
        if ($keyInfo.Key -eq 'Enter') {
            $projectName = $this._createText.Trim()

            if ([string]::IsNullOrWhiteSpace($projectName)) {
                $this._errorMessage = "Project name cannot be empty"
                return $true
            }

            # Check for duplicates
            $exists = $false
            foreach ($existing in $this._allProjects) {
                if ($existing.ToLower() -eq $projectName.ToLower()) {
                    $exists = $true
                    break
                }
            }

            if ($exists) {
                $this._errorMessage = "Project already exists"
                return $true
            }

            # Create project in PMC data
            try {
                $data = Get-PmcData
                if ($null -eq $data.projects) {
                    $data | Add-Member -NotePropertyName 'projects' -NotePropertyValue @() -Force
                }

                $newProject = [PSCustomObject]@{
                    name        = $projectName
                    description = ""
                    aliases     = @()
                    created     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                }

                $data.projects += $newProject
                Save-PmcData $data

                # Refresh and select new project
                $this._LoadProjects()
                $this._isCreateMode = $false
                $this._createText = ""
                $this._errorMessage = ""

                # Find and select the new project
                for ($i = 0; $i -lt $this._filteredProjects.Count; $i++) {
                    if ($this._filteredProjects[$i] -eq $projectName) {
                        $this._selectedIndex = $i
                        $this._AdjustScrollOffset()
                        break
                    }
                }

                $this.IsConfirmed = $true
                $this._InvokeCallback($this.OnProjectCreated, $projectName)
                $this._InvokeCallback($this.OnProjectSelected, $projectName)

                return $true
            }
            catch {
                $this._errorMessage = "Failed to create project"
                return $true
            }
        }

        # Escape - cancel create mode
        if ($keyInfo.Key -eq 'Escape') {
            $this._isCreateMode = $false
            $this._createText = ""
            $this._createCursorPos = 0
            $this._errorMessage = ""
            return $true
        }

        # Backspace
        if ($keyInfo.Key -eq 'Backspace') {
            if ($this._createCursorPos -gt 0) {
                $before = $this._createText.Substring(0, $this._createCursorPos - 1)
                $after = $(if ($this._createCursorPos -lt $this._createText.Length) {
                        $this._createText.Substring($this._createCursorPos)
                    }
                    else { "" })
                $this._createText = $before + $after
                $this._createCursorPos--
            }
            return $true
        }

        # Delete
        if ($keyInfo.Key -eq 'Delete') {
            if ($this._createCursorPos -lt $this._createText.Length) {
                $before = $this._createText.Substring(0, $this._createCursorPos)
                $after = $(if ($this._createCursorPos + 1 -lt $this._createText.Length) {
                        $this._createText.Substring($this._createCursorPos + 1)
                    }
                    else { "" })
                $this._createText = $before + $after
            }
            return $true
        }

        # Navigation
        if ($keyInfo.Key -eq 'LeftArrow') {
            if ($this._createCursorPos -gt 0) {
                $this._createCursorPos--
            }
            return $true
        }

        if ($keyInfo.Key -eq 'RightArrow') {
            if ($this._createCursorPos -lt $this._createText.Length) {
                $this._createCursorPos++
            }
            return $true
        }

        if ($keyInfo.Key -eq 'Home') {
            $this._createCursorPos = 0
            return $true
        }

        if ($keyInfo.Key -eq 'End') {
            $this._createCursorPos = $this._createText.Length
            return $true
        }

        # Regular character input
        if ($keyInfo.KeyChar -ge 32 -and $keyInfo.KeyChar -le 126) {
            $before = $this._createText.Substring(0, $this._createCursorPos)
            $after = $(if ($this._createCursorPos -lt $this._createText.Length) {
                    $this._createText.Substring($this._createCursorPos)
                }
                else { "" })
            $this._createText = $before + $keyInfo.KeyChar + $after
            $this._createCursorPos++
            return $true
        }

        # Space
        if ($keyInfo.Key -eq 'Spacebar') {
            $before = $this._createText.Substring(0, $this._createCursorPos)
            $after = $(if ($this._createCursorPos -lt $this._createText.Length) {
                    $this._createText.Substring($this._createCursorPos)
                }
                else { "" })
            $this._createText = $before + ' ' + $after
            $this._createCursorPos++
            return $true
        }

        return $false
    }

    <#
    .SYNOPSIS
    L-POL-8: Get task count for a project

    .PARAMETER projectName
    Name of the project

    .OUTPUTS
    Number of tasks in project, or -1 if count unavailable
    #>
    hidden [int] _GetTaskCountForProject([string]$projectName) {
        try {
            . "$PSScriptRoot/../services/TaskStore.ps1"
            $store = [TaskStore]::GetInstance()
            $allTasks = $store.GetAllTasks()

            if ($null -eq $allTasks) {
                return -1
            }

            $count = 0
            foreach ($task in $allTasks) {
                $taskProject = $task.project
                if ($taskProject -eq $projectName -and -not ($task.completed)) {
                    $count++
                }
            }

            return $count
        }
        catch {
            # Failed to get count - return -1 to skip displaying count
            return -1
        }
    }

    <#
    .SYNOPSIS
    Invoke a callback scriptblock safely

    .PARAMETER callback
    Scriptblock to invoke

    .PARAMETER args
    Arguments to pass
    #>
    hidden [void] _InvokeCallback([scriptblock]$callback, $argument) {
        if ($null -ne $callback) {
            try {
                if ($null -ne $argument) {
                    & $callback $argument
                }
                else {
                    & $callback
                }
            }
            catch {
                # Callback failed - log but don't crash widget
            }
        }
    }
}