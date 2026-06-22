@echo off
:: Project Winix — Convenience launcher
:: Right-click -> "Run as administrator" or execute from an elevated terminal.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-Winix.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Project Winix exited with error code %ERRORLEVEL%.
    pause
)
