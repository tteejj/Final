# SpeedTUI List Component - Scrollable list with selection

using namespace System.Collections.Generic

class ListItem {
    [string]$Text
    [object]$Value
    [bool]$Enabled = $true
    [string]$Icon = ""
    
    ListItem([string]$text, [object]$value) {
        $this.Text = $text
        $this.Value = $value
    }
}

class List : Component {
    [List[ListItem]]$Items
    [int]$SelectedIndex = -1
    [bool]$MultiSelect = $false
    [HashSet[int]]$SelectedIndices
    [scriptblock]$OnSelectionChanged = {}
    [scriptblock]$OnItemActivated = {}  # Double-click or Enter
    
    # Visual properties
    [bool]$ShowBorder = $true
    [string]$BorderStyle = "Single"
    [bool]$ShowScrollbar = $true
    [string]$SelectionIndicator = "▸"
    [string]$MultiSelectIndicator = "[x]"
    [string]$MultiSelectEmptyIndicator = "[ ]"
    
    # Scrolling
    hidden [int]$_scrollOffset = 0
    hidden [int]$_visibleItems = 0
    
    # Colors
    [string]$ItemColor = [Colors]::White
    [string]$SelectedItemColor = [Colors]::Black
    [string]$SelectedItemBackground = [Colors]::BgWhite
    [string]$DisabledItemColor = [Colors]::BrightBlack
    
    List() : base() {
        $this.CanFocus = $true
        $this.Items = [List[ListItem]]::new()
        $this.SelectedIndices = [HashSet[int]]::new()
        $this._logger.Debug("List", "Constructor", "List created")
    }
    
    # Add items
    [List] AddItem([string]$text) {
        $item = [ListItem]::new($text, $text)
        $this.Items.Add($item)
        $this.Invalidate()
        return $this
    }
    
    [List] AddItem([string]$text, [object]$value) {
        $item = [ListItem]::new($text, $value)
        $this.Items.Add($item)
        $this.Invalidate()
        return $this
    }
    
    [List] AddItems([string[]]$texts) {
        foreach ($text in $texts) {
            $this.AddItem($text)
        }
        return $this
    }
    
    # Builder methods
    [List] WithMultiSelect() {
        $this.MultiSelect = $true
        return $this
    }
    
    [List] WithBorder([string]$style) {
        $this.ShowBorder = $true
        $this.BorderStyle = $style
        return $this
    }
    
    [List] NoBorder() {
        $this.ShowBorder = $false
        return $this
    }
    
    [List] WithSelectionIndicator([string]$indicator) {
        $this.SelectionIndicator = $indicator
        return $this
    }
    
    [List] WithOnSelectionChanged([scriptblock]$handler) {
        $this.OnSelectionChanged = $handler
        return $this
    }
    
    [List] WithOnItemActivated([scriptblock]$handler) {
        $this.OnItemActivated = $handler
        return $this
    }
    
    # Selection management
    [void] SelectIndex([int]$index) {
        if ($index -lt 0 -or $index -ge $this.Items.Count) { return }
        
        if ($this.MultiSelect) {
            if ($this.SelectedIndices.Contains($index)) {
                [void]$this.SelectedIndices.Remove($index)
            } else {
                [void]$this.SelectedIndices.Add($index)
            }
        } else {
            $this.SelectedIndex = $index
        }
        
        $this.EnsureVisible($index)
        $this.Invalidate()
        
        if ($this.OnSelectionChanged) {
            & $this.OnSelectionChanged $this
        }
    }
    
    [object] GetSelectedValue() {
        if ($this.SelectedIndex -ge 0 -and $this.SelectedIndex -lt $this.Items.Count) {
            return $this.Items[$this.SelectedIndex].Value
        }
        return $null
    }
    
    [object[]] GetSelectedValues() {
        if ($this.MultiSelect) {
            $values = @()
            foreach ($index in $this.SelectedIndices) {
                if ($index -ge 0 -and $index -lt $this.Items.Count) {
                    $values += $this.Items[$index].Value
                }
            }
            return $values
        } else {
            $value = $this.GetSelectedValue()
            return $(if ($null -ne $value) { @($value) } else { @() })
        }
    }
    
