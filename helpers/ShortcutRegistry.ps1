# ShortcutRegistry - Centralized keyboard shortcut validation and conflict detection
# H-UI-5: Detect and prevent keyboard shortcut conflicts across the application

using namespace System.Collections.Generic

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Registry for tracking and validating keyboard shortcuts across screens and widgets

.DESCRIPTION
ShortcutRegistry provides centralized shortcut management to:
- Detect conflicts between shortcuts
- Validate shortcut availability
- Track shortcut usage across contexts
- Provide conflict resolution suggestions

.EXAMPLE
$registry = [ShortcutRegistry]::new()
$registry.Register("TaskList", "Ctrl+N", "New Task")
if ($registry.HasConflict("ProjectList", "Ctrl+N")) {
    # Handle conflict
}
#>
class ShortcutRegistry {
    # Dictionary: Context -> Dictionary<Shortcut, Description>
    [Dictionary[string, Dictionary[string, string]]]$_shortcuts

    # Global shortcuts that apply to all contexts
    [Dictionary[string, string]]$_globalShortcuts

    ShortcutRegistry() {
        $this._shortcuts = [Dictionary[string, Dictionary[string, string]]]::new()
        $this._globalShortcuts = [Dictionary[string, string]]::new()

        # Register common global shortcuts
        $this._globalShortcuts['Esc'] = 'Back/Cancel'
        $this._globalShortcuts['F10'] = 'Menu'
        $this._globalShortcuts['?'] = 'Help'
    }

    <#
    .SYNOPSIS
    Register a shortcut for a specific context

    .PARAMETER context
    The context (screen name, widget name, etc.)

    .PARAMETER shortcut
    The shortcut key combination (e.g., "Ctrl+N", "F5", "Alt+Enter")

    .PARAMETER description
    Description of what the shortcut does

    .RETURNS
    $true if registered successfully, $false if conflict detected
    #>
    [bool] Register([string]$context, [string]$shortcut, [string]$description) {
        # Check for global conflicts
        if ($this._globalShortcuts.ContainsKey($shortcut)) {
            Write-Warning "Shortcut conflict: '$shortcut' in context '$context' conflicts with global shortcut '$($this._globalShortcuts[$shortcut])'"
            return $false
        }

        # Ensure context exists
        if (-not $this._shortcuts.ContainsKey($context)) {
            $this._shortcuts[$context] = [Dictionary[string, string]]::new()
        }

        # Check for context-specific conflicts
        if ($this._shortcuts[$context].ContainsKey($shortcut)) {
            Write-Warning "Shortcut conflict: '$shortcut' already registered in context '$context' as '$($this._shortcuts[$context][$shortcut])'"
            return $false
        }

        # Register the shortcut
        $this._shortcuts[$context][$shortcut] = $description
        return $true
    }

    <#
    .SYNOPSIS
    Register a global shortcut that applies to all contexts

    .PARAMETER shortcut
    The shortcut key combination

    .PARAMETER description
    Description of what the shortcut does
    #>
    [void] RegisterGlobal([string]$shortcut, [string]$description) {
        $this._globalShortcuts[$shortcut] = $description
    }

    <#
    .SYNOPSIS
    Check if a shortcut would conflict in a given context

    .PARAMETER context
    The context to check

    .PARAMETER shortcut
    The shortcut to check

    .RETURNS
    $true if conflict exists, $false otherwise
    #>
    [bool] HasConflict([string]$context, [string]$shortcut) {
        # Check global shortcuts
        if ($this._globalShortcuts.ContainsKey($shortcut)) {
            return $true
        }

        # Check context-specific shortcuts
        if ($this._shortcuts.ContainsKey($context) -and
            $this._shortcuts[$context].ContainsKey($shortcut)) {
            return $true
        }

        return $false
    }

    <#
    .SYNOPSIS
    Get all shortcuts registered for a context

    .PARAMETER context
    The context to query

    .RETURNS
    Dictionary of shortcuts and their descriptions
    #>
    [Dictionary[string, string]] GetShortcuts([string]$context) {
        if ($this._shortcuts.ContainsKey($context)) {
            return $this._shortcuts[$context]
        }
        return [Dictionary[string, string]]::new()
    }

    <#
    .SYNOPSIS
    Get all global shortcuts

    .RETURNS
    Dictionary of global shortcuts and their descriptions
    #>
    [Dictionary[string, string]] GetGlobalShortcuts() {
        return $this._globalShortcuts
    }

    <#
    .SYNOPSIS
    Unregister a shortcut from a context

    .PARAMETER context
    The context

    .PARAMETER shortcut
    The shortcut to unregister
    #>
    [void] Unregister([string]$context, [string]$shortcut) {
        if ($this._shortcuts.ContainsKey($context)) {
            $this._shortcuts[$context].Remove($shortcut)
        }
    }

    <#
    .SYNOPSIS
    Clear all shortcuts for a context

    .PARAMETER context
    The context to clear
    #>
    [void] ClearContext([string]$context) {
        if ($this._shortcuts.ContainsKey($context)) {
            $this._shortcuts.Remove($context)
        }
    }

    <#
    .SYNOPSIS
    Get a report of all registered shortcuts

    .RETURNS
    String containing formatted report
    #>
    [string] GetReport() {
        $sb = [System.Text.StringBuilder]::new()

        $sb.AppendLine("=== Keyboard Shortcut Registry ===")
        $sb.AppendLine()

        # Global shortcuts
        $sb.AppendLine("Global Shortcuts:")
        foreach ($kvp in $this._globalShortcuts.GetEnumerator()) {
            $sb.AppendLine("  $($kvp.Key.PadRight(15)) : $($kvp.Value)")
        }
        $sb.AppendLine()

        # Context-specific shortcuts
        foreach ($context in $this._shortcuts.Keys | Sort-Object) {
            $sb.AppendLine("Context: $context")
            foreach ($kvp in $this._shortcuts[$context].GetEnumerator() | Sort-Object Key) {
                $sb.AppendLine("  $($kvp.Key.PadRight(15)) : $($kvp.Value)")
            }
            $sb.AppendLine()
        }

        return $sb.ToString()
    }
}

# Create global singleton instance if needed
if (-not (Get-Variable -Name PmcShortcutRegistry -Scope Global -ErrorAction SilentlyContinue)) {
    $global:PmcShortcutRegistry = [ShortcutRegistry]::new()
}