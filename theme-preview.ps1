#!/usr/bin/env pwsh
# TRON ARES Theme Preview Script
# Shows theme colors in terminal without running full TUI

$ESC = [char]27
$Reset = "${ESC}[0m"

# Helper function to print colored text
function ShowColor([string]$name, [string]$hex, [string]$type = "Solid", [string]$start = "", [string]$end = "") {
    # Parse hex
    $hex = $hex.TrimStart('#')
    $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)

    if ($type -eq "Gradient") {
        # Show gradient preview
        $startHex = $start.TrimStart('#')
        $sr = [Convert]::ToInt32($startHex.Substring(0, 2), 16)
        $sg = [Convert]::ToInt32($startHex.Substring(2, 2), 16)
        $sb = [Convert]::ToInt32($startHex.Substring(4, 2), 16)

        $endHex = $end.TrimStart('#')
        $er = [Convert]::ToInt32($endHex.Substring(0, 2), 16)
        $eg = [Convert]::ToInt32($endHex.Substring(2, 2), 16)
        $eb = [Convert]::ToInt32($endHex.Substring(4, 2), 16)

        # Show start and end colors
        Write-Host "$name " -NoNewline
        Write-Host "${ESC}[38;2;${sr};${sg};${sb}m$Start${ESC}[0m " -NoNewline
        Write-Host "→ " -NoNewline
        Write-Host "${ESC}[38;2;${er};${eg};${eb}m$End${ESC}[0m " -NoNewline
        Write-Host "  [$hex → $end]" -ForegroundColor DarkGray
    } else {
        Write-Host "$name " -NoNewline
        Write-Host "${ESC}[38;2;${r};${g};${b}m████ SAMPLE ██████${ESC}[0m" -NoNewline
        Write-Host "  [$hex]" -ForegroundColor DarkGray
    }
}

# Helper to show background colors
function ShowBgColor([string]$name, [string]$hex, [string]$type = "Solid", [string]$start = "", [string]$end = "") {
    $hex = $hex.TrimStart('#')
    $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)

    if ($type -eq "Gradient") {
        $startHex = $start.TrimStart('#')
        $sr = [Convert]::ToInt32($startHex.Substring(0, 2), 16)
        $sg = [Convert]::ToInt32($startHex.Substring(2, 2), 16)
        $sb = [Convert]::ToInt32($startHex.Substring(4, 2), 16)

        $endHex = $end.TrimStart('#')
        $er = [Convert]::ToInt32($endHex.Substring(0, 2), 16)
        $eg = [Convert]::ToInt32($endHex.Substring(2, 2), 16)
        $eb = [Convert]::ToInt32($endHex.Substring(4, 2), 16)

        Write-Host "$name " -NoNewline
        Write-Host "${ESC}[48;2;${sr};${sg};${sb}m  START  ${ESC}[48;2;${er};${eg};${eb}m  →  END  ${ESC}[0m" -NoNewline
        Write-Host "  [$hex → $end]" -ForegroundColor DarkGray
    } else {
        Write-Host "$name " -NoNewline
        Write-Host "${ESC}[48;2;${r};${g};${b}m    BACKGROUND SAMPLE    ${ESC}[0m" -NoNewline
        Write-Host "  [$hex]" -ForegroundColor DarkGray
    }
}

Clear-Host
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  TRON ARES THEME - COLOR PREVIEW (BRIGHT NEON RED)                       ║" -ForegroundColor Red
Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkRed
Write-Host ""

Write-Host "═══ BACKGROUND COLORS ═══" -ForegroundColor Yellow
Write-Host ""
ShowBgColor "Background.Field" "#0a0a12"
ShowBgColor "Background.FieldFocused" "#1a1a2e"
ShowBgColor "Background.Row" "#080810"
ShowBgColor "Background.RowSelected" "#220005" "Gradient" "#220005" "#330008"
ShowBgColor "Background.MenuBar" "#0d0d1a" "Gradient" "#0d0d1a" "#12121f"
ShowBgColor "Background.Widget" "#0d0d1a"
ShowBgColor "Background.Panel" "#0e0e18"
ShowBgColor "Background.Header" "#0d0d1a" "Gradient" "#0d0d1a" "#151525"
Write-Host ""

