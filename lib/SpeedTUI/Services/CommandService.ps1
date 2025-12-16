# SpeedTUI CommandService - Comprehensive command library management
# Inherits from DataService for full CRUD operations

# Load dependencies
if (-not ([System.Management.Automation.PSTypeName]'DataService').Type) {
    . "$PSScriptRoot/DataService.ps1"
}

if (-not ([System.Management.Automation.PSTypeName]'Command').Type) {
    . "$PSScriptRoot/../Models/Command.ps1"
}

class CommandService : DataService {
    [hashtable]$SearchCache = @{}
    [hashtable]$GroupCache = @{}
    [string]$FileName = "commands"
    [string[]]$DefaultGroups = @("System", "Development", "PowerShell", "Git", "Docker", "Network", "File Management")
    [string[]]$DefaultCategories = @("Administration", "Development", "Utilities", "Scripts", "Maintenance")
    
    CommandService() : base("_ProjectData") {
        Write-Host "CommandService initialized"
        $this.EnsureDefaultData()
    }
    
    # =============================================================================
    # CRUD OPERATIONS FOR COMMAND
    # =============================================================================
    
    [Command[]] GetAll() {
        $data = $this.LoadData($this.FileName)
        $commands = @()
        
        foreach ($item in $data) {
            $commands += [Command]::new($item)
        }
        
        return $commands
    }
    
    [Command] GetById([string]$id) {
        $data = $this.LoadData($this.FileName)
        $item = $this.FindById($data, $id)
        
        if ($item) {
            return [Command]::new($item)
        }
        
        return $null
    }
    
    [Command] Create([Command]$entity) {
        if (-not $entity.IsValid()) {
            throw "Cannot create invalid command entity"
        }
        
        $data = $this.LoadData($this.FileName)
        $entityHash = $entity.ToHashtable()
        $data = $this.AddItem($data, $entityHash)
        $this.SaveData($this.FileName, $data)
        $this.ClearCommandCaches()
        
        Write-Host "Created command: $($entity.GetDisplayText())"
        return $entity
    }
    
    [Command] Update([Command]$entity) {
        if (-not $entity.IsValid()) {
            throw "Cannot update to invalid command entity"
        }
        
        $data = $this.LoadData($this.FileName)
        $entityHash = $entity.ToHashtable()
        $data = $this.UpdateItem($data, $entity.Id, $entityHash)
        $this.SaveData($this.FileName, $data)
        $this.ClearCommandCaches()
        
        Write-Host "Updated command: $($entity.GetDisplayText())"
        return $entity
    }
    
    [void] Delete([string]$id) {
        $data = $this.LoadData($this.FileName)
        $data = $this.DeleteItem($data, $id, $true)  # Soft delete
        $this.SaveData($this.FileName, $data)
        $this.ClearCommandCaches()
        
        Write-Host "Deleted command: $id"
    }
    
    # =============================================================================
    # SEARCH AND FILTERING
    # =============================================================================
    
    [Command[]] Search([string]$searchTerm) {
        if ([string]::IsNullOrEmpty($searchTerm)) {
            return $this.GetAll()
        }
        
        # Check cache first
        $cacheKey = $searchTerm.ToLower()
        if ($this.SearchCache.ContainsKey($cacheKey)) {
            Write-Host "Retrieved search results from cache for: $searchTerm"
            return $this.SearchCache[$cacheKey]
        }
        
        $allCommands = $this.GetAll()
        $results = @()
        
        foreach ($command in $allCommands) {
            if ($command.MatchesSearch($searchTerm)) {
                $results += $command
            }
        }
        
        # Cache results
        $this.SearchCache[$cacheKey] = $results
        
        Write-Host "Found $($results.Count) commands matching: $searchTerm"
        return $results
    }
    
    [Command[]] FilterByGroup([string]$group) {
        if ([string]::IsNullOrEmpty($group)) {
            return $this.GetAll()
        }
        
        $commands = $this.GetAll()
        $filtered = @()
        
        foreach ($command in $commands) {
            if ($command.MatchesDoFilter("group", $group)) {
                $filtered += $command
            }
        }
        
        return $filtered
    }
    
