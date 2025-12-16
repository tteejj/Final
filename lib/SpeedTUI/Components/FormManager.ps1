# SpeedTUI FormManager - Manages form input fields and navigation

. "$PSScriptRoot/InputField.ps1"
. "$PSScriptRoot/../Core/Logger.ps1"

class FormManager {
    [System.Collections.Generic.List[InputField]]$Fields
    [int]$CurrentFieldIndex = 0
    [bool]$IsActive = $false
    [hashtable]$FormData = @{}
    
    FormManager() {
        $this.Fields = [System.Collections.Generic.List[InputField]]::new()
    }
    
    [void] AddField([InputField]$field) {
        $this.Fields.Add($field)
    }
    
    [void] AddTextField([string]$label, [string]$placeholder = "") {
        $logger = Get-Logger
        $field = [InputField]::new($label, $placeholder)
        $this.Fields.Add($field)
        $logger.Debug("SpeedTUI", "FormManager", "Added text field", @{
            Label = $label
            Placeholder = $placeholder
            FieldCount = $this.Fields.Count
        })
    }
    
    [void] AddNumberField([string]$label, [string]$placeholder = "") {
        $field = [InputField]::new($label, $placeholder)
        $field.FieldType = "number"
        $field.Validator = [InputValidators]::Number()
        $this.Fields.Add($field)
    }
    
    [void] AddDateField([string]$label, [string]$placeholder = "MM/dd/yyyy") {
        $field = [InputField]::new($label, $placeholder)
        $field.FieldType = "date"
        $field.Validator = [InputValidators]::Date()
        $this.Fields.Add($field)
    }
    
    [void] Activate() {
        $logger = Get-Logger
        $this.IsActive = $true
        if ($this.Fields.Count -gt 0) {
            $this.Fields[0].Activate()
            $logger.Debug("SpeedTUI", "FormManager", "Form activated", @{
                FirstFieldLabel = $this.Fields[0].Label
                TotalFields = $this.Fields.Count
            })
        } else {
            $logger.Warn("SpeedTUI", "FormManager", "Form activated with no fields")
        }
    }
    
    [void] Deactivate() {
        $this.IsActive = $false
        foreach ($field in $this.Fields) {
            $field.Deactivate()
        }
    }
    
    [string] HandleInput([System.ConsoleKeyInfo]$keyInfo) {
        $logger = Get-Logger
        
        if (-not $this.IsActive -or $this.Fields.Count -eq 0) {
            $logger.Debug("SpeedTUI", "FormManager", "HandleInput - Form not active or no fields", @{
                IsActive = $this.IsActive
                FieldCount = $this.Fields.Count
            })
            return "CONTINUE"
        }
        
        $currentField = $this.Fields[$this.CurrentFieldIndex]
        
        $logger.Trace("SpeedTUI", "FormManager", "HandleInput", @{
            Key = $keyInfo.Key.ToString()
            CurrentFieldIndex = $this.CurrentFieldIndex
            CurrentFieldLabel = $currentField.Label
        })
        
        switch ($keyInfo.Key) {
            ([System.ConsoleKey]::Tab) {
                # Move to next field
                $currentField.Deactivate()
                
                if ($keyInfo.Modifiers -band [System.ConsoleModifiers]::Shift) {
                    # Shift+Tab - Previous field
                    $this.CurrentFieldIndex--
                    if ($this.CurrentFieldIndex -lt 0) {
                        $this.CurrentFieldIndex = $this.Fields.Count - 1
                    }
                } else {
                    # Tab - Next field
                    $this.CurrentFieldIndex++
                    if ($this.CurrentFieldIndex -ge $this.Fields.Count) {
                        $this.CurrentFieldIndex = 0
                    }
                }
                
                $this.Fields[$this.CurrentFieldIndex].Activate()
                return "REFRESH"
            }
            ([System.ConsoleKey]::DownArrow) {
                # Move to next field (same as Tab)
                $currentField.Deactivate()
                $this.CurrentFieldIndex++
                if ($this.CurrentFieldIndex -ge $this.Fields.Count) {
                    $this.CurrentFieldIndex = 0
                }
                $this.Fields[$this.CurrentFieldIndex].Activate()
                $logger.Debug("SpeedTUI", "FormManager", "Moved to next field via DownArrow", @{
                    NewFieldIndex = $this.CurrentFieldIndex
                    NewFieldLabel = $this.Fields[$this.CurrentFieldIndex].Label
                })
                return "REFRESH"
            }
            ([System.ConsoleKey]::UpArrow) {
                # Move to previous field (same as Shift+Tab)
                $currentField.Deactivate()
                $this.CurrentFieldIndex--
                if ($this.CurrentFieldIndex -lt 0) {
                    $this.CurrentFieldIndex = $this.Fields.Count - 1
                }
                $this.Fields[$this.CurrentFieldIndex].Activate()
                $logger.Debug("SpeedTUI", "FormManager", "Moved to previous field via UpArrow", @{
                    NewFieldIndex = $this.CurrentFieldIndex
                    NewFieldLabel = $this.Fields[$this.CurrentFieldIndex].Label
                })
                return "REFRESH"
            }
            ([System.ConsoleKey]::Enter) {
                # Submit form if all fields are valid
                $validationResult = $this.ValidateAll()
                $logger.Debug("SpeedTUI", "FormManager", "Form validation result", @{
                    IsValid = $validationResult
                    InvalidFields = ($this.Fields | Where-Object { -not [string]::IsNullOrEmpty($_.ValidationError) } | ForEach-Object { $_.Label }) -join ", "
                })
                
                if ($validationResult) {
                    $this.CollectFormData()
                    $logger.Debug("SpeedTUI", "FormManager", "Form submitted successfully")
                    return "SUBMIT"
                } else {
                    # Move to first invalid field
                    for ($i = 0; $i -lt $this.Fields.Count; $i++) {
                        if (-not [string]::IsNullOrEmpty($this.Fields[$i].ValidationError)) {
                            $currentField.Deactivate()
                            $this.CurrentFieldIndex = $i
                            $this.Fields[$i].Activate()
                            $logger.Debug("SpeedTUI", "FormManager", "Moved to first invalid field", @{
                                FieldLabel = $this.Fields[$i].Label
                                ValidationError = $this.Fields[$i].ValidationError
                            })
                            break
                        }
                    }
                    return "REFRESH"
                }
            }
            ([System.ConsoleKey]::Escape) {
                return "CANCEL"
            }
            default {
                # Pass input to current field
                $currentField.HandleInput($keyInfo)
                return "REFRESH"
            }
        }
        
        return "CONTINUE"
    }
    
