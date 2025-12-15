# ClosureHelper.ps1 - Standardized closure creation utilities
#
# PowerShell closures (via .GetNewClosure()) capture variables but NOT functions
# from the outer scope. This helper provides patterns and utilities for safe
# closure creation in the TUI application.
#
# RECOMMENDED PATTERN:
#   $self = $this                                     # Capture object reference
#   $getSafe = ${function:Global:Get-SafeProperty}    # Capture function reference
#   $callback = {
#       $item = $self.GetItem()
#       & $getSafe $item 'name'
#   }.GetNewClosure()

Set-StrictMode -Version Latest

<#
.SYNOPSIS
Create a closure capturing specified variables safely

.DESCRIPTION
This function helps create closures with explicit variable capture,
avoiding common pitfalls where variables are not captured as expected.

.PARAMETER ScriptBlock
The scriptblock to wrap as a closure

.PARAMETER CaptureVariables
Hashtable of variable name => value to capture in the closure

.OUTPUTS
ScriptBlock with captured variables

.EXAMPLE
$closure = New-SafeClosure -ScriptBlock { $self.DoSomething($value) } -CaptureVariables @{
    self = $this
    value = $someValue
}
#>
function New-SafeClosure {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory=$true)]
        [hashtable]$CaptureVariables
    )

    # Create new scope with captured variables
    $boundBlock = {
        param($captureVars, $innerBlock)
        
        # Inject captured variables into scope
        foreach ($key in $captureVars.Keys) {
            Set-Variable -Name $key -Value $captureVars[$key]
        }
        
        # Return closure with variables in scope
        return $innerBlock.GetNewClosure()
    }
    
    return & $boundBlock $CaptureVariables $ScriptBlock
}

<#
.SYNOPSIS
Build a callback that captures $this safely for event handlers

.DESCRIPTION
Common pattern for UI callbacks where you need to capture the current
object instance and call a method on it.

.PARAMETER Target
The object to capture (usually $this)

.PARAMETER MethodName
Name of method to call on the target

.OUTPUTS
ScriptBlock closure that calls target.MethodName(args)

.EXAMPLE
$onClick = New-MethodCallback -Target $this -MethodName 'OnItemClicked'
$widget.OnClick = $onClick
#>
function New-MethodCallback {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Target,

        [Parameter(Mandatory=$true)]
        [string]$MethodName
    )

    $self = $Target
    $method = $MethodName
    
    return {
        param($arg)
        $self.$method($arg)
    }.GetNewClosure()
}

<#
.SYNOPSIS
Build a callback for data binding formatters

.DESCRIPTION
Creates a closure for column formatters that safely captures
the format function and any helper functions needed.

.PARAMETER FormatBlock
Scriptblock that formats the data

.PARAMETER Helpers
Hashtable of helper function names to capture

.OUTPUTS
ScriptBlock closure for use as column formatter

.EXAMPLE
$formatter = New-FormatterCallback -FormatBlock {
    param($row)
    & $getSafe $row 'name'
} -Helpers @{
    getSafe = ${function:Global:Get-SafeProperty}
}
#>
function New-FormatterCallback {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$FormatBlock,

        [Parameter(Mandatory=$false)]
        [hashtable]$Helpers = @{}
    )

    # Capture helpers in local scope
    $capturedHelpers = $Helpers.Clone()
    $innerBlock = $FormatBlock
    
    return {
        param($row)
        # Inject helpers
        foreach ($name in $capturedHelpers.Keys) {
            Set-Variable -Name $name -Value $capturedHelpers[$name]
        }
        # Execute format block
        & $innerBlock $row
    }.GetNewClosure()
}

<#
.SYNOPSIS
Capture global helper functions for use in closures

.DESCRIPTION
Many closures need access to global helper functions like Get-SafeProperty.
This function returns a hashtable of commonly needed function references.

.OUTPUTS
Hashtable of function name => scriptblock

.EXAMPLE
$helpers = Get-ClosureHelpers
$callback = {
    param($item)
    & $helpers.GetSafe $item 'text'
}.GetNewClosure()
#>
function Get-ClosureHelpers {
    return @{
        GetSafe = ${function:Global:Get-SafeProperty}
        TestSafe = ${function:Global:Test-SafeProperty}
        FormatDate = ${function:Global:Format-SafeDate}
    }
}

# Only export when running as a module
if ($MyInvocation.InvocationName -ne '.') {
    Export-ModuleMember -Function New-SafeClosure, New-MethodCallback, New-FormatterCallback, Get-ClosureHelpers
}
