# Constants.ps1 - Terminal and application constants
#
# Centralized constants to eliminate magic numbers and hardcoded values
# throughout the PMC TUI codebase.
#
# M-CQ-2: Terminal Dimension Constants
# M-CQ-7: Status Constants

using namespace System

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Terminal and application constants for PMC TUI

.DESCRIPTION
Centralized constants file to replace hardcoded values throughout the codebase.
Includes terminal dimensions, task status values, priority levels, and other
application-wide constants.

.NOTES
This file should be loaded early in the application bootstrap process.
#>

# ============================================================================
# TERMINAL DIMENSIONS
# ============================================================================

# Minimum supported terminal dimensions
# M-CQ-2: Replaces hardcoded 120x40, 80x24 throughout code
$global:MIN_TERM_WIDTH = 80
$global:MIN_TERM_HEIGHT = 24

# Recommended terminal dimensions for optimal experience
$global:RECOMMENDED_TERM_WIDTH = 120
$global:RECOMMENDED_TERM_HEIGHT = 40

# Maximum dimensions for virtual scrolling
$global:MAX_VISIBLE_ROWS = 1000  # M-PERF-7: Virtual scrolling limit

# ============================================================================
# TASK STATUS CONSTANTS
# ============================================================================

# M-CQ-7: Status Constants
# Task status values (enum-like constants)
$global:TASK_STATUS_PENDING = 'pending'
$global:TASK_STATUS_ACTIVE = 'active'
$global:TASK_STATUS_COMPLETED = 'completed'
$global:TASK_STATUS_BLOCKED = 'blocked'
$global:TASK_STATUS_CANCELLED = 'cancelled'
$global:TASK_STATUS_DEFERRED = 'deferred'

# All valid task statuses
$global:TASK_STATUSES = @(
    $global:TASK_STATUS_PENDING,
    $global:TASK_STATUS_ACTIVE,
    $global:TASK_STATUS_COMPLETED,
    $global:TASK_STATUS_BLOCKED,
    $global:TASK_STATUS_CANCELLED,
    $global:TASK_STATUS_DEFERRED
)

# ============================================================================
# PRIORITY CONSTANTS
# ============================================================================

$global:PRIORITY_HIGH = 'high'
$global:PRIORITY_MEDIUM = 'medium'
$global:PRIORITY_LOW = 'low'
$global:PRIORITY_NONE = 'none'

# All valid priority levels
$global:PRIORITIES = @(
    $global:PRIORITY_HIGH,
    $global:PRIORITY_MEDIUM,
    $global:PRIORITY_LOW,
    $global:PRIORITY_NONE
)

# Default priority for new tasks (configurable via preferences)
# M-CFG-3: Make Default Priority Configurable
$global:DEFAULT_PRIORITY = $global:PRIORITY_MEDIUM

# ============================================================================
# PERFORMANCE CONSTANTS
# ============================================================================

# M-PERF-4: Debounce search input delay (milliseconds)
$global:SEARCH_DEBOUNCE_MS = 150

# Cache refresh interval (milliseconds)
$global:CACHE_REFRESH_INTERVAL_MS = 500

# Maximum items before pagination required
$global:MAX_ITEMS_BEFORE_PAGINATION = 100

# ============================================================================
# UI CONSTANTS
# ============================================================================

# Default column widths for various views
$global:COLUMN_WIDTH_DATE = 10
$global:COLUMN_WIDTH_TIME = 8
$global:COLUMN_WIDTH_STATUS = 12
$global:COLUMN_WIDTH_PRIORITY = 10
$global:COLUMN_WIDTH_PROJECT = 20
$global:COLUMN_WIDTH_TAGS = 15

# Padding and spacing
$global:DEFAULT_PADDING = 1
$global:DEFAULT_MARGIN = 0

# Dialog dimensions
$global:DEFAULT_DIALOG_WIDTH = 60
$global:DEFAULT_DIALOG_HEIGHT = 20

# ============================================================================
# INPUT VALIDATION - LENGTH LIMITS
# ============================================================================

