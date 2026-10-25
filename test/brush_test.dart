import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/drawing/drawing_controller.dart';
import 'package:jingyao_paint/drawing/stroke.dart';
import 'package:jingyao_paint/settings.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

const _size = Size(200, 100);

/// Renders [strokes] on white and returns RGBA bytes, so tests can check
/// real pixels.
Future<ByteData> render(List<Stroke> strokes) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & _size, Paint()..color = Colors.white);
  canvas.saveLayer(Offset.zero & _size, Paint());
  for (final s in strokes) {
    s.paint(canvas);
  }
  canvas.restore();
  final image = await recorder
      .endRecording()
      .toImage(_size.width.toInt(), _size.height.toInt());
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return data;
}

/// The red channel at (x, y): 255 on white paper, lower where ink is.
int red(ByteData px, int x, int y) => px.getUint8((y * _size.width.toInt() + x) * 4);

Stroke line(BrushType brush,
        {double opacity = 1, double? mirrorX, int seed = 42,
        StampShape stamp = StampShape.heart}) =>
    Stroke(
      brush: brush,
      color: Colors.black,
      size: 10,
      opacity: opacity,
      mirrorX: mirrorX,
      seed: seed,
      stamp: stamp,
      usesRealPressure: false,
      isComplete: true,
      points: [
        for (var x = 20.0; x <= 80; x += 5) PointVector(x, 50, 0.5),
      ],
    );

