@{
    # Menu item definitions for PMC TUI
    # Format: ScreenName = @{ Menu = 'MenuName'; Label = 'Display Label'; Hotkey = 'X'; Order = 10 }

    # ===== TOOLS MENU =====
    'CommandLibraryScreen' = @{
        Menu = 'Tools'
        Label = 'Command Library'
        Hotkey = 'L'
        Order = 10
        ScreenFile = 'CommandLibraryScreen.ps1'
    }

    'NotesMenuScreen' = @{
        Menu = 'Tools'
        Label = 'Notes'
        Hotkey = 'N'
        Order = 20
        ScreenFile = 'NotesMenuScreen.ps1'
    }

    'ChecklistsLauncherScreen' = @{
        Menu = 'Tools'
        Label = 'Checklists'
        Hotkey = 'C'
        Order = 25
        ScreenFile = 'ChecklistsLauncherScreen.ps1'
    }

    'ChecklistTemplatesFolderScreen' = @{
        Menu = 'Tools'
        Label = 'Checklist Templates'
        Hotkey = 'H'
        Order = 30
        ScreenFile = 'ChecklistTemplatesFolderScreen.ps1'
    }

    'ExcelImportProfileManagerScreen' = @{
        Menu = 'Tools'
        Label = 'Excel Import Profiles'
        Hotkey = 'I'
        Order = 40
        ScreenFile = 'ExcelImportProfileManagerScreen.ps1'
    }

    'TextExportProfileManagerScreen' = @{
        Menu = 'Tools'
        Label = 'T2020 Export Profiles'
        Hotkey = 'E'
        Order = 45
        ScreenFile = 'TextExportProfileManagerScreen.ps1'
    }

    'CalendarScreen' = @{
        Menu = 'Tools'
        Label = 'Calendar'
        Hotkey = 'A'
        Order = 50
        ScreenFile = 'CalendarScreen.ps1'
    }

    # ===== PROJECTS MENU =====
    'ProjectListScreen' = @{
        Menu = 'Projects'
        Label = 'Project List'
        Hotkey = 'L'
        Order = 10
        ScreenFile = 'ProjectListScreen.ps1'
    }

    # ProjectInfoScreenV4 removed from menu - accessed via 'V' key in ProjectListScreen
    # Requires a project to be selected, so should not be directly accessible from menu

    'ExcelImportScreen' = @{
        Menu = 'Projects'
        Label = 'Import from Excel'
        Hotkey = 'I'
        Order = 40
        ScreenFile = 'ExcelImportScreen.ps1'
    }

    'ExcelProfileManagerScreen' = @{
        Menu = 'Projects'
        Label = 'Excel Profiles'
        Hotkey = 'M'
        Order = 50
        ScreenFile = 'ExcelProfileManagerScreen.ps1'
    }

    # ===== TASKS MENU =====
    'TaskListScreen_Default' = @{
        Menu = 'Tasks'
        Label = 'Task List'
        Hotkey = 'L'
        Order = 5
        ScreenFile = 'TaskListScreen.ps1'
    }



    # KanbanScreenV2 removed - archived 2025-12-17

    # ===== TIME MENU =====
    'TimeListScreen' = @{
        Menu = 'Time'
        Label = 'Time Tracking'
        Hotkey = 'T'
        Order = 5
        ScreenFile = 'TimeListScreen.ps1'
    }

    'WeeklyTimeReportScreen' = @{
        Menu = 'Time'
        Label = 'Weekly Report'
        Hotkey = 'W'
        Order = 10
        ScreenFile = 'WeeklyTimeReportScreen.ps1'
    }

    # TimeReportScreen removed - functionality merged into TimeListScreen and WeeklyTimeReportScreen

    # ===== OPTIONS MENU =====
    'ThemeEditorScreen' = @{
        Menu = 'Options'
        Label = 'Theme Editor'
        Hotkey = 'T'
        Order = 10
        ScreenFile = 'ThemeEditorScreen.ps1'
    }

    'SettingsScreen' = @{
        Menu = 'Options'
        Label = 'Settings'
        Hotkey = 'S'
        Order = 20
        ScreenFile = 'SettingsScreen.ps1'
    }

    # ===== HELP MENU =====
    'HelpViewScreen' = @{
        Menu = 'Help'
        Label = 'Help'
        Hotkey = 'H'
        Order = 10
        ScreenFile = 'HelpViewScreen.ps1'
    }
}
