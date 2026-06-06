@echo off
REM Launch inside Windows Terminal if it exists
where wt.exe > nul 2>&1
if not errorlevel 1 (
    start "" wt.exe cmd /k "%~dp0start.bat"
    exit /b 0
)
REM Fallback: Launch in standard Command Prompt (CMD)
start "" cmd /k "%~dp0start.bat"
