# JingyaoPaint (靖瑶的画板)

JingyaoPaint is a cute drawing app for Android phones and tablets, built with Flutter.
The UI is in Simplified Chinese by default, with English available in Settings.

What it does:

- **Drawing**:
  - 10 tools: pen, pencil, marker, highlighter, spray, rainbow, stamps, text, move and a round eraser.
  - Pressure-sensitive strokes, opacity, shapes with fill, mirror drawing and paper colors.
- **Canvas**:
  - Pinch to zoom and pan.
  - Brushes and colors live in a drawer that opens from the "画笔 · 颜色" button.
  - That button and the undo bar can be dragged to any corner of the paper.
- **Paintings**:
  - Autosave, and a gallery (我的画作) with dates and a year filter.
  - Send as PNG, JPG, PDF or an editable `.jypaint` file, and print.
  - Open `.jypaint` files received from other apps.
- **Look**:
  - 5 portable JSON themes checked against WCAG contrast.
  - 4 bundled cute fonts.
  - Works on tablets in both orientations.

Package name `com.personal.jingyaopaint`, Dart package `jingyao_paint`. The version is in `pubspec.yaml`.

## Prerequisites

The project is developed on Windows 10/11 with VS Code. These are the versions it's known to work with:

| Tool | Version used | Needed for |
|---|---|---|
| [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (includes Dart) | Flutter 3.47.8, Dart 3.13 | Everything. `pubspec.yaml` requires Dart `^3.13.7`. |
| [Git for Windows](https://git-scm.com/download/win) | any recent | Flutter itself; Git Bash is handy for scripts |
| [VS Code](https://code.visualstudio.com/) + extensions **Dart** and **Flutter** (`Dart-Code.dart-code`, `Dart-Code.flutter`) | latest | Editing, F5 debugging, hot reload |
| [Android Studio](https://developer.android.com/studio) | latest | Ships the JDK (JBR) that Gradle uses, plus the SDK and emulator manager |
| Android SDK packages | see below | Building and running on Android |
| Google Chrome | latest | Fastest debug target (no emulator needed) |
| Visual Studio 2022 with "Desktop development with C++" *(optional)* | 2022 | Windows desktop build only |

### Android SDK packages

Install these into `%LOCALAPPDATA%\Android\Sdk` (Android Studio → SDK Manager, or the command line):

- Android SDK Platform 34, 35 and 36
- Android SDK Build-Tools 36.0.0
- NDK (Side by side) 28.2.13676358
- Android SDK Platform-Tools (`adb`)
- Android SDK Command-line Tools (latest)
- Android Emulator, plus an x86_64 Google APIs system image (Android 15 or 16) for testing

Gradle 9.3.1 is downloaded automatically by the wrapper. The Android build targets Java 17.

> **Gotcha:** don't install packages with `sdkmanager.bat "platforms;android-36"` from cmd/PowerShell.
> The batch file splits arguments at `;`. Use the Android Studio SDK Manager, or:
> ```powershell
> & "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\android.exe" --sdk="$env:LOCALAPPDATA\Android\Sdk" sdk install "build-tools;36.0.0"
> ```

### One-time setup

1. Add Flutter to `PATH` (this project uses `C:\dev\flutter\bin`).
2. Point Gradle at Android Studio's JDK: `setx JAVA_HOME "C:\Program Files\Android\Android Studio\jbr"`.
3. Accept the Android licenses: `flutter doctor --android-licenses`.
4. To use emulators, turn on CPU virtualization in the BIOS. Then enable **Windows Hypervisor Platform**:
   - Open "Turn Windows features on or off".
   - Check Windows Hypervisor Platform.
   - Reboot.
5. Optional (Windows desktop builds): turn on **Developer Mode** in Windows Settings so Flutter can create symlinks.
6. Check everything:
   ```powershell
   flutter doctor -v
   ```
   You need green checks for Flutter, Android toolchain, Chrome and VS Code. Visual Studio is only needed for Windows builds.

## Testing environments

| Environment | How to get it | Use it for |
|---|---|---|
| Chrome | Installed with Chrome | Quick UI work and hot reload. "Save to album" downloads a file instead, and Android-only features (open with, album) don't apply. |
| Phone emulator | AVD `medium_phone` (1080×2400) | Default phone layout |
| Tablet emulator | AVD `medium_tablet` (2560×1600) | Side rail, landscape/portrait, paper scaling |
| Real Android device | USB debugging on, then `adb devices` | Stylus pressure, real pinch, sharing to chat apps, printing |

Create and start the emulators with Android Studio's Device Manager, or:

```powershell
$android = "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\android.exe"
& $android emulator create medium_tablet
& $android emulator start medium_tablet
```

If an emulator shows a black screen, cold-boot it:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd medium_tablet -no-snapshot-load -gpu host
```

## Run and debug

From the workspace root (`C:\AIProjects`), open VS Code and press **F5**. `.vscode/launch.json` offers three configurations:

- JingyaoPaint (Chrome)
- JingyaoPaint (phone / emulator)
- JingyaoPaint (Windows)

From a terminal in this folder:

```powershell
flutter pub get
flutter run -d chrome          # browser
flutter devices                # list emulators/phones
flutter run -d emulator-5554   # a running emulator
```

## Tests

```powershell
flutter analyze   # must report "No issues found!"
flutter test      # unit, rendering and widget tests
```

What the tests cover:

- **`test/brush_test.dart`**: pixel tests for brushes and shapes, the text tool, moving strokes and save/reload.
- **`test/model_test.dart`**: the painting store, autosave and import.
- **`test/export_test.dart`**: real PNG, JPEG and PDF output, and `.jypaint` round trips.
- **`test/theme_test.dart`**: theme JSON and WCAG contrast.
- **`test/widget_test.dart`**: the whole UI, including:
  - phone, tablet and landscape sizes;
  - both languages;
  - large text;
  - Flutter's accessibility guidelines: text contrast, 48 dp tap targets and labels.

Before calling a change done, run analyze and test, then try it on the tablet emulator.

## Build a release APK

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_apk.ps1             # one small APK per CPU type
powershell -ExecutionPolicy Bypass -File tool\build_apk.ps1 -Universal  # one big APK for every device
```

APKs land in `dist\` as `JingyaoPaint-v<version>-<abi>.apk`:

- **arm64**: almost every phone and tablet.
- **armv7**: old 32-bit phones.
- **x86_64**: emulators.

Builds are obfuscated. Crash symbols go to `build\symbols\<version>`; keep them to read stack traces. The APK is signed with the debug key, which is fine for sideloading but not for the Play Store.

Install on a running emulator or a connected phone:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r dist\JingyaoPaint-v1.6.0-x86_64.apk
```

To release a new version:

1. Bump `version:` in `pubspec.yaml`.
2. Bump `appVersion` in `lib/settings_page.dart`.

## Project layout

```
lib/
  main.dart            app shell: tabs or side rail, theme, incoming files
  drawing/             canvas page, strokes, drawing controller, text editor
  gallery/             My Paintings page and storage (file / browser / memory)
  share/               send, print, import, .jypaint format
  theme/               portable JSON themes, contrast math, fonts (see theme/README.md)
  widgets/             drop-down menu, draggable corner controls
  l10n.dart            all UI text, zh and en
  settings.dart        remembered choices (brush, colors, corners, theme…)
assets/                logo, theme JSON files, fonts and their OFL licenses
android/               Android host app (MainActivity handles "open with")
tool/                  build_apk.ps1, watch_build.ps1, make_icons.ps1
docs/appdev/           FEATURES.md, MISTAKES.md, DEVLOG.md
test/                  see Tests above
```

Read `docs/appdev/MISTAKES.md` before making changes. Its rules come from problems this project has already hit.
