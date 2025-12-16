# SpeedTUI Performance Monitor - Real-time performance tracking and metrics

using namespace System.Diagnostics
using namespace System.Collections.Concurrent

class PerformanceMetric {
    [string]$Name
    [DateTime]$Timestamp
    [double]$Value
    [string]$Unit
    [hashtable]$Tags
    
    PerformanceMetric([string]$name, [double]$value, [string]$unit = "", [hashtable]$tags = @{}) {
        $this.Name = $name
        $this.Timestamp = [DateTime]::Now
        $this.Value = $value
        $this.Unit = $unit
        $this.Tags = $tags
    }
    
    [string] ToString() {
        $tagStr = $(if ($this.Tags.Count -gt 0) {
            " (" + ($this.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", " + ")"
        } else { "" })
        
        return "$($this.Timestamp.ToString('HH:mm:ss.fff')) $($this.Name): $($this.Value)$($this.Unit)$tagStr"
    }
}

class TimingContext {
    [string]$Operation
    [Stopwatch]$Stopwatch
    [hashtable]$Tags
    [DateTime]$StartTime
    
    TimingContext([string]$operation, [hashtable]$tags = @{}) {
        $this.Operation = $operation
        $this.Tags = $tags
        $this.StartTime = [DateTime]::Now
        $this.Stopwatch = [Stopwatch]::StartNew()
    }
    
    [void] Stop() {
        $this.Stopwatch.Stop()
    }
    
    [double] GetElapsedMilliseconds() {
        return $this.Stopwatch.ElapsedMilliseconds
    }
}

class PerformanceMonitor {
    [ConcurrentQueue[PerformanceMetric]]$Metrics
    [ConcurrentDictionary[string, object]]$Counters
    [bool]$Enabled = $true
    [int]$MaxMetrics = 10000
    [string]$LogFile
    [object]$Logger
    
    static [PerformanceMonitor]$Instance
    
    PerformanceMonitor() {
        $this.Metrics = [ConcurrentQueue[PerformanceMetric]]::new()
        $this.Counters = [ConcurrentDictionary[string, object]]::new()
        $this.LogFile = "Logs/performance_$(Get-Date -Format 'yyyyMMdd').log"
        
        # Ensure logs directory exists
        $logsDir = Split-Path $this.LogFile -Parent
        if (-not (Test-Path $logsDir)) {
            New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
        }
    }
    
    static [PerformanceMonitor] GetInstance() {
        if (-not [PerformanceMonitor]::Instance) {
            [PerformanceMonitor]::Instance = [PerformanceMonitor]::new()
        }
        return [PerformanceMonitor]::Instance
    }
    
    [void] SetLogger([object]$logger) {
        $this.Logger = $logger
    }
    
    [void] RecordMetric([string]$name, [double]$value, [string]$unit = "", [hashtable]$tags = @{}) {
        if (-not $this.Enabled) { return }
        
        $metric = [PerformanceMetric]::new($name, $value, $unit, $tags)
        $this.Metrics.Enqueue($metric)
        
        # Maintain max metrics limit
        while ($this.Metrics.Count -gt $this.MaxMetrics) {
            $null = $this.Metrics.TryDequeue([ref]$null)
        }
        
        # Log to file and logger if available
        $this.LogMetric($metric)
    }
    
    [TimingContext] StartTiming([string]$operation, [hashtable]$tags = @{}) {
        return [TimingContext]::new($operation, $tags)
    }
    
    [void] EndTiming([TimingContext]$context) {
        if (-not $this.Enabled) { return }
        
        $context.Stop()
        $elapsed = $context.GetElapsedMilliseconds()
        
        $this.RecordMetric(
            "timing.$($context.Operation)", 
            $elapsed, 
            "ms", 
            $context.Tags
        )
    }
    
