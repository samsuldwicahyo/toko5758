param()

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $projectRoot "release\android"

New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

Push-Location $projectRoot
try {
    flutter build appbundle --release --target-platform android-arm,android-arm64 --no-pub
    flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --no-pub

    Copy-Item "build\app\outputs\bundle\release\app-release.aab" `
        (Join-Path $releaseDir "toko5758-release.aab") -Force

    Copy-Item "build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk" `
        (Join-Path $releaseDir "toko5758-armeabi-v7a-release.apk") -Force

    Copy-Item "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" `
        (Join-Path $releaseDir "toko5758-arm64-v8a-release.apk") -Force
}
finally {
    Pop-Location
}
