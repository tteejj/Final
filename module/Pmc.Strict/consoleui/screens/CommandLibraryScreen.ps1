using namespace System.Collections.Generic
using namespace System.Text

# CommandLibraryScreen - Command library management using StandardListScreen
# Allows users to save, manage, and copy frequently used commands

Set-StrictMode -Version Latest

. "$PSScriptRoot/../base/StandardListScreen.ps1"
. "$PSScriptRoot/../services/CommandService.ps1"

<#
.SYNOPSIS
Command library management screen

.DESCRIPTION
Manage a library of saved commands:
- Add/Edit/Delete commands
- Copy commands to clipboard
- Track usage statistics
#>
class CommandLibraryScreen : StandardListScreen {
    hidden [object]$_commandService = $null

    # Container constructor
    CommandLibraryScreen([object]$container) : base("CommandLibrary", "Command Library", $container) {
        $this._InitializeScreen()
    }

    hidden [void] _InitializeScreen() {
        # Initialize service
        $this._commandService = [CommandService]::GetInstance()

        # Configure capabilities
        $this.AllowAdd = $true
        $this.AllowEdit = $true
        $this.AllowDelete = $true
        $this.AllowFilter = $true

        # Configure header
        $this.Header.SetBreadcrumb(@("Home", "Tools", "Command Library"))

        # Configure footer shortcuts
        $this.Footer.ClearShortcuts()
        $this.Footer.AddShortcut("A", "Add")
        $this.Footer.AddShortcut("E", "Edit")
        $this.Footer.AddShortcut("D", "Delete")
        $this.Footer.AddShortcut("Enter/C", "Copy")
        $this.Footer.AddShortcut("Esc", "Back")

        # Setup event handlers
        $self = $this
        $this._commandService.OnCommandsChanged = {
            if ($null -ne $self -and $self.IsActive) {
                $self.LoadData()
            }
        }.GetNewClosure()
    }

    # Required by StandardListScreen - loads and displays data
    [void] LoadData() {
        $items = $this.LoadItems()
        $columns = $this.GetColumns()
        $this.List.SetColumns($columns)
        $this.List.SetData($items)
    }

    # === Abstract Method Implementations ===

    # Get entity type for store operations
    [string] GetEntityType() {
        return 'command'
    }

    # Define columns for list display
    [array] GetColumns() {
        # Calculate column widths dynamically based on List widget width
        # Account for 2 separators (2 spaces each = 4 chars) between 3 columns + borders
        $availableWidth = $(if ($this.List -and $this.List.Width -gt 4) { $this.List.Width - 4 - 4 } else { 110 })
        
        # Proportions: Name=30%, Category=20%, Command=50%
        $nameWidth = [Math]::Max(15, [Math]::Floor($availableWidth * 0.30))
        $categoryWidth = [Math]::Max(10, [Math]::Floor($availableWidth * 0.20))
        $commandWidth = [Math]::Max(20, [Math]::Floor($availableWidth * 0.50))
        
        return @(
            @{ Name = 'name'; Label = 'Name'; Width = $nameWidth; Align = 'left' }
            @{ Name = 'category'; Label = 'Category'; Width = $categoryWidth; Align = 'left' }
            @{ Name = 'command_text'; Label = 'Command'; Width = $commandWidth; Align = 'left' }
        )
    }

    # Load items from data store
    [array] LoadItems() {
        $commands = @($this._commandService.GetAllCommands())

        # Format for display
        foreach ($cmd in $commands) {
            # Format tags for display
            if ($cmd.ContainsKey('tags') -and $cmd.tags -is [array]) {
                $cmd['tags_display'] = $cmd.tags -join ', '
            } else {
                $cmd['tags_display'] = ''
            }
        }

        return $commands
    }

    # Define filter fields for StandardListScreen
    [array] GetFilterFields() {
        return @(
            @{ Name='category'; Label='Category'; Type='text' }
            @{ Name='tags'; Label='Tags (comma-separated)'; Type='text' }
        )
    }

