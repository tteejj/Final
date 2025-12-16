# SpeedTUI TimeTrackingService - Comprehensive time tracking with fiscal year support
# Inherits from DataService for full CRUD operations

# Load dependencies
if (-not ([System.Management.Automation.PSTypeName]'DataService').Type) {
    . "$PSScriptRoot/DataService.ps1"
}

if (-not ([System.Management.Automation.PSTypeName]'TimeEntry').Type) {
    . "$PSScriptRoot/../Models/TimeEntry.ps1"
}

if (-not ([System.Management.Automation.PSTypeName]'Logger').Type) {
    . "$PSScriptRoot/../Core/Logger.ps1"
}

class TimeTrackingService : DataService {
    [hashtable]$WeekCache = @{}
    [hashtable]$FiscalYearCache = @{}
    [string]$CurrentFiscalYear = ""
    [string]$FileName = "timeentries"
    [object]$Logger
    
    TimeTrackingService() : base("_ProjectData") {
        $this.Logger = Get-Logger
        $this.CurrentFiscalYear = $this.CalculateCurrentFiscalYear()
        $this.Logger.Info("SpeedTUI", "TimeTrackingService", "Initialized for fiscal year: $($this.CurrentFiscalYear)")
    }
    
    # =============================================================================
    # CRUD OPERATIONS FOR TIMEENTRY
    # =============================================================================
    
    [TimeEntry[]] GetAll() {
        $data = $this.LoadData($this.FileName)
        $entries = @()
        
        foreach ($item in $data) {
            $entries += [TimeEntry]::new($item)
        }
        
        return $entries
    }
    
    [TimeEntry] GetById([string]$id) {
        $data = $this.LoadData($this.FileName)
        $item = $this.FindById($data, $id)
        
        if ($item) {
            return [TimeEntry]::new($item)
        }
        
        return $null
    }
    
    [TimeEntry] Create([TimeEntry]$entity) {
        # Ensure fiscal year is calculated
        if ([string]::IsNullOrEmpty($entity.FiscalYear)) {
            $entity.FiscalYear = $entity.CalculateFiscalYear($entity.WeekEndingFriday)
        }
        
        # Calculate total if not set
        if ($entity.Total -eq 0) {
            $entity.CalculateTotal()
        }
        
        $data = $this.LoadData($this.FileName)
        $entityHash = $entity.ToHashtable()
        $data = $this.AddItem($data, $entityHash)
        $this.SaveData($this.FileName, $data)
        $this.ClearTimeTrackingCaches()
        
        return $entity
    }
    
    [TimeEntry] Update([TimeEntry]$entity) {
        # Recalculate fiscal year in case week changed
        $entity.FiscalYear = $entity.CalculateFiscalYear($entity.WeekEndingFriday)
        
        # Always recalculate total on update
        $entity.CalculateTotal()
        
        $data = $this.LoadData($this.FileName)
        $entityHash = $entity.ToHashtable()
        $data = $this.UpdateItem($data, $entity.Id, $entityHash)
        $this.SaveData($this.FileName, $data)
        $this.ClearTimeTrackingCaches()
        
        return $entity
    }
    
    [void] Delete([string]$id) {
        $data = $this.LoadData($this.FileName)
        $data = $this.DeleteItem($data, $id, $true)  # Soft delete
        $this.SaveData($this.FileName, $data)
        $this.ClearTimeTrackingCaches()
    }
    
    # Alias for Delete method - provides backward compatibility
    [void] Remove([string]$id) {
        $this.Delete($id)
    }
    
    # =============================================================================
    # FISCAL YEAR OPERATIONS
    # =============================================================================
    
    [string] CalculateCurrentFiscalYear() {
        $now = [DateTime]::Now
        if ($now.Month -ge 4) {
            return "$($now.Year)-$($now.Year + 1)"
        } else {
            return "$($now.Year - 1)-$($now.Year)"
        }
    }
    
    [string[]] GetAvailableFiscalYears() {
        $entries = $this.GetAll()
        $fiscalYears = @()
        
        foreach ($entry in $entries) {
            if (-not [string]::IsNullOrEmpty($entry.FiscalYear) -and $entry.FiscalYear -notin $fiscalYears) {
                $fiscalYears += $entry.FiscalYear
            }
        }
        
        return ($fiscalYears | Sort-Object -Descending)
    }
    
