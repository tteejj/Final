# SpeedTUI TimeEntry Model - Time tracking with fiscal year support

# Load BaseModel if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'BaseModel').Type) {
    . "$PSScriptRoot/BaseModel.ps1"
}

class TimeEntry : BaseModel {
    [string]$WeekEndingFriday = ""  # Format: yyyyMMdd
    [string]$Name = ""
    [string]$ID1 = ""
    [string]$ID2 = ""
    [decimal]$Monday = 0
    [decimal]$Tuesday = 0
    [decimal]$Wednesday = 0
    [decimal]$Thursday = 0
    [decimal]$Friday = 0
    [decimal]$Total = 0
    [string]$FiscalYear = ""
    [string]$TimeCodeID = ""  # For non-project time entries
    [string]$Description = ""
    [bool]$IsProjectEntry = $true
    
    TimeEntry() : base() {
        $this.WeekEndingFriday = $this.GetCurrentWeekEndingFriday()
        $this.FiscalYear = $this.CalculateFiscalYear($this.WeekEndingFriday)
    }
    
    TimeEntry([hashtable]$data) : base($data) {
        $this.WeekEndingFriday = $(if ($data.WeekEndingFriday) { $data.WeekEndingFriday } else { $this.GetCurrentWeekEndingFriday() })
        $this.Name = $(if ($data.Name) { $data.Name } else { "" })
        $this.ID1 = $(if ($data.ID1) { $data.ID1 } else { "" })
        $this.ID2 = $(if ($data.ID2) { $data.ID2 } else { "" })
        $this.Monday = $(if ($null -ne $data.Monday) { [decimal]$data.Monday } else { 0 })
        $this.Tuesday = $(if ($null -ne $data.Tuesday) { [decimal]$data.Tuesday } else { 0 })
        $this.Wednesday = $(if ($null -ne $data.Wednesday) { [decimal]$data.Wednesday } else { 0 })
        $this.Thursday = $(if ($null -ne $data.Thursday) { [decimal]$data.Thursday } else { 0 })
        $this.Friday = $(if ($null -ne $data.Friday) { [decimal]$data.Friday } else { 0 })
        $this.Total = $(if ($null -ne $data.Total) { [decimal]$data.Total } else { 0 })
        $this.FiscalYear = $(if ($data.FiscalYear) { $data.FiscalYear } else { $this.CalculateFiscalYear($this.WeekEndingFriday) })
        $this.TimeCodeID = $(if ($data.TimeCodeID) { $data.TimeCodeID } else { "" })
        $this.Description = $(if ($data.Description) { $data.Description } else { "" })
        $this.IsProjectEntry = $(if ($null -ne $data.IsProjectEntry) { [bool]$data.IsProjectEntry } else { $true })
        
        # Recalculate total if not provided or if daily values changed
        if ($this.Total -eq 0) {
            $this.CalculateTotal()
        }
    }
    
    [hashtable] ToHashtable() {
        $baseHash = ([BaseModel]$this).ToHashtable()
        
        $timeHash = @{
            WeekEndingFriday = $this.WeekEndingFriday
            Name = $this.Name
            ID1 = $this.ID1
            ID2 = $this.ID2
            Monday = $this.Monday
            Tuesday = $this.Tuesday
            Wednesday = $this.Wednesday
            Thursday = $this.Thursday
            Friday = $this.Friday
            Total = $this.Total
            FiscalYear = $this.FiscalYear
            TimeCodeID = $this.TimeCodeID
            Description = $this.Description
            IsProjectEntry = $this.IsProjectEntry
        }
        
        # Merge base and time entry properties
        foreach ($key in $timeHash.Keys) {
            $baseHash[$key] = $timeHash[$key]
        }
        
        return $baseHash
    }
    
    [void] CalculateTotal() {
        $this.Total = $this.Monday + $this.Tuesday + $this.Wednesday + $this.Thursday + $this.Friday
        $this.Touch()
    }
    
    [string] CalculateFiscalYear([string]$weekEndingFridayStr) {
        if ([string]::IsNullOrEmpty($weekEndingFridayStr)) {
            return ""
        }
        
        try {
            $weekEndingDate = [DateTime]::ParseExact($weekEndingFridayStr, "yyyyMMdd", $null)
            
            # Fiscal year runs April 1 to March 31
            if ($weekEndingDate.Month -ge 4) {
                return "$($weekEndingDate.Year)-$($weekEndingDate.Year + 1)"
            } else {
                return "$($weekEndingDate.Year - 1)-$($weekEndingDate.Year)"
            }
        } catch {
            return ""
        }
    }
    
    [string] GetCurrentWeekEndingFriday() {
        $today = [DateTime]::Now.Date
        $daysUntilFriday = ([DayOfWeek]::Friday - $today.DayOfWeek + 7) % 7
        if ($daysUntilFriday -eq 0 -and $today.DayOfWeek -ne [DayOfWeek]::Friday) {
            $daysUntilFriday = 7
        }
        
        $fridayDate = $today.AddDays($daysUntilFriday)
        return $fridayDate.ToString("yyyyMMdd")
    }
    
