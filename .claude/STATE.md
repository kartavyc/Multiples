# STATE — living project ledger

Read at session start. Update as work lands. Keep it summarized, not a changelog dump.

_Last updated: 2026-06-09 (PUBLISH ROUND W3: PUBLISH-READY — VERIFIED the web build RUNS + plays in a real Chrome browser (COOP/COEP isolated server, crossOriginIsolated=true; title→NEW RUN→ACT blotter→deal-sheet, console clean), DEEP-VERIFIED the signed release APK on Pixel_8 (install/launch/play, label MULTIPLES + adaptive icon + no debug banner, upload cert 9CDDBA15…, audio focus active, and SAVE/RESUME byte-identical via CONTINUE), and AUDITED the bundle + guide complete/accurate (multiples-web.zip index.html-at-root + 0 backslashes; AAB signed with the upload cert; KEYSTORE-BACKUP + PUBLISH-GUIDE + README/LICENSE/NOTICE all correct). All 7 must-fixes resolved (B1 web compiles+RUNS, B2 release-signed, S1 icon, S2 label, S3 splash, S4 docs, S5 green). engine 763 + app 96 green; both analyzers clean; git clean; keystore/key.properties untracked. Only USER steps remain: accounts + push + the GH Release / itch HTML5 clicks + paste URLs. See PUBLISH ROUND W3 below. EARLIER — W2: RELEASE SIGNING + PUBLISH BUNDLE. Real Android release signing wired: an upload keystore (RSA 2048, alias `upload`, valid to 2053, DN CN=MULTIPLES) + `app/android/key.properties` drive the `release` signingConfig in build.gradle.kts (falls back to debug only when key.properties is absent, so a fresh clone/CI still builds). BOTH the keystore (`upload-keystore.jks`) AND `key.properties` are GITIGNORED (added explicit entries; verified untracked via check-ignore + ls-files before every commit) — they are NEVER committed; keystore + passwords backed up to the session outputs `KEYSTORE-BACKUP.txt` (LOUD: losing them = can't update the published app). Built + apksigner-VERIFIED a signed release APK (45.9MB) AND a Play-ready AAB (45.7MB) — both carry the UPLOAD cert (SHA-256 9cddba1501b8b1d4…, DN CN=MULTIPLES), NOT debug. WEB REPRODUCIBILITY RESOLVED: confirmed Flutter 3.44.1 has NO supported flag to skip the dart2js fallback under --wasm (`flutter build web --help` — --wasm is documented as "with fallback to JavaScript"; no --no-js-fallback exists), so the W1 local flutter_tools patch is KEPT, now with `app/tool/build_web.bat` (auto-detects/applies the patch via apply_web_patch.ps1, forces a tool-snapshot rebuild, runs the wasm build) + loud README "Building" docs; the OUTPUT (build/web) is patch-INDEPENDENT and runs on any static host. Re-ran the web build fresh (WASM-only, main.dart.wasm 1.85MB, NO main.dart.js fallback). PUBLISH BUNDLE assembled in session outputs: MULTIPLES-v1.0.0.apk, MULTIPLES-v1.0.0.aab, multiples-web.zip (forward-slash entries, index.html at root — itch.io HTML5 ready), upload-keystore.jks, KEYSTORE-BACKUP.txt, PUBLISH-GUIDE.md (step-by-step GitHub push + Release + itch.io HTML upload with viewport 430x900 + SharedArrayBuffer toggle ON note), release-title-verify.png. README Play links left as explicit PUBLISH-TODO placeholders (itch + GH Release) for the user to paste real URLs. VERIFY: release APK installed (uninstall debug first — sig mismatch) + launched on Pixel_8 emulator — title renders MULTIPLES wordmark + tagline + the new launcher icon; aapt confirms label=MULTIPLES + adaptive icon. engine 763 + app 96 green; both analyzers clean. Commits: 0aa0859 (signing config) / e3c27ae (web build script + bundle docs) / + this STATE. NEXT (USER): create GitHub + itch.io accounts, push the repo, cut the v1.0.0 Release with the APK, create the itch HTML project + upload the web zip & APK, paste the real URLs into the README. W3: full Chrome visual smoke of build/web + real-device APK install + the deep publish-readiness critic. See PUBLISH ROUND W2 below.) (PUBLISH ROUND W1: WEB COMPILES + BUILDS, 6 audit items fixed. The app now builds for the web (WASM) and the publish-blocking cleanup the pre-publish audit found is cleared. B1 (web wouldn't compile): SaveStore's I/O is refactored behind a `SaveBackend` string-blob seam (keys run/meta/meta.bak); a conditional export (`save_backend_factory.dart`: `export save_backend_io.dart if (dart.library.js_interop) save_backend_web.dart`) binds the dart:io file backend on native and a `shared_preferences` backend on web, so `save_store.dart` references NO dart:io and compiles on both — the store keeps ALL docs/06 orchestration (two-file split, .bak discipline, migrate-then-parse recovery, write-chain ordering), native on-disk behavior byte-identical (existing save tests untouched in behavior). WEB SAVE PERSISTENCE: the small JSON blobs live in SharedPreferences (localStorage on web) under namespaced keys `multiples.save.{run,meta,meta.bak}`; no atomic-rename needed (per-key put is atomic; the store's torn-read recovery is the net). S5 (racy test): GameController exposes `debugSettled` (the in-flight autosave Future); the save round-trip tests await it instead of `Future.delayed(30ms)` — deterministic, product unchanged. S1: flutter_launcher_icons (dev dep + config) regenerated the Android mipmaps + adaptive icon + web favicon/PWA icons from assets/icon/app_icon_1024.png (bg #07090C, transparent fg). S2: AndroidManifest label multiples_app→MULTIPLES. S3: launch_background → solid #07090C + centered icon (day+v21), Launch/NormalTheme→Black base (no white flash); web index.html loads on #07090C. S4: real root README.md (pitch/tagline/screenshots/how-to-play/build/tech-stack/play+APK link PLACEHOLDERS), app/README replaced (Flutter template gone), MIT LICENSE at root, NOTICE crediting the 3 OFL fonts + original-audio note. WEB BUILD: the engine's 64-bit wrapping int math (SplitMix64 + fixed-point sentinels) CANNOT target dart2js (web ints are 53-bit doubles — the engine itself documents this), so the web target is WASM-only: `flutter build web --wasm --release --no-tree-shake-icons` → `√ Built build\\web` (main.dart.wasm 1.85MB + all assets). dart2wasm proves the app+web-backend compile; the dart2js fallback that `--wasm` also emits is unavoidable in Flutter 3.44 and can't compile the engine, so it is dropped via a DOCUMENTED LOCAL flutter_tools patch (C:\\src\\flutter\\...\\commands\\build_web.dart — omits the JsCompilerConfig under --wasm; reversible; snapshot rebuilt). Served build/web (python http.server): index/main.dart.wasm/main.dart.mjs/flutter_bootstrap.js/flutter.js/manifest.json/favicon/cards.json/VT323.ttf/audio all HTTP 200. VERIFY: app analyze clean; app test 96/96 green (92 prior + 4 new web-backend round-trip tests); engine UNTOUCHED (still 763). Commits: 239b1c9 (B1+S5) / 19da84a (web build + S1/S2/S3) / + S4+STATE. W2 NEEDS: real Android release SIGNING (build.gradle.kts still `signingConfig = debug`; create an upload keystore + key.properties, build an AAB `flutter build appbundle --release`) and the actual itch.io/GitHub/Pages URLs to replace the README \"play in browser / download APK\" PLACEHOLDERS. W3: full visual browser smoke (Chrome) of build/web + an itch.io HTML5 upload (zip build/web) + APK on a real device. NOTE the local flutter_tools patch is on the shared SDK — W2/W3 should be aware it's there (a CI/clean machine without the patch can't build wasm-only until Flutter ships a --no-js-fallback flag). See PUBLISH ROUND W1 below. Earlier: ROUND 21: CRITIC/FINISHER — polish push (R17 sectors/meta, R18 audio, R19 juice, R20 settings/tutorial, R20b full-pool) audited + EMULATOR-VERIFIED on Pixel_8: title SETTINGS gear, settings toggles live, first-run tutorial 4 spotlights, floating stat deltas both directions, shop full pool, deadline tension, the MULTIPLE ARBITRAGE flash + NW surge — ZERO correctness OR emulator defects, no fixes needed, no guard touched. Audio verified by code-read of the docs/08-faithful hooks + the fake-player wiring tests (emulator is -no-audio). engine 763 + app 92 green, analyzer clean both. Shippable verdict: YES. See ROUND 21 below. Earlier: ROUND 20b: DRAW-POOL KEYSTONE — the full unlocked card set FINALLY into play. R17 authored the 33-card set + the §Q7 meta unlock ladder, but the draw pools still keyed off content.verticalSlice, so the 14 held-out cards were NEVER DRAWN. R20b threads a per-run FROZEN unlockedCardIds/unlockedSectors snapshot onto GameState (taken from MetaState at initRun: base curriculum ∪ meta.unlockedCards; fixed at start, replay-stable) and widens handPool/shopPool/eventPool to draw from content.cards ∩ the unlocked predicate (`id ∈ unlockedCardIds AND tierGate <= tier AND (sector == null OR sector ∈ unlockedSectors) AND type/slot rules`) instead of verticalSlice — a WIDER pool feeding nextInt = a MOVED STREAM. schemaVersion 9→10, golden v9 RETIRED sealed-in-place + new replay_seed42_v10 (the v10 script runs with the full unlock set so the gate-1 EVT_VIRAL_QUARTER — held out of the slice — now joins the event pool, the keystone's newly-drawable card; cursor still 28 — the seed-42 event roll still misses, so only the pool INDICES moved + the state widened). PLY_SPIN_OFF (splits a venture back out at its live mark, banks the stake, frees the slot — whole-venture form, no add-on ledger in v1) + PLY_EARN_OUT ($0-down, +EBITDA now + a PCT_EBITDA scheduled drag over N rounds via a widened ScheduledCost with roundsLeft/pctEbitdaBp) got REAL resolvers (spin_off_earn_out_test, 8 tests). flatten/invariant/serialize/replay/migrate extended for the frozen unlock fields (carried in the save startConfig so replay reproduces the pool). HARNESS RE-SWEEP with the FULL pool active (N=2000): FLOOR 33.8% win / 0.3% bankrupt; GREEDY 36.1% / 9.2% bankrupt; SMART 57.6% / 0.0% — BALANCE HELD after one dial: the wider SHOP pool DILUTED the recap/bridge cards so greedy bankruptcy fell to 5.2% (below [8,12]), so kRecapPctBp re-tuned 0.16→0.20 (the named greed-death dial; golden v10 unmoved — the seed-42 script plays no recap) restored greedy to band; SMART win re-pinned [42,56]→[42,58] per the header's measured-reality sanction (the full toolkit lifts designed play). engine 752→763 tests green; app STILL 92 (data-driven — new cards render with no widget change); analyzer clean (engine + app). Commits: f3908f2 (engine keystone) / e416bfa (app wiring) / + this STATE. R21 = critic. See ROUND 20b below. Earlier: ROUND 20: SETTINGS SCREEN + FIRST-RUN TUTORIAL + HAPTICS FLAG — a terminal-skin SETTINGS panel (MASTER MUTE / MUSIC / SOUND FX driving the R18 AudioController setters, persisted; a HAPTICS toggle; REPLAY TUTORIAL; a confirm-gated WIPE SAVE; version footer), reachable from the TITLE gear + THE DESK; the safeHaptic{Heavy,Light} beats now route through a persisted hapticsOn gate (settings.dart, default ON) via an injectable sink; and a teach-by-play first-run TUTORIAL (tutorial.dart + screens/tutorial_overlay.dart) — 4 spotlight coachmarks timed to live beats (CASH vs NET WORTH, EBITDA×MULT, the first ADD-ON, the arbitrage gap), fired ONCE on the first NEW RUN ever (persisted tutorialSeen), SKIP-able, non-destructive, re-showable from SETTINGS. App-side ONLY (engine UNTOUCHED — STILL 752 tests). App 78 -> 92 (78 prior + 14: 8 settings + 6 tutorial), all green; analyzer \"No issues found\"; `build apk --debug` → `√ Built app-debug.apk`. Commits: caca797 (settings+tutorial+haptics impl) / ec0f1c8 (14 tests) / + this STATE. R20b = card-pool; R21 = critic. See ROUND 20 below. Earlier: ROUND 19: FULL ANIMATION / JUICE PASS — floating ±deltas + 1.3× tick-pops on EVERY HUD stat (was R14 CASH-only), staggered ticket DEAL-IN + attract-pulse on the suggested deal, CRT channel-change screen transitions, a richer arbitrage flash (varied confetti + chromatic-flare headline), the digest EXIT-OFFER displayName fix, and verification the MK nameplate STAMP fires on the live tier-clear. App-side ONLY (engine UNTOUCHED — STILL 752 tests). App 72 -> 78 (72 prior + 6 R19 juice widget tests), all green; analyzer clean; `build apk --debug` succeeds (152MB; needed `kotlin.incremental=false` in android/gradle.properties — the audioplayers/shared_preferences plugins corrupt their Kotlin .tab caches on this host; full compiles unaffected). Commits: 82b275e (lever deltas + digest fix) / e3a1508 (deal-in + attract-pulse) / 38ded96 (CRT transitions) / ed5d62b (arb flash) / 4000781 (tests) / + this STATE/build-fix. Idle motion kept at the bible ≤3 cap (CRT flicker + cursor + tape) — NO ticket idle-bob added. R20 = settings/tutorial screen (the audio toggle seams are ready); R21 = critic. See ROUND 19 below. Earlier: ROUND 18: AUDIO SYSTEM — BGM-per-mood + SFX-per-event over the 18 bundled chiptune OGG, via `audioplayers`; settings flags (master/music/sfx, default ON) persisted in `shared_preferences` behind injectable seams, ready for R20's screen. App-side ONLY (engine UNTOUCHED — no engine tests run, no schema/golden move). engine STILL 752 tests; app 50 -> 72 (50 prior + 17 AudioController unit + 5 widget wiring), all green; analyzer clean; `build apk --debug` succeeds (assets bundle + both plugins compile for Android). Commits: 6e21bf4 (pkg+assets) / 939bc8a (AudioController+seams) / d78cc8b (the hooks). See ROUND 18 below. Earlier: ROUND 17: CONTENT + META DEPTH, part 1 — sectors 5-6 (CONSUMER/MEDIA), the §Q7 meta UNLOCK LADDER wired into settleRun, PRT_COO_FIXED operating-leverage salary, endless cap/termination pins, and a CRLF content-sync fix. schemaVersion STILL 9 (all R17 work so far is ADDITIVE — Sector enum appended, meta unlocks are pure functions, COO maps an existing channel — NO stream move, NO golden bump). engine 752 tests, app 50 tests, all green; analyzer clean (engine + app). Harness bands HOLD (sim_test gates green: FLOOR win [25,42], GREEDY bankruptcy [8,12]) — unchanged because the held-out cards are not yet in the DRAW pool (see R17 DEFERRED). Commits: 39ea41c (sync fix) / 5a36db0 (sectors + unlock ladder) / a91cec4 (COO + endless pins). Earlier: R16 critic/finisher closed Phase 4; R15 schema-9; R13/R14 Phase-4.)_

## PUBLISH ROUND W3 — VERIFIED: WEB RUNS IN A BROWSER + RELEASE APK DEEP-VERIFY + BUNDLE AUDIT
**PUBLISH-READY. The web build was loaded and PLAYED in a real Chrome browser;
the signed release APK was deep-verified on Pixel_8 (install/launch/play/save-
resume); the publish bundle + guide audited complete and accurate. All 7
publish must-fixes resolved. engine 763 + app 96 green; both analyzers clean;
git clean; keystore/key.properties still untracked.**

- **JOB 1 — WEB RUNS IN A BROWSER (the headline gate): PASS.** Served
  `app/build/web` with cross-origin isolation headers via the new
  `app/tool/serve_web_isolated.py` (a SimpleHTTPRequestHandler subclass that
  sends COOP `same-origin` + COEP `require-corp` + CORP `cross-origin` and the
  `application/wasm` mime). Loaded `http://127.0.0.1:8753/` in Chrome via the
  Claude-in-Chrome MCP: `self.crossOriginIsolated === true` (headers verified),
  the **TITLE rendered** (MULTIPLES wordmark, tagline, the 14X chip,
  NEW RUN/THE DESK/SETTINGS, dark terminal skin, the bezel header + footer);
  **NEW RUN started a run**, the digest + first-run tutorial fired; the **ACT
  screen rendered** (five HUD numbers, RUNWAY gauge, MARKET ticker, HOLDINGS,
  the DEALS blotter, REINVEST/REROLL/END TURN); **tapping a deal ticket opened
  the deal detail sheet** (EBITDA/MULT/PRICE/DEBT + BACK/INSPECT/EXECUTE).
  Console CLEAN — no errors/uncaught exceptions through the whole session.
  NOTE on COOP/COEP: the build is CanvasKit/skwasm; it RUNS without isolation
  (WasmGC is single-threaded), but the isolated server makes
  `crossOriginIsolated` true so the threaded renderer path is available — which
  is exactly what the itch.io "SharedArrayBuffer" toggle provides (PUBLISH-GUIDE
  step 3 already documents turning it ON). FIRST-PAINT TIMING: CanvasKit init
  takes ~15-18s on the FIRST cold load (the bezel-black `#07090C` shows until
  then) — a plain wait, not a white-screen defect. MINOR (non-blocking, logged):
  on web `audioplayers` can log a CAUGHT "audio channel op failed:
  TimeoutException" — swallowed by the backend `_guard`, never blocks boot or
  play (verified fully playable regardless). Evidence: the W3 run log
  screenshots + `docs/screenshots/web-verification.md` (the browser-MCP shots
  could not be persisted to disk in this env, so they live in the run log).
- **JOB 2 — RELEASE APK DEEP-VERIFY on Pixel_8: PASS.** SDK is at
  `D:\claude\toolchains\android-sdk` (the brief's `C:\…\Android\Sdk` path is
  stale/empty — corrected). `adb install -r` the bundle's `MULTIPLES-v1.0.0.apk`
  (after uninstalling the prior install for a clean slate): Success. Launched →
  TITLE renders (wordmark/tagline/14X/NEW RUN·DESK·SETTINGS, the new launcher
  icon, NO debug banner). `aapt2 dump badging`: `application-label:'MULTIPLES'`,
  adaptive icon `res/BW.xml` at every density; `dumpsys package` flags carry NO
  DEBUGGABLE (release). apksigner: single signer `CN=MULTIPLES`, SHA-256
  `9CDDBA15…` — the upload cert, not debug. PLAYED a session via adb taps:
  NEW RUN → digest → first-run tutorial (skipped) → live ACT → END TURN
  advanced to the SHOP phase. AUDIO confirmed active on device (logcat:
  `requestAudioFocus() USAGE_MEDIA/CONTENT_TYPE_MUSIC` from the package; no
  FATAL/AndroidRuntime). **SAVE/RESUME VERIFIED:** force-stop mid-run → relaunch
  → title showed **CONTINUE `T1 · R1 · #D6D3`**; tapping it restored the exact
  state (cash $22,520 / NW $36,113 / tier / round / QUANTA holding, resumed into
  the post-END-TURN SHOP phase) byte-identical.
- **JOB 3 — BUNDLE + GUIDE AUDIT: complete + accurate.** `multiples-web.zip`:
  64 entries, `index.html` at the ROOT, **0 backslash entries** (all
  forward-slash — itch-ready), carries main.dart.wasm + flutter_bootstrap.js +
  manifest.json + assets/data/cards.json + canvaskit — it is the exact build
  verified running in Chrome. `MULTIPLES-v1.0.0.aab`: signed (`META-INF/UPLOAD.RSA`
  + `.SF`); keytool on the embedded cert = `CN=MULTIPLES`, SHA-256
  `9C:DD:BA:15…` — IDENTICAL to the APK upload cert. `KEYSTORE-BACKUP.txt`:
  passwords + alias + cert SHA-256 + the loud "lose it = can never update"
  warning + restore steps — accurate. `PUBLISH-GUIDE.md`: the GitHub push +
  Release + itch HTML5 (played-in-browser tick, 430×900 viewport,
  SharedArrayBuffer toggle ON, APK as a download) + README URL-paste steps all
  read correctly; the screenshot filenames it cites all EXIST in
  docs/screenshots/. README/LICENSE(MIT)/NOTICE read well for a public repo;
  the OFL fonts (VT323/Silkscreen/IBM Plex Mono) + original audio are credited;
  every README screenshot link resolves to a real file.
- **7 MUST-FIXES — ALL RESOLVED:** B1 web compiles **+ RUNS in a browser**
  (W1 compile, W3 in-browser play) ✓ · B2 release-signed (upload cert on APK+AAB,
  re-verified) ✓ · S1 launcher icon (adaptive `res/BW.xml`, shows on device) ✓ ·
  S2 label MULTIPLES (aapt) ✓ · S3 dark splash (#07090C, no white flash; web
  index + Android theme) ✓ · S4 docs (README/LICENSE/NOTICE) ✓ · S5 green test
  (deterministic autosave join; 763 + 96 green) ✓.
- **CLOSE:** engine 763 + app 96 green; engine + app analyzers "No issues found";
  `git status` clean (only the W3 verification artifacts added); keystore +
  key.properties confirmed gitignored AND untracked (ls-files empty).
- **NEXT — USER actions only (cannot be automated):** (1) create GitHub + itch.io
  accounts; (2) `git remote add origin … && git push -u origin main`; (3) cut the
  GitHub Release v1.0.0 and attach `MULTIPLES-v1.0.0.apk`; (4) create the itch.io
  HTML project, upload `multiples-web.zip` (tick "played in browser", viewport
  430×900, **SharedArrayBuffer ON**, mobile-friendly, fullscreen) + upload the
  APK as an Android download; (5) paste the real itch + Release URLs into the
  README's Play section and commit. Full click-path: PUBLISH-GUIDE.md.

## PUBLISH ROUND W2 — RELEASE SIGNING + REPRODUCIBLE WEB BUILD + PUBLISH BUNDLE
**Android release is now properly signed; the web build is reproducible via a
script + loud docs; the full GitHub/itch.io publish bundle is assembled in the
session outputs. engine 763 + app 96 green; both analyzers clean.**

- **B2 — RELEASE SIGNING (the W2 keystone).** Generated an upload keystore with
  keytool (`C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`):
  `upload-keystore.jks`, RSA 2048 / SHA384withRSA, alias `upload`, validity
  10000 days (→ 2053-10-25), DN `CN=MULTIPLES, O=MULTIPLES, C=US`,
  cert SHA-256 `9CDDBA1501B8B1D4…`. `app/android/key.properties`
  (storePassword/keyPassword/keyAlias=upload/storeFile=upload-keystore.jks)
  feeds `app/android/app/build.gradle.kts`: it reads `rootProject.file(...)` for
  both key.properties and the .jks (so the keystore lives at
  `app/android/upload-keystore.jks`), creates a `release` signingConfig when
  key.properties exists, and points the `release` buildType at it — FALLING BACK
  to debug signing only when key.properties is absent (a fresh clone / CI without
  the secret still compiles). **SECURITY:** both `upload-keystore.jks` AND
  `app/android/key.properties` are GITIGNORED (added explicit entries beside the
  existing `*.jks`); verified untracked via `git check-ignore` + `git ls-files`
  and confirmed `git status` showed ONLY .gitignore + build.gradle.kts before
  committing. Built `app-release.apk` (45.9MB) + `app-release.aab` (45.7MB);
  apksigner verify --print-certs confirms a SINGLE V2 signer with the UPLOAD cert
  (SHA-256 matches the keystore, DN CN=MULTIPLES) — NOT the Android debug cert.
  Keystore + passwords + restore steps backed up to the session outputs
  (KEYSTORE-BACKUP.txt + a copy of the .jks) with a LOUD "back this up or you can
  never update the app" warning.
- **WEB REPRODUCIBILITY — patch kept, automated, documented (no supported flag
  exists).** Verified against `flutter build web --help` (Flutter 3.44.1): there
  is NO `--no-js-fallback` / wasm-only flag; `--wasm` is documented as "with
  fallback to JavaScript" and always emits the dart2js config. So the W1 local
  flutter_tools patch (omits `JsCompilerConfig` under `--wasm` in the shared SDK
  `C:\src\flutter\…\commands\build_web.dart`) is KEPT and made reproducible:
  `app/tool/build_web.bat` detects the patch marker, applies it via
  `app/tool/apply_web_patch.ps1` (idempotent reversible regex replace) + deletes
  `flutter_tools.stamp` to force a snapshot rebuild if it had to patch, then runs
  `flutter build web --wasm --release --no-tree-shake-icons`. README "Building"
  documents the dependency LOUDLY and stresses the OUTPUT (`build/web`) is
  patch-INDEPENDENT — plain WASM + assets, runs on any static host; only
  PRODUCING the build needs the patch. Re-ran the build fresh: WASM-only,
  `main.dart.wasm` 1.85MB + `main.dart.mjs`, confirmed NO `main.dart.js` fallback.
- **PUBLISH BUNDLE (session outputs):** `MULTIPLES-v1.0.0.apk` (signed release),
  `MULTIPLES-v1.0.0.aab` (signed, future Play), `multiples-web.zip` (15.5MB —
  rebuilt with FORWARD-SLASH zip entries because Windows Compress-Archive emits
  backslashes itch.io rejects; `index.html` at the zip root, verified),
  `upload-keystore.jks`, `KEYSTORE-BACKUP.txt`, `release-title-verify.png`, and
  `PUBLISH-GUIDE.md` — the exact click-path for (a) `git remote add origin … &&
  git push -u origin main` (notes what's gitignored), (b) a GitHub Release
  v1.0.0 with the APK attached, (c) itch.io: Kind=HTML, upload the web zip +
  tick "played in the browser", viewport 430×900 portrait, mobile-friendly,
  fullscreen, **SharedArrayBuffer toggle ON** (Flutter WasmGC runs without it but
  the toggle adds the COOP/COEP cross-origin-isolation headers CanvasKit's faster
  path wants — and is the fix if the canvas ever blanks), upload the APK as an
  Android download, description from the README, screenshots from
  docs/screenshots/. README Play links are explicit PUBLISH-TODO placeholders
  (itch + GH Release) for the user to paste real URLs (+ a one-liner commit).
- **VERIFY (release build runs):** uninstalled the debug APK (signature mismatch)
  then `adb install -r` the release APK on Pixel_8 (already booted) — Success;
  monkey-launched → MainActivity focused; title screenshot
  (outputs/release-title-verify.png) shows the MULTIPLES wordmark, the tagline,
  the 14X button, NEW RUN/THE DESK/SETTINGS, and the new launcher icon renders.
  aapt2 badging confirms `application-label:'MULTIPLES'` + adaptive icon
  `res/BW.xml`. engine 763 + app 96 tests green; engine + app analyzers "No
  issues found".
- **Commits:** 0aa0859 (signing config) · e3c27ae (web build script + bundle
  docs) · + this STATE.
- **NEXT — USER actions (cannot be automated):** create GitHub + itch.io
  accounts; push the repo; cut the v1.0.0 GitHub Release with the APK; create the
  itch HTML project, upload the web zip + APK, set the viewport + SharedArrayBuffer
  toggle; paste the real itch + Release URLs into the README's Play section.
  **W3:** full Chrome visual smoke of build/web + a real-device APK install + the
  deep publish-readiness critic pass.

## PUBLISH ROUND W1 — WEB COMPILES + BUILDS; the 6 audit items fixed
**The app now `flutter build web`s (WASM) and the publish-blocking cleanup is cleared.
engine UNTOUCHED (763); app 92→96 green (4 new web-backend tests); analyzer clean.**

- **B1 — web save backend (the keystone).** `save_store.dart` no longer imports
  `dart:io`/`path_provider`; its I/O sits behind `SaveBackend` (lib/save_backend.dart) —
  opaque string blobs keyed `run`/`meta`/`meta.bak`. `save_backend_factory.dart` does the
  conditional export `export 'save_backend_io.dart' if (dart.library.js_interop)
  'save_backend_web.dart'`, so on web NO dart:io symbol is referenced. `IoSaveBackend`
  (native) = today's atomic temp+rename files; `WebSaveBackend` (web) = `shared_preferences`
  (already a dep) under namespaced keys `multiples.save.*`. The store keeps every docs/06
  rule (two-file split, .bak refresh-before-overwrite, the full loadRun recovery ladder,
  the serialized write-chain). `SaveStore.forDirectory(Object)` preserved for the existing
  native tests (delegates to the io factory; throws on web); added `SaveStore.forBackend`.
- **WEB SAVE PERSISTENCE design:** blobs are tiny JSON, so a KV store is right; each
  SaveBackend key → one SharedPreferences key (localStorage on web). No atomic rename on
  web (a per-key put is itself atomic; the store's torn-read → corrupt-recovery is the net).
- **S5 — racy test.** `GameController.debugSettled` exposes the last in-flight autosave
  Future (the store serializes writes, so awaiting the latest joins them all). The two save
  round-trip tests + the orphan-guard test await it instead of `Future.delayed(30ms)`.
  Product behavior unchanged; the suite is deterministic.
- **S1 icon / S2 label / S3 splash:** flutter_launcher_icons regenerated Android mipmaps +
  adaptive icon + web favicon/PWA icons from `assets/icon/app_icon_1024.png`; manifest label
  → MULTIPLES; launch_background → #07090C + centered icon, themes → Black base (no white
  flash); web index.html/manifest themed #07090C, title MULTIPLES, tagline as description.
- **S4 docs/license:** root README (pitch, tagline, screenshots, how-to-play, build cmds,
  play/APK link PLACEHOLDERS, tech stack, design credit); app/README replaced (template
  gone); MIT LICENSE (covers code; note re-license-able); NOTICE (OFL fonts VT323/Silkscreen/
  IBM Plex Mono + original-audio note).
- **WEB BUILD = WASM-ONLY.** The engine's SplitMix64 + fixed-point sentinels are 64-bit
  wrapping ints that dart2js literally cannot represent (rng.dart says so) — so JS-web is
  not a target. `flutter build web --wasm --release --no-tree-shake-icons` → `√ Built
  build\web` (main.dart.wasm 1.85MB + assets/data/cards.json + 18 audio OGG + 5 fonts).
  Flutter 3.44's `--wasm` ALSO emits a dart2js fallback with no flag to skip it; that
  fallback can't compile the engine, so it's dropped via a DOCUMENTED, REVERSIBLE local
  patch to `C:\src\flutter\...\commands\build_web.dart` (snapshot rebuilt). `--no-tree-shake-
  icons` is required because there's no dart2js kernel to subset in a wasm-only build.
  SERVE SMOKE (python http.server): index, main.dart.wasm, main.dart.mjs, flutter_bootstrap.js,
  flutter.js, manifest.json, favicon.png, assets/assets/data/cards.json, …/fonts/VT323-Regular.ttf,
  …/audio/ all returned HTTP 200.
- **Commits:** 239b1c9 (B1+S5) · 19da84a (web build + S1/S2/S3) · + S4 + this STATE.
- **DEFERRED → W2:** real Android release signing (build.gradle.kts is still debug-signed;
  needs an upload keystore + key.properties + an AAB). The README play/APK links are
  PLACEHOLDERS pending the itch.io/GitHub URLs. **W3:** full Chrome visual smoke of build/web,
  the itch.io HTML5 upload (zip build/web), APK on a device. **CAVEAT:** the wasm-only build
  depends on the local flutter_tools patch — a clean/CI machine can't reproduce it until
  Flutter ships a supported no-JS-fallback option.

## ROUND 21 — CRITIC / FINISHER: POLISH PUSH COMPLETE, BUILD EMULATOR-VERIFIED (no fixes needed)
**Adversarial static audit of R17→R20b + a full emulator run on Pixel_8 (debug APK).
Verdict: ZERO correctness defects, ZERO emulator defects — the polish arc landed clean.
No surgical fixes were required; no guard touched. This is a docs-only close.**

- **STATE RECONCILE:** STATE.md was already current through R20b (round summaries are newest-first
  at the top); HEAD de5fb68 matches. This R21 entry is the only addition.
- **R20b POOL (verified by code-read + targeted tests):** `cardInUnlockedPool` keys off the FROZEN
  per-run `unlockedCardIds`/`unlockedSectors` (seated at initRun, preserved by copyWith, NEVER
  written by any action/step — invariant whitelists them as constant access-state paths like
  backgroundId). flatten serializes them; the run save startConfig carries them (serialize.dart
  748-760) and reload restores them (868-885) so replayRun rebuilds the identical pool.
  engineSchemaVersion = 10 (model.dart); golden v10 active, v1-v9 sealed/retired; cursor still 28.
  migrate: meta 9→10 pure bump, ANY v<10 RUN abandoned (stream moved). SPIN_OFF
  (`_playConsumable` early-return: live-mark equity proceeds, frees slot, emits exitRealized) and
  EARN_OUT (registers a real PCT_EBITDA ScheduledCost w/ roundsLeft + pctEbitdaBp; operate step 3c
  charges −trunc(ebitda×bp/10000) each round, orphan-safe) are REAL resolvers, not stubs — closes
  the long-standing EARN_OUT-bases deferral. Only balance change is kRecapPctBp 0.16→0.20 (the
  named greed-death dial; documented re-sweep). The 3 sim bands hold (sim_test green in the 763).
- **R18 AUDIO (verified by code-read + the fake-player tests):** AudioController is a PURE UI
  listener (no engine import; takes event-type-NAME strings — zero economic coupling).
  audio.dart's BGM-mood + SFX maps are BYTE-FAITHFUL to docs/08 (5 moods, 13 SFX, identical asset
  paths/triggers; ducking on exactly arbitrage/tier-clear/bankruptcy). Mute/music/sfx gate
  playback; crossfade + ducking + lifecycle pause/resume + dispose (cancels the duck timer, frees
  every channel). All 18 .ogg bundled (pubspec `assets/audio/`), confirmed on disk (689,495 bytes
  total, ~673KB). audio_test (22 cases) asserts the right asset per mood/SFX; audio_wiring_test
  drives the LIVE widget tree and asserts the exact asset fires per event (sfx_ticket on the deal,
  sfx_key on END TURN/CONTINUE, sfx_select+sfx_napkin on a ticket tap, sfx_arbitrage WITH BGM
  ducked to 0.40 on EXECUTE, sfx_nw_surge on BOOK IT) — this is the audio verification method,
  since the emulator runs -no-audio.
- **R19 JUICE (verified by code-read + r19_juice_test):** FloatingDeltaBox fires on EVERY change
  up OR down; wired to CASH + all 4 levers via `_Lever` (= 5 stats; "R14→R19 extended to EVERY
  stat"). DealIn stagger + AttractPulse (post-frame-deferred loop to avoid fake-async asserts) +
  MK stamp on live tier-clear + CrtScreenSwitcher channel-change (main.dart, AnimatedSwitcher
  w/ per-screen ValueKeys). EVERY animation runs off an AnimationController (juice.dart header:
  no Timer/Future.delayed), every State disposes its controller — the juice test's CRT case
  asserts "no orphaned controllers". dart:math is app-layer-only (noted; engine still bans it).
- **R20 SETTINGS/TUTORIAL (verified by code-read + settings_test/tutorial_test):** settings drive
  the AudioController setters + persist (AppSettingsController); the hapticsOn flag gates
  safeHaptic* via setHapticsEnabledGate; tutorial is first-run-only (persisted tutorialSeen),
  skippable, non-destructive (overlay), re-showable (REPLAY TUTORIAL), in-voice, gated to live
  beats. Pure UI, no game logic.
- **EMULATOR RUN (Pixel_8, 1080x2400, debug APK `√ Built app-debug.apk`, pm-clear fresh player;
  screenshots committed docs/screenshots/r21-*.png):**
  (a) TITLE — MULTIPLES + tagline + the 14X hero; NEW RUN / THE DESK / **SETTINGS (gear)** all
      present; fresh player shows NO CONTINUE (correct).
  (b) SETTINGS — AUDIO (MASTER MUTE/MUSIC/SOUND FX), FEEL (HAPTICS), TUTORIAL (REPLAY), DANGER
      (WIPE SAVE), ABOUT (v1.0.0). Toggled MASTER MUTE ON → it correctly cascaded MUSIC+SOUND FX
      to a dimmed OFF (live state proof), then toggled back.
  (c) FRESH NEW RUN → FIRST-RUN TUTORIAL fired: step 1 "REAL vs PAPER" spotlighting the CASH vs
      NET WORTH boxes, step 2 "VALUE IS A PRODUCT" spotlighting the EBITDA×MULT levers, step 3
      "THE ADD-ON" on the first add-on ticket, step 4 "THAT GAP" firing right after the arbitrage
      was booked (the arbitrageSeen beat). TAP TO CONTINUE + SKIP both present; finishes → seen.
  (d) PLAYED 2 ROUNDS — saw floating stat deltas (EBITDA +$1,200/+$2,160 green; MULT +0.7x then
      −1.3x red on a down-drift round — both directions juice), the digest "THE YEAR PASSED",
      the SHOP (DOWN ROUND / SECONDARY SALE / MARKET READ — full R20b pool visible), the
      DEADLINE CHECK (NEED 1.37x/RD · AT 1.20x in red = behind-pace tension state). CRT
      scanline/phosphor artifacts visible on the panels.
  (e) ARBITRAGE (ADD-ON→INSPECT→EXECUTE) — the "✱✱✱ MULTIPLE ARBITRAGE ✱✱✱" flash, "$1,800 @
      2.7x → 6.7x", EBITDA count-up 7,200→9,360, ENT VALUE →$63,320, the big green +$7,178 NW
      surge, "THAT'S ALLOWED?!" + BOOK IT. NO broken card render at any point (T1, all card types).
- **AUDIO VERIFICATION VERDICT:** PASS by code-read of the docs/08-faithful hooks + the fake-player
  unit/wiring tests that assert the exact asset per event through the live widget tree. (Emulator
  is -no-audio by design; not heard.)
- **FINAL COUNTS:** engine **763** tests + analyzer "No issues found!"; app **92** tests +
  analyzer "No issues found!". Debug APK builds clean (non-fatal audioplayers KGP deprecation
  warning only). Branch `main`, clean tree.
- **HONEST WHAT REMAINS (carried, not regressions):** (1) iOS — never started (Android-first).
  (2) Per-add-on SPIN_OFF ledger — v1 add-ons merge destructively, so spin-off is whole-venture
  only (the doc's add-on-ledger form needs a schema that tracks add-on provenance). (3) The unlock
  TREE is surfaced on THE DESK but the unlock-payout depth + rep thresholds are still thin/partly
  unset tuning dials in economy-model.json. (4) TakeDebt cold-market gate + partner fixed-cost
  card face await content authoring the flagged cards.
- **OVERALL VERDICT:** YES — a feature-complete, polished, Android-shippable game a user can fairly
  judge: full T1→T5 loop, save/resume, meta/Desk, the full card pool in play, audio, animation/
  juice, settings, and a teach-by-play tutorial — all emulator-verified, all guards intact.
  Commit: `docs: STATE — polish push complete, R21 build verified`.

## ROUND 20b — DRAW-POOL KEYSTONE (LANDED; engine schema 10 / golden v10; engine 763, app 92)
- **THE POOL PREDICATE (dealflow.cardInUnlockedPool — the v10 contract):** a card is in a
  run's draw pool iff `id ∈ run.unlockedCardIds AND tierGate <= tier AND (sector == null OR
  sector ∈ run.unlockedSectors)` plus the per-pool type/slot rules (hand = venture/addon/partner
  with the v5 dead-draw venture filter at full slots; shop = financing/consumable; event = events).
  The intersection of the CROSS-run unlock set and the IN-run tier/sector gates (GDD §Q7). Pools now
  select from `content.cards` ∩ that predicate, in CONTENT FILE ORDER (was `content.verticalSlice`).
- **WHAT NOW DRAWS THAT DIDN'T:** the 14 held-out cards once their gate/sector is reached —
  VEN_SW_PLATFORM, ADD_RET_STORES, ADD_IND_SUPPLIER, PRT_COO_FIXED, PRT_GROWTH_HACKER,
  FIN_GROWTH_RAISE, FIN_LBO_LOAN ($20M), FIN_REFI, EVT_VIRAL_QUARTER (gate-1!), EVT_SUPPLY_SHOCK,
  PLY_TENDER, PLY_ASSET_STRIP, PLY_SPIN_OFF, PLY_EARN_OUT. A default/new-player run still plays the
  base curriculum (the 19-card slice = `kDefaultUnlockedCardIds`) at T1; the §Q7 ladder widens it.
- **FROZEN per-run snapshot (schemaVersion 10):** GameState gained `unlockedCardIds`/`unlockedSectors`,
  taken from MetaState at initRun (`runUnlockedCardIds(meta, content)` = base ∪ meta.unlockedCards),
  so the legal pool is FIXED at run start and replay-stable. flatten() serializes them
  (indexed/ordered); the run save's startConfig carries them so replayRun rebuilds the same pool;
  invariant whitelists them as frozen access-state paths (never written by any action/step). App:
  controller._startRun sources them from the live meta; resume restores them; save_store.writeRun
  forwards them.
- **SPIN_OFF + EARN_OUT resolvers (doc 02 §3.6; spin_off_earn_out_test, 8 tests):** PLY_SPIN_OFF splits
  the target venture back out at its CURRENT live mark (no offer haircut / hot window — locks value),
  banks `trunc((EV_live − netDebt) × own / 10000)`, removes it (frees the slot); the 300k fee is the
  shop-buy cost (purchase-mirror stripped, like HOT_WINDOW). Whole-venture form — the doc's add-on-
  ledger form is unimplementable in v1 (add-ons merge destructively; R21+ could add a ledger).
  PLY_EARN_OUT lands its +500k EBITDA NOW ($0 down) and pushes a non-recurring PCT_EBITDA
  ScheduledCost (widened with `roundsLeft` countdown + `pctEbitdaBp`): OPERATE step 3c charges
  `−trunc(target.ebitda × kEarnOutPctBp/10000)` each round for kEarnOutRounds (2500bp / 4 rounds —
  tuning dials), then drops the entry; an orphaned entry (its venture exited) dies without firing.
- **SCHEMA 10 + GOLDEN v10:** the locked version-bump procedure. v9 sealed in place + retired; new
  replay_seed42_v10. The v10 script runs with the full unlock set so the EVENT pool holds the gate-1
  EVT_VIRAL_QUARTER (the keystone's newly-drawable card). Cursor STILL 28 (the seed-42 event roll
  still misses → no pick draw), cash/ebitda byte-identical to v9 — the bump is the moved pool INDICES
  + the widened state (unlockedCardIds.*/unlockedSectors.*), not the draw COUNT. migrate: 9→10 meta
  step (pure bump — MetaState unchanged); a v9 run is ABANDONED (stream moved).
- **HARNESS RE-SWEEP (the critical balance answer — FULL pool active, sim.dart inits with the full
  unlock set):** N=2000 headline:
  | policy | win | bankruptcy | merged/exited/hired |
  |--------|-----|------------|---------------------|
  | FLOOR  | 33.8% | 0.3% | 0/0/0 |
  | GREEDY | 36.1% | 9.2% | 0/0/0 |
  | SMART  | 57.6% | 0.0% | 99.5/45.4/100 |
  DID BALANCE HOLD? YES, after ONE dial. The widened SHOP pool DILUTED the recap/bridge cards, so
  greedy couldn't lever as fast and bankruptcy fell to 5.2% (below the [8,12]% band — greed stopped
  being fatal). **kRecapPctBp re-tuned 0.16 → 0.20** (the named greed-death dial, dealflow.dart; still
  under the R12-retired 0.30) restored greedy bankruptcy to band (10.7% N=400 / 9.2% N=2000) while the
  prudent floor (recaps only to 3.0x behind a max-crunch buffer) stayed 0.0–0.3%. The recap re-tune
  does NOT move golden v10 (the seed-42 script plays no recap). SMART win climbed (the full toolkit —
  more venture re-founds for the exit cycle, asset-strip liquidity) so its measured-reality band was
  re-pinned [42,56] → [42,58] (N=400 54.7%, N=2000 57.6%; the header sanctions re-pinning WITH a
  harness change). FLOOR win [25,42] and GREEDY bankruptcy [8,12] HOLD; dead-hand 0.0%, ≥3.5 playable.
- **CONTENT LINTS / 3-COPY SYNC:** green, untouched. The vertical-slice concept (doc 04 §3 /
  content_lint lint 3) is UNCHANGED in meaning — it IS the T1 default-unlock curriculum
  (`inVerticalSlice` == `kDefaultUnlockedCardIds`); the keystone widened the DRAW pool, not the
  slice definition, so the lint stays authoritative as-is.
- **VERIFY:** engine 752 → 763 (added: spin_off_earn_out 8, golden FULL-pool probe 1, v9-retirement
  block 2; net +11 with the v10 contract test replacing the v9 one); app STILL 92 (data-driven — every
  new card is an existing render type, no widget change); analyzer "No issues found" (engine + app).
  Commits: f3908f2 (engine keystone — schema 10/golden v10/resolvers/sweep) / e416bfa (app wiring) / +
  this STATE. NO UI follow-up needed for rendering; R21 (critic) could add the unlock-tree affordance +
  a per-add-on ledger so SPIN_OFF can split a single bolt-on (the doc's preferred form).

## ROUND 20 — SETTINGS SCREEN + FIRST-RUN TUTORIAL + HAPTICS FLAG (LANDED; app-side only, engine UNTOUCHED — 752 still)
- **SETTINGS SCREEN (caca797; lib/screens/settings_screen.dart — terminal skin):** MASTER MUTE / MUSIC /
  SOUND FX toggles drive the R18 `AudioController.setMasterMuted/setMusicOn/setSfxOn` (which persist via
  the audio settings store) + apply LIVE; a HAPTICS toggle (FEEL section); a REPLAY TUTORIAL key (clears
  the seen flag → fires on next NEW RUN); a DANGER `WIPE SAVE` with an in-screen confirm (ERASE
  EVERYTHING? → WIPE FOR GOOD → "SAVE WIPED.") calling `SaveStore.wipeSave` (deletes run.json + meta +
  .bak); an ABOUT footer (version `MULTIPLES MK·I · v1.0.0`). Music/SFX rows disable when master-muted.
  Reachable from the TITLE (a `SETTINGS` gear chunky key in the stack) and THE DESK (a `SET` gear beside
  START RUN). Pure UI/prefs — no engine math. The gear only shows when an AudioController is wired (so
  store-less smoke tests don't surface it).
- **HAPTICS FLAG WIRING:** `widgets/juice.dart` safeHaptic{Heavy,Light} (the surge/flash/exit/tier-stamp
  beats) now gate on a module-level `_hapticsEnabled` flag + fire through an injectable `HapticSink`
  (production = HapticFeedback; tests swap a recording sink). `AppSettingsController` (lib/settings.dart,
  persisted via `shared_preferences` SharedPrefsAppSettingsStore in audio_backend.dart) drives the gate
  on load + every toggle; default ON. The 5 call sites stay one-liners (no per-site threading). Pinned:
  haptics-OFF → the sink records NOTHING (settings_test).
- **FIRST-RUN TUTORIAL (caca797; lib/tutorial.dart + screens/tutorial_overlay.dart):** teach-by-play, NOT
  a wall of text (docs/05 / design §Q3 "show the chips, hide the wisdom"). 4-beat script, each landing on
  a live moment the player is already looking at: (1) CASH (REAL/solid) vs NET WORTH (PAPER/dashed) —
  "CASH is yours. NET WORTH is a promise."; (2) the EBITDA×MULT levers — "value is a product"; (3) the
  first ADD-ON ticket — "buy cheap, fold it in, watch it revalue at YOUR multiple"; (4) after the first
  arbitrage flash dismisses — "that gap is free money. that's the game." Each = a dim-everything-but-the-
  target spotlight (a cut-out painter over a GlobalKey-resolved rect, blue ring + callout that flips to
  the clear half) + one terse line + TAP TO CONTINUE; a SKIP TUTORIAL key is always reachable.
  NON-DESTRUCTIVE: only shows in ACT with no flash/digest/deadline panel up (never covers a real beat),
  and the overlay's tap only advances — the keys beneath are covered, never fired through. `TutorialController`
  (a step is surfaced only once its TRIGGER fires — the run screen reports actReady / addonInHand /
  arbitrageSeen off the live state). Fires exactly ONCE on the very first NEW RUN ever (persisted
  `tutorialSeen`); finish OR skip latches it seen. Re-showable from SETTINGS. The store-less test fallback
  defaults tutorialSeen=TRUE so existing widget tests don't trip the overlay (a tutorial test injects
  tutorialSeen:false).
- **TESTS (ec0f1c8):** 14 new (78→92). settings_test (8): AppSettingsController persist + the live gate;
  haptics-OFF suppresses the sink; the SETTINGS screen toggles drive the audio setters + the haptics flag;
  REPLAY clears seen; WIPE confirms→fires. tutorial_test (6): TutorialController gating/advance/skip (unit)
  + the first-run overlay shows once through the REAL run screen, walks steps, SKIP/finish marks seen, a
  returning player sees nothing. Seed 2; no pumpAndSettle (explicit pump(Duration); no leaked timers).
- **VERIFY:** analyzer "No issues found"; app 92 tests green; `build apk --debug` → `√ Built
  app-debug.apk` (the audioplayers KGP warning is pre-existing + non-fatal). Engine UNTOUCHED (no engine
  run by design — pure UI/prefs, no schema/golden move). HAND TO R20b: card-pool (the held-out cards into
  the draw pool + the harness re-band). R21: critic.

## ROUND 19 — FULL ANIMATION / JUICE PASS (LANDED; app-side only, engine UNTOUCHED — 752 still)
- **FLOATING DELTAS ON EVERY STAT (82b275e; item 1):** the R14 CASH-only FloatingDeltaBox now wraps
  ALL four levers (EBITDA/MULT/DEBT/OWN) — each pops 1.3× (bible) + floats a +/- chip up-and-fade on
  every value change (green up / red down, keyed per lever for tests). The round-snapshot change chip
  beneath tick-pops 1.3× (mockup `.lv.tick`/tickpop .5s) the frame its signed delta moves (_LeverChip).
  NW keeps the up-only green surge; CASH keeps its gentle 1.12 pop. FloatingDeltaBox gained
  peak/floatFontSize/popAlignment/deltaKey knobs (CASH behavior unchanged). Skin-only — every floated
  magnitude is an engine value through an engine formatter; the float color follows the SAME raw
  signed-delta coloring as the existing round chip (a debt RISE reads green — the established lever
  convention, no per-stat semantic recolor). Also: digest EXIT-OFFER row now shows the venture
  displayName (QUANTA…) via `targetVenture(id)?.displayName`, not the raw "V1" (R16 punch #7).
- **TICKET DEAL-IN + ATTRACT-PULSE (e3a1508; item 2):** new DealIn + AttractPulse in widgets/juice.dart.
  The blotter no longer hard-appears — each ticket slides in from the right + fades up ~260ms,
  staggered ~55ms/row (mount-driven: a fresh hand → new ids → new keys → remount deals in; a SELECT
  keeps the keys → no replay). The SUGGESTED ticket (first ADD-ON, else the EXIT OFFER) breathes a blue
  attract-pulse (mockup `.ticket.attract` 1.4s; bible idle list) while the blotter is idle; a
  select/aim/out-of-plays drops it. AttractPulse defers its repeat() to a post-frame callback (never
  started synchronously during mount) to dodge fake-async's `elapsedInSeconds>=0` assertion when
  several loops mount in one pump.
- **CRT SCREEN TRANSITIONS (38ded96; item 4):** CrtScreenSwitcher + _CrtSweep in theme.dart replace
  the shell's hard title↔desk↔run cuts with a ~300ms CRT channel-change — fade-through-black + a bright
  accent scanline sweeping across, incoming screen fades up under a sweep that lifts off. Built on
  AnimatedSwitcher (finite per-swap controller auto-disposed; incoming screen in the tree from frame
  one so finders resolve immediately). main.dart keys each top-level screen + the boot gate.
- **RICHER ARBITRAGE FLASH (ed5d62b; item 5):** the spark burst scatters with per-particle reach +
  speed jitter, a gravity arc, varied 4..9 sizes, and mixes squares + diamonds (SparkBurst is shared,
  so victory gets it too). The +$accretion headline pop gains a chromatic-aberration flare — two
  low-alpha warm/cool echoes split widest mid-pop and converge as it settles (crisp green number reads
  sharp; the split is garnish behind it). The EXIT paper→cash COLLAPSE (translateX+scale .08+fade into
  the solid CASH box, shake+haptic at landing) was already faithful from R8 — verified, unchanged.
- **MK STAMP — VERIFIED LIVE (item 3):** the nameplate stamp (shrink→1.5× green-flash→settle, mockup
  `mkstamp`) was already wired into the LIVE _Nameplate (didUpdateWidget on `s.tier` increase, fed
  `s.won?5:s.tier`) — the R19 test PROVES it fires on a tier-clear (debugSetState 1→2: mark relabels
  MK·I→MK·II, scale leaves rest + overshoots ~1.5× then settles). Not just the panel.
- **IDLE LIFE (item 6):** CRT flicker + cursor blink + news tape are live (theme.dart) — that's the
  bible's ≤3-element idle cap, so NO ticket idle-bob was added (would be a 4th loop); market-needle is
  a static segbar marker by design. The new attract-pulse is a per-ticket idle highlight, not a global
  loop, so it doesn't count against the cap.
- **TESTS (4000781; item 8):** 6 widget tests in test/r19_juice_test.dart (seed 2, no pumpAndSettle —
  explicit pump(Duration) steps; no leaked timers): lever float fires+clears on an EBITDA move; 5
  FloatingDeltaBoxes in the HUD; the deal-in completes (tickets settle fully opaque); the suggested
  ADD-ON pulses + a select stops it; the MK stamp fires on tier-clear; the CRT transition sweeps
  title→run + settles clean (no orphaned ticker). All controllers initState-created + disposed.
- **VERIFY:** analyzer "No issues found"; app 78 tests green; `build apk --debug` → `√ Built
  app-debug.apk` (152MB). Engine untouched (no engine run by design). HAND TO R20: settings/tutorial
  screen — the audio toggle seams (setMasterMuted/setMusicOn/setSfxOn) are ready from R18. R21: critic.

## ROUND 18 — AUDIO SYSTEM (LANDED; app-side only, engine untouched)
- **PACKAGE (6e21bf4):** `audioplayers ^6.6.0` (resolved 6.7.1) — the common choice for "one looping
  BGM channel + many simultaneous SFX": each AudioPlayer is an independent channel, so the SFX pool
  and the BGM never cut each other. `shared_preferences ^2.5.5` persists the settings flags. pubspec
  `flutter:assets` now bundles `assets/audio/` (the 18 chiptune OGG, all present). pub get clean
  (path_provider constraint compatible).
- **AudioController (939bc8a; lib/audio.dart — PLUGIN-FREE):** one looping BGM player +
  `setMood(AudioMood)` crossfading ~400ms (down-ramp → source-swap → up-ramp; **no-op on the live
  mood — the loop never restarts**); a round-robin SFX **pool** (default 4) so overlapping one-shots
  don't cut each other; **DUCKING** (BGM → ~40% for ~700ms under arbitrage/tier-clear/bankruptcy,
  then restore via a token-guarded timer); mute logic (master/music/sfx, each gating its channel,
  re-applied live); pause/resume lifecycle. The audioplayers plugin + shared_preferences are held
  behind injectable seams (`AudioBackend`/`AudioPlayerHandle`/`AudioSettingsStore`) — production
  wiring is `lib/audio_backend.dart` (`AudioplayersBackend` + `SharedPrefsAudioSettingsStore`,
  error-guarded so audio never crashes the game); headless tests inject a recording FAKE.
- **THE HOOKS (d78cc8b):** thin listener calls, no logic leaves the engine. **main.dart** builds the
  controller at boot, pumps title/Desk BGM to the title mood, and hooks the existing
  WidgetsBindingObserver (pause on paused/inactive, resume on resumed). **run_screen.dart** is the
  central ROUTER: BGM mood follows the live phase (ACT/digest/shop → act; deadline panel
  behind-pace OR final round / endless → tension; runOver → autopsy|victory). SFX per docs/08:
  MULTIPLE_ARBITRAGE→arbitrage(+duck), NW surge→nw_surge (up-only, deferred behind the flash to
  BOOK IT / CASHED OUT), EXIT_REALIZED→exit_cash, TIER_CLEARED/won→tier_clear,
  BANKRUPTCY/missedDeadline→bankruptcy, ACTION_REJECTED→error, dilution→raise,
  partner-commit→partner (card TYPE at dispatch — engine emits no partner event), hand
  dealt→ticket, napkin open→napkin, reroll→reroll, selects→select, chunky keys→key. The
  event→sfx map is a pure name-keyed switch (`audio.dart sfxForEventName`) so audio.dart stays
  engine-import-free. Small render-only seams added: `controller.lastDeadlineEvents`,
  `SurgeController.hasDeferredRise`, `DigestOverlay.onContinue`.
- **SETTINGS SEAM FOR R20:** the three flags live in `AudioSettings` (default all-ON), are persisted
  through `AudioSettingsStore` (shared_preferences keys `audio.masterMuted|musicOn|sfxOn`), and are
  toggled via `AudioController.setMasterMuted/setMusicOn/setSfxOn` (each writes through + re-applies
  live). **R20 just builds the SCREEN that drives those three setters** — the flags, persistence,
  and live mute behavior already work and are tested.
- **TESTS:** 17 AudioController unit tests (fake backend: crossfade+dedupe, SFX round-robin, mute
  suppression, ducking restore, lifecycle, persistence) + 5 widget wiring tests (REAL screens + REAL
  controller over the FAKE backend: mood-follows-screen, opening hand→ticket, CONTINUE→key, ticket
  tap→select+napkin, ADD-ON EXECUTE→arbitrage(+duck)→BOOK IT→nw_surge, END TURN→key). Shared fakes
  in test/audio_fakes.dart. App suite 72 green; engine untouched (752, not re-run by design).
- **NO MANIFEST DEVIATION.** All 5 BGM moods + 13 SFX wired exactly per docs/08. Note: the manifest's
  raise trigger is realized via the engine `dilution` event (RaiseEquity's signal); partner via the
  card type at commit (no dedicated engine event) — both faithful to the trigger table.

## ROUND 17 — CONTENT + META DEPTH (part 1 LANDED; the draw-pool wiring DEFERRED to R18)
- **CONTENT-SYNC FIX (39ea41c):** the two build copies of cards.json had drifted to CRLF (431 CRs, 17969 bytes) vs data/'s LF (17538) — content_sync_test (audit M1) + content_test were RED at baseline. Re-synced both as exact LF byte-copies. NOTE: git autocrlf warned it may re-CRLF on checkout — if the sync test goes red again, re-copy from data/ (consider a .gitattributes `*.json -text` pin).
- **SECTORS 5-6 (5a36db0; GDD §8 Q6 / doc 04):** `Sector` enum APPENDED `consumer`, `media` (at the END — existing `.index` values unchanged, so flatten/golden replay contract preserved, NO schema bump). sectorFromJson/sectorToJson/sectorVolMilli(operate)/sectorNormMilli(meta)/ventureDisplayName pools all extended. economy-model.json sectors[]: CONSUMER 6x / vol 0.15 (brand-y mid, steady); MEDIA 16x / vol 0.35 (SOFTWARE++, whips hardest). All 3 content copies synced. content_test pins 6 sectors + bands. **Reputation-GATED** (kPostLaunchSectors, unlock only on beating the game; NOT in the base draw pool).
- **META UNLOCK LADDER (5a36db0; GDD §Q7 "access never advantage; unlock order == curriculum order"):** pure meta.dart — `applyUnlocks(meta, gameBeaten:)` derives the unlock sets from progress: reach T2 -> raise/operating deck (kTier2UnlockCards: VEN_SW_PLATFORM, ADD_RET_STORES, PRT_COO_FIXED, PRT_GROWTH_HACKER, FIN_GROWTH_RAISE, EVT_SUPPLY_SHOCK, PLY_TENDER, PLY_ASSET_STRIP) + OPERATOR bg; T3 -> exit/empire deck (kTier3UnlockCards: ADD_IND_SUPPLIER, FIN_REFI, PLY_SPIN_OFF, PLY_EARN_OUT) + VC_DARLING bg; T4 -> acquirer/LBO deck (kTier4UnlockCards: FIN_LBO_LOAN) + DEALMAKER bg; BEAT GAME -> Endless + hard modes (kBeatGameHardModes: IRONMAN/COLD_OPEN/NO_CREDIT) + the 2 post-launch sectors. Additive + idempotent (access never regresses; gameBeaten persistent via `endlessUnlocked(meta)`). Stable deterministic ordering for save round-trip. Cosmetic title ladder `kTitleLadder` (ANALYST..KINGMAKER) keyed to metaLevel via `titlesForLevel`. **settleRun now CALLS applyUnlocks** after the progress update; double-settle guard still a clean no-op. 13 new tests.
- **PRT_COO_FIXED salary (a91cec4; doc 04 §1 operating leverage):** actionForCard DERIVES the recurring fixed salary id-keyed (the v1 schema has no explicit fixed-cost face) = `kCooFixedCostBp` (60%) of the +EBITDA -> a -$270k/round recurring ScheduledCost (OPERATE step 3c). Lethal when earnings thin (can push cash negative mid-OPERATE; F6 still verdicts at step 6). Other partners still map 0. The HirePartner fixedCost channel (live since R10) now has its first real consumer.
- **ENDLESS depth (a91cec4; item 4):** the R15 geometric-ante escalation (entry x 1.5^ante, satMul-saturated, fails-out MISSED_DEADLINE, never wins) already runs a real loop with full escalation/fail-out/mid-ante coverage. Added the two pins the model lacked: TERMINATION (bar compounds monotonically -> outruns any finite NW in bounded antes; the run cannot go forever) + CAP (satMul holds the bar from int64 overflow even 200 antes deep; degenerate entry -> 0 bar).
- **R17 DEFERRED to R18 (the keystone that ACTIVATES the above content):** the 14 held-out cards exist in cards.json + are grouped into the unlock decks, but the engine DRAW POOLS (dealflow.dart handPool/shopPool/eventPool) still key off `content.verticalSlice` — so the held-out cards are AUTHORED + unlock-tracked but NOT YET DRAWN. Wiring them needs a per-run frozen `unlockedCardIds` config threaded onto GameState (like backgroundId; §7-exempt access state) -> handPool/shopPool/eventPool widen the pool to slice ∪ unlocked -> runOperate/endTurn/Reroll/serialize/flatten/invariant updated. This MOVES THE STREAM (the pool grows) = golden v10 + schemaVersion 10 + a harness re-validation pass (the new cards' magnitudes — esp. FIN_LBO_LOAN $20M leverage, PLY_DIVIDEND_RECAP/recap, PLY_ASSET_STRIP — must be swept for the [25,42]%/[8,12]% bands; tune any warper, content dial). Also still minimal: PLY_SPIN_OFF (slot-free + add-on-share resolver) + PLY_EARN_OUT (scheduled PCT drag + roundsLeft countdown) need their real resolvers (today they'd map as raw-delta PlayConsumables — faithful enough to draw, but the slot-free / scheduled semantics are unimplemented); the content_lint vertical-slice pin (doc 04 §3) stays authoritative — revisit when the slice definition changes. App: the Desk already reads unlock counts (cards x/35, sectors x/6) off MetaState, so the new unlocks surface automatically; a future app round can add the unlock-tree affordance + post-launch-sector run setup.

## Current position
- **Phase 0 (toolchain): DONE.** git repo on `main`; design corpus committed; Dart 3.12.1 installed
  (`C:\src\dart-sdk` + `~/bin/dart` shim); engine package skeleton + smoke test green.
- **Phase 1 (engine action layer): COMPLETE** on branch `feat/phase-0-toolchain`. All 11 actions
  resolve, §7 invariant + golden replay contract + purity guards lock it down.
- **Phase 2 (content pipeline): AUDITED + CLOSED** (round-2 adversarial audit landed as e1561a8;
  282 tests passing, analyzer clean). Audit verified: generated content.g.dart is purity-clean and
  the guard scans lib/ recursively (now non-vacuously pinned to include content.dart + content.g.dart);
  the decimal-text claim holds (the jsonDecode double is only ever stringified — edge tests pin
  0.3 == 0.30, exponent rejection, scale-exactness rejection); the 19-card slice matches doc 04 §3;
  CI ok by inspection. Added: lint 4 (doc 04 §0 directionality signs — face debt lands as +netDebt,
  financing debt pays +cash, dilution never pairs with +own, consumable own == -dilution face,
  financing raises author no own delta, purchase cash mirror, ventures own 10000) with named
  predicates + planted-violation tests for every lint incl. the MEMO ban; raw-integer cross-check
  pins (PLY_BRIDGE_LOAN 1.15x netDebt, FIN_LBO_LOAN tier 4); `ContentDb.verticalSlice` getter for
  Phase 3. Non-lintable cases (resolver-computed proceeds, consumable cost-vs-cash) documented in
  content_lint_test.dart's header.
- **Phase 3 round 1 (OPERATE/market layer): LANDED.** The engine's first real RNG draws;
  **schemaVersion bumped 1 -> 2** per the locked docs/03 §6 procedure. 347 tests, analyzer clean.
  - New: `lib/operate.dart` (`runOperate(state, rng) -> OperateResult`) runs doc 01 §6.1's exact
    order: market roll -> per-venture drift -> cash yield -> neglect decay -> events HOOK (0 draws,
    documented) -> interest/F6. Survival lands phase=ACT + playsRemaining=playsPerRound(tier)
    2/3/3/4/4; bankruptcy lands runOver + negative cash (never clamped) + BANKRUPTCY event.
  - **DRAW-ORDER CONTRACT (operate.dart header is authoritative):** per OPERATE:
    [boundary only: nextInt(100) transition bucket 18 hot/18 cold/64 neutral, then nextInt(2)
    duration 2..3] -> nextInt(10000) live-rate position (AFTER transition; new temp's rateMul
    90/100/180 over base 800+span*u~/10000) -> per venture IN LIST ORDER: nextInt(1000) u1,
    nextInt(1000) u2 (tri = u1+u2-1000 permille). Total = (2 if boundary) + 1 + 2*ventures.
    Drift delta = one final division: (multiple * (stateFactorMilli*(1e6 + vol*tri) - 1e9)) ~/ 1e9,
    floored at 1000 milli. stateFactor 1350/1000/750; sector vol permille 300/220/100/120.
  - Model: `MarketTemp {cold,neutral,hot}` + `PhaseId` enums (DECLARATION ORDER = replay contract,
    flatten serializes .index), `MarketState {temp, roundsInState, stateDurationRounds, liveRateBp}`
    (sector drift NOT stored — computed per venture at apply time per doc 01 §7.3, documented),
    `kOpeningMarket` (neutral, 1 of 2, rate 0 = not yet drawn), Venture.roundsNeglected,
    GameState.{market, phase, playsRemaining}; `engineSchemaVersion = 2` const.
  - Neglect: decay [4,8,15]% ebitda / [0,3,6]% multiple at min(n,3), halved for passive, multiple
    floored at 1000; yield computed on PRE-decay ebitda (step 3 before 4); reset-on-target wired
    into all 7 venture-targeting apply() branches (StartVenture seeds 0).
  - **TUNING DIAL (not canon): passive cash yield = 35/200** (active 35/100 per cashYield 0.35).
    Doc 02 §4's CASH_YIELD_BP_PASSIVE is spreadsheet-owned and UNSET in economy-model.json; the
    engine uses cashYield x 1/2 citing decay.passiveMultiplier 0.5 as nearest canon. Loud comment
    at operate.dart `cashYieldDenPassive`. Replace when the spreadsheet pins it (golden-affecting).
  - Goldens: `test/golden/replay_seed42_v2.txt` = seed-42 action+OPERATE interleave (drift, a
    boundary transition, interest on real debt, active + passive-halved decay ticks, plays grant,
    cursor 19). v1 file RETIRED in place untouched (byte-sealed by test); bankruptcy covered by a
    separate deterministic mini-script (runOver + cash < 0 + replays identically).
  - §7: invariant test gained runOperate with a SPLIT whitelist — market.*/phase/playsRemaining are
    operate-only paths; player actions still fail if they touch them. roundsNeglected = bookkeeping
    both sides. flatten() now covers market.*, phase, playsRemaining, roundsNeglected (all
    replay-relevant, golden-pinned).
- **Phase 3 round 2 (round machine): LANDED.** 415 tests, analyzer clean. **schemaVersion 2 -> 3**
  (FIELD ADDITIONS ONLY — draw order unchanged from v2; the bump is for the widened flatten paths +
  v2's script being unreplayable under the strict gates). Golden v3 = full-round T1 script: round
  advance, TIER CLEAR with reseed, post-reseed OPERATE at T2; cursor 9. v2 retired in place,
  sealed-by-test like v1.
  - New `lib/round.dart`: `endTurn` (act->shop, no economics), `runDeadlineCheck` (doc 02 §2 exact:
    bar -> T4 win / tier advance + §3.3 reseed / round advance / missedDeadline death; throws
    outside shop), `ForwardMeters computeMeters` (pure derived, never stored), tier bars
    (1e8..1e11 cents + T5 max-int sentinel), reseed helpers. Zero RNG anywhere — the step
    signatures take no stream, so no-draw is structural.
  - Model: GameState gains `netWorthAtTierEntry`/`netWorthLastRound` (the two doc 02 §5.1
    whitelisted write-once snapshots, exact names), `won`, `death` (DeathCause enum, order locked,
    flatten -1=alive). runOperate now REQUIRES phase==operate (StateError), sets
    death=bankruptcy, snapshots netWorthLastRound at step 9 (bankrupt branch included).
  - Phase/plays gates in apply(): wrong_phase (Reroll legal in act|shop, all else act-only),
    no_plays_remaining; gates run BEFORE action PREs; costing actions (all but
    Reroll/PlayConsumable/SellPlay) decrement playsRemaining on SUCCESS only.
  - RESEED (doc 01 §3.3): seedEbitda = trunc(0.24*NW*1000/8000) ONE division, SET on
    ventures.first (multi-venture: first-in-list = the carried platform, documented); multiple SET
    8000; debt/own/cash carry. **ENGINE CAP (documented decision): seed = min(formula, EV~/8)** so
    the reseed never marks the venture UP — honors §3.3's own "re-derives to <= what you had"
    claim, which the raw formula violates for cash-heavy clears. NW-never-increases asserted in
    tests; reseed is LOGGED (actionLog) per §3.3; netWorthAtTierEntry = PRE-reseed clearing NW
    (doc 01 §6 keys the 10x table off the cleared bar). No ventures -> no reseed. T4 clear = win
    (no reseed). T5: bar sentinel, NO deadline in canon -> always advances (endless layer owns
    termination).
  - METERS: runway vs MAX-CRUNCH rate 2520bp (1400 x 180/100) so F6 is always pre-flagged
    (telegraph tests: doomed fixtures flagged + die on any seed; healthy fixture unflagged +
    survives). Growth rates = integer per-round compounding with per-step trunc + bisection:
    needed = min r in [1000,3000] with compound(nw,r,roundsLeft)>=bar (roundsLeft =
    deadline-round+1; 1000 if cleared/T5; saturates 3000); realized = max r in [0,3000] with
    compound(entry,r,round)<=nw (0 if entry/nw <= 0). Pins: T1 seed needs 1434 (doc's ~1.42x).
  - §7: playsRemaining moved into the ACTION whitelist (doc 02 §5.2.1 play counters);
    netWorthLastRound/death = operate-only paths; netWorthAtTierEntry/won/death/phase =
    deadline-only; invariant (e) implements §5.1's exact-name snapshot whitelist (strip-then-scan
    + final-field pins). runDeadlineCheck + endTurn joined the behavioral diff loop with reseed
    reconciliation.
- **Phase 3 round 4 (DEAL-FLOW layer): LANDED — the engine is FEATURE-COMPLETE for the Tier-1
  vertical slice.** 535 tests, analyzer clean. **schemaVersion 3 -> 4** (the second PRE-DECLARED
  stream-breaking bump — apply.dart's Reroll note, promised since Phase 1: the stream MOVED).
  Golden v4 = test/golden/replay_seed42_v4.txt (initRun -> round 1 with a hand-played
  ADD_SW_PLUGIN merge + reinvest -> shop deal + PLY_DOWN_ROUND buy -> advance -> round 2 operate
  -> held play -> a real ACT reroll; cursor 28, hand-verified breakdown pinned in the test).
  v3 retired in place, sealed-by-test like v1/v2 + a moved-stream proof.
  - **NEW DRAW CONTRACT (dealflow.dart header authoritative; operate.dart composes it).** Per
    OPERATE: step 0 HAND draw FIRST (doc 03 §3.1 step 1) = nextInt(3) size (3+draw, clamped to
    pool) + size nextInt(remaining) no-replacement walks over the slice ACT pool (venture+addon,
    tierGate<=tier, slice order); then market boundary/rate/drift as in v2; then the EVENT ROLL at
    doc 01 §6.1 STEP 5 (after decay, before interest — RECONCILED against doc 03 §3.1's "step 3"
    listing in favor of economy-model roundOrder): nextInt(100) < 25 -> nextInt(eventPool) picks a
    slice event whose deltas auto-resolve (sector events hit every venture OF that sector;
    sector-NULL events are market-wide; cash lands once, globally; clamps per resolverInputs) +
    EVENT_RESOLVED. Total/OPERATE = (1+handSize) + (2 if boundary) + 1 + 2V + 1 (+1 if fired).
    endTurn(state, rng, content) deals the SHOP counter (exactly 3 draws, financing+consumable
    pool). Reroll REALLY redraws (act -> full hand routine incl. fresh size draw; shop -> offers);
    apply is now apply(state, action, rng, content) — only Reroll consumes content.
  - lib/init.dart: initRun(economy:) = the canonical opening (cash $20k + the 6x SOFTWARE seed
    venture 'v1' = the $56k NW contract, round 1/tier 1/phase OPERATE, kOpeningMarket, empty
    decks, §5.1 snapshots seeded at the opening NW). Takes EconomyConfig (NOT ContentDb — the
    opening is constants-only) and no RNG (draws nothing; caller owns the stream).
  - Model: hand/shopOffers/playsHeld = List<String> of card IDS (faces live in ContentDb; compact
    flatten/golden, content stays authoritative); indexed flatten paths hand.N etc. (STRING
    values; walker widened to Map<String, Object>). playsHeldMax 2/2/2/3/3.
  - Card->action glue (dealflow.actionForCard) + entry points (apply.playCard/buyShopOffer):
    venture->StartVenture; addon->AcquireAddOn with the IMPLIED m_buy = trunc(price*1000/ebitda)
    (the v1 schema carries no buy multiple; ADD_SW_MICRO's recomputed price lands 499860 vs the
    500000 face — sub-dollar truncation to the player, pinned); financing dispatched by SHAPE
    (dilution face -> RaiseEquity, else TakeDebt — FIN_REFI maps with negative payloads);
    consumable->PlayConsumable with the PURCHASE-MIRROR STRIP (deltas.cash == -cost.cash was paid
    at the buy; HOT_WINDOW/MARKET_READ are pure costs in v1). playCard consumes
    venture/addon from hand (card_not_in_hand), financing from shopOffers (offer_not_in_shop),
    consumables via apply's play_not_held; buyShopOffer = SHOP-phase consumable buy (plays_full /
    insufficient_cash / offer_not_buyable gates).
  - **TUNING DIALS (not canon, loud comments in dealflow.dart):** event probability 25/100; hand
    size distribution 3 + nextInt(3) (doc only fixes the 3-5 range); shop offer count 3.
  - **SCOPE DECISIONS (documented loudly):** PARTNER CARDS EXCLUDED from the v1 hand pool (the
    PartnerEngine per-round layer is unmodeled; dealing one would fake its economics — hand pool =
    venture+addon until that layer lands). Raise cards' growth riders (FIN_SEED_RAISE +200k
    ebitda/+1x) NOT applied — RaiseEquity has no rider channel yet (the dilution lesson is
    intact). Financing offers persist on the counter until the next endTurn and are EXERCISED in
    ACT through the locked play-costing actions (doc 04 §0's "SHOP, no PLAY" wording reconciled to
    the round-2 plays matrix). Events never touch roundsNeglected (weather, not an Act).
  - §7: deck whitelists split BY STEP (operate may write hand.*; endTurn
    phase/shopOffers.*/rngCursor; deadline check NO deck) and BY ACTION (Reroll redraws;
    PlayConsumable/SellPlay consume playsHeld; every other action NO deck path) with planted
    pins + a planted rogue deck mutation; no-unwinnable-hand pinned structurally (ReinvestBaseline
    is an always-available ACTION — legal at any cash incl. 0, sweep-tested over live draws).
- **Phase 3 round 5 (Task 3.0 Flutter shell): LANDED** (commit fffa896; Flutter 3.44.1 stable at
  `C:\src\flutter`, Android SDK 36). `app/` = `flutter create --org com.multiples --project-name
  multiples_app --platforms=android` (ANDROID ONLY; iOS is a later CI exercise per docs/03 §7);
  engine wired via path dep; `app/tool/winflutter.bat` mirrors the engine's win*.bat shims.
  `lib/main.dart` = single-file ENGINE SMOKE SCREEN (art-bible tokens: bg #07090C, phosphor
  #E6EDF3, blue budget on CASH + the one primary key): MULTIPLES wordmark, NET WORTH $56,000 /
  CASH $20,000 off `initRun`, the `SOFTWARE 6.0x EBITDA $6,000` seed line, TIER·ROUND·PHASE·PLAYS
  status, and ONE `RUN OPERATE ▸` key -> `runOperate(state, SplitMix64Rng(42), content)` re-renders
  the post-operate numbers + drawn hand chips; the key disables outside OPERATE (one-shot smoke by
  design). All logic engine-side; the widget calls and renders only (flutter-app.md).
  - **ASSET DECISION (app/assets/data/README.md):** the engine purity guard bans any `flutter:`
    pubspec key, and Flutter only bundles a dependency's assets if the dependency declares them —
    so `app/assets/data/` holds byte-identical COPIES of `/data/*.json`, pinned to the source of
    truth by `app/test/smoke_test.dart` (the engine's own staleness-pin pattern). `MultiplesApp`
    takes the two JSON strings by constructor (tests inject via dart:io; `main()` rootBundle-loads).
  - Verified: `winflutter.bat analyze` = No issues found; `winflutter.bat test` = 4/4 green
    (2 staleness pins; opening render pins $56,000/$20,000/seed line/HAND (0); operate tick ->
    ACT + PLAYS 2 + HAND (3-5) + key disabled). Engine suite re-run 535/535 — engine untouched.
    No .gitignore changes needed (build/, .dart_tool/, local.properties, *.iml already covered).
  - ~~DEFERRED: `build apk --debug` on disk space~~ **APK GATE PASSED (round 6):**
    `√ Built build\app\outputs\flutter-apk\app-debug.apk`, exit 0 — 146,244,166 bytes at
    `app\build\app\outputs\flutter-apk\app-debug.apk` (Gradle re-downloaded a corrupted NDK
    28.2.13676358 + SDK Platform 36 + CMake 3.22.1 mid-build, 426 s total). The build predates the
    round-6 formatMultiple swap (render-identical "6.0x"; rebuild unnecessary for the gate).
    **WATCH: C: free fell to ~1.1 GB after the NDK/SDK installs** — free space before the next
    build/emulator session. NEXT GATE: `flutter run` on an emulator (plan Task 3.0's last leg),
    folded into the screens round.
- **Phase 3 round 6 (adversarial audit, deal-flow + shell): CLOSED — Tier-1 slice UNBLOCKED.**
  Engine 542 tests + analyzer clean; app 4/4 + analyzer clean. ONE fix (d5bcbdf): flutter-app.md
  requires multiples to format through engine money.dart, so `formatMultiple(int milli)` moved
  into the engine (TDD, 7 tests; truncating one-decimal, .0 kept, sign-correct) and main.dart's
  ad-hoc `_fmtMultiple` was deleted — the app layer is now arithmetic-free. Verified by
  re-derivation, not by trusting this file: golden v4 cursor 28 recounted from the contract
  headers (8 + 3 + 11 + 6); no-replacement draws twin-probed + 40-seed duplicate/off-pool sweeps +
  synthetic pool-exhaustion clamp + T1/T2 tier gating + the partner exclusion tested across all
  5 tiers; event semantics (sector / sector-NULL / clamps / global-once cash / EVENT_RESOLVED)
  pinned with the fired path deterministic (seed-8 crunch + decay-before-event ordering — the
  golden's two misses are the pinned stream); every consumption gate value-identical on reject;
  ADD_SW_MICRO 499860: the engine GATES and CHARGES the same recomputed price (the 500000 face is
  only ever the m_buy input — no leak); §7 deck whitelists split by step AND action with planted
  pins, and indexed-path shrinkage is family-whitelisted per consuming action (no false
  positives); app assets byte-pinned, art-bible hexes match docs/07 exactly, widget taps route
  through real runOperate.
- **Phase 3 round 7 (theme + HUD + ACT, screens 3.1-3.3): LANDED** (commit 72d969d). `app/lib/theme.dart`
  (art-bible tokens + ChunkyKey/SegBar/Solid-GhostBox/CRT/cursor/tape), `controller.dart` (GameController:
  engine state + dispatch, lever chips, UI dials), `screens/run_screen.dart` (S1 HUD canonical order +
  S3 blotter + confirm stub + shop/digest/end placeholders). 9 app tests; engine untouched.
- **Phase 3 round 8 (overlays + juice, screens 3.4-3.6): LANDED.** App analyze clean, 21 app tests, engine
  542 untouched. One overlay/panel per file under `app/lib/screens/` + shared juice under `app/lib/widgets/`
  (juice.dart count-up/shake/sparks/pop/haptics; surge.dart SurgeController + tint + surge NW box;
  card_kind.dart; rejection_line.dart). ALL numbers engine-made: events carry the deltas; render-only
  previews call engine pure helpers; the documented display-delta exceptions live in controller.dart's header.
  - **S4 napkin (napkin_overlay.dart)**: two-stage — stage 1 raw face (§Q3), INSPECT -> stage 2 napkin:
    PAY (resolver addonPrice via actionForCard's implied m_buy + enterpriseValue) / EBITDA / SECTOR ✓SAME·✕CROSS /
    SYNERGY (absorbSameSector composition) / MULT held-or-dragged (absorbCrossSectorMultiple + 1000-milli
    floor) — `controller.addonPreview`; BACK/INSPECT/EXECUTE keys; REINVEST keeps a one-stage confirm.
  - **S6 flash (arbitrage_flash.dart)**: full takeover on MULTIPLE_ARBITRAGE — banner-in 500ms overshoot,
    EBITDA count-up 700ms @350, EV 700ms @1100, headline pop (VT323 64, overshoot 1.25) + shake 420ms +
    20 sparks + heavy haptic @1900, BOOK IT; headline = the event's render-only accretion
    (`controller.pendingFlash` captures before/after engine values at commit).
  - **NW SURGE (widgets/surge.dart, the signature)**: SurgeController watches derived-NW transitions around
    every action dispatch (run_screen `_withSurge`); a flash DEFERS the surge to BOOK IT. Beat: NW box flips
    green + counts up 900ms ease-out inside a 1700ms envelope, screen-wide green tint + edge glow, shake,
    haptic — settles back to ghost. Fires on rises only; death screens get nothing.
  - **S2 digest (digest_overlay.dart)**: mockup rows — OPERATIONS (engine cashYieldCents on pre-OPERATE
    ventures = the exact step-3 yield), INTEREST (event amount, shown even at 0), MARKET TURNS, MARKET DRIFT
    per venture (multiple display-delta; blurs neglect-multiple loss, documented), NEGLECT rows (events),
    EVENT (ContentDb name or —), NET CASH (post−pre); RUNWAY restated in words off meters; CONTINUE.
  - **S5 shop (shop_panel.dart)**: offers as tickets; BUY via engine rejection events — insufficient_cash
    flashes the row red ~350ms (AnimationController, no timers); held plays show the engine trunc(price/2)
    SELL face but the key is INERT + 'IN ACT' — **apply.dart's phase gate locks SellPlay (like all non-Reroll
    actions) to ACT**, the same reconciliation financing carries; controller.sellPlay works in ACT (tested).
  - **S7 deadline (deadline_panel.dart)**: advance() now opens the panel (no auto-operate) — cleared:
    TIER CLEARED, NW(ghost) vs BAR(solid), 16-seg fill animating past the bar marker (~200+75ms/seg) with
    counting pct, ROUNDS USED x/y, YOU ARE NOW TIER n, NEXT TIER; behind-pace: DEADLINE CHECK + red
    `NEED a/RD · AT b` straight off meters (telegraph #2) + NEXT ROUND. `proceedFromDeadline()` runs the
    next OPERATE. Nameplate MK·mark STAMPS on tier increase (shrink -> 1.5x overshoot green flash -> settle,
    900ms; victory shows MK·V via won-override).
  - **S8 autopsy (autopsy_screen.dart)**: three panels — CAUSE (GREED./TOO SLOW. by DeathCause, slow 3s red
    pulse, the only motion), THE NUMBER (bankruptcy: real INTEREST DUE vs pre-charge CASH off
    lastOperateEvents; missed: NW vs BAR + realized-vs-needed rates off meters in the gut-punch), THE ROUND
    (last non-TierReseed actionLog entry); RETRY; zero celebration juice. **S10 victory
    (victory_screen.dart)**: real-NW count-up 1400ms + sparks + tint + shake + haptic, ROUNDS USED + seed,
    ENDLESS (controller.enterEndless = documented tier-5 re-entry dial) / NEW RUN.
  - **S0 title (title_screen.dart)**: wordmark + tagline + 14× glyph + NEW RUN (blue primary) + № seed +
    offline footer; gates the run in main.dart (CONTINUE/Desk = Phase 4).
  - Tests (21): napkin engine-derived rows + addonPreview==pure-helpers; flash headline == event amount
    (twin-controller cross-check) + count-ups land on post-merge values; surge fires/defers/settles
    (controller unit + widget keys); digest rows == OperateResult (+ programmatic event mirror); autopsy
    GREED + real interest-vs-cash on a debt-crushed fixture driven through debugSetState + the screen's own
    beginRound, missed-deadline meters variant; title -> run; deadline panel widget + full-loop rework;
    SELL wrong_phase reject then ACT sale. All animations AnimationController-driven — pump(Duration) steps
    every beat; haptics try-wrapped.
  - **Flutter gotcha pinned in code comments: never lazy-init a `late final` AnimationController that
    dispose() may touch first** — creating its Ticker during teardown is an unsafe ancestor lookup that
    crashes the widget-tree finalizer (every R8 controller is initState-created).
- **Phase 3 round 9 (EMULATOR VISUAL AUDIT): PASSED — phase 3 UI work CLOSED.** Engine 550 tests
  (+8 formatMultiple2) + analyzer clean; app 21 + analyzer clean. The real app ran on a Pixel_8 AVD
  (Android 36.1, 1080x2400 @420dpi) and every reachable S0-S8 screen was driven by adb taps,
  screenshotted, and audited against ui-v4-all-screens.html + docs/07 — the committed visual record
  is `docs/screenshots/` (16 frames incl. the green NW-surge mid-flight, both arbitrage-flash
  stages, napkin stages, rejection line, decay/drift chips, behind-pace deadline, TOO SLOW autopsy).
  - **Defects found by eye and fixed (all emulator-re-verified):** (1) `▶` U+25B6 key icons
    rendered as the ORANGE COLOR-EMOJI play button on Android (END TURN/ADVANCE/CONTINUE/NEXT
    ROUND/EXECUTE/RETRY) → swapped to `▸` U+25B8 (no emoji mapping, always monochrome); (2) `⚡`
    U+26A1 (Emoji_Presentation=YES) in the plays counter → `↯` U+21AF; these emoji glyphs ALSO
    leaked a stale Impeller glyph+glow layer that floated over later overlays (the blue square on
    the S7 panel) — gone with the emoji; (3) ACT three-key row clipped `REROLL $15,000` →
    ChunkyKey caps now FittedBox-scaleDown, never clip; (4) S7/S8 pace lines printed
    `NEED 1.3x/RD · AT 1.3x` (one-decimal formatMultiple collapses rates that differ in the
    hundredths — the red warning contradicted its own numbers) → NEW ENGINE HELPER
    `formatMultiple2` (two-decimal truncating, money.dart, 8 tests, display-shape rule honored);
    (5) shop FINANCE rows showed a meaningless `$0` cost face → show the `+$15,000` draw face
    (deltas.cash, engine face data) beside IN ACT; (6) consumable PLAY badges were blue → kGain
    green per the mockup's t-addon class + the blue-budget law.
  - **Emulator toolchain notes (moved-home first boot):** `set ANDROID_AVD_HOME=...&` must have NO
    space before `&` (cmd bakes the trailing space into the value → "Unknown AVD"); both AVD
    config.ini skin.path entries still pointed at the deleted C: SDK → repointed to
    D:\claude\toolchains\android-sdk\skins\ (fixed in place, boots clean now). The emulator
    HARD-CRASHED (0xC0000005) twice on the gfxstream software paths (windowed llvmpipe AND
    headless swiftshader) ~1-2 min after the app started; `-no-window -gpu host` (NVIDIA GTX 1650)
    is STABLE — use that invocation for future emulator rounds.
  - **Known gaps (deliberate, not regressions):** S10 victory + bankruptcy-autopsy + TIER CLEARED
    panel + MK-stamp beat not emulator-screenshotted (unreachable in a short organic run; all four
    remain pinned by the R8 widget tests); S8 "THE ROUND IT BROKE" prints the engine actionLog
    verbatim (`BuyShopOffer PLY_MARKET_READ: cost 100000, held 1/2` — raw cents, debug flavor) —
    needs a future engine `describeAction` display helper; venture display names are engine ids
    (V1 vs the mockup's NIMBUS) pending a naming layer.
- **Phase 3 round 10 (GAMEPLAY COMPLETENESS): LANDED.** Engine 599 tests + analyzer clean; app
  21/21 + analyzer clean. **schemaVersion 4 -> 5** (the THIRD pre-declared stream-breaking bump).
  Golden v5 = test/golden/replay_seed42_v5.txt (initRun -> operate [filtered 3-card hand +
  exit-offer pair] -> HIRE PARTNER + ADD_SW_PLUGIN merge -> shop deal + SHOP reroll + buy
  PLY_MARKET_READ -> advance -> boundary operate [partner +150k accrues] -> held play [hint set]
  -> reinvest; cursor 28; partners/flags/exitOffer pinned in the end-state flatten). v4 retired
  sealed-in-place (31 frozen paths incl. the dead-draw venture hand the v5 filter fixed).
  Commits: e120e29 (partners) / 117befa (flags) / 068ebc9 (riders) / cec79b6 (schema 5 + exit
  offers + pool) / e21d516 (app pins).
  - **PARTNER ENGINE LAYER (doc 02 §3.5/§1):** Venture.partners = PartnerEngine{defId,
    perRoundEbitdaCents}; GameState.scheduled = minimal ScheduledCost{ventureId?, cashDeltaCents,
    recurring} (FIXED-basis cash-only slice of doc 02's ScheduledEffect — EARN_OUT's PCT_*/
    roundsLeft widen it later). HirePartner = the 12th union variant (PRE venture+cash; POST
    attach engine + one-time multiple bump [PRT_GROWTH_HACKER face, floored] + fixed-cost
    variants push a recurring ScheduledCost; costs a play). OPERATE step 3a ACCRUES the +EBITDA
    onto the venture PRE-yield (documented divergence from doc 02's non-accruing ventureCashYield
    pseudocode in favor of its §3.5 organic-compounder prose); step 3c fires scheduled costs
    alongside yield (doc 02's relative position inside doc 01 §6.1 step 3 — documented at the
    code site), prunes one-shots after firing and orphans (venture gone) without firing; a fixed
    cost can push cash negative mid-OPERATE, F6 still verdicts at step 6. actionForCard maps
    partner cards (purchase mirror ignored; **fixedCostCents maps 0 — the v1 card SCHEMA has no
    fixed-cost face**; PRT_COO_FIXED is out of slice; the channel is live + unit-tested).
    Partner cards are ACT hand cards via playCard (card_not_in_hand / consumed on success).
  - **EXIT OFFERS PLAYABLE:** drawHand appends 2 draws when ventures exist — nextInt(#ventures)
    picks the venture (list order), then u = nextInt(301) prices it by the EXACT formula
    `offerMilli = (live x (900 + u)) ~/ 1000` (0.90x..1.20x band around the venture's LIVE
    multiple, floored 1000 milli; band shape = TUNING DIAL, no canon). GameState.exitOffer is the
    UI's EXIT OFFER ticket; dealflow.exitOfferAction maps it onto ExitVenture with live = the
    venture's drifted multipleMilli (the round-4 "TEMPORARY payload" note RESOLVED — the field is
    a payload carrier by design now); min(offer, live) + the hot override resolve as ever; an
    exit of the offered venture clears the ticket; every hand draw replaces it wholesale
    (venture-less draws clear it, 0 extra draws).
  - **CONSUMABLE FLAGS (doc 02 §1 lifetimes):** MarketState gains hotWindowArmed +
    hotWindowExpiresRound and marketReadHint + marketReadExpiresRound (flat-round expiries;
    flatRoundOf = tier*100 + round). PlayConsumable gains armsHotWindow/readsMarket, ID-KEYED by
    actionForCard (PLY_HOT_WINDOW / PLY_MARKET_READ — no consumableKind in the v1 schema,
    documented). Arm = expiry flat+1 (one-window lifetime: usable rest of round r + round r+1,
    swept at the r+2 OPERATE). OPERATE step 0a expires stale flags FIRST (draw-free, before the
    hand draw; HOT_WINDOW_EXPIRED emitted, the read clears silently per doc 02 §2 step 1). EXIT
    under an armed window uses **live x135/100** (doc 01 §7.6 sectorHotMultiple read via the
    canon driftBubble 1.35 — TUNING DIAL) overriding min(offer, live), clears the flag, emits
    HOT_WINDOW_FIRED. MARKET_READ derives the direction HONESTLY with ZERO draws (documented in
    model.dart marketReadDirection): mid-state = the CERTAIN current temp (the machine cannot
    transition mid-state); at a boundary = the MODAL neutral (64/100) forecast — revealing the
    real draw would consume or peek the stream, breaking replay.
  - **RAISE RIDERS:** RaiseEquity gains ebitdaDeltaCents/multipleDeltaMilli (defaults 0). ORDER
    DECISION: F5 dilution prices the company AS-IS (preMoney = pre-rider equity); the riders are
    what the new money buys. FIN_SEED_RAISE now lands +200k EBITDA / +1000 milli with its
    dilution; clamps per resolverInputs.
  - **T1 DEAD-DRAW FIX (the v5 pool contract):** handPool(content, tier, slotsFull:) — partners
    RE-INCLUDED (round-4 exclusion closed); venture-type cards EXCLUDED while ventures.length >=
    slotsMax(tier). T1's slot is full from initRun, so T1 hands are exactly the addon+partner
    set — no more dead venture tickets. slotsMax moved apply.dart -> dealflow.dart (re-exported
    from apply.dart, no caller breaks).
  - **§7/flatten/v5 draw contract:** flatten gains venture.X.partners.N.*, scheduled.N.*, the
    four market flag paths, exitOffer.* — ALL emit paths only when set/non-empty (the
    appeared/disappeared convention). Whitelists: partners = HirePartner-only; scheduled =
    HirePartner + OPERATE step 3c; flags = PlayConsumable (arm) / ExitVenture (hot clear) /
    OPERATE (expiry); exitOffer = deck-like (operate hand routine + ACT Reroll write, ExitVenture
    clears) — all planted-pinned. operate_test's twin probes re-derive the v5 contract; the
    seed-pinned tests now HUNT their seeds via the probe (re-hunt on contract moves, never
    weaken). Per-OPERATE draws = (1 + handSize + (2 if ventures)) + (2 if boundary) + 1 + 2V + 1
    (+1 if event fired).
  - **APP (minimal, R10 item 7):** two seed-2 stream pins reconciled (v5 hand tickets =
    addon+partner pool; round-1 digest now pins the fired EVT_KEY_CLIENT_LOSS — SERVICES-only,
    money rows event-proof). NO new UI: R11 owns the affordances (hand partner ticket action,
    EXIT OFFER ticket rendering via exitOfferAction, hint/armed badges off market flags,
    scheduled-cost digest rows).
- **Phase 3 round 10.5 / ROUND 11 (UI AFFORDANCES for the R10 systems): LANDED** (commit efecb7d).
  Engine UNTOUCHED (599 + analyzer clean re-verified); app analyzer clean, **34 tests (21 + 13
  round-11)**. All numbers engine-made or documented mirrors (controller class docs name every
  source); pinned-animation widget tests throughout (no pumpAndSettle, AnimationControllers only).
  - **EXIT FLOW (items 1)**: the DEALS blotter renders the per-round EXIT OFFER ticket
    (`_ExitTicket`, mockup .t-exit: red EXIT/OFFER badge, `V1 @ 6.3x` midline, SELL /
    PAPER→CASH) → tap → exit napkin (napkin_overlay `exit:` mode): OFFER / LIVE MARK /
    EXIT MULTIPLE (min fork or `x HOT` + the `〔 HOT WINDOW ARMED: WILL ROLL x.xx 〕` override
    line) / EQUITY AT EXIT / YOUR OWNERSHIP / PROCEEDS → CASH — all `controller.ExitPreview`,
    a DOCUMENTED MIRROR of apply.dart's fork (engine hotExitMulNum/Den consts +
    equityValue/netWorth pure helpers; the round-11 test pins preview == the EXIT_REALIZED
    event to the cent). EXECUTE → **S6-EXIT beat** (`screens/exit_flash.dart`): stage rows,
    then the dashed PAPER box COLLAPSES INTO the solid CASH box (mockup #paper-box.collapse
    translate+scale .08+fade over the first 40% of a 1500ms beat, shake+haptic at landing)
    + proceeds count-up + `SLOT FREED x/y` + CASHED OUT, which releases the DEFERRED NW surge
    (R8 machinery; a min(offer,live) exit never rises, a hot exit does — surge-tested).
  - **PARTNER TICKETS (item 2)**: hand partner tickets play through the napkin — face midline
    `+$1,500 EBITDA /RD` + HIRE price (white-phosphor PARTNER badge, card_kind), napkin ENGINE
    row + the FIXED COST warning row (renders only when actionForCard maps one — 0 across the
    v1 slice, channel tested); hired engines show as a green `+$X/RD` tag on the holdings row
    (`partnerTag-<id>`; controller.partnerPerRoundCents composition).
  - **TARGET PICKER (item 3)**: a targeted ticket (addon/financing/partner) with >1 ventures
    enters AIMING — the napkin waits, HOLDINGS glows (tglow border+glow), `TAP A VENTURE TO
    AIM ▼` hint, row tap locks the target and opens the napkin on it; playBlotterCard/
    addonPreview/napkin all thread targetVentureId (cross-sector merge onto v2 pinned: raw
    absorb + x0.92 drag, v1 untouched). Single venture auto-targets as before.
  - **CONSUMABLE AFFORDANCES (item 4)**: held PLAYS chips tappable in ACT → USE/SELL sheet
    (napkin `heldPlay:` mode; raw delta faces, SELL VALUE row) — USE dispatches
    controller.playHeld (actionForCard → apply; market-read/hot-window arm engine-side),
    SELL pays the engine trunc(price/2) (the R8 'IN ACT' inert-key gap closed); HOT WINDOW
    armed = `↯ARMED` chip by the market meter (`hotArmedChip`) + the napkin override line;
    MARKET READ = `(READ: NEUTRAL→)` hint on the meter while unexpired (expiry engine-side).
  - **REINVEST PICKER + REROLL (item 5)**: napkin quick keys 25/50/100% (controller dial,
    default 50 = the R7 half-pocket behavior) + the engine efficiency line `+$X EBITDA AT Y%`
    (resolver reinvestEfficiencyBp; the gain mirror is pinned == the resolver's exact landed
    gain); both REROLL keys (ACT + SHOP) show the real fee and DISABLE cash-short
    (controller.canReroll; the engine still gates at apply).
  - **DIGEST/HUD (item 6)**: digest gains PARTNERS (+accrual EBITDA, the step-3a composition —
    OPERATIONS now yields on post-accrual EBITDA exactly like step 3b), FIXED COST rows
    (scheduledEffectFired events), and the EXIT OFFER tease line (`V1 @ 6.3x`); lever chips
    stay the existing real per-round snapshot deltas (kept simple per the work order).
  - Files: controller.dart (ExitPreview/ExitFlashData/PartnerPreview, exitVenture/playHeld/
    partnerPreview/targetVenture, reinvest pct dial, digest fields), screens/exit_flash.dart
    (NEW), napkin_overlay.dart (exit/heldPlay modes, partner rows, picker keys),
    run_screen.dart (_ExitTicket, aiming state, rail picker, plays-strip taps, meter chips,
    reroll disable), digest_overlay.dart, widgets/card_kind.dart, test/round11_test.dart (NEW).
  - NOT DONE THIS ROUND (deliberate): apk-debug gate skipped (C: free space watch, optional
    gate); scaling reroll fee still the flat $15k dial; held plays with per-venture deltas
    target the platform (no aim step on the sheet — document/extend when a multi-venture
    consumable matters).
