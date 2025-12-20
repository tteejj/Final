# Theme and Preferences management

function Initialize-PmcThemeSystem {
    # OPTIMIZATION: Initialization guard - skip if already initialized
    # (unless force flag is set)
    param([switch]$Force)

    $existingTheme = Get-PmcState -Section 'Display' -Key 'Theme' -ErrorAction SilentlyContinue
    if ($existingTheme -and -not $Force) {
        # Already initialized, skip redundant work
        Write-PmcDebug -Level 3 -Category 'Theme' -Message "Theme system already initialized (use -Force to re-initialize)"
        return
    }

    # Force VT/ANSI capabilities; no fallbacks
    $caps = @{ AnsiSupport=$true; TrueColorSupport=$true; IsTTY=$true; NoColor=$false; Platform='forced' }
    Set-PmcState -Section 'Display' -Key 'Capabilities' -Value $caps

    # Normalize theme from config
    $cfg = Get-PmcConfig
    $theme = @{ PaletteName='default'; Hex='#33aaff'; TrueColor=$true; HighContrast=$false; ColorBlindMode='none' }
    try {
        if ($cfg.Display -and $cfg.Display.Theme) {
            if ($cfg.Display.Theme.Hex) { $theme.Hex = ($cfg.Display.Theme.Hex.ToString()) }
            if ($cfg.Display.Theme.Properties) { $theme.Properties = $cfg.Display.Theme.Properties }
            if ($cfg.Display.Theme.Enabled -ne $null) { } # reserved for future toggles
        }
        if ($cfg.Display -and $cfg.Display.Icons -and $cfg.Display.Icons.Mode) {
            Set-PmcState -Section 'Display' -Key 'Icons' -Value @{ Mode = ($cfg.Display.Icons.Mode.ToString()) }
        }
    } catch { }
    Set-PmcState -Section 'Display' -Key 'Theme' -Value $theme

    # Compute style tokens from theme hex
    $palette = Get-PmcColorPalette
    $styles = @{
        Title    = @{ Fg=$theme.Hex }
        Header   = @{ Fg=$theme.Hex }
        Body     = @{ Fg=(Format-Hex-RGB $palette.Text) }
        Muted    = @{ Fg=(Format-Hex-RGB $palette.Muted) }
        Success  = @{ Fg=(Format-Hex-RGB $palette.Success) }
        Warning  = @{ Fg=(Format-Hex-RGB $palette.Warning) }
        Error    = @{ Fg=(Format-Hex-RGB $palette.Error) }
        Info     = @{ Fg=$theme.Hex }
        Prompt   = @{ Fg=(Format-Hex-RGB $palette.Muted) }
        Border   = @{ Fg=(Format-Hex-RGB $palette.Border) }
        Highlight= @{ Fg=(Format-Hex-RGB $palette.Bright) }
        Editing  = @{ Bg=$theme.Hex; Fg='White'; Bold=$true }
        Selected = @{ Bg=$theme.Hex; Fg='White' }
        Subheader= @{ Fg=(Format-Hex-RGB $palette.Muted) }
    }
    Set-PmcState -Section 'Display' -Key 'Styles' -Value $styles

    # CRITICAL FIX: Ensure PmcThemeManager is initialized to configure PmcThemeEngine
    # The engine has no properties until the manager calls Configure() on it.
    try {
        if (([System.Management.Automation.PSTypeName]'PmcThemeManager').Type) {
            [void][PmcThemeManager]::GetInstance()
            # NOTE: Do NOT call Reload() here - it causes issues during initialization
            # The manager will be properly initialized via Start-PmcTUI.ps1's Theme service registration
        }
    } catch {
        # PmcThemeManager may not be loaded yet (e.g., during module import)
        if ((Test-Path variable:global:PmcDebug) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
            Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [Theme] PmcThemeManager init failed: $_"
        }
    }
}

function Format-Hex-RGB {
    param($rgb)
    if (-not $rgb -or -not $rgb.R) { return '#FFFFFF' }
    return "#{0:X2}{1:X2}{2:X2}" -f $rgb.R,$rgb.G,$rgb.B
}

