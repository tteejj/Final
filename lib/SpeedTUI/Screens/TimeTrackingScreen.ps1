# SpeedTUI Time Tracking Screen - Comprehensive time entry and management

# Load dependencies
. "$PSScriptRoot/../Core/Component.ps1"
. "$PSScriptRoot/../Core/PerformanceMonitor.ps1"
. "$PSScriptRoot/../Services/TimeTrackingService.ps1"
. "$PSScriptRoot/../BorderHelper.ps1"
. "$PSScriptRoot/../Components/FormManager.ps1"

class TimeTrackingScreen : Component {
    [object]$TimeService
    [object]$PerformanceMonitor
    [array]$TimeEntries = @()
    [int]$SelectedEntry = 0
    [string]$ViewMode = "List"  # List, Add, Edit, Delete
    [hashtable]$NewEntry = @{}
    [DateTime]$LastRefresh
    [DateTime]$CurrentWeekStarting = [DateTime]::MinValue  # Monday of current viewing week
    [FormManager]$AddForm
    [FormManager]$EditForm
    
    TimeTrackingScreen() : base() {
        try {
            $this.Initialize()
        } catch {
            $logger = Get-Logger
            $logger.Fatal("SpeedTUI", "TimeTrackingScreen", "Constructor failed", @{
                Exception = $_.Exception.ToString()
                Message = $_.Exception.Message
            })
            throw
        }
    }
    
    [void] Initialize() {
        try {
            $this.TimeService = [TimeTrackingService]::new()
            $this.PerformanceMonitor = Get-PerformanceMonitor
            
            # Initialize empty array to prevent null reference
            if ($null -eq $this.TimeEntries) {
                $this.TimeEntries = @()
            }
            
            # Initialize forms
            $this.InitializeForms()
            
            # Initialize current week to this week (Monday to Friday)
            $this.InitializeCurrentWeek()
            
            $this.RefreshData()
            $this.LastRefresh = [DateTime]::Now
            
            $this.PerformanceMonitor.IncrementCounter("screen.timetracking.initialized", @{})
        } catch {
            $logger = Get-Logger
            $logger.Error("SpeedTUI", "TimeTrackingScreen", "Initialization failed", @{
                Exception = $_.Exception.ToString()
                Message = $_.Exception.Message
            })
            # Ensure we have at least empty collections
            if ($null -eq $this.TimeEntries) {
                $this.TimeEntries = @()
            }
        }
    }
    
    [void] InitializeForms() {
        $logger = Get-Logger
        $logger.Debug("SpeedTUI", "TimeTrackingScreen", "Initializing forms")
        
        # Create Add form
        $this.AddForm = [FormManager]::new()
        $logger.Debug("SpeedTUI", "TimeTrackingScreen", "AddForm created")
        
        # Add required fields with validation
        $projectId1Field = [InputField]::new("Project ID1", "e.g., PRJ001")
        $projectId1Field.Validator = [InputValidators]::Required()
        $this.AddForm.AddField($projectId1Field)
        
        $projectId2Field = [InputField]::new("Project ID2", "e.g., TASK01")
        $projectId2Field.Validator = [InputValidators]::Required()
        $this.AddForm.AddField($projectId2Field)
        
        $this.AddForm.AddTextField("Project Name", "e.g., Website Redesign")
        
        $weekEndingField = [InputField]::new("Week Ending (Friday)", "MM/dd/yyyy")
        $weekEndingField.Validator = [InputValidators]::Required()
        $weekEndingField.FieldType = "date"
        $this.AddForm.AddField($weekEndingField)
        $this.AddForm.AddNumberField("Monday Hours", "0.0")
        $this.AddForm.AddNumberField("Tuesday Hours", "0.0")
        $this.AddForm.AddNumberField("Wednesday Hours", "0.0")
        $this.AddForm.AddNumberField("Thursday Hours", "0.0")
        $this.AddForm.AddNumberField("Friday Hours", "0.0")
        
        $logger.Debug("SpeedTUI", "TimeTrackingScreen", "AddForm fields added", @{
            FieldCount = $this.AddForm.Fields.Count
        })
        
        # Create Edit form (same fields as Add form)
        $this.EditForm = [FormManager]::new()
        
        # Add required fields with validation (same as Add form)
        $editProjectId1Field = [InputField]::new("Project ID1", "e.g., PRJ001")
        $editProjectId1Field.Validator = [InputValidators]::Required()
        $this.EditForm.AddField($editProjectId1Field)
        
        $editProjectId2Field = [InputField]::new("Project ID2", "e.g., TASK01")
        $editProjectId2Field.Validator = [InputValidators]::Required()
        $this.EditForm.AddField($editProjectId2Field)
        
        $this.EditForm.AddTextField("Project Name", "e.g., Website Redesign")
        
        $editWeekEndingField = [InputField]::new("Week Ending (Friday)", "MM/dd/yyyy")
        $editWeekEndingField.Validator = [InputValidators]::Required()
        $editWeekEndingField.FieldType = "date"
        $this.EditForm.AddField($editWeekEndingField)
        
        $this.EditForm.AddNumberField("Monday Hours", "0.0")
        $this.EditForm.AddNumberField("Tuesday Hours", "0.0")
        $this.EditForm.AddNumberField("Wednesday Hours", "0.0")
        $this.EditForm.AddNumberField("Thursday Hours", "0.0")
        $this.EditForm.AddNumberField("Friday Hours", "0.0")
    }
    
