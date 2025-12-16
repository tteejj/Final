# SpeedTUI Project Model - Complete project management entity

# Load BaseModel if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'BaseModel').Type) {
    . "$PSScriptRoot/BaseModel.ps1"
}

class Project : BaseModel {
    # Core Project Information
    [string]$FullProjectName = ""
    [string]$ID1 = ""
    [string]$ID2 = ""
    [DateTime]$DateAssigned
    [DateTime]$BFDate
    [DateTime]$DateDue
    [string]$Note = ""
    [string]$CAAPath = ""
    [string]$RequestPath = ""
    [string]$T2020Path = ""
    [decimal]$CumulativeHrs = 0
    [DateTime]$ClosedDate
    [string]$Status = "Active"
    
    # Audit Information
    [string]$AuditType = ""
    [string]$AuditProgram = ""
    [string]$AuditCase = ""
    [DateTime]$AuditStartDate
    [DateTime]$AuditPeriodFrom
    [DateTime]$AuditPeriodTo
    [DateTime]$AuditPeriod2From
    [DateTime]$AuditPeriod2To
    [DateTime]$AuditPeriod3From
    [DateTime]$AuditPeriod3To
    [DateTime]$AuditPeriod4From
    [DateTime]$AuditPeriod4To
    [DateTime]$AuditPeriod5From
    [DateTime]$AuditPeriod5To
    
    # Client Information
    [string]$ClientID = ""  # TPNum
    [string]$Address = ""
    [string]$City = ""
    [string]$Province = ""
    [string]$PostalCode = ""
    [string]$Country = ""
    [string]$ShipToAddress = ""
    
    # Personnel
    [string]$AuditorName = ""
    [string]$AuditorPhone = ""
    [string]$AuditorTL = ""
    [string]$AuditorTLPhone = ""
    
    # Contacts
    [string]$Contact1Name = ""
    [string]$Contact1Phone = ""
    [string]$Contact1Ext = ""
    [string]$Contact1Address = ""
    [string]$Contact1Title = ""
    [string]$Contact2Name = ""
    [string]$Contact2Phone = ""
    [string]$Contact2Ext = ""
    [string]$Contact2Address = ""
    [string]$Contact2Title = ""
    
    # Accounting Systems
    [string]$AccountingSoftware1 = ""
    [string]$AccountingSoftware1Other = ""
    [string]$AccountingSoftware1Type = ""
    [string]$AccountingSoftware2 = ""
    [string]$AccountingSoftware2Other = ""
    [string]$AccountingSoftware2Type = ""
    
    # Additional Information
    [DateTime]$RequestDate
    [string]$FXInfo = ""
    [string]$Comments = ""
    
    Project() : base() {
        $this.DateAssigned = [DateTime]::Now
        $this.DateDue = [DateTime]::Now.AddDays(30)
        $this.BFDate = [DateTime]::Now
        $this.AuditStartDate = [DateTime]::Now
        $this.AuditPeriodFrom = [DateTime]::Now.AddYears(-1)
        $this.AuditPeriodTo = [DateTime]::Now
        $this.RequestDate = [DateTime]::Now
    }
    
