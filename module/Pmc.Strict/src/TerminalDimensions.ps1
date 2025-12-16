# TerminalDimensions.ps1 - Centralized terminal dimension service for PMC
# Provides consistent screen dimension handling across all components

Set-StrictMode -Version Latest

class PmcTerminalService {
    static [int] $CachedWidth = 0
    static [int] $CachedHeight = 0
    static [datetime] $LastUpdate = [datetime]::MinValue
    static [int] $CacheValidityMs = 500  # Cache dimensions for 500ms

    static [hashtable] GetDimensions() {
        $now = [datetime]::Now
        if (($now - [PmcTerminalService]::LastUpdate).TotalMilliseconds -lt [PmcTerminalService]::CacheValidityMs -and
            [PmcTerminalService]::CachedWidth -gt 0 -and [PmcTerminalService]::CachedHeight -gt 0) {
            return @{
                Width = [PmcTerminalService]::CachedWidth
                Height = [PmcTerminalService]::CachedHeight
                MinWidth = 40
                MinHeight = 10
                IsCached = $true
            }
        }

        # Refresh cache
        try {
            [PmcTerminalService]::CachedWidth = [Console]::WindowWidth
            [PmcTerminalService]::CachedHeight = [Console]::WindowHeight
            [PmcTerminalService]::LastUpdate = $now
        } catch {
            # Fallback values if console access fails
            [PmcTerminalService]::CachedWidth = 80
            [PmcTerminalService]::CachedHeight = 24
        }

        # Apply minimum constraints
        if ([PmcTerminalService]::CachedWidth -lt 40) { [PmcTerminalService]::CachedWidth = 80 }
        if ([PmcTerminalService]::CachedHeight -lt 10) { [PmcTerminalService]::CachedHeight = 24 }

        return @{
            Width = [PmcTerminalService]::CachedWidth
            Height = [PmcTerminalService]::CachedHeight
            MinWidth = 40
            MinHeight = 10
            IsCached = $false
        }
    }

    static [int] GetWidth() {
        return [PmcTerminalService]::GetDimensions().Width
    }

    static [int] GetHeight() {
        return [PmcTerminalService]::GetDimensions().Height
    }

    static [void] InvalidateCache() {
        [PmcTerminalService]::LastUpdate = [datetime]::MinValue
    }

    static [bool] ValidateContent([string]$Content, [int]$MaxWidth = 0, [int]$MaxHeight = 0) {
        $dims = [PmcTerminalService]::GetDimensions()
        $actualMaxWidth = $(if ($MaxWidth -gt 0) { [Math]::Min($MaxWidth, $dims.Width) } else { $dims.Width })
        $actualMaxHeight = $(if ($MaxHeight -gt 0) { [Math]::Min($MaxHeight, $dims.Height) } else { $dims.Height })

        $lines = $Content -split "`n"
        if (@($lines).Count -gt $actualMaxHeight) { return $false }

        foreach ($line in $lines) {
            # Strip ANSI codes for accurate width measurement
            $cleanLine = $line -replace '\e\[[0-9;]*m', ''
            if ($cleanLine.Length -gt $actualMaxWidth) { return $false }
        }

        return $true
    }

    static [string] EnforceContentBounds([string]$Content, [int]$MaxWidth = 0, [int]$MaxHeight = 0) {
        $dims = [PmcTerminalService]::GetDimensions()
        $actualMaxWidth = $(if ($MaxWidth -gt 0) { [Math]::Min($MaxWidth, $dims.Width) } else { $dims.Width })
        $actualMaxHeight = $(if ($MaxHeight -gt 0) { [Math]::Min($MaxHeight, $dims.Height) } else { $dims.Height })

        $lines = $Content -split "`n"
        $resultLines = @()

        # Truncate height if needed
        $linesToProcess = $(if (@($lines).Count -gt $actualMaxHeight) {
            $lines[0..($actualMaxHeight - 1)]
        } else {
            $lines
        })

        # Truncate width for each line
        foreach ($line in $linesToProcess) {
            if ($line.Length -le $actualMaxWidth) {
                $resultLines += $line
            } else {
                # Check if line contains ANSI codes
                if ($line -match '\e\[[0-9;]*m') {
                    # Complex truncation preserving ANSI codes
                    $resultLines += [PmcTerminalService]::TruncateWithAnsi($line, $actualMaxWidth)
                } else {
                    # Simple truncation
                    $resultLines += $line.Substring(0, [Math]::Min($line.Length, $actualMaxWidth - 3)) + "..."
                }
            }
        }

        return ($resultLines -join "`n")
    }

    static [string] TruncateWithAnsi([string]$Text, [int]$MaxWidth) {
        # Preserve ANSI codes while truncating visible text
        $ansiPattern = '\e\[[0-9;]*m'
        $parts = $Text -split "($ansiPattern)"
        $result = ""
        $visibleLength = 0

        foreach ($part in $parts) {
            if ($part -match $ansiPattern) {
                # ANSI code - add without counting length
                $result += $part
            } else {
                # Regular text - check length
                $remainingSpace = $MaxWidth - $visibleLength
                if ($remainingSpace -le 0) { break }

                if ($part.Length -le $remainingSpace) {
                    $result += $part
                    $visibleLength += $part.Length
                } else {
                    $result += $part.Substring(0, [Math]::Max(0, $remainingSpace - 3)) + "..."
                    break
                }
            }
        }

        return $result
    }
}

# Convenience functions for backward compatibility
function Get-PmcTerminalWidth { return [PmcTerminalService]::GetWidth() }
function Get-PmcTerminalHeight { return [PmcTerminalService]::GetHeight() }
function Get-PmcTerminalDimensions { return [PmcTerminalService]::GetDimensions() }
function Test-PmcContentBounds { param([string]$Content, [int]$MaxWidth = 0, [int]$MaxHeight = 0) return [PmcTerminalService]::ValidateContent($Content, $MaxWidth, $MaxHeight) }
function Set-PmcContentBounds { param([string]$Content, [int]$MaxWidth = 0, [int]$MaxHeight = 0) return [PmcTerminalService]::EnforceContentBounds($Content, $MaxWidth, $MaxHeight) }

#Export-ModuleMember -Function Get-PmcTerminalWidth, Get-PmcTerminalHeight, Get-PmcTerminalDimensions, Test-PmcContentBounds, Set-PmcContentBounds