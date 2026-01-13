# PMC Enhanced Command Processor - Secure, performant command execution
# Implements Phase 3 core logic improvements

Set-StrictMode -Version Latest

# Input sanitization and validation
class PmcInputSanitizer {
    static [string] SanitizeCommandInput([string]$input) {
        if (-not $input) { return "" }

        # Validate length
        if ($input.Length -gt 2000) {
            throw "Command input too long (max 2000 characters)"
        }

        # Remove dangerous characters that could enable injection
        $sanitized = $input -replace '[`$;&|<>{}]', ''

        # Check for potentially dangerous patterns
        $dangerousPatterns = @(
            'Invoke-Expression', 'iex', 'cmd\.exe', 'powershell\.exe',
            'Start-Process', 'New-Object.*System\.', 'Get-WmiObject',
            '\[.*\]::.*', 'Add-Type', 'Reflection\.'
        )

        foreach ($pattern in $dangerousPatterns) {
            if ($sanitized -match $pattern) {
                throw "Potentially dangerous input detected: $pattern"
            }
        }

        return $sanitized.Trim()
    }

    static [bool] ValidateTokenSafety([string]$token) {
        if (-not $token) { return $true }

        # Allow expected PMC patterns
        $safePatterns = @(
            '^@[\w\s\-\.]+$',      # Project references
            '^p[1-3]$',             # Priority
            '^due:[\w\-:]+$',       # Due dates
            '^#[\w\-]+$',           # Tags
            '^task:\d+$',           # Task references
            '^[\w\-\.\s]+$'         # General text
        )

        foreach ($pattern in $safePatterns) {
            if ($token -match $pattern) { return $true }
        }

        # Check length
        if ($token.Length -gt 100) { return $false }

        # Reject dangerous patterns
        if ($token -match '[`$;&|<>{}()[\]]') { return $false }

        return $true
    }
}

# Enhanced command context with validation
class PmcEnhancedCommandContext {
    [string] $Domain
    [string] $Action
    [hashtable] $Args = @{}
    [string[]] $FreeText = @()
    [datetime] $Timestamp = [datetime]::Now
    [string] $OriginalInput
    [hashtable] $Metadata = @{}
    [bool] $IsValidated = $false
    [string[]] $ValidationErrors = @()

    PmcEnhancedCommandContext([string]$domain, [string]$action) {
        $this.Domain = $domain
        $this.Action = $action
    }

    [void] AddValidationError([string]$error) {
        $this.ValidationErrors += $error
    }

    [bool] IsValid() {
        return $this.ValidationErrors.Count -eq 0
    }

    [void] MarkValidated() {
        $this.IsValidated = $true
    }
}

# Performance monitoring for command execution
class PmcCommandPerformanceMonitor {
    hidden [hashtable] $_metrics = @{}
    hidden [int] $_commandCount = 0

    [void] RecordCommand([string]$command, [long]$durationMs, [bool]$success) {
        $this._commandCount++

        $key = $command.Split(' ')[0]  # Use first token as key
        if (-not $this._metrics.ContainsKey($key)) {
            $this._metrics[$key] = @{
                Count = 0
                TotalMs = 0
                Successes = 0
                Failures = 0
                AvgMs = 0
                MaxMs = 0
                MinMs = [long]::MaxValue
            }
        }

        $metric = $this._metrics[$key]
        $metric.Count++
        $metric.TotalMs += $durationMs

        if ($success) { $metric.Successes++ } else { $metric.Failures++ }

        $metric.AvgMs = [Math]::Round($metric.TotalMs / $metric.Count, 2)
        $metric.MaxMs = [Math]::Max($metric.MaxMs, $durationMs)
        $metric.MinMs = [Math]::Min($metric.MinMs, $durationMs)
    }

    [hashtable] GetMetrics() {
        return $this._metrics.Clone()
    }

    [int] GetCommandCount() {
        return $this._commandCount
    }

    [void] Reset() {
        $this._metrics.Clear()
        $this._commandCount = 0
    }
}

# Enhanced command processor with security and performance improvements
class PmcEnhancedCommandProcessor {
    hidden [PmcCommandPerformanceMonitor] $_perfMonitor
    hidden [hashtable] $_cache = @{}
    hidden [datetime] $_lastCacheClean = [datetime]::Now
    hidden [int] $_maxCacheSize = 100

    PmcEnhancedCommandProcessor() {
        $this._perfMonitor = [PmcCommandPerformanceMonitor]::new()
    }