void main() {
  group('New brushes', () {
    // The text tool never makes freehand strokes; see the Text group.
    for (final brush in BrushType.values.where((b) => b != BrushType.text && b != BrushType.move)) {
      test('${brush.name} draws without errors and leaves ink', () async {
        final strokes = [
          if (brush == BrushType.eraser) line(BrushType.marker),
          line(brush),
        ];
        final px = await render(strokes);
        final inked = red(px, 50, 50) < 250;
        // The eraser removes the marker underneath, so that spot is white.
        expect(inked, brush != BrushType.eraser, reason: brush.name);
      });
    }

    test('spray and stamps look the same after saving and reloading', () async {
      for (final brush in [BrushType.spray, BrushType.stamp, BrushType.rainbow]) {
        final original = line(brush, seed: 7, stamp: StampShape.flower);
        final reloaded = Stroke.fromJson(original.toJson());
        final a = await render([original]);
        final b = await render([reloaded]);
        expect(a.buffer.asUint8List(), b.buffer.asUint8List(),
            reason: '${brush.name} must render identically');
      }
    });

    test('every stamp shape draws', () async {
      for (final shape in StampShape.values) {
        final px = await render([line(BrushType.stamp, stamp: shape)]);
        final anyInk = [for (var x = 15; x < 90; x++) red(px, x, 50)]
            .any((r) => r < 200);
        expect(anyInk, isTrue, reason: shape.name);
      }
    });
  });

  group('Opacity', () {
    test('half opacity paints a lighter mark than full opacity', () async {
      final full = red(await render([line(BrushType.marker)]), 50, 50);
      final half =
          red(await render([line(BrushType.marker, opacity: 0.5)]), 50, 50);
      expect(full, lessThan(20));
      expect(half, inInclusiveRange(100, 155));
    });

    test('overlapping spray dots do not get darker than the opacity', () async {
      final px = await render([line(BrushType.spray, opacity: 0.5)]);
      final darkest = [
        for (var x = 20; x < 80; x++)
          for (var y = 45; y < 56; y++) red(px, x, y),
      ].reduce((a, b) => a < b ? a : b);
      expect(darkest, greaterThanOrEqualTo(120));
    });

    test('a half-opacity eraser fades ink instead of removing it', () async {
      final px = await render(
          [line(BrushType.marker), line(BrushType.eraser, opacity: 0.5)]);
      expect(red(px, 50, 50), inInclusiveRange(100, 155));
    });
  });

  group('Mirror drawing', () {
    test('a mirrored stroke also appears on the other side', () async {
      // Drawn on x 20..80; mirrored across x=100 it lands on x 120..180.
      final px = await render([line(BrushType.marker, mirrorX: 100)]);
      expect(red(px, 50, 50), lessThan(50));
      expect(red(px, 150, 50), lessThan(50));
    });

    test('without mirror the other side stays blank', () async {
      final px = await render([line(BrushType.marker)]);
      expect(red(px, 150, 50), 255);
    });
  });

  group('Shapes', () {
    Stroke shape(ShapeKind kind,
            {BrushType brush = BrushType.marker,
            bool fill = false,
            double opacity = 1,
            double? mirrorX,
            Offset from = const Offset(20, 20),
            Offset to = const Offset(80, 80)}) =>
        Stroke.shape(
          shape: kind,
          from: from,
          to: to,
          brush: brush,
          color: Colors.black,
          size: 4,
          opacity: opacity,
          fill: fill,
          mirrorX: mirrorX,
          seed: 3,
          isComplete: true,
        );

    test('every shape draws its outline with every brush', () async {
      for (final kind in ShapeKind.values) {
        for (final brush in BrushType.values.where((b) => b != BrushType.eraser && b != BrushType.move)) {
          final px = await render([shape(kind, brush: brush)]);
          final anyInk = [
            for (var x = 10; x < 95; x += 2)
              for (var y = 10; y < 95; y += 2) red(px, x, y),
          ].any((r) => r < 200);
          expect(anyInk, isTrue, reason: '${kind.name} with ${brush.name}');
        }
      }
    });

    test('rectangle outline: the edge is inked, the middle stays empty',
        () async {
      final px = await render([shape(ShapeKind.rectangle)]);
      expect(red(px, 50, 20), lessThan(60), reason: 'top edge');
      expect(red(px, 20, 50), lessThan(60), reason: 'left edge');
      expect(red(px, 50, 50), 255, reason: 'inside');
    });

    test('a filled shape paints its inside', () async {
      for (final kind in [ShapeKind.rectangle, ShapeKind.ellipse,
          ShapeKind.heart, ShapeKind.star, ShapeKind.triangle]) {
        final px = await render([shape(kind, fill: true)]);
        expect(red(px, 50, 55), lessThan(60), reason: kind.name);
      }
    });

    test('lines and arrows cannot be filled', () {
      expect(shape(ShapeKind.line, fill: true).fill, isFalse);
      expect(shape(ShapeKind.arrow, fill: true).fill, isFalse);
    });

    test('a half-opacity filled shape is evenly see-through', () async {
      final px = await render(
          [shape(ShapeKind.rectangle, fill: true, opacity: 0.5)]);
      // Edge (fill + outline overlap) and middle must look the same.
      expect((red(px, 50, 20) - red(px, 50, 50)).abs(), lessThan(6));
      expect(red(px, 50, 50), inInclusiveRange(100, 155));
    });

    test('a filled eraser shape clears its area', () async {
      final px = await render([
        line(BrushType.marker),
        Stroke.shape(
          shape: ShapeKind.rectangle,
          from: const Offset(40, 30),
          to: const Offset(60, 70),
          brush: BrushType.eraser,
          color: Colors.black,
          size: 4,
          fill: true,
          isComplete: true,
        ),
      ]);
      expect(red(px, 50, 50), 255, reason: 'erased');
      expect(red(px, 25, 50), lessThan(50), reason: 'ink outside remains');
    });

    test('shapes are mirrored too', () async {
      final px = await render(
          [shape(ShapeKind.rectangle, mirrorX: 100)]);
      expect(red(px, 150, 20), lessThan(60));
    });

    test('dragging backwards still makes the same rectangle', () async {
      final a = await render([shape(ShapeKind.rectangle)]);
      final b = await render([
        shape(ShapeKind.rectangle,
            from: const Offset(80, 80), to: const Offset(20, 20)),
      ]);
      expect(a.buffer.asUint8List(), b.buffer.asUint8List());
    });

    test('shapes save as two corners and reload identically', () async {
      for (final kind in ShapeKind.values) {
        final original =
            shape(kind, brush: BrushType.stamp, fill: kind.closed);
        final json = original.toJson();
        expect(json['points'], isEmpty, reason: 'points are rebuilt on load');
        final reloaded = Stroke.fromJson(json);
        expect(reloaded.shape, kind);
        expect(reloaded.fill, original.fill);
        final a = await render([original]);
        final b = await render([reloaded]);
        expect(a.buffer.asUint8List(), b.buffer.asUint8List(),
            reason: kind.name);
      }
    });

    test('a tap with a shape tool draws nothing', () {
      final drawing = DrawingController()
        ..begin(shape(ShapeKind.ellipse,
            from: const Offset(5, 5), to: const Offset(6, 6)))
        ..end();
      expect(drawing.strokes, isEmpty);
    });

    test('dragging resizes the shape being drawn', () {
      final drawing = DrawingController()
        ..begin(shape(ShapeKind.rectangle,
            from: const Offset(10, 10), to: const Offset(10, 10)))
        ..moveShapeEnd(const Offset(90, 60))
        ..end();
      final s = drawing.strokes.single;
      expect(s.shapeTo, const Offset(90, 60));
      final xs = s.points.map((p) => p.x);
      expect(xs.reduce((a, b) => a > b ? a : b), closeTo(90, 0.5));
    });
  });

  group('Text', () {
    Stroke text(TextContent content,
            {Offset at = const Offset(100, 30), double opacity = 1}) =>
        Stroke.text(
            anchor: at, content: content, color: Colors.black, opacity: opacity);

    // Widget tests use a font where every glyph is a solid square, which
    // makes text easy to find in pixels.
    test('text is drawn starting at its anchor', () async {
      final px = await render(
          [text(const TextContent(text: 'AB', fontSize: 20), at: const Offset(20, 30))]);
      expect(red(px, 25, 40), lessThan(60), reason: 'inside the first glyph');
      expect(red(px, 15, 40), 255, reason: 'left of the anchor');
    });

    test('alignment decides which edge sits on the anchor', () {
      const content = TextContent(text: 'ABCD', fontSize: 20);
      final left = text(content).textBounds;
      final center = text(content.copyWith(align: TextAlign.center)).textBounds;
      final right = text(content.copyWith(align: TextAlign.right)).textBounds;
      expect(left.center.dx, greaterThan(100));
      expect(center.center.dx, closeTo(100, 1));
      expect(right.center.dx, lessThan(100));
    });

    test('a bubble paints a soft background around the text', () async {
      final plain = await render([text(const TextContent(text: 'A', fontSize: 20))]);
      final bubbled = await render(
          [text(const TextContent(text: 'A', fontSize: 20, bubble: true))]);
      // Just outside the glyph: blank without a bubble, tinted with one.
      expect(red(plain, 97, 35), 255);
      expect(red(bubbled, 97, 35), lessThan(255));
    });

    test('opacity fades text', () async {
      final px = await render([
        text(const TextContent(text: 'A', fontSize: 20),
            at: const Offset(20, 30), opacity: 0.5),
      ]);
      expect(red(px, 25, 40), inInclusiveRange(100, 155));
    });

    test('formatting and position survive saving', () {
      final original = text(const TextContent(
        text: '靖瑶\n画画',
        fontFamily: 'ZCOOLKuaiLe',
        fontSize: 48,
        bold: true,
        italic: true,
        underline: true,
        strikethrough: true,
        align: TextAlign.center,
        bubble: true,
      ), opacity: 0.7);
      final back = Stroke.fromJson(original.toJson());
      expect(back.text!.toJson(), original.text!.toJson());
      expect(back.anchor, original.anchor);
      expect(back.opacity, 0.7);
      expect(back.brush, BrushType.text);
    });

    test('moving text keeps everything but the position', () {
      final original = text(const TextContent(text: 'x', bold: true));
      final moved = original.movedTo(const Offset(5, 6));
      expect(moved.anchor, const Offset(5, 6));
      expect(moved.text!.toJson(), original.text!.toJson());
      expect(moved.color, original.color);
    });

    test('tapping finds the topmost text under the finger', () {
      final low = text(const TextContent(text: 'AAAA', fontSize: 20));
      final high = text(const TextContent(text: 'BB', fontSize: 20));
      final d = DrawingController()
        ..add(low)
        ..add(high);
      expect(d.hitText(const Offset(105, 40)), same(high));
      expect(d.hitText(const Offset(170, 40)), same(low));
      expect(d.hitText(const Offset(5, 90)), isNull);
    });
  });

  group('Moving strokes', () {
    test('any kind of stroke can be moved and keeps its look', () async {
      const d = Offset(40, 15);
      final strokes = [
        line(BrushType.marker),
        line(BrushType.spray, seed: 9),
        line(BrushType.marker, mirrorX: 100),
        Stroke.shape(
          shape: ShapeKind.heart,
          from: const Offset(20, 20),
          to: const Offset(60, 60),
          brush: BrushType.stamp,
          color: Colors.pink,
          size: 4,
          fill: true,
          seed: 4,
          isComplete: true,
        ),
        Stroke.text(
            anchor: const Offset(30, 30),
            content: const TextContent(text: 'AB', fontSize: 20),
            color: Colors.black),
      ];
      for (final s in strokes) {
        final m = s.moved(d);
        expect(m.bounds.topLeft, offsetMoreOrLessEquals(s.bounds.topLeft + d, epsilon: 1),
            reason: '${s.brush.name} ${s.shape?.name ?? ''}');
        expect(m.seed, s.seed, reason: 'spray and stamps look identical');
        expect(m.toJson()['brush'], s.toJson()['brush']);
        if (s.mirrorX != null) expect(m.mirrorX, s.mirrorX! + d.dx);
      }
    });

    test('a moved spray stroke renders as the same picture, shifted', () async {
      final original = line(BrushType.spray, seed: 5);
      final moved = original.moved(const Offset(30, 0));
      final a = await render([original]);
      final b = await render([moved]);
      // Same dot 30px to the right.
      for (var x = 20; x < 80; x += 7) {
        expect(red(b, x + 30, 50), red(a, x, 50), reason: 'x=$x');
      }
    });

    test('hits: on the line or inside a filled shape, not far away', () {
      final stroke = line(BrushType.marker);
      expect(stroke.hits(const Offset(50, 52)), isTrue);
      expect(stroke.hits(const Offset(50, 90)), isFalse);
      final filled = Stroke.shape(
          shape: ShapeKind.rectangle,
          from: const Offset(10, 10),
          to: const Offset(90, 90),
          brush: BrushType.marker,
          color: Colors.black,
          size: 4,
          fill: true,
          isComplete: true);
      expect(filled.hits(const Offset(50, 50)), isTrue, reason: 'inside');
      final mirrored = line(BrushType.marker, mirrorX: 100);
      expect(mirrored.hits(const Offset(150, 50)), isTrue,
          reason: 'the mirror image counts');
    });

    test('the topmost stroke is picked, and erased strokes never are', () {
      final low = line(BrushType.marker);
      final high = line(BrushType.pen);
      final eraser = line(BrushType.eraser);
      final d = DrawingController()
        ..add(low)
        ..add(high)
        ..add(eraser);
      expect(d.hitStroke(const Offset(50, 50)), same(high));
    });
  });

  group('Saved data', () {
    test('strokes saved before v1.2 still load with sensible defaults', () {
      final old = Stroke.fromJson({
        'brush': 'pen',
        'color': 0xFF000000,
        'size': 8,
        'realPressure': false,
        'points': [1, 2, 0.5, 3, 4, 0.5],
      });
      expect(old.opacity, 1);
      expect(old.mirrorX, isNull);
      expect(old.points, hasLength(2));
    });

    test('opacity, seed, stamp and mirror survive JSON', () {
      final s = Stroke.fromJson(line(BrushType.stamp,
              opacity: 0.4, mirrorX: 100, seed: 9, stamp: StampShape.star)
          .toJson());
      expect(s.opacity, 0.4);
      expect(s.mirrorX, 100);
      expect(s.seed, 9);
      expect(s.stamp, StampShape.star);
    });

    test('paper color is saved with the painting and restored', () async {
      final app = await createTestApp();
      app.session.drawing.load([sampleStroke()]);
      app.session.drawing.setPaper(const Color(0xFFFFF0F5));
      await app.session.save();
      final id = app.session.id;

      await app.session.newPainting();
      await app.session.open(id);
      expect(app.session.drawing.paper.toARGB32(), 0xFFFFF0F5);
    });

    test('changing only the paper counts as an edit', () {
      final drawing = DrawingController();
      final before = drawing.revision;
      drawing.setPaper(const Color(0xFFEEF6FF));
      expect(drawing.revision, greaterThan(before));
    });
  });

  group('Brush settings', () {
    test('opacity, stamp, mirror, paper and theme are remembered', () async {
      SharedPreferences.setMockInitialValues({});
      (await AppSettings.load())
        ..brush = BrushType.spray
        ..opacity = 0.3
        ..stamp = StampShape.flower
        ..mirror = true
        ..paper = const Color(0xFFFFF8E7)
        ..theme = 'mint';

      final reloaded = AppSettings(await SharedPreferences.getInstance());
      expect(reloaded.brush, BrushType.spray);
      expect(reloaded.opacity, closeTo(0.3, 1e-9));
      expect(reloaded.opacityFor(BrushType.pen), 1,
          reason: 'each brush has its own opacity');
      expect(reloaded.stamp, StampShape.flower);
      expect(reloaded.mirror, isTrue);
      expect(reloaded.paper.toARGB32(), 0xFFFFF8E7);
      expect(reloaded.themeId.value, 'mint');
    });

    test('defaults: sakura theme, cute font, freehand, full opacity',
        () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      expect(settings.themeId.value, 'sakura');
      expect(settings.fontId.value, 'kuaile');
      expect(settings.shape, isNull);
      expect(settings.fill, isFalse);
      expect(settings.opacity, 1);
      expect(settings.mirror, isFalse);
    });

    test('shape, fill and font are remembered', () async {
      SharedPreferences.setMockInitialValues({});
      (await AppSettings.load())
        ..shape = ShapeKind.heart
        ..fill = true
        ..font = 'longcang';
      final reloaded = AppSettings(await SharedPreferences.getInstance());
      expect(reloaded.shape, ShapeKind.heart);
      expect(reloaded.fill, isTrue);
      expect(reloaded.fontId.value, 'longcang');

      reloaded.shape = null; // back to freehand
      final again = AppSettings(await SharedPreferences.getInstance());
      expect(again.shape, isNull);
    });

    test('picking a color leaves the rainbow brush for the pen', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load()..brush = BrushType.rainbow;
      settings.color = Colors.blue;
      expect(settings.brush, BrushType.pen);
    });
  });
}
