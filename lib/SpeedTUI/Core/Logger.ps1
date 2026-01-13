# SpeedTUI Logger - Granular, module-specific logging with extensive null checks
using namespace System.Collections.Concurrent
using namespace System.IO

enum LogLevel {
    Trace = 0
    Debug = 1
    Info = 2
    Warn = 3
    Error = 4
    Fatal = 5
    None = 99
}

class LogEntry {
    [DateTime]$Timestamp
    [LogLevel]$Level
    [string]$Module
    [string]$Component
    [string]$Message
    [hashtable]$Context
    [string]$StackTrace
    
    [string] ToString() {
        $ctx = $(if ($this.Context -and $this.Context.Count -gt 0) {
                " | " + ($this.Context.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", "
            }
            else { "" })
        
        return "$($this.Timestamp.ToString('yyyy-MM-dd HH:mm:ss.fff')) [$($this.Level)] [$($this.Module)][$($this.Component)] $($this.Message)$ctx"
    }
}

class Logger {
    # Singleton instance
    static [object]$Instance = $null
    
    # Configuration
    [ConcurrentDictionary[string, LogLevel]]$ModuleLevels
    [ConcurrentDictionary[string, LogLevel]]$ComponentLevels
    [LogLevel]$GlobalLevel = [LogLevel]::Debug
    [bool]$EnableConsole = $false
    [bool]$EnableFile = $true
    [string]$LogDirectory
    [string]$LogFilePath
    
    # Performance
    hidden [StreamWriter]$_fileWriter
    hidden [ConcurrentQueue[LogEntry]]$_logQueue
    hidden [System.Threading.Timer]$_flushTimer
    hidden [object]$_writeLock = [object]::new()
    
    # Statistics
    [ConcurrentDictionary[string, int]]$LogCounts
    [ConcurrentDictionary[string, TimeSpan]]$PerformanceMetrics
    
    hidden Logger() {
        $this.ModuleLevels = [ConcurrentDictionary[string, LogLevel]]::new()
        $this.ComponentLevels = [ConcurrentDictionary[string, LogLevel]]::new()
        $this.LogCounts = [ConcurrentDictionary[string, int]]::new()
        $this.PerformanceMetrics = [ConcurrentDictionary[string, TimeSpan]]::new()
        $this._logQueue = [ConcurrentQueue[LogEntry]]::new()
        
        # Set up log directory
        $this.LogDirectory = Join-Path (Join-Path $PSScriptRoot "..") "Logs"
        if (-not (Test-Path $this.LogDirectory)) {
            New-Item -ItemType Directory -Path $this.LogDirectory -Force | Out-Null
        }
        
        # Create log file with timestamp
        $timestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss")
        $this.LogFilePath = Join-Path $this.LogDirectory "speedtui_$timestamp.log"
        
        # Initialize file writer
        $this.InitializeFileWriter()
        
        # No automatic timer - will flush synchronously for now
    }
    
    static [object] GetInstance() {
        if ($null -eq [Logger]::Instance) {
            [Logger]::Instance = [Logger]::new()
        }
        return [Logger]::Instance
    }
    
    hidden [void] InitializeFileWriter() {
        try {
            $this._fileWriter = [StreamWriter]::new($this.LogFilePath, $true)
            $this._fileWriter.AutoFlush = $false
        }
        catch {
            Write-Warning "Failed to initialize log file writer: $_"
            $this.EnableFile = $false
        }
    }
    
    # Module-level configuration
    [void] SetModuleLevel([string]$module, [LogLevel]$level) {
        if ([string]::IsNullOrWhiteSpace($module)) { return }
        $this.ModuleLevels[$module] = $level
    }
    
    # Component-level configuration (more granular)
    [void] SetComponentLevel([string]$module, [string]$component, [LogLevel]$level) {
        if ([string]::IsNullOrWhiteSpace($module) -or [string]::IsNullOrWhiteSpace($component)) { return }
        $key = "$module.$component"
        $this.ComponentLevels[$key] = $level
    }
    
    # Check if logging is enabled for given context
    hidden [bool] ShouldLog([LogLevel]$level, [string]$module, [string]$component) {
        if ($level -lt $this.GlobalLevel) { return $false }
        
        # Check component-specific level first (most specific)
        if (-not [string]::IsNullOrWhiteSpace($component)) {
            $componentKey = "$module.$component"
            $componentLevel = $null
            if ($this.ComponentLevels.ContainsKey($componentKey)) {
                $componentLevel = $this.ComponentLevels[$componentKey]
                return $level -ge $componentLevel
            }
        }
        
        # Check module-specific level
        if (-not [string]::IsNullOrWhiteSpace($module)) {
            $moduleLevel = $null
            if ($this.ModuleLevels.ContainsKey($module)) {
                $moduleLevel = $this.ModuleLevels[$module]
                return $level -ge $moduleLevel
            }
        }
        
        # Fall back to global level
        return $true
    }
    
