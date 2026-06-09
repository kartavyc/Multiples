// Custom Flutter web bootstrap: force CanvasKit CPU-only rendering on iOS
// Safari, where the default WebGL path black-screens (a documented
// Flutter/WebKit issue). Every other browser keeps the faster GPU path.
{{flutter_js}}
{{flutter_build_config}}
(function () {
  var ua = navigator.userAgent || "";
  var isIOS =
    /iPad|iPhone|iPod/.test(ua) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  _flutter.loader.load({
    config: isIOS ? { canvasKitForceCpuOnly: true } : {},
  });
})();
