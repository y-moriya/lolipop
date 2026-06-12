@echo off
echo ============================================
echo  anman-ai Self Updater
echo ============================================
if exist "anman-ai.exe" (
  anman-ai.exe --update
) else (
  ruby bin/anman-ai --update
)
pause
