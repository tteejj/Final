# SpeedTUI Table Component - Data grid with sorting and filtering

using namespace System.Collections.Generic

enum ColumnAlignment {
    Left
    Center
    Right
}

class TableColumn {
    [string]$Name
    [string]$Property
    [int]$Width = 0  # 0 = auto
    [ColumnAlignment]$Alignment = [ColumnAlignment]::Left
    [scriptblock]$Format = { $_ }  # Custom formatter
    [bool]$Sortable = $true
    
    TableColumn([string]$name, [string]$property) {
        $this.Name = $name
        $this.Property = $property
    }
}

class Table : Component {
    [List[TableColumn]]$Columns
    [List[object]]$Data
    [int]$SelectedIndex = -1
    [scriptblock]$OnSelectionChanged = {}
    [scriptblock]$OnItemActivated = {}
    
    # Visual properties
    [bool]$ShowBorder = $true
    [string]$BorderStyle = "Single"
    [bool]$ShowHeader = $true
    [bool]$ShowGridLines = $false
    [bool]$AlternateRowColors = $false
    [bool]$ShowRowNumbers = $false
    
    # Sorting
    [string]$SortColumn = ""
    [bool]$SortDescending = $false
    
    # Filtering
    [string]$FilterText = ""
    [bool]$ShowFilter = $false
    
    # Scrolling
    hidden [int]$_scrollOffset = 0
    hidden [int]$_horizontalScroll = 0
    hidden [int]$_visibleRows = 0
    hidden [List[object]]$_filteredData
    
    # Colors
    [string]$HeaderColor = [Colors]::Bold + [Colors]::White
    [string]$HeaderBackground = ""
    [string]$GridLineColor = [Colors]::BrightBlack
    [string]$AlternateRowColor = ""
    [string]$SelectedRowColor = [Colors]::Black
    [string]$SelectedRowBackground = [Colors]::BgWhite
    
    # Calculated column widths
    hidden [int[]]$_columnWidths
    hidden [int]$_totalWidth
    
    Table() : base() {
        $this.CanFocus = $true
        $this.Columns = [List[TableColumn]]::new()
        $this.Data = [List[object]]::new()
        $this._filteredData = [List[object]]::new()
        $this._logger.Debug("Table", "Constructor", "Table created")
    }
    
    # Add columns
    [Table] AddColumn([string]$name, [string]$property) {
        $column = [TableColumn]::new($name, $property)
        $this.Columns.Add($column)
        $this.Invalidate()
        return $this
    }
    
    [Table] AddColumn([string]$name, [string]$property, [int]$width) {
        $column = [TableColumn]::new($name, $property)
        $column.Width = $width
        $this.Columns.Add($column)
        $this.Invalidate()
        return $this
    }
    
    [Table] AddColumn([TableColumn]$column) {
        [Guard]::NotNull($column, "column")
        $this.Columns.Add($column)
        $this.Invalidate()
        return $this
    }
    
    # Set data
    [Table] SetData([object[]]$data) {
        $this.Data.Clear()
        $this.Data.AddRange($data)
        $this.ApplyDoFilter()
        $this.CalculateColumnWidths()
        $this.Invalidate()
        return $this
    }
    
    # Builder methods
    [Table] WithBorder([string]$style) {
        $this.ShowBorder = $true
        $this.BorderStyle = $style
        return $this
    }
    
    [Table] WithGridLines() {
        $this.ShowGridLines = $true
        return $this
    }
    
    [Table] WithAlternateRows() {
        $this.AlternateRowColors = $true
        return $this
    }
    
    [Table] WithRowNumbers() {
        $this.ShowRowNumbers = $true
        return $this
    }
    
    [Table] WithDoFilter() {
        $this.ShowFilter = $true
        return $this
    }
    
    [Table] WithOnSelectionChanged([scriptblock]$handler) {
        $this.OnSelectionChanged = $handler
        return $this
    }
    
    [Table] WithOnItemActivated([scriptblock]$handler) {
        $this.OnItemActivated = $handler
        return $this
    }
    
    # Filtering
    hidden [void] ApplyDoFilter() {
        $this._filteredData.Clear()
        
        if ([string]::IsNullOrWhiteSpace($this.FilterText)) {
            $this._filteredData.AddRange($this.Data)
        } else {
            foreach ($item in $this.Data) {
                $match = $false
                foreach ($column in $this.Columns) {
                    $value = $this.GetPropertyValue($item, $column.Property)
                    if ($null -ne $value -and $value.ToString().Contains($this.FilterText, [StringComparison]::OrdinalIgnoreCase)) {
                        $match = $true
                        break
                    }
                }
                if ($match) {
                    $this._filteredData.Add($item)
                }
            }
        }
        
        # Apply sorting
        if (-not [string]::IsNullOrEmpty($this.SortColumn)) {
            $this.SortData()
        }
    }
    
