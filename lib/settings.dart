import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'drawing/stroke.dart';
import 'widgets/corner_float.dart';

/// User choices that survive app restarts: language, theme, brush, colors,
/// sizes, opacity, stamp shape, mirror mode and paper.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs)
      : locale = ValueNotifier(Locale(_prefs.getString(_kLanguage) ?? 'zh')),
        themeId = ValueNotifier(_prefs.getString(_kTheme) ?? defaultThemeId),
        fontId = ValueNotifier(_prefs.getString(_kFont) ?? defaultFontId),
        _shape = ShapeKind.fromName(_prefs.getString(_kShape)),
        _undoCorner = Corner.fromName(
            _prefs.getString(_kUndoCorner), Corner.topRight),
        _toolsCorner = Corner.fromName(
            _prefs.getString(_kToolsCorner), Corner.bottomRight),
        _fill = _prefs.getBool(_kFill) ?? false,
        _brush = BrushType.fromName(_prefs.getString(_kBrush)),
        _color = Color(_prefs.getInt(_kColor) ?? Colors.black.toARGB32()),
        _stamp = StampShape.fromName(_prefs.getString(_kStamp)),
        _mirror = _prefs.getBool(_kMirror) ?? false,
        _paper = Color(_prefs.getInt(_kPaper) ?? 0xFFFFFFFF),
        _customColors = [
          for (final v in _prefs.getStringList(_kCustomColors) ?? const [])
            if (int.tryParse(v) case final int argb) Color(argb),
        ];

  static Future<AppSettings> load() async =>
      AppSettings(await SharedPreferences.getInstance());

  static const supportedLanguages = ['zh', 'en'];
  static const defaultThemeId = 'sakura';
  static const defaultFontId = 'kuaile';
  static const maxCustomColors = 8;
  static const minOpacity = 0.05;

  static const _kLanguage = 'language';
  static const _kTheme = 'theme';
  static const _kFont = 'font';
  static const _kShape = 'shape';
  static const _kFill = 'fill';
  static const _kTextStyle = 'textStyle';
  static const _kUndoCorner = 'undoCorner';
  static const _kToolsCorner = 'toolsCorner';
  static const _kBrush = 'brush';
  static const _kColor = 'color';
  static const _kStamp = 'stamp';
  static const _kMirror = 'mirror';
  static const _kPaper = 'paper';
  static const _kCustomColors = 'customColors';
  static const _kLastPainting = 'lastPaintingId';
  static String _kSize(BrushType b) => 'size.${b.name}';
  static String _kOpacity(BrushType b) => 'opacity.${b.name}';

  final SharedPreferences _prefs;

  /// Kept separate from the other settings so changing a brush doesn't
  /// rebuild the whole MaterialApp.
  final ValueNotifier<Locale> locale;
  final ValueNotifier<String> themeId;
  final ValueNotifier<String> fontId;

  ShapeKind? _shape;
  bool _fill;
  Corner _undoCorner;
  Corner _toolsCorner;

  /// Where the floating undo/redo buttons sit (default: top right, for the
  /// right thumb).
  Corner get undoCorner => _undoCorner;

  /// Where the "画笔 · 颜色" button sits; the drawer opens from that side.
  Corner get toolsCorner => _toolsCorner;

  set undoCorner(Corner value) {
    _undoCorner = value;
    _prefs.setString(_kUndoCorner, value.name);
    notifyListeners();
  }

  set toolsCorner(Corner value) {
    _toolsCorner = value;
    _prefs.setString(_kToolsCorner, value.name);
    notifyListeners();
  }
  BrushType _brush;
  Color _color;
  StampShape _stamp;
  bool _mirror;
  Color _paper;
  final List<Color> _customColors;

  /// The shape tool, or null for freehand drawing.
  ShapeKind? get shape => _shape;

  /// Whether closed shapes are drawn filled.
  bool get fill => _fill;
  BrushType get brush => _brush;
  Color get color => _color;
  StampShape get stamp => _stamp;
  bool get mirror => _mirror;

  /// Paper color for new paintings: the last one picked.
  Color get paper => _paper;
  List<Color> get customColors => List.unmodifiable(_customColors);

  /// Each brush remembers its own size and opacity.
  double get size => sizeFor(_brush);
  double sizeFor(BrushType b) =>
      _prefs.getDouble(_kSize(b)) ??
      switch (b) { BrushType.pencil => 6, BrushType.text => 16, _ => 10 };
  double get opacity => opacityFor(_brush);
  double opacityFor(BrushType b) => _prefs.getDouble(_kOpacity(b)) ?? 1;

  String? get lastPaintingId => _prefs.getString(_kLastPainting);

  set language(String code) {
    if (!supportedLanguages.contains(code)) return;
    _prefs.setString(_kLanguage, code);
    locale.value = Locale(code);
  }

  set theme(String id) {
    _prefs.setString(_kTheme, id);
    themeId.value = id;
  }

  /// The formatting used for the last text added (its words are not kept),
  /// or null before any text was added.
  TextContent? get textStyle {
    final raw = _prefs.getString(_kTextStyle);
    if (raw == null) return null;
    try {
      return TextContent.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  set textStyle(TextContent value) => _prefs.setString(
      _kTextStyle, jsonEncode(value.copyWith(text: '').toJson()));

  set font(String id) {
    _prefs.setString(_kFont, id);
    fontId.value = id;
  }

  set shape(ShapeKind? value) {
    _shape = value;
    if (value == null) {
      _prefs.remove(_kShape);
    } else {
      _prefs.setString(_kShape, value.name);
    }
    notifyListeners();
  }

  set fill(bool value) {
    _fill = value;
    _prefs.setBool(_kFill, value);
    notifyListeners();
  }

  set brush(BrushType value) {
    _brush = value;
    _prefs.setString(_kBrush, value.name);
    notifyListeners();
  }

  set color(Color value) {
    _color = value;
    _prefs.setInt(_kColor, value.toARGB32());
    // Picking a color means the user wants to paint with it.
    if (!_brush.usesColor) brush = BrushType.pen;
    notifyListeners();
  }

  set size(double value) {
    _prefs.setDouble(_kSize(_brush), value);
    notifyListeners();
  }

  set opacity(double value) {
    _prefs.setDouble(_kOpacity(_brush), value.clamp(minOpacity, 1));
    notifyListeners();
  }

  set stamp(StampShape value) {
    _stamp = value;
    _prefs.setString(_kStamp, value.name);
    notifyListeners();
  }

  set mirror(bool value) {
    _mirror = value;
    _prefs.setBool(_kMirror, value);
    notifyListeners();
  }

  set paper(Color value) {
    _paper = value;
    _prefs.setInt(_kPaper, value.toARGB32());
    notifyListeners();
  }

  set lastPaintingId(String? id) {
    if (id == null) {
      _prefs.remove(_kLastPainting);
    } else {
      _prefs.setString(_kLastPainting, id);
    }
  }

  /// Remembers a color picked from the full picker, newest first.
  void addCustomColor(Color value) {
    _customColors
      ..removeWhere((c) => c.toARGB32() == value.toARGB32())
      ..insert(0, value);
    if (_customColors.length > maxCustomColors) _customColors.removeLast();
    _prefs.setStringList(_kCustomColors,
        [for (final c in _customColors) c.toARGB32().toString()]);
    notifyListeners();
  }

  @override
  void dispose() {
    locale.dispose();
    themeId.dispose();
    fontId.dispose();
    super.dispose();
  }
}
