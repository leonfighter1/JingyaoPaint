import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/app_theme.dart';
import 'package:jingyao_paint/drawing/stroke.dart';
import 'package:jingyao_paint/theme/contrast.dart';
import 'package:jingyao_paint/theme/cute_theme.dart';
import 'package:jingyao_paint/theme/theme_spec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Contrast', () {
    test('matches the WCAG reference values', () {
      expect(Contrast.ratio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(Contrast.ratio(Colors.white, Colors.white), closeTo(1, 0.01));
      // #767676 is the classic "just passes 4.5:1 on white" grey.
      expect(Contrast.ratio(const Color(0xFF767676), Colors.white),
          closeTo(4.54, 0.01));
    });

    test('picks dark text on a pale color and white on a dark one', () {
      const candidates = [Colors.white, Colors.black];
      expect(Contrast.bestOn(const Color(0xFFFFD6E5), candidates),
          Colors.black);
      expect(Contrast.bestOn(const Color(0xFF4A2338), candidates),
          Colors.white);
    });
  });

  group('Bundled themes', () {
    late List<ThemeSpec> themes;

    setUpAll(() async {
      themes = await ThemeSpec.loadAll(kThemeIds);
    });

    test('there are 5 themes with unique ids and names in both languages',
        () {
      expect(themes, hasLength(5));
      expect(themes.map((t) => t.id).toSet(), hasLength(5));
      for (final t in themes) {
        expect(t.name('zh'), isNotEmpty);
        expect(t.name('en'), isNotEmpty);
        expect(t.header, hasLength(greaterThanOrEqualTo(2)));
        expect(t.nav, hasLength(3), reason: 'one color per bottom tab');
      }
    });

    test('theme emoji have no variation selectors', () {
      // U+FE0E/U+FE0F (as in "☁️") have no Noto font, so Flutter web logs
      // "Could not find a set of Noto fonts to display all missing
      // characters". Use emoji that are a single code point.
      for (final t in themes) {
        final selectors =
            t.emoji.runes.where((r) => r == 0xFE0E || r == 0xFE0F);
        expect(selectors, isEmpty, reason: '${t.id}: ${t.emoji}');
      }
    });

    test('every theme meets WCAG AA contrast', () {
      final issues = [for (final t in themes) ...t.contrastIssues()];
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    test('pale headers get dark text, never white', () {
      for (final t in themes) {
        final paleHeader =
            t.header.every((c) => Contrast.luminance(c) > 0.5);
        if (paleHeader) {
          expect(t.onHeader, isNot(Colors.white), reason: t.id);
        }
      }
    });

    test('brush colors are readable icons on every theme', () {
      for (final t in themes) {
        for (final b in BrushType.values) {
          final accent = AppTheme.brushColor(b);
          final tint = Contrast.over(
              accent.withValues(alpha: AppTheme.brushTintAlpha), t.surface);
          expect(Contrast.ratio(accent, tint),
              greaterThanOrEqualTo(Contrast.largeTextOrIcon),
              reason: '${t.id}: ${b.name} icon on its tile');
          expect(Contrast.ratio(t.onColor(accent), accent),
              greaterThanOrEqualTo(Contrast.largeTextOrIcon),
              reason: '${t.id}: ${b.name} selected icon');
        }
      }
    });

    test('a theme survives a JSON round trip', () {
      for (final t in themes) {
        final copy = ThemeSpec.fromJson(t.toJson());
        expect(copy.toJson(), t.toJson());
      }
    });

    test('builds a Material theme that carries the template', () {
      final data = CuteTheme.build(themes.first);
      expect(data.extension<CuteTheme>()!.spec.id, themes.first.id);
      expect(data.colorScheme.primary, themes.first.primary);
      expect(data.colorScheme.onSurface, themes.first.ink);
    });
  });
}
