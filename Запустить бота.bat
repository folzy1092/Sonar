@echo off
chcp 65001 >nul
rem Бот @SonarMusicApp на этом ПК (polling). Окно не закрывай, пока бот нужен; Ctrl+C — остановить.
cd /d "%~dp0server"
if not exist ".env" (
  copy /y "env.example" ".env" >nul
  echo Создал server\.env — впиши токен бота в строку SONAR_BOT_TOKEN=, сохрани и закрой блокнот.
  notepad ".env"
)
python -m pip install -q -r requirements.txt
python -m sonar
pause
