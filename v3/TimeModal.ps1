# TimeModal.ps1 - Time entries modal with weekly view
# Tab 1: Time entries list for project
# Tab 2: Weekly time view

class TimeModal {
    hidden [bool]$_visible = $false
    hidden [FluxStore]$_store
    hidden [string]$_projectId = ""
    hidden [string]$_projectName = ""
    hidden [int]$_activeTab = 0  # 0=Entries, 1=Weekly
    hidden [array]$_timelogs = @()
    hidden [int]$_selectedIndex = 0
    hidden [int]$_scrollOffset = 0
    hidden [int]$_weekOffset = 0  # 0=current, -1=last, etc.
    hidden [bool]$_editing = $false
    hidden [hashtable]$_editBuffer = $null
    hidden [int]$_editField = 0
    hidden [bool]$_calendarActive = $false
    hidden [DateTime]$_calendarMonth = [DateTime]::MinValue
    
    TimeModal([FluxStore]$store) {
        $this._store = $store
    }
    
    [void] Open([string]$projectId, [string]$projectName) {
        $this._projectId = $projectId
        $this._projectName = $projectName
        $this._visible = $true
        $this._activeTab = 0
        $this._selectedIndex = 0
        $this._scrollOffset = 0
        $this._weekOffset = 0
        $this._editing = $false
        $this._LoadTimelogs()
    }
    
    [void] Close() {
        $this._visible = $false
        $this._editing = $false
    }
    
    [bool] IsVisible() {
        return $this._visible
    }
    
    hidden [void] _LoadTimelogs() {
        $state = $this._store.GetState()
        
        if ($state.Data.ContainsKey('timelogs') -and $state.Data.timelogs) {
            if ([string]::IsNullOrEmpty($this._projectId)) {
                # General/Non-project time - show entries without projectId OR all entries
                $this._timelogs = @($state.Data.timelogs | Where-Object { [string]::IsNullOrEmpty($_['projectId']) } | Sort-Object { $_['date'] } -Descending)
            } else {
                $this._timelogs = @($state.Data.timelogs | Where-Object { $_['projectId'] -eq $this._projectId } | Sort-Object { $_['date'] } -Descending)
            }
        } else {
            $this._timelogs = @()
        }
        [Logger]::Log("TimeModal._LoadTimelogs: Loaded $($this._timelogs.Count) entries for project '$($this._projectId)'", 3)
    }
    
    [void] Render([HybridRenderEngine]$engine) {

        if (-not $this._visible) { return }
        
        [Logger]::Log("TimeModal.Render: Frame (Editing: $($this._editing))", 4)
        
        # Render Modal Box
        $w = 80
        $h = 24
        
        # Center the modal
        $x = [Math]::Max(0, [int](($engine.Width - $w) / 2))
        $y = [Math]::Max(0, [int](($engine.Height - $h) / 2))
        
        [Logger]::Log("TimeModal.Render: ScrW=$($engine.Width) ScrH=$($engine.Height) ModalX=$x ModalY=$y ModalH=$h MenuY=$($y + $h - 2)", 1)
        
        $engine.BeginLayer(110) # High Z-Index
        
        # 1. Clear modal area completely + 3 rows below to prevent ghosts from dashboard
        $engine.Fill($x, $y, $w, $h + 3, " ", [Colors]::Foreground, [Colors]::PanelBg)
        
        # 2. Draw Box Border
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
        
        # Title with Project Name
        $title = " Time: $($this._projectName) "
        $engine.WriteAt($x + 2, $y, $title, [Colors]::White, [Colors]::Accent)
        
        # Tabs
        $tabY = $y + 1
        $tabs = @("Entries", "Weekly")
        $tabX = $x + 2
        for ($i = 0; $i -lt $tabs.Count; $i++) {
            $fg = if ($i -eq $this._activeTab) { [Colors]::White } else { [Colors]::Gray }
            $bg = if ($i -eq $this._activeTab) { [Colors]::SelectionBg } else { [Colors]::Background }
            $tabText = " $($i + 1):$($tabs[$i]) "
            $engine.WriteAt($tabX, $tabY, $tabText, $fg, $bg)
            $tabX += $tabText.Length + 1
        }
        
        # Content area
        $contentY = $y + 3
        $contentH = $h - 6
        
        if ($this._activeTab -eq 0) {
            $this._RenderEntriesTab($engine, $x, $contentY, $w, $contentH)
        } else {
            $this._RenderWeeklyTab($engine, $x, $contentY, $w, $contentH)
        }
        
        # Footer / Menu
        $menuY = $y + $h - 2
        # Explicitly clear footer line (Corrected width to avoid artifacts)
        $engine.Fill($x + 1, $menuY, $w - 2, 1, " ", [Colors]::White, [Colors]::PanelBg)
        
        if ($this._editing) {
            $menu = "[Enter] Save Field  [Tab] Next Field  [Esc] Cancel Edit"
            $engine.WriteAt($x + 2, $menuY, $menu, [Colors]::White, [Colors]::PanelBg)
        } else {
            $menu = "[N] New  [Enter] Edit  [Delete] Remove  [Tab] Weekly  [Esc] Close"
            $engine.WriteAt($x + 2, $menuY, $menu, [Colors]::White, [Colors]::PanelBg)
        }
        
        # Render Calendar Overlay
        if ($this._calendarActive) {
            # Position calendar below the date field roughly
            # Date field is at x+2. Row depends on selection.
            # We need to calculate row Y again.
            $listY = $y + 3 + 2 
            $listH = $h - 6 - 4
            
            # Simple calc for modal logic (ScrollOffset etc already applied)
            # Just render centered for now or reuse render logic? 
            # We need the Y position of the editing row. 
            $rowVisualIndex = $this._selectedIndex - $this._scrollOffset
            if ($rowVisualIndex -ge 0 -and $rowVisualIndex -lt $listH) {
                 $calY = $listY + $rowVisualIndex + 1
                 $this._RenderCalendar($engine, $x + 2, $calY)
            }
        }
        
        $engine.EndLayer()
    }
    
