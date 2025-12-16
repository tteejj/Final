# SpeedTUI Stack Layout - Vertical and horizontal stacking layouts

using namespace System.Collections.Generic

enum StackOrientation {
    Vertical
    Horizontal
}

enum StackAlignment {
    Start
    Center
    End
    Stretch
}

class StackLayout : Component {
    [StackOrientation]$Orientation = [StackOrientation]::Vertical
    [StackAlignment]$Alignment = [StackAlignment]::Stretch
    [StackAlignment]$CrossAlignment = [StackAlignment]::Stretch
    [int]$Spacing = 0
    [List[Component]]$Items
    
    # Calculated positions
    hidden [int[]]$_itemPositions
    hidden [int[]]$_itemSizes
    
    StackLayout() : base() {
        $this.Items = [List[Component]]::new()
        $this._logger.Debug("StackLayout", "Constructor", "StackLayout created")
    }
    
    StackLayout([StackOrientation]$orientation) : base() {
        $this.Items = [List[Component]]::new()
        $this.Orientation = $orientation
        $this._logger.Debug("StackLayout", "Constructor", "StackLayout created", @{
            Orientation = $orientation
        })
    }
    
    # Add item to stack
    [StackLayout] AddItem([Component]$component) {
        [Guard]::NotNull($component, "component")
        
        $this.Items.Add($component)
        $this.AddChild($component)
        
        $this._logger.Debug("StackLayout", "AddItem", "Item added to stack", @{
            ComponentId = $component.Id
            ItemCount = $this.Items.Count
        })
        
        return $this
    }
    
    # Builder methods
    [StackLayout] WithOrientation([StackOrientation]$orientation) {
        $this.Orientation = $orientation
        $this.Invalidate()
        return $this
    }
    
    [StackLayout] WithSpacing([int]$spacing) {
        [Guard]::NonNegative($spacing, "spacing")
        $this.Spacing = $spacing
        $this.Invalidate()
        return $this
    }
    
    [StackLayout] WithAlignment([StackAlignment]$alignment) {
        $this.Alignment = $alignment
        $this.Invalidate()
        return $this
    }
    
    [StackLayout] WithCrossAlignment([StackAlignment]$alignment) {
        $this.CrossAlignment = $alignment
        $this.Invalidate()
        return $this
    }
    
    # Layout calculation
    [void] OnBoundsChanged() {
        $this.CalculateLayout()
        $this.PositionChildren()
    }
    
    hidden [void] CalculateLayout() {
        if ($this.Items.Count -eq 0) { return }
        
        $timer = $this._logger.MeasurePerformance("StackLayout", "CalculateLayout")
        
        try {
            $this._itemPositions = New-Object int[] $this.Items.Count
            $this._itemSizes = New-Object int[] $this.Items.Count
            
            if ($this.Orientation -eq [StackOrientation]::Vertical) {
                $this.CalculateVerticalLayout()
            } else {
                $this.CalculateHorizontalLayout()
            }
            
        } finally {
            $timer.Dispose()
        }
    }
    
    hidden [void] CalculateVerticalLayout() {
        $totalSpacing = $this.Spacing * ([Math]::Max(0, $this.Items.Count - 1))
        $availableHeight = $this.Height - $totalSpacing
        $stretchCount = 0
        $fixedHeight = 0
        
        # First pass: calculate fixed heights
        for ($i = 0; $i -lt $this.Items.Count; $i++) {
            $item = $this.Items[$i]
            if ($item.Height -gt 0) {
                $this._itemSizes[$i] = $item.Height
                $fixedHeight += $item.Height
            } else {
                $stretchCount++
            }
        }
        
        # Second pass: distribute remaining height to stretch items
        if ($stretchCount -gt 0) {
            $remainingHeight = [Math]::Max(0, $availableHeight - $fixedHeight)
            $stretchHeight = [int]($remainingHeight / $stretchCount)
            
            for ($i = 0; $i -lt $this.Items.Count; $i++) {
                if ($this._itemSizes[$i] -eq 0) {
                    $this._itemSizes[$i] = $stretchHeight
                }
            }
        }
        
        # Calculate positions based on alignment
        $currentPos = 0
        
        switch ($this.Alignment) {
            Start {
                $currentPos = $this.Y
            }
            Center {
                $totalHeight = ($this._itemSizes | Measure-Object -Sum).Sum + $totalSpacing
                $currentPos = $this.Y + ($this.Height - $totalHeight) / 2
            }
            End {
                $totalHeight = ($this._itemSizes | Measure-Object -Sum).Sum + $totalSpacing
                $currentPos = $this.Y + $this.Height - $totalHeight
            }
            Stretch {
                $currentPos = $this.Y
            }
        }
        
        # Set positions
        for ($i = 0; $i -lt $this.Items.Count; $i++) {
            $this._itemPositions[$i] = [int]$currentPos
            $currentPos += $this._itemSizes[$i] + $this.Spacing
        }
    }
    
