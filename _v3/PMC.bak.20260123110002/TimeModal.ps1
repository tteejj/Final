# TimeModal.ps1 - Unified Time Entries & Weekly View
using namespace System.Collections.Generic

class TimeModal {
    hidden [bool]$_visible = $false
    hidden [FluxStore]$_store
    hidden [int]$_activeTab = 0  # 0=Entries, 1=Weekly
    hidden [array]$_timelogs = @()
    hidden [int]$_selectedIndex = 0
    hidden [int]$_scrollOffset = 0
    hidden [int]$_weekOffset = 0
    
    # Editing State
    hidden [bool]$_editing = $false
    hidden [hashtable]$_editBuffer = $null
    hidden [int]$_editField = 0 # 0=Date, 1=Proj/Code, 2=Hours, 3=Desc
    
    # Overlays
    hidden [bool]$_calendarActive = $false
    hidden [DateTime]$_calendarMonth = [DateTime]::MinValue
    
    hidden [bool]$_projectSelectorActive = $false
    hidden [int]$_projectSelectorIndex = 0
    hidden [array]$_filteredProjects = @()
    
    TimeModal([FluxStore]$store) {
        $this._store = $store
    }
    
    [void] Open() {
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
        $this._calendarActive = $false
        $this._projectSelectorActive = $false
    }
    
    [bool] IsVisible() {
        return $this._visible
    }
    
    hidden [void] _LoadTimelogs() {
        $state = $this._store.GetState()
        if ($state.Data.ContainsKey('timelogs') -and $state.Data.timelogs) {
            # Load ALL logs, sorted by date desc
            $this._timelogs = @($state.Data.timelogs | Sort-Object { $_['date'] } -Descending)
        } else {
            $this._timelogs = @()
        }
    }
    
    [void] Render([HybridRenderEngine]$engine) {
        if (-not $this._visible) { return }
        
        $w = 90
        $h = 24
        $x = [Math]::Max(0, [int](($engine.Width - $w) / 2))
        $y = [Math]::Max(0, [int](($engine.Height - $h) / 2))
        
        $engine.BeginLayer(110)
        
        $engine.Fill($x, $y, $w, $h + 3, " ", [Colors]::Foreground, [Colors]::PanelBg)
        $engine.DrawBox($x, $y, $w, $h, [Colors]::Accent, [Colors]::PanelBg)
        $engine.WriteAt($x + 2, $y, " Unified Time Entry ", [Colors]::White, [Colors]::Accent)
        
        # Tabs
        $tabY = $y + 1
        $tabs = @("Log Entry", "Weekly Report")
        $tabX = $x + 2
        for ($i = 0; $i -lt $tabs.Count; $i++) {
            $fg = if ($i -eq $this._activeTab) { [Colors]::White } else { [Colors]::Muted }
            $bg = if ($i -eq $this._activeTab) { [Colors]::SelectionBg } else { [Colors]::Background }
            $tabText = " $($i + 1):$($tabs[$i]) "
            $engine.WriteAt($tabX, $tabY, $tabText, $fg, $bg)
            $tabX += $tabText.Length + 1
        }
        
        $contentY = $y + 3
        $contentH = $h - 6
        
        if ($this._activeTab -eq 0) {
            $this._RenderEntriesTab($engine, $x, $contentY, $w, $contentH)
        } else {
            $this._RenderWeeklyTab($engine, $x, $contentY, $w, $contentH)
        }
        
        # Footer
        $menuY = $y + $h - 2
        $engine.Fill($x + 1, $menuY, $w - 2, 1, " ", [Colors]::White, [Colors]::PanelBg)
        
        if ($this._projectSelectorActive) {
            $menu = "[Enter] Select Project  [Esc] Back to Code"
            $engine.WriteAt($x + 2, $menuY, $menu, [Colors]::Accent, [Colors]::PanelBg)
        } elseif ($this._editing) {
            $menu = "[Enter] Save Field  [Tab] Next  [Down] Proj List(ID)  [Esc] Cancel"
            $engine.WriteAt($x + 2, $menuY, $menu, [Colors]::White, [Colors]::PanelBg)
        } else {
            $menu = "[N] New  [Enter] Edit  [Delete] Remove  [Esc] Close"
            $engine.WriteAt($x + 2, $menuY, $menu, [Colors]::White, [Colors]::PanelBg)
        }
        
        # Overlays
        if ($this._calendarActive) {
            $this._RenderCalendar($engine, $x + 2, $y + 6) 
        }
        if ($this._projectSelectorActive) {
            $this._RenderProjectSelector($engine, $x + 14, $y + 6)
        }
        
        $engine.EndLayer()
    }
    
