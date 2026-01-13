# DataDisplay.ps1 - Universal data grid system for PMC
# Provides flexible, auto-sizing grid display for any domain combination

Set-StrictMode -Version Latest

class PmcGridRenderer {
    [hashtable] $ColumnConfig
    [int] $TerminalWidth
    [string[]] $Domains
    [hashtable] $Filters
    [hashtable] $ThemeConfig
    [hashtable] $ProjectLookup

    # NEW: Interactive navigation state
    [int] $SelectedRow = 0
    [int] $SelectedColumn = 0
    [string] $NavigationMode = "Row"  # Row, Cell, MultiSelect
    [bool] $Interactive = $false
    [bool] $ShowInternalHeader = $true
    [string] $TitleText = 'PMC Interactive Data Grid'
    [object[]] $CurrentData = @()
    [object[]] $AllData = @()
    [hashtable] $KeyBindings = @{}

    # NEW: Navigation mode flags
    [bool] $EditMode = $true          # true = Enter edits cells, false = Enter navigates/selects
    [scriptblock] $OnSelectCallback = $null  # Callback for navigation mode Enter

    # NEW: Editing state
    [bool] $InEditMode = $false
    [string] $EditingColumn = ""
    [string] $EditingValue = ""
    [hashtable] $EditCallbacks = @{}
    [bool] $LiveEditing = $false
    [scriptblock] $SaveCallback = $null

    # NEW: Inline editing state
    [bool] $InlineEditMode = $false
    [int] $EditCursorPos = 0
    [hashtable] $PendingEdits = @{}  # Store pending edits in memory until session completes
    [bool] $AllowSensitiveEdits = $false
    [string] $ConflictPolicy = 'InlineRelaxed'  # InlineRelaxed | Strict

    # NEW: Selection and multi-select
    [int[]] $SelectedRows = @()
    [bool] $MultiSelectMode = $false

    # NEW: Performance/diff rendering placeholders
    [hashtable] $RenderCache = @{}
    [bool] $DifferentialMode = $true

    # NEW: Simple live filtering state
    [string] $FilterQuery = ''
    [string] $LastErrorMessage = ''

    [string] GetPrimaryDomain() {
        if ($this.Domains -and @($this.Domains).Count -gt 0) { return [string]$this.Domains[0] }
        return ''
    }

    [hashtable] GetFieldSchema([string]$ColumnName) {
        $dom = $this.GetPrimaryDomain()
        if ($dom) { return (Get-PmcFieldSchema -Domain $dom -Field $ColumnName) }
        return $null
    }

    [string] GetFieldHint([string]$ColumnName) {
        $sch = $this.GetFieldSchema($ColumnName)
        if ($sch -and $sch.ContainsKey('Hint')) { return [string]$sch.Hint }
        return ''
    }

    [string] NormalizeField([string]$ColumnName, [string]$Value) {
        $sch = $this.GetFieldSchema($ColumnName)
        if ($sch -and $sch.ContainsKey('Normalize') -and $sch.Normalize) { return (& $sch.Normalize $Value) }
        return $Value
    }

    [void] ValidateField([string]$ColumnName, [string]$Value) {
        $sch = $this.GetFieldSchema($ColumnName)
        if ($sch -and $sch.ContainsKey('Validate') -and $sch.Validate) { & $sch.Validate $Value | Out-Null }
    }

    # NEW: Sorting state
    [string] $SortColumn = ''
    [string] $SortDirection = 'None'  # None | Asc | Desc

    # NEW: Saved views map
    [hashtable] $SavedViews = @{}

    # NEW: Differential rendering cache/state
    [string[]] $LastLines = @()

    # NEW: Praxis frame renderer for proper double buffering
    [object] $FrameRenderer = $null
    [bool] $HasInitialRender = $false
    [int] $RefreshIntervalMs = 0
    [datetime] $LastRefreshAt = [datetime]::MinValue

    # NEW: Layout and scrolling
    [int] $WindowHeight = 0
    [int] $HeaderLines = 4   # Title, border, header, separator
    [int] $ScrollOffset = 0

    PmcGridRenderer([hashtable]$Columns, [string[]]$Domains, [hashtable]$Filters) {
        $this.ColumnConfig = $Columns
        $this.Domains = $Domains
        $this.Filters = $Filters
        $this.ThemeConfig = $this.InitializeTheme(@{})
        $this.TerminalWidth = $this.GetTerminalWidth()
        $this.WindowHeight = $this.GetTerminalHeight()
        $this.ProjectLookup = $this.LoadProjectLookup()
        $this.InitializeKeyBindings()
        $this.LoadSavedViews()

        # Initialize Praxis frame renderer for proper double buffering
        $this.FrameRenderer = [PraxisFrameRenderer]::new()
    }

    [hashtable] InitializeTheme([hashtable]$UserTheme) {
        # Get PMC's existing style system
        $pmcStyles = Get-PmcState -Section 'Display' -Key 'Styles'

        # Default grid theme using PMC style tokens
        $defaultTheme = @{
            Default = @{
                Style = "Body"  # Uses PMC's Body style token
            }
            Columns = @{}
            Rows = @{
                Header = @{ Style = "Header" }      # Uses PMC's Header style
                Separator = @{ Style = "Border" }   # Uses PMC's Border style
            }
            Cells = @()
        }

        # Merge user theme with defaults (deep merge)
        if ($UserTheme.PSObject.Properties['Default']) {
            $defaultTheme.Default = $this.MergeStyles($defaultTheme.Default, $UserTheme.Default)
        }
        if ($UserTheme.PSObject.Properties['Columns']) {
            foreach ($col in $UserTheme.Columns.Keys) {
                $defaultTheme.Columns[$col] = $UserTheme.Columns[$col]
            }
        }
        if ($UserTheme.PSObject.Properties['Rows']) {
            foreach ($row in $UserTheme.Rows.Keys) {
                $defaultTheme.Rows[$row] = $this.MergeStyles($defaultTheme.Rows[$row], $UserTheme.Rows[$row])
            }
        }
        if ($UserTheme.PSObject.Properties['Cells']) {
            $defaultTheme.Cells = $UserTheme.Cells
        }

        return $defaultTheme
    }

    [hashtable] MergeStyles([hashtable]$Base, [hashtable]$Override) {
        $merged = @{}
        if ($Base) {
            foreach ($key in $Base.Keys) { $merged[$key] = $Base[$key] }
        }
        if ($Override) {
            foreach ($key in $Override.Keys) { $merged[$key] = $Override[$key] }
        }
        return $merged
    }

    [hashtable] GetCellTheme([object]$Item, [string]$ColumnName, [int]$RowIndex, [bool]$IsHeader) {
        # Start with default theme
        $cellTheme = $this.ThemeConfig.Default.Clone()

        # Apply column theme
        if ($ColumnName -and $this.ThemeConfig.Columns.PSObject.Properties[$ColumnName]) {
            $cellTheme = $this.MergeStyles($cellTheme, $this.ThemeConfig.Columns[$ColumnName])
        }

        # Apply row theme
        if ($IsHeader -and $this.ThemeConfig.Rows.PSObject.Properties['Header']) {
            $cellTheme = $this.MergeStyles($cellTheme, $this.ThemeConfig.Rows.Header)
        }

        # Apply cell-specific themes (conditional)
        if (-not $IsHeader -and $this.ThemeConfig.Cells) {
            foreach ($cellRule in $this.ThemeConfig.Cells) {
                # Check if rule applies to this cell
                if ($cellRule.PSObject.Properties['Column'] -and $cellRule.Column -ne $ColumnName) {
                    continue  # Rule is column-specific and doesn't match
                }

                $applies = $true
                if ($cellRule.PSObject.Properties['Condition'] -and $cellRule.Condition) {
                    try {
                        $applies = & $cellRule.Condition $Item
                    } catch {
                        $applies = $false
                    }
                }

                if ($applies -and $cellRule.PSObject.Properties['Style']) {
                    $cellTheme = $this.MergeStyles($cellTheme, $cellRule.Style)
                }
            }
        }

        # Consult global cell style hook if available
        if (-not $IsHeader) {
            $hook = Get-Command -Name 'Get-PmcCellStyle' -ErrorAction SilentlyContinue
            if ($hook) {
                $val = $null
                if ($Item -ne $null -and $ColumnName) {
                    $val = $this.GetItemValue($Item, $ColumnName)
                }
                $ext = Get-PmcCellStyle -RowData $Item -Column $ColumnName -Value $val
                if ($ext -and ($ext -is [hashtable])) { $cellTheme = $this.MergeStyles($cellTheme, $ext) }
            }
        }

        return $cellTheme
    }

    [string] ApplyTheme([string]$Text, [hashtable]$CellTheme) {
        # If we have a PMC style token, use Write-PmcStyled approach
        if ($CellTheme.PSObject.Properties['Style']) {
            $style = Get-PmcStyle $CellTheme.Style
            if ($style -and $style.PSObject.Properties['Fg']) {
                # Use PMC's styling but return the ANSI codes directly for grid integration
                return $this.ConvertPmcStyleToAnsi($Text, $style, $CellTheme)
            }
        }

        # Direct color specification (RGB, Hex, Named)
        $fgCode = ""
        $bgCode = ""

        # Handle foreground color
        if ($CellTheme.PSObject.Properties['Foreground'] -or $CellTheme.PSObject.Properties['Fg']) {
            $fg = $(if ($CellTheme.Foreground) { $CellTheme.Foreground } else { $CellTheme.Fg })
            $fgCode = $this.GetColorCode($fg, $false)
        }

        # Handle background color
        if ($CellTheme.PSObject.Properties['Background'] -or $CellTheme.PSObject.Properties['Bg']) {
            $bg = $(if ($CellTheme.Background) { $CellTheme.Background } else { $CellTheme.Bg })
            $bgCode = $this.GetColorCode($bg, $true)
        }

        if ($fgCode -or $bgCode) {
            $pre = "$fgCode$bgCode"
            if ($CellTheme.PSObject.Properties['Bold'] -and $CellTheme.Bold) { $pre += [PmcVT]::Bold() }
            return "$pre$Text" + [PmcVT]::Reset()
        }

        return $Text
    }

