# Web build — in-browser verification (PUBLISH ROUND W3)

The WASM web build (`app/build/web`, packaged as `multiples-web.zip`) was loaded
and PLAYED in a real Chrome browser on 2026-06-09, served locally with
cross-origin isolation headers via `app/tool/serve_web_isolated.py`
(COOP `same-origin` + COEP `require-corp`, `application/wasm` mime).

## Result: PASS — playable in-browser

- `self.crossOriginIsolated === true` (COOP/COEP headers verified; enables the
  threaded skwasm/CanvasKit renderer).
- The **TITLE** screen rendered: MULTIPLES wordmark, tagline
  "get in. get rich. get out. Wait, that's allowed?!", the 14X chip,
  NEW RUN / THE DESK / SETTINGS, the dark terminal skin, bezel header
  "MULTIPLES MK-I · №51D4", footer "NO ACCOUNT · OFFLINE · SAVED ON DEVICE".
- **NEW RUN** started a run; the digest recap ("THE YEAR PASSED") and the
  first-run tutorial coachmark both fired.
- The **ACT** screen rendered: the five HUD numbers (CASH $22,520,
  NET WORTH $69,759, EBITDA $7,200, MULT 6.5x, DEBT $0, OWN 100%), the RUNWAY
  gauge, the MARKET ticker, HOLDINGS (QUANTA), the DEALS blotter
  (partner / two add-ons / exit offer), and the REINVEST / REROLL / END TURN bar.
- **Interaction** worked: tapping a deal ticket opened the deal detail sheet
  (EBITDA / BUY MULTIPLE / PRICE / DEBT, with BACK / INSPECT / EXECUTE).
- **Console clean**: no errors or uncaught exceptions during the session.

## First-paint timing note

CanvasKit/skwasm initialization takes ~15-18s on the FIRST cold load (WASM +
the canvaskit chunk download); the bezel-black `#07090C` background shows until
the first frame paints. Subsequent navigations are fast. This is normal Flutter
WasmGC behavior, not a defect.

## Known minor (non-blocking)

On web, the `audioplayers` asset preload can log a caught
"audio channel op failed: TimeoutException" to the console. It is swallowed by
the backend's `_guard` (audio is non-essential) and never blocks boot or
gameplay — verified the app renders and is fully playable regardless.

## Screenshots

The browser-MCP screenshots from this session could not be persisted to disk in
the verification environment, so they live inline in the W3 run log rather than
as committed PNGs. The emulator screenshots in this folder cover the same
screens for the on-device build.
