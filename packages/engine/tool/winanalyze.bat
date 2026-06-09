@echo off
rem Analyzer runner for Windows automation.
cd /d "%~dp0.."
C:\src\dart-sdk\bin\dart.exe analyze lib test
