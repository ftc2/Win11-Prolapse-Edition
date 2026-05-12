@echo off
setlocal

set "REPO_DIR=%~dp0"
if "%REPO_DIR:~-1%"=="\" set "REPO_DIR=%REPO_DIR:~0,-1%"
set "LOG_DIR=%USERPROFILE%\Desktop\Prolapse Logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

where /q code
if not errorlevel 1 (
  start "" code "%REPO_DIR%" "%LOG_DIR%"
  exit /b 0
)

for %%P in (
  "%LocalAppData%\Programs\Microsoft VS Code\Code.exe"
  "%ProgramFiles%\Microsoft VS Code\Code.exe"
  "%ProgramFiles(x86)%\Microsoft VS Code\Code.exe"
) do (
  if exist "%%~fP" (
    start "" "%%~fP" "%REPO_DIR%" "%LOG_DIR%"
    exit /b 0
  )
)

echo VS Code was not found.
echo Install VS Code first, then run this script again.
pause
exit /b 1