    [Command[]] FilterByCategory([string]$category) {
        if ([string]::IsNullOrEmpty($category)) {
            return $this.GetAll()
        }
        
        $commands = $this.GetAll()
        $filtered = @()
        
        foreach ($command in $commands) {
            if ($command.MatchesDoFilter("category", $category)) {
                $filtered += $command
            }
        }
        
        return $filtered
    }
    
    [Command[]] FilterByLanguage([string]$language) {
        if ([string]::IsNullOrEmpty($language)) {
            return $this.GetAll()
        }
        
        $commands = $this.GetAll()
        $filtered = @()
        
        foreach ($command in $commands) {
            if ($command.MatchesDoFilter("language", $language)) {
                $filtered += $command
            }
        }
        
        return $filtered
    }
    
    [Command[]] FilterByTag([string]$tag) {
        if ([string]::IsNullOrEmpty($tag)) {
            return $this.GetAll()
        }
        
        $commands = $this.GetAll()
        $filtered = @()
        
        foreach ($command in $commands) {
            if ($command.MatchesDoFilter("tag", $tag)) {
                $filtered += $command
            }
        }
        
        return $filtered
    }
    
    [Command[]] FilterByUsage([string]$usage) {
        $commands = $this.GetAll()
        $filtered = @()
        
        foreach ($command in $commands) {
            if ($command.MatchesDoFilter("used", $usage)) {
                $filtered += $command
            }
        }
        
        return $filtered
    }
    
    [Command[]] AdvancedSearch([hashtable]$criteria) {
        $commands = $this.GetAll()
        $results = @()
        
        foreach ($command in $commands) {
            $matches = $true
            
            # Apply each filter criteria
            foreach ($key in $criteria.Keys) {
                $value = $criteria[$key]
                if (-not [string]::IsNullOrEmpty($value)) {
                    if ($key -eq "search") {
                        if (-not $command.MatchesSearch($value)) {
                            $matches = $false
                            break
                        }
                    } else {
                        if (-not $command.MatchesDoFilter($key, $value)) {
                            $matches = $false
                            break
                        }
                    }
                }
            }
            
            if ($matches) {
                $results += $command
            }
        }
        
        Write-Host "Advanced search found $($results.Count) commands"
        return $results
    }
    
    # =============================================================================
    # COMMAND ORGANIZATION
    # =============================================================================
    
    [string[]] GetAllGroups() {
        $commands = $this.GetAll()
        $groups = @()
        
        foreach ($command in $commands) {
            if (-not [string]::IsNullOrEmpty($command.Group) -and $command.Group -notin $groups) {
                $groups += $command.Group
            }
        }
        
        return ($groups | Sort-Object)
    }
    
    [string[]] GetAllCategories() {
        $commands = $this.GetAll()
        $categories = @()
        
        foreach ($command in $commands) {
            if (-not [string]::IsNullOrEmpty($command.Category) -and $command.Category -notin $categories) {
                $categories += $command.Category
            }
        }
        
        return ($categories | Sort-Object)
    }
    
    [string[]] GetAllLanguages() {
        $commands = $this.GetAll()
        $languages = @()
        
        foreach ($command in $commands) {
            if (-not [string]::IsNullOrEmpty($command.Language) -and $command.Language -notin $languages) {
                $languages += $command.Language
            }
        }
        
        return ($languages | Sort-Object)
    }
    
    [string[]] GetAllTags() {
        $commands = $this.GetAll()
        $tags = @()
        
        foreach ($command in $commands) {
            foreach ($tag in $command.Tags) {
                if (-not [string]::IsNullOrEmpty($tag) -and $tag -notin $tags) {
                    $tags += $tag
                }
            }
        }
        
        return ($tags | Sort-Object)
    }
    
    [hashtable] GetGroupSummary() {
        $commands = $this.GetAll()
        $summary = @{}
        
        foreach ($command in $commands) {
            $group = $(if ([string]::IsNullOrEmpty($command.Group)) { "Ungrouped" } else { $command.Group })
            
            if ($summary.ContainsKey($group)) {
                $summary[$group]++
            } else {
                $summary[$group] = 1
            }
        }
        
        return $summary
    }
    
    # =============================================================================
    # USAGE TRACKING
    # =============================================================================
    
    [void] RecordUsage([string]$commandId) {
        $command = $this.GetById($commandId)
        if ($command) {
            $command.RecordUsage()
            $this.Update($command)
        }
    }
    