function Set-PmcTheme {
    param([PmcCommandContext]$Context)
    Write-PmcDebug -Level 1 -Category "Theme" -Message "Starting theme set" -Data @{ FreeText = $Context.FreeText }
    $cfg = Get-PmcConfig
    $color = ($Context.FreeText -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($color)) {
        Write-PmcStyled -Style 'Warning' -Text "Usage: theme <#RRGGBB> | <preset>"
        Write-PmcStyled -Style 'Muted' -Text "Presets: ocean, lime, purple, slate"
        return
    }
    $hex = $null
    switch -Regex ($color.ToLower()) {
        '^#?[0-9a-f]{6}$' { $hex = $(if ($color.StartsWith('#')) { $color } else { '#'+$color }); break }
        '^ocean$'   { $hex = '#33aaff'; break }
        '^lime$'    { $hex = '#33cc66'; break }
        '^purple$'  { $hex = '#9966ff'; break }
        '^slate$'   { $hex = '#8899aa'; break }
        default     { }
    }
    if (-not $hex) { Write-PmcStyled -Style 'Error' -Text "Invalid color. Use #RRGGBB or a preset."; return }
    try {
        if (-not $cfg.Display) { $cfg.Display = @{} }
        if (-not $cfg.Display.Theme) { $cfg.Display.Theme = @{} }
        $cfg.Display.Theme.Hex = $hex
        $cfg.Display.Theme.Enabled = $true
        Save-PmcConfig $cfg
        Write-PmcStyled -Style 'Success' -Text ("Theme color set to {0}" -f $hex)
    } catch {
        Write-PmcStyled -Style 'Error' -Text "Failed to save theme"
    }
}

function Reset-PmcTheme {
    param($Context = $null)
    try {
        $cfg = Get-PmcConfig
        if (-not $cfg) { $cfg = @{} }
        if (-not (Pmc-HasProp $cfg 'Display')) { $cfg | Add-Member -NotePropertyName 'Display' -NotePropertyValue @{} -Force }
        if (-not (Pmc-HasProp $cfg.Display 'Theme')) { $cfg.Display | Add-Member -NotePropertyName 'Theme' -NotePropertyValue @{} -Force }
        $cfg.Display.Theme.Hex = '#33aaff'
        $cfg.Display.Theme.Enabled = $true
        Save-PmcConfig $cfg
        Write-PmcStyled -Style 'Success' -Text "Theme reset to default (#33aaff)"
    } catch {
        Write-PmcStyled -Style 'Warning' -Text "Theme reset completed (config may be read-only)"
    }
}

function Set-PmcIconMode {
    param([PmcCommandContext]$Context)
    $mode = ($Context.FreeText -join ' ').Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($mode)) {
        Write-PmcStyled -Style 'Warning' -Text "Usage: config icons ascii|emoji"
        return
    }
    if ($mode -notin @('ascii','emoji')) { Write-PmcStyled -Style 'Error' -Text "Invalid mode. Use ascii or emoji."; return }
    $cfg = Get-PmcConfig
    if (-not $cfg.Display) { $cfg.Display = @{} }
    if (-not $cfg.Display.Icons) { $cfg.Display.Icons = @{} }
    $cfg.Display.Icons.Mode = $mode
    Save-PmcConfig $cfg
    Write-PmcStyled -Style 'Success' -Text ("Icon mode set to {0}" -f $mode)
}

