# Kanban Screen V2 - Complete Implementation

**Status**: ✅ Fully Implemented
**File**: `consoleui/screens/KanbanScreenV2.ps1`
**Date**: 2025-11-13

---

## Overview

Enhanced Kanban board with 3 columns, independent scrolling, custom task coloring, and comprehensive task management capabilities.

### Key Features

✅ **Three-column layout**: TODO, IN PROGRESS, DONE
✅ **Independent scrolling**: Each column scrolls separately
✅ **Dynamic column width**: Adjusts to terminal size (minimum 120 chars)
✅ **Ctrl+Arrow movement**: Move tasks between columns and reorder within columns
✅ **Custom task colors**: Per-task and per-tag color schemes
✅ **Subtask hierarchy**: Expand/collapse parent tasks, children move with parents
✅ **Tag editing**: Full tag management using existing TagEditor widget
✅ **Visual separators**: Column borders and scroll indicators

---

## Controls

### Navigation
- `↑/↓` - Move selection within active column
- `←/→` - Switch between columns
- `Space` - Expand/collapse parent task (show/hide subtasks)

### Task Movement
- `Ctrl+←` - Move task to previous column (Done → In Progress → TODO)
- `Ctrl+→` - Move task to next column (TODO → In Progress → Done)
- `Ctrl+↑` - Move task up within column (swap with task above)
- `Ctrl+↓` - Move task down within column (swap with task below)

### Task Customization
- `T` - Edit tags (opens TagEditor widget)
- `C` - Pick custom color for task

### Other
- `R` - Refresh/reload data
- `Esc` - Exit to previous screen

---

## Data Model

### Task Fields Used

```powershell
@{
    id = "uuid"                       # Unique identifier
    text = "Task description"         # Task text
    status = "todo|in-progress|done"  # Column assignment
    order = 0                         # Position within column (for manual reordering)
    color = "#FF5733"                 # Custom per-task color (optional)
    parent_id = "uuid"                # Parent task ID (for subtasks)
    tags = @("work", "urgent")        # Tags (optional)
    priority = 1-5                    # Priority (shown as prefix)
    completed = $true/$false          # Completion status
    completedDate = "2025-11-13"      # Completion timestamp
}
```

### Status Mapping

| Column | Status Values |
|--------|--------------|
| TODO | `'todo'`, `'pending'`, or no status |
| IN PROGRESS | `'in-progress'` |
| DONE | `'done'` or `completed = true` |

### Order Field

Tasks are sorted by `order` field (ascending), then `priority` (descending).
When you use Ctrl+Up/Down to reorder, the `order` values are swapped.

---

## Color System

### Per-Task Colors

Set with `C` key - stores hex color directly on task:
```powershell
$task.color = "#FF0000"  # Red
```

### Per-Tag Colors

Configured in `config.json`:
```json
{
  "Kanban": {
    "TagColors": {
      "urgent": "#FF0000",
      "important": "#FFA500",
      "work": "#0066CC",
      "personal": "#00CC66",
      "blocked": "#CC0000",
      "waiting": "#CCCC00"
    }
  }
}
```

### Color Priority

1. **Per-task color** (if set) - highest priority
2. **Per-tag color** (first matching tag)
3. **Default theme color**

---

## Subtask Behavior

### Parent-Child Relationship

Tasks are displayed as bordered cards with task text and tags:

```
┌─ TODO ─────────────────────────┐
│ ┌────────────────────────────┐ │
│ │ ▸ Project Alpha            │ │  ← Parent (collapsed)
│ │ #work #important           │ │
│ └────────────────────────────┘ │
│                                 │
│ ┌────────────────────────────┐ │
│ │ ▼ Website Redesign         │ │  ← Parent (expanded)
│ │ #project                   │ │
│ └────────────────────────────┘ │
│                                 │
│ ┌────────────────────────────┐ │
│ │   ├─ Design mockups        │ │  ← Child (indented)
│ │ #design                    │ │
│ └────────────────────────────┘ │
│                                 │
> ┌────────────────────────────┐   ← Selected (cursor)
│ │ Regular task               │ │
│ │ #urgent                    │ │
│ └────────────────────────────┘ │
└─────────────────────────────────┘
```

### Movement Rules

**When moving parent with Ctrl+Left/Right:**
- Parent status changes
- **All children move with parent** (status updated)
- Children maintain their subtask relationship

**When moving child manually:**
- Can move child independently of parent
- Child keeps `parent_id` reference
- May end up in different column than parent

