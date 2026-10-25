import 'dart:math' as math;
import 'dart:ui';

/// WCAG 2.1 color-contrast helpers.
///
/// Thresholds: normal text needs 4.5:1, large text (18pt, or 14pt bold) and
/// icons need 3:1. https://www.w3.org/TR/WCAG21/#contrast-minimum
abstract final class Contrast {
  static const text = 4.5;
  static const largeTextOrIcon = 3.0;

  /// Relative luminance, from 0 (black) to 1 (white).
  static double luminance(Color c) {
    double channel(double v) => v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  /// Contrast ratio between two opaque colors, from 1 to 21.
  static double ratio(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// [fg] drawn with its alpha over [bg], as the eye sees it.
  static Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

  /// Whichever of [candidates] reads best on [background].
  static Color bestOn(Color background, List<Color> candidates) =>
      bestOnAll([background], candidates);

  /// Whichever of [candidates] has the highest *worst-case* contrast against
  /// every color in [backgrounds], such as all stops of a gradient.
  static Color bestOnAll(List<Color> backgrounds, List<Color> candidates) {
    Color best = candidates.first;
    var bestScore = -1.0;
    for (final c in candidates) {
      final score = backgrounds.map((b) => ratio(c, b)).reduce(math.min);
      if (score > bestScore) {
        best = c;
        bestScore = score;
      }
    }
    return best;
  }

  /// Lowest contrast of [fg] against any of [backgrounds].
  static double worst(Color fg, List<Color> backgrounds) =>
      backgrounds.map((b) => ratio(fg, b)).reduce(math.min);
}