    Project([hashtable]$data) : base($data) {
        # Core Information
        $this.FullProjectName = $(if ($data.FullProjectName) { $data.FullProjectName } else { "" })
        $this.ID1 = $(if ($data.ID1) { $data.ID1 } else { "" })
        $this.ID2 = $(if ($data.ID2) { $data.ID2 } else { "" })
        $this.DateAssigned = $(if ($data.DateAssigned) { [DateTime]$data.DateAssigned } else { [DateTime]::Now })
        $this.BFDate = $(if ($data.BFDate) { [DateTime]$data.BFDate } else { [DateTime]::Now })
        $this.DateDue = $(if ($data.DateDue) { [DateTime]$data.DateDue } else { [DateTime]::Now.AddDays(30) })
        $this.Note = $(if ($data.Note) { $data.Note } else { "" })
        $this.CAAPath = $(if ($data.CAAPath) { $data.CAAPath } else { "" })
        $this.RequestPath = $(if ($data.RequestPath) { $data.RequestPath } else { "" })
        $this.T2020Path = $(if ($data.T2020Path) { $data.T2020Path } else { "" })
        $this.CumulativeHrs = $(if ($data.CumulativeHrs) { [decimal]$data.CumulativeHrs } else { 0 })
        $this.ClosedDate = $(if ($data.ClosedDate) { [DateTime]$data.ClosedDate } else { [DateTime]::MinValue })
        $this.Status = $(if ($data.Status) { $data.Status } else { "Active" })
        
        # Audit Information
        $this.AuditType = $(if ($data.AuditType) { $data.AuditType } else { "" })
        $this.AuditProgram = $(if ($data.AuditProgram) { $data.AuditProgram } else { "" })
        $this.AuditCase = $(if ($data.AuditCase) { $data.AuditCase } else { "" })
        $this.AuditStartDate = $(if ($data.AuditStartDate) { [DateTime]$data.AuditStartDate } else { [DateTime]::Now })
        $this.AuditPeriodFrom = $(if ($data.AuditPeriodFrom) { [DateTime]$data.AuditPeriodFrom } else { [DateTime]::Now.AddYears(-1) })
        $this.AuditPeriodTo = $(if ($data.AuditPeriodTo) { [DateTime]$data.AuditPeriodTo } else { [DateTime]::Now })
        
        # Set additional audit periods if provided
        if ($data.AuditPeriod2From) { $this.AuditPeriod2From = [DateTime]$data.AuditPeriod2From }
        if ($data.AuditPeriod2To) { $this.AuditPeriod2To = [DateTime]$data.AuditPeriod2To }
        if ($data.AuditPeriod3From) { $this.AuditPeriod3From = [DateTime]$data.AuditPeriod3From }
        if ($data.AuditPeriod3To) { $this.AuditPeriod3To = [DateTime]$data.AuditPeriod3To }
        if ($data.AuditPeriod4From) { $this.AuditPeriod4From = [DateTime]$data.AuditPeriod4From }
        if ($data.AuditPeriod4To) { $this.AuditPeriod4To = [DateTime]$data.AuditPeriod4To }
        if ($data.AuditPeriod5From) { $this.AuditPeriod5From = [DateTime]$data.AuditPeriod5From }
        if ($data.AuditPeriod5To) { $this.AuditPeriod5To = [DateTime]$data.AuditPeriod5To }
        
        # Client Information
        $this.ClientID = $(if ($data.ClientID) { $data.ClientID } else { "" })
        $this.Address = $(if ($data.Address) { $data.Address } else { "" })
        $this.City = $(if ($data.City) { $data.City } else { "" })
        $this.Province = $(if ($data.Province) { $data.Province } else { "" })
        $this.PostalCode = $(if ($data.PostalCode) { $data.PostalCode } else { "" })
        $this.Country = $(if ($data.Country) { $data.Country } else { "" })
        $this.ShipToAddress = $(if ($data.ShipToAddress) { $data.ShipToAddress } else { "" })
        
        # Personnel
        $this.AuditorName = $(if ($data.AuditorName) { $data.AuditorName } else { "" })
        $this.AuditorPhone = $(if ($data.AuditorPhone) { $data.AuditorPhone } else { "" })
        $this.AuditorTL = $(if ($data.AuditorTL) { $data.AuditorTL } else { "" })
        $this.AuditorTLPhone = $(if ($data.AuditorTLPhone) { $data.AuditorTLPhone } else { "" })
        
        # Contacts
        $this.Contact1Name = $(if ($data.Contact1Name) { $data.Contact1Name } else { "" })
        $this.Contact1Phone = $(if ($data.Contact1Phone) { $data.Contact1Phone } else { "" })
        $this.Contact1Ext = $(if ($data.Contact1Ext) { $data.Contact1Ext } else { "" })
        $this.Contact1Address = $(if ($data.Contact1Address) { $data.Contact1Address } else { "" })
        $this.Contact1Title = $(if ($data.Contact1Title) { $data.Contact1Title } else { "" })
        $this.Contact2Name = $(if ($data.Contact2Name) { $data.Contact2Name } else { "" })
        $this.Contact2Phone = $(if ($data.Contact2Phone) { $data.Contact2Phone } else { "" })
        $this.Contact2Ext = $(if ($data.Contact2Ext) { $data.Contact2Ext } else { "" })
        $this.Contact2Address = $(if ($data.Contact2Address) { $data.Contact2Address } else { "" })
        $this.Contact2Title = $(if ($data.Contact2Title) { $data.Contact2Title } else { "" })
        
        # Accounting Systems
        $this.AccountingSoftware1 = $(if ($data.AccountingSoftware1) { $data.AccountingSoftware1 } else { "" })
        $this.AccountingSoftware1Other = $(if ($data.AccountingSoftware1Other) { $data.AccountingSoftware1Other } else { "" })
        $this.AccountingSoftware1Type = $(if ($data.AccountingSoftware1Type) { $data.AccountingSoftware1Type } else { "" })
        $this.AccountingSoftware2 = $(if ($data.AccountingSoftware2) { $data.AccountingSoftware2 } else { "" })
        $this.AccountingSoftware2Other = $(if ($data.AccountingSoftware2Other) { $data.AccountingSoftware2Other } else { "" })
        $this.AccountingSoftware2Type = $(if ($data.AccountingSoftware2Type) { $data.AccountingSoftware2Type } else { "" })
        
        # Additional Information
        $this.RequestDate = $(if ($data.RequestDate) { [DateTime]$data.RequestDate } else { [DateTime]::Now })
        $this.FXInfo = $(if ($data.FXInfo) { $data.FXInfo } else { "" })
        $this.Comments = $(if ($data.Comments) { $data.Comments } else { "" })
    }
    
