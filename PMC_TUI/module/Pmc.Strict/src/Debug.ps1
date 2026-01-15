# Structured Debug Logging System for PMC
# Multi-level debug output with file rotation and sensitive data redaction

Set-StrictMode -Version Latest

# Debug system state - now managed by centralized state
# State initialization moved to State.ps1

function Initialize-PmcDebugSystem {
    <#
    .SYNOPSIS
    Initializes the debug system based on configuration and command line arguments

    .PARAMETER Level
    Debug level (0=off, 1=basic, 2=detailed, 3=verbose)

    .PARAMETER LogPath
    Path to debug log file (relative to PMC root or absolute)
    #>
    param(
        [int]$Level = 0,
        [string]$LogPath = 'debug.log'
    )

    # Defer config loading to avoid circular dependency during initialization
    # Configuration will be applied later via Update-PmcDebugFromConfig

    # Override with explicit parameters
    if ($Level -gt 0) { Set-PmcState -Section 'Debug' -Key 'Level' -Value $Level }
    if ($LogPath -ne 'debug.log') { Set-PmcState -Section 'Debug' -Key 'LogPath' -Value $LogPath }

    # Check environment variables for debug settings
    if ($env:PMC_DEBUG) {
        try {
            $envLevel = [int]$env:PMC_DEBUG
            if ($envLevel -ge 1 -and $envLevel -le 3) {
                Set-PmcState -Section 'Debug' -Key 'Level' -Value $envLevel
            }
        } catch {
            # Environment variable parsing failed - skip environment override
        }
    }

    # Check PowerShell debug preference
    if ($DebugPreference -ne 'SilentlyContinue') {
        $debugState = Get-PmcDebugState
        Set-PmcState -Section 'Debug' -Key 'Level' -Value ([Math]::Max($debugState.Level, 1))
    }

    $debugState = Get-PmcDebugState
    if ($debugState.Level -gt 0) {
        Ensure-PmcDebugLogPath
        Write-PmcDebug -Level 1 -Category 'SYSTEM' -Message "Debug system initialized (Level=$($debugState.Level), Session=$($debugState.SessionId))"
    }
}

function Ensure-PmcDebugLogPath {
    try {
        $logPath = Get-PmcDebugLogPath
        $dir = Split-Path $logPath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        # Rotate log if it's too large
        if (Test-Path $logPath) {
            $size = (Get-Item $logPath).Length
            $debugState = Get-PmcDebugState
            if ($size -gt $debugState.MaxSize) {
                $oldPath = $logPath + '.old'
                if (Test-Path $oldPath) { Remove-Item $oldPath -Force }
                Move-Item $logPath $oldPath -Force
            }
        }
    } catch {
        # Debug log path setup failed - debug output may be unavailable
        Write-PmcDebug -Level 1 -Category 'SYSTEM' -Message "Debug log setup failed: $_"
    }
}

function Get-PmcDebugLogPath {
    $debugState = Get-PmcDebugState
    $logPath = $debugState.LogPath
    if ([System.IO.Path]::IsPathRooted($logPath)) {
        return $logPath
    }

    # Relative to PMC root directory (three levels up from src)
    $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    return Join-Path $root $logPath
}

function Write-PmcDebug {
    <#
    .SYNOPSIS
    Writes a debug message with specified level and category

    .PARAMETER Level
    Debug level required for this message (1=basic, 2=detailed, 3=verbose)

    .PARAMETER Category
    Category/component name (e.g., COMMAND, COMPLETION, UI, STORAGE)

    .PARAMETER Message
    Debug message content

    .PARAMETER Data
    Optional structured data to include (hashtable/object)

    .PARAMETER Timing
    Optional timing information (milliseconds)
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1,3)]
        [int]$Level,

        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Message,

        [object]$Data = $null,

        [int]$Timing = -1
    )

    # Skip if debug level is insufficient
    $debugState = Get-PmcDebugState
    if ($debugState.Level -lt $Level) { return }

    try {
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $session = $debugState.SessionId
        $levelName = @('', 'DBG1', 'DBG2', 'DBG3')[$Level]

        # Build base log entry
        $logEntry = "[$timestamp] [$session] [$levelName] [$Category] $Message"

        # Add timing if provided and enabled
        if ($Timing -ge 0 -and $debugState.IncludePerformance) {
            $logEntry += " (${Timing}ms)"
        }

        # Add structured data if provided
        if ($Data) {
            try {
                $dataJson = $Data | ConvertTo-Json -Compress -Depth 3
                $logEntry += " | Data: $dataJson"
            } catch {
                $logEntry += " | Data: [Serialization Error]"
            }
        }

        # Redact sensitive information if enabled
        if ($debugState.RedactSensitive) {
            $logEntry = Protect-PmcSensitiveData $logEntry
        }

        # Write to log file
        $logPath = Get-PmcDebugLogPath
        Add-Content -Path $logPath -Value $logEntry -Encoding UTF8

    } catch {
        # Silent failure - don't let debug logging break the application
    }
}