    [DateTime] GetWeekStartMonday() {
        try {
            $weekEndingDate = [DateTime]::ParseExact($this.WeekEndingFriday, "yyyyMMdd", $null)
            return $weekEndingDate.AddDays(-4)  # Friday - 4 days = Monday
        } catch {
            return [DateTime]::Now.Date
        }
    }
    
    [string] GetWeekDisplayString() {
        try {
            $weekEndingDate = [DateTime]::ParseExact($this.WeekEndingFriday, "yyyyMMdd", $null)
            $weekStartDate = $weekEndingDate.AddDays(-4)
            
            return "$($weekStartDate.ToString('MMM dd')) - $($weekEndingDate.ToString('MMM dd, yyyy'))"
        } catch {
            return $this.WeekEndingFriday
        }
    }
    
    [void] SetDayHours([string]$dayName, [decimal]$hours) {
        if ($hours -lt 0) { $hours = 0 }
        if ($hours -gt 24) { $hours = 24 }
        
        switch ($dayName.ToLower()) {
            "monday" { $this.Monday = $hours }
            "tuesday" { $this.Tuesday = $hours }
            "wednesday" { $this.Wednesday = $hours }
            "thursday" { $this.Thursday = $hours }
            "friday" { $this.Friday = $hours }
        }
        
        $this.CalculateTotal()
    }
    
    [decimal] GetDayHours([string]$dayName) {
        $day = $dayName.ToLower()
        if ($day -eq "monday") {
            return $this.Monday
        } elseif ($day -eq "tuesday") {
            return $this.Tuesday
        } elseif ($day -eq "wednesday") {
            return $this.Wednesday
        } elseif ($day -eq "thursday") {
            return $this.Thursday
        } elseif ($day -eq "friday") {
            return $this.Friday
        } else {
            return 0
        }
    }
    
    [string[]] GetDayNames() {
        return @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")
    }
    
    [decimal[]] GetDayHoursArray() {
        return @($this.Monday, $this.Tuesday, $this.Wednesday, $this.Thursday, $this.Friday)
    }
    
    [bool] IsValidProjectEntry() {
        return $this.IsProjectEntry -and (-not [string]::IsNullOrEmpty($this.ID1) -or -not [string]::IsNullOrEmpty($this.ID2))
    }
    
    [bool] IsValidTimeCodeEntry() {
        return -not $this.IsProjectEntry -and -not [string]::IsNullOrEmpty($this.TimeCodeID)
    }
    
    [string] GetEntryType() {
        if ($this.IsValidProjectEntry()) {
            return "Project"
        } elseif ($this.IsValidTimeCodeEntry()) {
            return "Time Code"
        } else {
            return "Unknown"
        }
    }
    
    [string] GetProjectCode() {
        if (-not [string]::IsNullOrEmpty($this.ID1) -and -not [string]::IsNullOrEmpty($this.ID2)) {
            return "$($this.ID1)-$($this.ID2)"
        } elseif (-not [string]::IsNullOrEmpty($this.ID1)) {
            return $this.ID1
        } else {
            return ""
        }
    }
    
    [bool] HasTime() {
        return $this.Total -gt 0
    }
    
    [bool] IsFullWeek() {
        return $this.Total -ge 35  # Assuming 7 hours per day, 5 days
    }
    
    [string] GetTimeDistribution() {
        if ($this.Total -eq 0) {
            return "No time logged"
        }
        
        $days = @()
        if ($this.Monday -gt 0) { $days += "Mon: $($this.Monday)h" }
        if ($this.Tuesday -gt 0) { $days += "Tue: $($this.Tuesday)h" }
        if ($this.Wednesday -gt 0) { $days += "Wed: $($this.Wednesday)h" }
        if ($this.Thursday -gt 0) { $days += "Thu: $($this.Thursday)h" }
        if ($this.Friday -gt 0) { $days += "Fri: $($this.Friday)h" }
        
        return $days -join ", "
    }
    
    [bool] IsValid() {
        $baseValid = ([BaseModel]$this).IsValid()
        $hasWeek = -not [string]::IsNullOrEmpty($this.WeekEndingFriday)
        $hasIdentifier = (-not [string]::IsNullOrEmpty($this.ID1)) -or (-not [string]::IsNullOrEmpty($this.TimeCodeID))
        
        return $baseValid -and $hasWeek -and $hasIdentifier
    }
    
    [string] GetDisplaySummary() {
        $week = $this.GetWeekDisplayString()
        $identifier = ""
        
        if ($this.IsValidProjectEntry()) {
            $identifier = $this.GetProjectCode()
            if (-not [string]::IsNullOrEmpty($this.Name)) {
                $identifier += " ($($this.Name))"
            }
        } else {
            $identifier = $this.TimeCodeID
            if (-not [string]::IsNullOrEmpty($this.Description)) {
                $identifier += " ($($this.Description))"
            }
        }
        
        return "$identifier - $week - $($this.Total)h total"
    }
}