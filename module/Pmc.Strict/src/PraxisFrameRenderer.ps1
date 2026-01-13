# Frame-based rendering system - stolen from Praxis ScreenManager and adapted for PMC

class PraxisFrameRenderer {
    # Double buffering
    hidden [string]$_lastFrame = ""
    hidden [bool]$_needsRender = $true
    hidden [int]$_frameCount = 0

    # Performance tracking
    hidden [System.Diagnostics.Stopwatch]$_renderTimer
    hidden [double]$_lastRenderTime = 0

    PraxisFrameRenderer() {
        $this._renderTimer = [System.Diagnostics.Stopwatch]::new()
    }

    # Main render method - stolen from Praxis ScreenManager
    [void] RenderFrame([string]$content) {
        $this._renderTimer.Restart()

        # Only render if content changed (Praxis optimization)
        if ($this._lastFrame -ne $content -or $this._needsRender) {

            # Clear screen only on first render or significant changes
            if ($this._lastFrame -eq "" -or $this._frameCount -eq 0) {
                [Console]::Write([PraxisVT]::Clear())
            }

            # Single atomic write - the Praxis way
            [Console]::CursorVisible = $false
            [Console]::SetCursorPosition(0, 0)
            [Console]::Write($content)

            # Store for next comparison
            $this._lastFrame = $content
            $this._needsRender = $false
        }

        $this._renderTimer.Stop()
        $this._frameCount++
        $this._lastRenderTime = $this._renderTimer.ElapsedMilliseconds
    }

    # Force next render (for resize, data changes, etc.)
    [void] Invalidate() {
        $this._needsRender = $true
        $this._lastFrame = ""  # Force full redraw
    }

    # Get performance info
    [hashtable] GetStats() {
        return @{
            FrameCount = $this._frameCount
            LastRenderTime = $this._lastRenderTime
            NeedsRender = $this._needsRender
        }
    }
}

# Grid frame builder - adapts Praxis CleanRender concepts for PMC grids
class PraxisGridFrameBuilder {
    static [string] BuildGridFrame([array]$data, [hashtable]$columns, [string]$title, [int]$selectedRow, [hashtable]$theme, [object]$renderer) {
        return [PraxisStringBuilderPool]::Build({
            param($sb)

            # Title
            if ($title) {
                $sb.AppendLine($title)
                $sb.AppendLine("─" * 50)  # Simple separator
            }

            # Use PMC's intelligent column width calculation
            $widths = $renderer.GetColumnWidths($data)

            # Column headers
            $headerParts = @()
            $separatorParts = @()
            $colNames = @($columns.Keys)
            foreach ($col in $colNames) {
                $config = $columns[$col]
                $width = $widths[$col]
                $header = $col
                if ($config -and $config.PSObject.Properties['Header'] -and $config.Header) { $header = $config.Header }

                $headerParts += [PraxisMeasure]::Pad($header, $width, "Left")
                $separatorParts += "─" * $width
            }
            $sb.AppendLine(($headerParts -join "  "))
            $sb.AppendLine(($separatorParts -join "  "))

            # Data rows
            for ($i = 0; $i -lt $data.Count; $i++) {
                $item = $data[$i]
                $isSelected = ($i -eq $selectedRow)
                $prefix = " "
                if ($isSelected) { $prefix = "►" }

                $rowParts = @()
                foreach ($col in $colNames) {
                    $width = $widths[$col]
                    # Prefer renderer's item value logic
                    $value = $renderer.GetItemValue($item, $col)
                    # If selected row is being actively edited, show live EditingValue
                    if ($isSelected -and $renderer.InlineEditMode -and $renderer.EditingColumn -eq $col) {
                        $value = [string]$renderer.EditingValue
                    }
                    # Otherwise, if selected row has a staged edit, show it
                    elseif ($isSelected -and $renderer.PendingEdits.ContainsKey($col)) {
                        $value = [string]$renderer.PendingEdits[$col]
                    }

                    # Show inline edit mode with background highlight (themeable)
                    $padded = [PraxisMeasure]::Pad($value, $width, "Left")
                    if ($isSelected -and $renderer.InlineEditMode -and $renderer.EditingColumn -eq $col) {
                        $editStyle = Get-PmcStyle 'Editing'
                        $padded = $renderer.ConvertPmcStyleToAnsi($padded, $editStyle, @{})
                    } elseif ($isSelected) {
                        # Apply selection highlight
                        $applyCell = $true
                        if ($renderer.NavigationMode -eq 'Cell') {
                            # Only highlight the selected column in Cell mode
                            $selIdx = [Math]::Min($colNames.Count-1, [Math]::Max(0, $renderer.SelectedColumn))
                            if ($col -ne $colNames[$selIdx]) { $applyCell = $false }
                        }
                        if ($applyCell) {
                            $selStyle = Get-PmcStyle 'Selected'
                            $padded = $renderer.ConvertPmcStyleToAnsi($padded, $selStyle, @{})
                        }
                    }
                    $rowParts += $padded
                }

                $sb.Append($prefix)
                $sb.AppendLine(($rowParts -join "  "))
            }

            # Status line (move to bottom)
            $consoleHeight = [PmcTerminalService]::GetHeight()
            $currentLine = $data.Count + 5  # Approximate current line
            $bottomLine = $consoleHeight - 1

            # Determine footer lines: optional error, optional hint, plus status
            $footerCount = 1
            $hasError = ($renderer.LastErrorMessage -and $renderer.LastErrorMessage.Length -gt 0)
            $hasHint = $renderer.InlineEditMode
            if ($hasError) { $footerCount++ }
            if ($hasHint) { $footerCount++ }

            if ($currentLine -lt $bottomLine) {
                # Add spacing to push footers to bottom
                $spacingNeeded = $bottomLine - $currentLine - $footerCount
                for ($i = 0; $i -lt $spacingNeeded; $i++) { $sb.AppendLine("") }
            }

            # Error line (highlighted)
            if ($hasError) {
                $err = $renderer.StyleText('Error', ("ERROR: {0}" -f $renderer.LastErrorMessage))
                $sb.AppendLine($err)
            }

            # Hint line during editing
            if ($hasHint) {
                $col = $renderer.EditingColumn
                $hint = $renderer.GetFieldHint($col)
                if (-not $hint) { $hint = 'Enter: Save, Esc: Cancel, Tab: Next, Shift+Tab: Prev' }
                $hintLine = $renderer.StyleText('Info', ("Editing {0} — {1}" -f $col, $hint))
                $sb.AppendLine($hintLine)
            }

            # Status line
            $statusText = "ROW [$($selectedRow + 1)/$($data.Count)] | Arrow keys: Navigate | Enter: Edit | Q: Exit"
            $sb.Append($statusText)
        })
    }
}