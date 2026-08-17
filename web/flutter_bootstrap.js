{{flutter_js}}
{{flutter_build_config}}

// CanvasKit can lose its WebGL context after repeated hot restarts or when a
// browser GPU process runs out of memory. Add ?cpu=true during development to
// keep CanvasKit in CPU-only mode. Normal and production URLs remain GPU-based.
const forceCpuRendering =
    new URLSearchParams(window.location.search).get('cpu') === 'true';

_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: forceCpuRendering,
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
