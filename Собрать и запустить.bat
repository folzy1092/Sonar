@echo off
chcp 65001 >nul
rem Собрать свежую версию Sonar и сразу открыть. Пересобирается только изменённое.
cd /d "%~dp0windows"

if not exist node_modules (
  echo Ставлю зависимости, это один раз...
  call npm ci || goto fail
)

echo Собираю Sonar...
call npx tauri build --no-bundle || goto fail

start "" "%~dp0windows\src-tauri\target\release\sonar.exe"
exit /b 0

:fail
echo.
echo Сборка не удалась — ошибка выше.
pause
exit /b 1
