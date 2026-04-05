@echo off
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\dev\pie\scripts\pie_backend_cmd_mock_v1.ps1" "%~1" "%~2"
exit /b %ERRORLEVEL%