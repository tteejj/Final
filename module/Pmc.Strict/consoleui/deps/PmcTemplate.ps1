# Local PmcTemplate class for template-based rendering

Set-StrictMode -Version Latest

class PmcTemplate {
    [string]$Name
    [string]$Type        # 'grid', 'list', 'card', 'summary'
    [string]$Header      # Header template
    [string]$Row         # Row/item template
    [string]$Footer      # Footer template
    [hashtable]$Settings # Width, alignment, etc.

    PmcTemplate([string]$name, [hashtable]$config) {
        $this.Name = $name
        $this.Type = $(if ($config.ContainsKey('type')) { $config.type } else { 'list' })
        $this.Header = $(if ($config.ContainsKey('header')) { $config.header } else { '' })
        $this.Row = $(if ($config.ContainsKey('row')) { $config.row } else { '' })
        $this.Footer = $(if ($config.ContainsKey('footer')) { $config.footer } else { '' })
        $this.Settings = $(if ($config.ContainsKey('settings')) { $config.settings } else { @{} })
    }
}