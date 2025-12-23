
# reproduce_tabs.ps1

$modulePath = "/home/teej/ztest/module/Pmc.Strict/Pmc.Strict.psd1"
Import-Module $modulePath -Force

# Mock dependencies
$global:PmcTuiLogFile = "/home/teej/ztest/data/logs/repro_debug.log"
$global:PmcContainer = [PmcContainer]::new()

# Register TaskStore mock or use real one? Real one is fine if it doesn't need UI.
# But ProjectInfoScreenV4 needs a container with TaskStore.

# Load required scripts manually if module doesn't export classes (it should)
# But we need to make sure the classes are loaded.
# Load dependencies in order
. "/home/teej/ztest/lib/SpeedTUI/Core/Internal/PerformanceCore.ps1"
. "/home/teej/ztest/lib/SpeedTUI/Core/NullCheck.ps1"
. "/home/teej/ztest/lib/SpeedTUI/Core/Component.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/src/PmcThemeEngine.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/layout/PmcLayoutManager.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/ZIndex.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/widgets/PmcWidget.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/widgets/TabPanel.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/widgets/TextInput.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/services/TaskStore.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/widgets/ProjectPicker.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/widgets/InlineEditor.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/ServiceContainer.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/PmcScreen.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/base/TabbedScreen.ps1"
. "/home/teej/ztest/module/Pmc.Strict/consoleui/screens/ProjectInfoScreenV4.ps1"

# Mock TaskStore if needed, or just let it fail gracefully (LoadData handles null project)
# We just want to see if tabs are built.

Write-Host "Instantiating ProjectInfoScreenV4..."
$container = [ServiceContainer]::new()
# Mock TaskStore?
# $container.Register('TaskStore', $mockTaskStore)
$screen = [ProjectInfoScreenV4]::new($container)
$screen.ProjectName = "TestProject"

Write-Host "Calling LoadData..."
$screen.LoadData()

Write-Host "Tab count: $($screen.TabPanel.Tabs.Count)"

if ($screen.TabPanel.Tabs.Count -gt 0) {
    Write-Host "SUCCESS: Tabs created."
    $screen.TabPanel.Tabs | ForEach-Object { Write-Host " - Tab: $($_.Name)" }
} else {
    Write-Host "FAILURE: No tabs created."
}
