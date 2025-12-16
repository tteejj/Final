# Helper function to safely get property from hashtable or PSCustomObject
function Get-SafeProperty {
    param(
        [Parameter(Mandatory)]
        $Object,
        
        [Parameter(Mandatory)]
        [string]$PropertyName,
        
        [Parameter()]
        $DefaultValue = $null
    )
    
    if ($null -eq $Object) {
        return $DefaultValue
    }
    
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($PropertyName)) {
            return $Object[$PropertyName]
        }
    }
    elseif ($Object.PSObject.Properties[$PropertyName]) {
        return $Object.PSObject.Properties[$PropertyName].Value
    }
    
    return $DefaultValue
}
