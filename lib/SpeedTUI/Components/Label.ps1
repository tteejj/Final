# SpeedTUI Label Component - Simple text display

class Label : Component {
    [string]$Text = ""
    [string]$ForegroundColor = ""
    [string]$BackgroundColor = ""
    [bool]$Bold = $false
    [bool]$Italic = $false
    [bool]$Underline = $false
    [string]$HorizontalAlignment = "left"  # left, center, right
    [string]$VerticalAlignment = "top"     # top, middle, bottom
    [bool]$WordWrap = $false
    [int]$MaxLines = 0  # 0 = unlimited
    
    # Cached wrapped lines
    hidden [string[]]$_wrappedLines
    hidden [int]$_lastWidth = -1
    
    Label() : base() {
        $this.CanFocus = $false
        $this._logger.Debug("Label", "Constructor", "Label created")
    }
    
    Label([string]$text) : base() {
        $this.CanFocus = $false
        $this.Text = $text
        $this._logger.Debug("Label", "Constructor", "Label created with text", @{
            Text = $text
        })
    }
    
    # Builder methods
    [Label] WithText([string]$text) {
        $this.Text = $text
        $this.Invalidate()
        return $this
    }
    
    [Label] WithColor([string]$foreground) {
        $this.ForegroundColor = $foreground
        $this.Invalidate()
        return $this
    }
    
    [Label] WithColor([string]$foreground, [string]$background) {
        $this.ForegroundColor = $foreground
        $this.BackgroundColor = $background
        $this.Invalidate()
        return $this
    }
    
    [Label] WithStyle([bool]$bold, [bool]$italic, [bool]$underline) {
        $this.Bold = $bold
        $this.Italic = $italic
        $this.Underline = $underline
        $this.Invalidate()
        return $this
    }
    
    [Label] WithAlignment([string]$horizontal, [string]$vertical) {
        $this.HorizontalAlignment = $horizontal
        $this.VerticalAlignment = $vertical
        $this.Invalidate()
        return $this
    }
    
    [Label] WithWordWrap([bool]$wrap) {
        $this.WordWrap = $wrap
        $this.Invalidate()
        return $this
    }
    
    [void] OnBoundsChanged() {
        # Recalculate wrapped lines if width changed
        if ($this.WordWrap -and $this._lastWidth -ne $this.Width) {
            $this._wrappedLines = $null
            $this._lastWidth = $this.Width
        }
    }
    
    [void] OnRender() {
        if ([string]::IsNullOrEmpty($this.Text)) { return }
        
        # Get lines to render
        $lines = $this.GetLinesToRender()
        if ($lines.Count -eq 0) { return }
        
        # Calculate vertical position
        $startY = 0
        switch ($this.VerticalAlignment) {
            "top" { $startY = 0 }
            "middle" { $startY = ($this.Height - $lines.Count) / 2 }
            "bottom" { $startY = $this.Height - $lines.Count }
        }
        $startY = [Math]::Max(0, [int]$startY)
        
        # Build style string
        $style = $this.BuildStyleString()
        $reset = $(if ($style) { [Colors]::Reset } else { "" })
        
        # Render each line
        for ($i = 0; $i -lt $lines.Count -and ($startY + $i) -lt $this.Height; $i++) {
            $line = $lines[$i]
            
            # Calculate horizontal position
            $x = 0
            switch ($this.HorizontalAlignment) {
                "left" { $x = 0 }
                "center" { $x = ($this.Width - $line.Length) / 2 }
                "right" { $x = $this.Width - $line.Length }
            }
            $x = [Math]::Max(0, [int]$x)
            
            # Clip line to width
            if ($line.Length + $x -gt $this.Width) {
                $line = $line.Substring(0, $this.Width - $x)
            }
            
            # Write the line
            $this.WriteAt($x, $startY + $i, "$style$line$reset")
        }
    }
    
