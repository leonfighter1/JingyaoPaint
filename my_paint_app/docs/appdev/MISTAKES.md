# Mistakes and lessons: 靖瑶的画板 (my_paint_app)

## Rules (read before every task)
1. Create Flutter projects with every platform you'll debug on: `flutter create --platforms android,web,windows`.
2. Before using a plugin, check its supported platforms on pub.dev. Put Android/desktop-only plugins (like `gal`) behind a conditional import (`if (dart.library.js_interop)`).
3. On a Windows host, plugin builds need **Developer Mode** (for symlinks). Check it before promising a Windows desktop build.
4. Don't run `flutter run` as a background task for the user. It has no keyboard input, so hot reload can't be used. Let the user press F5 in VS Code. Use background runs only to confirm that the app starts.
5. When replacing template code, update `test/widget_test.dart` in the same step.
6. Fix type mismatches at the source. Never silence them with `as dynamic`.
7. Generated IDs must be guaranteed unique (time plus a counter that only goes up). Code that saves user data needs tests that create several items quickly.
8. Use `dart:convert`'s `utf8` for text encoding. Don't hand-roll encoders.
9. Any async save must finish (or be awaited) before a delete of the same item. Otherwise the save can bring the deleted item back.
10. Never hard-code text or icon colors (like `Colors.white`) on themed backgrounds. Derive them with `Contrast.bestOn` / `CuteTheme.onColor`, and keep the accessibility guideline tests passing for every theme.
11. Don't use overshooting curves (`easeOutBack`, `elasticOut`) on `AnimatedContainer`s that animate shadows or other values that must stay non-negative.
12. Any row that holds tappable chips or buttons must be at least 48px tall. `androidTapTargetGuideline` fails otherwise.
13. In widget tests, scroll to items in horizontal lists before tapping them (`ensureVisible`), and use `skipOffstage: false` when only checking that they exist.
14. Items far down a lazy list aren't built at all, so `skipOffstage: false` won't find them. Use `scrollUntilVisible`, and resolve the scrollable to an element first, because a finder relative to an item that scrolls away stops matching.
15. Run `textContrastGuideline` on a screen tall enough that no text is half-cut at a scroll edge. Clipped text gets measured against the background and fails falsely.
16. Tap chips and menu items by their widget (`widgetWithText(ChoiceChip, …)` or the `PopupMenuItem` ancestor), not by their inner text, to avoid "would not hit test" warnings.
17. Put VS Code launch configs in the folder VS Code actually has open (here `C:\AIProjects\.vscode\launch.json`, pointing into `my_paint_app` via `cwd`), not only in the app's subfolder.
18. Use single-code-point emoji in UI text. Variation selectors (U+FE0F, as in ☁️ ❤️ ✏️) have no Noto font, so Flutter web logs "Could not find a set of Noto fonts". `theme_test` checks the theme emoji.
19. Install Android SDK packages with `cmdline-tools\latest\bin\android.exe --sdk=<sdk> sdk install "ndk;28.2.13676358"`, not `sdkmanager.bat`. The .bat splits arguments at `;`, so every package name fails ("Package ndk not found"). Gradle's automatic NDK install goes through the same .bat, so pre-install the NDK version Flutter asks for (`ndkVersion` in `FlutterExtension.kt`).
20. Unzip big archives with `unzip`/`tar`, not PowerShell 5.1 `Expand-Archive`, which failed on the command-line tools zip.
21. Save `.ps1` scripts that contain Chinese (or any non-ASCII) as UTF-8 **with BOM**. Windows PowerShell 5.1 reads BOM-less files as ANSI, and the script fails to parse.
22. In Git Bash, set `MSYS_NO_PATHCONV=1` before `adb push/shell` with device paths. Otherwise `/sdcard/...` is rewritten to `C:/Program Files/Git/sdcard/...` and the command fails.
23. Read a 2D zoom from the matrix's x-axis scale, never `getMaxScaleOnAxis()`.
24. Never change a notifier (ValueNotifier, setState on another widget) inside build or LayoutBuilder; react in a listener or a post-frame callback.
25. When a `Semantics` uses `excludeSemantics: true` around a button, give it the action (`onTap`) too, and test that the semantics node can be tapped.
26. If an emulator draws black, cold-boot it (`-no-snapshot-load`) before suspecting the app; launch from the launcher, not `am start` right after install.
27. In widget tests, leave Settings with `find.byType(BackButton)`, not `pageBack()`, which needs the English tooltip.
28. `num.clamp(lo, hi)` throws when `hi < lo`. When the upper bound is "space minus size", wrap it in `math.max(lo, …)`: on tiny screens with large text, a widget can be bigger than its area.

## Log

### 2026-10-25: Corner control crashed on a small phone with large text
- **Symptom:** `ArgumentError: Invalid argument(s): 0.0` in the 360×640 English, 1.3× text test.
- **Root cause:** `CornerFloat` clamped its position to `area - size`, which was negative because the control was wider than its area.
- **Fix:** the upper bound is `math.max(0, area - size)`.
- **Rule:** 28.

