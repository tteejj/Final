# SpeedTUI Development Helpers - Making development easy and debugging clear
# Provides practical tools that developers actually want to use

using namespace System.Collections.Generic

<#
.SYNOPSIS
SpeedTUI development and debugging helper class

.DESCRIPTION
Provides practical debugging and development tools that make building
SpeedTUI applications easier. Includes component inspection, performance
monitoring, layout visualization, and troubleshooting helpers.

.EXAMPLE
# Show component layout
[DevHelpers]::ShowLayout($screen)

# Monitor performance
[DevHelpers]::StartPerformanceMonitoring()

# Debug component issues
[DevHelpers]::InspectComponent($button)
#>
class DevHelpers {
    static [bool]$DebugMode = $false
    static [hashtable]$PerformanceData = @{}
    static [System.Diagnostics.Stopwatch]$PerformanceTimer = [System.Diagnostics.Stopwatch]::new()
    
    <#
    .SYNOPSIS
    Show visual layout of components in ASCII art
    
    .PARAMETER rootComponent
    Root component to visualize (usually a Screen)
    
    .PARAMETER showDetails
    Whether to show detailed information about each component
    
    .EXAMPLE
    [DevHelpers]::ShowLayout($screen)
    [DevHelpers]::ShowLayout($screen, $true)  # With details
    #>
    static [void] ShowLayout([object]$rootComponent, [bool]$showDetails = $false) {
        if (-not $rootComponent) {
            Write-Host "No component provided" -ForegroundColor Red
            return
        }
        
        Write-Host "`n=== SpeedTUI Layout Visualization ===" -ForegroundColor Cyan
        Write-Host "Root: $($rootComponent.GetType().Name)" -ForegroundColor Yellow
        
        if ($rootComponent.PSObject.Properties['Width'] -and $rootComponent.PSObject.Properties['Height']) {
            Write-Host "Size: $($rootComponent.Width) x $($rootComponent.Height)" -ForegroundColor Green
        }
        
        Write-Host ""
        
        # Create a visual grid
        $maxWidth = 80
        $maxHeight = 24
        
        if ($rootComponent.PSObject.Properties['Width']) {
            $maxWidth = [Math]::Min($rootComponent.Width, 80)
        }
        if ($rootComponent.PSObject.Properties['Height']) {
            $maxHeight = [Math]::Min($rootComponent.Height, 24)
        }
        
        # Initialize grid
        $grid = @()
        for ($y = 0; $y -lt $maxHeight; $y++) {
            $row = @()
            for ($x = 0; $x -lt $maxWidth; $x++) {
                $row += ' '
            }
            $grid += ,$row
        }
        
        # Draw components on grid
        [DevHelpers]::DrawComponentOnGrid($grid, $rootComponent, 0, 0, $maxWidth, $maxHeight)
        
        # Print grid
        for ($y = 0; $y -lt $maxHeight; $y++) {
            $line = -join $grid[$y]
            Write-Host $line
        }
        
        Write-Host "`n=== End Layout ===" -ForegroundColor Cyan
        
        if ($showDetails) {
            [DevHelpers]::ShowComponentDetails($rootComponent, 0)
        }
    }
    
    # Helper method to draw components on ASCII grid
    static hidden [void] DrawComponentOnGrid([array]$grid, [object]$component, [int]$offsetX, [int]$offsetY, [int]$maxWidth, [int]$maxHeight) {
        if (-not $component) { return }
        
        $x = $offsetX
        $y = $offsetY
        $width = 10
        $height = 3
        
        # Get component position and size
        if ($component.PSObject.Properties['X']) { $x += $component.X }
        if ($component.PSObject.Properties['Y']) { $y += $component.Y }
        if ($component.PSObject.Properties['Width']) { $width = $component.Width }
        if ($component.PSObject.Properties['Height']) { $height = $component.Height }
        
        # Determine character to use based on component type
        $char = switch ($component.GetType().Name) {
            "Button" { 'B' }
            "Label" { 'L' }
            "InputField" { 'I' }
            "List" { '#' }
            "Table" { 'T' }
            default { '?' }
        }
        
        # Draw component on grid
        for ($cy = $y; $cy -lt ($y + $height) -and $cy -lt $maxHeight; $cy++) {
            for ($cx = $x; $cx -lt ($x + $width) -and $cx -lt $maxWidth; $cx++) {
                if ($cy -ge 0 -and $cx -ge 0) {
                    # Draw border for first/last row/column, fill for others
                    if ($cy -eq $y -or $cy -eq ($y + $height - 1) -or 
                        $cx -eq $x -or $cx -eq ($x + $width - 1)) {
                        $grid[$cy][$cx] = $char
                    } else {
                        $grid[$cy][$cx] = '.'
                    }
                }
            }
        }
        
        # Draw children if they exist
        if ($component.PSObject.Properties['Children']) {
            foreach ($child in $component.Children) {
                [DevHelpers]::DrawComponentOnGrid($grid, $child, $x, $y, $maxWidth, $maxHeight)
            }
        }
    }
    
