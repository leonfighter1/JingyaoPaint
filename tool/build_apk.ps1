# Builds release APKs into dist\.
#
#   powershell -ExecutionPolicy Bypass -File tool\build_apk.ps1             # small: one APK per CPU type
#   powershell -ExecutionPolicy Bypass -File tool\build_apk.ps1 -Universal  # one big APK for every phone
#
# The small builds hold only one CPU type's native code each, so they are
# much smaller. Almost every phone from the last several years needs the
# arm64 one; old 32-bit phones need armv7; x86_64 is for emulators.
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [switch]$Universal
)

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    $env:Path += ';C:\dev\flutter\bin'
}
if (-not $env:JAVA_HOME) {
    $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
}
Set-Location $Root

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$dist = Join-Path $Root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$outputs = 'build\app\outputs\flutter-apk'
# Symbols for reading crash stack traces of the obfuscated build; not shipped.
$symbols = Join-Path $Root "build\symbols\$version"

if ($Universal) {
    flutter build apk --release --obfuscate --split-debug-info=$symbols
    if ($LASTEXITCODE -ne 0) { Write-Output 'BUILD FAILED'; exit 1 }
    $apks = @{ 'app-release.apk' = "JoyPainting-v$version.apk" }
} else {
    flutter build apk --release --split-per-abi --obfuscate --split-debug-info=$symbols
    if ($LASTEXITCODE -ne 0) { Write-Output 'BUILD FAILED'; exit 1 }
    $apks = [ordered]@{
        'app-arm64-v8a-release.apk'   = "JoyPainting-v$version-arm64.apk"
        'app-armeabi-v7a-release.apk' = "JoyPainting-v$version-armv7.apk"
        'app-x86_64-release.apk'      = "JoyPainting-v$version-x86_64.apk"
    }
}

foreach ($name in $apks.Keys) {
    $out = Join-Path $dist $apks[$name]
    Copy-Item (Join-Path $outputs $name) $out -Force
    Write-Output ("APK: {0} ({1:N1} MB)" -f $out, ((Get-Item $out).Length / 1MB))
}
