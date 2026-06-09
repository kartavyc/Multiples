@echo off
rem Runs the Flutter SDK CLI from the app package root (cds itself; callers
rem never need quoting). Toolchain caches were RELOCATED to D: (2026-06-07);
rem the SET lines below make every invocation immune to stale inherited env.
set GRADLE_USER_HOME=D:\claude\toolchains\gradle
set ANDROID_HOME=D:\claude\toolchains\android-sdk
set ANDROID_SDK_ROOT=D:\claude\toolchains\android-sdk
set ANDROID_AVD_HOME=D:\claude\toolchains\avd
rem Some launch contexts inherit a cmd env WITHOUT ProgramFiles(x86) (the
rem parenthesized var); flutter.bat's shared.bat aborts loudly when it is
rem missing. Default it so `flutter test`/`build` work regardless of how the
rem shell was spawned (harmless when already set).
if not defined ProgramFiles(x86) set "ProgramFiles(x86)=C:\Program Files (x86)"
cd /d "%~dp0.."
C:\src\flutter\bin\flutter.bat %*
