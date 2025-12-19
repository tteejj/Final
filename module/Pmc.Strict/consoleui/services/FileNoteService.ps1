# FileNoteService.ps1 - Filesystem-based note service
#
# Human-readable filenames (title = filename), optional per-note .meta sidecar.
# Much simpler than legacy NoteService - no monolithic metadata manifest.
#
# Storage structure:
#   notes/
#     Meeting Notes.txt      <- Note content
#     Meeting Notes.meta     <- Optional: tags, owner (only if needed)
#     Project Ideas.txt
#
# Usage:
#   $service = [FileNoteService]::GetInstance()
#   $notes = $service.GetAllNotes()
#   $service.CreateNote("My New Note")

using namespace System
using namespace System.IO
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

class FileNoteService {
    # === Singleton ===
    static hidden [FileNoteService]$_instance = $null
    static hidden [object]$_instanceLock = [object]::new()

    # === Configuration ===
    hidden [string]$_notesDir
    hidden [hashtable]$_metaCache = @{}  # In-memory cache for .meta files

    # === Events ===
    [scriptblock]$OnNotesChanged = $null
    [scriptblock]$OnNoteAdded = $null

    # === Singleton Access ===
    static [FileNoteService] GetInstance() {
        if ($null -eq [FileNoteService]::_instance) {
            [System.Threading.Monitor]::Enter([FileNoteService]::_instanceLock)
            try {
                if ($null -eq [FileNoteService]::_instance) {
                    [FileNoteService]::_instance = [FileNoteService]::new()
                }
            } finally {
                [System.Threading.Monitor]::Exit([FileNoteService]::_instanceLock)
            }
        }
        return [FileNoteService]::_instance
    }

    # === Constructor ===
    FileNoteService() {
        # Determine notes directory relative to PMC root
        $pmcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $this._notesDir = Join-Path $pmcRoot "notes"

        # Ensure directory exists
        if (-not (Test-Path $this._notesDir)) {
            New-Item -ItemType Directory -Path $this._notesDir -Force | Out-Null
        }
    }

    # === CRUD Operations ===

    <#
    .SYNOPSIS
    Get all notes by scanning the directory
    #>
    [array] GetAllNotes() {
        $notes = @()
        
        $files = Get-ChildItem -Path $this._notesDir -Filter "*.txt" -File -ErrorAction SilentlyContinue
        
        foreach ($file in $files) {
            $noteId = $file.BaseName  # Filename without extension = ID and title
            $meta = $this._LoadMetadata($noteId)
            
            $notes += @{
                id = $noteId
                title = $noteId
                file = $file.FullName
                created = $file.CreationTime
                modified = $file.LastWriteTime
                tags = $(if ($meta['tags']) { $meta['tags'] } else { @() })
                owner_type = $(if ($meta['owner_type']) { $meta['owner_type'] } else { "global" })
                owner_id = $(if ($meta['owner_id']) { $meta['owner_id'] } else { "" })
                word_count = 0  # Compute on demand if needed
                line_count = 0
            }
        }
        
        # Sort by modified descending (most recent first)
        return $notes | Sort-Object -Property modified -Descending
    }

    <#
    .SYNOPSIS
    Get notes filtered by owner
    #>
    [array] GetNotesByOwner([string]$ownerType, [string]$ownerId) {
        return $this.GetAllNotes() | Where-Object {
            $_.owner_type -eq $ownerType -and $_.owner_id -eq $ownerId
        }
    }

    <#
    .SYNOPSIS
    Get a single note by ID (title)
    #>
    [object] GetNote([string]$noteId) {
        $filePath = Join-Path $this._notesDir "$noteId.txt"
        if (-not (Test-Path $filePath)) {
            return $null
        }
        
        $file = Get-Item $filePath
        $meta = $this._LoadMetadata($noteId)
        
        return @{
            id = $noteId
            title = $noteId
            file = $file.FullName
            created = $file.CreationTime
            modified = $file.LastWriteTime
            tags = $(if ($meta['tags']) { $meta['tags'] } else { @() })
            owner_type = $(if ($meta['owner_type']) { $meta['owner_type'] } else { "global" })
            owner_id = $(if ($meta['owner_id']) { $meta['owner_id'] } else { "" })
        }
    }

    <#
    .SYNOPSIS
    Create a new note with the given title
    #>
    [object] CreateNote([string]$title) {
        return $this.CreateNote($title, @(), "global", $null)
    }

