# SpeedTUI Null Check Utilities - Defensive programming helpers

class Guard {
    static hidden [object]$_logger = $null
    
    static [object] GetLogger() {
        if ($null -eq [Guard]::_logger) {
            [Guard]::_logger = Get-Logger
        }
        return [Guard]::_logger
    }
    # Throw if null with detailed context
    static [void] NotNull([object]$value, [string]$paramName) {
        $logger = [Guard]::GetLogger()
        $logger.Trace("Guard", "NotNull", "Validating parameter", @{
            ParamName = $paramName
            IsNull = $null -eq $value
        })
        
        if ($null -eq $value) {
            $caller = (Get-PSCallStack)[1]
            $errorMsg = "Parameter '$paramName' cannot be null. Called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
            
            $logger.Error("Guard", "NotNull", "Null parameter validation failed", @{
                ParamName = $paramName
                Caller = $caller.Command
                LineNumber = $caller.ScriptLineNumber
            })
            
            throw [System.ArgumentNullException]::new($paramName, $errorMsg)
        }
        
        $logger.Trace("Guard", "NotNull", "Parameter validation passed")
    }
    
    # Throw if null or empty string
    static [void] NotNullOrEmpty([string]$value, [string]$paramName) {
        $logger = [Guard]::GetLogger()
        $logger.Trace("Guard", "NotNullOrEmpty", "Validating string parameter", @{
            ParamName = $paramName
            IsNullOrEmpty = [string]::IsNullOrEmpty($value)
        })
        
        if ([string]::IsNullOrEmpty($value)) {
            $caller = (Get-PSCallStack)[1]
            $errorMsg = "Parameter '$paramName' cannot be null or empty. Called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
            
            $logger.Error("Guard", "NotNullOrEmpty", "String validation failed", @{
                ParamName = $paramName
                Caller = $caller.Command
                LineNumber = $caller.ScriptLineNumber
            })
            
            throw [System.ArgumentException]::new($errorMsg, $paramName)
        }
        
        $logger.Trace("Guard", "NotNullOrEmpty", "String validation passed")
    }
    
    # Throw if null or whitespace
    static [void] NotNullOrWhiteSpace([string]$value, [string]$paramName) {
        $logger = [Guard]::GetLogger()
        $logger.Trace("Guard", "NotNullOrWhiteSpace", "Validating whitespace parameter", @{
            ParamName = $paramName
            IsNullOrWhiteSpace = [string]::IsNullOrWhiteSpace($value)
        })
        
        if ([string]::IsNullOrWhiteSpace($value)) {
            $caller = (Get-PSCallStack)[1]
            $errorMsg = "Parameter '$paramName' cannot be null, empty, or whitespace. Called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
            
            $logger.Error("Guard", "NotNullOrWhiteSpace", "Whitespace validation failed", @{
                ParamName = $paramName
                Caller = $caller.Command
                LineNumber = $caller.ScriptLineNumber
            })
            
            throw [System.ArgumentException]::new($errorMsg, $paramName)
        }
        
        $logger.Trace("Guard", "NotNullOrWhiteSpace", "Whitespace validation passed")
    }
    
    # Validate array not null or empty
    static [void] NotNullOrEmptyArray([array]$value, [string]$paramName) {
        $logger = [Guard]::GetLogger()
        $isNullOrEmpty = $null -eq $value -or $value.Count -eq 0
        
        $logger.Trace("Guard", "NotNullOrEmptyArray", "Validating array parameter", @{
            ParamName = $paramName
            IsNull = $null -eq $value
            Count = $(if ($null -ne $value) { $value.Count } else { 0 })
            IsNullOrEmpty = $isNullOrEmpty
        })
        
        if ($isNullOrEmpty) {
            $caller = (Get-PSCallStack)[1]
            $errorMsg = "Parameter '$paramName' cannot be null or empty array. Called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
            
            $logger.Error("Guard", "NotNullOrEmptyArray", "Array validation failed", @{
                ParamName = $paramName
                Caller = $caller.Command
                LineNumber = $caller.ScriptLineNumber
            })
            
            throw [System.ArgumentException]::new($errorMsg, $paramName)
        }
        
        $logger.Trace("Guard", "NotNullOrEmptyArray", "Array validation passed")
    }
    
