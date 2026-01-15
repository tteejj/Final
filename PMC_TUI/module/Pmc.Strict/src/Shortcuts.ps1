# Workflow shortcuts

function Invoke-PmcShortcut {
    param([PmcCommandContext]$Context)
    # Use: "# 3" to view item at index 3 from last task list
    if ($Context.FreeText.Count -lt 1) { Write-PmcStyled -Style 'Warning' -Text "Usage: # <index>"; return }
    $tok = $Context.FreeText[0]
    if (-not ($tok -match '^\d+$')) { Write-PmcStyled -Style 'Error' -Text "Invalid index"; return }
    $n = [int]$tok
    $indexMap = Get-PmcLastTaskListMap
    if (-not $indexMap -or -not $indexMap.ContainsKey($n)) {
        Write-PmcStyled -Style 'Warning' -Text "No recent list or index out of range"
        return
    }
    # Delegate to task view
    $ctx = [PmcCommandContext]::new('task','view')
    $ctx.FreeText = @([string]$n)
    Show-PmcTask -Context $ctx
}

#Export-ModuleMember -Function Invoke-PmcShortcut