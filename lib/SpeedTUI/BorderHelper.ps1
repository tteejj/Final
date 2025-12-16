#!/usr/bin/env pwsh
# BorderHelper - Foolproof border drawing utility

class BorderHelper {
    static [int]$ConsoleWidth = 80
    static [int]$ConsoleHeight = 24
    
    static [void] UpdateDimensions() {
        try {
            [BorderHelper]::ConsoleWidth = [Console]::WindowWidth
            [BorderHelper]::ConsoleHeight = [Console]::WindowHeight
        } catch {
            # Fallback to safe defaults
            [BorderHelper]::ConsoleWidth = 80
            [BorderHelper]::ConsoleHeight = 24
        }
    }
    
    static [string] TopBorder() {
        [BorderHelper]::UpdateDimensions()
        $width = [BorderHelper]::ConsoleWidth
        $content = "╔" + ("═" * ($width - 2)) + "╗"
        return $content
    }
    
    static [string] TopBorder([int]$customWidth) {
        [BorderHelper]::UpdateDimensions()
        $width = $(if ($customWidth -gt 0) { $customWidth } else { [BorderHelper]::ConsoleWidth })
        $content = "╔" + ("═" * ($width - 2)) + "╗"
        return $content
    }
    
    static [string] MiddleBorder() {
        [BorderHelper]::UpdateDimensions()
        $width = [BorderHelper]::ConsoleWidth
        $content = "╠" + ("═" * ($width - 2)) + "╣"
        return $content
    }
    
    static [string] MiddleBorder([int]$customWidth) {
        [BorderHelper]::UpdateDimensions()
        $width = $(if ($customWidth -gt 0) { $customWidth } else { [BorderHelper]::ConsoleWidth })
        $content = "╠" + ("═" * ($width - 2)) + "╣"
        return $content
    }
    
    static [string] BottomBorder() {
        [BorderHelper]::UpdateDimensions()
        $width = [BorderHelper]::ConsoleWidth
        $content = "╚" + ("═" * ($width - 2)) + "╝"
        return $content
    }
    
    static [string] BottomBorder([int]$customWidth) {
        [BorderHelper]::UpdateDimensions()
        $width = $(if ($customWidth -gt 0) { $customWidth } else { [BorderHelper]::ConsoleWidth })
        $content = "╚" + ("═" * ($width - 2)) + "╝"
        return $content
    }
    
    static [string] ContentLine([string]$text) {
        [BorderHelper]::UpdateDimensions()
        $width = [BorderHelper]::ConsoleWidth
        # "║  " (3) + content + "  ║" (3) = 6 chars overhead
        $maxContentWidth = $width - 6
        
        # Truncate text if too long
        if ($text.Length -gt $maxContentWidth) {
            $text = $text.Substring(0, $maxContentWidth - 3) + "..."
        }
        
        # Pad to exact width
        $paddedText = $text.PadRight($maxContentWidth)
        $content = "║  " + $paddedText + "  ║"
        
        return $content
    }
    
    static [string] ContentLine([string]$text, [int]$customWidth) {
        [BorderHelper]::UpdateDimensions()
        $width = $(if ($customWidth -gt 0) { $customWidth } else { [BorderHelper]::ConsoleWidth })
        # "║  " (3) + content + "  ║" (3) = 6 chars overhead
        $maxContentWidth = $width - 6
        
        # Truncate text if too long
        if ($text.Length -gt $maxContentWidth) {
            $text = $text.Substring(0, $maxContentWidth - 3) + "..."
        }
        
        # Pad to exact width
        $paddedText = $text.PadRight($maxContentWidth)
        $content = "║  " + $paddedText + "  ║"
        
        return $content
    }
    
    static [string] EmptyLine() {
        [BorderHelper]::UpdateDimensions()
        $width = [BorderHelper]::ConsoleWidth
        $spaces = " " * ($width - 2)
        return "║$spaces║"
    }
    
    static [string] EmptyLine([int]$customWidth) {
        [BorderHelper]::UpdateDimensions()
        $width = $(if ($customWidth -gt 0) { $customWidth } else { [BorderHelper]::ConsoleWidth })
        $spaces = " " * ($width - 2)
        return "║$spaces║"
    }
    
    static [string] StatusLine([string]$text) {
        [BorderHelper]::UpdateDimensions()
        $width = [BorderHelper]::ConsoleWidth
        # "║  " (3) + content + "  ║" (3) = 6 chars overhead
        $maxContentWidth = $width - 6
        
        # Truncate if needed
        if ($text.Length -gt $maxContentWidth) {
            $text = $text.Substring(0, $maxContentWidth - 3) + "..."
        }
        
        # Center the text
        $padding = $maxContentWidth - $text.Length
        $leftPad = [Math]::Floor($padding / 2)
        $rightPad = $padding - $leftPad
        $centeredText = (" " * $leftPad) + $text + (" " * $rightPad)
        
        return "║  " + $centeredText + "  ║"
    }
    
    static [string] StatusLine([string]$text, [int]$customWidth) {
        [BorderHelper]::UpdateDimensions()
        $width = $(if ($customWidth -gt 0) { $customWidth } else { [BorderHelper]::ConsoleWidth })
        # "║  " (3) + content + "  ║" (3) = 6 chars overhead
        $maxContentWidth = $width - 6
        
        # Truncate if needed
        if ($text.Length -gt $maxContentWidth) {
            $text = $text.Substring(0, $maxContentWidth - 3) + "..."
        }
        
        # Center the text
        $padding = $maxContentWidth - $text.Length
        $leftPad = [Math]::Floor($padding / 2)
        $rightPad = $padding - $leftPad
        $centeredText = (" " * $leftPad) + $text + (" " * $rightPad)
        
        return "║  " + $centeredText + "  ║"
    }
}

# Test the border helper
function Test-BorderHelper {
    Write-Host "Testing BorderHelper with current console dimensions..." -ForegroundColor Cyan
    
    [BorderHelper]::UpdateDimensions()
    Write-Host "Console size: $([BorderHelper]::ConsoleWidth) x $([BorderHelper]::ConsoleHeight)" -ForegroundColor Yellow
    
    # Test borders
    $top = [BorderHelper]::TopBorder()
    $middle = [BorderHelper]::MiddleBorder()
    $bottom = [BorderHelper]::BottomBorder()
    $empty = [BorderHelper]::EmptyLine()
    $content = [BorderHelper]::ContentLine("Test content line")
    $status = [BorderHelper]::StatusLine("Centered status text")
    
    Write-Host "Actual lengths:" -ForegroundColor Green
    Write-Host "  Top border: $($top.Length) chars" -ForegroundColor Green
    Write-Host "  Content line: $($content.Length) chars" -ForegroundColor Green
    Write-Host "  Bottom border: $($bottom.Length) chars" -ForegroundColor Green
    
    Write-Host "`nRendered output:" -ForegroundColor Green
    Write-Host $top -ForegroundColor Cyan
    Write-Host $content -ForegroundColor White
    Write-Host $middle -ForegroundColor Cyan
    Write-Host $status -ForegroundColor Gray
    Write-Host $empty -ForegroundColor White
    Write-Host $bottom -ForegroundColor Cyan
}