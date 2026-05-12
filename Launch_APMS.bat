@echo off

cd /d "%~dp0"

powershell.exe ^
 -NoProfile ^
 -ExecutionPolicy Bypass ^
 -File "APMS.ps1"

pause