    # Show detailed component information
    static hidden [void] ShowComponentDetails([object]$component, [int]$indent) {
        $indentStr = "  " * $indent
        $type = $component.GetType().Name
        
        Write-Host "$indentStr$type" -ForegroundColor Yellow
        
        if ($component.PSObject.Properties['Id']) {
            Write-Host "$indentStr  ID: $($component.Id)" -ForegroundColor Gray
        }
        
        if ($component.PSObject.Properties['X'] -and $component.PSObject.Properties['Y']) {
            Write-Host "$indentStr  Position: $($component.X), $($component.Y)" -ForegroundColor Green
        }
        
        if ($component.PSObject.Properties['Width'] -and $component.PSObject.Properties['Height']) {
            Write-Host "$indentStr  Size: $($component.Width) x $($component.Height)" -ForegroundColor Green
        }
        
        if ($component.PSObject.Properties['Visible']) {
            Write-Host "$indentStr  Visible: $($component.Visible)" -ForegroundColor $(if ($component.Visible) { "Green" } else { "Red" })
        }
        
        if ($component.PSObject.Properties['CanFocus']) {
            Write-Host "$indentStr  Can Focus: $($component.CanFocus)" -ForegroundColor Blue
        }
        
        # Show children
        if ($component.PSObject.Properties['Children'] -and $component.Children.Count -gt 0) {
            Write-Host "$indentStr  Children ($($component.Children.Count)):" -ForegroundColor Cyan
            foreach ($child in $component.Children) {
                [DevHelpers]::ShowComponentDetails($child, $indent + 1)
            }
        }
    }
    
    <#
    .SYNOPSIS
    Inspect a specific component and show all its properties
    
    .PARAMETER component
    Component to inspect
    
