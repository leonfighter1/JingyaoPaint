import 'dart:math' as math;
import 'dart:typed_data';
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

/// A 2D move, turn and resize applied to a finished stroke when it's
/// painted: `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty`.
///
/// Transforming the canvas (instead of the stroke's points) keeps every
/// brush exact: filled shapes stay crisp, spray and stamps keep their look,
/// and a mirrored pair turns as one piece.
@immutable
class StrokeTransform {
  const StrokeTransform(this.a, this.b, this.c, this.d, this.tx, this.ty);

  /// Scales by [scale] and turns by [angle] (radians, clockwise on screen)
  /// around [center].
  factory StrokeTransform.around(Offset center,
      {double scale = 1, double angle = 0}) {
    final a = scale * math.cos(angle), b = scale * math.sin(angle);
    return StrokeTransform(a, b, -b, a, center.dx - a * center.dx + b * center.dy,
        center.dy - b * center.dx - a * center.dy);
  }

  factory StrokeTransform.translation(Offset delta) =>
      StrokeTransform(1, 0, 0, 1, delta.dx, delta.dy);

  final double a, b, c, d, tx, ty;

  /// How much bigger than the original it is drawn.
  double get scale => math.sqrt(a * a + b * b);

  /// How far it is turned, in radians.
  double get angle => math.atan2(b, a);

  Offset apply(Offset p) =>
      Offset(a * p.dx + c * p.dy + tx, b * p.dx + d * p.dy + ty);

  /// This transform followed by [next].
  StrokeTransform then(StrokeTransform next) => StrokeTransform(
        next.a * a + next.c * b,
        next.b * a + next.d * b,
        next.a * c + next.c * d,
        next.b * c + next.d * d,
        next.a * tx + next.c * ty + next.tx,
        next.b * tx + next.d * ty + next.ty,
      );

  StrokeTransform get inverse {
    final det = a * d - b * c;
    final ia = d / det, ib = -b / det, ic = -c / det, id = a / det;
    return StrokeTransform(
        ia, ib, ic, id, -(ia * tx + ic * ty), -(ib * tx + id * ty));
  }

