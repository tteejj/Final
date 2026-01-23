using namespace System.Collections.Generic

# Strictly typed palette class for high-performance JIT access
class PmcPalette {
    # Core Colors
    [int] $Foreground
    [int] $Background
    [int] $PanelBg
    [int] $PanelBorder
    
    # Validation / State
    [int] $Error
    [int] $Success
    [int] $Warning
    [int] $Info
    
    # UI Elements
    [int] $Accent
    [int] $SelectionBg
    [int] $SelectionFg
    [int] $Muted
    [int] $Header
    
    PmcPalette() {
        # Default Fallback (VS Code Dark style) - Guaranteed valid ints
        $this.Foreground    = 0xD4D4D4
        $this.Background    = 0x1E1E1E
        $this.PanelBg       = 0x252526
        $this.PanelBorder   = 0x3E3E42
        
        $this.Error         = 0xF44747
        $this.Success       = 0x4EC9B0
        $this.Warning       = 0xDCDCAA
        $this.Info          = 0x9CDCFE
        
        $this.Accent        = 0x007ACC
        $this.SelectionBg   = 0x264F78
        $this.SelectionFg   = 0xFFFFFF
        $this.Muted         = 0x808080
        $this.Header        = 0xCCCCCC
    }
}

class ThemeService {
    # Singleton Instance
    static [PmcPalette] $Current
    
    static [void] Initialize() {
        if ($null -eq [ThemeService]::Current) {
            Write-Host "Initializing Default Theme Service..." -ForegroundColor DarkGray
            [ThemeService]::Current = [PmcPalette]::new()
        }
    }
    
    static [void] LoadTheme([hashtable]$themeData) {
        if (-not $themeData) { return }
        
        # In strict mode, we map carefully. 
        # Future: Could use reflection, but explicit mapping is faster/safer for now.
        $p = [ThemeService]::Current
        
        # Helper scriptblock for parsing or local logic could be used, 
        # but direct assignment is most performant.
        
        if ($themeData.ContainsKey('Foreground')) { $p.Foreground = $themeData['Foreground'] }
        if ($themeData.ContainsKey('Background')) { $p.Background = $themeData['Background'] }
        if ($themeData.ContainsKey('PanelBg'))    { $p.PanelBg    = $themeData['PanelBg'] }
        if ($themeData.ContainsKey('PanelBorder')){ $p.PanelBorder= $themeData['PanelBorder'] }
        
        if ($themeData.ContainsKey('Error'))      { $p.Error      = $themeData['Error'] }
        if ($themeData.ContainsKey('Success'))    { $p.Success    = $themeData['Success'] }
        if ($themeData.ContainsKey('Warning'))    { $p.Warning    = $themeData['Warning'] }
        if ($themeData.ContainsKey('Info'))       { $p.Info       = $themeData['Info'] }
        
        if ($themeData.ContainsKey('Accent'))     { $p.Accent     = $themeData['Accent'] }
        if ($themeData.ContainsKey('SelectionBg')){ $p.SelectionBg= $themeData['SelectionBg'] }
        if ($themeData.ContainsKey('SelectionFg')){ $p.SelectionFg= $themeData['SelectionFg'] }
        if ($themeData.ContainsKey('Muted'))      { $p.Muted      = $themeData['Muted'] }
        if ($themeData.ContainsKey('Header'))     { $p.Header     = $themeData['Header'] }
        
        # Trigger any engine cache invalidation if needed
        # [HybridRenderEngine]::InvalidateAll() # (If such method existed/needed)
    }

    static [array] GetPresets() {
        return @(
            @{ Name = "VS Code Dark"; Data = @{ 
                Foreground = 0xD4D4D4; Background = 0x1E1E1E; PanelBg = 0x252526; PanelBorder = 0x3E3E42
                Accent = 0x007ACC; SelectionBg = 0x264F78; SelectionFg = 0xFFFFFF
                Muted = 0x808080; Header = 0xCCCCCC
                Success = 0x4EC9B0; Warning = 0xDCDCAA; Error = 0xF44747
            }}
            @{ Name = "Matrix"; Data = @{ 
                Foreground = 0x00FF00; Background = 0x000000; PanelBg = 0x001100; PanelBorder = 0x003300
                Accent = 0x00AA00; SelectionBg = 0x003300; SelectionFg = 0x00FF00
                Muted = 0x006600; Header = 0x00CC00
                Success = 0x00FF00; Warning = 0xAAFF00; Error = 0xFF0000
            }}
            @{ Name = "Solarized Dark"; Data = @{ 
                Foreground = 0x839496; Background = 0x002B36; PanelBg = 0x073642; PanelBorder = 0x586E75
                Accent = 0x268BD2; SelectionBg = 0x073642; SelectionFg = 0x93A1A1
                Muted = 0x586E75; Header = 0x93A1A1
                Success = 0x859900; Warning = 0xB58900; Error = 0xDC322F
            }}
            @{ Name = "Monokai"; Data = @{ 
                Foreground = 0xF8F8F2; Background = 0x272822; PanelBg = 0x272822; PanelBorder = 0x75715E
                Accent = 0xF92672; SelectionBg = 0x49483E; SelectionFg = 0xF8F8F2
                Muted = 0x75715E; Header = 0xE6DB74
                Success = 0xA6E22E; Warning = 0xE6DB74; Error = 0xF92672
            }}
            @{ Name = "High Contrast"; Data = @{ 
                Foreground = 0xFFFFFF; Background = 0x000000; PanelBg = 0x000000; PanelBorder = 0xFFFFFF
                Accent = 0xFFFF00; SelectionBg = 0xFFFFFF; SelectionFg = 0x000000
                Muted = 0x808080; Header = 0xFFFFFF
                Success = 0x00FF00; Warning = 0xFFFF00; Error = 0xFF0000
            }}
            @{ Name = "Oceanic"; Data = @{ 
                Foreground = 0xD8DEE9; Background = 0x1B2B34; PanelBg = 0x343D46; PanelBorder = 0x4F5B66
                Accent = 0x6699CC; SelectionBg = 0x4F5B66; SelectionFg = 0xD8DEE9
                Muted = 0x65737E; Header = 0xABB2BF
                Success = 0x99C794; Warning = 0xFAC863; Error = 0xEC5F67
            }}
            @{ Name = "Notepad"; Data = @{ 
                Foreground = 0x000000; Background = 0xFFFFFF; PanelBg = 0xFFFFFF; PanelBorder = 0xC0C0C0
                Accent = 0x0066CC; SelectionBg = 0x0066CC; SelectionFg = 0xFFFFFF
                Muted = 0x808080; Header = 0x000000
                Success = 0x008000; Warning = 0x808000; Error = 0xCC0000
            }}
            @{ Name = "Amber Terminal"; Data = @{ 
                Foreground = 0xFFB000; Background = 0x000000; PanelBg = 0x0A0A00; PanelBorder = 0x805800
                Accent = 0xFFCC00; SelectionBg = 0x804000; SelectionFg = 0xFFE000
                Muted = 0x805800; Header = 0xFFCC00
                Success = 0xFFCC00; Warning = 0xFF8800; Error = 0xFF4400
            }}
        )
    }
}
