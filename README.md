# JingyaoPaint (靖瑶的画板)

JingyaoPaint is a cute drawing app for Android and iOS phones and tablets, built with Flutter. Both apps come from the same code in this repository.
The UI is in Simplified Chinese by default, with English available in Settings.

What it does:

- **Drawing**:
  - 10 tools: pen, pencil, marker, highlighter, spray, rainbow, stamps, text, move and a round eraser.
  - Pressure-sensitive strokes, opacity, shapes with fill, mirror drawing and paper colors.
- **Editing what's drawn** (move tool):
  - Tap a stroke, or drag a box over empty paper to select several at once.
  - Drag to move, drag the corner knob to resize (same proportions), drag the top knob to turn.
  - A bar next to the selection copies, resizes, turns, recolors, changes opacity and deletes. Every change undoes in one step.
- **Canvas**:
  - Pinch to zoom and pan.
  - Brushes and colors live in a drawer that opens from the "画笔 · 颜色" button.
  - That button and the undo bar can be dragged to any corner of the paper.
- **Paintings**:
  - Autosave, and a gallery (我的画作) with dates and a year filter.
  - Send as PNG, JPG, PDF or an editable `.jypaint` file.
  - Print from an in-app preview with a big close button (Android's own print screen has none).
  - Open `.jypaint` files received from other apps.
- **Background music**:
  - Loops while you draw and pauses in the background. On/off in the ⋮ menu; volume and track in Settings.
  - Two built-in tracks, or add your own (MP3, M4A/AAC, WAV, OGG/Opus, FLAC, MIDI…).
- **Look**:
  - 5 portable JSON themes checked against WCAG contrast.
  - 4 bundled cute fonts.
  - Works on tablets in both orientations.

Package name `com.personal.jingyaopaint`, Dart package `jingyao_paint`. The version is in `pubspec.yaml` (current: **2.0.0**).

## Versions

| Version | Date | Highlights |
|---|---|---|
| **2.0.0** | 2026-10-25 | First iOS (iPhone and iPad) version. Box-select several strokes; copy, resize, turn, recolor and fade the selection; looping background music (built-in or your own, with volume); print preview with an easy way out |
| 1.6.0 | 2026-10-25 | Draggable corner controls, move tool, round eraser |
| 1.5.0 | 2026-10-25 | Tablet and landscape layouts, pinch zoom, tools drawer, smaller APKs |
| 1.4.0 | 2026-10-24 | Send, print, import `.jypaint`, text tool, undo for every edit; renamed to JingyaoPaint |
| 1.3.0 | 2026-10-24 | Shapes with fill, eraser range circle, cute fonts |
| 1.2.0 | 2026-10-24 | Spray, rainbow and stamp brushes, opacity, mirror drawing, paper colors, themes |
| 1.1.0 | 2026-10-24 | New name and icon, gallery, autosave, Chinese and English |
| 1.0.0 | 2026-10-23 | Freehand drawing, undo/redo, colors, save to album |

The full list of what each version added, with the code and tests behind it, is in [docs/appdev/FEATURES.md](docs/appdev/FEATURES.md).

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
| A Mac with the newest Xcode *(optional)* | latest | Running iOS locally. Without one, GitHub Actions builds iOS (see below). |
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
| iPhone and iPad simulators | GitHub Actions (`.github/workflows/ios.yml`) or a Mac | The real iOS build: starts on the newest iPhone and iPad and leaves screenshots |

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

Get the code and open the repository folder itself in VS Code:

```powershell
git clone https://github.com/leonfighter1/JingyaoPaint.git
code JingyaoPaint
```

Press **F5**. `.vscode/launch.json` offers three configurations:

- **JingyaoPaint (debug)**: a running emulator or connected phone.
- **JingyaoPaint (Chrome)**
- **JingyaoPaint (Windows)**

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
- **`test/selection_test.dart`**: turning and resizing strokes (pixels, hits, saving), box selection, and the move tool's knobs, bar and color sheet.
- **`test/music_test.dart`**: the music library, the looping player (on/off, volume, background pause, fallback) and the music settings.
- **`test/print_test.dart`**: the print preview's close buttons, Back, printing and page orientation.
- **`test/ios_test.dart`**: the app running as iOS (scrolling, transitions and text editing differ per platform), Apple's music formats and the iPad share-sheet anchor.
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
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r dist\JingyaoPaint-v2.0.0-x86_64.apk
```

To release a new version:

1. Bump `version:` in `pubspec.yaml` (the build number after `+` too: Android needs it to go up).
2. Bump `appVersion` in `lib/settings_page.dart`.
3. Add a row to the Versions table above and a section to `docs/appdev/FEATURES.md`.

## iOS

iOS builds need macOS and Xcode, so they run on GitHub's Macs (free for this public repository). Every push to `main` (or a manual run under Actions → iOS → Run workflow) does:

1. Analyze and test.
2. Build an unsigned release build for iPhone and iPad with the newest stable Xcode, which targets the newest iOS.
3. Start the app on the newest iPhone and iPad Pro simulators. A crash on launch fails the run.

The screenshots and app logs are under the run's **Artifacts → ios-screenshots**.

The iOS app needs iOS 15 or later. Its bundle ID `com.personal.jingyaopaint` matches the Android package. iOS-specific parts:

- `ios/Runner/Info.plist`: Chinese and English localizations, Photos permission texts and the `.jypaint` document type.
- `ios/Runner/AppDelegate.swift`: "Open in JingyaoPaint" for `.jypaint` files, on the same channel as Android's `MainActivity.kt`.
- Background music uses the "ambient" audio session: the silent switch mutes it, and it plays along with other apps' audio.
- The app icon comes from `tool/make_icons.ps1`.

To install on a real iPhone or iPad, or to share through TestFlight, you need an Apple Developer account and signing set up. The workflow doesn't do that yet. On a Mac, you can run the app directly: `flutter run -d <simulator or device>`.

## Project layout

```
lib/
  main.dart            app shell: tabs or side rail, theme, incoming files
  drawing/             canvas page, strokes, drawing controller, text editor
  gallery/             My Paintings page and storage (file / browser / memory)
  music/               background music: track library, saved uploads, looping player
  share/               send, print preview, import, .jypaint format
  theme/               portable JSON themes, contrast math, fonts (see theme/README.md)
  widgets/             drop-down menu, draggable corner controls
  l10n.dart            all UI text, zh and en
  settings.dart        remembered choices (brush, colors, corners, theme…)
assets/                logo, theme JSON files, fonts and their OFL licenses, built-in music
android/               Android host app (MainActivity handles "open with")
ios/                   iOS host app (AppDelegate handles "Open in", Info.plist)
.github/workflows/     ios.yml: builds and starts the iOS app on GitHub's Macs
tool/                  build_apk.ps1, watch_build.ps1, make_icons.ps1, make_music.dart, ios_sim_smoke.sh
docs/appdev/           FEATURES.md, MISTAKES.md, DEVLOG.md
test/                  see Tests above
```

Read `docs/appdev/MISTAKES.md` before making changes. Its rules come from problems this project has already hit.
