# SpeedTUI Data Store - Reactive data management with change notifications

using namespace System.Collections.Generic
using namespace System.ComponentModel

class DataChangeEventArgs : EventArgs {
    [string]$PropertyName
    [object]$OldValue
    [object]$NewValue
    [string]$Path
    hidden [object]$_logger
    
    DataChangeEventArgs([string]$propertyName, [object]$oldValue, [object]$newValue, [string]$path) {
        $this._logger = Get-Logger
        
        $this._logger.Trace("DataChangeEventArgs", "Constructor", "Creating data change event args", @{
            PropertyName = $propertyName
            HasOldValue = $null -ne $oldValue
            HasNewValue = $null -ne $newValue
            Path = $path
        })
        
        try {
            $this.PropertyName = $propertyName
            $this.OldValue = $oldValue
            $this.NewValue = $newValue
            $this.Path = $path
            
            $this._logger.Trace("DataChangeEventArgs", "Constructor", "Event args created successfully")
        } catch {
            $this._logger.Error("DataChangeEventArgs", "Constructor", "Failed to create event args", @{
                Exception = $_.Exception.Message
            })
            throw
        }
    }
}

class ObservableObject {
    hidden [Dictionary[string, object]]$_properties
    hidden [Dictionary[string, List[scriptblock]]]$_propertyWatchers
    hidden [object]$_logger
    
    # Property changed event (simplified)
    hidden [List[scriptblock]]$_propertyChangedHandlers
    