    # Scrolling
    hidden [void] EnsureVisible([int]$index) {
        if ($index -lt $this._scrollOffset) {
            $this._scrollOffset = $index
        } elseif ($index -ge $this._scrollOffset + $this._visibleItems) {
            $this._scrollOffset = $index - $this._visibleItems + 1
        }
        
        # Clamp scroll offset
        $maxScroll = [Math]::Max(0, $this.Items.Count - $this._visibleItems)
        $this._scrollOffset = [Math]::Max(0, [Math]::Min($this._scrollOffset, $maxScroll))
    }
    
    [void] OnBoundsChanged() {
        $this.CalculateVisibleItems()
    }
    
    hidden [void] CalculateVisibleItems() {
        $contentHeight = $this.Height
        if ($this.ShowBorder) {
            $contentHeight -= 2  # Top and bottom border
        }
        $this._visibleItems = [Math]::Max(1, $contentHeight)
    }
    
    [void] OnRender() {
        $startX = 0
        $startY = 0
        $contentWidth = $this.Width
        $contentHeight = $this.Height
        
        # Draw border if enabled
        if ($this.ShowBorder) {
            $this.DrawBox(0, 0, $this.Width, $this.Height, $this.BorderStyle)
            $startX = 1
            $startY = 1
            $contentWidth -= 2
            $contentHeight -= 2
        }
        
        # Calculate visible range
        $this.CalculateVisibleItems()
        $endIndex = [Math]::Min($this._scrollOffset + $this._visibleItems, $this.Items.Count)
        
        # Render visible items
        for ($i = $this._scrollOffset; $i -lt $endIndex; $i++) {
            $item = $this.Items[$i]
            $y = $startY + ($i - $this._scrollOffset)
            
            # Build item text
            $text = ""
            $isSelected = $(if ($this.MultiSelect) { 
                $this.SelectedIndices.Contains($i) 
            } else { 
                $i -eq $this.SelectedIndex 
            })
            
            # Add selection indicator
            if ($this.MultiSelect) {
                $text = $(if ($isSelected) { $this.MultiSelectIndicator } else { $this.MultiSelectEmptyIndicator })
                $text += " "
            } elseif ($isSelected) {
                $text = $this.SelectionIndicator + " "
            } else {
                $text = "  "
            }
            
            # Add icon if present
            if (-not [string]::IsNullOrEmpty($item.Icon)) {
                $text += $item.Icon + " "
            }
            
            # Add item text
            $text += $item.Text
            
            # Truncate if too long
            $maxLength = $contentWidth
            if ($this.ShowScrollbar -and $this.Items.Count -gt $this._visibleItems) {
                $maxLength -= 1  # Reserve space for scrollbar
            }
            
            if ($text.Length -gt $maxLength) {
                $text = $text.Substring(0, $maxLength - 3) + "..."
            }
            
            # Apply colors
            $style = ""
            $reset = [Colors]::Reset
            
            if (-not $item.Enabled) {
                $style = $this.DisabledItemColor
            } elseif ($isSelected -and $this.HasFocus) {
                $style = $this.SelectedItemColor + $this.SelectedItemBackground
            } elseif ($isSelected) {
                $style = [Colors]::Reverse
            } else {
                $style = $this.ItemColor
            }
            
            # Clear line first (for proper background color)
            $clearLine = " " * $maxLength
            $this.WriteAt($startX, $y, $clearLine)
            
            # Write item
            $this.WriteAt($startX, $y, "$style$text$reset")
        }
        
        # Draw scrollbar if needed
        if ($this.ShowScrollbar -and $this.Items.Count -gt $this._visibleItems) {
            $this.DrawScrollbar($startX + $contentWidth - 1, $startY, $contentHeight)
        }
    }
    
