Set-StrictMode -Version Latest

function ConvertTo-PmcProjectObject {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Project,
        [Parameter(Mandatory=$true)]
        [ref]$DataArray,
        [Parameter(Mandatory=$true)]
        [int]$Index
    )

    if ($Project -is [string]) {
        $newProject = [pscustomobject]@{
            name = $Project
        }
        $DataArray.Value[$Index] = $newProject
        return $newProject
    } else {
        return $Project
    }
}