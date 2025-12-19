# ConsoleUI DepsLoader - loads dependencies from src/ (primary) and deps/ (ConsoleUI-specific only)
# Eliminates duplication by using src/ as single source of truth

param()

Set-StrictMode -Version Latest

# Paths
$depsDir = Join-Path $PSScriptRoot 'deps'
$srcDir = Join-Path $PSScriptRoot '../src'  # Pmc.Strict/consoleui/../src = Pmc.Strict/src

# Verify paths exist
if (-not (Test-Path $srcDir)) {
    throw "Source directory not found: $srcDir"
}
if (-not (Test-Path $depsDir)) {
    throw "Deps directory not found: $depsDir"
}

# NOTE: Most dependencies are already loaded by Pmc.Strict.psm1 module
# Only load ConsoleUI-specific files here to avoid duplicate loading

# Neutralize Export-ModuleMember calls in copied files
function Export-ModuleMember { param([Parameter(ValueFromRemainingArguments=$true)]$args) }

# Type normalization helpers (helpers/ - ConsoleUI-specific)
. (Join-Path $PSScriptRoot 'helpers/TypeNormalization.ps1')

# ConsoleUI-specific PmcTemplate class (UNIQUE to deps/)
. (Join-Path $depsDir 'PmcTemplate.ps1')

# Help content (UNIQUE to deps/ - curated for ConsoleUI)
. (Join-Path $depsDir 'HelpContent.ps1')

# Project utility function (UNIQUE to deps/)
. (Join-Path $depsDir 'Project.ps1')

# Excel integration (from src/, optional - will load if Excel is available)
try {
    . (Join-Path $srcDir 'Excel.ps1')
    # Initialize field mappings from disk or defaults
    if (Get-Command Initialize-ExcelT2020Mappings -ErrorAction SilentlyContinue) {
        Initialize-ExcelT2020Mappings
    }
} catch {
    # Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [DepsLoader] Excel integration not available (Excel COM not installed)"
}

# Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [DepsLoader] ConsoleUI deps loaded (from src/ + deps/ unique files)"