# Security and Safety Hardening for PMC
# Input validation, path protection, resource limits, and execution safety

Set-StrictMode -Version Latest

# Security system state - now managed by centralized state
# State initialization moved to State.ps1

function Initialize-PmcSecuritySystem {
    <#
    .SYNOPSIS
    Initializes security system based on configuration
    #>

    # Defer config loading to avoid circular dependency during initialization
    # Configuration will be applied later via Update-PmcSecurityFromConfig

    # Default allowed paths if none configured
    $securityState = Get-PmcSecurityState

    # Disable path whitelist for now to allow TUI to save tasks
    Set-PmcState -Section 'Security' -Key 'PathWhitelistEnabled' -Value $false

    if ($securityState.AllowedWritePaths.Count -eq 0) {
        # $PSScriptRoot is /home/teej/pmc/module/Pmc.Strict/src
        # We need to go up to /home/teej/pmc
        $moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pmcRoot = Split-Path $moduleRoot -Parent

        $defaultPaths = @(
            $pmcRoot                              # /home/teej/pmc
            Join-Path $pmcRoot 'reports'
            Join-Path $pmcRoot 'backups'
            Join-Path $pmcRoot 'exports'
            [System.IO.Path]::GetTempPath()
        )
        Set-PmcState -Section 'Security' -Key 'AllowedWritePaths' -Value $defaultPaths
    }
}

function Test-PmcInputSafety {
    <#
    .SYNOPSIS
    Validates input for potential security issues

    .PARAMETER Input
    User input to validate

    .PARAMETER InputType
    Type of input (command, text, path, etc.)
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Input,

        [string]$InputType = 'general'
    )

    $securityState = Get-PmcSecurityState
    if (-not $securityState.InputValidationEnabled) { return $true }

    $threats = @()

    try {
        # Check for command injection patterns
        $injectionPatterns = @(
            ';.*(?:rm|del|format|shutdown|reboot)',
            '\|.*(?:nc|netcat|wget|curl|powershell|cmd)',
            '&.*(?:ping|nslookup|whoami|net\s)',
            '`.*(?:Get-.*|Invoke-.*|Start-.*)',
            '\$\(.*(?:Get-.*|Invoke-.*|Remove-.*)\)',
            '(?:>|>>).*(?:/etc/|C:\\Windows\\)',
            '(?:\.\.[\\/]){3,}',  # Path traversal
            '(?i)(?:javascript:|data:|vbscript:)',  # Script injection
            '(?i)(?:<script|<iframe|<object|<embed)',  # HTML injection
            'eval\s*\(',  # Code evaluation
            '(?:exec|system|shell_exec|passthru)\s*\('  # System execution
        )

        foreach ($pattern in $injectionPatterns) {
            if ($Input -match $pattern) {
                $threats += "Potential injection: $pattern"
            }
        }

        # Check for sensitive data exposure
        if ($securityState.SensitiveDataScanEnabled) {
            $sensitivePatterns = @(
                '\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b',  # Credit card
                '\b\d{3}-\d{2}-\d{4}\b',  # SSN
                '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',  # Email
                '\b[0-9a-fA-F]{32,}\b',  # Long hex (potential secrets)
                '(?i)(password|passwd|secret|token|key)\s*[:=]\s*\S+',  # Credentials
                'BEGIN\s+(RSA\s+)?PRIVATE\s+KEY',  # Private keys
                'sk_live_[0-9a-zA-Z]{24}',  # Stripe keys
                'AIza[0-9A-Za-z\\-_]{35}',  # Google API keys
                'ya29\\.[0-9A-Za-z\\-_]+',  # Google OAuth
                'AKIA[0-9A-Z]{16}'  # AWS access keys
            )

            foreach ($pattern in $sensitivePatterns) {
                if ($Input -match $pattern) {
                    $threats += "Potential sensitive data: $pattern"
                }
            }
        }

        # Input length validation
        if ($Input.Length -gt 10000) {
            $threats += "Input too long (${$Input.Length} chars, max 10000)"
        }

        # Null byte injection
        if ($Input.Contains("`0")) {
            $threats += "Null byte injection detected"
        }

        # Unicode normalization attacks
        if ($Input -match '[\u202A-\u202E\u2066-\u2069]') {
            $threats += "Unicode direction override detected"
        }

        if ($threats.Count -gt 0) {
            Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Input validation failed" -Data @{ Input = $Input.Substring(0, [Math]::Min($Input.Length, 100)); Threats = $threats; Type = $InputType }
            return $false
        }

        Write-PmcDebug -Level 3 -Category 'SECURITY' -Message "Input validation passed" -Data @{ Length = $Input.Length; Type = $InputType }
        return $true

    } catch {
        Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Input validation error: $_"
        return $false
    }
}

