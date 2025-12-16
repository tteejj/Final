# SpeedTUI Component Builder Base Class
# Provides fluent API pattern for component configuration

<#
.SYNOPSIS
Base class for component builders that provide fluent API pattern

.DESCRIPTION
ComponentBuilder provides a base class for creating fluent APIs for component configuration.
Each component can have a corresponding builder class that inherits from this base.

.EXAMPLE
# Button builder example
$button = [ButtonBuilder]::new()
    .Text("Click Me")
    .Position(10, 5)
    .Size(20, 3)
    .OnClick({ Write-Host "Clicked!" })
    .Build()
#>
class ComponentBuilder {
    # The component being built
    hidden [Component]$_component
    
    <#
    .SYNOPSIS
    Initialize component builder with a component instance
    
    .PARAMETER component
    The component instance to build/configure
    #>
    ComponentBuilder([Component]$component) {
        $this._component = $component
    }
    
    <#
    .SYNOPSIS
    Set component position using fluent API
    
    .PARAMETER x
    X coordinate
    
    .PARAMETER y
    Y coordinate
    
    .OUTPUTS
    ComponentBuilder for method chaining
    #>
    [ComponentBuilder] Position([int]$x, [int]$y) {
        $this._component.SetPosition($x, $y)
        return $this
    }
    
    <#
    .SYNOPSIS
    Set component size using fluent API
    
    .PARAMETER width
    Component width
    
    .PARAMETER height
    Component height
    
    .OUTPUTS
    ComponentBuilder for method chaining
    #>
    [ComponentBuilder] Size([int]$width, [int]$height) {
        $this._component.SetSize($width, $height)
        return $this
    }
    
    <#
    .SYNOPSIS
    Set component theme using fluent API
    
    .PARAMETER themeName
    Name of theme to apply
    
    .OUTPUTS
    ComponentBuilder for method chaining
    #>
    [ComponentBuilder] Theme([string]$themeName) {
        $this._component.SetTheme($themeName)
        return $this
    }
    
    <#
    .SYNOPSIS
    Set component color role using fluent API
    
    .PARAMETER colorRole
    Color role name
    
    .OUTPUTS
    ComponentBuilder for method chaining
    #>
    [ComponentBuilder] Color([string]$colorRole) {
        $this._component.SetColor($colorRole)
        return $this
    }
    
    <#
    .SYNOPSIS
    Set component visibility using fluent API
    
    .PARAMETER visible
    Whether component should be visible
    
    .OUTPUTS
    ComponentBuilder for method chaining
    #>
    [ComponentBuilder] Visible([bool]$visible) {
        $this._component.Visible = $visible
        return $this
    }
    
    <#
    .SYNOPSIS
    Set component focus capability using fluent API
    
    .PARAMETER canFocus
    Whether component can receive focus
    
    .OUTPUTS
    ComponentBuilder for method chaining
    #>
    [ComponentBuilder] CanFocus([bool]$canFocus) {
        $this._component.CanFocus = $canFocus
        return $this
    }
    
    <#
    .SYNOPSIS
    Set component tab index using fluent API
    
    .PARAMETER tabIndex
    Tab order index
    
    .OUTPUTS
    ComponentBuilder for method chaining
    #>
    [ComponentBuilder] TabIndex([int]$tabIndex) {
        $this._component.TabIndex = $tabIndex
        return $this
    }
    
    <#
    .SYNOPSIS
    Set focus event handler using fluent API
    
    .PARAMETER handler
    Script block to execute on focus
    
    .OUTPUTS
    ComponentBuilder for method chaining
    #>
    [ComponentBuilder] OnFocus([scriptblock]$handler) {
        $this._component.OnFocus = $handler
        return $this
    }
    
    <#
    .SYNOPSIS
    Set blur event handler using fluent API
    
    .PARAMETER handler
    Script block to execute on blur
    
    .OUTPUTS
    ComponentBuilder for method chaining
    #>
    [ComponentBuilder] OnBlur([scriptblock]$handler) {
        $this._component.OnBlur = $handler
        return $this
    }
    
    <#
    .SYNOPSIS
    Set key press event handler using fluent API
    
    .PARAMETER handler
    Script block to execute on key press
    
    .OUTPUTS
    ComponentBuilder for method chaining
    #>
    [ComponentBuilder] OnKeyPress([scriptblock]$handler) {
        $this._component.OnKeyPress = $handler
        return $this
    }
    
    <#
    .SYNOPSIS
    Build and return the configured component
    
    .OUTPUTS
    The configured component instance
    #>
    [Component] Build() {
        return $this._component
    }
    
    <#
    .SYNOPSIS
    Get the component being built (for derived classes)
    
    .OUTPUTS
    The component instance
    #>
    hidden [Component] GetComponent() {
        return $this._component
    }
}