@echo off
rem Pub-get runner for Windows automation (mirrors wintest.bat; Desktop Commander safe).
cd /d "%~dp0.."
C:\src\dart-sdk\bin\dart.exe pub get %*