**Expanding/Collapsing:**
- Press `Space` on parent task
- Expanded state persists during session
- Subtasks show indented with `├─` prefix

---

## Independent Scrolling

Each column maintains its own scroll offset:

```powershell
[int]$ScrollOffsetTodo = 0
[int]$ScrollOffsetInProgress = 0
[int]$ScrollOffsetDone = 0
```

### Behavior

- Only the **active column** scrolls with arrow keys
- Other columns stay at their current scroll position
- Scroll adjusts automatically to keep selection visible
- Scroll indicators show "↑ More above" and "↓ +N more"

### Selection Tracking

Each column has independent selection:
```powershell
[int]$SelectedIndexTodo = 0
[int]$SelectedIndexInProgress = 0
[int]$SelectedIndexDone = 0
```

Switching columns with `←/→` preserves each column's selection position.

---

## Dynamic Layout

### Column Width Calculation

```powershell
# Minimum total width: 120 chars
$minTotalWidth = 120
$actualWidth = [Math]::Max($minTotalWidth, $contentRect.Width)

# 3 columns + 6 chars for borders
$columnWidth = [Math]::Floor(($actualWidth - 6) / 3)
```

### Responsive Behavior

| Terminal Width | Column Width | Notes |
|----------------|--------------|-------|
| 120 chars | 38 chars each | Minimum |
| 150 chars | 48 chars each | Comfortable |
| 180+ chars | 58+ chars each | Spacious |

Columns expand equally as terminal width increases.

---

## Tag Editing

### TagEditor Integration

Uses the existing `TagEditor.ps1` widget (sophisticated autocomplete-enabled editor):

**Features:**
- Autocomplete from existing tags
- Type-ahead filtering
- Tab/Enter to add tags
- Backspace to remove tags
- Comma-separated input
- Max 10 tags per task

**Workflow:**
1. Press `T` on selected task
2. TagEditor opens as modal dialog
3. Type tags, use autocomplete
4. Press `Esc` to confirm and save
5. Tags saved to task immediately

---

## Color Picker

### Simple Color Menu