# Maximum lengths for various text fields
$global:MAX_TASK_TITLE_LENGTH = 500           # Task title/name
$global:MAX_DESCRIPTION_LENGTH = 4000         # Description fields
$global:MAX_TAG_LENGTH = 50                   # Individual tag length
$global:MAX_PROJECT_NAME_LENGTH = 100         # Project name length
$global:MAX_TAGS_PER_TASK = 50                # Maximum number of tags per task
$global:MAX_DEPENDENCIES_PER_TASK = 20        # Maximum task dependencies

# ============================================================================
# FILE PATHS
# ============================================================================

# M-CFG-1: Configurable Log Path (uses environment variable or default)
$global:DEFAULT_LOG_PATH = "/tmp"
$global:LOG_FILE_PREFIX = "pmc-tui"
$global:LOG_FILE_EXTENSION = ".log"

# Backup directory (relative to config path)
$global:BACKUP_DIRECTORY = "backups"

# Preferences file name
# M-ACC-2: Symbol alternatives for color-only indicators
$global:USE_SYMBOLS = $true  # Configurable via preferences

# Status symbols (when USE_SYMBOLS is true)
$global:SYMBOL_COMPLETED = "[[OK]]"
$global:SYMBOL_PENDING = "[ ]"
$global:SYMBOL_BLOCKED = "[⊗]"
$global:SYMBOL_ACTIVE = "[→]"
$global:SYMBOL_OVERDUE = "[[WARN]]"

# Screen reader alternatives
$global:SYMBOL_COMPLETED_TEXT = "[DONE]"
$global:SYMBOL_PENDING_TEXT = "[TODO]"
$global:SYMBOL_BLOCKED_TEXT = "[BLOCKED]"
$global:SYMBOL_ACTIVE_TEXT = "[IN-PROGRESS]"
$global:SYMBOL_OVERDUE_TEXT = "[OVERDUE]"

# ============================================================================
# TIMEZONE CONSTANTS
# ============================================================================

# M-INT-5: Timezone handling
# Default timezone assumption: local system time
$global:DEFAULT_TIMEZONE = [System.TimeZoneInfo]::Local
$global:USE_UTC_INTERNALLY = $false  # If true, convert all dates to UTC internally

# ============================================================================
# ERROR MESSAGE FORMATS
# ============================================================================

# M-CQ-5: Standardize Error Messages
$global:ERROR_FORMAT = "Operation failed: {0}"
$global:WARNING_FORMAT = "Warning: {0}"
$global:INFO_FORMAT = "Info: {0}"
$global:SUCCESS_FORMAT = "Success: {0}"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
Get formatted error message

.PARAMETER details
Error details to format

.OUTPUTS
Formatted error message string
#>
function Get-FormattedError {
    param([string]$details)
    return $script:ERROR_FORMAT -f $details
}

<#
.SYNOPSIS
Get formatted warning message

.PARAMETER details
Warning details to format

.OUTPUTS
Formatted warning message string
#>
function Get-FormattedWarning {
    param([string]$details)
    return $script:WARNING_FORMAT -f $details
}

<#
.SYNOPSIS
Get formatted info message

.PARAMETER details
Info details to format

.OUTPUTS
Formatted info message string
#>
function Get-FormattedInfo {
    param([string]$details)
    return $script:INFO_FORMAT -f $details
}

<#
.SYNOPSIS
Get formatted success message

.PARAMETER details
Success details to format

.OUTPUTS
Formatted success message string
#>
function Get-FormattedSuccess {
    param([string]$details)
    return $script:SUCCESS_FORMAT -f $details
}

<#
.SYNOPSIS
Validate task status value

.PARAMETER status
Status value to validate

.OUTPUTS
Boolean indicating if status is valid
#>
function Test-ValidTaskStatus {
    param([string]$status)
    return $status -in $global:TASK_STATUSES
}

<#
.SYNOPSIS
Validate priority value

.PARAMETER priority
Priority value to validate

.OUTPUTS
Boolean indicating if priority is valid
#>
function Test-ValidPriority {
    param([string]$priority)
    return $priority -in $script:PRIORITIES
}

<#
.SYNOPSIS
Get symbol for task status

.PARAMETER status
Task status

.PARAMETER useSymbols
Whether to use Unicode symbols (true) or text alternatives (false)

