@echo off
chcp 65001 > nul
title anman-ai - AI Werewolf Player

echo ============================================
echo  anman-ai - AI Werewolf Player
echo  Ctrl+C or close this window to stop.
echo ============================================
echo.

set EXE_DIR=%~dp0
set CONFIG=%EXE_DIR%config\config.yaml
set EXE=%EXE_DIR%anman-ai.exe

if not exist "%EXE%" (
    echo [Error] anman-ai.exe が見つかりません: %EXE%
    pause
    exit /b 1
)

if not exist "%CONFIG%" (
    echo [Error] 設定ファイルが見つかりません: %CONFIG%
    echo config\config.yaml を編集してから再起動してください。
    pause
    exit /b 1
)

:loop
echo [%date% %time%] anman-ai を起動します...
"%EXE%" "%CONFIG%"
set ERR=%errorlevel%
if %ERR% equ 0 (
    echo [%date% %time%] 正常終了しました。
    goto end
)
echo [%date% %time%] 終了コード %ERR% (5秒後に再起動...)
timeout /t 5 /nobreak > nul
goto loop

:end
pause