    ObservableObject() {
        $this._logger = Get-Logger
        
        $this._logger.Trace("ObservableObject", "Constructor", "Creating observable object")
        
        try {
            $this._properties = [Dictionary[string, object]]::new()
            $this._propertyWatchers = [Dictionary[string, List[scriptblock]]]::new()
            $this._propertyChangedHandlers = [List[scriptblock]]::new()
            
            $this._logger.Debug("ObservableObject", "Constructor", "Observable object created successfully")
        } catch {
            $this._logger.Error("ObservableObject", "Constructor", "Failed to create observable object", @{
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    # Get property value
    [object] Get([string]$propertyName) {
        $this._logger.Trace("ObservableObject", "Get", "Getting property value", @{
            PropertyName = $propertyName
        })
        
        try {
            [Guard]::NotNullOrEmpty($propertyName, "propertyName")
            
            if ($this._properties.ContainsKey($propertyName)) {
                $value = $this._properties[$propertyName]
                
                $this._logger.Trace("ObservableObject", "Get", "Property value retrieved", @{
                    PropertyName = $propertyName
                    HasValue = $null -ne $value
                    ValueType = $(if ($null -ne $value) { $value.GetType().Name } else { "null" })
                })
                
                return $value
            }
            
            $this._logger.Trace("ObservableObject", "Get", "Property not found, returning null", @{
                PropertyName = $propertyName
                AvailableProperties = ($this._properties.Keys -join ", ")
            })
            
            return $null
        } catch {
            $this._logger.Error("ObservableObject", "Get", "Failed to get property value", @{
                PropertyName = $propertyName
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    # Set property value
    [void] Set([string]$propertyName, [object]$value) {
        $this._logger.Trace("ObservableObject", "Set", "Setting property value", @{
            PropertyName = $propertyName
            HasValue = $null -ne $value
            ValueType = $(if ($null -ne $value) { $value.GetType().Name } else { "null" })
        })
        
        try {
            [Guard]::NotNullOrEmpty($propertyName, "propertyName")
            
            $oldValue = $this.Get($propertyName)
            
            # Check if value actually changed
            if ([object]::Equals($oldValue, $value)) {
                $this._logger.Trace("ObservableObject", "Set", "Value unchanged, skipping notification", @{
                    PropertyName = $propertyName
                })
                return
            }
            
            # Set new value
            $this._properties[$propertyName] = $value
            
            # Log change
            $this._logger.Debug("ObservableObject", "Set", "Property changed", @{
                Property = $propertyName
                OldValue = $oldValue
                NewValue = $value
                OldType = $(if ($null -ne $oldValue) { $oldValue.GetType().Name } else { "null" })
                NewType = $(if ($null -ne $value) { $value.GetType().Name } else { "null" })
            })
            
            # Notify property changed
            $this.OnPropertyChanged($propertyName, $oldValue, $value)
            
            $this._logger.Trace("ObservableObject", "Set", "Property set successfully")
        } catch {
            $this._logger.Error("ObservableObject", "Set", "Failed to set property value", @{
                PropertyName = $propertyName
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    # Watch for property changes
    [void] Watch([string]$propertyName, [scriptblock]$handler) {
        $this._logger.Trace("ObservableObject", "Watch", "Adding property watcher", @{
            PropertyName = $propertyName
            HasHandler = $null -ne $handler
        })
        
        try {
            [Guard]::NotNullOrEmpty($propertyName, "propertyName")
            [Guard]::NotNull($handler, "handler")
            
            if (-not $this._propertyWatchers.ContainsKey($propertyName)) {
                $this._propertyWatchers[$propertyName] = [List[scriptblock]]::new()
                $this._logger.Debug("ObservableObject", "Watch", "Created new watcher list", @{
                    PropertyName = $propertyName
                })
            }
            
            $this._propertyWatchers[$propertyName].Add($handler)
            
            $this._logger.Debug("ObservableObject", "Watch", "Watcher added successfully", @{
                Property = $propertyName
                WatcherCount = $this._propertyWatchers[$propertyName].Count
                TotalWatchedProperties = $this._propertyWatchers.Count
            })
        } catch {
            $this._logger.Error("ObservableObject", "Watch", "Failed to add watcher", @{
                PropertyName = $propertyName
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    # Remove watcher
    [void] Unwatch([string]$propertyName, [scriptblock]$handler) {
        $this._logger.Trace("ObservableObject", "Unwatch", "Removing property watcher", @{
            PropertyName = $propertyName
            HasHandler = $null -ne $handler
        })
        
        try {
            [Guard]::NotNullOrEmpty($propertyName, "propertyName")
            [Guard]::NotNull($handler, "handler")
            
            if ($this._propertyWatchers.ContainsKey($propertyName)) {
                $removed = $this._propertyWatchers[$propertyName].Remove($handler)
                
                $this._logger.Debug("ObservableObject", "Unwatch", "Watcher removal attempt", @{
                    PropertyName = $propertyName
                    WasRemoved = $removed
                    RemainingWatchers = $this._propertyWatchers[$propertyName].Count
                })
                
                # Clean up empty watcher lists
                if ($this._propertyWatchers[$propertyName].Count -eq 0) {
                    $this._propertyWatchers.Remove($propertyName)
                    $this._logger.Trace("ObservableObject", "Unwatch", "Removed empty watcher list")
                }
            } else {
                $this._logger.Warn("ObservableObject", "Unwatch", "No watchers found for property", @{
                    PropertyName = $propertyName
                    WatchedProperties = ($this._propertyWatchers.Keys -join ", ")
                })
            }
        } catch {
            $this._logger.Error("ObservableObject", "Unwatch", "Failed to remove watcher", @{
                PropertyName = $propertyName
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    # Property changed notification
    hidden [void] OnPropertyChanged([string]$propertyName, [object]$oldValue, [object]$newValue) {
        $this._logger.Trace("ObservableObject", "OnPropertyChanged", "Notifying property change", @{
            PropertyName = $propertyName
            PropertyWatchers = $(if ($this._propertyWatchers.ContainsKey($propertyName)) { $this._propertyWatchers[$propertyName].Count } else { 0 })
            GlobalHandlers = $this._propertyChangedHandlers.Count
        })
        
        try {
            $watchersNotified = 0
            $watchersFailed = 0
            
            # Notify watchers
            if ($this._propertyWatchers.ContainsKey($propertyName)) {
                foreach ($watcher in $this._propertyWatchers[$propertyName]) {
                    try {
                        & $watcher $propertyName $oldValue $newValue
                        $watchersNotified++
                    } catch {
                        $watchersFailed++
                        $this._logger.Error("ObservableObject", "OnPropertyChanged", "Watcher execution failed", @{
                            Property = $propertyName
                            Exception = $_.Exception.Message
                            StackTrace = $_.ScriptStackTrace
                        })
                    }
                }
            }
            
            $handlersNotified = 0
            $handlersFailed = 0
            
            # Raise PropertyChanged event
            foreach ($handler in $this._propertyChangedHandlers) {
                try {
                    & $handler $propertyName $oldValue $newValue
                    $handlersNotified++
                } catch {
                    $handlersFailed++
                    $this._logger.Error("ObservableObject", "OnPropertyChanged", "PropertyChanged handler execution failed", @{
                        Property = $propertyName
                        Exception = $_.Exception.Message
                        StackTrace = $_.ScriptStackTrace
                    })
                }
            }
            
            $this._logger.Debug("ObservableObject", "OnPropertyChanged", "Property change notification completed", @{
                PropertyName = $propertyName
                WatchersNotified = $watchersNotified
                WatchersFailed = $watchersFailed
                HandlersNotified = $handlersNotified
                HandlersFailed = $handlersFailed
            })
        } catch {
            $this._logger.Error("ObservableObject", "OnPropertyChanged", "Property change notification failed", @{
                PropertyName = $propertyName
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    # Get all property names
    [string[]] GetPropertyNames() {
        $this._logger.Trace("ObservableObject", "GetPropertyNames", "Getting all property names", @{
            PropertyCount = $this._properties.Count
        })
        
        try {
            $keys = $this._properties.Keys
            
            $this._logger.Trace("ObservableObject", "GetPropertyNames", "Property names retrieved", @{
                PropertyCount = $keys.Count
                PropertyNames = ($keys -join ", ")
            })
            
            return $keys
        } catch {
            $this._logger.Error("ObservableObject", "GetPropertyNames", "Failed to get property names", @{
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    # Check if property exists
    [bool] HasProperty([string]$propertyName) {
        $this._logger.Trace("ObservableObject", "HasProperty", "Checking if property exists", @{
            PropertyName = $propertyName
        })
        
        try {
            $exists = $this._properties.ContainsKey($propertyName)
            
            $this._logger.Trace("ObservableObject", "HasProperty", "Property existence check completed", @{
                PropertyName = $propertyName
                Exists = $exists
            })
            
            return $exists
        } catch {
            $this._logger.Error("ObservableObject", "HasProperty", "Failed to check property existence", @{
                PropertyName = $propertyName
                Exception = $_.Exception.Message
            })
            throw
        }
    }
}

class DataStore : ObservableObject {
    hidden [Dictionary[string, ObservableObject]]$_collections
    hidden [List[scriptblock]]$_globalWatchers
    hidden [string]$_name
    
    DataStore([string]$name) {
        $this._logger = Get-Logger
        
        $this._logger.Trace("DataStore", "Constructor", "Creating data store", @{
            Name = $name
        })
        
        try {
            [Guard]::NotNullOrEmpty($name, "name")
            
            $this._name = $name
            $this._collections = [Dictionary[string, ObservableObject]]::new()
            $this._globalWatchers = [List[scriptblock]]::new()
            
            $this._logger.Info("DataStore", "Constructor", "DataStore created successfully", @{
                Name = $name
            })
        } catch {
            $this._logger.Error("DataStore", "Constructor", "Failed to create data store", @{
                Name = $name
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    # Create or get a collection
    [ObservableObject] Collection([string]$name) {
        $this._logger.Trace("DataStore", "Collection", "Getting or creating collection", @{
            Store = $this._name
            CollectionName = $name
            ExistingCollections = $this._collections.Count
        })
        
        try {
            [Guard]::NotNullOrEmpty($name, "name")
            
            if (-not $this._collections.ContainsKey($name)) {
                $this._logger.Debug("DataStore", "Collection", "Creating new collection", @{
                    Store = $this._name
                    CollectionName = $name
                })
                
                $collection = [ObservableObject]::new()
                $this._collections[$name] = $collection
                
                # Set up collection watcher to propagate changes
                $store = $this
                $collection.Watch("*", {
                    param($prop, $old, $new)
                    $store.NotifyGlobalWatchers("$name.$prop", $old, $new)
                })
                
                $this._logger.Debug("DataStore", "Collection", "Collection created successfully", @{
                    Store = $this._name
                    Collection = $name
                    TotalCollections = $this._collections.Count
                })
            } else {
                $this._logger.Trace("DataStore", "Collection", "Returning existing collection", @{
                    Store = $this._name
                    CollectionName = $name
                })
            }
            
            return $this._collections[$name]
        } catch {
            $this._logger.Error("DataStore", "Collection", "Failed to get or create collection", @{
                Store = $this._name
                CollectionName = $name
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            throw
        }
    }
    
    # Get value using path notation (e.g., "users.currentUser.name")
    [object] GetPath([string]$path) {
        $this._logger.Trace("DataStore", "GetPath", "Getting value by path", @{
            Store = $this._name
            Path = $path
        })
        
        try {
            [Guard]::NotNullOrEmpty($path, "path")
            
            $parts = $path.Split('.')
            
            if ($parts.Count -eq 0) { 
                $this._logger.Warn("DataStore", "GetPath", "Empty path parts")
                return $null 
            }
            
            # Get collection
            $collection = $this.Collection($parts[0])
            
            if ($parts.Count -eq 1) {
                $this._logger.Trace("DataStore", "GetPath", "Returning collection directly")
                return $collection
            }
            
            # Navigate path
            $current = $collection
            for ($i = 1; $i -lt $parts.Count; $i++) {
                $propName = $parts[$i]
                $value = $current.Get($propName)
                
                if ($i -eq $parts.Count - 1) {
                    $this._logger.Debug("DataStore", "GetPath", "Path value retrieved", @{
                        Path = $path
                        HasValue = $null -ne $value
                        ValueType = $(if ($null -ne $value) { $value.GetType().Name } else { "null" })
                    })
                    return $value
                }
                
                if ($value -is [ObservableObject]) {
                    $current = $value
                } else {
                    $this._logger.Debug("DataStore", "GetPath", "Path navigation stopped - non-observable object", @{
                        Path = $path
                        StoppedAt = $propName
                    })
                    return $null
                }
            }
            
            return $null
        } catch {
            $this._logger.Error("DataStore", "GetPath", "Failed to get path value", @{
                Store = $this._name
                Path = $path
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    # Set value using path notation
    [void] SetPath([string]$path, [object]$value) {
        [Guard]::NotNullOrEmpty($path, "path")
        
        $parts = $path.Split('.')
        
        if ($parts.Count -eq 0) { return }
        
        # Get collection
        $collection = $this.Collection($parts[0])
        
        if ($parts.Count -eq 1) {
            throw [ArgumentException]::new("Cannot set collection directly")
        }
        
        # Navigate to parent
        $current = $collection
        for ($i = 1; $i -lt $parts.Count - 1; $i++) {
            $propName = $parts[$i]
            $obj = $current.Get($propName)
            
            if ($null -eq $obj) {
                # Create intermediate objects
                $obj = [ObservableObject]::new()
                $current.Set($propName, $obj)
            }
            
            if ($obj -is [ObservableObject]) {
                $current = $obj
            } else {
                throw [InvalidOperationException]::new("Cannot navigate through non-observable object at: $propName")
            }
        }
        
        # Set final property
        $finalProp = $parts[$parts.Count - 1]
        $current.Set($finalProp, $value)
        
        $this._logger.Debug("DataStore", "SetPath", "Value set via path", @{
            Store = $this._name
            Path = $path
            Value = $value
        })
    }
    
    # Watch for any changes in the store
    [void] WatchAll([scriptblock]$handler) {
        [Guard]::NotNull($handler, "handler")
        
        $this._globalWatchers.Add($handler)
        
        $this._logger.Debug("DataStore", "WatchAll", "Global watcher added", @{
            Store = $this._name
            WatcherCount = $this._globalWatchers.Count
        })
    }
    
    # Watch specific path
    [void] WatchPath([string]$path, [scriptblock]$handler) {
        [Guard]::NotNullOrEmpty($path, "path")
        [Guard]::NotNull($handler, "handler")
        
        $this.WatchAll({
            param($changedPath, $old, $new)
            if ($changedPath -eq $path -or $changedPath.StartsWith("$path.")) {
                & $handler $changedPath $old $new
            }
        })
    }
    
    # Notify global watchers
    hidden [void] NotifyGlobalWatchers([string]$path, [object]$oldValue, [object]$newValue) {
        foreach ($watcher in $this._globalWatchers) {
            try {
                & $watcher $path $oldValue $newValue
            } catch {
                $this._logger.Error("DataStore", "NotifyGlobalWatchers", "Global watcher failed", @{
                    Store = $this._name
                    Path = $path
                    Error = $_.Exception.Message
                })
            }
        }
    }
    
    # Create snapshot of store data
    [hashtable] CreateSnapshot() {
        $snapshot = @{}
        
        foreach ($kvp in $this._collections.GetEnumerator()) {
            $collectionData = @{}
            $collection = $kvp.Value
            
            foreach ($prop in $collection.GetPropertyNames()) {
                $collectionData[$prop] = $collection.Get($prop)
            }
            
            $snapshot[$kvp.Key] = $collectionData
        }
        
        return $snapshot
    }
    
    # Restore from snapshot
    [void] RestoreSnapshot([hashtable]$snapshot) {
        [Guard]::NotNull($snapshot, "snapshot")
        
        $this._logger.Info("DataStore", "RestoreSnapshot", "Restoring from snapshot", @{
            Store = $this._name
            Collections = $snapshot.Keys -join ", "
        })
        
        foreach ($kvp in $snapshot.GetEnumerator()) {
            $collection = $this.Collection($kvp.Key)
            $data = $kvp.Value
            
            if ($data -is [hashtable]) {
                foreach ($prop in $data.GetEnumerator()) {
                    $collection.Set($prop.Key, $prop.Value)
                }
            }
        }
    }
}

# Global data store manager
class DataStoreManager {
    static [Dictionary[string, DataStore]]$_stores = [Dictionary[string, DataStore]]::new()
    static [object]$_logger = [object]::GetInstance()
    
    static [DataStore] GetStore([string]$name) {
        [DataStoreManager]::_logger.Trace("DataStoreManager", "GetStore", "Getting data store", @{
            Name = $name
            ExistingStores = [DataStoreManager]::_stores.Count
        })
        
        try {
            [Guard]::NotNullOrEmpty($name, "name")
            
            if (-not [DataStoreManager]::_stores.ContainsKey($name)) {
                [DataStoreManager]::_logger.Debug("DataStoreManager", "GetStore", "Creating new store", @{
                    StoreName = $name
                })
                
                $store = [DataStore]::new($name)
                [DataStoreManager]::_stores[$name] = $store
                
                [DataStoreManager]::_logger.Info("DataStoreManager", "GetStore", "Store created successfully", @{
                    StoreName = $name
                    TotalStores = [DataStoreManager]::_stores.Count
                })
            } else {
                [DataStoreManager]::_logger.Trace("DataStoreManager", "GetStore", "Returning existing store")
            }
            
            return [DataStoreManager]::_stores[$name]
        } catch {
            [DataStoreManager]::_logger.Error("DataStoreManager", "GetStore", "Failed to get store", @{
                Name = $name
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    static [void] RemoveStore([string]$name) {
        [Guard]::NotNullOrEmpty($name, "name")
        
        if ([DataStoreManager]::_stores.Remove($name)) {
            [DataStoreManager]::_logger.Info("DataStoreManager", "RemoveStore", "Store removed", @{
                StoreName = $name
            })
        }
    }
    
    static [string[]] GetStoreNames() {
        return [DataStoreManager]::_stores.Keys
    }
}