    [TimeEntry[]] GetEntriesForFiscalYear([string]$fiscalYear) {
        if ([string]::IsNullOrEmpty($fiscalYear)) {
            $fiscalYear = $this.CurrentFiscalYear
        }
        
        # Check cache first
        if ($this.FiscalYearCache.ContainsKey($fiscalYear)) {
            $this.Logger.Debug("SpeedTUI", "TimeTrackingService", "Retrieved $($fiscalYear) entries from cache")
            return $this.FiscalYearCache[$fiscalYear]
        }
        
        $entries = $this.GetAll() | Where-Object { $_.FiscalYear -eq $fiscalYear }
        $this.FiscalYearCache[$fiscalYear] = $entries
        
        $this.Logger.Info("SpeedTUI", "TimeTrackingService", "Retrieved $($entries.Count) entries for fiscal year $fiscalYear")
        return $entries
    }
    
    # =============================================================================
    # WEEK OPERATIONS
    # =============================================================================
    
    [string] GetCurrentWeekEndingFriday() {
        $today = [DateTime]::Now.Date
        $daysUntilFriday = ([DayOfWeek]::Friday - $today.DayOfWeek + 7) % 7
        if ($daysUntilFriday -eq 0 -and $today.DayOfWeek -ne [DayOfWeek]::Friday) {
            $daysUntilFriday = 7
        }
        
        $fridayDate = $today.AddDays($daysUntilFriday)
        return $fridayDate.ToString("yyyyMMdd")
    }
    
    [string[]] GetWeeksInFiscalYear([string]$fiscalYear) {
        if ([string]::IsNullOrEmpty($fiscalYear)) {
            $fiscalYear = $this.CurrentFiscalYear
        }
        
        $entries = $this.GetEntriesForFiscalYear($fiscalYear)
        $weeks = @()
        
        foreach ($entry in $entries) {
            if (-not [string]::IsNullOrEmpty($entry.WeekEndingFriday) -and $entry.WeekEndingFriday -notin $weeks) {
                $weeks += $entry.WeekEndingFriday
            }
        }
        
        return ($weeks | Sort-Object -Descending)
    }
    
    [TimeEntry[]] GetEntriesForWeek([string]$weekEndingFriday) {
        if ([string]::IsNullOrEmpty($weekEndingFriday)) {
            $weekEndingFriday = $this.GetCurrentWeekEndingFriday()
        }
        
        # Check cache first
        if ($this.WeekCache.ContainsKey($weekEndingFriday)) {
            $this.Logger.Debug("SpeedTUI", "TimeTrackingService", "Retrieved week $weekEndingFriday entries from cache")
            return $this.WeekCache[$weekEndingFriday]
        }
        
        $entries = $this.GetAll() | Where-Object { $_.WeekEndingFriday -eq $weekEndingFriday }
        $this.WeekCache[$weekEndingFriday] = $entries
        
        $this.Logger.Info("SpeedTUI", "TimeTrackingService", "Retrieved $($entries.Count) entries for week ending $weekEndingFriday")
        return $entries
    }
    
    [decimal] GetWeekTotalHours([string]$weekEndingFriday) {
        $entries = $this.GetEntriesForWeek($weekEndingFriday)
        $total = 0
        
        foreach ($entry in $entries) {
            $total += $entry.Total
        }
        
        return $total
    }
    
    # =============================================================================
    # PROJECT TIME TRACKING
    # =============================================================================
    
    [TimeEntry[]] GetProjectEntries([string]$projectId1, [string]$projectId2 = "") {
        $filter = { 
            $_.IsProjectEntry -and 
            $_.ID1 -eq $projectId1 -and 
            (-not $projectId2 -or $_.ID2 -eq $projectId2)
        }
        
        return $this.GetAll() | Where-Object $filter
    }
    
    [decimal] GetProjectTotalHours([string]$projectId1, [string]$projectId2 = "", [string]$fiscalYear = "") {
        $entries = $this.GetProjectEntries($projectId1, $projectId2)
        
        if (-not [string]::IsNullOrEmpty($fiscalYear)) {
            $entries = $entries | Where-Object { $_.FiscalYear -eq $fiscalYear }
        }
        
        $total = 0
        foreach ($entry in $entries) {
            $total += $entry.Total
        }
        
        $this.Logger.Debug("SpeedTUI", "TimeTrackingService", "Project $projectId1-$projectId2 total hours: $total")
        return $total
    }
    
