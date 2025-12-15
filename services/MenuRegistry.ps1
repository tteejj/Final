# MenuRegistry.ps1 - Dynamic menu registration system
#
# Allows screens to register their own menu items instead of hardcoding
# menu structure in TaskListScreen.
#
# Usage in screen classes:
#   static [void] RegisterMenuItems([MenuRegistry]$registry) {
#       $registry.AddMenuItem('Tasks', 'Today View', 'Y', {
#           . "$PSScriptRoot/TodayViewScreen.ps1"
#           $global:PmcApp.PushScreen([TodayViewScreen]::new())
#       })
#   }

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Dynamic menu registration system for PMC screens

.DESCRIPTION
MenuRegistry allows screens to register their own menu items dynamically.
This decouples menu structure from TaskListScreen and allows screens to
control their own menu presence.

Menu structure:
- Tasks: Task views and actions
- Projects: Project management screens
- Time: Time tracking screens
- Tools: Utilities and helpers
- Options: Settings and configuration
- Help: Help and about screens

.EXAMPLE
$registry = [MenuRegistry]::new()
$registry.AddMenuItem('Tasks', 'Today', 'Y', { Show-TodayView })
$menuItems = $registry.GetMenuItems('Tasks')
#>
class MenuRegistry {
    # Singleton instance
    static [MenuRegistry]$_instance = $null

    # Menu structure: @{ 'Tasks' = @( @{ Label='Today'; Hotkey='Y'; Action={...} }, ... ) }
    [hashtable]$_menuItems = @{
        'Tasks' = [List[hashtable]]::new()
        'Projects' = [List[hashtable]]::new()
        'Time' = [List[hashtable]]::new()
        'Tools' = [List[hashtable]]::new()
        'Options' = [List[hashtable]]::new()
        'Help' = [List[hashtable]]::new()
    }

    # === Singleton Pattern ===

    <#
    .SYNOPSIS
    Get the singleton instance of MenuRegistry

    .OUTPUTS
    MenuRegistry singleton instance
    #>
    static [MenuRegistry] GetInstance() {
        if ($null -eq [MenuRegistry]::_instance) {
            [MenuRegistry]::_instance = [MenuRegistry]::new()
        }
        return [MenuRegistry]::_instance
    }

    # Private constructor for singleton
    hidden MenuRegistry() {
        # Initialize menu structure
    }

    # === Registration ===

    <#
    .SYNOPSIS
    Register a menu item

    .PARAMETER menuName
    Menu to add item to ('Tasks', 'Projects', 'Time', 'Tools', 'Options', 'Help')

    .PARAMETER label
    Display label for menu item

    .PARAMETER hotkey
    Keyboard shortcut (single character or [char]0 for separator)

    .PARAMETER action
    Scriptblock to execute when item is selected

    .PARAMETER order
    Optional sort order (lower numbers appear first, default 100)
    #>
    [void] AddMenuItem([string]$menuName, [string]$label, [char]$hotkey, [scriptblock]$action) {
        $this.AddMenuItem($menuName, $label, $hotkey, $action, 100)
    }

    [void] AddMenuItem([string]$menuName, [string]$label, [char]$hotkey, [scriptblock]$action, [int]$order) {
        if (-not $this._menuItems.ContainsKey($menuName)) {
            throw "Invalid menu name: $menuName. Valid: Tasks, Projects, Time, Tools, Options, Help"
        }

        $item = @{
            Label = $label
            Hotkey = $hotkey
            Action = $action
            Order = $order
        }

        $this._menuItems[$menuName].Add($item)
    }

    <#
    .SYNOPSIS
    Add a menu separator

    .PARAMETER menuName
    Menu to add separator to
    #>
    [void] AddSeparator([string]$menuName) {
        $this.AddMenuItem($menuName, "", [char]0, $null, 100)
    }

    [void] AddSeparator([string]$menuName, [int]$order) {
        $this.AddMenuItem($menuName, "", [char]0, $null, $order)
    }

    # === Retrieval ===

    <#
    .SYNOPSIS
    Get all menu items for a specific menu, sorted by order

    .PARAMETER menuName
    Menu name ('Tasks', 'Projects', etc.)

    .OUTPUTS
    Array of menu item hashtables sorted by Order
    #>
    [array] GetMenuItems([string]$menuName) {
        if (-not $this._menuItems.ContainsKey($menuName)) {
            return @()
        }

        # Sort by Order, then by Label
        return $this._menuItems[$menuName] | Sort-Object -Property Order, Label
    }

    <#
    .SYNOPSIS
    Get all registered menus with items

    .OUTPUTS
    Hashtable of menu names to sorted item arrays
    #>
    [hashtable] GetAllMenus() {
        $result = @{}
        foreach ($menuName in $this._menuItems.Keys) {
            $items = $this.GetMenuItems($menuName)
            if ($items.Count -gt 0) {
                $result[$menuName] = $items
            }
        }
        return $result
    }