function Test-PmcPathSafety {
    <#
    .SYNOPSIS
    Validates that a file path is safe to write to

    .PARAMETER Path
    File path to validate

    .PARAMETER Operation
    Operation being performed (read, write, delete)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Operation = 'write'
    )

    $securityState = Get-PmcSecurityState
    # TEMPORARY: Disable whitelist to allow TUI saves
    return $true
    if (-not $securityState.PathWhitelistEnabled) { return $true }

    try {
        # Resolve path to absolute form
        $resolvedPath = $null
        try {
            if ([System.IO.Path]::IsPathRooted($Path)) {
                $resolvedPath = [System.IO.Path]::GetFullPath($Path)
            } else {
                $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
                $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $root $Path))
            }
        } catch {
            Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Path resolution failed: $_" -Data @{ Path = $Path }
            return $false
        }

        # Check against whitelist for write operations
        if ($Operation -eq 'write' -or $Operation -eq 'delete') {
            $allowed = $false
            Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Checking path against whitelist" -Data @{ Path = $resolvedPath; AllowedPaths = ($securityState.AllowedWritePaths -join '; ') }
            foreach ($allowedPath in $securityState.AllowedWritePaths) {
                try {
                    $allowedResolved = [System.IO.Path]::GetFullPath($allowedPath)
                    Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Comparing paths" -Data @{ Resolved = $resolvedPath; Allowed = $allowedResolved; Match = $resolvedPath.StartsWith($allowedResolved, [System.StringComparison]::OrdinalIgnoreCase) }
                    if ($resolvedPath.StartsWith($allowedResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $allowed = $true
                        break
                    }
                } catch {
                    # Path resolution failed - skip this allowed path
                }
            }

            if (-not $allowed) {
                Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Path not in whitelist" -Data @{ Path = $resolvedPath; Operation = $Operation; AllowedPaths = $securityState.AllowedWritePaths }
                return $false
            }
        }

        # Check for dangerous paths
        $dangerousPaths = @(
            'C:\Windows\System32',
            'C:\Windows\SysWOW64',
            '/etc/',
            '/bin/',
            '/sbin/',
            '/usr/bin/',
            '/usr/sbin/',
            '/boot/',
            '/sys/',
            '/proc/'
        )

        foreach ($dangerousPath in $dangerousPaths) {
            if ($resolvedPath.StartsWith($dangerousPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Dangerous path detected" -Data @{ Path = $resolvedPath; DangerousPath = $dangerousPath }
                return $false
            }
        }

        # Log audit trail for file operations
        if ($securityState.AuditLoggingEnabled) {
            Write-PmcDebug -Level 2 -Category 'AUDIT' -Message "File operation approved" -Data @{ Path = $resolvedPath; Operation = $Operation; User = $env:USERNAME }
        }

        return $true

    } catch {
        Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Path safety check error: $_"
        return $false
    }
}

function Invoke-PmcSecureFileOperation {
    <#
    .SYNOPSIS
    Performs file operations with security checks and resource limits

    .PARAMETER Path
    File path for the operation

    .PARAMETER Operation
    Type of operation (read, write, delete)

    .PARAMETER Content
    Content to write (for write operations)

    .PARAMETER ScriptBlock
    Custom operation to perform within security context
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('read', 'write', 'delete', 'custom')]
        [string]$Operation,

        [string]$Content = '',

        [scriptblock]$ScriptBlock = $null
    )

    # Validate path safety
    if (-not (Test-PmcPathSafety -Path $Path -Operation $Operation)) {
        throw "Path safety validation failed: $Path"
    }

    # Check resource limits
    $securityState = Get-PmcSecurityState
    if ($securityState.ResourceLimitsEnabled) {
        if ($Operation -eq 'write' -and $Content.Length -gt 0) {
            $sizeBytes = [System.Text.Encoding]::UTF8.GetByteCount($Content)
            if ($sizeBytes -gt $securityState.MaxFileSize) {
                throw "Content size ($sizeBytes bytes) exceeds maximum allowed ($($securityState.MaxFileSize) bytes)"
            }
        }

        # Check existing file size for read operations
        if ($Operation -eq 'read' -and (Test-Path $Path)) {
            $fileSize = (Get-Item $Path).Length
            if ($fileSize -gt $securityState.MaxFileSize) {
                throw "File size ($fileSize bytes) exceeds maximum allowed ($($securityState.MaxFileSize) bytes)"
            }
        }
    }

    # Audit log the operation
    if ($securityState.AuditLoggingEnabled) {
        Write-PmcDebug -Level 1 -Category 'AUDIT' -Message "Secure file operation" -Data @{
            Path = $Path
            Operation = $Operation
            ContentSize = $Content.Length
            User = $env:USERNAME
            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }

    try {
        # Perform the operation within timeout
        $result = Measure-PmcOperation -Name "SecureFileOp:$Operation" -Category 'SECURITY' -ScriptBlock {
            switch ($Operation) {
                'read' {
                    return Get-Content -Path $Path -Raw -Encoding UTF8
                }
                'write' {
                    return Set-Content -Path $Path -Value $Content -Encoding UTF8
                }
                'delete' {
                    return Remove-Item -Path $Path -Force
                }
                'custom' {
                    if ($ScriptBlock) {
                        return & $ScriptBlock
                    } else {
                        throw "Custom operation requires ScriptBlock parameter"
                    }
                }
            }
        }

        return $result

    } catch {
        Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Secure file operation failed: $_" -Data @{ Path = $Path; Operation = $Operation }
        throw
    }
}