function Edit-PmcTheme {
    param([PmcCommandContext]$Context)

    # Read current theme
    $cfg = Get-PmcConfig
    $hex = try { if ($cfg.Display -and $cfg.Display.Theme -and $cfg.Display.Theme.Hex) { [string]$cfg.Display.Theme.Hex } else { '#33aaff' } } catch { '#33aaff' }
    if (-not $hex.StartsWith('#')) { $hex = '#'+$hex }
    $rgb = ConvertFrom-PmcHex $hex
    $r = [int]$rgb.R; $g=[int]$rgb.G; $b=[int]$rgb.B
    $chan = 0  # 0=R,1=G,2=B

    $done = $false
    while (-not $done) {
        # Render UI
        Write-Host ([PraxisVT]::ClearScreen())
        Show-PmcHeader -Title 'THEME ADJUSTER' -Icon '🎨'
        Write-Host ''

        # Preview box
        $preview = [PmcVT]::BgRGB($r,$g,$b) + '          ' + [PmcVT]::Reset() + ("  #{0:X2}{1:X2}{2:X2}" -f $r,$g,$b)
        Write-Host ("  Preview: " + $preview)
        Write-Host ''

        # Sliders
        Show-Slider -Label 'R' -Value $r -Selected:($chan -eq 0)
        Show-Slider -Label 'G' -Value $g -Selected:($chan -eq 1)
        Show-Slider -Label 'B' -Value $b -Selected:($chan -eq 2)

        Write-Host ''
        Write-Host '  Use ↑/↓ to select channel, ←/→ to adjust, PgUp/PgDn for ±10, Enter to save, Esc to cancel' -ForegroundColor DarkGray

        # Read key
        $k = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($k.VirtualKeyCode) {
            38 { $chan = [Math]::Max(0, $chan - 1) }       # Up
            40 { $chan = [Math]::Min(2, $chan + 1) }       # Down
            37 { if ($chan -eq 0) { $r = [Math]::Max(0,$r-1) } elseif ($chan -eq 1) { $g=[Math]::Max(0,$g-1) } else { $b=[Math]::Max(0,$b-1) } }  # Left
            39 { if ($chan -eq 0) { $r = [Math]::Min(255,$r+1) } elseif ($chan -eq 1) { $g=[Math]::Min(255,$g+1) } else { $b=[Math]::Min(255,$b+1) } } # Right
            33 { if ($chan -eq 0) { $r = [Math]::Min(255,$r+10) } elseif ($chan -eq 1) { $g=[Math]::Min(255,$g+10) } else { $b=[Math]::Min(255,$b+10) } } # PgUp
            34 { if ($chan -eq 0) { $r = [Math]::Max(0,$r-10) } elseif ($chan -eq 1) { $g=[Math]::Max(0,$g-10) } else { $b=[Math]::Max(0,$b-10) } } # PgDn
            13 {
                # Enter: save and exit
                $newHex = ("#{0:X2}{1:X2}{2:X2}" -f $r,$g,$b)
                if (-not $cfg.Display) { $cfg.Display=@{} }
                if (-not $cfg.Display.Theme) { $cfg.Display.Theme=@{} }
                $cfg.Display.Theme.Hex = $newHex
                Save-PmcConfig $cfg
                Write-Host "Saved theme: $newHex" -ForegroundColor Green
                Start-Sleep -Milliseconds 400
                $done = $true
            }
            27 { $done = $true } # Esc: cancel
            default {}
        }
    }
}

function Show-Slider {
    param(
        [string]$Label,
        [int]$Value,
        [switch]$Selected
    )
    $width = 32
    $filled = [int]([Math]::Round(($Value / 255.0) * $width))
    $bar = ('#' * $filled) + ('-' * ($width - $filled))
    $sel = $(if ($Selected) { '▶' } else { ' ' })
    $fg = $(if ($Selected) { 'White' } else { 'Gray' })
    Write-Host ("  {0} {1}: [{2}] {3,3}" -f $sel, $Label, $bar, $Value) -ForegroundColor $fg
}

