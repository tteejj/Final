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

    'TaskListScreen_Today' = @{
        Menu = 'Tasks'
        Label = 'Today'
        Hotkey = 'Y'
        Order = 10
        ScreenFile = 'TaskListScreen.ps1'
        ViewMode = 'today'
    }

    'TaskListScreen_Tomorrow' = @{
        Menu = 'Tasks'
        Label = 'Tomorrow'
        Hotkey = 'T'
        Order = 15
        ScreenFile = 'TaskListScreen.ps1'
        ViewMode = 'tomorrow'
    }

    'TaskListScreen_Week' = @{
        Menu = 'Tasks'
        Label = 'Week View'
        Hotkey = 'W'
        Order = 20
        ScreenFile = 'TaskListScreen.ps1'
        ViewMode = 'week'
    }

    'TaskListScreen_Upcoming' = @{
        Menu = 'Tasks'
        Label = 'Upcoming'
        Hotkey = 'U'
        Order = 25
        ScreenFile = 'TaskListScreen.ps1'
        ViewMode = 'upcoming'
    }

    'TaskListScreen_Overdue' = @{
        Menu = 'Tasks'
        Label = 'Overdue'
        Hotkey = 'O'
        Order = 30
        ScreenFile = 'TaskListScreen.ps1'
        ViewMode = 'overdue'
    }

    'TaskListScreen_NextActions' = @{
        Menu = 'Tasks'
        Label = 'Next Actions'
        Hotkey = 'N'
        Order = 35
        ScreenFile = 'TaskListScreen.ps1'
        ViewMode = 'nextactions'
    }

    'TaskListScreen_NoDate' = @{
        Menu = 'Tasks'
        Label = 'No Due Date'
        Hotkey = 'D'
        Order = 40
        ScreenFile = 'TaskListScreen.ps1'
        ViewMode = 'noduedate'
    }

    'TaskListScreen_Month' = @{
        Menu = 'Tasks'
        Label = 'Month View'
        Hotkey = 'M'
        Order = 45
        ScreenFile = 'TaskListScreen.ps1'
        ViewMode = 'month'
    }

    'TaskListScreen_Agenda' = @{
        Menu = 'Tasks'
        Label = 'Agenda View'
        Hotkey = 'A'
        Order = 50
        ScreenFile = 'TaskListScreen.ps1'
        ViewMode = 'agenda'
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

    'TimeReportScreen' = @{
        Menu = 'Time'
        Label = 'Time Report'
        Hotkey = 'R'
        Order = 20
        ScreenFile = 'TimeReportScreen.ps1'
    }

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