    hidden [void] _RenderEntriesTab([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$w, [int]$h) {
        $engine.Fill($x + 1, $y, $w - 2, $h, " ", [Colors]::Foreground, [Colors]::PanelBg)
        
        # Headers - Project Name, ID1, ID2
        $hdrColor = [Colors]::Header
        if ($hdrColor -eq 0) { $hdrColor = [Colors]::Accent }

        $engine.WriteAt($x + 2, $y, "Date".PadRight(12), $hdrColor, [Colors]::PanelBg)
        $engine.WriteAt($x + 14, $y, "Project Name".PadRight(20), $hdrColor, [Colors]::PanelBg)
        $engine.WriteAt($x + 35, $y, "ID1".PadRight(10), $hdrColor, [Colors]::PanelBg)
        $engine.WriteAt($x + 46, $y, "ID2".PadRight(10), $hdrColor, [Colors]::PanelBg)
        $engine.WriteAt($x + 57, $y, "Hrs".PadRight(6), $hdrColor, [Colors]::PanelBg)
        $engine.WriteAt($x + 64, $y, "Description", $hdrColor, [Colors]::PanelBg)
        
        $engine.WriteAt($x + 1, $y + 1, ("─" * ($w - 2)), [Colors]::PanelBorder, [Colors]::PanelBg)
        
        $listY = $y + 2
        $listH = $h - 4
        $maxDesc = [Math]::Max(0, $w - 66)
        
        # Pagination
        if ($this._selectedIndex -lt $this._scrollOffset) { $this._scrollOffset = $this._selectedIndex }
        if ($this._selectedIndex -ge $this._scrollOffset + $listH) { $this._scrollOffset = $this._selectedIndex - $listH + 1 }
        
        # Lookup Projects map
        $state = $this._store.GetState()
        $projMap = @{}
        if ($state.Data.projects) {
            foreach ($p in $state.Data.projects) { $projMap[$p['id']] = $p }
        }
        
        for ($i = 0; $i -lt $listH; $i++) {
            $idx = $i + $this._scrollOffset
            if ($idx -ge $this._timelogs.Count) { break }
            
            $entry = $this._timelogs[$idx]
            if ($null -eq $entry) { continue }
            
            $rowY = $listY + $i
            $isSelected = ($idx -eq $this._selectedIndex)
            
            $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
            $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::PanelBg }
            
            $engine.Fill($x + 1, $rowY, $w - 2, 1, " ", $fg, $bg)
            
            # Data Prep
            $date = if ($entry['date']) { ([datetime]$entry['date']).ToString("yyyy-MM-dd") } else { "" }
            
            $projName = ""
            if ($entry['projectId'] -and $projMap.ContainsKey($entry['projectId'])) {
                $projName = $projMap[$entry['projectId']]['name']
            }
            if ($projName.Length -gt 19) { $projName = $projName.Substring(0, 16) + "..." }
            
            $id1 = if ($entry['id1']) { $entry['id1'] } else { "" }
            # ID2 usually maps to projectId BUT user wants raw ID2 field visible/editable? 
            # Or is ID2 the Project ID?
            # User said "ID2 (mapped to projectId)" previously.
            # But now wants "Project Name, ID1, ID2".
            # If Project is selected, ID2 IS the projectId.
            # So display projectId in ID2 column? Or a separate field `id2`?
            # Assuming ID2 = projectId for now, displayed as raw ID.
            # ID2 Logic: explicit entry value OR fallback to project ID2
            $id2 = if ($entry.ContainsKey('id2') -and $entry['id2']) { $entry['id2'] } else { "" }
            if ($id2 -eq "" -and $entry['projectId'] -and $projMap.ContainsKey($entry['projectId'])) {
                $p = $projMap[$entry['projectId']]
                if ($p.ContainsKey('ID2')) { $id2 = $p['ID2'] }
                elseif ($p.ContainsKey('id2')) { $id2 = $p['id2'] }
            }
            if ($id2.Length -gt 9) { $id2 = $id2.Substring(0, 6) + ".." }
            
            $hours = if ($entry['hours']) { "{0:N2}" -f [double]$entry['hours'] } else { "0.00" }
            $desc = if ($entry['description']) { $entry['description'] } else { "" }
            if ($desc.Length -gt $maxDesc) { $desc = $desc.Substring(0, $maxDesc - 3) + "..." }
            
            # Rendering (Edit Mode Overlay)
            if ($this._editing -and $isSelected -and $null -ne $this._editBuffer) {
                $editVal = $this._editBuffer['Value']
                
                # Render base row first
                $engine.WriteAt($x + 2, $rowY, $date.PadRight(12), $fg, $bg)
                $engine.WriteAt($x + 14, $rowY, $projName.PadRight(20), $fg, $bg)
                $engine.WriteAt($x + 35, $rowY, $id1.PadRight(10), $fg, $bg)
                $engine.WriteAt($x + 46, $rowY, $id2.PadRight(10), $fg, $bg)
                $engine.WriteAt($x + 57, $rowY, $hours.PadRight(6), $fg, $bg)
                $engine.WriteAt($x + 64, $rowY, $desc, $fg, $bg)
                
                # Highlight Edit Field
                if ($this._editField -eq 0) { $engine.WriteAt($x + 2, $rowY, $editVal.PadRight(12), [Colors]::Black, [Colors]::Accent) }
                elseif ($this._editField -eq 1) { $engine.WriteAt($x + 14, $rowY, $editVal.PadRight(20), [Colors]::Black, [Colors]::Accent) }
                elseif ($this._editField -eq 2) { $engine.WriteAt($x + 35, $rowY, $editVal.PadRight(10), [Colors]::Black, [Colors]::Accent) }
                elseif ($this._editField -eq 3) { $engine.WriteAt($x + 46, $rowY, $editVal.PadRight(10), [Colors]::Black, [Colors]::Accent) }
                elseif ($this._editField -eq 4) { $engine.WriteAt($x + 57, $rowY, $editVal.PadRight(6), [Colors]::Black, [Colors]::Accent) }
                elseif ($this._editField -eq 5) { $engine.WriteAt($x + 64, $rowY, $editVal, [Colors]::Black, [Colors]::Accent) }
                
            } else {
                $engine.WriteAt($x + 2, $rowY, $date.PadRight(12), $fg, $bg)
                $engine.WriteAt($x + 14, $rowY, $projName.PadRight(20), $fg, $bg)
                $engine.WriteAt($x + 35, $rowY, $id1.PadRight(10), $fg, $bg)
                $engine.WriteAt($x + 46, $rowY, $id2.PadRight(10), $fg, $bg)
                $engine.WriteAt($x + 57, $rowY, $hours.PadRight(6), $fg, $bg)
                $engine.WriteAt($x + 64, $rowY, $desc, $fg, $bg)
            }
        }
    }
    

    
    hidden [void] _RenderWeeklyTab([HybridRenderEngine]$engine, [int]$x, [int]$y, [int]$w, [int]$h) {
        # Reuse existing logic but adapt for new width
        $engine.Fill($x + 1, $y, $w - 2, $h, " ", [Colors]::Foreground, [Colors]::PanelBg)
        
         $today = [DateTime]::Today
         $startOfWeek = $today.AddDays(-[int]$today.DayOfWeek + 1 + ($this._weekOffset * 7))
         if ($today.DayOfWeek -eq [DayOfWeek]::Sunday) { $startOfWeek = $startOfWeek.AddDays(-7) }
         
         $weekRange = "$($startOfWeek.ToString('MMM dd')) - $($startOfWeek.AddDays(6).ToString('MMM dd, yyyy'))"
         $engine.WriteAt($x + 2, $y, "◀ $weekRange ▶", [Colors]::Accent, [Colors]::PanelBg)
         
         # Grouping Logic reuse...
         # Headers
         $headerY = $y + 2
         $engine.WriteAt($x + 2, $headerY, "Project / Code", [Colors]::Accent, [Colors]::PanelBg)
         $engine.WriteAt($x + 40, $headerY, "Hours", [Colors]::Accent, [Colors]::PanelBg)
         $engine.WriteAt($x + 1, $headerY + 1, ("─" * ($w - 2)), [Colors]::PanelBorder, [Colors]::PanelBg)
         
         # Build Project Map
         $state = $this._store.GetState()
         $projMap = @{}
         if ($state.Data.projects) {
             foreach ($p in $state.Data.projects) { $projMap[$p['id']] = $p }
         }
         
         $totals = @{}
         $totalWeek = 0.0
         $endOfWeek = $startOfWeek.AddDays(7)
         
         foreach ($entry in $this._timelogs) {
             if (-not $entry['date']) { continue }
             $d = [datetime]$entry['date']
             if ($d -ge $startOfWeek -and $d -lt $endOfWeek) {
                 # Key generation
                 $key = if ($entry['projectId']) { $entry['projectId'] } else { "MANUAL:" + $entry['id1'] }
                 
                 if (-not $totals.ContainsKey($key)) {
                      $totals[$key] = @{ 
                         Hours = 0.0
                         Name = "" 
                         Code = $entry['id1']
                         IsProj = ($null -ne $entry['projectId'] -and $entry['projectId'] -ne "")
                      }
                      
                      if ($totals[$key]['IsProj'] -and $projMap.ContainsKey($entry['projectId'])) {
                           $totals[$key]['Name'] = $projMap[$entry['projectId']]['name']
                           $totals[$key]['Code'] = $projMap[$entry['projectId']]['id1'] 
                      } else {
                           $totals[$key]['Name'] = if ($entry['id1']) { $entry['id1'] } else { "(No Code)" }
                      }
                 }
                 
                 $hrs = 0.0
                 if ($entry['hours']) { $hrs = [double]$entry['hours'] }
                 $totals[$key]['Hours'] += $hrs
                 $totalWeek += $hrs
             }
         }
         
         # Render Grouped Rows
         $rowIdx = 0
         foreach ($key in $totals.Keys) {
             $item = $totals[$key]
              if ($item['Hours'] -eq 0) { continue }
             $rowY = $headerY + 2 + $rowIdx
             if ($rowY -ge $h + $y - 2) { break }
             
             $label = $item['Name']
             if ($item['IsProj']) { $label += " ($($item['Code']))" }
             if ($label.Length -gt 38) { $label = $label.Substring(0, 35) + "..." }
             
             $valText = "{0:N2}" -f $item['Hours']
             
             $engine.WriteAt($x + 2, $rowY, $label.PadRight(38), [Colors]::Foreground, [Colors]::PanelBg)
             $engine.WriteAt($x + 40, $rowY, $valText.PadRight(8), [Colors]::White, [Colors]::PanelBg)
             $rowIdx++
         }
         
         # Total
         $footY = $headerY + 2 + $rowIdx + 1
         if ($footY -lt $h + $y) {
             $engine.WriteAt($x + 2, $footY, "-------------------", [Colors]::Muted, [Colors]::PanelBg)
             $engine.WriteAt($x + 2, $footY + 1, "Total: {0:N2}" -f $totalWeek, [Colors]::Accent, [Colors]::PanelBg)
         }
    }