function Show-PmcPreferences {
    param([PmcCommandContext]$Context)
    $cfg = Get-PmcConfig
    Write-Host "\nPREFERENCES" -ForegroundColor Cyan
    Write-PmcStyled -Style 'Border' -Text "───────────"
    Write-Host ("1) Theme color: {0}" -f $(if ($null -ne $cfg.Display.Theme.Hex) { $cfg.Display.Theme.Hex } else { '#33aaff' }))
    Write-Host ("2) Icons: {0}" -f $(if ($null -ne $cfg.Display.Icons.Mode) { $cfg.Display.Icons.Mode } else { 'emoji' }))
    Write-Host ("3) CSV ledger: {0}" -f $(if ($null -ne $cfg.Behavior.EnableCsvLedger) { $cfg.Behavior.EnableCsvLedger } else { $true }))
    Write-Host "q) Quit"
    while ($true) {
        $sel = Read-Host "Select option (1/2/3/q)"
        switch ($sel) {
            '1' {
                # Launch interactive adjuster with preview and sliders
                $ctx = [PmcCommandContext]::new('theme','adjust')
                Edit-PmcTheme -Context $ctx
            }
            '2' {
                $m = Read-Host "Enter icons mode (ascii/emoji)"
                $ctx = [PmcCommandContext]::new('config','icons'); $ctx.FreeText = @($m)
                Set-PmcIconMode -Context $ctx
            }
            '3' {
                $v = Read-Host "Enable CSV ledger? (y/n)"
                $flag = ($v -match '^(?i)y')
                if (-not $cfg.Behavior) { $cfg.Behavior=@{} }
                $cfg.Behavior.EnableCsvLedger = $flag
                Save-PmcConfig $cfg
                Write-Host ("CSV ledger set to {0}" -f $flag) -ForegroundColor Green
            }
            'q' { break }
            default { Write-Host 'Invalid choice' -ForegroundColor Yellow }
        }
    }
}

# Additional theme utilities and commands
function Get-PmcThemeList { [PmcCommandContext]$Context | Out-Null; @('default','ocean','#33aaff','lime','#33cc66','purple','#9966ff','slate','#8899aa','high-contrast') | ForEach-Object { Write-Host $_ } }

function Apply-PmcTheme {
    param([PmcCommandContext]$Context)
    $arg = ($Context.FreeText -join ' ').Trim()
    if (-not $arg) { Write-Host "Usage: theme apply <name|#RRGGBB>" -ForegroundColor Yellow; return }
    $hex = $null
    switch -Regex ($arg.ToLower()) {
        '^#?[0-9a-f]{6}$' { $hex = $(if ($arg.StartsWith('#')) { $arg } else { '#'+$arg }); break }
        '^(default|ocean)$' { $hex = '#33aaff'; break }
        '^lime$'    { $hex = '#33cc66'; break }
        '^purple$'  { $hex = '#9966ff'; break }
        '^slate$'   { $hex = '#8899aa'; break }
        '^high-contrast$' { $hex = '#00ffff'; break }
        default {}
    }
    if (-not $hex) { Write-Host "Unknown theme; see 'theme list'" -ForegroundColor Yellow; return }
    $cfg = Get-PmcConfig
    if (-not $cfg.Display) { $cfg.Display=@{} }
    if (-not $cfg.Display.Theme) { $cfg.Display.Theme=@{} }
    $cfg.Display.Theme.Hex = $hex
    Save-PmcConfig $cfg
    Initialize-PmcThemeSystem
    Write-Host ("Theme applied: {0}" -f $hex) -ForegroundColor Green
}

function Show-PmcThemeInfo { param([PmcCommandContext]$Context)
    $disp = Get-PmcState -Section 'Display'
    $theme = $disp.Theme
    Write-Host "Theme: $($theme.PaletteName) $($theme.Hex)  TrueColor=$($theme.TrueColor) HighContrast=$($theme.HighContrast)" -ForegroundColor Cyan
}

function Reload-PmcConfig { param([PmcCommandContext]$Context)
    # Re-apply runtime from config (providers already return latest on read)
    $cfg = Get-PmcConfig
    $lvl = try { [int]$cfg.Debug.Level } catch { 0 }
    Initialize-PmcDebugSystem -Level $lvl
    Initialize-PmcSecuritySystem
    Initialize-PmcThemeSystem
    Ensure-PmcUniversalDisplay
    Write-Host "Configuration reloaded and systems re-initialized" -ForegroundColor Green
}

Export-ModuleMember -Function Initialize-PmcThemeSystem, Set-PmcTheme, Reset-PmcTheme, Set-PmcIconMode, Edit-PmcTheme, Show-Slider, Show-PmcPreferences, Get-PmcThemeList, Apply-PmcTheme, Show-PmcThemeInfo
