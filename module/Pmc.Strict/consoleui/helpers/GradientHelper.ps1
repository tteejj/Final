# GradientHelper.ps1 - Per-character horizontal gradient text rendering
# Renders text with ANSI 24-bit true color gradients

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Renders a string with a horizontal gradient from one color to another

.DESCRIPTION
Each character gets its own ANSI 24-bit color code, interpolated from
the start color to the end color across the width of the text.

.PARAMETER Text
The text to render with gradient

.PARAMETER StartHex
Starting color in hex format (e.g., "#ff00ff")

.PARAMETER EndHex
Ending color in hex format (e.g., "#00ffff")

.OUTPUTS
String with embedded ANSI escape codes for gradient coloring

.EXAMPLE
$gradient = Get-GradientText "SYNTHWAVE" "#ff00ff" "#00ffff"
Write-Host $gradient
#>
function Get-GradientText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$StartHex,

        [Parameter(Mandatory = $true)]
        [string]$EndHex
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    # Parse start color
    $startHex = $StartHex.TrimStart('#')
    $startR = [Convert]::ToInt32($startHex.Substring(0, 2), 16)
    $startG = [Convert]::ToInt32($startHex.Substring(2, 2), 16)
    $startB = [Convert]::ToInt32($startHex.Substring(4, 2), 16)

    # Parse end color
    $endHex = $EndHex.TrimStart('#')
    $endR = [Convert]::ToInt32($endHex.Substring(0, 2), 16)
    $endG = [Convert]::ToInt32($endHex.Substring(2, 2), 16)
    $endB = [Convert]::ToInt32($endHex.Substring(4, 2), 16)

    $len = $Text.Length
    if ($len -eq 1) {
        return "`e[38;2;${startR};${startG};${startB}m${Text}`e[0m"
    }

    $sb = [System.Text.StringBuilder]::new($len * 20)

    for ($i = 0; $i -lt $len; $i++) {
        $t = $i / ($len - 1)  # 0 to 1

        # Linear interpolation
        $r = [int]($startR + ($endR - $startR) * $t)
        $g = [int]($startG + ($endG - $startG) * $t)
        $b = [int]($startB + ($endB - $startB) * $t)

        # Clamp values
        $r = [Math]::Max(0, [Math]::Min(255, $r))
        $g = [Math]::Max(0, [Math]::Min(255, $g))
        $b = [Math]::Max(0, [Math]::Min(255, $b))

        $char = $Text[$i]
        [void]$sb.Append("`e[38;2;${r};${g};${b}m${char}")
    }

    [void]$sb.Append("`e[0m")
    return $sb.ToString()
}

<#
.SYNOPSIS
Renders a line of gradient text directly to the render engine

.DESCRIPTION
Writes each character individually with gradient coloring to the specified position

.PARAMETER Engine
The render engine with WriteAt method

.PARAMETER X
X coordinate (column)

.PARAMETER Y
Y coordinate (row)

.PARAMETER Text
Text to render

.PARAMETER StartHex
Starting gradient color

.PARAMETER EndHex
Ending gradient color

.PARAMETER Bg
Background color (optional, null for transparent)
#>
function Write-GradientAt {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Engine,

        [Parameter(Mandatory = $true)]
        [int]$X,

        [Parameter(Mandatory = $true)]
        [int]$Y,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$StartHex,

        [Parameter(Mandatory = $true)]
        [string]$EndHex,

        [object]$Bg = $null
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return
    }

    # Parse start color
    $startHex = $StartHex.TrimStart('#')
    $startR = [Convert]::ToInt32($startHex.Substring(0, 2), 16)
    $startG = [Convert]::ToInt32($startHex.Substring(2, 2), 16)
    $startB = [Convert]::ToInt32($startHex.Substring(4, 2), 16)

    # Parse end color
    $endHex = $EndHex.TrimStart('#')
    $endR = [Convert]::ToInt32($endHex.Substring(0, 2), 16)
    $endG = [Convert]::ToInt32($endHex.Substring(2, 2), 16)
    $endB = [Convert]::ToInt32($endHex.Substring(4, 2), 16)

    $len = $Text.Length

    for ($i = 0; $i -lt $len; $i++) {
        if ($len -eq 1) {
            $t = 0
        } else {
            $t = $i / ($len - 1)
        }

        # Linear interpolation
        $r = [int]($startR + ($endR - $startR) * $t)
        $g = [int]($startG + ($endG - $startG) * $t)
        $b = [int]($startB + ($endB - $startB) * $t)

        # Clamp
        $r = [Math]::Max(0, [Math]::Min(255, $r))
        $g = [Math]::Max(0, [Math]::Min(255, $g))
        $b = [Math]::Max(0, [Math]::Min(255, $b))

        # Convert to int for WriteAt
        $fg = ($r -shl 16) -bor ($g -shl 8) -bor $b

        $char = $Text[$i]
        $Engine.WriteAt($X + $i, $Y, [string]$char, $fg, $Bg)
    }
}

<#
.SYNOPSIS
Prebuilt synthwave gradient: Magenta to Cyan

.PARAMETER Text
Text to render

.OUTPUTS
String with ANSI gradient coloring
#>
function Get-SynthwaveGradient {
    param([string]$Text)
    return Get-GradientText -Text $Text -StartHex "#ff00ff" -EndHex "#00ffff"
}

<#
.SYNOPSIS
Writes synthwave gradient text to render engine

.PARAMETER Engine
Render engine

.PARAMETER X
X position

.PARAMETER Y
Y position

.PARAMETER Text
Text to render

.PARAMETER Bg
Background color (optional)
#>
function Write-SynthwaveGradientAt {
    param(
        [object]$Engine,
        [int]$X,
        [int]$Y,
        [string]$Text,
        [object]$Bg = $null
    )
    Write-GradientAt -Engine $Engine -X $X -Y $Y -Text $Text -StartHex "#ff00ff" -EndHex "#00ffff" -Bg $Bg
}

# Export functions
Export-ModuleMember -Function Get-GradientText, Write-GradientAt, Get-SynthwaveGradient, Write-SynthwaveGradientAt
