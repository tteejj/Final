# Pmc UI primitives with centralized style tokens and sanitization

Set-StrictMode -Version Latest

class PmcVT {
    static [string] MoveTo([int]$x, [int]$y) { return "`e[$($y + 1);$($x + 1)H" }
    static [string] Clear() { return "`e[2J`e[H" }
    static [string] ClearLine() { return "`e[2K" }
    static [string] Hide() { return "`e[?25l" }
    static [string] Show() { return "`e[?25h" }
    static [string] FgRGB([int]$r, [int]$g, [int]$b) { return "`e[38;2;$r;$g;${b}m" }
    static [string] BgRGB([int]$r, [int]$g, [int]$b) { return "`e[48;2;$r;$g;${b}m" }
    static [string] Reset() { return "`e[0m" }
    static [string] Bold() { return "`e[1m" }
}

function Sanitize-PmcOutput {
    param([string]$Text)
    if (-not $Text) { return '' }
    # Strip ANSI escape sequences and control chars
    $t = $Text -replace "`e\[[0-9;]*[A-Za-z]", ''
    $t = ($t.ToCharArray() | Where-Object { [int]$_ -ge 32 -or [int]$_ -eq 10 -or [int]$_ -eq 13 } ) -join ''
    return $t
}

function Get-PmcStyle {
    param([string]$Token)
    $styles = Get-PmcState -Section 'Display' -Key 'Styles'
    if (-not $styles) { return @{ Fg='White' } }
    if ($styles.ContainsKey($Token)) { return $styles[$Token] }
    return @{ Fg='White' }
}

function Write-PmcStyled {
    param(
        [Parameter(Mandatory)] [string]$Style,
        [Parameter(Mandatory)] [string]$Text,
        [switch]$NoNewline
    )
    $sty = Get-PmcStyle $Style
    $fg = $sty.Fg
    $safe = Sanitize-PmcOutput $Text

    if ($fg) {
        # Check if Fg is a hex color (#RRGGBB)
        if ($fg -match '^#([0-9A-Fa-f]{6})$') {
            $rgb = ConvertFrom-PmcHex $fg
            $colorSeq = "`e[38;2;$($rgb.R);$($rgb.G);$($rgb.B)m"
            $reset = "`e[0m"
            if ($NoNewline) { Write-Host -NoNewline "$colorSeq$safe$reset" } else { Write-Host "$colorSeq$safe$reset" }
        } else {
            # Standard PowerShell color name
            if ($NoNewline) { Write-Host -NoNewline $safe -ForegroundColor $fg } else { Write-Host $safe -ForegroundColor $fg }
        }
    } else {
        if ($NoNewline) { Write-Host -NoNewline $safe } else { Write-Host $safe }
    }
}

function ConvertFrom-PmcHex {
    param([string]$Hex)
    $h = $(if ($Hex) { $Hex.Trim() } else { '#33aaff' })
    if ($h.StartsWith('#')) { $h = $h.Substring(1) }
    if ($h.Length -eq 3) { $h = ($h[0]+$h[0]+$h[1]+$h[1]+$h[2]+$h[2]) }
    if ($h.Length -ne 6) { $h = '33aaff' }
    return @{
        R = [Convert]::ToInt32($h.Substring(0,2),16)
        G = [Convert]::ToInt32($h.Substring(2,2),16)
        B = [Convert]::ToInt32($h.Substring(4,2),16)
    }
}

function Get-PmcColorPalette {
    $cfg = Get-PmcConfig
    $hex = '#33aaff'
    try { if ($cfg.Display -and $cfg.Display.Theme -and $cfg.Display.Theme.Hex) { $hex = [string]$cfg.Display.Theme.Hex } } catch {
        # Theme configuration access failed - use default hex color
    }
    $rgb = ConvertFrom-PmcHex $hex
    # Derive all colors from the theme hex
    $dim = @{
        R = [int]([Math]::Max(0, $rgb.R * 0.7)); G = [int]([Math]::Max(0, $rgb.G * 0.7)); B = [int]([Math]::Max(0, $rgb.B * 0.7))
    }
    $bright = @{
        R = [int]([Math]::Min(255, $rgb.R * 1.3)); G = [int]([Math]::Min(255, $rgb.G * 1.3)); B = [int]([Math]::Min(255, $rgb.B * 1.3))
    }
    $text = @{
        R = [int]([Math]::Min(255, $rgb.R * 0.4 + 180)); G = [int]([Math]::Min(255, $rgb.G * 0.4 + 180)); B = [int]([Math]::Min(255, $rgb.B * 0.4 + 180))
    }
    $muted = @{
        R = [int]($rgb.R * 0.5 + 75); G = [int]($rgb.G * 0.5 + 75); B = [int]($rgb.B * 0.5 + 75)
    }
    # Warning: shift toward yellow-ish in the theme's color space
    $warning = @{
        R = [int]([Math]::Min(255, $rgb.R * 0.8 + 100)); G = [int]([Math]::Min(255, $rgb.G * 0.6 + 120)); B = [int]($rgb.B * 0.3)
    }
    # Error: shift toward red-ish
    $error = @{
        R = [int]([Math]::Min(255, $rgb.R * 0.3 + 180)); G = [int]($rgb.G * 0.3); B = [int]($rgb.B * 0.3)
    }
    # Success: use the theme color as-is or slightly brighter
    $success = $bright

    # Provide all tokens used by interactive UIs (wizard/editor)
    return @{
        Primary  = $rgb
        Border   = $dim
        Text     = $text
        Muted    = $muted
        Error    = $error
        Warning  = $warning
        Success  = $success
        Bright   = $bright
        # Additional expected tokens
        Header   = $rgb
        Label    = $muted
        Highlight= $rgb
        Footer   = $dim
        Cursor   = $rgb
        Status   = $muted
    }
}

