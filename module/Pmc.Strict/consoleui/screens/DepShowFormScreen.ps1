using namespace System.Collections.Generic
using namespace System.Text

# DepShowFormScreen - Show task dependencies
# Displays dependencies for a specific task in tree view


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Show task dependencies screen

.DESCRIPTION
Shows task dependencies in tree view.
Supports:
- Viewing tasks this depends on
- Viewing tasks that depend on this
- Read-only view
#>
class DepShowFormScreen : PmcScreen {
    # Data
    [string]$InputBuffer = ""
    [bool]$IsInputMode = $true
    [object]$Task = $null
    [array]$Dependencies = @()

    # Backward compatible constructor
    DepShowFormScreen() : base("DepShow", "Show Dependencies") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Dependencies", "View"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Enter", "Submit")
        $this.Footer.AddShortcut("Esc", "Back")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    # Container constructor
    DepShowFormScreen([object]$container) : base("DepShow", "Show Dependencies", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Dependencies", "View"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Enter", "Submit")
        $this.Footer.AddShortcut("Esc", "Back")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")
    }

    [void] LoadData() {
        if ($this.IsInputMode) {
            $this.ShowStatus("Enter task ID to show dependencies")
        }
    }

    [void] RenderContentToEngine([object]$engine) {
        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $successColor = $this.Header.GetThemedColorInt('Foreground.Success')
        $errorColor = $this.Header.GetThemedColorInt('Foreground.Error')
        $warningColor = $this.Header.GetThemedColorInt('Foreground.Warning') 
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $y = 4
        $x = 4

        # Title
        $title = " Show Task Dependencies "
        $titleX = $x + [Math]::Floor(($this.TermWidth - $x - $title.Length) / 2)
        $titleX = [Math]::Max($x, [Math]::Floor(($this.TermWidth - $title.Length) / 2))
        
        $engine.WriteAt($titleX, $y, $title, $highlightColor, $bg)
        $y += 2

        if ($this.IsInputMode) {
            # Input mode - ask for task ID
            $engine.WriteAt($x, $y, "Task ID:", $textColor, $bg)
            $engine.WriteAt($x + 13, $y, $this.InputBuffer + "_", $highlightColor, $bg)
        }
        else {
            # Display mode - show dependencies
            if ($null -eq $this.Task) {
                $engine.WriteAt($x, $y, "Task not found", $errorColor, $bg)
            }
            else {
                # Show task info
                $engine.WriteAt($x, $y, "Task:", $warningColor, $bg)
                
                $taskText = $this.Task.text
                if ($taskText.Length -gt 60) {
                    $taskText = $taskText.Substring(0, 60) + "..."
                }
                $engine.WriteAt($x + 6, $y, $taskText, $textColor, $bg)
                $y += 2

                # Show dependencies
                if ($this.Dependencies.Count -eq 0) {
                    $engine.WriteAt($x, $y, "No dependencies", $mutedColor, $bg)
                }
                else {
                    $engine.WriteAt($x, $y, "Dependencies:", $warningColor, $bg)
                    $y += 2

                    $maxLines = [Math]::Min($this.Dependencies.Count, $this.TermHeight - 15)
                    for ($i = 0; $i -lt $maxLines; $i++) {
                        $dep = $this.Dependencies[$i]

                        # Status icon
                        $depStatus = $dep.status
                        $statusIcon = $(if ($depStatus -eq 'completed') { 'X' } else { 'o' })
                        $statusColor = $(if ($depStatus -eq 'completed') { $successColor } else { $errorColor })

                        $engine.WriteAt($x + 2, $y, $statusIcon, $statusColor, $bg)

                        # Task ID
                        $depId = $dep.id
                        $engine.WriteAt($x + 4, $y, "#$depId", $mutedColor, $bg)

                        # Task text
                        $depText = $dep.text
                        if ($depText.Length -gt 50) {
                            $depText = $depText.Substring(0, 50) + "..."
                        }
                        $engine.WriteAt($x + 11, $y, $depText, $textColor, $bg)

                        $y++
                    }
                }

                # Show blocked status
                $y += 2
                $isBlocked = $this.Task.blocked
                if ($isBlocked) {
                    $engine.WriteAt($x, $y, "WARNING: Task is BLOCKED", $errorColor, $bg)
                }
                else {
                    $engine.WriteAt($x, $y, "Task is ready", $successColor, $bg)
                }
            }
        }
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        if ($this.IsInputMode) {
            switch ($keyInfo.Key) {
                'Enter' {
                    $this._LoadTask()
                    return $true
                }
                'Escape' {
                    $this.App.PopScreen()
                    return $true
                }
                'Backspace' {
                    if ($this.InputBuffer.Length -gt 0) {
                        $this.InputBuffer = $this.InputBuffer.Substring(0, $this.InputBuffer.Length - 1)
                        return $true
                    }
                }
                default {
                    if ($keyInfo.KeyChar -and -not [char]::IsControl($keyInfo.KeyChar)) {
                        $this.InputBuffer += $keyInfo.KeyChar
                        return $true
                    }
                }
            }
        }
        else {
            # Display mode - just wait for Esc
            if ($keyInfo.Key -eq 'Escape') {
                $this.App.PopScreen()
                return $true
            }
        }

        return $false
    }

    hidden [void] _LoadTask() {
        try {
            $taskId = [int]$this.InputBuffer

            if ($taskId -le 0) {
                $this.ShowError("Invalid task ID")
                return
            }

            $data = Get-PmcData
            $this.Task = $data.tasks | Where-Object { ($_.id) -eq $taskId } | Select-Object -First 1

            if (-not $this.Task) {
                $this.ShowError("Task $taskId not found")
                return
            }

            # Load dependencies
            $depends = $this.Task.depends
            $depends = $(if ($depends) { $depends } else { @() })
            $this.Dependencies = @()

            foreach ($depId in $depends) {
                $depTask = $data.tasks | Where-Object { ($_.id) -eq $depId } | Select-Object -First 1
                if ($depTask) {
                    $this.Dependencies += $depTask
                }
            }

            $this.IsInputMode = $false
            $this.ShowStatus("Showing dependencies for task #$taskId")

        }
        catch {
            $this.ShowError("Failed to load task: $_")
        }
    }
}

# Entry point function for compatibility
function Show-DepShowFormScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object DepShowFormScreen
    $App.PushScreen($screen)
}