    [string] ConvertPmcStyleToAnsi([string]$Text, [hashtable]$PmcStyle, [hashtable]$CellTheme) {
        $codes = ""

        # Convert PMC style to ANSI codes (robust hashtable access)
        $fgVal = $null; $bgVal = $null; $bold = $false
        if ($PmcStyle) {
            if (($PmcStyle -is [hashtable]) -and $PmcStyle.ContainsKey('Fg')) { $fgVal = $PmcStyle['Fg'] }
            elseif ($PmcStyle.PSObject -and $PmcStyle.PSObject.Properties['Fg']) { $fgVal = $PmcStyle.Fg }
            if (($PmcStyle -is [hashtable]) -and $PmcStyle.ContainsKey('Bg')) { $bgVal = $PmcStyle['Bg'] }
            elseif ($PmcStyle.PSObject -and $PmcStyle.PSObject.Properties['Bg']) { $bgVal = $PmcStyle.Bg }
            if (($PmcStyle -is [hashtable]) -and $PmcStyle.ContainsKey('Bold')) { if ($PmcStyle['Bold']) { $bold = $true } }
            elseif ($PmcStyle.PSObject -and $PmcStyle.PSObject.Properties['Bold']) { if ($PmcStyle.Bold) { $bold = $true } }
        }
        if ($fgVal) { $codes += $this.GetColorCode([string]$fgVal, $false) }
        if ($bgVal) { $codes += $this.GetColorCode([string]$bgVal, $true) }

        # Apply any additional cell-specific overrides
        if ($CellTheme) {
            $cellFg = $null; $cellBg = $null; $cellBold = $false
            if (($CellTheme -is [hashtable]) -and $CellTheme.ContainsKey('Fg')) { $cellFg = $CellTheme['Fg'] }
            elseif ($CellTheme.PSObject -and $CellTheme.PSObject.Properties['Fg']) { $cellFg = $CellTheme.Fg }
            if (($CellTheme -is [hashtable]) -and $CellTheme.ContainsKey('Bg')) { $cellBg = $CellTheme['Bg'] }
            elseif ($CellTheme.PSObject -and $CellTheme.PSObject.Properties['Bg']) { $cellBg = $CellTheme.Bg }
            if (($CellTheme -is [hashtable]) -and $CellTheme.ContainsKey('Bold')) { if ($CellTheme['Bold']) { $cellBold = $true } }
            elseif ($CellTheme.PSObject -and $CellTheme.PSObject.Properties['Bold']) { if ($CellTheme.Bold) { $cellBold = $true } }
            if ($cellFg) { $codes += $this.GetColorCode([string]$cellFg, $false) }
            if ($cellBg) { $codes += $this.GetColorCode([string]$cellBg, $true) }
            if ($cellBold) { $bold = $true }
        }

        # Bold emphasis if requested
        if ($bold) { $codes += [PmcVT]::Bold() }

        if ($codes) {
            return "$codes$Text" + [PmcVT]::Reset()
        }
        return $Text
    }

    [string] GetColorCode([string]$Color, [bool]$IsBackground) {
        if (-not $Color) { return "" }

        # Handle hex colors (#RRGGBB or #RGB)
        if ($Color -match '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})$') {
            $rgb = ConvertFrom-PmcHex $Color
            if ($rgb) {
                if ($IsBackground) {
                    return [PmcVT]::BgRGB($rgb.R, $rgb.G, $rgb.B)
                } else {
                    return [PmcVT]::FgRGB($rgb.R, $rgb.G, $rgb.B)
                }
            }
        }

        # Handle RGB values (255,128,64)
        if ($Color -match '^(\d{1,3}),(\d{1,3}),(\d{1,3})$') {
            $r = [int]$Matches[1]
            $g = [int]$Matches[2]
            $b = [int]$Matches[3]
            if ($r -le 255 -and $g -le 255 -and $b -le 255) {
                if ($IsBackground) {
                    return [PmcVT]::BgRGB($r, $g, $b)
                } else {
                    return [PmcVT]::FgRGB($r, $g, $b)
                }
            }
        }

        # Handle named colors (fallback to standard ANSI)
        $ansiCode = $(if ($IsBackground) { 40 } else { 30 })
        switch ($Color.ToLower()) {
            "black" { $ansiCode += 0 }
            "red" { $ansiCode += 1 }
            "green" { $ansiCode += 2 }
            "yellow" { $ansiCode += 3 }
            "blue" { $ansiCode += 4 }
            "magenta" { $ansiCode += 5 }
            "cyan" { $ansiCode += 6 }
            "white" { $ansiCode += 7 }
            "gray" { $ansiCode = $(if ($IsBackground) { 100 } else { 90 }) }
            "brightred" { $ansiCode = $(if ($IsBackground) { 101 } else { 91 }) }
            "brightgreen" { $ansiCode = $(if ($IsBackground) { 102 } else { 92 }) }
            "brightyellow" { $ansiCode = $(if ($IsBackground) { 103 } else { 93 }) }
            "brightblue" { $ansiCode = $(if ($IsBackground) { 104 } else { 94 }) }
            "brightmagenta" { $ansiCode = $(if ($IsBackground) { 105 } else { 95 }) }
            "brightcyan" { $ansiCode = $(if ($IsBackground) { 106 } else { 96 }) }
            "brightwhite" { $ansiCode = $(if ($IsBackground) { 107 } else { 97 }) }
            default { return "" }
        }

        return "`e[${ansiCode}m"
    }

    [int] GetTerminalWidth() {
        return [PmcTerminalService]::GetWidth()
    }

    [int] GetTerminalHeight() {
        return [PmcTerminalService]::GetHeight()
    }

    [hashtable] GetTerminalBounds() {
        return [PmcTerminalService]::GetDimensions()
    }

    [bool] ValidateScreenBounds([string]$Content, [int]$MaxWidth = 0, [int]$MaxHeight = 0) {
        return [PmcTerminalService]::ValidateContent($Content, $MaxWidth, $MaxHeight)
    }

    [string] EnforceScreenBounds([string]$Content, [int]$MaxWidth = 0, [int]$MaxHeight = 0) {
        return [PmcTerminalService]::EnforceContentBounds($Content, $MaxWidth, $MaxHeight)
    }

