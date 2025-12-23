# SpeedTUI Plugin Manager - Simple, extensible plugin system
# Allows easy addition of new components, themes, and functionality

using namespace System.Collections.Generic
using namespace System.IO

<#
.SYNOPSIS
Plugin information container

.DESCRIPTION
Contains metadata about a loaded plugin including its name, version,
components, and capabilities.

.EXAMPLE
$pluginInfo = [PluginInfo]::new("MyPlugin", "1.0", "Custom components for SpeedTUI")
#>
class PluginInfo {
    [string]$Name
    [string]$Version
    [string]$Description
    [string]$Author
    [string]$FilePath
    [DateTime]$LoadedAt
    [hashtable]$Metadata
    [string[]]$ProvidedComponents
    [string[]]$ProvidedThemes
    [string[]]$ProvidedCommands
    
    PluginInfo([string]$name, [string]$version, [string]$description) {
        $this.Name = $name
        $this.Version = $version
        $this.Description = $description
        $this.Author = ""
        $this.FilePath = ""
        $this.LoadedAt = [DateTime]::Now
        $this.Metadata = @{}
        $this.ProvidedComponents = @()
        $this.ProvidedThemes = @()
        $this.ProvidedCommands = @()
    }
    
    [string] ToString() {
        return "$($this.Name) v$($this.Version) - $($this.Description)"
    }
}

<#
.SYNOPSIS
Simple, powerful plugin manager for SpeedTUI

.DESCRIPTION
Provides easy plugin loading and management with automatic discovery
of components, themes, and commands. Plugins are simple PowerShell
files that follow naming conventions.

.EXAMPLE
$pluginManager = [PluginManager]::new()
$pluginManager.LoadPlugin("./Plugins/AdvancedDataGrid.ps1")
$pluginManager.LoadPluginsFromDirectory("./Plugins")
#>
class PluginManager {
    hidden [Dictionary[string, PluginInfo]]$_loadedPlugins
    hidden [Dictionary[string, type]]$_registeredComponents
    hidden [Dictionary[string, object]]$_registeredThemes
    hidden [Dictionary[string, scriptblock]]$_registeredCommands
    hidden [object]$_logger
    hidden [string[]]$_pluginDirectories
    
    # Event manager for plugin events
    hidden [object]$_eventManager
    
    PluginManager() {
        $this._loadedPlugins = [Dictionary[string, PluginInfo]]::new()
        $this._registeredComponents = [Dictionary[string, type]]::new()
        $this._registeredThemes = [Dictionary[string, object]]::new()
        $this._registeredCommands = [Dictionary[string, scriptblock]]::new()
        $this._logger = Get-Logger
        $this._pluginDirectories = @("./Plugins", "./Extensions", "./Components")
        
        # Try to get event manager
        try {
            $this._eventManager = Get-EventManager -ErrorAction SilentlyContinue
        } catch {
            $this._eventManager = $null
        }
        
        $this._logger.Info("PluginManager", "Constructor", "Plugin manager initialized")
    }
    
    <#
    .SYNOPSIS
    Load a plugin from a file
    
    .PARAMETER pluginPath
    Path to the plugin file (.ps1)
    
    .OUTPUTS
    PluginInfo object if successful, null if failed
    
