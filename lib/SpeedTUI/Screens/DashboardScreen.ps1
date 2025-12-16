# SpeedTUI Dashboard Screen - Main entry point and navigation hub

# Load dependencies
. "$PSScriptRoot/../Core/Component.ps1"
. "$PSScriptRoot/../Core/PerformanceMonitor.ps1"
. "$PSScriptRoot/../Services/ConfigurationService.ps1"
. "$PSScriptRoot/../Services/TimeTrackingService.ps1"
. "$PSScriptRoot/../Services/CommandService.ps1"
. "$PSScriptRoot/../BorderHelper.ps1"
# . "$PSScriptRoot/../Components/Table.ps1"
# . "$PSScriptRoot/../Components/Label.ps1"

class DashboardScreen : Component {
    [object]$ConfigService
    [object]$TimeService
    [object]$CommandService
    [object]$PerformanceMonitor
    [hashtable]$QuickStats = @{}
    [DateTime]$LastRefresh
    [string[]]$MenuOptions
    [int]$SelectedOption = 0
    
    DashboardScreen() : base() {
        $this.Initialize()
    }
    
    [void] Initialize() {
        # Initialize services
        try {
            $this.ConfigService = [ConfigurationService]::new()
            $this.TimeService = [TimeTrackingService]::new()
            $this.CommandService = [CommandService]::new()
            $this.PerformanceMonitor = Get-PerformanceMonitor
            
            # Set up performance monitoring
            $this.PerformanceMonitor.SetLogger($null)  # We'll handle our own logging for now
            
            # Initialize menu options
            $this.MenuOptions = @(
                "1. Time Tracking",
                "2. Command Library", 
                "3. Projects",
                "4. Tasks",
                "5. File Browser",
                "6. Text Editor",
                "7. System Monitoring",
                "8. Settings",
                "9. Import/Export",
                "10. Help & About",
                "0. Exit"
            )
            
            $this.RefreshQuickStats()
            $this.LastRefresh = [DateTime]::Now
            
            # Record initialization
            $this.PerformanceMonitor.IncrementCounter("dashboard.initialized", @{})
            
        } catch {
            Write-Host "Error initializing dashboard: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [string[]] Render() {
        $timing = Start-PerformanceTiming "DashboardScreen.Render"
        
        try {
            $lines = @()
            
            # Header
            $lines += $this.RenderHeader()
            $lines += ""
            
            # Quick Stats Section
            $lines += $this.RenderQuickStats()
            $lines += ""
            
            # Main Menu
            $lines += $this.RenderMainMenu()
            $lines += ""
            
            # Recent Activity
            $lines += $this.RenderRecentActivity()
            $lines += ""
            
            # Status Bar
            $lines += $this.RenderStatusBar()
            
            return $lines
            
        } finally {
            Stop-PerformanceTiming $timing
        }
    }
    
    [string[]] RenderHeader() {
        $lines = @()
        $appName = $this.ConfigService.GetSetting("Application.Name")
        $version = $this.ConfigService.GetSetting("Application.Version")
        $currentTime = Get-Date -Format "dddd, MMMM dd, yyyy - HH:mm:ss"
        
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::EmptyLine()
        $lines += [BorderHelper]::ContentLine("    ███████╗██████╗ ███████╗███████╗██████╗ ████████╗██╗   ██╗██╗    FAST • POWERFUL • INTEGRATED")
        $lines += [BorderHelper]::ContentLine("    ██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗╚══██╔══╝██║   ██║██║")
        $lines += [BorderHelper]::ContentLine("    ███████╗██████╔╝█████╗  █████╗  ██║  ██║   ██║   ██║   ██║██║    PowerShell Terminal Interface")
        $lines += [BorderHelper]::ContentLine("    ╚════██║██╔═══╝ ██╔══╝  ██╔══╝  ██║  ██║   ██║   ██║   ██║██║")
        $lines += [BorderHelper]::ContentLine("    ███████║██║     ███████╗███████╗██████╔╝   ██║   ╚██████╔╝██║    Version $version")
        $lines += [BorderHelper]::ContentLine("    ╚══════╝╚═╝     ╚══════╝╚══════╝╚═════╝    ╚═╝    ╚═════╝ ╚═╝")
        $lines += [BorderHelper]::EmptyLine()
        $lines += [BorderHelper]::ContentLine($currentTime.PadLeft(([Console]::WindowWidth - 4) / 2 + $currentTime.Length / 2))
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string[]] RenderQuickStats() {
        $lines = @()
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::ContentLine("Quick Statistics".PadLeft(([Console]::WindowWidth - 4) / 2 + 8))
        $lines += [BorderHelper]::MiddleBorder()
        
        try {
            # Get stats from services
            $totalCommands = ($this.CommandService.GetAll()).Count
            $totalProjects = 0  # Will implement when ProjectService is ready
            $totalTimeEntries = ($this.TimeService.GetAll()).Count
            $currentFY = $this.TimeService.CurrentFiscalYear
            
            # Performance stats
            $currentProcess = [System.Diagnostics.Process]::GetCurrentDoProcess()
            $memoryMB = [Math]::Round($currentProcess.WorkingSet64 / 1MB, 1)
            $uptime = [DateTime]::Now - $currentProcess.StartTime
            $uptimeStr = $uptime.ToString("d\.hh\:mm")
            
            $lines += [BorderHelper]::EmptyLine()
            $commandsStr = "📊 COMMANDS: $($totalCommands.ToString().PadLeft(4))"
            $projectsStr = "🎯 PROJECTS: $($totalProjects.ToString().PadLeft(4))"
            $entriesStr = "⏱️  TIME ENTRIES: $($totalTimeEntries.ToString().PadLeft(4))"
            $lines += [BorderHelper]::ContentLine("    $($commandsStr.PadRight(25)) $($projectsStr.PadRight(25)) $entriesStr")
            $lines += [BorderHelper]::EmptyLine()
            $fiscalStr = "📅 FISCAL YEAR: $($currentFY.PadRight(12))"
            $memoryStr = "💾 MEMORY: $($memoryMB.ToString('F1').PadLeft(6)) MB"
            $uptimeStr2 = "⏰ UPTIME: $($uptimeStr.PadLeft(8))"
            $lines += [BorderHelper]::ContentLine("    $($fiscalStr.PadRight(30)) $($memoryStr.PadRight(25)) $uptimeStr2")
            $lines += [BorderHelper]::EmptyLine()
            
        } catch {
            $errorMsg = $_.Exception.Message
            if ($errorMsg.Length -gt ([Console]::WindowWidth - 10)) {
                $errorMsg = $errorMsg.Substring(0, [Console]::WindowWidth - 13) + "..."
            }
            $lines += [BorderHelper]::ContentLine("Error loading statistics: $errorMsg")
            $lines += [BorderHelper]::EmptyLine()
        }
        
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string[]] RenderMainMenu() {
        $lines = @()
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::ContentLine("Main Menu".PadLeft(([Console]::WindowWidth - 4) / 2 + 5))
        $lines += [BorderHelper]::MiddleBorder()
        $lines += [BorderHelper]::EmptyLine()
        
        # Split menu into two columns
        $leftColumn = $this.MenuOptions[0..4]
        $rightColumn = $this.MenuOptions[5..($this.MenuOptions.Count-1)]
        
        $maxRows = [Math]::Max($leftColumn.Count, $rightColumn.Count)
        $colWidth = ([Console]::WindowWidth - 10) / 2
        
        for ($i = 0; $i -lt $maxRows; $i++) {
            $leftItem = $(if ($i -lt $leftColumn.Count) { $leftColumn[$i] } else { "" })
            $rightItem = $(if ($i -lt $rightColumn.Count) { $rightColumn[$i] } else { "" })
            
            # Highlight selected option
            if ($this.SelectedOption -eq $i -or $this.SelectedOption -eq ($i + 5)) {
                if ($this.SelectedOption -eq $i) {
                    $leftItem = "► $leftItem"
                }
                if ($this.SelectedOption -eq ($i + 5)) {
                    $rightItem = "► $rightItem"
                }
            }
            
            $leftPadded = $leftItem.PadRight($colWidth)
            $rightPadded = $rightItem.PadRight($colWidth)
            
            $lines += [BorderHelper]::ContentLine("  $leftPadded │  $rightPadded")
        }
        
        $lines += [BorderHelper]::EmptyLine()
        $lines += [BorderHelper]::ContentLine("  Use ↑↓ arrows or number keys to select, Enter to activate, Tab for quick access")
        $lines += [BorderHelper]::EmptyLine()
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string[]] RenderRecentActivity() {
        $lines = @()
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::ContentLine("Recent Activity".PadLeft(([Console]::WindowWidth - 4) / 2 + 7))
        $lines += [BorderHelper]::MiddleBorder()
        
        try {
            # Get recent performance metrics to show activity
            $recentMetrics = $this.PerformanceMonitor.GetMetrics(5)
            
            if ($recentMetrics.Count -gt 0) {
                foreach ($metric in ($recentMetrics | Sort-Object Timestamp -Descending | Select-Object -First 3)) {
                    $time = $metric.Timestamp.ToString("HH:mm:ss")
                    $activity = $this.FormatActivityMessage($metric)
                    $maxActivityLength = [Console]::WindowWidth - 15
                    if ($activity.Length -gt $maxActivityLength) {
                        $activity = $activity.Substring(0, $maxActivityLength - 3) + "..."
                    }
                    $lines += [BorderHelper]::ContentLine("$time - $activity")
                }
            } else {
                $lines += [BorderHelper]::ContentLine("No recent activity. Start using SpeedTUI to see activity here.")
                $lines += [BorderHelper]::EmptyLine()
            }
            
            # Fill to consistent height
            while (($lines.Count - 3) -lt 4) {
                $lines += [BorderHelper]::EmptyLine()
            }
            
        } catch {
            $errorMsg = $_.Exception.Message
            $maxErrorLength = [Console]::WindowWidth - 35
            if ($errorMsg.Length -gt $maxErrorLength) {
                $errorMsg = $errorMsg.Substring(0, $maxErrorLength - 3) + "..."
            }
            $lines += [BorderHelper]::ContentLine("Error loading recent activity: $errorMsg")
            $lines += [BorderHelper]::EmptyLine()
        }
        
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string] FormatActivityMessage([object]$metric) {
        $name = $metric.Name
        
        switch -Regex ($name) {
            '^timing\..*' {
                $operation = $name -replace '^timing\.', ''
                return "Completed operation: $operation ($($metric.Value.ToString('F0'))ms)"
            }
            '^counter\..*' {
                $counter = $name -replace '^counter\.', ''
                return "Activity: $counter (count: $($metric.Value))"
            }
            '^system\..*' {
                return "System metric updated: $($name -replace '^system\.', '') = $($metric.Value)$($metric.Unit)"
            }
            default {
                return "Metric recorded: $name = $($metric.Value)$($metric.Unit)"
            }
        }
        return "Unknown metric: $name"
    }
    
    [string[]] RenderStatusBar() {
        $lines = @()
        
        # Get current status information
        $debugMode = $(if ($this.ConfigService.IsDebugMode()) { "DEBUG" } else { "NORMAL" })
        $autoSave = $(if ($this.ConfigService.GetSetting("Application.AutoSave")) { "AUTO-SAVE" } else { "MANUAL" })
        $theme = $this.ConfigService.GetSetting("UI.Theme")
        
        $statusLine = "Mode: $debugMode │ Save: $autoSave │ Theme: $theme │ Press F1 for Help │ F11 for Monitor │ Ctrl+Q to Exit"
        
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::ContentLine($statusLine)
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string] HandleInput([string]$key) {
        $timing = Start-PerformanceTiming "DashboardScreen.HandleInput" @{ key = $key }
        
        try {
            switch ($key) {
                # Number keys for direct menu access
                '1' { return $this.NavigateToScreen("TimeTracking") }
                '2' { return $this.NavigateToScreen("CommandLibrary") }
                '3' { return $this.NavigateToScreen("Projects") }
                '4' { return $this.NavigateToScreen("Tasks") }
                '5' { return $this.NavigateToScreen("FileBrowser") }
                '6' { return $this.NavigateToScreen("TextEditor") }
                '7' { return $this.NavigateToScreen("SystemMonitoring") }
                '8' { return $this.NavigateToScreen("Settings") }
                '9' { return $this.NavigateToScreen("ImportExport") }
                '1' { return $this.NavigateToScreen("HelpAbout") }
                '0' { return "EXIT" }
                
                # Arrow key navigation
                'UpArrow' {
                    $this.SelectedOption = $(if ($this.SelectedOption -gt 0) { $this.SelectedOption - 1 } else { $this.MenuOptions.Count - 1 })
                    $this.PerformanceMonitor.IncrementCounter("dashboard.navigation.up", @{})
                    return "REFRESH"
                }
                'DownArrow' {
                    $this.SelectedOption = $(if ($this.SelectedOption -lt ($this.MenuOptions.Count - 1)) { $this.SelectedOption + 1 } else { 0 })
                    $this.PerformanceMonitor.IncrementCounter("dashboard.navigation.down", @{})
                    return "REFRESH"
                }
                'Enter' {
                    return $this.ActivateSelectedOption()
                }
                
                # Function keys
                'F1' { return $this.NavigateToScreen("HelpAbout") }
                'F11' { return $this.NavigateToScreen("SystemMonitoring") }
                
                # Quick refresh
                'F5' {
                    $this.RefreshQuickStats()
                    $this.PerformanceMonitor.IncrementCounter("dashboard.refresh", @{})
                    return "REFRESH"
                }
                
                # Configuration shortcuts
                'Ctrl+,' { return $this.NavigateToScreen("Settings") }
                'Ctrl+Q' { return "EXIT" }
                
                default {
                    return "CONTINUE"
                }
            }
        } finally {
            Stop-PerformanceTiming $timing
        }
        return "CONTINUE"
    }
    
    [string] NavigateToScreen([string]$screenName) {
        $this.PerformanceMonitor.IncrementCounter("dashboard.navigation", @{ screen = $screenName })
        
        switch ($screenName) {
            "SystemMonitoring" {
                return "MONITOR"  # Signal to show monitoring screen
            }
            "Settings" {
                Write-Host "Opening Settings..." -ForegroundColor Green
                return "CONTINUE"  # For now, just acknowledge
            }
            "TimeTracking" {
                Write-Host "Opening Time Tracking..." -ForegroundColor Green
                return "TIMETRACKING"
            }
            "CommandLibrary" {
                Write-Host "Opening Command Library..." -ForegroundColor Green
                return "CONTINUE"
            }
            "HelpAbout" {
                $this.ShowHelpAbout()
                return "CONTINUE"
            }
            default {
                Write-Host "Screen '$screenName' not yet implemented" -ForegroundColor Yellow
                return "CONTINUE"
            }
        }
        return "CONTINUE"
    }
    
    [string] ActivateSelectedOption() {
        $selectedIndex = $this.SelectedOption + 1  # Convert to 1-based for menu numbers
        if ($selectedIndex -eq 10) { $selectedIndex = 0 }  # Handle exit option
        
        return $this.HandleInput($selectedIndex.ToString())
    }
    
    [void] RefreshQuickStats() {
        $timing = Start-PerformanceTiming "DashboardScreen.RefreshQuickStats"
        
        try {
            # Update stats (services will be called when they exist)
            $this.LastRefresh = [DateTime]::Now
            # Record system metrics if available
            if ($this.PerformanceMonitor.PSObject.Methods['RecordSystemMetrics']) {
                $this.PerformanceMonitor.RecordSystemMetrics()
            }
            
        } catch {
            Write-Host "Error refreshing stats: $($_.Exception.Message)" -ForegroundColor Red
        } finally {
            Stop-PerformanceTiming $timing
        }
    }
    
    [void] ShowHelpAbout() {
        $help = @(
            "",
            "SpeedTUI - PowerShell Terminal User Interface",
            "=============================================",
            "",
            "A high-performance, feature-rich terminal interface designed for PowerShell users.",
            "",
            "Key Features:",
            "• Fast, responsive interface optimized for speed",
            "• Comprehensive project and time tracking",
            "• Extensive command library with usage tracking",
            "• Built-in text editor and file browser",
            "• Real-time system monitoring and performance metrics",
            "• Configurable themes and settings",
            "• Excel import/export capabilities",
            "",
            "Navigation:",
            "• Use number keys (1-9, 0) for quick menu access",
            "• Use arrow keys to navigate, Enter to select",
            "• F1 for help, F11 for system monitor, F5 to refresh",
            "• Ctrl+Q to exit, Ctrl+, for settings",
            "",
            "Performance:",
            "• Real-time performance monitoring built-in",
            "• Optimized data structures and caching",
            "• Minimal memory footprint and fast startup",
            "",
            "Version: $($this.ConfigService.GetSetting('Application.Version'))",
            "PowerShell Version: $((Get-Host).Version)",
            "",
            "Press any key to continue..."
        )
        
        Write-Host ($help -join "`n") -ForegroundColor Cyan
        $null = Read-Host
        
        $this.PerformanceMonitor.IncrementCounter("dashboard.help_viewed", @{})
    }
}