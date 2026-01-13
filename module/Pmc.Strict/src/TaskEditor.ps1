# TaskEditor.ps1 - Interactive task editing with full-screen editor
# Provides rich editing experience for PMC tasks with multi-line support and metadata editing

class PmcTaskEditor {
    [string]$TaskId
    [hashtable]$TaskData
    [string[]]$DescriptionLines
    [string]$Project
    [string]$Priority
    [string]$DueDate
    [string[]]$Tags
    [int]$CurrentLine
    [int]$CursorColumn
    [bool]$IsEditing
    [string]$Mode  # 'description', 'metadata', 'preview'
    [hashtable]$OriginalData
    [int]$StartRow
    [int]$EndRow

    PmcTaskEditor([string]$taskId) {
        $this.TaskId = $taskId
        $this.LoadTask()
        $this.InitializeEditor()
    }

    [void] LoadTask() {
        try {
            # Load task data from PMC data store
            $taskDataResult = Invoke-PmcCommand "task show $($this.TaskId)" -Raw

            if (-not $taskDataResult) {
                throw "Task $($this.TaskId) not found"
            }

            $this.TaskData = $taskDataResult
            $this.OriginalData = $taskDataResult.Clone()

            # Parse task fields
            $this.DescriptionLines = @($taskDataResult.description -split "`n")
            $this.Project = $(if ($taskDataResult.project) { $taskDataResult.project } else { "" })
            $this.Priority = $(if ($taskDataResult.priority) { $taskDataResult.priority } else { "" })
            $this.DueDate = $(if ($taskDataResult.due) { $taskDataResult.due } else { "" })
            $this.Tags = @($(if ($taskDataResult.tags) { $taskDataResult.tags } else { @() }))

        } catch {
            throw "Failed to load task: $_"
        }
    }

    [void] InitializeEditor() {
        $this.CurrentLine = 0
        $this.CursorColumn = 0
        $this.IsEditing = $false
        $this.Mode = 'description'

        # Calculate screen regions
        $this.StartRow = 3
        $this.EndRow = [Console]::WindowHeight - 8
    }

    [void] Show() {
        try {
            # Clear screen and setup editor
            [Console]::Clear()
            $this.DrawHeader()
            $this.DrawTaskContent()
            $this.DrawFooter()
            $this.DrawStatusLine()

            # Start editor loop
            $this.EditorLoop()

        } catch {
            Write-PmcStyled -Style 'Error' -Text ("Editor error: {0}" -f $_)
            Start-Sleep -Seconds 2
        }
    }

    [bool] HasUnsavedChanges() {
        # Compare current state with original
        $currentDescription = $this.DescriptionLines -join "`n"
        $originalDescription = $this.OriginalData.description

        return ($currentDescription -ne $originalDescription) -or
               ($this.Project -ne $this.OriginalData.project) -or
               ($this.Priority -ne $this.OriginalData.priority) -or
               ($this.DueDate -ne $this.OriginalData.due)
    }

