# ThemeHelper.ps1 - Hot reload support for theme changes
# Allows themes to be changed without restarting the TUI

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Hot reload the theme system after a theme change

.DESCRIPTION
Reloads the theme engine with new colors from the palette,
invalidates caches, and forces a full screen redraw to apply
the new theme immediately without restarting the TUI.

.PARAMETER hexColor
Optional hex color to reload. If not provided, uses current theme from config.

.EXAMPLE
Invoke-ThemeHotReload "#33cc66"

.EXAMPLE
Invoke-ThemeHotReload  # Reload current theme
#>
function Invoke-ThemeHotReload {
    param(
        [string]$hexColor = $null
    )

    try {
        # 1. If hex provided, save it to config first
        if (-not [string]::IsNullOrEmpty($hexColor)) {
            $cfg = Get-PmcConfig
            if (-not $cfg.Display) { $cfg.Display = @{} }
            if (-not $cfg.Display.Theme) { $cfg.Display.Theme = @{} }
            $cfg.Display.Theme.Hex = $hexColor
            Save-PmcConfig $cfg
        }

        # 2. Reinitialize PMC theme system to update state
        Initialize-PmcThemeSystem -Force

        # 3. Get fresh color palette from PMC
        $palette = Get-PmcColorPalette

        # 4. Convert RGB objects to hex strings for PmcThemeEngine
        $paletteHex = @{}
        foreach ($key in $palette.Keys) {
            $rgb = $palette[$key]
            $paletteHex[$key] = "#{0:X2}{1:X2}{2:X2}" -f $rgb.R, $rgb.G, $rgb.B
        }

        # 5. Reload PmcThemeManager (which configures the Engine)
        $themeManager = [PmcThemeManager]::GetInstance()
        $themeManager.Reload()

        # 6. Force full screen refresh if app is running
        if ($global:PmcApp) {
            # Request clear to invalidate render buffer
            $global:PmcApp.RenderEngine.RequestClear()

            # Mark current screen dirty to force redraw
            if ($global:PmcApp.CurrentScreen) {
                $global:PmcApp.CurrentScreen.NeedsClear = $true
            }

            # Request render on next frame
            $global:PmcApp.RequestRender()
        }

        return $true

    } catch {
        Write-Error "Theme hot reload failed: $_"
        return $false
    }
}