    [Command[]] GetMostUsedCommands([int]$limit = 10) {
        $commands = $this.GetAll()
        return ($commands | Sort-Object UseCount -Descending | Select-Object -First $limit)
    }
    
    [Command[]] GetRecentlyUsedCommands([int]$limit = 10) {
        $commands = $this.GetAll() | Where-Object { $_.LastUsed -ne [DateTime]::MinValue }
        return ($commands | Sort-Object LastUsed -Descending | Select-Object -First $limit)
    }
    
    [Command[]] GetNeverUsedCommands() {
        $commands = $this.GetAll()
        return ($commands | Where-Object { $_.UseCount -eq 0 })
    }
    
    [hashtable] GetUsageStatistics() {
        $commands = $this.GetAll()
        $totalCommands = $commands.Count
        $usedCommands = ($commands | Where-Object { $_.UseCount -gt 0 }).Count
        $neverUsed = $totalCommands - $usedCommands
        $totalUsage = ($commands | Measure-Object -Property UseCount -Sum).Sum
        $averageUsage = $(if ($totalCommands -gt 0) { [Math]::Round($totalUsage / $totalCommands, 2) } else { 0 })
        
        $stats = @{
            TotalCommands = $totalCommands
            UsedCommands = $usedCommands
            NeverUsed = $neverUsed
            TotalUsage = $totalUsage
            AverageUsage = $averageUsage
            UsageRate = $(if ($totalCommands -gt 0) { [Math]::Round(($usedCommands / $totalCommands) * 100, 1) } else { 0 })
        }
        
        return $stats
    }
    
    # =============================================================================
    # COMMAND TEMPLATES AND CLONING
    # =============================================================================
    
    [Command[]] GetTemplates() {
        $commands = $this.GetAll()
        return ($commands | Where-Object { $_.IsTemplate })
    }
    
    [Command] CreateFromTemplate([string]$templateId, [hashtable]$customizations = @{}) {
        $template = $this.GetById($templateId)
        if (-not $template) {
            throw "Template not found: $templateId"
        }
        
        if (-not $template.IsTemplate) {
            throw "Command is not a template: $templateId"
        }
        
        $newCommand = $template.Clone()
        
        # Apply customizations
        foreach ($key in $customizations.Keys) {
            if ($newCommand.PSObject.Properties[$key]) {
                $newCommand.$key = $customizations[$key]
            }
        }
        
        # Ensure it's not marked as a template
        $newCommand.IsTemplate = $false
        
        return $this.Create($newCommand)
    }
    
    [Command] CloneCommand([string]$commandId, [hashtable]$customizations = @{}) {
        $original = $this.GetById($commandId)
        if (-not $original) {
            throw "Command not found: $commandId"
        }
        
        $clone = $original.Clone()
        
        # Apply customizations
        foreach ($key in $customizations.Keys) {
            if ($clone.PSObject.Properties[$key]) {
                $clone.$key = $customizations[$key]
            }
        }
        
        return $this.Create($clone)
    }
    
    # =============================================================================
    # BULK OPERATIONS
    # =============================================================================
    
    [void] ImportCommands([hashtable[]]$commandData) {
        Write-Host "Starting import of command data"
        $importCount = 0
        $skipCount = 0
        
        foreach ($data in $commandData) {
            try {
                $command = [Command]::new($data)
                if ($command.IsValid()) {
                    $this.Create($command)
                    $importCount++
                } else {
                    Write-Host "Skipped invalid command: $($data.Title)"
                    $skipCount++
                }
            } catch {
                Write-Host "Failed to import command: $($_.Exception.Message)"
                $skipCount++
            }
        }
        
        Write-Host "Imported $importCount commands, skipped $skipCount"
    }
    
    [hashtable[]] ExportCommands([string]$filterType = "", [string]$filterValue = "") {
        $commands = $(if ([string]::IsNullOrEmpty($filterType)) {
            $this.GetAll()
        } else {
            switch ($filterType.ToLower()) {
                "group" { $this.FilterByGroup($filterValue) }
                "category" { $this.FilterByCategory($filterValue) }
                "language" { $this.FilterByLanguage($filterValue) }
                "tag" { $this.FilterByTag($filterValue) }
                default { $this.GetAll() }
            }
        })
        
        $exportData = @()
        foreach ($command in $commands) {
            $exportData += $command.ToHashtable()
        }
        
        Write-Host "Exported $($exportData.Count) commands"
        return $exportData
    }
    