    # Validate numeric range
    static [void] InRange([int]$value, [int]$min, [int]$max, [string]$paramName) {
        $logger = [Guard]::GetLogger()
        $inRange = $value -ge $min -and $value -le $max
        
        $logger.Trace("Guard", "InRange", "Validating range parameter", @{
            ParamName = $paramName
            Value = $value
            Min = $min
            Max = $max
            InRange = $inRange
        })
        
        if (-not $inRange) {
            $caller = (Get-PSCallStack)[1]
            $errorMsg = "Parameter '$paramName' must be between $min and $max. Got: $value. Called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
            
            $logger.Error("Guard", "InRange", "Range validation failed", @{
                ParamName = $paramName
                Value = $value
                Min = $min
                Max = $max
                Caller = $caller.Command
                LineNumber = $caller.ScriptLineNumber
            })
            
            throw [System.ArgumentOutOfRangeException]::new($paramName, $value, $errorMsg)
        }
        
        $logger.Trace("Guard", "InRange", "Range validation passed")
    }
    
    # Validate positive number
    static [void] Positive([int]$value, [string]$paramName) {
        $logger = [Guard]::GetLogger()
        $isPositive = $value -gt 0
        
        $logger.Trace("Guard", "Positive", "Validating positive parameter", @{
            ParamName = $paramName
            Value = $value
            IsPositive = $isPositive
        })
        
        if (-not $isPositive) {
            $caller = (Get-PSCallStack)[1]
            $errorMsg = "Parameter '$paramName' must be positive. Got: $value. Called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
            
            $logger.Error("Guard", "Positive", "Positive validation failed", @{
                ParamName = $paramName
                Value = $value
                Caller = $caller.Command
                LineNumber = $caller.ScriptLineNumber
            })
            
            throw [System.ArgumentOutOfRangeException]::new($paramName, $value, $errorMsg)
        }
        
        $logger.Trace("Guard", "Positive", "Positive validation passed")
    }
    
    # Validate non-negative number
    static [void] NonNegative([int]$value, [string]$paramName) {
        $logger = [Guard]::GetLogger()
        $isNonNegative = $value -ge 0
        
        $logger.Trace("Guard", "NonNegative", "Validating non-negative parameter", @{
            ParamName = $paramName
            Value = $value
            IsNonNegative = $isNonNegative
        })
        
        if (-not $isNonNegative) {
            $caller = (Get-PSCallStack)[1]
            $errorMsg = "Parameter '$paramName' must be non-negative. Got: $value. Called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
            
            $logger.Error("Guard", "NonNegative", "Non-negative validation failed", @{
                ParamName = $paramName
                Value = $value
                Caller = $caller.Command
                LineNumber = $caller.ScriptLineNumber
            })
            
            throw [System.ArgumentOutOfRangeException]::new($paramName, $value, $errorMsg)
        }
        
        $logger.Trace("Guard", "NonNegative", "Non-negative validation passed")
    }
    
