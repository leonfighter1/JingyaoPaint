import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import 'stroke.dart';

/// What the drawing looked like before an edit, for undo and redo.
class _Snapshot {
  _Snapshot(List<Stroke> strokes, this.paper) : strokes = List.of(strokes);

  final List<Stroke> strokes;
  final Color paper;
}

/// Holds the strokes and paper color of the open painting, plus its
/// undo/redo history.
///
/// Every edit (a stroke, clearing, moving or editing text, changing paper)
/// records a snapshot first, so all of them can be undone. Strokes are never
/// changed in place, so a snapshot only needs to copy the list.
class DrawingController extends ChangeNotifier {
  final List<Stroke> strokes = [];
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  Stroke? current;
  Color paper = Colors.white;

  /// Older steps are forgotten past this many, to bound memory.
  static const maxUndo = 100;

  /// Bumped whenever the finished drawing changes, so listeners can tell an
  /// edit worth saving apart from a repaint of the stroke being drawn.
  int revision = 0;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isEmpty => strokes.isEmpty && current == null;

  /// The area everything drawn so far covers, or [Rect.zero] if nothing is.
  Rect get contentBounds => strokes.isEmpty
      ? Rect.zero
      : strokes.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b));

  /// Starts [stroke]. Freehand strokes pass their first [point]; shape
  /// strokes already have their outline.
  void begin(Stroke stroke, [PointVector? point]) {
    current = stroke;
    if (point != null) stroke.points.add(point);
    notifyListeners();
  }

  void extend(PointVector point) {
    if (current == null) return;
    current!.points.add(point);
    notifyListeners();
  }

  /// Drops the stroke being drawn without keeping it, for example when a
  /// second finger turns the touch into a pinch.
  void cancel() {
    if (current == null) return;
    current = null;
    notifyListeners();
  }

  /// Drags the far corner of the shape being drawn.
  void moveShapeEnd(Offset end) {
    final c = current;
    if (c == null || c.shape == null) return;
    c.setShapeEnds(c.shapeFrom!, end);
    notifyListeners();
  }

  void end() {
    if (current == null) return;
    if (current!.isDegenerateShape) {
      // A tap with a shape tool draws nothing.
      current = null;
      notifyListeners();
      return;
    }
    _record();
    strokes.add(current!..isComplete = true);
    current = null;
    _changed();
  }

  /// Adds a finished stroke, such as a new text item.
  void add(Stroke stroke) {
    _record();
    strokes.add(stroke);
    _changed();
  }

  /// Swaps [old] for [replacement] in place, keeping its layer order.
  /// Pass `recordUndo: false` for the later steps of one continuous edit
  /// (like dragging text), so the whole drag undoes in one step.
  void replace(Stroke old, Stroke replacement, {bool recordUndo = true}) {
    final i = strokes.indexOf(old);
    if (i < 0) return;
    if (recordUndo) _record();
    strokes[i] = replacement;
    _changed();
  }

  /// Swaps each of [olds] for the replacement at the same index, as one
  /// edit. See [replace] for `recordUndo`.
  void replaceAll(List<Stroke> olds, List<Stroke> replacements,
      {bool recordUndo = true}) {
    assert(olds.length == replacements.length);
    if (!olds.any(strokes.contains)) return;
    if (recordUndo) _record();
    for (final (i, old) in olds.indexed) {
      final at = strokes.indexOf(old);
      if (at >= 0) strokes[at] = replacements[i];
    }
    _changed();
  }

  /// Adds finished strokes on top, as one edit (for example copies).
  void addAll(List<Stroke> added) {
    if (added.isEmpty) return;
    _record();
    strokes.addAll(added);
    _changed();
  }

  void remove(Stroke stroke) => removeAll([stroke]);

  /// Removes [removed] as one edit.
  void removeAll(List<Stroke> removed) {
    if (!removed.any(strokes.contains)) return;
    _record();
    strokes.removeWhere(removed.contains);
    _changed();
  }

  /// The topmost stroke of any kind under [point], if any.
  Stroke? hitStroke(Offset point) {
    for (final s in strokes.reversed) {
      // Eraser strokes are invisible, so they can't be picked up.
      if (s.brush != BrushType.eraser && s.hits(point)) return s;
    }
    return null;
  }

  /// Every visible stroke a selection box over [box] catches, in drawing
  /// order.
  List<Stroke> strokesIn(Rect box) => [
        for (final s in strokes)
          if (s.brush != BrushType.eraser && s.touches(box)) s,
      ];

  /// The topmost text item under [point], if any.
  Stroke? hitText(Offset point) {
    for (final s in strokes.reversed) {
      if (s.text != null && s.hits(point)) return s;
    }
    return null;
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_Snapshot(strokes, paper));
    _restore(_undo.removeLast());
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_Snapshot(strokes, paper));
    _restore(_redo.removeLast());
  }

  /// Removes every stroke. Can be undone.
  void clear() {
    if (strokes.isEmpty) return;
    _record();
    strokes.clear();
    current = null;
    _changed();
  }

  void setPaper(Color color) {
    if (color.toARGB32() == paper.toARGB32()) return;
    _record();
    paper = color;
    _changed();
  }

  /// Replaces the drawing with [loaded] strokes and forgets undo history.
  void load(List<Stroke> loaded, {Color paper = Colors.white}) {
    strokes
      ..clear()
      ..addAll(loaded);
    _undo.clear();
    _redo.clear();
    current = null;
    this.paper = paper;
    revision++;
    notifyListeners();
  }

  void _record() {
    _undo.add(_Snapshot(strokes, paper));
    if (_undo.length > maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(_Snapshot s) {
    strokes
      ..clear()
      ..addAll(s.strokes);
    paper = s.paper;
    _changed();
  }

  void _changed() {
    revision++;
    notifyListeners();
  }

  void paintStrokes(Canvas canvas, Size size) =>
      _paint(canvas, size, [...strokes, ?current]);

  static void _paint(Canvas canvas, Size size, List<Stroke> strokes) {
    // Strokes go on their own layer so the eraser only removes ink, not the
    // paper underneath.
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in strokes) {
      stroke.paint(canvas);
    }
    canvas.restore();
  }

  /// Renders the drawing on its paper as PNG bytes.
  Future<Uint8List> exportPng(Size size, double pixelRatio) =>
      renderPng(strokes, size, pixelRatio, paper: paper);

  static Future<ui.Image> _renderImage(
      List<Stroke> strokes, Size size, double pixelRatio, Color paper) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    _paint(canvas, size, strokes);
    return recorder.endRecording().toImage(
        (size.width * pixelRatio).round().clamp(1, 1 << 14),
        (size.height * pixelRatio).round().clamp(1, 1 << 14));
  }

  /// Renders [strokes] on [paper] as PNG bytes.
  static Future<Uint8List> renderPng(
      List<Stroke> strokes, Size size, double pixelRatio,
      {Color paper = Colors.white}) async {
    final image = await _renderImage(strokes, size, pixelRatio, paper);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// Renders [strokes] on [paper] as raw RGBA pixels, for encoders that
  /// Flutter doesn't have built in (like JPEG).
  static Future<({Uint8List rgba, int width, int height})> renderRgba(
      List<Stroke> strokes, Size size, double pixelRatio,
      {Color paper = Colors.white}) async {
    final image = await _renderImage(strokes, size, pixelRatio, paper);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = (
      rgba: data!.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
    image.dispose();
    return result;
  }
}
