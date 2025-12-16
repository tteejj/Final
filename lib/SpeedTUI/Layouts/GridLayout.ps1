# SpeedTUI Grid Layout - CSS Grid-inspired layout system

using namespace System.Collections.Generic

enum GridUnit {
    Auto      # Size to content
    Pixel     # Fixed pixel size
    Fraction  # Fractional unit (like CSS fr)
    Percent   # Percentage of parent
}

class GridSize {
    [GridUnit]$Unit
    [double]$Value
    
    GridSize([GridUnit]$unit, [double]$value) {
        $this.Unit = $unit
        $this.Value = $value
    }
    
    static [GridSize] Auto() {
        return [GridSize]::new([GridUnit]::Auto, 0)
    }
    
    static [GridSize] Pixels([int]$pixels) {
        [Guard]::NonNegative($pixels, "pixels")
        return [GridSize]::new([GridUnit]::Pixel, $pixels)
    }
    
    static [GridSize] Fraction([double]$fraction) {
        [Guard]::Positive($fraction, "fraction")
        return [GridSize]::new([GridUnit]::Fraction, $fraction)
    }
    
    static [GridSize] Percent([double]$percent) {
        [Guard]::InRange($percent, 0, 100, "percent")
        return [GridSize]::new([GridUnit]::Percent, $percent)
    }
    
    [string] ToString() {
        switch ($this.Unit) {
            Auto { return "auto" }
            Pixel { return "$($this.Value)px" }
            Fraction { return "$($this.Value)fr" }
            Percent { return "$($this.Value)%" }
        }
        return "unknown"
    }
}

class GridCell {
    [Component]$Component
    [int]$Row
    [int]$Column
    [int]$RowSpan = 1
    [int]$ColumnSpan = 1
    [string]$Align = "stretch"      # start, center, end, stretch
    [string]$VerticalAlign = "stretch"  # start, center, end, stretch
    
    GridCell([Component]$component, [int]$row, [int]$column) {
        [Guard]::NotNull($component, "component")
        [Guard]::NonNegative($row, "row")
        [Guard]::NonNegative($column, "column")
        
        $this.Component = $component
        $this.Row = $row
        $this.Column = $column
    }
}

class GridLayout : Component {
    [List[GridSize]]$RowDefinitions
    [List[GridSize]]$ColumnDefinitions
    [List[GridCell]]$Cells
    [int]$RowGap = 0
    [int]$ColumnGap = 0
    
    # Calculated sizes
    hidden [int[]]$_rowHeights
    hidden [int[]]$_columnWidths
    hidden [int[]]$_rowPositions
    hidden [int[]]$_columnPositions
    
    GridLayout() : base() {
        $this.RowDefinitions = [List[GridSize]]::new()
        $this.ColumnDefinitions = [List[GridSize]]::new()
        $this.Cells = [List[GridCell]]::new()
        
        $this._logger.Debug("GridLayout", "Constructor", "GridLayout created")
    }
    
    # Builder methods
    [GridLayout] Rows([GridSize[]]$rows) {
        [Guard]::NotNullOrEmptyArray($rows, "rows")
        $this.RowDefinitions.Clear()
        $this.RowDefinitions.AddRange($rows)
        return $this
    }
    
    [GridLayout] Columns([GridSize[]]$columns) {
        [Guard]::NotNullOrEmptyArray($columns, "columns")
        $this.ColumnDefinitions.Clear()
        $this.ColumnDefinitions.AddRange($columns)
        return $this
    }
    
    [GridLayout] Gap([int]$gap) {
        [Guard]::NonNegative($gap, "gap")
        $this.RowGap = $gap
        $this.ColumnGap = $gap
        return $this
    }
    
    [GridLayout] RowGap([int]$gap) {
        [Guard]::NonNegative($gap, "gap")
        $this.RowGap = $gap
        return $this
    }
    
    [GridLayout] ColumnGap([int]$gap) {
        [Guard]::NonNegative($gap, "gap")
        $this.ColumnGap = $gap
        return $this
    }
    
    # Add component to grid
    [GridCell] Add([Component]$component, [int]$row, [int]$column) {
        [Guard]::NotNull($component, "component")
        
        $cell = [GridCell]::new($component, $row, $column)
        $this.Cells.Add($cell)
        $this.AddChild($component)
        
        $this._logger.Debug("GridLayout", "Add", "Component added to grid", @{
            ComponentId = $component.Id
            Row = $row
            Column = $column
        })
        
        return $cell
    }
    
