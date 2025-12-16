using namespace System.Collections.Generic
using namespace System.Text

# PmcMenuBar - Top-level navigation menu with dropdown support
# Full keyboard navigation, hotkeys, and dropdown menus

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Menu item within a dropdown menu

.DESCRIPTION
Represents a single item in a dropdown menu with:
- Display label
- Hotkey character
- Action scriptblock
- Enabled/disabled state
- Separator flag
#>
class PmcMenuItem {
    [string]$Label = ""
    [char]$Hotkey = [char]0
    [scriptblock]$Action = $null
    [bool]$Enabled = $true
    [bool]$IsSeparator = $false
    [string]$Description = ""  # Optional hint text

    PmcMenuItem([string]$label, [char]$hotkey, [scriptblock]$action) {
        $this.Label = $label
        $this.Hotkey = $hotkey
        $this.Action = $action
    }

    # Constructor for separator
    static [PmcMenuItem] Separator() {
        $item = [PmcMenuItem]::new("", [char]0, $null)
        $item.IsSeparator = $true
        return $item
    }
}

<#
.SYNOPSIS
Top-level menu containing dropdown items

.DESCRIPTION
Represents a menu in the menu bar (e.g., "File", "Edit", "View")
#>
class PmcMenu {
    [string]$Title = ""
    [char]$Hotkey = [char]0
    [List[PmcMenuItem]]$Items

    PmcMenu([string]$title, [char]$hotkey) {
        $this.Title = $title
        $this.Hotkey = $hotkey
        $this.Items = [List[PmcMenuItem]]::new()
    }

    [PmcMenu] AddItem([string]$label, [char]$hotkey, [scriptblock]$action) {
        $this.Items.Add([PmcMenuItem]::new($label, $hotkey, $action))
        return $this
    }

    [PmcMenu] AddSeparator() {
        $this.Items.Add([PmcMenuItem]::Separator())
        return $this
    }
}

<#
.SYNOPSIS
Menu bar widget with dropdown menus

.DESCRIPTION
PmcMenuBar provides:
- Top-level horizontal menu bar
- Dropdown menus on activation
- Full keyboard navigation (arrows, hotkeys)
- Themed rendering
- Event callbacks

