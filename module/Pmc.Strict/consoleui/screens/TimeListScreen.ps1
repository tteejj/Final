using namespace System.Collections.Generic
using namespace System.Text

# TimeListScreen - Time tracking list with full CRUD operations
# Uses UniversalList widget and InlineEditor for consistent UX


Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../widgets/TimeEntryDetailDialog.ps1"

# LOW FIX TLS-L2, L3, L4: Define constants for magic numbers and limits
$global:MAX_TASK_LENGTH = 200
$global:MAX_TASK_TRUNCATE_LENGTH = 197
$global:MAX_NOTES_LENGTH = 300
$global:MAX_NOTES_TRUNCATE_LENGTH = 297
$global:MAX_HOURS_PER_ENTRY = 24
$global:MIN_HOURS_PER_ENTRY = 0.25
$script:DIALOG_TIMEOUT_ITERATIONS = 36000  # 36000 * 50ms = 30 minutes
$script:DIALOG_POLL_INTERVAL_MS = 50

<#
.SYNOPSIS
Time tracking list screen with CRUD operations

.DESCRIPTION
Shows all time entries with:
- Add/Edit/Delete via InlineEditor (a/e/d keys)
- View entries by task or project
- Generate time reports
- Automatic aggregation by date/project/timecode
- Press Enter on aggregated entries (shown with count) to see individual entries
- Filter by date range
#>
class TimeListScreen : StandardListScreen {

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Time', 'Time Tracking', 'T', {
            . "$PSScriptRoot/TimeListScreen.ps1"
            $global:PmcApp.PushScreen((New-Object -TypeName TimeListScreen))
        }, 5)
    }

    # LOW FIX TLS-L1: Extract common initialization to helper method (DRY principle)
    hidden [void] ConfigureCapabilities() {
        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $true

        # Configure inline editor layout mode for horizontal (inline) editing
        $this.InlineEditor.LayoutMode = 'horizontal'

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Time Tracking"))

        # Load time entries
        $this.RefreshList()
    }

    # Constructor
    TimeListScreen() : base("TimeList", "Time Tracking") {
        $this.ConfigureCapabilities()
    }

    # Constructor with container (DI-enabled)
    TimeListScreen([object]$container) : base("TimeList", "Time Tracking", $container) {
        # Write-PmcTuiLog "TimeListScreen: Constructor called, about to ConfigureCapabilities"
        $this.ConfigureCapabilities()
        # Write-PmcTuiLog "TimeListScreen: Constructor complete"
    }

    # === Abstract Method Implementations ===

    # Get entity type for store operations
    [string] GetEntityType() {
        return 'timelog'
    }

    # Define columns for list display
    [array] GetColumns() {
        return @(
            @{ Name='date_display'; Label='Date'; Width=12 },
            @{ Name='task'; Label='Task'; Width=25 },
            @{ Name='project'; Label='Project'; Width=16 },
            @{ Name='id1'; Label='ID1'; Width=10 },
            @{ Name='id2'; Label='ID2'; Width=10 },
            @{ Name='duration'; Label='Duration'; Width=18 },
            @{ Name='notes'; Label='Notes'; Width=40 }
        )
    }

    # Load data and refresh list (required by StandardListScreen)
    [void] LoadData() {
        # Write-PmcTuiLog "TimeListScreen.LoadData: START"
        $items = $this.LoadItems()
        # Write-PmcTuiLog "TimeListScreen.LoadData: LoadItems completed, checking type"
        # Write-PmcTuiLog "TimeListScreen.LoadData: items type=$($items.GetType().FullName)"
        if ($null -eq $items) {
            # Write-PmcTuiLog "TimeListScreen.LoadData: items is null, setting to empty array" "WARNING"
            $items = @()
        }
        # Write-PmcTuiLog "TimeListScreen.LoadData: About to count items"
        $itemCount = $(if ($items -is [array]) { $items.Count } else { 1 })
        # Write-PmcTuiLog "TimeListScreen.LoadData: LoadItems returned $itemCount items"
        # Write-PmcTuiLog "TimeListScreen.LoadData: Calling SetData"
        $this.List.SetData($items)
        # Write-PmcTuiLog "TimeListScreen.LoadData: COMPLETE"
    }

    # Load items from data store
    [array] LoadItems() {
        # CRITICAL FIX TLS-C1: Add null check on GetAllTimeLogs()
        $entries = $this.Store.GetAllTimeLogs()
        if ($null -eq $entries) {
            # Write-PmcTuiLog "TimeListScreen.LoadItems: GetAllTimeLogs() returned null" "ERROR"
            $entries = @()
        }

        # TS-M1 FIX: Track failed date parses to provide user feedback
        $failedDateParses = 0

        # Group entries by date, project, and timecode
        $grouped = @{}
        foreach ($entry in $entries) {
            # TIM-1 FIX: Format date for grouping with error handling
            $dateStr = ''
            if ($entry.ContainsKey('date') -and $entry.date) {
                try {
                    if ($entry.date -is [DateTime]) {
                        $dateStr = $entry.date.ToString('yyyy-MM-dd')
                    } else {
                        # Try to parse as DateTime
                        $parsedDate = [DateTime]::Parse($entry.date)
                        $dateStr = $parsedDate.ToString('yyyy-MM-dd')
                    }
                } catch {
                    # TS-M1 FIX: Instead of empty string, use original date value with marker
                    # This preserves data context and prevents incorrect grouping
                    $dateStr = "INVALID:$($entry.date)"
                    $failedDateParses++
                    # Write-PmcTuiLog "TimeListScreen.LoadItems: Failed to parse date '$($entry.date)': $_" "WARNING"
                }
            }

            # Create grouping key
            # TS-M3 FIX: Sanitize components to prevent pipe character breaking grouping
            $project = $(if ($entry.ContainsKey('project')) { $entry.project } else { '' })
            $id1 = $(if ($entry.ContainsKey('id1')) { $entry.id1 } else { '' })

            # Replace pipe characters in components to prevent grouping key corruption
            $dateStrSafe = $dateStr -replace '\|', '_'
            $projectSafe = $project -replace '\|', '_'
            $id1Safe = $id1 -replace '\|', '_'

            $groupKey = "$dateStrSafe|$projectSafe|$id1Safe"

            # Initialize group if needed
            if (-not $grouped.ContainsKey($groupKey)) {
                $grouped[$groupKey] = @{
                    date = $entry.date
                    date_display = $dateStr
                    project = $project
                    id1 = $id1
                    id2 = $(if ($entry.ContainsKey('id2')) { $entry.id2 } else { '' })
                    task = $(if ($entry.ContainsKey('task')) { $entry.task } else { '' })
                    notes = $(if ($entry.ContainsKey('notes')) { $entry.notes } else { '' })
                    minutes = 0
                    entry_count = 0
                    entry_ids = @()
                }
            }

            # Aggregate minutes
            if ($entry.ContainsKey('minutes')) {
                $grouped[$groupKey].minutes += $entry.minutes
            }
            $grouped[$groupKey].entry_count++
            if ($entry.ContainsKey('id')) {
                $grouped[$groupKey].entry_ids += $entry.id
            }

            # Store original entry for drill-down
            if (-not $grouped[$groupKey].ContainsKey('original_entries')) {
                $grouped[$groupKey].original_entries = @()
            }
            $grouped[$groupKey].original_entries += $entry

            # TS-M3 FIX: Simplify task/notes concatenation and prevent excessive string length
            # MEDIUM FIX TLS-M1: Use script-level constants for length limits
            # Concatenate tasks if multiple (with length limit to prevent memory issues)
            if ($entry.ContainsKey('task') -and $entry.task) {
                $currentTask = $grouped[$groupKey].task
                if ($currentTask -and $currentTask -ne $entry.task) {
                    # Limit concatenated task length to prevent excessive growth
                    $newTask = "$currentTask; $($entry.task)"
                    $grouped[$groupKey].task = $(if ($newTask.Length -gt $global:MAX_TASK_LENGTH) {
                        $newTask.Substring(0, $global:MAX_TASK_TRUNCATE_LENGTH) + "..."
                    } else {
                        $newTask
                    })
                } elseif (-not $currentTask) {
                    $grouped[$groupKey].task = $entry.task
                }
            }

            # Concatenate notes if multiple (with length limit to prevent memory issues)
            # MEDIUM FIX TLS-M1: Use script-level constants for length limits
            if ($entry.ContainsKey('notes') -and $entry.notes) {
                $currentNotes = $grouped[$groupKey].notes
                if ($currentNotes -and $currentNotes -ne $entry.notes) {
                    # Limit concatenated notes length to prevent excessive growth
                    $newNotes = "$currentNotes; $($entry.notes)"
                    $grouped[$groupKey].notes = $(if ($newNotes.Length -gt $global:MAX_NOTES_LENGTH) {
                        $newNotes.Substring(0, $global:MAX_NOTES_TRUNCATE_LENGTH) + "..."
                    } else {
                        $newNotes
                    })
                } elseif (-not $currentNotes) {
                    $grouped[$groupKey].notes = $entry.notes
                }
            }
        }

        # Convert to array and format
        $aggregated = @()
        foreach ($key in $grouped.Keys) {
            $entry = $grouped[$key]

            # Format duration as HH:MM with null checks
            # CRITICAL FIX TLS-C2: Validate numeric type before division/modulo
            if ($entry.ContainsKey('minutes') -and $null -ne $entry.minutes) {
                $numericMinutes = 0
                if ([double]::TryParse($entry.minutes, [ref]$numericMinutes)) {
                    $hours = [int][Math]::Floor($numericMinutes / 60)
                    $mins = [int]($numericMinutes % 60)
                    $entry['duration'] = "{0:D2}:{1:D2}" -f $hours, $mins
                } else {
                    # Write-PmcTuiLog "TimeListScreen.LoadItems: Invalid minutes value: $($entry.minutes)" "WARNING"
                    $entry['duration'] = "00:00"
                }
            } else {
                $entry['duration'] = "00:00"
            }

            # Add indicator if aggregated
            if ($entry.entry_count -gt 1) {
                $entry['duration'] = "$($entry.duration) ($($entry.entry_count))"
            }

            # DEBUG: Log the keys in this entry
            $keysStr = ($entry.Keys | Sort-Object) -join ', '
            # Write-PmcTuiLog "TimeListScreen.LoadItems: Created entry with keys: $keysStr"
            # Write-PmcTuiLog "TimeListScreen.LoadItems: date_display='$($entry.date_display)' date='$($entry.date)'"

            $aggregated += $entry
        }

        # TS-M1 FIX: Notify user if there were failed date parses
        if ($failedDateParses -gt 0) {
            # Write-PmcTuiLog "TimeListScreen.LoadItems: $failedDateParses time entries had unparseable dates" "WARNING"
            $this.SetStatusMessage("Warning: $failedDateParses entries have invalid dates", "warning")
        }

        # Sort by date descending (most recent first)
        # HIGH FIX TLS-H5: Handle null dates in sort
        $sorted = $aggregated | Sort-Object { if ($null -ne $_.date) { $_.date } else { [DateTime]::MaxValue } } -Descending
        # Ensure we always return an array (PowerShell returns single object if count=1)
        return @($sorted)
    }

    # Define columns for list display
    [array] GetListColumns() {
        return @(
            @{ Name='date_display'; Header='Date'; Width=12 }
            @{ Name='task'; Header='Task'; Width=25 }
            @{ Name='project'; Header='Project'; Width=16 }
            @{ Name='id1'; Header='ID1/Code'; Width=10 }
            @{ Name='id2'; Header='ID2'; Width=10 }
            @{ Name='duration'; Header='Duration'; Width=18 }
            @{ Name='notes'; Header='Notes'; Width=40 }
        )
    }

    # Define edit fields for InlineEditor
    [array] GetEditFields([object]$item) {
        # CRITICAL: Match GetColumns() field widths exactly
        # GetColumns defines: date_display=12, task=25, project=16, id1=10, id2=10, duration=18, notes=40
        $dateWidth = 12      # Matches date_display column
        $taskWidth = 25      # Matches task column
        $projectWidth = 16   # Matches project column
        $id1Width = 10       # Matches id1 column
        $id2Width = 10       # Matches id2 column
        $hoursWidth = 18     # Matches duration column
        $notesWidth = 40     # Matches notes column

        if ($null -eq $item -or ($item -is [hashtable] -and $item.Count -eq 0)) {
            # New time entry - empty fields
            return @(
                @{ Name='date'; Type='date'; Label='Date'; Required=$true; Value=[DateTime]::Now; Width=$dateWidth }
                @{ Name='task'; Type='text'; Label='Task'; Value=''; Width=$taskWidth }
                @{ Name='project'; Type='project'; Label='Project'; Value=''; Width=$projectWidth }
                @{ Name='id1'; Type='text'; Label='ID1'; Value=''; MaxLength=10; Width=$id1Width }
                @{ Name='id2'; Type='text'; Label='ID2'; Value=''; MaxLength=10; Width=$id2Width }
                # MEDIUM FIX TMS-M3 & TLS-M2: Use constant for max hours validation
                @{ Name='hours'; Type='number'; Label='Hours'; Min=$global:MIN_HOURS_PER_ENTRY; Max=$global:MAX_HOURS_PER_ENTRY; Step=0.25; Value=$global:MIN_HOURS_PER_ENTRY; Width=$hoursWidth }
                @{ Name='notes'; Type='text'; Label='Notes'; Value=''; Width=$notesWidth }
            )
        } else {
            # Existing time entry - populate from item
            $projectVal = $(if ($item.ContainsKey('project')) { $item.project } else { '' })
            $id1Val = $(if ($item.ContainsKey('id1')) { $item.id1 } else { '' })
            $id2Val = $(if ($item.ContainsKey('id2')) { $item.id2 } else { '' })
            # Convert minutes to hours for display
            $hoursVal = $(if ($item.ContainsKey('minutes')) { [math]::Round($item.minutes / 60, 2) } else { 0.25 })
            # HIGH FIX TLS-H1: Add null check for task field
            $taskVal = $(if ($item.ContainsKey('task')) { $item.task } else { '' })
            # HIGH FIX TLS-H2: Add null check for notes field
            $notesVal = $(if ($item.ContainsKey('notes')) { $item.notes } else { '' })
            return @(
                @{ Name='date'; Type='date'; Label='Date'; Required=$true; Value=$item.date; Width=$dateWidth }
                @{ Name='task'; Type='text'; Label='Task'; Value=$taskVal; Width=$taskWidth }
                @{ Name='project'; Type='project'; Label='Project'; Value=$projectVal; Width=$projectWidth }
                @{ Name='id1'; Type='text'; Label='ID1'; Value=$id1Val; MaxLength=10; Width=$id1Width }
                @{ Name='id2'; Type='text'; Label='ID2'; Value=$id2Val; MaxLength=10; Width=$id2Width }
                # MEDIUM FIX TMS-M3 & TLS-M2: Use constant for max hours validation
                @{ Name='hours'; Type='number'; Label='Hours'; Min=$global:MIN_HOURS_PER_ENTRY; Max=$global:MAX_HOURS_PER_ENTRY; Step=0.25; Value=$hoursVal; Width=$hoursWidth }
                @{ Name='notes'; Type='text'; Label='Notes'; Value=$notesVal; Width=$notesWidth }
            )
        }
    }

    # Helper: Get ID1/ID2 values from project if project is selected
    hidden [void] PopulateIDsFromProject([hashtable]$timeData) {
        if ($timeData.ContainsKey('project') -and -not [string]::IsNullOrWhiteSpace($timeData.project)) {
            # Project is selected - try to get ID1/ID2 from it
            $project = $this.Store.GetProject($timeData.project)
            if ($project) {
                # Write-PmcTuiLog "TimeListScreen.PopulateIDsFromProject: Found project '$($timeData.project)'" "DEBUG"

                # If project has ID1, use it (unless user already entered a value)
                if (-not [string]::IsNullOrWhiteSpace($project.ID1) -and [string]::IsNullOrWhiteSpace($timeData.id1)) {
                    $timeData.id1 = $project.ID1
                    # Write-PmcTuiLog "TimeListScreen.PopulateIDsFromProject: Set id1 from project: '$($timeData.id1)'" "DEBUG"
                }

                # If project has ID2, use it (unless user already entered a value)
                if (-not [string]::IsNullOrWhiteSpace($project.ID2) -and [string]::IsNullOrWhiteSpace($timeData.id2)) {
                    $timeData.id2 = $project.ID2
                    # Write-PmcTuiLog "TimeListScreen.PopulateIDsFromProject: Set id2 from project: '$($timeData.id2)'" "DEBUG"
                }
            } else {
                # Write-PmcTuiLog "TimeListScreen.PopulateIDsFromProject: Project '$($timeData.project)' not found" "WARNING"
            }
        } else {
            # No project selected - clear ID1/ID2 if they should come from project
            # Write-PmcTuiLog "TimeListScreen.PopulateIDsFromProject: No project selected, keeping user-entered ID1/ID2 values" "DEBUG"
        }
    }

    # Handle item creation
    [void] OnItemCreated([hashtable]$values) {
        if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
            # Write-PmcTuiLog "TimeListScreen.OnItemCreated: CALLED with values: $($values | ConvertTo-Json -Compress)" "DEBUG"
        }
        try {
            # ENDEMIC FIX: Safe conversion with validation
            if (-not $values.ContainsKey('hours') -or [string]::IsNullOrWhiteSpace($values.hours)) {
                # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Hours validation failed" "DEBUG"
                $this.SetStatusMessage("Hours field is required", "error")
                return
            }
            # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Hours validation passed" "DEBUG"

            $hoursValue = 0.0
            try {
                $hoursValue = [double]$values.hours
            } catch {
                # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Hours conversion failed" "DEBUG"
                $this.SetStatusMessage("Invalid hours value: $($values.hours)", "error")
                return
            }

            if ($global:PmcTuiLogFile -and $global:PmcTuiLogLevel -ge 3) {
                # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Hours value=$hoursValue, MAX_HOURS_PER_ENTRY=$global:MAX_HOURS_PER_ENTRY" "DEBUG"
            }

            # Validate hour range
            # MEDIUM FIX TLS-M3: Use constant for hours validation
            if ($hoursValue -le 0) {
                # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Hours <= 0" "DEBUG"
                $this.SetStatusMessage("Hours must be greater than 0", "error")
                return
            }
            if ($hoursValue -gt $global:MAX_HOURS_PER_ENTRY) {
                # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Hours > MAX ($hoursValue > $global:MAX_HOURS_PER_ENTRY)" "DEBUG"
                $this.SetStatusMessage("Hours must be $global:MAX_HOURS_PER_ENTRY or less", "error")
                return
            }
            # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Hour range validation passed" "DEBUG"

            # HIGH FIX TMS-H3: Use Math.Round instead of [int] to prevent precision loss
            # 2.75 hours = 165 minutes (not 165.0 truncated to 165)
            # CRITICAL: Cast to [int] because validation requires int type
            $minutes = [int][Math]::Round($hoursValue * 60)
            # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Calculated minutes=$minutes" "DEBUG"

            # Safe date conversion
            $dateValue = [DateTime]::Today
            if ($values.ContainsKey('date') -and $values.date) {
                try {
                    $dateValue = [DateTime]$values.date
                } catch {
                    # Write-PmcTuiLog "Failed to parse date '$($values.date)', using today" "WARNING"
                }
            }
            # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Date=$dateValue" "DEBUG"

            $timeData = @{
                date = $dateValue
                task = $(if ($values.ContainsKey('task')) { $values.task } else { '' })
                project = $(if ($values.ContainsKey('project')) { $values.project } else { '' })
                id1 = $(if ($values.ContainsKey('id1')) { $values.id1 } else { '' })
                id2 = $(if ($values.ContainsKey('id2')) { $values.id2 } else { '' })
                minutes = $minutes
                notes = $(if ($values.ContainsKey('notes')) { $values.notes } else { '' })
                created = [DateTime]::Now
            }

            # Populate ID1/ID2 from project if project is selected and IDs are empty
            $this.PopulateIDsFromProject($timeData)

            # Write-PmcTuiLog "TimeListScreen.OnItemCreated: About to save time entry - id1='$($timeData.id1)' id2='$($timeData.id2)'" "DEBUG"
            # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Calling Store.AddTimeLog..." "DEBUG"

            $success = $this.Store.AddTimeLog($timeData)
            # Write-PmcTuiLog "TimeListScreen.OnItemCreated: AddTimeLog returned success=$success" "DEBUG"
            if (-not $success) {
                # Write-PmcTuiLog "TimeListScreen.OnItemCreated: Store.LastError=$($this.Store.LastError)" "ERROR"
            }

            $statusMsg = "Time entry added: {0:F2} hours" -f $hoursValue
            if ($success) {
                $this.SetStatusMessage($statusMsg, "success")
            } else {
                $this.SetStatusMessage("Failed to add time entry: $($this.Store.LastError)", "error")
            }
        } catch {
            # Write-PmcTuiLog "OnItemCreated exception: $_" "ERROR"
            $this.SetStatusMessage("Unexpected error: $($_.Exception.Message)", "error")
        }
    }

    # Handle item update
    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            # ENDEMIC FIX: Safe conversion with validation
            if (-not $values.ContainsKey('hours') -or [string]::IsNullOrWhiteSpace($values.hours)) {
                $this.SetStatusMessage("Hours field is required", "error")
                return
            }

            $hoursValue = 0.0
            try {
                $hoursValue = [double]$values.hours
            } catch {
                $this.SetStatusMessage("Invalid hours value: $($values.hours)", "error")
                return
            }

            # Validate hour range
            # MEDIUM FIX TLS-M3: Use constant for hours validation
            if ($hoursValue -le 0) {
                $this.SetStatusMessage("Hours must be greater than 0", "error")
                return
            }
            if ($hoursValue -gt $global:MAX_HOURS_PER_ENTRY) {
                $this.SetStatusMessage("Hours must be $global:MAX_HOURS_PER_ENTRY or less", "error")
                return
            }

            # HIGH FIX TMS-H3: Use Math.Round instead of [int] to prevent precision loss
            # 2.75 hours = 165 minutes (not 165.0 truncated to 165)
            # CRITICAL: Cast to [int] because validation requires int type
            $minutes = [int][Math]::Round($hoursValue * 60)

            # Safe date conversion
            $dateValue = [DateTime]::Today
            if ($values.ContainsKey('date') -and $values.date) {
                try {
                    $dateValue = [DateTime]$values.date
                } catch {
                    # Write-PmcTuiLog "Failed to parse date '$($values.date)', using today" "WARNING"
                }
            }

            $changes = @{
                date = $dateValue
                task = $(if ($values.ContainsKey('task')) { $values.task } else { '' })
                project = $(if ($values.ContainsKey('project')) { $values.project } else { '' })
                id1 = $(if ($values.ContainsKey('id1')) { $values.id1 } else { '' })
                id2 = $(if ($values.ContainsKey('id2')) { $values.id2 } else { '' })
                minutes = $minutes
                notes = $(if ($values.ContainsKey('notes')) { $values.notes } else { '' })
            }

            # Populate ID1/ID2 from project if project is selected and IDs are empty
            $this.PopulateIDsFromProject($changes)

            # Write-PmcTuiLog "TimeListScreen.OnItemUpdated: About to save changes - id1='$($changes.id1)' id2='$($changes.id2)'" "DEBUG"

            # Update time log via TaskStore
            if ($item.ContainsKey('id') -and -not [string]::IsNullOrWhiteSpace($item.id)) {
                # Write-PmcTuiLog "TimeListScreen.OnItemUpdated: Calling Store.UpdateTimeLog with id=$($item.id)" "DEBUG"
                $success = $this.Store.UpdateTimeLog($item.id, $changes)
                if ($success) {
                    $this.SetStatusMessage("Time entry updated", "success")
                    # TS-M6 FIX: Use RefreshList() instead of LoadData() for incremental refresh
                    # RefreshList() is more efficient than full LoadData() for single item updates
                    $this.RefreshList()
                } else {
                    $this.SetStatusMessage("Failed to update time entry: $($this.Store.LastError)", "error")
                }
            } else {
                $this.SetStatusMessage("Cannot update time entry without ID", "error")
            }
        } catch {
            # Write-PmcTuiLog "OnItemUpdated exception: $_" "ERROR"
            $this.SetStatusMessage("Unexpected error: $($_.Exception.Message)", "error")
        }
    }

    # Handle item deletion
    [void] OnItemDeleted([object]$item) {
        # HIGH FIX TLS-H3: Validate ID is not empty/whitespace
        if ($item.ContainsKey('id') -and -not [string]::IsNullOrWhiteSpace($item.id)) {
            $success = $this.Store.DeleteTimeLog($item.id)
            if ($success) {
                $this.SetStatusMessage("Time entry deleted", "success")
            } else {
                $this.SetStatusMessage("Failed to delete time entry: $($this.Store.LastError)", "error")
            }
        } else {
            $this.SetStatusMessage("Cannot delete time entry without ID", "error")
        }
    }

    # Virtual method called when inline editor is confirmed
    # This method is called by StandardListScreen when inline editing is confirmed
    # TimeListScreen already handles inline editing through OnItemCreated and OnItemUpdated,
    # so this is a no-op to prevent method-not-found errors
    [void] OnInlineEditConfirmed([hashtable]$values) {
        if ($null -eq $values) {
            # Write-PmcTuiLog "TimeListScreen.OnInlineEditConfirmed called with null values" "WARNING"
            return
        }
        # Write-PmcTuiLog "TimeListScreen.OnInlineEditConfirmed called with values: $($values.Keys -join ',')" "DEBUG"

        # Route to OnItemCreated or OnItemUpdated based on mode
        $isAddMode = ($this.EditorMode -eq 'add')

        if ($isAddMode) {
            # Write-PmcTuiLog "OnInlineEditConfirmed: Processing ADD mode for time entry" "INFO"
            $this.OnItemCreated($values)
        }
        else {
            # Write-PmcTuiLog "OnInlineEditConfirmed: Processing EDIT mode for time entry" "INFO"
            if ($this.CurrentEditItem) {
                $this.OnItemUpdated($this.CurrentEditItem, $values)
            }
            else {
                # Write-PmcTuiLog "OnInlineEditConfirmed: EDIT mode but no CurrentEditItem!" "ERROR"
            }
        }
    }

    # Virtual method called when inline editor is cancelled
    # This method is called by StandardListScreen when inline editing is cancelled
    # TimeListScreen already handles inline editing through its own callbacks,
    # so this is a no-op to prevent method-not-found errors
    [void] OnInlineEditCancelled() {
        # Write-PmcTuiLog "TimeListScreen.OnInlineEditCancelled called" "DEBUG"
        # No-op: TimeListScreen handles inline editor callbacks directly
    }


    # Get custom actions for footer display
    [array] GetCustomActions() {
        $self = $this
        return @(
            @{ Key='w'; Label='Week Report'; Callback={
                $screenPath = "$PSScriptRoot/WeeklyTimeReportScreen.ps1"
                . $screenPath
                $screen = New-Object WeeklyTimeReportScreen
                $global:PmcApp.PushScreen($screen)
            }.GetNewClosure() },
            @{ Key='g'; Label='Generate'; Callback={
                $self.GenerateReport()
            }.GetNewClosure() }
        )
    }

    # === Custom Actions ===

    # Show detail dialog for aggregated entries
    [void] ShowDetailDialog([hashtable]$item) {
        # CRITICAL FIX TLS-C3: Add null check on $item parameter
        if ($null -eq $item) {
            # Write-PmcTuiLog "TimeListScreen.ShowDetailDialog: item parameter is null" "WARNING"
            return
        }
        if (-not $item.ContainsKey('original_entries') -or $item.original_entries.Count -eq 0) {
            return
        }

        # Create dialog title
        # HIGH FIX TLS-H4: Add null checks for string interpolation
        $dateDisplay = $(if ($item.ContainsKey('date_display')) { $item.date_display } else { 'Unknown' })
        $project = $(if ($item.ContainsKey('project')) { $item.project } else { 'N/A' })
        $title = "Time Entry Details - $dateDisplay - $project"
        # HIGH FIX TLS-H6: Use ContainsKey check for timecode
        if ($item.ContainsKey('timecode') -and $item.timecode) {
            $title += " [$($item.timecode)]"
        }
        $entryCount = $(if ($item.ContainsKey('entry_count')) { $item.entry_count } else { 0 })
        $title += " ($entryCount entries)"

        # LOW FIX TS-L1: Add error handling on dialog creation
        try {
            $dialog = [TimeEntryDetailDialog]::new($title, $item.original_entries)
        } catch {
            $this.SetStatusMessage("Failed to create detail dialog: $($_.Exception.Message)", "error")
            # Write-PmcTuiLog "TimeListScreen: Dialog creation failed - $_" "ERROR"
            return
        }

        # TIM-7 FIX: Dialog render loop with timeout protection
        # CRITICAL FIX TMS-C1 & EDGE FIX TLS-E1: Use constants for timeout and poll interval
        $maxIterations = $script:DIALOG_TIMEOUT_ITERATIONS
        $iterations = 0

        while (-not $dialog.IsComplete -and $iterations -lt $maxIterations) {
            $iterations++

            # Get theme from theme manager
            $themeManager = [PmcThemeManager]::GetInstance()
            $theme = $themeManager.GetTheme()

            # Render dialog
            $termWidth = [Console]::WindowWidth
            $termHeight = [Console]::WindowHeight
            $dialogOutput = $dialog.Render($termWidth, $termHeight, $theme)

            # Handle input
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $dialog.HandleInput($key)

                # HIGH FIX TMS-H4: Only close on Escape, Ctrl+C, or Ctrl+Q (not all Control keys)
                # Checking -band [ConsoleModifiers]::Control catches Ctrl+V, Ctrl+A, etc.
                if ($key.Key -eq 'Escape' -or
                    ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) -or
                    ($key.Key -eq 'Q' -and ($key.Modifiers -band [ConsoleModifiers]::Control))) {
                    $dialog.IsComplete = $true
                    break
                }
            }

            Start-Sleep -Milliseconds $script:DIALOG_POLL_INTERVAL_MS
        }

        # TS-M2 FIX: Show user-visible warning if timeout occurred
        if ($iterations -ge $maxIterations) {
            # Write-PmcTuiLog "TimeListScreen.ShowDetailDialog: Timeout after $maxIterations iterations (3 minutes)" "WARNING"
            $this.SetStatusMessage("Dialog closed due to timeout (3 minutes)", "warning")
        }

        # Redraw screen after dialog closes
        $this.RenderEngine.ForceRedraw()
    }

    # Generate time report for selected period
    [void] GenerateReport() {
        # Navigate to time report screen
        . "$PSScriptRoot/TimeReportScreen.ps1"
        $screen = New-Object TimeReportScreen
        $this.App.PushScreen($screen)
    }

    # === Input Handling ===

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # Custom key: Enter = Show detail dialog for aggregated entries
        if ($keyInfo.Key -eq 'Enter' -and -not $this.ShowInlineEditor) {
            $selectedItem = $this.List.GetSelectedItem()
            if ($selectedItem -and $selectedItem.ContainsKey('entry_count') -and $selectedItem.entry_count -gt 1) {
                $this.ShowDetailDialog($selectedItem)
                return $true
            }
        }

        # Call parent handler (handles list navigation, add/edit/delete)
        $handled = ([StandardListScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        # Custom key: G = Generate report
        if ($keyInfo.KeyChar -eq 'g' -or $keyInfo.KeyChar -eq 'G') {
            $this.GenerateReport()
            return $true
        }

        # Custom key: W = Weekly time report
        if ($keyInfo.KeyChar -eq 'w' -or $keyInfo.KeyChar -eq 'W') {
            . "$PSScriptRoot/WeeklyTimeReportScreen.ps1"
            $screen = New-Object WeeklyTimeReportScreen
            $this.App.PushScreen($screen)
            return $true
        }

        return $false
    }
}