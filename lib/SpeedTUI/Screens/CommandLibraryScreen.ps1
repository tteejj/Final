# SpeedTUI Command Library Screen - Command management and execution

# Load dependencies
. "$PSScriptRoot/../Core/Component.ps1"
. "$PSScriptRoot/../Core/PerformanceMonitor.ps1"
. "$PSScriptRoot/../Services/CommandService.ps1"

class CommandLibraryScreen : Component {
    [object]$CommandService
    [object]$PerformanceMonitor
    [array]$Commands = @()
    [int]$SelectedCommand = 0
    [string]$ViewMode = "List"  # List, Add, Edit, Execute
    [hashtable]$NewCommand = @{}
    [string]$SearchFilter = ""
    [DateTime]$LastRefresh
    
    CommandLibraryScreen() : base() {
        $this.Initialize()
    }
    
    [void] Initialize() {
        try {
            $this.CommandService = [CommandService]::new()
            $this.PerformanceMonitor = Get-PerformanceMonitor
            $this.RefreshData()
            $this.LastRefresh = [DateTime]::Now
            
            $this.PerformanceMonitor.RecordMetric("screen.commandlibrary.initialized", 1, "count")
        } catch {
            Write-Host "Error initializing command library: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [string[]] Render() {
        $timing = Start-PerformanceTiming "CommandLibraryScreen.Render"
        
        try {
            $lines = @()
            
            # Header
            $lines += $this.RenderHeader()
            $lines += ""
            
            switch ($this.ViewMode) {
                "List" {
                    $lines += $this.RenderCommandsList()
                }
                "Add" {
                    $lines += $this.RenderAddCommand()
                }
                "Edit" {
                    $lines += $this.RenderEditCommand()
                }
                "Execute" {
                    $lines += $this.RenderExecuteCommand()
                }
            }
            
            $lines += ""
            $lines += $this.RenderControls()
            
            return $lines
            
        } finally {
            Stop-PerformanceTiming $timing
        }
    }
    
    [string[]] RenderHeader() {
        $lines = @()
        $totalCommands = $this.Commands.Count
        $totalExecutions = ($this.Commands | Measure-Object -Property UsageCount -Sum).Sum
        $filterStatus = $(if ($this.SearchFilter) { "Filtered: '$($this.SearchFilter)'" } else { "All Commands" })
        
        $lines += "╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗"
        $lines += "║                                            COMMAND LIBRARY MANAGEMENT                                             ║"
        $lines += "║    Total Commands: $($totalCommands.ToString().PadLeft(4)) │ Total Executions: $($totalExecutions.ToString().PadLeft(6)) │ View: $($filterStatus.PadRight(20))           ║"
        $lines += "╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝"
        
        return $lines
    }
    
    [string[]] RenderCommandsList() {
        $lines = @()
        $lines += "┌─ Command Library ──────────────────────────────────────────────────────────────────────────────────────────────┐"
        
        if ($this.Commands.Count -eq 0) {
            $lines += "│ No commands found. Press 'A' to add your first command.                                                      │"
            $lines += "│                                                                                                                │"
        } else {
            $lines += "│ Name                     │ Category       │ Usage │ Last Used    │ Description                         │"
            $lines += "├──────────────────────────┼────────────────┼───────┼──────────────┼─────────────────────────────────────┤"
            
            # Show commands (filtered if needed)
            $commandsToShow = $this.Commands
            if ($this.SearchFilter) {
                $commandsToShow = $this.Commands | Where-Object { 
                    $_.Name -like "*$($this.SearchFilter)*" -or 
                    $_.Category -like "*$($this.SearchFilter)*" -or 
                    $_.Description -like "*$($this.SearchFilter)*"
                }
            }
            
            $commandsToShow = $commandsToShow | Sort-Object LastUsed -Descending | Select-Object -First 15
            $index = 0
            foreach ($command in $commandsToShow) {
                $marker = $(if ($index -eq $this.SelectedCommand) { "►" } else { " " })
                $nameStr = $command.Name.PadRight(24)
                if ($nameStr.Length -gt 24) { $nameStr = $nameStr.Substring(0, 21) + "..." }
                $categoryStr = $command.Category.PadRight(14)
                if ($categoryStr.Length -gt 14) { $categoryStr = $categoryStr.Substring(0, 11) + "..." }
                $usageStr = $command.UsageCount.ToString().PadLeft(5)
                $lastUsedStr = $(if ($command.LastUsed) { 
                    $command.LastUsed.ToString("MM/dd/yy").PadRight(12)
                } else { 
                    "Never".PadRight(12)
                })
                $descStr = $command.Description.PadRight(35)
                if ($descStr.Length -gt 35) { $descStr = $descStr.Substring(0, 32) + "..." }
                
                $lines += "│$marker$nameStr │ $categoryStr │ $usageStr │ $lastUsedStr │ $descStr │"
                $index++
            }
            
            # Fill remaining lines
            while (($lines.Count - 3) -lt 15) {
                $lines += "│                                                                                                                │"
            }
        }
        
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string[]] RenderAddCommand() {
        $lines = @()
        $lines += "┌─ Add New Command ──────────────────────────────────────────────────────────────────────────────────────────────┐"
        $lines += "│                                                                                                                │"
        $lines += "│ Name: $($this.NewCommand.Name.PadRight(86)) │"
        $lines += "│ Category: $($this.NewCommand.Category.PadRight(82)) │"
        $lines += "│ Command: $($this.NewCommand.CommandText.PadRight(81)) │"
        $lines += "│ Description: $($this.NewCommand.Description.PadRight(77)) │"
        $lines += "│ Tags: $($this.NewCommand.Tags.PadRight(86)) │"
        $lines += "│                                                                                                                │"
        $lines += "│ Press S to Save, C to Cancel                                                                                  │"
        $lines += "│                                                                                                                │"
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string[]] RenderEditCommand() {
        $lines = @()
        $lines += "┌─ Edit Command ─────────────────────────────────────────────────────────────────────────────────────────────────┐"
        $lines += "│                                                                                                                │"
        $lines += "│ [Edit mode not yet implemented]                                                                               │"
        $lines += "│                                                                                                                │"
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string[]] RenderExecuteCommand() {
        $lines = @()  
        $lines += "┌─ Execute Command ──────────────────────────────────────────────────────────────────────────────────────────────┐"
        $lines += "│                                                                                                                │"
        
        if ($this.Commands.Count -gt 0 -and $this.SelectedCommand -lt $this.Commands.Count) {
            $command = $this.Commands[$this.SelectedCommand]
            $lines += "│ Command: $($command.Name.PadRight(83)) │"
            $lines += "│ Category: $($command.Category.PadRight(82)) │"
            $lines += "│ Description: $($command.Description.PadRight(77)) │"
            $lines += "│                                                                                                                │"
            $lines += "│ Command Text:                                                                                              │"
            $lines += "│ $($command.CommandText.PadRight(95)) │"
            $lines += "│                                                                                                                │"
            $lines += "│ Press Enter to Execute, C to Cancel                                                                       │"
        } else {
            $lines += "│ No command selected                                                                                           │"
        }
        
        $lines += "│                                                                                                                │"
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string[]] RenderControls() {
        $lines = @()
        $lines += "┌─ Controls ─────────────────────────────────────────────────────────────────────────────────────────────────────┐"
        
        switch ($this.ViewMode) {
            "List" {
                $lines += "│ A - Add │ E - Edit │ D - Delete │ X - Execute │ F - Filter │ R - Refresh │ B - Back │ Q - Quit        │"
            }
            "Add" {
                $lines += "│ S - Save Command │ C - Cancel │ Tab - Next Field │ Shift+Tab - Previous Field                           │"
            }
            "Edit" {
                $lines += "│ S - Save Changes │ C - Cancel │ Tab - Next Field │ Shift+Tab - Previous Field                          │"
            }
            "Execute" {
                $lines += "│ Enter - Execute Command │ C - Cancel │ Esc - Back to List                                              │"
            }
        }
        
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string] HandleInput([string]$key) {
        $timing = Start-PerformanceTiming "CommandLibraryScreen.HandleInput" @{ key = $key }
        
        try {
            switch ($this.ViewMode) {
                "List" {
                    return $this.HandleListInput($key)
                }
                "Add" {
                    return $this.HandleAddInput($key)
                }
                "Edit" {
                    return $this.HandleEditInput($key)
                }
                "Execute" {
                    return $this.HandleExecuteInput($key)
                }
            }
        } finally {
            Stop-PerformanceTiming $timing
        }
        return "CONTINUE"
    }
    
    [string] HandleListInput([string]$key) {
        switch ($key.ToUpper()) {
            'A' {
                $this.ViewMode = "Add"
                $this.InitializeNewCommand()
                return "REFRESH"
            }
            'E' {
                if ($this.Commands.Count -gt 0) {
                    $this.ViewMode = "Edit"
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'D' {
                $this.DeleteSelectedCommand()
                return "REFRESH"
            }
            'X' {
                if ($this.Commands.Count -gt 0) {
                    $this.ViewMode = "Execute"
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'F' {
                Write-Host "Enter search filter (or press Enter for all): " -NoNewline -ForegroundColor Yellow
                $this.SearchFilter = Read-Host
                $this.RefreshData()
                return "REFRESH"
            }
            'R' {
                $this.SearchFilter = ""
                $this.RefreshData()
                return "REFRESH"
            }
            'B' {
                return "DASHBOARD"
            }
            'Q' {
                return "EXIT"
            }
            'UpArrow' {
                if ($this.SelectedCommand -gt 0) {
                    $this.SelectedCommand--
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'DownArrow' {
                if ($this.SelectedCommand -lt ($this.Commands.Count - 1)) {
                    $this.SelectedCommand++
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            default {
                return "CONTINUE"
            }
        }
    }
    
    [string] HandleAddInput([string]$key) {
        switch ($key.ToUpper()) {
            'S' {
                $this.SaveNewCommand()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            'C' {
                $this.ViewMode = "List"
                return "REFRESH"
            }
            default {
                return "CONTINUE"
            }
        }
    }
    
    [string] HandleEditInput([string]$key) {
        switch ($key.ToUpper()) {
            'S' {
                $this.ViewMode = "List"
                return "REFRESH"
            }
            'C' {
                $this.ViewMode = "List"
                return "REFRESH"
            }
            default {
                return "CONTINUE"
            }
        }
    }
    
    [string] HandleExecuteInput([string]$key) {
        switch ($key) {
            'Enter' {
                $this.ExecuteSelectedCommand()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            'C' {
                $this.ViewMode = "List"
                return "REFRESH"
            }
            'Escape' {
                $this.ViewMode = "List"
                return "REFRESH"
            }
            default {
                return "CONTINUE"
            }
        }
    }
    
    [void] RefreshData() {
        try {
            $this.Commands = $this.CommandService.GetAll()
            $this.LastRefresh = [DateTime]::Now
            $this.PerformanceMonitor.RecordMetric("screen.commandlibrary.refresh", 1, "count")
        } catch {
            Write-Host "Error refreshing commands: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] InitializeNewCommand() {
        $this.NewCommand = @{
            Name = ""
            Category = ""
            CommandText = ""
            Description = ""
            Tags = ""
        }
    }
    
    [void] SaveNewCommand() {
        try {
            $command = [Command]::new()
            $command.Name = $this.NewCommand.Name
            $command.Category = $this.NewCommand.Category
            $command.CommandText = $this.NewCommand.CommandText
            $command.Description = $this.NewCommand.Description
            $command.Tags = $this.NewCommand.Tags -split ","
            
            $this.CommandService.Add($command)
            $this.RefreshData()
            
            Write-Host "Command saved successfully!" -ForegroundColor Green
            $this.PerformanceMonitor.RecordMetric("screen.commandlibrary.command_added", 1, "count")
        } catch {
            Write-Host "Error saving command: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] DeleteSelectedCommand() {
        if ($this.Commands.Count -eq 0 -or $this.SelectedCommand -ge $this.Commands.Count) {
            return
        }
        
        try {
            $command = $this.Commands[$this.SelectedCommand]
            $this.CommandService.Remove($command.Id)
            $this.RefreshData()
            
            # Adjust selection if needed
            if ($this.SelectedCommand -ge $this.Commands.Count -and $this.Commands.Count -gt 0) {
                $this.SelectedCommand = $this.Commands.Count - 1
            }
            
            Write-Host "Command deleted successfully!" -ForegroundColor Green
            $this.PerformanceMonitor.RecordMetric("screen.commandlibrary.command_deleted", 1, "count")
        } catch {
            Write-Host "Error deleting command: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] ExecuteSelectedCommand() {
        if ($this.Commands.Count -eq 0 -or $this.SelectedCommand -ge $this.Commands.Count) {
            return
        }
        
        try {
            $command = $this.Commands[$this.SelectedCommand]
            Write-Host "Executing: $($command.Name)" -ForegroundColor Green
            Write-Host "Command: $($command.CommandText)" -ForegroundColor Gray
            
            # Execute the command
            $result = Invoke-Expression $command.CommandText
            
            # Update usage statistics
            $command.UsageCount++
            $command.LastUsed = [DateTime]::Now
            $this.CommandService.Update($command)
            
            Write-Host "Command executed successfully!" -ForegroundColor Green
            if ($result) {
                Write-Host "Output: $result" -ForegroundColor Cyan
            }
            
            $this.PerformanceMonitor.RecordMetric("screen.commandlibrary.command_executed", 1, "count")
            
            Write-Host "Press any key to continue..." -ForegroundColor Yellow
            $null = Read-Host
            
        } catch {
            Write-Host "Error executing command: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Press any key to continue..." -ForegroundColor Yellow
            $null = Read-Host
        }
    }
}