### 2026-10-25: Zoom couldn't go below 100%
- **Symptom:** the zoom test stuck at 1.0 when zooming out; the chip would show 100% at any zoom-out.
- **Root cause:** `Matrix4.getMaxScaleOnAxis()` includes the z axis, which a 2D zoom leaves at 1, so it never reports less than 1.
- **Fix:** `CanvasPageState.zoomLevel` reads the x-axis scale.
- **Rule:** 23.

### 2026-10-25: "setState() called during build" when opening another painting
- **Symptom:** an exception when the session switched paintings.
- **Root cause:** the zoom view was reset inside a LayoutBuilder's build, which notified other widgets mid-build.
- **Fix:** reset the view from a session listener instead.
- **Rule:** 24.

### 2026-10-25: Screen readers couldn't press the tools button
- **Symptom:** on the emulator, uiautomator showed the button as `clickable="false"`. Flutter's tap-target and label guidelines passed anyway, because they only check nodes that already have a tap action.
- **Root cause:** `Semantics(excludeSemantics: true)` also dropped the InkWell's tap action.
- **Fix:** pass `onTap` to that Semantics, and added a test that activates the button through semantics.
- **Rule:** 25.

### 2026-10-25: Emulator showed a black or blank screen
- **Symptom:** the app (and even system Settings) drew black after an emulator restart; once, it drew nothing right after reinstall plus rotation.
- **Root cause:** the emulator's graphics state, not the app (no errors in logcat). A quick-boot snapshot saved after a forced stop restored a broken GPU state.
- **Fix:** `emulator -avd <name> -no-snapshot-load -gpu host`, then launch from the launcher (`adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1`) instead of `am start` straight after install.
- **Rule:** 26.

### 2026-10-25: Test-only snags with the new UI
- `tester.pageBack()` looks for the English "Back" tooltip and fails in the Chinese UI; tap `find.byType(BackButton)` instead.
- Lazy lists (the drawer, and the menu at first) don't build off-screen rows; the menu is now a non-lazy Column, and drawer tests use `scrollUntilVisible`.
- **Rule:** 14 (existing) and 27.

### 2026-10-24: Android SDK packages "not found"; APK build failed on the NDK
- **Symptom:** `sdkmanager "platforms;android-36"` reported "Package platforms not found / Package android-36 not found". The first `flutter build apk` then failed with "sdkmanager did not install NDK 28.2.13676358".
- **Root cause:** the new `sdkmanager.bat` is a cmd wrapper. cmd treats `;` as an argument separator, so `platforms;android-36` arrived as two arguments. Gradle's NDK auto-install calls the same wrapper.
- **Fix:** installed the platform, build-tools and NDK with `android.exe sdk install`, then rebuilt.
- **Rule:** 19 (and 20 for the earlier `Expand-Archive` failure).

### 2026-10-24: Web console warned "Could not find a set of Noto fonts"
- **Symptom:** running in Chrome logged "Could not find a set of Noto fonts to display all missing characters".
- **Root cause:** the 棉花糖 theme emoji ☁️ is U+2601 plus the variation selector U+FE0F, and Flutter web has no Noto font that covers U+FE0F. The settings page is built at startup, inside an IndexedStack, so the warning appeared immediately.
- **Fix:** changed the emoji to 🍭 (a single code point), and added a test that fails on variation selectors in theme emoji.
- **Rule:** 18.

### 2026-10-24: F5 said "cannot find a class with the main method"
- **Symptom:** the user pressed F5 and got a Java error instead of the app starting.
- **Root cause:** the VS Code workspace is `C:\AIProjects`, but `launch.json` was only in `my_paint_app/.vscode/`, so VS Code didn't see it. With no config, F5 picked a debugger from the open file (`GeneratedPluginRegistrant.java`), and the installed Java extension pack tried to run it as a Java program.
- **Fix:** added `C:\AIProjects\.vscode\launch.json` with Dart configs that use `cwd: ${workspaceFolder}/my_paint_app`.
- **Rule:** 17.

### 2026-10-24: Contrast test failed on half-visible "开源许可"
- **Symptom:** 4 of 5 themes failed `textContrastGuideline` with 1.15:1 on the 开源许可 tile.
- **Root cause:** the longer settings page pushed that tile half below the viewport. The guideline sampled the clipped background, not the text. The real colors pass.
- **Fix:** accessibility tests use a 393×1200 screen. Small-screen layout is still covered by the separate 360×640 overflow test.
- **Rule:** 15.

### 2026-10-24: Fill-chip test couldn't find its target
- **Symptom:** `Bad state: No element`, first for the 填充 chip and then for the scroll row itself.
- **Root cause:** the 9th chip is beyond the lazy list's build range, and the row finder was relative to 自由画, which scrolled away during `scrollUntilVisible`.
- **Fix:** resolve the row's element once, then `scrollUntilVisible`.
- **Rule:** 14.