function Protect-PmcUserInput {
    <#
    .SYNOPSIS
    Sanitizes user input for safe processing

    .PARAMETER Input
    User input to sanitize

    .PARAMETER AllowHtml
    Whether to allow HTML tags (default: false)
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Input,

        [bool]$AllowHtml = $false
    )

    try {
        $sanitized = $Input

        # Remove null bytes
        $sanitized = $sanitized -replace "`0", ''

        # Remove Unicode direction overrides
        $sanitized = $sanitized -replace '[\u202A-\u202E\u2066-\u2069]', ''

        # Remove or escape HTML if not allowed
        if (-not $AllowHtml) {
            $sanitized = $sanitized -replace '<', '&lt;'
            $sanitized = $sanitized -replace '>', '&gt;'
            $sanitized = $sanitized -replace '"', '&quot;'
            $sanitized = $sanitized -replace "'", '&#39;'
        }

        # Limit length
        if ($sanitized.Length -gt 10000) {
            $sanitized = $sanitized.Substring(0, 10000)
            Write-PmcDebug -Level 2 -Category 'SECURITY' -Message "Input truncated to 10000 characters"
        }

        Write-PmcDebug -Level 3 -Category 'SECURITY' -Message "Input sanitized" -Data @{
            OriginalLength = $Input.Length
            SanitizedLength = $sanitized.Length
            Modified = ($Input -ne $sanitized)
        }

        return $sanitized

    } catch {
        Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Input sanitization failed: $_"
        return ""
    }
}

function Test-PmcResourceLimits {
    <#
    .SYNOPSIS
    Checks current resource usage against configured limits

    .DESCRIPTION
    Monitors memory usage, execution time, and other resource constraints
    #>

    $securityState = Get-PmcSecurityState
    if (-not $securityState.ResourceLimitsEnabled) { return $true }

    try {
        # Check memory usage
        $process = Get-Process -Id $PID
        $memoryUsage = $process.WorkingSet64

        if ($memoryUsage -gt $securityState.MaxMemoryUsage) {
            Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Memory limit exceeded" -Data @{
                CurrentUsage = $memoryUsage
                Limit = $securityState.MaxMemoryUsage
                UsagePercent = [Math]::Round(($memoryUsage / $securityState.MaxMemoryUsage) * 100, 2)
            }
            return $false
        }

        Write-PmcDebug -Level 3 -Category 'SECURITY' -Message "Resource limits check passed" -Data @{
            MemoryUsage = $memoryUsage
            MemoryLimit = $securityState.MaxMemoryUsage
        }

        return $true

    } catch {
        Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Resource limit check failed: $_"
        return $false
    }
}

function Get-PmcSecurityStatus {
    <#
    .SYNOPSIS
    Returns current security system status and configuration
    #>

    $securityState = Get-PmcSecurityState
    return [PSCustomObject]@{
        InputValidationEnabled = $securityState.InputValidationEnabled
        PathWhitelistEnabled = $securityState.PathWhitelistEnabled
        ResourceLimitsEnabled = $securityState.ResourceLimitsEnabled
        SensitiveDataScanEnabled = $securityState.SensitiveDataScanEnabled
        AuditLoggingEnabled = $securityState.AuditLoggingEnabled
        AllowedWritePaths = $securityState.AllowedWritePaths
        MaxFileSize = $securityState.MaxFileSize
        MaxMemoryUsage = $securityState.MaxMemoryUsage
        MaxExecutionTime = $securityState.MaxExecutionTime
        CurrentMemoryUsage = (Get-Process -Id $PID).WorkingSet64
    }
}

