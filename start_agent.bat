@echo off
cd /d "%~dp0"
if not exist agent_config.json (
  copy /y agent_config.example.json agent_config.json >nul
)
LANMonitorAgent.exe
