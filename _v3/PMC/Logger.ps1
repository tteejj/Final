# Logger.ps1 - Debug Logging Infrastructure
class Logger {
    static hidden [string]$_logFile = ""
    static hidden [int]$_debugLevel = 1 # 0=None, 1=Errors, 2=Info, 3=Debug, 4=Trace
    
    static [void] Initialize([string]$logFile, [int]$level) {
        [Logger]::_logFile = $logFile
        [Logger]::_debugLevel = $level
        if ($logFile) {
            "--- Log Started: $(Get-Date) (Level: $level) ---" | Out-File -FilePath $logFile -Encoding utf8
        }
    }
    
    static [void] SetDebugLevel([int]$level) {
        [Logger]::_debugLevel = $level
    }

    static [void] Log([string]$message) {
        [Logger]::Log($message, 2)
    }
    
    static [void] Log([string]$message, [int]$level) {
        if ([Logger]::_debugLevel -ge $level -and [Logger]::_logFile) {
             "$(Get-Date -Format 'HH:mm:ss.fff') [INFO] $message" | Out-File -FilePath ([Logger]::_logFile) -Append -Encoding utf8
        }
    }
    
    static [void] Error([string]$message, [Exception]$ex) {
        if ([Logger]::_debugLevel -ge 1 -and [Logger]::_logFile) {
             "$(Get-Date -Format 'HH:mm:ss.fff') [ERROR] $message`n$($ex.ToString())" | Out-File -FilePath ([Logger]::_logFile) -Append -Encoding utf8
        }
    }
}