    [bool] ValidateAll() {
        $allValid = $true
        foreach ($field in $this.Fields) {
            if (-not $field.Validate()) {
                $allValid = $false
            }
        }
        return $allValid
    }
    
    [void] CollectFormData() {
        $this.FormData.Clear()
        foreach ($field in $this.Fields) {
            $this.FormData[$field.Label] = $field.Value
        }
    }
    
    [hashtable] GetFormData() {
        $logger = Get-Logger
        # Always collect current data before returning
        $this.CollectFormData()
        $logger.Debug("SpeedTUI", "FormManager", "GetFormData", @{
            FieldCount = $this.FormData.Count
            Keys = ($this.FormData.Keys -join ", ")
        })
        return $this.FormData
    }
    
    [void] SetFieldValue([string]$label, [string]$value) {
        $field = $this.Fields | Where-Object { $_.Label -eq $label } | Select-Object -First 1
        if ($field) {
            $field.SetValue($value)
        }
    }
    
    [void] Clear() {
        foreach ($field in $this.Fields) {
            $field.Clear()
        }
        $this.FormData.Clear()
        $this.CurrentFieldIndex = 0
    }
    
    [string[]] Render([int]$width) {
        $lines = @()
        
        if ($null -eq $this.Fields -or $this.Fields.Count -eq 0) {
            $lines += "No fields configured"
            return $lines
        }
        
        for ($i = 0; $i -lt $this.Fields.Count; $i++) {
            $field = $this.Fields[$i]
            if ($null -eq $field) {
                continue
            }
            
            $isCurrentField = ($i -eq $this.CurrentFieldIndex)
            
            # Add field indicator
            $prefix = $(if ($isCurrentField) { "▶ " } else { "  " })
            
            try {
                $fieldLines = $field.Render([Math]::Max(20, $width - 2)) -split "`n"
                foreach ($line in $fieldLines) {
                    $lines += $prefix + $line
                    $prefix = "  " # Only first line gets the indicator
                }
            } catch {
                $lines += $prefix + "Error rendering field: $($_.Exception.Message)"
            }
        }
        
        return $lines
    }
    
    [void] LoadData([hashtable]$data) {
        foreach ($key in $data.Keys) {
            $this.SetFieldValue($key, $data[$key].ToString())
        }
    }
}