.EXAMPLE
$menuBar = [PmcMenuBar]::new()
$menuBar.AddMenu('File', 'F', @(
    [PmcMenuItem]::new('New', 'N', { Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcMenuBar] New!" })
    [PmcMenuItem]::new('Open', 'O', { Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [PmcMenuBar] Open!" })
    [PmcMenuItem]::Separator()
    [PmcMenuItem]::new('Exit', 'X', { exit })
))
#>
class PmcMenuBar : PmcWidget {
    # === Properties ===
    [List[PmcMenu]]$Menus
    [int]$SelectedMenuIndex = -1        # Which menu is selected (hover)
    [int]$SelectedItemIndex = -1        # Which item in dropdown is selected
    [bool]$IsActive = $false            # Menu bar has focus
    [bool]$DropdownVisible = $false     # Dropdown is showing

    # === Events ===
    [scriptblock]$OnMenuItemSelected = $null

    # === Cached Render Data ===
    hidden [List[int]]$_menuXPositions = [List[int]]::new()  # X position of each menu
    
    # === Constructor ===
    PmcMenuBar() : base("MenuBar") {
        $this.Menus = [List[PmcMenu]]::new()
        $this.CanFocus = $true

        # Default size (will be set by layout manager)
        $this.Width = 80
        $this.Height = 1
    }

    # === Menu Management ===

    <#
    .SYNOPSIS
    Add a menu to the menu bar
    #>
    [PmcMenuBar] AddMenu([string]$title, [char]$hotkey, [array]$items) {
        $menu = [PmcMenu]::new($title, $hotkey)
        foreach ($item in $items) {
            $menu.Items.Add($item)
        }
        $this.Menus.Add($menu)
        return $this
    }

    # === Navigation ===

    <#
    .SYNOPSIS
    Activate the menu bar (show first menu or highlight bar)
    #>
    [void] Activate() {
        $this.IsActive = $true
        if ($this.Menus.Count -gt 0) {
            $this.SelectedMenuIndex = 0
        }
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Deactivate the menu bar
    #>
    [void] Deactivate() {
        $this.IsActive = $false
        $this.DropdownVisible = $false
        $this.SelectedMenuIndex = -1
        $this.SelectedItemIndex = -1
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Show dropdown for currently selected menu
    #>
    [void] ShowDropdown() {
        if ($this.SelectedMenuIndex -ge 0 -and $this.SelectedMenuIndex -lt $this.Menus.Count) {
            $menu = $this.Menus[$this.SelectedMenuIndex]

            # Don't show dropdown if menu has no items
            if ($null -eq $menu.Items -or $menu.Items.Count -eq 0) {
                return
            }

            $this.DropdownVisible = $true
            $this.SelectedItemIndex = 0
            # Skip separators
            $this._SelectNextEnabledItem()
            $this.Invalidate()
        }
    }

    <#
    .SYNOPSIS
    Hide dropdown
    #>
    [void] HideDropdown() {
        $this.DropdownVisible = $false
        $this.SelectedItemIndex = -1
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Move selection to next menu
    #>
    [void] SelectNextMenu() {
        if ($this.Menus.Count -eq 0) { return }
        $this.SelectedMenuIndex = ($this.SelectedMenuIndex + 1) % $this.Menus.Count
        $this.SelectedItemIndex = -1
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Move selection to previous menu
    #>
    [void] SelectPreviousMenu() {
        if ($this.Menus.Count -eq 0) { return }
        $this.SelectedMenuIndex--
        if ($this.SelectedMenuIndex -lt 0) {
            $this.SelectedMenuIndex = $this.Menus.Count - 1
        }
        $this.SelectedItemIndex = -1
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Move selection to next item in dropdown
    #>
    [void] SelectNextItem() {
        if (-not $this.DropdownVisible -or $this.SelectedMenuIndex -lt 0) { return }
        $menu = $this.Menus[$this.SelectedMenuIndex]
        if ($menu.Items.Count -eq 0) { return }

        $this.SelectedItemIndex = ($this.SelectedItemIndex + 1) % $menu.Items.Count
        $this._SelectNextEnabledItem()
        $this.Invalidate()
    }

    <#
    .SYNOPSIS
    Move selection to previous item in dropdown
    #>
    [void] SelectPreviousItem() {
        if (-not $this.DropdownVisible -or $this.SelectedMenuIndex -lt 0) { return }
        $menu = $this.Menus[$this.SelectedMenuIndex]
        if ($menu.Items.Count -eq 0) { return }

        $this.SelectedItemIndex--
        if ($this.SelectedItemIndex -lt 0) {
            $this.SelectedItemIndex = $menu.Items.Count - 1
        }
        $this._SelectPreviousEnabledItem()
        $this.Invalidate()
    }

    # Skip separators and disabled items
    hidden [void] _SelectNextEnabledItem() {
        if ($this.SelectedMenuIndex -lt 0) { return }
        $menu = $this.Menus[$this.SelectedMenuIndex]
        $attempts = 0
        while ($attempts -lt $menu.Items.Count) {
            $item = $menu.Items[$this.SelectedItemIndex]
            if (-not $item.IsSeparator -and $item.Enabled) { break }
            $this.SelectedItemIndex = ($this.SelectedItemIndex + 1) % $menu.Items.Count
            $attempts++
        }
    }

    hidden [void] _SelectPreviousEnabledItem() {
        if ($this.SelectedMenuIndex -lt 0) { return }
        $menu = $this.Menus[$this.SelectedMenuIndex]
        $attempts = 0
        while ($attempts -lt $menu.Items.Count) {
            $item = $menu.Items[$this.SelectedItemIndex]
            if (-not $item.IsSeparator -and $item.Enabled) { break }
            $this.SelectedItemIndex--
            if ($this.SelectedItemIndex -lt 0) {
                $this.SelectedItemIndex = $menu.Items.Count - 1
            }
            $attempts++
        }
    }

    <#
    .SYNOPSIS
    Execute currently selected menu item
    #>
    [bool] ExecuteSelectedItem() {
        if (-not $this.DropdownVisible -or $this.SelectedMenuIndex -lt 0 -or $this.SelectedItemIndex -lt 0) {
            return $false
        }

        $menu = $this.Menus[$this.SelectedMenuIndex]
        if ($this.SelectedItemIndex -ge $menu.Items.Count) {
            return $false
        }

        $item = $menu.Items[$this.SelectedItemIndex]
        if ($item.IsSeparator -or -not $item.Enabled) {
            return $false
        }

        # Close dropdown BEFORE executing action
        $this.HideDropdown()
        $this.Deactivate()

        # Execute action
        if ($item.Action) {
            try {
                & $item.Action
            } catch {
                # Log error
            }
        }

        # Fire event
        if ($this.OnMenuItemSelected) {
            & $this.OnMenuItemSelected $this $menu $item
        }

        return $true
    }

    # === Layout System ===

    [void] RegisterLayout([object]$engine) {
        ([PmcWidget]$this).RegisterLayout($engine)
        $engine.DefineRegion("$($this.RegionID)_Main", $this.X, $this.Y, $this.Width, $this.Height)
    }

    # === Rendering ===

    [string] OnRender() {
        # Legacy support if needed, but we prefer RenderToEngine
        return "" 
    }

    <#
    .SYNOPSIS
    Render directly to engine (new high-performance path)
    #>
    [void] RenderToEngine([object]$engine) {
        $this.RegisterLayout($engine)

        # Colors (Ints)
        $bg = $this.GetThemedBgInt('Background.MenuBar', 1, 0)
        $fg = $this.GetThemedInt('Foreground.Row')
        $highlightBg = $this.GetThemedBgInt('Background.RowSelected', 1, 0)
        $highlightFg = $this.GetThemedInt('Foreground.RowSelected')
        
        if ($bg -eq -1) { $bg = [HybridRenderEngine]::_PackRGB(30, 30, 30) }

        # 1. Draw Main Bar Background
        $engine.Fill($this.X, $this.Y, $this.Width, 1, ' ', $fg, $bg)
        
        # 2. Draw Menu Titles
        $currentX = $this.X + 1
        $this._menuXPositions.Clear()
        
        for ($i = 0; $i -lt $this.Menus.Count; $i++) {
            $menu = $this.Menus[$i]
            $this._menuXPositions.Add($currentX - $this.X)
            
            $text = " $($menu.Title)"
            if ($menu.Hotkey -ne 0) { $text += "($($menu.Hotkey))" }
            $text += " "
            
            $itemBg = $bg
            $itemFg = $fg
            if ($i -eq $this.SelectedMenuIndex -and $this.IsActive) {
                $itemBg = $highlightBg
                $itemFg = $highlightFg
            }
            
            $engine.WriteAt($currentX, $this.Y, $text, $itemFg, $itemBg)
            $currentX += $text.Length
        }

        # 3. Draw Dropdown (if visible)
        if ($this.DropdownVisible -and $this.SelectedMenuIndex -ge 0) {
             $this._RenderDropdownToEngine($engine)
        }
    }

    hidden [void] _RenderDropdownToEngine([object]$engine) {
        if ($this.SelectedMenuIndex -lt 0 -or $this.SelectedMenuIndex -ge $this.Menus.Count) { return }
        $menu = $this.Menus[$this.SelectedMenuIndex]
        if ($menu.Items.Count -eq 0) { return }

        # Calculate width
        $maxWidth = 10
        foreach ($item in $menu.Items) {
            if (-not $item.IsSeparator) {
                $itemWidth = $item.Label.Length + 5
                if ($item.Hotkey -eq 0) { $itemWidth = $item.Label.Length + 1 }
                if ($itemWidth -gt $maxWidth) { $maxWidth = $itemWidth }
            }
        }
        $width = $maxWidth + 2
        $height = $menu.Items.Count + 2 # Borders
        
        $x = $this.X + $this._menuXPositions[$this.SelectedMenuIndex]
        $y = $this.Y + 1
        
        # Define Popup Region
        $regionId = "$($this.RegionID)_Dropdown"
        $engine.DefineRegion($regionId, $x, $y, $width, $height, 100) # Z=100
        
        # Colors
        $bg = $this.GetThemedBgInt('Background.MenuBar', 1, 0)
        $fg = $this.GetThemedInt('Foreground.Row')
        $borderFg = $this.GetThemedInt('Border.Widget')
        $highlightBg = $this.GetThemedBgInt('Background.RowSelected', 1, 0)
        $highlightFg = $this.GetThemedInt('Foreground.RowSelected')
        $mutedFg = $this.GetThemedInt('Foreground.Muted')
        
        if ($bg -eq -1) { $bg = [HybridRenderEngine]::_PackRGB(30, 30, 30) }

        # Draw Box in Region
        # We can use Fill/WriteToRegion
        $engine.Fill($x, $y, $width, $height, ' ', $fg, $bg)
        
        # Borders
        $engine.WriteToRegion($regionId, $this.BuildBoxBorder($width, 'top', 'single'), $borderFg, $bg)
        
        # Items
        for ($i = 0; $i -lt $menu.Items.Count; $i++) {
            $item = $menu.Items[$i]
            $itemY = $y + 1 + $i
            
            # Left/Right Border
            $engine.WriteAt($x, $itemY, $this.GetBoxChar('single_vertical'), $borderFg, $bg)
            $engine.WriteAt($x + $width - 1, $itemY, $this.GetBoxChar('single_vertical'), $borderFg, $bg)
            
            if ($item.IsSeparator) {
                # Separator
                $sep = $this.GetBoxChar('single_vertical') + ($this.GetBoxChar('single_horizontal') * ($width - 2)) + $this.GetBoxChar('single_vertical')
                $engine.WriteAt($x, $itemY, $sep, $borderFg, $bg)
            } else {
                $isSelected = ($i -eq $this.SelectedItemIndex)
                $iBg = $(if ($isSelected) { $highlightBg } else { $bg })
                $iFg = $(if ($isSelected) { $highlightFg } else { $fg })
                if (-not $item.Enabled) { $iFg = $mutedFg }
                
                $text = " $($item.Label)"
                if ($item.Hotkey -ne 0) { $text += " ($($item.Hotkey))" }
                
                # Pad
                $padLen = $width - 2 - $text.Length
                if ($padLen -gt 0) { $text += (" " * $padLen) }
                
                $engine.WriteAt($x + 1, $itemY, $text, $iFg, $iBg)
            }
        }
        
        # Bottom Border
        $engine.WriteAt($x, $y + $height - 1, $this.BuildBoxBorder($width, 'bottom', 'single'), $borderFg, $bg)
    }

    # === Input Handling ===

    [bool] HandleKeyPress([System.ConsoleKeyInfo]$keyInfo) {
        $key = $keyInfo.Key
        $char = $keyInfo.KeyChar


        # }

        # Handle Alt+hotkey even when not active (to activate menu)
        if ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt) {
            # }
            if ($this._HandleMenuHotkey($char)) {
                # Menu hotkey handler already set SelectedMenuIndex and showed dropdown
                # Just ensure IsActive is set (don't call Activate() which resets index to 0)
                $this.IsActive = $true
                # }
                return $true
            }
            # }
        }

        # Normal menu operations require IsActive
        if (-not $this.IsActive) {
            return $false
        }

        # Dropdown navigation
        if ($this.DropdownVisible) {
            switch ($key) {
                'UpArrow' {
                    $this.SelectPreviousItem()
                    return $true
                }
                'DownArrow' {
                    $this.SelectNextItem()
                    return $true
                }
                'LeftArrow' {
                    $this.HideDropdown()
                    $this.SelectPreviousMenu()
                    $this.ShowDropdown()
                    return $true
                }
                'RightArrow' {
                    $this.HideDropdown()
                    $this.SelectNextMenu()
                    $this.ShowDropdown()
                    return $true
                }
                'Enter' {
                    $this.ExecuteSelectedItem()
                    # Always return true - we handled the key (even if no action executed)
                    return $true
                }
                'Escape' {
                    # }
                    $this.HideDropdown()
                    $this.Deactivate()
                    return $true
                }
                default {
                    # Check hotkeys
                    if ($this._HandleItemHotkey($char)) {
                        return $true
                    }
                }
            }
        } else {
            # Menu bar navigation
            switch ($key) {
                'LeftArrow' {
                    $this.SelectPreviousMenu()
                    return $true
                }
                'RightArrow' {
                    $this.SelectNextMenu()
                    return $true
                }
                'DownArrow' {
                    $this.ShowDropdown()
                    return $true
                }
                'Enter' {
                    $this.ShowDropdown()
                    return $true
                }
                'Escape' {
                    # }
                    $this.Deactivate()
                    return $true
                }
                default {
                    # Check menu hotkeys
                    if ($this._HandleMenuHotkey($char)) {
                        return $true
                    }
                }
            }
        }

        return $false
    }

    hidden [bool] _HandleMenuHotkey([char]$char) {
        if ($char -eq [char]0) { return $false }
        $charUpper = [char]::ToUpper($char)

        for ($i = 0; $i -lt $this.Menus.Count; $i++) {
            $menu = $this.Menus[$i]
            if ([char]::ToUpper($menu.Hotkey) -eq $charUpper) {
                $this.SelectedMenuIndex = $i
                $this.ShowDropdown()
                return $true
            }
        }
        return $false
    }

    hidden [bool] _HandleItemHotkey([char]$char) {
        if ($char -eq [char]0 -or $this.SelectedMenuIndex -lt 0) { return $false }
        $charUpper = [char]::ToUpper($char)

        $menu = $this.Menus[$this.SelectedMenuIndex]
        for ($i = 0; $i -lt $menu.Items.Count; $i++) {
            $item = $menu.Items[$i]
            if (-not $item.IsSeparator -and $item.Enabled -and [char]::ToUpper($item.Hotkey) -eq $charUpper) {
                $this.SelectedItemIndex = $i
                return $this.ExecuteSelectedItem()
            }
        }
        return $false
    }
}

# Classes exported automatically in PowerShell 5.1+