    [void] InitializeCurrentWeek() {
        $today = [DateTime]::Today
        # Find Monday of this week (Monday = 1, Sunday = 0)
        $daysFromMonday = ($today.DayOfWeek - [DayOfWeek]::Monday + 7) % 7
        $this.CurrentWeekStarting = $today.AddDays(-$daysFromMonday)
        
        $logger = Get-Logger
        $logger.Debug("SpeedTUI", "TimeTrackingScreen", "Current week initialized", @{
            WeekStarting = $this.CurrentWeekStarting.ToString("yyyy-MM-dd")
            WeekEnding = $this.CurrentWeekStarting.AddDays(4).ToString("yyyy-MM-dd")
        })
    }
    
    [DateTime] GetCurrentWeekEnding() {
        return $this.CurrentWeekStarting.AddDays(4)  # Friday
    }
    
    [void] NavigateToNextWeek() {
        $this.CurrentWeekStarting = $this.CurrentWeekStarting.AddDays(7)
        $logger = Get-Logger
        $logger.Debug("SpeedTUI", "TimeTrackingScreen", "Navigated to next week", @{
            WeekStarting = $this.CurrentWeekStarting.ToString("yyyy-MM-dd")
        })
    }
    
    [void] NavigateToPreviousWeek() {
        $this.CurrentWeekStarting = $this.CurrentWeekStarting.AddDays(-7)
        $logger = Get-Logger  
        $logger.Debug("SpeedTUI", "TimeTrackingScreen", "Navigated to previous week", @{
            WeekStarting = $this.CurrentWeekStarting.ToString("yyyy-MM-dd")
        })
    }
    
    [array] GetCurrentWeekEntries() {
        $weekStarting = $this.CurrentWeekStarting
        $weekEnding = $this.GetCurrentWeekEnding()
        $weekEndingString = $weekEnding.ToString("yyyyMMdd")
        
        # Filter entries for this specific week
        $weekEntries = $this.TimeEntries | Where-Object { 
            $_.WeekEndingFriday -eq $weekEndingString 
        }
        
        return $weekEntries
    }
    
    [string[]] Render() {
        $timing = Start-PerformanceTiming "TimeTrackingScreen.Render"
        $logger = Get-Logger
        
        $logger.Trace("SpeedTUI", "TimeTrackingScreen", "Render start", @{
            ViewMode = $this.ViewMode
            TimeEntriesCount = $(if ($this.TimeEntries) { $this.TimeEntries.Count } else { 0 })
            AddFormExists = $null -ne $this.AddForm
            EditFormExists = $null -ne $this.EditForm
        })
        
        try {
            $lines = @()
            
            # Header
            $lines += $this.RenderHeader()
            $lines += ""
            
            switch ($this.ViewMode) {
                "List" {
                    $lines += $this.RenderTimeEntriesList()
                }
                "Add" {
                    $lines += $this.RenderAddEntry()
                }
                "Edit" {
                    $lines += $this.RenderEditEntry()
                }
                "Delete" {
                    $lines += $this.RenderDeleteConfirmation()
                }
            }
            
            $lines += ""
            $lines += $this.RenderControls()
            
            return $lines
            
        } finally {
            Stop-PerformanceTiming $timing
        }
    }
    