Write-Host "═══ FOREGROUND COLORS ═══" -ForegroundColor Yellow
Write-Host ""
ShowColor "Foreground.Field" "#ff0033"
ShowColor "Foreground.FieldFocused" "#ff0022" "Gradient" "#ff0022" "#ff0033"
ShowColor "Foreground.Row" "#ff0033"
ShowColor "Foreground.RowSelected" "#00e5ff" "Gradient" "#00e5ff" "#ffffff"
ShowColor "Foreground.Title" "#ff0015" "Gradient" "#ff0015" "#ff0022"
ShowColor "Foreground.Muted" "#660011"
ShowColor "Foreground.Warning" "#ffaa00"
ShowColor "Foreground.Error" "#ff3333"
ShowColor "Foreground.Success" "#00ff66"
Write-Host ""

Write-Host "═══ BORDER & ACCENT COLORS ═══" -ForegroundColor Yellow
Write-Host ""
ShowColor "Foreground.Primary" "#ff0022" "Gradient" "#ff0022" "#00e5ff"
ShowColor "Border.Widget" "#ff0022" "Gradient" "#ff0022" "#cc0018"
ShowColor "Foreground.Border" "#ff0022"
ShowColor "Foreground.Secondary" "#00ccdd"
ShowColor "Foreground.Accent" "#00e5ff" "Gradient" "#00e5ff" "#00ffff"
Write-Host ""

Write-Host "═══ MOCKUP VISUALIZATION ═══" -ForegroundColor Yellow
Write-Host ""

# Create mockup
$menuBarBg = "${ESC}[48;2;13;13;26m"
$menuBarFg = "${ESC}[38;2;255;0;51m"
$menuHighlightBg = "${ESC}[48;2;34;0;5m"
$menuHighlightFg = "${ESC}[38;2;0;229;255m"
$borderFg = "${ESC}[38;2;255;0;34m"
$rowBg = "${ESC}[48;2;8;8;16m"
$rowFg = "${ESC}[38;2;255;0;51m"
$selectedRowBg = "${ESC}[48;2;34;0;5m"
$selectedRowFg = "${ESC}[38;2;0;229;255m"
$titleFg = "${ESC}[38;2;255;0;34m"
$reset = "${ESC}[0m"

Write-Host "$menuBarBg$menuBarFg  [File]  [Edit]  [View]  [Help]$reset"
Write-Host ""
Write-Host "$titleFg╔══════════════════════════════════════════════════════════════╗$reset"
Write-Host "$titleFg║  PROJECT MANAGER                                                ║$reset"
Write-Host "$titleFg╠══════════════════════════════════════════════════════════════╣$reset"
Write-Host "$rowBg$rowFg║  Task: Implement authentication system                          ║$reset"
Write-Host "$selectedRowBg$selectedRowFg║  Task: Design database schema (SELECTED)                         ║$reset"
Write-Host "$rowBg$rowFg║  Task: Write unit tests                                         ║$reset"
Write-Host "$rowBg$rowFg║  Task: Setup CI/CD pipeline                                    ║$reset"
Write-Host "$titleFg╚══════════════════════════════════════════════════════════════╝$reset"
Write-Host ""

Write-Host "Key: " -NoNewline
Write-Host "█" -ForegroundColor DarkGray -NoNewline
Write-Host " = Normal row | " -NoNewline
Write-Host "$selectedRowBg$selectedRowFg█$reset" -NoNewline
Write-Host " = Selected row | " -NoNewline
Write-Host "$titleFg█$reset" -NoNewline
Write-Host " = Border/Title"
Write-Host ""

Write-Host "═══ THEME PALETTE SUMMARY ═══" -ForegroundColor Yellow
Write-Host ""
Write-Host "Primary Color:     ARES Neon Red  #ff0022"
Write-Host "Secondary Color:   TRON Cyan      #00e5ff"
Write-Host "Text Color:        Bright Red     #ff0033"
Write-Host "Background:        Deep Space     #0a0a12"
Write-Host ""
Write-Host "Total Background Variations: 6 distinct shades"
Write-Host "Total Foreground Variations: 9 distinct colors"
Write-Host "Gradients Used: 9 properties"
Write-Host ""

Write-Host "Theme activated in config.json. Run 'Start-PmcTUI.ps1' in a terminal to see it live."
