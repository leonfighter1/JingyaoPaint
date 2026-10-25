import 'package:flutter/material.dart';

import 'theme_spec.dart';

/// Theme values Material's [ThemeData] has no slot for: the header gradient,
/// per-tab navigation colors and readable text colors for each of them.
///
/// Read it with `CuteTheme.of(context)`.
class CuteTheme extends ThemeExtension<CuteTheme> {
  const CuteTheme(this.spec);

  final ThemeSpec spec;

  static CuteTheme of(BuildContext context) =>
      Theme.of(context).extension<CuteTheme>()!;

  LinearGradient get headerGradient => LinearGradient(
        colors: spec.header,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  Color get onHeader => spec.onHeader;
  Color get ink => spec.ink;
  List<Color> get nav => spec.nav;
  Color get navBackground => spec.navBackground;
  double get radius => spec.radius;

  /// Readable text or icon color for anything drawn on [color].
  Color onColor(Color color) => spec.onColor(color);

  /// Builds a complete Material 3 theme from [spec], optionally in
  /// [fontFamily] (a family declared in pubspec.yaml). Characters the font
  /// lacks fall back to the system font automatically.
  static ThemeData build(ThemeSpec spec, {String? fontFamily}) {
    final scheme = ColorScheme.fromSeed(seedColor: spec.primary).copyWith(
      primary: spec.primary,
      onPrimary: spec.onPrimary,
      secondary: spec.secondary,
      onSecondary: spec.onSecondary,
      surface: spec.surface,
      onSurface: spec.ink,
    );
    final rounded =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(spec.radius));
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
    );
    return base.copyWith(
      scaffoldBackgroundColor: spec.background,
      extensions: [CuteTheme(spec)],
      textTheme: base.textTheme.apply(
        bodyColor: spec.ink,
        displayColor: spec.ink,
      ),
      appBarTheme: AppBarTheme(
        foregroundColor: spec.onHeader,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: spec.onHeader,
          fontFamily: fontFamily,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: spec.surface,
        clipBehavior: Clip.antiAlias,
        shape: rounded.copyWith(
          side: BorderSide(color: spec.primary.withValues(alpha: 0.12)),
        ),
      ),
      chipTheme: const ChipThemeData(shape: StadiumBorder()),
      dialogTheme: DialogThemeData(shape: rounded),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: spec.secondary,
        foregroundColor: spec.onSecondary,
        shape: const StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: spec.navBackground,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: spec.ink,
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
          ),
        ),
      ),
      // The side rail used on wide screens; same colors as the bottom bar.
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: spec.navBackground,
        selectedLabelTextStyle: TextStyle(
          color: spec.ink,
          fontFamily: fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: spec.ink,
          fontFamily: fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      sliderTheme: const SliderThemeData(trackHeight: 6),
    );
  }

  @override
  CuteTheme copyWith({ThemeSpec? spec}) => CuteTheme(spec ?? this.spec);

  @override
  CuteTheme lerp(CuteTheme? other, double t) =>
      other == null || t < 0.5 ? this : other;
}