    [GridCell] Add([Component]$component, [int]$row, [int]$column, [int]$rowSpan, [int]$columnSpan) {
        $cell = $this.Add($component, $row, $column)
        $cell.RowSpan = $rowSpan
        $cell.ColumnSpan = $columnSpan
        return $cell
    }
    
    # Calculate layout
    [void] OnBoundsChanged() {
        $this.CalculateGrid()
        $this.LayoutChildren()
    }
    
    hidden [void] CalculateGrid() {
        if ($this.RowDefinitions.Count -eq 0 -or $this.ColumnDefinitions.Count -eq 0) {
            return
        }
        
        $timer = $this._logger.MeasurePerformance("GridLayout", "CalculateGrid")
        
        try {
            # Calculate available space
            $availableHeight = $this.Height - ($this.RowGap * ([Math]::Max(0, $this.RowDefinitions.Count - 1)))
            $availableWidth = $this.Width - ($this.ColumnGap * ([Math]::Max(0, $this.ColumnDefinitions.Count - 1)))
            
            # Calculate row heights
            $this._rowHeights = $this.CalculateSizes($this.RowDefinitions, $availableHeight, $true)
            
            # Calculate column widths
            $this._columnWidths = $this.CalculateSizes($this.ColumnDefinitions, $availableWidth, $false)
            
            # Calculate positions
            $this._rowPositions = $this.CalculatePositions($this._rowHeights, $this.RowGap)
            $this._columnPositions = $this.CalculatePositions($this._columnWidths, $this.ColumnGap)
            
            $this._logger.Trace("GridLayout", "CalculateGrid", "Grid calculated", @{
                Rows = $this._rowHeights -join ","
                Columns = $this._columnWidths -join ","
            })
            
        } finally {
            $timer.Dispose()
        }
    }
    
    hidden [int[]] CalculateSizes([List[GridSize]]$definitions, [int]$availableSpace, [bool]$isRow) {
        $sizes = New-Object int[] $definitions.Count
        $totalFixed = 0
        $totalFractions = 0.0
        
        # First pass: Calculate fixed sizes and count fractions
        for ($i = 0; $i -lt $definitions.Count; $i++) {
            $def = $definitions[$i]
            
            switch ($def.Unit) {
                Pixel {
                    $sizes[$i] = [int]$def.Value
                    $totalFixed += $sizes[$i]
                }
                Percent {
                    $sizes[$i] = [int]($availableSpace * $def.Value / 100)
                    $totalFixed += $sizes[$i]
                }
                Auto {
                    # Calculate based on content
                    $sizes[$i] = $this.CalculateAutoSize($i, $isRow)
                    $totalFixed += $sizes[$i]
                }
                Fraction {
                    $totalFractions += $def.Value
                }
            }
        }
        
        # Second pass: Distribute remaining space to fractional units
        if ($totalFractions -gt 0) {
            $remainingSpace = [Math]::Max(0, $availableSpace - $totalFixed)
            $fractionSize = $remainingSpace / $totalFractions
            
            for ($i = 0; $i -lt $definitions.Count; $i++) {
                if ($definitions[$i].Unit -eq [GridUnit]::Fraction) {
                    $sizes[$i] = [int]($fractionSize * $definitions[$i].Value)
                }
            }
        }
        
        return $sizes
    }
    
    hidden [int] CalculateAutoSize([int]$index, [bool]$isRow) {
        $maxSize = 0
        
        foreach ($cell in $this.Cells) {
            if ($isRow) {
                if ($cell.Row -eq $index) {
                    # Get preferred height of component
                    $maxSize = [Math]::Max($maxSize, 3)  # Default min height
                }
            } else {
                if ($cell.Column -eq $index) {
                    # Get preferred width of component
                    $maxSize = [Math]::Max($maxSize, 10)  # Default min width
                }
            }
        }
        
        return $maxSize
    }
    
