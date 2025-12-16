# SpeedTUI Monitoring Screen - Real-time performance and system monitoring

# Load dependencies
. "$PSScriptRoot/../Core/Component.ps1"
. "$PSScriptRoot/../Core/PerformanceMonitor.ps1"
# . "$PSScriptRoot/../Components/Table.ps1"
# . "$PSScriptRoot/../Components/Label.ps1"

class MonitoringScreen : Component {
    [object]$PerformanceMonitor
    [hashtable]$LastMetrics = @{}
    [DateTime]$LastRefresh
    [int]$RefreshInterval = 2000  # 2 seconds
    [bool]$AutoRefresh = $true
    
    MonitoringScreen() : base() {
        $this.ComponentType = "MonitoringScreen"
        $this.Width = 120
        $this.Height = 30
        $this.PerformanceMonitor = Get-PerformanceMonitor
        $this.LastRefresh = [DateTime]::Now
        
        $this.Initialize()
    }
    
    [void] Initialize() {
        # Start collecting system metrics
        $this.PerformanceMonitor.RecordSystemMetrics()
        
        # Record initialization
        $this.PerformanceMonitor.IncrementCounter("screen.monitoring.initialized", @{})
    }
    
    [string[]] Render() {
        $timing = Start-PerformanceTiming "MonitoringScreen.Render"
        
        try {
            $lines = @()
            
            # Header
            $lines += $this.RenderHeader()
            $lines += ""
            
            # System Overview
            $lines += $this.RenderSystemOverview()
            $lines += ""
            
            # Performance Metrics
            $lines += $this.RenderPerformanceMetrics()
            $lines += ""
            
            # Recent Activity
            $lines += $this.RenderRecentActivity()
            $lines += ""
            
            # Help
            $lines += $this.RenderHelp()
            
            # Update refresh time
            $this.LastRefresh = [DateTime]::Now
            
            return $lines
            
        } finally {
            Stop-PerformanceTiming $timing
        }
    }
    
    [string[]] RenderHeader() {
        $lines = @()
        $lines += "╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗"
        $lines += "║                                            SPEEDTUI SYSTEM MONITOR                                                ║"
        $lines += "║                                          Last Updated: $(Get-Date -Format 'HH:mm:ss')                                                ║"
        $lines += "╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝"
        
        return $lines
    }
    
