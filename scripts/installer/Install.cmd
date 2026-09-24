@echo off
setlocal EnableExtensions
title Codex NInfer Installer

rem Entry point for the Codex NInfer Windows installer.
rem Double-clicking this file runs install-ninfer.ps1 with a fixed
rem execution policy, so your machine policy settings do not matter.

cd /d "%~dp0"

if not exist "install-ninfer.ps1" (
    echo ERROR: install-ninfer.ps1 was not found next to Install.cmd.
    echo Make sure the release ZIP was fully extracted.
    goto :error
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-ninfer.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto :error

echo.
echo Installation finished. Press any key to close this window.
pause >nul
exit /b 0

:error
echo.
echo The installer stopped with an error.
echo Read the message above, fix the problem, and run Install.cmd again.
echo.
pause
exit /b 1