    hidden [void] _RenderEntriesTab([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$w, [int]$h) {
        [Logger]::Log("TimeModal._RenderEntriesTab: Count=$($this._timelogs.Count)", 3)
        
        # Clear content area
        $engine.Fill($x + 1, $y, $w - 2, $h, " ", [Colors]::Foreground, [Colors]::PanelBg)
        
        # Column headers - Date, ID1, Hours, Description
        $engine.WriteAt($x + 2, $y, "Date".PadRight(12), [Colors]::Cyan, [Colors]::PanelBg)
        $engine.WriteAt($x + 14, $y, "ID1".PadRight(8), [Colors]::Cyan, [Colors]::PanelBg)
        $engine.WriteAt($x + 22, $y, "Hours".PadRight(8), [Colors]::Cyan, [Colors]::PanelBg)
        $engine.WriteAt($x + 30, $y, "Description", [Colors]::Cyan, [Colors]::PanelBg)
        
        $engine.WriteAt($x + 1, $y + 1, ("─" * ($w - 2)), [Colors]::PanelBorder, [Colors]::PanelBg)
        
        $listY = $y + 2
        $listH = $h - 4
        $maxDesc = [Math]::Max(0, $w - 34)
        
        if ($this._timelogs.Count -eq 0) {
            $engine.WriteAt($x + 4, $listY, "(No time entries. Press N to add one)", [Colors]::Gray, [Colors]::PanelBg)
        } else {
            # Adjust scroll
            if ($this._selectedIndex -lt $this._scrollOffset) {
                $this._scrollOffset = $this._selectedIndex
            }
            if ($this._selectedIndex -ge $this._scrollOffset + $listH) {
                $this._scrollOffset = $this._selectedIndex - $listH + 1
            }
            
            for ($displayRow = 0; $displayRow -lt $listH; $displayRow++) {
                $idx = $displayRow + $this._scrollOffset
                if ($idx -ge $this._timelogs.Count) { break }
                
                $entry = $this._timelogs[$idx]
                if ($null -eq $entry) { continue }  # Skip null entries
                
                $rowY = $listY + $displayRow
                $isSelected = ($idx -eq $this._selectedIndex)
                
                $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
                $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::PanelBg }
                
                # Explicitly redraw borders
                $engine.WriteAt($x, $rowY, "│", [Colors]::Accent, [Colors]::PanelBg)
                $engine.WriteAt($x + $w - 1, $rowY, "│", [Colors]::Accent, [Colors]::PanelBg)
                
                # Clear row (Full width to avoid artifacts)
                $engine.Fill($x + 1, $rowY, $w - 2, 1, " ", $fg, $bg)
                
                $dateRaw = if ($entry['date']) { [string]$entry['date'] } else { "" }
                $date = if ($dateRaw.Length -gt 10) { $dateRaw.Substring(0, 10) } else { $dateRaw }
                $id1 = if ($entry['id1']) { $entry['id1'] } else { "" }
                $hours = if ($entry['hours']) { "{0:N2}" -f [double]$entry['hours'] } else { "0.00" }
                $desc = if ($entry['description']) { $entry['description'] } else { "" }
                if ($desc.Length -gt $maxDesc) { $desc = $desc.Substring(0, $maxDesc - 3) + "..." }
                
                # Inline Editing Rendering
                if ($this._editing -and $isSelected -and $null -ne $this._editBuffer) {
                    $editVal = $this._editBuffer['Value']
                    
                    if ($this._editField -eq 0) { # Date
                        $engine.WriteAt($x + 2, $rowY, $editVal.PadRight(12), [Colors]::Black, [Colors]::Cyan)
                        $engine.WriteAt($x + 14, $rowY, $id1.PadRight(8), $fg, $bg)
                        $engine.WriteAt($x + 22, $rowY, $hours.PadRight(8), $fg, $bg)
                        $engine.WriteAt($x + 30, $rowY, $desc.PadRight($maxDesc), $fg, $bg)
                    } elseif ($this._editField -eq 1) { # ID1
                        $engine.WriteAt($x + 2, $rowY, $date.PadRight(12), $fg, $bg)
                        $engine.WriteAt($x + 14, $rowY, $editVal.PadRight(8), [Colors]::Black, [Colors]::Cyan)
                        $engine.WriteAt($x + 22, $rowY, $hours.PadRight(8), $fg, $bg)
                        $engine.WriteAt($x + 30, $rowY, $desc.PadRight($maxDesc), $fg, $bg)
                    } elseif ($this._editField -eq 2) { # Hours
                        $engine.WriteAt($x + 2, $rowY, $date.PadRight(12), $fg, $bg)
                        $engine.WriteAt($x + 14, $rowY, $id1.PadRight(8), $fg, $bg)
                        $engine.WriteAt($x + 22, $rowY, $editVal.PadRight(8), [Colors]::Black, [Colors]::Cyan)
                        $engine.WriteAt($x + 30, $rowY, $desc.PadRight($maxDesc), $fg, $bg)
                    } elseif ($this._editField -eq 3) { # Description
                        $engine.WriteAt($x + 2, $rowY, $date.PadRight(12), $fg, $bg)
                        $engine.WriteAt($x + 14, $rowY, $id1.PadRight(8), $fg, $bg)
                        $engine.WriteAt($x + 22, $rowY, $hours.PadRight(8), $fg, $bg)
                        $engine.WriteAt($x + 30, $rowY, $editVal, [Colors]::Black, [Colors]::Cyan)
                    }
                } else {
                    $engine.WriteAt($x + 2, $rowY, $date.PadRight(12), $fg, $bg)
                    $engine.WriteAt($x + 14, $rowY, $id1.PadRight(8), $fg, $bg)
                    $engine.WriteAt($x + 22, $rowY, $hours.PadRight(8), $fg, $bg)
                    $engine.WriteAt($x + 30, $rowY, $desc.PadRight($maxDesc), $fg, $bg)
                }
            }
        }
        
        # Total
        $total = 0.0
        if ($this._timelogs.Count -gt 0) {
            $total = ($this._timelogs | ForEach-Object { [double]$_['hours'] } | Measure-Object -Sum).Sum
        }
        $totalStr = "Total: {0:N2} hours" -f $total
        $engine.WriteAt($x + 2, $y + $h - 1, $totalStr, [Colors]::Cyan, [Colors]::PanelBg)
    }
    
