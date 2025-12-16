# SpeedTUI Theme Manager - Simple, efficient theming system

using namespace System.Collections.Generic

class ThemeColor {
    [string]$Name
    [string]$Foreground
    [string]$Background
    
    ThemeColor([string]$name, [string]$fg, [string]$bg) {
        $this.Name = $name
        $this.Foreground = $fg
        $this.Background = $bg
    }
}

class Theme {
    [string]$Name
    [Dictionary[string, ThemeColor]]$Colors
    [Dictionary[string, string]]$Styles
    
    Theme([string]$name) {
        $this.Name = $name
        $this.Colors = [Dictionary[string, ThemeColor]]::new()
        $this.Styles = [Dictionary[string, string]]::new()
    }
    
    [Theme] DefineColor([string]$name, [string]$foreground, [string]$background) {
        $color = [ThemeColor]::new($name, $foreground, $background)
        $this.Colors[$name] = $color
        return $this
    }
    
    [Theme] DefineColor([string]$name, [string]$foreground) {
        return $this.DefineColor($name, $foreground, "")
    }
    
    [Theme] DefineStyle([string]$name, [string]$style) {
        $this.Styles[$name] = $style
        return $this
    }
    
    [ThemeColor] GetColor([string]$name) {
        if ($this.Colors.ContainsKey($name)) {
            return $this.Colors[$name]
        }
        # Return default if not found
        return [ThemeColor]::new($name, [Colors]::Default, "")
    }
    
    [string] GetStyle([string]$name) {
        if ($this.Styles.ContainsKey($name)) {
            return $this.Styles[$name]
        }
        return ""
    }
}

class ThemeManager {
    hidden [Dictionary[string, Theme]]$_themes
    hidden [Theme]$_currentTheme
    hidden [string]$_currentThemeName
    hidden [object]$_logger
    hidden [List[scriptblock]]$_changeHandlers
    
    ThemeManager() {
        $this._themes = [Dictionary[string, Theme]]::new()
        $this._changeHandlers = [List[scriptblock]]::new()
        $this._logger = Get-Logger
        
        # Register built-in themes
        $this.RegisterBuiltInThemes()
        
        # Set default theme
        $this.SetTheme("default")
        
        $this._logger.Info("ThemeManager", "Constructor", "ThemeManager initialized")
    }
    
    hidden [void] RegisterBuiltInThemes() {
        # Default theme - clean and simple
        $default = [Theme]::new("default").
            DefineColor("primary", [Colors]::Blue).
            DefineColor("secondary", [Colors]::Cyan).
            DefineColor("success", [Colors]::Green).
            DefineColor("warning", [Colors]::Yellow).
            DefineColor("error", [Colors]::Red).
            DefineColor("info", [Colors]::Cyan).
            DefineColor("text", [Colors]::White).
            DefineColor("textDim", [Colors]::BrightBlack).
            DefineColor("background", "", [Colors]::BgBlack).
            DefineColor("selection", [Colors]::Black, [Colors]::BgWhite).
            DefineColor("focus", [Colors]::Yellow).
            DefineColor("border", [Colors]::BrightBlack).
            DefineColor("header", [Colors]::Bold + [Colors]::White).
            DefineStyle("bold", [Colors]::Bold).
            DefineStyle("dim", [Colors]::Dim).
            DefineStyle("italic", [Colors]::Italic).
            DefineStyle("underline", [Colors]::Underline)
        
        $this.RegisterTheme($default)
        
        # Dark theme
        $dark = [Theme]::new("dark").
            DefineColor("primary", [Colors]::BrightBlue).
            DefineColor("secondary", [Colors]::BrightCyan).
            DefineColor("success", [Colors]::BrightGreen).
            DefineColor("warning", [Colors]::BrightYellow).
            DefineColor("error", [Colors]::BrightRed).
            DefineColor("info", [Colors]::BrightCyan).
            DefineColor("text", [Colors]::BrightWhite).
            DefineColor("textDim", [Colors]::White).
            DefineColor("background", "", [Colors]::BgBlack).
            DefineColor("selection", [Colors]::Black, [Colors]::BgBrightWhite).
            DefineColor("focus", [Colors]::BrightYellow).
            DefineColor("border", [Colors]::White).
            DefineColor("header", [Colors]::Bold + [Colors]::BrightWhite)
        
        $this.RegisterTheme($dark)
        
        # Light theme
        $light = [Theme]::new("light").
            DefineColor("primary", [Colors]::Blue, [Colors]::BgWhite).
            DefineColor("secondary", [Colors]::Cyan, [Colors]::BgWhite).
            DefineColor("success", [Colors]::Green, [Colors]::BgWhite).
            DefineColor("warning", [Colors]::Yellow + [Colors]::Bold, [Colors]::BgWhite).
            DefineColor("error", [Colors]::Red, [Colors]::BgWhite).
            DefineColor("info", [Colors]::Cyan, [Colors]::BgWhite).
            DefineColor("text", [Colors]::Black, [Colors]::BgWhite).
            DefineColor("textDim", [Colors]::BrightBlack, [Colors]::BgWhite).
            DefineColor("background", [Colors]::Black, [Colors]::BgWhite).
            DefineColor("selection", [Colors]::White, [Colors]::BgBlue).
            DefineColor("focus", [Colors]::Blue, [Colors]::BgWhite).
            DefineColor("border", [Colors]::Black, [Colors]::BgWhite).
            DefineColor("header", [Colors]::Bold + [Colors]::Black, [Colors]::BgWhite)
        
        $this.RegisterTheme($light)
        
        # Solarized theme
        $solarized = [Theme]::new("solarized").
            DefineColor("primary", [Colors]::RGB(38, 139, 210)).      # Blue
            DefineColor("secondary", [Colors]::RGB(42, 161, 152)).    # Cyan
            DefineColor("success", [Colors]::RGB(133, 153, 0)).       # Green
            DefineColor("warning", [Colors]::RGB(181, 137, 0)).       # Yellow
            DefineColor("error", [Colors]::RGB(220, 50, 47)).         # Red
            DefineColor("info", [Colors]::RGB(42, 161, 152)).         # Cyan
            DefineColor("text", [Colors]::RGB(147, 161, 161)).        # Base1
            DefineColor("textDim", [Colors]::RGB(88, 110, 117)).      # Base01
            DefineColor("background", "", [Colors]::BgRGB(0, 43, 54)). # Base03
            DefineColor("selection", [Colors]::RGB(253, 246, 227), [Colors]::BgRGB(7, 54, 66)). # Base3 on Base02
            DefineColor("focus", [Colors]::RGB(181, 137, 0)).         # Yellow
            DefineColor("border", [Colors]::RGB(88, 110, 117)).       # Base01
            DefineColor("header", [Colors]::Bold + [Colors]::RGB(147, 161, 161)) # Bold Base1
        
        $this.RegisterTheme($solarized)
        
        # Synthwave theme (inspired by Praxis)
        $synthwave = [Theme]::new("synthwave").
            DefineColor("primary", [Colors]::RGB(255, 0, 255)).       # Magenta
            DefineColor("secondary", [Colors]::RGB(0, 255, 255)).     # Cyan
            DefineColor("success", [Colors]::RGB(0, 255, 0)).         # Green
            DefineColor("warning", [Colors]::RGB(255, 255, 0)).       # Yellow
            DefineColor("error", [Colors]::RGB(255, 0, 0)).           # Red
            DefineColor("info", [Colors]::RGB(0, 255, 255)).          # Cyan
            DefineColor("text", [Colors]::RGB(255, 255, 255)).        # White
            DefineColor("textDim", [Colors]::RGB(128, 128, 128)).     # Gray
            DefineColor("background", "", [Colors]::BgRGB(16, 0, 32)). # Deep purple
            DefineColor("selection", [Colors]::RGB(0, 0, 0), [Colors]::BgRGB(255, 0, 255)). # Black on Magenta
            DefineColor("focus", [Colors]::RGB(255, 0, 255)).         # Magenta
            DefineColor("border", [Colors]::RGB(0, 255, 255)).        # Cyan
            DefineColor("header", [Colors]::Bold + [Colors]::RGB(255, 0, 255)) # Bold Magenta
        
        $this.RegisterTheme($synthwave)
    }
    
