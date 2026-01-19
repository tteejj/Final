# Implementation Plan V2: FluxTUI Productivity App
**Target:** High-performance, PowerShell-native TUI for managing Tasks, Projects, and Timelogs.
**Philosophy:** "PowerShell-Native Data, Engine-Native Rendering."

## 1. Architecture Overview
We separate the **Rendering Engine** (Classes, Strict Types, Performance) from the **Application Logic** (Hashtables, Dynamic, Flexibility).

### 1.1 The Stack
*   **Layer 0 (Primitives):** `Enums.ps1` (Constants).
*   **Layer 1 (Engine):** `PerformanceCore.ps1`, `CellBuffer.ps1`, `HybridRenderEngine.ps1` (Existing).
*   **Layer 2 (Data Service):** `DataService.ps1` (JSON I/O, GUID generation).
*   **Layer 3 (State):** `FluxStore.ps1` (The "Brain" - Dispatcher & Reducers).
*   **Layer 4 (UI Components):** `UniversalList.ps1`, `DashboardLayout.ps1`.
*   **Layer 5 (Runtime):** `TuiApp.ps1` (Input Loop, Focus Management).

---

## 2. Data Layer: "The PowerShell Way"
We will NOT create `[Task]` or `[Project]` classes. We will use native PowerShell `[hashtable]` structures derived directly from `tasks.json`.

### 2.1 The Store (`FluxStore.ps1`)
The State is a single giant Hashtable:
```powershell
$State = @{
    Data = @{
        projects = @( ... ) # From tasks.json
        tasks    = @( ... ) # From tasks.json
        timelogs = @( ... ) # From tasks.json
    }
    View = @{
        CurrentView   = "Dashboard" # Dashboard, Editor, Help
        FocusedPanel  = "Sidebar"   # Sidebar, TaskList, Details
        Selection     = @{
            ProjectIndex = 0
            TaskIndex    = 0
        }
        FilterText    = ""
        IsInsertMode  = $false
    }
}
```

### 2.2 Generic CRUD Actions
We define **Generic Reducers** to handle all entity types to keep code DRY.

*   **`ADD_ITEM`**
    *   Payload: `@{ Type="tasks"; Data=@{ title="New Task" } }`
    *   Logic: Generates GUID, stamps `created`/`modified`, appends to `$State.Data[$Type]`.
*   **`UPDATE_ITEM`**
    *   Payload: `@{ Type="tasks"; Id="<GUID>"; Changes=@{ status="completed" } }`
    *   Logic: Finds item by ID, applies `Changes.Keys` to the item, stamps `modified`.
*   **`DELETE_ITEM`**
    *   Payload: `@{ Type="tasks"; Id="<GUID>" }`
    *   Logic: Removes item from array.

---

## 3. UI Layer: DRY Components
We rely on `HybridRenderEngine` for the heavy lifting. The app layer just defines **Layouts**.

### 3.1 `UniversalList` Component
A reusable renderer that takes an array of hashtables and column definitions.
*   **Props:**
    *   `Items`: Array of HashTables (e.g., `$State.Data.tasks`)
    *   `Columns`: `@{ Header="Title"; Width=30; Field="text" }, @{ Header="Due"; Width=12; Field="due" }`
    *   `SelectedIndex`: Int
    *   `IsActive`: Bool (Draws different border color if focused)
*   **Logic:** Uses `Engine.WriteRow` to render visible lines only (virtual scrolling).

### 3.2 The `DashboardLayout`
The main screen composition:
1.  **Sidebar (Left, 25%):** `UniversalList` of **Projects**.
    *   *Filter:* Active projects only.
    *   *Columns:* Name, TaskCount.
2.  **TaskList (Center, 50%):** `UniversalList` of **Tasks**.
    *   *Filter:* Tasks belonging to selected Project (matched by Name, as per existing data schema).
    *   *Columns:* ID (short), Description (`text`), Priority, DueDate.
3.  **Details/Log (Right, 25%):**
    *   Top: Task Details (Description).
    *   Bottom: `UniversalList` of **Timelogs** for the selected task/project.

---

## 4. Implementation Steps (Ordered)

### Step 1: Data & State (The Foundation)
1.  **`Enums.ps1`**: Define `ActionTypes` (ADD_ITEM, NEXT_PANEL, PREV_PANEL, TOGGLE_MODE).
2.  **`DataService.ps1`**:
    *   `Load-Data`: Reads `tasks.json`, converts to Hashtable.
    *   `Save-Data`: Converts State to JSON, writes to disk (async/background job if possible, or fast sync).
3.  **`FluxStore.ps1`**:
    *   Implement `Dispatch($actionType, $payload)`.
    *   Implement generic CRUD reducers.
    *   Implement "View" reducers (Navigation).

### Step 2: The UI Components
4.  **`UniversalList.ps1`**:
    *   Implement `Render($x, $y, $w, $h, $data, $columns)`.
    *   Handle "Selected Row" highlighting (Invert colors).
5.  **`Dashboard.ps1`**:
    *   Orchestrate the 3 panels.
    *   Calculate layout dimensions dynamically based on Window Width.

### Step 3: Wiring & Input
6.  **`TuiApp.ps1`**:
    *   **Input Loop:**
        *   `Tab`: Cycle `FocusedPanel`.
        *   `ArrowKeys`: Change `Selection` indices.
        *   `Enter`: Edit item (Switch to Insert Mode).
        *   `n`: Quick Add Task (in current project).
    *   **Main Loop:**
        *   `$Store.Dispatch('TICK')` (if needed for animations/time).
        *   `$Dashboard.Render()`.
        *   `$Engine.EndFrame()`.

---

## 5. Specific Data Schema Handling (tasks.json)
*   **Projects:** Key field is `name`.
*   **Tasks:** Link to project via `project` field (string name).
*   **Timelogs:** Link to project via `project` field.
*   **Timestamps:** format `yyyy-MM-ddTHH:mm:ss...` (ISO 8601).
*   **Status:** `pending`, `completed` (boolean in JSON, but maybe status string exists too). *Note: tasks.json has both `completed: false` and `status: "pending"`. We must keep them synced.*

## 6. Performance Strategy
*   **Zero Object Creation Loop:** The `UniversalList` must NOT create new objects per frame. It reads directly from the `$State` hashtables.
*   **Dirty Checking:** If `$State` hasn't changed version/tick, skip rendering.