    [hashtable] ToHashtable() {
        $baseHash = ([BaseModel]$this).ToHashtable()
        
        $projectHash = @{
            # Core Information
            FullProjectName = $this.FullProjectName
            ID1 = $this.ID1
            ID2 = $this.ID2
            DateAssigned = $this.DateAssigned
            BFDate = $this.BFDate
            DateDue = $this.DateDue
            Note = $this.Note
            CAAPath = $this.CAAPath
            RequestPath = $this.RequestPath
            T2020Path = $this.T2020Path
            CumulativeHrs = $this.CumulativeHrs
            ClosedDate = $this.ClosedDate
            Status = $this.Status
            
            # Audit Information
            AuditType = $this.AuditType
            AuditProgram = $this.AuditProgram
            AuditCase = $this.AuditCase
            AuditStartDate = $this.AuditStartDate
            AuditPeriodFrom = $this.AuditPeriodFrom
            AuditPeriodTo = $this.AuditPeriodTo
            AuditPeriod2From = $this.AuditPeriod2From
            AuditPeriod2To = $this.AuditPeriod2To
            AuditPeriod3From = $this.AuditPeriod3From
            AuditPeriod3To = $this.AuditPeriod3To
            AuditPeriod4From = $this.AuditPeriod4From
            AuditPeriod4To = $this.AuditPeriod4To
            AuditPeriod5From = $this.AuditPeriod5From
            AuditPeriod5To = $this.AuditPeriod5To
            
            # Client Information
            ClientID = $this.ClientID
            Address = $this.Address
            City = $this.City
            Province = $this.Province
            PostalCode = $this.PostalCode
            Country = $this.Country
            ShipToAddress = $this.ShipToAddress
            
            # Personnel
            AuditorName = $this.AuditorName
            AuditorPhone = $this.AuditorPhone
            AuditorTL = $this.AuditorTL
            AuditorTLPhone = $this.AuditorTLPhone
            
            # Contacts
            Contact1Name = $this.Contact1Name
            Contact1Phone = $this.Contact1Phone
            Contact1Ext = $this.Contact1Ext
            Contact1Address = $this.Contact1Address
            Contact1Title = $this.Contact1Title
            Contact2Name = $this.Contact2Name
            Contact2Phone = $this.Contact2Phone
            Contact2Ext = $this.Contact2Ext
            Contact2Address = $this.Contact2Address
            Contact2Title = $this.Contact2Title
            
            # Accounting Systems
            AccountingSoftware1 = $this.AccountingSoftware1
            AccountingSoftware1Other = $this.AccountingSoftware1Other
            AccountingSoftware1Type = $this.AccountingSoftware1Type
            AccountingSoftware2 = $this.AccountingSoftware2
            AccountingSoftware2Other = $this.AccountingSoftware2Other
            AccountingSoftware2Type = $this.AccountingSoftware2Type
            
            # Additional Information
            RequestDate = $this.RequestDate
            FXInfo = $this.FXInfo
            Comments = $this.Comments
        }
        
        # Merge base and project properties
        foreach ($key in $projectHash.Keys) {
            $baseHash[$key] = $projectHash[$key]
        }
        
        return $baseHash
    }
    
    [string] GetDisplayName() {
        if (-not [string]::IsNullOrEmpty($this.FullProjectName)) {
            return $this.FullProjectName
        } elseif (-not [string]::IsNullOrEmpty($this.ID1)) {
            return "$($this.ID1) - $($this.ID2)"
        } else {
            return "Unnamed Project"
        }
    }
    
    [string] GetProjectCode() {
        if (-not [string]::IsNullOrEmpty($this.ID1) -and -not [string]::IsNullOrEmpty($this.ID2)) {
            return "$($this.ID1)-$($this.ID2)"
        } elseif (-not [string]::IsNullOrEmpty($this.ID1)) {
            return $this.ID1
        } else {
            return ""
        }
    }
    
    [bool] IsOverdue() {
        return $this.DateDue -lt [DateTime]::Now.Date -and $this.Status -ne "Completed" -and $this.Status -ne "Closed"
    }
    
    [int] GetDaysUntilDue() {
        return ($this.DateDue.Date - [DateTime]::Now.Date).Days
    }
    
    [bool] IsActive() {
        return $this.Status -eq "Active" -and -not $this.Deleted
    }
    
    [bool] IsValid() {
        $baseValid = ([BaseModel]$this).IsValid()
        $hasName = -not [string]::IsNullOrEmpty($this.FullProjectName)
        $hasID = -not [string]::IsNullOrEmpty($this.ID1)
        
        return $baseValid -and ($hasName -or $hasID)
    }
}