    [void] RegisterTheme([Theme]$theme) {
        [Guard]::NotNull($theme, "theme")
        
        $this._themes[$theme.Name] = $theme
        
        $this._logger.Debug("ThemeManager", "RegisterTheme", "Theme registered", @{
            ThemeName = $theme.Name
            ColorCount = $theme.Colors.Count
            StyleCount = $theme.Styles.Count
        })
    }
    
    [void] SetTheme([string]$themeName) {
        [Guard]::NotNullOrEmpty($themeName, "themeName")
        
        if (-not $this._themes.ContainsKey($themeName)) {
            $this._logger.Warn("ThemeManager", "SetTheme", "Theme not found, using default", @{
                RequestedTheme = $themeName
            })
            $themeName = "default"
        }
        
        $this._currentTheme = $this._themes[$themeName]
        $this._currentThemeName = $themeName
        
        $this._logger.Info("ThemeManager", "SetTheme", "Theme changed", @{
            ThemeName = $themeName
        })
        
        # Notify change handlers
        foreach ($handler in $this._changeHandlers) {
            try {
                & $handler $this._currentTheme
            } catch {
                $this._logger.Error("ThemeManager", "SetTheme", "Change handler failed", @{
                    Error = $_.Exception.Message
                })
            }
        }
    }
    
    [Theme] GetCurrentTheme() {
        return $this._currentTheme
    }
    
    [string] GetCurrentThemeName() {
        return $this._currentThemeName
    }
    
    [string[]] GetAvailableThemes() {
        return $this._themes.Keys
    }
    
    [void] OnThemeChanged([scriptblock]$handler) {
        [Guard]::NotNull($handler, "handler")
        $this._changeHandlers.Add($handler)
    }
    
    # Convenience methods for current theme
    [ThemeColor] GetColor([string]$name) {
        return $this._currentTheme.GetColor($name)
    }
    
    [string] GetStyle([string]$name) {
        return $this._currentTheme.GetStyle($name)
    }
    
    [string] ApplyColor([string]$colorName, [string]$text) {
        $color = $this.GetColor($colorName)
        return $color.Foreground + $color.Background + $text + [Colors]::Reset
    }
}

# Global theme manager instance
class ThemeService {
    static [ThemeManager]$Instance
    
    static [ThemeManager] GetInstance() {
        if ($null -eq [ThemeService]::Instance) {
            [ThemeService]::Instance = [ThemeManager]::new()
        }
        return [ThemeService]::Instance
    }
}

# Helper function for easy access
function Get-Theme {
    return [ThemeService]::GetInstance()
}