    [hashtable] GetProjectHoursByWeek([string]$projectId1, [string]$projectId2 = "", [string]$fiscalYear = "") {
        $entries = $this.GetProjectEntries($projectId1, $projectId2)
        
        if (-not [string]::IsNullOrEmpty($fiscalYear)) {
            $entries = $entries | Where-Object { $_.FiscalYear -eq $fiscalYear }
        }
        
        $weeklyHours = @{}
        foreach ($entry in $entries) {
            if ($weeklyHours.ContainsKey($entry.WeekEndingFriday)) {
                $weeklyHours[$entry.WeekEndingFriday] += $entry.Total
            } else {
                $weeklyHours[$entry.WeekEndingFriday] = $entry.Total
            }
        }
        
        return $weeklyHours
    }
    
    # =============================================================================
    # TIME CODE TRACKING (NON-PROJECT TIME)
    # =============================================================================
    
    [TimeEntry[]] GetTimeCodeEntries([string]$timeCodeId) {
        return $this.GetAll() | Where-Object { -not $_.IsProjectEntry -and $_.TimeCodeID -eq $timeCodeId }
    }
    
    [decimal] GetTimeCodeTotalHours([string]$timeCodeId, [string]$fiscalYear = "") {
        $entries = $this.GetTimeCodeEntries($timeCodeId)
        
        if (-not [string]::IsNullOrEmpty($fiscalYear)) {
            $entries = $entries | Where-Object { $_.FiscalYear -eq $fiscalYear }
        }
        
        $total = 0
        foreach ($entry in $entries) {
            $total += $entry.Total
        }
        
        return $total
    }
    
    [string[]] GetAvailableTimeCodes() {
        $entries = $this.GetAll() | Where-Object { -not $_.IsProjectEntry -and -not [string]::IsNullOrEmpty($_.TimeCodeID) }
        $timeCodes = @()
        
        foreach ($entry in $entries) {
            if ($entry.TimeCodeID -notin $timeCodes) {
                $timeCodes += $entry.TimeCodeID
            }
        }
        
        return ($timeCodes | Sort-Object)
    }
    
    # =============================================================================
    # REPORTING AND ANALYTICS
    # =============================================================================
    
    [hashtable] GetFiscalYearSummary([string]$fiscalYear = "") {
        if ([string]::IsNullOrEmpty($fiscalYear)) {
            $fiscalYear = $this.CurrentFiscalYear
        }
        
        $entries = $this.GetEntriesForFiscalYear($fiscalYear)
        $projectEntries = $entries | Where-Object { $_.IsValidProjectEntry() }
        $timeCodeEntries = $entries | Where-Object { $_.IsValidTimeCodeEntry() }
        
        $summary = @{
            FiscalYear = $fiscalYear
            TotalEntries = $entries.Count
            ProjectEntries = $projectEntries.Count
            TimeCodeEntries = $timeCodeEntries.Count
            TotalHours = ($entries | Measure-Object -Property Total -Sum).Sum
            ProjectHours = ($projectEntries | Measure-Object -Property Total -Sum).Sum
            TimeCodeHours = ($timeCodeEntries | Measure-Object -Property Total -Sum).Sum
            WeeksWithTime = ($entries | Group-Object WeekEndingFriday | Where-Object { $_.Group.Total -gt 0 }).Count
            AverageHoursPerWeek = 0
            UniqueProjects = ($projectEntries | Where-Object { -not [string]::IsNullOrEmpty($_.ID1) } | Group-Object ID1).Count
            UniqueTimeCodes = ($timeCodeEntries | Where-Object { -not [string]::IsNullOrEmpty($_.TimeCodeID) } | Group-Object TimeCodeID).Count
        }
        
        if ($summary.WeeksWithTime -gt 0) {
            $summary.AverageHoursPerWeek = [Math]::Round($summary.TotalHours / $summary.WeeksWithTime, 2)
        }
        
        $this.Logger.Info("SpeedTUI", "TimeTrackingService", "Generated fiscal year summary for $fiscalYear")
        return $summary
    }
    
