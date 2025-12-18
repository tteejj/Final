using namespace System.Collections.Generic
using namespace System.Text

# SearchFormScreen - Search tasks
# Input field for search query with live results display


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Task search screen with live results

.DESCRIPTION
Shows an input field where users can type search queries.
Displays matching tasks as the user types (live search).
Search matches task text, project, and tags.
Supports:
- Text input for search query
- Live search results update
- Enter to view selected task
- Up/Down to navigate results
- Esc to cancel
#>
class SearchFormScreen : PmcScreen {
    # Data
    [string]$SearchQuery = ""
    [array]$MatchingTasks = @()
    [int]$SelectedIndex = 0

    # Backward compatible constructor
    SearchFormScreen() : base("SearchForm", "Search Tasks") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Search"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Type", "Search")
        $this.Footer.AddShortcut("Up/Down", "Navigate")
        $this.Footer.AddShortcut("Enter", "View Task")
        $this.Footer.AddShortcut("Esc", "Cancel")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    # Container constructor
    SearchFormScreen([object]$container) : base("SearchForm", "Search Tasks", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Search"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Type", "Search")
        $this.Footer.AddShortcut("Up/Down", "Navigate")
        $this.Footer.AddShortcut("Enter", "View Task")
        $this.Footer.AddShortcut("Esc", "Cancel")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    [void] LoadData() {
        $this.ShowStatus("Type to search tasks...")
        $this._UpdateSearch()
    }

    hidden [void] _UpdateSearch() {
        try {
            $data = Get-PmcData

            if ([string]::IsNullOrWhiteSpace($this.SearchQuery)) {
                $this.MatchingTasks = @()
                $this.ShowStatus("Type to search tasks...")
                return
            }

            # Search in task text, project, and tags
            $query = $this.SearchQuery.ToLower()
            $this.MatchingTasks = @($data.tasks | Where-Object {
                    -not $_.completed -and (
                        $_.text.ToLower().Contains($query) -or
                        $_.project.ToLower().Contains($query) -or
                        ($_.tags -and ($_.tags -join ' ').ToLower().Contains($query))
                    )
                })

            # Reset selection if out of bounds
            if ($this.SelectedIndex -ge $this.MatchingTasks.Count) {
                $this.SelectedIndex = [Math]::Max(0, $this.MatchingTasks.Count - 1)
            }

            $count = $this.MatchingTasks.Count
            if ($count -eq 0) {
                $this.ShowStatus("No matches found")
            }
            elseif ($count -eq 1) {
                $this.ShowStatus("1 match found")
            }
            else {
                $this.ShowStatus("$count matches found")
            }

        }
        catch {
            $this.ShowError("Search error: $_")
            $this.MatchingTasks = @()
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        if (-not $this.LayoutManager) { return }

        # Get content area
        $contentRect = $this.LayoutManager.GetRegion('Content', $this.TermWidth, $this.TermHeight)

        # Colors (Ints)
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $selectedBg = $this.Header.GetThemedColorInt('Background.FieldFocused')
        $selectedFg = $this.Header.GetThemedColorInt('Foreground.Field')
        $cursorColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $priorityColor = $this.Header.GetThemedColorInt('Warning')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $y = $contentRect.Y
        
        # Search prompt
        $engine.WriteAt($contentRect.X + 4, $y, "Search for:", $textColor, $bg)
        $y += 2
        
        # Search input box
        $prompt = "> "
        $engine.WriteAt($contentRect.X + 4, $y, $prompt, $cursorColor, $bg)
        
        $inputX = $contentRect.X + 4 + $prompt.Length
        $engine.WriteAt($inputX, $y, $this.SearchQuery, $textColor, $bg)
        $engine.WriteAt($inputX + $this.SearchQuery.Length, $y, "_", $cursorColor, $bg)
        
        $y += 3
        
        # Results header
        if ($this.MatchingTasks.Count -gt 0) {
            $engine.WriteAt($contentRect.X + 4, $y, "Results:", $mutedColor, $bg)
            $y += 2
            
            # Column headers
            $headerText = "ID".PadRight(6) + "PRI".PadRight(5) + "PROJECT".PadRight(15) + "TASK"
            $engine.WriteAt($contentRect.X + 4, $y, $headerText, $mutedColor, $bg)
            $y++
            
            # Results list
            $maxLines = $contentRect.Height - 10
            for ($i = 0; $i -lt [Math]::Min($this.MatchingTasks.Count, $maxLines); $i++) {
                $task = $this.MatchingTasks[$i]
                $isSelected = ($i -eq $this.SelectedIndex)
                
                # Colors for this row
                $rowBg = if ($isSelected) { $selectedBg } else { $bg }
                $rowFg = if ($isSelected) { $selectedFg } else { $textColor }
                
                # Cursor
                if ($isSelected) {
                    $engine.WriteAt($contentRect.X + 2, $y, ">", $cursorColor, $bg)
                }
                
                $x = $contentRect.X + 4
                
                # Prepare row text parts
                # ID
                $idText = "#$($task.id)".PadRight(6)
                $engine.WriteAt($x, $y, $idText, $rowFg, $rowBg)
                $x += 6
                
                # Priority
                $priText = "  ".PadRight(5)
                $priColor = $rowFg # Default
                if ($task.priority -and $task.priority -gt 0) {
                    $priText = "P$($task.priority)".PadRight(5)
                    if (-not $isSelected) { $priColor = $priorityColor }
                }
                $engine.WriteAt($x, $y, $priText, $priColor, $rowBg)
                $x += 5
                
                # Project
                $projText = $(if ($task.project) { $task.project } else { "" })
                if ($projText.Length -gt 14) {
                    $projText = $projText.Substring(0, 11) + "..."
                }
                $projText = $projText.PadRight(15)
                $engine.WriteAt($x, $y, $projText, $rowFg, $rowBg)
                $x += 15
                
                # Task text
                $maxTaskWidth = $contentRect.Width - 35
                $taskText = $(if ($task.text) { $task.text } else { "" })
                if ($taskText.Length -gt $maxTaskWidth) {
                    $taskText = $taskText.Substring(0, $maxTaskWidth - 3) + "..."
                }
                $engine.WriteAt($x, $y, $taskText, $rowFg, $rowBg)
                
                $y++
            }
            
            # More results indicator
            if ($this.MatchingTasks.Count -gt $maxLines) {
                $engine.WriteAt($contentRect.X + 4, $y, "... and $($this.MatchingTasks.Count - $maxLines) more", $mutedColor, $bg)
            }
            
        }
        else {
            # No results message
            if (-not [string]::IsNullOrWhiteSpace($this.SearchQuery)) {
                $engine.WriteAt($contentRect.X + 4, $y, "No tasks match your search", $mutedColor, $bg)
            }
        }
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # CRITICAL: Call parent FIRST for MenuBar, F10, Alt+keys, content widgets
        $handled = ([PmcScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this.MatchingTasks.Count -gt 0 -and $this.SelectedIndex -gt 0) {
                    $this.SelectedIndex--
                    return $true
                }
            }
            'DownArrow' {
                if ($this.SelectedIndex -lt ($this.MatchingTasks.Count - 1)) {
                    $this.SelectedIndex++
                    return $true
                }
            }
            'Enter' {
                if ($this.MatchingTasks.Count -gt 0) {
                    $this._ViewSelectedTask()
                }
                return $true
            }
            'Backspace' {
                if ($this.SearchQuery.Length -gt 0) {
                    $this.SearchQuery = $this.SearchQuery.Substring(0, $this.SearchQuery.Length - 1)
                    $this._UpdateSearch()
                    return $true
                }
            }
            default {
                # Add character to search query
                if ($keyInfo.KeyChar -and -not [char]::IsControl($keyInfo.KeyChar)) {
                    $this.SearchQuery += $keyInfo.KeyChar
                    $this._UpdateSearch()
                    return $true
                }
            }
        }

        return $false
    }

    hidden [void] _ViewSelectedTask() {
        if ($this.SelectedIndex -lt 0 -or $this.SelectedIndex -ge $this.MatchingTasks.Count) {
            return
        }

        if ($this.MatchingTasks.Count -gt 0) {
            $task = $this.MatchingTasks[$this.SelectedIndex]
            . "$PSScriptRoot/TaskDetailScreen.ps1"
            $screen = New-Object TaskDetailScreen
            $screen.SetTask($task)
            $global:PmcApp.PushScreen($screen)
        }
    }
}

# Entry point function for compatibility
function Show-SearchFormScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object SearchFormScreen
    $App.PushScreen($screen)
}