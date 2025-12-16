# TestWidgetScreen - Demo screen showing all PMC widgets
# This validates the complete widget library architecture

Set-StrictMode -Version Latest

using namespace System

# Load widget dependencies
. "$PSScriptRoot/PmcWidget.ps1"
. "$PSScriptRoot/PmcMenuBar.ps1"
. "$PSScriptRoot/PmcHeader.ps1"
. "$PSScriptRoot/PmcFooter.ps1"
. "$PSScriptRoot/PmcStatusBar.ps1"
. "$PSScriptRoot/PmcPanel.ps1"
. "$PSScriptRoot/../layout/PmcLayoutManager.ps1"
. "$PSScriptRoot/../theme/PmcThemeManager.ps1"

<#
.SYNOPSIS
Test screen demonstrating all PMC widgets

.DESCRIPTION
Shows:
- MenuBar with dropdowns
- Header with title and breadcrumb
- Content panel
- Footer with shortcuts
- StatusBar with info

.EXAMPLE
Show-TestWidgetScreen
#>
function Show-TestWidgetScreen {
    try {
        # Initialize components
        Write-Host "Initializing PMC Widget Test Screen..." -ForegroundColor Cyan

        # Get terminal size
        $termWidth = [Console]::WindowWidth
        $termHeight = [Console]::WindowHeight

        Write-Host "Terminal size: ${termWidth}x${termHeight}" -ForegroundColor Gray

        # Create layout manager
        $layout = [PmcLayoutManager]::new()

        # Create menu bar
        Write-Host "Creating menu bar..." -ForegroundColor Gray
        $menuBar = [PmcMenuBar]::new()

        # Add File menu
        $fileItems = @(
            [PmcMenuItem]::new('New Task', 'N', { Write-Host "New Task!" -ForegroundColor Green })
            [PmcMenuItem]::new('Open Project', 'O', { Write-Host "Open Project!" -ForegroundColor Green })
            [PmcMenuItem]::Separator()
            [PmcMenuItem]::new('Exit', 'X', { Write-Host "Exit!" -ForegroundColor Yellow })
        )
        $menuBar.AddMenu('File', 'F', $fileItems)

        # Add View menu
        $viewItems = @(
            [PmcMenuItem]::new('Tasks', 'T', { Write-Host "Tasks view!" -ForegroundColor Green })
            [PmcMenuItem]::new('Projects', 'P', { Write-Host "Projects view!" -ForegroundColor Green })
            [PmcMenuItem]::new('Calendar', 'C', { Write-Host "Calendar view!" -ForegroundColor Green })
        )
        $menuBar.AddMenu('View', 'V', $viewItems)

        # Add Help menu
        $helpItems = @(
            [PmcMenuItem]::new('About', 'A', { Write-Host "About PMC!" -ForegroundColor Cyan })
            [PmcMenuItem]::new('Documentation', 'D', { Write-Host "Docs!" -ForegroundColor Cyan })
        )
        $menuBar.AddMenu('Help', 'H', $helpItems)

        # Apply layout to menu bar
        $menuBarRect = $layout.GetRegion('MenuBar', $termWidth, $termHeight)
        $menuBar.SetPosition($menuBarRect.X, $menuBarRect.Y)
        $menuBar.SetSize($menuBarRect.Width, $menuBarRect.Height)

        Write-Host "Menu bar configured: X=$($menuBar.X), Y=$($menuBar.Y), W=$($menuBar.Width), H=$($menuBar.Height)" -ForegroundColor Gray

        # Create header
        Write-Host "Creating header..." -ForegroundColor Gray
        $header = [PmcHeader]::new("Widget Demo")
        $header.SetIcon("⚡")
        $header.SetBreadcrumb(@("Home", "Development", "Widget Test"))
        $header.SetContext("Phase 1 Complete")

        # Apply layout
        $headerRect = $layout.GetRegion('Header', $termWidth, $termHeight)
        $header.SetPosition($headerRect.X, $headerRect.Y)
        $header.SetSize($headerRect.Width, $headerRect.Height)

        Write-Host "Header configured: X=$($header.X), Y=$($header.Y), W=$($header.Width), H=$($header.Height)" -ForegroundColor Gray

        # Create content panel
        Write-Host "Creating content panel..." -ForegroundColor Gray
        $panel = [PmcPanel]::new("Test Panel", 60, 12)
        $panel.SetBorderStyle('rounded')
        $panel.SetPadding(2)
        $panel.SetContent(@"
PMC Widget Library - Phase 1 Implementation

[OK] PmcWidget base class
[OK] PmcThemeManager (hybrid PMC + SpeedTUI)
[OK] PmcLayoutManager (named regions)
[OK] PmcMenuBar (with dropdowns)
[OK] PmcHeader (title, breadcrumb, context)
[OK] PmcFooter (keyboard shortcuts)
[OK] PmcStatusBar (3-section status)
[OK] PmcPanel (borders, padding, content)

All core widgets operational!
"@, 'left')

        # Position panel in content area
        $contentRect = $layout.GetRegion('Content', $termWidth, $termHeight)
        $panel.SetPosition($contentRect.X + 2, $contentRect.Y + 1)

        Write-Host "Panel configured: X=$($panel.X), Y=$($panel.Y), W=$($panel.Width), H=$($panel.Height)" -ForegroundColor Gray

        # Create footer
        Write-Host "Creating footer..." -ForegroundColor Gray
        $footer = [PmcFooter]::new()
        $footer.AddShortcut("F10", "Menu")
        $footer.AddShortcut("↑↓←→", "Navigate")
        $footer.AddShortcut("Enter", "Select")
        $footer.AddShortcut("Esc", "Exit")

        # Apply layout
        $footerRect = $layout.GetRegion('Footer', $termWidth, $termHeight)
        $footer.SetPosition($footerRect.X, $footerRect.Y)
        $footer.SetSize($footerRect.Width, $footerRect.Height)

        Write-Host "Footer configured: X=$($footer.X), Y=$($footer.Y), W=$($footer.Width), H=$($footer.Height)" -ForegroundColor Gray

        # Create status bar
        Write-Host "Creating status bar..." -ForegroundColor Gray
        $statusBar = [PmcStatusBar]::new()
        $statusBar.SetLeftText("[OK] Phase 1 Complete")
        $statusBar.SetCenterText("DEMO MODE")
        $statusBar.SetRightText((Get-Date).ToString("HH:mm:ss"))

        # Apply layout
        $statusBarRect = $layout.GetRegion('StatusBar', $termWidth, $termHeight)
        $statusBar.SetPosition($statusBarRect.X, $statusBarRect.Y)
        $statusBar.SetSize($statusBarRect.Width, $statusBarRect.Height)

        Write-Host "Status bar configured: X=$($statusBar.X), Y=$($statusBar.Y), W=$($statusBar.Width), H=$($statusBar.Height)" -ForegroundColor Gray

        # Clear screen and render
        Write-Host "`nRendering screen..." -ForegroundColor Cyan
        Write-Host "`e[2J`e[H"  # Clear screen and home cursor
        Write-Host "`e[?25l"    # Hide cursor

        # Render all widgets
        Write-Host "Rendering menu bar..." -ForegroundColor Gray
        $menuBarOutput = $menuBar.OnRender()
        Write-Host $menuBarOutput -NoNewline

        Write-Host "Rendering header..." -ForegroundColor Gray
        $headerOutput = $header.OnRender()
        Write-Host $headerOutput -NoNewline

        Write-Host "Rendering panel..." -ForegroundColor Gray
        $panelOutput = $panel.OnRender()
        Write-Host $panelOutput -NoNewline

        Write-Host "Rendering footer..." -ForegroundColor Gray
        $footerOutput = $footer.OnRender()
        Write-Host $footerOutput -NoNewline

        Write-Host "Rendering status bar..." -ForegroundColor Gray
        $statusBarOutput = $statusBar.OnRender()
        Write-Host $statusBarOutput -NoNewline

        Write-Host "`e[?25h"  # Show cursor

        # Position cursor at bottom for messages
        Write-Host "`e[$(($termHeight - 5));1H"
        Write-Host "`n`n[OK] All widgets rendered successfully!" -ForegroundColor Green
        Write-Host "Press F10 to activate menu bar (not fully wired yet)" -ForegroundColor Yellow
        Write-Host "Press Q to quit" -ForegroundColor Yellow

        # Simple event loop (for demonstration)
        Write-Host "`nWaiting for input..." -ForegroundColor Gray
        $continue = $true
        while ($continue) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                switch ($key.Key) {
                    'F10' {
                        Write-Host "`e[$(($termHeight - 3));1H"
                        Write-Host "F10 pressed - Menu bar would activate here" -ForegroundColor Cyan
                        $menuBar.Activate()
                        # Re-render menu bar in active state
                        $menuBarOutput = $menuBar.OnRender()
                        Write-Host $menuBarOutput -NoNewline
                    }
                    'Q' {
                        $continue = $false
                    }
                    'Escape' {
                        if ($menuBar.IsActive) {
                            $menuBar.Deactivate()
                            # Re-render menu bar in inactive state
                            $menuBarOutput = $menuBar.OnRender()
                            Write-Host $menuBarOutput -NoNewline
                        } else {
                            $continue = $false
                        }
                    }
                    default {
                        # Pass to menu bar if active
                        if ($menuBar.IsActive) {
                            $handled = $menuBar.HandleKeyPress($key)
                            if ($handled) {
                                # Re-render menu bar
                                $menuBarOutput = $menuBar.OnRender()
                                Write-Host $menuBarOutput -NoNewline
                            }
                        }
                    }
                }
            }
            Start-Sleep -Milliseconds 50
        }

        # Cleanup
        Write-Host "`e[2J`e[H"  # Clear screen
        Write-Host "`e[?25h"    # Show cursor
        Write-Host "`nTest complete. Widget library validated!" -ForegroundColor Green

    } catch {
        Write-Host "`e[?25h"  # Show cursor on error
        Write-Host "`nError in test screen: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        throw
    }
}