    .EXAMPLE
    $plugin = $pluginManager.LoadPlugin("./Plugins/AdvancedDataGrid.ps1")
    if ($plugin) {
        Write-Host "Loaded plugin: $($plugin.Name)"
    }
    #>
    [PluginInfo] LoadPlugin([string]$pluginPath) {
        if ([string]::IsNullOrWhiteSpace($pluginPath)) {
            $this._logger.Error("PluginManager", "LoadPlugin", "Plugin path is null or empty")
            return $null
        }
        
        if (-not (Test-Path $pluginPath)) {
            $this._logger.Error("PluginManager", "LoadPlugin", "Plugin file not found", @{
                Path = $pluginPath
            })
            return $null
        }
        
        try {
            $this._logger.Info("PluginManager", "LoadPlugin", "Loading plugin", @{
                Path = $pluginPath
            })
            
            # Create a safe execution context for the plugin
            $pluginScope = @{
                PluginManager = $this
                RegisterComponent = { param($name, $type) $this.RegisterComponent($name, $type) }
                RegisterTheme = { param($name, $theme) $this.RegisterTheme($name, $theme) }
                RegisterCommand = { param($name, $command) $this.RegisterCommand($name, $command) }
                GetEventManager = { Get-EventManager -ErrorAction SilentlyContinue }
                GetThemeManager = { Get-ThemeManager -ErrorAction SilentlyContinue }
            }
            
            # Load plugin content
            $pluginContent = Get-Content $pluginPath -Raw
            
            # Look for plugin metadata in comments
            $pluginInfo = $this.ParsePluginMetadata($pluginContent, $pluginPath)
            
            # Execute the plugin in a controlled way
            $scriptBlock = [scriptblock]::Create($pluginContent)
            & $scriptBlock
            
            # Register the plugin
            $this._loadedPlugins[$pluginInfo.Name] = $pluginInfo
            
            # Fire plugin loaded event
            if ($this._eventManager) {
                $this._eventManager.Fire("plugin.loaded", @{
                    Plugin = $pluginInfo
                    Path = $pluginPath
                }, "PluginManager")
            }
            
            $this._logger.Info("PluginManager", "LoadPlugin", "Plugin loaded successfully", @{
                Name = $pluginInfo.Name
                Version = $pluginInfo.Version
                Components = $pluginInfo.ProvidedComponents.Count
                Themes = $pluginInfo.ProvidedThemes.Count
                Commands = $pluginInfo.ProvidedCommands.Count
            })
            
            return $pluginInfo
            
        } catch {
            $this._logger.Error("PluginManager", "LoadPlugin", "Failed to load plugin", @{
                Path = $pluginPath
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            return $null
        }
    }
    
    <#
    .SYNOPSIS
    Load all plugins from a directory
    
    .PARAMETER directoryPath
    Path to directory containing plugin files
    
    .PARAMETER recursive
    Whether to search subdirectories
    
    .OUTPUTS
    Array of loaded PluginInfo objects
    
    .EXAMPLE
    $plugins = $pluginManager.LoadPluginsFromDirectory("./Plugins")
    Write-Host "Loaded $($plugins.Count) plugins"
    #>
    [PluginInfo[]] LoadPluginsFromDirectory([string]$directoryPath, [bool]$recursive = $false) {
        if ([string]::IsNullOrWhiteSpace($directoryPath)) {
            $this._logger.Error("PluginManager", "LoadPluginsFromDirectory", "Directory path is null or empty")
            return @()
        }
        
        if (-not (Test-Path $directoryPath)) {
            $this._logger.Warn("PluginManager", "LoadPluginsFromDirectory", "Plugin directory not found", @{
                Path = $directoryPath
            })
            return @()
        }
        
        $loadedPlugins = [List[PluginInfo]]::new()
        
        try {
            $searchOption = $(if ($recursive) { [SearchOption]::AllDirectories } else { [SearchOption]::TopDirectoryOnly })
            $pluginFiles = [Directory]::GetFiles($directoryPath, "*.ps1", $searchOption)
            
            $this._logger.Info("PluginManager", "LoadPluginsFromDirectory", "Found plugin files", @{
                Directory = $directoryPath
                FileCount = $pluginFiles.Count
                Recursive = $recursive
            })
            
            foreach ($pluginFile in $pluginFiles) {
                $plugin = $this.LoadPlugin($pluginFile)
                if ($plugin) {
                    $loadedPlugins.Add($plugin)
                }
            }
            
        } catch {
            $this._logger.Error("PluginManager", "LoadPluginsFromDirectory", "Failed to load plugins from directory", @{
                Directory = $directoryPath
                Exception = $_.Exception.Message
            })
        }
        
        return $loadedPlugins.ToArray()
    }
    
    <#
    .SYNOPSIS
    Auto-discover and load plugins from standard directories
    
    .OUTPUTS
    Array of loaded PluginInfo objects
    
    .EXAMPLE
    $plugins = $pluginManager.DiscoverAndLoadPlugins()
    #>
    [PluginInfo[]] DiscoverAndLoadPlugins() {
        $allPlugins = [List[PluginInfo]]::new()
        
        foreach ($directory in $this._pluginDirectories) {
            if (Test-Path $directory) {
                $plugins = $this.LoadPluginsFromDirectory($directory)
                $allPlugins.AddRange($plugins)
            }
        }
        
        $this._logger.Info("PluginManager", "DiscoverAndLoadPlugins", "Plugin discovery complete", @{
            TotalPlugins = $allPlugins.Count
            SearchedDirectories = ($this._pluginDirectories -join ", ")
        })
        
        return $allPlugins.ToArray()
    }
    
    <#
    .SYNOPSIS
    Register a component type from a plugin
    
    .PARAMETER name
    Name of the component
    
    .PARAMETER componentType
    Type of the component class
    
    .EXAMPLE
    $pluginManager.RegisterComponent("AdvancedDataGrid", [AdvancedDataGrid])
    #>
    [void] RegisterComponent([string]$name, [type]$componentType) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Component name cannot be null or empty")
        }
        if (-not $componentType) {
            throw [ArgumentException]::new("Component type cannot be null")
        }
        
        $this._registeredComponents[$name] = $componentType
        
        $this._logger.Info("PluginManager", "RegisterComponent", "Component registered", @{
            Name = $name
            Type = $componentType.Name
        })
        
        # Fire component registered event
        if ($this._eventManager) {
            $this._eventManager.Fire("component.registered", @{
                Name = $name
                Type = $componentType
            }, "PluginManager")
        }
    }
    
