import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// How a brush turns pointer points into paint.
enum BrushKind {
  /// A smooth filled outline (perfect_freehand).
  outline,

  /// A cloud of random dots, like an airbrush.
  spray,

  /// A line whose color cycles through the rainbow.
  rainbow,

  /// Little shapes stamped along the path.
  stamp,

  /// A block of formatted text placed on the paper.
  text,
}

/// The drawing tools, in toolbar order.
enum BrushType {
  pen(BrushKind.outline, thinning: 0.6, smoothing: 0.5, streamline: 0.5, sizeFactor: 1),
  pencil(BrushKind.outline, thinning: 0.3, smoothing: 0.3, streamline: 0.3, sizeFactor: 0.5, opacity: 0.85),
  marker(BrushKind.outline, smoothing: 0.6, streamline: 0.5, sizeFactor: 1.2),
  highlighter(BrushKind.outline, smoothing: 0.6, streamline: 0.6, sizeFactor: 2, opacity: 0.35),
  spray(BrushKind.spray, sizeFactor: 2.5),
  rainbow(BrushKind.rainbow, sizeFactor: 1),
  stamp(BrushKind.stamp, sizeFactor: 2.2),

  /// Not a brush but a tool: tap to add text. Its "size" is half the font
  /// size, so the shared size slider still makes sense.
  text(BrushKind.text, sizeFactor: 2),

  /// Not a brush but a tool: select one stroke and drag it somewhere else.
  /// It never creates strokes.
  move(BrushKind.outline, sizeFactor: 1),
  eraser(BrushKind.outline, sizeFactor: 2);

  const BrushType(
    this.kind, {
    this.thinning = 0,
    this.smoothing = 0.5,
    this.streamline = 0.5,
    required this.sizeFactor,
    this.opacity = 1,
  });

  final BrushKind kind;

  /// How much pressure changes the width (0 = constant width). Outline only.
  final double thinning;
  final double smoothing;
  final double streamline;

  /// Multiplies the slider size so every brush feels right at the same setting.
  final double sizeFactor;

  /// Built-in see-through-ness (a highlighter is always a bit transparent),
  /// multiplied with the user's opacity slider.
  final double opacity;

  /// Brushes that ignore the chosen color.
  bool get usesColor => this != eraser && this != rainbow && this != move;

  /// Tools that can draw shapes. The eraser is always a round tip; text and
  /// move don't draw at all.
  bool get usesShapes => this != eraser && this != text && this != move;

  static BrushType fromName(String? name) =>
      values.firstWhere((b) => b.name == name, orElse: () => pen);
}

enum StampShape {
  heart,
  star,
  flower;

  static StampShape fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => heart);
}

/// Geometric shapes drawn by dragging from one corner to the opposite one
/// (or from start to end, for lines and arrows).
enum ShapeKind {
  line,
  arrow,
  rectangle,
  ellipse,
  triangle,
  star,
  heart;

  /// Closed shapes can be filled.
  bool get closed => this != line && this != arrow;

