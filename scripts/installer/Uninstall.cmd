@echo off
setlocal EnableExtensions
title Codex NInfer Uninstaller

rem Entry point for the Codex NInfer uninstaller.
rem It removes the installed binaries from %LOCALAPPDATA%\CodexNInfer\bin,
rem removes the user PATH entry, and only deletes the .codex-ninfer profile
rem folder if you explicitly answer yes.

cd /d "%~dp0"

if not exist "install-ninfer.ps1" (
    echo ERROR: install-ninfer.ps1 was not found next to Uninstall.cmd.
    echo Make sure the release ZIP was fully extracted.
    goto :error
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-ninfer.ps1" -Uninstall
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto :error

echo.
echo Uninstall finished. Press any key to close this window.
pause >nul
exit /b 0

:error
echo.
echo The uninstaller stopped with an error.
echo Read the message above. You can run Uninstall.cmd again to continue.
echo.
pause
exit /b 1