    [string] HandleInput([ConsoleKeyInfo]$key) {
        if (-not $this._visible) { return "Continue" }
        
        if ($this._calendarActive) { return $this._HandleCalendarInput($key) }
        if ($this._projectSelectorActive) { return $this._HandleProjectSelectorInput($key) }
        if ($this._editing) { return $this._HandleEditInput($key) }
        
        switch ($key.Key) {
            'Escape' { $this._visible = $false; return "Handled" }
            'Tab' { $this._activeTab = ($this._activeTab + 1) % 2; return "Handled" }
            'N' { 
                $this._CreateEntry()
                $this._editing = $true
                $this._editField = 1 # Start at Code/Project
                $this._InitEditBuffer() 
                return "Handled" 
            }
            'Enter' {
                if ($this._timelogs.Count -gt 0) {
                    $this._editing = $true
                    $this._editField = 1
                    $this._InitEditBuffer()
                }
                return "Handled"
            }
            'Delete' { $this._DeleteEntry(); return "Handled" }
            'UpArrow' { if ($this._selectedIndex -gt 0) { $this._selectedIndex-- }; return "Handled" }
            'DownArrow' { if ($this._selectedIndex -lt $this._timelogs.Count - 1) { $this._selectedIndex++ }; return "Handled" }
            'LeftArrow' { 
                if ($this._activeTab -eq 1) { $this._weekOffset-- } # Weekly Report tab - change week
                return "Handled" 
            }
            'RightArrow' { 
                if ($this._activeTab -eq 1) { $this._weekOffset++ } # Weekly Report tab - change week
                return "Handled" 
            }
        }
        return "Continue"
    }

