# BackupCleanupHelper.ps1 - Cleanup stale backup files at startup
#
# FIX 7.2: Backup File Accumulation
# Cleans up old backup files in the application root to prevent disk space growth

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Clean up stale backup files in the application root directory

.DESCRIPTION
Called once at startup to remove old backup files.
Keeps only the 5 most recent backups to prevent disk space growth.

.PARAMETER RootPath
The application root directory to clean

.EXAMPLE
Invoke-BackupCleanup -RootPath "/home/user/pmc-tui"
#>
function Invoke-BackupCleanup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )
    
    try {
        # Skip if path doesn't exist
        if (-not (Test-Path $RootPath)) { return }
        
        # Find all backup files matching common patterns
        $backupPatterns = @('*.backup.*', '*.bak[0-9]', '*.bak', '*.undo')
        $allBackups = @()
        
        foreach ($pattern in $backupPatterns) {
            $found = Get-ChildItem -Path $RootPath -Filter $pattern -File -ErrorAction SilentlyContinue
            if ($found) {
                $allBackups += $found
            }
        }
        
        # Keep only 5 most recent backups total
        if ($allBackups.Count -gt 5) {
            $toDelete = $allBackups | Sort-Object LastWriteTime -Descending | Select-Object -Skip 5
            foreach ($file in $toDelete) {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                # Uncomment for debugging:
                # Write-PmcTuiLog "BackupCleanup: Deleted stale backup $($file.Name)" "DEBUG"
            }
        }
    }
    catch {
        # Non-critical operation - log and continue
        # Write-PmcTuiLog "BackupCleanup: Error during cleanup: $_" "WARNING"
    }
}
