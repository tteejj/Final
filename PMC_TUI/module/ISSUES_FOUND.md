# Issues Found - December 8, 2024 Log Analysis

## Critical Errors Discovered

### 1. Screen Navigation Failures (CRITICAL)

**Logs:** `pmc-tui-20251208-221642.log`

**Affected Screens:**
- **TimeListScreen** - Failed at 22:16:55
  - Error: `Unable to find type [TimeEntryDetailDialog]` at line 520
  - Error: `Unable to find type [PmcThemeManager]` at line 536

- **ThemeEditorScreen** - Failed at 22:16:51
  - Error: `Unable to find type [PmcThemeManager]` at line 356

- **Likely affected** (uses PmcThemeManager):
  - ExcelImportScreen

**Root Cause:**
PowerShell scope isolation - Classes loaded at startup in parent scope aren't accessible inside MenuRegistry factory closures when screens are lazy-loaded on menu navigation.

**Impact:**
- Cannot access Time menu screens (Time Tracking, Weekly Report, Time Report)
- Cannot access Tools menu screens (Notes, Checklists, Command Library, Templates)
- Cannot access Options menu screens (Theme Editor, Settings)
- Application crashes when trying to navigate to these screens

### 2. Widget Loading Incompleteness

**Current State:**
- Hardcoded list loads only **11 of 19** production widgets
- **8 missing widgets** not loaded at startup:
  - PmcDialog.ps1
  - PmcFooter.ps1 *(loaded separately at line 143)*
  - PmcHeader.ps1 *(loaded separately at line 142)*
  - PmcMenuBar.ps1 *(loaded separately at line 141)*
  - PmcPanel.ps1 *(loaded separately at line 140)*
  - PmcStatusBar.ps1 *(loaded separately at line 144)*
  - PmcWidget.ps1 *(loaded separately at line 139)*
  - SimpleFilePicker.ps1

**Impact:**
- SimpleFilePicker required by ProjectInfoScreenV4 (currently uses lazy-loading workaround)
- PmcDialog might be needed by future screens
- Other widgets were loaded separately but in brittle hardcoded manner

### 3. Loader Architecture Brittleness

**Problems Identified:**
1. **Hardcoded file lists** - Requires manual maintenance when adding new files
2. **Scope isolation** - `$PSScriptRoot` is null in scriptblock closures
3. **Silent failures** - Dot-sourcing with relative paths fails silently when `$PSScriptRoot` is undefined
4. **No dependency tracking** - No guarantee dependencies load before dependents
5. **No retry logic** - Transient dependency issues cause permanent failures
6. **Test file pollution** - Must manually exclude test files

**Code Locations:**
- Start-PmcTUI.ps1:179-191 - Hardcoded widget list
- MenuRegistry.ps1:242 - Dot-sources screens inside closure (fails due to scope)
- Multiple screen files - Attempt to dot-source dependencies with `$PSScriptRoot` (fails in closures)

## Other Issues Not Yet Investigated

### User-Reported Issues (Not in These Logs):

1. **Inline Editor Input Issues:**
   - Typing not responding when inline editor active in project screen
   - ESC key not exiting the editor
   - *Not observed in the analyzed logs - needs longer session capture*

2. **General Screen Access:**
   - User reported inability to access "screens, tools, time, and other menus"
   - Confirmed for Time and Tools menus
   - Need to verify all menu items work after fix

## Solutions Implemented

### 1. ClassLoader.ps1 (NEW)

Smart auto-discovery class loader with:
- Directory walking - Auto-discovers .ps1 files
- Priority-based ordering - Lower priority = loaded first
- Multi-pass loading - Retries failed files up to 3 times
- Dependency resolution - Detects "Unable to find type" errors and retries
- Test file exclusion - Automatically skips Test*.ps1 files
- Comprehensive logging - Detailed diagnostics for troubleshooting
- Circular dependency detection - Prevents infinite retry loops

**Location:** `og_transport/working/module/Pmc.Strict/consoleui/ClassLoader.ps1`

### 2. Start-PmcTUI.ps1 Updates

Replaced brittle hardcoded loading with ClassLoader:

**Before:**
- Lines 106-229: ~120 lines of hardcoded file lists and manual loading

**After:**
- Lines 106-181: ~75 lines using ClassLoader auto-discovery
- Loads directories in priority order:
  - Priority 5: theme
  - Priority 10: layout
  - Priority 20: widgets (ALL 19 files auto-discovered)
  - Priority 30: base classes
  - Priority 40: services
  - Priority 50: helpers

**Benefits:**
- All widgets now loaded automatically
- All classes available in global scope (fixes MenuRegistry factory issue)
- New files automatically discovered - no code changes needed
- Test files automatically excluded
- Detailed diagnostics via `$global:PmcClassLoaderStats`

## Expected Outcomes

### Fixed:
✅ TimeListScreen should now be accessible (TimeEntryDetailDialog + PmcThemeManager available)
✅ ThemeEditorScreen should now be accessible (PmcThemeManager available)
✅ All Time menu items should work (Time Tracking, Weekly Report, Time Report)
✅ All Tools menu items should work (Notes, Checklists, Command Library, Templates)
✅ All Options menu items should work (Theme Editor, Settings)
✅ SimpleFilePicker available for ProjectInfoScreenV4
✅ No more manual widget list maintenance needed

### Still To Investigate:
⏳ Inline editor ESC/typing issues (not visible in current logs)
⏳ Any other screen-specific navigation issues

## Testing Checklist

After deploying these changes, verify:

1. **Menu Navigation:**
   - [ ] Time → Time Tracking (was failing)
   - [ ] Time → Weekly Report
   - [ ] Time → Time Report
   - [ ] Tools → Command Library
   - [ ] Tools → Notes
   - [ ] Tools → Checklists
   - [ ] Tools → Checklist Templates
   - [ ] Options → Theme Editor (was failing)
   - [ ] Options → Settings

2. **Project Screen:**
   - [ ] Can navigate to Projects → Project List
   - [ ] Can open project details
   - [ ] Inline editor works
   - [ ] ESC exits inline editor
   - [ ] Typing responds in inline editor
   - [ ] File picker works (uses SimpleFilePicker)

3. **Startup Performance:**
   - [ ] Check startup time (ClassLoader adds minimal overhead)
   - [ ] Review `$global:PmcClassLoaderStats` for load statistics
   - [ ] Verify no "Failed to load" errors in console

4. **Log Review:**
   - [ ] Enable logging: `Start-PmcTUI -DebugLog -LogLevel 3`
   - [ ] Check for any ClassLoader warnings/errors
   - [ ] Verify all widgets loaded successfully

## Files Modified

1. `og_transport/working/module/Pmc.Strict/consoleui/ClassLoader.ps1` (NEW)
   - 313 lines of smart loading infrastructure

2. `og_transport/working/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1` (MODIFIED)
   - Replaced hardcoded loading (lines 106-229)
   - Now uses ClassLoader for auto-discovery
   - Cleaner, more maintainable code
   - Approximately 50 lines shorter

## Next Steps

1. **Deploy and Test** - Verify all menu screens now accessible
2. **Monitor Logs** - Watch for any new issues during extended usage
3. **Investigate Inline Editor** - Capture logs during inline editing to debug ESC/typing issues
4. **Performance Baseline** - Measure startup time and compare to previous version
5. **Documentation** - Update developer docs about ClassLoader usage for new screens
