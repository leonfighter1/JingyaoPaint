# Dev log: JingyaoPaint (靖瑶的画板)

## 2026-10-25: Web version on GitHub Pages
- Why: without a paid Apple account, an iOS build only installs for 7 days at a time; the web version added to the home screen has no signing or expiry. The user chose GitHub's free address over a custom domain or another host for now.
- Done: IndexedDB storage (with persistence request and localStorage migration), music that waits for the first touch in browsers, home-screen meta and opaque apple-touch icon, no portrait lock, loading screen, `.github/workflows/web.yml` (browser storage tests in Chrome, build with self-hosted CanvasKit, deploy to Pages), README web section. `--base-href /JingyaoPaint/` build checked locally.
- Mistakes: none reached the user. The new music test caught retries slipping past the "wait for a touch" state; fixed. Chrome and Edge can't start headless from this PC's tool shell, so the browser test runs in CI only.
- Harness: PASS (analyze 0 issues, 192 tests; web release build ok).
- The user enabled Pages. First deploy (run 40235752058): green, including the IndexedDB tests in Chrome; site returns 200 with base href /JingyaoPaint/, app code, CanvasKit, icon, manifest and music; a headless Chrome screenshot at 1180×820 shows the canvas page drawn in the cute font. Moved upload-pages-artifact and deploy-pages to v5 (Node 24).
- Not tested: Safari on a real iPhone/iPad (home-screen launch, Pencil, storage persistence), whether github.io and the fallback fonts load well where the family is.

## 2026-10-25: iOS version (same repo, built on GitHub Actions)
- Decision (with the user): keep iOS in this repo, since Flutter shares all of `lib/`; build on GitHub-hosted Macs, which are free for this public repo. Signing and TestFlight wait for an Apple Developer account.
- Done: `flutter create --platforms ios` (Flutter 3.47.8 template: SceneDelegate, implicit engine, Swift Package Manager); bundle ID set to match Android; Info.plist (name, zh-Hans/en, Photos texts, `.jypaint` document and exported type, no in-place opening, no-encryption flag); `OpenFilePlugin` in AppDelegate.swift written against the engine headers at revision 737ba8f885 (scene lifecycle delegate; Flutter replays launch options to it); single 1024px opaque icon from `make_icons.ps1`; ambient audio session on iOS; Apple-only music formats; iPad share anchor; `.github/workflows/ios.yml` and `tool/ios_sim_smoke.sh`; README iOS section.
- Mistakes: plist CRLF made regex edits miss (rule 34). Rule 35 added for native code that can't be compiled here.
- Harness: PASS (analyze 0 issues, 191 tests, build web ok). Android/web icons unchanged after regenerating.
- **Not verified:** nothing iOS has been compiled or run. The Swift code, Info.plist and the workflow get their first real check when this is pushed and the iOS workflow runs. Also untested: a real device, Apple Pencil pressure, AirPrint on iPad, "Open in" from Files/AirDrop.
- First workflow run (40227038101, commit 662a376): all steps green in 12 minutes (analyze, 191 tests, release build, simulator build, app running on the iPhone and iPad simulators). Fixed its only warning: actions/checkout and upload-artifact moved from v4 (Node 20, deprecated) to v5. Screenshots are in the run's artifacts; downloading needs a GitHub login, so they haven't been looked at here.
- Next: look at the screenshots; for hands-on testing from Windows, a simulator build zip could go to a browser simulator (Appetize); signing and TestFlight once there's an Apple Developer account.

