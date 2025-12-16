# SpeedTUI InputField Component - Interactive text input with validation

. "$PSScriptRoot/../Core/Logger.ps1"

class InputField {
    [string]$Label
    [string]$Value = ""
    [string]$PlaceholderText = ""
    [int]$MaxLength = 100
    [bool]$IsActive = $false
    [bool]$IsPassword = $false
    [scriptblock]$Validator = $null
    [string]$ValidationError = ""
    [int]$CursorPosition = 0
    [string]$FieldType = "text" # text, number, date, etc.
    
    InputField([string]$label) {
        $this.Label = $label
    }
    
    InputField([string]$label, [string]$placeholder) {
        $this.Label = $label
        $this.PlaceholderText = $placeholder
    }
    
    [string] GetDisplayValue() {
        if ([string]::IsNullOrEmpty($this.Value)) {
            return $this.PlaceholderText
        }
        
        if ($this.IsPassword) {
            return "*" * $this.Value.Length
        }
        
        return $this.Value
    }
    
    [void] HandleInput([System.ConsoleKeyInfo]$keyInfo) {
        $logger = Get-Logger
        
        if (-not $this.IsActive) {
            $logger.Trace("SpeedTUI", "InputField", "HandleInput - Field not active", @{
                Label = $this.Label
            })
            return
        }
        
        $logger.Trace("SpeedTUI", "InputField", "HandleInput", @{
            Label = $this.Label
            Key = $keyInfo.Key.ToString()
            KeyChar = [int]$keyInfo.KeyChar
            CurrentValue = $this.Value
            CursorPos = $this.CursorPosition
        })
        
        switch ($keyInfo.Key) {
            ([System.ConsoleKey]::Backspace) {
                if ($this.CursorPosition -gt 0) {
                    $this.Value = $this.Value.Remove($this.CursorPosition - 1, 1)
                    $this.CursorPosition--
                    $this.Validate()
                }
            }
            ([System.ConsoleKey]::Delete) {
                if ($this.CursorPosition -lt $this.Value.Length) {
                    $this.Value = $this.Value.Remove($this.CursorPosition, 1)
                    $this.Validate()
                }
            }
            ([System.ConsoleKey]::LeftArrow) {
                if ($this.CursorPosition -gt 0) {
                    $this.CursorPosition--
                }
            }
            ([System.ConsoleKey]::RightArrow) {
                if ($this.CursorPosition -lt $this.Value.Length) {
                    $this.CursorPosition++
                }
            }
            ([System.ConsoleKey]::Home) {
                $this.CursorPosition = 0
            }
            ([System.ConsoleKey]::End) {
                $this.CursorPosition = $this.Value.Length
            }
            default {
                # Handle character input
                if ($keyInfo.KeyChar -and [char]::IsControl($keyInfo.KeyChar) -eq $false) {
                    if ($this.Value.Length -lt $this.MaxLength) {
                        $this.Value = $this.Value.Insert($this.CursorPosition, $keyInfo.KeyChar)
                        $this.CursorPosition++
                        $this.Validate()
                    }
                }
            }
        }
    }
    
    [void] SetValue([string]$value) {
        $this.Value = $value
        $this.CursorPosition = $value.Length
        $this.Validate()
    }
    
    [void] Clear() {
        $this.Value = ""
        $this.CursorPosition = 0
        $this.ValidationError = ""
    }
    
    [void] Activate() {
        $this.IsActive = $true
        $this.CursorPosition = $this.Value.Length
    }
    
    [void] Deactivate() {
        $this.IsActive = $false
    }
    
    [bool] Validate() {
        if ($null -eq $this.Validator) {
            $this.ValidationError = ""
            return $true
        }
        
        try {
            $result = & $this.Validator $this.Value
            if ($result -eq $true) {
                $this.ValidationError = ""
                return $true
            } else {
                $this.ValidationError = $(if ($result -is [string]) { $result } else { "Invalid value" })
                return $false
            }
        } catch {
            $this.ValidationError = $_.Exception.Message
            return $false
        }
    }
    
    [string] Render([int]$width) {
        $labelWidth = [Math]::Min($this.Label.Length + 2, [Math]::Floor($width * 0.3))
        $fieldWidth = $width - $labelWidth - 3
        
        $displayValue = $this.GetDisplayValue()
        if ($displayValue.Length -gt $fieldWidth - 2) {
            # Scroll the display to show cursor
            $start = [Math]::Max(0, $this.CursorPosition - $fieldWidth + 5)
            $displayValue = $displayValue.Substring($start, [Math]::Min($fieldWidth - 2, $displayValue.Length - $start))
        }
        
        $labelText = $this.Label.PadRight($labelWidth)
        $fieldText = $displayValue.PadRight($fieldWidth - 2)
        
        # Make active field very obvious
        if ($this.IsActive) {
            $fieldColor = "►["
            $fieldColorEnd = "]◄"
            $cursor = $(if ($this.CursorPosition -lt $displayValue.Length) { "│" } else { "_" })
            # Insert cursor at position
            if ($displayValue.Length -eq 0) {
                $fieldText = "_".PadRight($fieldWidth - 2)
            } else {
                $beforeCursor = $displayValue.Substring(0, [Math]::Min($this.CursorPosition, $displayValue.Length))
                $afterCursor = $(if ($this.CursorPosition -lt $displayValue.Length) { 
                    $displayValue.Substring($this.CursorPosition) 
                } else { 
                    "" 
                })
                $fieldText = ($beforeCursor + "_" + $afterCursor).PadRight($fieldWidth - 2)
            }
        } else {
            $fieldColor = " "
            $fieldColorEnd = " "
            $fieldText = $displayValue.PadRight($fieldWidth - 2)
        }
        
        $line = "$labelText$fieldColor$fieldText$fieldColorEnd"
        
        if (-not [string]::IsNullOrEmpty($this.ValidationError)) {
            $line += "`n" + (" " * $labelWidth) + "└─ " + $this.ValidationError
        }
        
        return $line
    }
}

# Common validators
class InputValidators {
    static [scriptblock] Required() {
        return {
            param($value)
            if ([string]::IsNullOrWhiteSpace($value)) {
                return "This field is required"
            }
            return $true
        }
    }
    
    static [scriptblock] Number() {
        return {
            param($value)
            if ([string]::IsNullOrWhiteSpace($value)) {
                return $true
            }
            if ($value -notmatch '^\d*\.?\d*$') {
                return "Must be a valid number"
            }
            return $true
        }
    }
    
    static [scriptblock] Date() {
        return {
            param($value)
            if ([string]::IsNullOrWhiteSpace($value)) {
                return $true
            }
            try {
                [DateTime]::Parse($value)
                return $true
            } catch {
                return "Must be a valid date (MM/dd/yyyy)"
            }
        }
    }
    
    static [scriptblock] MinLength([int]$min) {
        return {
            param($value)
            if ($value.Length -lt $min) {
                return "Must be at least $min characters"
            }
            return $true
        }.GetNewClosure()
    }
}