    hidden [string[]] GetLinesToRender() {
        if (-not $this.WordWrap) {
            # No wrapping - return single line or split by newlines
            if ($this.Text.Contains("`n")) {
                $lines = $this.Text -split "`n"
            } else {
                $lines = @($this.Text)
            }
            
            # Apply max lines limit
            if ($this.MaxLines -gt 0 -and $lines.Count -gt $this.MaxLines) {
                $lines = $lines[0..($this.MaxLines - 1)]
            }
            
            return $lines
        }
        
        # Word wrap enabled
        if ($null -eq $this._wrappedLines -or $this._lastWidth -ne $this.Width) {
            $this._wrappedLines = $this.WrapText($this.Text, $this.Width)
            $this._lastWidth = $this.Width
        }
        
        return $this._wrappedLines
    }
    
    hidden [string[]] WrapText([string]$text, [int]$width) {
        if ($width -le 0) { return @() }
        
        $lines = [System.Collections.Generic.List[string]]::new()
        $paragraphs = $text -split "`n"
        
        foreach ($paragraph in $paragraphs) {
            if ($paragraph.Length -eq 0) {
                $lines.Add("")
                continue
            }
            
            $words = $paragraph -split '\s+'
            $currentLine = ""
            
            foreach ($word in $words) {
                if ($currentLine.Length -eq 0) {
                    $currentLine = $word
                } elseif (($currentLine.Length + 1 + $word.Length) -le $width) {
                    $currentLine += " " + $word
                } else {
                    $lines.Add($currentLine)
                    $currentLine = $word
                    
                    # Check max lines
                    if ($this.MaxLines -gt 0 -and $lines.Count -ge $this.MaxLines) {
                        return $lines.ToArray()
                    }
                }
            }
            
            if ($currentLine.Length -gt 0) {
                $lines.Add($currentLine)
                
                # Check max lines
                if ($this.MaxLines -gt 0 -and $lines.Count -ge $this.MaxLines) {
                    return $lines.ToArray()
                }
            }
        }
        
        return $lines.ToArray()
    }
    
    hidden [string] BuildStyleString() {
        $style = ""
        
        # Colors
        if ($this.ForegroundColor) {
            $style += $this.ForegroundColor
        }
        if ($this.BackgroundColor) {
            $style += $this.BackgroundColor
        }
        
        # Text decorations
        if ($this.Bold) { $style += [Colors]::Bold }
        if ($this.Italic) { $style += [Colors]::Italic }
        if ($this.Underline) { $style += [Colors]::Underline }
        
        return $style
    }
}

# Label builder for fluent API
class LabelBuilder : ComponentBuilder {
    LabelBuilder() : base([Label]::new()) { }
    
    [LabelBuilder] Text([string]$text) {
        ([Label]$this._component).Text = $text
        return $this
    }
    
    [LabelBuilder] Color([string]$foreground) {
        ([Label]$this._component).ForegroundColor = $foreground
        return $this
    }
    
    [LabelBuilder] Color([string]$foreground, [string]$background) {
        ([Label]$this._component).ForegroundColor = $foreground
        ([Label]$this._component).BackgroundColor = $background
        return $this
    }
    
    [LabelBuilder] Bold() {
        ([Label]$this._component).Bold = $true
        return $this
    }
    
    [LabelBuilder] Italic() {
        ([Label]$this._component).Italic = $true
        return $this
    }
    
    [LabelBuilder] Underline() {
        ([Label]$this._component).Underline = $true
        return $this
    }
    
    [LabelBuilder] Align([string]$horizontal, [string]$vertical) {
        ([Label]$this._component).HorizontalAlignment = $horizontal
        ([Label]$this._component).VerticalAlignment = $vertical
        return $this
    }
    
    [LabelBuilder] WordWrap() {
        ([Label]$this._component).WordWrap = $true
        return $this
    }
    
    [LabelBuilder] MaxLines([int]$lines) {
        ([Label]$this._component).MaxLines = $lines
        return $this
    }
}