    [hashtable] LoadProjectLookup() {
        # Load project data to resolve project names from IDs
        $lookup = @{}
        try {
            $data = Get-PmcDataProvider 'Storage'
            if ($data -and $data.GetData) {
                $projectData = $data.GetData()
                if ($projectData.projects) {
                    foreach ($project in $projectData.projects) {
                        if ($project.name) {
                            $lookup[$project.name] = $project.name
                            # Also map any aliases if they exist
                            if ($project.PSObject.Properties['aliases'] -and $project.aliases) {
                                foreach ($alias in $project.aliases) {
                                    $lookup[$alias] = $project.name
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            Write-PmcDebug -Level 2 -Category "DataDisplay" -Message "Failed to load project lookup" -Data @{ Error = $_.Exception.Message }
        }
        return $lookup
    }

    [void] InitializeKeyBindings() {
        $this.KeyBindings = @{
            # Navigation
            "UpArrow"    = { $this.MoveUp() }
            "DownArrow"  = { $this.MoveDown() }
            "LeftArrow"  = { $this.MoveLeft() }
            "RightArrow" = { $this.MoveRight() }
            "PageUp"     = { $this.PageUp() }
            "PageDown"   = { $this.PageDown() }
            "Home"       = { $this.MoveToStart() }
            "End"        = { $this.MoveToDoEnd() }
            "Ctrl+LeftArrow"  = { $this.MoveToColumnStart() }
            "Ctrl+RightArrow" = { $this.MoveToColumnDoEnd() }

            # Selection
            "Shift+UpArrow"   = { $this.ExtendSelectionUp() }
            "Shift+DownArrow" = { $this.ExtendSelectionDown() }
            "Ctrl+A"          = { $this.SelectAll() }

            # Editing/Navigation
            "Enter"      = { $this.HandleEnterKey() }
            "F2"         = { $this.StartCellEdit() }
            "Escape"     = { if ($this.InEditMode -or $this.InlineEditMode) { $this.CancelEdit() } else { $this.ExitInteractive() } }
            "Delete"     = { $this.DeleteSelected() }

            # Actions
            "Ctrl+S"     = { $this.SaveChanges() }
            "Ctrl+Z"     = { $this.Undo() }
            "Ctrl+R"     = { $this.RefreshData() }
            "F5"         = { $this.RefreshData() }
            "Ctrl+F"     = { $this.PromptDoFilter() }
            # Quick open filter/search with '/'
            "Oem2"       = { $this.PromptDoFilter() }  # '/' key on most layouts
            # Sorting
            "F3"         = { $this.ToggleSortCurrentColumn() }
            # Saved views
            "F6"         = { $this.PromptSaveView() }
            "F7"         = { $this.PromptLoadView() }
            "F8"         = { $this.ListSavedViews() }

            # Mode switching
            "Tab"        = { $this.SwitchNavigationMode($false) }
            "Shift+Tab"  = { $this.SwitchNavigationMode($true) }

            # Exit
            "Q"          = { $this.ExitInteractive() }
            "Ctrl+C"     = { $this.ExitInteractive() }
        }
    }

    # Navigation methods
    [void] MoveUp() {
        if (@($this.CurrentData).Count -eq 0) { return }
        if ($this.SelectedRow -gt 0) {
            $oldRow = $this.SelectedRow
            $this.SelectedRow--
            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'MoveUp navigation' -Data @{ From = $oldRow; To = $this.SelectedRow; DataCount = @($this.CurrentData).Count }
            $this.EnsureInView()
            $this.RefreshDisplay()
        }
    }

    [void] MoveDown() {
        if (@($this.CurrentData).Count -eq 0) { return }
        if ($this.SelectedRow -lt (@($this.CurrentData).Count - 1)) {
            $oldRow = $this.SelectedRow
            $this.SelectedRow++
            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'MoveDown navigation' -Data @{ From = $oldRow; To = $this.SelectedRow; DataCount = @($this.CurrentData).Count }
            $this.EnsureInView()
            $this.RefreshDisplay()
        }
    }

    [void] MoveLeft() {
        if ($this.NavigationMode -eq "Cell") {
            $columns = @($this.ColumnConfig.Keys)
            if ($this.SelectedColumn -gt 0) {
                $this.SelectedColumn--
                $this.RefreshDisplay()
            }
        }
    }

    [void] MoveRight() {
        if ($this.NavigationMode -eq "Cell") {
            $columns = @($this.ColumnConfig.Keys)
            if ($this.SelectedColumn -lt ($columns.Count - 1)) {
                $this.SelectedColumn++
                $this.RefreshDisplay()
            }
        }
    }

    [void] PageUp() {
        if (@($this.CurrentData).Count -eq 0) { return }
        try {
            $winHeight = [PmcTerminalService]::GetHeight()
            $pageSize = [Math]::Max(1, $winHeight - ($this.HeaderLines + 2))
        } catch {
            $pageSize = 10  # Fallback page size
        }
        $this.SelectedRow = [Math]::Max(0, $this.SelectedRow - $pageSize)
        $this.EnsureInView()
        $this.RefreshDisplay()
    }

    [void] PageDown() {
        if (@($this.CurrentData).Count -eq 0) { return }
        try {
            $winHeight = [PmcTerminalService]::GetHeight()
            $pageSize = [Math]::Max(1, $winHeight - ($this.HeaderLines + 2))
        } catch {
            $pageSize = 10  # Fallback page size
        }
        $this.SelectedRow = [Math]::Min(@($this.CurrentData).Count - 1, $this.SelectedRow + $pageSize)
        $this.EnsureInView()
        $this.RefreshDisplay()
    }

    [void] MoveToStart() {
        $this.SelectedRow = 0
        $this.ScrollOffset = 0
        $this.RefreshDisplay()
    }

    [void] MoveToDoEnd() {
        if (@($this.CurrentData).Count -gt 0) {
            $this.SelectedRow = @($this.CurrentData).Count - 1
            $this.EnsureInView()
            $this.RefreshDisplay()
        }
    }

    # Selection methods
    [void] ExtendSelectionUp() {
        $this.MultiSelectMode = $true
        if (@($this.SelectedRows).Count -eq 0) {
            $this.SelectedRows = @($this.SelectedRow)
        }
        if ($this.SelectedRow -gt 0) {
            $this.SelectedRow--
            if ($this.SelectedRows -notcontains $this.SelectedRow) {
                $this.SelectedRows += $this.SelectedRow
            }
            $this.RefreshDisplay()
        }
    }

    [void] ExtendSelectionDown() {
        $this.MultiSelectMode = $true
        if (@($this.SelectedRows).Count -eq 0) {
            $this.SelectedRows = @($this.SelectedRow)
        }
        if ($this.SelectedRow -lt (@($this.CurrentData).Count - 1)) {
            $this.SelectedRow++
            if ($this.SelectedRows -notcontains $this.SelectedRow) {
                $this.SelectedRows += $this.SelectedRow
            }
            $this.RefreshDisplay()
        }
    }

    [void] SelectAll() {
        $this.MultiSelectMode = $true
        $this.SelectedRows = @(0..(@($this.CurrentData).Count - 1))
        $this.RefreshDisplay()
    }

    # Editing methods
    # NEW: Handle Enter key based on mode
    [void] HandleEnterKey() {
        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'HandleEnterKey' -Data @{ EditMode=$this.EditMode; HasCallback=($this.OnSelectCallback -ne $null) }

        if ($this.EditMode) {
            # Edit mode: Start cell editing (original behavior)
            $this.StartCellEdit()
        } else {
            # Navigation mode: Execute selection callback or exit
            if ($this.OnSelectCallback -ne $null) {
                Write-PmcDebug -Level 2 -Category 'DataDisplay' -Message 'Executing OnSelectCallback'
                try {
                    $selectedItem = $(if (@($this.CurrentData).Count -gt 0 -and $this.SelectedRow -lt @($this.CurrentData).Count) {
                        $this.CurrentData[$this.SelectedRow]
                    } else {
                        $null
                    })
                    & $this.OnSelectCallback $selectedItem $this.SelectedRow
                } catch {
                    Write-PmcDebug -Level 1 -Category 'DataDisplay' -Message 'OnSelectCallback error' -Data @{ Error = $_.Exception.Message }
                }
            } else {
                # No callback, exit interactive mode
                Write-PmcDebug -Level 2 -Category 'DataDisplay' -Message 'No callback, exiting interactive mode'
                $this.Interactive = $false
            }
        }
    }

    [void] StartCellEdit() {
        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'StartCellEdit' -Data @{ Nav=$this.NavigationMode; Row=$this.SelectedRow; Count=@($this.CurrentData).Count }

        if (@($this.CurrentData).Count -eq 0 -or $this.SelectedRow -ge @($this.CurrentData).Count) {
            Write-PmcDebug -Level 2 -Category 'DataDisplay' -Message 'StartCellEdit: No data or invalid row'
            return
        }

        $columns = @($this.ColumnConfig.Keys)
        $editableColumns = $this.GetEditableColumns()
        $columnName = $null

        # Determine which column to edit based on navigation mode
        if ($this.NavigationMode -eq "Row") {
            # Start with the first editable column (defaults generally to 'text')
            if (@($editableColumns).Count -gt 0) { $columnName = $editableColumns[0] }
            elseif (@($columns).Count -gt 0) { $columnName = $columns[0] }
        }
        elseif ($this.NavigationMode -eq "Cell" -and $this.SelectedColumn -lt @($columns).Count) {
            $tryCol = $columns[$this.SelectedColumn]
            if ($this.IsColumnEditable($tryCol)) { $columnName = $tryCol }
            else {
                # Find the next editable column from the current position (wrapping)
                for ($i = 1; $i -le @($columns).Count; $i++) {
                    $idx = ($this.SelectedColumn + $i) % @($columns).Count
                    $c = $columns[$idx]
                    if ($this.IsColumnEditable($c)) { $columnName = $c; break }
                }
            }
        }

        if ($columnName) {
            $currentItem = $this.CurrentData[$this.SelectedRow]
            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'Editing item' -Data $currentItem
            if ($this.PendingEdits.ContainsKey($columnName)) { $currentValue = [string]$this.PendingEdits[$columnName] }
            else { $currentValue = $this.GetItemValue($currentItem, $columnName) }

            $this.InEditMode = $true
            $this.EditingColumn = $columnName
            $this.EditingValue = $currentValue
            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Starting edit for column '{0}'" -f $columnName) -Data @{ Value=$currentValue }
            $this.ShowEditDialog($columnName, $currentValue)
        }
        else {
            Write-PmcDebug -Level 2 -Category 'DataDisplay' -Message 'StartCellEdit: Invalid mode or column'
        }
    }

    [void] ShowEditDialog([string]$ColumnName, [string]$CurrentValue) {
        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("ShowEditDialog: start '{0}'" -f $ColumnName)

        # Start inline editing mode
        $this.EditingValue = $CurrentValue
        $this.EditCursorPos = $CurrentValue.Length
        $this.InlineEditMode = $true
        $this.LastErrorMessage = ''

        while ($true) {
            # Redraw with edit indicator and get new value through key input
            $this.RefreshDisplay()
            $newVal = $this.HandleInlineEdit()

            if ($null -eq $newVal) {
                # Escape or navigation-only path: discard staged and exit dialog
                $this.CancelEdit()
                return
            }

            # Normalize then stage current column value
            try {
                $normalized = $this.NormalizeField($ColumnName, [string]$newVal)
            } catch {
                $this.LastErrorMessage = $_.Exception.Message
                # Re-enter editing on same column with user input intact
                $this.EditingValue = [string]$newVal
                $this.EditCursorPos = $this.EditingValue.Length
                $this.InlineEditMode = $true
                continue
            }
            $this.PendingEdits[$ColumnName] = [string]$normalized

            # Validate all staged edits
            $validationError = $null
            foreach ($col in @($this.PendingEdits.Keys)) {
                $val = [string]$this.PendingEdits[$col]
                if ($this.EditCallbacks.ContainsKey($col)) {
                    $ok = & $this.EditCallbacks[$col] $val
                    if (-not $ok) { $validationError = "Invalid value for $col"; break }
                } else {
                    try {
                        $this.ValidateField($col, $val)
                    } catch {
                        $validationError = $_.Exception.Message
                        break
                    }
                }
            }

            if ($validationError) {
                $this.LastErrorMessage = $validationError
                # Re-enter editing on current column
                $this.EditingValue = [string]$normalized
                $this.EditCursorPos = $this.EditingValue.Length
                $this.InlineEditMode = $true
                continue
            }

            # Apply batch and exit
            try {
                $this.ApplyPendingEdits()
                $this.LastErrorMessage = ''
                $this.CancelEdit()
                return
            } catch {
                $this.LastErrorMessage = "Failed to save: $($_.Exception.Message)"
                # Keep editing to allow correction
                $this.InlineEditMode = $true
            }
        }
    }

    # Per-field normalization moved to FieldSchemas

    [void] CancelEdit() {
        $this.InEditMode = $false
        $this.InlineEditMode = $false
        $this.EditingColumn = ""
        $this.EditingValue = ""
        # Clear pending edits without saving
        $this.PendingEdits.Clear()
        $this.RefreshDisplay()
    }

    [void] ApplyPendingEdits() {
        Write-PmcDebug -Level 2 -Category 'DataDisplay' -Message 'ApplyPendingEdits' -Data @{ Columns = @($this.PendingEdits.Keys) }
        foreach ($column in $this.PendingEdits.Keys) {
            $value = $this.PendingEdits[$column]
            try {
                # Inline editing: skip value conflict checks (opt-in strict policy can be implemented per-view later)
                $this.ApplyCellEdit($this.SelectedRow, $column, $value, $null)
                Write-PmcDebug -Level 2 -Category 'DataDisplay' -Message ("Applied edit for '{0}'" -f $column) -Data @{ Value=$value }
            } catch {
                Write-PmcDebug -Level 1 -Category 'DataDisplay' -Message ("Failed to apply edit for '{0}'" -f $column) -Data @{ Error = $_.ToString() }
            }
        }
        $this.PendingEdits.Clear()
    }

    [void] EnableInlineEditing([string]$Column, [scriptblock]$Validator) {
        if (-not $Column) { throw "EnableInlineEditing: Column is required" }
        $this.EditCallbacks[$Column] = $Validator
    }

    [void] ApplyCellEdit([int]$RowIndex, [string]$ColumnName, [string]$NewValue, [string]$OriginalValue) {
        if ($RowIndex -lt 0 -or $RowIndex -ge @($this.CurrentData).Count) { throw "Invalid row index" }
        $item = $this.CurrentData[$RowIndex]
        if (-not $item) { throw "No item at row $RowIndex" }

        # Wizard/form editing: in-memory only, no persistence
        $primaryDomain = $this.GetPrimaryDomain()
        if ($primaryDomain -eq 'wizard') {
            if ($item.PSObject.Properties[$ColumnName]) { $item.$ColumnName = [string]$NewValue }
            else { $item | Add-Member -NotePropertyName $ColumnName -NotePropertyValue ([string]$NewValue) -Force }
            return
        }

        # Update in persistent store by ID when available
        $id = $null
        if ($item.PSObject.Properties['id']) { $id = [int]$item.id }
        if ($null -eq $id) { throw "Cannot edit item without id" }

        $root = Get-PmcDataAlias
        if (-not $root -or -not $root.tasks) { throw "Data store not available" }

        $target = $root.tasks | Where-Object { $_ -ne $null -and $_.id -eq $id } | Select-Object -First 1
        if (-not $target) { throw "Item #$id not found" }

        # Optional optimistic concurrency check
        if ($OriginalValue -ne $null) {
            $currentOnDisk = ''
            if ($target.PSObject.Properties[$ColumnName]) { $currentOnDisk = [string]$target.$ColumnName }
            if ($currentOnDisk -ne $OriginalValue) {
                throw ("Conflict: {0} changed externally (was '{1}', now '{2}')" -f $ColumnName, $OriginalValue, $currentOnDisk)
            }
        }

        switch ($ColumnName) {
            'text'     { $target.text = [string]$NewValue }
            'project'  {
                $dataAll = Get-PmcDataAlias
                $resolved = Resolve-Project -Data $dataAll -Name ([string]$NewValue)
                if (-not $resolved) { throw ("Unknown project '{0}'" -f $NewValue) }
                $target.project = [string]$resolved.name
            }
            'priority' { $target.priority = [int]$NewValue }
            'due'      { $target.due = [string]$NewValue }
            default    { $target | Add-Member -NotePropertyName $ColumnName -NotePropertyValue $NewValue -Force }
        }

        Save-PmcData -data $root -Action "edit:$ColumnName"

        # Reflect changes in current view item as well
        if ($item.PSObject.Properties[$ColumnName]) { $item.$ColumnName = $NewValue }
        else { $item | Add-Member -NotePropertyName $ColumnName -NotePropertyValue $NewValue -Force }
    }

    [void] SaveChanges() {
        if ($this.SaveCallback) {
            & $this.SaveCallback @{}
            return
        }
        throw "No pending changes or SaveCallback configured"
    }

    [void] DeleteSelected() {
        # Only support deleting tasks for now
        if (-not ($this.Domains -contains 'task')) { throw "Delete not supported for this view" }
        if (@($this.CurrentData).Count -eq 0) { return }
        $rows = @()
        if ($this.MultiSelectMode -and @($this.SelectedRows).Count -gt 0) { $rows = @($this.SelectedRows) } else { $rows = @($this.SelectedRow) }
        $ids = @()
        foreach ($ri in $rows) {
            if ($ri -ge 0 -and $ri -lt @($this.CurrentData).Count) {
                $it = $this.CurrentData[$ri]
                if ($it -and $it.PSObject.Properties['id']) { $ids += [int]$it.id }
            }
        }
        if (@($ids).Count -eq 0) { return }

        $root = Get-PmcDataAlias
        if (-not $root -or -not $root.tasks) { throw "Data store not available" }
        $root.tasks = @($root.tasks | Where-Object { $_ -eq $null -or ($_.PSObject.Properties['id'] -and (-not ($ids -contains [int]$_.id))) })
        Save-PmcData -data $root -Action 'delete:task'
        $this.RefreshData()
    }

    [void] Undo() {
        if (Get-Command Invoke-PmcUndo -ErrorAction SilentlyContinue) {
            Invoke-PmcUndo | Out-Null
            $this.RefreshData()
            return
        }
        throw "Undo not available"
    }

    [void] PromptDoFilter() {
        $row = [PmcTerminalService]::GetHeight() - 2
        Write-Host ([PmcVT]::MoveTo(0, $row) + [PmcVT]::ClearLine())
        Write-Host -NoNewline "DoFilter (text or re:/pattern/): "
        $q = Read-Host
        if ($null -ne $q) { $this.FilterQuery = [string]$q; $this.ApplyDoFilter(); $this.RefreshDisplay() }
    }

    [void] RefreshData() {
        # Reload data from PMC and refresh display
        if ($this.Interactive) {
            $newData = Get-PmcFilteredData -Domains $this.Domains -Filters $this.Filters
            $this.AllData = $newData
            $this.ApplyDoFilter()
            $this.RefreshDisplay()
        }
    }

    [void] SwitchNavigationMode([bool]$Reverse = $false) {
        if ($Reverse) {
            $this.NavigationMode = $(if ($this.NavigationMode -eq "Row") { "Cell" } else { "Row" })
        } else {
            $this.NavigationMode = $(if ($this.NavigationMode -eq "Cell") { "Row" } else { "Cell" })
        }
        $this.RefreshDisplay()
    }

    [string] HandleInlineEdit() {
        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'HandleInlineEdit: start'

        $editBuffer = $this.EditingValue
        $cursorPos = $this.EditCursorPos

        while ($this.InlineEditMode) {
            try {
                if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $keyName = $key.Key.ToString()

                Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'Inline edit key' -Data @{ Key=$keyName; Char=[int]$key.KeyChar }

                switch ($key.Key) {
                    "Enter" {
                        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'Enter: save current field and exit edit mode' -Data @{ Value=$editBuffer }

                        # Store current field edit in pending edits
                        $this.PendingEdits[$this.EditingColumn] = $editBuffer
                        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Staged final edit for '{0}' on Enter" -f $this.EditingColumn) -Data @{ Value=$editBuffer }

                        # Exit edit mode and signal to save all pending edits
                        $this.InlineEditMode = $false
                        return $editBuffer
                    }
                    "Escape" {
                        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'Inline edit cancelled'
                        $this.InlineEditMode = $false
                        return $null
                    }
                    "Tab" {
                        # Check for Shift modifier
                        if ($key.Modifiers -band [ConsoleModifiers]::Shift) {
                            # Shift+Tab moves to previous column
                            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'Shift+Tab: previous column'

                            # Store current edit in memory instead of saving immediately
                            $this.PendingEdits[$this.EditingColumn] = $editBuffer
                            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Staged edit for '{0}'" -f $this.EditingColumn) -Data @{ Value=$editBuffer }

                            # Move to previous column
                            $this.MoveToPreviousColumnAndEdit()
                            return $null
                        } else {
                            # Tab moves to next column and continues editing
                            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'Tab: next column'

                            # Store current edit in memory instead of saving immediately
                            $this.PendingEdits[$this.EditingColumn] = $editBuffer
                            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Staged edit for '{0}'" -f $this.EditingColumn) -Data @{ Value=$editBuffer }

                            # Move to next column
                            $this.MoveToNextColumnAndEdit()
                            return $null  # Don't return the value, we're continuing to edit
                        }
                    }
                    "LeftArrow" {
                        if ($cursorPos -gt 0) {
                            $cursorPos--
                            $this.EditCursorPos = $cursorPos
                            $this.RefreshDisplay()
                        }
                    }
                    "RightArrow" {
                        if ($cursorPos -lt $editBuffer.Length) {
                            $cursorPos++
                            $this.EditCursorPos = $cursorPos
                            $this.RefreshDisplay()
                        }
                    }
                    "Home" {
                        $cursorPos = 0
                        $this.EditCursorPos = $cursorPos
                        $this.RefreshDisplay()
                    }
                    "End" {
                        $cursorPos = $editBuffer.Length
                        $this.EditCursorPos = $cursorPos
                        $this.RefreshDisplay()
                    }
                    "Backspace" {
                        if ($cursorPos -gt 0) {
                            $editBuffer = $editBuffer.Remove($cursorPos - 1, 1)
                            $cursorPos--
                            $this.EditingValue = $editBuffer
                            $this.EditCursorPos = $cursorPos
                            $this.RefreshDisplay()
                        }
                    }
                    "Delete" {
                        if ($cursorPos -lt $editBuffer.Length) {
                            $editBuffer = $editBuffer.Remove($cursorPos, 1)
                            $this.EditingValue = $editBuffer
                            $this.RefreshDisplay()
                        }
                    }
                    default {
                        # Add printable characters at cursor position
                        if ($key.KeyChar -and [int]$key.KeyChar -ge 32 -and [int]$key.KeyChar -le 126) {
                            $editBuffer = $editBuffer.Insert($cursorPos, $key.KeyChar)
                            $cursorPos++
                            $this.EditingValue = $editBuffer
                            $this.EditCursorPos = $cursorPos
                            $this.RefreshDisplay()
                        }
                    }
                }
                } else {
                    Start-Sleep -Milliseconds 50
                }
            } catch {
                # Fallback for non-interactive environments
                Start-Sleep -Milliseconds 50
            }
        }
        return $null
    }

    [void] MoveToNextColumnAndEdit() {
        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'MoveToNextColumnAndEdit'
        $columns = $this.GetEditableColumns()
        if (@($columns).Count -eq 0) { $this.CancelEdit(); return }
        $currentIndex = $columns.IndexOf($this.EditingColumn)
        if ($currentIndex -lt 0) { $currentIndex = 0 }
        $nextIndex = ($currentIndex + 1) % @($columns).Count
        $nextColumn = $columns[$nextIndex]
        $currentItem = $this.CurrentData[$this.SelectedRow]
        if ($this.PendingEdits.ContainsKey($nextColumn)) {
            $nextValue = $this.PendingEdits[$nextColumn]
                Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Using staged value for '{0}'" -f $nextColumn) -Data @{ Value=$nextValue }
        } else {
            $nextValue = $this.GetItemValue($currentItem, $nextColumn)
                Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Using original value for '{0}'" -f $nextColumn) -Data @{ Value=$nextValue }
        }

            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Move edit focus: '{0}' -> '{1}'" -f $this.EditingColumn, $nextColumn)

        $this.EditingColumn = $nextColumn
        $this.EditingValue = $nextValue
        $this.EditCursorPos = $nextValue.Length
        $this.InlineEditMode = $true
        $this.RefreshDisplay()

        # Continue editing the new column
            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'Continue edit on new column'
        $newVal = $this.HandleInlineEdit()
        if ($newVal -ne $null) {
            # Store the edit in memory instead of applying immediately
            $this.PendingEdits[$nextColumn] = $newVal
                Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Staged final value for '{0}'" -f $nextColumn) -Data @{ Value=$newVal }
        }
    }

    [void] MoveToPreviousColumnAndEdit() {
        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'MoveToPreviousColumnAndEdit'
        $columns = $this.GetEditableColumns()
        if (@($columns).Count -eq 0) { $this.CancelEdit(); return }
        $currentIndex = $columns.IndexOf($this.EditingColumn)
        if ($currentIndex -lt 0) { $currentIndex = 0 }
        $prevIndex = ($currentIndex - 1)
        if ($prevIndex -lt 0) { $prevIndex = @($columns).Count - 1 }
        $prevColumn = $columns[$prevIndex]
        $currentItem = $this.CurrentData[$this.SelectedRow]
        if ($this.PendingEdits.ContainsKey($prevColumn)) {
            $prevValue = $this.PendingEdits[$prevColumn]
                Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Using staged value for '{0}'" -f $prevColumn) -Data @{ Value=$prevValue }
        } else {
            $prevValue = $this.GetItemValue($currentItem, $prevColumn)
                Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Using original value for '{0}'" -f $prevColumn) -Data @{ Value=$prevValue }
        }

            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Move edit focus: '{0}' -> '{1}'" -f $this.EditingColumn, $prevColumn)

        $this.EditingColumn = $prevColumn
        $this.EditingValue = $prevValue
        $this.EditCursorPos = $prevValue.Length
        $this.InlineEditMode = $true
        $this.RefreshDisplay()

        # Continue editing the new column
            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'Continue edit on previous column'
        $newVal = $this.HandleInlineEdit()
        if ($newVal -ne $null) {
            # Store the edit in memory instead of applying immediately
            $this.PendingEdits[$prevColumn] = $newVal
                Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Staged final value for '{0}'" -f $prevColumn) -Data @{ Value=$newVal }
        }
    }

    [string[]] GetEditableColumns() {
        $cols = @()
        foreach ($c in $this.ColumnConfig.Keys) {
            if ($this.IsColumnEditable($c)) { $cols += $c }
        }
        return $cols
    }

    [bool] IsColumnEditable([string]$ColumnName) {
        if (-not $this.ColumnConfig.Keys -contains $ColumnName) { return $false }
        $cfg = $this.ColumnConfig[$ColumnName]
        $sch = $this.GetFieldSchema($ColumnName)
        $editable = $true
        if ($cfg.PSObject.Properties['Editable']) { $editable = [bool]$cfg.Editable }
        elseif ($sch -and $sch.ContainsKey('Editable')) { $editable = [bool]$sch.Editable }
        else { $editable = $true }

        $sensitive = $false
        if ($cfg.PSObject.Properties['Sensitive']) { $sensitive = [bool]$cfg.Sensitive }
        elseif ($sch -and $sch.ContainsKey('Sensitive')) { $sensitive = [bool]$sch.Sensitive }
        if ($sensitive -and (-not $this.AllowSensitiveEdits)) { return $false }
        return $editable
    }

    [void] ExitInteractive() {
        $this.Interactive = $false
        Write-Host ([PmcVT]::Show())  # Show cursor
    }

    # Display refresh method (Praxis frame-based rendering only)
    [void] RefreshDisplay() {
        if (-not $this.Interactive) { return }

        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'RefreshDisplay (Praxis frame)' -Data @{ Row=$this.SelectedRow }

        # Build complete frame content using Praxis approach (single owner painter)
        $title = $(if ([string]::IsNullOrWhiteSpace($this.TitleText)) { 'PMC Interactive Data Grid' } else { $this.TitleText })
        $frameContent = [PraxisGridFrameBuilder]::BuildGridFrame(
            $this.CurrentData,
            $this.ColumnConfig,
            $title,
            $this.SelectedRow,
            $this.ThemeConfig,
            $this
        )

        # Single atomic write with internal double-buffering
        $this.FrameRenderer.RenderFrame($frameContent)
    }

    [string[]] RenderGridWithinBounds([object[]]$Data, [object]$ContentBounds) {
        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'RenderGridWithinBounds' -Data @{
            DataCount = @($Data).Count
            BoundsWidth = $ContentBounds.Width
            BoundsHeight = $ContentBounds.Height
        }

        # Use content bounds for width/height when computing column layout
        $oldWidth = $this.TerminalWidth
        $oldHeight = $this.WindowHeight
        try {
            $this.TerminalWidth = [int]$ContentBounds.Width
            $this.WindowHeight = [int]$ContentBounds.Height
        } catch {}

        # Build lines with adjusted bounds
        $this.CurrentData = $Data
        $allLines = $this.BuildInteractiveLines()

        # Restore previous metrics
        $this.TerminalWidth = $oldWidth
        $this.WindowHeight = $oldHeight

        # Truncate to fit within content bounds
        $maxLines = $ContentBounds.Height - 1  # Reserve space for status
        $gridLines = @()

        for ($i = 0; $i -lt [Math]::Min($allLines.Count, $maxLines); $i++) {
            $line = $allLines[$i]
            # Truncate line to fit width
            if ($line.Length -gt $ContentBounds.Width) {
                $line = $line.Substring(0, $ContentBounds.Width - 3) + "..."
            }
            $gridLines += $line
        }

        return $gridLines
    }

    [void] ShowStatusLine() {
        $statusRow = [PmcTerminalService]::GetHeight() - 1
        $mode = $(if ($this.NavigationMode -eq "Cell") { "CELL" } else { "ROW" })
        $shownStart = [Math]::Min(@($this.CurrentData).Count, $this.ScrollOffset + 1)
        $visible = [Math]::Max(1, [PmcTerminalService]::GetHeight() - ($this.HeaderLines + 1))
        $shownEnd = [Math]::Min(@($this.CurrentData).Count, $this.ScrollOffset + $visible)
        $position = "[$($this.SelectedRow + 1)/$(@($this.CurrentData).Count) | $shownStart-$shownEnd]"
        $selection = $(if ($this.MultiSelectMode -and @($this.SelectedRows).Count -gt 1) { " [$(@($this.SelectedRows).Count) selected]" } else { "" })
        $filter = $(if ($this.FilterQuery) { " | Filter: '$($this.FilterQuery)'" } else { '' })
        $sort = $(if ($this.SortDirection -ne 'None' -and $this.SortColumn) { " | Sort: $($this.SortColumn) $($this.SortDirection.ToLower())" } else { '' })
        $status = "$mode $position$selection$filter$sort | Arrow keys: Navigate | Enter: Edit | Tab: Switch mode | F3: Sort | F6/F7: Save/Load view | Q: Exit"

        Write-Host ([PmcVT]::MoveTo(0, $statusRow) + [PmcVT]::ClearLine())
        Write-PmcStyled -Style 'Muted' -Text $status -NoNewline
    }

    [hashtable] GetColumnWidths([object[]]$Data) {
        $widths = @{}
        $totalFixed = 0
        $flexColumns = @()

        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'GetColumnWidths' -Data @{ Width=$this.TerminalWidth; Count=$this.ColumnConfig.Keys.Count }

        # Smart default widths for common columns
        $smartDefaults = @{
            "due" = 10          # yyyy-MM-dd = 10 chars
            "priority" = 3      # P1/P2/P3 = 3 chars
            "P" = 3
            "#" = 4             # Task numbers
            "id" = 4
        }

        # Calculate fixed widths and identify flex columns (respect schema MinWidth)
        foreach ($col in $this.ColumnConfig.Keys) {
            $minW = 0
            $sch = $this.GetFieldSchema($col)
            if ($sch -and $sch.ContainsKey('MinWidth')) { try { $minW = [int]$sch.MinWidth } catch { $minW = 0 } }
            if ($smartDefaults.ContainsKey($col)) {
                # Smart defaults ALWAYS take priority for known column types
                $widths[$col] = [Math]::Max($minW, $smartDefaults[$col])
                $totalFixed += $widths[$col]
            } elseif ($this.ColumnConfig[$col].Width) {
                # Explicit width for custom columns only
                $widths[$col] = [Math]::Max($minW, [int]$this.ColumnConfig[$col].Width)
                $totalFixed += $widths[$col]
            } else {
                # This is a flex column (will get remaining space)
                $flexColumns += $col
            }
        }

        # Calculate available space for flex columns
        $padding = (@($this.ColumnConfig.Keys).Count - 1) * 2  # 2 spaces between columns
        $available = $this.TerminalWidth - $totalFixed - $padding - 4  # 4 for margins

        if (@($flexColumns).Count -gt 0) {
            $flexBase = [Math]::Max(8, [Math]::Floor($available / @($flexColumns).Count))
            foreach ($col in $flexColumns) {
                $minW = 0
                $sch2 = $this.GetFieldSchema($col)
                if ($sch2 -and $sch2.ContainsKey('MinWidth')) { try { $minW = [int]$sch2.MinWidth } catch { $minW = 0 } }
                $widths[$col] = [Math]::Max($minW, $flexBase)
            }
        }

        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'GetColumnWidths result' -Data $widths
        return $widths
    }

    [string] FormatRow([object]$Item, [hashtable]$Widths, [bool]$IsHeader = $false, [int]$RowIndex = 0, [bool]$IsSelected = $false) {
        $parts = @()

        foreach ($col in $this.ColumnConfig.Keys) {
            $width = $Widths[$col]
            $formatted = ""
            $colConfig = $this.ColumnConfig[$col]

            if ($IsHeader) {
                $value = $(if ($colConfig.PSObject.Properties['Header']) { $colConfig.Header } else { $col })
            } else {
                $value = $this.GetItemValue($Item, $col)
            }

            # Apply truncation if needed
            if ($colConfig.PSObject.Properties['Truncate'] -and $colConfig.Truncate -and $value.Length -gt $width) {
                $value = $value.Substring(0, $width - 3) + "..."
            } elseif ($value.Length -gt $width) {
                $value = $value.Substring(0, $width)
            }

            # Apply alignment
            $alignment = $(if ($colConfig.PSObject.Properties['Alignment'] -and $colConfig.Alignment) { $colConfig.Alignment } else { "Left" })

            switch ($alignment) {
                "Right" { $formatted = $value.PadLeft($width) }
                "Center" {
                    $padding = $width - $value.Length
                    $leftPad = [Math]::Floor($padding / 2)
                    $rightPad = $padding - $leftPad
                    $formatted = " " * $leftPad + $value + " " * $rightPad
                }
                default { $formatted = $value.PadRight($width) }  # Left
            }

            # Apply theming to the formatted cell content
            $cellTheme = $this.GetCellTheme($Item, $col, $RowIndex, $IsHeader)

            # Apply selection highlighting
            if ($IsSelected -and -not $IsHeader) {
                $cellTheme = $this.MergeStyles($cellTheme, @{ Bg = "#0078d4"; Fg = "White" })
            }

            # Emphasize currently editing cell
            if ($this.InEditMode -and -not $IsHeader -and $RowIndex -eq $this.SelectedRow) {
                $cols = @($this.ColumnConfig.Keys)
                if ($this.NavigationMode -eq 'Cell' -and $this.SelectedColumn -lt @($cols).Count) {
                    if ($col -eq $cols[$this.SelectedColumn]) { $cellTheme = $this.MergeStyles($cellTheme, @{ Bold = $true }) }
                }
            }

            $themedText = $this.ApplyTheme($formatted, $cellTheme)
            $parts += $themedText
        }

        # Add selection indicator for row mode
        $indicator = $(if ($IsSelected -and -not $IsHeader) { "►" } else { " " })
        return "$indicator " + ($parts -join "  ")
    }

    [string] GetItemValue([object]$Item, [string]$ColumnName) {
        try {
            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("GetItemValue: '{0}'" -f $ColumnName)
            switch ($ColumnName) {
                "id" {
                    $val = (Pmc-GetProp $Item 'id' '') -as [string]
                    Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'GetItemValue: id' -Data @{ Value=$val }
                    return $val
                }
                "text" {
                    $val = (Pmc-GetProp $Item 'text' '') -as [string]
                    Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message 'GetItemValue: text' -Data @{ Value=$val }
                    return $val
                }
                "Task" { return (Pmc-GetProp $Item 'text' '') -as [string] }  # Map Task to text
                "project" {
                    $projectId = (Pmc-GetProp $Item 'project' 'inbox') -as [string]
                    # Resolve project name if lookup is available
                    if ($this.ProjectLookup -and $this.ProjectLookup.PSObject.Properties[$projectId]) {
                        return $this.ProjectLookup[$projectId]
                    }
                    return $projectId
                }
                "due" {
                    $dueVal = (Pmc-GetProp $Item 'due' $null)
                    if ($dueVal) {
                        try {
                            $date = [datetime]$dueVal
                            return $date.ToString('MM/dd')
                        } catch {
                            return [string]$dueVal
                        }
                    }
                    return ""
                }
                "priority" {
                    $p = (Pmc-GetProp $Item 'priority' 0)
                    if ($p -and $p -le 3) {
                        return "P$($p)"
                    }
                    return ""
                }
                "status" {
                    if ($Item.status) {
                        return $Item.status
                    } else {
                        return "pending"
                    }
                }
                default {
                    # Dynamic property access
                    if ($Item.PSObject.Properties[$ColumnName]) {
                        return $Item.$ColumnName.ToString()
                    }
                    return ""
                }
            }
            return ""
        } catch {
            return ""
        }
    }

    [object[]] RenderGrid([object[]]$Data) {
        return $this.BuildInteractiveLines()
    }

    [object[]] BuildInteractiveLines() {
        $lines = @()
        if (-not $this.CurrentData -or @($this.CurrentData).Count -eq 0) {
            $lines += $this.StyleText('Muted', '  No data to display')
            return $lines
        }
        # Recalculate terminal metrics and adjust layout
        try {
            $this.TerminalWidth = $this.GetTerminalWidth()
            $this.WindowHeight = $this.GetTerminalHeight()
        } catch {}
        $widths = $this.GetColumnWidths($this.CurrentData)
        if ($this.ShowInternalHeader) {
            $lines += $this.StyleText('Title', $this.TitleText)
            $lines += $this.StyleText('Border', ("═" * 50))
        }
        $headerLine = $this.FormatRow($null, $widths, $true, -1, $false)
        if ($this.SortDirection -ne 'None' -and $this.SortColumn) {
            $arrow = $(if ($this.SortDirection -eq 'Asc') { '↑' } else { '↓' })
            $headerLine = $headerLine + "  (sorted by $($this.SortColumn) $arrow)"
        }
        $lines += $headerLine
        $separatorParts = @(); foreach ($col in $this.ColumnConfig.Keys) { $separatorParts += "─" * $widths[$col] }
        $separatorLine = "  " + ($separatorParts -join "  ")
        $lines += $this.StyleText('Border', $separatorLine)
        # Determine visible rows based on window height
        $available = [Math]::Max(1, $this.WindowHeight - ($this.HeaderLines + 1))
        $this.EnsureInView()
        $start = $this.ScrollOffset
        $endExclusive = [Math]::Min(@($this.CurrentData).Count, $start + $available)
        for ($i = $start; $i -lt $endExclusive; $i++) {
            $item = $this.CurrentData[$i]
            $isSelected = ($i -eq $this.SelectedRow) -or ($this.MultiSelectMode -and $this.SelectedRows -contains $i)
            $lines += $this.FormatRow($item, $widths, $false, $i, $isSelected)
        }
        # Indicate more content above/below when scrolled
        if ($this.ScrollOffset -gt 0) { $lines[$this.HeaderLines] = ("↑ " + ($lines[$this.HeaderLines].Substring(2))) }
        if ($endExclusive -lt @($this.CurrentData).Count) { $lines[@($lines).Count-1] = ($lines[@($lines).Count-1] + ' …') }
        return $lines
    }

    [void] EnsureInView() {
        $this.WindowHeight = $this.GetTerminalHeight()
        $available = [Math]::Max(1, $this.WindowHeight - ($this.HeaderLines + 1))
        if ($this.SelectedRow -lt $this.ScrollOffset) { $this.ScrollOffset = $this.SelectedRow }
        elseif ($this.SelectedRow -ge ($this.ScrollOffset + $available)) { $this.ScrollOffset = $this.SelectedRow - $available + 1 }
        if ($this.ScrollOffset -lt 0) { $this.ScrollOffset = 0 }
    }

    [string] StyleText([string]$StyleToken, [string]$Text) {
        $sty = Get-PmcStyle $StyleToken
        $styledText = $this.ConvertPmcStyleToAnsi($Text, $sty, @{})

        # Apply screen bounds enforcement
        return $this.EnforceScreenBounds($styledText, 0, 0)
    }

    # Main interactive method
    [void] StartInteractive([object[]]$Data) {
        Write-PmcDebug -Level 1 -Category 'Grid' -Message "StartInteractive called" -Data @{ DataCount = @($Data).Count }
        $this.Interactive = $true
        $this.AllData = $Data
        $this.ApplyDoFilter()
        $this.SelectedRow = 0
        $this.SelectedColumn = 0
        $this.MultiSelectMode = $false
        $this.SelectedRows = @()
        $this.HasInitialRender = $false
        $this.LastLines = @()
        $this.LastRefreshAt = Get-Date

        # Hide cursor for cleaner display
        Write-Host ([PmcVT]::Hide())
        Write-PmcDebug -Level 1 -Category 'Grid' -Message "Starting interactive loop"

        try {
            # Initial display
            $this.RefreshDisplay()

            # Main input loop
            while ($this.Interactive) {
                try {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        Write-PmcDebug -Level 2 -Category 'Grid' -Message "Key pressed" -Data @{ Key = $key.Key; KeyChar = $key.KeyChar }
                        $this.HandleKeyPress($key)
                    } else {
                        if ($this.RefreshIntervalMs -gt 0) {
                            $now = Get-Date
                            if ((($now - $this.LastRefreshAt).TotalMilliseconds) -ge $this.RefreshIntervalMs) {
                                $this.LastRefreshAt = $now
                                $this.RefreshDisplay()
                            }
                        }
                        Start-Sleep -Milliseconds 50
                    }
                } catch {
                    # Fallback for non-interactive or redirected environments
                    Start-Sleep -Milliseconds 50
                    if ($this.RefreshIntervalMs -gt 0) {
                        $now = Get-Date
                        if ((($now - $this.LastRefreshAt).TotalMilliseconds) -ge $this.RefreshIntervalMs) {
                            $this.LastRefreshAt = $now
                            $this.RefreshData()
                        }
                    }
                    Start-Sleep -Milliseconds 50
                }
            }
        }
        finally {
            # Always restore cursor visibility
            Write-Host ([PmcVT]::Show())
        }
    }

    [void] HandleKeyPress([ConsoleKeyInfo]$Key) {
        $keyName = $Key.Key.ToString()

        # Handle modifier keys
        if ($Key.Modifiers -band [ConsoleModifiers]::Shift) {
            $keyName = "Shift+$keyName"
        }
        if ($Key.Modifiers -band [ConsoleModifiers]::Control) {
            $keyName = "Ctrl+$keyName"
        }

        Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Key pressed: '{0}'" -f $keyName)

        # Execute key binding if it exists
        if ($this.KeyBindings.ContainsKey($keyName)) {
            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("Execute key binding: '{0}'" -f $keyName)
            try {
                & $this.KeyBindings[$keyName]
            } catch {
                Write-PmcDebug -Level 1 -Category 'DataDisplay' -Message ("Key binding error: '{0}'" -f $keyName) -Data @{ Error = $_.Exception.Message }
                Write-PmcDebug -Level 1 -Category "DataDisplay" -Message "Key binding error" -Data @{
                    Key = $keyName;
                    Error = $_.Exception.Message
                }
            }
        } else {
            Write-PmcDebug -Level 3 -Category 'DataDisplay' -Message ("No key binding for: '{0}'" -f $keyName)
            # Type-to-filter: accept printable chars; Backspace handled here when not bound
            $ch = $Key.KeyChar
            if ([int]$ch -ge 32 -and [int]$ch -le 126 -and -not ($Key.Modifiers -band [ConsoleModifiers]::Control)) {
                $this.FilterQuery += [string]$ch
                $this.ApplyDoFilter(); $this.RefreshDisplay(); return
            }
            if ($Key.Key -eq [ConsoleKey]::Backspace -and -not ($Key.Modifiers -band [ConsoleModifiers]::Control)) {
                if ($this.FilterQuery.Length -gt 0) { $this.FilterQuery = $this.FilterQuery.Substring(0, $this.FilterQuery.Length - 1); $this.ApplyDoFilter(); $this.RefreshDisplay(); return }
            }
            # Unhandled key - ignore
        }
    }

    [void] ToggleSortCurrentColumn() {
        $columns = @($this.ColumnConfig.Keys)
        $col = ''
        if ($this.NavigationMode -eq 'Cell' -and $this.SelectedColumn -lt @($columns).Count) {
            $col = $columns[$this.SelectedColumn]
        } else {
            if (@($columns).Count -gt 0) { $col = $columns[0] }
        }
        if (-not $col) { return }
        if ($this.SortColumn -ne $col) { $this.SortColumn = $col; $this.SortDirection = 'Asc' }
        else {
            switch ($this.SortDirection) {
                'Asc'  { $this.SortDirection = 'Desc' }
                'Desc' { $this.SortDirection = 'None' }
                default { $this.SortDirection = 'Asc' }
            }
        }
        $this.ApplyDoFilter(); $this.RefreshDisplay()
    }

    [void] PromptSaveView() {
        $row = [PmcTerminalService]::GetHeight() - 2
        Write-Host ([PmcVT]::MoveTo(0, $row) + [PmcVT]::ClearLine())
        Write-Host -NoNewline "Save view as: "
        $name = Read-Host
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $this.SavedViews[$name] = @{
            Filters = $this.Filters.Clone()
            Columns = $this.ColumnConfig.Clone()
            Theme   = $this.ThemeConfig
            Sort    = @{ Column=$this.SortColumn; Direction=$this.SortDirection }
            Query   = $this.FilterQuery
        }
        $this.PersistSavedViews()
        Write-Host ([PmcVT]::MoveTo(0, $row) + [PmcVT]::ClearLine())
        Write-PmcStyled -Style 'Success' -Text ("Saved view: {0}" -f $name)
    }

    [void] PromptLoadView() {
        if ($this.SavedViews.Keys.Count -eq 0) { return }
        $row = [PmcTerminalService]::GetHeight() - 2
        Write-Host ([PmcVT]::MoveTo(0, $row) + [PmcVT]::ClearLine())
        Write-Host -NoNewline ("Load view [{0}]: " -f ($this.SavedViews.Keys -join ', '))
        $name = Read-Host
        if (-not $this.SavedViews.ContainsKey($name)) { return }
        $v = $this.SavedViews[$name]
        $this.Filters = $v.Filters
        $this.ColumnConfig = $v.Columns
        $this.ThemeConfig = $v.Theme
        $this.SortColumn = $v.Sort.Column
        $this.SortDirection = $v.Sort.Direction
        $this.FilterQuery = $v.Query
        $this.RefreshData()
    }

    [void] ListSavedViews() {
        $row = [PmcTerminalService]::GetHeight() - 2
        Write-Host ([PmcVT]::MoveTo(0, $row) + [PmcVT]::ClearLine())
        if ($this.SavedViews.Keys.Count -eq 0) { Write-PmcStyled -Style 'Muted' -Text 'No saved views'; return }
        Write-PmcStyled -Style 'Body' -Text ("Saved views: {0}" -f ($this.SavedViews.Keys -join ', '))
    }

    [void] LoadSavedViews() {
        $cfg = Get-PmcConfig
        if ($cfg -and $cfg.ContainsKey('Display') -and $cfg.Display -and $cfg.Display.ContainsKey('GridViews')) {
            $views = $cfg.Display.GridViews
            if ($views -is [hashtable]) { $this.SavedViews = $views }
        }
    }

    [void] PersistSavedViews() {
        $cfg = Get-PmcConfig
        if (-not $cfg.ContainsKey('Display')) { $cfg['Display'] = @{} }
        $cfg.Display['GridViews'] = $this.SavedViews
        Save-PmcConfig $cfg
    }

    [void] ApplyDoFilter() {
        if (-not $this.AllData) { $this.CurrentData = @(); return }
        if ([string]::IsNullOrWhiteSpace($this.FilterQuery)) { $this.CurrentData = $this.AllData; return }
        $q = $this.FilterQuery.ToLowerInvariant()
        $isRegex = $false
        $pattern = $null
        if ($q.StartsWith('re:')) { $isRegex = $true; $pattern = $q.Substring(3) }
        elseif ($this.FilterQuery.StartsWith('/') -and $this.FilterQuery.EndsWith('/')) { $isRegex = $true; $pattern = $this.FilterQuery.Trim('/') }
        $filtered = @()
        foreach ($it in $this.AllData) {
            if ($it -eq $null) { continue }
            $t = ''
            if ($it.PSObject.Properties['text'] -and $it.text) { $t = [string]$it.text }
            $p = ''
            if ($it.PSObject.Properties['project'] -and $it.project) { $p = [string]$it.project }
            $d = ''
            if ($it.PSObject.Properties['due'] -and $it.due) { $d = [string]$it.due }
            $hay = ($t + ' ' + $p + ' ' + $d).ToLowerInvariant()
            if ($isRegex) {
                if ($hay -match $pattern) { $filtered += $it }
            } else {
                if ($hay.Contains($q)) { $filtered += $it }
            }
        }
        # Apply sorting to filtered results
        if ($this.SortDirection -ne 'None' -and $this.SortColumn) {
            $key = $this.SortColumn; $asc = ($this.SortDirection -eq 'Asc')
            $filtered = @($filtered | Sort-Object -Property @{Expression={ if ($_.PSObject.Properties[$key]) { $_.$key } else { $null } }; Ascending=$asc})
        }
        $this.CurrentData = $filtered
        if ($this.SelectedRow -ge @($this.CurrentData).Count) { $this.SelectedRow = [Math]::Max(0, @($this.CurrentData).Count - 1) }
    }

    [void] RenderStaticGrid([array]$Data) {
        # Simple non-interactive grid rendering for compatibility
        if (-not $Data -or @($Data).Count -eq 0) {
            Write-PmcStyled -Style 'Muted' -Text "No items to display"
            return
        }

        $this.AllData = $Data
        $this.CurrentData = $Data
        $widths = $this.GetColumnWidths($Data)

        # Display header
        $headerLine = $this.FormatRow($null, $widths, $true, -1, $false)
        Write-Host $headerLine

        # Display separator
        $sepParts = @()
        foreach ($col in $this.ColumnConfig.Keys) {
            $sepParts += "─" * $widths[$col]
        }
        Write-Host ("  " + ($sepParts -join "  "))

        # Display data rows
        for ($i = 0; $i -lt @($Data).Count; $i++) {
            $item = $Data[$i]
            if ($item -ne $null) {
                $line = $this.FormatRow($item, $widths, $false, $i, $false)
                Write-Host $line
            }
        }
    }

    [void] StartInteractiveMode([hashtable]$Config) {
        # Optional configurator compatible with plan terminology
        if ($Config -and $Config.ContainsKey('AllowEditing')) { $this.LiveEditing = [bool]$Config.AllowEditing }
        if ($Config -and $Config.ContainsKey('SaveCallback')) { $this.SaveCallback = [scriptblock]$Config.SaveCallback }
        if ($this.CurrentData -and @($this.CurrentData).Count -gt 0) { $this.StartInteractive($this.CurrentData) }
    }

    [void] MoveToColumnStart() {
        if ($this.NavigationMode -ne 'Cell') { return }
        $this.SelectedColumn = 0
        $this.RefreshDisplay()
    }

    [void] MoveToColumnDoEnd() {
        if ($this.NavigationMode -ne 'Cell') { return }
        $columns = @($this.ColumnConfig.Keys)
        if ($columns.Count -gt 0) { $this.SelectedColumn = $columns.Count - 1 }
        $this.RefreshDisplay()
    }
}

function Get-PmcFilteredData {
    param(
        [string[]]$Domains,
        [hashtable]$Filters
    )

    $data = Get-PmcDataAlias
    $results = @()

    foreach ($domain in $Domains) {
        switch ($domain) {
            "task" {
                $items = $(if ($data.tasks) { @($data.tasks) } else { @() })

                # Apply filters
                if ($Filters.PSObject.Properties['status'] -and $Filters.status) {
                    $items = @($items | Where-Object { $_.PSObject.Properties['status'] -and $_.status -eq $Filters.status })
                }

                if ($Filters.PSObject.Properties['due_range'] -and $Filters.due_range) {
                    $today = (Get-Date).Date
                    switch ($Filters.due_range) {
                        "overdue_and_today" {
                            $items = @($items | Where-Object {
                                if (-not ($_.PSObject.Properties['due'] -and $_.due -and ($_.due -is [string]) -and $_.due -match '^\d{4}-\d{2}-\d{2}$')) { return $false }
                                $d = [datetime]::ParseExact([string]$_.due, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                                return ($d.Date -le $today)
                            })
                        }
                        "today" {
                            $items = @($items | Where-Object {
                                if (-not ($_.PSObject.Properties['due'] -and $_.due -and ($_.due -is [string]) -and $_.due -match '^\d{4}-\d{2}-\d{2}$')) { return $false }
                                $d = [datetime]::ParseExact([string]$_.due, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                                return ($d.Date -eq $today)
                            })
                        }
                        "overdue" {
                            $items = @($items | Where-Object {
                                if (-not ($_.PSObject.Properties['due'] -and $_.due -and ($_.due -is [string]) -and $_.due -match '^\d{4}-\d{2}-\d{2}$')) { return $false }
                                $d = [datetime]::ParseExact([string]$_.due, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                                return ($d.Date -lt $today)
                            })
                        }
                        "upcoming" {
                            $weekFromNow = $today.AddDays(7)
                            $items = @($items | Where-Object {
                                if (-not ($_.PSObject.Properties['due'] -and $_.due -and ($_.due -is [string]) -and $_.due -match '^\d{4}-\d{2}-\d{2}$')) { return $false }
                                $d = [datetime]::ParseExact([string]$_.due, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                                return ($d.Date -gt $today -and $d.Date -le $weekFromNow)
                            })
                        }
                    }
                }

                if ($Filters.ContainsKey('project') -and $Filters.project) {
                    $items = @($items | Where-Object { $_.PSObject.Properties['project'] -and $_.project -eq $Filters.project })
                }

                if ($Filters.PSObject.Properties['blocked'] -and $Filters.blocked) {
                    $items = @($items | Where-Object { $_ -ne $null -and $_.PSObject.Properties['blocked'] -and $_.blocked })
                }

                if ($Filters.PSObject.Properties['no_due_date'] -and $Filters.no_due_date) {
                    $items = @($items | Where-Object { $_ -ne $null -and (-not $_.PSObject.Properties['due'] -or -not $_.due -or $_.due -eq '') })
                }

                $results += $items
            }
            "project" {
                $items = $(if ($data.projects) { @($data.projects) } else { @() })

                # Apply project filters if any
                if ($Filters.archived -eq $false) {
                    $items = @($items | Where-Object { (-not (Pmc-HasProp $_ 'isArchived')) -or (-not $_.isArchived) })
                }

                $results += $items
            }
            "timelog" {
                $items = $(if ($data.timelogs) { @($data.timelogs) } else { @() })
                $results += $items
            }
        }
    }

    return $results
}

function Show-PmcDataGrid {
    param(
        [string[]]$Domains = @("task"),
        [hashtable]$Columns = @{},
        [hashtable]$Filters = @{},
        [string]$Title = "",
        [hashtable]$Theme = @{},
        [switch]$Interactive,
        [string]$Sort,
        [int]$RefreshIntervalMs,
        [scriptblock]$OnSelectCallback,
        [object[]]$Data
    )

    Write-PmcDebug -Level 2 -Category "DataDisplay" -Message "Rendering data grid" -Data @{
        Domains = $Domains -join ","
        ColumnCount = $Columns.Keys.Count
        FilterCount = $Filters.Keys.Count
    }

    # Default column configuration derived from FieldSchemas for common data types
    if ($Columns.Keys.Count -eq 0 -and $Domains -contains "task") {
        $fs = Get-PmcFieldSchemasForDomain -Domain 'task'
        $Columns = @{}
        foreach ($name in @('id','text','project','due','priority')) {
            $sch = $null
            if ($fs.ContainsKey($name)) { $sch = $fs[$name] }
            $h = switch ($name) { 'id' { '#'} 'text' { 'Task' } 'project' { 'Project' } 'due' { 'Due' } 'priority' { 'pri' } default { $name } }
            $w = 35
            if ($sch -and $sch.ContainsKey('DefaultWidth')) {
                $w = [int]$sch.DefaultWidth
            } else {
                switch ($name) {
                    'id' { $w = 4 }
                    'priority' { $w = 3 }
                    'due' { $w = 10 }
                    'project' { $w = 12 }
                }
            }
            $al = switch ($name) { 'id' { 'Right' } 'priority' { 'Center' } 'due' { 'Center' } default { 'Left' } }
            $editable = $true
            if ($sch -and $sch.ContainsKey('Editable')) { $editable = [bool]$sch.Editable }
            $sensitive = $false
            if ($sch -and $sch.ContainsKey('Sensitive')) { $sensitive = [bool]$sch.Sensitive }
            $truncate = ($name -eq 'text' -or $name -eq 'project')
            $Columns[$name] = @{ Header = $h; Width = $w; Alignment = $al; Editable = $editable; Sensitive = $sensitive; Truncate = $truncate }
        }
    }
    elseif ($Columns.Keys.Count -eq 0 -and $Domains -contains "project") {
        $fs = Get-PmcFieldSchemasForDomain -Domain 'project'
        $Columns = @{}
        foreach ($name in @('name','description','task_count','completion')) {
            $sch = $null
            if ($fs.ContainsKey($name)) { $sch = $fs[$name] }
            $h = switch ($name) { 'name' { 'Project' } 'description' { 'Description' } 'task_count' { 'Tasks' } 'completion' { '%' } default { $name } }
            $w = 30
            if ($sch -and $sch.ContainsKey('DefaultWidth')) {
                $w = [int]$sch.DefaultWidth
            } else {
                switch ($name) {
                    'task_count' { $w = 6 }
                    'completion' { $w = 6 }
                    'name' { $w = 20 }
                }
            }
            $al = switch ($name) { 'task_count' { 'Right' } 'completion' { 'Right' } default { 'Left' } }
            $editable = $false
            if ($sch -and $sch.ContainsKey('Editable')) { $editable = [bool]$sch.Editable }
            $sensitive = $false
            if ($sch -and $sch.ContainsKey('Sensitive')) { $sensitive = [bool]$sch.Sensitive }
            $truncate = ($name -eq 'description')
            $Columns[$name] = @{ Header = $h; Width = $w; Alignment = $al; Editable = $editable; Sensitive = $sensitive; Truncate = $truncate }
        }
    }
    elseif ($Columns.Keys.Count -eq 0 -and $Domains -contains "timelog") {
        $fs = Get-PmcFieldSchemasForDomain -Domain 'timelog'
        $Columns = @{}
        foreach ($name in @('date','project','duration','description')) {
            $sch = $null
            if ($fs.ContainsKey($name)) { $sch = $fs[$name] }
            $h = switch ($name) { 'date' { 'Date' } 'project' { 'Project' } 'duration' { 'Duration' } 'description' { 'Description' } default { $name } }
            $w = 35
            if ($sch -and $sch.ContainsKey('DefaultWidth')) {
                $w = [int]$sch.DefaultWidth
            } else {
                switch ($name) {
                    'date' { $w = 10 }
                    'project' { $w = 15 }
                    'duration' { $w = 8 }
                }
            }
            $al = switch ($name) { 'duration' { 'Right' } 'date' { 'Center' } default { 'Left' } }
            $editable = $false
            if ($sch -and $sch.ContainsKey('Editable')) { $editable = [bool]$sch.Editable }
            $sensitive = $false
            if ($sch -and $sch.ContainsKey('Sensitive')) { $sensitive = [bool]$sch.Sensitive }
            $truncate = ($name -eq 'description')
            $Columns[$name] = @{ Header = $h; Width = $w; Alignment = $al; Editable = $editable; Sensitive = $sensitive; Truncate = $truncate }
        }
    }

    # Resolve data source (explicit data wins)
    if ($PSBoundParameters.ContainsKey('Data')) {
        $data = $Data
    } else {
        # Get filtered data - HACK for help domain
        if ($Domains -contains "help") {
            # Use Get-PmcHelpData function for consistent help data
            $data = Get-PmcHelpData -Context $null
            Write-PmcDebug -Level 2 -Category "DataDisplay" -Message "Help data retrieved" -Data @{ Count = @($data).Count }
        } else {
            $data = Get-PmcFilteredData -Domains $Domains -Filters $Filters
        }
    }

    # Optional sorting for static mode
    if (-not $Interactive.IsPresent -and $Sort) {
        $sortText = [string]$Sort
        $col = $null; $asc = $true
        if ($sortText -match '^([-+]?)([A-Za-z0-9_:-]+)$') {
            $sig = $matches[1]; $name = $matches[2]
            $col = $name
            if ($sig -eq '-') { $asc = $false }
        } elseif ($sortText -match '^([^:]+):(asc|desc)$') {
            $col = $matches[1]; $asc = ($matches[2].ToLower() -eq 'asc')
        }
        if ($col) {
            $data = @($data | Sort-Object -Property @{Expression={ if ($_.PSObject.Properties[$col]) { $_.$col } else { $null } }; Ascending=$asc})
        } else {
            throw ("Invalid Sort format: '{0}'" -f $Sort)
        }
    }

    # Display title if provided
    if ($Title) {
        Write-PmcStyled -Style 'Title' -Text "`n$Title"
        Write-PmcStyled -Style 'Border' -Text ("─" * 50)
        # Helpful hint for help-related views
        $isHelp = $false
        foreach ($d in $Domains) { if ($d -like 'help*') { $isHelp = $true; break } }
        if ($isHelp) {
            Write-PmcStyled -Style 'Muted' -Text 'Tip: / opens search • Ctrl+F filter • "phrase" matches • Enter inserts'
        }
    }

    if (-not $data -or @($data).Count -eq 0) {
        Write-PmcDebug -Level 2 -Category "DataDisplay" -Message "No data found for display" -Data @{
            DataIsNull = ($data -eq $null)
            DataCount = $(if ($data) { @($data).Count } else { "null" })
            Domains = $Domains -join ","
        }
        Write-PmcStyled -Style 'Muted' -Text "No items match the specified criteria"
        return
    }

    # Create and configure the grid renderer
    $renderer = [PmcGridRenderer]::new($Columns, $Domains, $Filters)
    $renderer.CurrentData = $data
    $renderer.AllData = $data

    # Apply theme configuration if provided
    if ($Theme.Count -gt 0) {
        $renderer.ThemeConfig = $renderer.InitializeTheme($Theme)
    }

    # Apply additional parameters
    if ($OnSelectCallback) { $renderer.OnSelectCallback = $OnSelectCallback }

    # Choose rendering mode
    if ($Interactive) {
        # Start interactive mode
        if ($PSBoundParameters.ContainsKey('RefreshIntervalMs')) { $renderer.RefreshIntervalMs = [int]$RefreshIntervalMs }
        $renderer.StartInteractive($data)
    } else {
        # Standard static rendering
        $gridLines = $renderer.RenderGrid($data)
        foreach ($line in $gridLines) {
            Write-Host $line
        }
    }

    Write-PmcDebug -Level 2 -Category "DataDisplay" -Message "Grid rendering completed" -Data @{
        ItemCount = @($data).Count
        Interactive = $Interactive.IsPresent
    }
}

# Compatibility wrapper: Show-PmcCustomGrid → Show-PmcDataGrid
function Show-PmcCustomGrid {
    param(
        [string]$Domain,
        [hashtable]$Columns,
        [object[]]$Data,
        [string]$Title,
        [string]$Group,
        [string]$View,
        [switch]$Interactive
    )
    try {
        if (($View -and $View.ToLower() -eq 'kanban') -and (Get-Command -Name 'Show-PmcKanban' -ErrorAction SilentlyContinue)) {
            # Delegate to Kanban renderer when requested
            Show-PmcKanban -Domain $Domain -Data $Data -Columns $Columns -Title $Title -Interactive:$Interactive
            return
        }
    } catch {}

    $domains = @($Domain)
    if (-not $Columns) { $Columns = @{} }
    if ($Title) {
        Write-PmcStyled -Style 'Title' -Text "`n$Title"
        Write-PmcStyled -Style 'Border' -Text ("─" * 50)
    }
    Show-PmcDataGrid -Domains $domains -Columns $Columns -Data $Data -Interactive:$Interactive
}

# Export functions for module manifest
Export-ModuleMember -Function Show-PmcDataGrid, Show-PmcCustomGrid