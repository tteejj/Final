# SpeedTUI Input Manager - Centralized input handling with focus management

using namespace System.Collections.Generic
using namespace System.Threading
using namespace System.Collections.Concurrent

class KeyBinding {
    [System.ConsoleKey]$Key
    [System.ConsoleModifiers]$Modifiers
    [string]$Action
    [scriptblock]$Handler
    [string]$Description
    hidden [object]$_logger
    
    KeyBinding([System.ConsoleKey]$key, [System.ConsoleModifiers]$modifiers, [string]$action, [scriptblock]$handler) {
        $this._logger = Get-Logger
        $this._logger.Trace("KeyBinding", "Constructor", "Creating key binding", @{
            Key = $key
            Modifiers = $modifiers
            Action = $action
        })
        
        $this.Key = $key
        $this.Modifiers = $modifiers
        $this.Action = $action
        $this.Handler = $handler
        $this.Description = ""
    }
    
    [bool] Matches([System.ConsoleKeyInfo]$keyInfo) {
        $this._logger.Trace("KeyBinding", "Matches", "Checking key match", @{
            BindingKey = $this.Key
            BindingModifiers = $this.Modifiers
            InputKey = $keyInfo.Key
            InputModifiers = $keyInfo.Modifiers
        })
        
        $matches = $keyInfo.Key -eq $this.Key -and $keyInfo.Modifiers -eq $this.Modifiers
        $this._logger.Trace("KeyBinding", "Matches", "Match result", @{ Matches = $matches })
        return $matches
    }
    
    [string] ToString() {
        $modStr = ""
        if ($this.Modifiers -band [System.ConsoleModifiers]::Control) { $modStr += "Ctrl+" }
        if ($this.Modifiers -band [System.ConsoleModifiers]::Alt) { $modStr += "Alt+" }
        if ($this.Modifiers -band [System.ConsoleModifiers]::Shift) { $modStr += "Shift+" }
        return "$modStr$($this.Key)"
    }
}

class FocusManager {
    hidden [List[Component]]$_focusableComponents
    hidden [Component]$_currentFocus
    hidden [object]$_logger
    
    FocusManager() {
        $this._logger = Get-Logger
        $this._logger.Trace("FocusManager", "Constructor", "Creating focus manager")
        
        $this._focusableComponents = [List[Component]]::new()
        $this._logger.Debug("FocusManager", "Constructor", "FocusManager created successfully")
    }
    
