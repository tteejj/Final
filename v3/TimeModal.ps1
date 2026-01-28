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
        
        [Logger]::Log("TimeModal.Render: START Frame. Editing=$($this._editing) ActiveTab=$($this._activeTab)", 4)
        
        # Render Modal Box
        # Dynamic Size: 80% width (clamped), Height - 4 (clamped)
        $w = [Math]::Min([Math]::Max(60, [int]($engine.Width * 0.8)), 100)
        $h = [Math]::Max(10, $engine.Height - 4)
        
        # Safety Check: If H hits bottom edge, shrink it
        if ($h -ge $engine.Height) { $h = $engine.Height - 1 }
        
        # Center the modal
        $x = [Math]::Max(0, [int](($engine.Width - $w) / 2))
        $y = [Math]::Max(0, [int](($engine.Height - $h) / 2))
        
        [Logger]::Log("TimeModal.Render: ScrW=$($engine.Width) ScrH=$($engine.Height) ModalX=$x ModalY=$y ModalH=$h MenuY=$($y + $h - 2)", 1)
        
        $engine.BeginLayer(110) # High Z-Index
        
        # 1. Clear modal area completely
        $engine.Fill($x, $y, $w, $h, " ", [Colors]::Foreground, [Colors]::PanelBg)
        
        # 2. Draw Box Border
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
        
        # Title with Project Name
        $title = " Time: $($this._projectName) "
        $engine.WriteAt($x + 2, $y, $title, [Colors]::Bright, [Colors]::Accent)
        
        # Tabs
        $tabY = $y + 1
        $tabs = @("Entries", "Weekly")
        $tabX = $x + 2
        for ($i = 0; $i -lt $tabs.Count; $i++) {
            $fg = if ($i -eq $this._activeTab) { [Colors]::Bright } else { [Colors]::Muted }
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
        
        [Logger]::Log("TimeModal.Render: Geometry X=$x Y=$y W=$w H=$h MenuY=$menuY Editing=$($this._editing)", 4)
        
        # Explicitly clear footer line (Corrected width to avoid artifacts)
        $engine.Fill($x + 1, $menuY, $w - 2, 1, " ", [Colors]::Bright, [Colors]::PanelBg)
        
        if ($this._editing) {
            $menu = "[Enter] Save Field  [Tab] Next Field  [Esc] Cancel Edit"
            [Logger]::Log("TimeModal.Render: Drawing EDIT MENU at X=$($x + 2) Y=$menuY Content='$menu'", 4)
            $engine.WriteAt($x + 2, $menuY, $menu, [Colors]::Bright, [Colors]::PanelBg)
        } else {
            $menu = "[N] New  [Enter] Edit  [Delete] Remove  [Tab] Weekly  [Esc] Close"
            [Logger]::Log("TimeModal.Render: Drawing STANDARD MENU at X=$($x + 2) Y=$menuY", 4)
            $engine.WriteAt($x + 2, $menuY, $menu, [Colors]::Bright, [Colors]::PanelBg)
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
        
        # Explicitly clear EVERYTHING below the modal to wipe any ghost text/artifacts
        # Dynamic Wipe: From (Y+H) to (ScreenHeight)
        $wipeY = $y + $h
        if ($wipeY -lt $engine.Height) {
             # Wipe to the very bottom of the screen
             $remainingH = $engine.Height - $wipeY
             $engine.Fill($x, $wipeY, $w, $remainingH, " ", [Colors]::Foreground, [Colors]::Background)
        }
        
        $engine.EndLayer()
    }
    
    hidden [void] _RenderEntriesTab([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$w, [int]$h) {
        # Clear content area
        $engine.Fill($x + 1, $y, $w - 2, $h, " ", [Colors]::Foreground, [Colors]::PanelBg)
        
        # Column headers - Date, Project, ID1, ID2, Hours, Description
        $engine.WriteAt($x + 2, $y, "Date".PadRight(12), [Colors]::Title, [Colors]::PanelBg)
        $engine.WriteAt($x + 14, $y, "Project".PadRight(15), [Colors]::Title, [Colors]::PanelBg)
        $engine.WriteAt($x + 30, $y, "ID1".PadRight(8), [Colors]::Title, [Colors]::PanelBg)
        $engine.WriteAt($x + 39, $y, "ID2".PadRight(8), [Colors]::Title, [Colors]::PanelBg)
        $engine.WriteAt($x + 48, $y, "Hours".PadRight(8), [Colors]::Title, [Colors]::PanelBg)
        $engine.WriteAt($x + 57, $y, "Description", [Colors]::Title, [Colors]::PanelBg)
        
        $engine.WriteAt($x + 1, $y + 1, ("─" * ($w - 2)), [Colors]::PanelBorder, [Colors]::PanelBg)
        
        $listY = $y + 2
        $listH = $h - 4
        # Reduce width to ensure we don't hit the right border (Start 57 + Width < 79)
        # 58 was hitting exact border (index 79). 60 leaves 1 char gap.
        $maxDesc = [Math]::Max(0, $w - 60)
        
        if ($this._timelogs.Count -eq 0) {
            $engine.WriteAt($x + 4, $listY, "(No time entries. Press N to add one)", [Colors]::Muted, [Colors]::PanelBg)
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
                $projName = if ($this._projectName) { $this._projectName } else { "General" }
                if ($projName.Length -gt 14) { $projName = $projName.Substring(0, 14) }
                $id1 = if ($entry['id1']) { $entry['id1'] } else { "" }
                $id2 = if ($entry['id2']) { $entry['id2'] } else { "" }
                $hours = if ($entry['hours']) { "{0:N2}" -f [double]$entry['hours'] } else { "0.00" }
                $desc = if ($entry['description']) { $entry['description'] } else { "" }
                if ($desc.Length -gt $maxDesc) { $desc = $desc.Substring(0, $maxDesc - 3) + "..." }
                
                # Inline Editing Rendering
                if ($this._editing -and $isSelected -and $null -ne $this._editBuffer) {
                    $editVal = $this._editBuffer['Value']
                    
                    $colDate = if ($this._editField -eq 0) { [Colors]::CursorBg } else { $fg }
                    $bgDate = if ($this._editField -eq 0) { [Colors]::Title } else { $bg }
                    $txtDate = if ($this._editField -eq 0) { $editVal.PadRight(12) } else { $date.PadRight(12) }
                    
                    # Project Name is not editable here (it's context)
                    $txtProj = $projName.PadRight(15)
                    
                    $colId1 = if ($this._editField -eq 1) { [Colors]::CursorBg } else { $fg }
                    $bgId1 = if ($this._editField -eq 1) { [Colors]::Title } else { $bg }
                    $txtId1 = if ($this._editField -eq 1) { $editVal.PadRight(8) } else { $id1.PadRight(8) }
                    
                    $colId2 = if ($this._editField -eq 2) { [Colors]::CursorBg } else { $fg }
                    $bgId2 = if ($this._editField -eq 2) { [Colors]::Title } else { $bg }
                    $txtId2 = if ($this._editField -eq 2) { $editVal.PadRight(8) } else { $id2.PadRight(8) }
                    
                    $colHours = if ($this._editField -eq 3) { [Colors]::CursorBg } else { $fg }
                    $bgHours = if ($this._editField -eq 3) { [Colors]::Title } else { $bg }
                    $txtHours = if ($this._editField -eq 3) { $editVal.PadRight(8) } else { $hours.PadRight(8) }
                    
                    $colDesc = if ($this._editField -eq 4) { [Colors]::CursorBg } else { $fg }
                    $bgDesc = if ($this._editField -eq 4) { [Colors]::Title } else { $bg }
                    $txtDesc = if ($this._editField -eq 4) { $editVal } else { $desc.PadRight($maxDesc) }
                    # Clip description while editing to prevent overflow
                    if ($txtDesc.Length -gt $maxDesc) { $txtDesc = $txtDesc.Substring(0, $maxDesc) }
                    
                    $engine.WriteAt($x + 2, $rowY, $txtDate, $colDate, $bgDate)
                    $engine.WriteAt($x + 14, $rowY, $txtProj, $fg, $bg)
                    $engine.WriteAt($x + 30, $rowY, $txtId1, $colId1, $bgId1)
                    $engine.WriteAt($x + 39, $rowY, $txtId2, $colId2, $bgId2)
                    $engine.WriteAt($x + 48, $rowY, $txtHours, $colHours, $bgHours)
                    $engine.WriteAt($x + 57, $rowY, $txtDesc.PadRight($maxDesc), $colDesc, $bgDesc)
                    
                } else {
                    $engine.WriteAt($x + 2, $rowY, $date.PadRight(12), $fg, $bg)
                    $engine.WriteAt($x + 14, $rowY, $projName.PadRight(15), $fg, $bg)
                    $engine.WriteAt($x + 30, $rowY, $id1.PadRight(8), $fg, $bg)
                    $engine.WriteAt($x + 39, $rowY, $id2.PadRight(8), $fg, $bg)
                    $engine.WriteAt($x + 48, $rowY, $hours.PadRight(8), $fg, $bg)
                    $engine.WriteAt($x + 57, $rowY, $desc.PadRight($maxDesc), $fg, $bg)
                }
            }
        }
        
        # Total
        $total = 0.0
        if ($this._timelogs.Count -gt 0) {
            $total = ($this._timelogs | ForEach-Object { [double]$_['hours'] } | Measure-Object -Sum).Sum
        }
        $totalStr = "Total: {0:N2} hours" -f $total
        $engine.WriteAt($x + 2, $y + $h - 1, $totalStr, [Colors]::Title, [Colors]::PanelBg)
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
        $engine.WriteAt($x + 2, $y, "◀ $weekRange ▶  [Weekly Report]", [Colors]::Title, [Colors]::PanelBg)
        
        # Column headers: Project/ID1, Hours, Description
        $headerY = $y + 2
        $engine.WriteAt($x + 2, $headerY, "Project/ID".PadRight(20), [Colors]::Title, [Colors]::PanelBg)
        $engine.WriteAt($x + 22, $headerY, "Hours".PadRight(10), [Colors]::Title, [Colors]::PanelBg)
        $engine.WriteAt($x + 32, $headerY, "Description", [Colors]::Title, [Colors]::PanelBg)
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
            $engine.WriteAt($x + 22, $listY + $row, $hours.PadRight(10), [Colors]::Title, $bg)
            $row++
        }
        
        if ($row -eq 0) {
            $engine.WriteAt($x + 4, $listY, "(No time entries this week)", [Colors]::Muted, [Colors]::PanelBg)
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
        $barColor = if ($pct -ge 100) { [Colors]::Success } elseif ($pct -ge 80) { [Colors]::Warning } else { [Colors]::Error }
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

                        # Ensure scroll keeps new item visible
                        if ($this._selectedIndex -ge $this._scrollOffset + ($this._engine.Height - 10)) {
                             $this._scrollOffset = $this._selectedIndex - ($this._engine.Height - 10) + 1
                        }
                        break
                    }
                }
                
                # Auto-start editing hours (Field 3)
                $this._editField = 3
                $this._editing = $true
                $this._InitEditBuffer()
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
        [Logger]::Log("TimeModal._HandleEditInput: Key=$($key.Key)", 4)
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
                } elseif ($this._editField -eq 2) { # ID2
                     $entry['id2'] = $val
                } elseif ($this._editField -eq 3) { # Hours
                     try { $entry['hours'] = [double]$val } catch {}
                } elseif ($this._editField -eq 4) { # Description
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
                } elseif ($this._editField -eq 2) { # ID2
                     $entry['id2'] = $val
                } elseif ($this._editField -eq 3) { # Hours
                     try { $entry['hours'] = [double]$val } catch {}
                } elseif ($this._editField -eq 4) { # Description
                     $entry['description'] = $val
                }
                
                # Switch field: Date -> ID1 -> ID2 -> Hours -> Description -> Date
                $this._editField = ($this._editField + 1) % 5
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
                } elseif ($this._editField -eq 3) { # Hours -> Decrement
                    try { 
                        $cur = [double]$this._editBuffer['Value'] 
                        $cur = [Math]::Max(0, $cur - 0.25)
                        $this._editBuffer['Value'] = "{0:N2}" -f $cur
                    } catch {}
                    return "Continue"
                }
            }
            'UpArrow' {
                 if ($this._editField -eq 3) { # Hours -> Increment
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
                $val = if ($entry['id2']) { $entry['id2'] } else { "" }
            } elseif ($this._editField -eq 3) {
                $val = if ($entry['hours']) { "$($entry['hours'])" } else { "0" }
            } elseif ($this._editField -eq 4) {
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
        
        # Look up project to pre-fill ID1/ID2
        $projId1 = ""
        $projId2 = ""
        
        if (-not [string]::IsNullOrEmpty($this._projectId)) {
             $state = $this._store.GetState()
             if ($state.Data.projects) {
                $proj = $state.Data.projects | Where-Object { $_['id'] -eq $this._projectId } | Select-Object -First 1
                if ($proj) {
                    if ($proj['id1']) { $projId1 = $proj['id1'] }
                    if ($proj['id2']) { $projId2 = $proj['id2'] }
                }
             }
        }
        
        $newEntry = @{
            id = $id
            projectId = $this._projectId
            date = [DateTime]::Today.ToString("yyyy-MM-dd")
            hours = 0.0
            id1 = $projId1
            id2 = $projId2
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
        $engine.WriteAt($x + 2, $y, " $header ", [Colors]::Bright, [Colors]::Accent)
        
        # Days Header
        $days = "Su Mo Tu We Th Fr Sa"
        $engine.WriteAt($x + 2, $y + 2, $days, [Colors]::Muted, [Colors]::PanelBg)
        
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
                
                $fg = if ($isSelected) { [Colors]::CursorBg } elseif ($isCurrentMonth) { [Colors]::Bright } else { [Colors]::Muted }
                $bg = if ($isSelected) { [Colors]::Title } else { [Colors]::PanelBg }
                
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
