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
      // Touching a stroke selects it; touching the current selection keeps
      // it (so a big stroke can be grabbed anywhere in its box); touching
      // empty paper clears the selection.
      final current = selected.value;
      final hit =
          _drawing.hitStroke(e.localPosition) ??
          (current != null &&
                  _drawing.strokes.contains(current) &&
                  current.bounds.inflate(8).contains(e.localPosition)
              ? current
              : null);
      selected.value = hit;
      _moveGesture = hit == null
          ? null
          : (stroke: hit, down: e.localPosition, dragged: null);
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
      _dragSelected(e.localPosition);
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
      _moveGesture = null;
      return;
    }
    _drawing.end();
  }

  /// The move tool's current touch: the stroke being moved, where the finger
  /// went down, and the moved copy while dragging.
  ({Stroke stroke, Offset down, Stroke? dragged})? _moveGesture;

  /// The stroke the move tool has selected, outlined on the paper.
  final selected = ValueNotifier<Stroke?>(null);

  void _dragSelected(Offset at) {
    final g = _moveGesture;
    if (g == null) return;
    final delta = at - g.down;
    if (g.dragged == null && delta.distance < _dragSlop) return;
    final moved = g.stroke.moved(delta);
    // Only the first step records undo, so a whole drag undoes at once.
    _drawing.replace(
      g.dragged ?? g.stroke,
      moved,
      recordUndo: g.dragged == null,
    );
    _moveGesture = (stroke: g.stroke, down: g.down, dragged: moved);
    selected.value = moved;
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
    if (_settings.brush != BrushType.move) {
      selected.value = null;
    } else if (!_drawing.strokes.contains(selected.value)) {
      selected.value = _drawing.strokes.lastOrNull;
    }
  }

  /// Undo can remove the selected stroke; then nothing is selected.
  void _onDrawingChanged() {
    final s = selected.value;
    if (s != null && !_drawing.strokes.contains(s)) selected.value = null;
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
    final moved = hit.movedTo(hit.anchor + delta);
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
    final s = S.of(context);
    var picked = _settings.color;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.pickColor),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _settings.color,
            onColorChanged: (c) => picked = c,
            // Transparency has its own slider in the tool panel.
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
    if (ok == true) {
      _settings
        ..color = picked
        ..addCustomColor(picked);
    }
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
                        child: CustomPaint(
                          key: paperKey,
                          painter: _CanvasPainter(_drawing),
                          foregroundPainter: CanvasOverlayPainter(
                            settings: _settings,
                            eraserCursor: _eraserCursor,
                            selected: selected,
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

/// Guides drawn over the paper that are not part of the picture: the dashed
/// mirror axis and the eraser's range circle.
class CanvasOverlayPainter extends CustomPainter {
  CanvasOverlayPainter({
    required this.settings,
    required this.eraserCursor,
    required this.selected,
    required this.accent,
    required this.ink,
  }) : super(repaint: Listenable.merge([settings, eraserCursor, selected]));

  final AppSettings settings;
  final ValueListenable<Offset?> eraserCursor;

  /// The move tool's selection, outlined with a dashed box.
  final ValueListenable<Stroke?> selected;
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
    if (selected.value case final s?) _paintSelection(canvas, s.bounds);
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

  /// A dashed rounded box with corner dots around the selected stroke.
  void _paintSelection(Canvas canvas, Rect bounds) {
    final box = RRect.fromRectAndRadius(
      bounds.inflate(10),
      const Radius.circular(12),
    );
    canvas.drawRRect(box, Paint()..color = accent.withValues(alpha: 0.06));
    final dash = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in (Path()..addRRect(box)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 12) {
        canvas.drawPath(metric.extractPath(d, d + 7), dash);
      }
    }
    final r = box.outerRect;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas
        ..drawCircle(c, 6, Paint()..color = Colors.white)
        ..drawCircle(c, 4.5, Paint()..color = accent);
    }
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