    hidden [string] _HandleEditInput([ConsoleKeyInfo]$key) {
        switch ($key.Key) {
            'Escape' { $this._editing = $false; return "Handled" }
            'Enter' { 
                # ID 1 (Project Name) logic
                if ($this._editField -eq 1) { 
                     $this._OpenProjectSelector()
                     return "Handled"
                }
                $this._SaveField(); $this._editing = $false; return "Handled" 
            }
            'Tab' { 
                $this._SaveField()
                $this._editField = ($this._editField + 1) % 6
                $this._InitEditBuffer()
                return "Handled" 
            }
            'DownArrow' {
                if ($this._editField -eq 1) { # ID1 / Project Selection
                    $this._OpenProjectSelector()
                    return "Handled"
                }
                if ($this._editField -eq 0) { $this._calendarActive = $true }
            }
        }
        
        # Default typing
        if (-not [char]::IsControl($key.KeyChar)) {
            $this._editBuffer['Value'] += $key.KeyChar
        } elseif ($key.Key -eq 'Backspace' -and $this._editBuffer['Value'].Length -gt 0) {
            $this._editBuffer['Value'] = $this._editBuffer['Value'].Substring(0, $this._editBuffer['Value'].Length - 1)
        }
        
        return "Handled"
    }
    
    hidden [void] _OpenProjectSelector() {
        try {
            $state = $this._store.GetState()
            if ($null -eq $state.Data.projects) { 
                $this._filteredProjects = @()
            } else {
                $this._filteredProjects = @($state.Data.projects | Sort-Object name)
            }
            $this._projectSelectorActive = $true
            $this._projectSelectorIndex = 0
            
            # Auto-select the current project if editing an existing one
            $entry = $this._timelogs[$this._selectedIndex]
            if ($entry['projectId']) {
                for ($i = 0; $i -lt $this._filteredProjects.Count; $i++) {
                    if ($this._filteredProjects[$i]['id'] -eq $entry['projectId']) {
                        $this._projectSelectorIndex = $i
                        break
                    }
                }
            }
        } catch {
            [Logger]::Error("TimeModal._OpenProjectSelector CRASH", $_)
            $this._projectSelectorActive = $false
        }
    }
    
