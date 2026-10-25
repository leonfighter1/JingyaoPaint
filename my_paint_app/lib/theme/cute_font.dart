/// A selectable app font. [family] must match a `fonts:` entry in
/// pubspec.yaml; null means the platform's default font.
class CuteFont {
  const CuteFont({
    required this.id,
    required this.family,
    required this.names,
    this.licenseAsset,
  });

  final String id;
  final String? family;

  /// Display name per language code.
  final Map<String, String> names;

  /// The font's license text (for example its OFL.txt), shown on the
  /// licenses page.
  final String? licenseAsset;

  static const system = CuteFont(
    id: 'system',
    family: null,
    names: {'zh': '系统默认', 'en': 'System'},
  );

  String name(String languageCode) =>
      names[languageCode] ?? names['en'] ?? names.values.first;
}
