# Phase 3 toolchain install (human steps, ~30–45 min mostly waiting)

Do these in order while the fleet builds the engine round-loop. Everything else is automated.

## 1. Flutter SDK (zip install — winget has no Flutter package)
1. Download the latest **stable** Windows zip: https://docs.flutter.dev/get-started/install/windows/mobile (the "flutter_windows_x.x.x-stable.zip" link).
2. Extract so you end up with `C:\src\flutter\bin\flutter.bat` (same convention as the Dart SDK already at `C:\src\dart-sdk`).
3. Add `C:\src\flutter\bin` to your user PATH: Start → "Edit environment variables for your account" → Path → New → `C:\src\flutter\bin`.
4. New terminal → `flutter --version` should print Flutter 3.x. (Note: Flutter bundles its own Dart; the standalone `C:\src\dart-sdk` stays for the pure engine — don't delete it.)

## 2. Android Studio (interactive installer — this is why you're needed)
1. Download: https://developer.android.com/studio → install with defaults (includes Android SDK, platform-tools, emulator).
2. First-launch wizard: pick **Standard** setup, accept licenses, let it download the SDK.
3. In Android Studio: **More Actions → Virtual Device Manager → Create device** → pick a Pixel-class phone → newest stable system image (let it download) → Finish. Boot it once to verify.

## 3. Wire them together (one terminal, copy-paste)
```
flutter config --android-studio-dir "C:\Program Files\Android\Android Studio"
flutter doctor --android-licenses     (press y through the prompts)
flutter doctor
```
Target state: `[√] Flutter`, `[√] Android toolchain`, `[√] Android Studio`. (`[!]` on Chrome/Visual Studio is fine — not targets.)

## 4. Tell Claude "toolchain ready"
The fleet then runs Task 3.0 (`flutter create` the app shell wired to the engine) and starts the grey-box screens (3.1–3.6) against the emulator.

*Troubleshooting: if `flutter` isn't recognized after PATH edit, open a fresh terminal (PATH loads at shell start). If doctor can't find the SDK, it's usually at `%LOCALAPPDATA%\Android\Sdk` — set it via `flutter config --android-sdk <path>`.*