    # Type validation
    static [void] IsType([object]$value, [Type]$expectedType, [string]$paramName) {
        $logger = [Guard]::GetLogger()
        
        $logger.Trace("Guard", "IsType", "Validating type parameter", @{
            ParamName = $paramName
            ExpectedType = $expectedType.Name
            ActualType = $(if ($null -ne $value) { $value.GetType().Name } else { "null" })
        })
        
        try {
            if ($null -eq $value) {
                [Guard]::NotNull($value, $paramName)
            }
            
            $actualType = $value.GetType()
            $isCorrectType = $actualType -eq $expectedType -or $actualType.IsSubclassOf($expectedType)
            
            if (-not $isCorrectType) {
                $caller = (Get-PSCallStack)[1]
                $errorMsg = "Parameter '$paramName' must be of type '$($expectedType.Name)'. Got: '$($actualType.Name)'. Called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
                
                $logger.Error("Guard", "IsType", "Type validation failed", @{
                    ParamName = $paramName
                    ExpectedType = $expectedType.Name
                    ActualType = $actualType.Name
                    Caller = $caller.Command
                    LineNumber = $caller.ScriptLineNumber
                })
                
                throw [System.ArgumentException]::new($errorMsg, $paramName)
            }
            
            $logger.Trace("Guard", "IsType", "Type validation passed")
        } catch {
            $logger.Error("Guard", "IsType", "Type validation error", @{
                ParamName = $paramName
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    # Collection contains validation
    static [void] Contains([System.Collections.IEnumerable]$collection, [object]$item, [string]$message) {
        $logger = [Guard]::GetLogger()
        
        $logger.Trace("Guard", "Contains", "Validating collection contains item", @{
            HasCollection = $null -ne $collection
            Item = $(if ($null -ne $item) { $item.ToString() } else { "null" })
            Message = $message
        })
        
        try {
            [Guard]::NotNull($collection, "collection")
            
            $found = $false
            $elementCount = 0
            foreach ($element in $collection) {
                $elementCount++
                if ($element -eq $item) {
                    $found = $true
                    $logger.Debug("Guard", "Contains", "Item found in collection", @{
                        Item = $item
                        Position = $elementCount
                    })
                    break
                }
            }
            
            if (-not $found) {
                $caller = (Get-PSCallStack)[1]
                $msg = $(if ($message) { $message } else { "Collection does not contain required item: $item" })
                $errorMsg = "$msg. Called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
                
                $logger.Error("Guard", "Contains", "Collection validation failed", @{
                    Item = $item
                    CollectionSize = $elementCount
                    Message = $message
                    Caller = $caller.Command
                    LineNumber = $caller.ScriptLineNumber
                })
                
                throw [System.ArgumentException]::new($errorMsg)
            }
            
            $logger.Trace("Guard", "Contains", "Collection validation passed")
        } catch {
            $logger.Error("Guard", "Contains", "Collection validation error", @{
                Exception = $_.Exception.Message
            })
            throw
        }
    }
    
    # Custom condition validation
    static [void] Condition([bool]$condition, [string]$message) {
        $logger = [Guard]::GetLogger()
        
        $logger.Trace("Guard", "Condition", "Validating custom condition", @{
            Condition = $condition
            Message = $message
        })
        
        if (-not $condition) {
            $caller = (Get-PSCallStack)[1]
            $errorMsg = "$message. Called from: $($caller.Command) at line $($caller.ScriptLineNumber)"
            
            $logger.Error("Guard", "Condition", "Condition validation failed", @{
                Condition = $condition
                Message = $message
                Caller = $caller.Command
                LineNumber = $caller.ScriptLineNumber
            })
            
            throw [System.InvalidOperationException]::new($errorMsg)
        }
        
        $logger.Trace("Guard", "Condition", "Condition validation passed")
    }
}

# Safe navigation helpers
class Safe {
    static hidden [object]$_logger = $null
    
    static [object] GetLogger() {
        if ($null -eq [Safe]::_logger) {
            [Safe]::_logger = Get-Logger
        }
        return [Safe]::_logger
    }
    # Get property value safely
    static [object] GetProperty([object]$obj, [string]$propertyName, [object]$defaultValue) {
        $logger = [Safe]::GetLogger()
        
        $logger.Trace("Safe", "GetProperty", "Getting property safely", @{
            HasObject = $null -ne $obj
            ObjectType = $(if ($null -ne $obj) { $obj.GetType().Name } else { "null" })
            PropertyName = $propertyName
            HasDefaultValue = $null -ne $defaultValue
        })
        
        try {
            if ($null -eq $obj) { 
                $logger.Debug("Safe", "GetProperty", "Object is null, returning default")
                return $defaultValue 
            }
            if ([string]::IsNullOrEmpty($propertyName)) { 
                $logger.Debug("Safe", "GetProperty", "Property name is null/empty, returning default")
                return $defaultValue 
            }
            
            $value = $obj.$propertyName
            $result = $(if ($null -ne $value) { $value } else { $defaultValue })
            
            $logger.Debug("Safe", "GetProperty", "Property retrieved successfully", @{
                PropertyName = $propertyName
                HasValue = $null -ne $value
                UsingDefault = $null -eq $value
            })
            
            return $result
        } catch {
            $logger.Warn("Safe", "GetProperty", "Failed to get property, returning default", @{
                PropertyName = $propertyName
                Exception = $_.Exception.Message
            })
            return $defaultValue
        }
    }
    
    # Invoke method safely
    static [object] InvokeMethod([object]$obj, [string]$methodName, [object[]]$args) {
        $logger = [Safe]::GetLogger()
        
        $logger.Trace("Safe", "InvokeMethod", "Invoking method safely", @{
            HasObject = $null -ne $obj
            ObjectType = $(if ($null -ne $obj) { $obj.GetType().Name } else { "null" })
            MethodName = $methodName
            ArgCount = $(if ($null -ne $args) { $args.Count } else { 0 })
        })
        
        try {
            if ($null -eq $obj) { 
                $logger.Debug("Safe", "InvokeMethod", "Object is null, returning null")
                return $null 
            }
            if ([string]::IsNullOrEmpty($methodName)) { 
                $logger.Debug("Safe", "InvokeMethod", "Method name is null/empty, returning null")
                return $null 
            }
            
            $result = $obj.$methodName.Invoke($args)
            
            $logger.Debug("Safe", "InvokeMethod", "Method invoked successfully", @{
                MethodName = $methodName
                HasResult = $null -ne $result
            })
            
            return $result
        } catch {
            $logger.Error("Safe", "InvokeMethod", "Failed to invoke method '$methodName'", @{
                ObjectType = $(if ($null -ne $obj) { $obj.GetType().Name } else { "null" })
                Method = $methodName
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            return $null
        }
    }
    
    # Execute scriptblock safely
    static [object] Execute([scriptblock]$scriptBlock, [object]$defaultValue) {
        $logger = [Safe]::GetLogger()
        
        $logger.Trace("Safe", "Execute", "Executing scriptblock safely", @{
            HasScriptBlock = $null -ne $scriptBlock
            HasDefaultValue = $null -ne $defaultValue
        })
        
        try {
            if ($null -eq $scriptBlock) { 
                $logger.Debug("Safe", "Execute", "ScriptBlock is null, returning default")
                return $defaultValue 
            }
            
            $result = & $scriptBlock
            $finalResult = $(if ($null -ne $result) { $result } else { $defaultValue })
            
            $logger.Debug("Safe", "Execute", "ScriptBlock executed successfully", @{
                HasResult = $null -ne $result
                UsingDefault = $null -eq $result
            })
            
            return $finalResult
        } catch {
            $logger.Error("Safe", "Execute", "Failed to execute scriptblock", @{
                Exception = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
            })
            return $defaultValue
        }
    }
    
    # Try parse with default
    static [int] ParseInt([string]$value, [int]$defaultValue) {
        $logger = [Safe]::GetLogger()
        
        $logger.Trace("Safe", "ParseInt", "Parsing integer safely", @{
            Value = $value
            DefaultValue = $defaultValue
            IsNullOrWhiteSpace = [string]::IsNullOrWhiteSpace($value)
        })
        
        try {
            if ([string]::IsNullOrWhiteSpace($value)) { 
                $logger.Debug("Safe", "ParseInt", "Value is null/whitespace, returning default")
                return $defaultValue 
            }
            
            $result = 0
            if ([int]::TryParse($value, [ref]$result)) {
                $logger.Debug("Safe", "ParseInt", "Parse successful", @{
                    Value = $value
                    Result = $result
                })
                return $result
            }
            
            $logger.Debug("Safe", "ParseInt", "Parse failed, returning default", @{
                Value = $value
                DefaultValue = $defaultValue
            })
            return $defaultValue
        } catch {
            $logger.Error("Safe", "ParseInt", "Parse operation failed", @{
                Value = $value
                Exception = $_.Exception.Message
            })
            return $defaultValue
        }
    }
    
    # Safe array access
    static [object] GetArrayElement([array]$array, [int]$index, [object]$defaultValue) {
        $logger = [Safe]::GetLogger()
        
        $logger.Trace("Safe", "GetArrayElement", "Getting array element safely", @{
            HasArray = $null -ne $array
            ArrayCount = $(if ($null -ne $array) { $array.Count } else { 0 })
            Index = $index
            HasDefaultValue = $null -ne $defaultValue
        })
        
        try {
            $isValidAccess = $null -ne $array -and $index -ge 0 -and $index -lt $array.Count
            
            if (-not $isValidAccess) {
                $logger.Debug("Safe", "GetArrayElement", "Invalid array access, returning default", @{
                    HasArray = $null -ne $array
                    Index = $index
                    ArrayCount = $(if ($null -ne $array) { $array.Count } else { 0 })
                    Reason = $(if ($null -eq $array) { "ArrayIsNull" } elseif ($index -lt 0) { "IndexNegative" } else { "IndexOutOfBounds" })
                })
                return $defaultValue
            }
            
            $result = $array[$index]
            
            $logger.Debug("Safe", "GetArrayElement", "Array element retrieved successfully", @{
                Index = $index
                HasResult = $null -ne $result
            })
            
            return $result
        } catch {
            $logger.Error("Safe", "GetArrayElement", "Array access failed", @{
                Index = $index
                Exception = $_.Exception.Message
            })
            return $defaultValue
        }
    }
    
    # Safe dictionary access
    static [object] GetDictionaryValue([hashtable]$dict, [string]$key, [object]$defaultValue) {
        $logger = [Safe]::GetLogger()
        
        $logger.Trace("Safe", "GetDictionaryValue", "Getting dictionary value safely", @{
            HasDict = $null -ne $dict
            DictCount = $(if ($null -ne $dict) { $dict.Count } else { 0 })
            Key = $key
            HasDefaultValue = $null -ne $defaultValue
        })
        
        try {
            if ($null -eq $dict -or [string]::IsNullOrEmpty($key)) {
                $logger.Debug("Safe", "GetDictionaryValue", "Invalid dictionary access, returning default", @{
                    HasDict = $null -ne $dict
                    Key = $key
                    Reason = $(if ($null -eq $dict) { "DictIsNull" } else { "KeyNullOrEmpty" })
                })
                return $defaultValue
            }
            
            if ($dict.ContainsKey($key)) {
                $result = $dict[$key]
                
                $logger.Debug("Safe", "GetDictionaryValue", "Dictionary value found", @{
                    Key = $key
                    HasResult = $null -ne $result
                })
                
                return $result
            }
            
            $logger.Debug("Safe", "GetDictionaryValue", "Key not found, returning default", @{
                Key = $key
                DictKeys = ($dict.Keys -join ", ")
            })
            
            return $defaultValue
        } catch {
            $logger.Error("Safe", "GetDictionaryValue", "Dictionary access failed", @{
                Key = $key
                Exception = $_.Exception.Message
            })
            return $defaultValue
        }
    }
}

# Result type for operations that can fail
class Result {
    [bool]$Success
    [object]$Value
    [string]$Error
    hidden [object]$_logger
    
    hidden Result([bool]$success, [object]$value, [string]$error) {
        $this._logger = Get-Logger
        $this.Success = $success
        $this.Value = $value
        $this.Error = $error
        
        $this._logger.Trace("Result", "Constructor", "Result created", @{
            Success = $success
            HasValue = $null -ne $value
            HasError = -not [string]::IsNullOrEmpty($error)
        })
    }
    
    static [Result] Ok([object]$value) {
        $logger = Get-Logger
        $logger.Trace("Result", "Ok", "Creating success result", @{
            HasValue = $null -ne $value
            ValueType = $(if ($null -ne $value) { $value.GetType().Name } else { "null" })
        })
        
        return [Result]::new($true, $value, $null)
    }
    
    static [Result] Fail([string]$error) {
        $logger = Get-Logger
        $logger.Trace("Result", "Fail", "Creating failure result", @{
            Error = $error
            HasError = -not [string]::IsNullOrEmpty($error)
        })
        
        return [Result]::new($false, $null, $error)
    }
    
    [bool] IsOk() { 
        $this._logger.Trace("Result", "IsOk", "Checking if result is success", @{
            Success = $this.Success
        })
        return $this.Success 
    }
    
    [bool] IsFail() { 
        $this._logger.Trace("Result", "IsFail", "Checking if result is failure", @{
            Success = $this.Success
            IsFail = -not $this.Success
        })
        return -not $this.Success 
    }
}