    [hashtable] GetWeekSummary([string]$weekEndingFriday = "") {
        if ([string]::IsNullOrEmpty($weekEndingFriday)) {
            $weekEndingFriday = $this.GetCurrentWeekEndingFriday()
        }
        
        $entries = $this.GetEntriesForWeek($weekEndingFriday)
        $projectEntries = $entries | Where-Object { $_.IsValidProjectEntry() }
        $timeCodeEntries = $entries | Where-Object { $_.IsValidTimeCodeEntry() }
        
        # Calculate daily totals
        $dailyTotals = @{
            Monday = ($entries | Measure-Object -Property Monday -Sum).Sum
            Tuesday = ($entries | Measure-Object -Property Tuesday -Sum).Sum
            Wednesday = ($entries | Measure-Object -Property Wednesday -Sum).Sum
            Thursday = ($entries | Measure-Object -Property Thursday -Sum).Sum
            Friday = ($entries | Measure-Object -Property Friday -Sum).Sum
        }
        
        $summary = @{
            WeekEndingFriday = $weekEndingFriday
            TotalEntries = $entries.Count
            ProjectEntries = $projectEntries.Count
            TimeCodeEntries = $timeCodeEntries.Count
            TotalHours = ($entries | Measure-Object -Property Total -Sum).Sum
            ProjectHours = ($projectEntries | Measure-Object -Property Total -Sum).Sum
            TimeCodeHours = ($timeCodeEntries | Measure-Object -Property Total -Sum).Sum
            DailyTotals = $dailyTotals
            IsComplete = $false
            UniqueProjects = ($projectEntries | Where-Object { -not [string]::IsNullOrEmpty($_.ID1) } | Group-Object ID1).Count
            UniqueTimeCodes = ($timeCodeEntries | Where-Object { -not [string]::IsNullOrEmpty($_.TimeCodeID) } | Group-Object TimeCodeID).Count
        }
        
        # Check if week is complete (>= 35 hours total)
        $summary.IsComplete = $summary.TotalHours -ge 35
        
        return $summary
    }
    
    [TimeEntry[]] GetTopProjectsByHours([int]$limit = 10, [string]$fiscalYear = "") {
        $entries = $(if ([string]::IsNullOrEmpty($fiscalYear)) { $this.GetAll() } else { $this.GetEntriesForFiscalYear($fiscalYear) })
        $projectEntries = $entries | Where-Object { $_.IsValidProjectEntry() }
        
        $projectGroups = $projectEntries | Group-Object { "$($_.ID1)-$($_.ID2)" }
        $projectSummaries = @()
        
        foreach ($group in $projectGroups) {
            $totalHours = ($group.Group | Measure-Object -Property Total -Sum).Sum
            $firstEntry = $group.Group[0]
            
            # Create summary entry
            $summary = [TimeEntry]::new(@{
                ID1 = $firstEntry.ID1
                ID2 = $firstEntry.ID2
                Name = $firstEntry.Name
                Total = $totalHours
                WeekEndingFriday = "SUMMARY"
                FiscalYear = $(if ($fiscalYear) { $fiscalYear } else { "ALL" })
            })
            
            $projectSummaries += $summary
        }
        
        return ($projectSummaries | Sort-Object Total -Descending | Select-Object -First $limit)
    }
    
    # =============================================================================
    # BULK OPERATIONS
    # =============================================================================
    
    [void] ImportWeekData([hashtable]$weekData) {
        $this.Logger.Info("SpeedTUI", "TimeTrackingService", "Starting import of week data")
        $importCount = 0
        
        foreach ($entryData in $weekData.Values) {
            try {
                $entry = [TimeEntry]::new($entryData)
                if ($entry.IsValid()) {
                    $this.Create($entry)
                    $importCount++
                } else {
                    $this.Logger.Warn("SpeedTUI", "TimeTrackingService", "Skipped invalid time entry: $($entryData | ConvertTo-Json -Compress)")
                }
            } catch {
                $this.Logger.Error("SpeedTUI", "TimeTrackingService", "Failed to import time entry: $($_.Exception.Message)")
            }
        }
        
        # Clear caches after import
        $this.ClearTimeTrackingCaches()
        
        $this.Logger.Info("SpeedTUI", "TimeTrackingService", "Imported $importCount time entries")
    }
    
    [hashtable] ExportWeekData([string]$weekEndingFriday) {
        $entries = $this.GetEntriesForWeek($weekEndingFriday)
        $exportData = @{
            WeekEndingFriday = $weekEndingFriday
            ExportDate = [DateTime]::Now
            Entries = @()
        }
        
        foreach ($entry in $entries) {
            $exportData.Entries += $entry.ToHashtable()
        }
        
        $this.Logger.Info("SpeedTUI", "TimeTrackingService", "Exported $($entries.Count) entries for week $weekEndingFriday")
        return $exportData
    }
    
    [hashtable] ExportFiscalYearData([string]$fiscalYear = "") {
        if ([string]::IsNullOrEmpty($fiscalYear)) {
            $fiscalYear = $this.CurrentFiscalYear
        }
        
        $entries = $this.GetEntriesForFiscalYear($fiscalYear)
        $exportData = @{
            FiscalYear = $fiscalYear
            ExportDate = [DateTime]::Now
            Summary = $this.GetFiscalYearSummary($fiscalYear)
            Entries = @()
        }
        
        foreach ($entry in $entries) {
            $exportData.Entries += $entry.ToHashtable()
        }
        
        $this.Logger.Info("SpeedTUI", "TimeTrackingService", "Exported $($entries.Count) entries for fiscal year $fiscalYear")
        return $exportData
    }
    
