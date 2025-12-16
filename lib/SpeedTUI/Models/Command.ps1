# SpeedTUI Command Model - Command library with usage tracking

# Load BaseModel if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'BaseModel').Type) {
    . "$PSScriptRoot/BaseModel.ps1"
}

class Command : BaseModel {
    [string]$Title = ""
    [string]$Description = ""
    [string[]]$Tags = @()
    [string]$Group = ""
    [string]$CommandText = ""  # Required - the actual command
    [DateTime]$LastUsed
    [int]$UseCount = 0
    [string]$Category = ""
    [string]$Language = "PowerShell"  # PowerShell, Batch, Bash, etc.
    [bool]$IsTemplate = $false
    [hashtable]$Parameters = @{}
    [string]$Notes = ""
    
    Command() : base() {
        $this.LastUsed = [DateTime]::MinValue
    }
    
    Command([hashtable]$data) : base($data) {
        $this.Title = $(if ($data.Title) { $data.Title } else { "" })
        $this.Description = $(if ($data.Description) { $data.Description } else { "" })
        $this.Tags = $(if ($data.Tags) { $data.Tags } else { @() })
        $this.Group = $(if ($data.Group) { $data.Group } else { "" })
        $this.CommandText = $(if ($data.CommandText) { $data.CommandText } else { "" })
        $this.LastUsed = $(if ($data.LastUsed) { [DateTime]$data.LastUsed } else { [DateTime]::MinValue })
        $this.UseCount = $(if ($null -ne $data.UseCount) { [int]$data.UseCount } else { 0 })
        $this.Category = $(if ($data.Category) { $data.Category } else { "" })
        $this.Language = $(if ($data.Language) { $data.Language } else { "PowerShell" })
        $this.IsTemplate = $(if ($null -ne $data.IsTemplate) { [bool]$data.IsTemplate } else { $false })
        $this.Parameters = $(if ($data.Parameters) { $data.Parameters } else { @{} })
        $this.Notes = $(if ($data.Notes) { $data.Notes } else { "" })
    }
    
    [hashtable] ToHashtable() {
        $baseHash = ([BaseModel]$this).ToHashtable()
        
        $commandHash = @{
            Title = $this.Title
            Description = $this.Description
            Tags = $this.Tags
            Group = $this.Group
            CommandText = $this.CommandText
            LastUsed = $this.LastUsed
            UseCount = $this.UseCount
            Category = $this.Category
            Language = $this.Language
            IsTemplate = $this.IsTemplate
            Parameters = $this.Parameters
            Notes = $this.Notes
        }
        
        # Merge base and command properties
        foreach ($key in $commandHash.Keys) {
            $baseHash[$key] = $commandHash[$key]
        }
        
        return $baseHash
    }
    
    [bool] IsValid() {
        $baseValid = ([BaseModel]$this).IsValid()
        $hasCommandText = -not [string]::IsNullOrEmpty($this.CommandText)
        
        return $baseValid -and $hasCommandText
    }
    
    [void] RecordUsage() {
        $this.UseCount++
        $this.LastUsed = [DateTime]::Now
        $this.Touch()
    }
    
    [string] GetDisplayText() {
        if (-not [string]::IsNullOrEmpty($this.Title)) {
            return $this.Title
        } else {
            # Use first 50 characters of command text
            $cmdText = $this.CommandText
            if ($cmdText.Length -gt 50) {
                $cmdText = $cmdText.Substring(0, 47) + "..."
            }
            return $cmdText
        }
    }
    
    [string] GetSearchableText() {
        $searchText = @()
        
        if (-not [string]::IsNullOrEmpty($this.Title)) {
            $searchText += $this.Title
        }
        
        if (-not [string]::IsNullOrEmpty($this.Description)) {
            $searchText += $this.Description
        }
        
        if (-not [string]::IsNullOrEmpty($this.Group)) {
            $searchText += $this.Group
        }
        
        if (-not [string]::IsNullOrEmpty($this.Category)) {
            $searchText += $this.Category
        }
        
        if ($this.Tags.Count -gt 0) {
            $searchText += ($this.Tags -join " ")
        }
        
        $searchText += $this.CommandText
        
        return ($searchText -join " ").ToLower()
    }
    