  /// null means freehand drawing.
  static ShapeKind? fromName(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// The exact outline from [a] to [b]. [arrowHead] is the arrow head's
  /// length (scaled to the brush width by the caller).
  Path path(Offset a, Offset b, {double arrowHead = 16}) {
    final r = Rect.fromPoints(a, b);
    final path = Path();
    switch (this) {
      case ShapeKind.line:
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      case ShapeKind.arrow:
        // One continuous outline (shaft, then each side of the head), so
        // spray, rainbow and stamps can follow it without jumps.
        final back = (a - b).direction;
        final head = math.min(arrowHead, (b - a).distance * 0.45);
        final h1 = b + Offset.fromDirection(back + 0.45, head);
        final h2 = b + Offset.fromDirection(back - 0.45, head);
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(h1.dx, h1.dy)
          ..moveTo(b.dx, b.dy)
          ..lineTo(h2.dx, h2.dy);
      case ShapeKind.rectangle:
        path.addRect(r);
      case ShapeKind.ellipse:
        path.addOval(r);
      case ShapeKind.triangle:
        path
          ..moveTo(r.topCenter.dx, r.topCenter.dy)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..close();
      case ShapeKind.star:
        for (var i = 0; i < 10; i++) {
          final k = i.isEven ? 1.0 : 0.45;
          final angle = i * math.pi / 5 - math.pi / 2;
          final p = r.center +
              Offset(math.cos(angle) * r.width / 2 * k,
                  math.sin(angle) * r.height / 2 * k);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        path.close();
      case ShapeKind.heart:
        final x = r.left, y = r.top, w = r.width, h = r.height;
        path
          ..moveTo(x + w / 2, y + h * 0.25)
          ..cubicTo(x + w / 2, y, x, y, x, y + h * 0.3)
          ..cubicTo(x, y + h * 0.6, x + w / 2, y + h * 0.8, x + w / 2, y + h)
          ..cubicTo(x + w / 2, y + h * 0.8, x + w, y + h * 0.6, x + w, y + h * 0.3)
          ..cubicTo(x + w, y, x + w / 2, y, x + w / 2, y + h * 0.25)
          ..close();
    }
    return path;
  }
}

/// The words and formatting of a text item.
class TextContent {
  const TextContent({
    this.text = '',
    this.fontFamily,
    this.fontSize = 32,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.align = TextAlign.left,
    this.bubble = false,
  });

  final String text;

  /// A pubspec font family, or null for the app's current font.
  final String? fontFamily;
  final double fontSize;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;

  /// left, center or right: the anchor point is that edge of the text.
  final TextAlign align;

  /// Draws a soft rounded bubble behind the text.
  final bool bubble;

  /// Padding between the text and its bubble.
  static const bubblePadding = 10.0;

  TextStyle style(Color color) => TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.25,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (underline) TextDecoration.underline,
          if (strikethrough) TextDecoration.lineThrough,
        ]),
        decorationColor: color,
        decorationThickness: 2,
      );

  TextContent copyWith({
    String? text,
    String? Function()? fontFamily,
    double? fontSize,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    TextAlign? align,
    bool? bubble,
  }) =>
      TextContent(
        text: text ?? this.text,
        fontFamily: fontFamily == null ? this.fontFamily : fontFamily(),
        fontSize: fontSize ?? this.fontSize,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strikethrough: strikethrough ?? this.strikethrough,
        align: align ?? this.align,
        bubble: bubble ?? this.bubble,
      );

  Map<String, Object?> toJson() => {
        'text': text,
        if (fontFamily != null) 'fontFamily': fontFamily,
        'fontSize': fontSize,
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'strikethrough': strikethrough,
        'align': align.name,
        'bubble': bubble,
      };

  factory TextContent.fromJson(Map<String, Object?> json) => TextContent(
        text: json['text'] as String? ?? '',
        fontFamily: json['fontFamily'] as String?,
        fontSize: (json['fontSize'] as num? ?? 32).toDouble(),
        bold: json['bold'] as bool? ?? false,
        italic: json['italic'] as bool? ?? false,
        underline: json['underline'] as bool? ?? false,
        strikethrough: json['strikethrough'] as bool? ?? false,
        align: TextAlign.values.firstWhere((a) => a.name == json['align'],
            orElse: () => TextAlign.left),
        bubble: json['bubble'] as bool? ?? false,
      );
}

/// One continuous stroke made with a single brush.
class Stroke {
  Stroke({
    required this.brush,
    required this.color,
    required this.size,
    required this.usesRealPressure,
    this.opacity = 1,
    int? seed,
    this.stamp = StampShape.heart,
    this.mirrorX,
    this.shape,
    this.fill = false,
    this.text,
    List<PointVector>? points,
    this.isComplete = false,
  })  : seed = seed ?? math.Random().nextInt(1 << 30),
        points = points ?? [];

