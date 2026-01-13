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
        [string]$themeName = $null
    )

    try {
        if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
            Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeHotReload] Starting hot reload for theme: '$themeName'"
        }

        # 1. If theme name provided, save it to config
        if (-not [string]::IsNullOrEmpty($themeName)) {
            Set-ActiveTheme -themeName $themeName
            if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
                Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeHotReload] Set-ActiveTheme completed"
            }
        }

        # 2. Reload PmcThemeManager (Single Source of Truth)
        # This reloads the theme file and invalidates PmcThemeEngine cache
        $themeManager = [PmcThemeManager]::GetInstance()
        $themeManager.Reload()
        
        if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
            Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeHotReload] PmcThemeManager.Reload completed"
        }

        # 5. Force full screen refresh if app is running
        if ($global:PmcApp) {
            # Request clear to invalidate render buffer
            $global:PmcApp.RenderEngine.RequestClear()

            # Mark current screen dirty to force redraw
            if ($global:PmcApp.CurrentScreen) {
                $screen = $global:PmcApp.CurrentScreen
                $screen.NeedsClear = $true
                
                # Force header and footer to re-theme themselves
                if ($screen.Header) {
                    $screen.Header._themeInitialized = $false
                }
                if ($screen.Footer) {
                    $screen.Footer._themeInitialized = $false
                }
                if ($screen.StatusBar) {
                    $screen.StatusBar._themeInitialized = $false
                }
            }

            # Request render on next frame
            $global:PmcApp.RequestRender()
        }

        return $true

    } catch {
        if ($null -ne (Get-Variable -Name PmcDebug -Scope Global -ErrorAction SilentlyContinue) -and $global:PmcDebug -and $global:PmcTuiLogFile) {
            Add-Content $global:PmcTuiLogFile "[$(Get-Date -F 'HH:mm:ss.fff')] [ThemeHotReload] ERROR: $_"
        }
        return $false
    }
}
