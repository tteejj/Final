# Logger.ps1 - Debug Logging Infrastructure
class Logger {
    static hidden [string]$_logFile = ""
    static hidden [int]$_debugLevel = 1 # 0=None, 1=Errors, 2=Info, 3=Debug, 4=Trace

    static hidden [System.IO.StreamWriter]$_writer = $null

    static [void] Initialize([string]$logFile, [int]$level) {
        [Logger]::_logFile = $logFile
        [Logger]::_debugLevel = $level
        if ($logFile) {
            # Use FileStream for non-locking shared read access if needed, but simple AppendText is safest for now
            # Actually, Keep Open to avoid FS overhead? Or Open/Close for safety?
            # Open/Close is safer against crashes.

            try {
                $msg = "--- Log Started: $(Get-Date) (Level: $level) ---"
                [System.IO.File]::AppendAllText($logFile, "$msg`n")
            } catch {
                Write-Host "LOGGER INIT FAILED: $_" -ForegroundColor Red
            }
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
             $line = "$(Get-Date -Format 'HH:mm:ss.fff') [INFO] $message"
             try {
                 [System.IO.File]::AppendAllText([Logger]::_logFile, "$line`n")
             } catch {}
        }
    }

    static [void] Error([string]$message, [Exception]$ex) {
        if ([Logger]::_debugLevel -ge 1 -and [Logger]::_logFile) {
             $line = "$(Get-Date -Format 'HH:mm:ss.fff') [ERROR] $message`n$($ex.ToString())"
             try {
                 [System.IO.File]::AppendAllText([Logger]::_logFile, "$line`n")
             } catch {
                 Write-Host "LOGGER WRITE FAILED: $_" -ForegroundColor Red
             }
        }
    }
}