    [void] BulkUpdateGroup([string[]]$commandIds, [string]$newGroup) {
        $updateCount = 0
        
        foreach ($id in $commandIds) {
            $command = $this.GetById($id)
            if ($command) {
                $command.Group = $newGroup
                $this.Update($command)
                $updateCount++
            }
        }
        
        Write-Host "Updated group for $updateCount commands"
    }
    
    [void] BulkUpdateCategory([string[]]$commandIds, [string]$newCategory) {
        $updateCount = 0
        
        foreach ($id in $commandIds) {
            $command = $this.GetById($id)
            if ($command) {
                $command.Category = $newCategory
                $this.Update($command)
                $updateCount++
            }
        }
        
        Write-Host "Updated category for $updateCount commands"
    }
    
    [void] BulkAddTag([string[]]$commandIds, [string]$tag) {
        $updateCount = 0
        
        foreach ($id in $commandIds) {
            $command = $this.GetById($id)
            if ($command) {
                $command.AddTag($tag)
                $this.Update($command)
                $updateCount++
            }
        }
        
        Write-Host "Added tag '$tag' to $updateCount commands"
    }
    
    [void] BulkRemoveTag([string[]]$commandIds, [string]$tag) {
        $updateCount = 0
        
        foreach ($id in $commandIds) {
            $command = $this.GetById($id)
            if ($command) {
                $command.RemoveTag($tag)
                $this.Update($command)
                $updateCount++
            }
        }
        
        Write-Host "Removed tag '$tag' from $updateCount commands"
    }
    
    # =============================================================================
    # QUICK COMMAND CREATION
    # =============================================================================
    
    [Command] CreateQuickCommand([string]$commandText, [string]$title = "", [string]$group = "General") {
        $commandData = @{
            CommandText = $commandText
            Title = $(if ([string]::IsNullOrEmpty($title)) { $commandText } else { $title })
            Group = $group
            Language = "PowerShell"
        }
        
        $command = [Command]::new($commandData)
        return $this.Create($command)
    }
    
    [Command] CreateCommandWithDetails([hashtable]$details) {
        $requiredFields = @("CommandText")
        foreach ($field in $requiredFields) {
            if (-not $details.ContainsKey($field) -or [string]::IsNullOrEmpty($details[$field])) {
                throw "Required field missing: $field"
            }
        }
        
        # Set defaults for optional fields
        if (-not $details.ContainsKey("Language")) { $details.Language = "PowerShell" }
        if (-not $details.ContainsKey("Group")) { $details.Group = "General" }
        if (-not $details.ContainsKey("Tags")) { $details.Tags = @() }
        
        $command = [Command]::new($details)
        return $this.Create($command)
    }
    
    # =============================================================================
    # FAVORITES AND BOOKMARKS
    # =============================================================================
    
    [void] AddToFavorites([string]$commandId) {
        $command = $this.GetById($commandId)
        if ($command) {
            $command.AddTag("favorite")
            $this.Update($command)
            Write-Host "Added to favorites: $($command.GetDisplayText())"
        }
    }
    
    [void] RemoveFromFavorites([string]$commandId) {
        $command = $this.GetById($commandId)
        if ($command) {
            $command.RemoveTag("favorite")
            $this.Update($command)
            Write-Host "Removed from favorites: $($command.GetDisplayText())"
        }
    }
    
    [Command[]] GetFavorites() {
        return $this.FilterByTag("favorite")
    }
    
    [bool] IsFavorite([string]$commandId) {
        $command = $this.GetById($commandId)
        return $command -and $command.HasTag("favorite")
    }
    
    # =============================================================================
    # CACHE MANAGEMENT
    # =============================================================================
    
    [void] ClearCommandCaches() {
        $this.SearchCache.Clear()
        $this.GroupCache.Clear()
        Write-Host "Cleared command caches"
    }
    
    [void] RefreshCaches() {
        $this.ClearCommandCaches()
        
        # Pre-populate common searches
        $commonSearches = @("git", "docker", "powershell", "system")
        foreach ($term in $commonSearches) {
            $this.Search($term) | Out-Null
        }
        
        Write-Host "Refreshed command caches"
    }
    
