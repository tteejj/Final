    <#
    .SYNOPSIS
    Build UI properties from current palette for Engine
    #>
    hidden [hashtable] _BuildThemeProperties() {
        $primaryHex = $this._GetPaletteHex('Primary', '#ff8833')
        $textHex = $this._GetPaletteHex('Text', '#ffe8c8')
        $mutedHex = $this._GetPaletteHex('Muted', '#888888')
        $warningHex = $this._GetPaletteHex('Warning', '#ffaa00')
        $errorHex = $this._GetPaletteHex('Error', '#ff3333')
        $successHex = $this._GetPaletteHex('Success', '#33ff33')
        $borderHex = $this._GetPaletteHex('Border', '#b25f24')

        # Use properties from config if available (Dynamic Theming)
        # FIX: Use hashtable indexing instead of dot notation for strict mode compatibility
        $themeProps = $null
        if ($this.PmcTheme) {
            if ($this.PmcTheme -is [hashtable]) {
                $themeProps = $this.PmcTheme['Properties']
            } elseif ($this.PmcTheme -is [System.Management.Automation.PSCustomObject]) {
                $themeProps = $this.PmcTheme.Properties
            }
        }

        if ($themeProps) {
            $props = $themeProps
            if ($props -is [System.Management.Automation.PSCustomObject]) {
                # Convert PSCustomObject to Hashtable
                $ht = @{}
                $props.PSObject.Properties | ForEach-Object {
                    $val = $_.Value
                    if ($val -is [System.Management.Automation.PSCustomObject]) {
                        # Deep convert for nested objects (Type/Color/Gradient)
                        $nestedHt = @{}
                        $val.PSObject.Properties | ForEach-Object { $nestedHt[$_.Name] = $_.Value }
                        $ht[$_.Name] = $nestedHt
                    } else {
                        $ht[$_.Name] = $val
                    }
                }
                return $ht
            } elseif ($props -is [hashtable]) {
                # Already a hashtable, but check for nested PSCustomObjects
                $ht = @{}
                foreach ($key in $props.Keys) {
                    $val = $props[$key]
                    if ($val -is [System.Management.Automation.PSCustomObject]) {
                        $nestedHt = @{}
                        $val.PSObject.Properties | ForEach-Object { $nestedHt[$_.Name] = $_.Value }
                        $ht[$key] = $nestedHt
                    } else {
                        $ht[$key] = $val
                    }
                }
                return $ht
            }
            return $props
        }

        return @{
            'Background.Field'        = @{ Type = 'Solid'; Color = '#000000' }
            'Background.FieldFocused' = @{ Type = 'Solid'; Color = $primaryHex }
            'Background.Row'          = @{ Type = 'Solid'; Color = '#000000' }
            'Background.RowSelected'  = @{ Type = 'Solid'; Color = $primaryHex }
            'Background.Warning'      = @{ Type = 'Solid'; Color = $warningHex }
            'Background.MenuBar'      = @{ Type = 'Solid'; Color = $borderHex }
            'Background.TabActive'    = @{ Type = 'Solid'; Color = $primaryHex }
            'Background.TabInactive'  = @{ Type = 'Solid'; Color = '#333333' }
            'Background.Primary'      = @{ Type = 'Solid'; Color = '#000000' }
            'Background.Widget'       = @{ Type = 'Solid'; Color = '#1a1a1a' }
            'Background.Panel'        = @{ Type = 'Solid'; Color = '#1a1a1a' }
            'Background.Header'       = @{ Type = 'Solid'; Color = '#1a1a1a' }
            'Background.Footer'       = @{ Type = 'Solid'; Color = '#1a1a1a' }
            'Foreground.Field'        = @{ Type = 'Solid'; Color = $textHex }
            'Foreground.FieldFocused' = @{ Type = 'Solid'; Color = '#FFFFFF' }
            'Foreground.Row'          = @{ Type = 'Solid'; Color = $textHex }
            'Foreground.RowSelected'  = @{ Type = 'Solid'; Color = '#FFFFFF' }
            'Foreground.Title'        = @{ Type = 'Solid'; Color = $primaryHex }
            'Foreground.Muted'        = @{ Type = 'Solid'; Color = $mutedHex }
            'Foreground.Warning'      = @{ Type = 'Solid'; Color = $warningHex }
            'Foreground.Error'        = @{ Type = 'Solid'; Color = $errorHex }
            'Foreground.Success'      = @{ Type = 'Solid'; Color = $successHex }
            'Foreground.TabActive'    = @{ Type = 'Solid'; Color = $primaryHex }
            'Foreground.TabInactive'  = @{ Type = 'Solid'; Color = $mutedHex }
            'Foreground.Primary'      = @{ Type = 'Solid'; Color = $primaryHex }
            'Border.Widget'           = @{ Type = 'Solid'; Color = $borderHex }
        }
    }
