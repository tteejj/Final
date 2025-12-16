# SpeedTUI Event Manager - Simple, clear event system
# Much simpler than Praxis EventBus while maintaining power and flexibility

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

<#
.SYNOPSIS
Simple event data container for passing information with events

.DESCRIPTION
Lightweight container for event data that's easy to create and use.
Developers can pass any hashtable or object as event data.

.EXAMPLE
$eventData = [EventData]::new("button.clicked", @{ ButtonId = "okButton"; Value = "OK" })
#>
class EventData {
    [string]$EventName
    [object]$Data
    [DateTime]$Timestamp
    [string]$Source
    
    EventData([string]$eventName, [object]$data = $null, [string]$source = "") {
        $this.EventName = $eventName
        $this.Data = $data
        $this.Timestamp = [DateTime]::Now
        $this.Source = $source
    }
    
    # Easy access to data properties
    [object] Get([string]$key) {
        if ($this.Data -is [hashtable] -and $this.Data.ContainsKey($key)) {
            return $this.Data[$key]
        }
        if ($this.Data -and $this.Data.PSObject.Properties[$key]) {
            return $this.Data.PSObject.Properties[$key].Value
        }
        return $null
    }
    
    [string] ToString() {
        return "Event: $($this.EventName) at $($this.Timestamp.ToString('HH:mm:ss.fff'))"
    }
}

<#
.SYNOPSIS
Simple, powerful event manager for SpeedTUI

.DESCRIPTION
Provides a clean event system that's much easier to use than complex pub/sub systems.
- Simple On/Off methods for subscribing to events
- Easy Fire method for triggering events  
- Automatic cleanup and error handling
- Thread-safe operations
- Optional event history for debugging

.EXAMPLE
# Simple usage
$events = [EventManager]::new()
$events.On("button.clicked") { param($eventData)
    Write-Host "Button clicked: $($eventData.Get('ButtonId'))"
}
$events.Fire("button.clicked", @{ ButtonId = "okButton" })

# Advanced usage with cleanup
$subscription = $events.On("data.changed") { param($eventData)
    # Handle data change
}
$events.Off("data.changed", $subscription)
#>
class EventManager {
    # Event handlers storage (thread-safe)
    hidden [ConcurrentDictionary[string, List[hashtable]]]$_handlers
    hidden [int]$_nextSubscriptionId = 1
    
    # Optional event history for debugging
    [bool]$EnableHistory = $false
    [int]$MaxHistorySize = 100
    hidden [List[EventData]]$_eventHistory
    
    # Performance tracking
    hidden [hashtable]$_stats = @{
        EventsFired = 0
        HandlersExecuted = 0
        ErrorsOccurred = 0
    }
    
    # Logger for debugging
    hidden [object]$_logger
    
    EventManager() {
        $this._handlers = [ConcurrentDictionary[string, List[hashtable]]]::new()
        $this._eventHistory = [List[EventData]]::new()
        $this._logger = Get-Logger
        
        $this._logger.Info("EventManager", "Constructor", "Event manager created")
    }
    
    <#
    .SYNOPSIS
    Subscribe to an event (simple, clear method name)
    
    .PARAMETER eventName
    Name of the event to listen for (e.g., "button.clicked", "data.changed")
    
    .PARAMETER handler
    Scriptblock to execute when event fires. Receives EventData parameter.
    
    .OUTPUTS
    Subscription ID that can be used to unsubscribe later
    
    .EXAMPLE
    $id = $events.On("button.clicked") { param($eventData)
        Write-Host "Button $($eventData.Get('ButtonId')) clicked!"
    }
    #>
    [string] On([string]$eventName, [scriptblock]$handler) {
        if ([string]::IsNullOrWhiteSpace($eventName)) {
            throw [ArgumentException]::new("Event name cannot be null or empty")
        }
        if (-not $handler) {
            throw [ArgumentException]::new("Handler cannot be null")
        }
        
        # Create subscription
        $subscriptionId = "sub_$($this._nextSubscriptionId)"
        $this._nextSubscriptionId++
        
        $subscription = @{
            Id = $subscriptionId
            Handler = $handler
            CreatedAt = [DateTime]::Now
            ExecutionCount = 0
        }
        
        # Add to handlers (thread-safe)
        $handlers = $this._handlers.GetOrAdd($eventName, [List[hashtable]]::new())
        $handlers.Add($subscription)
        
        $this._logger.Debug("EventManager", "On", "Event subscription created", @{
            EventName = $eventName
            SubscriptionId = $subscriptionId
            TotalHandlers = $handlers.Count
        })
        
        return $subscriptionId
    }
    
