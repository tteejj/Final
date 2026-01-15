# How to Enable Auto-Accept for Commands

## Option 1: Environment Variable (Recommended)

Set this environment variable before starting your session:

```bash
export GEMINI_AUTO_ACCEPT_COMMANDS=true
```

To make it permanent, add to your `~/.bashrc` or `~/.zshrc`:

```bash
echo 'export GEMINI_AUTO_ACCEPT_COMMANDS=true' >> ~/.bashrc
source ~/.bashrc
```

## Option 2: Configuration File

Create or edit `~/.gemini/config.json`:

```json
{
  "autoAcceptCommands": true,
  "autoAcceptSafeCommands": true
}
```

## Option 3: Per-Session Setting

In the Gemini interface, look for settings/preferences and enable:
- "Auto-accept safe commands"
- "Auto-accept all commands" (use with caution)

## What Gets Auto-Accepted?

With `SafeToAutoRun=true`, commands like:
- ✓ `ls`, `cat`, `grep` (read-only operations)
- ✓ `chmod +x` on new scripts
- ✓ Running verification scripts

Commands that require approval:
- ✗ `rm`, `mv` (destructive operations)
- ✗ System modifications
- ✗ Network operations

## Testing Auto-Accept

Run this to verify:
```bash
# This should auto-run without asking
ls -la /tmp

# This will still ask for approval
rm /tmp/test-file
```

---

## Automated Testing Scripts Created

### Quick Verification (Fast)
```bash
pwsh /home/teej/ztest/module/Pmc.Strict/consoleui/verify-tui.ps1
```

Checks:
- ✓ TimeListScreen has callback methods
- ✓ TabPanel widget exists  
- ✓ ProjectInfoScreenV4 exists

### Full Test Suite (Slower, loads all dependencies)
```bash
pwsh /home/teej/ztest/module/Pmc.Strict/consoleui/test-tui.ps1
```

Note: Currently has dependency loading issues, use verify-tui.ps1 instead.

---

## Manual Testing Checklist

After running automated tests, manually verify:

1. **TimeListScreen Fix**
   ```bash
   pwsh /home/teej/ztest/module/Pmc.Strict/consoleui/Start-PmcTUI.ps1
   ```
   - Press `F10` → `Time` → `Time Tracking`
   - Press `a` to add entry
   - Should NOT see "Method invocation failed" error

2. **ProjectInfoScreenV4 Tabs**
   - Press `F10` → `Projects` → `Project List`
   - Select project, press Enter
   - Check if tabs visible at top

3. **General Rendering**
   - Navigate through screens
   - Look for visual artifacts or missing text
