# TRON ARES Theme - Visual Mockup

## Theme Overview
A cyber-futuristic TRON-inspired theme with ARES (amber/orange) as the primary accent color, cyan highlights, and deep space black backgrounds.

## Color Palette

### Primary Colors
| Element | Color | Usage |
|---------|-------|-------|
| **Deep Space Black** | `#0a0a12` | Main background, field backgrounds |
| **Darker Void** | `#080810` | Row backgrounds (alternating) |
| **Panel Base** | `#0e0e18` | Panel backgrounds |
| **Widget Base** | `#0d0d1a` | Widget containers, gradients |

### Accent Colors
| Element | Color | Usage |
|---------|-------|-------|
| **ARES Orange** | `#ff6600` | Primary accent, borders, titles |
| **Amber Glow** | `#ffa500` | Field text, row text |
| **Golden** | `#ffcc00` | Focused fields, highlights |
| **TRON Cyan** | `#00e5ff` | Selection, accents, secondary |
| **Bright White** | `#ffffff` | Selected text, focus |
| **Neon Red** | `#ff3333` | Errors |
| **Success Green** | `#00ff66` | Success messages |

### Gradients
| Property | Start → End | Visual Effect |
|----------|-------------|---------------|
| `Foreground.Title` | `#ff6600 → #ffaa00` | Glowing title from orange to amber |
| `Foreground.Primary` | `#ff6600 → #00e5ff` | Orange to cyan gradient |
| `Foreground.RowSelected` | `#00e5ff → #ffffff` | Cyan to white on selection |
| `Foreground.Accent` | `#00e5ff → #00ffff` | Bright cyan highlight |
| `Background.MenuBar` | `#0d0d1a → #12121f` | Subtle vertical gradient |
| `Background.Header` | `#0d0d1a → #151525` | Header gradient |
| `Background.Footer` | `#0d0d1a → #151525` | Footer gradient |
| `Background.RowSelected` | `#2a1a0a → #3d200d` | Dark amber glow on selection |
| `Border.Widget` | `#ff6600 → #cc5500` | Border gradient |

## Visual Mockup - Screen Layout

```
┌────────────────────────────────────────────────────────────────────────────┐
│  ╔═══╗ ╔═══════╗ ╔═══╗ ╔═════╗ ╔═══════════╗    [3 projects active]     │
│  ║ F ║ ║  E    ║ ║ V ║ ║  T  ║ ║    H      ║                             │
│  ║ i ║ ║  d    ║ ║ i ║ ║  a  ║ ║    e      ║  Title gradient:           │
│  ║ l ║ ║  i    ║ ║ e ║ ║  s  ║ ║    l      ║  orange→amber              │
│  ║ e ║ ║  t    ║ ║ w ║ ║  k  ║ ║    p      ║                             │
│  ╚═══╝ ╚═══════╝ ╚═══╝ ╚═════╝ ╚═══════════╝                             │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────┐     │
│  │  Pri  Task Name                    Status     Due Date            │     │
│  ├──────────────────────────────────────────────────────────────────┤     │
│  │  ●    Implement authentication       In Progress 2026-01-15      │     │
│  │  ○    Design database schema       Pending     2026-01-20      │     │
│  │  ○    Write unit tests             Pending     2026-01-22      │     │
│  │  ●    Setup CI/CD pipeline         Completed   2026-01-05      │     │
│  └──────────────────────────────────────────────────────────────────┘     │
│                                                                            │
│  Row text: Amber orange #ffa500                                            │
│  Selected row: Dark amber gradient background + Cyan→White text           │
│  Borders: Orange gradient #ff6600→#cc5500                                  │
│                                                                            │
├────────────────────────────────────────────────────────────────────────────┤
│  [↑↓] Navigate  [Enter] Open  [a]dd  [e]dit  [d]elete  [?] Help         │
│                                                                            │
│  Key bindings in amber/orange #ff8c00                                     │
│  Descriptions in muted #885522                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

## Key Design Features

### 1. Menu Bar - Different Text Color from Background
- **Background**: Subtle dark gradient `#0d0d1a → #12121f`
- **Menu Titles**: Amber orange `#ff8c00`
- **Hover/Active**: Dark amber glow background `#2a1a0a` with bright text
- **Border**: Orange gradient

### 2. List Screen - Distinct from Menu Bar
- **Row Background**: Slightly darker `#080810` (alternating with main `#0a0a12`)
- **Row Text**: Amber `#ffa500`
- **Selected Row**: Dark amber gradient background with cyan-to-white text
- **Borders**: Orange gradient

### 3. Maximum Color Variation
Unlike previous themes which used 2-3 main colors, this theme uses:

**Backgrounds**: 6 distinct shades
- Main: `#0a0a12`
- Rows: `#080810`
- Panels: `#0e0e18`
- Widgets: `#0d0d1a`
- Selected: `#2a1a0a → #3d200d` (gradient)
- Accent: `#1a0d08`

**Foregrounds**: 9 distinct colors
- Primary: `#ff6600`
- Secondary: `#00ccdd`
- Field: `#ffa500`
- Title: `#ff6600 → #ffaa00` (gradient)
- Muted: `#885522`
- Error: `#ff3333`
- Success: `#00ff66`
- Warning: `#ffcc00`
- Selection: `#00e5ff → #ffffff` (gradient)

### 4. Gradient Usage
9 gradient properties provide visual depth:
- Titles, primary text, accents
- Selection highlights
- Borders
- Menu bar, header, footer backgrounds

## Theme File Location
`/home/teej/ztest/themes/tronares.json`

## How to Test
```powershell
# Edit config.json to set theme
{
  "Display": {
    "Theme": {
      "Active": "tronares"
    }
  }
}

# Or use ThemeEditorScreen to select the theme
```

## TRON ARES Aesthetic Notes
- **Inspiration**: TRON Legacy's CLU program + Greek god ARES (war/fire theme)
- **Feeling**: Digital, aggressive, high-tech, glowing
- **Contrast**: High contrast for readability in terminal
- **Palette**: Orange dominant with cyan providing complementary contrast
