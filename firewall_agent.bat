@echo off
echo Opening TCP port 8765 for LAN Monitor Agent...
netsh advfirewall firewall add rule name="LAN Monitor Agent 8765" dir=in action=allow protocol=TCP localport=8765 profile=private
echo.
echo Firewall rule added. Run LANMonitorAgent.exe now.
pause