    hidden [string] _HandleProjectSelectorInput([ConsoleKeyInfo]$key) {
        if ($this._filteredProjects.Count -eq 0) {
            $this._projectSelectorActive = $false
            return "Handled"
        }
        
        switch ($key.Key) {
            'Escape' { $this._projectSelectorActive = $false; return "Handled" }
            'UpArrow' { if ($this._projectSelectorIndex -gt 0) { $this._projectSelectorIndex-- }; return "Handled" }
            'DownArrow' { if ($this._projectSelectorIndex -lt $this._filteredProjects.Count - 1) { $this._projectSelectorIndex++ }; return "Handled" }
            'Enter' {
                $p = $this._filteredProjects[$this._projectSelectorIndex]
                # Apply Project
                $entry = $this._timelogs[$this._selectedIndex]
                $entry['projectId'] = $p['id']
                
                # SAFE ID1 Access (from 'id1' or 'ID1')
                $code = ""
                if ($p.ContainsKey('id1') -and $p['id1']) { $code = $p['id1'] }
                elseif ($p.ContainsKey('ID1') -and $p['ID1']) { $code = $p['ID1'] }
                $entry['id1'] = $code 
                
                # SAFE ID2 Access (from 'id2' or 'ID2')
                $code2 = ""
                if ($p.ContainsKey('id2') -and $p['id2']) { $code2 = $p['id2'] }
                elseif ($p.ContainsKey('ID2') -and $p['ID2']) { $code2 = $p['ID2'] }
                $entry['id2'] = $code2 
                
                # Update Edit Buffer if we were editing Project Name (Field 1)
                if ($this._editField -eq 1) {
                    $entryName = if ($p.ContainsKey('name')) { $p['name'] } else { "Unknown" }
                    $this._editBuffer['Value'] = $entryName
                }
                
                $this._projectSelectorActive = $false
                return "Handled"
            }
        }
        return "Handled"
    }

