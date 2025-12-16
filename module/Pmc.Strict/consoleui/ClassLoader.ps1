# ClassLoader.ps1 - Smart dependency-aware class loading system
# Replaces brittle hardcoded file lists with auto-discovery and intelligent ordering

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Smart class loader that auto-discovers and loads PowerShell class files with dependency resolution

.DESCRIPTION
Features:
- Auto-discovers all .ps1 files in specified directories
- Respects load order via priority system
- Multi-pass loading with dependency retry logic
- Excludes test files automatically
- Detailed logging for troubleshooting
- Handles circular dependencies gracefully

.EXAMPLE
$loader = [ClassLoader]::new($PSScriptRoot)
$loader.AddDirectory("widgets", 100)
$loader.AddDirectory("base", 50)
$loader.LoadAll()
#>
class ClassLoader {
    [System.Collections.ArrayList]$LoadQueue = @()
    [System.Collections.ArrayList]$LoadedFiles = @()
    [System.Collections.ArrayList]$FailedFiles = @()
    [hashtable]$LoadStats = @{}
    [string]$BaseDirectory
    [int]$MaxRetries = 3
    [bool]$ExcludeTests = $true
    [bool]$VerboseLogging = $false

    ClassLoader([string]$baseDir) {
        $this.BaseDirectory = $baseDir
        $this.LoadStats = @{
            TotalFiles = 0
            Loaded = 0
            Failed = 0
            Skipped = 0
            Retries = 0
        }
    }

    <#
    .SYNOPSIS
    Add a directory to the load queue

    .PARAMETER relativePath
    Path relative to BaseDirectory (e.g., "widgets", "base", "screens")

    .PARAMETER priority
    Lower number = loaded first (e.g., base=10, widgets=50, screens=100)

    .PARAMETER recursive
    Whether to include subdirectories
    #>
    [void] AddDirectory([string]$relativePath, [int]$priority, [bool]$recursive = $false) {
        $fullPath = Join-Path $this.BaseDirectory $relativePath

        if (-not (Test-Path $fullPath)) {
            $this.Log("WARNING: Directory not found: $fullPath", "WARN")
            return
        }

        # Discover files
        $files = if ($recursive) {
            Get-ChildItem -Path $fullPath -Filter "*.ps1" -Recurse -File
        } else {
            Get-ChildItem -Path $fullPath -Filter "*.ps1" -File
        }

        foreach ($file in $files) {
            # Skip test files if configured
            if ($this.ExcludeTests -and $file.Name -match '^Test.*\.ps1$') {
                $this.Log("Skipping test file: $($file.Name)", "DEBUG")
                $this.LoadStats.Skipped++
                continue
            }

            # Check for priority override in file header
            $filePriority = $this.ExtractPriorityFromFile($file.FullName)
            if ($null -ne $filePriority) {
                $priority = $filePriority
            }

            $this.LoadQueue.Add(@{
                Path = $file.FullName
                Name = $file.Name
                Priority = $priority
                Directory = $relativePath
                Retries = 0
                LastError = $null
            }) | Out-Null

            $this.LoadStats.TotalFiles++
        }

        $fileCount = @($files).Count
        $this.Log("Discovered $fileCount files in $relativePath (priority=$priority)", "INFO")
    }

    <#
    .SYNOPSIS
    Extract load priority from file header comment
    Files can specify: # LoadPriority: 25
    #>
    [object] ExtractPriorityFromFile([string]$filePath) {
        try {
            $content = Get-Content -Path $filePath -TotalCount 10 -ErrorAction SilentlyContinue
            foreach ($line in $content) {
                if ($line -match '^\s*#\s*LoadPriority:\s*(\d+)') {
                    return [int]$matches[1]
                }
            }
        } catch {
            # Ignore errors reading file header
        }
        return $null
    }

    <#
    .SYNOPSIS
    Load all queued files with dependency resolution
    #>
    [void] LoadAll() {
        $this.Log("=== Starting ClassLoader ===", "INFO")
        $this.Log("Total files queued: $($this.LoadStats.TotalFiles)", "INFO")

        # Sort by priority (lower number first)
        $sortedQueue = $this.LoadQueue | Sort-Object { $_.Priority }, { $_.Name }

        # Multi-pass loading with retry logic
        $pass = 1
        $remainingFiles = [System.Collections.ArrayList]::new($sortedQueue)

        while ($remainingFiles.Count -gt 0 -and $pass -le $this.MaxRetries) {
            $this.Log("--- Load Pass $pass ($($remainingFiles.Count) files remaining) ---", "INFO")

            $stillFailing = [System.Collections.ArrayList]::new()

            foreach ($fileInfo in $remainingFiles) {
                $success = $this.LoadFile($fileInfo)

                if ($success) {
                    $this.LoadedFiles.Add($fileInfo) | Out-Null
                    $this.LoadStats.Loaded++
                } else {
                    # Check if error is due to missing type (dependency issue)
                    if ($fileInfo.LastError -match 'Unable to find type') {
                        if ($fileInfo.Retries -lt $this.MaxRetries) {
                            $fileInfo.Retries++
                            $stillFailing.Add($fileInfo) | Out-Null
                            $this.LoadStats.Retries++
                            $this.Log("Will retry: $($fileInfo.Name) (attempt $($fileInfo.Retries + 1))", "DEBUG")
                        } else {
                            $this.FailedFiles.Add($fileInfo) | Out-Null
                            $this.LoadStats.Failed++
                            $this.Log("FAILED after $($this.MaxRetries) attempts: $($fileInfo.Name)", "ERROR")
                            $this.Log("  Error: $($fileInfo.LastError)", "ERROR")
                        }
                    } else {
                        # Non-dependency error, fail immediately
                        $this.FailedFiles.Add($fileInfo) | Out-Null
                        $this.LoadStats.Failed++
                        $this.Log("FAILED (non-dependency error): $($fileInfo.Name)", "ERROR")
                        $this.Log("  Error: $($fileInfo.LastError)", "ERROR")
                    }
                }
            }

            # If no progress made this pass, break to avoid infinite loop
            if ($stillFailing.Count -eq $remainingFiles.Count) {
                $this.Log("No progress made in pass $pass - circular dependency or missing files", "WARN")
                foreach ($f in $stillFailing) {
                    $this.FailedFiles.Add($f) | Out-Null
                    $this.LoadStats.Failed++
                }
                break
            }

            $remainingFiles = $stillFailing
            $pass++
        }

        $this.PrintSummary()
    }