    hidden [void] CalculateHorizontalLayout() {
        $totalSpacing = $this.Spacing * ([Math]::Max(0, $this.Items.Count - 1))
        $availableWidth = $this.Width - $totalSpacing
        $stretchCount = 0
        $fixedWidth = 0
        
        # First pass: calculate fixed widths
        for ($i = 0; $i -lt $this.Items.Count; $i++) {
            $item = $this.Items[$i]
            if ($item.Width -gt 0) {
                $this._itemSizes[$i] = $item.Width
                $fixedWidth += $item.Width
            } else {
                $stretchCount++
            }
        }
        
        # Second pass: distribute remaining width to stretch items
        if ($stretchCount -gt 0) {
            $remainingWidth = [Math]::Max(0, $availableWidth - $fixedWidth)
            $stretchWidth = [int]($remainingWidth / $stretchCount)
            
            for ($i = 0; $i -lt $this.Items.Count; $i++) {
                if ($this._itemSizes[$i] -eq 0) {
                    $this._itemSizes[$i] = $stretchWidth
                }
            }
        }
        
        # Calculate positions based on alignment
        $currentPos = 0
        
        switch ($this.Alignment) {
            Start {
                $currentPos = $this.X
            }
            Center {
                $totalWidth = ($this._itemSizes | Measure-Object -Sum).Sum + $totalSpacing
                $currentPos = $this.X + ($this.Width - $totalWidth) / 2
            }
            End {
                $totalWidth = ($this._itemSizes | Measure-Object -Sum).Sum + $totalSpacing
                $currentPos = $this.X + $this.Width - $totalWidth
            }
            Stretch {
                $currentPos = $this.X
            }
        }
        
        # Set positions
        for ($i = 0; $i -lt $this.Items.Count; $i++) {
            $this._itemPositions[$i] = [int]$currentPos
            $currentPos += $this._itemSizes[$i] + $this.Spacing
        }
    }
    
    hidden [void] PositionChildren() {
        for ($i = 0; $i -lt $this.Items.Count; $i++) {
            $item = $this.Items[$i]
            
            if ($this.Orientation -eq [StackOrientation]::Vertical) {
                # Vertical stacking
                $x = $this.X
                $y = $this._itemPositions[$i]
                $width = $this.Width
                $height = $this._itemSizes[$i]
                
                # Apply cross alignment
                switch ($this.CrossAlignment) {
                    Start {
                        $width = $item.Width
                    }
                    Center {
                        $x = $this.X + ($this.Width - $item.Width) / 2
                        $width = $item.Width
                    }
                    End {
                        $x = $this.X + $this.Width - $item.Width
                        $width = $item.Width
                    }
                    Stretch {
                        # Use full width
                    }
                }
                
                $item.SetBounds([int]$x, [int]$y, [int]$width, [int]$height)
            } else {
                # Horizontal stacking
                $x = $this._itemPositions[$i]
                $y = $this.Y
                $width = $this._itemSizes[$i]
                $height = $this.Height
                
                # Apply cross alignment
                switch ($this.CrossAlignment) {
                    Start {
                        $height = $item.Height
                    }
                    Center {
                        $y = $this.Y + ($this.Height - $item.Height) / 2
                        $height = $item.Height
                    }
                    End {
                        $y = $this.Y + $this.Height - $item.Height
                        $height = $item.Height
                    }
                    Stretch {
                        # Use full height
                    }
                }
                
                $item.SetBounds([int]$x, [int]$y, [int]$width, [int]$height)
            }
        }
    }
    
    [void] OnRender() {
        # Stack doesn't render anything itself, just its children
    }
}

# Convenience classes
class VStack : StackLayout {
    VStack() : base([StackOrientation]::Vertical) { }
    
    [VStack] Build() {
        return $this
    }
}

class HStack : StackLayout {
    HStack() : base([StackOrientation]::Horizontal) { }
    
    [HStack] Build() {
        return $this
    }
}

# Stack builder for fluent API
class StackBuilder {
    hidden [StackLayout]$_stack
    
    StackBuilder([StackOrientation]$orientation) {
        $this._stack = [StackLayout]::new($orientation)
    }
    
    [StackBuilder] Spacing([int]$spacing) {
        $this._stack.WithSpacing($spacing)
        return $this
    }
    
    [StackBuilder] Alignment([StackAlignment]$alignment) {
        $this._stack.WithAlignment($alignment)
        return $this
    }
    
    [StackBuilder] CrossAlignment([StackAlignment]$alignment) {
        $this._stack.WithCrossAlignment($alignment)
        return $this
    }
    
    [StackBuilder] Add([Component]$component) {
        $this._stack.AddItem($component)
        return $this
    }
    
    [StackLayout] Build() {
        return $this._stack
    }
}

# Helper functions for easy creation
function VStack {
    param([scriptblock]$builder)
    
    $stack = [VStack]::new()
    if ($builder) {
        & $builder $stack
    }
    return $stack
}

function HStack {
    param([scriptblock]$builder)
    
    $stack = [HStack]::new()
    if ($builder) {
        & $builder $stack
    }
    return $stack
}