Shows 9 color options:
- Red (#FF0000)
- Orange (#FFA500)
- Yellow (#FFFF00)
- Green (#00FF00)
- Blue (#0000FF)
- Purple (#9966FF)
- Pink (#FF69B4)
- Cyan (#00FFFF)
- Clear (use tag color)

**Workflow:**
1. Press `C` on selected task
2. Color picker opens as modal menu
3. Use `↑↓` to select color
4. Press `Enter` to apply
5. Color saved to task immediately

### Visual Preview

Each color shows as colored blocks: `███ > Red`

---

## Implementation Details

### File Structure

```
consoleui/screens/KanbanScreenV2.ps1      # Main implementation (980 lines)
consoleui/widgets/TagEditor.ps1           # Tag editing widget (reused)
```

### Key Methods

**Data Loading:**
- `LoadData()` - Loads tasks from Get-PmcData, filters by status

**Rendering:**
- `_RenderKanbanBoard()` - Main board layout
- `_RenderColumn()` - Individual column rendering with bordered task cards
- `_BuildFlatTaskList()` - Expands parent/child hierarchy

**Card Rendering:**
Each task is rendered as a 4-line bordered card:
```
Line 1: ┌────────┐  (top border)
Line 2: │ text   │  (task text with indicators)
Line 3: │ #tags  │  (tags in muted color)
Line 4: └────────┘  (bottom border)
```
Cards use box-drawing characters (┌─┐│└┘) with custom colors applied to borders and content.

**Movement:**
- `_MoveTaskLeft()` / `_MoveTaskRight()` - Inter-column movement
- `_ReorderTaskUp()` / `_ReorderTaskDown()` - Intra-column reordering
- `_SwapTaskOrder()` - Swaps order field values

**Hierarchy:**
- `_HasChildren()` - Checks if task is a parent
- `_GetChildren()` - Gets child tasks
- `_ToggleExpand()` - Expand/collapse parent

**Colors:**
- `_GetTaskColor()` - Resolves color (per-task > per-tag > default)
- `_HexToAnsi()` - Converts hex to ANSI RGB sequence

**Dialogs:**
- `_EditTags()` - Opens TagEditor modal
- `_PickColor()` - Opens color picker modal

---

## Usage Example

### From TUI Menu

1. Launch PMC TUI: `pwsh Start-PmcTUI.ps1`
2. Open the **Tasks** menu
3. Press `K` for **Kanban Board**

**Menu Location**: Tasks → Kanban Board (K)

### Programmatic

```powershell
# Push Kanban screen
$screen = [KanbanScreenV2]::new()
$app.PushScreen($screen)

# Or use helper function
Show-KanbanScreenV2 -App $app
```

### Menu Configuration

Configured in `MenuItems.psd1`:
```powershell
'KanbanScreenV2' = @{
    Menu = 'Tasks'
    Label = 'Kanban Board'
    Hotkey = 'K'
    Order = 55
    ScreenFile = 'KanbanScreenV2.ps1'
}
```

---

## Testing Checklist

### Navigation
- [x] Up/Down moves selection within column
- [x] Left/Right switches columns
- [x] Scroll offsets adjust to keep selection visible
- [x] Each column scrolls independently

### Task Movement
- [x] Ctrl+Left moves task to previous column
- [x] Ctrl+Right moves task to next column
- [x] Ctrl+Up swaps task with one above
- [x] Ctrl+Down swaps task with one below
- [x] Status field updates correctly
- [x] Completed/completedDate updates for DONE column

### Subtasks
- [x] Space expands/collapses parent tasks
- [x] Subtasks show indented with tree characters
- [x] Moving parent moves all children
- [x] Children can be moved independently

### Colors
- [x] Per-task colors display correctly
- [x] Per-tag colors display when no task color
- [x] Color picker saves colors
- [x] Clearing color removes task color

### Tags
- [x] Tag editor opens and closes
- [x] Tags save to task
- [x] Autocomplete works
- [x] Tag colors apply

### Layout
- [x] Columns adjust to terminal width
- [x] Minimum 120 char width enforced
- [x] Column headers show counts
- [x] Vertical separators render
- [x] Scroll indicators appear

---

## Differences from Original Kanban Screen

| Feature | Original | V2 |
|---------|----------|-----|
| Scrolling | Truncation only | Independent per column |
| Movement | 'M' key cycles status | Ctrl+Arrows (directional) |
| Reordering | Not supported | Ctrl+Up/Down swaps |
| Colors | Priority-based only | Per-task + per-tag custom |
| Tags | View only | Full editing (T key) |
| Subtasks | Not shown | Expand/collapse hierarchy |
| Layout | Fixed width | Dynamic (min 120) |
| Column width | Hardcoded | Calculated from terminal |

---

## Configuration

### Default Tag Colors

Edit in `config.json`:
```json
{
  "Kanban": {
    "TagColors": {
      "urgent": "#FF0000",
      "work": "#0066CC"
    }
  }
}
```

### Load Tag Colors

Done automatically in constructor:
```powershell
hidden [void] _LoadTagColors() {
    $cfg = Get-PmcConfig
    if ($cfg.Kanban -and $cfg.Kanban.TagColors) {
        $this.TagColors = $cfg.Kanban.TagColors
    }
}
```

---

## Performance Notes

- **Flat list building**: O(n) per column render
- **Card-based scrolling**: Each card takes 4 lines; typically shows 5-8 tasks per column
- **Scroll optimization**: Only renders visible task cards
- **Color caching**: Theme ANSI sequences cached by Header widget
- **Tag refresh**: TagEditor reloads tags every 10 seconds
- **Rendering**: Each task card requires 4 cursor movements + 4 string appends

---

## Future Enhancements (Out of Scope)

- [ ] Drag-and-drop with mouse
- [ ] Keyboard shortcuts customization
- [ ] Export to CSV/JSON
- [ ] Filter by tag/priority
- [ ] Search within columns
- [ ] Column limits (WIP warnings)
- [ ] Swimlanes (additional column grouping)
- [ ] Custom column definitions

---

## Known Limitations

1. **No task creation**: Use TaskListScreen to create tasks (by design)
2. **No task editing**: Text editing happens in TaskListScreen (by design)
3. **Max subtask depth**: 1 level (parent → children, no grandchildren)
4. **Color picker**: Fixed color palette (9 colors)
5. **Modal dialogs**: Block main screen updates during editing

---

## Troubleshooting

### "Tasks not appearing"
- Check task `status` field matches column filter
- Ensure tasks aren't filtered out by `completed` status

### "Colors not showing"
- Verify terminal supports 24-bit color (true color)
- Check `color` field format is `#RRGGBB`

### "Subtasks not visible"
- Press `Space` on parent to expand
- Ensure `parent_id` matches parent's `id`

### "Scrolling not working"
- Check content area has enough height
- Verify tasks exceed visible area

---

**Implementation Complete!** ✅

All requested features implemented and tested.
