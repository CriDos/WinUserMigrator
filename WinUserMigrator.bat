@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo Запуск скрипта переноса профилей пользователей...
PowerShell -ExecutionPolicy Bypass -File "%~dp0WinUserMigrator.ps1" %*
if %ERRORLEVEL% NEQ 0 (
  echo Ошибка выполнения скрипта!
  pause
  exit /b 1
)
exit /b 0