    [string[]] RenderHeader() {
        $lines = @()
        $currentFY = $(if ($this.TimeService) { $this.TimeService.CurrentFiscalYear } else { "N/A" })
        
        # Get current week entries and totals
        $weekEntries = $this.GetCurrentWeekEntries()
        $totalEntries = $weekEntries.Count
        $totalHours = 0
        
        if ($weekEntries -and $weekEntries.Count -gt 0) {
            $sumResult = ($weekEntries | Measure-Object -Property Total -Sum)
            if ($sumResult -and $null -ne $sumResult.Sum) {
                $totalHours = $sumResult.Sum
            }
        }
        
        # Format current week display
        $weekStarting = $this.CurrentWeekStarting.ToString("MM/dd/yy")
        $weekEnding = $this.GetCurrentWeekEnding().ToString("MM/dd/yy")
        $weekDisplay = "$weekStarting - $weekEnding"
        
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::ContentLine("TIME TRACKING - WEEK $weekDisplay".PadLeft(([Console]::WindowWidth - 35) / 2 + 30))
        $lines += [BorderHelper]::ContentLine("Fiscal Year: $($currentFY.PadRight(15)) │ This Week Entries: $($totalEntries.ToString().PadLeft(2)) │ Week Hours: $($totalHours.ToString('F1').PadLeft(6))")
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string[]] RenderTimeEntriesList() {
        $lines = @()
        
        # Get current week entries only
        $weekEntries = $this.GetCurrentWeekEntries()
        $weekStarting = $this.CurrentWeekStarting.ToString("MM/dd/yy")  
        $weekEnding = $this.GetCurrentWeekEnding().ToString("MM/dd/yy")
        
        $lines += [BorderHelper]::TopBorder()
        $lines += [BorderHelper]::ContentLine("Week: $weekStarting - $weekEnding                    ← → to change weeks")
        $lines += [BorderHelper]::MiddleBorder()
        
        if ($weekEntries.Count -eq 0) {
            $lines += [BorderHelper]::ContentLine("No time entries found for this week. Press 'A' to add an entry.")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::EmptyLine()
        } else {
            $lines += [BorderHelper]::ContentLine("Project Name                    │ ID1    │ ID2      │ Mon │ Tue │ Wed │ Thu │ Fri │ Total")
            $lines += [BorderHelper]::MiddleBorder()
            
            # Show current week entries
            $index = 0
            foreach ($entry in $weekEntries) {
                $marker = $(if ($index -eq $this.SelectedEntry) { "►" } else { " " })
                
                # Format name (project name or ID2 for non-project)
                $nameStr = $(if ($entry.Name) { $entry.Name } else { $entry.ID2 })
                $nameStr = "$marker$nameStr".PadRight(32)
                if ($nameStr.Length -gt 32) { $nameStr = $nameStr.Substring(0, 29) + "..." }
                
                # Format IDs
                $id1Str = $entry.ID1.PadRight(6)
                if ($id1Str.Length -gt 6) { $id1Str = $id1Str.Substring(0, 6) }
                $id2Str = $entry.ID2.PadRight(8)
                if ($id2Str.Length -gt 8) { $id2Str = $id2Str.Substring(0, 8) }
                
                # Format daily hours
                $monStr = $entry.Monday.ToString("F1").PadLeft(3)
                $tueStr = $entry.Tuesday.ToString("F1").PadLeft(3)
                $wedStr = $entry.Wednesday.ToString("F1").PadLeft(3)
                $thuStr = $entry.Thursday.ToString("F1").PadLeft(3)
                $friStr = $entry.Friday.ToString("F1").PadLeft(3)
                $totalStr = $entry.Total.ToString("F1").PadLeft(5)
                
                $lines += [BorderHelper]::ContentLine("$nameStr │ $id1Str │ $id2Str │ $monStr │ $tueStr │ $wedStr │ $thuStr │ $friStr │ $totalStr")
                $index++
            }
            
            # Fill remaining lines to maintain consistent height
            while ($index -lt 5) {
                $lines += [BorderHelper]::EmptyLine()
                $index++
            }
        }
        
        $lines += [BorderHelper]::BottomBorder()
        
        return $lines
    }
    