  /// A text item anchored at [anchor] (its left, center or right edge,
  /// depending on alignment, at the top of the text).
  factory Stroke.text({
    required Offset anchor,
    required TextContent content,
    required Color color,
    double opacity = 1,
  }) =>
      Stroke(
        brush: BrushType.text,
        color: color,
        size: content.fontSize / BrushType.text.sizeFactor,
        opacity: opacity,
        usesRealPressure: false,
        seed: 0,
        text: content,
        isComplete: true,
        points: [PointVector(anchor.dx, anchor.dy, 0.5)],
      );

  /// The same text moved so its anchor is at [anchor].
  Stroke movedTo(Offset anchor) => Stroke.text(
      anchor: anchor, content: text!, color: color, opacity: opacity);

  /// A copy of any stroke shifted by [delta]. Strokes are never changed in
  /// place (undo snapshots rely on that), so moving makes a new one. The
  /// seed is kept so spray and stamps look identical after the move, and a
  /// mirrored stroke's axis moves with it so the pair stays together.
  Stroke moved(Offset delta) {
    if (text != null) return movedTo(anchor + delta);
    final mirror = mirrorX == null ? null : mirrorX! + delta.dx;
    if (shape != null) {
      return Stroke.shape(
        shape: shape!,
        from: _from! + delta,
        to: _to! + delta,
        brush: brush,
        color: color,
        size: size,
        opacity: opacity,
        fill: fill,
        seed: seed,
        stamp: stamp,
        mirrorX: mirror,
        isComplete: true,
      );
    }
    return Stroke(
      brush: brush,
      color: color,
      size: size,
      opacity: opacity,
      usesRealPressure: usesRealPressure,
      seed: seed,
      stamp: stamp,
      mirrorX: mirror,
      isComplete: true,
      points: [
        for (final p in points)
          PointVector(p.x + delta.dx, p.y + delta.dy, p.pressure),
      ],
    );
  }

  /// Whether [p] is on this stroke: inside text or a filled shape, or within
  /// finger reach of its line (or of its mirror image).
  bool hits(Offset p, {double reach = 14}) {
    if (text != null) return textBounds.contains(p);
    if (!bounds.inflate(reach).contains(p)) return false;
    final candidates = [p, if (mirrorX case final m?) Offset(2 * m - p.dx, p.dy)];
    final tolerance = width / 2 + reach;
    for (final q in candidates) {
      if (fill && shape != null && _shapePath.contains(q)) return true;
      for (final pt in points) {
        if ((pt - q).distance <= tolerance) return true;
      }
    }
    return false;
  }

  /// Creates a shape stroke from [from] to [to]; its points are generated
  /// along the outline so every brush can draw it.
  factory Stroke.shape({
    required ShapeKind shape,
    required Offset from,
    required Offset to,
    required BrushType brush,
    required Color color,
    required double size,
    double opacity = 1,
    bool fill = false,
    int? seed,
    StampShape stamp = StampShape.heart,
    double? mirrorX,
    bool isComplete = false,
  }) =>
      Stroke(
        brush: brush,
        color: color,
        size: size,
        opacity: opacity,
        usesRealPressure: false,
        seed: seed,
        stamp: stamp,
        mirrorX: mirrorX,
        shape: shape,
        fill: fill && shape.closed,
        isComplete: isComplete,
      )..setShapeEnds(from, to);

  final BrushType brush;
  final Color color;

  /// The slider size when the stroke was drawn, before [BrushType.sizeFactor].
  final double size;

  /// The opacity slider, 0.05 to 1.
  final double opacity;

  /// Stylus input reports real pressure; finger input gets simulated pressure.
  final bool usesRealPressure;

  /// Seeds the spray dots and stamp wobble, so a saved stroke looks exactly
  /// the same every time it is drawn.
  final int seed;
  final StampShape stamp;

