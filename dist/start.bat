@echo off
chcp 65001 > nul
title anman-ai - AI Werewolf Player

set EXE_DIR=%~dp0
set CONFIG=%EXE_DIR%config\config.yaml
set EXE=%EXE_DIR%anman-ai.exe

:: Process CLI arguments (for shortcuts or outer tools)
if "%1"=="--update" goto update
if "%1"=="--wt" goto start_wt

:menu
cls
echo ============================================
echo  anman-ai - AI Werewolf Player
echo ============================================
echo  1. AI起動 (通常プロンプト)
echo  2. AI起動 (Windows Terminal)
echo  3. 自己アップデート実行
echo  4. 終了
echo ============================================
echo.

:: Automatically choose 1 after 5 seconds of inactivity
choice /c 1234 /t 5 /d 1 /m "メニュー番号を選択してください: "
set opt=%errorlevel%

if %opt% equ 1 goto start_normal
if %opt% equ 2 goto start_wt
if %opt% equ 3 goto update
if %opt% equ 4 exit /b 0
goto start_normal

:start_normal
echo.
echo Ctrl+C またはこのウィンドウを閉じることで停止します。
echo.
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

:start_wt
echo Windows Terminal で起動中...
where wt.exe > nul 2>&1
if not errorlevel 1 (
    start "" wt.exe cmd /c "%~f0" --normal-launched
    exit /b 0
)
echo [Warning] Windows Terminal (wt.exe) が見つかりませんでした。通常プロンプトで起動します。
timeout /t 2 /nobreak > nul
goto start_normal

:update
echo.
echo ============================================
echo  anman-ai Self Updater
echo ============================================
if exist "%EXE%" (
    "%EXE%" --update
) else (
    ruby bin/anman-ai --update
)
pause
goto menu

:end
pause
