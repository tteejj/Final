# Simple Component base class for SpeedTUI screens

class Component {
    [string]$ComponentType = "Component"
    [int]$Width = 120
    [int]$Height = 30
    [bool]$Visible = $true
    
    Component() {
        # Simple constructor
    }
    
    [string[]] Render() {
        return @("Component not implemented")
    }
    
    [void] Update() {
        # Override in derived classes if needed
    }
    
    [bool] ShouldRefresh() {
        return $false
    }
}