    hidden [void] DrawScrollbar([int]$x, [int]$y, [int]$height) {
        # Calculate scrollbar position and size
        $scrollbarHeight = [Math]::Max(1, [int]($height * $this._visibleItems / $this.Items.Count))
        $scrollbarPosition = [int]($height * $this._scrollOffset / $this.Items.Count)
        
        # Draw scrollbar track
        for ($i = 0; $i -lt $height; $i++) {
            if ($i -ge $scrollbarPosition -and $i -lt $scrollbarPosition + $scrollbarHeight) {
                $this.WriteAt($x, $y + $i, "█")
            } else {
                $this.WriteAt($x, $y + $i, "│")
            }
        }
    }
    
    [bool] HandleKeyPress([System.ConsoleKeyInfo]$keyInfo) {
        $handled = $false
        
        switch ($keyInfo.Key) {
            ([System.ConsoleKey]::UpArrow) {
                if ($this.Items.Count -gt 0) {
                    $newIndex = $(if ($this.SelectedIndex -le 0) { 
                        $this.Items.Count - 1 
                    } else { 
                        $this.SelectedIndex - 1 
                    })
                    $this.SelectIndex($newIndex)
                    $handled = $true
                }
            }
            
            ([System.ConsoleKey]::DownArrow) {
                if ($this.Items.Count -gt 0) {
                    $newIndex = $(if ($this.SelectedIndex -ge $this.Items.Count - 1) { 
                        0 
                    } else { 
                        $this.SelectedIndex + 1 
                    })
                    $this.SelectIndex($newIndex)
                    $handled = $true
                }
            }
            
            ([System.ConsoleKey]::Home) {
                if ($this.Items.Count -gt 0) {
                    $this.SelectIndex(0)
                    $handled = $true
                }
            }
            
            ([System.ConsoleKey]::End) {
                if ($this.Items.Count -gt 0) {
                    $this.SelectIndex($this.Items.Count - 1)
                    $handled = $true
                }
            }
            
            ([System.ConsoleKey]::PageUp) {
                if ($this.Items.Count -gt 0) {
                    $newIndex = [Math]::Max(0, $this.SelectedIndex - $this._visibleItems)
                    $this.SelectIndex($newIndex)
                    $handled = $true
                }
            }
            
            ([System.ConsoleKey]::PageDown) {
                if ($this.Items.Count -gt 0) {
                    $newIndex = [Math]::Min($this.Items.Count - 1, $this.SelectedIndex + $this._visibleItems)
                    $this.SelectIndex($newIndex)
                    $handled = $true
                }
            }
            
            ([System.ConsoleKey]::Spacebar) {
                if ($this.MultiSelect -and $this.SelectedIndex -ge 0) {
                    $this.SelectIndex($this.SelectedIndex)
                    $handled = $true
                }
            }
            
            ([System.ConsoleKey]::Enter) {
                if ($this.SelectedIndex -ge 0 -and $this.OnItemActivated) {
                    & $this.OnItemActivated $this $this.Items[$this.SelectedIndex]
                    $handled = $true
                }
            }
        }
        
        return $handled
    }
}

# List builder for fluent API
class ListBuilder : ComponentBuilder {
    ListBuilder() : base([List]::new()) { }
    
    [ListBuilder] Items([string[]]$items) {
        foreach ($item in $items) {
            ([List]$this._component).AddItem($item)
        }
        return $this
    }
    
    [ListBuilder] MultiSelect() {
        ([List]$this._component).MultiSelect = $true
        return $this
    }
    
    [ListBuilder] Border([string]$style) {
        ([List]$this._component).ShowBorder = $true
        ([List]$this._component).BorderStyle = $style
        return $this
    }
    
    [ListBuilder] NoBorder() {
        ([List]$this._component).ShowBorder = $false
        return $this
    }
    
    [ListBuilder] OnSelectionChanged([scriptblock]$handler) {
        ([List]$this._component).OnSelectionChanged = $handler
        return $this
    }
    
    [ListBuilder] OnItemActivated([scriptblock]$handler) {
        ([List]$this._component).OnItemActivated = $handler
        return $this
    }
}