- **ROUND 12 (PHASE 5 BALANCE HARNESS + TUNING): LANDED — rounds 10-12 close the "rubbish runs"
  arc.** Engine 635 tests + analyzer clean (lib/test/tool); app 34 + analyzer clean.
  **schemaVersion 6 AND 7 this round** (golden v6 = organic growth, commit 0caa0d1; golden v7 =
  the tuning pass — both via the locked docs/03 §6 procedure; draw order NEVER moved, cursor 28
  throughout; v5/v6 retired sealed-in-place).
  - **ORGANIC GROWTH (doc 01 §3.2, commit 0caa0d1):** economy organicGrowthDefault — parsed since
    Phase 2, never applied — now lands at OPERATE step 3a on PARTNERED ventures; initRun attaches
    the FOUNDING OPERATOR (0-face PartnerEngine) to the seed venture. Passive halves it
    (decay.passiveMultiplier 0.5, the cashYieldDenPassive pattern — TUNING DIAL note at the site).
  - **CANONICAL DIVIDEND RECAP (doc 01 §7.7):** PLY_DIVIDEND_RECAP's fixed $30k faces were inert
    (neither scale with EV nor match the doc formula — the "primary greed-death dial" measured
    ~1.6% greedy bankruptcy). actionForCard now STRIPS the illustrative faces and routes
    PlayConsumable.recapBp = kRecapPctBp; apply computes `pull = trunc(EV x recapBp/10000)` at
    RESOLVE TIME against the target's live EV — cash += pull, netDebt += pull on the target, a
    dividendRecap event carries the amount. Draw-free; §7-reconciled (NW unchanged: paper -> pocket
    via new debt); a worthless EV pulls nothing but still consumes the play.
  - **FULL-MODEL MONTE-CARLO HARNESS (tool/sim.dart + test/sim_test.dart)** — the doc 01 §12 P1
    deliverable: a headless auto-player driving the REAL engine (initRun -> runOperate -> policy
    ACT over the live card surface -> endTurn -> policy SHOP -> runDeadlineCheck) under 3 policies:
    FLOOR (§11.3 verbatim: lever to 3.0x not-in-crunch at the JS 1.2xEBITDA/round pace, reinvest
    above a max-crunch buffer, never merge/exit/hire), GREEDY (§11.2: 5.8x line, any market, no
    buffer), SMART (floor + the skill layers: hot/bubble exits, re-found, hires, accretive
    same-sector merges, prudent recap <= 4.0x). Integer-only (permille/x100), deterministic (run k
    = seed seedBase+k-1; sim_test pins byte-identical reports + seed tiling + a purity scan of the
    tool source). FEEL metrics per ACT: dead-hand rate, playable tickets/hand, actions/round,
    merge/exit/hire uptake. CI prints the N=400 table; the gates run inside `dart test`.
  - **THE TUNE (doc 01 §8 knob order; reasoning AT each dial site).** Where it started (full
    model, N=1000-2000): floor win 1.3% (vs §11.3 band [25,42]%), greedy bankruptcy 22-25% (vs
    [8,12]%), smart 9%. Root cause: the engine's reachable baseline compounding (~1.27x/round)
    sat under EVERY tier's needed rate (the JS calibration grew ~1.45x), which ALSO parked
    greedy's steady-state leverage (pace/(growth surplus)) past the yield-vs-interest breakeven.
    Final dials (old -> new):
    | dial | old | new | where |
    |------|-----|-----|-------|
    | organicGrowthDefault | 0.10 | 0.20 | operate.dart organicGrowthNum |
    | carrySeedFrac | 0.24 | 0.37 | round.dart carrySeedNum |
    | deadlineRounds | [8,8,9,10] | [9,10,9,10] | resolver.dart tierDeadlineRounds |
    | interestMax | 0.14 | 0.12 | resolver.dart interestMaxBp |
    | crunch rateMul | 1.8 | 1.3 | operate.dart rateMulColdNum (maxCrunchRateBp 2520 -> 1560) |
    | crunch entry P | 0.18 | 0.12 | operate.dart transitionColdPct (hot bucket untouched) |
    | recapPct | 0.30 | 0.16 | dealflow.dart kRecapPctBp |
    economy-model.json synced (constants + curves.interestBand + transitionAtBoundary + tierBars +
    tuningKnobs notes record every turn); /data -> engine assets -> app assets byte-identical.
  - **HEADLINE (N=2000, seedBase 1, schema v7; disjoint-seed re-run within ±2pp):**
    | policy | win | bankrupt | T1/T2/T3/T4 cleared | median run | dead-hand | playable/hand | uptake (merge/exit/hire) |
    |--------|-----|----------|---------------------|-----------|-----------|---------------|--------------------------|
    | FLOOR  | 41.5% | 0.2% | 82/70/51/42% | 23 rds | 0.0% | 3.64 | —/—/— |
    | GREEDY | 43.6% | 11.2% | 84/73/55/44% | 22 rds | 0.0% | 3.61 | —/—/— |
    | SMART  | 47.1% | 0.0% | 69/62/51/47% | 21 rds | 0.0% | 3.43 | 99.5/67/100% |
    Bands: greedy bankruptcy [8,12]% ✓ (doc gate); floor [25,42]% ✓ (41.5 sits near the top — §12's
    "pull toward 30%" stays open); smart pinned from measured reality [42,56]% with smart > floor
    (headroom) + prudence-near-never-dies (<=2%) + feel gates (dead-hand <=2%, >=3.0 playable)
    — all asserted in sim_test.dart with the reasoning in its header.
  - **KNOWN HONEST LIMITS:** the harness floor is stricter than the doc's "competent-but-plain"
    (never merges/hires/exits — §11's own scope-honesty), so it bounds the real floor from BELOW;
    smart's T1 (69%) trails the floor's (82%) because it spends early cash on hires/merges that
    pay off at T2+ (T2-T4 conditionals: smart 89/83/92% vs floor 85/72/82%) — policy artifact,
    documented, not tuned around. Greedy's win (43.6%) only narrowly tops the floor's (the doc's
    JS pass had 73 vs 40) — the recap-chunk down-tune traded greed's upside for the death band;
    revisit if greed stops feeling tempting in live play.
- **ROUND 14 (PHASE 4 APP SIDE — save/resume + S9 Desk + meta-wired loop + polish): LANDED.**
  A human can now play a complete, persistent game. Engine 701 tests UNTOUCHED + analyzer clean;
  app 34 -> 50 tests, analyzer clean (lib + test); `build apk --debug` SUCCEEDS (path_provider, the
  first native plugin, compiles + bundles; SDK Platform 35 auto-installed). schemaVersion STILL 8
  (no engine change — app consumes the R13 API). Commits: 3792328 (SaveStore + controller
  journal/autosave) / 19585f2 (S9 Desk + title CONTINUE + meta end screens + boot shell) / 612a7a0
  (venture names + CASH juice) / c371d27 (tests + write-serialization fix) / <this> (STATE).
  - **PERSISTENCE (app/lib/save_store.dart):** docs/06 two-file split run.json + meta.json in the
    app documents dir via path_provider; atomic temp-write + rename; meta `.bak` (via .bak.tmp +
    rename). Load ladder: migrate-then-parse; AbandonRun -> drop run keep meta; SaveFromNewerVersion
    -> keep file don't resume; corrupt -> discard; lastSettledRunId orphan guard. Calls ENGINE
    serialize/migrate funcs ONLY (no game logic). Directory INJECTED (`SaveStore.forDirectory`) for
    tests; `SaveStore.open()` resolves the real dir. ALL mutating ops serialized through a
    tail-Future chain (concurrent autosave + flush + settle-delete never collide on the shared .tmp
    — a real correctness fix the round-trip test surfaced).
  - **AUTOSAVE CADENCE (controller.dart):** a `List<RunStep>` journal appended at EVERY committed
    mutation (OperateStep on beginRound; ApplyStep for reinvest/reroll/sell/exit; PlayCardStep for
    blotter; held consumables -> ApplyStep(PlayConsumable) since the controller dispatches them via
    apply not playCard; BuyShopStep; EndTurnStep; DeadlineCheckStep). Eager autosave after each +
    each phase transition; `flush()` on AppLifecycleState.paused/inactive (WidgetsBindingObserver in
    main). Fire-and-forget writes, runOver no-ops (the save is deleted at settlement). ENDLESS marks
    the run non-resumable (it leaves the replayable model). `GameController.resume(RunLoadResult)`
    seats the replayed state + rng AT cursor (SplitMix64 fast-forward) + journal.
  - **SETTLEMENT:** RUN_OVER -> `settleRunOver()` (post-frame, one-shot from run_screen) = build
    RunOutcomes (folded from EXIT_REALIZED/dividendRecap as events fired) -> engine settleRun ->
    write meta atomically -> delete run.json (the docs/06 §5.1 order).
  - **S9 THE DESK (screens/desk_screen.dart, mockup-faithful):** TRACK RECORD rep bar (level + total
    + next-unlock line, off MetaState/metaLevelFor/kMetaLevelThresholds), founder-background picker
    (kFounderBackgrounds; perk+constraint faces derived from the dials; LOCKED when not in
    meta.unlockedBackgrounds — only BOOTSTRAPPER unlocked by default), UNLOCKED counts (cards x/35 ·
    sectors x/6), cosmetic title, START RUN (hands the chosen background to initRun). Reachable from
    title + after a run (victory/autopsy -> THE DESK).
  - **TITLE CONTINUE + boot shell (main.dart):** main() is now a boot+routing shell — loads meta +
    any resumable run, routes title <-> Desk <-> run. CONTINUE slot (T<tier>·R<round>·#seed, shown
    only with a resumable save) + THE DESK key; footer "SAVED ON DEVICE" now TRUE. Content load
    wrapped in try/catch -> terminal ERROR screen (audit L5, screens/error_screen.dart).
  - **END SCREENS wired to meta:** victory RUNS TO GET HERE = meta.runsPlayed (post-settle); autopsy
    "THE ROUND IT BROKE" via describeRunStep off the typed journal (no raw cents — fixes R9 leak);
    both route to THE DESK / RETRY (RETRY reuses the chosen background).
  - **VENTURE NAMES (#5):** holdings rail, EXIT ticket midline, napkin target/exit headers, exit
    beat all render `Venture.displayName` (QUANTA…), never "V1". ExitFlashData gained ventureName
    (captured pre-exit). round11 target-picker test updated to the dynamic displayName.
  - **POLISH (#6 / audit L2):** FloatingDeltaBox (widgets/juice.dart) — CASH box pops + floats a
    +$/−$ chip up+fade on every change (green up / loss-red down; the NW box keeps the up-only
    signature surge). Reinvest picker + USE/SELL affordance VERIFIED present (round11 tests).
  - **TESTS (app 50):** save round-trip (write->read->resume == flattened state); resumed-controller
    state+cursor; meta round-trip; corrupt-discard; v7 stream-break ABANDON keeps meta; newer-version
    kept-not-resumed; orphan guard; v7->v8 meta migration; Desk rep/backgrounds + VC Darling -> 80%
    own; title CONTINUE in/out; victory runsPlayed; venture-name render. Injected temp-dir store;
    widget-test boot bridged with runAsync / store-less app to avoid real-I/O fake-async hangs.
  - **DEFERRED to R15 (engine/infra):** the DEALMAKER +1-play GRANT is still UNWIRED — the dial is
    on the background (initRun reads cash/own/partner correctly) but plays are granted inside
    runOperate/runDeadlineCheck which don't see the backgroundId; threading it needs a GameState
    field = a schema bump (R15 engine territory; putting it app-side would be game logic in the app).
    Also still: scaling reroll fee (flat $15k dial, R15 engine rerollCost formula); PLY_SECONDARY_
    SALE engine proceeds (placeholder). tool/winflutter.bat now defaults ProgramFiles(x86) so
    `flutter test`/`build` work in this session's cmd env (was aborting loudly).
- **ROUND 13 (PHASE 4 SAVE/PERSISTENCE — engine side + meta layer + 2 polish fixes): LANDED.**
  Engine 701 tests + analyzer clean (lib/test); app 34/34 + analyzer clean (NO app changes — R14
  owns app features; no pins broke). **schemaVersion 7 -> 8** (golden v8 via the locked docs/03 §6
  procedure; v7 RETIRED sealed-in-place). The bump is the PERSISTED-CONTRACT change + the widened
  flatten, NOT a moved stream — cursor STILL 28 (nothing in serialize/migrate/meta/describe touches
  the RNG); a v7 run is abandoned (docs/06 §3), meta migrates. Commits: 0cf112d (schema 8 +
  displayName + MetaState model) / 330d239 (meta layer) / e541d8c (serialize) / 269991e (migrate +
  meta.json + fixtures) / 2e87f85 (describe).
  - **VENTURE DISPLAY NAMES (R9/R11 "V1 vs NIMBUS"):** `Venture.displayName` is a pure GETTER =
    `ventureDisplayName(id, sector)` (model.dart) — an RNG-free per-sector flavor namer
    (code-unit-sum hash over FROZEN pools). Adds nothing to the constructor/equality (derived, like
    netWorthCents). Seed `v1` (SOFTWARE) pins to **QUANTA**. flatten() serializes it (the v8
    path-set addition, +1 line/venture); invariant whitelists it as derived venture-family
    bookkeeping.
  - **MetaState + MetaCosmetics (model.dart):** the doc 02 §1 durable store + the docs/06 §5.1
    `lastSettledRunId` double-settle guard. Pure value types, OUTSIDE §7 (access state, never
    economy), NEVER flattened into the run. `kBootstrapperBackgroundId` const.
  - **lib/meta.dart (pure):** FOUNDER BACKGROUNDS (§Q7) `kFounderBackgrounds` — BOOTSTRAPPER
    (default; ALL-ZERO variant — `initRun(default)` is byte-identical to the pinned $56k seed),
    OPERATOR (free founding partner +$1,500/rd; -$8k cash), VC_DARLING (+$60k; pre-diluted to 80%),
    DEALMAKER (+1 play/round dial; -$6k cash) — perk + matching constraint, NUMBERS ARE TUNING DIALS
    (economy outOfScope). `RunOutcomes`/`ExitOutcome` (run-local REALIZED-outcome tally the caller
    accumulates as events fire). `reputationFromOutcomes` = doc 02 §2 realized-only formula (paper
    NW NEVER counts; per clean exit `mulBp(mulBp(proceeds, exitMul*10000/sectorNorm), ownership)`,
    + secondaries x50%, + dividends x25%; fire-sales 0). `metaLevelFor`. `settleRun` = the strict
    doc 02 §2 RUN_OVER sequence + the idempotency guard (re-settling the same runId is a no-op).
    Dials: kCleanExitMinMultipleMilli 2000, kRepSecondaryBp 5000, kRepDividendBp 2500,
    sectorNormMilli (SW 14000/SVC 5000/RET 3000/IND 8000), kMetaLevelThresholds.
  - **lib/serialize.dart (pure; dart:convert only):** `flatten()` MOVED here from the test helper
    (docs/06 §2.2 — load path + invariant/golden share ONE walker; helper now re-exports). `RunStep`
    sealed union (Operate/EndTurn/DeadlineCheck/Apply(Action)/PlayCard(cardId,target?)/
    BuyShop(cardId)) = the typed REPLAYABLE journal (the on-disk actionLog; replaying it regenerates
    the display LoggedAction list identically). `actionToJson/FromJson` (all 12 variants),
    `runSaveToJson`/`runSaveFromJson` (+ `...String`) = docs/06 minimal record; `replayRun`
    reconstructs BY REPLAY (a rejected step throws `ReplayDesyncError`); cache reconciled-or-discarded
    (rng stripped + re-injected; trusted only if flatten-equal AND schema-equal). `metaStateToJson/
    FromJson` (meta.json whole; enums as NAMES). `runIdForSeed`.
  - **lib/migrate.dart (pure):** forward-only `migrateMeta` (additive; never abandons; step 7->8
    defaults lastSettledRunId/cleanExits) + `migrateRun` (THROWS `AbandonRun` on stream-breaking;
    runMigrations EMPTY so any v<8 run abandons). `SaveFromNewerVersion` on a future save. Golden
    fixtures `test/golden/saves/{meta_v7,run_v7}.json` (synthetic; docs/06 §3.2 rule 5) prove the
    chain: v7 meta -> v8 (Track Record preserved), v7 run -> AbandonRun.
  - **lib/describe.dart (pure):** `describeAction(Action, {round, ventureName?})` + `describeRunStep`
    — the autopsy "THE ROUND IT BROKE" human line, money/multiple-FORMATTED (fixes the R9 cents
    leak: `cost 100000` -> `$1,000`; "exited QUANTA at 6.0x").
  - **THE PUBLIC API R14 MUST CALL (exact signatures):**
    - `initRun({required EconomyConfig economy, String backgroundId = kBootstrapperBackgroundId}) -> GameState`
    - `String runSaveToJsonString({required int seed, required int cursor, required String backgroundId, required List<RunStep> steps, GameState? cacheState})` (+ map form `runSaveToJson(...)`)
    - `RunLoadResult runSaveFromJsonString(String json, {required EconomyConfig economy, required ContentDb content})` (+ map form `runSaveFromJson(Map<String,Object?> json, {economy, content})`). `RunLoadResult{GameState state, int seed, int cursor, String backgroundId, String runId, List<RunStep> steps, bool usedCache}`.
    - `GameState replayRun(List<RunStep> steps, {required int seed, required String backgroundId, required EconomyConfig economy, required ContentDb content})`
    - `String runIdForSeed(int seed)`; `Map<String,Object> flatten(GameState)` (both from serialize.dart).
    - RunStep ctors to RECORD as the player dispatches: `OperateStep()`, `EndTurnStep()`, `DeadlineCheckStep()`, `ApplyStep(Action)`, `PlayCardStep(String cardId, {String? targetVentureId})`, `BuyShopStep(String cardId)`. R14 keeps a `List<RunStep>` per run, appends one per engine call, and persists it via runSaveToJsonString on each committed mutation (docs/06 §4 cadence).
    - `String metaStateToJsonString(MetaState)`; `MetaState metaStateFromJsonString(String)` (meta.json read/write).
    - `MetaState migrateMeta(Map<String,Object?> json, int from)` -> then metaStateFromJson; `Map<String,Object?> migrateRun(Map<String,Object?> json, int from)` (catch `AbandonRun` -> drop run; catch `SaveFromNewerVersion`). Migrate runs BEFORE the From-Json parse.
    - `MetaState settleRun(MetaState meta, {required GameState finishedRun, required String runId, RunOutcomes? outcomes})` at RUN_OVER; build `RunOutcomes` by folding EXIT_REALIZED (-> `ExitOutcome` with `sectorNormMilli(sector)` + the clean test `equity>0 && exitMul>=kCleanExitMinMultipleMilli`), dividendRecap, and secondary events as they fire. Then write meta atomically, THEN delete run.json (docs/06 §5.1 order).
    - `String describeAction(Action a, {required int round, String? ventureName})` / `String describeRunStep(RunStep, {required int round, ContentDb? content, List<Venture> ventures})` for the S8 autopsy round-line + S9 Desk.
    - `List<FounderBackground> kFounderBackgrounds` + `FounderBackground backgroundFor(String id)` for the run-setup / S9 Desk background picker (label/blurb fields).
  - **STILL DEFERRED (R14+):** the app-side file I/O (path_provider, temp-write+rename, .bak, the
    eager-autosave cadence, lifecycle flush) — engine is I/O-free by design; S9 Desk meta screen +
    background picker UI; the Dealmaker +1-play GRANT must be wired in the round layer (the dial is
    on the background, the grant is not yet applied — R14 or a round-layer follow-up); PLY_SECONDARY_
    SALE engine proceeds still a placeholder (the reputation channel is live, the resolver isn't).
- **Phase 3 round 3 (adversarial audit): ROUND-LOOP LAYER CLOSED.** 421 tests, analyzer clean,
  ZERO engine-code changes — every checklist item verified against docs 01/02/03 + economy-model;
  no behavior moved, so no golden/schema bump. Audit verified by re-derivation: draw contract
  (bucket map 0-17 hot/18-35 cold/36-99 neutral consistent with rateMul 90/180 + stateFactor
  1350/750; count (2 if boundary)+1+2V; drift = one final division, |nano| < 7.6e8 so int64-safe
  to a ~12,000,000x multiple); F6 exactness (strict <0, ==0 survives, never clamped/rolled);
  reseed cap proof (EV' = 8*seed <= EV => NW' <= NW on ALL paths incl. negative equity — ~/ is
  monotone across negatives); compound monotone in r (step map monotone for x>=0, so the
  bisections cannot mis-bracket); snapshots write-once at exactly the doc 02 §2 sites, read only
  by computeMeters; v1/v2 goldens sealed, v3 cursor 9 recounted. Hardening ADDED (test-only):
  clear-ON-deadline-round advances + bar-1 dies pinned for all four tiers (T4 = win); negative-
  equity + venture-dominant-RETAIL reseed fixtures (exact pins + the never-increase sweep);
  compound monotone sweep + exact bisection boundaries (needed-1 misses, realized+1 overshoots);
  telegraph-across-tier-clear test (a reseed-gutted yield IS flagged on the post-check state —
  derived meters never go stale; deaths AND survivals both reachable = warning-not-verdict);
  planted §7 rogue-mutation test routed through the real diff machinery. Plan Task 1.7 errata
  appended (replay golden + cursor pin, not a raw draw-list file).
  ~~NEXT: deal-flow layer~~ LANDED in round 4 (above). ~~NEXT: Flutter shell Task 3.0~~ LANDED
  in round 5 (above). The engine is feature-complete for the Tier-1 slice.
- Phase 2 build detail (tasks 2.1 + 2.2, commits c413577 + f9070a0):
  `lib/content.dart` = PURE parsing (raw JSON strings in; app/tests do I/O); typed Card/ContentDb +
  EconomyConfig with fractions converted ONCE at parse to integer fixed-point via decimal-text
  integer arithmetic (no float math). Validation fails loudly with the card id: §7 delta-key subset,
  unknown keys/spellings, non-integer money, duplicate ids, and cost face values >= 0 (closes the
  round-4 audit note). Content lints: §Q2 MEMO ban scoped to CONSUMABLES only (doc 03 §5.1 errata
  added; raise/partner positive multiples legal per doc 04 §1, events are market weather), venture
  face multiples in a generous sector band (>0, <=2x base), vertical slice pinned to doc 04 §3's
  19 cards. assets/ = byte-identical build copies of data/ (test-pinned; data/ is source of truth).
  json_serializable codegen handles SHAPE (generated `content.g.dart` passed the purity guard —
  no revert needed); hand-written checks own SEMANTICS. `.github/workflows/ci.yml` runs pub get ->
  build_runner -> dart test -> dart analyze on push (`*.g.dart` gitignored, CI rebuilds).
  tool/winpub.bat + winbuild.bat join wintest/winanalyze. NEXT: Phase 3 Flutter app shell.

## Phase 1 task status
- [x] 1.1 money + fixed-point/format helpers (22 tests)
- [x] 1.2 SplitMix64 RNG + cursor replay, golden-pinned (7 tests)
- [x] 1.3 immutable model + derived net worth, $56k seed (19 tests)
- [x] 1.4 Layer-1 frozen formulas, port of proven prototype (14 tests)
- [x] 1.5 `apply(state, action)` — ALL 11 actions resolve (round 3: financing 0b420cd,
      exit/lifecycle da817fe). One test file per action; every rejection pins whole-state value
      equality + unmoved RNG. All actions draw 0 this round.
- [x] 1.6 §7 invariant test (f39cb53): cards.json 33/33 deltas ⊆ five keys; behavioral flatten()
      diff over every action; structural reconciliation; directionality signs; score-field ban.
- [x] 1.7 golden replay-determinism contract + purity guards (8a9804d). Adapted from the plan's
      draw-order snapshot: all 11 actions draw 0 today, so the golden pins REPLAY — (seed 42,
      scripted 15-action log covering every action + 2 no-op rejections + a full venture lifecycle)
      -> byte-identical end state via the shared `test/helpers/flatten.dart` walker + final cursor.
      Golden `test/golden/replay_seed42_v1.txt` is STREAM-BREAKING to touch (docs/03 §6): never edit
      in place — version a v2 + schemaVersion bump (the first real RNG draw is that moment).
      `purity_guard_test.dart` adds doc 03 §4's static guards: no double/.toDouble(/dart:math/
      DateTime/Random( in lib code (comments exempt), no flutter dep in pubspec.

## Deferred hooks left in the engine (resolve with later layers)
- ~~Reroll provisional 0 draws~~ RESOLVED in round 4: the real redraw is live (golden v4).
- ~~OPERATE step 5 event hook~~ RESOLVED in round 4: event cards auto-resolve (25/100 dial).
- ~~Run-init layer~~ RESOLVED in round 4 (lib/init.dart).
- ~~"Draw a fresh hand" on advance~~ RESOLVED in round 4 (the next OPERATE's step-0 draw).
- ~~PlayConsumable/SellPlay plays[] inventory~~ RESOLVED in round 4 (playsHeld + gates).
- ~~PartnerEngine layer~~ RESOLVED in round 10 (HirePartner + accrual + ScheduledCost; partner
  cards back in the pool). REMAINING SLIVER: the v1 card schema has no fixed-cost face — when
  content adds one, map it in actionForCard (the HirePartner channel is live + unit-tested).
- ~~Raise-card growth riders~~ RESOLVED in round 10 (RaiseEquity rider channel; dilution prices
  pre-rider).
- ~~HOT_WINDOW / MARKET_READ market flags~~ RESOLVED in round 10 (armed/hint + flat-round
  expiries; hot exit = live x135/100; marketRead is honest — modal NEUTRAL at a boundary,
  certain temp mid-state; model.dart documents the knowability limit).
- ~~ExitVenture TEMPORARY live-multiple payload~~ RESOLVED in round 10: payload-carrier BY
  DESIGN; exitOfferAction fills it with the venture's drifted multipleMilli; the per-round EXIT
  OFFER ticket (GameState.exitOffer) is live.
- PLY_SECONDARY_SALE engine-computed proceeds (equity at live mark): the card's cash face is the
  0 placeholder; the per-kind resolver computation is future work (content_lint documents it).
- ScheduledCost is the MINIMAL slice ({ventureId?, cashDeltaCents, recurring}); EARN_OUT needs
  doc 02's PCT_EBITDA/PCT_EV bases + roundsLeft countdown when it ships.
- TakeDebt COLD-market gate (doc 02 §3.3): UNBLOCKED (market.temp exists) but needs the
  COLD-priced-variant card flag from content — wire both together.
- T5 endless termination + escalating modifiers: DEADLINE_CHECK currently always advances in T5
  (no canonical deadline exists); the endless layer owns ending it.
- ReinvestBaseline follows economy-model.json round-progress decay (doc 02 §3.9's reinvestCount
  curve superseded; JSON is authoritative per CLAUDE.md).

## Audit notes (round-4 verifier, engine trusts upstream by design)
- Action payloads are raw magnitudes the content layer guarantees (e.g. a negative `raiseCents` or
  `costCents` would invert an action's economics). Consistent with "the engine charges exactly what
  it is handed"; the content layer must validate face values when it lands. Rejections never touch
  actionLog; all clamps verified at the apply sites.

## Then
- Phase 2: content pipeline (typed JSON load + json_serializable codegen + CI).
- Phase 3: ~~Flutter app shell~~ DONE (3.0). ~~Screens 3.1-3.6~~ DONE (rounds 7-8). ~~Round 9
  emulator run gate + on-device audit~~ **PASSED (round 9 above) — PHASE 3 SCREENS COMPLETE
  (emulator-verified, docs/screenshots/).** ~~Round 10 gameplay completeness~~ **LANDED (round 10
  above; schemaVersion 5).** ~~R11 UI affordances~~ **LANDED (round 11 above; exit flow +
  partners + target picker + consumable/reinvest affordances; app 34 tests).** ~~R12 balance
  harness + tuning~~ **LANDED (round 12 above; organic growth + canonical recap + tool/sim.dart
  Monte-Carlo + the §8 dial pass; schemaVersion 7, golden v7). Untouched dials left for a future
  pass: event 25%, exit band 900..1200, hot 135/100, passive yield 35/200, hand-size dist, shop
  count.** **NEXT: Phase 4 save/persistence (+ S9 Desk meta).**
  Carried punch list (R8-R11 deferrals): ~~ACT-side sell/play affordance~~ DONE R11 (USE/SELL
  sheet; the SHOP key stays inert 'IN ACT' — consider widening the engine SellPlay gate to shop
  with the docs/05 S5 wording, draw-free so goldens hold); ~~venture rail as target picker~~
  DONE R11; ~~REINVEST amount picker~~ DONE R11 (scaling reroll fee still the flat $15k dial —
  needs the doc 02 §4 rerollCost formula content-side); ~~EXIT flow UI~~ DONE R11; small-delta
  juice (floating ±$ deltas, stat tick pops); held plays with per-venture deltas always target
  the platform (no aim step on the USE sheet); digest drift row blurs neglect-multiple loss
  (split when the engine emits a drift event); victory 'runs to get here' needs Phase-4 meta (NOW AVAILABLE — settleRun/MetaState landed
  R13, R14 wires the screen); ~~engine `describeAction` display helper for the S8 round-line~~
  DONE R13 (lib/describe.dart — describeAction/describeRunStep, money-formatted, the cents leak
  fixed); ~~venture display-name layer (V1 vs NIMBUS)~~ DONE R13 (Venture.displayName getter;
  seed -> QUANTA); apk-debug rebuild gate (skipped R11 on the C: free-space watch).
- Phase 4: save/persistence (+ S9 Desk meta). **ENGINE SIDE LANDED R13, APP SIDE LANDED R14** —
  COMPLETE. R13: serialize/migrate/meta/describe. R14: SaveStore file I/O (path_provider, temp-write
  + rename, meta .bak, eager autosave + lifecycle flush), the S9 Desk + founder picker, title
  CONTINUE, the RunStep journal recorded as the player dispatches, RUN_OVER settlement, venture
  names, CASH juice, the boot ERROR screen. apk-debug gate PASSED (R11 deferral cleared). Phase 5:
  balance sim harness — DONE R12 (CI-gated acceptance band).
- **R15 engine/infra + AUDIT-2026-06-09 fixes: LANDED** (schemaVersion 8 -> 9). Schema-9 features:
  (a) DEALMAKER +1-play grant — `GameState.backgroundId` now carried on the run state (was only in
  the save's startConfig) so `playsGrantedForRound(tier, backgroundId)` = `playsPerRound(tier)` +
  `background.extraPlaysPerRound`, honored uniformly by runOperate/runDeadlineCheck/_clearTier;
  (b) PLY_SECONDARY_SALE got its real resolver (`PlayConsumable.secondaryBp` sells Δownership at
  the live mark; clamped to the held stake so own never goes negative; $0 fire-sale of paper still
  emits) — closes audit L3's `$0 placeholder`; (c) T5 ENDLESS escalation (closes L1): fixed-length
  antes (10 rounds) with a geometric rising survival bar (`entry x 1.5^ante`, satMul-saturated),
  fails-out MISSED_DEADLINE at the ante deadline, never WINS — bounds run length. AUDIT fixes:
  M3 `satMul` net-worth overflow guard (money.dart, cap 2^60, routes the two netWorthCents
  products, changes NO in-range golden); L2 engine reroll curve ($15k base +$15k/use cap $150k,
  resets per round; app delegates via the aliased engine_resolver import — no app math); M1
  content-copy sync test (pins data/ == app/assets/data/ == packages/engine/assets/); H2 app CI
  (a second `app` job: flutter analyze + flutter test, PINNED Dart 3.12.1/Flutter 3.44.1, on push
  AND pull_request); L4 stale-comment sweep. Golden v9 via the locked procedure; v8 sealed in place.
- **R16 critic/finisher: PHASE 4 COMPLETE — build arc CLOSED.** Adversarial static audit of R13-15
  (save correctness, schema-9, §7/purity/determinism) found NO correctness defect; all guards
  unweakened. EMULATOR-VERIFIED on Pixel_8 (debug APK, screenshots in docs/screenshots/r16-*.png):
  S0 title fresh = NO CONTINUE (correct); THE DESK = Lv 0/0 REP, 4 founder backgrounds, CARDS 0/35
  · SECTORS 4/6; run start = venture NAME (QUANTA) in HUD/rail/exit-ticket (not V1), exit offer +
  partner ticket in the blotter, reroll shows the engine scaling fee ($15k SHOP base / $26k mid-
  curve ACT); **SAVE/RESUME VERIFIED — force-stop mid-run, relaunch, title showed CONTINUE
  `T1 · R1 · #3717`, tapping it restored the EXACT state (cash $22,520 / NW $63,221 / round / tier /
  holdings / hand / exit offer all byte-identical) via the engine replay reconstruction.** `main`
  fast-forwarded to the build head (was the seed commit; HEAD is a descendant — zero commits lost);
  the stale `feat/phase-0-toolchain` name retired. Engine 737 tests + app 50 tests green, analyzer
  clean. **PHASE 4 (save/persistence + S9 Desk meta) COMPLETE.**

  AUDIT-2026-06-09 DISPOSITION (all findings): H1 no-save FIXED (R13/R14, emulator-verified R16);
  H2 app-CI FIXED (R15); M1 content-sync FIXED (R15 sync test); M2 stale-branch FIXED (R16 main
  fast-forward); M3 overflow FIXED (R15 satMul); M4 trust-boundary ACCEPTED-by-design (content lint
  is the boundary; logged); L1 endless-stub FIXED (R15 escalation); L2 reroll-dial FIXED (R15 engine
  curve); L3 deferred-hooks PARTIAL — PLY_SECONDARY_SALE FIXED (R15), but EARN_OUT bases / countdown,
  TakeDebt cold-market content flag, and the partner FIXED-COST face on the v1 card schema remain
  honest deferrals (wired-but-minimal, no card uses them today); L4 comment-drift FIXED (R15 sweep);
  L5 main() error-screen FIXED (R14 boot ERROR screen); L6 iOS NOT STARTED (honest deferral —
  Android-first is the plan); L7 stale index.lock OPERATIONAL (transient, cleared).

  WHAT REMAINS (next-session ground truth): (1) iOS build/config (L6) — never started, Android-only
  today. (2) The L3 minimal slices — EARN_OUT countdown bases, TakeDebt cold-market gate flag, the
  partner fixed-cost card face — wired but not fleshed; widen the card schema + content lint when
  those cards are authored. (3) Deeper meta/unlock content — the Desk shows the unlock TREE (cards
  0/35, founder gating at 500k rep) but the actual unlock payouts/cosmetics are a thin slice; the
  rep formula + unlock thresholds are tuning dials still partly UNSET in economy-model.json.

## Decisions log (durable choices, newest first)
- 2026-06-09: **Branch hygiene (audit M2, round 16): `main` FAST-FORWARDED to the build head.** `main`
  sat at the seed commit (2c4233d) and was a strict ANCESTOR of the build HEAD (8d64bdb + R16 docs),
  so the fast-forward is loss-free (zero commits dropped — verified `merge-base --is-ancestor main
  HEAD` == 0 before moving). The meaningless `feat/phase-0-toolchain` name is retired. `main` is now
  the real trunk at Phase-4-complete. NEVER force-push; this was a clean FF only.
- 2026-06-09: **schemaVersion 8 -> 9 (round 15: Dealmaker grant + secondary-sale resolver + endless
  escalation).** STREAM-BREAKING for RUN saves (the run flatten widened with `backgroundId`, the
  persisted PlayConsumable journal action gained `secondaryBp`, and T5 endless behavior MOVED), so
  `runMigrations` has NO v8->9 step — any v<9 run is ABANDONED (drop run, keep meta) per docs/06 §3.
  META migrates additively (the 8->9 step is a pure version bump; MetaState unchanged). Golden v9 via
  the locked docs/03 §6 procedure; v8 retired sealed-in-place. The `satMul` net-worth guard (audit
  M3, 2^60 cap) and the endless geometric ante bar are co-designed: escalation bounds run length so
  net worth dies long before the cap; satMul is the backstop against a silent int64 wrap. The reroll
  fee curve (audit L2) is an ENGINE resolver function the app calls (no app-side game math — the
  flutter-app.md rule holds).
- 2026-06-09: **schemaVersion 7 -> 8 (round 13 save/persistence; the PERSISTED-CONTRACT bump, NOT a
  moved stream).** The run save (docs/06) is the minimal record `{seed, cursor, startConfig:{runId,
  backgroundId}, actionLog}` replayed through the engine; the on-disk actionLog is serialize.dart's
  typed RunStep journal (the "parallel typed action log" the work order sanctioned over extending
  the display LoggedAction — lower regression risk, and replay regenerates the display log
  identically). Also additive to the state: `Venture.displayName` (a pure id+sector getter,
  flatten-serialized — seed v1 -> QUANTA). The RNG DRAW ORDER IS UNCHANGED (cursor 28); the bump is
  the persisted contract + the widened flatten, so a v7 run is ABANDONED (docs/06 §3), meta
  migrates additively. Golden v8 via the locked docs/03 §6 procedure; v7 sealed-in-place.
  DESIGN CHOICE: flatten() moved into lib/serialize.dart (docs/06 §2.2 — the load path and the
  invariant/golden tests share ONE walker); the test helper re-exports it. Founder-background +
  reputation NUMBERS are tuning dials (economy outOfScope leaves them unset).
- 2026-06-08: **schemaVersion 5 -> 6 -> 7 (round 12 balance: organic growth, canonical recap,
  the tuning pass).** Two bumps for moved VALUES (the draw ORDER never changed; cursor 28 across
  v5/v6/v7): v6 = organic growth applied at OPERATE step 3a (partnered ventures only; founding
  operator attached at initRun) + the canonical resolve-time recap (the $30k faces stripped);
  v7 = the doc 01 §8 dial pass (organic 0.20, carrySeed 0.37, deadlines [9,10,9,10], interestMax
  0.12, crunch rateMul 1.3 / entry 0.12, recapPct 0.16 — bands met at N=2000: floor 41.5%,
  greedy bankruptcy 11.2%, smart 47.1%). Tuning measurement = tool/sim.dart (full-model
  Monte-Carlo, 3 policies, integer-only, deterministic); gates = test/sim_test.dart. The JSON
  (economy-model.json) is the dial ledger — every R12 turn is recorded in its tuningKnobs notes.
- 2026-06-08: **schemaVersion 4 -> 5 (round 10 gameplay completeness; the stream MOVED — the
  third pre-declared break).** The hand routine appends the exit-offer pair (venture pick +
  `(live x (900 + nextInt(301))) ~/ 1000` band, floored 1000); the v5 pool re-includes partners
  and dead-draw-filters venture cards at full slots. Partner +EBITDA ACCRUES pre-yield (doc 02
  §3.5 prose over its pseudocode); scheduled costs fire alongside yield (doc 02's step-5 position
  inside doc 01 §6.1 step 3); hot exit = live x135/100 (driftBubble 1.35 as the hot factor);
  marketRead reveals the certain mid-state temp / the modal NEUTRAL at a boundary (never a stream
  peek); raise dilution prices PRE-rider. Dials (no canon): exit-offer band 900..1200 permille,
  hot factor 135/100. Golden v5 cursor 28; v4 retired sealed. New-family flatten paths emit only
  when set (the appeared/disappeared convention).
- 2026-06-07: **Display formatting is an ENGINE concern** (round 6). flutter-app.md's "format
  money/multiples through money.dart" is enforced literally: `formatMultiple` joined `formatMoney`
  in the engine; app widgets carry ZERO cents/milli/bp arithmetic, even presentation-only. Any
  future display shape (percent, bp, rate) gets an engine helper first.
- 2026-06-07: **The app bundles /data COPIES, not engine package assets** (Task 3.0). The engine
  purity guard bans any `flutter:` key in its pubspec, and Flutter cannot bundle a dependency's
  assets unless that dependency declares them, so `app/assets/data/*.json` are byte-identical
  build copies pinned by an app-side staleness test; the engine keeps parsing raw strings
  (loadCards/loadEconomy). Smoke-screen seed 42 is demo plumbing, not canon; the save layer owns
  real seed lifecycle. APK debug build deferred on host disk space (gradle caches intact).
- 2026-06-07: **schemaVersion 3 -> 4 (deal-flow layer; the stream MOVED — the second pre-declared
  break).** Hand draw opens OPERATE (doc 03 §3.1 step 1); event roll sits at doc 01 §6.1 step 5
  (economy roundOrder wins over doc 03 §3.1's step-3 listing); endTurn deals the shop; Reroll
  really redraws. Dials (no canon): event chance 25/100, hand size 3+nextInt(3), shop offers 3.
  Partner cards excluded from the v1 pool (PartnerEngine unmodeled); raise riders dropped
  (RaiseEquity has no rider channel); financing offers exercise in ACT via the locked
  play-costing actions; consumable purchase mirrors are stripped at play (paid at buy). Decks
  hold card IDS; flatten serializes them as indexed string paths. initRun takes EconomyConfig and
  no RNG. Golden v4 cursor 28; v3 retired sealed. The engine is Tier-1-slice feature-complete.
- 2026-06-07: **Round-3 audit closed the round-loop layer with zero engine-code changes** (test
  hardening + plan errata only; schemaVersion stays 3, golden v3 untouched). Verdicts now pinned
  by test: tier-clear is evaluated ON the deadline round (clear advances, bar-1 dies, T4 = win);
  the reseed cap holds for negative-equity and low-multiple platforms; compoundCents is monotone
  in r; the bankruptcy telegraph stays sound across a tier clear because meters are DERIVED (the
  post-reseed end-of-round state re-flags runwayOk).
- 2026-06-06: **schemaVersion 2 -> 3** (round machine; FIELD ADDITIONS to flatten only — the RNG
  draw order is unchanged from v2; golden v3 versioned, v2 retired untouched). **Reseed cap**:
  seedEbitda = min(doc 01 §3.3 formula, EV~/8) so a tier reseed never increases derived NW — the
  doc's stated "<= what you had" property wins over its raw formula in the cash-heavy corner;
  multi-venture reseed targets ventures.first; netWorthAtTierEntry snapshots PRE-reseed. T5 has
  no deadline (doc 01 §5 "—"); DEADLINE_CHECK always advances there. Meters: max-crunch runway
  rate 2520bp; growth gauges by integer bisection over per-step-trunc compounding, bracket
  [1000..3000] needed / [0..3000] realized. Plays matrix: Reroll/PlayConsumable/SellPlay free,
  the other 8 actions cost 1 (decrement on success only).
- 2026-06-06: **schemaVersion 1 -> 2** (OPERATE = first real RNG draws; golden v2 versioned, v1
  retired untouched). Drift is computed per venture at apply time (doc 01 §7.3), never stored
  per sector. Passive cash yield 35/200 is a TUNING DIAL pending the spreadsheet's
  CASH_YIELD_BP_PASSIVE. MarketTemp/PhaseId enum declaration order is replay-contract-locked
  (flatten serializes .index).
- 2026-06-06: **Title renamed MULTIPLE → MULTIPLES**; tagline "broke to billionaire" replaced with
  **"get in. get rich. get out. Wait, that's allowed?!"** across all docs, mockups, data, and prototype files.
  The word "multiple" as a game term (stat labels, MULTIPLE ARBITRAGE flash) is unchanged by design.
- 2026-06-06: **Art direction locked: "THE TERMINAL"** (retro dealmaker terminal; black bezel, white phosphor
  numbers, blue as accent-only, green NW-surge signature moment, label-over-number, no cryptic glyphs).
  Canon: `docs/07-art-style-bible.md` + `docs/mockups/layout-a-v4.html` + `docs/mockups/ui-v4-all-screens.html`.
  Earlier mockups in docs/mockups/ are superseded exploration. Skin-only; engine untouched.
- 2026-06-06: `interestDue` is rate-parameterized. economy-model.json defines an 8-14% (800-1400bp) band
  with the live rate drawn per round; the prototype's hardcoded 12% was not canonical. Live rate draw is
  the drift/Operate layer's job, not the frozen-formula layer.
- 2026-06-06: Reconciled doc 03 §4.1 to milli-units x1000 for `multiple` (it had wrongly said basis
  points x10000). Single source of truth now: cents / multipleMilli x1000 / ownershipBp x10000.
- 2026-06-06: Monorepo with `packages/engine` (pure Dart) + `app` (Flutter), one-way dependency.
- 2026-06-06: Dart installed manually (winget extract is broken, exit 92); Flutter deferred to Phase 3.

## Watch out for
- Don't reintroduce `double` into the engine. Don't let any code write net worth. Don't weaken the §7
  invariant or golden tests to make something pass.
- 2026-06-07: **Project moved C: - D:\claude\aura-maxxing** (C: copy deleted; 1026 files, git fsck clean, 542 tests green post-move; no-space path chosen because D: disables 8.3 names). Cowork folder mount must be re-pointed next session.  