    [object] CreateNote([string]$title, [array]$tags) {
        return $this.CreateNote($title, $tags, "global", $null)
    }

    [object] CreateNote([string]$title, [array]$tags, [string]$ownerType, [string]$ownerId) {
        # Sanitize title for filename
        $safeName = $this._SanitizeFilename($title)
        
        # Handle duplicates by appending number
        $baseName = $safeName
        $counter = 1
        while (Test-Path (Join-Path $this._notesDir "$safeName.txt")) {
            $safeName = "$baseName ($counter)"
            $counter++
        }
        
        $filePath = Join-Path $this._notesDir "$safeName.txt"
        
        # Create empty file with atomic write
        $this._AtomicWrite($filePath, "")
        
        # Save metadata if we have tags or owner
        if ($tags.Count -gt 0 -or ($ownerType -ne "global" -and $ownerId)) {
            $this._SaveMetadata($safeName, @{
                tags = $tags
                owner_type = $ownerType
                owner_id = $ownerId
            })
        }
        
        $note = $this.GetNote($safeName)
        
        # Fire events
        if ($this.OnNoteAdded) {
            & $this.OnNoteAdded $note
        }
        if ($this.OnNotesChanged) {
            & $this.OnNotesChanged
        }
        
        return $note
    }

    <#
    .SYNOPSIS
    Load note content from file
    #>
    [string] LoadNoteContent([string]$noteId) {
        $filePath = Join-Path $this._notesDir "$noteId.txt"
        
        if (-not (Test-Path $filePath)) {
            throw "Note not found: $noteId"
        }
        
        return Get-Content -Path $filePath -Raw -ErrorAction SilentlyContinue
    }

    <#
    .SYNOPSIS
    Save note content with atomic write and fsync
    #>
    [void] SaveNoteContent([string]$noteId, [string]$content) {
        $filePath = Join-Path $this._notesDir "$noteId.txt"
        
        if (-not (Test-Path $filePath)) {
            throw "Note not found: $noteId"
        }
        
        $this._AtomicWrite($filePath, $content)
        
        # Note: We do NOT rewrite any manifest here - that's the whole point!
        # Modified time is updated by the filesystem automatically.
    }

    <#
    .SYNOPSIS
    Update note metadata (tags, owner)
    #>
    [void] UpdateNoteMetadata([string]$noteId, [hashtable]$changes) {
        $filePath = Join-Path $this._notesDir "$noteId.txt"
        if (-not (Test-Path $filePath)) {
            throw "Note not found: $noteId"
        }
        
        # Handle title change = file rename
        if ($changes.ContainsKey('title') -and $changes.title -ne $noteId) {
            $newName = $this._SanitizeFilename($changes.title)
            $this.RenameNote($noteId, $newName)
            $noteId = $newName
        }
        
        # Load existing metadata
        $meta = $this._LoadMetadata($noteId)
        if (-not $meta) { $meta = @{} }
        
        # Apply changes
        if ($changes.ContainsKey('tags')) { $meta.tags = $changes.tags }
        if ($changes.ContainsKey('owner_type')) { $meta.owner_type = $changes.owner_type }
        if ($changes.ContainsKey('owner_id')) { $meta.owner_id = $changes.owner_id }
        
        # Save metadata (only if we have anything to store)
        if ($meta.tags -or ($meta.owner_type -and $meta.owner_type -ne "global") -or $meta.owner_id) {
            $this._SaveMetadata($noteId, $meta)
        }
        
        if ($this.OnNotesChanged) {
            & $this.OnNotesChanged
        }
    }

    <#
    .SYNOPSIS
    Rename a note (changes both file and title)
    #>
    [void] RenameNote([string]$oldName, [string]$newName) {
        $oldPath = Join-Path $this._notesDir "$oldName.txt"
        $newPath = Join-Path $this._notesDir "$newName.txt"
        
        if (-not (Test-Path $oldPath)) {
            throw "Note not found: $oldName"
        }
        
        if (Test-Path $newPath) {
            throw "A note with name '$newName' already exists"
        }
        
        # Rename content file
        Rename-Item $oldPath $newPath
        
        # Rename metadata file if exists
        $oldMeta = Join-Path $this._notesDir "$oldName.meta"
        $newMeta = Join-Path $this._notesDir "$newName.meta"
        if (Test-Path $oldMeta) {
            Rename-Item $oldMeta $newMeta
        }
        
        # Update cache
        if ($this._metaCache.ContainsKey($oldName)) {
            $this._metaCache[$newName] = $this._metaCache[$oldName]
            $this._metaCache.Remove($oldName)
        }
    }

