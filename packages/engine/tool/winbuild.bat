@echo off
rem build_runner codegen runner for Windows automation (mirrors wintest.bat).
rem Regenerates lib/*.g.dart (json_serializable). Generated files are
rem gitignored (*.g.dart); CI rebuilds them on every push.
cd /d "%~dp0.."
C:\src\dart-sdk\bin\dart.exe run build_runner build --delete-conflicting-outputs %*
