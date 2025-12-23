#!/usr/bin/env pwsh
# Test terminal size detection in different contexts

Write-Host "=== Terminal Size Detection Test ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1] Environment Variables:" -ForegroundColor Yellow
Write-Host "  COLUMNS: $env:COLUMNS"
Write-Host "  LINES: $env:LINES"
Write-Host "  TERM: $env:TERM"
Write-Host ""

Write-Host "[2] PowerShell Console API:" -ForegroundColor Yellow
try {
    Write-Host "  WindowWidth: $([Console]::WindowWidth)"
    Write-Host "  WindowHeight: $([Console]::WindowHeight)"
    Write-Host "  BufferWidth: $([Console]::BufferWidth)"
    Write-Host "  BufferHeight: $([Console]::BufferHeight)"
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
}
Write-Host ""

Write-Host "[3] tput (via bash):" -ForegroundColor Yellow
try {
    $cols = bash -c 'tput cols'
    $lines = bash -c 'tput lines'
    Write-Host "  cols: $cols"
    Write-Host "  lines: $lines"
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
}
Write-Host ""

Write-Host "[4] stty:" -ForegroundColor Yellow
try {
    $size = bash -c 'stty size'
    Write-Host "  size: $size"
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
}
Write-Host ""

Write-Host "[5] ioctl TIOCGWINSZ (via Python):" -ForegroundColor Yellow
try {
    $pySize = python3 -c "import struct, fcntl, termios, sys; print(struct.unpack('hh', fcntl.ioctl(0, termios.TIOCGWINSZ, '1234')))" 2>&1
    Write-Host "  size: $pySize"
} catch {
    Write-Host "  Python not available or error" -ForegroundColor Gray
}
Write-Host ""

Write-Host "[6] Checking if running in tmux/screen:" -ForegroundColor Yellow
Write-Host "  TMUX: $env:TMUX"
Write-Host "  STY: $env:STY"
Write-Host "  TERM_PROGRAM: $env:TERM_PROGRAM"
Write-Host ""

Write-Host "=== Analysis ===" -ForegroundColor Cyan
if ([Console]::WindowWidth -lt 80 -or [Console]::WindowHeight -lt 24) {
    Write-Host "⚠️  Terminal size is below minimum (80x24)" -ForegroundColor Yellow
    Write-Host "   Current: $([Console]::WindowWidth)x$([Console]::WindowHeight)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  1. Running through a wrapper that limits size" -ForegroundColor White
    Write-Host "  2. Terminal emulator has small default size" -ForegroundColor White
    Write-Host "  3. COLUMNS/LINES env vars are set incorrectly" -ForegroundColor White
    Write-Host "  4. Running in a constrained environment (container, CI, etc.)" -ForegroundColor White
} else {
    Write-Host "✓ Terminal size is adequate" -ForegroundColor Green
}
