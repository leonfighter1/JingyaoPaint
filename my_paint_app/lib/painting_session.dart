import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'drawing/drawing_controller.dart';
import 'drawing/stroke.dart';
import 'gallery/painting_file.dart';
import 'gallery/painting_store.dart';
import 'settings.dart';

/// Renders a thumbnail for the gallery. Swappable so widget tests can skip
/// real image encoding, which doesn't complete under fake async.
typedef Thumbnailer = Future<Uint8List> Function(
    List<Stroke> strokes, Size size, Color paper);

/// Longest side of a gallery thumbnail, in pixels.
const thumbnailMaxSide = 360.0;

Future<Uint8List> renderThumbnail(List<Stroke> strokes, Size size, Color paper) {
  final scale = thumbnailMaxSide / math.max(size.width, size.height);
  return DrawingController.renderPng(strokes, size, scale, paper: paper);
}

/// The painting currently open on the canvas, and keeping it saved.
///
/// Every finished edit schedules an autosave; switching or creating a
/// painting saves first, so work is never silently dropped.
class PaintingSession extends ChangeNotifier {
  PaintingSession({
    required this.store,
    required this.settings,
    this.thumbnailer = renderThumbnail,
    this.autosaveDelay = const Duration(milliseconds: 800),
  }) : id = _newId(),
       createdAt = DateTime.now() {
    drawing.paper = settings.paper;
    drawing.addListener(_onDrawingChanged);
  }

  final PaintingStore store;
  final AppSettings settings;
  final Thumbnailer thumbnailer;
  final Duration autosaveDelay;
  final drawing = DrawingController();

  String id;
  DateTime createdAt;

  /// The open painting's paper size, in canvas units: set by the canvas on
  /// every layout to the space available, but never smaller than what's
  /// drawn (see `CanvasPage`). An opened painting starts at its saved size.
  Size canvasSize = Size.zero;

  /// Called when an autosave fails, so the UI can tell the user.
  void Function(Object error)? onSaveError;

  int _savedRevision = 0;

  /// Whether this painting exists in the store yet. Untouched new paintings
  /// aren't saved, so the gallery doesn't fill up with blank pages.
  bool _persisted = false;
  Timer? _autosave;

  bool get hasUnsavedChanges => drawing.revision != _savedRevision;

  /// Whether this painting is in My Paintings yet.
  bool get isSaved => _persisted;

  static int _lastId = 0;

  /// Time-based ids, forced to increase: the clock can return the same
  /// microsecond twice, and a repeated id would overwrite another painting.
  static String _newId() {
    _lastId = math.max(DateTime.now().microsecondsSinceEpoch, _lastId + 1);
    return _lastId.toString();
  }

  /// Reopens the painting that was open when the app last closed.
  Future<void> restoreLast() async {
    final lastId = settings.lastPaintingId;
    if (lastId == null) return;
    try {
      final doc = await store.load(lastId);
      if (doc != null) _show(doc);
    } catch (e) {
      debugPrint('Could not reopen painting $lastId: $e');
    }
  }

  void _onDrawingChanged() {
    if (!hasUnsavedChanges) return;
    _autosave?.cancel();
    _autosave = Timer(autosaveDelay, save);
  }

  /// Saves now if anything changed. Safe to call any time.
  ///
  /// Returns false if saving failed, so callers about to leave this
  /// painting can stop instead of losing work.
  Future<bool> save() => _lastSave = _save();

  /// The most recent save, so [delete] can wait for it rather than have it
  /// finish afterwards and bring the deleted painting back.
  Future<bool> _lastSave = Future.value(true);

  Future<bool> _save() async {
    _autosave?.cancel();
    if (!hasUnsavedChanges) return true;
    final revision = drawing.revision;
    if (drawing.strokes.isEmpty && !_persisted) {
      _savedRevision = revision;
      return true;
    }
    // Snapshot first: the user may keep drawing while this save runs.
    final strokes = List<Stroke>.of(drawing.strokes);
    final paper = drawing.paper;
    final size = canvasSize.isEmpty ? _boundsOf(strokes) : canvasSize;
    final paintingId = id;
    try {
      final thumbnail = await thumbnailer(strokes, size, paper);
      await store.save(
        PaintingDoc(
          meta: PaintingMeta(
            id: paintingId,
            createdAt: createdAt,
            updatedAt: DateTime.now(),
            width: size.width,
            height: size.height,
            strokeCount: strokes.length,
          ),
          strokes: strokes,
          paper: paper,
        ),
        thumbnail,
      );
      // Only mark saved if the user is still on the same painting.
      if (paintingId == id) {
        _savedRevision = revision;
        _persisted = true;
        settings.lastPaintingId = id;
      }
      return true;
    } catch (e) {
      debugPrint('Autosave failed: $e');
      onSaveError?.call(e);
      return false;
    }
  }

