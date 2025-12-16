# StringBuilder pooling system - stolen directly from Praxis

class PraxisStringBuilderPool {
    static [System.Collections.Generic.Queue[System.Text.StringBuilder]]$_pool = [System.Collections.Generic.Queue[System.Text.StringBuilder]]::new()
    static [int]$_maxPoolSize = 20
    static [int]$_defaultCapacity = 1024

    static [System.Text.StringBuilder] Get([int]$initialCapacity = 1024) {
        if ([PraxisStringBuilderPool]::_pool.Count -gt 0) {
            $sb = [PraxisStringBuilderPool]::_pool.Dequeue()
            $sb.Clear()
            if ($sb.Capacity -lt $initialCapacity) {
                $sb.Capacity = $initialCapacity
            }
            return $sb
        }
        return [System.Text.StringBuilder]::new($initialCapacity)
    }

    static [void] Recycle([System.Text.StringBuilder]$sb) {
        if ($sb -and [PraxisStringBuilderPool]::_pool.Count -lt [PraxisStringBuilderPool]::_maxPoolSize) {
            $sb.Clear()
            [PraxisStringBuilderPool]::_pool.Enqueue($sb)
        }
    }

    static [string] Build([scriptblock]$buildAction) {
        $sb = [PraxisStringBuilderPool]::Get(1024)
        try {
            & $buildAction $sb
            return $sb.ToString()
        } finally {
            [PraxisStringBuilderPool]::Recycle($sb)
        }
    }
}

# Convenience functions
function Get-PooledStringBuilder([int]$capacity = 1024) {
    return [PraxisStringBuilderPool]::Get($capacity)
}

function Return-PooledStringBuilder([System.Text.StringBuilder]$sb) {
    [PraxisStringBuilderPool]::Recycle($sb)
}

#Export-ModuleMember -Function Get-PooledStringBuilder, Return-PooledStringBuilder