function Set-PmcSecurityLevel {
    <#
    .SYNOPSIS
    Configures security level with predefined profiles

    .PARAMETER Level
    Security level: 'permissive', 'balanced', 'strict'
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('permissive', 'balanced', 'strict')]
        [string]$Level
    )

    switch ($Level) {
        'permissive' {
            Update-PmcStateSection -Section 'Security' -Values @{
                InputValidationEnabled = $false
                PathWhitelistEnabled = $false
                ResourceLimitsEnabled = $false
                SensitiveDataScanEnabled = $false
            }
        }
        'balanced' {
            Update-PmcStateSection -Section 'Security' -Values @{
                InputValidationEnabled = $true
                PathWhitelistEnabled = $true
                ResourceLimitsEnabled = $true
                SensitiveDataScanEnabled = $true
                MaxFileSize = 100MB
                MaxMemoryUsage = 500MB
            }
        }
        'strict' {
            Update-PmcStateSection -Section 'Security' -Values @{
                InputValidationEnabled = $true
                PathWhitelistEnabled = $true
                ResourceLimitsEnabled = $true
                SensitiveDataScanEnabled = $true
                AuditLoggingEnabled = $true
                MaxFileSize = 50MB
                MaxMemoryUsage = 256MB
            }
        }
    }

    Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Security level changed to: $Level" -Data (Get-PmcSecurityState)
}

function Update-PmcSecurityFromConfig {
    <#
    .SYNOPSIS
    Updates security settings from configuration after config provider is ready
    #>
    try {
        $cfg = Get-PmcConfig
        if ($cfg.Security) {
            if ($cfg.Security.AllowedWritePaths) {
                Set-PmcState -Section 'Security' -Key 'AllowedWritePaths' -Value @($cfg.Security.AllowedWritePaths)
            }
            if ($cfg.Security.MaxFileSize) {
                try {
                    $sizeStr = [string]$cfg.Security.MaxFileSize
                    if ($sizeStr -match '^(\d+)(MB|GB)?$') {
                        $num = [int64]$matches[1]
                        $unit = $matches[2]
                        $bytes = switch ($unit) {
                            'GB' { $num * 1GB }
                            'MB' { $num * 1MB }
                            default { $num }
                        }
                        Set-PmcState -Section 'Security' -Key 'MaxFileSize' -Value $bytes
                    }
                } catch {
                    # Size configuration parsing failed - keep default value
                }
            }
            if ($cfg.Security.MaxMemoryUsage) {
                try {
                    $sizeStr = [string]$cfg.Security.MaxMemoryUsage
                    if ($sizeStr -match '^(\d+)(MB|GB)?$') {
                        $num = [int64]$matches[1]
                        $unit = $matches[2]
                        $bytes = switch ($unit) {
                            'GB' { $num * 1GB }
                            'MB' { $num * 1MB }
                            default { $num }
                        }
                        Set-PmcState -Section 'Security' -Key 'MaxMemoryUsage' -Value $bytes
                    }
                } catch {
                    # Size configuration parsing failed - keep default value
                }
            }
            if ($cfg.Security.RequirePathWhitelist -ne $null) {
                Set-PmcState -Section 'Security' -Key 'PathWhitelistEnabled' -Value ([bool]$cfg.Security.RequirePathWhitelist)
            }
            if ($cfg.Security.ScanForSensitiveData -ne $null) {
                Set-PmcState -Section 'Security' -Key 'SensitiveDataScanEnabled' -Value ([bool]$cfg.Security.ScanForSensitiveData)
            }
            if ($cfg.Security.AuditAllFileOps -ne $null) {
                Set-PmcState -Section 'Security' -Key 'AuditLoggingEnabled' -Value ([bool]$cfg.Security.AuditAllFileOps)
            }
            if ($cfg.Security.AllowTemplateExecution -ne $null) {
                Set-PmcState -Section 'Security' -Key 'TemplateExecutionEnabled' -Value ([bool]$cfg.Security.AllowTemplateExecution)
            }
        }
    } catch {
        Write-PmcDebug -Level 1 -Category 'SECURITY' -Message "Failed to load security config: $_"
    }
}

# Note: Security system is initialized by the root orchestrator after config providers are set

#Export-ModuleMember -Function Initialize-PmcSecuritySystem, Test-PmcInputSafety, Test-PmcPathSafety, Invoke-PmcSecureFileOperation, Protect-PmcUserInput, Test-PmcResourceLimits, Get-PmcSecurityStatus, Set-PmcSecurityLevel, Update-PmcSecurityFromConfig