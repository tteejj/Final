# ErrorHandler.ps1 - Standardized error handling utilities
# 
# Provides consistent error handling patterns across the TUI application:
# - Logging with proper levels
# - User-friendly status messages
# - Error recovery helpers

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Handle an error with consistent logging and optional user notification

.PARAMETER ErrorRecord
The error record from catch block ($_)

.PARAMETER Context
Description of what was being attempted when error occurred

.PARAMETER StatusBar
Optional widget to display user-friendly message

.PARAMETER Silent
If true, suppress status bar message (log only)

.OUTPUTS
Nothing - logs error and optionally updates status

.EXAMPLE
try {
    $this.Store.SaveData()
} catch {
    Invoke-ErrorHandler -ErrorRecord $_ -Context "Saving task data" -StatusBar $this.StatusBar
}
#>
function Invoke-ErrorHandler {
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory=$true)]
        [string]$Context,

        [Parameter(Mandatory=$false)]
        [object]$StatusBar = $null,

        [Parameter(Mandatory=$false)]
        [switch]$Silent
    )

    # Extract error details
    $errorMsg = $ErrorRecord.Exception.Message
    $errorLocation = $ErrorRecord.InvocationInfo.ScriptName
    $errorLine = $ErrorRecord.InvocationInfo.ScriptLineNumber

    # Log with full details
    $logMessage = "$Context failed: $errorMsg (at $errorLocation`:$errorLine)"
    # Write-PmcTuiLog $logMessage "ERROR"

    # Log stack trace at DEBUG level (check variable exists first for StrictMode)
    $logLevel = (Get-Variable -Name 'PmcTuiLogLevel' -Scope Global -ValueOnly -ErrorAction SilentlyContinue)
    if ($logLevel -ge 3) {
        # Write-PmcTuiLog "Stack: $($ErrorRecord.ScriptStackTrace)" "DEBUG"
    }

    # Update status bar if provided and not silent
    if (-not $Silent -and $null -ne $StatusBar) {
        $userMessage = "$Context failed: $errorMsg"
        if ($StatusBar.PSObject.Methods['SetMessage']) {
            $StatusBar.SetMessage($userMessage, 'error')
        }
    }
}

<#
.SYNOPSIS
Execute a scriptblock with standardized error handling

.PARAMETER ScriptBlock
Code to execute

.PARAMETER Context
Description of what the code does

.PARAMETER DefaultValue
Value to return if error occurs

.PARAMETER StatusBar
Optional status bar for user notification

.OUTPUTS
Result of ScriptBlock, or DefaultValue on error

.EXAMPLE
$data = Invoke-SafeBlock -ScriptBlock { Get-Content $file } -Context "Loading file" -DefaultValue @()
#>
function Invoke-SafeBlock {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory=$true)]
        [string]$Context,

        [Parameter(Mandatory=$false)]
        $DefaultValue = $null,

        [Parameter(Mandatory=$false)]
        [object]$StatusBar = $null
    )

    try {
        return (& $ScriptBlock)
    } catch {
        Invoke-ErrorHandler -ErrorRecord $_ -Context $Context -StatusBar $StatusBar
        return $DefaultValue
    }
}

<#
.SYNOPSIS
Validate a condition and log/display error if false

.PARAMETER Condition
Boolean condition to check

.PARAMETER ErrorMessage
Message to display/log if condition is false

.PARAMETER StatusBar
Optional status bar for user notification

.OUTPUTS
Boolean - the condition value

.EXAMPLE
if (-not (Test-Precondition -Condition ($null -ne $data) -ErrorMessage "Data not loaded")) {
    return
}
#>
function Test-Precondition {
    param(
        [Parameter(Mandatory=$true)]
        [bool]$Condition,

        [Parameter(Mandatory=$true)]
        [string]$ErrorMessage,

        [Parameter(Mandatory=$false)]
        [object]$StatusBar = $null
    )

    if (-not $Condition) {
        # Write-PmcTuiLog $ErrorMessage "ERROR"
        
        if ($null -ne $StatusBar -and $StatusBar.PSObject.Methods['SetMessage']) {
            $StatusBar.SetMessage($ErrorMessage, 'error')
        }
    }

    return $Condition
}

# Only export when running as a module, not when dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    Export-ModuleMember -Function Invoke-ErrorHandler, Invoke-SafeBlock, Test-Precondition
}