    # Sorting
    hidden [void] SortData() {
        $column = $this.Columns | Where-Object { $_.Property -eq $this.SortColumn } | Select-Object -First 1
        if ($null -eq $column) { return }
        
        $sorted = $this._filteredData | Sort-Object -Property $column.Property -Descending:$this.SortDescending
        $this._filteredData.Clear()
        $this._filteredData.AddRange($sorted)
    }
    
    [void] SortBy([string]$columnProperty) {
        if ($this.SortColumn -eq $columnProperty) {
            $this.SortDescending = -not $this.SortDescending
        } else {
            $this.SortColumn = $columnProperty
            $this.SortDescending = $false
        }
        
        $this.ApplyDoFilter()
        $this.Invalidate()
    }
    
    # Column width calculation
    hidden [void] CalculateColumnWidths() {
        if ($this.Columns.Count -eq 0) { return }
        
        $this._columnWidths = New-Object int[] $this.Columns.Count
        $availableWidth = $this.Width
        
        if ($this.ShowBorder) { $availableWidth -= 2 }
        if ($this.ShowRowNumbers) { $availableWidth -= 6 }  # Reserve space for row numbers
        
        # Calculate column widths
        for ($i = 0; $i -lt $this.Columns.Count; $i++) {
            $column = $this.Columns[$i]
            
            if ($column.Width -gt 0) {
                # Fixed width
                $this._columnWidths[$i] = $column.Width
            } else {
                # Auto width - based on content
                $maxWidth = $column.Name.Length
                
                foreach ($item in $this._filteredData) {
                    $value = $this.GetPropertyValue($item, $column.Property)
                    if ($null -ne $value) {
                        $formatted = & $column.Format $value
                        $maxWidth = [Math]::Max($maxWidth, $formatted.ToString().Length)
                    }
                }
                
                $this._columnWidths[$i] = [Math]::Min($maxWidth + 2, 30)  # Cap at 30 chars
            }
        }
        
        # Adjust if total width exceeds available
        $totalWidth = ($this._columnWidths | Measure-Object -Sum).Sum + ($this.Columns.Count - 1)
        if ($totalWidth -gt $availableWidth) {
            $scale = $availableWidth / $totalWidth
            for ($i = 0; $i -lt $this._columnWidths.Length; $i++) {
                $this._columnWidths[$i] = [Math]::Max(5, [int]($this._columnWidths[$i] * $scale))
            }
        }
        
        $this._totalWidth = ($this._columnWidths | Measure-Object -Sum).Sum + ($this.Columns.Count - 1)
    }
    
    # Get property value with null checks
    hidden [object] GetPropertyValue([object]$item, [string]$propertyPath) {
        if ($null -eq $item) { return $null }
        
        $parts = $propertyPath.Split('.')
        $current = $item
        
        foreach ($part in $parts) {
            if ($null -eq $current) { return $null }
            
            try {
                $current = $current.$part
            } catch {
                return $null
            }
        }
        
        return $current
    }
    
    [void] OnBoundsChanged() {
        $this.CalculateVisibleRows()
        $this.CalculateColumnWidths()
    }
    
    hidden [void] CalculateVisibleRows() {
        $contentHeight = $this.Height
        if ($this.ShowBorder) { $contentHeight -= 2 }
        if ($this.ShowHeader) { $contentHeight -= 1 }
        if ($this.ShowFilter) { $contentHeight -= 2 }
        if ($this.ShowGridLines) { $contentHeight = [int]($contentHeight / 2) }
        
        $this._visibleRows = [Math]::Max(1, $contentHeight)
    }
    
    [void] OnRender() {
        $startX = 0
        $startY = 0
        
        # Draw border
        if ($this.ShowBorder) {
            $this.DrawBox(0, 0, $this.Width, $this.Height, $this.BorderStyle)
            $startX = 1
            $startY = 1
        }
        
        $currentY = $startY
        
        # Draw filter
        if ($this.ShowFilter) {
            $this.DrawDoFilter($startX, $currentY)
            $currentY += 2
        }
        
        # Draw header
        if ($this.ShowHeader) {
            $this.DrawHeader($startX, $currentY)
            $currentY++
            
            if ($this.ShowGridLines) {
                $this.DrawHorizontalLine($startX, $currentY)
                $currentY++
            }
        }
        
        # Draw rows
        $this.DrawRows($startX, $currentY)
    }
    
