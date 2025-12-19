# ChecklistService.ps1 - Service for managing checklists and templates
#
# Provides CRUD operations for checklist templates and instances
# Templates are reusable checklist definitions
# Instances are attached to projects/tasks with completion tracking
#
# Usage:
#   $service = [ChecklistService]::GetInstance()
#   $template = $service.CreateTemplate("Code Review", @("Check tests", "Review security"))
#   $instance = $service.CreateInstanceFromTemplate($templateId, "project", $projectId)

using namespace System
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

class ChecklistService {
    # === Singleton Instance ===
    static hidden [ChecklistService]$_instance = $null
    static hidden [object]$_instanceLock = [object]::new()

    # === Configuration ===
    hidden [string]$_checklistsDir
    hidden [string]$_templatesFile
    hidden [string]$_instancesFile

    # === In-memory cache ===
    hidden [hashtable]$_templatesCache = @{}
    hidden [hashtable]$_instancesCache = @{}
    hidden [datetime]$_cacheLoadTime = [datetime]::MinValue

    # === Event Callbacks ===
    [scriptblock]$OnTemplateAdded = {}
    [scriptblock]$OnTemplateUpdated = {}
    [scriptblock]$OnTemplateDeleted = {}
    [scriptblock]$OnInstanceAdded = {}
    [scriptblock]$OnInstanceUpdated = {}
    [scriptblock]$OnInstanceDeleted = {}
    [scriptblock]$OnChecklistsChanged = {}

    # === Singleton Access ===
    static [ChecklistService] GetInstance() {
        if ([ChecklistService]::_instance -eq $null) {
            [System.Threading.Monitor]::Enter([ChecklistService]::_instanceLock)
            try {
                if ([ChecklistService]::_instance -eq $null) {
                    [ChecklistService]::_instance = [ChecklistService]::new()
                }
            } finally {
                [System.Threading.Monitor]::Exit([ChecklistService]::_instanceLock)
            }
        }
        return [ChecklistService]::_instance
    }

    # === Constructor (Private - use GetInstance) ===
    ChecklistService() {
        # Determine checklists directory relative to PMC root
        $pmcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $this._checklistsDir = Join-Path $pmcRoot "checklists"
        $this._templatesFile = Join-Path $this._checklistsDir "templates.json"
        $this._instancesFile = Join-Path $this._checklistsDir "instances.json"

        # Ensure checklists directory exists
        if (-not (Test-Path $this._checklistsDir)) {
            New-Item -ItemType Directory -Path $this._checklistsDir -Force | Out-Null
        }

        # Load metadata
        $this.LoadTemplates()
        $this.LoadInstances()
    }

    # === Template Management ===
    hidden [void] LoadTemplates() {
        if (Test-Path $this._templatesFile) {
            try {
                $json = Get-Content $this._templatesFile -Raw | ConvertFrom-Json -Depth 10
                foreach ($template in $json.templates) {
                    $items = @()
                    foreach ($item in $template.items) {
                        $items += @{
                            text = $item.text
                            order = $item.order
                        }
                    }

                    $this._templatesCache[$template.id] = @{
                        id = $template.id
                        name = $template.name
                        description = $template.description
                        category = $template.category
                        items = $items
                        created = [datetime]::Parse($template.created)
                        modified = [datetime]::Parse($template.modified)
                    }
                }
                $this._cacheLoadTime = [datetime]::Now
            } catch {
                # Write-PmcTuiLog "Failed to load checklist templates: $_" "ERROR"
                $this._templatesCache = @{}
            }
        }
    }

    hidden [void] SaveTemplates() {
        try {
            $templates = $this._templatesCache.Values | ForEach-Object {
                @{
                    id = $_.id
                    name = $_.name
                    description = $_.description
                    category = $_.category
                    items = $_.items
                    created = $_.created.ToString("o")
                    modified = $_.modified.ToString("o")
                }
            }

            $metadata = @{
                schema_version = 1
                templates = $templates
            }

            # Atomic save
            $tempFile = "$($this._templatesFile).tmp"
            $metadata | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding utf8

            if (Test-Path $this._templatesFile) {
                Copy-Item $this._templatesFile "$($this._templatesFile).bak" -Force
            }

            Move-Item -Path $tempFile -Destination $this._templatesFile -Force

        } catch {
            # Write-PmcTuiLog "Failed to save checklist templates: $_" "ERROR"
            throw
        }
    }

