# Portable cute theme module

This folder doesn't depend on anything else in the app, so you can copy it
into any Flutter project.

| File | Purpose |
|---|---|
| `contrast.dart` | WCAG 2.1 contrast math: `Contrast.ratio`, `bestOn`, `bestOnAll` |
| `theme_spec.dart` | `ThemeSpec`, a theme template read from JSON, with `contrastIssues()` |
| `cute_theme.dart` | `CuteTheme.build(spec, fontFamily: ...)` → `ThemeData`, plus the `CuteTheme` extension (header gradient, tab colors) |
| `cute_font.dart` | `CuteFont`, a selectable font (pubspec family, names, license asset) |

### Fonts

Fonts are chosen separately from color themes, so any theme works with any
font. To bring the cute fonts along, also copy `assets/fonts/` and the
`fonts:` and OFL `assets:` entries from this app's `pubspec.yaml`, then pass
`fontFamily: font.family` to `CuteTheme.build`. The fonts use the SIL Open
Font License: keep each `OFL.txt` and register it with `LicenseRegistry`
(see `_registerFontLicenses` in `lib/main.dart`).

## Using it in another app

1. Copy `lib/theme/` and `assets/themes/` into the new project.
2. In `pubspec.yaml`, add:
   ```yaml
   flutter:
     assets:
       - assets/themes/
   ```
3. Load the themes and apply one:
   ```dart
   final themes = await ThemeSpec.loadAll(['sakura', 'lavender', 'peach', 'mint', 'cloud']);
   MaterialApp(theme: CuteTheme.build(themes.first), ...);
   ```
4. In widgets, use `CuteTheme.of(context).headerGradient`, `.onHeader`,
   `.nav` and `.onColor(c)` to get text that stays readable on any color.

## Making a new theme

Copy any JSON file in `assets/themes/`, change `id`, `name` and the colors,
and add the id to the list you pass to `loadAll`. You only choose base colors.
Text colors on top of them (header text, button text, chip text) are picked
automatically for contrast, so a pale header gets dark text instead of white.

The tests in `test/theme_test.dart` run `contrastIssues()` on every theme. A
theme with unreadable text fails the build until its colors are fixed.

| Key | Used for | Contrast checked |
|---|---|---|
| `primary` | buttons, selected items, accent text | ≥ 4.5:1 on `surface` and `background` |
| `secondary` | floating button, soft highlights | its text ≥ 4.5:1 |
| `background` / `surface` | page / cards and panels | `ink` ≥ 4.5:1 on both |
| `ink` | main text | see above |
| `header` | header gradient stops | header text ≥ 4.5:1 on every stop |
| `nav` | one color per bottom tab | icons ≥ 3:1 on the bar and on the selected pill |
| `navBackground` | bottom bar | `ink` labels ≥ 4.5:1 |
| `radius` | card and panel corners | not checked |