    hidden [int[]] CalculatePositions([int[]]$sizes, [int]$gap) {
        $positions = New-Object int[] $sizes.Length
        $currentPos = 0
        
        for ($i = 0; $i -lt $sizes.Length; $i++) {
            $positions[$i] = $currentPos
            $currentPos += $sizes[$i] + $gap
        }
        
        return $positions
    }
    
    hidden [void] LayoutChildren() {
        foreach ($cell in $this.Cells) {
            if ($cell.Row -ge $this._rowPositions.Length -or 
                $cell.Column -ge $this._columnPositions.Length) {
                continue
            }
            
            # Calculate cell bounds
            $x = $this.X + $this._columnPositions[$cell.Column]
            $y = $this.Y + $this._rowPositions[$cell.Row]
            
            # Calculate width spanning columns
            $width = 0
            for ($c = 0; $c -lt $cell.ColumnSpan -and ($cell.Column + $c) -lt $this._columnWidths.Length; $c++) {
                $width += $this._columnWidths[$cell.Column + $c]
                if ($c -gt 0) { $width += $this.ColumnGap }
            }
            
            # Calculate height spanning rows
            $height = 0
            for ($r = 0; $r -lt $cell.RowSpan -and ($cell.Row + $r) -lt $this._rowHeights.Length; $r++) {
                $height += $this._rowHeights[$cell.Row + $r]
                if ($r -gt 0) { $height += $this.RowGap }
            }
            
            # Apply alignment
            $componentX = $x
            $componentY = $y
            $componentWidth = $width
            $componentHeight = $height
            
            # Horizontal alignment
            switch ($cell.Align) {
                "start" {
                    # Default position
                }
                "center" {
                    $componentX = $x + ($width - $cell.Component.Width) / 2
                }
                "end" {
                    $componentX = $x + $width - $cell.Component.Width
                }
                "stretch" {
                    # Use full width
                }
            }
            
            # Vertical alignment
            switch ($cell.VerticalAlign) {
                "start" {
                    # Default position
                }
                "center" {
                    $componentY = $y + ($height - $cell.Component.Height) / 2
                }
                "end" {
                    $componentY = $y + $height - $cell.Component.Height
                }
                "stretch" {
                    # Use full height
                }
            }
            
            # Set component bounds
            $cell.Component.SetBounds([int]$componentX, [int]$componentY, [int]$componentWidth, [int]$componentHeight)
        }
    }
    
    [void] OnRender() {
        # Grid doesn't render anything itself, just its children
        # Could add grid lines here if needed for debugging
    }
}

# Grid builder for fluent API
class GridBuilder {
    hidden [GridLayout]$_grid
    
    GridBuilder() {
        $this._grid = [GridLayout]::new()
    }
    
    [GridBuilder] Rows([string[]]$rowDefinitions) {
        $rows = foreach ($def in $rowDefinitions) {
            $this.ParseSize($def)
        }
        $this._grid.Rows($rows)
        return $this
    }
    
    [GridBuilder] Columns([string[]]$columnDefinitions) {
        $columns = foreach ($def in $columnDefinitions) {
            $this.ParseSize($def)
        }
        $this._grid.Columns($columns)
        return $this
    }
    
    hidden [GridSize] ParseSize([string]$definition) {
        if ($definition -eq "auto") {
            return [GridSize]::Auto()
        }
        elseif ($definition -match "^(\d+)px$") {
            return [GridSize]::Pixels([int]$matches[1])
        }
        elseif ($definition -match "^(\d+(?:\.\d+)?)fr$") {
            return [GridSize]::Fraction([double]$matches[1])
        }
        elseif ($definition -match "^(\d+(?:\.\d+)?)%$") {
            return [GridSize]::Percent([double]$matches[1])
        }
        else {
            throw [ArgumentException]::new("Invalid size definition: $definition")
        }
    }
    
    [GridBuilder] Gap([int]$gap) {
        $this._grid.Gap($gap)
        return $this
    }
    
    [GridBuilder] Add([Component]$component, [int]$row, [int]$column) {
        $this._grid.Add($component, $row, $column)
        return $this
    }
    
    [GridBuilder] Add([Component]$component, [int]$row, [int]$column, [int]$rowSpan, [int]$columnSpan) {
        $this._grid.Add($component, $row, $column, $rowSpan, $columnSpan)
        return $this
    }
    
    [GridLayout] Build() {
        return $this._grid
    }
}