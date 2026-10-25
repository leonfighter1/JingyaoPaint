import 'dart:convert';

import 'package:flutter/services.dart';

import 'contrast.dart';

/// A theme template, loaded from a JSON file such as `assets/themes/sakura.json`.
///
/// A template lists only the base colors. Every text and icon color drawn on
/// top of them is *derived* by [Contrast], so a pale theme automatically gets
/// dark text instead of white. [contrastIssues] reports any pairing that
/// fails WCAG AA, and tests run it on every bundled theme.
class ThemeSpec {
  const ThemeSpec({
    required this.id,
    required this.names,
    required this.emoji,
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.ink,
    required this.header,
    required this.nav,
    required this.navBackground,
    this.radius = 24,
  });

  final String id;

  /// Display name per language code, for example {'zh': '樱花粉', 'en': 'Sakura'}.
  final Map<String, String> names;
  final String emoji;

  /// Buttons, selected states and accent text.
  final Color primary;

  /// Floating action button and soft highlights.
  final Color secondary;

  /// Page background.
  final Color background;

  /// Cards, panels and dialogs.
  final Color surface;

  /// Main text color, used on [background] and [surface].
  final Color ink;

  /// Header gradient stops, top-left to bottom-right.
  final List<Color> header;

  /// One color per bottom navigation tab.
  final List<Color> nav;
  final Color navBackground;

  /// Corner radius for cards and panels. Bigger looks softer and cuter.
  final double radius;

  /// Strength of the tinted pill behind the selected navigation tab.
  static const navIndicatorAlpha = 0.22;

  // Colors derived for readability; never stored in the template.
  Color get onPrimary => Contrast.bestOn(primary, [ink, _white, _black]);
  Color get onSecondary => Contrast.bestOn(secondary, [ink, _white, _black]);
  Color get onHeader => Contrast.bestOnAll(header, [ink, _white, _black]);

  /// Text or icon color for anything drawn on [color] (chips, badges, tiles).
  Color onColor(Color color) => Contrast.bestOn(color, [ink, _white, _black]);

  static const _white = Color(0xFFFFFFFF);
  static const _black = Color(0xFF000000);

  String name(String languageCode) =>
      names[languageCode] ?? names['en'] ?? names.values.first;

  /// Every color pairing this theme draws, and whether each meets WCAG AA.
  /// Empty means the theme is fully readable.
  List<String> contrastIssues() {
    final issues = <String>[];
    void check(String what, Color fg, List<Color> bgs, double min) {
      final r = Contrast.worst(fg, bgs);
      if (r < min) {
        issues.add('$id: $what is ${r.toStringAsFixed(2)}:1, needs $min:1');
      }
    }

    check('ink on background', ink, [background], Contrast.text);
    check('ink on surface', ink, [surface], Contrast.text);
    check('ink on nav bar', ink, [navBackground], Contrast.text);
    check('primary text on surface', primary, [surface], Contrast.text);
    check('primary text on background', primary, [background], Contrast.text);
    check('text on primary buttons', onPrimary, [primary], Contrast.text);
    check('text on secondary', onSecondary, [secondary], Contrast.text);
    check('header text', onHeader, header, Contrast.text);
    for (final (i, c) in nav.indexed) {
      final pill =
          Contrast.over(c.withValues(alpha: navIndicatorAlpha), navBackground);
      check('nav icon $i on bar', c, [navBackground], Contrast.largeTextOrIcon);
      check('nav icon $i on its pill', c, [pill], Contrast.largeTextOrIcon);
      check('text on nav color $i', onColor(c), [c], Contrast.text);
    }
    return issues;
  }

  factory ThemeSpec.fromJson(Map<String, Object?> json) {
    List<Color> colors(String key) =>
        [for (final v in json[key] as List) parseColor(v as String)];
    return ThemeSpec(
      id: json['id'] as String,
      names: (json['name'] as Map).cast<String, String>(),
      emoji: json['emoji'] as String? ?? '',
      primary: parseColor(json['primary'] as String),
      secondary: parseColor(json['secondary'] as String),
      background: parseColor(json['background'] as String),
      surface: parseColor(json['surface'] as String),
      ink: parseColor(json['ink'] as String),
      header: colors('header'),
      nav: colors('nav'),
      navBackground: parseColor(json['navBackground'] as String),
      radius: (json['radius'] as num? ?? 24).toDouble(),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': names,
        'emoji': emoji,
        'primary': formatColor(primary),
        'secondary': formatColor(secondary),
        'background': formatColor(background),
        'surface': formatColor(surface),
        'ink': formatColor(ink),
        'header': [for (final c in header) formatColor(c)],
        'nav': [for (final c in nav) formatColor(c)],
        'navBackground': formatColor(navBackground),
        'radius': radius,
      };

  /// Loads the templates named [ids] from `<folder>/<id>.json`, in order.
  static Future<List<ThemeSpec>> loadAll(
    List<String> ids, {
    AssetBundle? bundle,
    String folder = 'assets/themes',
  }) async {
    final b = bundle ?? rootBundle;
    return [
      for (final id in ids)
        ThemeSpec.fromJson(
            jsonDecode(await b.loadString('$folder/$id.json'))
                as Map<String, Object?>),
    ];
  }

  /// Parses `#RRGGBB` or `#AARRGGBB`.
  static Color parseColor(String hex) {
    final h = hex.replaceFirst('#', '');
    final v = int.parse(h, radix: 16);
    return Color(h.length == 6 ? 0xFF000000 | v : v);
  }

  static String formatColor(Color c) {
    final argb = c.toARGB32();
    final hex = (c.a == 1 ? argb & 0xFFFFFF : argb)
        .toRadixString(16)
        .padLeft(c.a == 1 ? 6 : 8, '0')
        .toUpperCase();
    return '#$hex';
  }
}
