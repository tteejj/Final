# Enums.ps1 - Core primitives for FluxTUI

enum ActionType {
    NONE
    
    # System
    APP_INIT
    APP_EXIT
    LOAD_DATA
    SAVE_DATA
    
    # Generic Data CRUD
    ADD_ITEM    # { Type, Data }
    UPDATE_ITEM # { Type, Id, Changes }
    DELETE_ITEM # { Type, Id }
    
    # Navigation / View State
    SET_FOCUS      # { PanelName }
    SET_VIEW       # { ViewName }
    SET_SELECTION  # { PanelName, Index }
    NEXT_PANEL
    PREV_PANEL
    TOGGLE_ZOOM
    
    # Interaction
    TOGGLE_MODE    # Normal <-> Insert
    INPUT_KEY      # { Key, Modifiers }
    
    # Editing
    START_EDIT     # { RowId, Type, Values }
    CANCEL_EDIT
    
    # Time Tracking
    START_TIMER    # { TaskId }
    STOP_TIMER     # { TaskId }
}

enum KeyCode {
    Unknown = 0
    Enter = 13
    Escape = 27
    Space = 32
    Backspace = 8
    Tab = 9
    UpArrow = 38
    DownArrow = 40
    LeftArrow = 37
    RightArrow = 39
    Delete = 46
    Home = 36
    End = 35
    PageUp = 33
    PageDown = 34
    F1 = 112
    F2 = 113
    F3 = 114
    F4 = 115
    F5 = 116
    F6 = 117
    F7 = 118
    F8 = 119
    F9 = 120
    F10 = 121
    F11 = 122
    F12 = 123
}

class Colors {
    # ALL colors are theme-derived - no hardcoded fallbacks
    # These are default values that get overwritten by theme loading
    
    # Semantic UI Colors (use these instead of basic colors)
    static [int] $Title        = 0x00FFFF  # For headers, column titles (replaces Cyan)
    static [int] $Muted        = 0x808080  # For secondary text, hints (replaces Gray)
    static [int] $Bright       = 0xFFFFFF  # For emphasis, highlights (replaces White)
    static [int] $Cursor       = 0xFFFFFF  # For cursor/caret display
    static [int] $CursorBg     = 0x000000  # Background behind cursor
    
    # Core Theme Colors
    static [int] $Background     = 0x1E1E1E
    static [int] $PanelBg        = 0x252526
    static [int] $PanelBorder    = 0x3E3E42
    static [int] $Foreground     = 0xD4D4D4
    static [int] $Accent         = 0x007ACC
    static [int] $Success        = 0x4EC9B0
    static [int] $Warning        = 0xDCDCAA
    static [int] $Error          = 0xF44747
    static [int] $SelectionBg    = 0x264F78
    static [int] $SelectionFg    = 0xFFFFFF
}