  /// When set, the stroke is also drawn mirrored across this vertical line.
  final double? mirrorX;

  /// Set for shape strokes; null for freehand.
  final ShapeKind? shape;

  /// Whether a closed shape is filled with the stroke's color.
  final bool fill;

  /// Set for text items; null otherwise.
  final TextContent? text;
  TextPainter? _textPainter;
  Offset? _from;
  Offset? _to;

  final List<PointVector> points;
  bool isComplete;

  Path? _cachedPath;
  final List<Offset> _sprayDots = [];
  int _sprayPointsDone = 0;

  double get width => size * brush.sizeFactor;

  Offset? get shapeFrom => _from;
  Offset? get shapeTo => _to;

  /// Moves a shape's corners and regenerates its points.
  void setShapeEnds(Offset from, Offset to) {
    assert(shape != null);
    _from = from;
    _to = to;
    points
      ..clear()
      ..addAll(_sampleOutline(_shapePath));
    _cachedPath = null;
    _sprayDots.clear();
    _sprayPointsDone = 0;
  }

  /// A shape smaller than this (a tap rather than a drag) is discarded.
  bool get isDegenerateShape =>
      shape != null && (_to! - _from!).distance < 3;

  Path get _shapePath =>
      shape!.path(_from!, _to!, arrowHead: math.max(14, width * 2.5));

  /// Points every ~3px along [path], for brushes that follow points.
  static List<PointVector> _sampleOutline(Path path) {
    final out = <PointVector>[];
    for (final metric in path.computeMetrics()) {
      final steps = math.max(1, (metric.length / 3).ceil());
      for (var i = 0; i <= steps; i++) {
        final t = metric.getTangentForOffset(metric.length * i / steps);
        if (t != null) out.add(PointVector(t.position.dx, t.position.dy, 0.5));
      }
    }
    return out;
  }

  /// Paints the stroke (and its mirror image) onto [canvas].
  void paint(Canvas canvas) {
    _paintOnce(canvas);
    if (mirrorX case final m?) {
      canvas
        ..save()
        ..translate(2 * m, 0)
        ..scale(-1, 1);
      _paintOnce(canvas);
      canvas.restore();
    }
  }

  Offset get anchor => points.first;

  TextPainter get _laidOutText => _textPainter ??= TextPainter(
        text: TextSpan(text: text!.text, style: text!.style(color.withValues(alpha: 1))),
        textAlign: text!.align,
        textDirection: TextDirection.ltr,
      )..layout();

  /// Where the text's top-left corner goes, given its alignment.
  Offset get _textTopLeft {
    final w = _laidOutText.width;
    return switch (text!.align) {
      TextAlign.center => anchor - Offset(w / 2, 0),
      TextAlign.right || TextAlign.end => anchor - Offset(w, 0),
      _ => anchor,
    };
  }

  /// The area a text item covers, including its bubble; used for tapping
  /// and dragging text.
  Rect get textBounds {
    final rect = _textTopLeft & _laidOutText.size;
    return rect.inflate(text!.bubble ? TextContent.bubblePadding : 4);
  }

