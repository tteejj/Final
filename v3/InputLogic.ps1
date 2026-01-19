# InputLogic.ps1 - Pure logic for smart parsing and data handling
# Ported from legacy widgets (DatePicker, TextInput, ProjectPicker) to support the new architecture.

using namespace System
using namespace System.Globalization

class InputLogic {

    # === Date Logic ===

    static [DateTime] ParseDateInput([string]$input) {
        $text = $input.Trim().ToLower()
        if ([string]::IsNullOrWhiteSpace($text)) { return [DateTime]::MinValue }

        # 1. Relative Days (+1, -7)
        if ($text -match '^([+-])(\d+)$') {
            $sign = $matches[1]
            $days = [int]$matches[2]
            return [DateTime]::Today.AddDays($(if ($sign -eq '-') { -$days } else { $days }))
        }

        # 2. Keywords
        switch ($text) {
            'today'     { return [DateTime]::Today }
            't'         { return [DateTime]::Today }
            'tomorrow'  { return [DateTime]::Today.AddDays(1) }
            'tom'       { return [DateTime]::Today.AddDays(1) }
            'yesterday' { return [DateTime]::Today.AddDays(-1) }
            'eom'       { 
                $now = [DateTime]::Today
                return [DateTime]::new($now.Year, $now.Month, [DateTime]::DaysInMonth($now.Year, $now.Month))
            }
            'som'       {
                $now = [DateTime]::Today
                return [DateTime]::new($now.Year, $now.Month, 1)
            }
        }

        # 3. Next [DayOfWeek]
        if ($text -match '^next\s+(\w+)') {
            $targetDay = [InputLogic]::ParseDayOfWeek($matches[1])
            if ($null -ne $targetDay) {
                $today = [DateTime]::Today
                $daysUntil = (([int]$targetDay - [int]$today.DayOfWeek + 7) % 7)
                if ($daysUntil -eq 0) { $daysUntil = 7 }
                return $today.AddDays($daysUntil)
            }
        }

        # 4. Compact Formats (20250101, 250101)
        if ($text -match '^\d{8}$') {
            try { return [DateTime]::ParseExact($text, 'yyyyMMdd', [CultureInfo]::InvariantCulture) } catch {}
        }
        if ($text -match '^\d{6}$') {
            try { return [DateTime]::ParseExact($text, 'yyMMdd', [CultureInfo]::InvariantCulture) } catch {}
        }

        # 5. Standard Formats
        try { return [DateTime]::Parse($text) } catch {}

        return [DateTime]::MinValue
    }

    static [object] ParseDayOfWeek([string]$name) {
        switch -Regex ($name.ToLower()) {
            '^su(n|nday)?$' { return [DayOfWeek]::Sunday }
            '^mo(n|nday)?$' { return [DayOfWeek]::Monday }
            '^tu(e|es|esday)?$' { return [DayOfWeek]::Tuesday }
            '^we(d|dnesday)?$' { return [DayOfWeek]::Wednesday }
            '^th(u|ursday)?$' { return [DayOfWeek]::Thursday }
            '^fr(i|iday)?$' { return [DayOfWeek]::Friday }
            '^sa(t|turday)?$' { return [DayOfWeek]::Saturday }
        }
        return $null
    }

    # === Time Logic ===

    # Increments/Decrements time in 0.25 (15 min) steps
    static [double] AdjustTime([double]$current, [string]$direction, [double]$min, [double]$max) {
        $step = 0.25
        $newValue = $current
        
        if ($direction -eq 'Up' -or $direction -eq 'Right') {
            $newValue += $step
        } else {
            $newValue -= $step
        }

        # Clamp
        if ($newValue -lt $min) { $newValue = $min }
        if ($newValue -gt $max) { $newValue = $max }

        return [Math]::Round($newValue, 2)
    }

    # === Project Fuzzy Search ===

    static [array] FuzzySearchProjects([string[]]$projects, [string]$query) {
        if ([string]::IsNullOrWhiteSpace($query)) { return $projects }
        
        $searchLower = $query.ToLower()
        $matches = [System.Collections.ArrayList]::new()

        foreach ($p in $projects) {
            $pLower = $p.ToLower()
            
            # Exact/Contains
            if ($pLower.Contains($searchLower)) {
                [void]$matches.Add($p)
                continue
            }

            # Initials / Subsequence (Simple)
            # e.g. "wd" matches "Web Dev"
            $pIdx = 0
            $sIdx = 0
            while ($pIdx -lt $pLower.Length -and $sIdx -lt $searchLower.Length) {
                if ($pLower[$pIdx] -eq $searchLower[$sIdx]) {
                    $sIdx++
                }
                $pIdx++
            }
            if ($sIdx -eq $searchLower.Length) {
                [void]$matches.Add($p)
            }
        }
        return $matches.ToArray()
    }
}
