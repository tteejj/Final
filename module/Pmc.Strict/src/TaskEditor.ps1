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
        $this.EndRow = [PmcTerminalService]::GetHeight() - 8
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
        } finally {
            # Restore normal screen
            [Console]::Clear()
        }
    }

    [void] DrawHeader() {
        $palette = Get-PmcColorPalette
        $headerColor = Get-PmcColorSequence $palette.Header
        $resetColor = [PmcVT]::Reset()

        [Console]::SetCursorPosition(0, 0)
        $title = "PMC Task Editor - Task #$($this.TaskId)"
        $separator = "═" * [PmcTerminalService]::GetWidth()

        Write-Host "$headerColor$title$resetColor"
        Write-Host "$headerColor$separator$resetColor"
        Write-Host ""
    }

    [void] DrawTaskContent() {
        $startRowPos = $this.StartRow

        # Mode indicator
        $modeIndicator = switch ($this.Mode) {
            'description' { "[F1] Description Editor" }
            'metadata' { "[F2] Metadata Editor" }
            'preview' { "[F3] Preview Mode" }
        }

        [Console]::SetCursorPosition(0, $startRowPos - 1)
        Write-PmcStyled -Style 'Warning' -Text $modeIndicator

        switch ($this.Mode) {
            'description' { $this.DrawDescriptionEditor($startRowPos) }
            'metadata' { $this.DrawMetadataEditor($startRowPos) }
            'preview' { $this.DrawPreviewMode($startRowPos) }
        }
    }

    [void] DrawDescriptionEditor([int]$startRow) {
        $palette = Get-PmcColorPalette
        $textColor = Get-PmcColorSequence $palette.Text
        $resetColor = [PmcVT]::Reset()
        $cursorColor = Get-PmcColorSequence $palette.Cursor

        # Clear content area
        for ($i = $startRow; $i -le $this.EndRow; $i++) {
            [Console]::SetCursorPosition(0, $i)
            Write-Host (' ' * [PmcTerminalService]::GetWidth()) -NoNewline
        }

        # Draw description lines
        $maxLines = $this.EndRow - $startRow + 1
        $visibleLines = [Math]::Min($this.DescriptionLines.Count, $maxLines)

        for ($i = 0; $i -lt $visibleLines; $i++) {
            [Console]::SetCursorPosition(0, $startRow + $i)

            $line = $this.DescriptionLines[$i]
            $lineNumber = ($i + 1).ToString().PadLeft(3)

            if ($i -eq $this.CurrentLine) {
                # Highlight current line
                Write-Host "$cursorColor$lineNumber │ $line$resetColor" -NoNewline
            } else {
                Write-Host "$textColor$lineNumber │ $line$resetColor" -NoNewline
            }
        }

        # Show cursor position
        if ($this.CurrentLine -lt $visibleLines) {
            $cursorRow = $startRow + $this.CurrentLine
            $cursorCol = 6 + $this.CursorColumn  # Account for line number prefix
            [Console]::SetCursorPosition($cursorCol, $cursorRow)
        }
    }

    [void] DrawMetadataEditor([int]$startRow) {
        $palette = Get-PmcColorPalette
        $labelColor = Get-PmcColorSequence $palette.Label
        $valueColor = Get-PmcColorSequence $palette.Text
        $resetColor = [PmcVT]::Reset()

        # Clear area
        for ($i = $startRow; $i -le $this.EndRow; $i++) {
            [Console]::SetCursorPosition(0, $i)
            Write-Host (' ' * [PmcTerminalService]::GetWidth()) -NoNewline
        }

        $row = $startRow

        # Project field
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$labelColor  Project:$resetColor $valueColor$($this.Project)$resetColor"

        # Priority field
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$labelColor Priority:$resetColor $valueColor$($this.Priority)$resetColor"

        # Due date field
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$labelColor Due Date:$resetColor $valueColor$($this.DueDate)$resetColor"

        # Tags field
        [Console]::SetCursorPosition(0, $row++)
        $tagsStr = $(if ($this.Tags.Count -gt 0) { $this.Tags -join ", " } else { "(none)" })
        Write-Host "$labelColor     Tags:$resetColor $valueColor$tagsStr$resetColor"

        $row++

        # Metadata editing instructions
        [Console]::SetCursorPosition(0, $row)
        Write-PmcStyled -Style 'Muted' -Text "Press Enter to edit a field, Tab/Shift+Tab to navigate"
    }

    [void] DrawPreviewMode([int]$startRow) {
        $palette = Get-PmcColorPalette
        $headerColor = Get-PmcColorSequence $palette.Header
        $textColor = Get-PmcColorSequence $palette.Text
        $metaColor = Get-PmcColorSequence $palette.Muted
        $resetColor = [PmcVT]::Reset()

        # Clear area
        for ($i = $startRow; $i -le $this.EndRow; $i++) {
            [Console]::SetCursorPosition(0, $i)
            Write-Host (' ' * [PmcTerminalService]::GetWidth()) -NoNewline
        }

        $row = $startRow

        # Task header
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$headerColor╭─ Task Preview ─────────────────────────$resetColor"

        # Description
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$textColor│ Description:$resetColor"

        foreach ($line in $this.DescriptionLines) {
            [Console]::SetCursorPosition(0, $row++)
            Write-Host "$textColor│   $line$resetColor"
        }

        # Metadata
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$textColor│$resetColor"
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$textColor│ Metadata:$resetColor"
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$metaColor│   Project: $($this.Project)$resetColor"
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$metaColor│   Priority: $($this.Priority)$resetColor"
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$metaColor│   Due: $($this.DueDate)$resetColor"
        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$metaColor│   Tags: $($this.Tags -join ', ')$resetColor"

        [Console]::SetCursorPosition(0, $row++)
        Write-Host "$headerColor╰────────────────────────────────────────$resetColor"
    }

    [void] DrawFooter() {
        $footerRow = [PmcTerminalService]::GetHeight() - 4
        $palette = Get-PmcColorPalette
        $footerColor = Get-PmcColorSequence $palette.Footer
        $resetColor = [PmcVT]::Reset()

        [Console]::SetCursorPosition(0, $footerRow)
        Write-Host "$footerColor$('─' * [PmcTerminalService]::GetWidth())$resetColor"

        [Console]::SetCursorPosition(0, $footerRow + 1)
        Write-Host "$footerColor F1:Description  F2:Metadata  F3:Preview  Ctrl+S:Save  Esc:Cancel$resetColor"
    }

    [void] DrawStatusLine() {
        $statusRow = [PmcTerminalService]::GetHeight() - 2
        $palette = Get-PmcColorPalette
        $statusColor = Get-PmcColorSequence $palette.Status
        $resetColor = [PmcVT]::Reset()

        [Console]::SetCursorPosition(0, $statusRow)

        $status = switch ($this.Mode) {
            'description' { "Line $($this.CurrentLine + 1), Column $($this.CursorColumn + 1)" }
            'metadata' { "Metadata Editor - Use Enter to edit fields" }
            'preview' { "Preview Mode - Read-only view" }
        }

        $hasChanges = $this.HasUnsavedChanges()
        $changeIndicator = $(if ($hasChanges) { " [Modified]" } else { "" })

        Write-Host "$statusColor$status$changeIndicator$resetColor" -NoNewline
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

        [Console]::SetCursorPosition(0, [PmcTerminalService]::GetHeight() - 1)
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

            [Console]::SetCursorPosition(0, [PmcTerminalService]::GetHeight() - 1)
            Write-PmcStyled -Style 'Success' -Text "[OK] Task saved successfully!"
            Start-Sleep -Seconds 1

        } catch {
            [Console]::SetCursorPosition(0, [PmcTerminalService]::GetHeight() - 1)
            Write-PmcStyled -Style 'Error' -Text ("[ERROR] Error saving task: {0}" -f $_)
            Start-Sleep -Seconds 2
        }
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