    # Apply filters to items
    [array] ApplyFilters([array]$items, [hashtable]$filters) {
        if ($null -eq $filters -or $filters.Count -eq 0) {
            return $items
        }

        $filtered = $items

        # Filter by category
        if ($filters.ContainsKey('category') -and -not [string]::IsNullOrWhiteSpace($filters.category)) {
            $categoryFilter = $filters.category.Trim()
            $filtered = @($filtered | Where-Object {
                $itemCategory = $(if ($_ -is [hashtable]) { $_['category'] } else { $_.category })
                $itemCategory -like "*$categoryFilter*"
            })
        }

        # Filter by tags
        if ($filters.ContainsKey('tags') -and -not [string]::IsNullOrWhiteSpace($filters.tags)) {
            $tagFilters = @($filters.tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $filtered = @($filtered | Where-Object {
                $itemTags = $(if ($_ -is [hashtable]) { $_['tags'] } else { $_.tags })
                if ($null -eq $itemTags -or $itemTags.Count -eq 0) {
                    return $false
                }
                # Check if item has any of the specified tags
                $hasTag = $false
                foreach ($filterTag in $tagFilters) {
                    foreach ($itemTag in $itemTags) {
                        if ($itemTag -like "*$filterTag*") {
                            $hasTag = $true
                            break
                        }
                    }
                    if ($hasTag) { break }
                }
                return $hasTag
            })
        }

        return $filtered
    }

    # Define edit fields for InlineEditor
    [array] GetEditFields([object]$item) {
        # Calculate field widths - MUST MATCH GetColumns() exactly
        $availableWidth = $(if ($this.List -and $this.List.Width -gt 4) { $this.List.Width - 4 - 4 } else { 103 })
        $nameWidth = [Math]::Max(20, [Math]::Floor($availableWidth * 0.30))
        $categoryWidth = [Math]::Max(12, [Math]::Floor($availableWidth * 0.20))
        $descWidth = [Math]::Max(30, [Math]::Floor($availableWidth * 0.50))

        if ($null -eq $item -or $item.Count -eq 0) {
            # New command - empty fields (3 fields to match 3 columns)
            return @(
                @{ Name='name'; Type='text'; Label=''; Required=$true; Value=''; Width=$nameWidth; Placeholder='Command name' }
                @{ Name='category'; Type='text'; Label=''; Value='General'; Width=$categoryWidth; Placeholder='Category' }
                @{ Name='description'; Type='text'; Label=''; Value=''; Width=$descWidth; Placeholder='Enter command text (will be copied to clipboard)'; Required=$true }
            )
        } else {
            # Existing command - populate from item (3 fields to match 3 columns)
            return @(
                @{ Name='name'; Type='text'; Label=''; Required=$true; Value=$item.name; Width=$nameWidth; Placeholder='Command name' }
                @{ Name='category'; Type='text'; Label=''; Value=$item.category; Width=$categoryWidth; Placeholder='Category' }
                @{ Name='description'; Type='text'; Label=''; Value=$item.command_text; Width=$descWidth; Placeholder='Enter command text (will be copied to clipboard)'; Required=$true }
            )
        }
    }

    # Handle item creation
    [void] OnItemCreated([hashtable]$values) {
        try {
            # VALIDATION: Command name is required
            if (-not $values.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($values.name)) {
                $this.SetStatusMessage("Command name is required", "error")
                return
            }

            # VALIDATION: Command text is required (stored in 'description' field for column alignment)
            if (-not $values.ContainsKey('description') -or [string]::IsNullOrWhiteSpace($values.description)) {
                $this.SetStatusMessage("Command text is required - enter the text you want to copy in the 'Command' field", "error")
                return
            }

            $tags = $(if ($values.ContainsKey('tags') -and -not [string]::IsNullOrWhiteSpace($values.tags)) {
                @($values.tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            } else {
                @()
            })

            $name = $values.name
            # description field IS the command text (for column alignment)
            $commandText = $values.description
            $category = $(if ($values.ContainsKey('category')) { $values.category } else { '' })
            $description = ''  # We don't have a separate description field

            $this._commandService.CreateCommand($name, $commandText, $category, $description, $tags)

            $this.SetStatusMessage("Command '$name' saved", "success")
        } catch {
            $this.SetStatusMessage("Error creating command: $($_.Exception.Message)", "error")
        }
    }

    # Handle item update
    [void] OnItemUpdated([object]$item, [hashtable]$values) {
        try {
            $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })

            $tags = $(if ($values.ContainsKey('tags') -and -not [string]::IsNullOrWhiteSpace($values.tags)) {
                @($values.tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            } else {
                @()
            })

            # ENDEMIC FIX: Safe value access
            $changes = @{
                name = $(if ($values.ContainsKey('name')) { $values.name } else { '' })
                category = $(if ($values.ContainsKey('category')) { $values.category } else { '' })
                command_text = $(if ($values.ContainsKey('description')) { $values.description } else { '' })
                description = ''  # description field IS command_text
                tags = $tags
            }

            if ([string]::IsNullOrWhiteSpace($changes.name)) {
                $this.SetStatusMessage("Command name is required", "error")
                return
            }

            $this._commandService.UpdateCommand($itemId, $changes)
            $this.SetStatusMessage("Command '$($changes.name)' updated", "success")
        } catch {
            $this.SetStatusMessage("Error updating command: $($_.Exception.Message)", "error")
        }
    }

    # Handle item deletion
    [void] OnItemDeleted([object]$item) {
        try {
            $itemId = $(if ($item -is [hashtable]) { $item['id'] } else { $item.id })
            $itemName = $(if ($item -is [hashtable]) { $item['name'] } else { $item.name })
            
            Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: Starting delete for id='$itemId' name='$itemName'" "DEBUG"

            if ($itemId) {
                Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: Calling DeleteCommand..." "DEBUG"
                $this._commandService.DeleteCommand($itemId)
                Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: DeleteCommand completed" "DEBUG"
                
                # Force refresh list data from cache
                Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: Calling LoadData..." "DEBUG"
                $this.LoadData()
                Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: LoadData completed, list now has $($this.List.Items.Count) items" "DEBUG"
                
                # Force immediate screen re-render
                if ($this.RenderEngine) {
                    Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: Starting render cycle..." "DEBUG"
                    $this.RenderEngine.BeginFrame()
                    $this.RenderToEngine($this.RenderEngine)
                    $this.RenderEngine.EndFrame()
                    Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: Render cycle completed" "DEBUG"
                } else {
                    Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: No RenderEngine available!" "WARNING"
                }
                
                $this.SetStatusMessage("Command '$itemName' deleted", "success")
                Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: Delete complete" "DEBUG"
            } else {
                Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: No itemId found!" "ERROR"
                $this.SetStatusMessage("Cannot delete command without ID", "error")
            }
        } catch {
            Write-PmcTuiLog "CommandLibraryScreen.OnItemDeleted: EXCEPTION - $($_.Exception.Message)" "ERROR"
            $this.SetStatusMessage("Error deleting command: $($_.Exception.Message)", "error")
        }
    }

    # Virtual method called when inline editor is confirmed
    [void] OnInlineEditConfirmed([hashtable]$values) {
        if ($null -eq $values) {
            return
        }

        # Determine if we're adding a new command or editing existing one
        $isAddMode = ($this.EditorMode -eq 'add')

        if ($isAddMode) {
            $this.OnItemCreated($values)
        }
        else {
            if ($this.CurrentEditItem) {
                $this.OnItemUpdated($this.CurrentEditItem, $values)
            }
        }
    }

    # Virtual method called when inline editor is cancelled
    [void] OnInlineEditCancelled() {
        # No-op: StandardListScreen handles the UI updates
    }

    # === Custom Actions ===

    # Copy the selected command to clipboard
    [void] CopyCommand() {
        $selectedItem = $this.List.GetSelectedItem()
        if ($null -eq $selectedItem) {
            $this.SetStatusMessage("No command selected - select a command and press Enter to copy", "error")
            return
        }

        $commandText = $(if ($selectedItem -is [hashtable]) { $selectedItem['command_text'] } else { $selectedItem.command_text })
        $commandName = $(if ($selectedItem -is [hashtable]) { $selectedItem['name'] } else { $selectedItem.name })
        $commandId = $(if ($selectedItem -is [hashtable]) { $selectedItem['id'] } else { $selectedItem.id })

        if ([string]::IsNullOrEmpty($commandText)) {
            $this.SetStatusMessage("Command '$commandName' has no text to copy - edit it and add command text in the 'Command' field", "error")
            return
        }

        try {
            # Copy to clipboard (Windows only)
            Set-Clipboard -Value $commandText

            # Update usage statistics
            if ($commandId) {
                $this._commandService.IncrementUsageCount($commandId)
            }

            $this.SetStatusMessage("Copied to clipboard: $commandText", "success")
        } catch {
            $this.SetStatusMessage("Failed to copy to clipboard: $($_.Exception.Message)", "error")
        }
    }

    # === Input Handling ===

    [bool] HandleKeyPress([ConsoleKeyInfo]$keyInfo) {
        # Phase B: Active modal gets priority
        if ($this.HandleModalInput($keyInfo)) {
            return $true
        }

        # CRITICAL FIX: Only handle custom keys when NOT in edit mode
        # This allows typing 'c' in command name field and using Enter to save
        if (-not $this.ShowInlineEditor -and -not $this.ShowFilterPanel) {
            # Custom key: Enter = Copy command to clipboard (only when not editing)
            if ($keyInfo.Key -eq ([ConsoleKey]::Enter)) {
                $this.CopyCommand()
                return $true
            }

            # Custom key: C = Copy command to clipboard (only when not editing)
            if ($keyInfo.Key -eq ([ConsoleKey]::C)) {
                $this.CopyCommand()
                return $true
            }
        }

        # Call parent handler for list navigation, add/edit/delete
        # When in edit mode, parent will handle Enter to save
        $handled = ([StandardListScreen]$this).HandleKeyPress($keyInfo)
        if ($handled) { return $true }

        return $false
    }
}