@echo off
cd /d "%~dp0"
echo ====================================================
echo        LAN Monitor - Day ma nguon len GitHub
echo ====================================================
echo.

git push -u origin main
if %ERRORLEVEL% EQU 0 (
    echo.
    echo [OK] Day code len GitHub thanh cong!
    echo.
    echo Truy cap duong dan sau de xem qua trinh build va tai file .ipa:
    echo https://github.com/nhdien07122012/LANMonitor/actions
) else (
    echo.
    echo [!] Chua the day code. Ban da tao repository tren GitHub chua?
    echo Hay mo trinh duyet va vao link sau de bam "Create repository":
    echo https://github.com/new?name=LANMonitor^&private=true
)
echo.
pause