  /// The upright box around [r] once transformed.
  Rect applyRect(Rect r) {
    final corners = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]
        .map(apply)
        .toList();
    var out = Rect.fromPoints(corners[0], corners[0]);
    for (final p in corners.skip(1)) {
      out = out.expandToInclude(Rect.fromPoints(p, p));
    }
    return out;
  }

  /// Column-major 4x4 matrix for [Canvas.transform].
  Float64List get matrix4 => Float64List.fromList(
      [a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]);

  List<double> toJson() => [
        for (final v in [a, b, c, d]) (v * 10000).round() / 10000,
        for (final v in [tx, ty]) (v * 10).round() / 10,
      ];

  static StrokeTransform? fromJson(Object? json) {
    if (json is! List || json.length != 6) return null;
    final v = [for (final n in json.cast<num>()) n.toDouble()];
    return StrokeTransform(v[0], v[1], v[2], v[3], v[4], v[5]);
  }

  @override
  bool operator ==(Object other) =>
      other is StrokeTransform &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.tx == tx &&
      other.ty == ty;

  @override
  int get hashCode => Object.hash(a, b, c, d, tx, ty);
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
    this.transform,
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
    StrokeTransform? transform,
  }) =>
      Stroke(
        brush: BrushType.text,
        color: color,
        size: content.fontSize / BrushType.text.sizeFactor,
        opacity: opacity,
        usesRealPressure: false,
        seed: 0,
        text: content,
        transform: transform,
        isComplete: true,
        points: [PointVector(anchor.dx, anchor.dy, 0.5)],
      );

  /// A copy of any stroke shifted by [delta]. Strokes are never changed in
  /// place (undo snapshots rely on that), so moving makes a new one. The
  /// seed is kept so spray and stamps look identical after the move, and a
  /// mirrored stroke's axis moves with it so the pair stays together.
  Stroke moved(Offset delta) {
    // A turned or resized stroke moves by adding to its transform.
    if (transform != null) {
      return transformed(StrokeTransform.translation(delta));
    }
    if (text != null) {
      return Stroke.text(
          anchor: anchor + delta, content: text!, color: color, opacity: opacity);
    }
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

  /// A copy turned and/or resized by [t], on top of any earlier transform.
  Stroke transformed(StrokeTransform t) =>
      copyWith(transform: () => (transform ?? _identity).then(t));

  static const _identity = StrokeTransform(1, 0, 0, 1, 0, 0);

  /// A copy with a new color, opacity or transform. Everything else,
  /// including the seed, stays the same.
  Stroke copyWith({
    Color? color,
    double? opacity,
    StrokeTransform? Function()? transform,
  }) {
    final c = color ?? this.color;
    final o = opacity ?? this.opacity;
    final t = transform == null ? this.transform : transform();
    if (text != null) {
      return Stroke.text(
          anchor: anchor, content: text!, color: c, opacity: o, transform: t);
    }
    if (shape != null) {
      return Stroke.shape(
        shape: shape!,
        from: _from!,
        to: _to!,
        brush: brush,
        color: c,
        size: size,
        opacity: o,
        fill: fill,
        seed: seed,
        stamp: stamp,
        mirrorX: mirrorX,
        transform: t,
        isComplete: true,
      );
    }
    return Stroke(
      brush: brush,
      color: c,
      size: size,
      opacity: o,
      usesRealPressure: usesRealPressure,
      seed: seed,
      stamp: stamp,
      mirrorX: mirrorX,
      transform: t,
      isComplete: true,
      points: List.of(points),
    );
  }

  /// Whether [p] is on this stroke: inside text or a filled shape, or within
  /// finger reach of its line (or of its mirror image).
  bool hits(Offset p, {double reach = 14}) {
    if (transform case final t?) {
      // Test in the stroke's own coordinates.
      p = t.inverse.apply(p);
      reach /= t.scale;
    }
    if (text != null) return textBounds.contains(p);
    if (!_localBounds.inflate(reach).contains(p)) return false;
    final candidates = [p, if (mirrorX case final m?) Offset(2 * m - p.dx, p.dy)];
    final tolerance = width / 2 + reach;
    for (final q in candidates) {
      if (fill && shape != null && _shapePath.contains(q)) return true;
      // The line between points counts too: a quick swipe records few
      // points far apart.
      for (var i = 0; i < points.length; i++) {
        final a = points[i] as Offset;
        final b = i + 1 < points.length ? points[i + 1] as Offset : a;
        if (_distanceToSegment(q, a, b) <= tolerance) return true;
      }
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// Whether a selection box drawn over the paper catches this stroke:
  /// some of its line (or its mirror image) is inside [box], or [box]
  /// overlaps its text.
  bool touches(Rect box) {
    if (!bounds.overlaps(box)) return false;
    if (text != null) return true;
    final t = transform;
    Offset place(Offset q) => t == null ? q : t.apply(q);
    for (var i = 0; i < points.length; i++) {
      final a = points[i] as Offset;
      final b = i + 1 < points.length ? points[i + 1] as Offset : a;
      // Walk each segment in small steps: few, far-apart points still
      // count where the line between them crosses the box.
      final steps = math.max(1, ((b - a).distance / 4).ceil());
      for (var k = 0; k <= steps; k++) {
        final q = Offset.lerp(a, b, k / steps)!;
        if (box.contains(place(q))) return true;
        if (mirrorX case final m? when box.contains(place(Offset(2 * m - q.dx, q.dy)))) {
          return true;
        }
      }
    }
    // A big filled shape can be caught by a box drawn inside it.
    return fill && shape != null && hits(box.center, reach: 0);
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
    StrokeTransform? transform,
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
        transform: transform,
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

  /// Set once the stroke has been turned or resized with the move tool.
  final StrokeTransform? transform;
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
    if (transform case final t?) {
      canvas
        ..save()
        ..transform(t.matrix4);
    }
    _paintOnce(canvas);
    if (mirrorX case final m?) {
      canvas
        ..save()
        ..translate(2 * m, 0)
        ..scale(-1, 1);
      _paintOnce(canvas);
      canvas.restore();
    }
    if (transform != null) canvas.restore();
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

  /// The area this stroke paints on the paper, mirror image and transform
  /// included.
  Rect get bounds => transform?.applyRect(_localBounds) ?? _localBounds;

  /// [bounds] before the transform.
  Rect get _localBounds {
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
        if (transform != null) 'transform': transform!.toJson(),
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
    // Paintings saved before v2.0 have no transform.
    final transform = StrokeTransform.fromJson(json['transform']);
    if (json['text'] case final Map<String, Object?> text) {
      final p = (json['points'] as List).cast<num>();
      return Stroke.text(
        anchor: Offset(p[0].toDouble(), p[1].toDouble()),
        content: TextContent.fromJson(text),
        color: Color(json['color'] as int),
        opacity: (json['opacity'] as num? ?? 1).toDouble(),
        transform: transform,
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
        transform: transform,
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
      transform: transform,
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
