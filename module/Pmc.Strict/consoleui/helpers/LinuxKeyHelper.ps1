# LinuxKeyHelper.ps1 - Handles escape sequence parsing for Ctrl+Arrow keys on Linux
# Workaround for Console.ReadKey not properly detecting Ctrl+Arrow on Linux terminals

Set-StrictMode -Version Latest

class LinuxKeyHelper {
    # Parse escape sequence for Ctrl+Arrow keys
    # Returns: "Ctrl+Up", "Ctrl+Down", "Ctrl+Left", "Ctrl+Right", or $null
    static [string] ParseCtrlArrow([ConsoleKeyInfo]$keyInfo) {
        # First check if ReadKey properly detected it (works on some terminals)
        $ctrl = $keyInfo.Modifiers -band [ConsoleModifiers]::Control
        if ($ctrl) {
            switch ($keyInfo.Key) {
                ([ConsoleKey]::UpArrow) { return "Ctrl+Up" }
                ([ConsoleKey]::DownArrow) { return "Ctrl+Down" }
                ([ConsoleKey]::LeftArrow) { return "Ctrl+Left" }
                ([ConsoleKey]::RightArrow) { return "Ctrl+Right" }
            }
        }

        # Linux workaround: Check if this is ESC (start of escape sequence)
        # Ctrl+Arrow sends: ESC [  1 ; 5 A/B/C/D
        # Where A=Up, B=Down, C=Right, D=Left, and 5=Ctrl modifier
        if ($keyInfo.Key -eq [ConsoleKey]::Escape) {
            # Need to read the rest of the sequence
            # This is tricky because ReadKey already consumed the ESC
            # We need to check if more keys are available immediately
            if ([Console]::KeyAvailable) {
                $next1 = [Console]::ReadKey($true)
                if ($next1.KeyChar -eq '[' -and [Console]::KeyAvailable) {
                    # Read the sequence: could be "1;5A" or just "A"
                    $sequence = ""
                    while ([Console]::KeyAvailable) {
                        $ch = [Console]::ReadKey($true)
                        $sequence += $ch.KeyChar
                        # Stop at letter (A/B/C/D)
                        if ($ch.KeyChar -match '[A-Z]') {
                            break
                        }
                    }

                    # Parse the sequence
                    # Format: "1;5A" = Ctrl+Up
                    # Format: "1;5B" = Ctrl+Down
                    # Format: "1;5C" = Ctrl+Right
                    # Format: "1;5D" = Ctrl+Left
                    if ($sequence -match '1;5([ABCD])') {
                        switch ($Matches[1]) {
                            'A' { return "Ctrl+Up" }
                            'B' { return "Ctrl+Down" }
                            'C' { return "Ctrl+Right" }
                            'D' { return "Ctrl+Left" }
                        }
                    }
                }
            }
        }

        return $null
    }

    # Check if a key is a Ctrl+Arrow and return the direction
    static [string] DetectCtrlArrow([ConsoleKeyInfo]$keyInfo) {
        return [LinuxKeyHelper]::ParseCtrlArrow($keyInfo)
    }
}