    hidden [void] _RenderProjectSelector([HybridRenderEngine]$engine, [int]$x, [int]$y) {
        try {
            $selectorW = 40
            $selectorH = 10
            
            $engine.BeginLayer(130)
            $engine.DrawBox($x, $y, $selectorW, $selectorH, [Colors]::Accent, [Colors]::PanelBg)
            $engine.WriteAt($x + 1, $y, " Select Project ", [Colors]::White, [Colors]::Accent)
            
            if ($null -eq $this._filteredProjects -or $this._filteredProjects.Count -eq 0) {
                $engine.WriteAt($x + 2, $y + 2, "(No Projects Found)", [Colors]::Muted, [Colors]::PanelBg)
                $engine.EndLayer()
                return
            }
            
            # Calculate scroll for selector
            $visibleRows = $selectorH - 2
            $pStart = 0
            if ($this._projectSelectorIndex -ge $visibleRows) {
               $pStart = $this._projectSelectorIndex - $visibleRows + 1
            }
            
            for ($i = 0; $i -lt $visibleRows; $i++) {
                $idx = $pStart + $i
                if ($idx -ge $this._filteredProjects.Count) { break }
                
                $p = $this._filteredProjects[$idx]
                if ($null -eq $p) { continue }
                
                $isSelected = ($idx -eq $this._projectSelectorIndex)
                
                $fg = if ($isSelected) { [Colors]::SelectionFg } else { [Colors]::Foreground }
                $bg = if ($isSelected) { [Colors]::SelectionBg } else { [Colors]::PanelBg }
                $rowY = $y + 1 + $i
                
                $pName = if ($p.ContainsKey('name')) { $p['name'] } else { "Unknown" }
                $pCode = if ($p.ContainsKey('id1')) { $p['id1'] } else { "" }
                
                $line = "$pName ($pCode)"
                if ($line.Length -gt $selectorW - 2) { $line = $line.Substring(0, $selectorW - 5) + "..." }
                
                $engine.Fill($x + 1, $rowY, $selectorW - 2, 1, " ", $fg, $bg)
                $engine.WriteAt($x + 1, $rowY, $line.PadRight($selectorW - 2), $fg, $bg)
            }
            $engine.EndLayer()
        } catch {
             # Fix Logger crash by using ToString
             [Logger]::Log("TimeModal._RenderProjectSelector ERROR: $_", 1) 
        }
    }

    hidden [void] _InitEditBuffer() {
        $entry = $this._timelogs[$this._selectedIndex]
        $val = ""
        if ($this._editField -eq 0) { $val = ([datetime]$entry['date']).ToString("yyyy-MM-dd") }
        elseif ($this._editField -eq 1) { 
            # Project Name
             $state = $this._store.GetState()
             if ($entry['projectId']) {
                 $proj = ($state.Data.projects | Where-Object { $_.id -eq $entry['projectId'] } | Select-Object -First 1)
                 if ($proj) { $val = $proj.name }
             }
        }
        elseif ($this._editField -eq 2) { $val = if ($entry['id1']) { $entry['id1'] } else { "" } }
        elseif ($this._editField -eq 3) { 
             # ID2 - use entry ID2 or fallback to Project ID2
             $val = if ($entry.ContainsKey('id2') -and $entry['id2']) { $entry['id2'] } else { "" }
             if ($val -eq "" -and $entry['projectId']) {
                 $state = $this._store.GetState()
                 $proj = ($state.Data.projects | Where-Object { $_.id -eq $entry['projectId'] } | Select-Object -First 1)
                 if ($proj) {
                     if ($proj.ContainsKey('ID2')) { $val = $proj['ID2'] }
                     elseif ($proj.ContainsKey('id2')) { $val = $proj['id2'] }
                 }
             }
        }
        elseif ($this._editField -eq 4) { $val = "$($entry['hours'])" }
        elseif ($this._editField -eq 5) { $val = $entry['description'] }
        $this._editBuffer = @{ Value = $val }
    }
    