    # Core logging method with extensive null checks
    [void] Log([LogLevel]$level, [string]$module, [string]$component, [string]$message, [hashtable]$context) {
        # Null checks
        if ($null -eq $module) { $module = "Unknown" }
        if ($null -eq $component) { $component = "Unknown" }
        if ($null -eq $message) { $message = "" }
        if ($null -eq $context) { $context = @{} }
        
        # Check if we should log
        if (-not $this.ShouldLog($level, $module, $component)) { return }
        
        # Create log entry
        $entry = [LogEntry]@{
            Timestamp  = [DateTime]::Now
            Level      = $level
            Module     = $module
            Component  = $component
            Message    = $message
            Context    = $context
            StackTrace = $(if ($level -ge [LogLevel]::Error) { (Get-PSCallStack | Out-String) } else { "" })
        }
        
        # Queue for async write
        $this._logQueue.Enqueue($entry)

        # PERFORMANCE FIX: Only flush immediately for ERROR/FATAL, batch everything else
        # This prevents 6000+ disk writes/sec in render loops
        if ($level -ge [LogLevel]::Error) {
            $this.FlushQueue()
        }
        # Flush periodically when queue gets large (100 entries)
        elseif ($this._logQueue.Count -ge 100) {
            $this.FlushQueue()
        }
        
        # Update statistics
        $statKey = "$module.$component.$level"
        [void]$this.LogCounts.AddOrUpdate($statKey, 1, { param($k, $v) $v + 1 })
        
        # Console output for errors/warnings in debug mode
        if ($this.EnableConsole -and $level -ge [LogLevel]::Warn) {
            $this.WriteToConsole($entry)
        }
    }
    
    # Convenience methods for each log level
    [void] Trace([string]$module, [string]$component, [string]$message) {
        $this.Log([LogLevel]::Trace, $module, $component, $message, @{})
    }
    
    [void] Trace([string]$module, [string]$component, [string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Trace, $module, $component, $message, $context)
    }
    
    [void] Debug([string]$module, [string]$component, [string]$message) {
        $this.Log([LogLevel]::Debug, $module, $component, $message, @{})
    }
    
    [void] Debug([string]$module, [string]$component, [string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Debug, $module, $component, $message, $context)
    }
    
    [void] Info([string]$module, [string]$component, [string]$message) {
        $this.Log([LogLevel]::Info, $module, $component, $message, @{})
    }
    
    [void] Info([string]$module, [string]$component, [string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Info, $module, $component, $message, $context)
    }
    
    [void] Warn([string]$module, [string]$component, [string]$message) {
        $this.Log([LogLevel]::Warn, $module, $component, $message, @{})
    }
    
    [void] Warn([string]$module, [string]$component, [string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Warn, $module, $component, $message, $context)
    }
    
    [void] Error([string]$module, [string]$component, [string]$message) {
        $this.Log([LogLevel]::Error, $module, $component, $message, @{})
    }
    
    [void] Error([string]$module, [string]$component, [string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Error, $module, $component, $message, $context)
    }
    
    [void] Fatal([string]$module, [string]$component, [string]$message) {
        $this.Log([LogLevel]::Fatal, $module, $component, $message, @{})
    }
    
    [void] Fatal([string]$module, [string]$component, [string]$message, [hashtable]$context) {
        $this.Log([LogLevel]::Fatal, $module, $component, $message, $context)
    }
    
    # Performance tracking
    [IDisposable] MeasurePerformance([string]$module, [string]$operation) {
        return [PerformanceTimer]::new($this, $module, $operation)
    }
    
    # Flush queue to file
    hidden [void] FlushQueue() {
        if (-not $this.EnableFile -or $null -eq $this._fileWriter) { return }
        
        $entries = [System.Collections.Generic.List[LogEntry]]::new()
        $entry = $null
        
        # Dequeue all pending entries
        while ($this._logQueue.TryDequeue([ref]$entry)) {
            $entries.Add($entry)
        }
        
        if ($entries.Count -eq 0) { return }
        
        # Write to file
        try {
            [System.Threading.Monitor]::Enter($this._writeLock)
            foreach ($e in $entries) {
                $this._fileWriter.WriteLine($e.ToString())
            }
            $this._fileWriter.Flush()
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
        }
        finally {
            [System.Threading.Monitor]::Exit($this._writeLock)
        }
    }
    
    # Console output with color coding
    hidden [void] WriteToConsole([LogEntry]$entry) {
        $color = switch ($entry.Level) {
            Trace { "DarkGray" }
            Debug { "Gray" }
            Info { "White" }
            Warn { "Yellow" }
            Error { "Red" }
            Fatal { "DarkRed" }
            default { "White" }
        }
        
        Write-Host $entry.ToString() -ForegroundColor $color
    }
    
    # Get statistics
    [hashtable] GetStatistics() {
        return @{
            LogCounts          = $this.LogCounts.ToArray()
            PerformanceMetrics = $this.PerformanceMetrics.ToArray()
            QueueSize          = $this._logQueue.Count
            LogFilePath        = $this.LogFilePath
        }
    }
    
    # Cleanup
    [void] Dispose() {
        $this.FlushQueue()
        
        if ($null -ne $this._fileWriter) {
            $this._fileWriter.Close()
            $this._fileWriter.Dispose()
            $this._fileWriter = $null
        }
    }
}

# Performance measurement helper
class PerformanceTimer : System.IDisposable {
    hidden [object]$_logger
    hidden [string]$_module
    hidden [string]$_operation
    hidden [System.Diagnostics.Stopwatch]$_stopwatch
    
    PerformanceTimer([object]$logger, [string]$module, [string]$operation) {
        $this._logger = $logger
        $this._module = $module
        $this._operation = $operation
        $this._stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $logger.Trace($module, "Performance", "Starting operation: $operation")
    }
    
    [void] Dispose() {
        $this._stopwatch.Stop()
        $elapsed = $this._stopwatch.Elapsed
        
        $this._logger.Debug($this._module, "Performance", "Completed operation: $($this._operation)", @{
                ElapsedMs = $elapsed.TotalMilliseconds
                Operation = $this._operation
            })
        
        # Store metric
        $key = "$($this._module).$($this._operation)"
        [void]$this._logger.PerformanceMetrics.AddOrUpdate($key, $elapsed, { 
                param($k, $v) 
                if ($elapsed -gt $v) { $elapsed } else { $v }
            })
    }
}

# Global logger instance helper
function Get-Logger {
    return [Logger]::GetInstance()
}