function Protect-PmcSensitiveData {
    param([string]$Text)

    try {
        # Redact common sensitive patterns
        $protected = $Text

        # API keys, tokens, secrets
        $protected = $protected -replace '((?i)(token|secret|password|passwd|apikey|api_key|key|pwd)\s*[:=]\s*)(\S+)', '$1****'

        # Long hex strings (potential secrets/hashes)
        $protected = $protected -replace '\b[0-9a-fA-F]{32,}\b', '****'

        # Email addresses
        $protected = $protected -replace '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b', '****@****.***'

        # File paths that might contain usernames
        $protected = $protected -replace '([C-Z]:\\Users\\)([^\\]+)', '$1****'
        $protected = $protected -replace '(/home/)([^/]+)', '$1****'

        # Credit card numbers (basic pattern)
        $protected = $protected -replace '\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b', '****-****-****-****'

        # Social Security Numbers
        $protected = $protected -replace '\b\d{3}-\d{2}-\d{4}\b', '***-**-****'

        return $protected
    } catch {
        return $Text
    }
}

function Measure-PmcOperation {
    <#
    .SYNOPSIS
    Measures execution time of a script block and logs performance data

    .PARAMETER Name
    Operation name for logging

    .PARAMETER Category
    Debug category

    .PARAMETER ScriptBlock
    Code to execute and measure

    .PARAMETER Level
    Debug level for performance logging (default 2)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Category = 'PERF',

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [int]$Level = 2
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $result = & $ScriptBlock
        $stopwatch.Stop()

        Write-PmcDebug -Level $Level -Category $Category -Message "$Name completed" -Timing $stopwatch.ElapsedMilliseconds

        return $result
    } catch {
        $stopwatch.Stop()
        Write-PmcDebug -Level 1 -Category $Category -Message "$Name failed: $_" -Timing $stopwatch.ElapsedMilliseconds
        throw
    }
}

function Write-PmcDebugCommand {
    <#
    .SYNOPSIS
    Debug logging specifically for command execution (Level 1)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string]$Status = 'EXECUTE',

        [object]$Context = $null,

        [int]$Timing = -1
    )

    Write-PmcDebug -Level 1 -Category 'COMMAND' -Message "$Status`: $Command" -Data $Context -Timing $Timing
}

function Write-PmcDebugCompletion {
    <#
    .SYNOPSIS
    Debug logging for completion system (Level 2)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [object]$Data = $null,

        [int]$Timing = -1
    )

    Write-PmcDebug -Level 2 -Category 'COMPLETION' -Message $Message -Data $Data -Timing $Timing
}

function Write-PmcDebugUI {
    <#
    .SYNOPSIS
    Debug logging for UI rendering (Level 3)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [object]$Data = $null,

        [int]$Timing = -1
    )

    Write-PmcDebug -Level 3 -Category 'UI' -Message $Message -Data $Data -Timing $Timing
}

function Write-PmcDebugStorage {
    <#
    .SYNOPSIS
    Debug logging for storage operations (Level 2)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [string]$File = '',

        [object]$Data = $null,

        [int]$Timing = -1
    )

    $message = $(if ($File) { "$Operation`: $File" } else { $Operation })
    Write-PmcDebug -Level 2 -Category 'STORAGE' -Message $message -Data $Data -Timing $Timing
}

