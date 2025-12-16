# SpeedTUI Base Model - Foundation for all data models

class BaseModel {
    [string]$Id
    [DateTime]$CreatedAt
    [DateTime]$UpdatedAt
    [bool]$Deleted = $false
    
    BaseModel() {
        $this.Id = [Guid]::NewGuid().ToString()
        $this.CreatedAt = [DateTime]::Now
        $this.UpdatedAt = [DateTime]::Now
    }
    
    BaseModel([hashtable]$data) {
        $this.Id = $(if ($data.Id) { $data.Id } else { [Guid]::NewGuid().ToString() })
        $this.CreatedAt = $(if ($data.CreatedAt) { [DateTime]$data.CreatedAt } else { [DateTime]::Now })
        $this.UpdatedAt = $(if ($data.UpdatedAt) { [DateTime]$data.UpdatedAt } else { [DateTime]::Now })
        $this.Deleted = $(if ($null -ne $data.Deleted) { [bool]$data.Deleted } else { $false })
    }
    
    [void] Touch() {
        $this.UpdatedAt = [DateTime]::Now
    }
    
    [void] SoftDelete() {
        $this.Deleted = $true
        $this.Touch()
    }
    
    [hashtable] ToHashtable() {
        return @{
            Id = $this.Id
            CreatedAt = $this.CreatedAt
            UpdatedAt = $this.UpdatedAt
            Deleted = $this.Deleted
        }
    }
    
    [bool] IsValid() {
        return -not [string]::IsNullOrEmpty($this.Id)
    }
}