    hidden [void] DrawHeader([int]$x, [int]$y) {
        $currentX = $x
        $style = $this.HeaderColor + $this.HeaderBackground
        $reset = [Colors]::Reset
        
        # Row number column
        if ($this.ShowRowNumbers) {
            $this.WriteAt($currentX, $y, "$style  #  $reset")
            $currentX += 6
        }
        
        # Column headers
        for ($i = 0; $i -lt $this.Columns.Count; $i++) {
            $column = $this.Columns[$i]
            $width = $this._columnWidths[$i]
            
            # Add sort indicator
            $header = $column.Name
            if ($column.Property -eq $this.SortColumn) {
                $header += $(if ($this.SortDescending) { " ▼" } else { " ▲" })
            }
            
            # Truncate if needed
            if ($header.Length -gt $width) {
                $header = $header.Substring(0, $width - 1)
            }
            
            # Align text
            $paddedHeader = switch ($column.Alignment) {
                Center { $header.PadLeft(($width + $header.Length) / 2).PadRight($width) }
                Right { $header.PadLeft($width) }
                default { $header.PadRight($width) }
            }
            
            $this.WriteAt($currentX, $y, "$style$paddedHeader$reset")
            $currentX += $width
            
            if ($i -lt $this.Columns.Count - 1) {
                if ($this.ShowGridLines) {
                    $this.WriteAt($currentX, $y, $this.GridLineColor + "│" + $reset)
                }
                $currentX++
            }
        }
    }
    
    hidden [void] DrawRows([int]$x, [int]$y) {
        $this.CalculateVisibleRows()
        $endIndex = [Math]::Min($this._scrollOffset + $this._visibleRows, $this._filteredData.Count)
        
        for ($i = $this._scrollOffset; $i -lt $endIndex; $i++) {
            $item = $this._filteredData[$i]
            $rowSpacing = $(if ($this.ShowGridLines) { 2 } else { 1 })
            $rowY = $y + (($i - $this._scrollOffset) * $rowSpacing)
            
            # Determine row style
            $isSelected = $i -eq $this.SelectedIndex
            $isAlternate = $this.AlternateRowColors -and ($i % 2 -eq 1)
            
            $style = ""
            $reset = [Colors]::Reset
            
            if ($isSelected -and $this.HasFocus) {
                $style = $this.SelectedRowColor + $this.SelectedRowBackground
            } elseif ($isSelected) {
                $style = [Colors]::Reverse
            } elseif ($isAlternate -and $this.AlternateRowColor) {
                $style = $this.AlternateRowColor
            }
            
            $this.DrawRow($x, $rowY, $item, $i, $style)
            
            # Draw grid line
            if ($this.ShowGridLines -and $i -lt $endIndex - 1) {
                $this.DrawHorizontalLine($x, $rowY + 1)
            }
        }
    }
    
    hidden [void] DrawRow([int]$x, [int]$y, [object]$item, [int]$rowIndex, [string]$style) {
        $currentX = $x
        $reset = [Colors]::Reset
        
        # Clear row first
        $rowWidth = $(if ($this.ShowBorder) { $this.Width - 2 } else { $this.Width })
        $this.WriteAt($x, $y, " " * $rowWidth)
        
        # Row number
        if ($this.ShowRowNumbers) {
            $rowNum = ($rowIndex + 1).ToString().PadLeft(4)
            $this.WriteAt($currentX, $y, "$style$rowNum $reset")
            $currentX += 6
        }
        
        # Column values
        for ($i = 0; $i -lt $this.Columns.Count; $i++) {
            $column = $this.Columns[$i]
            $width = $this._columnWidths[$i]
            
            # Get and format value
            $value = $this.GetPropertyValue($item, $column.Property)
            $formatted = $(if ($null -ne $value) { & $column.Format $value } else { "" })
            $text = $(if ($null -ne $formatted) { $formatted.ToString() } else { "" })
            
            # Truncate if needed
            if ($text.Length -gt $width) {
                $text = $text.Substring(0, $width - 3) + "..."
            }
            
            # Align text
            $paddedText = switch ($column.Alignment) {
                Center { $text.PadLeft(($width + $text.Length) / 2).PadRight($width) }
                Right { $text.PadLeft($width) }
                default { $text.PadRight($width) }
            }
            
            $this.WriteAt($currentX, $y, "$style$paddedText$reset")
            $currentX += $width
            
            if ($i -lt $this.Columns.Count - 1) {
                if ($this.ShowGridLines) {
                    $this.WriteAt($currentX, $y, $this.GridLineColor + "│" + $reset)
                }
                $currentX++
            }
        }
    }
    
