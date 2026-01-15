# ServiceContainer.ps1 - Dependency Injection Container
# Manages lifecycle and dependencies of all services, screens, and widgets

using namespace System.Collections.Generic

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Dependency injection container for PMC TUI

.DESCRIPTION
ServiceContainer manages registration and resolution of all dependencies:
- Services (TaskStore, MenuRegistry, etc.)
- Configuration (Theme, Config)
- Screens (lazy loaded on demand)
- Widgets (created per screen)

Solves initialization order, circular dependencies, and timing issues.

.EXAMPLE
$container = [ServiceContainer]::new()
$container.Register('Theme', { Initialize-PmcThemeSystem; return $global:PmcTheme })
$container.Register('TaskStore', { param($c) return [TaskStore]::GetInstance() })
$theme = $container.Resolve('Theme')
#>
class ServiceContainer {
    # Registered service factories
    hidden [hashtable]$_factories = @{}

    # Resolved singleton instances
    hidden [hashtable]$_singletons = @{}

    # Registration flags
    hidden [hashtable]$_isSingleton = @{}

    # Resolution stack (for circular dependency detection)
    hidden [List[string]]$_resolutionStack = [List[string]]::new()

    <#
    .SYNOPSIS
    Register a service with a factory function

    .PARAMETER name
    Service name (e.g., 'Theme', 'TaskStore', 'TaskListScreen')

    .PARAMETER factory
    Scriptblock that creates the service. Receives container as parameter.

    .PARAMETER singleton
    If true, service is created once and cached. Default: true

    .EXAMPLE
    $container.Register('Theme', {
        Initialize-PmcThemeSystem
        return Get-PmcState -Section 'Display' | Select-Object -ExpandProperty Theme
    })

    .EXAMPLE
    $container.Register('TaskStore', {
        param($container)
        $theme = $container.Resolve('Theme')  # Depend on theme
        return [TaskStore]::GetInstance()
    })
    #>
    [void] Register([string]$name, [scriptblock]$factory, [bool]$singleton = $true) {
        if ($this._factories.ContainsKey($name)) {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [WARN] ServiceContainer: Re-registering service '$name'"
            }
        }

        $this._factories[$name] = $factory
        $this._isSingleton[$name] = $singleton

        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ServiceContainer: Registered '$name' (singleton=$singleton)"
        }
    }

    <#
    .SYNOPSIS
    Resolve a service by name

    .PARAMETER name
    Service name to resolve

    .OUTPUTS
    Service instance

    .EXAMPLE
    $theme = $container.Resolve('Theme')
    $screen = $container.Resolve('TaskListScreen')
    #>
    [object] Resolve([string]$name) {
        # Check if already resolved (singleton)
        if ($this._isSingleton[$name] -and $this._singletons.ContainsKey($name)) {
            return $this._singletons[$name]
        }

        # Check if service registered
        if (-not $this._factories.ContainsKey($name)) {
            $error = "Service '$name' not registered in container"
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] ServiceContainer: $error"
            }
            throw $error
        }

        # Detect circular dependencies
        if ($this._resolutionStack.Contains($name)) {
            $chain = ($this._resolutionStack -join ' -> ') + " -> $name"
            $error = "Circular dependency detected: $chain"
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] ServiceContainer: $error"
            }
            throw $error
        }

        # Add to resolution stack
        $this._resolutionStack.Add($name)

        try {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ServiceContainer: Resolving '$name'..."
            }

            # Invoke factory (pass container for nested resolution)
            $factory = $this._factories[$name]
            $instance = & $factory $this

            # Cache if singleton
            if ($this._isSingleton[$name]) {
                $this._singletons[$name] = $instance
            }

            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ServiceContainer: Resolved '$name' successfully"
            }

            return $instance

        } catch {
            if ($global:PmcTuiLogFile) {
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] ServiceContainer: Failed to resolve '$name': $_"
                Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] Stack trace: $($_.ScriptStackTrace)"
            }
            throw
        } finally {
            # CRITICAL: Remove from resolution stack (cleanup on all paths)
            # Extra safety: wrap in try-catch to prevent double-fault
            try {
                $this._resolutionStack.Remove($name) | Out-Null
            } catch {
                # Resolution stack cleanup failed - log but don't throw
                if ($global:PmcTuiLogFile) {
                    Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [ERROR] ServiceContainer: Failed to clean resolution stack: $_"
                }
            }
        }
    }

    <#
    .SYNOPSIS
    Check if a service is registered

    .PARAMETER name
    Service name

    .OUTPUTS
    Boolean
    #>
    [bool] IsRegistered([string]$name) {
        return $this._factories.ContainsKey($name)
    }

    <#
    .SYNOPSIS
    Get all registered service names

    .OUTPUTS
    Array of service names
    #>
    [array] GetRegisteredServices() {
        return $this._factories.Keys
    }

    <#
    .SYNOPSIS
    Clear all resolved singletons (for testing/reset)
    #>
    [void] ClearResolved() {
        $this._singletons.Clear()
        if ($global:PmcTuiLogFile) {
            Add-Content -Path $global:PmcTuiLogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] ServiceContainer: Cleared all resolved singletons"
        }
    }
}