    [void] RegisterComponent([Component]$component) {
        $this._logger.Trace("FocusManager", "RegisterComponent", "Registering component", @{
            ComponentId = $(if ($component) { $component.Id } else { "null" })
            CanFocus = $(if ($component) { $component.CanFocus } else { $false })
        })
        
        try {
            [Guard]::NotNull($component, "component")
            
            if ($component.CanFocus -and -not $this._focusableComponents.Contains($component)) {
                $this._focusableComponents.Add($component)
                $this._logger.Debug("FocusManager", "RegisterComponent", "Component registered", @{
                    ComponentId = $component.Id
                    TotalFocusableComponents = $this._focusableComponents.Count
                })
            } else {
                $this._logger.Trace("FocusManager", "RegisterComponent", "Component not registered", @{
                    ComponentId = $component.Id
                    Reason = $(if (-not $component.CanFocus) { "CannotFocus" } else { "AlreadyRegistered" })
                })
            }
            
            # Sort by TabIndex
            $this._focusableComponents.Sort({
                param($a, $b)
                $a.TabIndex.CompareTo($b.TabIndex)
            })
            
        } catch {
            $this._logger.Error("FocusManager", "RegisterComponent", "Failed to register component", @{
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    [void] UnregisterComponent([Component]$component) {
        [Guard]::NotNull($component, "component")
        
        if ($this._focusableComponents.Remove($component)) {
            if ($this._currentFocus -eq $component) {
                $this.FocusNext()
            }
            
            $this._logger.Debug("FocusManager", "UnregisterComponent", "Component unregistered", @{
                ComponentId = $component.Id
            })
        }
    }
    
    [void] SetFocus([Component]$component) {
        [Guard]::NotNull($component, "component")
        
        if (-not $component.CanFocus -or -not $component.Visible) {
            $this._logger.Warn("FocusManager", "SetFocus", "Cannot focus component", @{
                ComponentId = $component.Id
                CanFocus = $component.CanFocus
                Visible = $component.Visible
            })
            return
        }
        
        if ($this._currentFocus -ne $component) {
            # Blur current
            if ($null -ne $this._currentFocus) {
                $this._currentFocus.Blur()
            }
            
            # Focus new
            $this._currentFocus = $component
            $component.Focus()
            
            $this._logger.Debug("FocusManager", "SetFocus", "Focus changed", @{
                ComponentId = $component.Id
                ComponentType = $component.GetType().Name
            })
        }
    }
    
    [void] FocusNext() {
        if ($this._focusableComponents.Count -eq 0) { return }
        
        $currentIndex = -1
        if ($null -ne $this._currentFocus) {
            $currentIndex = $this._focusableComponents.IndexOf($this._currentFocus)
        }
        
        $nextIndex = ($currentIndex + 1) % $this._focusableComponents.Count
        $attempts = 0
        
        # Find next visible component
        while ($attempts -lt $this._focusableComponents.Count) {
            $next = $this._focusableComponents[$nextIndex]
            if ($next.Visible) {
                $this.SetFocus($next)
                break
            }
            $nextIndex = ($nextIndex + 1) % $this._focusableComponents.Count
            $attempts++
        }
    }
    
    [void] FocusPrevious() {
        if ($this._focusableComponents.Count -eq 0) { return }
        
        $currentIndex = -1
        if ($null -ne $this._currentFocus) {
            $currentIndex = $this._focusableComponents.IndexOf($this._currentFocus)
        }
        
        $prevIndex = $(if ($currentIndex -le 0) { 
            $this._focusableComponents.Count - 1 
        } else { 
            $currentIndex - 1 
        })
        
        $attempts = 0
        
        # Find previous visible component
        while ($attempts -lt $this._focusableComponents.Count) {
            $prev = $this._focusableComponents[$prevIndex]
            if ($prev.Visible) {
                $this.SetFocus($prev)
                break
            }
            $prevIndex = $(if ($prevIndex -le 0) { 
                $this._focusableComponents.Count - 1 
            } else { 
                $prevIndex - 1 
            })
            $attempts++
        }
    }
    
    [Component] GetFocusedComponent() {
        return $this._currentFocus
    }
    
    [void] RefreshFocusableList([Component]$root) {
        [Guard]::NotNull($root, "root")
        
        $this._focusableComponents.Clear()
        $focusable = $root.GetFocusableComponents()
        
        foreach ($component in $focusable) {
            $this.RegisterComponent($component)
        }
        
        $this._logger.Debug("FocusManager", "RefreshFocusableList", "Focusable list refreshed", @{
            TotalComponents = $this._focusableComponents.Count
        })
        
        # Focus first component if nothing focused
        if ($null -eq $this._currentFocus -and $this._focusableComponents.Count -gt 0) {
            $this.SetFocus($this._focusableComponents[0])
        }
    }
}

class InputManager {
    hidden [Dictionary[string, KeyBinding]]$_globalBindings
    hidden [Dictionary[string, Dictionary[string, KeyBinding]]]$_contextBindings
    hidden [string]$_currentContext = "default"
    hidden [FocusManager]$_focusManager
    hidden [object]$_logger
    hidden [bool]$_running = $false
    hidden [Thread]$_inputThread
    hidden [BlockingCollection[System.ConsoleKeyInfo]]$_keyQueue
    
    InputManager() {
        $this._globalBindings = [Dictionary[string, KeyBinding]]::new()
        $this._contextBindings = [Dictionary[string, Dictionary[string, KeyBinding]]]::new()
        $this._focusManager = [FocusManager]::new()
        $this._keyQueue = [BlockingCollection[System.ConsoleKeyInfo]]::new()
        $this._logger = Get-Logger
        
        $this._logger.Info("InputManager", "Constructor", "InputManager created")
        
        # Register default bindings
        $this.RegisterDefaultBindings()
    }
    
    [void] RegisterDefaultBindings() {
        # Tab navigation
        $this.RegisterGlobalBinding([System.ConsoleKey]::Tab, 0, "FocusNext", {
            $this._focusManager.FocusNext()
        })
        
        $this.RegisterGlobalBinding([System.ConsoleKey]::Tab, [System.ConsoleModifiers]::Shift, "FocusPrevious", {
            $this._focusManager.FocusPrevious()
        })
        
        # Escape
        $this.RegisterGlobalBinding([System.ConsoleKey]::Escape, 0, "Cancel", {})
        
        $this._logger.Debug("InputManager", "RegisterDefaultBindings", "Default bindings registered")
    }
    
    [void] RegisterGlobalBinding([System.ConsoleKey]$key, [System.ConsoleModifiers]$modifiers, [string]$action, [scriptblock]$handler) {
        [Guard]::NotNullOrEmpty($action, "action")
        [Guard]::NotNull($handler, "handler")
        
        $binding = [KeyBinding]::new($key, $modifiers, $action, $handler)
        $bindingKey = "$($key)_$($modifiers)"
        $this._globalBindings[$bindingKey] = $binding
        
        $this._logger.Debug("InputManager", "RegisterGlobalBinding", "Global binding registered", @{
            Key = $binding.ToString()
            Action = $action
        })
    }
    
    [void] RegisterContextBinding([string]$context, [System.ConsoleKey]$key, [System.ConsoleModifiers]$modifiers, [string]$action, [scriptblock]$handler) {
        [Guard]::NotNullOrEmpty($context, "context")
        [Guard]::NotNullOrEmpty($action, "action")
        [Guard]::NotNull($handler, "handler")
        
        if (-not $this._contextBindings.ContainsKey($context)) {
            $this._contextBindings[$context] = [Dictionary[string, KeyBinding]]::new()
        }
        
        $binding = [KeyBinding]::new($key, $modifiers, $action, $handler)
        $bindingKey = "$($key)_$($modifiers)"
        $this._contextBindings[$context][$bindingKey] = $binding
        
        $this._logger.Debug("InputManager", "RegisterContextBinding", "Context binding registered", @{
            Context = $context
            Key = $binding.ToString()
            Action = $action
        })
    }
    
    [void] SetContext([string]$context) {
        [Guard]::NotNullOrEmpty($context, "context")
        
        if ($this._currentContext -ne $context) {
            $this._logger.Debug("InputManager", "SetContext", "Context changed", @{
                OldContext = $this._currentContext
                NewContext = $context
            })
            $this._currentContext = $context
        }
    }
    
    [void] Start() {
        if ($this._running) { return }
        
        $this._running = $true
        
        # Don't use background thread for now - will check keys synchronously
        
        $this._logger.Info("InputManager", "Start", "Input manager started")
    }
    
    [void] Stop() {
        $this._running = $false
        
        if ($null -ne $this._inputThread) {
            $this._inputThread.Join(1000)
            $this._inputThread = $null
        }
        
        $this._logger.Info("InputManager", "Stop", "Input manager stopped")
    }
    
    [bool] ProcessInput([Component]$rootComponent) {
        [Guard]::NotNull($rootComponent, "rootComponent")
        
        # Check for available keys directly
        if (-not [Console]::KeyAvailable) {
            return $false
        }
        
        $keyInfo = [Console]::ReadKey($true)
        
        $this._logger.Trace("InputManager", "ProcessInput", "Key received", @{
            Key = $keyInfo.Key
            Char = $keyInfo.KeyChar
            Modifiers = $keyInfo.Modifiers
        })
        
        # Let focused component handle first
        $focused = $this._focusManager.GetFocusedComponent()
        if ($null -ne $focused -and $focused.HandleKeyPress($keyInfo)) {
            return $true
        }
        
        # Check context bindings
        $bindingKey = "$($keyInfo.Key)_$($keyInfo.Modifiers)"
        
        if ($this._contextBindings.ContainsKey($this._currentContext)) {
            $contextBindings = $this._contextBindings[$this._currentContext]
            if ($contextBindings.ContainsKey($bindingKey)) {
                $binding = $contextBindings[$bindingKey]
                $this._logger.Debug("InputManager", "ProcessInput", "Context binding triggered", @{
                    Context = $this._currentContext
                    Action = $binding.Action
                })
                & $binding.Handler
                return $true
            }
        }
        
        # Check global bindings
        if ($this._globalBindings.ContainsKey($bindingKey)) {
            $binding = $this._globalBindings[$bindingKey]
            $this._logger.Debug("InputManager", "ProcessInput", "Global binding triggered", @{
                Action = $binding.Action
            })
            & $binding.Handler
            return $true
        }
        
        # Let root component handle unhandled keys
        return $rootComponent.HandleKeyPress($keyInfo)
    }
    
    [FocusManager] GetFocusManager() {
        return $this._focusManager
    }
    
    [List[KeyBinding]] GetActiveBindings() {
        $bindings = [List[KeyBinding]]::new()
        
        # Add context bindings
        if ($this._contextBindings.ContainsKey($this._currentContext)) {
            foreach ($binding in $this._contextBindings[$this._currentContext].Values) {
                $bindings.Add($binding)
            }
        }
        
        # Add global bindings
        foreach ($binding in $this._globalBindings.Values) {
            $bindings.Add($binding)
        }
        
        return $bindings
    }
}