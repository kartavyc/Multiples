@echo off
rem ===========================================================================
rem  build_web.bat  -  reproducible WASM-only web build for MULTIPLES
rem ===========================================================================
rem
rem  WHY THIS SCRIPT EXISTS (read docs in README "Building" + .claude/STATE.md):
rem  The engine uses 64-bit wrapping integer math (SplitMix64 RNG + fixed-point
rem  sentinels) that dart2js CANNOT represent, so the web target is WASM-only.
rem  Flutter 3.44.1's `flutter build web --wasm` ALWAYS also emits a dart2js
rem  fallback and offers NO supported flag to skip it (verified: `flutter build
rem  web --help` has no --no-js-fallback; --wasm is documented as "with fallback
rem  to JavaScript"). That fallback fails to compile the engine.
rem
rem  Resolution: a small, REVERSIBLE local patch to the Flutter SDK's
rem  build_web.dart omits the JsCompilerConfig under --wasm. This script applies
rem  the patch if it is not already present, then runs the build. The patch
rem  lives on the SHARED SDK at:
rem    C:\src\flutter\packages\flutter_tools\lib\src\commands\build_web.dart
rem
rem  IMPORTANT: the OUTPUT (app/build/web) is PATCH-INDEPENDENT. Once built it
rem  is plain WASM + assets and runs on ANY static host with zero patch needed.
rem  Only PRODUCING the build needs the patch on this machine.
rem ===========================================================================

setlocal
set SDK_FILE=C:\src\flutter\packages\flutter_tools\lib\src\commands\build_web.dart
set STAMP=C:\src\flutter\bin\cache\flutter_tools.stamp
set MARKER=LOCAL PATCH (MULTIPLES publish)

if not exist "%SDK_FILE%" (
  echo [build_web] ERROR: cannot find the Flutter SDK build_web.dart at:
  echo            %SDK_FILE%
  echo            Adjust SDK_FILE in this script to your Flutter install.
  exit /b 1
)

findstr /c:"%MARKER%" "%SDK_FILE%" >nul 2>&1
if %errorlevel%==0 (
  echo [build_web] WASM-only patch already present in the Flutter SDK. Good.
) else (
  echo [build_web] Patch NOT found - applying the WASM-only patch now...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply_web_patch.ps1"
  if errorlevel 1 (
    echo [build_web] ERROR: patch application failed. See output above.
    exit /b 1
  )
  echo [build_web] Patch applied. Forcing a flutter_tools snapshot rebuild...
  if exist "%STAMP%" del /q "%STAMP%"
)

echo [build_web] Running: flutter build web --wasm --release --no-tree-shake-icons
call "%~dp0winflutter.bat" build web --wasm --release --no-tree-shake-icons
if errorlevel 1 (
  echo [build_web] ERROR: the web build failed.
  exit /b 1
)
echo [build_web] DONE. Output is in app\build\web (WASM-only; serve with any
echo             static file server). The output needs NO patch to run.
endlocal
