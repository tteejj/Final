using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

# Ensure PmcWidget is loaded
if (-not ([System.Management.Automation.PSTypeName]'PmcWidget').Type) {
    . "$PSScriptRoot/PmcWidget.ps1"
}

<#
.SYNOPSIS
Dialog to show individual time entries within an aggregated group
#>
class TimeEntryDetailDialog : PmcWidget {
    [string]$Title
    [array]$Entries
    # [int]$Width  # Inherited
    # [int]$Height # Inherited
    [bool]$IsComplete = $false
    [int]$ScrollOffset = 0
    [int]$SelectedIndex = 0

    TimeEntryDetailDialog([string]$title, [array]$entries) : base("TimeEntryDetail") {
        $this.Title = $title
        $this.Entries = $entries
        $this.Width = 80
        $this.Height = [Math]::Min(25, $entries.Count + 7)
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

        # Colors
        # Use Panel background
        $bg = [HybridRenderEngine]::AnsiColorToInt($this.GetThemedBg('Background.Panel', 1, 0))
        $fg = [HybridRenderEngine]::AnsiColorToInt($this.GetThemedFg('Foreground.Row'))
        $borderFg = [HybridRenderEngine]::AnsiColorToInt($this.GetThemedFg('Border.Widget'))
        $highlightFg = [HybridRenderEngine]::AnsiColorToInt($this.GetThemedFg('Foreground.Title'))
        $selectedBg = [HybridRenderEngine]::AnsiColorToInt($this.GetThemedBg('Background.RowSelected', 1, 0))
        
        if ($bg -eq -1) { $bg = [HybridRenderEngine]::_PackRGB(45, 55, 72) }

        # Draw Box
        $engine.Fill($this.X, $this.Y, $this.Width, $this.Height, ' ', $fg, $bg)
        $engine.DrawBox($this.X, $this.Y, $this.Width, $this.Height, $borderFg, $bg)
        
        # Title
        $pad = [Math]::Max(0, [Math]::Floor(($this.Width - 4 - $this.Title.Length) / 2))
        $engine.WriteAt($this.X + 2 + $pad, $this.Y + 1, $this.Title, $highlightFg, $bg)
        
        # Header
        $headerText = " Task".PadRight(25) + " Hours  " + " Notes"
        # Manual clip if needed - header is fixed width usually
        $engine.WriteAt($this.X + 2, $this.Y + 2, $headerText, $highlightFg, $bg)
        
        # Separator 1
        $engine.WriteAt($this.X, $this.Y + 3, "├" + ("─" * ($this.Width - 2)) + "┤", $borderFg, $bg)
        
        # List Area
        $listX = $this.X + 2
        $listY = $this.Y + 4
        $listWidth = $this.Width - 4
        $listHeight = $this.Height - 6
        
        for ($i = 0; $i -lt $listHeight; $i++) {
            $entryIndex = $this.ScrollOffset + $i
            if ($entryIndex -ge $this.Entries.Count) { break }
            
            $entry = $this.Entries[$entryIndex]
            $isSelected = ($entryIndex -eq $this.SelectedIndex)
            
            $iBg = if ($isSelected) { $selectedBg } else { $bg }
            
            # Format
            $task = if ($entry.ContainsKey('task')) { $entry.task } else { '' }
            if ($task.Length -gt 24) { $task = $task.Substring(0, 21) + "..." }
            
            $minutes = if ($entry.ContainsKey('minutes')) { $entry.minutes } else { 0 }
            $hours = [Math]::Round($minutes / 60.0, 2)
            
            $notes = if ($entry.ContainsKey('notes')) { $entry.notes } else { '' }
            $maxNotesLen = $this.Width - 35
            if ($notes.Length -gt $maxNotesLen) { $notes = $notes.Substring(0, $maxNotesLen - 3) + "..." }
            
            $line = " $($task.PadRight(24)) $($hours.ToString('0.00').PadLeft(5))  $notes"
            
            # Ensure line fits
            if ($line.Length -gt $listWidth) { $line = $line.Substring(0, $listWidth) }
            
            $engine.Fill($listX, $listY + $i, $listWidth, 1, ' ', $fg, $iBg)
            $engine.WriteAt($listX, $listY + $i, $line, $fg, $iBg)
        }
        
        # Separator 2
        $engine.WriteAt($this.X, $this.Y + $this.Height - 3, "├" + ("─" * ($this.Width - 2)) + "┤", $borderFg, $bg)
        
        # Footer
        $footer = " ↑/↓: Navigate  Enter/Esc: Close"
        $engine.WriteAt($this.X + 2, $this.Y + $this.Height - 2, $footer, $fg, $bg)
    }



    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this.SelectedIndex -gt 0) {
                    $this.SelectedIndex--
                    # Adjust scroll if needed
                    if ($this.SelectedIndex -lt $this.ScrollOffset) {
                        $this.ScrollOffset = $this.SelectedIndex
                    }
                }
                return $true
            }
            'DownArrow' {
                if ($this.SelectedIndex -lt ($this.Entries.Count - 1)) {
                    $this.SelectedIndex++
                    # Adjust scroll if needed
                    $maxVisible = $this.Height - 6  # 6 rows for border/header/footer
                    if ($this.SelectedIndex -ge ($this.ScrollOffset + $maxVisible)) {
                        $this.ScrollOffset = $this.SelectedIndex - $maxVisible + 1
                    }
                }
                return $true
            }
            'Enter' {
                $this.IsComplete = $true
                return $true
            }
            'Escape' {
                $this.IsComplete = $true
                return $true
            }
        }
        return $false
    }
}