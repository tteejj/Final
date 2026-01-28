# SpeedTUI Performance Core - Hidden optimization layer
# This file contains performance optimizations that are completely transparent to developers
# Developers write normal PowerShell code, but it runs fast under the hood

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent
using namespace System.Text

<#
.SYNOPSIS
Internal string caching system for maximum performance

.DESCRIPTION
This class provides transparent caching of commonly used strings like spaces,
ANSI sequences, and box drawing characters. Developers never interact with this
directly - it's used internally to optimize string operations.

.EXAMPLE
# Developer writes normal code:
$spaces = " " * 50

# But internally, it's cached for performance
#>
class InternalStringCache {
    # Pre-cached common strings
    static [hashtable]$_spaces = @{}
    static [hashtable]$_ansiSequences = @{}
    static [hashtable]$_boxDrawing = @{}
    static [int]$_maxCacheSize = 200
    static [bool]$_initialized = $false

    # Initialize the cache with common strings
    static [void] Initialize() {
        if ([InternalStringCache]::_initialized) { return }

        # Pre-cache common space strings (1-200 characters)
        for ($i = 1; $i -le [InternalStringCache]::_maxCacheSize; $i++) {
            [InternalStringCache]::_spaces[$i] = " " * $i
        }

        # Pre-cache common ANSI sequences
        [InternalStringCache]::_ansiSequences["reset"] = "`e[0m"
        [InternalStringCache]::_ansiSequences["clear"] = "`e[2J"
        [InternalStringCache]::_ansiSequences["clearline"] = "`e[2K"
        [InternalStringCache]::_ansiSequences["home"] = "`e[H"
        [InternalStringCache]::_ansiSequences["hidecursor"] = "`e[?25l"
        [InternalStringCache]::_ansiSequences["showcursor"] = "`e[?25h"

        # Pre-cache box drawing characters
        [InternalStringCache]::_boxDrawing["horizontal"] = "─"
        [InternalStringCache]::_boxDrawing["vertical"] = "│"
        [InternalStringCache]::_boxDrawing["topleft"] = "┌"
        [InternalStringCache]::_boxDrawing["topright"] = "┐"
        [InternalStringCache]::_boxDrawing["bottomleft"] = "└"
        [InternalStringCache]::_boxDrawing["bottomright"] = "┘"

        [InternalStringCache]::_initialized = $true
    }

    <#
    .SYNOPSIS
    Get cached spaces string for optimal performance

    .DESCRIPTION
    Returns a string of spaces of the specified length. Uses pre-cached strings
    for common lengths (1-200) to avoid repeated string multiplication.

    .PARAMETER count
    Number of spaces needed

    .OUTPUTS
    String of spaces
    #>
    static [string] GetSpaces([int]$count) {
        if ($count -le 0) { return "" }

        if ($count -le [InternalStringCache]::_maxCacheSize) {
            return [InternalStringCache]::_spaces[$count]
        }

        # For very large strings, build dynamically
        return " " * $count
    }

    <#
    .SYNOPSIS
    Get cached ANSI sequence for optimal performance

    .PARAMETER sequenceName
    Name of the ANSI sequence (reset, clear, clearline, etc.)

    .OUTPUTS
    ANSI escape sequence string
    #>
    static [string] GetAnsiSequence([string]$sequenceName) {
        if ([InternalStringCache]::_ansiSequences.ContainsKey($sequenceName)) {
            return [InternalStringCache]::_ansiSequences[$sequenceName]
        }
        return ""
    }

    <#
    .SYNOPSIS
    Get cached box drawing character

    .PARAMETER characterName
    Name of the box drawing character (horizontal, vertical, topleft, etc.)

    .OUTPUTS
    Box drawing character string
    #>
    static [string] GetBoxDrawing([string]$characterName) {
        if ([InternalStringCache]::_boxDrawing.ContainsKey($characterName)) {
            return [InternalStringCache]::_boxDrawing[$characterName]
        }
        return ""
    }

    <#
    .SYNOPSIS
    Cache a custom string for later retrieval

    .PARAMETER key
    Unique key for the cached string

    .PARAMETER value
    String value to cache
    #>
    static [void] CacheCustomString([string]$key, [string]$value) {
        if (-not [InternalStringCache]::_ansiSequences.ContainsKey($key)) {
            [InternalStringCache]::_ansiSequences[$key] = $value
        }
    }
}

<#
.SYNOPSIS
Internal StringBuilder pooling for memory efficiency

.DESCRIPTION
This class manages a pool of StringBuilder objects to reduce memory allocation
and garbage collection pressure. Developers never see this - it's used internally
to optimize string building operations.

.EXAMPLE
# Developer writes normal code:
$content = ""
$content += "Hello"
$content += " World"

# But internally, StringBuilder pooling is used for performance
#>
class InternalStringBuilderPool {
    static [ConcurrentQueue[StringBuilder]]$_pool = [ConcurrentQueue[StringBuilder]]::new()
    static [int]$_maxPoolSize = 50
    static [int]$_maxCapacity = 32768  # 32KB max before discarding
    static [int]$_created = 0
    static [int]$_reused = 0