    [string[]] RenderSystemOverview() {
        $lines = @()
        $lines += "┌─ System Overview ──────────────────────────────────────────────────────────────────────────────────────────────┐"
        
        try {
            # Get current process info
            $currentProcess = [System.Diagnostics.Process]::GetCurrentDoProcess()
            $processId = $currentProcess.Id
            
            # Memory usage
            $workingSetMB = [Math]::Round($currentProcess.WorkingSet64 / 1MB, 2)
            $privateMB = [Math]::Round($currentProcess.PrivateMemorySize64 / 1MB, 2)
            
            # CPU time
            $cpuTime = $currentProcess.TotalProcessorTime.TotalSeconds
            
            # Threads and handles
            $threads = $currentProcess.Threads.Count
            $handles = $currentProcess.HandleCount
            
            # GC info
            $gen0 = [GC]::CollectionCount(0)
            $gen1 = [GC]::CollectionCount(1)
            $gen2 = [GC]::CollectionCount(2)
            $gcMemoryMB = [Math]::Round([GC]::GetTotalMemory($false) / 1MB, 2)
            
            # Uptime
            $uptime = [DateTime]::Now - $currentProcess.StartTime
            
            $lines += "│ Process ID: $($processId.ToString().PadRight(10)) │ Uptime: $($uptime.ToString('d\.hh\:mm\:ss').PadRight(15)) │ PowerShell: $((Get-Host).Version.ToString().PadRight(10)) │"
            $lines += "│ Working Set: $($workingSetMB.ToString('F2').PadLeft(8)) MB │ Private Memory: $($privateMB.ToString('F2').PadLeft(8)) MB │ GC Memory: $($gcMemoryMB.ToString('F2').PadLeft(8)) MB │"
            $lines += "│ CPU Time: $($cpuTime.ToString('F2').PadLeft(10)) s │ Threads: $($threads.ToString().PadLeft(6)) │ Handles: $($handles.ToString().PadLeft(6)) │ GC: $gen0/$gen1/$gen2    │"
            
        } catch {
            $lines += "│ Error retrieving system information: $($_.Exception.Message.Substring(0, [Math]::Min(80, $_.Exception.Message.Length))) │"
        }
        
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string[]] RenderPerformanceMetrics() {
        $lines = @()
        $lines += "┌─ Performance Metrics ──────────────────────────────────────────────────────────────────────────────────────────┐"
        
        try {
            # Get recent timing metrics
            $timingMetrics = $this.PerformanceMonitor.GetMetricsByName("timing", 20)
            
            if ($timingMetrics.Count -gt 0) {
                # Group by operation and get stats
                $grouped = $timingMetrics | Group-Object { $_.Name -replace '^timing\.', '' }
                
                $lines += "│ Operation                    │ Count │ Avg (ms) │ Min (ms) │ Max (ms) │ Last (ms) │"
                $lines += "├─────────────────────────────┼───────┼──────────┼──────────┼──────────┼───────────┤"
                
                foreach ($group in ($grouped | Sort-Object Name | Select-Object -First 8)) {
                    $stats = $this.PerformanceMonitor.GetSummaryStats("timing.$($group.Name)")
                    $opName = $group.Name.PadRight(28)
                    if ($opName.Length -gt 28) {
                        $opName = $opName.Substring(0, 25) + "..."
                    }
                    
                    $count = $stats.Count.ToString().PadLeft(5)
                    $avg = $stats.Average.ToString("F2").PadLeft(8)
                    $min = $stats.Min.ToString("F2").PadLeft(8)
                    $max = $stats.Max.ToString("F2").PadLeft(8)
                    $last = $stats.Latest.ToString("F2").PadLeft(9)
                    
                    $lines += "│ $opName │ $count │ $avg │ $min │ $max │ $last │"
                }
            } else {
                $lines += "│ No performance metrics available yet. Metrics will appear as operations are performed.                        │"
                $lines += "│                                                                                                                │"
            }
            
            # Fill remaining lines if needed
            $currentLines = $lines.Count - 2  # Subtract header lines
            $targetLines = 10
            while ($currentLines -lt $targetLines) {
                $lines += "│                                                                                                                │"
                $currentLines++
            }
            
        } catch {
            $lines += "│ Error retrieving performance metrics: $($_.Exception.Message.Substring(0, [Math]::Min(90, $_.Exception.Message.Length))) │"
        }
        
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string[]] RenderRecentActivity() {
        $lines = @()
        $lines += "┌─ Recent Activity ──────────────────────────────────────────────────────────────────────────────────────────────┐"
        
        try {
            # Get recent metrics (last 10)
            $recentMetrics = $this.PerformanceMonitor.GetMetrics(10)
            
            if ($recentMetrics.Count -gt 0) {
                $lines += "│ Time     │ Metric                                        │ Value           │ Unit │"
                $lines += "├──────────┼───────────────────────────────────────────────┼─────────────────┼──────┤"
                
                foreach ($metric in ($recentMetrics | Sort-Object Timestamp -Descending | Select-Object -First 8)) {
                    $time = $metric.Timestamp.ToString("HH:mm:ss").PadRight(8)
                    $name = $metric.Name.PadRight(45)
                    if ($name.Length -gt 45) {
                        $name = $name.Substring(0, 42) + "..."
                    }
                    
                    $value = $metric.Value.ToString("F2").PadLeft(15)
                    $unit = $metric.Unit.PadRight(4)
                    
                    $lines += "│ $time │ $name │ $value │ $unit │"
                }
            } else {
                $lines += "│ No recent activity. Activity will appear as the application is used.                                          │"
                $lines += "│                                                                                                                │"
            }
            
            # Fill remaining lines if needed
            $currentLines = $lines.Count - 2  # Subtract header lines
            $targetLines = 10
            while ($currentLines -lt $targetLines) {
                $lines += "│                                                                                                                │"
                $currentLines++
            }
            
        } catch {
            $lines += "│ Error retrieving recent activity: $($_.Exception.Message.Substring(0, [Math]::Min(90, $_.Exception.Message.Length))) │"
        }
        
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [string[]] RenderHelp() {
        $lines = @()
        $lines += "┌─ Controls ─────────────────────────────────────────────────────────────────────────────────────────────────────┐"
        $lines += "│ R - Refresh Now │ A - Toggle Auto-refresh │ C - Clear Metrics │ S - Save Report │ Q - Quit │ ? - Help  │"
        $lines += "└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
        
        return $lines
    }
    
    [bool] HandleInput([string]$key) {
        $timing = Start-PerformanceTiming "MonitoringScreen.HandleInput" @{ key = $key }
        
        try {
            switch ($key.ToUpper()) {
                'R' {
                    # Force refresh
                    $this.RefreshData()
                    $this.PerformanceMonitor.IncrementCounter("screen.monitoring.manual_refresh", @{})
                    return $true
                }
                'A' {
                    # Toggle auto-refresh
                    $this.AutoRefresh = -not $this.AutoRefresh
                    $status = $(if ($this.AutoRefresh) { "enabled" } else { "disabled" })
                    Write-Host "Auto-refresh $status"
                    $this.PerformanceMonitor.IncrementCounter("screen.monitoring.toggle_autorefresh", @{})
                    return $true
                }
                'C' {
                    # Clear metrics
                    $this.PerformanceMonitor.ClearMetrics()
                    Write-Host "Performance metrics cleared"
                    $this.PerformanceMonitor.IncrementCounter("screen.monitoring.clear_metrics", @{})
                    return $true
                }
                'S' {
                    # Save report
                    $this.SaveReport()
                    $this.PerformanceMonitor.IncrementCounter("screen.monitoring.save_report", @{})
                    return $true
                }
                'Q' {
                    # Quit monitoring screen
                    $this.PerformanceMonitor.IncrementCounter("screen.monitoring.quit", @{})
                    return $false  # Exit screen
                }
                '?' {
                    # Show detailed help
                    $this.ShowHelp()
                    $this.PerformanceMonitor.IncrementCounter("screen.monitoring.help", @{})
                    return $true
                }
                default {
                    return $true  # Continue running
                }
            }
        } finally {
            Stop-PerformanceTiming $timing
        }
        return $true
    }
    
    [void] RefreshData() {
        # Collect fresh system metrics
        $this.PerformanceMonitor.RecordSystemMetrics()
        $this.LastRefresh = [DateTime]::Now
    }
    
    [void] SaveReport() {
        try {
            $report = $this.PerformanceMonitor.GenerateReport()
            $fileName = "SpeedTUI_Performance_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            $filePath = Join-Path "Logs" $fileName
            
            # Ensure directory exists
            $dir = Split-Path $filePath -Parent
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
            
            Set-Content -Path $filePath -Value $report
            Write-Host "Performance report saved to: $filePath"
            
        } catch {
            Write-Host "Error saving report: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] ShowHelp() {
        $help = @(
            "",
            "SpeedTUI Monitoring Screen Help",
            "===============================",
            "",
            "This screen provides real-time monitoring of SpeedTUI performance and system resources.",
            "",
            "Sections:",
            "  System Overview - Shows current process information, memory usage, and system stats",
            "  Performance Metrics - Displays timing statistics for various operations",
            "  Recent Activity - Shows the most recent performance metrics recorded",
            "",
            "Controls:",
            "  R - Refresh Now: Immediately update all metrics and refresh the display",
            "  A - Toggle Auto-refresh: Enable/disable automatic refresh every 2 seconds",
            "  C - Clear Metrics: Clear all stored performance metrics (fresh start)",
            "  S - Save Report: Generate and save a detailed performance report to file",
            "  Q - Quit: Exit the monitoring screen and return to previous screen",
            "  ? - Help: Show this help information",
            "",
            "Notes:",
            "  - Metrics are automatically collected as you use SpeedTUI",
            "  - System metrics are updated every refresh cycle",
            "  - Performance data is stored in memory with a 10,000 metric limit",
            "  - Reports are saved to the Logs directory with timestamp",
            "",
            "Press any key to continue..."
        )
        
        Write-Host ($help -join "`n")
        $null = Read-Host
    }
    
    [bool] ShouldRefresh() {
        if (-not $this.AutoRefresh) {
            return $false
        }
        
        $elapsed = ([DateTime]::Now - $this.LastRefresh).TotalMilliseconds
        return $elapsed -ge $this.RefreshInterval
    }
    
    [void] Update() {
        if ($this.ShouldRefresh()) {
            $this.RefreshData()
        }
    }
}