function Get-PmcColorSequence {
    param($rgb)
    try {
        if ($rgb -and $rgb.PSObject -and $rgb.PSObject.Properties['R'] -and $rgb.PSObject.Properties['G'] -and $rgb.PSObject.Properties['B']) {
            $r = [int]$rgb.R
            $g = [int]$rgb.G
            $b = [int]$rgb.B
            return "`e[38;2;${r};${g};${b}m"
        }
    } catch { }
    return ''
}

# Cell-level theming hook for grid renderer (Stage 1.3)
function Get-PmcCellStyle {
    param([object]$RowData, [string]$Column, [object]$Value)

    if (-not $RowData) { return Get-PmcStyle 'Body' }

    # Priority-based coloring (1=highest)
    if ($Column -eq 'priority' -and $RowData.PSObject.Properties['priority'] -and $RowData.priority) {
        $p = [string]$RowData.priority
        switch ($p) {
            '1' { return @{ Fg = 'Red';    Bold = $true } }
            '2' { return @{ Fg = 'Yellow'; Bold = $true } }
            '3' { return @{ Fg = 'Green' } }
        }
    }

    # Due date warnings (expects yyyy-MM-dd)
    if ($Column -eq 'due' -and $RowData.PSObject.Properties['due'] -and $RowData.due) {
        $dstr = [string]$RowData.due
        try {
            $dt = [DateTime]::ParseExact($dstr, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            $ok = $true
        } catch {
            $ok = $false
        }
        if ($ok) {
            $today = (Get-Date).Date
            if ($dt.Date -lt $today) { return @{ Fg = 'Red'; Bold = $true } }
            if ($dt.Date -le $today.AddDays(1)) { return @{ Fg = 'Yellow'; Bold = $true } }
        }
    }

    return Get-PmcStyle 'Body'
}

function Show-PmcHeader {
    param([string]$Title,[string]$Icon='')
    $t = $(if ($Icon) { " $Icon $Title" } else { " $Title" })
    Write-PmcStyled -Style 'Title' -Text $t
    $width = [Math]::Max(8, $t.Length)
    Write-PmcStyled -Style 'Border' -Text ('-' * $width)
}

function Show-PmcTip { param([string]$Text) Write-PmcStyled -Style 'Muted' -Text ('  ' + $Text) }

function Get-PmcIcon {
    param([string]$Name)
    $mode = 'emoji'
    try { $cfg = Get-PmcConfig; if ($cfg.Display -and $cfg.Display.Icons -and $cfg.Display.Icons.Mode) { $mode = [string]$cfg.Display.Icons.Mode } } catch {
        # Icon configuration access failed - use default mode
    }
    switch ($Name) {
        'notice' { if ($mode -eq 'ascii') { return '*' } else { return '•' } }
        'warn'   { if ($mode -eq 'ascii') { return '!' } else { return '[WARN]' } }
        'error'  { if ($mode -eq 'ascii') { return 'X' } else { return '✖' } }
        'ok'     { if ($mode -eq 'ascii') { return '+' } else { return '[OK]' } }
        default  { return '' }
    }
}

function Show-PmcNotice { param([string]$Text) $i=(Get-PmcIcon 'notice'); Write-PmcStyled -Style 'Body' -Text ($i + ' ' + $Text) }
function Show-PmcWarning { param([string]$Text) $i=(Get-PmcIcon 'warn'); Write-PmcStyled -Style 'Warning' -Text ($i + ' ' + $Text) }
function Show-PmcError { param([string]$Text) $i=(Get-PmcIcon 'error'); Write-PmcStyled -Style 'Error' -Text ($i + ' ' + $Text) }
function Show-PmcSuccess { param([string]$Text) $i=(Get-PmcIcon 'ok'); Write-PmcStyled -Style 'Success' -Text ($i + ' ' + $Text) }
function Show-PmcSeparator { param([int]$Width=40) Write-PmcStyled -Style 'Border' -Text ('─' * [Math]::Max(8,$Width)) }

function Show-PmcTable {
    param(
        [array]$Columns,
        [array]$Rows,
        [string]$Title=''
    )
    throw "Show-PmcTable is DEPRECATED and should not be used! All views must use Show-PmcCustomGrid. Function called with Title: '$Title'"
}

Export-ModuleMember -Function Sanitize-PmcOutput, Get-PmcStyle, Write-PmcStyled, ConvertFrom-PmcHex, Get-PmcColorPalette, Get-PmcColorSequence, Get-PmcCellStyle, Show-PmcHeader, Show-PmcTip, Get-PmcIcon