    # =============================================================================
    # TIME ENTRY CREATION HELPERS
    # =============================================================================
    
    [TimeEntry] CreateProjectTimeEntry([string]$projectId1, [string]$projectId2, [string]$projectName, [string]$weekEndingFriday = "") {
        if ([string]::IsNullOrEmpty($weekEndingFriday)) {
            $weekEndingFriday = $this.GetCurrentWeekEndingFriday()
        }
        
        $entryData = @{
            ID1 = $projectId1
            ID2 = $projectId2
            Name = $projectName
            WeekEndingFriday = $weekEndingFriday
            IsProjectEntry = $true
        }
        
        $entry = [TimeEntry]::new($entryData)
        return $this.Create($entry)
    }
    
    [TimeEntry] CreateTimeCodeEntry([string]$timeCodeId, [string]$description, [string]$weekEndingFriday = "") {
        if ([string]::IsNullOrEmpty($weekEndingFriday)) {
            $weekEndingFriday = $this.GetCurrentWeekEndingFriday()
        }
        
        $entryData = @{
            TimeCodeID = $timeCodeId
            Description = $description
            WeekEndingFriday = $weekEndingFriday
            IsProjectEntry = $false
        }
        
        $entry = [TimeEntry]::new($entryData)
        return $this.Create($entry)
    }
    
    [TimeEntry] CreateQuickEntry([string]$identifier, [string]$name, [decimal]$hours, [string]$day = "Monday") {
        $isProject = $identifier.Contains("-")
        $weekEndingFriday = $this.GetCurrentWeekEndingFriday()
        
        if ($isProject) {
            $parts = $identifier.Split("-")
            $entry = $this.CreateProjectTimeEntry($parts[0], $parts[1], $name, $weekEndingFriday)
        } else {
            $entry = $this.CreateTimeCodeEntry($identifier, $name, $weekEndingFriday)
        }
        
        $entry.SetDayHours($day, $hours)
        return $this.Update($entry)
    }
    
    # =============================================================================
    # CACHE MANAGEMENT
    # =============================================================================
    
    [void] ClearTimeTrackingCaches() {
        $this.WeekCache.Clear()
        $this.FiscalYearCache.Clear()
        $this.Logger.Debug("SpeedTUI", "TimeTrackingService", "Cleared time tracking caches")
    }
    
    [void] RefreshCaches() {
        $this.ClearTimeTrackingCaches()
        
        # Pre-populate current week and fiscal year
        $currentWeek = $this.GetCurrentWeekEndingFriday()
        $this.GetEntriesForWeek($currentWeek) | Out-Null
        $this.GetEntriesForFiscalYear($this.CurrentFiscalYear) | Out-Null
        
        $this.Logger.Info("SpeedTUI", "TimeTrackingService", "Refreshed time tracking caches")
    }
    
    # =============================================================================
    # VALIDATION AND UTILITIES
    # =============================================================================
    
    [bool] ValidateWeekEndingFriday([string]$weekEndingFriday) {
        try {
            $date = [DateTime]::ParseExact($weekEndingFriday, "yyyyMMdd", $null)
            return $date.DayOfWeek -eq [DayOfWeek]::Friday
        } catch {
            return $false
        }
    }
    
    [string[]] GetWeekDayNames() {
        return @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")
    }
    
    [DateTime] GetWeekStartDate([string]$weekEndingFriday) {
        try {
            $fridayDate = [DateTime]::ParseExact($weekEndingFriday, "yyyyMMdd", $null)
            return $fridayDate.AddDays(-4)
        } catch {
            return [DateTime]::Now
        }
    }
    
    [string] FormatWeekRange([string]$weekEndingFriday) {
        try {
            $fridayDate = [DateTime]::ParseExact($weekEndingFriday, "yyyyMMdd", $null)
            $mondayDate = $fridayDate.AddDays(-4)
            return "$($mondayDate.ToString('MMM dd')) - $($fridayDate.ToString('MMM dd, yyyy'))"
        } catch {
            return $weekEndingFriday
        }
    }
    
    # =============================================================================
    # OVERRIDES FROM DATASERVICE
    # =============================================================================
}