using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

. "$PSScriptRoot/PmcDialog.ps1"

<#
.SYNOPSIS
Project picker dialog for selecting from available projects

.DESCRIPTION
Shows a list of projects with keyboard navigation.
User can select a project using arrow keys and Enter.
Can also create new projects inline with Alt+N.
#>
class ProjectPickerDialog : PmcDialog {
    hidden [string[]]$_projects = @()
    hidden [int]$_selectedIndex = 0
    hidden [string]$_createText = ""
    hidden [bool]$_isCreateMode = $false
    hidden [string]$_errorMessage = ""

    [scriptblock]$OnProjectSelected = {}

    ProjectPickerDialog([array]$projects, [string]$title) : base($title, "") {
        $this._projects = $projects

        # Calculate dimensions based on project count
        # Projects are objects with .name property, not strings
        $maxNameLength = 20
        foreach ($project in $projects) {
            $projectName = $(if ($project -is [hashtable]) { $project['name'] } elseif ($project.PSObject.Properties['name']) { $project.name } else { "$project" })
            if ($projectName -and $projectName.Length -gt $maxNameLength) {
                $maxNameLength = $projectName.Length
            }
        }

        $this.Width = [Math]::Max(45, $maxNameLength + 15)
        $this.Height = [Math]::Min(20, $projects.Count + 6)
    }

