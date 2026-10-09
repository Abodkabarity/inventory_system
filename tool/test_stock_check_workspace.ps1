$ErrorActionPreference = 'Stop'
$stockWorkspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $stockWorkspaceRoot
$stockRendererCreated = $false
$stockRendererDirectory = Join-Path $stockWorkspaceRoot 'test/canvaskit'
try {
    flutter test --no-pub test/stock_check_workspace_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Stock Check model/data tests failed.' }

    # Flutter 3.44's local CanvasKit handler uses a slash prefix on Windows.
    # Serve these SDK files through the test directory fallback, temporarily.
    if (Test-Path -LiteralPath $stockRendererDirectory) {
        throw "Test renderer directory already exists: $stockRendererDirectory"
    }
    $stockFlutterCommand = (Get-Command flutter).Source
    $stockFlutterRoot = Split-Path (Split-Path $stockFlutterCommand -Parent) -Parent
    $stockRendererSource = Join-Path $stockFlutterRoot 'bin/cache/flutter_web_sdk/canvaskit/chromium'
    New-Item -ItemType Directory -Path (Join-Path $stockRendererDirectory 'chromium') -Force | Out-Null
    $stockRendererCreated = $true
    foreach ($stockRendererFile in @('canvaskit.js', 'canvaskit.wasm')) {
        Copy-Item -LiteralPath (Join-Path $stockRendererSource $stockRendererFile) -Destination (Join-Path $stockRendererDirectory "chromium/$stockRendererFile")
    }
    # Use the SDK's real text font, so fixed legacy controls are measured as in the app.
    Copy-Item -LiteralPath (Join-Path $stockFlutterRoot 'bin/cache/artifacts/material_fonts/roboto-regular.ttf') -Destination (Join-Path $stockRendererDirectory 'roboto.ttf')
    flutter test --no-pub --platform chrome test/stock_check_workspace_widget_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Stock Check browser widget tests failed.' }
} finally {
    if ($stockRendererCreated) {
        # Delete only the two files created here, then the empty directories.
        foreach ($stockRendererFile in @('canvaskit.js', 'canvaskit.wasm')) {
            $stockRendererTarget = Join-Path $stockRendererDirectory "chromium/$stockRendererFile"
            if (Test-Path -LiteralPath $stockRendererTarget) { Remove-Item -LiteralPath $stockRendererTarget }
        }
        $stockFontTarget = Join-Path $stockRendererDirectory 'roboto.ttf'
        if (Test-Path -LiteralPath $stockFontTarget) { Remove-Item -LiteralPath $stockFontTarget }
        Remove-Item -LiteralPath (Join-Path $stockRendererDirectory 'chromium')
        Remove-Item -LiteralPath $stockRendererDirectory
    }
    Pop-Location
}