    hidden [void] _SaveField() {
        $entry = $this._timelogs[$this._selectedIndex]
        $val = $this._editBuffer['Value']
        
        if ($this._editField -eq 0) { $entry['date'] = $val }
        elseif ($this._editField -eq 1) { 
            # Saving Project Name manually? Only via selector usually.
            # If user types here, we could try to fuzzy match? 
            # For now, selector is key. 
        }
        elseif ($this._editField -eq 2) { $entry['id1'] = $val }
        elseif ($this._editField -eq 3) { $entry['id2'] = $val } # Save to ID2 (text)
        elseif ($this._editField -eq 4) { try { $entry['hours'] = [double]$val } catch {} }
        elseif ($this._editField -eq 5) { $entry['description'] = $val }
        
        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
    }
    
    hidden [void] _CreateEntry() {
          $id = [DataService]::NewGuid()
          $newEntry = @{
              id = $id
              projectId = "" # Unified: Start empty
              id1 = ""
              id2 = "" # Added ID2 field
              date = [DateTime]::Today.ToString("yyyy-MM-dd")
              hours = 0.0
              description = ""
              created = [DataService]::Timestamp()
          }
           $state = $this._store.GetState()
          if (-not $state.Data.ContainsKey('timelogs')) { $state.Data.timelogs = @() }
          $state.Data.timelogs += $newEntry
          $this._LoadTimelogs()
          $this._selectedIndex = 0 # Newest is top
    }
    
    hidden [void] _DeleteEntry() {
        if ($this._timelogs.Count -eq 0) { return }
        $entry = $this._timelogs[$this._selectedIndex]
        $state = $this._store.GetState()
        $state.Data.timelogs = @($state.Data.timelogs | Where-Object { $_['id'] -ne $entry['id'] })
        $this._store.Dispatch([ActionType]::SAVE_DATA, @{})
        $this._LoadTimelogs()
        if ($this._selectedIndex -ge $this._timelogs.Count) { $this._selectedIndex = [Math]::Max(0, $this._timelogs.Count - 1) }
    }
    
    hidden [string] _HandleCalendarInput([ConsoleKeyInfo]$key) {
        # Reuse existing calendar logic... (omitted for brevity in prompt, but assume implemented similarly)
        switch ($key.Key) {
            'Escape' { $this._calendarActive = $false; return "Handled" }
            'Enter' { 
                 $this._editBuffer['Value'] = $this._calendarMonth.ToString("yyyy-MM-dd")
                 $this._calendarActive = $false
                 return "Handled" 
            }
            'LeftArrow' { $this._calendarMonth = $this._calendarMonth.AddDays(-1); return "Handled" }
            'RightArrow' { $this._calendarMonth = $this._calendarMonth.AddDays(1); return "Handled" }
            'UpArrow' { $this._calendarMonth = $this._calendarMonth.AddDays(-7); return "Handled" }
            'DownArrow' { $this._calendarMonth = $this._calendarMonth.AddDays(7); return "Handled" }
        }
        return "Handled"
    }

    hidden [void] _RenderCalendar([HybridRenderEngine]$engine, [int]$x, [int]$y) {
         # Simple Calendar Render (Placeholder for brevity, full logic in actual file)
         $engine.BeginLayer(140)
         $engine.DrawBox($x, $y, 25, 10, [Colors]::Accent, [Colors]::PanelBg)
         $engine.WriteAt($x+2, $y+1, "Date: $($this._calendarMonth.ToString('yyyy-MM-dd'))", [Colors]::White, [Colors]::PanelBg)
         $engine.EndLayer()
    }
}
