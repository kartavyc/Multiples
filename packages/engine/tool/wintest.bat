@echo off
rem Engine test runner for Windows automation (Desktop Commander safe: no quoted-cd issues).
rem Usage: wintest.bat [dart test args...]   e.g. wintest.bat test/model_test.dart
cd /d "%~dp0.."
C:\src\dart-sdk\bin\dart.exe test %*