    <#
    .SYNOPSIS
    Load a single file with error handling
    #>
    [bool] LoadFile([hashtable]$fileInfo) {
        try {
            # Use dot-sourcing to load in current scope
            . $fileInfo.Path

            $this.Log("✓ Loaded: $($fileInfo.Name)", "DEBUG")
            return $true

        } catch {
            $fileInfo.LastError = $_.Exception.Message
            return $false
        }
    }

    <#
    .SYNOPSIS
    Print loading summary
    #>
    [void] PrintSummary() {
        $this.Log("=== ClassLoader Summary ===", "INFO")
        $this.Log("Total files discovered: $($this.LoadStats.TotalFiles)", "INFO")
        $this.Log("Successfully loaded: $($this.LoadStats.Loaded)", "INFO")
        $this.Log("Failed: $($this.LoadStats.Failed)", "INFO")
        $this.Log("Skipped (tests): $($this.LoadStats.Skipped)", "INFO")
        $this.Log("Total retries: $($this.LoadStats.Retries)", "INFO")

        if ($this.FailedFiles.Count -gt 0) {
            $this.Log("--- Failed Files ---", "ERROR")
            foreach ($f in $this.FailedFiles) {
                $this.Log("  ✗ $($f.Name): $($f.LastError)", "ERROR")
            }
        }
    }

    <#
    .SYNOPSIS
    Log message to console and file
    #>
    [void] Log([string]$message, [string]$level) {
        # Skip debug messages unless verbose
        if ($level -eq "DEBUG" -and -not $this.VerboseLogging) {
            return
        }

        # Log to PMC log file if available
        if ($global:PmcTuiLogFile) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            $logLine = "[$timestamp] [ClassLoader][$level] $message"
            Add-Content -Path $global:PmcTuiLogFile -Value $logLine
        }

        # Also log errors to file
        if ($level -in @("ERROR", "WARN")) {
            Add-Content -Path "/tmp/pmc-debug.log" -Value "[$(Get-Date -Format 'HH:mm:ss.fff')] [ClassLoader] [$level] $message"
        }
    }

    <#
    .SYNOPSIS
    Enable verbose logging for troubleshooting
    #>
    [void] EnableVerbose() {
        $this.VerboseLogging = $true
    }
}

<#
.SYNOPSIS
Helper function to create and configure a standard PMC class loader

.DESCRIPTION
Creates a ClassLoader configured with standard PMC directory structure:
- theme (priority 5) - Theme system
- widgets (priority 10) - Base widgets
- layout (priority 20) - Layout managers
- base (priority 30) - Base screen classes
- services (priority 40) - Service classes
- screens (priority 50) - Concrete screens (lazy-loaded via menu)
- helpers (priority 60) - Helper functions

.PARAMETER baseDirectory
Root directory (typically $PSScriptRoot of Start-PmcTUI.ps1)

.PARAMETER loadScreens
Whether to pre-load all screens (default: $false for lazy loading)

.EXAMPLE
$loader = New-PmcClassLoader $PSScriptRoot
$loader.LoadAll()
#>
function New-PmcClassLoader {
    param(
        [string]$baseDirectory,
        [bool]$loadScreens = $false,
        [bool]$verbose = $false
    )

    $loader = [ClassLoader]::new($baseDirectory)

    if ($verbose -or ($global:PmcTuiLogLevel -ge 3)) {
        $loader.EnableVerbose()
    }

    # Add directories in dependency order (lower priority = loaded first)
    $loader.AddDirectory("theme", 5)
    $loader.AddDirectory("widgets", 10)
    $loader.AddDirectory("layout", 20)
    $loader.AddDirectory("base", 30)
    $loader.AddDirectory("services", 40)

    # Screens are typically lazy-loaded via MenuRegistry
    # But can be pre-loaded for debugging or if lazy-loading causes issues
    if ($loadScreens) {
        $loader.AddDirectory("screens", 50)
    }

    $loader.AddDirectory("helpers", 60)

    return $loader
}
