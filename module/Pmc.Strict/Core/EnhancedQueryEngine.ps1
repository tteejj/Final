# PMC Enhanced Query Engine - Optimized query parsing and execution
# Implements Phase 3 query language improvements

Set-StrictMode -Version Latest

# Enhanced query specification with validation and optimization
class PmcEnhancedQuerySpec {
    [string] $Domain
    [string[]] $RawTokens = @()
    [hashtable] $Filters = @{}
    [hashtable] $Directives = @{}
    [hashtable] $Metadata = @{}
    [bool] $IsOptimized = $false
    [string[]] $ValidationErrors = @()
    [datetime] $ParseTime = [datetime]::Now

    # Query optimization hints
    [bool] $UseIndex = $false
    [string[]] $IndexFields = @()
    [int] $EstimatedRows = -1
    [string] $OptimizationStrategy = 'default'

    [void] AddValidationError([string]$error) {
        $this.ValidationErrors += $error
    }

    [bool] IsValid() {
        return $this.ValidationErrors.Count -eq 0
    }

    [void] MarkOptimized([string]$strategy) {
        $this.IsOptimized = $true
        $this.OptimizationStrategy = $strategy
    }
}

# AST model for enhanced queries (typed, structured)
class PmcAstNode { }
class PmcAstFilterNode : PmcAstNode {
    [string] $Field
    [string] $Operator
    [string] $Value
    PmcAstFilterNode([string]$f,[string]$op,[string]$v){ $this.Field=$f; $this.Operator=$op; $this.Value=$v }
}
class PmcAstDirectiveNode : PmcAstNode {
    [string] $Name
    [object] $Value
    PmcAstDirectiveNode([string]$n,[object]$v){ $this.Name=$n; $this.Value=$v }
}
class PmcAstQuery : PmcAstNode {
    [string] $Domain
    [System.Collections.Generic.List[PmcAstFilterNode]] $Filters
function Initialize-PmcEnhancedQueryEngine {
    if ($Script:PmcEnhancedQueryParser) {
        Write-Warning "PMC Enhanced Query Engine already initialized"
        return
    }

    $Script:PmcEnhancedQueryParser = [PmcEnhancedQueryParser]::new()
    $Script:PmcEnhancedQueryExecutor = [PmcEnhancedQueryExecutor]::new()

    Write-PmcDebug -Level 2 -Category 'EnhancedQuery' -Message "Enhanced query engine initialized"
}

function Invoke-PmcEnhancedQuery {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Tokens,

        [switch]$NoCache
    )

    if (-not $Script:PmcEnhancedQueryParser) {
        Initialize-PmcEnhancedQueryEngine
    }

    $spec = $Script:PmcEnhancedQueryParser.ParseQuery($Tokens)

    if (-not $spec.IsValid()) {
        Write-PmcStyled -Style 'Error' -Text "Query validation failed: $($spec.ValidationErrors -join '; ')"
        return @{ Success = $false; Errors = $spec.ValidationErrors }
    }

    if ($NoCache) {
        $Script:PmcEnhancedQueryExecutor.ClearCache()
    }

    return $Script:PmcEnhancedQueryExecutor.ExecuteQuery($spec)
}

function Get-PmcQueryPerformanceStats {
    if (-not $Script:PmcEnhancedQueryExecutor) {
        Write-Host "Enhanced query engine not initialized"
        return
    }

    $stats = $Script:PmcEnhancedQueryExecutor.GetExecutionStats()

    Write-Host "PMC Query Performance Statistics" -ForegroundColor Green
    Write-Host "===============================" -ForegroundColor Green
    Write-Host "Queries Executed: $($stats.QueriesExecuted)"
    Write-Host "Average Duration: $($stats.AverageDuration) ms"
    Write-Host "Total Duration: $($stats.TotalDuration) ms"
    Write-Host ""
    Write-Host "Cache Performance:" -ForegroundColor Yellow
    Write-Host "Cache Size: $($stats.CacheStats.Size)"
    Write-Host "Cache Hit Rate: $($stats.CacheStats.HitRate)%"
    Write-Host "Cache Hits: $($stats.CacheStats.Hits)"
    Write-Host "Cache Misses: $($stats.CacheStats.Misses)"
    Write-Host "Cache Evictions: $($stats.CacheStats.Evictions)"
}

Export-ModuleMember -Function Initialize-PmcEnhancedQueryEngine, Invoke-PmcEnhancedQuery, Get-PmcQueryPerformanceStats