    <#
    .SYNOPSIS
    Register a theme from a plugin
    
    .PARAMETER name
    Name of the theme
    
    .PARAMETER theme
    Theme object
    
    .EXAMPLE
    $pluginManager.RegisterTheme("CorporateBlue", $corporateTheme)
    #>
    [void] RegisterTheme([string]$name, [object]$theme) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Theme name cannot be null or empty")
        }
        if (-not $theme) {
            throw [ArgumentException]::new("Theme cannot be null")
        }
        
        $this._registeredThemes[$name] = $theme
        
        # Register with theme manager if available
        try {
            $themeManager = Get-ThemeManager -ErrorAction SilentlyContinue
            if ($themeManager) {
                $themeManager.RegisterTheme($theme)
            }
        } catch {
            $this._logger.Warn("PluginManager", "RegisterTheme", "Could not register theme with theme manager", @{
                ThemeName = $name
                Error = $_.Exception.Message
            })
        }
        
        $this._logger.Info("PluginManager", "RegisterTheme", "Theme registered", @{
            Name = $name
            Type = $theme.GetType().Name
        })
        
        # Fire theme registered event
        if ($this._eventManager) {
            $this._eventManager.Fire("theme.registered", @{
                Name = $name
                Theme = $theme
            }, "PluginManager")
        }
    }
    
    <#
    .SYNOPSIS
    Register a command from a plugin
    
    .PARAMETER name
    Name of the command
    
    .PARAMETER command
    Command scriptblock
    
    .EXAMPLE
    $pluginManager.RegisterCommand("Show-AdvancedGrid", { param($data) ... })
    #>
    [void] RegisterCommand([string]$name, [scriptblock]$command) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Command name cannot be null or empty")
        }
        if (-not $command) {
            throw [ArgumentException]::new("Command cannot be null")
        }
        
        $this._registeredCommands[$name] = $command
        
        $this._logger.Info("PluginManager", "RegisterCommand", "Command registered", @{
            Name = $name
        })
        
        # Fire command registered event
        if ($this._eventManager) {
            $this._eventManager.Fire("command.registered", @{
                Name = $name
                Command = $command
            }, "PluginManager")
        }
    }
    
    <#
    .SYNOPSIS
    Get a registered component type by name
    
    .PARAMETER name
    Name of the component
    
    .OUTPUTS
    Component type if found, null otherwise
    
    .EXAMPLE
    $gridType = $pluginManager.GetComponent("AdvancedDataGrid")
    if ($gridType) {
        $grid = $gridType::new()
    }
    #>
    [type] GetComponent([string]$name) {
        if ($this._registeredComponents.ContainsKey($name)) {
            return $this._registeredComponents[$name]
        }
        return $null
    }
    
    <#
    .SYNOPSIS
    Get a registered theme by name
    
    .PARAMETER name
    Name of the theme
    
    .OUTPUTS
    Theme object if found, null otherwise
    #>
    [object] GetTheme([string]$name) {
        if ($this._registeredThemes.ContainsKey($name)) {
            return $this._registeredThemes[$name]
        }
        return $null
    }
    
    <#
    .SYNOPSIS
    Execute a registered command
    
    .PARAMETER name
    Name of the command
    
    .PARAMETER parameters
    Parameters to pass to the command
    
    .OUTPUTS
    Command result
    
    .EXAMPLE
    $result = $pluginManager.ExecuteCommand("Show-AdvancedGrid", @{ Data = $myData })
    #>
    [object] ExecuteCommand([string]$name, [object]$parameters = $null) {
        if (-not $this._registeredCommands.ContainsKey($name)) {
            $this._logger.Warn("PluginManager", "ExecuteCommand", "Command not found", @{
                CommandName = $name
            })
            return $null
        }
        
        try {
            $command = $this._registeredCommands[$name]
            if ($parameters) {
                return & $command $parameters
            } else {
                return & $command
            }
        } catch {
            $this._logger.Error("PluginManager", "ExecuteCommand", "Command execution failed", @{
                CommandName = $name
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    <#
    .SYNOPSIS
    Get information about all loaded plugins
    
    .OUTPUTS
    Array of PluginInfo objects
    
    .EXAMPLE
    $plugins = $pluginManager.GetLoadedPlugins()
    foreach ($plugin in $plugins) {
        Write-Host $plugin.ToString()
    }
    #>
    [PluginInfo[]] GetLoadedPlugins() {
        return $this._loadedPlugins.Values | Sort-Object Name
    }
    
    <#
    .SYNOPSIS
    Get list of all registered component names
    
    .OUTPUTS
    Array of component names
    #>
    [string[]] GetRegisteredComponents() {
        return $this._registeredComponents.Keys | Sort-Object
    }
    
    <#
    .SYNOPSIS
    Get list of all registered theme names
    
    .OUTPUTS
    Array of theme names
    #>
    [string[]] GetRegisteredThemes() {
        return $this._registeredThemes.Keys | Sort-Object
    }
    
    <#
    .SYNOPSIS
    Get list of all registered command names
    
    .OUTPUTS
    Array of command names
    #>
    [string[]] GetRegisteredCommands() {
        return $this._registeredCommands.Keys | Sort-Object
    }
    
    <#
    .SYNOPSIS
    Unload a plugin and remove its registrations
    
    .PARAMETER pluginName
    Name of the plugin to unload
    
    .EXAMPLE
    $pluginManager.UnloadPlugin("MyPlugin")
    #>
    [bool] UnloadPlugin([string]$pluginName) {
        if (-not $this._loadedPlugins.ContainsKey($pluginName)) {
            return $false
        }
        
        $plugin = $this._loadedPlugins[$pluginName]
        
        # Remove component registrations
        foreach ($componentName in $plugin.ProvidedComponents) {
            $this._registeredComponents.Remove($componentName)
        }
        
        # Remove theme registrations
        foreach ($themeName in $plugin.ProvidedThemes) {
            $this._registeredThemes.Remove($themeName)
        }
        
        # Remove command registrations
        foreach ($commandName in $plugin.ProvidedCommands) {
            $this._registeredCommands.Remove($commandName)
        }
        
        # Remove plugin
        $this._loadedPlugins.Remove($pluginName)
        
        # Fire plugin unloaded event
        if ($this._eventManager) {
            $this._eventManager.Fire("plugin.unloaded", @{
                Plugin = $plugin
            }, "PluginManager")
        }
        
        $this._logger.Info("PluginManager", "UnloadPlugin", "Plugin unloaded", @{
            Name = $pluginName
        })
        
        return $true
    }
    
    # Parse plugin metadata from comments
    hidden [PluginInfo] ParsePluginMetadata([string]$content, [string]$filePath) {
        $name = [Path]::GetFileNameWithoutExtension($filePath)
        $version = "1.0"
        $description = ""
        $author = ""
        
        # Look for metadata in comments
        $lines = $content -split "`n"
        foreach ($line in $lines) {
            $line = $line.Trim()
            if ($line.StartsWith("#")) {
                if ($line -match "# Plugin: (.+)") {
                    $name = $matches[1].Trim()
                } elseif ($line -match "# Version: (.+)") {
                    $version = $matches[1].Trim()
                } elseif ($line -match "# Description: (.+)") {
                    $description = $matches[1].Trim()
                } elseif ($line -match "# Author: (.+)") {
                    $author = $matches[1].Trim()
                }
            } elseif (-not $line.StartsWith("#") -and $line.Length -gt 0) {
                # Stop parsing when we hit actual code
                break
            }
        }
        
        $pluginInfo = [PluginInfo]::new($name, $version, $description)
        $pluginInfo.Author = $author
        $pluginInfo.FilePath = $filePath
        
        return $pluginInfo
    }
}

# Global plugin manager instance
$global:SpeedTUIPluginManager = $null

<#
.SYNOPSIS
Get the global SpeedTUI plugin manager instance

.OUTPUTS
PluginManager instance

.EXAMPLE
$pluginManager = Get-PluginManager
$pluginManager.LoadPlugin("./MyPlugin.ps1")
#>
function Get-PluginManager {
    if (-not $global:SpeedTUIPluginManager) {
        $global:SpeedTUIPluginManager = [PluginManager]::new()
    }
    return $global:SpeedTUIPluginManager
}

<#
.SYNOPSIS
Load a SpeedTUI plugin from file

.PARAMETER PluginPath
Path to the plugin file

.EXAMPLE
Load-SpeedTUIPlugin "./Plugins/AdvancedDataGrid.ps1"
#>
function Load-SpeedTUIPlugin {
    param([string]$PluginPath)
    
    $pluginManager = Get-PluginManager
    return $pluginManager.LoadPlugin($PluginPath)
}

<#
.SYNOPSIS
Discover and load all SpeedTUI plugins

.EXAMPLE
$plugins = Find-SpeedTUIPlugins
Write-Host "Loaded $($plugins.Count) plugins"
#>
function Find-SpeedTUIPlugins {
    $pluginManager = Get-PluginManager
    return $pluginManager.DiscoverAndLoadPlugins()
}

<#
.SYNOPSIS
Get information about loaded SpeedTUI plugins

.EXAMPLE
Get-SpeedTUIPlugins | ForEach-Object { Write-Host $_.ToString() }
#>
function Get-SpeedTUIPlugins {
    $pluginManager = Get-PluginManager
    return $pluginManager.GetLoadedPlugins()
}

# Initialize the global plugin manager
$global:SpeedTUIPluginManager = [PluginManager]::new()

Export-ModuleMember -Function Get-PluginManager, Load-SpeedTUIPlugin, Find-SpeedTUIPlugins, Get-SpeedTUIPlugins