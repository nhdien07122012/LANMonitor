@echo off
echo ================================
echo LAN Monitor CPU Diagnostic
echo ================================
echo.
python -c "import psutil; print('CPU cores:', psutil.cpu_count()); print('CPU sample 1:', psutil.cpu_percent(interval=0.2)); print('CPU sample 2:', psutil.cpu_percent(interval=1.0))"
echo.
echo If CPU sample 2 changes when you open programs, CPU monitoring is working.
echo.
pause