    # =============================================================================
    # VALIDATION AND UTILITIES
    # =============================================================================
    
    [bool] ValidateCommand([Command]$command) {
        if (-not $command.IsValid()) {
            return $false
        }
        
        # Additional validations
        if ([string]::IsNullOrWhiteSpace($command.CommandText)) {
            return $false
        }
        
        return $true
    }
    
    [Command[]] SortCommands([Command[]]$commands, [string]$sortBy = "Title", [bool]$descending = $false) {
        $sortByLower = $sortBy.ToLower()
        
        if ($sortByLower -eq "title") {
            if ($descending) {
                return $commands | Sort-Object Title -Descending
            } else {
                return $commands | Sort-Object Title
            }
        } elseif ($sortByLower -eq "usecount") {
            if ($descending) {
                return $commands | Sort-Object UseCount -Descending
            } else {
                return $commands | Sort-Object UseCount
            }
        } elseif ($sortByLower -eq "lastused") {
            if ($descending) {
                return $commands | Sort-Object LastUsed -Descending
            } else {
                return $commands | Sort-Object LastUsed
            }
        } elseif ($sortByLower -eq "group") {
            if ($descending) {
                return $commands | Sort-Object Group -Descending
            } else {
                return $commands | Sort-Object Group
            }
        } elseif ($sortByLower -eq "category") {
            if ($descending) {
                return $commands | Sort-Object Category -Descending
            } else {
                return $commands | Sort-Object Category
            }
        } else {
            return $commands
        }
    }
    
    [Command[]] PaginateCommands([Command[]]$commands, [int]$page = 1, [int]$pageSize = 20) {
        $startIndex = ($page - 1) * $pageSize
        $endIndex = [Math]::Min($startIndex + $pageSize - 1, $commands.Count - 1)
        
        if ($startIndex -ge $commands.Count) {
            return @()
        }
        
        return $commands[$startIndex..$endIndex]
    }
    
    # =============================================================================
    # DEFAULT DATA INITIALIZATION
    # =============================================================================
    
    [void] EnsureDefaultData() {
        $commands = $this.GetAll()
        if ($commands.Count -eq 0) {
            Write-Host "Initializing default commands"
            $this.CreateDefaultCommands()
        }
    }
    
    [void] CreateDefaultCommands() {
        $defaultCommands = @(
            @{
                Title = "Get System Information"
                CommandText = "Get-ComputerInfo | Select-Object WindowsProductName, TotalPhysicalMemoryMB, CsProcessors"
                Description = "Display basic system information including OS, memory, and CPU"
                Group = "System"
                Category = "Administration"
                Language = "PowerShell"
                Tags = @("system", "info", "diagnostics")
            },
            @{
                Title = "List Running Processes"
                CommandText = "Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, CPU, WorkingSet"
                Description = "Show top 10 processes by CPU usage"
                Group = "System"
                Category = "Administration"
                Language = "PowerShell"
                Tags = @("process", "performance", "monitoring")
            },
            @{
                Title = "Git Status"
                CommandText = "git status --porcelain"
                Description = "Show git repository status in short format"
                Group = "Git"
                Category = "Development"
                Language = "Git"
                Tags = @("git", "status", "vcs")
            },
            @{
                Title = "Docker List Containers"
                CommandText = "docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
                Description = "List all Docker containers with formatted output"
                Group = "Docker"
                Category = "Development"
                Language = "Docker"
                Tags = @("docker", "containers", "devops")
            },
            @{
                Title = "Find Large Files"
                CommandText = "Get-ChildItem -Recurse | Sort-Object Length -Descending | Select-Object -First 10 FullName, @{Name='SizeMB';Expression={[Math]::Round($_.Length/1MB,2)}}"
                Description = "Find the 10 largest files in the current directory tree"
                Group = "File Management"
                Category = "Utilities"
                Language = "PowerShell"
                Tags = @("files", "disk", "cleanup")
            }
        )
        
        foreach ($cmdData in $defaultCommands) {
            try {
                $command = [Command]::new($cmdData)
                $this.Create($command)
            } catch {
                Write-Host "Failed to create default command: $($_.Exception.Message)"
            }
        }
    }
}