    # === Instance Management ===
    hidden [void] LoadInstances() {
        if (Test-Path $this._instancesFile) {
            try {
                $json = Get-Content $this._instancesFile -Raw | ConvertFrom-Json -Depth 10
                foreach ($instance in $json.instances) {
                    $items = @()
                    foreach ($item in $instance.items) {
                        $items += @{
                            text = $item.text
                            completed = $item.completed
                            completed_date = $(if ($item.completed_date) { [datetime]::Parse($item.completed_date) } else { $null })
                            order = $item.order
                        }
                    }

                    $this._instancesCache[$instance.id] = @{
                        id = $instance.id
                        title = $instance.title
                        template_id = $instance.template_id
                        owner_type = $instance.owner_type
                        owner_id = $instance.owner_id
                        items = $items
                        completed_count = $instance.completed_count
                        total_count = $instance.total_count
                        percent_complete = $instance.percent_complete
                        created = [datetime]::Parse($instance.created)
                        modified = [datetime]::Parse($instance.modified)
                    }
                }
            } catch {
                # Write-PmcTuiLog "Failed to load checklist instances: $_" "ERROR"
                $this._instancesCache = @{}
            }
        }
    }

    hidden [void] SaveInstances() {
        try {
            $instances = $this._instancesCache.Values | ForEach-Object {
                $items = @()
                foreach ($item in $_.items) {
                    $items += @{
                        text = $item.text
                        completed = $item.completed
                        completed_date = $(if ($item.completed_date) { $item.completed_date.ToString("o") } else { $null })
                        order = $item.order
                    }
                }

                @{
                    id = $_.id
                    title = $_.title
                    template_id = $_.template_id
                    owner_type = $_.owner_type
                    owner_id = $_.owner_id
                    items = $items
                    completed_count = $_.completed_count
                    total_count = $_.total_count
                    percent_complete = $_.percent_complete
                    created = $_.created.ToString("o")
                    modified = $_.modified.ToString("o")
                }
            }

            $metadata = @{
                schema_version = 1
                instances = $instances
            }

            # Atomic save
            $tempFile = "$($this._instancesFile).tmp"
            $metadata | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding utf8

            if (Test-Path $this._instancesFile) {
                Copy-Item $this._instancesFile "$($this._instancesFile).bak" -Force
            }

            Move-Item -Path $tempFile -Destination $this._instancesFile -Force

        } catch {
            # Write-PmcTuiLog "Failed to save checklist instances: $_" "ERROR"
            throw
        }
    }

    # === Template CRUD Operations ===

    [array] GetAllTemplates() {
        return @($this._templatesCache.Values | Sort-Object -Property name)
    }

    [object] GetTemplate([string]$templateId) {
        if ($this._templatesCache.ContainsKey($templateId)) {
            return $this._templatesCache[$templateId]
        }
        return $null
    }

    [object] CreateTemplate([string]$name, [string]$description, [string]$category, [array]$itemTexts) {
        $templateId = [guid]::NewGuid().ToString()

        $items = @()
        $order = 1
        foreach ($text in $itemTexts) {
            $items += @{
                text = $text
                order = $order++
            }
        }

        $template = @{
            id = $templateId
            name = $name
            description = $description
            category = $category
            items = $items
            created = [datetime]::Now
            modified = [datetime]::Now
        }

        $this._templatesCache[$templateId] = $template
        $this.SaveTemplates()

        if ($this.OnTemplateAdded) {
            & $this.OnTemplateAdded $template
        }
        if ($this.OnChecklistsChanged) {
            & $this.OnChecklistsChanged
        }

        return $template
    }

    [void] UpdateTemplate([string]$templateId, [hashtable]$changes) {
        if (-not $this._templatesCache.ContainsKey($templateId)) {
            throw "Template not found: $templateId"
        }

        $template = $this._templatesCache[$templateId]

        if ($changes.ContainsKey('name')) { $template.name = $changes.name }
        if ($changes.ContainsKey('description')) { $template.description = $changes.description }
        if ($changes.ContainsKey('category')) { $template.category = $changes.category }
        if ($changes.ContainsKey('items')) { $template.items = $changes.items }

        $template.modified = [datetime]::Now

        $this.SaveTemplates()

        if ($this.OnTemplateUpdated) {
            & $this.OnTemplateUpdated $template
        }
        if ($this.OnChecklistsChanged) {
            & $this.OnChecklistsChanged
        }
    }

    [void] DeleteTemplate([string]$templateId) {
        if (-not $this._templatesCache.ContainsKey($templateId)) {
            throw "Template not found: $templateId"
        }

        $template = $this._templatesCache[$templateId]
        $this._templatesCache.Remove($templateId)
        $this.SaveTemplates()

        if ($this.OnTemplateDeleted) {
            & $this.OnTemplateDeleted $template
        }
        if ($this.OnChecklistsChanged) {
            & $this.OnChecklistsChanged
        }
    }

    # === Instance CRUD Operations ===

    [array] GetAllInstances() {
        return @($this._instancesCache.Values | Sort-Object -Property modified -Descending)
    }

    [array] GetInstancesByOwner([string]$ownerType, [string]$ownerId) {
        return @($this._instancesCache.Values | Where-Object {
            $_.owner_type -eq $ownerType -and $_.owner_id -eq $ownerId
        } | Sort-Object -Property created -Descending)
    }

