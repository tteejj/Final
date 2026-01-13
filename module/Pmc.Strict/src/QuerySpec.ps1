# Query specification classes for the PMC query language system

Set-StrictMode -Version Latest

class PmcQuerySpec {
    [string] $Domain = ''       # task|project|timelog
    [string[]] $Columns = @()   # visible columns in order
    [string[]] $RawTokens = @() # raw query tokens (post 'q')
    [string[]] $Metrics = @()
    [hashtable[]] $Sort = @()   # e.g., @{ Field='due'; Dir='Asc' }
    [string[]] $With = @()
    [string] $Group = ''
    [hashtable] $Filters = @{}
    [string] $View = 'list'     # list | kanban (future)

    PmcQuerySpec() {
        $this.Columns = @()
        $this.RawTokens = @()
        $this.Metrics = @()
        $this.Sort = @()
        $this.With = @()
        $this.Filters = @{}
    }
}

# QuerySpec.ps1 contains only classes, no functions to export