    [void] EditorLoop() {
        while ($true) {
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                'F1' {
                    $this.Mode = 'description'
                    $this.DrawTaskContent()
                    $this.DrawStatusLine()
                }
                'F2' {
                    $this.Mode = 'metadata'
                    $this.DrawTaskContent()
                    $this.DrawStatusLine()
                }
                'F3' {
                    $this.Mode = 'preview'
                    $this.DrawTaskContent()
                    $this.DrawStatusLine()
                }
                'Escape' {
                    if ($this.ConfirmDoExit()) { return }
                }
                'S' {
                    if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                        $this.SaveTask()
                        return
                    }
                }
                default {
                    $this.HandleModeSpecificInput($key)
                }
            }
        }
    }

    [void] HandleModeSpecificInput([ConsoleKeyInfo]$key) {
        switch ($this.Mode) {
            'description' { $this.HandleDescriptionInput($key) }
            'metadata' { $this.HandleMetadataInput($key) }
            # Preview mode is read-only
        }

        $this.DrawTaskContent()
        $this.DrawStatusLine()
    }

    [void] HandleDescriptionInput([ConsoleKeyInfo]$key) {
        switch ($key.Key) {
            'UpArrow' {
                if ($this.CurrentLine -gt 0) {
                    $this.CurrentLine--
                    $this.CursorColumn = [Math]::Min($this.CursorColumn, $this.DescriptionLines[$this.CurrentLine].Length)
                }
            }
            'DownArrow' {
                if ($this.CurrentLine -lt ($this.DescriptionLines.Count - 1)) {
                    $this.CurrentLine++
                    $this.CursorColumn = [Math]::Min($this.CursorColumn, $this.DescriptionLines[$this.CurrentLine].Length)
                }
            }
            'LeftArrow' {
                if ($this.CursorColumn -gt 0) {
                    $this.CursorColumn--
                }
            }
            'RightArrow' {
                if ($this.CursorColumn -lt $this.DescriptionLines[$this.CurrentLine].Length) {
                    $this.CursorColumn++
                }
            }
            'Enter' {
                # Split current line at cursor position
                $currentLineText = $this.DescriptionLines[$this.CurrentLine]
                $beforeCursor = $currentLineText.Substring(0, $this.CursorColumn)
                $afterCursor = $currentLineText.Substring($this.CursorColumn)

                $this.DescriptionLines[$this.CurrentLine] = $beforeCursor
                $this.DescriptionLines = $this.DescriptionLines[0..$this.CurrentLine] + @($afterCursor) + $this.DescriptionLines[($this.CurrentLine + 1)..($this.DescriptionLines.Count - 1)]

                $this.CurrentLine++
                $this.CursorColumn = 0
            }
            'Backspace' {
                if ($this.CursorColumn -gt 0) {
                    $currentLineText = $this.DescriptionLines[$this.CurrentLine]
                    $newLine = $currentLineText.Substring(0, $this.CursorColumn - 1) + $currentLineText.Substring($this.CursorColumn)
                    $this.DescriptionLines[$this.CurrentLine] = $newLine
                    $this.CursorColumn--
                } elseif ($this.CurrentLine -gt 0) {
                    # Join with previous line
                    $prevLine = $this.DescriptionLines[$this.CurrentLine - 1]
                    $currentLineText = $this.DescriptionLines[$this.CurrentLine]
                    $this.CursorColumn = $prevLine.Length
                    $this.DescriptionLines[$this.CurrentLine - 1] = $prevLine + $currentLineText
                    $this.DescriptionLines = $this.DescriptionLines[0..($this.CurrentLine - 1)] + $this.DescriptionLines[($this.CurrentLine + 1)..($this.DescriptionLines.Count - 1)]
                    $this.CurrentLine--
                }
            }
            default {
                # Regular character input
                if ([char]::IsControl($key.KeyChar)) { return }

                $currentLineText = $this.DescriptionLines[$this.CurrentLine]
                $newLine = $currentLineText.Substring(0, $this.CursorColumn) + $key.KeyChar + $currentLineText.Substring($this.CursorColumn)
                $this.DescriptionLines[$this.CurrentLine] = $newLine
                $this.CursorColumn++
            }
        }
    }

    [void] HandleMetadataInput([ConsoleKeyInfo]$key) {
        # Metadata editing would be implemented here
        # For now, just basic navigation
    }

    [bool] ConfirmDoExit() {
        if (-not $this.HasUnsavedChanges()) {
            return $true
        }

        [Console]::SetCursorPosition(0, [Console]::WindowHeight - 1)
        Write-PmcStyled -Style 'Warning' -Text "Unsaved changes! Exit anyway? (y/N): " -NoNewline

        $response = [Console]::ReadKey($true)
        return ($response.Key -eq 'Y')
    }

    [void] SaveTask() {
        try {
            # Update task data
            $this.TaskData.description = $this.DescriptionLines -join "`n"
            $this.TaskData.project = $this.Project
            $this.TaskData.priority = $this.Priority
            $this.TaskData.due = $this.DueDate

            # Save via PMC command
            $updateCmd = "task edit $($this.TaskId) '$($this.TaskData.description)'"
            if ($this.Project) { $updateCmd += " @$($this.Project)" }
            if ($this.Priority) { $updateCmd += " $($this.Priority)" }
            if ($this.DueDate) { $updateCmd += " due:$($this.DueDate)" }

            Invoke-PmcCommand $updateCmd

            [Console]::SetCursorPosition(0, [Console]::WindowHeight - 1)
            Write-PmcStyled -Style 'Success' -Text "[OK] Task saved successfully!"
            Start-Sleep -Seconds 1

        } catch {
            [Console]::SetCursorPosition(0, [Console]::WindowHeight - 1)
            Write-PmcStyled -Style 'Error' -Text ("[ERROR] Error saving task: {0}" -f $_)
            Start-Sleep -Seconds 2
        }
    }

    [void] DrawHeader() {
        [Console]::SetCursorPosition(0, 0)
        Show-PmcHeader -Title "TASK EDITOR: $($this.TaskId)" -Icon '📝'
    }

    [void] DrawTaskContent() {
        # Clear content area
        for ($i = $this.StartRow; $i -le $this.EndRow; $i++) {
            [Console]::SetCursorPosition(0, $i)
            [Console]::Write(" " * [Console]::WindowWidth)
        }

        # Draw description
        for ($i = 0; $i -lt $this.DescriptionLines.Count; $i++) {
            $row = $this.StartRow + $i
            if ($row -gt $this.EndRow) { break }
            
            [Console]::SetCursorPosition(0, $row)
            if ($i -eq $this.CurrentLine -and $this.Mode -eq 'description') {
                # Highlight current line
                Write-PmcStyled -Style 'Editing' -Text $this.DescriptionLines[$i] -NoNewline
            } else {
                Write-PmcStyled -Style 'Body' -Text $this.DescriptionLines[$i] -NoNewline
            }
        }
        
        # Draw cursor if in description mode
        if ($this.Mode -eq 'description') {
            $cursorRow = $this.StartRow + $this.CurrentLine
            if ($cursorRow -le $this.EndRow) {
                [Console]::SetCursorPosition($this.CursorColumn, $cursorRow)
            }
        }
    }

    [void] DrawFooter() {
        $y = [Console]::WindowHeight - 3
        [Console]::SetCursorPosition(0, $y)
        Show-PmcSeparator
        
        [Console]::SetCursorPosition(0, $y + 1)
        Write-PmcStyled -Style 'Muted' -Text "F1:Desc F2:Meta F3:Preview ^S:Save Esc:Exit" -NoNewline
    }

    [void] DrawStatusLine() {
        $y = [Console]::WindowHeight - 1
        # Clear status line area
        [Console]::SetCursorPosition(0, $y)
        [Console]::Write(" " * [Console]::WindowWidth)
        
        [Console]::SetCursorPosition(0, $y)
        
        $status = switch ($this.Mode) {
            'description' { "Line $($this.CurrentLine + 1), Col $($this.CursorColumn + 1)" }
            'metadata' { "Metadata Editor - Use Enter to edit fields" }
            'preview' { "Preview Mode - Read-only view" }
        }
        
        $hasChanges = $this.HasUnsavedChanges()
        $changeIndicator = $(if ($hasChanges) { " [Modified]" } else { "" })
        
        Write-PmcStyled -Style 'Status' -Text "$status$changeIndicator" -NoNewline
    }
}

function Invoke-PmcTaskEditor {
    <#
    .SYNOPSIS
    Opens the interactive task editor for a specific task

    .PARAMETER TaskId
    The ID of the task to edit

    .EXAMPLE
    Invoke-PmcTaskEditor -TaskId "123"
    Opens the full-screen editor for task 123
    #>
    param(
        [Parameter(Mandatory)]
        [string]$TaskId
    )

    try {
        $editor = [PmcTaskEditor]::new($TaskId)
        $editor.Show()

    } catch {
        Write-PmcStyled -Style 'Error' -Text ("Error opening task editor: {0}" -f $_)
    }
}

# Export for module use
#Export-ModuleMember -Function Invoke-PmcTaskEditor