    <#
    .SYNOPSIS
    Clear all registered menu items (for testing/reset)
    #>
    [void] Clear() {
        foreach ($menuName in $this._menuItems.Keys) {
            $this._menuItems[$menuName].Clear()
        }
    }

    # === Manifest-Based Discovery ===

    <#
    .SYNOPSIS
    Load menu items from manifest file

    .PARAMETER manifestPath
    Path to MenuItems.psd1 manifest file

    .PARAMETER container
    ServiceContainer instance for resolving screen dependencies

    .DESCRIPTION
    Loads menu item definitions from manifest and registers them.
    Uses the DI container to resolve screens when menu items are clicked.
    This avoids parsing all screen files at startup, fixing type resolution issues.
    #>
    [void] LoadFromManifest([string]$manifestPath, [object]$container) {
        if (-not (Test-Path $manifestPath)) {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] MenuRegistry: Manifest not found at '$manifestPath'"
            }
            Write-Host "ERROR: Menu manifest not found at '$manifestPath'" -ForegroundColor Red
            return
        }

        try {
            # Load manifest
            $manifest = Import-PowerShellDataFile -Path $manifestPath

            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] MenuRegistry: Loaded manifest with $($manifest.Count) entries"
            }

            $screensDir = Split-Path $manifestPath -Parent

            # Register each menu item
            foreach ($entry in $manifest.GetEnumerator()) {
                $screenName = $entry.Key
                $config = $entry.Value

                $menu = $config.Menu
                $label = $config.Label
                $hotkey = $config.Hotkey
                $order = $config.Order
                $screenFile = $config.ScreenFile
                $viewMode = $(if ($config.ContainsKey('ViewMode')) { $config.ViewMode } else { $null })  # Optional, for TaskListScreen variants

                # Register screen factory in container if not already registered
                $screenTypeName = $screenFile -replace '\.ps1$', ''
                $screenPath = Join-Path $screensDir $screenFile

                if (-not $container.IsRegistered($screenName)) {
                    # Capture variables in closure for the factory
                    $factoryScreenPath = $screenPath
                    $factoryScreenTypeName = $screenTypeName
                    $factoryViewMode = $viewMode

                    # Register screen factory in container (non-singleton, creates new instance each time)
                    $container.Register($screenName, {
                        param($c)
                        # Dot-source screen file to load class
                        . $factoryScreenPath
                        # CRITICAL FIX: Use -ArgumentList parameter for reliable argument passing
                        # Positional arguments don't work correctly with New-Object in closures
                        if ($factoryViewMode) {
                            return New-Object $factoryScreenTypeName -ArgumentList $c, $factoryViewMode
                        } else {
                            return New-Object $factoryScreenTypeName -ArgumentList $c
                        }
                    }.GetNewClosure(), $false)  # Non-singleton: create new instance each time

                    if ($global:PmcTuiLogFile) {
                        Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] MenuRegistry: Registered screen factory '$screenName' in container (viewMode=$viewMode)"
                    }
                }

                # Build scriptblock that uses container to resolve screen
                $scriptblock = [scriptblock]::Create(@"
`$screen = `$global:PmcContainer.Resolve('$screenName')
`$global:PmcApp.PushScreen(`$screen)
"@)

                # Register the menu item
                $this.AddMenuItem($menu, $label, $hotkey, $scriptblock, $order)

                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] MenuRegistry: Registered '$label' in '$menu' menu (hotkey=$hotkey order=$order)"
                }
            }

        } catch {
            $errorMsg = "MenuRegistry: Error loading manifest: $($_.Exception.Message)"
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] $errorMsg"
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] Stack trace: $($_.ScriptStackTrace)"
            }
            Write-Host "ERROR: $errorMsg" -ForegroundColor Red
        }
    }

    <#
    .SYNOPSIS
    DEPRECATED: Old discovery method - kept for reference but not used

    .DESCRIPTION
    This method is deprecated in favor of LoadFromManifest().
    It caused type resolution issues due to parse-time type checking in PowerShell.
    #>
    [void] DiscoverScreens([string[]]$screenPaths) {
        # DEPRECATED: Use LoadFromManifest() instead
        # This method caused issues:
        # - Slow startup (loads all 40+ screen files)
        # - Type resolution errors (bracket notation requires types at parse time)
        # - Circular dependencies between screens

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [WARN] MenuRegistry.DiscoverScreens() is deprecated - use LoadFromManifest() instead"
        }
    }
}

# Export for module usage
if ($MyInvocation.MyCommand.Path) {
    Export-ModuleMember -Variable MenuRegistry
}