import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerHoverEvent, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import '../app_theme.dart';
import '../image_saver.dart';
import '../l10n.dart';
import '../painting_session.dart';
import '../settings.dart';
import '../share/share_actions.dart';
import '../theme/cute_theme.dart';
import '../widgets/corner_float.dart';
import '../widgets/drop_menu.dart';
import 'drawing_controller.dart';
import 'stroke.dart';
import 'text_editor.dart';

class CanvasPage extends StatefulWidget {
  const CanvasPage({
    super.key,
    required this.session,
    required this.settings,
    required this.onOpenSettings,
  });

  final PaintingSession session;
  final AppSettings settings;

  /// Opens the settings page (from the ⋮ menu).
  final VoidCallback onOpenSettings;

  @override
  State<CanvasPage> createState() => CanvasPageState();
}

class CanvasPageState extends State<CanvasPage> with TickerProviderStateMixin {
  static const _palette = [
    Colors.black,
    Colors.white,
    Color(0xFFFF5A5F),
    Color(0xFFFF8E3C),
    Color(0xFFFFD23F),
    Color(0xFF3DDC97),
    Color(0xFF3DA9FC),
    Color(0xFF7F5AF0),
    Color(0xFFFF6FB5),
    Color(0xFFFFB3C7),
    Color(0xFFB8E0FF),
    Color(0xFF8D6E63),
  ];

  int? _activePointer;

  /// Where to show the eraser's range circle, or null to hide it. Shown
  /// after a long press while erasing, or while a mouse/stylus hovers.
  final _eraserCursor = ValueNotifier<Offset?>(null);
  Timer? _longPress;
  Offset _lastPointer = Offset.zero;
  static const longPressDelay = Duration(milliseconds: 350);