.OUTPUTS
Symbol string for the status
#>
function Get-StatusSymbol {
    param(
        [string]$status,
        [bool]$useSymbols = $script:USE_SYMBOLS
    )

    if ($useSymbols) {
        switch ($status) {
            $global:TASK_STATUS_COMPLETED { return $script:SYMBOL_COMPLETED }
            $global:TASK_STATUS_BLOCKED { return $script:SYMBOL_BLOCKED }
            $global:TASK_STATUS_ACTIVE { return $script:SYMBOL_ACTIVE }
            $global:TASK_STATUS_PENDING { return $script:SYMBOL_PENDING }
            default { return $script:SYMBOL_PENDING }
        }
    } else {
        switch ($status) {
            $global:TASK_STATUS_COMPLETED { return $script:SYMBOL_COMPLETED_TEXT }
            $global:TASK_STATUS_BLOCKED { return $script:SYMBOL_BLOCKED_TEXT }
            $global:TASK_STATUS_ACTIVE { return $script:SYMBOL_ACTIVE_TEXT }
            $global:TASK_STATUS_PENDING { return $script:SYMBOL_PENDING_TEXT }
            default { return $script:SYMBOL_PENDING_TEXT }
        }
    }
}

# Export all constants and helper functions (only when imported as module)
# When dot-sourced, $MyInvocation.InvocationName is '.' so we skip Export-ModuleMember
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Export-ModuleMember -Variable @(
    'MIN_TERM_WIDTH',
    'MIN_TERM_HEIGHT',
    'RECOMMENDED_TERM_WIDTH',
    'RECOMMENDED_TERM_HEIGHT',
    'MAX_VISIBLE_ROWS',
    'TASK_STATUS_PENDING',
    'TASK_STATUS_ACTIVE',
    'TASK_STATUS_COMPLETED',
    'TASK_STATUS_BLOCKED',
    'TASK_STATUS_CANCELLED',
    'TASK_STATUS_DEFERRED',
    'TASK_STATUSES',
    'PRIORITY_HIGH',
    'PRIORITY_MEDIUM',
    'PRIORITY_LOW',
    'PRIORITY_NONE',
    'PRIORITIES',
    'DEFAULT_PRIORITY',
    'SEARCH_DEBOUNCE_MS',
    'CACHE_REFRESH_INTERVAL_MS',
    'MAX_ITEMS_BEFORE_PAGINATION',
    'COLUMN_WIDTH_DATE',
    'COLUMN_WIDTH_TIME',
    'COLUMN_WIDTH_STATUS',
    'COLUMN_WIDTH_PRIORITY',
    'COLUMN_WIDTH_PROJECT',
    'COLUMN_WIDTH_TAGS',
    'DEFAULT_PADDING',
    'DEFAULT_MARGIN',
    'DEFAULT_DIALOG_WIDTH',
    'DEFAULT_DIALOG_HEIGHT',
    'DEFAULT_LOG_PATH',
    'LOG_FILE_PREFIX',
    'LOG_FILE_EXTENSION',
    'BACKUP_DIRECTORY',
    'PREFERENCES_FILE',
    'MAX_TASK_TITLE_LENGTH',
    'MAX_DESCRIPTION_LENGTH',
    'MAX_TAG_LENGTH',
    'MAX_PROJECT_NAME_LENGTH',
    'MAX_TAGS_PER_TASK',
    'MAX_DEPENDENCIES_PER_TASK',
    'USE_SYMBOLS',
    'SYMBOL_COMPLETED',
    'SYMBOL_PENDING',
    'SYMBOL_BLOCKED',
    'SYMBOL_ACTIVE',
    'SYMBOL_OVERDUE',
    'SYMBOL_COMPLETED_TEXT',
    'SYMBOL_PENDING_TEXT',
    'SYMBOL_BLOCKED_TEXT',
    'SYMBOL_ACTIVE_TEXT',
    'SYMBOL_OVERDUE_TEXT',
    'DEFAULT_TIMEZONE',
    'USE_UTC_INTERNALLY',
    'ERROR_FORMAT',
    'WARNING_FORMAT',
    'INFO_FORMAT',
    'SUCCESS_FORMAT'
) -Function @(
    'Get-FormattedError',
    'Get-FormattedWarning',
    'Get-FormattedInfo',
    'Get-FormattedSuccess',
    'Test-ValidTaskStatus',
    'Test-ValidPriority',
    'Get-StatusSymbol'
)
    } catch {
        # Ignore Export-ModuleMember errors when not in a module context
    }
}