    [object] GetInstance([string]$instanceId) {
        if ($this._instancesCache.ContainsKey($instanceId)) {
            return $this._instancesCache[$instanceId]
        }
        return $null
    }

    [object] CreateInstanceFromTemplate([string]$templateId, [string]$ownerType, [string]$ownerId) {
        $template = $this.GetTemplate($templateId)
        if (-not $template) {
            throw "Template not found: $templateId"
        }

        $instanceId = [guid]::NewGuid().ToString()

        # Copy items from template
        $items = @()
        foreach ($templateItem in $template.items) {
            $items += @{
                text = $templateItem.text
                completed = $false
                completed_date = $null
                order = $templateItem.order
            }
        }

        $instance = @{
            id = $instanceId
            title = $template.name
            template_id = $templateId
            owner_type = $ownerType
            owner_id = $ownerId
            items = $items
            completed_count = 0
            total_count = $items.Count
            percent_complete = 0
            created = [datetime]::Now
            modified = [datetime]::Now
        }

        $this._instancesCache[$instanceId] = $instance
        $this.SaveInstances()

        if ($this.OnInstanceAdded) {
            & $this.OnInstanceAdded $instance
        }
        if ($this.OnChecklistsChanged) {
            & $this.OnChecklistsChanged
        }

        return $instance
    }

    [object] CreateBlankInstance([string]$title, [string]$ownerType, [string]$ownerId, [array]$itemTexts) {
        $instanceId = [guid]::NewGuid().ToString()

        $items = @()
        $order = 1
        foreach ($text in $itemTexts) {
            $items += @{
                text = $text
                completed = $false
                completed_date = $null
                order = $order++
            }
        }

        $instance = @{
            id = $instanceId
            title = $title
            template_id = $null
            owner_type = $ownerType
            owner_id = $ownerId
            items = $items
            completed_count = 0
            total_count = $items.Count
            percent_complete = 0
            created = [datetime]::Now
            modified = [datetime]::Now
        }

        $this._instancesCache[$instanceId] = $instance
        $this.SaveInstances()

        if ($this.OnInstanceAdded) {
            & $this.OnInstanceAdded $instance
        }
        if ($this.OnChecklistsChanged) {
            & $this.OnChecklistsChanged
        }

        return $instance
    }

    [void] ToggleItem([string]$instanceId, [int]$itemIndex) {
        if (-not $this._instancesCache.ContainsKey($instanceId)) {
            throw "Instance not found: $instanceId"
        }

        $instance = $this._instancesCache[$instanceId]
        if ($itemIndex -lt 0 -or $itemIndex -ge $instance.items.Count) {
            throw "Invalid item index: $itemIndex"
        }

        $item = $instance.items[$itemIndex]
        $item.completed = -not $item.completed
        $item.completed_date = $(if ($item.completed) { [datetime]::Now } else { $null })

        # Recalculate stats
        $completed = @($instance.items | Where-Object { $_.completed }).Count
        $instance.completed_count = $completed
        $instance.percent_complete = $(if ($instance.total_count -gt 0) {
            [Math]::Round(($completed / $instance.total_count) * 100, 0)
        } else {
            0
        })
        $instance.modified = [datetime]::Now

        $this.SaveInstances()

        if ($this.OnInstanceUpdated) {
            & $this.OnInstanceUpdated $instance
        }
        if ($this.OnChecklistsChanged) {
            & $this.OnChecklistsChanged
        }
    }

    [void] UpdateInstance([string]$instanceId, [hashtable]$changes) {
        if (-not $this._instancesCache.ContainsKey($instanceId)) {
            throw "Instance not found: $instanceId"
        }

        $instance = $this._instancesCache[$instanceId]

        if ($changes.ContainsKey('title')) { $instance.title = $changes.title }
        if ($changes.ContainsKey('items')) {
            $instance.items = $changes.items
            # Recalculate stats
            $instance.total_count = $instance.items.Count
            $completed = @($instance.items | Where-Object { $_.completed }).Count
            $instance.completed_count = $completed
            $instance.percent_complete = $(if ($instance.total_count -gt 0) {
                [Math]::Round(($completed / $instance.total_count) * 100, 0)
            } else {
                0
            })
        }

        $instance.modified = [datetime]::Now

        $this.SaveInstances()

        if ($this.OnInstanceUpdated) {
            & $this.OnInstanceUpdated $instance
        }
        if ($this.OnChecklistsChanged) {
            & $this.OnChecklistsChanged
        }
    }

    [void] DeleteInstance([string]$instanceId) {
        if (-not $this._instancesCache.ContainsKey($instanceId)) {
            throw "Instance not found: $instanceId"
        }

        $instance = $this._instancesCache[$instanceId]
        $this._instancesCache.Remove($instanceId)
        $this.SaveInstances()

        if ($this.OnInstanceDeleted) {
            & $this.OnInstanceDeleted $instance
        }
        if ($this.OnChecklistsChanged) {
            & $this.OnChecklistsChanged
        }
    }
}