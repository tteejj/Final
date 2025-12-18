using namespace System.Collections.Generic
using namespace System.Text

# DepRemoveFormScreen - Remove task dependency
# Removes dependency relationship between two tasks


Set-StrictMode -Version Latest

. "$PSScriptRoot/../PmcScreen.ps1"

<#
.SYNOPSIS
Remove dependency between tasks

.DESCRIPTION
Shows form to remove task dependency.
Supports:
- Selecting task with dependencies
- Selecting dependency to remove
- Confirming removal
#>
class DepRemoveFormScreen : PmcScreen {
    # Data
    [string]$InputBuffer = ""
    [string]$InputField = "taskId"  # "taskId" or "dependsId"
    [hashtable]$FormData = @{}

    # Backward compatible constructor
    DepRemoveFormScreen() : base("DepRemove", "Remove Dependency") {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Dependencies", "Remove"))

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
    DepRemoveFormScreen([object]$container) : base("DepRemove", "Remove Dependency", $container) {
        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Dependencies", "Remove"))

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
        $this.ShowStatus("Enter task IDs to remove dependency")
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
        $title = " Remove Dependency "
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

        # Remove dependency on Task ID field
        $labelColor = $(if ($this.InputField -eq 'dependsId') { $highlightColor } else { $textColor })
        $engine.WriteAt($x, $y, "Remove dependency on Task ID:", $labelColor, $bg)

        $valText = $(if ($this.InputField -eq 'dependsId') { $this.InputBuffer + "_" } else { $this.FormData['dependsId'] })
        $engine.WriteAt($x + 31, $y, $valText, $valColor, $bg)
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
                    $this.ShowStatus("Now enter dependency task ID to remove")
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

            if (-not $task) {
                $this.ShowError("Task $taskId not found!")
                return
            }

            $taskDepends = $task.depends
            if (-not $taskDepends) {
                $this.ShowError("Task has no dependencies!")
                return
            }

            $task.depends = @($taskDepends | Where-Object { $_ -ne $dependsId })

            # Clean up empty depends array
            if ($task.depends.Count -eq 0) {
                $task.PSObject.Properties.Remove('depends')
            }

            # Update blocked status
            Update-PmcBlockedStatus -data $data

            Save-PmcData -Data $data -Action "Removed dependency: $taskId no longer depends on $dependsId"
            $this.ShowSuccess("Dependency removed successfully!")

            $this.App.PopScreen()
        }
        catch {
            $this.ShowError("Failed to remove dependency: $_")
        }
    }
}

# Entry point function for compatibility
function Show-DepRemoveFormScreen {
    param([object]$App)

    if (-not $App) {
        throw "PmcApplication required"
    }

    $screen = New-Object DepRemoveFormScreen
    $App.PushScreen($screen)
}