function Get-PmcDebugStatus {
    <#
    .SYNOPSIS
    Returns current debug system status and configuration
    #>

    $logPath = Get-PmcDebugLogPath
    $logSize = $(if (Test-Path $logPath) { (Get-Item $logPath).Length } else { 0 })

    $debugState = Get-PmcDebugState
    return [PSCustomObject]@{
        Enabled = ($debugState.Level -gt 0)
        Level = $debugState.Level
        LogPath = $logPath
        LogSize = $logSize
        MaxSize = $debugState.MaxSize
        RedactSensitive = $debugState.RedactSensitive
        IncludePerformance = $debugState.IncludePerformance
        SessionId = $debugState.SessionId
        Uptime = ((Get-Date) - $debugState.StartTime)
    }
}

function Show-PmcDebugLog {
    <#
    .SYNOPSIS
    Shows recent debug log entries

    .PARAMETER Lines
    Number of recent lines to show (default 50)

    .PARAMETER Category
    Filter by category (optional)
    #>
    param(
        [int]$Lines = 50,
        [string]$Category = ''
    )

    $logPath = Get-PmcDebugLogPath
    if (-not (Test-Path $logPath)) {
        Write-Host "No debug log found at: $logPath" -ForegroundColor Yellow
        return
    }

    try {
        $content = Get-Content $logPath -Tail $Lines

        if ($Category) {
            $content = $content | Where-Object { $_ -match "\[$Category\]" }
        }

        foreach ($line in $content) {
            # Color code by level and category
            if ($line -match '\[DBG1\]') {
                Write-Host $line -ForegroundColor Green
            } elseif ($line -match '\[DBG2\]') {
                Write-Host $line -ForegroundColor Yellow
            } elseif ($line -match '\[DBG3\]') {
                Write-Host $line -ForegroundColor Cyan
            } elseif ($line -match '\[ERROR\]') {
                Write-Host $line -ForegroundColor Red
            } else {
                Write-Host $line
            }
        }
    } catch {
        Write-Host "Error reading debug log: $_" -ForegroundColor Red
    }
}

function Update-PmcDebugFromConfig {
    <#
    .SYNOPSIS
    Updates debug settings from configuration after config provider is ready
    #>
    try {
        $cfg = Get-PmcConfig
        if ($cfg.Debug) {
            if ($cfg.Debug.Level -ne $null) { Set-PmcState -Section 'Debug' -Key 'Level' -Value ([int]$cfg.Debug.Level) }
            if ($cfg.Debug.LogPath) { Set-PmcState -Section 'Debug' -Key 'LogPath' -Value ([string]$cfg.Debug.LogPath) }
            if ($cfg.Debug.MaxSize) {
                try {
                    $maxSize = [int64]($cfg.Debug.MaxSize -replace '[^\d]','') * 1MB
                    Set-PmcState -Section 'Debug' -Key 'MaxSize' -Value $maxSize
                } catch {
                    # Configuration parsing failed - keep default MaxSize value
                }
            }
            if ($cfg.Debug.RedactSensitive -ne $null) { Set-PmcState -Section 'Debug' -Key 'RedactSensitive' -Value ([bool]$cfg.Debug.RedactSensitive) }
            if ($cfg.Debug.IncludePerformance -ne $null) { Set-PmcState -Section 'Debug' -Key 'IncludePerformance' -Value ([bool]$cfg.Debug.IncludePerformance) }
        }
    } catch {
        # Configuration loading failed - debug system will use defaults
    }
}

# Note: Debug system is initialized by the root orchestrator after config providers are set

#Export-ModuleMember -Function Initialize-PmcDebugSystem, Ensure-PmcDebugLogPath, Get-PmcDebugLogPath, Write-PmcDebug, Protect-PmcSensitiveData, Measure-PmcOperation, Write-PmcDebugCommand, Write-PmcDebugCompletion, Write-PmcDebugUI, Write-PmcDebugStorage, Get-PmcDebugStatus, Show-PmcDebugLog, Update-PmcDebugFromConfig