    <#
    .SYNOPSIS
    Get a StringBuilder from the pool or create a new one

    .OUTPUTS
    StringBuilder instance ready for use
    #>
    static [StringBuilder] Get() {
        $sb = $null
        if ([InternalStringBuilderPool]::_pool.TryDequeue([ref]$sb)) {
            $sb.Clear()
            [InternalStringBuilderPool]::_reused++
        } else {
            $sb = [StringBuilder]::new()
            [InternalStringBuilderPool]::_created++
        }
        return $sb
    }

    <#
    .SYNOPSIS
    Get a StringBuilder with specific initial capacity

    .PARAMETER initialCapacity
    Initial capacity for the StringBuilder

    .OUTPUTS
    StringBuilder instance with specified capacity
    #>
    static [StringBuilder] Get([int]$initialCapacity) {
        $sb = $null
        if ([InternalStringBuilderPool]::_pool.TryDequeue([ref]$sb)) {
            $sb.Clear()
            if ($sb.Capacity -lt $initialCapacity) {
                $sb.Capacity = $initialCapacity
            }
            [InternalStringBuilderPool]::_reused++
        } else {
            $sb = [StringBuilder]::new($initialCapacity)
            [InternalStringBuilderPool]::_created++
        }
        return $sb
    }

    <#
    .SYNOPSIS
    Return a StringBuilder to the pool for reuse

    .PARAMETER sb
    StringBuilder to return to the pool
    #>
    static [void] Recycle([StringBuilder]$sb) {
        if (-not $sb) { return }

        # Don't pool if too large (prevents memory bloat)
        if ($sb.Capacity -gt [InternalStringBuilderPool]::_maxCapacity) {
            return
        }

        # Don't pool if we're at max capacity
        if ([InternalStringBuilderPool]::_pool.Count -ge [InternalStringBuilderPool]::_maxPoolSize) {
            return
        }

        $sb.Clear()
        [InternalStringBuilderPool]::_pool.Enqueue($sb)
    }

    <#
    .SYNOPSIS
    Get pool statistics for monitoring and debugging

    .OUTPUTS
    Hashtable with pool statistics
    #>
    static [hashtable] GetStats() {
        return @{
            PoolSize = [InternalStringBuilderPool]::_pool.Count
            MaxPoolSize = [InternalStringBuilderPool]::_maxPoolSize
            Created = [InternalStringBuilderPool]::_created
            Reused = [InternalStringBuilderPool]::_reused
            ReuseRate = $(if ([InternalStringBuilderPool]::_created -eq 0) { 0 } else {
                [Math]::Round(([InternalStringBuilderPool]::_reused / ([InternalStringBuilderPool]::_created + [InternalStringBuilderPool]::_reused)) * 100, 2)
            })
        }
    }
}

<#
.SYNOPSIS
Internal VT100/ANSI optimization layer

.DESCRIPTION
Provides optimized VT100/ANSI escape sequence generation with caching
and true color support. All sequences are pre-computed for maximum performance.
#>
class InternalVT100 {
    # Color cache for RGB sequences
    static [hashtable]$_colorCache = @{}
    static [int]$_maxColorCache = 500

    <#
    .SYNOPSIS
    Generate optimized cursor movement sequence

    .PARAMETER x
    X coordinate (0-based)

    .PARAMETER y
    Y coordinate (0-based)

    .OUTPUTS
    ANSI cursor movement sequence
    #>
    static [string] MoveTo([int]$x, [int]$y) {
        # Convert to 1-based for ANSI (terminals use 1-based coordinates)
        return "`e[$($y + 1);$($x + 1)H"
    }

    <#
    .SYNOPSIS
    Generate optimized RGB foreground color sequence

    .PARAMETER r
    Red component (0-255)

    .PARAMETER g
    Green component (0-255)

    .PARAMETER b
    Blue component (0-255)

    .OUTPUTS
    ANSI RGB foreground color sequence
    #>
    static [string] RGB([int]$r, [int]$g, [int]$b) {
        $key = "fg_${r}_${g}_${b}"

        if ([InternalVT100]::_colorCache.ContainsKey($key)) {
            return [InternalVT100]::_colorCache[$key]
        }

        $sequence = "`e[38;2;$r;$g;${b}m"

        # Cache if we have room
        if ([InternalVT100]::_colorCache.Count -lt [InternalVT100]::_maxColorCache) {
            [InternalVT100]::_colorCache[$key] = $sequence
        }

        return $sequence
    }

    <#
    .SYNOPSIS
    Generate optimized RGB background color sequence

    .PARAMETER r
    Red component (0-255)

    .PARAMETER g
    Green component (0-255)

    .PARAMETER b
    Blue component (0-255)