### 2026-10-24: v1.1 header used white text on a pale gradient
- **Symptom:** the user asked for accessible text colors ("如果主题颜色偏淡，那么字体颜色不要为白色"). The v1.1 header had white text on a violet→pink→peach gradient, and on the peach stop that is about 1.9:1, well below WCAG AA's 4.5:1. The pink "new painting" button with white text also failed.
- **Root cause:** foreground colors were picked by eye and never measured.
- **Fix:** themes are now JSON templates. Text colors are derived from contrast math, and tests check WCAG AA plus Flutter's accessibility guidelines on every theme and screen.
- **Rule:** 10.

### 2026-10-24: Brush button crashed with "blur radius should be non-negative"
- **Symptom:** a widget test crashed when switching brushes, followed by a 99,937px overflow.
- **Root cause:** `Curves.easeOutBack` overshoots past 1.0. While the selected tile's shadow faded out, the overshoot made its blur radius negative.
- **Fix:** switched to `Curves.easeOut`.
- **Rule:** 11.

### 2026-10-24: Year filter chips were too small to tap
- **Symptom:** `androidTapTargetGuideline` failed with chips 40px tall.
- **Root cause:** the chip row was 56px high with 8px padding, which squeezed the chips' 48px tap area.
- **Fix:** made the row 60px tall with 6px padding.
- **Rule:** 12.

### 2026-10-24: Tests couldn't find off-screen list items
- **Symptom:** finders for the 8th brush and the 4th theme card found nothing.
- **Root cause:** sideways-scrolling lists only count visible items as "onstage".
- **Fix:** `skipOffstage: false` for existence checks, and `ensureVisible` before tapping.
- **Rule:** 13.

### 2026-10-24: Deleting during an autosave could bring the painting back
- **Symptom:** found in review. Deleting the open painting while its autosave was rendering the thumbnail let the save finish after the delete, re-adding the painting to the gallery.
- **Root cause:** `delete()` didn't wait for the save already in progress.
- **Fix:** the session keeps the latest save's future, and `delete()` awaits it before deleting. Covered by the test "deleting while an autosave is running does not bring it back".
- **Rule:** 9.

### 2026-10-24: Painting IDs collided, so a new painting could overwrite the old one
- **Symptom:** two model tests failed, because "new painting" got the same ID as the previous painting.
- **Root cause:** IDs were `DateTime.now().microsecondsSinceEpoch`. On Windows the clock can return the same value twice in quick succession.
- **Fix:** `_newId()` now takes `max(now, last + 1)`.
- **Rule:** 7.

### 2026-10-24: Hand-rolled UTF-8 encoding didn't compile
- **Symptom:** analyzer error "Utf8Codec isn't a class" in `store_backend_io.dart`.
- **Root cause:** overcomplicated code that guessed at the system encoding.
- **Fix:** `utf8.encode(value)`.
- **Rule:** 8.

### 2026-10-23: Save in Chrome threw MissingPluginException
- **Symptom:** the user saw `MissingPluginException` when pressing Save in the Chrome debug session.
- **Root cause:** `gal` has no web implementation, but was called on every platform.
- **Fix:** `lib/image_saver.dart` picks `image_saver_io.dart` (gallery) or `image_saver_web.dart` (browser download) through a conditional export.
- **Rule:** 2.

### 2026-10-23: Windows debug build failed ("requires symlink support")
- **Symptom:** `flutter build windows` stopped with "Building with plugins requires symlink support".
- **Root cause:** Windows Developer Mode is off.
- **Fix:** used Chrome as the debug target. The user can turn on Developer Mode (`start ms-settings:developers`) to use Windows.
- **Rule:** 3.

### 2026-10-23: Project only had the Android platform
- **Symptom:** there was no way to debug before the Android SDK was installed.
- **Root cause:** created with `--platforms android`.
- **Fix:** `flutter create --platforms windows,web .`
- **Rule:** 1.

### 2026-10-23: Background `flutter run` couldn't hot reload
- **Symptom:** the Chrome session started by Claude couldn't take `r`/`R` keys.
- **Root cause:** background tasks have no keyboard input.
- **Fix:** added `.vscode/launch.json` so the user can run with F5, with hot reload on save.
- **Rule:** 4.

### 2026-10-23: Default widget test referenced the removed `MyApp`
- **Symptom:** analyzer error after `main.dart` was rewritten.
- **Fix:** rewrote `test/widget_test.dart` for the new app.
- **Rule:** 5.

### 2026-10-23: Used `as dynamic` to get past a type mismatch
- **Symptom:** `exportPng` returned `List<int>` but `Gal.putImageBytes` needs `Uint8List`.
- **Fix:** made `exportPng` return `Uint8List`.
- **Rule:** 6.