    # Enhanced command execution with full pipeline
    [object] ExecuteCommand([string]$input) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $success = $false
        $result = $null

        try {
            # Step 1: Input sanitization
            $sanitized = [PmcInputSanitizer]::SanitizeCommandInput($input)
            Write-PmcDebug -Level 3 -Category 'EnhancedProcessor' -Message "Input sanitized" -Data @{ Original = $input.Length; Sanitized = $sanitized.Length }

            # Step 2: Tokenization with safety validation
            $tokens = $this.SafeTokenize($sanitized)

            # Step 3: Context parsing with enhanced validation
            $context = $this.ParseEnhancedContext($tokens, $sanitized)

            # Step 4: Security validation
            $this.ValidateContextSecurity($context)

            # Step 5: Business logic validation
            $this.ValidateContextBusiness($context)

            if (-not $context.IsValid()) {
                throw "Validation failed: $($context.ValidationErrors -join '; ')"
            }

            # Step 6: Execute with performance monitoring
            $result = $this.ExecuteValidatedContext($context)
            $success = $true

            Write-PmcDebug -Level 2 -Category 'EnhancedProcessor' -Message "Command executed successfully" -Data @{ Domain = $context.Domain; Action = $context.Action; Duration = $stopwatch.ElapsedMilliseconds }

        } catch {
            Write-PmcDebug -Level 1 -Category 'EnhancedProcessor' -Message "Command execution failed" -Data @{ Error = $_.ToString(); Input = $input }
            $result = @{ Error = $_.ToString(); Success = $false }
        } finally {
            $stopwatch.Stop()
            $this._perfMonitor.RecordCommand($input, $stopwatch.ElapsedMilliseconds, $success)
            $this.CleanCacheIfNeeded()
        }

        return $result
    }

    # Safe tokenization with validation
    [string[]] SafeTokenize([string]$input) {
        $tokens = ConvertTo-PmcTokens $input

        foreach ($token in $tokens) {
            if (-not [PmcInputSanitizer]::ValidateTokenSafety($token)) {
                throw "Unsafe token detected: $token"
            }
        }

        return $tokens
    }

    # Enhanced context parsing
    [PmcEnhancedCommandContext] ParseEnhancedContext([string[]]$tokens, [string]$originalInput) {
        # Use existing parser as base, then enhance
        $parsed = ConvertTo-PmcContext $tokens

        if (-not $parsed.Success) {
            throw "Parse error: $($parsed.Error)"
        }

        # Create enhanced context
        $enhanced = [PmcEnhancedCommandContext]::new($parsed.Context.Domain, $parsed.Context.Action)
        $enhanced.Args = $parsed.Context.Args.Clone()
        $enhanced.FreeText = $parsed.Context.FreeText
        $enhanced.OriginalInput = $originalInput
        $enhanced.Metadata['Handler'] = $parsed.Handler

        return $enhanced
    }

    # Security validation layer
    [void] ValidateContextSecurity([PmcEnhancedCommandContext]$context) {
        # Validate domain and action are allowed
        $allowedDomains = @('task', 'project', 'time', 'help', 'config', 'query')
        if ($context.Domain -notin $allowedDomains) {
            $context.AddValidationError("Unknown domain: $($context.Domain)")
        }

        # Validate argument values for injection attempts
        foreach ($key in $context.Args.Keys) {
            $value = $context.Args[$key]
            if ($value -is [string]) {
                try {
                    [PmcInputSanitizer]::SanitizeCommandInput($value) | Out-Null
                } catch {
                    $context.AddValidationError("Unsafe argument value for $key`: $_")
                }
            }
        }

        # Validate free text
        foreach ($text in $context.FreeText) {
            if (-not [PmcInputSanitizer]::ValidateTokenSafety($text)) {
                $context.AddValidationError("Unsafe free text: $text")
            }
        }
    }

    # Business logic validation
    [void] ValidateContextBusiness([PmcEnhancedCommandContext]$context) {
        # Use existing validation but with enhanced error reporting
        try {
            $legacyContext = [PmcCommandContext]::new()
            $legacyContext.Domain = $context.Domain
            $legacyContext.Action = $context.Action
            $legacyContext.Args = $context.Args
            $legacyContext.FreeText = $context.FreeText

            Set-PmcContextDefaults -Context $legacyContext
            Normalize-PmcContextFields -Context $legacyContext

            $isValid = Test-PmcContext -Context $legacyContext
            if (-not $isValid) {
                $context.AddValidationError("Business logic validation failed")
            }

            # Copy back any normalized values
            $context.Args = $legacyContext.Args

        } catch {
            $context.AddValidationError("Business validation error: $_")
        }
    }

    # Execute validated context with enhanced error handling
    [object] ExecuteValidatedContext([PmcEnhancedCommandContext]$context) {
        # Prefer enhanced handler registry if available
        $legacyContext = [PmcCommandContext]::new()
        $legacyContext.Domain = $context.Domain
        $legacyContext.Action = $context.Action
        $legacyContext.Args = $context.Args
        $legacyContext.FreeText = $context.FreeText

        $usedEnhanced = $false
        try {
            if (Get-Command Get-PmcHandler -ErrorAction SilentlyContinue) {
                $desc = Get-PmcHandler -Domain $context.Domain -Action $context.Action
                if ($desc -and $desc.Execute) {
                    $usedEnhanced = $true
                    return (& $desc.Execute $legacyContext)
                }
            }
        } catch {}

        # Fall back to explicit handler name (must exist)
        $handler = $context.Metadata['Handler']
        if (-not (Get-Command -Name $handler -ErrorAction SilentlyContinue)) {
            throw "Handler not found: $handler"
        }

        return (& $handler -Context $legacyContext)
    }

    # Cache management
    [void] CleanCacheIfNeeded() {
        $now = [datetime]::Now
        if (($now - $this._lastCacheClean).TotalMinutes -gt 10 -or $this._cache.Count -gt $this._maxCacheSize) {
            $this._cache.Clear()
            $this._lastCacheClean = $now
            Write-PmcDebug -Level 3 -Category 'EnhancedProcessor' -Message "Cache cleaned"
        }
    }

    # Performance metrics
    [hashtable] GetPerformanceMetrics() {
        return $this._perfMonitor.GetMetrics()
    }

    [int] GetCommandCount() {
        return $this._perfMonitor.GetCommandCount()
    }

    [void] ResetMetrics() {
        $this._perfMonitor.Reset()
    }
}

