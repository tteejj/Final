#!/usr/bin/env pwsh
# Remove all commented-out PERF debug lines

param([switch]$DryRun)

Set-StrictMode -Version Latest

Write-Host "=== Cleaning Commented Debug Code ===" -ForegroundColor Cyan
Write-Host ""

# Find all files with PERF comments
$files = Get-ChildItem -Path "/home/teej/ztest/module/Pmc.Strict/consoleui" -Recurse -Filter "*.ps1" |
    Where-Object { (Get-Content $_.FullName -Raw) -match '# PERF:|# PERF FIX:' }

Write-Host "Found $($files.Count) files with commented debug code" -ForegroundColor Yellow
Write-Host ""

$totalRemoved = 0

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $originalLineCount = ($content -split "`n").Count
    
    # Count how many lines will be removed
    $perfLines = @(($content -split "`n") | Where-Object { $_ -match '^\s*# PERF:|^\s*# PERF FIX:' })
    
    if ($perfLines.Count -eq 0) {
        continue
    }
    
    Write-Host "Processing: $($file.Name)" -ForegroundColor Yellow
    Write-Host "  Found $($perfLines.Count) commented debug lines" -ForegroundColor Gray
    
    if ($DryRun) {
        # Show what would be removed
        Write-Host "  Would remove:" -ForegroundColor Gray
        $perfLines | Select-Object -First 3 | ForEach-Object {
            Write-Host "    $_" -ForegroundColor DarkGray
        }
        if ($perfLines.Count -gt 3) {
            Write-Host "    ... and $($perfLines.Count - 3) more" -ForegroundColor DarkGray
        }
    }
    else {
        # Remove lines matching pattern
        $newContent = ($content -split "`n") | Where-Object {
            $_ -notmatch '^\s*# PERF:' -and $_ -notmatch '^\s*# PERF FIX:'
        } | Out-String
        
        # Write back
        $newContent | Set-Content $file.FullName -NoNewline
        
        $newLineCount = ($newContent -split "`n").Count
        $removed = $originalLineCount - $newLineCount
        $totalRemoved += $removed
        
        Write-Host "  ✓ Removed $removed lines" -ForegroundColor Green
        
        # Validate syntax
        try {
            $null = [System.Management.Automation.PSParser]::Tokenize(
                $newContent,
                [ref]$null
            )
            Write-Host "  ✓ Syntax valid" -ForegroundColor Green
        }
        catch {
            Write-Host "  ✗ SYNTAX ERROR: $_" -ForegroundColor Red
            Write-Host "  Restoring from backup..." -ForegroundColor Yellow
            $content | Set-Content $file.FullName -NoNewline
        }
    }
    
    Write-Host ""
}

if ($DryRun) {
    Write-Host "=== DRY RUN - No files modified ===" -ForegroundColor Yellow
    Write-Host "Run without -DryRun to actually remove lines" -ForegroundColor Gray
}
else {
    Write-Host "=== Cleanup Complete ===" -ForegroundColor Green
    Write-Host "Total lines removed: $totalRemoved" -ForegroundColor Green
}