    [string[]] RenderAddEntry() {
        $lines = @()
        $lines += "┌─ Add New Time Entry " + ("─" * ([Console]::WindowWidth - 23)) + "┐"
        $lines += [BorderHelper]::EmptyLine()
        
        # Render the form with null check
        if ($null -ne $this.AddForm) {
            try {
                $width = [Math]::Max(40, [Console]::WindowWidth - 6)
                $formLines = $this.AddForm.Render($width)
                foreach ($line in $formLines) {
                    $lines += [BorderHelper]::ContentLine($line)
                }
            } catch {
                $lines += [BorderHelper]::ContentLine("Error rendering form: $($_.Exception.Message)")
            }
        } else {
            $lines += [BorderHelper]::ContentLine("Form not initialized")
        }
        
        $lines += [BorderHelper]::EmptyLine()
        $lines += [BorderHelper]::ContentLine("Tab/Shift+Tab: Navigate fields | Enter: Save | Esc: Cancel")
        $lines += [BorderHelper]::EmptyLine()
        $lines += "└" + ("─" * ([Console]::WindowWidth - 2)) + "┘"
        
        return $lines
    }
    
    [string[]] RenderEditEntry() {
        $lines = @()
        $lines += "┌─ Edit Time Entry " + ("─" * ([Console]::WindowWidth - 20)) + "┐"
        $lines += [BorderHelper]::EmptyLine()
        
        # Show which entry is being edited
        if ($this.SelectedEntry -lt $this.TimeEntries.Count) {
            $entry = $this.TimeEntries[$this.SelectedEntry]
            $lines += [BorderHelper]::ContentLine("Editing: $($entry.Name) - Week ending $($entry.WeekEndingFriday)")
            $lines += [BorderHelper]::EmptyLine()
        }
        
        # Render the edit form with null check
        if ($null -ne $this.EditForm) {
            try {
                $width = [Math]::Max(40, [Console]::WindowWidth - 6)
                $formLines = $this.EditForm.Render($width)
                foreach ($line in $formLines) {
                    $lines += [BorderHelper]::ContentLine($line)
                }
            } catch {
                $lines += [BorderHelper]::ContentLine("Error rendering form: $($_.Exception.Message)")
            }
        } else {
            $lines += [BorderHelper]::ContentLine("Edit form not initialized")
        }
        
        $lines += [BorderHelper]::EmptyLine()
        $lines += [BorderHelper]::ContentLine("Tab/Shift+Tab: Navigate fields | Enter: Save | Esc: Cancel")
        $lines += [BorderHelper]::EmptyLine()
        $lines += "└" + ("─" * ([Console]::WindowWidth - 2)) + "┘"
        
        return $lines
    }
    
    [string[]] RenderDeleteConfirmation() {
        $lines = @()
        $lines += "┌─ Delete Time Entry " + ("─" * ([Console]::WindowWidth - 22)) + "┐"
        $lines += [BorderHelper]::EmptyLine()
        
        # Show which entry will be deleted
        if ($this.SelectedEntry -lt $this.TimeEntries.Count) {
            $entry = $this.TimeEntries[$this.SelectedEntry]
            $lines += [BorderHelper]::ContentLine("[WARN]️  WARNING: You are about to delete this time entry:")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("   Project: $($entry.Name)")
            $lines += [BorderHelper]::ContentLine("   ID1: $($entry.ID1)     ID2: $($entry.ID2)")
            $lines += [BorderHelper]::ContentLine("   Week Ending: $($entry.WeekEndingFriday)")
            $lines += [BorderHelper]::ContentLine("   Total Hours: $($entry.Total.ToString('F1'))")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("❗ This action cannot be undone!")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("Are you sure you want to delete this entry?")
            $lines += [BorderHelper]::EmptyLine()
            $lines += [BorderHelper]::ContentLine("Press Y to confirm deletion, or any other key to cancel")
        } else {
            $lines += [BorderHelper]::ContentLine("No entry selected for deletion")
        }
        
        $lines += [BorderHelper]::EmptyLine()
        $lines += "└" + ("─" * ([Console]::WindowWidth - 2)) + "┘"
        
        return $lines
    }
    