  void _paintText(Canvas canvas) {
    final alpha = (color.a * opacity).clamp(0.0, 1.0);
    final bounds = textBounds;
    // Bubble and text fade together, so the bubble doesn't show through.
    final translucent = alpha < 1;
    if (translucent) {
      canvas.saveLayer(bounds.inflate(2), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    }
    if (text!.bubble) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(16)),
        Paint()..color = color.withValues(alpha: 0.16),
      );
    }
    _laidOutText.paint(canvas, _textTopLeft);
    if (translucent) canvas.restore();
  }

  void _paintOnce(Canvas canvas) {
    if (text != null) {
      _paintText(canvas);
      return;
    }
    if (shape != null) {
      _paintShape(canvas);
      return;
    }
    if (brush == BrushType.eraser) {
      // dstOut removes existing ink in proportion to alpha, so a
      // half-opacity eraser fades ink instead of removing it.
      canvas.drawPath(path, Paint()
        ..isAntiAlias = true
        ..blendMode = BlendMode.dstOut
        ..color = Color.fromRGBO(0, 0, 0, opacity));
      return;
    }
    final alpha = (color.a * opacity * brush.opacity).clamp(0.0, 1.0);
    if (brush.kind == BrushKind.outline) {
      // A single filled outline never overlaps itself, so a translucent
      // paint is enough.
      canvas.drawPath(path, Paint()
        ..isAntiAlias = true
        ..color = color.withValues(alpha: alpha));
      return;
    }
    // Dots, segments and stamps overlap each other. Draw them solid into a
    // layer and fade the whole layer, so overlaps don't get darker.
    final translucent = alpha < 1;
    if (translucent) {
      canvas.saveLayer(_bounds, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    }
    final solid = color.withValues(alpha: 1);
    switch (brush.kind) {
      case BrushKind.spray:
        _paintSpray(canvas, solid);
      case BrushKind.rainbow:
        _paintRainbow(canvas);
      case BrushKind.stamp:
        _paintStamps(canvas, solid);
      case BrushKind.outline || BrushKind.text:
        break;
    }
    if (translucent) canvas.restore();
  }

  void _paintShape(Canvas canvas) {
    final outline = _shapePath;
    final linePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (brush == BrushType.eraser) {
      // A filled eraser shape clears its whole area.
      final erase = Color.fromRGBO(0, 0, 0, opacity);
      if (fill) {
        canvas.drawPath(outline, Paint()
          ..blendMode = BlendMode.dstOut
          ..color = erase);
      }
      canvas.drawPath(outline, linePaint
        ..blendMode = BlendMode.dstOut
        ..color = erase);
      return;
    }
    // Fill and outline overlap, so fade them together in one layer.
    final alpha = (color.a * opacity * brush.opacity).clamp(0.0, 1.0);
    final translucent = alpha < 1;
    if (translucent) {
      canvas.saveLayer(_bounds, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    }
    final solid = color.withValues(alpha: 1);
    if (fill) {
      canvas.drawPath(outline, Paint()
        ..isAntiAlias = true
        ..color = brush == BrushType.rainbow ? _rainbowAt(0) : solid);
    }
    switch (brush.kind) {
      // Text never becomes a shape; treat it like a plain outline.
      case BrushKind.outline || BrushKind.text:
        // Exact geometry keeps corners crisp.
        canvas.drawPath(outline, linePaint..color = solid);
      case BrushKind.spray:
        _paintSpray(canvas, solid);
      case BrushKind.rainbow:
        _paintRainbow(canvas);
      case BrushKind.stamp:
        _paintStamps(canvas, solid);
    }
    if (translucent) canvas.restore();
  }

  Color _rainbowAt(double distance) => HSVColor.fromAHSV(
          1, ((seed % 360) + distance * 1.2) % 360, 0.6, 0.97)
      .toColor();

  /// The area this stroke paints on the paper, mirror image included.
  Rect get bounds {
    if (text != null) return textBounds;
    final r = _bounds;
    if (mirrorX case final m?) {
      return r.expandToInclude(
          Rect.fromLTRB(2 * m - r.right, r.top, 2 * m - r.left, r.bottom));
    }
    return r;
  }

  Rect get _bounds {
    if (points.isEmpty) return Rect.zero;
    var r = Rect.fromLTWH(points.first.x, points.first.y, 0, 0);
    for (final p in points) {
      r = r.expandToInclude(Rect.fromLTWH(p.x, p.y, 0, 0));
    }
    return r.inflate(width + 4);
  }

  Path get path {
    if (_cachedPath != null) return _cachedPath!;
    final outline = getStroke(
      points,
      options: StrokeOptions(
        size: width,
        thinning: brush.thinning,
        smoothing: brush.smoothing,
        streamline: brush.streamline,
        simulatePressure: !usesRealPressure && brush.thinning > 0,
        isComplete: isComplete,
      ),
    );
    final path = _outlineToPath(outline);
    // Only cache once the stroke is finished; in-progress strokes keep changing.
    if (isComplete) _cachedPath = path;
    return path;
  }

  static Path _outlineToPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    if (pts.length < 2) {
      return path..addOval(Rect.fromCircle(center: pts.first, radius: 1));
    }
    path.moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      path.quadraticBezierTo(
          p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    }
    return path..close();
  }

  void _paintSpray(Canvas canvas, Color solid) {
    final radius = math.max(2.0, width / 2);
    // Dots are generated once per new point and kept, so drawing stays fast
    // as the stroke grows. Each segment has its own seed, so the result never
    // depends on how many frames were painted.
    for (var i = _sprayPointsDone; i < points.length; i++) {
      final a = i == 0 ? points[0] : points[i - 1];
      final b = points[i];
      final rnd = math.Random(seed * 7919 + i);
      final steps =
          i == 0 ? 1 : math.max(1, ((b - a).distance / (radius * 0.5)).ceil());
      final perStep = (radius * radius / 10).clamp(6, 50).round();
      for (var s = 0; s < steps; s++) {
        final center = Offset.lerp(a, b, s / steps)!;
        for (var k = 0; k < perStep; k++) {
          final angle = rnd.nextDouble() * 2 * math.pi;
          final dist = radius * math.sqrt(rnd.nextDouble());
          _sprayDots.add(center + Offset(math.cos(angle), math.sin(angle)) * dist);
        }
      }
    }
    _sprayPointsDone = points.length;
    canvas.drawPoints(
      ui.PointMode.points,
      _sprayDots,
      Paint()
        ..color = solid
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.2, radius / 7),
    );
  }

  void _paintRainbow(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width;
    final hueAt = _rainbowAt;
    if (points.length == 1) {
      canvas.drawCircle(points.first, width / 2,
          paint..style = PaintingStyle.fill..color = hueAt(0));
      return;
    }
    var travelled = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      canvas.drawLine(a, b, paint..color = hueAt(travelled));
      travelled += (b - a).distance;
    }
  }

  void _paintStamps(Canvas canvas, Color solid) {
    final spacing = width * 1.3;
    final fill = Paint()
      ..isAntiAlias = true
      ..color = solid;
    final light = Paint()
      ..isAntiAlias = true
      ..color = Color.lerp(solid, Colors.white, 0.65)!;
    var index = 0;
    void place(Offset at) {
      final rnd = math.Random(seed + index++);
      final scale = width / 2 * (0.85 + rnd.nextDouble() * 0.3);
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate((rnd.nextDouble() - 0.5) * 0.8)
        ..scale(scale);
      for (final (path, isCenter) in _stampPaths[stamp]!) {
        canvas.drawPath(path, isCenter ? light : fill);
      }
      canvas.restore();
    }

    if (points.isEmpty) return;
    place(points.first);
    var untilNext = spacing;
    for (var i = 1; i < points.length; i++) {
      var a = points[i - 1] as Offset;
      final b = points[i] as Offset;
      var segment = (b - a).distance;
      while (segment >= untilNext) {
        a = Offset.lerp(a, b, untilNext / segment)!;
        place(a);
        segment = (b - a).distance;
        untilNext = spacing;
      }
      untilNext -= segment;
    }
  }

  /// Stamp shapes in a unit box centered on the origin. The bool marks a
  /// lighter center (the flower's middle).
  static final Map<StampShape, List<(Path, bool)>> _stampPaths = {
    StampShape.heart: [
      (
        Path()
          ..moveTo(0, 0.85)
          ..cubicTo(-1.3, 0, -0.85, -1.15, 0, -0.45)
          ..cubicTo(0.85, -1.15, 1.3, 0, 0, 0.85)
          ..close(),
        false,
      ),
    ],
    StampShape.star: [(_star(), false)],
    StampShape.flower: [
      for (var i = 0; i < 5; i++)
        (
          Path()
            ..addOval(Rect.fromCircle(
              center: Offset.fromDirection(i * 2 * math.pi / 5 - math.pi / 2, 0.52),
              radius: 0.42,
            )),
          false,
        ),
      (Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 0.3)), true),
    ],
  };

  static Path _star() {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? 1.0 : 0.45;
      final p = Offset.fromDirection(i * math.pi / 5 - math.pi / 2, r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  /// Points are stored as a flat [x, y, pressure, x, y, pressure, ...] list,
  /// rounded to keep saved files small.
  Map<String, Object?> toJson() => {
        'brush': brush.name,
        'color': color.toARGB32(),
        'size': size,
        'opacity': opacity,
        'realPressure': usesRealPressure,
        'seed': seed,
        if (brush == BrushType.stamp) 'stamp': stamp.name,
        if (mirrorX != null) 'mirrorX': _round(mirrorX!, 10),
        if (text != null) 'text': text!.toJson(),
        // Shapes are stored by their two corners and rebuilt on load.
        if (shape != null) ...{
          'shape': shape!.name,
          'fill': fill,
          'from': [_round(_from!.dx, 10), _round(_from!.dy, 10)],
          'to': [_round(_to!.dx, 10), _round(_to!.dy, 10)],
          'points': const <num>[],
        } else
          'points': [
            for (final p in points) ...[
              _round(p.x, 10),
              _round(p.y, 10),
              _round(p.pressure ?? 0.5, 100),
            ],
          ],
      };

  factory Stroke.fromJson(Map<String, Object?> json) {
    if (json['text'] case final Map<String, Object?> text) {
      final p = (json['points'] as List).cast<num>();
      return Stroke.text(
        anchor: Offset(p[0].toDouble(), p[1].toDouble()),
        content: TextContent.fromJson(text),
        color: Color(json['color'] as int),
        opacity: (json['opacity'] as num? ?? 1).toDouble(),
      );
    }
    final shape = ShapeKind.fromName(json['shape'] as String?);
    if (shape != null) {
      Offset offset(String key) {
        final v = (json[key] as List).cast<num>();
        return Offset(v[0].toDouble(), v[1].toDouble());
      }

      return Stroke.shape(
        shape: shape,
        from: offset('from'),
        to: offset('to'),
        brush: BrushType.fromName(json['brush'] as String?),
        color: Color(json['color'] as int),
        size: (json['size'] as num).toDouble(),
        opacity: (json['opacity'] as num? ?? 1).toDouble(),
        fill: json['fill'] as bool? ?? false,
        seed: json['seed'] as int? ?? 0,
        stamp: StampShape.fromName(json['stamp'] as String?),
        mirrorX: (json['mirrorX'] as num?)?.toDouble(),
        isComplete: true,
      );
    }
    final flat = (json['points'] as List).cast<num>();
    return Stroke(
      brush: BrushType.fromName(json['brush'] as String?),
      color: Color(json['color'] as int),
      size: (json['size'] as num).toDouble(),
      // Paintings saved before v1.2 have no opacity, seed, stamp or mirror.
      opacity: (json['opacity'] as num? ?? 1).toDouble(),
      usesRealPressure: json['realPressure'] as bool? ?? false,
      seed: json['seed'] as int? ?? 0,
      stamp: StampShape.fromName(json['stamp'] as String?),
      mirrorX: (json['mirrorX'] as num?)?.toDouble(),
      isComplete: true,
      points: [
        for (var i = 0; i + 2 < flat.length; i += 3)
          PointVector(flat[i].toDouble(), flat[i + 1].toDouble(),
              flat[i + 2].toDouble()),
      ],
    );
  }

  static double _round(double v, int scale) => (v * scale).round() / scale;
}