  /// Saves the current painting and starts a blank one.
  /// Returns false (and stays put) if the current painting couldn't be saved.
  Future<bool> newPainting() async {
    if (!await save()) return false;
    _reset(_newId(), DateTime.now(), const [], settings.paper);
    _persisted = false;
    settings.lastPaintingId = null;
    notifyListeners();
    return true;
  }

  /// The open painting as a document, for sending or printing.
  PaintingDoc currentDoc() {
    final strokes = List<Stroke>.of(drawing.strokes);
    final size = canvasSize.isEmpty ? _boundsOf(strokes) : canvasSize;
    return PaintingDoc(
      meta: PaintingMeta(
        id: id,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        width: size.width,
        height: size.height,
        strokeCount: strokes.length,
      ),
      strokes: strokes,
      paper: drawing.paper,
    );
  }

  /// Adds a `.jypaint` file someone sent as a new painting and opens it.
  /// It gets a fresh id, so it never overwrites an existing painting.
  /// Returns false if [bytes] isn't a painting file or saving failed.
  Future<bool> importPainting(Uint8List bytes) async {
    final PaintingDoc incoming;
    try {
      incoming = PaintingFile.decode(bytes);
    } on FormatException catch (e) {
      debugPrint('Import rejected: $e');
      return false;
    }
    if (!await save()) return false;
    final copy = PaintingDoc(
      meta: PaintingMeta(
        id: _newId(),
        createdAt: incoming.meta.createdAt,
        updatedAt: DateTime.now(),
        width: incoming.meta.width,
        height: incoming.meta.height,
        strokeCount: incoming.strokes.length,
      ),
      strokes: incoming.strokes,
      paper: incoming.paper,
    );
    try {
      final size = Size(copy.meta.width, copy.meta.height);
      await store.save(
        copy,
        await thumbnailer(copy.strokes,
            size.isEmpty ? _boundsOf(copy.strokes) : size, copy.paper),
      );
    } catch (e) {
      onSaveError?.call(e);
      return false;
    }
    _show(copy);
    return true;
  }

  /// Saves the current painting and opens [paintingId] from the store.
  /// Returns false if saving the current one or loading the new one failed.
  Future<bool> open(String paintingId) async {
    if (paintingId == id) return true;
    if (!await save()) return false;
    final doc = await store.load(paintingId);
    if (doc == null) return false;
    _show(doc);
    return true;
  }

  Future<void> delete(String paintingId) async {
    if (paintingId == id) {
      // Discard instead of saving: the user asked for it to be gone.
      _reset(_newId(), DateTime.now(), const [], settings.paper);
      _persisted = false;
      settings.lastPaintingId = null;
      notifyListeners();
    }
    await _lastSave;
    await store.delete(paintingId);
  }

  void _show(PaintingDoc doc) {
    _reset(doc.meta.id, doc.meta.createdAt, doc.strokes, doc.paper,
        size: Size(doc.meta.width, doc.meta.height));
    _persisted = true;
    settings.lastPaintingId = id;
    notifyListeners();
  }

  /// [size] is the painting's paper size; empty means "take whatever the
  /// canvas has room for", as for a new painting.
  void _reset(
      String newId, DateTime created, List<Stroke> strokes, Color paper,
      {Size size = Size.zero}) {
    id = newId;
    createdAt = created;
    canvasSize = size.isEmpty ? Size.zero : size;
    drawing.load(strokes, paper: paper);
    _savedRevision = drawing.revision;
    // Loading notifies listeners, which schedules an autosave; nothing
    // changed yet, so drop it.
    _autosave?.cancel();
  }

  static Size _boundsOf(List<Stroke> strokes) {
    var w = 1.0, h = 1.0;
    for (final s in strokes) {
      for (final p in s.points) {
        w = math.max(w, p.x + s.size);
        h = math.max(h, p.y + s.size);
      }
    }
    return Size(w, h);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    drawing.dispose();
    super.dispose();
  }
}
