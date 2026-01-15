# Consoleui Architecture Review (2026-01-01)

## Standalone Conversion Complete
Consoleui no longer depends on `Import-Module Pmc.Strict`. All data access goes through `DataService.ps1`.

---

## Remaining Legacy Items

### Get-Module References (Fixed)
- `TaskStore._CreatePersistentBackup()` - now uses DataService
- `ProjectInfoScreenV4` debug logging - removed module call

---

## Complexity Observations

### 1. TaskStore (1820 lines)
Full singleton with thread-safe locks, validation, rollback for simple JSON CRUD.
Most complexity is unused since UI is single-threaded.

### 2. Singletons (12+ classes)
All services use `::GetInstance()` pattern. Works fine, just verbose.

### 3. Theme State in Multiple Places
- config.json → PmcThemeManager → PmcThemeEngine → widget caches
- Theme changes must invalidate caches in correct order

### 4. ServiceContainer DI
Registration/resolution for services that are already singletons.

---

## Benefits Assessment

| Change | Code Cleanliness | Performance | Reliability | Worth Doing? |
|--------|-----------------|-------------|-------------|--------------|
| Fix Get-Module calls | ✓ | - | ✓ Prevents errors if module unloaded | **Yes** |
| Simplify TaskStore | ✓ | Maybe 5-10ms faster startup | Minor | **No** - works fine now |
| Remove ServiceContainer | ✓ | - | - | Low priority |
| Consolidate theme state | ✓ | - | ✓ Fewer race conditions | Maybe later |

### Bottom Line

The current architecture works. The complexity is overkill for the problem size, but it's **stable code**. 
Refactoring would provide no meaningful runtime benefit - just cleaner code for future maintenance.

**Exception:** If theme hot reload keeps having issues, consolidating theme state would help. But that's reactive work, not proactive.
