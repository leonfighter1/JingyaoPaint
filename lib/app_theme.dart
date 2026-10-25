import 'package:flutter/material.dart';

import 'drawing/stroke.dart';
import 'theme/cute_font.dart';
import 'theme/cute_theme.dart';

/// The bundled theme templates, in the order shown in Settings.
/// Each id is a file in `assets/themes/`.
const kThemeIds = ['sakura', 'lavender', 'peach', 'mint', 'cloud'];

/// The bundled fonts, in the order shown in Settings. The first is the
/// default: a cute rounded Chinese font.
const kFonts = [
  CuteFont(
    id: 'kuaile',
    family: 'ZCOOLKuaiLe',
    names: {'zh': '快乐体', 'en': 'KuaiLe (happy)'},
    licenseAsset: 'assets/fonts/zcoolkuaile/OFL.txt',
  ),
  CuteFont(
    id: 'huangyou',
    family: 'ZCOOLQingKeHuangYou',
    names: {'zh': '黄油体', 'en': 'HuangYou (chubby)'},
    licenseAsset: 'assets/fonts/zcoolqingkehuangyou/OFL.txt',
  ),
  CuteFont(
    id: 'longcang',
    family: 'LongCang',
    names: {'zh': '手写体', 'en': 'LongCang (handwritten)'},
    licenseAsset: 'assets/fonts/longcang/OFL.txt',
  ),
  CuteFont.system,
];

CuteFont fontById(String id) =>
    kFonts.firstWhere((f) => f.id == id, orElse: () => kFonts.first);

/// App-specific look that isn't part of the portable theme module.
abstract final class AppTheme {
  /// Strength of the tint behind an unselected brush button.
  static const brushTintAlpha = 0.14;

  /// Brush accent colors. Dark enough to read as icons (3:1) on their pale
  /// tile and on every theme's surface; tests check this.
  static Color brushColor(BrushType b) => switch (b) {
        BrushType.pen => const Color(0xFF7B4FD6),
        BrushType.pencil => const Color(0xFFB5521A),
        BrushType.marker => const Color(0xFFC2185B),
        BrushType.highlighter => const Color(0xFF8A6D00),
        BrushType.spray => const Color(0xFF1C7A96),
        BrushType.rainbow => const Color(0xFFA63A9E),
        BrushType.stamp => const Color(0xFFD1376F),
        BrushType.text => const Color(0xFF3B5BDB),
        BrushType.move => const Color(0xFF00796B),
        BrushType.eraser => const Color(0xFF5F6C7B),
      };

  static IconData brushIcon(BrushType b) => switch (b) {
        BrushType.pen => Icons.draw_rounded,
        BrushType.pencil => Icons.edit_rounded,
        BrushType.marker => Icons.brush_rounded,
        BrushType.highlighter => Icons.border_color_rounded,
        BrushType.spray => Icons.blur_on_rounded,
        BrushType.rainbow => Icons.looks_rounded,
        BrushType.stamp => Icons.favorite_rounded,
        BrushType.text => Icons.text_fields_rounded,
        BrushType.move => Icons.open_with_rounded,
        BrushType.eraser => Icons.auto_fix_normal_rounded,
      };

  static IconData shapeIcon(ShapeKind? s) => switch (s) {
        null => Icons.gesture_rounded,
        ShapeKind.line => Icons.horizontal_rule_rounded,
        ShapeKind.arrow => Icons.north_east_rounded,
        ShapeKind.rectangle => Icons.crop_square_rounded,
        ShapeKind.ellipse => Icons.circle_outlined,
        ShapeKind.triangle => Icons.change_history_rounded,
        ShapeKind.star => Icons.star_border_rounded,
        ShapeKind.heart => Icons.favorite_border_rounded,
      };

  static IconData stampIcon(StampShape s) => switch (s) {
        StampShape.heart => Icons.favorite_rounded,
        StampShape.star => Icons.star_rounded,
        StampShape.flower => Icons.local_florist_rounded,
      };

  /// Soft paper colors to draw on.
  static const papers = [
    Color(0xFFFFFFFF),
    Color(0xFFFFF8E7),
    Color(0xFFFFF0F5),
    Color(0xFFEEF6FF),
    Color(0xFFEEFBF4),
    Color(0xFFF5F0FF),
  ];
}

/// An AppBar on the theme's header gradient, with rounded bottom corners.
/// Its text and icons use the theme's contrast-checked header color.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GradientAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  final Widget title;
  final List<Widget>? actions;

  /// Replaces the automatic back button.
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cute = CuteTheme.of(context);
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
    );
    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      shape: shape,
      flexibleSpace: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          gradient: cute.headerGradient,
          shadows: [
            BoxShadow(
              color: cute.spec.primary.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app logo and theme emoji next to the title.
class AppLogoTitle extends StatelessWidget {
  const AppLogoTitle({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final emoji = CuteTheme.of(context).spec.emoji;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset('assets/icon/logo.png',
              width: 32, height: 32, excludeFromSemantics: true),
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        if (emoji.isNotEmpty) ...[
          const SizedBox(width: 6),
          ExcludeSemantics(child: Text(emoji)),
        ],
      ],
    );
  }
}