    [string[]] RenderControls() {
        $lines = @()
        $lines += "┌─ Controls " + ("─" * ([Console]::WindowWidth - 13)) + "┐"
        
        switch ($this.ViewMode) {
            "List" {
                $lines += [BorderHelper]::ContentLine("A - Add │ E - Edit │ D - Delete │ ← → Change Week │ ↑↓ Select Entry │ B - Back │ Q - Quit")
            }
            "Add" {
                $lines += [BorderHelper]::ContentLine("S - Save Entry │ C - Cancel │ Tab - Next Field │ Shift+Tab - Previous Field")
            }
            "Edit" {
                $lines += [BorderHelper]::ContentLine("S - Save Changes │ C - Cancel │ Tab - Next Field │ Shift+Tab - Previous Field")
            }
            "Delete" {
                $lines += [BorderHelper]::ContentLine("Y - Confirm Delete │ Any other key - Cancel and return to list")
            }
        }
        
        $lines += "└" + ("─" * ([Console]::WindowWidth - 2)) + "┘"
        
        return $lines
    }
    
    [string] HandleInput([string]$key) {
        $timing = Start-PerformanceTiming "TimeTrackingScreen.HandleInput" @{ key = $key }
        
        try {
            switch ($this.ViewMode) {
                "List" {
                    return $this.HandleListInput($key)
                }
                "Add" {
                    return $this.HandleAddInput($key)
                }
                "Edit" {
                    return $this.HandleEditInput($key)
                }
                "Delete" {
                    return $this.HandleDeleteInput($key)
                }
            }
        } finally {
            Stop-PerformanceTiming $timing
        }
        return "CONTINUE"
    }
    
    [string] HandleKey([System.ConsoleKeyInfo]$keyInfo) {
        # Direct key handling for forms
        switch ($this.ViewMode) {
            "Add" {
                return $this.HandleAddInputKey($keyInfo)
            }
            "Edit" {
                return $this.HandleEditInputKey($keyInfo)
            }
            default {
                # For list mode, use string-based handling
                $keyString = $keyInfo.Key.ToString()
                if ($keyInfo.Modifiers -band [ConsoleModifiers]::Control) {
                    $keyString = "Ctrl+$keyString"
                }
                return $this.HandleInput($keyString)
            }
        }
        return "CONTINUE"
    }
    
