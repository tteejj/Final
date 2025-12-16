# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **PowerShell TUI (Terminal User Interface) application** for project management and task tracking. The system uses the **SpeedTUI rendering engine** with VT100 escape codes to create interactive screens, forms, and dashboards. It's a class-based OOP application running in PowerShell 7+.

### Core Technologies
- **Language**: PowerShell 7+ (not a traditional shell, but a full OOP scripting platform)
- **Rendering**: SpeedTUI engine (custom ANSI/VT100 rendering)
- **Architecture**: Class-based OOP with dependency injection (ServiceContainer pattern)
- **Entry Point**: `/home/teej/ztest/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1`

## Directory Structure

```
/home/teej/ztest/
├── module/Pmc.Strict/consoleui/          # Main application code
│   ├── Start-PmcTUI.ps1                  # Entry point - loads all dependencies
│   ├── PmcApplication.ps1                # Main app wrapper (render engine, event loop, screen stack)
│   ├── PmcScreen.ps1                     # Base screen class for all screens
│   ├── ServiceContainer.ps1              # Dependency injection container
│   ├── ClassLoader.ps1                   # Smart auto-discovery class loader
│   ├── DepsLoader.ps1                    # Loads external dependencies
│   ├── SpeedTUILoader.ps1                # Initializes SpeedTUI engine
│   │
│   ├── base/                             # Base screen templates
│   │   ├── StandardDashboard.ps1         # Dashboard base
│   │   ├── StandardFormScreen.ps1        # Form base
│   │   ├── StandardListScreen.ps1        # List/table base
│   │   └── TabbedScreen.ps1              # Tabbed interface base
│   │
│   ├── screens/                          # Application screens (40+ screens)
│   │   ├── ProjectInfoScreenV4.ps1       # Project editor (main screen)
│   │   ├── KanbanScreenV2.ps1            # Kanban/status board
│   │   ├── TimeListScreen.ps1            # Time tracking
│   │   ├── NoteEditorScreen.ps1          # Notes
│   │   └── [30+ other screens]
│   │
│   ├── services/                         # Business logic services
│   │   ├── TaskStore.ps1                 # Task persistence (save/load)
│   │   ├── MenuRegistry.ps1              # Dynamic menu system
│   │   ├── NoteService.ps1               # Note management
│   │   ├── ChecklistService.ps1          # Checklist operations
│   │   ├── ExcelMappingService.ps1       # Excel import/export
│   │   └── PreferencesService.ps1        # User settings
│   │
│   ├── helpers/                          # Utility helpers
│   │   ├── Constants.ps1                 # Global constants (keys, colors, messages)
│   │   ├── GapBuffer.ps1                 # Efficient text editing (cursor tracking)
│   │   ├── DataBindingHelper.ps1         # Data binding logic
│   │   ├── ThemeHelper.ps1               # Theme/color management
│   │   ├── LinuxKeyHelper.ps1            # Linux terminal key codes
│   │   ├── ValidationHelper.ps1          # Input validation
│   │   └── [other helpers]
│   │
│   ├── layout/                           # Layout components
│   │   └── PmcLayoutManager.ps1          # Screen layout calculations
│   │
│   ├── deps/                             # Business domain classes
│   │   ├── Project.ps1                   # Project model
│   │   ├── PmcTemplate.ps1               # Template model
│   │   └── HelpContent.ps1               # Help system
│   │
│   ├── tests/                            # Test scripts
│   │   ├── test-tui.ps1                  # Main test suite
│   │   ├── verify-tui.ps1                # Quick verification
│   │   ├── test-comprehensive.ps1        # Full integration tests
│   │   └── [other test files]
│   │
│   └── .claude/                          # Claude AI assistant config (internal)
│
├── lib/SpeedTUI/                         # SpeedTUI rendering engine (external dependency)
│   ├── SpeedTUI.ps1                      # Core engine
│   ├── Core/                             # Core components
│   └── Components/                       # UI widgets (Button, Input, etc.)
│
└── config.json                           # Display theme configuration
```

## Key Architectural Concepts

### 1. Application Initialization Pipeline
The startup sequence in `Start-PmcTUI.ps1`:
1. **Logging Setup** - Optional debug logging (disabled by default for performance)
2. **ClassLoader** - Auto-discovers and loads all .ps1 files with dependency resolution
3. **SpeedTUI Engine** - Initializes rendering engine and widgets
4. **ServiceContainer** - Creates dependency injection container with business services
5. **PmcApplication** - Instantiates main application wrapper
6. **Event Loop** - Starts input handling and screen rendering cycle

### 2. Screen System
- **PmcScreen** (`PmcScreen.ps1`) - Base class for all screens
  - Handles rendering, input, and navigation
  - Manages component lifecycle
  - Supports undo/redo where needed

- **Base Screen Templates** - Common patterns in `base/`:
  - `StandardListScreen` - Tables/lists with inline editing
  - `StandardFormScreen` - Forms with validation
  - `StandardDashboard` - Summary dashboards
  - `TabbedScreen` - Multi-tab interfaces

- **Dynamic Screen Navigation** - `MenuRegistry.ps1` manages menu structure and lazy-loads screens

