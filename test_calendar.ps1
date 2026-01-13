
# Test Calendar Screen Loader

try {
    Write-Host "Defining mocks..."
    
    # Mock RenderCache
    class RenderCache {
        static [RenderCache] GetInstance() { return [RenderCache]::new() }
        [void] Clear() {}
    }
    
    # Mock PmcThemeEngine
    class PmcThemeEngine {
        static [PmcThemeEngine] GetInstance() { return [PmcThemeEngine]::new() }
        [int] GetForegroundInt([string]$role) { return 0 }
        [int] GetBackgroundInt([string]$role, [int]$w, [int]$i) { return 0 }
    }
    
    # Mock Widgets for PmcScreen
    class PmcMenuBar { 
        [void] AddMenu($t,$h,$i) {} 
        [void] Initialize($e) {}
        [void] SetPosition($x,$y) {}
        [void] SetSize($w,$h) {}
    }
    class PmcHeader { 
        PmcHeader($t) {} 
        [void] Initialize($e) {}
        [void] SetPosition($x,$y) {}
        [void] SetSize($w,$h) {}
        [void] SetBreadcrumb($b) {}
    }
    class PmcFooter { 
        [void] AddShortcut($k,$l) {} 
        [void] ClearShortcuts() {}
        [void] Initialize($e) {}
        [void] SetPosition($x,$y) {}
        [void] SetSize($w,$h) {}
    }
    class PmcStatusBar { 
        [void] SetLeftText($t) {} 
        [void] Initialize($e) {}
        [void] SetPosition($x,$y) {}
        [void] SetSize($w,$h) {}
    }

    Write-Host "Loading dependencies..."
    . "/home/teej/ztest/module/Pmc.Strict/consoleui/ZIndex.ps1"
    
    # Need to load PmcScreen but it uses PmcWidget too.
    # Logic: PmcWidget -> PmcScreen
    
    # Oops, PmcWidget uses PmcThemeEngine too (mocked above)
    . "/home/teej/ztest/module/Pmc.Strict/consoleui/widgets/PmcWidget.ps1"
    
     # Mock PmcLayoutManager if needed or load it. It's a class.
    . "/home/teej/ztest/module/Pmc.Strict/consoleui/layout/PmcLayoutManager.ps1" 

    . "/home/teej/ztest/module/Pmc.Strict/consoleui/PmcScreen.ps1"

    Write-Host "Dot-sourcing CalendarScreen.ps1..."
    . "/home/teej/ztest/module/Pmc.Strict/consoleui/screens/CalendarScreen.ps1"

    Write-Host "Attempting to create CalendarScreen instance..."
    $container = [PSCustomObject]@{
        Resolve = { param($name) return $null }
    }
    
    # Try constructor with container
    $screen = New-Object CalendarScreen -ArgumentList $container
    
    if ($screen) {
        Write-Host "SUCCESS: CalendarScreen created."
        Write-Host "Screen Title: $($screen.ScreenTitle)"
    } else {
        Write-Host "FAILED: CalendarScreen is null."
    }

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host "Stack Trace: $($_.ScriptStackTrace)"
}