    [string] GetDetailText() {
        $details = @()
        
        if (-not [string]::IsNullOrEmpty($this.Title)) {
            $details += "Title: $($this.Title)"
        }
        
        if (-not [string]::IsNullOrEmpty($this.Description)) {
            $details += "Description: $($this.Description)"
        }
        
        if (-not [string]::IsNullOrEmpty($this.Group)) {
            $details += "Group: $($this.Group)"
        }
        
        if (-not [string]::IsNullOrEmpty($this.Category)) {
            $details += "Category: $($this.Category)"
        }
        
        if ($this.Tags.Count -gt 0) {
            $details += "Tags: $($this.Tags -join ', ')"
        }
        
        $details += "Language: $($this.Language)"
        
        if ($this.UseCount -gt 0) {
            $details += "Used: $($this.UseCount) times"
            if ($this.LastUsed -ne [DateTime]::MinValue) {
                $details += "Last used: $($this.LastUsed.ToString('yyyy-MM-dd HH:mm'))"
            }
        }
        
        $details += "Command:"
        $details += $this.CommandText
        
        if (-not [string]::IsNullOrEmpty($this.Notes)) {
            $details += ""
            $details += "Notes:"
            $details += $this.Notes
        }
        
        return $details -join "`n"
    }
    
    [void] AddTag([string]$tag) {
        if (-not [string]::IsNullOrEmpty($tag) -and $tag -notin $this.Tags) {
            $this.Tags += $tag
            $this.Touch()
        }
    }
    
    [void] RemoveTag([string]$tag) {
        if ($tag -in $this.Tags) {
            $this.Tags = $this.Tags | Where-Object { $_ -ne $tag }
            $this.Touch()
        }
    }
    
    [bool] HasTag([string]$tag) {
        return $tag -in $this.Tags
    }
    
    [string] GetTagsDisplay() {
        if ($this.Tags.Count -eq 0) {
            return ""
        }
        return ($this.Tags -join ", ")
    }
    
    [bool] MatchesSearch([string]$searchTerm) {
        if ([string]::IsNullOrEmpty($searchTerm)) {
            return $true
        }
        
        $searchText = $this.GetSearchableText()
        $terms = $searchTerm.ToLower().Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
        
        foreach ($term in $terms) {
            if ($searchText -notlike "*$term*") {
                return $false
            }
        }
        
        return $true
    }
    
    [bool] MatchesDoFilter([string]$filterType, [string]$filterValue) {
        if ([string]::IsNullOrEmpty($filterValue)) {
            return $true
        }
        
        $filterTypeLower = $filterType.ToLower()
        if ($filterTypeLower -eq "group") {
            return $this.Group -like "*$filterValue*"
        } elseif ($filterTypeLower -eq "category") {
            return $this.Category -like "*$filterValue*"
        } elseif ($filterTypeLower -eq "language") {
            return $this.Language -like "*$filterValue*"
        } elseif ($filterTypeLower -eq "tag") {
            return $this.Tags -contains $filterValue
        } elseif ($filterTypeLower -eq "used") {
            $filterValueLower = $filterValue.ToLower()
            if ($filterValueLower -eq "never") {
                return $this.UseCount -eq 0
            } elseif ($filterValueLower -eq "once") {
                return $this.UseCount -eq 1
            } elseif ($filterValueLower -eq "few") {
                return $this.UseCount -gt 1 -and $this.UseCount -le 5
            } elseif ($filterValueLower -eq "many") {
                return $this.UseCount -gt 5
            } else {
                return $true
            }
        } else {
            return $true
        }
    }
    
    [string] GetUsageDisplay() {
        if ($this.UseCount -eq 0) {
            return "Never used"
        } elseif ($this.UseCount -eq 1) {
            return "Used once"
        } else {
            $lastUsedStr = $(if ($this.LastUsed -ne [DateTime]::MinValue) {
                " (last: $($this.LastUsed.ToString('MMM dd')))"
            } else {
                ""
            })
            return "Used $($this.UseCount) times$lastUsedStr"
        }
    }
    
    [string] GetCommandPreview([int]$maxLength = 100) {
        $preview = $this.CommandText
        if ($preview.Length -gt $maxLength) {
            $preview = $preview.Substring(0, $maxLength - 3) + "..."
        }
        
        # Replace newlines with spaces for single-line display
        $preview = $preview -replace "`r`n", " " -replace "`n", " " -replace "`r", " "
        $preview = $preview -replace "\s+", " "
        
        return $preview.Trim()
    }
    
    [string] GetDisplaySummary() {
        $displayText = $this.GetDisplayText()
        $preview = $this.GetCommandPreview(50)
        $usage = $this.GetUsageDisplay()
        
        return "$displayText - $preview - $usage"
    }
    
    # Create a copy of this command for editing
    [Command] Clone() {
        $cloneData = $this.ToHashtable()
        $cloneData.Id = [Guid]::NewGuid().ToString()
        $cloneData.CreatedAt = [DateTime]::Now
        $cloneData.UpdatedAt = [DateTime]::Now
        $cloneData.UseCount = 0
        $cloneData.LastUsed = [DateTime]::MinValue
        
        return [Command]::new($cloneData)
    }
}