    [void] RenderToEngine([object]$engine) {
        # Render base dialog (shadow, box, title)
        ([PmcDialog]$this).RenderToEngine($engine)

        $bg = $this.GetThemedColorInt('Background.Widget')
        $fg = $this.GetThemedColorInt('Foreground.Primary')
        $selectedBg = $this.GetThemedColorInt('Background.RowSelected')
        $selectedFg = $this.GetThemedColorInt('Foreground.RowSelected')
        $dimFg = $this.GetThemedColorInt('Foreground.Dim')
        $errorFg = $this.GetThemedColorInt('Foreground.Error')

        if ($this._isCreateMode) {
            # Create mode: Show text input
            $inputY = $this.Y + 3

            # Input prompt
            $engine.WriteAt($this.X + 2, $inputY, "Project name:", $fg, $bg)

            # Input field
            $inputText = if ([string]::IsNullOrWhiteSpace($this._createText)) { "" } else { $this._createText }
            $maxInputWidth = $this.Width - 18
            if ($inputText.Length -gt $maxInputWidth) {
                $inputText = $inputText.Substring($inputText.Length - $maxInputWidth)
            }
            $engine.WriteAt($this.X + 17, $inputY, $inputText.PadRight($maxInputWidth), $fg, $selectedBg)

            # Help text
            $helpText = "Enter=Create | Esc=Cancel"
            $footerX = $this.X + [Math]::Floor(($this.Width - $helpText.Length) / 2)
            $engine.WriteAt($footerX, $this.Y + $this.Height - 2, $helpText, $dimFg, $bg)

            # Error message
            if ($this._errorMessage) {
                $errorY = $this.Y + 5
                $errorMsg = $this._errorMessage
                if ($errorMsg.Length -gt $this.Width - 4) {
                    $errorMsg = $errorMsg.Substring(0, $this.Width - 7) + "..."
                }
                $engine.WriteAt($this.X + 2, $errorY, $errorMsg, $errorFg, $bg)
            }
        }
        else {
            # Selection mode: Show project list
            $listY = $this.Y + 3
            $maxVisibleItems = $this.Height - 6

            # Calculate scroll offset if needed
            $scrollOffset = 0
            if ($this._projects.Count -gt $maxVisibleItems) {
                if ($this._selectedIndex -ge $maxVisibleItems) {
                    $scrollOffset = $this._selectedIndex - $maxVisibleItems + 1
                }
            }

            # Render visible projects
            $visibleCount = [Math]::Min($maxVisibleItems, $this._projects.Count)
            for ($i = 0; $i -lt $visibleCount; $i++) {
                $projectIndex = $i + $scrollOffset
                if ($projectIndex -ge $this._projects.Count) { break }

                $project = $this._projects[$projectIndex]
                # Get project name from object
                $projectName = $(if ($project -is [hashtable]) { $project['name'] } elseif ($project.PSObject.Properties['name']) { $project.name } else { "$project" })
                $isSelected = ($projectIndex -eq $this._selectedIndex)

                $itemBg = if ($isSelected) { $selectedBg } else { $bg }
                $itemFg = if ($isSelected) { $selectedFg } else { $fg }

                $prefix = if ($isSelected) { "> " } else { "  " }
                $text = "$prefix$projectName"

                # Truncate if too long
                $maxWidth = $this.Width - 4
                if ($text.Length -gt $maxWidth) {
                    $text = $text.Substring(0, $maxWidth - 3) + "..."
                }

                $engine.WriteAt($this.X + 2, $listY + $i, $text, $itemFg, $itemBg)
            }

            # Footer with instructions
            $footer = "↑↓: Navigate | Enter: Select | Alt+N: New Project | Esc: Cancel"
            $footerX = $this.X + [Math]::Floor(($this.Width - $footer.Length) / 2)
            $footerY = $this.Y + $this.Height - 2
            if ($footerX -lt $this.X + 2) {
                $footerX = $this.X + 2
            }
            $engine.WriteAt($footerX, $footerY, $footer, $dimFg, $bg)

            # Scroll indicators
            if ($this._projects.Count -gt $maxVisibleItems) {
                if ($scrollOffset -gt 0) {
                    $engine.WriteAt($this.X + $this.Width - 3, $this.Y + 3, "▲", $fg, $bg)
                }
                if ($scrollOffset + $maxVisibleItems -lt $this._projects.Count) {
                    $engine.WriteAt($this.X + $this.Width - 3, $this.Y + $this.Height - 3, "▼", $fg, $bg)
                }
            }
        }
    }

    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        if ($this._isCreateMode) {
            return $this._HandleCreateModeInput($keyInfo)
        }

        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this._selectedIndex -gt 0) {
                    $this._selectedIndex--
                }
                return $true
            }
            'DownArrow' {
                if ($this._selectedIndex -lt ($this._projects.Count - 1)) {
                    $this._selectedIndex++
                }
                return $true
            }
            'PageUp' {
                $this._selectedIndex = [Math]::Max(0, $this._selectedIndex - 5)
                return $true
            }
            'PageDown' {
                $this._selectedIndex = [Math]::Min($this._projects.Count - 1, $this._selectedIndex + 5)
                return $true
            }
            'Home' {
                $this._selectedIndex = 0
                return $true
            }
            'End' {
                $this._selectedIndex = $this._projects.Count - 1
                return $true
            }
            'Enter' {
                if ($this._projects.Count -gt 0) {
                    $selectedProject = $this._projects[$this._selectedIndex]
                    $this.Result = $selectedProject
                    $this.IsComplete = $true
                    if ($this.OnProjectSelected) {
                        & $this.OnProjectSelected $selectedProject
                    }
                }
                return $true
            }
            'Escape' {
                $this.Result = $null
                $this.IsComplete = $true
                return $true
            }
        }

        # Alt+N - Create new project
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt -and $keyInfo.Key -eq 'N') {
            $this._isCreateMode = $true
            $this._createText = ""
            $this._errorMessage = ""
            return $true
        }

        return $false
    }

    hidden [bool] _HandleCreateModeInput([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'Enter' {
                $projectName = $this._createText.Trim()

                if ([string]::IsNullOrWhiteSpace($projectName)) {
                    $this._errorMessage = "Project name cannot be empty"
                    return $true
                }

                # Check for duplicates
                if ($this._projects -contains $projectName) {
                    $this._errorMessage = "Project already exists"
                    return $true
                }

                # Create project
                try {
                    . "$PSScriptRoot/../services/TaskStore.ps1"
                    $store = [TaskStore]::GetInstance()

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

                    # Refresh projects list
                    $this._projects = @($data.projects | ForEach-Object { $_.name })

                    # Select new project
                    $this._selectedIndex = $this._projects.Count - 1
                    $this._isCreateMode = $false
                    $this._createText = ""
                    $this._errorMessage = ""

                    $this.Result = $projectName
                    $this.IsComplete = $true

                    if ($this.OnProjectSelected) {
                        & $this.OnProjectSelected $projectName
                    }

                    return $true
                }
                catch {
                    $this._errorMessage = "Failed to create project"
                    return $true
                }
            }
            'Escape' {
                $this._isCreateMode = $false
                $this._createText = ""
                $this._errorMessage = ""
                return $true
            }
            'Backspace' {
                if ($this._createText.Length -gt 0) {
                    $this._createText = $this._createText.Substring(0, $this._createText.Length - 1)
                }
                return $true
            }
        }

        # Regular character input
        if ($keyInfo.KeyChar -ge 32 -and $keyInfo.KeyChar -le 126) {
            if ($this._createText.Length -lt 50) {
                $this._createText += $keyInfo.KeyChar
            }
            return $true
        }

        # Space
        if ($keyInfo.Key -eq 'Spacebar') {
            if ($this._createText.Length -lt 50) {
                $this._createText += ' '
            }
            return $true
        }

        return $false
    }

    [string] GetSelectedProject() {
        if ($this._selectedIndex -ge 0 -and $this._selectedIndex -lt $this._projects.Count) {
            return $this._projects[$this._selectedIndex]
        }
        return $null
    }
    
    <#
    .SYNOPSIS
    Show the dialog in a blocking event loop
    
    .OUTPUTS
    Selected project object or $null if cancelled
    #>
    [object] Show() {
        # Get terminal dimensions
        $termWidth = [Console]::WindowWidth
        $termHeight = [Console]::WindowHeight
        
        # Center the dialog
        $this.X = [Math]::Floor(($termWidth - $this.Width) / 2)
        $this.Y = [Math]::Floor(($termHeight - $this.Height) / 2)
        
        # Create a temporary render engine or use global
        $engine = $global:PmcApp.RenderEngine
        
        # Run event loop until complete
        while (-not $this.IsComplete) {
            # Render
            $engine.BeginFrame()
            $engine.BeginLayer(200)  # Dialog layer
            $this.RenderToEngine($engine)
            $engine.EndFrame()
            
            # Handle input
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $this.HandleInput($key)
            }
            
            Start-Sleep -Milliseconds 16  # ~60fps
        }
        
        # Request screen refresh
        $global:PmcApp.RequestRender()
        
        return $this.Result
    }
}
