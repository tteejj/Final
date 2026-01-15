using namespace System.Collections.Generic
using namespace System.Text

Set-StrictMode -Version Latest

. "$PSScriptRoot/PmcDialog.ps1"

<#
.SYNOPSIS
Profile picker dialog for selecting from multiple profiles

.DESCRIPTION
Shows a list of profiles (import/export) with keyboard navigation.
User can select a profile using arrow keys and Enter.
#>
class ProfilePickerDialog : PmcDialog {
    hidden [array]$_profiles = @()
    hidden [int]$_selectedIndex = 0

    [scriptblock]$OnProfileSelected = {}

    ProfilePickerDialog([array]$profiles, [string]$title) : base($title, "") {
        $this._profiles = $profiles
        $this._selectedIndex = 0

        # Calculate dimensions based on profile count
        $maxNameLength = 20
        foreach ($profile in $profiles) {
            $name = if ($profile.name) { $profile.name } else { "Unnamed" }
            if ($name.Length -gt $maxNameLength) {
                $maxNameLength = $name.Length
            }
        }

        $this.Width = [Math]::Max(45, $maxNameLength + 15)
        $this.Height = [Math]::Min(20, $profiles.Count + 8)
    }

    [void] RenderToEngine([object]$engine) {
        # Render base dialog (shadow, box, title)
        ([PmcDialog]$this).RenderToEngine($engine)

        $bg = $this.GetThemedColorInt('Background.Widget')
        $fg = $this.GetThemedColorInt('Foreground.Primary')
        $selectedBg = $this.GetThemedColorInt('Background.RowSelected')
        $selectedFg = $this.GetThemedColorInt('Foreground.RowSelected')
        $dimFg = $this.GetThemedColorInt('Foreground.Dim')

        # Render profile list
        $listY = $this.Y + 3
        $maxVisibleItems = $this.Height - 6

        # Calculate scroll offset if needed
        $scrollOffset = 0
        if ($this._profiles.Count -gt $maxVisibleItems) {
            if ($this._selectedIndex -ge $maxVisibleItems) {
                $scrollOffset = $this._selectedIndex - $maxVisibleItems + 1
            }
        }

        # Render visible profiles
        $visibleCount = [Math]::Min($maxVisibleItems, $this._profiles.Count)
        for ($i = 0; $i -lt $visibleCount; $i++) {
            $profileIndex = $i + $scrollOffset
            if ($profileIndex -ge $this._profiles.Count) { break }

            $profile = $this._profiles[$profileIndex]
            $name = if ($profile.name) { $profile.name } else { "Unnamed" }
            $isSelected = ($profileIndex -eq $this._selectedIndex)

            $itemBg = if ($isSelected) { $selectedBg } else { $bg }
            $itemFg = if ($isSelected) { $selectedFg } else { $fg }

            $prefix = if ($isSelected) { "> " } else { "  " }
            $text = "$prefix$name"

            # Truncate if too long
            $maxWidth = $this.Width - 4
            if ($text.Length -gt $maxWidth) {
                $text = $text.Substring(0, $maxWidth - 3) + "..."
            }

            $engine.WriteAt($this.X + 2, $listY + $i, $text, $itemFg, $itemBg)
        }

        # Footer with instructions
        $footer = "↑↓: Navigate | Enter: Select | Esc: Cancel"
        $footerX = $this.X + [Math]::Floor(($this.Width - $footer.Length) / 2)
        $footerY = $this.Y + $this.Height - 2
        $engine.WriteAt($footerX, $footerY, $footer, $dimFg, $bg)

        # Scroll indicators
        if ($this._profiles.Count -gt $maxVisibleItems) {
            if ($scrollOffset -gt 0) {
                $engine.WriteAt($this.X + $this.Width - 3, $this.Y + 3, "▲", $fg, $bg)
            }
            if ($scrollOffset + $maxVisibleItems -lt $this._profiles.Count) {
                $engine.WriteAt($this.X + $this.Width - 3, $this.Y + $this.Height - 3, "▼", $fg, $bg)
            }
        }
    }

    [bool] HandleInput([ConsoleKeyInfo]$keyInfo) {
        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($this._selectedIndex -gt 0) {
                    $this._selectedIndex--
                }
                return $true
            }
            'DownArrow' {
                if ($this._selectedIndex -lt ($this._profiles.Count - 1)) {
                    $this._selectedIndex++
                }
                return $true
            }
            'Enter' {
                $selectedProfile = $this._profiles[$this._selectedIndex]
                $this.Result = $true
                $this.IsComplete = $true
                if ($this.OnProfileSelected) {
                    & $this.OnProfileSelected $selectedProfile
                }
                return $true
            }
            'Escape' {
                $this.Result = $false
                $this.IsComplete = $true
                return $true
            }
            'Home' {
                $this._selectedIndex = 0
                return $true
            }
            'End' {
                $this._selectedIndex = $this._profiles.Count - 1
                return $true
            }
        }
        return $false
    }

    [object] GetSelectedProfile() {
        if ($this._selectedIndex -ge 0 -and $this._selectedIndex -lt $this._profiles.Count) {
            return $this._profiles[$this._selectedIndex]
        }
        return $null
    }
}