# Global instance
$Script:PmcEnhancedCommandProcessor = $null

function Initialize-PmcEnhancedCommandProcessor {
    if ($Script:PmcEnhancedCommandProcessor) {
        Write-Warning "PMC Enhanced Command Processor already initialized"
        return
    }

    $Script:PmcEnhancedCommandProcessor = [PmcEnhancedCommandProcessor]::new()
    Write-PmcDebug -Level 2 -Category 'EnhancedProcessor' -Message "Enhanced command processor initialized"
}

function Get-PmcEnhancedCommandProcessor {
    if (-not $Script:PmcEnhancedCommandProcessor) {
        Initialize-PmcEnhancedCommandProcessor
    }
    return $Script:PmcEnhancedCommandProcessor
}

function Invoke-PmcEnhancedCommand {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command
    )

    $processor = Get-PmcEnhancedCommandProcessor
    return $processor.ExecuteCommand($Command)
}

function Get-PmcCommandPerformanceStats {
    $processor = Get-PmcEnhancedCommandProcessor
    $metrics = $processor.GetPerformanceMetrics()
    $commandCount = $processor.GetCommandCount()

    Write-Host "PMC Command Performance Statistics" -ForegroundColor Green
    Write-Host "=================================" -ForegroundColor Green
    Write-Host "Total Commands: $commandCount"
    Write-Host ""

    if ($metrics.Count -gt 0) {
        $sorted = $metrics.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending

        Write-Host "Top Commands by Usage:" -ForegroundColor Yellow
        Write-Host "Command".PadRight(15) + "Count".PadRight(8) + "Avg(ms)".PadRight(10) + "Max(ms)".PadRight(10) + "Success%" -ForegroundColor Cyan
        Write-Host ("-" * 50) -ForegroundColor Gray

        foreach ($entry in $sorted) {
            $cmd = $entry.Key
            $stats = $entry.Value
            $successRate = $(if ($stats.Count -gt 0) { [Math]::Round(($stats.Successes * 100.0) / $stats.Count, 1) } else { 0 })

            Write-Host ($cmd.PadRight(15) +
                      $stats.Count.ToString().PadRight(8) +
                      $stats.AvgMs.ToString().PadRight(10) +
                      $stats.MaxMs.ToString().PadRight(10) +
                      "$successRate%")
        }
    } else {
        Write-Host "No command statistics available yet."
    }
}

Export-ModuleMember -Function Initialize-PmcEnhancedCommandProcessor, Get-PmcEnhancedCommandProcessor, Invoke-PmcEnhancedCommand, Get-PmcCommandPerformanceStats