    <#
    .SYNOPSIS
    Unsubscribe from an event (simple, clear method name)
    
    .PARAMETER eventName
    Name of the event to unsubscribe from
    
    .PARAMETER subscriptionId
    Subscription ID returned from On() method
    
    .EXAMPLE
    $id = $events.On("test.event") { }
    $events.Off("test.event", $id)
    #>
    [void] Off([string]$eventName, [string]$subscriptionId) {
        if ([string]::IsNullOrWhiteSpace($eventName)) {
            return  # Silently ignore invalid event names
        }
        if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
            return  # Silently ignore invalid subscription IDs
        }
        
        if ($this._handlers.ContainsKey($eventName)) {
            $handlers = $this._handlers[$eventName]
            $toRemove = $handlers | Where-Object { $_.Id -eq $subscriptionId }
            
            if ($toRemove) {
                $handlers.Remove($toRemove)
                
                # Clean up empty event entries
                if ($handlers.Count -eq 0) {
                    $this._handlers.TryRemove($eventName, [ref]$null)
                }
                
                $this._logger.Debug("EventManager", "Off", "Event subscription removed", @{
                    EventName = $eventName
                    SubscriptionId = $subscriptionId
                })
            }
        }
    }
    
    <#
    .SYNOPSIS
    Remove all subscriptions for an event
    
    .PARAMETER eventName
    Name of the event to clear all subscriptions for
    
    .EXAMPLE
    $events.OffAll("button.clicked")  # Remove all button click handlers
    #>
    [void] OffAll([string]$eventName) {
        if ([string]::IsNullOrWhiteSpace($eventName)) {
            return
        }
        
        if ($this._handlers.ContainsKey($eventName)) {
            $handlerCount = $this._handlers[$eventName].Count
            $this._handlers.TryRemove($eventName, [ref]$null)
            
            $this._logger.Debug("EventManager", "OffAll", "All subscriptions removed", @{
                EventName = $eventName
                RemovedHandlers = $handlerCount
            })
        }
    }
    
    <#
    .SYNOPSIS
    Fire an event to all subscribers (simple, clear method name)
    
    .PARAMETER eventName
    Name of the event to fire
    
    .PARAMETER data
    Optional data to send with the event (can be hashtable, object, or simple value)
    
    .PARAMETER source
    Optional source identifier for debugging
    
    .EXAMPLE
    # Simple event
    $events.Fire("button.clicked")
    
    # Event with data
    $events.Fire("user.login", @{ Username = "john"; LoginTime = (Get-Date) })
    
    # Event with source
    $events.Fire("error.occurred", "Database connection failed", "DatabaseService")
    #>
    [void] Fire([string]$eventName, [object]$data = $null, [string]$source = "") {
        if ([string]::IsNullOrWhiteSpace($eventName)) {
            $this._logger.Warn("EventManager", "Fire", "Attempted to fire event with null/empty name")
            return
        }
        
        # Create event data
        $eventData = [EventData]::new($eventName, $data, $source)
        
        # Add to history if enabled
        if ($this.EnableHistory) {
            $this._eventHistory.Add($eventData)
            
            # Maintain history size limit
            while ($this._eventHistory.Count -gt $this.MaxHistorySize) {
                $this._eventHistory.RemoveAt(0)
            }
        }
        
        # Update stats
        $this._stats.EventsFired++
        
        # Get handlers for this event
        if (-not $this._handlers.ContainsKey($eventName)) {
            $this._logger.Trace("EventManager", "Fire", "No handlers for event", @{
                EventName = $eventName
            })
            return
        }
        
        $handlers = $this._handlers[$eventName]
        $handlersExecuted = 0
        $errorsOccurred = 0
        
        $this._logger.Trace("EventManager", "Fire", "Firing event to handlers", @{
            EventName = $eventName
            HandlerCount = $handlers.Count
            HasData = $null -ne $data
            Source = $source
        })
        
        # Execute all handlers
        foreach ($handlerInfo in $handlers) {
            try {
                & $handlerInfo.Handler $eventData
                $handlerInfo.ExecutionCount++
                $handlersExecuted++
                $this._stats.HandlersExecuted++
                
            } catch {
                $errorsOccurred++
                $this._stats.ErrorsOccurred++
                
                $this._logger.Error("EventManager", "Fire", "Event handler error", @{
                    EventName = $eventName
                    SubscriptionId = $handlerInfo.Id
                    Exception = $_.Exception.Message
                    StackTrace = $_.ScriptStackTrace
                })
                
                # Continue executing other handlers even if one fails
            }
        }
        
        $this._logger.Debug("EventManager", "Fire", "Event fired", @{
            EventName = $eventName
            HandlersExecuted = $handlersExecuted
            ErrorsOccurred = $errorsOccurred
        })
    }
    
    <#
    .SYNOPSIS
    Check if any handlers are registered for an event
    
    .PARAMETER eventName
    Event name to check
    
    .OUTPUTS
    True if handlers exist, false otherwise
    
    .EXAMPLE
    if ($events.HasHandlers("data.changed")) {
        Write-Host "Data change handlers are registered"
    }
    #>
    [bool] HasHandlers([string]$eventName) {
        if ([string]::IsNullOrWhiteSpace($eventName)) {
            return $false
        }
        
        return $this._handlers.ContainsKey($eventName) -and $this._handlers[$eventName].Count -gt 0
    }
    
    <#
    .SYNOPSIS
    Get list of all events that have handlers
    
    .OUTPUTS
    Array of event names
    
    .EXAMPLE
    $eventNames = $events.GetEventNames()
    Write-Host "Registered events: $($eventNames -join ', ')"
    #>
    [string[]] GetEventNames() {
        return $this._handlers.Keys | Sort-Object
    }
    
    <#
    .SYNOPSIS
    Get number of handlers for a specific event
    
    .PARAMETER eventName
    Event name to check
    
    .OUTPUTS
    Number of handlers registered for the event
    
    .EXAMPLE
    $count = $events.GetHandlerCount("button.clicked")
    Write-Host "Button click handlers: $count"
    #>
    [int] GetHandlerCount([string]$eventName) {
        if ([string]::IsNullOrWhiteSpace($eventName) -or -not $this._handlers.ContainsKey($eventName)) {
            return 0
        }
        
        return $this._handlers[$eventName].Count
    }
    
    <#
    .SYNOPSIS
    Get event history (if history is enabled)
    
    .PARAMETER count
    Maximum number of recent events to return (default: all)
    
    .OUTPUTS
    Array of EventData objects
    
    .EXAMPLE
    $events.EnableHistory = $true
    $recentEvents = $events.GetEventHistory(10)
    foreach ($event in $recentEvents) {
        Write-Host $event.ToString()
    }
    #>
    [EventData[]] GetEventHistory([int]$count = -1) {
        if (-not $this.EnableHistory) {
            return @()
        }
        
        if ($count -le 0 -or $count -gt $this._eventHistory.Count) {
            return $this._eventHistory.ToArray()
        }
        
        $startIndex = [Math]::Max(0, $this._eventHistory.Count - $count)
        return $this._eventHistory.GetRange($startIndex, $count).ToArray()
    }
    
    <#
    .SYNOPSIS
    Get performance statistics
    
    .OUTPUTS
    Hashtable with performance information
    
    .EXAMPLE
    $stats = $events.GetStats()
    Write-Host "Events fired: $($stats.EventsFired)"
    Write-Host "Handlers executed: $($stats.HandlersExecuted)"
    #>
    [hashtable] GetStats() {
        return @{
            EventsFired = $this._stats.EventsFired
            HandlersExecuted = $this._stats.HandlersExecuted
            ErrorsOccurred = $this._stats.ErrorsOccurred
            RegisteredEvents = $this._handlers.Count
            TotalHandlers = ($this._handlers.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
            HistoryEnabled = $this.EnableHistory
            HistorySize = $this._eventHistory.Count
        }
    }
    
    <#
    .SYNOPSIS
    Clear all event handlers and history
    
    .EXAMPLE
    $events.Clear()  # Remove all subscriptions and clear history
    #>
    [void] Clear() {
        $handlerCount = ($this._handlers.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        $eventCount = $this._handlers.Count
        
        $this._handlers.Clear()
        $this._eventHistory.Clear()
        
        # Reset stats
        $this._stats.EventsFired = 0
        $this._stats.HandlersExecuted = 0
        $this._stats.ErrorsOccurred = 0
        
        $this._logger.Info("EventManager", "Clear", "All events and handlers cleared", @{
            ClearedEvents = $eventCount
            ClearedHandlers = $handlerCount
        })
    }
    
    <#
    .SYNOPSIS
    Enable debug mode for detailed event logging
    
    .PARAMETER enabled
    True to enable debug logging
    
    .EXAMPLE
    $events.SetDebugMode($true)   # Enable detailed logging
    $events.SetDebugMode($false)  # Disable detailed logging
    #>
    [void] SetDebugMode([bool]$enabled) {
        if ($enabled) {
            $this.EnableHistory = $true
            $this._logger.Info("EventManager", "SetDebugMode", "Debug mode enabled")
        } else {
            $this.EnableHistory = $false
            $this._eventHistory.Clear()
            $this._logger.Info("EventManager", "SetDebugMode", "Debug mode disabled")
        }
    }
}

# Global instance for easy access throughout SpeedTUI
$global:SpeedTUIEventManager = $null

<#
.SYNOPSIS
Get the global SpeedTUI event manager instance

.OUTPUTS
EventManager instance

.EXAMPLE
$events = Get-EventManager
$events.On("test.event") { Write-Host "Test event fired!" }
$events.Fire("test.event")
#>
function Get-EventManager {
    if (-not $global:SpeedTUIEventManager) {
        $global:SpeedTUIEventManager = [EventManager]::new()
    }
    return $global:SpeedTUIEventManager
}

<#
.SYNOPSIS
Quick helper to subscribe to an event using the global event manager

.PARAMETER EventName
Name of the event to listen for

.PARAMETER Handler
Scriptblock to execute when event fires

.OUTPUTS
Subscription ID for later unsubscription

.EXAMPLE
$id = Subscribe-Event "button.clicked" { param($e) 
    Write-Host "Button $($e.Get('ButtonId')) clicked!"
}
#>
function Subscribe-Event {
    param(
        [string]$EventName,
        [scriptblock]$Handler
    )
    
    $eventManager = Get-EventManager
    return $eventManager.On($EventName, $Handler)
}

<#
.SYNOPSIS
Quick helper to unsubscribe from an event using the global event manager

.PARAMETER EventName
Name of the event to unsubscribe from

.PARAMETER SubscriptionId
Subscription ID returned from Subscribe-Event

.EXAMPLE
$id = Subscribe-Event "test.event" { }
Unsubscribe-Event "test.event" $id
#>
function Unsubscribe-Event {
    param(
        [string]$EventName,
        [string]$SubscriptionId
    )
    
    $eventManager = Get-EventManager
    $eventManager.Off($EventName, $SubscriptionId)
}

<#
.SYNOPSIS
Quick helper to fire an event using the global event manager

.PARAMETER EventName
Name of the event to fire

.PARAMETER Data
Optional data to send with the event

.PARAMETER Source
Optional source identifier

.EXAMPLE
Fire-Event "user.login" @{ Username = "john"; Time = (Get-Date) }
#>
function Fire-Event {
    param(
        [string]$EventName,
        [object]$Data = $null,
        [string]$Source = ""
    )
    
    $eventManager = Get-EventManager
    $eventManager.Fire($EventName, $Data, $Source)
}

# Initialize the global event manager
$global:SpeedTUIEventManager = [EventManager]::new()

Export-ModuleMember -Function Get-EventManager, Subscribe-Event, Unsubscribe-Event, Fire-Event