    .EXAMPLE
    [DevHelpers]::InspectComponent($button)
    #>
    static [void] InspectComponent([object]$component) {
        if (-not $component) {
            Write-Host "No component provided" -ForegroundColor Red
            return
        }
        
        Write-Host "`n=== Component Inspector ===" -ForegroundColor Cyan
        Write-Host "Type: $($component.GetType().Name)" -ForegroundColor Yellow
        
        # Show all properties
        $properties = $component.PSObject.Properties | Where-Object { $_.MemberType -eq 'Property' -or $_.MemberType -eq 'NoteProperty' }
        
        foreach ($prop in $properties) {
            $name = $prop.Name
            $value = $prop.Value
            
            # Format value based on type
            $displayValue = $(if ($null -eq $value) {
                "null"
            } elseif ($value -is [string]) {
                "`"$value`""
            } elseif ($value -is [bool]) {
                $value.ToString().ToLower()
            } elseif ($value -is [scriptblock]) {
                "{ ... }"
            } elseif ($value -is [array] -or $value -is [System.Collections.ICollection]) {
                "[$($value.Count) items]"
            } else {
                $value.ToString()
            })
            
            $color = switch ($prop.MemberType) {
                'Property' { 'White' }
                'NoteProperty' { 'Gray' }
                default { 'White' }
            }
            
            Write-Host "  $name`: $displayValue" -ForegroundColor $color
        }
        
        # Show methods if requested
        Write-Host "`nPublic Methods:" -ForegroundColor Magenta
        $methods = $component.PSObject.Methods | Where-Object { $_.MemberType -eq 'Method' -and -not $_.Name.StartsWith('_') }
        foreach ($method in $methods | Sort-Object Name) {
            Write-Host "  $($method.Name)()" -ForegroundColor Blue
        }
        
        Write-Host "=== End Inspector ===`n" -ForegroundColor Cyan
    }
    
    <#
    .SYNOPSIS
    Start performance monitoring for SpeedTUI
    
    .EXAMPLE
    [DevHelpers]::StartPerformanceMonitoring()
    # ... do some work ...
    [DevHelpers]::ShowPerformanceReport()
    #>
    static [void] StartPerformanceMonitoring() {
        [DevHelpers]::PerformanceData.Clear()
        [DevHelpers]::PerformanceTimer.Restart()
        [DevHelpers]::DebugMode = $true
        
        Write-Host "Performance monitoring started" -ForegroundColor Green
        
        # Monitor key performance areas
        [DevHelpers]::PerformanceData['StartTime'] = [DateTime]::Now
        [DevHelpers]::PerformanceData['MemoryStart'] = [GC]::GetTotalMemory($false)
    }
    
    <#
    .SYNOPSIS
    Stop performance monitoring and show report
    
    .EXAMPLE
    [DevHelpers]::ShowPerformanceReport()
    #>
    static [void] ShowPerformanceReport() {
        [DevHelpers]::PerformanceTimer.Stop()
        [DevHelpers]::DebugMode = $false
        
        Write-Host "`n=== Performance Report ===" -ForegroundColor Cyan
        
        $elapsed = [DevHelpers]::PerformanceTimer.Elapsed
        Write-Host "Total Time: $($elapsed.TotalMilliseconds) ms" -ForegroundColor Yellow
        
        if ([DevHelpers]::PerformanceData.ContainsKey('MemoryStart')) {
            $memoryEnd = [GC]::GetTotalMemory($false)
            $memoryDiff = $memoryEnd - [DevHelpers]::PerformanceData['MemoryStart']
            $memoryDiffMB = [Math]::Round($memoryDiff / 1MB, 2)
            
            Write-Host "Memory Change: $memoryDiffMB MB" -ForegroundColor $(if ($memoryDiff -gt 0) { "Red" } else { "Green" })
        }
        
        # Show garbage collection info
        $gen0 = [GC]::CollectionCount(0)
        $gen1 = [GC]::CollectionCount(1) 
        $gen2 = [GC]::CollectionCount(2)
        
        Write-Host "GC Collections - Gen0: $gen0, Gen1: $gen1, Gen2: $gen2" -ForegroundColor Blue
        
        # Show performance optimizations if available
        $perfStats = Get-PerformanceStats -ErrorAction SilentlyContinue
        if ($perfStats) {
            Write-Host "`nOptimization Stats:" -ForegroundColor Magenta
            if ($perfStats.StringBuilderPool) {
                Write-Host "  StringBuilder Reuse Rate: $($perfStats.StringBuilderPool.ReuseRate)%" -ForegroundColor Green
            }
            if ($perfStats.ColorCacheSize) {
                Write-Host "  Color Cache Size: $($perfStats.ColorCacheSize)" -ForegroundColor Green
            }
        }
        
        Write-Host "=== End Report ===`n" -ForegroundColor Cyan
    }
    
    <#
    .SYNOPSIS
    Show SpeedTUI examples for common tasks
    
    .PARAMETER exampleName
    Name of the example to show (button, form, theming, etc.)
    
    .EXAMPLE
    [DevHelpers]::ShowExample("button")
    [DevHelpers]::ShowExample("form")
    [DevHelpers]::ShowExample("theming")
    #>
    static [void] ShowExample([string]$exampleName) {
        Write-Host "`n=== SpeedTUI Example: $exampleName ===" -ForegroundColor Cyan
        
        switch ($exampleName.ToLower()) {
            "button" {
                Write-Host @"
# Simple Button Example
`$button = [Button]::new("Click Me", 10, 5)
`$button.OnClick = { 
    Write-Host "Button clicked!" 
}
`$screen.AddComponent(`$button)

# Enhanced Button with Theme
`$enhancedButton = New-EnhancedComponent ([Button]::new()) |
    Position 10 5 |
    Size 20 3 |
    Theme "matrix" |
    Color "primary" |
    Build
"@ -ForegroundColor White
            }
            
            "form" {
                Write-Host @"
# Simple Form Example
`$screen = [Screen]::new()

`$nameLabel = [Label]::new("Name:", 5, 3)
`$nameInput = [InputField]::new(15, 3, 20)

`$emailLabel = [Label]::new("Email:", 5, 5) 
`$emailInput = [InputField]::new(15, 5, 20)

`$submitButton = [Button]::new("Submit", 15, 8)
`$submitButton.OnClick = {
    `$name = `$nameInput.Text
    `$email = `$emailInput.Text
    Write-Host "Name: `$name, Email: `$email"
}

`$screen.AddComponent(`$nameLabel)
`$screen.AddComponent(`$nameInput)
`$screen.AddComponent(`$emailLabel)
`$screen.AddComponent(`$emailInput)
`$screen.AddComponent(`$submitButton)
"@ -ForegroundColor White
            }
            
            "theming" {
                Write-Host @"
# Theme Examples

# Set global theme
Set-SpeedTUITheme "matrix"    # Green on black
Set-SpeedTUITheme "amber"     # Amber on dark
Set-SpeedTUITheme "electric"  # Electric blue

# Component-specific theming
`$button.SetTheme("matrix")
`$button.SetColor("primary")

# Custom colors
`$themeManager = Get-ThemeManager
`$themeManager.SetCustomColor("button.special", @(255, 100, 200))

# Create custom theme
`$myTheme = New-SpeedTUITheme "MyTheme" "My custom theme" {
    `$this.DefineRGBColor("primary", @(100, 150, 255))
    `$this.DefineRGBColor("secondary", @(255, 150, 100))
}
"@ -ForegroundColor White
            }
            
            "layout" {
                Write-Host @"
# Layout Examples

# Simple positioning
`$button.SetPosition(10, 5)
`$button.SetSize(20, 3)
`$button.MoveTo(15, 8)

# Automatic arrangement
@(`$button1, `$button2, `$button3) | Arrange-Vertically -StartX 10 -StartY 5 -Spacing 2
@(`$label1, `$label2, `$label3) | Arrange-Horizontally -StartX 5 -StartY 10 -Spacing 5

# Size constraints
`$input.SetSizeConstraints(10, 1, 50, 5)  # Min 10x1, max 50x5
"@ -ForegroundColor White
            }
            
            "events" {
                Write-Host @"
# Event System Examples

# Subscribe to events
`$events = Get-EventManager
`$id = `$events.On("button.clicked") { param(`$eventData)
    Write-Host "Button `$(`$eventData.Get('ButtonId')) clicked!"
}

# Fire events
`$events.Fire("button.clicked", @{ ButtonId = "okButton"; Value = "OK" })

# Global helpers
`$id = Subscribe-Event "data.changed" { param(`$e)
    Write-Host "Data changed: `$(`$e.Data)"
}
Fire-Event "data.changed" "New data value"

# Cleanup
Unsubscribe-Event "data.changed" `$id
"@ -ForegroundColor White
            }
            
            "debugging" {
                Write-Host @"
# Debugging Examples

# Show component layout
[DevHelpers]::ShowLayout(`$screen)
[DevHelpers]::ShowLayout(`$screen, `$true)  # With details

# Inspect specific component
[DevHelpers]::InspectComponent(`$button)

# Performance monitoring
[DevHelpers]::StartPerformanceMonitoring()
# ... your code here ...
[DevHelpers]::ShowPerformanceReport()

# Component debugging
`$button.ShowDebugBounds(`$true)     # Show visual bounds
`$button.ShowDebugInfo()             # Show component info
`$button.GetPerformanceStats()       # Get performance data

# Event debugging
`$events.SetDebugMode(`$true)        # Enable event tracing
`$events.GetEventHistory(10)         # Show recent events
"@ -ForegroundColor White
            }
            
            default {
                Write-Host "Available examples: button, form, theming, layout, events, debugging" -ForegroundColor Yellow
                Write-Host "Usage: [DevHelpers]::ShowExample('button')" -ForegroundColor Gray
            }
        }
        
        Write-Host "=== End Example ===`n" -ForegroundColor Cyan
    }
    
    <#
    .SYNOPSIS
    Run an interactive SpeedTUI demo
    
    .EXAMPLE
    [DevHelpers]::RunDemo()
    #>
    static [void] RunDemo() {
        Write-Host "=== SpeedTUI Interactive Demo ===" -ForegroundColor Cyan
        Write-Host "This would start an interactive demo showing SpeedTUI features" -ForegroundColor Yellow
        Write-Host "Use [DevHelpers]::ShowExample('button') to see code examples" -ForegroundColor Green
        Write-Host "===================================`n" -ForegroundColor Cyan
    }
    
    <#
    .SYNOPSIS
    Validate SpeedTUI installation and show system info
    
    .EXAMPLE
    [DevHelpers]::ValidateInstallation()
    #>
    static [void] ValidateInstallation() {
        Write-Host "`n=== SpeedTUI Installation Validation ===" -ForegroundColor Cyan
        
        # Check PowerShell version
        $psVersion = $PSVersionTable.PSVersion
        Write-Host "PowerShell Version: $psVersion" -ForegroundColor $(if ($psVersion.Major -ge 5) { "Green" } else { "Red" })
        
        # Check terminal capabilities
        try {
            $width = [Console]::WindowWidth
            $height = [Console]::WindowHeight
            Write-Host "Terminal Size: ${width}x${height}" -ForegroundColor Green
        } catch {
            Write-Host "Terminal Size: Unable to detect" -ForegroundColor Red
        }
        
        # Check color support
        try {
            Write-Host "Color Support: " -NoNewline
            Write-Host "████" -ForegroundColor Red -NoNewline
            Write-Host "████" -ForegroundColor Green -NoNewline
            Write-Host "████" -ForegroundColor Blue -NoNewline
            Write-Host "████" -ForegroundColor Yellow -NoNewline
            Write-Host " Available" -ForegroundColor Green
        } catch {
            Write-Host "Color Support: Limited" -ForegroundColor Yellow
        }
        
        # Check performance optimizations
        try {
            $perfStats = Get-PerformanceStats -ErrorAction SilentlyContinue
            if ($perfStats) {
                Write-Host "Performance Optimizations: Available" -ForegroundColor Green
                Write-Host "  String Cache: $($perfStats.SpacesCacheSize) items" -ForegroundColor Gray
                Write-Host "  Color Cache: $($perfStats.ColorCacheSize) items" -ForegroundColor Gray
            } else {
                Write-Host "Performance Optimizations: Not loaded" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Performance Optimizations: Error checking" -ForegroundColor Red
        }
        
        # Check theme system
        try {
            $themeManager = Get-ThemeManager -ErrorAction SilentlyContinue
            if ($themeManager) {
                $themes = $themeManager.GetAvailableThemes()
                Write-Host "Theme System: Available ($($themes.Count) themes)" -ForegroundColor Green
                Write-Host "  Themes: $($themes -join ', ')" -ForegroundColor Gray
            } else {
                Write-Host "Theme System: Not loaded" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Theme System: Error checking" -ForegroundColor Red
        }
        
        # Check event system
        try {
            $eventManager = Get-EventManager -ErrorAction SilentlyContinue
            if ($eventManager) {
                $stats = $eventManager.GetStats()
                Write-Host "Event System: Available" -ForegroundColor Green
                Write-Host "  Events: $($stats.RegisteredEvents), Handlers: $($stats.TotalHandlers)" -ForegroundColor Gray
            } else {
                Write-Host "Event System: Not loaded" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Event System: Error checking" -ForegroundColor Red
        }
        
        Write-Host "`n=== Validation Complete ===" -ForegroundColor Cyan
        Write-Host "Use [DevHelpers]::ShowExample('button') to get started!" -ForegroundColor Green
        Write-Host "================================`n" -ForegroundColor Cyan
    }
}

# Global helper functions for easy access

<#
.SYNOPSIS
Quick component inspection helper

.PARAMETER Component
Component to inspect

.EXAMPLE
Inspect-Component $button
#>
function Inspect-Component {
    param([object]$Component)
    [DevHelpers]::InspectComponent($Component)
}

<#
.SYNOPSIS
Quick layout visualization helper

.PARAMETER RootComponent
Root component to visualize

.PARAMETER ShowDetails
Whether to show detailed information

.EXAMPLE
Show-Layout $screen
Show-Layout $screen -ShowDetails
#>
function Show-Layout {
    param(
        [object]$RootComponent,
        [switch]$ShowDetails
    )
    [DevHelpers]::ShowLayout($RootComponent, $ShowDetails.IsPresent)
}

<#
.SYNOPSIS
Quick example display helper

.PARAMETER ExampleName
Name of example to show

.EXAMPLE
Show-SpeedTUIExample "button"
Show-SpeedTUIExample "theming"
#>
function Show-SpeedTUIExample {
    param([string]$ExampleName)
    [DevHelpers]::ShowExample($ExampleName)
}

<#
.SYNOPSIS
Quick performance monitoring helpers

.EXAMPLE
Start-SpeedTUIPerformanceMonitoring
# ... do work ...
Show-SpeedTUIPerformanceReport
#>
function Start-SpeedTUIPerformanceMonitoring {
    [DevHelpers]::StartPerformanceMonitoring()
}

function Show-SpeedTUIPerformanceReport {
    [DevHelpers]::ShowPerformanceReport()
}

<#
.SYNOPSIS
Quick installation validation

.EXAMPLE
Test-SpeedTUIInstallation
#>
function Test-SpeedTUIInstallation {
    [DevHelpers]::ValidateInstallation()
}

Export-ModuleMember -Function Inspect-Component, Show-Layout, Show-SpeedTUIExample, Start-SpeedTUIPerformanceMonitoring, Show-SpeedTUIPerformanceReport, Test-SpeedTUIInstallation