  /// The tools drawer: 0 = hidden, 1 = fully slid in.
  late final AnimationController _tools = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 240),
  )..addStatusListener((_) => setState(() {}));

  /// How the paper is zoomed and panned on screen. Only the view changes;
  /// the painting itself is untouched.
  final view = ValueNotifier<Matrix4>(Matrix4.identity());
  late final AnimationController _viewReset = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  static const minZoom = 0.5;
  static const maxZoom = 8.0;

  /// Fingers on the paper area, in screen-area coordinates, for pinching.
  final Map<int, Offset> _touches = {};

  /// True from the moment a second finger lands until every finger lifts:
  /// the touch is a pinch/pan, not drawing.
  bool _pinching = false;
  ({Offset focal, double distance, Matrix4 start})? _pinchStart;
  Size _room = Size.zero;
  String? _viewFor;

  DrawingController get _drawing => widget.session.drawing;
  AppSettings get _settings => widget.settings;
  bool get _erasing => _settings.brush == BrushType.eraser;
  bool get _toolsShown => _tools.status != AnimationStatus.dismissed;

  @override
  void initState() {
    super.initState();
    _viewFor = widget.session.id;
    widget.session.addListener(_onSessionChanged);
    _settings.addListener(_onSettingsChanged);
    _drawing.addListener(_onDrawingChanged);
    selectionFrame.addListener(_scheduleBarAnchor);
    view.addListener(_scheduleBarAnchor);
    _syncSelection();
  }

  /// A different painting starts at the whole-paper view. Done here, not
  /// while building, because changing the view rebuilds other widgets.
  void _onSessionChanged() {
    if (_viewFor == widget.session.id) return;
    _viewFor = widget.session.id;
    view.value = Matrix4.identity();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _settings.removeListener(_onSettingsChanged);
    _drawing.removeListener(_onDrawingChanged);
    selected.dispose();
    selectionFrame.dispose();
    selectionBox.dispose();
    _barAnchor.dispose();
    _longPress?.cancel();
    _eraserCursor.dispose();
    _tools.dispose();
    _viewReset.dispose();
    view.dispose();
    super.dispose();
  }

  // --- Tools drawer -------------------------------------------------------

  /// Respects the system "remove animations" setting.
  bool get _animate => !MediaQuery.disableAnimationsOf(context);

  void _openTools() => _animate ? _tools.forward() : _tools.value = 1;
  void _closeTools() => _animate ? _tools.reverse() : _tools.value = 0;

  // --- Zoom and pan -------------------------------------------------------

  void _onFrameDown(PointerDownEvent e) {
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) _startPinch();
  }

  void _onFrameMove(PointerMoveEvent e) {
    if (!_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.localPosition;
    if (_pinchStart != null) _updatePinch();
  }

  void _onFrameUp(PointerEvent e) {
    _touches.remove(e.pointer);
    if (_touches.length < 2) _pinchStart = null;
    if (_touches.isEmpty) _pinching = false;
  }

  void _startPinch() {
    _pinching = true;
    // The first finger may already have started a stroke; a pinch isn't
    // drawing, so drop it.
    _drawing.cancel();
    _textGesture = null;
    _activePointer = null;
    _longPress?.cancel();
    _eraserCursor.value = null;
    final pts = _touches.values.toList();
    _pinchStart = (
      focal: (pts[0] + pts[1]) / 2,
      distance: math.max(1, (pts[0] - pts[1]).distance),
      start: view.value.clone(),
    );
  }

  void _updatePinch() {
    final start = _pinchStart!;
    final pts = _touches.values.take(2).toList();
    final focal = (pts[0] + pts[1]) / 2;
    final base = zoomLevel(start.start);
    final zoom = (base * (pts[0] - pts[1]).distance / start.distance).clamp(
      minZoom,
      maxZoom,
    );
    // Scale around where the fingers started, then follow their midpoint so
    // moving both fingers together pans.
    final pan = focal - start.focal;
    view.value = Matrix4.translationValues(
      pan.dx,
      pan.dy,
      0,
    ).multiplied(_scaledAround(start.start, start.focal, zoom / base));
  }

  /// The view's zoom factor. Not `getMaxScaleOnAxis`: that also counts the
  /// untouched z axis (always 1), so it never reports less than 100%.
  static double zoomLevel(Matrix4 m) =>
      math.sqrt(m.entry(0, 0) * m.entry(0, 0) + m.entry(1, 0) * m.entry(1, 0));

  static Matrix4 _scaledAround(Matrix4 m, Offset focal, double k) =>
      Matrix4.translationValues(focal.dx, focal.dy, 0)
          .multiplied(Matrix4.diagonal3Values(k, k, 1))
          .multiplied(Matrix4.translationValues(-focal.dx, -focal.dy, 0))
          .multiplied(m);

  /// Zooms by [factor] around [focal] (mouse wheel, menu buttons).
  void _zoomAt(Offset focal, double factor) {
    final current = zoomLevel(view.value);
    final next = (current * factor).clamp(minZoom, maxZoom);
    view.value = _scaledAround(view.value, focal, next / current);
  }

  void _zoomCenter(double factor) =>
      _zoomAt(Offset(_room.width / 2, _room.height / 2), factor);

  /// Back to the whole paper on screen.
  void resetView() {
    if (!_animate) {
      view.value = Matrix4.identity();
      return;
    }
    final tween = Matrix4Tween(
      begin: view.value.clone(),
      end: Matrix4.identity(),
    );
    final curve = CurvedAnimation(
      parent: _viewReset,
      curve: Curves.easeOutCubic,
    );
    void step() => view.value = tween.evaluate(curve);
    _viewReset
      ..reset()
      ..addListener(step)
      ..forward().whenComplete(() => _viewReset.removeListener(step));
  }

  PointVector _toPoint(PointerEvent e) {
    final pressure = e.kind == ui.PointerDeviceKind.stylus ? e.pressure : 0.5;
    return PointVector(e.localPosition.dx, e.localPosition.dy, pressure);
  }

  void _onDown(PointerDownEvent e) {
    // Ignore extra fingers here: a second finger starts a pinch (handled by
    // the frame listener), and nothing draws until every finger lifts.
    if (_activePointer != null || _pinching) return;
    _activePointer = e.pointer;
    _lastPointer = e.localPosition;
    if (_settings.brush == BrushType.text) {
      _textGesture = (
        hit: _drawing.hitText(e.localPosition),
        down: e.localPosition,
        dragged: null,
      );
      return;
    }
    if (_settings.brush == BrushType.move) {
      _startMove(e.localPosition);
      return;
    }
    final mirrorX = _settings.mirror
        ? widget.session.canvasSize.width / 2
        : null;
    // The eraser always has a round tip; it never draws shapes.
    final shape = _settings.brush.usesShapes ? _settings.shape : null;
    if (shape != null) {
      _drawing.begin(
        Stroke.shape(
          shape: shape,
          from: e.localPosition,
          to: e.localPosition,
          brush: _settings.brush,
          color: _settings.color,
          size: _settings.size,
          opacity: _settings.opacity,
          fill: _settings.fill,
          stamp: _settings.stamp,
          mirrorX: mirrorX,
        ),
      );
    } else {
      _drawing.begin(
        Stroke(
          brush: _settings.brush,
          color: _settings.color,
          size: _settings.size,
          opacity: _settings.opacity,
          stamp: _settings.stamp,
          mirrorX: mirrorX,
          usesRealPressure: e.kind == ui.PointerDeviceKind.stylus,
        ),
        _toPoint(e),
      );
    }
    if (_erasing) {
      _longPress?.cancel();
      _longPress = Timer(
        longPressDelay,
        () => _eraserCursor.value = _lastPointer,
      );
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _activePointer || _pinching) return;
    _lastPointer = e.localPosition;
    if (_textGesture != null) {
      _dragText(e.localPosition);
      return;
    }
    if (_settings.brush == BrushType.move) {
      _continueMove(e.localPosition);
      return;
    }
    if (_eraserCursor.value != null) _eraserCursor.value = e.localPosition;
    if (_drawing.current?.shape != null) {
      _drawing.moveShapeEnd(e.localPosition);
    } else {
      _drawing.extend(_toPoint(e));
    }
  }

  void _onUp(PointerEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    _longPress?.cancel();
    _eraserCursor.value = null;
    if (_textGesture case final g?) {
      _textGesture = null;
      // A tap (not a drag, not a cancelled touch) adds or edits text.
      if (e is! PointerCancelEvent && g.dragged == null) {
        g.hit != null ? _editText(g.hit!) : _addText(g.down);
      }
      return;
    }
    if (_settings.brush == BrushType.move) {
      _endMove(cancelled: e is PointerCancelEvent);
      return;
    }
    _drawing.end();
  }

  // --- Move tool: select, move, resize, turn ------------------------------

  /// The move tool's current touch.
  _MoveGesture? _moveGesture;

  /// The strokes the move tool has selected, outlined on the paper.
  final selected = ValueNotifier<List<Stroke>>(const []);

  /// The dashed box around [selected], with its resize and turn handles.
  final selectionFrame = ValueNotifier<SelectionFrame?>(null);

  /// The box being dragged out over empty paper to select several strokes.
  final selectionBox = ValueNotifier<Rect?>(null);

  /// How close (in paper points) a touch must be to grab a handle.
  static const handleReach = 30.0;

  /// The brush the selection was last synced with.
  BrushType? _syncedBrush;

  void _select(List<Stroke> strokes, {SelectionFrame? frame}) {
    selected.value = List.unmodifiable(strokes);
    selectionFrame.value = frame ?? SelectionFrameHandles.around(strokes);
  }

  /// Where the selection is on screen (in the canvas stack's coordinates),
  /// so the selection bar can sit next to it. Null while a finger is moving
  /// the selection, which hides the bar.
  final _barAnchor = ValueNotifier<Rect?>(null);
  final _stackKey = GlobalKey();
  final _paperBoxKey = GlobalKey();
  bool _anchorScheduled = false;

  /// Measured after the next layout, when the paper's place on screen is
  /// known (never during build).
  void _scheduleBarAnchor() {
    if (_anchorScheduled) return;
    _anchorScheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _anchorScheduled = false;
        if (mounted) _updateBarAnchor();
      })
      ..ensureVisualUpdate();
  }

  void _updateBarAnchor() {
    final f = selectionFrame.value;
    final paper = _paperBoxKey.currentContext?.findRenderObject();
    final stack = _stackKey.currentContext?.findRenderObject();
    if (f == null ||
        _moveGesture != null ||
        paper is! RenderBox ||
        stack is! RenderBox) {
      _barAnchor.value = null;
      return;
    }
    // Through the zoom and the paper's fit-to-screen scaling.
    final toStack = paper.getTransformTo(stack);
    final corners = [
      f.box.topLeft,
      f.box.topRight,
      f.box.bottomLeft,
      f.box.bottomRight,
      f.box.topCenter - const Offset(0, SelectionFrameHandles.rotateHandleGap),
    ].map((p) => MatrixUtils.transformPoint(toStack, f.transform.apply(p)));
    _barAnchor.value = corners
        .map((p) => Rect.fromCenter(center: p, width: 36, height: 36))
        .reduce((a, b) => a.expandToInclude(b));
  }

  /// Touching a handle resizes or turns the selection; touching a selected
  /// stroke (or anywhere inside the selection's box) moves the selection;
  /// touching another stroke selects and moves just that one; touching
  /// empty paper starts a box that selects every stroke it catches.
  void _startMove(Offset p) {
    final sel = selected.value;
    final frame = selectionFrame.value;
    if (frame != null && sel.isNotEmpty) {
      if ((p - frame.scaleHandle).distance <= handleReach) {
        _moveGesture = _MoveGesture(_MoveMode.scale, sel, p, frame.box);
        return;
      }
      if ((p - frame.rotateHandle).distance <= handleReach) {
        _moveGesture = _MoveGesture(_MoveMode.rotate, sel, p, frame.box);
        return;
      }
    }
    final hit = _drawing.hitStroke(p);
    if (hit != null && !sel.contains(hit)) {
      _select([hit]);
      _moveGesture =
          _MoveGesture(_MoveMode.drag, [hit], p, selectionFrame.value!.box);
      return;
    }
    if (frame != null && (hit != null || frame.box.contains(p))) {
      _moveGesture = _MoveGesture(_MoveMode.drag, sel, p, frame.box);
      return;
    }
    _select(const []);
    _moveGesture = _MoveGesture(_MoveMode.box, const [], p, Rect.zero);
    selectionBox.value = Rect.fromPoints(p, p);
  }

  void _continueMove(Offset p) {
    final g = _moveGesture;
    if (g == null) return;
    final center = g.frame.center;
    switch (g.mode) {
      case _MoveMode.box:
        selectionBox.value = Rect.fromPoints(g.down, p);
      case _MoveMode.drag:
        final delta = p - g.down;
        if (g.current == null && delta.distance < _dragSlop) return;
        _applyMove(g, [for (final s in g.originals) s.moved(delta)]);
      case _MoveMode.scale:
        final k = ((p - center).distance /
                math.max(1, (g.down - center).distance))
            .clamp(minSelectionScale, maxSelectionScale);
        _applyMove(g, null, StrokeTransform.around(center, scale: k));
      case _MoveMode.rotate:
        final angle = (p - center).direction - (g.down - center).direction;
        _applyMove(g, null, StrokeTransform.around(center, angle: angle));
    }
  }

  static const minSelectionScale = 0.1;
  static const maxSelectionScale = 10.0;

  /// Puts the moved strokes on the paper. A resize or turn ([t]) also turns
  /// the dashed box with them, so the handles stay under the finger.
  void _applyMove(_MoveGesture g, List<Stroke>? moved, [StrokeTransform? t]) {
    final next = moved ?? [for (final s in g.originals) s.transformed(t!)];
    // Only the first step records undo, so a whole drag undoes at once.
    _drawing.replaceAll(
      g.current ?? g.originals,
      next,
      recordUndo: g.current == null,
    );
    g.current = next;
    _select(next, frame: t == null ? null : (box: g.frame, transform: t));
  }

  void _endMove({required bool cancelled}) {
    final g = _moveGesture;
    _moveGesture = null;
    if (g == null) return;
    if (g.mode == _MoveMode.box) {
      final box = selectionBox.value;
      selectionBox.value = null;
      // A tap on empty paper selects nothing.
      if (!cancelled && box != null && box.longestSide >= _dragSlop) {
        _select(_drawing.strokesIn(box));
      }
    } else if (g.current case final moved?) {
      // Back to an upright box around the new shape.
      _select(moved);
    }
    // The bar hid while the finger was down; bring it back.
    _scheduleBarAnchor();
  }

  /// Resizes or turns the whole selection around its middle (from the
  /// selection bar's buttons).
  void _transformSelection({double scale = 1, double angle = 0}) {
    final sel = selected.value;
    final frame = selectionFrame.value;
    if (sel.isEmpty || frame == null) return;
    final t =
        StrokeTransform.around(frame.box.center, scale: scale, angle: angle);
    final next = [for (final s in sel) s.transformed(t)];
    _drawing.replaceAll(sel, next);
    _select(next);
  }

  /// Copies sit a little down and to the right, and become the selection.
  void _duplicateSelection() {
    final copies = [
      for (final s in selected.value) s.moved(const Offset(24, 24)),
    ];
    _drawing.addAll(copies);
    _select(copies);
  }

  void _deleteSelection() {
    _drawing.removeAll(selected.value);
    _select(const []);
  }

  /// Recolors the selection. Rainbow strokes keep their own colors.
  void _recolorSelection(Color color) {
    final sel = selected.value;
    final next = [
      for (final s in sel)
        s.brush == BrushType.rainbow ? s : s.copyWith(color: color),
    ];
    _drawing.replaceAll(sel, next);
    _select(next);
  }

  /// Sets the selection's opacity. Pass `recordUndo: false` while the
  /// slider is still being dragged.
  void _fadeSelection(double opacity, {required bool recordUndo}) {
    final sel = selected.value;
    final next = [for (final s in sel) s.copyWith(opacity: opacity)];
    _drawing.replaceAll(sel, next, recordUndo: recordUndo);
    _select(next);
  }

  Future<void> _showSelectionStyle() async {
    final sel = selected.value;
    if (sel.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _SelectionStyleSheet(
        palette: _palette,
        customColors: _settings.customColors,
        color: sel.first.color,
        opacity: sel.first.opacity,
        onColor: _recolorSelection,
        onMoreColors: () async {
          final picked = await _showColorPicker(sel.first.color);
          if (picked == null) return null;
          _settings.addCustomColor(picked);
          _recolorSelection(picked);
          return picked;
        },
        onOpacity: _fadeSelection,
      ),
    );
  }

  /// Rebuilds the floating controls (their corners and the brush they show)
  /// and keeps the move tool's selection in step with the brush.
  void _onSettingsChanged() {
    _syncSelection();
    setState(() {});
  }

  /// Switching to the move tool selects the last thing drawn; switching
  /// away clears the selection.
  void _syncSelection() {
    final brush = _settings.brush;
    if (brush != BrushType.move) {
      if (selected.value.isNotEmpty) _select(const []);
    } else if (_syncedBrush != BrushType.move) {
      // Eraser strokes are invisible, so they're never selected.
      final last = _drawing.strokes.reversed
          .where((s) => s.brush != BrushType.eraser)
          .firstOrNull;
      _select([?last]);
    }
    _syncedBrush = brush;
  }

  /// Undo can remove selected strokes; the rest stay selected.
  void _onDrawingChanged() {
    if (_moveGesture != null) return;
    final sel = selected.value;
    final kept = [for (final s in sel) if (_drawing.strokes.contains(s)) s];
    if (kept.length != sel.length) _select(kept);
  }

  /// The text tool's current touch: the text under the finger (if any),
  /// where the finger went down, and the moved copy while dragging.
  ({Stroke? hit, Offset down, Stroke? dragged})? _textGesture;

  /// How far a finger must move before a tap on text becomes a drag.
  static const _dragSlop = 6.0;

  void _dragText(Offset at) {
    final g = _textGesture!;
    final hit = g.hit;
    if (hit == null) return;
    final delta = at - g.down;
    if (g.dragged == null && delta.distance < _dragSlop) return;
    final moved = hit.moved(delta);
    // Only the first step records undo, so a whole drag undoes at once.
    _drawing.replace(g.dragged ?? hit, moved, recordUndo: g.dragged == null);
    _textGesture = (hit: hit, down: g.down, dragged: moved);
  }

  Future<void> _addText(Offset at) async {
    final style =
        (_settings.textStyle ??
                TextContent(
                  fontFamily: fontById(_settings.fontId.value).family,
                ))
            .copyWith(fontSize: _settings.size * BrushType.text.sizeFactor);
    final result = await showTextEditor(
      context,
      initial: style,
      color: _settings.color,
      palette: _palette,
    );
    if (result?.content case final content?) {
      _rememberText(content, result!.color!);
      _drawing.add(
        Stroke.text(
          anchor: at,
          content: content,
          color: result.color!,
          opacity: _settings.opacity,
        ),
      );
    }
  }

  Future<void> _editText(Stroke item) async {
    final result = await showTextEditor(
      context,
      initial: item.text!,
      color: item.color,
      palette: _palette,
      editing: true,
    );
    if (result == null) return;
    if (result.delete) {
      _drawing.remove(item);
    } else {
      _rememberText(result.content!, result.color!);
      _drawing.replace(
        item,
        Stroke.text(
          anchor: item.anchor,
          content: result.content!,
          color: result.color!,
          opacity: item.opacity,
          transform: item.transform,
        ),
      );
    }
  }

  /// The next text starts with the same formatting, size and color.
  void _rememberText(TextContent content, Color color) {
    _settings
      ..textStyle = content
      ..size = content.fontSize / BrushType.text.sizeFactor
      ..color = color;
  }

  /// A mouse or stylus hovering with the eraser previews its range too.
  void _onHover(PointerHoverEvent e) {
    _eraserCursor.value = _erasing ? e.localPosition : null;
  }

  Future<void> _pickColor() async {
    final picked = await _showColorPicker(_settings.color);
    if (picked != null) {
      _settings
        ..color = picked
        ..addCustomColor(picked);
    }
  }

  /// The full color picker. Returns the chosen (opaque) color, or null.
  Future<Color?> _showColorPicker(Color initial) async {
    final s = S.of(context);
    var picked = initial.withValues(alpha: 1);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.pickColor),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            // Transparency has its own slider.
            enableAlpha: false,
            displayThumbColor: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.useColor),
          ),
        ],
      ),
    );
    return ok == true ? picked : null;
  }

  Future<void> _pickPaper() async {
    final s = S.of(context);
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(s.paperColor),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (i, paper) in AppTheme.papers.indexed)
                  _PaperChoice(
                    color: paper,
                    label: s.paperNames[i],
                    selected: paper.toARGB32() == _drawing.paper.toARGB32(),
                    onTap: () => Navigator.pop(context, paper),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      _drawing.setPaper(picked);
      _settings.paper = picked;
    }
  }

  Future<void> _confirmClear() async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.clearTitle),
        content: Text(s.clearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    if (ok == true) _drawing.clear();
  }

  /// Whether there's a painting worth saving or deleting (not a blank,
  /// never-saved page).
  bool get _hasPainting =>
      _drawing.strokes.isNotEmpty || widget.session.isSaved;

  /// The ⋮ menu: a grouped list that unfolds from the top and scrolls.
  Future<void> _openMenu() {
    final s = S.of(context);
    return showDropMenu(context, [
      DropMenuSection(
        title: s.menuShare,
        items: [
          DropMenuItem(
            icon: Icons.send_rounded,
            label: s.send,
            onSelected: () =>
                showSendSheet(context, widget.session.currentDoc()),
          ),
          DropMenuItem(
            icon: Icons.print_rounded,
            label: s.print,
            onSelected: () =>
                printPainting(context, widget.session.currentDoc()),
          ),
          DropMenuItem(
            icon: Icons.save_alt_rounded,
            label: kIsWeb ? s.downloadImage : s.saveToGallery,
            onSelected: _exportImage,
          ),
        ],
      ),
      // Zoom without pinching, for anyone who can't use two fingers.
      DropMenuSection(
        title: s.menuView,
        items: [
          DropMenuItem(
            icon: Icons.zoom_in_rounded,
            label: s.zoomIn,
            onSelected: () => _zoomCenter(1.25),
          ),
          DropMenuItem(
            icon: Icons.zoom_out_rounded,
            label: s.zoomOut,
            onSelected: () => _zoomCenter(0.8),
          ),
          DropMenuItem(
            icon: Icons.fit_screen_rounded,
            label: s.fitScreen,
            onSelected: resetView,
          ),
        ],
      ),
      DropMenuSection(
        title: s.menuPaper,
        items: [
          DropMenuItem(
            icon: Icons.flip_rounded,
            label: s.mirror,
            checked: _settings.mirror,
            onSelected: () => _settings.mirror = !_settings.mirror,
          ),
          DropMenuItem(
            icon: Icons.wallpaper_rounded,
            label: s.paperColor,
            onSelected: _pickPaper,
          ),
        ],
      ),
      // A quick switch; volume and tracks are in Settings.
      DropMenuSection(
        title: s.menuSound,
        items: [
          DropMenuItem(
            icon: Icons.music_note_rounded,
            label: s.backgroundMusic,
            checked: _settings.musicOn,
            onSelected: () => _settings.musicOn = !_settings.musicOn,
          ),
        ],
      ),
      DropMenuSection(
        title: s.menuPainting,
        items: [
          DropMenuItem(
            icon: Icons.delete_outline_rounded,
            label: s.deletePainting,
            danger: true,
            enabled: _hasPainting,
            onSelected: _confirmDeletePainting,
          ),
        ],
      ),
      DropMenuSection(
        items: [
          DropMenuItem(
            icon: Icons.settings_rounded,
            label: s.navSettings,
            onSelected: widget.onOpenSettings,
          ),
        ],
      ),
    ]);
  }

  /// Saves right now (autosave would too, a moment later) and says so.
  Future<void> _savePainting() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // A failure is already reported by the session's onSaveError.
    if (await widget.session.save()) {
      messenger.showSnackBar(SnackBar(content: Text(s.paintingSaved)));
    }
  }

  Future<void> _confirmDeletePainting() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.deleteTitle),
        content: Text(s.deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.session.delete(widget.session.id);
    messenger.showSnackBar(SnackBar(content: Text(s.paintingDeleted)));
  }

  Future<void> _newPainting() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (await widget.session.newPainting()) {
      messenger.showSnackBar(SnackBar(content: Text(s.newPaintingStarted)));
    }
  }

  Future<void> _exportImage() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final size = widget.session.canvasSize;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final name = 'paint_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final bytes = await _drawing.exportPng(size, pixelRatio);
      await saveImage(bytes, name);
      messenger.showSnackBar(
        SnackBar(
          content: Text(kIsWeb ? s.downloaded('$name.png') : s.savedToGallery),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.saveFailed(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    return Scaffold(
      appBar: GradientAppBar(
        title: AppLogoTitle(text: s.appTitle),
        // The painting's own actions, one tap away; everything else lives in
        // the ⋮ menu. Undo and redo float at the paper's top left.
        actions: [
          IconButton(
            tooltip: s.newPainting,
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: _newPainting,
          ),
          ListenableBuilder(
            listenable: Listenable.merge([_drawing, widget.session]),
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: s.savePainting,
                  icon: const Icon(Icons.save_rounded),
                  onPressed: _hasPainting ? _savePainting : null,
                ),
                IconButton(
                  tooltip: s.clear,
                  icon: const Icon(Icons.layers_clear_rounded),
                  onPressed: _drawing.strokes.isEmpty ? null : _confirmClear,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.more,
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: _openMenu,
          ),
        ],
      ),
      // While the tools drawer is open, Back closes it instead of leaving.
      body: PopScope(
        canPop: !_toolsShown,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _closeTools();
        },
        child: LayoutBuilder(
          builder: (context, box) {
            final drawerWidth = math.min(drawerMaxWidth, box.maxWidth * 0.88);
            final slide = CurvedAnimation(
              parent: _tools,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            final area = box.biggest;
            final margin = EdgeInsets.fromLTRB(
              16,
              14,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            );
            // The drawer opens from the side the tools button is on.
            final fromLeft = _settings.toolsCorner.isLeft;
            return Stack(
              key: _stackKey,
              children: [
                Positioned.fill(child: _buildPaper(s, cute)),
                // Centered at the top, clear of every corner.
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _ZoomChip(view: view, onReset: resetView),
                  ),
                ),
                // What the move tool can do with the selection, right next to
                // it (and under the corner controls, which stay usable).
                if (_settings.brush == BrushType.move)
                  Positioned.fill(
                    child: ValueListenableBuilder(
                      valueListenable: _barAnchor,
                      builder: (context, anchor, bar) => anchor == null
                          ? const SizedBox.shrink()
                          : CustomSingleChildLayout(
                              delegate: _NextToSelection(anchor),
                              child: bar,
                            ),
                      child: _SelectionBar(
                        selected: selected,
                        hide: slide,
                        actions: [
                          (
                            Icons.copy_rounded,
                            s.duplicate,
                            _duplicateSelection,
                          ),
                          (
                            Icons.open_in_full_rounded,
                            s.makeBigger,
                            () => _transformSelection(scale: 1.25),
                          ),
                          (
                            Icons.close_fullscreen_rounded,
                            s.makeSmaller,
                            () => _transformSelection(scale: 0.8),
                          ),
                          (
                            Icons.rotate_left_rounded,
                            s.turnLeft,
                            () => _transformSelection(angle: -math.pi / 12),
                          ),
                          (
                            Icons.rotate_right_rounded,
                            s.turnRight,
                            () => _transformSelection(angle: math.pi / 12),
                          ),
                          (
                            Icons.palette_rounded,
                            s.colorAndOpacity,
                            _showSelectionStyle,
                          ),
                          (
                            Icons.delete_outline_rounded,
                            s.deleteSelection,
                            _deleteSelection,
                          ),
                        ],
                      ),
                    ),
                  ),
                // Undo/redo and the tools button can each be dragged to any
                // corner; they never share one.
                CornerFloat(
                  key: undoFloatKey,
                  corner: _settings.undoCorner,
                  blocked: _settings.toolsCorner,
                  area: area,
                  margin: margin,
                  onCornerChanged: (c) => _settings.undoCorner = c,
                  child: _UndoRedoBar(drawing: _drawing, hide: slide),
                ),
                CornerFloat(
                  key: toolsFloatKey,
                  corner: _settings.toolsCorner,
                  blocked: _settings.undoCorner,
                  area: area,
                  margin: margin,
                  onCornerChanged: (c) => _settings.toolsCorner = c,
                  child: _ToolsLauncher(
                    key: toolsButtonKey,
                    settings: _settings,
                    fromLeft: fromLeft,
                    // Fades and shrinks away as the drawer slides in.
                    hide: slide,
                    onTap: _openTools,
                  ),
                ),
                if (_toolsShown) ...[
                  Positioned.fill(
                    child: FadeTransition(
                      opacity: slide,
                      child: ModalBarrier(
                        color: Colors.black.withValues(alpha: 0.22),
                        dismissible: true,
                        onDismiss: _closeTools,
                        semanticsLabel: s.closeTools,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: fromLeft ? 0 : null,
                    right: fromLeft ? null : 0,
                    width: drawerWidth,
                    child: SlideTransition(
                      position: Tween(
                        begin: Offset(fromLeft ? -1 : 1, 0),
                        end: Offset.zero,
                      ).animate(slide),
                      child: _ToolDrawer(
                        settings: _settings,
                        palette: _palette,
                        fromLeft: fromLeft,
                        onClose: _closeTools,
                        onMoreColors: _pickColor,
                        // Dragging the header back toward its edge closes it.
                        onDrag: (dx) =>
                            _tools.value -= (fromLeft ? -dx : dx) / drawerWidth,
                        onDragEnd: (velocity) =>
                            (fromLeft ? -velocity : velocity) > 300 ||
                                _tools.value < 0.6
                            ? _closeTools()
                            : _openTools(),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static const drawerMaxWidth = 360.0;

  /// Finds the tools button and the drawer's scrolling list in tests.
  static const toolsButtonKey = Key('toolsButton');
  static const toolsFloatKey = Key('toolsFloat');
  static const undoFloatKey = Key('undoFloat');
  static const toolsListKey = Key('toolsList');
  static const selectionBarKey = Key('selectionBar');

  /// The paper, like a sketchbook sheet, inside a zoomable view.
  ///
  /// The paper fills the space available, but is never smaller than what's
  /// already drawn. So when the space shrinks or changes shape (rotating a
  /// tablet, opening a painting made on a bigger screen) the whole sheet is
  /// scaled down to fit instead of cutting the drawing off. FittedBox and the
  /// zoom Transform both map touches back to paper coordinates, so drawing
  /// lands under the finger at any scale.
  Widget _buildPaper(S s, CuteTheme cute) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: ListenableBuilder(
        // An opened painting brings its own content.
        listenable: widget.session,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final room = constraints.biggest;
            _room = room;
            final drawn = _drawing.contentBounds;
            final size = Size(
              math.max(room.width, drawn.right),
              math.max(room.height, drawn.bottom),
            );
            widget.session.canvasSize = size;
            return ClipRect(
              child: Listener(
                // Sees every finger (in screen-area coordinates) to detect
                // pinches; the paper's own listener below does the drawing.
                onPointerDown: _onFrameDown,
                onPointerMove: _onFrameMove,
                onPointerUp: _onFrameUp,
                onPointerCancel: _onFrameUp,
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) {
                    _zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 400));
                  }
                },
                behavior: HitTestBehavior.translucent,
                child: ValueListenableBuilder(
                  valueListenable: view,
                  builder: (context, matrix, child) =>
                      Transform(key: zoomKey, transform: matrix, child: child),
                  child: _paperSheet(s, cute, size),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Finds the zoom transform in tests.
  static const zoomKey = Key('zoom');

  Widget _paperSheet(S s, CuteTheme cute, Size size) {
    return Center(
      child: AspectRatio(
        aspectRatio: size.width / size.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cute.radius),
            boxShadow: [
              BoxShadow(
                color: cute.spec.primary.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(cute.radius),
            child: FittedBox(
              child: SizedBox.fromSize(
                size: size,
                child: Semantics(
                  label: s.canvasLabel,
                  child: MouseRegion(
                    onHover: _onHover,
                    onExit: (_) => _eraserCursor.value = null,
                    child: Listener(
                      onPointerDown: _onDown,
                      onPointerMove: _onMove,
                      onPointerUp: _onUp,
                      onPointerCancel: _onUp,
                      child: RepaintBoundary(
                        key: _paperBoxKey,
                        child: CustomPaint(
                          key: paperKey,
                          painter: _CanvasPainter(_drawing),
                          foregroundPainter: CanvasOverlayPainter(
                            settings: _settings,
                            eraserCursor: _eraserCursor,
                            selected: selected,
                            frame: selectionFrame,
                            selectionBox: selectionBox,
                            accent: cute.spec.primary,
                            ink: cute.ink,
                          ),
                          size: size,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Finds the paper in tests.
  static const paperKey = Key('paper');
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.controller) : super(repaint: controller);

  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = controller.paper);
    controller.paintStrokes(canvas, size);
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) =>
      oldDelegate.controller != controller;
}

/// The dashed box around the move tool's selection: [box], turned and
/// resized by [transform] while a handle is dragged (upright otherwise).
typedef SelectionFrame = ({Rect box, StrokeTransform transform});

extension SelectionFrameHandles on SelectionFrame {
  /// The upright frame around [strokes], or null when nothing is selected.
  static SelectionFrame? around(List<Stroke> strokes) {
    if (strokes.isEmpty) return null;
    final bounds = strokes
        .map((s) => s.bounds)
        .reduce((a, b) => a.expandToInclude(b));
    return (box: bounds.inflate(10), transform: _upright);
  }

  static const _upright = StrokeTransform(1, 0, 0, 1, 0, 0);

  /// Drag this corner to make the selection bigger or smaller.
  Offset get scaleHandle => transform.apply(box.bottomRight);

  /// Drag this knob above the box to turn the selection.
  Offset get rotateHandle =>
      transform.apply(box.topCenter - const Offset(0, rotateHandleGap));

  static const rotateHandleGap = 40.0;
}

/// Guides drawn over the paper that are not part of the picture: the dashed
/// mirror axis, the eraser's range circle and the move tool's selection.
class CanvasOverlayPainter extends CustomPainter {
  CanvasOverlayPainter({
    required this.settings,
    required this.eraserCursor,
    required this.selected,
    required this.frame,
    required this.selectionBox,
    required this.accent,
    required this.ink,
  }) : super(
         repaint: Listenable.merge([
           settings,
           eraserCursor,
           frame,
           selectionBox,
         ]),
       );

  final AppSettings settings;
  final ValueListenable<Offset?> eraserCursor;

  /// The move tool's selection.
  final ValueListenable<List<Stroke>> selected;

  /// The dashed box drawn around [selected], with its handles.
  final ValueListenable<SelectionFrame?> frame;

  /// The box being dragged out to select several strokes.
  final ValueListenable<Rect?> selectionBox;
  final Color accent;
  final Color ink;

  /// The eraser circle's radius, matching how wide the eraser actually is.
  static double eraserRadius(AppSettings s) =>
      s.size * BrushType.eraser.sizeFactor / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    if (settings.mirror) {
      final paint = Paint()
        ..color = accent.withValues(alpha: 0.35)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var y = 6.0; y < size.height; y += 16) {
        canvas.drawLine(Offset(mid, y), Offset(mid, y + 8), paint);
      }
    }
    if (frame.value case final f?) _paintSelection(canvas, f);
    if (selectionBox.value case final box?) _paintSelectionBox(canvas, box);
    final at = eraserCursor.value;
    if (at == null || settings.brush != BrushType.eraser) return;
    final r = eraserRadius(settings);
    for (final c in [at, if (settings.mirror) Offset(2 * mid - at.dx, at.dy)]) {
      // A white ring outside a dark ring stays visible on any paper or ink.
      canvas
        ..drawCircle(c, r, Paint()..color = accent.withValues(alpha: 0.12))
        ..drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = Colors.white.withValues(alpha: 0.9),
        )
        ..drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = ink,
        );
    }
  }

  @override
  bool shouldRepaint(CanvasOverlayPainter old) =>
      old.accent != accent || old.ink != ink;

  /// A dashed rounded box around the selection, with corner dots, a resize
  /// handle at the bottom right and a turn knob above.
  void _paintSelection(Canvas canvas, SelectionFrame f) {
    final dash = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // The handles keep their size while the box is resized.
    final scale = f.transform.scale;
    canvas
      ..save()
      ..transform(f.transform.matrix4);
    final box = RRect.fromRectAndRadius(f.box, const Radius.circular(12));
    canvas.drawRRect(box, Paint()..color = accent.withValues(alpha: 0.06));
    for (final metric in (Path()..addRRect(box)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 12) {
        canvas.drawPath(metric.extractPath(d, d + 7), dash..strokeWidth = 2 / scale);
      }
    }
    final r = f.box;
    final knob = r.topCenter - const Offset(0, SelectionFrameHandles.rotateHandleGap);
    canvas.drawLine(r.topCenter, knob, dash..strokeWidth = 2 / scale);
    for (final c in [r.topLeft, r.topRight, r.bottomLeft]) {
      canvas
        ..drawCircle(c, 6 / scale, Paint()..color = Colors.white)
        ..drawCircle(c, 4.5 / scale, Paint()..color = accent);
    }
    canvas.restore();
    _paintHandle(canvas, f.scaleHandle, Icons.open_in_full_rounded);
    _paintHandle(canvas, f.rotateHandle, Icons.rotate_right_rounded);
  }

  /// A round accent knob with a white icon on it.
  void _paintHandle(Canvas canvas, Offset at, IconData icon) {
    canvas
      ..drawCircle(at, 17, Paint()..color = Colors.white)
      ..drawCircle(at, 15, Paint()..color = accent);
    final glyph = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 18,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph.paint(canvas, at - Offset(glyph.width / 2, glyph.height / 2));
    glyph.dispose();
  }

  /// The see-through box dragged out over empty paper.
  void _paintSelectionBox(Canvas canvas, Rect box) {
    canvas
      ..drawRect(box, Paint()..color = accent.withValues(alpha: 0.10))
      ..drawRect(
        box,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
  }
}

/// The button that brings out the tools drawer. It shows the current brush
/// and color, so it's obvious what it opens and what's selected.
class _ToolsLauncher extends StatelessWidget {
  const _ToolsLauncher({
    super.key,
    required this.settings,
    required this.fromLeft,
    required this.hide,
    required this.onTap,
  });

  final AppSettings settings;

  /// The drawer opens from the left: the arrow points that way.
  final bool fromLeft;

  /// The drawer's slide animation: the button fades out as it comes in.
  final Animation<double> hide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final brush = settings.brush;
    final accent = AppTheme.brushColor(brush);
    return AnimatedBuilder(
      animation: hide,
      builder: (context, child) => IgnorePointer(
        ignoring: hide.value > 0,
        child: Opacity(
          opacity: 1 - hide.value,
          child: Transform.scale(scale: 1 - 0.3 * hide.value, child: child),
        ),
      ),
      // excludeSemantics drops the InkWell's own tap action, so the action is
      // given here; otherwise screen readers can't activate the button.
      child: Semantics(
        button: true,
        label: s.openTools,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: scheme.surface,
          elevation: 8,
          shadowColor: cute.spec.primary.withValues(alpha: 0.4),
          shape: StadiumBorder(
            side: BorderSide(
              color: cute.spec.primary.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: accent,
                    child: Icon(
                      AppTheme.brushIcon(brush),
                      color: cute.onColor(accent),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (brush.usesColor) ...[
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: settings.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    s.toolsButton,
                    style: TextStyle(
                      color: cute.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  // Points to where the drawer will come from.
                  Icon(
                    fromLeft
                        ? Icons.chevron_right_rounded
                        : Icons.chevron_left_rounded,
                    color: cute.ink,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Undo and redo, floating at the top left of the paper.
/// Fades away while the tools drawer is open, like the tools button.
class _UndoRedoBar extends StatelessWidget {
  const _UndoRedoBar({required this.drawing, required this.hide});

  final DrawingController drawing;
  final Animation<double> hide;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    return AnimatedBuilder(
      animation: hide,
      builder: (context, child) => IgnorePointer(
        ignoring: hide.value > 0,
        child: Opacity(opacity: 1 - hide.value, child: child),
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 8,
        shadowColor: cute.spec.primary.withValues(alpha: 0.4),
        shape: StadiumBorder(
          side: BorderSide(
            color: cute.spec.primary.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: ListenableBuilder(
          listenable: drawing,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: s.undo,
                icon: const Icon(Icons.undo_rounded),
                color: cute.ink,
                onPressed: drawing.canUndo ? drawing.undo : null,
              ),
              IconButton(
                tooltip: s.redo,
                icon: const Icon(Icons.redo_rounded),
                color: cute.ink,
                onPressed: drawing.canRedo ? drawing.redo : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the zoom level while the paper is zoomed or moved; tap to fit the
/// whole paper back on screen.
class _ZoomChip extends StatelessWidget {
  const _ZoomChip({required this.view, required this.onReset});

  final ValueListenable<Matrix4> view;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    return ValueListenableBuilder(
      valueListenable: view,
      builder: (context, matrix, _) {
        final zoom = CanvasPageState.zoomLevel(matrix);
        final moved = matrix.getTranslation().length > 1;
        final show = (zoom - 1).abs() > 0.01 || moved;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: !show
              ? const SizedBox.shrink()
              : ActionChip(
                  key: const ValueKey('zoomChip'),
                  avatar: Icon(
                    Icons.fit_screen_rounded,
                    color: cute.ink,
                    size: 18,
                  ),
                  label: Text('${(zoom * 100).round()}% · ${s.fitScreen}'),
                  labelStyle: TextStyle(
                    color: cute.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  elevation: 4,
                  onPressed: onReset,
                ),
        );
      },
    );
  }
}

/// The tools drawer that slides in from the side the tools button is on.
class _ToolDrawer extends StatelessWidget {
  const _ToolDrawer({
    required this.settings,
    required this.palette,
    required this.fromLeft,
    required this.onClose,
    required this.onMoreColors,
    required this.onDrag,
    required this.onDragEnd,
  });

  final AppSettings settings;
  final List<Color> palette;
  final bool fromLeft;
  final VoidCallback onClose;
  final VoidCallback onMoreColors;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    return Material(
      elevation: 16,
      shadowColor: cute.spec.primary.withValues(alpha: 0.4),
      color: Theme.of(context).colorScheme.surface,
      // Rounded on the side facing the paper.
      shape: RoundedRectangleBorder(
        borderRadius: fromLeft
            ? BorderRadius.horizontal(right: Radius.circular(cute.radius))
            : BorderRadius.horizontal(left: Radius.circular(cute.radius)),
      ),
      child: SafeArea(
        left: fromLeft,
        right: !fromLeft,
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => onDrag(d.primaryDelta ?? 0),
              onHorizontalDragEnd: (d) => onDragEnd(d.primaryVelocity ?? 0),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                child: Row(
                  children: [
                    Icon(Icons.palette_rounded, color: cute.spec.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.toolsTitle,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: s.closeTools,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _ToolPanel(
                settings: settings,
                palette: palette,
                onMoreColors: onMoreColors,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brushes, colors, shapes, stamp shapes, size and opacity, as wrapped
/// groups in a scrolling column inside the tools drawer.
class _ToolPanel extends StatelessWidget {
  const _ToolPanel({
    required this.settings,
    required this.palette,
    required this.onMoreColors,
  });

  final AppSettings settings;
  final List<Color> palette;
  final VoidCallback onMoreColors;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    final brush = settings.brush;
    final accent = AppTheme.brushColor(brush);
    final custom = [
      for (final c in settings.customColors)
        if (!palette.any((p) => p.toARGB32() == c.toARGB32())) c,
    ];
    Widget wrap(List<Widget> items) =>
        Wrap(spacing: 0, runSpacing: 6, children: items);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(
        text,
        style: TextStyle(
          color: cute.ink,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );

    return ListView(
      key: CanvasPageState.toolsListKey,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      children: [
        wrap([
          for (final b in BrushType.values)
            _BrushTile(
              brush: b,
              label: s.brushName(b),
              selected: brush == b,
              onTap: () => settings.brush = b,
            ),
        ]),
        // Only the options that apply: the eraser, rainbow and move tools
        // ignore colors; the eraser, text and move tools draw no shapes.
        if (brush.usesColor) ...[
          heading(s.colors),
          wrap([
            _MoreColorsButton(tooltip: s.moreColors, onTap: onMoreColors),
            for (final c in [...custom, ...palette])
              _Swatch(
                color: c,
                label: s.colorLabel(c),
                selected: c.toARGB32() == settings.color.toARGB32(),
                onTap: () => settings.color = c,
              ),
          ]),
        ],
        if (switch (brush) {
              BrushType.text => s.textHint,
              BrushType.move => s.moveHint,
              BrushType.eraser => s.eraserHint,
              _ => null,
            }
            case final hint?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const SizedBox(width: 4),
                Icon(Icons.touch_app_rounded, color: accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hint,
                    style: TextStyle(color: cute.ink, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        if (brush.usesShapes) ...[
          heading(s.shapes),
          wrap([
            for (final shape in [null, ...ShapeKind.values])
              _ToolChip(
                icon: AppTheme.shapeIcon(shape),
                label: s.shapeName(shape),
                selected: settings.shape == shape,
                onTap: () => settings.shape = shape,
              ),
            _ToolChip(
              icon: Icons.format_color_fill_rounded,
              label: s.fillShape,
              selected: settings.fill,
              // Only closed shapes can be filled.
              enabled: settings.shape?.closed ?? false,
              onTap: () => settings.fill = !settings.fill,
            ),
          ]),
        ],
        if (brush == BrushType.stamp) ...[
          heading(s.brushName(BrushType.stamp)),
          wrap([
            for (final shape in StampShape.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(
                    AppTheme.stampIcon(shape),
                    size: 18,
                    color: settings.stamp == shape
                        ? cute.onColor(accent)
                        : accent,
                  ),
                  label: Text(s.stampName(shape)),
                  selected: settings.stamp == shape,
                  showCheckmark: false,
                  selectedColor: accent,
                  labelStyle: TextStyle(
                    color: settings.stamp == shape
                        ? cute.onColor(accent)
                        : cute.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => settings.stamp = shape,
                ),
              ),
          ]),
        ],
        // Size and opacity mean nothing to the move tool.
        if (brush != BrushType.move) ...[
          const Divider(height: 28),
          Row(
            children: [
              _SliderLabel(
                icon: Icons.line_weight_rounded,
                tooltip: s.brushSize,
                color: accent,
              ),
              Expanded(
                child: Slider(
                  min: 1,
                  max: 60,
                  divisions: 59,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  value: settings.size.clamp(1, 60),
                  label: settings.size.round().toString(),
                  semanticFormatterCallback: (v) =>
                      '${s.brushSize} ${v.round()}',
                  activeColor: accent,
                  onChanged: (v) => settings.size = v,
                ),
              ),
              _SizePreview(settings: settings),
            ],
          ),
          Row(
            children: [
              _SliderLabel(
                icon: Icons.opacity_rounded,
                tooltip: s.opacity,
                color: accent,
              ),
              Expanded(
                child: Slider(
                  min: AppSettings.minOpacity,
                  max: 1,
                  divisions: 19,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  value: settings.opacity,
                  label: s.percent(settings.opacity),
                  semanticFormatterCallback: (v) =>
                      '${s.opacity} ${s.percent(v)}',
                  activeColor: accent,
                  onChanged: (v) => settings.opacity = v,
                ),
              ),
            ],
          ),
        ],
        const Divider(height: 28),
        Row(
          children: [
            const SizedBox(width: 4),
            Icon(Icons.pinch_rounded, color: cute.spec.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.pinchHint,
                style: TextStyle(color: cute.ink, fontSize: 13),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A shape or option chip. Colors come from the theme's contrast-checked
/// primary pair.
class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cute = CuteTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : cute.ink;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        avatar: Icon(icon, size: 18, color: fg),
        label: Text(label),
        selected: selected && enabled,
        showCheckmark: false,
        selectedColor: scheme.primary,
        backgroundColor: scheme.surface,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
        labelStyle: TextStyle(color: fg, fontWeight: FontWeight.w600),
        onSelected: enabled ? (_) => onTap() : null,
      ),
    );
  }
}

class _SliderLabel extends StatelessWidget {
  const _SliderLabel({
    required this.icon,
    required this.tooltip,
    required this.color,
  });

  final IconData icon;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Tooltip(
      message: tooltip,
      child: Icon(icon, color: color, size: 22),
    ),
  );
}

/// A large, round, colorful brush button with its name underneath.
class _BrushTile extends StatelessWidget {
  const _BrushTile({
    required this.brush,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final BrushType brush;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cute = CuteTheme.of(context);
    final accent = AppTheme.brushColor(brush);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 62,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  // No overshooting curves here: going past 1.0 makes the
                  // fading shadow's blur radius negative, which crashes.
                  curve: Curves.easeOut,
                  width: selected ? 56 : 52,
                  height: selected ? 56 : 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: selected
                        ? LinearGradient(
                            colors: [
                              accent,
                              Color.lerp(accent, Colors.white, 0.18)!,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: selected
                        ? null
                        : accent.withValues(alpha: AppTheme.brushTintAlpha),
                    border: Border.all(
                      color: selected
                          ? Colors.white
                          : accent.withValues(alpha: 0.25),
                      width: selected ? 3 : 1.5,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    AppTheme.brushIcon(brush),
                    size: 28,
                    color: selected ? cute.onColor(accent) : accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: cute.ink,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round color. The visible dot is small but the tap area is 48x48.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: selected ? 38 : 32,
              height: selected ? 38 : 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? ring : Colors.black26,
                  width: selected ? 3 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: ring.withValues(alpha: 0.35),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rainbow button that opens the full color picker.
class _MoreColorsButton extends StatelessWidget {
  const _MoreColorsButton({required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Color(0xFFFF5A5F),
                    Color(0xFFFFD23F),
                    Color(0xFF3DDC97),
                    Color(0xFF3DA9FC),
                    Color(0xFF7F5AF0),
                    Color(0xFFFF5A5F),
                  ],
                ),
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                // Black on the light rainbow keeps the icon visible (3:1+).
                child: Icon(
                  Icons.palette_rounded,
                  color: Colors.black87,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperChoice extends StatelessWidget {
  const _PaperChoice({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? primary : Colors.black26,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, color: primary)
                    : null,
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows how big, what color and how see-through the next stroke will be.
class _SizePreview extends StatelessWidget {
  const _SizePreview({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final brush = settings.brush;
    final d = (settings.size * brush.sizeFactor).clamp(4, 36).toDouble();
    final Color fill = switch (brush) {
      BrushType.eraser => Colors.white,
      BrushType.rainbow => Colors.white,
      _ => settings.color,
    };
    return SizedBox(
      width: 44,
      height: 48,
      child: Center(
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            color: fill.withValues(alpha: settings.opacity * brush.opacity),
            gradient: brush == BrushType.rainbow
                ? SweepGradient(
                    colors: [
                      for (var h = 0; h <= 360; h += 60)
                        HSVColor.fromAHSV(
                          settings.opacity,
                          h % 360,
                          0.6,
                          0.97,
                        ).toColor(),
                    ],
                  )
                : null,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26),
          ),
        ),
      ),
    );
  }
}

enum _MoveMode { drag, scale, rotate, box }

/// One touch of the move tool.
class _MoveGesture {
  _MoveGesture(this.mode, this.originals, this.down, this.frame);

  final _MoveMode mode;

  /// The strokes as they were when the finger went down.
  final List<Stroke> originals;
  final Offset down;

  /// The selection's box when the finger went down; resizing and turning
  /// happen around its middle.
  final Rect frame;

  /// The moved strokes now on the paper, after the first step.
  List<Stroke>? current;
}

/// The move tool's buttons for the selected strokes: how many are selected,
/// then copy, bigger, smaller, turn, color and delete.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selected,
    required this.hide,
    required this.actions,
  });

  final ValueListenable<List<Stroke>> selected;

  /// Fades away while the tools drawer is open.
  final Animation<double> hide;
  final List<(IconData, String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    return ValueListenableBuilder(
      valueListenable: selected,
      builder: (context, sel, _) {
        if (sel.isEmpty) return const SizedBox.shrink();
        return AnimatedBuilder(
          animation: hide,
          builder: (context, child) => IgnorePointer(
            ignoring: hide.value > 0,
            child: Opacity(opacity: 1 - hide.value, child: child),
          ),
          child: Material(
            key: CanvasPageState.selectionBarKey,
            color: Theme.of(context).colorScheme.surface,
            elevation: 6,
            shadowColor: cute.spec.primary.withValues(alpha: 0.4),
            shape: StadiumBorder(
              side: BorderSide(
                color: cute.spec.primary.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            // Scrolls sideways on narrow phones instead of shrinking the
            // buttons below their 48px tap size.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      s.selectedCount(sel.length),
                      style: TextStyle(
                        color: cute.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  for (final (icon, label, onTap) in actions)
                    IconButton(
                      tooltip: label,
                      icon: Icon(icon),
                      color: cute.ink,
                      onPressed: onTap,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A sheet that recolors the selection and sets how see-through it is.
class _SelectionStyleSheet extends StatefulWidget {
  const _SelectionStyleSheet({
    required this.palette,
    required this.customColors,
    required this.color,
    required this.opacity,
    required this.onColor,
    required this.onMoreColors,
    required this.onOpacity,
  });

  final List<Color> palette;
  final List<Color> customColors;
  final Color color;
  final double opacity;
  final ValueChanged<Color> onColor;

  /// Opens the full picker; returns the color used, or null.
  final Future<Color?> Function() onMoreColors;
  final void Function(double opacity, {required bool recordUndo}) onOpacity;

  @override
  State<_SelectionStyleSheet> createState() => _SelectionStyleSheetState();
}

class _SelectionStyleSheetState extends State<_SelectionStyleSheet> {
  late Color _color = widget.color;
  late double _opacity = widget.opacity;

  /// One slider drag is one undo step.
  bool _dragging = false;
  bool _recorded = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final colors = [
      for (final c in widget.customColors)
        if (!widget.palette.any((p) => p.toARGB32() == c.toARGB32())) c,
      ...widget.palette,
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.colorAndOpacity,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              children: [
                _MoreColorsButton(
                  tooltip: s.moreColors,
                  onTap: () async {
                    final c = await widget.onMoreColors();
                    if (c != null && mounted) setState(() => _color = c);
                  },
                ),
                for (final c in colors)
                  _Swatch(
                    color: c,
                    label: s.colorLabel(c),
                    selected: c.toARGB32() == _color.toARGB32(),
                    onTap: () {
                      setState(() => _color = c);
                      widget.onColor(c);
                    },
                  ),
              ],
            ),
            Row(
              children: [
                _SliderLabel(
                  icon: Icons.opacity_rounded,
                  tooltip: s.opacity,
                  color: accent,
                ),
                Expanded(
                  child: Slider(
                    min: AppSettings.minOpacity,
                    max: 1,
                    divisions: 19,
                    value: _opacity.clamp(AppSettings.minOpacity, 1),
                    label: s.percent(_opacity),
                    semanticFormatterCallback: (v) =>
                        '${s.opacity} ${s.percent(v)}',
                    activeColor: accent,
                    onChangeStart: (_) {
                      _dragging = true;
                      _recorded = false;
                    },
                    onChanged: (v) {
                      setState(() => _opacity = v);
                      widget.onOpacity(v, recordUndo: !_recorded);
                      if (_dragging) _recorded = true;
                    },
                    onChangeEnd: (_) => _dragging = false,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    s.percent(_opacity),
                    style: TextStyle(color: cute.ink),
                  ),
                ),
              ],
            ),
            Text(
              s.rainbowKeepsColors,
              style: TextStyle(color: cute.ink, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Puts the selection bar just below the selection, or above it when there
/// isn't room, keeping clear of the corner controls at the top and bottom.
class _NextToSelection extends SingleChildLayoutDelegate {
  _NextToSelection(this.anchor);

  /// The selection (with its handles) on screen.
  final Rect anchor;

  /// Room left for the corner controls (undo, tools button).
  static const reserve = 72.0;
  static const gap = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(
        math.max(0, constraints.maxWidth - 32),
        constraints.maxHeight,
      ));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (anchor.center.dx - child.width / 2)
        .clamp(16.0, math.max(16.0, size.width - 16 - child.width))
        .toDouble();
    final below = anchor.bottom + gap;
    final above = anchor.top - gap - child.height;
    final double y;
    if (below + child.height <= size.height - reserve) {
      y = below;
    } else if (above >= reserve) {
      y = above;
    } else {
      // A selection as big as the screen: the top, below the corners.
      y = math.min(reserve, math.max(0.0, size.height - child.height));
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_NextToSelection old) => old.anchor != anchor;
}
