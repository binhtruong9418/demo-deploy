@echo off
setlocal enabledelayedexpansion

REM Terra Node Installation Script for Windows
REM Usage: install-terra-node.bat [client_id] [client_password]

echo ============================================
echo    Terra Node Installation for Windows
echo ============================================
echo.

REM Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] This script requires Administrator privileges.
    echo Please right-click and select "Run as Administrator"
    echo.
    pause
    exit /b 1
)

REM Get Client ID
set "CLIENT_ID=%~1"
if "%CLIENT_ID%"=="" (
    set /p CLIENT_ID="Enter Client ID: "
)

if "%CLIENT_ID%"=="" (
    echo [ERROR] Client ID is required!
    pause
    exit /b 1
)

REM Get Client Password
set "CLIENT_PASSWORD=%~2"
if "%CLIENT_PASSWORD%"=="" (
    set /p CLIENT_PASSWORD="Enter Client Password: "
)

if "%CLIENT_PASSWORD%"=="" (
    echo [ERROR] Client Password is required!
    pause
    exit /b 1
)

echo.
echo [INFO] Client ID: %CLIENT_ID%
echo [INFO] Starting installation...
echo.

REM Create installation directory
set "INSTALL_DIR=C:\Program Files\TerraNode"
if not exist "%INSTALL_DIR%" (
    echo [INFO] Creating installation directory: %INSTALL_DIR%
    mkdir "%INSTALL_DIR%"
)

REM Download PowerShell script to installation directory
set "PS_SCRIPT=%INSTALL_DIR%\terra-node-installer.ps1"
set "SCRIPT_URL=https://raw.githubusercontent.com/binhtruong9418/demo-deploy/main/terra-node-windows.ps1"

echo [INFO] Downloading installer script...
powershell -ExecutionPolicy Bypass -Command "& {try {Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%PS_SCRIPT%' -UseBasicParsing; Write-Host '[SUCCESS] Script downloaded successfully' -ForegroundColor Green} catch {Write-Host '[ERROR] Failed to download script: ' $_.Exception.Message -ForegroundColor Red; exit 1}}"

if %errorLevel% neq 0 (
    echo [ERROR] Failed to download installation script
    pause
    exit /b 1
)

REM Run PowerShell script
echo [INFO] Running installation...
echo.
powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -ClientId "%CLIENT_ID%" -ClientPassword "%CLIENT_PASSWORD%"

if %errorLevel% equ 0 (
    echo.
    echo ============================================
    echo    Installation completed successfully!
    echo ============================================
    echo.
    echo Installation files saved to: %INSTALL_DIR%
    echo.
    echo Service Management:
    echo   - Check status: sc query TerraNode
    echo   - Start service: net start TerraNode
    echo   - Stop service: net stop TerraNode
    echo.
) else (
    echo.
    echo ============================================
    echo    Installation failed!
    echo ============================================
    echo.
    echo Check the error messages above for details.
    echo Installation script location: %PS_SCRIPT%
    echo.
)

pause
