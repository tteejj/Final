# TerminalDimensions.ps1 - Centralized terminal dimension service for PMC
# Provides consistent screen dimension handling across all components
# OPTIMIZED: Reduced cache validity, added resize events, StringBuilder for O(n) performance

Set-StrictMode -Version Latest

class PmcTerminalService {
    static [int] $CachedWidth = 0
    static [int] $CachedHeight = 0
    static [datetime] $LastUpdate = [datetime]::MinValue
    static [int] $CacheValidityMs = 100  # Reduced from 500ms for snappier resize detection
    
    # Track previous dimensions for resize detection
    static [int] $PreviousWidth = 0
    static [int] $PreviousHeight = 0
    
    # Resize event callbacks
    static [System.Collections.Generic.List[scriptblock]] $OnResizeCallbacks = [System.Collections.Generic.List[scriptblock]]::new()

    static [hashtable] GetDimensions() {
        $now = [datetime]::Now
        $elapsed = ($now - [PmcTerminalService]::LastUpdate).TotalMilliseconds
        
        # Use cached values if still valid
        if ($elapsed -lt [PmcTerminalService]::CacheValidityMs -and
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
            $newWidth = [Console]::WindowWidth
            $newHeight = [Console]::WindowHeight
            
            # Check for resize
            $resized = ($newWidth -ne [PmcTerminalService]::CachedWidth -or 
                       $newHeight -ne [PmcTerminalService]::CachedHeight) -and
                       [PmcTerminalService]::CachedWidth -gt 0
            
            [PmcTerminalService]::PreviousWidth = [PmcTerminalService]::CachedWidth
            [PmcTerminalService]::PreviousHeight = [PmcTerminalService]::CachedHeight
            [PmcTerminalService]::CachedWidth = $newWidth
            [PmcTerminalService]::CachedHeight = $newHeight
            [PmcTerminalService]::LastUpdate = $now
            
            # Fire resize callbacks if dimensions changed
            if ($resized -and [PmcTerminalService]::OnResizeCallbacks.Count -gt 0) {
                foreach ($callback in [PmcTerminalService]::OnResizeCallbacks) {
                    try { & $callback $newWidth $newHeight } catch { }
                }
            }
        } catch {
            # Fallback values if console access fails
            if ([PmcTerminalService]::CachedWidth -eq 0) {
                [PmcTerminalService]::CachedWidth = 80
                [PmcTerminalService]::CachedHeight = 24
            }
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
    
    # Check for resize without full dimension refresh (for polling in main loop)
    static [bool] CheckForResize() {
        try {
            $currentWidth = [Console]::WindowWidth
            $currentHeight = [Console]::WindowHeight
            if ($currentWidth -ne [PmcTerminalService]::CachedWidth -or 
                $currentHeight -ne [PmcTerminalService]::CachedHeight) {
                [PmcTerminalService]::InvalidateCache()
                return $true
            }
        } catch { }
        return $false
    }
    
    # Register a callback for resize events
    static [void] RegisterOnResize([scriptblock]$callback) {
        if ($callback) {
            [PmcTerminalService]::OnResizeCallbacks.Add($callback)
        }
    }
    
    # Unregister a resize callback
    static [void] UnregisterOnResize([scriptblock]$callback) {
        if ($callback) {
            [PmcTerminalService]::OnResizeCallbacks.Remove($callback)
        }
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
        # Use List instead of array += for O(n) performance
        $resultLines = [System.Collections.Generic.List[string]]::new()

        # Truncate height if needed
        $linesToProcess = $(if (@($lines).Count -gt $actualMaxHeight) {
            $lines[0..($actualMaxHeight - 1)]
        } else {
            $lines
        })

        # Truncate width for each line
        foreach ($line in $linesToProcess) {
            if ($line.Length -le $actualMaxWidth) {
                $resultLines.Add($line)
            } else {
                # Check if line contains ANSI codes
                if ($line -match '\e\[[0-9;]*m') {
                    # Complex truncation preserving ANSI codes
                    $resultLines.Add([PmcTerminalService]::TruncateWithAnsi($line, $actualMaxWidth))
                } else {
                    # Simple truncation
                    $resultLines.Add($line.Substring(0, [Math]::Min($line.Length, $actualMaxWidth - 3)) + "...")
                }
            }
        }

        return ($resultLines -join "`n")
    }

    static [string] TruncateWithAnsi([string]$Text, [int]$MaxWidth) {
        # Preserve ANSI codes while truncating visible text
        # OPTIMIZED: Using StringBuilder for O(n) instead of O(n²) string concatenation
        $ansiPattern = '\e\[[0-9;]*m'
        $parts = $Text -split "($ansiPattern)"
        $sb = [System.Text.StringBuilder]::new($Text.Length)
        $visibleLength = 0

        foreach ($part in $parts) {
            if ($part -match $ansiPattern) {
                # ANSI code - add without counting length
                [void]$sb.Append($part)
            } else {
                # Regular text - check length
                $remainingSpace = $MaxWidth - $visibleLength
                if ($remainingSpace -le 0) { break }

                if ($part.Length -le $remainingSpace) {
                    [void]$sb.Append($part)
                    $visibleLength += $part.Length
                } else {
                    [void]$sb.Append($part.Substring(0, [Math]::Max(0, $remainingSpace - 3)))
                    [void]$sb.Append("...")
                    break
                }
            }
        }

        return $sb.ToString()
    }
}

# Convenience functions for backward compatibility
function Get-PmcTerminalWidth { return [PmcTerminalService]::GetWidth() }
function Get-PmcTerminalHeight { return [PmcTerminalService]::GetHeight() }
function Get-PmcTerminalDimensions { return [PmcTerminalService]::GetDimensions() }
function Test-PmcContentBounds { param([string]$Content, [int]$MaxWidth = 0, [int]$MaxHeight = 0) return [PmcTerminalService]::ValidateContent($Content, $MaxWidth, $MaxHeight) }
function Set-PmcContentBounds { param([string]$Content, [int]$MaxWidth = 0, [int]$MaxHeight = 0) return [PmcTerminalService]::EnforceContentBounds($Content, $MaxWidth, $MaxHeight) }

#Export-ModuleMember -Function Get-PmcTerminalWidth, Get-PmcTerminalHeight, Get-PmcTerminalDimensions, Test-PmcContentBounds, Set-PmcContentBounds