    [string] HandleListInput([string]$key) {
        switch ($key.ToUpper()) {
            'A' {
                $this.ViewMode = "Add"
                $this.InitializeNewEntry()
                return "REFRESH"
            }
            'E' {
                if ($this.TimeEntries.Count -gt 0) {
                    $this.ViewMode = "Edit"
                    $this.InitializeEditEntry()
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'D' {
                if ($this.TimeEntries.Count -gt 0) {
                    $this.ViewMode = "Delete"
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'R' {
                $this.RefreshData()
                return "REFRESH"
            }
            'F' {
                Write-Host "Filter feature not yet implemented" -ForegroundColor Yellow
                return "CONTINUE"
            }
            'B' {
                return "DASHBOARD"
            }
            'Q' {
                return "EXIT"
            }
            'LeftArrow' {
                $this.NavigateToPreviousWeek()
                $this.SelectedEntry = 0  # Reset selection to first entry
                return "REFRESH"
            }
            'RightArrow' {
                $this.NavigateToNextWeek()
                $this.SelectedEntry = 0  # Reset selection to first entry
                return "REFRESH"
            }
            'UpArrow' {
                $weekEntries = $this.GetCurrentWeekEntries()
                if ($this.SelectedEntry -gt 0) {
                    $this.SelectedEntry--
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            'DownArrow' {
                $weekEntries = $this.GetCurrentWeekEntries()
                if ($this.SelectedEntry -lt ($weekEntries.Count - 1)) {
                    $this.SelectedEntry++
                    return "REFRESH"
                }
                return "CONTINUE"
            }
            default {
                return "CONTINUE"
            }
        }
        return "CONTINUE"
    }
    
    [string] HandleAddInput([string]$key) {
        # For form mode, we need the actual ConsoleKeyInfo
        # This is a temporary solution - we'll need to pass the actual key from main loop
        
        # Handle special navigation keys first
        switch ($key) {
            'Escape' {
                $this.AddForm.Clear()
                $this.AddForm.Deactivate()
                $this.ViewMode = "List"
                return "REFRESH"
            }
        }
        
        # For now, return refresh to show typed characters
        # The real input handling will need to be refactored
        return "REFRESH"
    }
    
    [string] HandleAddInputKey([System.ConsoleKeyInfo]$keyInfo) {
        # This is the proper handler for form input
        $result = $this.AddForm.HandleInput($keyInfo)
        
        switch ($result) {
            "SUBMIT" {
                $this.SaveNewEntry()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            "CANCEL" {
                $this.AddForm.Clear()
                $this.AddForm.Deactivate()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            "REFRESH" {
                return "REFRESH"
            }
            default {
                return "CONTINUE"
            }
        }
        return "CONTINUE"
    }
    
    [string] HandleEditInput([string]$key) {
        switch ($key.ToUpper()) {
            'S' {
                $this.ViewMode = "List"
                return "REFRESH"
            }
            'C' {
                $this.ViewMode = "List"
                return "REFRESH"
            }
            default {
                return "CONTINUE"
            }
        }
        return "CONTINUE"
    }
    
    [string] HandleDeleteInput([string]$key) {
        $logger = Get-Logger
        $logger.Debug("SpeedTUI", "TimeTrackingScreen", "Delete confirmation input", @{
            Key = $key
            SelectedEntry = $this.SelectedEntry
        })
        
        switch ($key.ToUpper()) {
            'Y' {
                # Confirm deletion
                $this.ConfirmDeleteSelectedEntry()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            default {
                # Cancel deletion
                $logger.Debug("SpeedTUI", "TimeTrackingScreen", "Delete cancelled by user")
                $this.ViewMode = "List"
                return "REFRESH"
            }
        }
        return "CONTINUE"
    }
    
    [string] HandleEditInputKey([System.ConsoleKeyInfo]$keyInfo) {
        # This is the proper handler for edit form input
        $result = $this.EditForm.HandleInput($keyInfo)
        
        switch ($result) {
            "SUBMIT" {
                $this.SaveEditedEntry()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            "CANCEL" {
                $this.EditForm.Clear()
                $this.EditForm.Deactivate()
                $this.ViewMode = "List"
                return "REFRESH"
            }
            "REFRESH" {
                return "REFRESH"
            }
            default {
                return "CONTINUE"
            }
        }
        return "CONTINUE"
    }
    
    [void] InitializeEditEntry() {
        if ($this.SelectedEntry -ge $this.TimeEntries.Count) {
            return
        }
        
        $entry = $this.TimeEntries[$this.SelectedEntry]
        
        # Clear and activate the edit form
        $this.EditForm.Clear()
        $this.EditForm.Activate()
        
        # Populate form with existing data
        $this.EditForm.SetFieldValue("Project ID1", $entry.ID1)
        $this.EditForm.SetFieldValue("Project ID2", $entry.ID2)
        $this.EditForm.SetFieldValue("Project Name", $entry.Name)
        
        # Format the week ending date
        if ($entry.WeekEndingFriday) {
            try {
                $weekDate = [DateTime]::ParseExact($entry.WeekEndingFriday, "yyyyMMdd", $null)
                $this.EditForm.SetFieldValue("Week Ending (Friday)", $weekDate.ToString("MM/dd/yyyy"))
            } catch {
                $this.EditForm.SetFieldValue("Week Ending (Friday)", $entry.WeekEndingFriday)
            }
        }
        
        # Set the daily hours
        $this.EditForm.SetFieldValue("Monday Hours", $entry.Monday.ToString("F1"))
        $this.EditForm.SetFieldValue("Tuesday Hours", $entry.Tuesday.ToString("F1"))
        $this.EditForm.SetFieldValue("Wednesday Hours", $entry.Wednesday.ToString("F1"))
        $this.EditForm.SetFieldValue("Thursday Hours", $entry.Thursday.ToString("F1"))
        $this.EditForm.SetFieldValue("Friday Hours", $entry.Friday.ToString("F1"))
        
        $logger = Get-Logger
        $logger.Debug("SpeedTUI", "TimeTrackingScreen", "Edit entry initialized", @{
            EntryId = $entry.Id
            EntryName = $entry.Name
            SelectedIndex = $this.SelectedEntry
        })
    }
    
    [void] SaveEditedEntry() {
        try {
            if ($this.SelectedEntry -ge $this.TimeEntries.Count) {
                throw "No entry selected for editing"
            }
            
            # Get form data
            $formData = $this.EditForm.GetFormData()
            
            if ($null -eq $formData -or $formData.Count -eq 0) {
                throw "No form data available"
            }
            
            # Get the existing entry
            $entry = $this.TimeEntries[$this.SelectedEntry]
            
            # Parse week ending date
            $weekEndingText = $formData["Week Ending (Friday)"]
            if ([string]::IsNullOrWhiteSpace($weekEndingText)) {
                throw "Week ending date is required"
            }
            
            $weekEndingDate = [DateTime]::MinValue
            if (-not [DateTime]::TryParse($weekEndingText, [ref]$weekEndingDate)) {
                throw "Invalid date format. Please use MM/dd/yyyy"
            }
            
            if ($weekEndingDate.DayOfWeek -ne [DayOfWeek]::Friday) {
                throw "Week ending date must be a Friday"
            }
            
            # Update the entry with new values
            $entry.WeekEndingFriday = $weekEndingDate.ToString("yyyyMMdd")
            $entry.ID1 = $formData["Project ID1"]
            $entry.ID2 = $formData["Project ID2"]
            $entry.Name = $formData["Project Name"]
            
            # Parse hours with null/empty handling
            $mondayText = $(if ($formData["Monday Hours"]) { $formData["Monday Hours"] } else { "0" })
            $tuesdayText = $(if ($formData["Tuesday Hours"]) { $formData["Tuesday Hours"] } else { "0" })
            $wednesdayText = $(if ($formData["Wednesday Hours"]) { $formData["Wednesday Hours"] } else { "0" })
            $thursdayText = $(if ($formData["Thursday Hours"]) { $formData["Thursday Hours"] } else { "0" })
            $fridayText = $(if ($formData["Friday Hours"]) { $formData["Friday Hours"] } else { "0" })
            
            $entry.Monday = $(if ([string]::IsNullOrWhiteSpace($mondayText)) { 0 } else { [decimal]($mondayText -replace '[^0-9.]', '') })
            $entry.Tuesday = $(if ([string]::IsNullOrWhiteSpace($tuesdayText)) { 0 } else { [decimal]($tuesdayText -replace '[^0-9.]', '') })
            $entry.Wednesday = $(if ([string]::IsNullOrWhiteSpace($wednesdayText)) { 0 } else { [decimal]($wednesdayText -replace '[^0-9.]', '') })
            $entry.Thursday = $(if ([string]::IsNullOrWhiteSpace($thursdayText)) { 0 } else { [decimal]($thursdayText -replace '[^0-9.]', '') })
            $entry.Friday = $(if ([string]::IsNullOrWhiteSpace($fridayText)) { 0 } else { [decimal]($fridayText -replace '[^0-9.]', '') })
            
            $entry.CalculateTotal()
            
            # Update the entry in the service
            $this.TimeService.Update($entry)
            $this.RefreshData()
            
            # Clear form
            $this.EditForm.Clear()
            $this.EditForm.Deactivate()
            
            $logger = Get-Logger
            $logger.Debug("SpeedTUI", "TimeTrackingScreen", "Entry updated successfully", @{
                EntryId = $entry.Id
                EntryName = $entry.Name
            })
            
            $this.PerformanceMonitor.IncrementCounter("screen.timetracking.entry_updated", @{})
        } catch {
            $logger = Get-Logger
            $logger.Error("SpeedTUI", "TimeTrackingScreen", "Error updating time entry", @{
                Exception = $_.Exception.Message
                SelectedEntry = $this.SelectedEntry
            })
            # Don't clear form on error so user can fix validation issues
        }
    }
    
    [void] RefreshData() {
        try {
            $this.TimeEntries = $this.TimeService.GetAll()
            $this.LastRefresh = [DateTime]::Now
            $this.PerformanceMonitor.IncrementCounter("screen.timetracking.refresh", @{})
        } catch {
            Write-Host "Error refreshing time entries: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] InitializeNewEntry() {
        $this.NewEntry = @{
            Date = [DateTime]::Today
            Project = ""
            Task = ""
            Hours = 0.0
            Description = ""
        }
        
        # Clear and activate the form
        $this.AddForm.Clear()
        $this.AddForm.Activate()
        
        # Set week ending to the current viewing week's Friday
        $currentWeekFriday = $this.GetCurrentWeekEnding()
        $this.AddForm.SetFieldValue("Week Ending (Friday)", $currentWeekFriday.ToString("MM/dd/yyyy"))
    }
    
    [void] SaveNewEntry() {
        try {
            # Get form data
            $formData = $this.AddForm.GetFormData()
            
            if ($null -eq $formData -or $formData.Count -eq 0) {
                throw "No form data available"
            }
            
            # Parse week ending date
            $weekEndingText = $formData["Week Ending (Friday)"]
            if ([string]::IsNullOrWhiteSpace($weekEndingText)) {
                throw "Week ending date is required"
            }
            
            $weekEndingDate = [DateTime]::MinValue
            if (-not [DateTime]::TryParse($weekEndingText, [ref]$weekEndingDate)) {
                throw "Invalid date format. Please use MM/dd/yyyy"
            }
            
            if ($weekEndingDate.DayOfWeek -ne [DayOfWeek]::Friday) {
                throw "Week ending date must be a Friday"
            }
            
            # Create new time entry
            $entry = [TimeEntry]::new()
            $entry.WeekEndingFriday = $weekEndingDate.ToString("yyyyMMdd")
            $entry.ID1 = $formData["Project ID1"]
            $entry.ID2 = $formData["Project ID2"]
            $entry.Name = $formData["Project Name"]
            # Parse hours with null/empty handling
            $mondayText = $(if ($formData["Monday Hours"]) { $formData["Monday Hours"] } else { "0" })
            $tuesdayText = $(if ($formData["Tuesday Hours"]) { $formData["Tuesday Hours"] } else { "0" })
            $wednesdayText = $(if ($formData["Wednesday Hours"]) { $formData["Wednesday Hours"] } else { "0" })
            $thursdayText = $(if ($formData["Thursday Hours"]) { $formData["Thursday Hours"] } else { "0" })
            $fridayText = $(if ($formData["Friday Hours"]) { $formData["Friday Hours"] } else { "0" })
            
            $entry.Monday = $(if ([string]::IsNullOrWhiteSpace($mondayText)) { 0 } else { [decimal]($mondayText -replace '[^0-9.]', '') })
            $entry.Tuesday = $(if ([string]::IsNullOrWhiteSpace($tuesdayText)) { 0 } else { [decimal]($tuesdayText -replace '[^0-9.]', '') })
            $entry.Wednesday = $(if ([string]::IsNullOrWhiteSpace($wednesdayText)) { 0 } else { [decimal]($wednesdayText -replace '[^0-9.]', '') })
            $entry.Thursday = $(if ([string]::IsNullOrWhiteSpace($thursdayText)) { 0 } else { [decimal]($thursdayText -replace '[^0-9.]', '') })
            $entry.Friday = $(if ([string]::IsNullOrWhiteSpace($fridayText)) { 0 } else { [decimal]($fridayText -replace '[^0-9.]', '') })
            $entry.IsProjectEntry = $true
            $entry.CalculateTotal()
            
            # Save the entry
            $this.TimeService.Create($entry)
            $this.RefreshData()
            
            # Clear form
            $this.AddForm.Clear()
            $this.AddForm.Deactivate()
            
            Write-Host "Time entry saved successfully!" -ForegroundColor Green
            $this.PerformanceMonitor.IncrementCounter("screen.timetracking.entry_added", @{})
        } catch {
            Write-Host "Error saving time entry: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    [void] ConfirmDeleteSelectedEntry() {
        if ($this.TimeEntries.Count -eq 0 -or $this.SelectedEntry -ge $this.TimeEntries.Count) {
            return
        }
        
        try {
            $entry = $this.TimeEntries[$this.SelectedEntry]
            $logger = Get-Logger
            
            $logger.Debug("SpeedTUI", "TimeTrackingScreen", "Deleting time entry", @{
                EntryId = $entry.Id
                EntryName = $entry.Name
                SelectedIndex = $this.SelectedEntry
            })
            
            $this.TimeService.Remove($entry.Id)
            $this.RefreshData()
            
            # Adjust selection if needed
            if ($this.SelectedEntry -ge $this.TimeEntries.Count -and $this.TimeEntries.Count -gt 0) {
                $this.SelectedEntry = $this.TimeEntries.Count - 1
            }
            
            $logger.Debug("SpeedTUI", "TimeTrackingScreen", "Time entry deleted successfully", @{
                EntryId = $entry.Id
                RemainingEntries = $this.TimeEntries.Count
            })
            $this.PerformanceMonitor.IncrementCounter("screen.timetracking.entry_deleted", @{})
        } catch {
            $logger = Get-Logger
            $logger.Error("SpeedTUI", "TimeTrackingScreen", "Error deleting time entry", @{
                Exception = $_.Exception.Message
                SelectedEntry = $this.SelectedEntry
            })
        }
    }
}