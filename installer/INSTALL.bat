@echo off
title VIctory AMD installer (RDNA2 / RDNA3 / RDNA4)
set "PACK_DIR=%~dp0"
if "%PACK_DIR:~-1%"=="\" set "PACK_DIR=%PACK_DIR:~0,-1%"
if not exist "%PACK_DIR%\payload\setup.ps1" (
    echo [ERROR] payload\setup.ps1 is missing. Extract the WHOLE zip first.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PACK_DIR%\payload\setup.ps1" -PackDir "%PACK_DIR%" %*
echo.
pause