## 2026-10-25: v2.0.0 (box selection, copy/resize/turn, recolor/fade, background music, print preview)
- Done: the move tool selects several strokes with a box; the selection can be copied, resized (corner knob or buttons), turned (top knob or buttons), recolored, faded and deleted, each as one undo step, with a bar that follows the selection. Strokes gained a saved `StrokeTransform`. Looping background music with two synthesized built-in tracks, uploads of common formats, volume, track choice, a ⋮ quick switch and pause in the background (`audioplayers`). Printing now goes through an in-app preview with a big close button. README gained a Versions table.
- Clarified by the user: "颜色和透明度" means the selected elements, not the whole board. A started paper color/transparency change was dropped.
- Emulator (2560×1600 tablet, x86_64 release APK 2.0.0, installed over 1.6.0 with the user's paintings kept): box select (2 of 3 strokes), quarter turn by the knob, 1.5× resize by the knob, copy, recolor to purple and fade to 40%, one undo restoring the opacity, print preview → system print screen → Back → preview → 关闭; music on (active 16 kHz track at −8 dB in the mixer), paused on HOME and resumed on return, looping every 17 s; a WAV added through the system picker played and was deleted again. Test painting, test song and Download file removed afterwards; music left off.
- Mistakes: sparse-point hit test, bar over the turn knob, English large-text overflow, two scripting slips (MISTAKES rules 29–33). The print bug is logged as a user report.
- Harness: PASS (analyze 0 issues, 186 tests, build web ok). Release APKs: arm64 28.2 MB / armv7 25.9 MB / x86_64 29.6 MB.
- Not tested: a real phone (fingers on the knobs, real speakers, MP3/M4A files from a real music library, a real printer); actual sound quality of the built-in tracks (the emulator gives no audio to listen to).

## 2026-10-25: v1.6.0 (corner controls, move tool, round eraser)
- Done: undo/redo default to the top right. The undo bar and tools launcher can be dragged, snapping only to the paper's four corners and never overlapping (positions are remembered). The drawer slides in from the launcher's side. New 选择移动 tool auto-selects the last stroke and drags any stroke, with one-step undo. The eraser has no colors or shapes.
- Emulator (2560×1600 tablet, portrait, x86_64 release APK 1.6.0) checks: undo bar at top right; launcher dragged to bottom left; drawer opens from the left; eraser panel shows only the round-tip hint and sliders; move tool selects the last stroke and drags it; one undo restores it; undo bar dropped on the launcher's corner snaps to bottom right.
- Mistakes: clamp with a negative upper bound (rule 28). Avoided setState in initState by splitting the selection sync.
- Harness: PASS (analyze 0 issues, 151 tests). Release APKs: arm64 26.5 MB / armv7 24.2 MB / x86_64 27.9 MB.
- Not tested yet: a real phone (dragging with a real finger, stylus).

## 2026-10-25: v1.5.0 (tablets, pinch zoom, tools drawer, new layout, small APKs)
- Done: tablet/landscape support (side rail, paper scales to fit and never crops, centered settings); pinch zoom and pan with a fit chip, wheel zoom and menu zoom; tools moved into a sliding drawer opened by a "画笔 · 颜色" button; save and clear top right; delete, settings, zoom, mirror, paper, share and print in an unfolding grouped ⋮ menu; undo/redo at top left; settings removed from the bottom bar; split-per-ABI obfuscated APKs (arm64 26.4 MB).
- Emulator (2560×1600 tablet, Android 15), on the final build: install, landscape canvas, drawer open/close/select, drawing with the backdrop closing the drawer, menu zoom to 156% and drawing while zoomed, fit animation, settings from ⋮ and back, portrait rotation without cropping, delete with confirmation, and the new ⋮ dropdown.
- Found and fixed through testing: zoom stuck at 100% (z-axis scale), a notifier changed during build, the tools button not activatable by screen readers (found on the emulator, now covered by a test).
- Unexplained, once: after Back closed the drawer in a freshly rotated session, one tap on delete opened the send sheet. It didn't reproduce in 3 retries (2 scripted, 1 manual) and delete has since moved into the menu. Watch for it on real devices.
- Harness: PASS (analyze 0 issues, 138 tests). Release APKs built: arm64 / armv7 / x86_64.
- Not tested yet: a real phone (pinch with real fingers, stylus, WeChat file sharing, real printer).

## 2026-10-24: APK tested on an emulator (Android 16, 1080×2400)
- Setup: the user enabled Windows Hypervisor Platform (WHPX usable). Installed the emulator and a system image, created AVD `medium_phone` with `android.exe emulator create medium_phone`, and started it with `android.exe emulator start medium_phone`.
- PASS: APK installs; app launches with no errors in logcat; 快乐体 font and 樱花粉 theme render; freehand drawing; color change; autosave (the drawing appeared in the gallery after an import replaced it on the canvas).
- PASS: "open with" for `.jypaint`, both while the app is running (`onNewIntent`) and from a fully stopped app (cold start, `takeInitialFile`). The imported painting (bold centered bubble text, filled heart, marker line, pink paper) matched the file exactly, got a new id, and kept its 2025 creation date in the year filter.
- PASS: send → JPG opened the system chooser; print opened the Android print UI with a correct A4 preview (it loads after a few seconds).
- Known limit: with a generic type (`application/octet-stream`), Android only offers JingyaoPaint when the link contains the `.jypaint` name. File-manager style links do; bare MediaStore ids (`content://media/external/file/16`) don't. The in-app 导入画作文件 button covers that case.
- Not tested: real WeChat/QQ (not on the emulator), stylus pressure, a real printer.

## 2026-10-24: Android SDK installed, renamed, first APK
- Done: installed the Android SDK (cmdline-tools 16111833, platform 36, build-tools 36.0.0, NDK 28.2; Gradle also pulled platforms 34 and 35); renamed to JingyaoPaint (`com.personal.jingyaopaint`); built `dist\JingyaoPaint-v1.4.0.apk` (64.7 MB); added build and watch scripts.
- Licenses: the Android SDK licenses were accepted on the user's behalf, because they asked for the SDK to be installed.
- Mistakes: sdkmanager.bat semicolon splitting, Expand-Archive failure, a BOM-less Chinese .ps1 (MISTAKES rules 19–21).
- Harness: PASS (analyze 0 issues, 112 tests); `flutter build apk --release` OK, so `MainActivity.kt` now compiles.
- Not verified yet: running on a real phone ("open with" from chat apps, sharing, printing, stylus). The emulator needs Windows Hypervisor Platform (admin + reboot).
- Next: install on a phone and go through the test checklist. Consider `--split-per-abi` (an arm64-only APK is much smaller) and a private release keystore before sharing the APK widely.

## 2026-10-24: v1.4.0 (send, print, import, text tool)
- Done: send as PNG/JPG/PDF/.jypaint via the share sheet; print via the system dialog; import from a file picker and (Android) "open with"; a text tool with full formatting; snapshot-based undo that covers every edit.
- Also fixed: ☁️ emoji warning on web (MISTAKES rule 18); F5 launching the Java debugger (rule 17).
- Mistakes: none reached the user. A generic brush test needed to skip the text tool, and a Kotlin nullable smart-cast error was caught by reading the code, since it can't be compiled here.
- Harness: PASS (analyze 0 issues, 112 tests, build web ok).
- **Not verified:** `MainActivity.kt` and the intent filters have never been compiled or run (no Android SDK). Sharing and printing on a real phone, and how chat apps (WeChat, QQ) label `.jypaint` files, are also untested. These are the first things to check once the APK builds.
- Next: install the Android SDK (Android Studio setup wizard), run `check.ps1 -Build apk`, and test "open with" from a chat app.

## 2026-10-24: v1.3.0 (shapes, eraser range circle, cute fonts)
- Done: 7 shapes with fill that work with every brush, color and opacity; an eraser range circle on long press or hover; 3 OFL cute Chinese fonts plus system (default 快乐体), font picker, licenses page.
- Mistakes: half-clipped text failing the contrast check, a lazy-list finder in tests (see MISTAKES.md). No app bugs reached the user; the harness caught both before reporting.
- Harness: PASS (analyze 0 issues, 84 tests, build web ok, fonts present in the web bundle).
- Not verified yet: how the fonts actually look (widget tests use a box test font), glyph coverage of rare characters (they fall back to the system font), and APK size with fonts (about +15 MB).
- Next: install the Android SDK and build the APK. Consider dropping 黄油体 if the APK size matters.

## 2026-10-24: v1.2.0 (more brushes, cute themes, accessibility)
- Done: spray, rainbow and stamp (heart/star/flower) brushes; a per-brush opacity slider; mirror drawing; paper colors; a collapsible tool panel; cute rounded style; a portable theme module (`lib/theme/`) with 5 JSON themes; WCAG-derived text colors.
- Added harness checks: theme contrast tests, plus Flutter accessibility guidelines (text contrast, 48px tap targets, labels) on 3 screens × 5 themes, plus a 360×640 phone at 1.3× text size in zh and en.
- Mistakes: white text on a pale header, easeOutBack crash, small chip tap targets, off-screen test finders (see MISTAKES.md).
- Harness: PASS (analyze 0 issues, 67 tests, build web ok).
- Not verified yet: APK and real-phone feel (the Android SDK still isn't installed). Widget tests render Chinese and emoji in a box test font, so the visual look still needs checking in Chrome.
- Next: install the Android SDK and build the APK. Possible next features: fill bucket, layers, and an eyedropper color picker.

## 2026-10-24: v1.1.0 (UI refresh, gallery, autosave, languages)
- Done: new header "靖瑶的画板", app icon (`tool/make_icons.ps1`), gradient app bar, colorful bottom navigation, large brush buttons (5 brushes), autosave with reopen-on-launch, My Paintings gallery with dates, year filter and delete, remembered brush/color/size/custom colors, zh (default) and en.
- Code split out of the single `main.dart` into `drawing/`, `gallery/`, `painting_session.dart`, `settings.dart`, `l10n.dart` and `app_theme.dart`.
- Mistakes: ID collision, UTF-8 encoder, delete during autosave (see MISTAKES.md).
- Harness: PASS (analyze 0 issues, 27 tests, build web ok).
- Not verified yet: APK build and on-device behaviour (the Android SDK setup wizard hasn't been run), stylus pressure, and Windows (needs Developer Mode).
- Next: install the Android SDK and build the APK. Consider caching finished strokes as a picture if drawing slows down with hundreds of strokes.

## 2026-10-23: v1.0.0 (first working app)
- Done: set up the toolchain (Flutter 3.47.8 in `C:\dev\flutter`, Android Studio, VS Code Flutter extensions), freehand canvas, colors, size, eraser, undo/redo, save PNG, Chrome debug target.
- Mistakes: Android-only project, gal on web, Windows symlinks, background run without hot reload.
- Harness: analyze clean, 1 test passing, web build ok.
