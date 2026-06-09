# apply_web_patch.ps1
# Applies the MULTIPLES WASM-only patch to the Flutter SDK's build_web.dart:
# removes the JsCompilerConfig(...) entry that --wasm emits as a dart2js
# fallback, replacing it with an explanatory comment. Idempotent + reversible.
# See app/tool/build_web.bat and README "Building" for the rationale.

$ErrorActionPreference = 'Stop'
$file = 'C:\src\flutter\packages\flutter_tools\lib\src\commands\build_web.dart'

if (-not (Test-Path $file)) {
    Write-Error "build_web.dart not found at $file"
    exit 1
}

$text = Get-Content -Raw $file

if ($text -match 'LOCAL PATCH \(MULTIPLES publish\)') {
    Write-Host "[apply_web_patch] Already patched - nothing to do."
    exit 0
}

# The exact JsCompilerConfig fallback block emitted under the `useWasm` branch.
# Matched loosely on whitespace so a reformat upstream still hits.
$pattern = @'
        JsCompilerConfig\(\s*
\s*csp: boolArg\('csp'\),\s*
\s*dumpInfo: boolArg\('dump-info'\),\s*
\s*minify: minifyJs,\s*
\s*nativeNullAssertions: boolArg\('native-null-assertions'\),\s*
\s*useFrequencyBasedMinification: !boolArg\('no-frequency-based-minification'\),\s*
\s*optimizationLevel: jsOptimizationLevel,\s*
\s*sourceMaps: sourceMaps,\s*
\s*\),
'@

$replacement = @'
        // LOCAL PATCH (MULTIPLES publish): the JS fallback is intentionally
        // omitted. The pure-Dart engine relies on 64-bit wrapping integer
        // math (SplitMix64 RNG + fixed-point sentinels) that dart2js cannot
        // represent, so a JS fallback both fails to compile and would be
        // non-deterministic. The app ships WASM-only. Revert by restoring the
        // JsCompilerConfig(...) here. Upstream tracking: a --no-js-fallback
        // flag is not yet available in this Flutter version.
'@

# Only touch the FIRST occurrence (the one inside the useWasm branch).
$rx = [regex]$pattern
if (-not $rx.IsMatch($text)) {
    Write-Error "[apply_web_patch] Could not locate the JsCompilerConfig fallback block. Flutter source may have changed; patch manually (see README) or revert with: cd /d C:\src\flutter & git checkout -- packages/flutter_tools/lib/src/commands/build_web.dart"
    exit 1
}
$patched = $rx.Replace($text, $replacement, 1)
Set-Content -NoNewline -Path $file -Value $patched
Write-Host "[apply_web_patch] Patch applied to $file"
exit 0
