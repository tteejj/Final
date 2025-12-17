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
- Search and filter commands
#>
class CommandLibraryScreen : StandardListScreen {
    hidden [CommandService]$_commandService = $null

    # Static: Register menu items
    static [void] RegisterMenuItems([object]$registry) {
        $registry.AddMenuItem('Tools', 'Command Library', 'C', {
            . "$PSScriptRoot/CommandLibraryScreen.ps1"
            $global:PmcApp.PushScreen((New-Object -TypeName CommandLibraryScreen))
        }, 10)
    }

    # Legacy constructor (backward compatible)
    CommandLibraryScreen() : base("CommandLibrary", "Command Library") {
        $this._InitializeScreen()
    }

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

    # === Abstract Method Implementations ===

    # Get entity type for store operations
    [string] GetEntityType() {
        return 'command'
    }

    # Define columns for list display
    [array] GetColumns() {
        # Calculate column widths dynamically based on available width
        # Account for 4 separators (2 spaces each = 8 chars total) between 5 columns
        $availableWidth = $(if ($this.List -and $this.List.Width -gt 4) { $this.List.Width - 4 - 8 } else { 103 })
        $nameWidth = [Math]::Max(20, [Math]::Floor($availableWidth * 0.24))
        $categoryWidth = [Math]::Max(12, [Math]::Floor($availableWidth * 0.15))
        $usesWidth = 8  # Fixed narrow column
        $lastUsedWidth = [Math]::Max(10, [Math]::Floor($availableWidth * 0.12))
        $descWidth = [Math]::Max(30, [Math]::Floor($availableWidth * 0.44))

        return @(
            @{ Name='name'; Label='Name'; Width=$nameWidth }
            @{ Name='category'; Label='Category'; Width=$categoryWidth }
            @{ Name='usage_count'; Label='Uses'; Width=$usesWidth }
            @{ Name='last_used'; Label='Last Used'; Width=$lastUsedWidth }
            @{ Name='description'; Label='Command'; Width=$descWidth }
        )
    }

    # Load data and refresh list
    [void] LoadData() {
        $items = $this.LoadItems()
        $this.List.SetData($items)
    }

    # Load items from data store
    [array] LoadItems() {
        $commands = @($this._commandService.GetAllCommands())

        # Format for display
        foreach ($cmd in $commands) {
            if (-not $cmd.ContainsKey('usage_count')) {
                $cmd['usage_count'] = 0
            }
            if ($cmd.ContainsKey('last_used') -and $cmd.last_used -is [DateTime]) {
                $cmd['last_used'] = $cmd.last_used.ToString('yyyy-MM-dd')
            } elseif ($cmd.ContainsKey('last_used') -and $cmd.last_used) {
                # Already a string, keep it
            } else {
                $cmd['last_used'] = 'Never'
            }

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
        $availableWidth = $(if ($this.List -and $this.List.Width -gt 4) { $this.List.Width - 4 - 8 } else { 103 })
        $nameWidth = [Math]::Max(20, [Math]::Floor($availableWidth * 0.24))
        $categoryWidth = [Math]::Max(12, [Math]::Floor($availableWidth * 0.15))
        $usesWidth = 8  # Fixed narrow column - display only
        $lastUsedWidth = [Math]::Max(10, [Math]::Floor($availableWidth * 0.12))
        $descWidth = [Math]::Max(30, [Math]::Floor($availableWidth * 0.44))

        if ($null -eq $item -or $item.Count -eq 0) {
            # New command - empty fields (5 fields to match 5 columns)
            return @(
                @{ Name='name'; Type='text'; Label=''; Required=$true; Value=''; Width=$nameWidth; Placeholder='Command name' }
                @{ Name='category'; Type='text'; Label=''; Value='General'; Width=$categoryWidth; Placeholder='Category' }
                @{ Name='usage_count'; Type='text'; Label=''; Value='0'; Width=$usesWidth; ReadOnly=$true }
                @{ Name='last_used'; Type='text'; Label=''; Value='Never'; Width=$lastUsedWidth; ReadOnly=$true }
                @{ Name='description'; Type='text'; Label=''; Value=''; Width=$descWidth; Placeholder='Enter command text (will be copied to clipboard)'; Required=$true }
            )
        } else {
            # Existing command - populate from item (5 fields to match 5 columns)
            $uses = $(if ($item.usage_count) { $item.usage_count.ToString() } else { '0' })
            $lastUsed = $(if ($item.last_used) { $item.last_used } else { 'Never' })
            return @(
                @{ Name='name'; Type='text'; Label=''; Required=$true; Value=$item.name; Width=$nameWidth; Placeholder='Command name' }
                @{ Name='category'; Type='text'; Label=''; Value=$item.category; Width=$categoryWidth; Placeholder='Category' }
                @{ Name='usage_count'; Type='text'; Label=''; Value=$uses; Width=$usesWidth; ReadOnly=$true }
                @{ Name='last_used'; Type='text'; Label=''; Value=$lastUsed; Width=$lastUsedWidth; ReadOnly=$true }
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

            if ($itemId) {
                $this._commandService.DeleteCommand($itemId)
                $this.SetStatusMessage("Command '$itemName' deleted", "success")
            } else {
                $this.SetStatusMessage("Cannot delete command without ID", "error")
            }
        } catch {
            $this.SetStatusMessage("Error deleting command: $($_.Exception.Message)", "error")
        }
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