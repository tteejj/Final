# TUI Issues - What to Test Manually

## Context
- Antigravity environment has 21x10 terminal limit (expected)
- User's real terminal should have proper size
- Need to test in user's actual terminal, not through Antigravity

## Reported Issues

### 1. Task Not Saving ❌
**User Report**: "adding a task didnt save"

**What to Test**:
1. Run TUI in your real terminal: `pwsh /home/teej/ztest/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1`
2. Press `a` to add a task
3. Enter task details
4. Press Enter to save
5. Check if task appears in list
6. Exit TUI (Ctrl+Q)
7. Check `/home/teej/ztest/tasks.json` - does it have the new task?

**Code Path**:
- `TaskListScreen.OnItemCreated()` calls `Store.AddTask()`
- `TaskStore.AddTask()` should save to disk
- Located at: `/home/teej/ztest/module/Pmc.Strict/consoleui/services/TaskStore.ps1`

**Possible Causes**:
- TaskStore not flushing to disk
- Validation failing silently
- Error not being displayed

### 2. Rendering Corruption ❌
**User Report**: "rendering is all wrong" - shows "B]" and "task" fragments

**What to Test**:
1. Run TUI in your real terminal (NOT through Antigravity)
2. Check if:
   - Menu bar displays correctly at top
   - Task list shows full columns
   - No text fragments or corruption
   - Screen fills entire terminal

**Possible Causes**:
- ANSI escape sequence issues
- Column width calculations wrong
- Cache invalidation problems
- Z-index layering issues

### 3. Screen Not Filling ❌
**User Report**: "tui should fill screen. it doesnt"

**What to Test**:
1. Run TUI in full-size terminal
2. Verify it uses entire terminal width/height
3. Check if resizing terminal updates TUI size

**Possible Causes**:
- Terminal size detection using wrong values
- Layout not applying correctly
- Widgets using hardcoded sizes

## What I've Fixed

✅ **TimeListScreen Callbacks** - Added missing methods
✅ **Config.ps1 Debug Logging** - Disabled 15 lines causing errors
✅ **Test Scripts** - Created comprehensive test suite

## What I Cannot Test

❌ **Actual TUI in Real Terminal** - Antigravity environment has 21x10 limit
❌ **Visual Rendering** - Need to see actual output in real terminal
❌ **Task Persistence** - Need to verify files are actually written

## Next Steps

1. **User Testing Required**: Run TUI in your real terminal and report:
   - Does task saving work?
   - Is rendering correct?
   - Does screen fill properly?
   - Any error messages?

2. **If Issues Persist**: Provide:
   - Screenshot of TUI
   - Contents of latest log file
   - Output of: `echo $COLUMNS x $LINES` in your terminal
   - Contents of `/home/teej/ztest/tasks.json` before and after adding task

3. **Debugging Steps**:
   ```bash
   # Enable debug logging
   pwsh /home/teej/ztest/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1 -DebugLog -LogLevel 3
   
   # After testing, check log
   tail -100 /home/teej/ztest/module/.pmc-data/logs/pmc-tui-*.log
   ```