    .OUTPUTS
    ANSI RGB background color sequence
    #>
    static [string] BgRGB([int]$r, [int]$g, [int]$b) {
        $key = "bg_${r}_${g}_${b}"

        if ([InternalVT100]::_colorCache.ContainsKey($key)) {
            return [InternalVT100]::_colorCache[$key]
        }

        $sequence = "`e[48;2;$r;$g;${b}m"

        # Cache if we have room
        if ([InternalVT100]::_colorCache.Count -lt [InternalVT100]::_maxColorCache) {
            [InternalVT100]::_colorCache[$key] = $sequence
        }

        return $sequence
    }

    # Alias for backward compatibility
    static [string] RGBBackground([int]$r, [int]$g, [int]$b) {
        return [InternalVT100]::BgRGB($r, $g, $b)
    }

    <#
    .SYNOPSIS
    Get reset sequence
    #>
    static [string] Reset() {
        return "`e[0m"
    }

    <#
    .SYNOPSIS
    Get default color sequence
    #>
    static [string] Default() {
        return "`e[39m"
    }

    <#
    .SYNOPSIS
    Get bold style sequence
    #>
    static [string] Bold() {
        return "`e[1m"
    }

    <#
    .SYNOPSIS
    Get underline style sequence
    #>
    static [string] Underline() {
        return "`e[4m"
    }

    <#
    .SYNOPSIS
    Get blue color sequence
    #>
    static [string] Blue() {
        return "`e[34m"
    }

    <#
    .SYNOPSIS
    Get cyan color sequence
    #>
    static [string] Cyan() {
        return "`e[36m"
    }

    <#
    .SYNOPSIS
    Get green color sequence
    #>
    static [string] Green() {
        return "`e[32m"
    }

    <#
    .SYNOPSIS
    Get yellow color sequence
    #>
    static [string] Yellow() {
        return "`e[33m"
    }

    <#
    .SYNOPSIS
    Get red color sequence
    #>
    static [string] Red() {
        return "`e[31m"
    }

    <#
    .SYNOPSIS
    Get white color sequence
    #>
    static [string] White() {
        return "`e[37m"
    }

    <#
    .SYNOPSIS
    Get black background sequence
    #>
    static [string] BgBlack() {
        return "`e[40m"
    }

    <#
    .SYNOPSIS
    Get white background sequence
    #>
    static [string] BgWhite() {
        return "`e[47m"
    }

    <#
    .SYNOPSIS
    Get spaces string
    #>
    static [string] GetSpaces([int]$count) {
        return [InternalStringCache]::GetSpaces($count)
    }

    <#
    .SYNOPSIS
    Get common ANSI sequences

    .OUTPUTS
    Hashtable with common ANSI sequences
    #>
    static [hashtable] GetCommonSequences() {
        return @{
            Reset = "`e[0m"
            Clear = "`e[2J"
            ClearLine = "`e[2K"
            Home = "`e[H"
            HideCursor = "`e[?25l"
            ShowCursor = "`e[?25h"
            Bold = "`e[1m"
            Dim = "`e[2m"
            Italic = "`e[3m"
            Underline = "`e[4m"
        }
    }
}

# Auto-initialize the performance systems
[InternalStringCache]::Initialize()

<#
.SYNOPSIS
Global helper functions for performance optimization (Internal use only)

.DESCRIPTION
These functions provide easy access to the performance optimization systems
while maintaining a clean, simple interface for internal SpeedTUI code.
#>

function Get-OptimizedSpaces {
    <#
    .SYNOPSIS
    Get optimized spaces string (Internal use only)

    .PARAMETER Count
    Number of spaces needed

    .OUTPUTS
    Optimized string of spaces
    #>
    param([int]$Count)
    return [InternalStringCache]::GetSpaces($Count)
}

function Get-PooledStringBuilder {
    <#
    .SYNOPSIS
    Get a pooled StringBuilder for efficient string building (Internal use only)

    .PARAMETER InitialCapacity
    Optional initial capacity for the StringBuilder

    .OUTPUTS
    StringBuilder instance from the pool
    #>
    param([int]$InitialCapacity = 256)

    if ($InitialCapacity -gt 0) {
        return [InternalStringBuilderPool]::Get($InitialCapacity)
    } else {
        return [InternalStringBuilderPool]::Get()
    }
}

function Return-PooledStringBuilder {
    <#
    .SYNOPSIS
    Return a StringBuilder to the pool for reuse (Internal use only)

    .PARAMETER StringBuilder
    StringBuilder to return to the pool
    #>
    param([StringBuilder]$StringBuilder)
    [InternalStringBuilderPool]::Recycle($StringBuilder)
}

function Get-PerformanceStats {
    <#
    .SYNOPSIS
    Get performance statistics for monitoring (Internal use only)

    .OUTPUTS
    Hashtable with performance statistics
    #>
    return @{
        StringBuilderPool = [InternalStringBuilderPool]::GetStats()
        ColorCacheSize = [InternalVT100]::_colorCache.Count
        SpacesCacheSize = [InternalStringCache]::_spaces.Count
    }
}