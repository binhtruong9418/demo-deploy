@echo off
net session >nul 2>&1 || (echo Run as Administrator! && pause && exit /b 1)
set "CLIENT_ID=%~1"
set "CLIENT_PASSWORD=%~2"
if "%CLIENT_ID%"=="" (echo CLIENT_ID required! && pause && exit /b 1)
if "%CLIENT_PASSWORD%"=="" (echo CLIENT_PASSWORD required! && pause && exit /b 1)
set "DIR=C:\Program Files\TerraNode"
mkdir "%DIR%" 2>nul
echo Downloading installer...
powershell -ExecutionPolicy Bypass -Command "iwr -useb 'https://raw.githubusercontent.com/binhtruong9418/demo-deploy/main/terra-node-windows.ps1' -OutFile '%DIR%\install.ps1'" || (echo Download failed! && pause && exit /b 1)
echo Installing Terra Node [%CLIENT_ID%]...
powershell -ExecutionPolicy Bypass -File "%DIR%\install.ps1" -ClientId "%CLIENT_ID%" -ClientPassword "%CLIENT_PASSWORD%"
if %errorLevel% equ 0 (echo Success! Service: TerraNode) else (echo Failed!)
pause
