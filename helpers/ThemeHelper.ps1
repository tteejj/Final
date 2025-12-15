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
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ThemeHelper: Hot reload started (hex=$hexColor)"
        }

        # 1. Reinitialize PMC theme system to update state
        Initialize-PmcThemeSystem -Force

        # 2. Get fresh color palette from PMC
        $palette = Get-PmcColorPalette

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ThemeHelper: Palette loaded with $($palette.Count) colors"
        }

        # 3. Convert RGB objects to hex strings for PmcThemeEngine
        $paletteHex = @{}
        foreach ($key in $palette.Keys) {
            $rgb = $palette[$key]
            $paletteHex[$key] = "#{0:X2}{1:X2}{2:X2}" -f $rgb.R, $rgb.G, $rgb.B
        }

        # 4. Reload PmcThemeEngine with new palette
        $engine = [PmcThemeEngine]::GetInstance()
        $themeConfig = @{
            Palette = $paletteHex
        }
        $engine.LoadFromConfig($themeConfig)

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ThemeHelper: PmcThemeEngine reloaded"
        }

        # 5. Reload PmcThemeManager
        $themeManager = [PmcThemeManager]::GetInstance()
        $themeManager.Reload()

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ThemeHelper: PmcThemeManager reloaded"
        }

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

            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ThemeHelper: Screen refresh requested"
            }
        }

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ThemeHelper: Hot reload COMPLETE"
        }

        return $true

    } catch {
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ThemeHelper: ERROR during hot reload: $_"
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ThemeHelper: Stack: $($_.ScriptStackTrace)"
        }
        Write-Error "Theme hot reload failed: $_"
        return $false
    }
}