    <#
    .SYNOPSIS
    Delete a note and its metadata
    #>
    [void] DeleteNote([string]$noteId) {
        $filePath = Join-Path $this._notesDir "$noteId.txt"
        
        if (-not (Test-Path $filePath)) {
            throw "Note not found: $noteId"
        }
        
        # Delete content file
        Remove-Item $filePath -Force
        
        # Delete metadata file if exists
        $metaPath = Join-Path $this._notesDir "$noteId.meta"
        if (Test-Path $metaPath) {
            Remove-Item $metaPath -Force
        }
        
        # Clear from cache
        $this._metaCache.Remove($noteId)
        
        if ($this.OnNotesChanged) {
            & $this.OnNotesChanged
        }
    }

    # === Private Helpers ===

    <#
    .SYNOPSIS
    Atomic write with fsync - write to temp, flush, rename
    #>
    hidden [void] _AtomicWrite([string]$targetPath, [string]$content) {
        $tempPath = "$targetPath.tmp"
        
        try {
            # Write to temp file
            [System.IO.File]::WriteAllText($tempPath, $content)
            
            # Fsync - ensure data hits disk
            $stream = [System.IO.File]::Open($tempPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
            $stream.Flush()
            $stream.Close()
            
            # Atomic rename
            Move-Item -Path $tempPath -Destination $targetPath -Force
            
        } catch {
            # Cleanup temp file on error
            if (Test-Path $tempPath) {
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
            }
            throw
        }
    }

    <#
    .SYNOPSIS
    Load per-note metadata from .meta sidecar file
    #>
    hidden [hashtable] _LoadMetadata([string]$noteId) {
        # Check cache first
        if ($this._metaCache.ContainsKey($noteId)) {
            return $this._metaCache[$noteId]
        }
        
        $metaPath = Join-Path $this._notesDir "$noteId.meta"
        
        if (Test-Path $metaPath) {
            try {
                $json = Get-Content $metaPath -Raw | ConvertFrom-Json
                $meta = @{
                    tags = $(if ($json.tags) { @($json.tags) } else { @() })
                    owner_type = $(if ($json.owner_type) { $json.owner_type } else { "global" })
                    owner_id = $(if ($json.owner_id) { $json.owner_id } else { "" })
                }
                $this._metaCache[$noteId] = $meta
                return $meta
            } catch {
                Write-Warning "Failed to load metadata for $noteId $_"
            }
        }
        
        return @{}
    }

    <#
    .SYNOPSIS
    Save per-note metadata to .meta sidecar file
    #>
    hidden [void] _SaveMetadata([string]$noteId, [hashtable]$meta) {
        $metaPath = Join-Path $this._notesDir "$noteId.meta"
        
        $data = @{
            tags = $(if ($meta.tags) { $meta.tags } else { @() })
            owner_type = $(if ($meta.owner_type) { $meta.owner_type } else { "global" })
            owner_id = $(if ($meta.owner_id) { $meta.owner_id } else { "" })
        }
        
        $json = $data | ConvertTo-Json -Compress
        $this._AtomicWrite($metaPath, $json)
        
        # Update cache
        $this._metaCache[$noteId] = $meta
    }

    <#
    .SYNOPSIS
    Sanitize a string for use as a filename
    #>
    hidden [string] _SanitizeFilename([string]$name) {
        # Remove invalid characters
        $invalid = [System.IO.Path]::GetInvalidFileNameChars()
        $safeName = $name
        
        foreach ($char in $invalid) {
            $safeName = $safeName.Replace([string]$char, '')
        }
        
        # Trim whitespace and dots
        $safeName = $safeName.Trim().TrimEnd('.')
        
        # Ensure not empty
        if ([string]::IsNullOrWhiteSpace($safeName)) {
            $safeName = "Untitled"
        }
        
        # Limit length (Windows has 260 char path limit)
        if ($safeName.Length -gt 200) {
            $safeName = $safeName.Substring(0, 200)
        }
        
        return $safeName
    }

    <#
    .SYNOPSIS
    Update word/line stats (computed on demand, not stored)
    #>
    [void] UpdateNoteStats([string]$noteId, [int]$wordCount, [int]$lineCount) {
        # In filesystem mode, we don't store stats - they're derived from content
        # This method exists for API compatibility but is a no-op
    }
}