    hidden [void] _RenderWeeklyTab([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$w, [int]$h) {
        # Clear area
        $engine.Fill($x + 1, $y, $w - 2, $h, " ", [Colors]::Foreground, [Colors]::PanelBg)
        
        # Get week dates
        $today = [DateTime]::Today
        $startOfWeek = $today.AddDays(-[int]$today.DayOfWeek + 1 + ($this._weekOffset * 7))  # Monday
        if ($today.DayOfWeek -eq [DayOfWeek]::Sunday) {
            $startOfWeek = $startOfWeek.AddDays(-7)
        }
        
        # Week header
        $weekRange = "$($startOfWeek.ToString('MMM dd')) - $($startOfWeek.AddDays(6).ToString('MMM dd, yyyy'))"
        $engine.WriteAt($x + 2, $y, "◀ $weekRange ▶  [Weekly Report]", [Colors]::Cyan, [Colors]::PanelBg)
        
        # Column headers: Project/ID1, Hours, Description
        $headerY = $y + 2
        $engine.WriteAt($x + 2, $headerY, "Project/ID".PadRight(20), [Colors]::Cyan, [Colors]::PanelBg)
        $engine.WriteAt($x + 22, $headerY, "Hours".PadRight(10), [Colors]::Cyan, [Colors]::PanelBg)
        $engine.WriteAt($x + 32, $headerY, "Description", [Colors]::Cyan, [Colors]::PanelBg)
        $engine.WriteAt($x + 1, $headerY + 1, ("─" * ($w - 2)), [Colors]::PanelBorder, [Colors]::PanelBg)
        
        # Get all timelogs for the week and aggregate by project OR ID1
        $state = $this._store.GetState()
        $allTimelogs = @()
        if ($state.Data.ContainsKey('timelogs') -and $state.Data.timelogs) {
            $allTimelogs = @($state.Data.timelogs)
        }
        
        $projects = @{}
        if ($state.Data.ContainsKey('projects') -and $state.Data.projects) {
            foreach ($p in $state.Data.projects) {
                $projects[$p['id']] = $p
            }
        }
        
        # Group entries - key is either projectId or "ID1:<code>" for general time
        $grouped = @{}
        $weekTotal = 0.0
        
        foreach ($entry in $allTimelogs) {
            if (-not $entry['date']) { continue }
            try {
                $entryDate = [DateTime]::Parse($entry['date'])
                $dayDiff = ($entryDate - $startOfWeek).Days
                if ($dayDiff -lt 0 -or $dayDiff -ge 7) { continue }
                
                $hours = if ($entry['hours']) { [double]$entry['hours'] } else { 0.0 }
                $weekTotal += $hours
                
                # Determine grouping key
                $key = ""
                $displayName = ""
                $projId = $entry['projectId']
                $id1 = $entry['id1']
                
                if ($projId -and $projects.ContainsKey($projId)) {
                    # Project-based entry
                    $key = "proj:$projId"
                    $proj = $projects[$projId]
                    $displayName = $proj['name']
                    if ($proj['id1']) { $displayName += " ($($proj['id1']))" }
                } elseif ($id1) {
                    # General time with ID1 code
                    $key = "id1:$id1"
                    $displayName = "Code: $id1"
                } else {
                    # General time, no code
                    $key = "general"
                    $displayName = "(General - no code)"
                }
                
                if (-not $grouped.ContainsKey($key)) {
                    $grouped[$key] = @{ Name = $displayName; Hours = 0.0 }
                }
                $grouped[$key].Hours += $hours
            } catch {}
        }
        
        # Render grouped entries
        $listY = $headerY + 2
        $listH = $h - 8
        $row = 0
        $maxDesc = $w - 36
        
        foreach ($key in $grouped.Keys | Sort-Object) {
            if ($row -ge $listH) { break }
            
            $item = $grouped[$key]
            $name = $item.Name
            if ($name.Length -gt 18) { $name = $name.Substring(0, 15) + "..." }
            $hours = "{0:N2}" -f $item.Hours
            
            $fg = [Colors]::Foreground
            $bg = [Colors]::PanelBg
            
            $engine.WriteAt($x + 2, $listY + $row, $name.PadRight(20), $fg, $bg)
            $engine.WriteAt($x + 22, $listY + $row, $hours.PadRight(10), [Colors]::Cyan, $bg)
            $row++
        }
        
        if ($row -eq 0) {
            $engine.WriteAt($x + 4, $listY, "(No time entries this week)", [Colors]::Gray, [Colors]::PanelBg)
        }
        
        # Summary at bottom
        $summaryY = $y + $h - 4
        $weekTarget = 37.5
        $pct = if ($weekTarget -gt 0) { ($weekTotal / $weekTarget) * 100 } else { 0 }
        
        $weekStr = "Week Total: {0:N1} / {1:N1} hours ({2:N0}%)" -f $weekTotal, $weekTarget, $pct
        $engine.WriteAt($x + 2, $summaryY, $weekStr, [Colors]::Foreground, [Colors]::PanelBg)
        
        # Progress bar
        $barY = $summaryY + 1
        $barWidth = $w - 10
        $filledWidth = [Math]::Min($barWidth, [int](($pct / 100) * $barWidth))
        $bar = ("█" * $filledWidth) + ("░" * ($barWidth - $filledWidth))
        $barColor = if ($pct -ge 100) { [Colors]::Green } elseif ($pct -ge 80) { [Colors]::Yellow } else { [Colors]::Red }
        $engine.WriteAt($x + 2, $barY, $bar, $barColor, [Colors]::PanelBg)
    }
    
    [string] HandleInput([ConsoleKeyInfo]$key) {
        [Logger]::Log("TimeModal.HandleInput: Key=$($key.Key) Char='$($key.KeyChar)' Mod=$($key.Modifiers)", 4)
        if (-not $this._visible) { return "Continue" }
        
        if ($this._calendarActive) {
            return $this._HandleCalendarInput($key)
        }

        if ($this._editing) {
            return $this._HandleEditInput($key)
        }
        
        switch ($key.Key) {
            'Escape' {
                $this._visible = $false
                return "Handled"
            }
            'Tab' {
                $this._activeTab = ($this._activeTab + 1) % 2
                return "Continue"
            }
            'D1' { $this._activeTab = 0; return "Continue" }
            'D2' { $this._activeTab = 1; return "Continue" }
            'N' {
                [Logger]::Log("TimeModal: 'N' pressed - BEFORE CreateEntry", 1)
                $newId = $this._CreateEntry() # Adds to Store (Sync)
                [Logger]::Log("TimeModal: 'N' pressed - AFTER CreateEntry, newId=$newId", 1)
                
                # Find the index of the new entry (Robust)
                for ($i = 0; $i -lt $this._timelogs.Count; $i++) {
                    if ($this._timelogs[$i]['id'] -eq $newId) {
                        $this._selectedIndex = $i
                        break
                    }
                }
                
                # Auto-start editing description
                $this._editField = 2 # Desc
                $this._editing = $true
                $this._InitEditBuffer()
                [Logger]::Log("TimeModal: 'N' pressed - Editing started, field=$($this._editField)", 1)
                return "Continue"
            }
            'Enter' {
                if ($this._timelogs.Count -gt 0) {
                    $this._editing = $true
                    $this._editField = 1 # Start on Hours usually
                    $this._InitEditBuffer()
                }
                return "Continue"
            }
            'UpArrow' {
                if ($this._selectedIndex -gt 0) {
                    $this._selectedIndex--
                }
                return "Continue"
            }
            'DownArrow' {
                if ($this._selectedIndex -lt $this._timelogs.Count - 1) {
                    $this._selectedIndex++
                }
                return "Continue"
            }
            'Delete' {
                $this._DeleteEntry()
                return "Continue"
            }
        }
        
        if ($this._activeTab -eq 0) {
            return $this._HandleEntriesInput($key)
        } else {
            return $this._HandleWeeklyInput($key)
        }
        return "Continue"
    }
    
    hidden [string] _HandleEditInput([ConsoleKeyInfo]$key) {
        switch ($key.Key) {
            'Escape' {
                $this._editing = $false
                return "Continue"
            }
            'Enter' {
                # Save current field
                $entry = $this._timelogs[$this._selectedIndex]
                $val = $this._editBuffer['Value']
                
                if ($this._editField -eq 0) { # Date
                     $entry['date'] = $val
                } elseif ($this._editField -eq 1) { # ID1
                     $entry['id1'] = $val
                } elseif ($this._editField -eq 2) { # Hours
                     try { $entry['hours'] = [double]$val } catch {}
                } elseif ($this._editField -eq 3) { # Description
                     $entry['description'] = $val
                }
                
                # Should we save to disk instantly or wait? Instant is better for safety.
                $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
                
                $this._editing = $false
                return "Continue"
            }
            'Tab' {
                # Save current field before switching
                $entry = $this._timelogs[$this._selectedIndex]
                $val = $this._editBuffer['Value']
                
                if ($this._editField -eq 0) { # Date
                     $entry['date'] = $val
                } elseif ($this._editField -eq 1) { # ID1
                     $entry['id1'] = $val
                } elseif ($this._editField -eq 2) { # Hours
                     try { $entry['hours'] = [double]$val } catch {}
                } elseif ($this._editField -eq 3) { # Description
                     $entry['description'] = $val
                }
                
                # Switch field: Date -> ID1 -> Hours -> Description -> Date
                $this._editField = ($this._editField + 1) % 4
                $this._InitEditBuffer()
                
                # Save Data on Tab to prevent loss
                $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
                
                return "Continue"
            }
            'DownArrow' {
                if ($this._editField -eq 0) { # Date -> Calendar
                    $this._calendarActive = $true
                    $val = $this._editBuffer['Value']
                    try { $this._calendarMonth = [DateTime]::Parse($val) } catch { $this._calendarMonth = [DateTime]::Today }
                    return "Continue"
                } elseif ($this._editField -eq 2) { # Hours -> Decrement
                    try { 
                        $cur = [double]$this._editBuffer['Value'] 
                        $cur = [Math]::Max(0, $cur - 0.25)
                        $this._editBuffer['Value'] = "{0:N2}" -f $cur
                    } catch {}
                    return "Continue"
                }
            }
            'UpArrow' {
                 if ($this._editField -eq 2) { # Hours -> Increment
                    try {
                        $cur = [double]$this._editBuffer['Value']
                        $cur += 0.25
                        $this._editBuffer['Value'] = "{0:N2}" -f $cur
                    } catch {}
                    return "Continue"
                }
            }
            'Backspace' {
                if ($this._editBuffer['Value'].Length -gt 0) {
                    $this._editBuffer['Value'] = $this._editBuffer['Value'].Substring(0, $this._editBuffer['Value'].Length - 1)
                }
                return "Continue"
            }
            Default {
                if (-not [char]::IsControl($key.KeyChar)) {
                    $this._editBuffer['Value'] += $key.KeyChar
                }
                return "Continue"
            }
        }
        return "Continue"
    }
    
    hidden [void] _InitEditBuffer() {
        if ($null -eq $this._timelogs) {
            [Logger]::Error("TimeModal._InitEditBuffer: _timelogs is NULL!", $null)
            $this._timelogs = @() # Recover
            return
        }
        
        [Logger]::Log("TimeModal._InitEditBuffer: SelIndex=$($this._selectedIndex) Count=$($this._timelogs.Count)", 3)
        
        if ($this._selectedIndex -ge 0 -and $this._selectedIndex -lt $this._timelogs.Count) {
            $entry = $this._timelogs[$this._selectedIndex]
            if ($null -eq $entry) {
                [Logger]::Error("TimeModal._InitEditBuffer: Entry at index $($this._selectedIndex) is NULL!", $null)
                return
            }
            
            $val = ""
            if ($this._editField -eq 0) {
                if ($entry['date']) { $val = ([datetime]$entry['date']).ToString("yyyy-MM-dd") }
            } elseif ($this._editField -eq 1) {
                $val = if ($entry['id1']) { $entry['id1'] } else { "" }
            } elseif ($this._editField -eq 2) {
                $val = if ($entry['hours']) { "$($entry['hours'])" } else { "0" }
            } elseif ($this._editField -eq 3) {
                $val = if ($entry['description']) { $entry['description'] } else { "" }
            }
            
            [Logger]::Log("TimeModal._InitEditBuffer: Field=$($this._editField) Val='$val'", 3)
            
            $this._editBuffer = @{
                Value = $val
                CursorPos = $val.Length
            }
        }
    }
    
    hidden [string] _HandleEntriesInput([ConsoleKeyInfo]$key) {
        # This seems to be legacy/dead code since HandleInput handles these keys directly now.
        # Keeping empty or removing content to prevent confusion.
        return "Continue"
    }
    
    hidden [string] _HandleWeeklyInput([ConsoleKeyInfo]$key) {
        switch ($key.Key) {
            'LeftArrow' {
                $this._weekOffset--
                return "Continue"
            }
            'RightArrow' {
                $this._weekOffset++
                return "Continue"
            }
        }
        return "Continue"
    }
    
    hidden [string] _CreateEntry() {
        $id = [DataService]::NewGuid()
        $newEntry = @{
            id = $id
            projectId = $this._projectId
            date = [DateTime]::Today.ToString("yyyy-MM-dd")
            hours = 0.0
            description = ""
            created = [DataService]::Timestamp()
        }
        
        $state = $this._store.GetState()
        if (-not $state.Data.ContainsKey('timelogs')) {
            $state.Data.timelogs = @()
        }
        $state.Data.timelogs += $newEntry
        
        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
        $this._LoadTimelogs()
        return $id
    }
    
    hidden [void] _RenderCalendar([HybridRenderEngine]$engine, [int]$x, [int]$y) {
        # Calendar Dimensions: 26w x 10h
        $w = 26
        $h = 10
        
        # Ensure Month is valid 
        if ($this._calendarMonth -eq [DateTime]::MinValue) { $this._calendarMonth = [DateTime]::Today }

        # Draw Box
        $engine.BeginLayer(120) # Top Layer
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
        
        # Header: Month Year
        $header = $this._calendarMonth.ToString("MMMM yyyy")
        $engine.WriteAt($x + 2, $y, " $header ", [Colors]::White, [Colors]::Accent)
        
        # Days Header
        $days = "Su Mo Tu We Th Fr Sa"
        $engine.WriteAt($x + 2, $y + 2, $days, [Colors]::Gray, [Colors]::PanelBg)
        
        # Calendar Grid
        $firstDayOfMonth = [DateTime]::new($this._calendarMonth.Year, $this._calendarMonth.Month, 1)
        $daysInMonth = [DateTime]::DaysInMonth($this._calendarMonth.Year, $this._calendarMonth.Month)
        $startOffset = [int]$firstDayOfMonth.DayOfWeek
        
        $currentDate = $firstDayOfMonth.AddDays(-$startOffset)
        
        # Selection
        $selectedDate = [DateTime]::Today
        try { $selectedDate = [DateTime]::Parse($this._editBuffer['Value']) } catch {}
        
        for ($row = 0; $row -lt 6; $row++) {
            for ($col = 0; $col -lt 7; $col++) {
                $dayStr = $currentDate.Day.ToString().PadLeft(2)
                $drawX = $x + 2 + ($col * 3)
                $drawY = $y + 3 + $row
                
                if ($drawY -ge $y + $h - 1) { continue }
                
                $isCurrentMonth = ($currentDate.Month -eq $this._calendarMonth.Month)
                $isSelected = ($currentDate.Date -eq $selectedDate.Date)
                
                $fg = if ($isSelected) { [Colors]::Black } elseif ($isCurrentMonth) { [Colors]::White } else { [Colors]::Gray }
                $bg = if ($isSelected) { [Colors]::Cyan } else { [Colors]::PanelBg }
                
                $engine.WriteAt($drawX, $drawY, $dayStr, $fg, $bg)
                
                $currentDate = $currentDate.AddDays(1)
            }
        }
        $engine.EndLayer()
    }

    hidden [string] _HandleCalendarInput([ConsoleKeyInfo]$key) {
        $current = [DateTime]::Today
        try { $current = [DateTime]::Parse($this._editBuffer['Value']) } catch {}
        
        $newDate = $current
        $changed = $false

        switch ($key.Key) {
            'LeftArrow' { $newDate = $current.AddDays(-1); $changed = $true }
            'RightArrow' { $newDate = $current.AddDays(1); $changed = $true }
            'UpArrow' { $newDate = $current.AddDays(-7); $changed = $true }
            'DownArrow' { $newDate = $current.AddDays(7); $changed = $true }
            'PageUp' { $newDate = $current.AddMonths(-1); $changed = $true }
            'PageDown' { $newDate = $current.AddMonths(1); $changed = $true }
            'Enter' { 
                $this._calendarActive = $false 
                return "Continue"
            }
            'Escape' {
                $this._calendarActive = $false
                return "Continue"
            }
        }

        if ($changed) {
            $this._editBuffer['Value'] = $newDate.ToString("yyyy-MM-dd")
            # Sync calendar month
            if ($newDate.Month -ne $this._calendarMonth.Month -or $newDate.Year -ne $this._calendarMonth.Year) {
                $this._calendarMonth = $newDate
            }
        }
        return "Continue"
    }

    hidden [void] _DeleteEntry() {
        if ($this._timelogs.Count -eq 0 -or $this._selectedIndex -ge $this._timelogs.Count) { return }
        
        $entry = $this._timelogs[$this._selectedIndex]
        
        $state = $this._store.GetState()
        $state.Data.timelogs = @($state.Data.timelogs | Where-Object { $_['id'] -ne $entry['id'] })
        
        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
        $this._LoadTimelogs()
        
        if ($this._selectedIndex -ge $this._timelogs.Count -and $this._selectedIndex -gt 0) {
            $this._selectedIndex--
        }
    }
}
