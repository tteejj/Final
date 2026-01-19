# WeeklyView.ps1 - Weekly Time Report Grid
using namespace System.Collections.Generic
using namespace System.Globalization

class WeeklyView {
    hidden [int]$_weekOffset = 0
    
    [void] Render([HybridRenderEngine]$engine, [hashtable]$state) {
        $w = $engine.Width
        $h = $engine.Height - 2
        
        # Calculate Dates
        $today = [DateTime]::Today
        $diff = (7 + ($today.DayOfWeek - [DayOfWeek]::Monday)) % 7
        $monday = $today.AddDays(-1 * $diff).AddDays($this._weekOffset * 7)
        
        $weekDates = @()
        for ($i = 0; $i -lt 7; $i++) { $weekDates += $monday.AddDays($i) }
        
        # Title
        $title = "Weekly Report: $($monday.ToString('MMM dd')) - $($weekDates[6].ToString('MMM dd'))"
        if ($this._weekOffset -eq 0) { $title += " (This Week)" }
        $engine.DrawBox(0, 0, $w, $h, [Colors]::Accent, [Colors]::Background)
        $engine.WriteAt(2, 0, " $title ", [Colors]::White, [Colors]::Background)
        
        # Grid Headers
        # Name (20) | Mon | Tue | Wed | Thu | Fri | Sat | Sun | Total
        $colW = 8
        $nameW = 20
        $startX = 2
        $headerY = 2
        
        $engine.WriteAt($startX, $headerY, "Project".PadRight($nameW), [Colors]::Cyan, [Colors]::Background)
        
        $x = $startX + $nameW + 1
        $days = @("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
        for ($i = 0; $i -lt 7; $i++) {
            $d = $days[$i]
            $date = $weekDates[$i]
            $header = "$d " + $date.Day
            $engine.WriteAt($x, $headerY, $header.PadLeft($colW), [Colors]::Cyan, [Colors]::Background)
            $x += $colW + 1
        }
        $engine.WriteAt($x, $headerY, "Total".PadLeft($colW), [Colors]::White, [Colors]::Background)
        
        $engine.Fill($startX, $headerY + 1, $w - 4, 1, "-", [Colors]::DarkGray, [Colors]::Background)
        
        # Process Data
        $timelogs = $state.Data.timelogs
        $projects = $state.Data.projects
        
        # Group by Project -> Day -> Sum
        $matrix = @{} # ProjId -> [Array of 7 days]
        $projNames = @{}
        
        # Init Matrix
        foreach ($p in $projects) {
            $matrix[$p.id] = [double[]]::new(7)
            $projNames[$p.id] = $p.name
        }
        # Catch logs with no project or unknown project
        $unknownId = "UNKNOWN"
        $matrix[$unknownId] = [double[]]::new(7)
        $projNames[$unknownId] = "(No Project)"
        
        # Aggregate
        foreach ($log in $timelogs) {
            if ($log.date) {
                try {
                    $d = [DateTime]::Parse($log.date)
                    $logDate = $d.Date
                    
                    if ($logDate -ge $monday -and $logDate -le $weekDates[6]) {
                        $dayIdx = ($logDate - $monday).Days
                        $projId = if ($log.projectId) { $log.projectId } else { $unknownId }
                        if (-not $matrix.ContainsKey($projId)) {
                            $matrix[$projId] = [double[]]::new(7)
                            $projNames[$projId] = "Unknown ($projId)"
                        }
                        
                        $hours = [Math]::Round($log.minutes / 60.0, 2)
                        $matrix[$projId][$dayIdx] += $hours
                    }
                } catch {}
            }
        }
        
        # Render Rows
        $y = $headerY + 2
        $grandTotal = 0
        $dayTotals = [double[]]::new(7)
        
        foreach ($projId in $matrix.Keys) {
            $row = $matrix[$projId]
            $rowTotal = 0
            $hasData = $false
            for ($i=0; $i -lt 7; $i++) { 
                if ($row[$i] -gt 0) { $hasData = $true }
                $rowTotal += $row[$i]
                $dayTotals[$i] += $row[$i]
            }
            
            if ($hasData) {
                if ($y -ge $h - 2) { break }
                
                $name = $projNames[$projId]
                if ($name.Length -gt $nameW) { $name = $name.Substring(0, $nameW) }
                $engine.WriteAt($startX, $y, $name.PadRight($nameW), [Colors]::White, [Colors]::Background)
                
                $x = $startX + $nameW + 1
                for ($i = 0; $i -lt 7; $i++) {
                    $val = $row[$i]
                    $txt = if ($val -gt 0) { $val.ToString("0.0") } else { "-" }
                    $col = if ($val -gt 0) { [Colors]::Green } else { [Colors]::DarkGray }
                    $engine.WriteAt($x, $y, $txt.PadLeft($colW), $col, [Colors]::Background)
                    $x += $colW + 1
                }
                
                $engine.WriteAt($x, $y, $rowTotal.ToString("0.0").PadLeft($colW), [Colors]::White, [Colors]::Background)
                $grandTotal += $rowTotal
                $y++
            }
        }
        
        # Totals Row
        $engine.Fill($startX, $y, $w - 4, 1, "-", [Colors]::DarkGray, [Colors]::Background)
        $y++
        $engine.WriteAt($startX, $y, "TOTALS".PadRight($nameW), [Colors]::White, [Colors]::Background)
        
        $x = $startX + $nameW + 1
        for ($i = 0; $i -lt 7; $i++) {
            $val = $dayTotals[$i]
            $txt = if ($val -gt 0) { $val.ToString("0.0") } else { "-" }
            $engine.WriteAt($x, $y, $txt.PadLeft($colW), [Colors]::White, [Colors]::Background)
            $x += $colW + 1
        }
        $engine.WriteAt($x, $y, $grandTotal.ToString("0.0").PadLeft($colW), [Colors]::Accent, [Colors]::Background)
        
        # Status Bar
        $engine.Fill(0, $h, $w, 2, " ", [Colors]::Foreground, [Colors]::SelectionBg)
        $engine.WriteAt(0, $h + 1, " [Weekly] | arrows: Navigate | Esc: Back", [Colors]::White, [Colors]::SelectionBg)
    }
    
    [bool] HandleInput([ConsoleKeyInfo]$key) {
        switch ($key.Key) {
            'LeftArrow' { $this._weekOffset--; return $true }
            'RightArrow' { $this._weekOffset++; return $true }
            'Escape' { return $false } # Signal to exit view
        }
        return $true
    }
}
