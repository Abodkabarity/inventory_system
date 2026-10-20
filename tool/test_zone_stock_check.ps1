param([switch]$Live)
$ErrorActionPreference = 'Stop'
$zoneWorkspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $zoneWorkspaceRoot
$zoneRenderer = [System.IO.Path]::GetFullPath((Join-Path $zoneWorkspaceRoot 'test/canvaskit'))
$zoneExpectedParent = [System.IO.Path]::GetFullPath((Join-Path $zoneWorkspaceRoot 'test'))
$zoneCreatedRenderer = $false
try {
    $zoneDataArgs = @('test', '--no-pub', 'test/zone_stock_check_remote_ds_test.dart')
    if ($Live) {
        $zoneDataArgs += @('--dart-define=RUN_STOCK_CHECK_LIVE_TEST=true', 'test/zone_stock_check_live_test.dart')
    }
    & flutter @zoneDataArgs
    if ($LASTEXITCODE -ne 0) { throw 'Zone Stock Check data tests failed.' }
    if (-not $zoneRenderer.StartsWith($zoneExpectedParent + [System.IO.Path]::DirectorySeparatorChar)) { throw 'Unexpected renderer target.' }
    if (Test-Path -LiteralPath $zoneRenderer) { throw 'Renderer folder already exists.' }
    $zoneFlutterRoot = Split-Path (Split-Path (Get-Command flutter).Source -Parent) -Parent
    New-Item -ItemType Directory -Path (Join-Path $zoneRenderer 'chromium') | Out-Null
    $zoneCreatedRenderer = $true
    foreach ($zoneAsset in @('canvaskit.js', 'canvaskit.wasm')) {
        Copy-Item -LiteralPath (Join-Path $zoneFlutterRoot "bin/cache/flutter_web_sdk/canvaskit/chromium/$zoneAsset") -Destination (Join-Path $zoneRenderer "chromium/$zoneAsset")
    }
    Copy-Item -LiteralPath (Join-Path $zoneFlutterRoot 'bin/cache/artifacts/material_fonts/roboto-regular.ttf') -Destination (Join-Path $zoneRenderer 'roboto.ttf')
    flutter test --no-pub --platform chrome test/zone_stock_check_widget_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Zone Stock Check browser tests failed.' }
} finally {
    if ($zoneCreatedRenderer) {
        foreach ($zoneAsset in @('chromium/canvaskit.js', 'chromium/canvaskit.wasm', 'roboto.ttf')) {
            Remove-Item -LiteralPath (Join-Path $zoneRenderer $zoneAsset)
        }
        Remove-Item -LiteralPath (Join-Path $zoneRenderer 'chromium')
        Remove-Item -LiteralPath $zoneRenderer
    }
    Pop-Location
}
