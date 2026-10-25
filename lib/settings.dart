import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'drawing/stroke.dart';
import 'widgets/corner_float.dart';

/// One child using the app. Each kid has their own paintings.
@immutable
class Kid {
  const Kid(this.id, this.name);

  final String id;
  final String name;

  /// The first kid keeps the storage paintings had before kids existed.
  static const firstId = 'main';

  /// Put before each of this kid's stored item names (see
  /// `PrefixedStoreBackend`).
  String get storePrefix => id == firstId ? '' : 'kid-$id-';

  Kid withName(String name) => Kid(id, name);

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  static Kid? fromJson(Object? json) => switch (json) {
        {'id': final String id, 'name': final String name} => Kid(id, name),
        _ => null,
      };
}

/// How background music moves on when a track ends.
enum MusicMode {
  /// The same track again and again.
  repeatOne,

  /// Every track in list order, then from the top.
  sequence,

  /// A random other track each time.
  shuffle;

  static MusicMode fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => repeatOne);
}

/// User choices that survive app restarts: language, theme, brush, colors,
/// sizes, opacity, stamp shape, mirror mode, paper, music and the kids.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs)
      : locale = ValueNotifier(
            Locale(_prefs.getString(_kLanguage) ?? _defaultLanguage(_prefs))),
        onboarded = ValueNotifier(_prefs.getBool(_kOnboarded) ?? false),
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
        _musicOn = _prefs.getBool(_kMusicOn) ?? false,
        _musicVolume = _prefs.getDouble(_kMusicVolume) ?? defaultMusicVolume,
        _musicTrack = _prefs.getString(_kMusicTrack) ?? defaultMusicTrack,
        _musicMode = MusicMode.fromName(_prefs.getString(_kMusicMode)),
        _kids = _readKids(_prefs),
        _currentKidId = _prefs.getString(_kCurrentKid) ?? Kid.firstId,
        _customColors = [
          for (final v in _prefs.getStringList(_kCustomColors) ?? const [])
            if (int.tryParse(v) case final int argb) Color(argb),
        ];

  static Future<AppSettings> load() async =>
      AppSettings(await SharedPreferences.getInstance());

  /// English for a new install. Versions before 2.1 were Chinese unless
  /// changed, so an existing install (any saved setting) stays Chinese.
  static String _defaultLanguage(SharedPreferences prefs) =>
      prefs.getKeys().isEmpty ? 'en' : 'zh';

  static List<Kid> _readKids(SharedPreferences prefs) {
    final raw = prefs.getString(_kKids);
    if (raw != null) {
      try {
        final kids = [
          for (final k in jsonDecode(raw) as List) ?Kid.fromJson(k),
        ];
        if (kids.isNotEmpty) return kids;
      } catch (_) {}
    }
    // This app was made for 靖瑶: an install from before kids existed keeps
    // her name, so the title stays the same.
    return [Kid(Kid.firstId, prefs.getKeys().isEmpty ? '' : '靖瑶')];
  }

  static const supportedLanguages = ['zh', 'en'];
  static const defaultThemeId = 'sakura';
  static const defaultFontId = 'kuaile';
  static const maxCustomColors = 8;
  static const minOpacity = 0.05;
  static const defaultMusicVolume = 0.4;
  static const defaultMusicTrack = 'builtin:sunny';

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
  static const _kMusicOn = 'musicOn';
  static const _kMusicVolume = 'musicVolume';
  static const _kMusicTrack = 'musicTrack';
  static const _kMusicMode = 'musicMode';
  static const _kOnboarded = 'onboarded';
  static const _kKids = 'kids';
  static const _kCurrentKid = 'currentKid';
  static String _kSize(BrushType b) => 'size.${b.name}';
  static String _kOpacity(BrushType b) => 'opacity.${b.name}';

  final SharedPreferences _prefs;

  /// Kept separate from the other settings so changing a brush doesn't
  /// rebuild the whole MaterialApp.
  final ValueNotifier<Locale> locale;
  final ValueNotifier<String> themeId;
  final ValueNotifier<String> fontId;

  /// Whether the first-start setup (language, theme, name) is done.
  final ValueNotifier<bool> onboarded;

  set onboardingDone(bool value) {
    _prefs.setBool(_kOnboarded, value);
    onboarded.value = value;
  }

  List<Kid> _kids;
  String _currentKidId;

  List<Kid> get kids => List.unmodifiable(_kids);

  /// The kid whose paintings are shown.
  Kid get currentKid =>
      _kids.firstWhere((k) => k.id == _currentKidId, orElse: () => _kids.first);

  /// The current kid's name ("" when not given), shown in the title.
  String get kidName => currentKid.name;

  void _saveKids() => _prefs.setString(
      _kKids, jsonEncode([for (final k in _kids) k.toJson()]));

  /// Switches to [id]'s paintings (see `Family`).
  set currentKidId(String id) {
    if (!_kids.any((k) => k.id == id) || id == _currentKidId) return;
    _currentKidId = id;
    _prefs.setString(_kCurrentKid, id);
    notifyListeners();
  }

  Kid addKid(String name) {
    final kid = Kid(DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        name.trim());
    _kids.add(kid);
    _saveKids();
    notifyListeners();
    return kid;
  }

  void renameKid(String id, String name) {
    final i = _kids.indexWhere((k) => k.id == id);
    if (i < 0) return;
    _kids[i] = _kids[i].withName(name.trim());
    _saveKids();
    notifyListeners();
  }

  /// Removes [id] from the list (its paintings are deleted by `Family`).
  /// The last kid can't be removed; reset the app instead.
  void removeKid(String id) {
    if (_kids.length < 2) return;
    _kids.removeWhere((k) => k.id == id);
    _prefs.remove('$_kLastPainting.$id');
    _saveKids();
    if (_currentKidId == id) currentKidId = _kids.first.id;
    notifyListeners();
  }

  /// Forgets every setting and kid, as on a fresh install: English, the
  /// default theme, and the first-start setup again.
  Future<void> resetAll() async {
    await _prefs.clear();
    _shape = null;
    _fill = false;
    _undoCorner = Corner.topRight;
    _toolsCorner = Corner.bottomRight;
    _brush = BrushType.pen;
    _color = Colors.black;
    _stamp = StampShape.heart;
    _mirror = false;
    _paper = const Color(0xFFFFFFFF);
    _musicOn = false;
    _musicVolume = defaultMusicVolume;
    _musicTrack = defaultMusicTrack;
    _musicMode = MusicMode.repeatOne;
    _customColors.clear();
    _kids = [const Kid(Kid.firstId, '')];
    _currentKidId = Kid.firstId;
    locale.value = const Locale('en');
    themeId.value = defaultThemeId;
    fontId.value = defaultFontId;
    onboarded.value = false;
    notifyListeners();
  }

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

  /// The painting the current kid last had open.
  String? get lastPaintingId => _prefs.getString(_lastPaintingKey);

  String get _lastPaintingKey => _currentKidId == Kid.firstId
      ? _kLastPainting
      : '$_kLastPainting.$_currentKidId';

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

  bool _musicOn;
  double _musicVolume;
  String _musicTrack;
  MusicMode _musicMode;

  /// What happens when a track ends.
  MusicMode get musicMode => _musicMode;

  set musicMode(MusicMode value) {
    _musicMode = value;
    _prefs.setString(_kMusicMode, value.name);
    notifyListeners();
  }

  /// Whether background music plays while the app is open.
  bool get musicOn => _musicOn;

  /// Background music volume, 0 to 1.
  double get musicVolume => _musicVolume;

  /// The background music track's id (see MusicLibrary).
  String get musicTrack => _musicTrack;

  set musicOn(bool value) {
    _musicOn = value;
    _prefs.setBool(_kMusicOn, value);
    notifyListeners();
  }

  set musicVolume(double value) {
    _musicVolume = value.clamp(0.0, 1.0);
    _prefs.setDouble(_kMusicVolume, _musicVolume);
    notifyListeners();
  }

  set musicTrack(String id) {
    _musicTrack = id;
    _prefs.setString(_kMusicTrack, id);
    notifyListeners();
  }

  set lastPaintingId(String? id) {
    if (id == null) {
      _prefs.remove(_lastPaintingKey);
    } else {
      _prefs.setString(_lastPaintingKey, id);
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
    onboarded.dispose();
    themeId.dispose();
    fontId.dispose();
    super.dispose();
  }
}
