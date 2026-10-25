# Shows the progress of a running APK build (tool\build_apk.ps1).
# Open a second terminal and run:
#   powershell -ExecutionPolicy Bypass -File tool\watch_build.ps1
#
# Progress is real, not guessed: a release build compiles the Dart code once
# per phone CPU type (arm, arm64, x64), producing one app.so each, then
# packages the APK. This counts those files as they appear.
param([string]$Root = (Split-Path $PSScriptRoot -Parent))

$build = Join-Path $Root 'build\app'
$started = Get-Date
$steps = 5   # assets, 3 x app.so, APK
while ($true) {
    $assets = Test-Path (Join-Path $build 'intermediates\flutter\release\flutter_assets\AssetManifest.bin')
    $so = @(Get-ChildItem (Join-Path $build 'intermediates\flutter\release') -Recurse -Filter app.so -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $started.AddHours(-2) }).Count
    $apk = Get-ChildItem (Join-Path $build 'outputs\flutter-apk\app-release.apk') -ErrorAction SilentlyContinue
    $done = [int]$assets + $so + [int]($null -ne $apk)

    $phase = if ($apk) { 'APK 已生成 / APK ready' }
        elseif (Get-Process dartaotruntime, gen_snapshot -ErrorAction SilentlyContinue) { "Dart 编译成原生代码 / compiling Dart ($so/3 CPU types done)" }
        elseif ($so -ge 3) { '打包 APK / packaging the APK' }
        elseif (Get-Process java -ErrorAction SilentlyContinue) { 'Gradle 准备中 / Gradle preparing' }
        else { '没有正在运行的编译 / no build running' }

    $pct = [int](100 * $done / $steps)
    $bar = ('#' * [int]($pct / 5)).PadRight(20, '.')
    $elapsed = (Get-Date) - $started
    Write-Host -NoNewline ("`r[{0}] {1,3}%  {2:mm\:ss}  {3}          " -f $bar, $pct, $elapsed, $phase)
    if ($apk) { Write-Host ''; Write-Host "完成 / Done: $($apk.FullName) ($([math]::Round($apk.Length / 1MB, 1)) MB)"; break }
    Start-Sleep -Seconds 3
}