<#
.SYNOPSIS
Quick validation test - just creates widgets without rendering

.DESCRIPTION
Tests widget instantiation and configuration without full rendering
#>
function Test-WidgetCreation {
    Write-Host "Testing widget creation..." -ForegroundColor Cyan

    try {
        Write-Host "  Creating PmcMenuBar..." -ForegroundColor Gray
        $menuBar = [PmcMenuBar]::new()
        Write-Host "    [OK] PmcMenuBar created" -ForegroundColor Green

        Write-Host "  Creating PmcHeader..." -ForegroundColor Gray
        $header = [PmcHeader]::new("Test")
        Write-Host "    [OK] PmcHeader created" -ForegroundColor Green

        Write-Host "  Creating PmcFooter..." -ForegroundColor Gray
        $footer = [PmcFooter]::new()
        Write-Host "    [OK] PmcFooter created" -ForegroundColor Green

        Write-Host "  Creating PmcStatusBar..." -ForegroundColor Gray
        $statusBar = [PmcStatusBar]::new()
        Write-Host "    [OK] PmcStatusBar created" -ForegroundColor Green

        Write-Host "  Creating PmcPanel..." -ForegroundColor Gray
        $panel = [PmcPanel]::new("Test Panel")
        Write-Host "    [OK] PmcPanel created" -ForegroundColor Green

        Write-Host "  Creating PmcLayoutManager..." -ForegroundColor Gray
        $layout = [PmcLayoutManager]::new()
        Write-Host "    [OK] PmcLayoutManager created" -ForegroundColor Green

        Write-Host "  Creating PmcThemeManager..." -ForegroundColor Gray
        $theme = [PmcThemeManager]::GetInstance()
        Write-Host "    [OK] PmcThemeManager created" -ForegroundColor Green

        Write-Host "`n[OK] All widget classes validated!" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "`n[ERROR] Widget creation failed: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        return $false
    }
}

# Functions exported automatically in PowerShell 5.1+