    hidden [void] DrawHorizontalLine([int]$x, [int]$y) {
        $width = $(if ($this.ShowBorder) { $this.Width - 2 } else { $this.Width })
        $line = "─" * $width
        $this.WriteAt($x, $y, $this.GridLineColor + $line + [Colors]::Reset)
    }
    
    hidden [void] DrawDoFilter([int]$x, [int]$y) {
        $width = $(if ($this.ShowBorder) { $this.Width - 2 } else { $this.Width })
        $filterLabel = "Filter: "
        $inputWidth = $width - $filterLabel.Length - 2
        
        $this.WriteAt($x, $y, $filterLabel)
        $this.WriteAt($x + $filterLabel.Length, $y, "[" + $this.FilterText.PadRight($inputWidth) + "]")
    }
    
    [bool] HandleKeyPress([System.ConsoleKeyInfo]$keyInfo) {
        $handled = $false
        
        switch ($keyInfo.Key) {
            ([System.ConsoleKey]::UpArrow) {
                if ($this._filteredData.Count -gt 0) {
                    $newIndex = $(if ($this.SelectedIndex -le 0) { 
                        $this._filteredData.Count - 1 
                    } else { 
                        $this.SelectedIndex - 1 
                    })
                    $this.SelectIndex($newIndex)
                    $handled = $true
                }
            }
            
            ([System.ConsoleKey]::DownArrow) {
                if ($this._filteredData.Count -gt 0) {
                    $newIndex = $(if ($this.SelectedIndex -ge $this._filteredData.Count - 1) { 
                        0 
                    } else { 
                        $this.SelectedIndex + 1 
                    })
                    $this.SelectIndex($newIndex)
                    $handled = $true
                }
            }
            
            ([System.ConsoleKey]::Enter) {
                if ($this.SelectedIndex -ge 0 -and $this.OnItemActivated) {
                    & $this.OnItemActivated $this $this._filteredData[$this.SelectedIndex]
                    $handled = $true
                }
            }
            
            default {
                # Handle sorting with number keys
                if ($keyInfo.KeyChar -ge '1' -and $keyInfo.KeyChar -le '9') {
                    $columnIndex = [int]($keyInfo.KeyChar - '1')
                    if ($columnIndex -lt $this.Columns.Count) {
                        $this.SortBy($this.Columns[$columnIndex].Property)
                        $handled = $true
                    }
                }
            }
        }
        
        return $handled
    }
    
    [void] SelectIndex([int]$index) {
        if ($index -lt 0 -or $index -ge $this._filteredData.Count) { return }
        
        $this.SelectedIndex = $index
        $this.EnsureVisible($index)
        $this.Invalidate()
        
        if ($this.OnSelectionChanged) {
            & $this.OnSelectionChanged $this
        }
    }
    
    hidden [void] EnsureVisible([int]$index) {
        if ($index -lt $this._scrollOffset) {
            $this._scrollOffset = $index
        } elseif ($index -ge $this._scrollOffset + $this._visibleRows) {
            $this._scrollOffset = $index - $this._visibleRows + 1
        }
        
        $maxScroll = [Math]::Max(0, $this._filteredData.Count - $this._visibleRows)
        $this._scrollOffset = [Math]::Max(0, [Math]::Min($this._scrollOffset, $maxScroll))
    }
}

# Table builder for fluent API
class TableBuilder : ComponentBuilder {
    TableBuilder() : base([Table]::new()) { }
    
    [TableBuilder] Column([string]$name, [string]$property) {
        ([Table]$this._component).AddColumn($name, $property)
        return $this
    }
    
    [TableBuilder] Column([string]$name, [string]$property, [int]$width) {
        ([Table]$this._component).AddColumn($name, $property, $width)
        return $this
    }
    
    [TableBuilder] Data([object[]]$data) {
        ([Table]$this._component).SetData($data)
        return $this
    }
    
    [TableBuilder] Border([string]$style) {
        ([Table]$this._component).WithBorder($style)
        return $this
    }
    
    [TableBuilder] GridLines() {
        ([Table]$this._component).WithGridLines()
        return $this
    }
    
    [TableBuilder] AlternateRows() {
        ([Table]$this._component).WithAlternateRows()
        return $this
    }
    
    [TableBuilder] RowNumbers() {
        ([Table]$this._component).WithRowNumbers()
        return $this
    }
    
    [TableBuilder] Filterable() {
        ([Table]$this._component).WithDoFilter()
        return $this
    }
    
    [TableBuilder] OnSelectionChanged([scriptblock]$handler) {
        ([Table]$this._component).WithOnSelectionChanged($handler)
        return $this
    }
    
    [TableBuilder] OnItemActivated([scriptblock]$handler) {
        ([Table]$this._component).WithOnItemActivated($handler)
        return $this
    }
}