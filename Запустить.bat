@echo off
chcp 65001 >nul
rem Открыть последнюю собранную версию Sonar без сборки.
set "EXE=%~dp0windows\src-tauri\target\release\sonar.exe"
if exist "%EXE%" (
  start "" "%EXE%"
  exit /b 0
)
echo Sonar ещё не собран. Запусти «Собрать и запустить.bat».
pause
