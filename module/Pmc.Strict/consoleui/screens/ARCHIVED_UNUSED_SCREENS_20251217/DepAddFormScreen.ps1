using namespace System.Collections.Generic
using namespace System.Text

# DepAddFormScreen - Add task dependency
# Creates dependency relationship between two tasks


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Add dependency between tasks

.DESCRIPTION
Shows form to create task dependency.
Supports:
- Selecting task that depends on another
- Selecting dependency task
- Creating dependency relationship
#>
class DepAddFormScreen : PmcScreen {
    # Data
    [string]$InputBuffer = ""
    [string]$InputField = "taskId"  # "taskId" or "dependsId"
    [hashtable]$FormData = @{}

    # Backward compatible constructor
    DepAddFormScreen() : base("DepAdd", "Add Dependency") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Dependencies", "Add"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Tab", "Next Field")
        $this.Footer.AddShortcut("Enter", "Submit")
        $this.Footer.AddShortcut("Esc", "Cancel")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")

        # Initialize form data
        $this.FormData = @{
            taskId    = ""
            dependsId = ""
        }
    }

    # Container constructor
    DepAddFormScreen([object]$container) : base("DepAdd", "Add Dependency", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Dependencies", "Add"))

        # Configure footer with shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("Tab", "Next Field")
        $this.Footer.AddShortcut("Enter", "Submit")
        $this.Footer.AddShortcut("Esc", "Cancel")
        $this.Footer.AddShortcut("Ctrl+Q", "Quit")

        # Initialize form data
        $this.FormData = @{
            taskId    = ""
            dependsId = ""
        }
    }

    [void] LoadData() {
        $this.ShowStatus("Enter task IDs to create dependency")
    }

    [void] RenderContentToEngine([object]$engine) {
        # Colors
        $textColor = $this.Header.GetThemedColorInt('Foreground.Field')
        $highlightColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $mutedColor = $this.Header.GetThemedColorInt('Foreground.Muted')
        $inputColor = $this.Header.GetThemedColorInt('Foreground.FieldFocused')
        $bg = $this.Header.GetThemedColorInt('Background.Primary')
        
        $y = 4
        $x = 4

        # Title
        $title = " Add Dependency "
        $titleX = $x + [Math]::Floor(($this.TermWidth - $x - $title.Length) / 2)
        $titleX = [Math]::Max($x, [Math]::Floor(($this.TermWidth - $title.Length) / 2))
        
        $engine.WriteAt($titleX, $y, $title, $highlightColor, $bg)
        $y += 2

        # Task ID field
        $labelColor = $(if ($this.InputField -eq 'taskId') { $highlightColor } else { $textColor })
        $engine.WriteAt($x, $y, "Task ID:", $labelColor, $bg)

        $valColor = $inputColor
        $valText = $(if ($this.InputField -eq 'taskId') { $this.InputBuffer + "_" } else { $this.FormData['taskId'] })
        $engine.WriteAt($x + 13, $y, $valText, $valColor, $bg)
        $y += 2

        # Depends on Task ID field
        $labelColor = $(if ($this.InputField -eq 'dependsId') { $highlightColor } else { $textColor })
        $engine.WriteAt($x, $y, "Depends on Task ID:", $labelColor, $bg)

        $valText = $(if ($this.InputField -eq 'dependsId') { $this.InputBuffer + "_" } else { $this.FormData['dependsId'] })
        $engine.WriteAt($x + 22, $y, $valText, $valColor, $bg)
        $y += 2

        # Help text
        $engine.WriteAt($x, $y, "(Task will be blocked until dependency is completed)", $mutedColor, $bg)
    }

    [string] RenderContent() { return "" }

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'Enter' {
                if ($this.InputField -eq 'taskId') {
                    # Save and move to next field
                    $this.FormData['taskId'] = $this.InputBuffer
                    $this.InputBuffer = $this.FormData['dependsId']
                    $this.InputField = 'dependsId'
                    $this.ShowStatus("Now enter dependency task ID")
                }
                else {
                    # Submit form
                    $this.FormData['dependsId'] = $this.InputBuffer
                    $this._SubmitForm()
                }
                return $true
            }
            'Tab' {
                # Save current field and cycle
                $this.FormData[$this.InputField] = $this.InputBuffer

                if ($this.InputField -eq 'taskId') {
                    $this.InputField = 'dependsId'
                    $this.InputBuffer = $this.FormData['dependsId']
                }
                else {
                    $this.InputField = 'taskId'
                    $this.InputBuffer = $this.FormData['taskId']
                }
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

        return $false
    }

    hidden [void] _SubmitForm() {
        try {
            $taskId = [int]$this.FormData['taskId']
            $dependsId = [int]$this.FormData['dependsId']

            if ($taskId -le 0 -or $dependsId -le 0) {
                $this.ShowError("Invalid task IDs")
                return
            }

            $data = Get-PmcData
            $task = $data.tasks | Where-Object { ($_.id) -eq $taskId } | Select-Object -First 1
            $dependsTask = $data.tasks | Where-Object { ($_.id) -eq $dependsId } | Select-Object -First 1

            if (-not $task) {
                $this.ShowError("Task $taskId not found!")
                return
            }

            if (-not $dependsTask) {
                $this.ShowError("Task $dependsId not found!")
                return
            }

            # Get existing depends or initialize
            $taskDepends = $task.depends
            if (-not $taskDepends) {
                $task | Add-Member -NotePropertyName depends -NotePropertyValue @()
                $taskDepends = @()
            }

            # Check if dependency already exists
            if ($taskDepends -contains $dependsId) {
                $this.ShowError("Dependency already exists!")
                return
            }

            $task.depends = @($taskDepends + $dependsId)

            # Update blocked status
            Update-PmcBlockedStatus -data $data

            Save-PmcData -Data $data -Action "Added dependency: $taskId depends on $dependsId"
            $this.ShowSuccess("Dependency added successfully! Task $taskId now depends on task $dependsId.")

            $this.App.PopScreen()
        }
        catch {
            $this.ShowError("Failed to add dependency: $_")
        }
    }
}

# Entry point function for compatibility
function Show-DepAddFormScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object DepAddFormScreen
    $App.PushScreen($screen)
}