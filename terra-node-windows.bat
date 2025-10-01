@echo off
REM Terra Node Quick Installer
REM Downloads and runs the main installer in one command
REM Usage: quick-install.bat <client_id> <client_password>

echo ============================================
echo   Terra Node Setup Program 
echo ============================================
echo.

REM Check arguments
if "%~1"=="" (
    echo [ERROR] Usage: install.bat ^<client_id^> ^<client_password^>
    echo.
    echo Example:
    echo   install.bat myid123 mypassword456
    pause
    exit /b 1
)

if "%~2"=="" (
    echo [ERROR] Usage: install.bat ^<client_id^> ^<client_password^>
    pause
    exit /b 1
)

set "CLIENT_ID=%~1"
set "CLIENT_PASSWORD=%~2"

echo [INFO] Downloading main installer...
echo [INFO] Client ID: %CLIENT_ID%
echo.

REM Download the main installer
powershell -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/binhtruong9418/demo-deploy/main/terra-node-windows.bat' -OutFile 'terra-install.bat' -UseBasicParsing; Write-Host '[OK] Installer downloaded' -ForegroundColor Green } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message -ForegroundColor Red; exit 1 }"

if %errorLevel% neq 0 (
    echo [ERROR] Failed to download installer!
    pause
    exit /b 1
)

echo [INFO] Running installer...
echo.

REM Run the main installer with arguments
call terra-install.bat "%CLIENT_ID%" "%CLIENT_PASSWORD%"

REM Cleanup
if exist "install.bat" del /f /q "install.bat" >nul 2>&1

exit /b %errorLevel%
