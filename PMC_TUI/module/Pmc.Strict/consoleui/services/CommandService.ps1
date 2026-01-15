# CommandService.ps1 - Service for managing command library
#
# Provides CRUD operations for saved commands with file-based storage
# Commands are stored in commands/ subdirectory as JSON metadata
#
# Usage:
#   $service = [CommandService]::GetInstance()
#   $commands = $service.GetAllCommands()
#   $service.CreateCommand("Deploy Script", "kubectl apply -f deploy.yaml")
#   $service.DeleteCommand($commandId)

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

class CommandService {
    # === Singleton Instance ===
    static hidden [CommandService]$_instance = $null
    static hidden [object]$_instanceLock = [object]::new()

    # === Configuration ===
    hidden [string]$_commandsDir
    hidden [string]$_metadataFile

    # === In-memory cache ===
    hidden [hashtable]$_commandsCache = @{}
    hidden [datetime]$_cacheLoadTime = [datetime]::MinValue

    # === Event Callbacks ===
    [scriptblock]$OnCommandAdded = {}
    [scriptblock]$OnCommandUpdated = {}
    [scriptblock]$OnCommandDeleted = {}
    [scriptblock]$OnCommandsChanged = {}

    # === Singleton Access ===
    static [CommandService] GetInstance() {
        if ([CommandService]::_instance -eq $null) {
            [System.Threading.Monitor]::Enter([CommandService]::_instanceLock)
            try {
                if ([CommandService]::_instance -eq $null) {
                    [CommandService]::_instance = [CommandService]::new()
                }
            } finally {
                [System.Threading.Monitor]::Exit([CommandService]::_instanceLock)
            }
        }
        return [CommandService]::_instance
    }

    # === Constructor (Private - use GetInstance) ===
    CommandService() {
        # Determine commands directory relative to PMC root
        $pmcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $this._commandsDir = Join-Path $pmcRoot "commands"
        $this._metadataFile = Join-Path $this._commandsDir "commands_metadata.json"

        # Ensure commands directory exists
        if (-not (Test-Path $this._commandsDir)) {
            New-Item -ItemType Directory -Path $this._commandsDir -Force | Out-Null
        }

        # Load metadata
        $this.LoadMetadata()
    }

    # === Metadata Management ===
    hidden [void] LoadMetadata() {
        if (Test-Path $this._metadataFile) {
            try {
                $json = Get-Content $this._metadataFile -Raw | ConvertFrom-Json -Depth 10
                foreach ($cmd in $json.commands) {
                    $this._commandsCache[$cmd.id] = @{
                        id = $cmd.id
                        name = $cmd.name
                        category = $cmd.category
                        command_text = $cmd.command_text
                        description = $cmd.description
                        tags = $cmd.tags
                        created = [datetime]::Parse($cmd.created)
                        modified = [datetime]::Parse($cmd.modified)
                        usage_count = $cmd.usage_count
                        last_used = $(if ($cmd.last_used) { [datetime]::Parse($cmd.last_used) } else { $null })
                    }
                }
                $this._cacheLoadTime = [datetime]::Now
            } catch {
                # Write-PmcTuiLog "Failed to load commands metadata: $_" "ERROR"
                $this._commandsCache = @{}
            }
        }
    }

    hidden [void] SaveMetadata() {
        try {
            $commands = $this._commandsCache.Values | ForEach-Object {
                @{
                    id = $_.id
                    name = $_.name
                    category = $_.category
                    command_text = $_.command_text
                    description = $_.description
                    tags = $_.tags
                    created = $_.created.ToString("o")
                    modified = $_.modified.ToString("o")
                    usage_count = $_.usage_count
                    last_used = $(if ($_.last_used) { $_.last_used.ToString("o") } else { $null })
                }
            }

            $metadata = @{
                schema_version = 1
                commands = $commands
            }

            # Atomic save: write to temp file, then rename
            $tempFile = "$($this._metadataFile).tmp"
            $metadata | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding utf8

            # Backup existing file
            if (Test-Path $this._metadataFile) {
                Copy-Item $this._metadataFile "$($this._metadataFile).bak" -Force
            }

            # Rename temp to actual
            Move-Item -Path $tempFile -Destination $this._metadataFile -Force

        } catch {
            # Write-PmcTuiLog "Failed to save commands metadata: $_" "ERROR"
            throw
        }
    }

    # === CRUD Operations ===

    [array] GetAllCommands() {
        $commands = @($this._commandsCache.Values | Sort-Object -Property modified -Descending)
        return $commands
    }

    [object] GetCommand([string]$commandId) {
        if ($this._commandsCache.ContainsKey($commandId)) {
            return $this._commandsCache[$commandId]
        }
        return $null
    }

    [object] CreateCommand([string]$name, [string]$commandText) {
        return $this.CreateCommand($name, $commandText, "General", "", @())
    }

    [object] CreateCommand([string]$name, [string]$commandText, [string]$category, [string]$description, [array]$tags) {
        # Generate unique ID
        $commandId = [guid]::NewGuid().ToString()

        # Create command object
        $command = @{
            id = $commandId
            name = $name
            category = $category
            command_text = $commandText
            description = $description
            tags = $tags
            created = [datetime]::Now
            modified = [datetime]::Now
            usage_count = 0
            last_used = $null
        }

        # Add to cache
        $this._commandsCache[$commandId] = $command

        # Save metadata
        $this.SaveMetadata()

        # Fire event
        if ($this.OnCommandAdded) {
            & $this.OnCommandAdded $command
        }
        if ($this.OnCommandsChanged) {
            & $this.OnCommandsChanged
        }

        return $command
    }

    [void] UpdateCommand([string]$commandId, [hashtable]$changes) {
        if (-not $this._commandsCache.ContainsKey($commandId)) {
            throw "Command not found: $commandId"
        }

        $command = $this._commandsCache[$commandId]

        # Apply changes
        if ($changes.ContainsKey('name')) { $command.name = $changes.name }
        if ($changes.ContainsKey('category')) { $command.category = $changes.category }
        if ($changes.ContainsKey('command_text')) { $command.command_text = $changes.command_text }
        if ($changes.ContainsKey('description')) { $command.description = $changes.description }
        if ($changes.ContainsKey('tags')) { $command.tags = $changes.tags }

        $command.modified = [datetime]::Now

        # Save metadata
        $this.SaveMetadata()

        # Fire event
        if ($this.OnCommandUpdated) {
            & $this.OnCommandUpdated $command
        }
        if ($this.OnCommandsChanged) {
            & $this.OnCommandsChanged
        }
    }

    [void] DeleteCommand([string]$commandId) {
        if (-not $this._commandsCache.ContainsKey($commandId)) {
            throw "Command not found: $commandId"
        }

        $command = $this._commandsCache[$commandId]

        # Remove from cache
        $this._commandsCache.Remove($commandId)

        # Save metadata
        $this.SaveMetadata()

        # Fire event
        if ($this.OnCommandDeleted) {
            & $this.OnCommandDeleted $command
        }
        if ($this.OnCommandsChanged) {
            & $this.OnCommandsChanged
        }
    }

    [void] IncrementUsageCount([string]$commandId) {
        if (-not $this._commandsCache.ContainsKey($commandId)) {
            throw "Command not found: $commandId"
        }

        $command = $this._commandsCache[$commandId]
        $command.usage_count++
        $command.last_used = [datetime]::Now

        # Save metadata
        $this.SaveMetadata()

        # Fire event
        if ($this.OnCommandsChanged) {
            & $this.OnCommandsChanged
        }
    }
}