### 3. Rendering Engine
- **SpeedTUI** - Custom ANSI/VT100 rendering engine (in `/lib/SpeedTUI/`)
- **Rendering Modes**:
  - `OptimizedRenderEngine` - Default, uses dirty flag optimization
  - `HybridRenderEngine` - Fallback for troubleshooting
- **Key Feature** - Dirty flag pattern (only redraw when `$IsDirty = $true`)

### 4. Data Persistence
- **TaskStore** (`services/TaskStore.ps1`) - Central data persistence
  - Loads `tasks.json` at startup
  - Saves with timestamped backups (keeps last 5)
  - 6-phase save logging for debugging
  - In-memory task cache with persistence verification

### 5. Dependency Injection
- **ServiceContainer** (`ServiceContainer.ps1`) - IoC container
  - Registers singleton and transient services
  - Used by screens to access TaskStore, MenuRegistry, etc.
  - Example: `$taskStore = $container.Get('TaskStore')`

### 6. Class Loading System
- **ClassLoader** (`ClassLoader.ps1`) - Smart auto-discovery
  - Walks directory trees for .ps1 files
  - Respects priority ordering (lower = loaded first)
  - Multi-pass retry logic (handles dependency issues)
  - Detects circular dependencies
  - Auto-excludes Test*.ps1 files
  - Logs detailed diagnostics

## Common Development Tasks

### Starting the Application
```powershell
cd /home/teej/ztest/module/Pmc.Strict/consoleui
pwsh ./Start-PmcTUI.ps1

# Enable debug logging (performance cost)
pwsh ./Start-PmcTUI.ps1 -DebugLog -LogLevel 2
```

### Running Tests
```powershell
# Quick verification (fast, ~5 seconds)
pwsh ./tests/verify-tui.ps1

# Full integration test suite
pwsh ./tests/test-tui.ps1

# Comprehensive testing with logging
pwsh ./tests/test-comprehensive.ps1

# Memory profiling
pwsh ./tests/profile-memory.ps1
```

### Adding a New Screen
1. Create new file in `screens/` (e.g., `MyNewScreen.ps1`)
2. Inherit from base class: `class MyNewScreen : StandardListScreen {}`
3. Implement required methods: `[void] Render()`, `[void] HandleInput($key)`
4. Register in `MenuRegistry.ps1` using lazy-loading pattern
5. ClassLoader will automatically discover and load it

### Adding a Service
1. Create in `services/` as a PowerShell class
2. Register in `Start-PmcTUI.ps1` via ServiceContainer
3. Make it a singleton if it manages shared state (like TaskStore)

### Debugging Rendering Issues
1. Enable debug logging: `-LogLevel 3`
2. Check logs in `.pmc-data/logs/`
3. Use `verify-tui.ps1` to isolate problems
4. Review `SpeedTUI.ps1` for rendering state

## Architecture Notes

### Scope Isolation (Important!)
PowerShell has scope isolation issues with closures. Key patterns to follow:
- Classes loaded at startup must be in module scope before MenuRegistry closures use them
- Use `$PSScriptRoot` for path resolution ONLY outside of closures
- ClassLoader handles this automatically - use it instead of manual dot-sourcing

### Performance Considerations
- Debug logging is expensive - disabled by default
- Rendering uses dirty flag pattern - only redraw when needed
- Task loading is deferred on startup for speed
- Avoid large loops in render methods - they're called every frame

### Testing Patterns
- Lightweight unit tests in `tests/` prefixed with `test-`
- Can import classes directly without full app startup
- Use `ServiceContainer` to inject mocks for isolated testing

## Important Files to Know

| File | Purpose |
|------|---------|
| `Start-PmcTUI.ps1` | Entry point & initialization (660+ lines) |
| `PmcApplication.ps1` | Main app (event loop, render cycle) |
| `PmcScreen.ps1` | Base screen class |
| `ServiceContainer.ps1` | Dependency injection |
| `ClassLoader.ps1` | Auto-discovery class loading |
| `services/TaskStore.ps1` | Task data persistence (1400+ lines) |
| `services/MenuRegistry.ps1` | Dynamic menu system |
| `Constants.ps1` | Global config (keys, colors, messages) |
| `lib/SpeedTUI/SpeedTUI.ps1` | Rendering engine |

## Known Issues & Considerations

### Resolved (see ISSUES_FOUND.md for history)
- Screen lazy-loading scope isolation ✓
- Missing widget loading ✓
- Brittle hardcoded file lists ✓

### Active Considerations
- Terminal size changes may require resize handling
- Complex screens with many components may need performance optimization
- Test file pollution - ClassLoader auto-excludes Test*.ps1 but be explicit if needed

## Related Documentation

- `IMPROVEMENTS.md` - Recent production hardening changes
- `ISSUES_FOUND.md` - Technical analysis of past issues and solutions
- `AUTO-ACCEPT-GUIDE.md` - Testing and verification procedures
- `TESTING-SUMMARY.md` - Test coverage overview
- `screens/KANBAN_V2_README.md` - Kanban board screen documentation
