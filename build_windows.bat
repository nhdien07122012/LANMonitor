@echo off
setlocal
cd /d "%~dp0"

echo [1/4] Creating virtual environment...
if not exist .venv python -m venv .venv
call .venv\Scripts\activate.bat

echo [2/4] Installing dependencies...
python -m pip install --upgrade pip
pip install -r requirements.txt

echo.
echo Chon che do build:
echo 1. Build Agent
echo 2. Build Dashboard
echo 3. Build Ca hai
set /p choice="Nhap lua chon (1-3): "

if "%choice%"=="1" goto build_agent
if "%choice%"=="2" goto build_dashboard
if "%choice%"=="3" goto build_all
goto end

:build_agent
echo [Building Agent...]
taskkill /F /IM LANMonitorAgent.exe /T 2>nul
python -m PyInstaller --noconfirm --clean --onefile --windowed --icon=app-agent.ico --add-data "app-agent.ico;." --name LANMonitorAgent agent.py
goto end

:build_dashboard
echo [Building Dashboard...]
taskkill /F /IM LANMonitorDashboard.exe /T 2>nul
python -m PyInstaller --noconfirm --clean --onefile --windowed --icon=app-das.ico --add-data "app-das.ico;." --name LANMonitorDashboard dashboard.py
goto end

:build_all
echo [Building Agent...]
taskkill /F /IM LANMonitorAgent.exe /T 2>nul
python -m PyInstaller --noconfirm --clean --onefile --windowed --icon=app-agent.ico --add-data "app-agent.ico;." --name LANMonitorAgent agent.py

echo [Building Dashboard...]
taskkill /F /IM LANMonitorDashboard.exe /T 2>nul
python -m PyInstaller --noconfirm --clean --onefile --windowed --icon=app-das.ico --add-data "app-das.ico;." --name LANMonitorDashboard dashboard.py
goto end

:end
echo.
echo DONE.
echo Files are in dist\
pause