    [void] IncrementCounter([string]$name, [hashtable]$tags = @{}) {
        if (-not $this.Enabled) { return }
        
        $key = $name
        if ($tags.Count -gt 0) {
            $tagStr = ($tags.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ","
            $key = "$name[$tagStr]"
        }
        
        $newValue = $this.Counters.AddOrUpdate($key, 1, { param($k, $v) $v + 1 })
        $this.RecordMetric("counter.$name", $newValue, "count", $tags)
    }
    
    [void] SetGauge([string]$name, [double]$value, [hashtable]$tags = @{}) {
        if (-not $this.Enabled) { return }
        
        $this.RecordMetric("gauge.$name", $value, "", $tags)
    }
    
    [void] RecordSystemMetrics() {
        if (-not $this.Enabled) { return }
        
        try {
            # Memory metrics
            $processId = [System.Diagnostics.Process]::GetCurrentDoProcess().Id
            $currentProcess = Get-Process -Id $processId
            $this.SetGauge("system.memory.working_set", $currentProcess.WorkingSet64 / 1MB, @{unit="MB"})
            $this.SetGauge("system.memory.private", $currentProcess.PrivateMemorySize64 / 1MB, @{unit="MB"})
            
            # CPU metrics
            $this.SetGauge("system.cpu.time", $currentProcess.TotalProcessorTime.TotalMilliseconds, @{unit="ms"})
            
            # Thread metrics
            $this.SetGauge("system.threads", $currentProcess.Threads.Count, @{unit="count"})
            
            # Handle metrics
            $this.SetGauge("system.handles", $currentProcess.HandleCount, @{unit="count"})
            
            # GC metrics
            $gen0 = [GC]::CollectionCount(0)
            $gen1 = [GC]::CollectionCount(1)
            $gen2 = [GC]::CollectionCount(2)
            $totalMemory = [GC]::GetTotalMemory($false) / 1MB
            
            $this.SetGauge("system.gc.gen0", $gen0, @{unit="count"})
            $this.SetGauge("system.gc.gen1", $gen1, @{unit="count"})
            $this.SetGauge("system.gc.gen2", $gen2, @{unit="count"})
            $this.SetGauge("system.gc.total_memory", $totalMemory, @{unit="MB"})
            
        } catch {
            if ($this.Logger) {
                $this.Logger.Error("PerformanceMonitor", "RecordSystemMetrics", "Failed to record system metrics: $($_.Exception.Message)")
            }
        }
    }
    
    [PerformanceMetric[]] GetMetrics([int]$limit = 100) {
        $resultMetrics = [System.Collections.Generic.List[PerformanceMetric]]::new()
        $tempQueue = [ConcurrentQueue[PerformanceMetric]]::new()
        
        # Dequeue metrics up to limit
        $count = 0
        $currentMetric = $null
        while ($count -lt $limit -and $this.Metrics.TryDequeue([ref]$currentMetric)) {
            $resultMetrics.Add($currentMetric)
            $tempQueue.Enqueue($currentMetric)
            $count++
        }
        
        # Put them back
        while ($tempQueue.TryDequeue([ref]$currentMetric)) {
            $this.Metrics.Enqueue($currentMetric)
        }
        
        return $resultMetrics.ToArray()
    }
    
    [PerformanceMetric[]] GetMetricsByName([string]$name, [int]$limit = 100) {
        $allMetrics = $this.GetMetrics(1000)  # Get more to filter
        $filtered = $allMetrics | Where-Object { $_.Name -like "*$name*" } | Select-Object -First $limit
        return $filtered
    }
    
    [hashtable] GetCounters() {
        $result = @{}
        foreach ($kvp in $this.Counters.GetEnumerator()) {
            $result[$kvp.Key] = $kvp.Value
        }
        return $result
    }
    
    [hashtable] GetSummaryStats([string]$metricName) {
        $foundMetrics = $this.GetMetricsByName($metricName, 1000)
        
        if ($foundMetrics.Count -eq 0) {
            return @{
                Count = 0
                Min = 0
                Max = 0
                Average = 0
                Total = 0
                Latest = 0
                Oldest = 0
            }
        }
        
        $values = $foundMetrics | ForEach-Object { $_.Value }
        
        return @{
            Count = $foundMetrics.Count
            Min = ($values | Measure-Object -Minimum).Minimum
            Max = ($values | Measure-Object -Maximum).Maximum
            Average = ($values | Measure-Object -Average).Average
            Total = ($values | Measure-Object -Sum).Sum
            Latest = $foundMetrics[0].Value
            Oldest = $foundMetrics[-1].Value
        }
    }
    
    [void] LogMetric([PerformanceMetric]$metric) {
        try {
            # Log to file
            Add-Content -Path $this.LogFile -Value $metric.ToString() -ErrorAction SilentlyContinue
            
            # Log to logger if available
            if ($this.Logger) {
                $this.Logger.Debug("PerformanceMonitor", "Metric", $metric.ToString())
            }
        } catch {
            # Silently fail to avoid recursion issues
        }
    }
    
    [string] GenerateReport() {
        $report = @()
        $report += "SpeedTUI Performance Report"
        $report += "=========================="
        $report += "Generated: $(Get-Date)"
        $report += ""
        
        # System metrics summary
        $report += "System Metrics:"
        $systemMetrics = $this.GetMetricsByName("system", 50) | Group-Object Name
        foreach ($group in $systemMetrics) {
            $latest = $group.Group | Sort-Object Timestamp -Descending | Select-Object -First 1
            $report += "  $($group.Name): $($latest.Value)$($latest.Unit)"
        }
        $report += ""
        
        # Timing summary
        $report += "Performance Timings:"
        $timingMetrics = $this.GetMetricsByName("timing", 100) | Group-Object Name
        foreach ($group in $timingMetrics) {
            $stats = $this.GetSummaryStats($group.Name)
            $report += "  $($group.Name):"
            $report += "    Count: $($stats.Count)"
            $report += "    Average: $([Math]::Round($stats.Average, 2))ms"
            $report += "    Min: $([Math]::Round($stats.Min, 2))ms"
            $report += "    Max: $([Math]::Round($stats.Max, 2))ms"
        }
        $report += ""
        
        # Counter summary
        $report += "Counters:"
        $allCounters = $this.GetCounters()
        foreach ($counter in $allCounters.GetEnumerator() | Sort-Object Key) {
            $report += "  $($counter.Key): $($counter.Value)"
        }
        
        return $report -join "`n"
    }
    
    [void] ClearMetrics() {
        while ($this.Metrics.TryDequeue([ref]$null)) { }
        $this.Counters.Clear()
    }
    
    [void] Enable() {
        $this.Enabled = $true
        if ($this.Logger) {
            $this.Logger.Info("PerformanceMonitor", "Enable", "Performance monitoring enabled")
        }
    }
    
    [void] Disable() {
        $this.Enabled = $false
        if ($this.Logger) {
            $this.Logger.Info("PerformanceMonitor", "Disable", "Performance monitoring disabled")
        }
    }
}

# Global function for easy access
function Get-PerformanceMonitor {
    return [PerformanceMonitor]::GetInstance()
}

# Helper functions for common operations
function Start-PerformanceTiming {
    param(
        [string]$Operation,
        [hashtable]$Tags = @{}
    )
    
    $monitor = Get-PerformanceMonitor
    return $monitor.StartTiming($Operation, $Tags)
}

function Stop-PerformanceTiming {
    param(
        [TimingContext]$Context
    )
    
    $monitor = Get-PerformanceMonitor
    $monitor.EndTiming($Context)
}

function Record-PerformanceMetric {
    param(
        [string]$Name,
        [double]$Value,
        [string]$Unit = "",
        [hashtable]$Tags = @{}
    )
    
    $monitor = Get-PerformanceMonitor
    $monitor.RecordMetric($Name, $Value, $Unit, $Tags)
}

function Increment-PerformanceCounter {
    param(
        [string]$Name,
        [hashtable]$Tags = @{}
    )
    
    $monitor = Get-PerformanceMonitor
    $monitor.IncrementCounter($Name, $Tags)
}

# Auto-initialize global instance
$global:SpeedTUIPerformanceMonitor = [PerformanceMonitor]::GetInstance()