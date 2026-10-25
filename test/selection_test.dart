import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/drawing/canvas_page.dart';
import 'package:jingyao_paint/drawing/drawing_controller.dart';
import 'package:jingyao_paint/drawing/stroke.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import 'brush_test.dart' show red, render;
import 'test_helpers.dart';
import 'widget_test.dart' show pumpApp;

/// A horizontal black line from (x0, y) to (x1, y).
Stroke hLine(double x0, double x1, double y, {Color color = Colors.black}) =>
    Stroke(
      brush: BrushType.marker,
      color: color,
      size: 8,
      seed: 7,
      usesRealPressure: false,
      isComplete: true,
      points: [
        for (var x = x0; x <= x1; x += 5) PointVector(x, y, 0.5),
      ],
    );

void main() {
  group('Turning and resizing strokes', () {
    test('a transform keeps its center fixed and undoes cleanly', () {
      final t = StrokeTransform.around(const Offset(50, 40),
          scale: 2, angle: math.pi / 2);
      final c = t.apply(const Offset(50, 40));
      expect(c.dx, closeTo(50, 1e-9));
      expect(c.dy, closeTo(40, 1e-9));
      // 10 to the right becomes 20 downward (a quarter turn, twice as big).
      final p = t.apply(const Offset(60, 40));
      expect(p.dx, closeTo(50, 1e-9));
      expect(p.dy, closeTo(60, 1e-9));
      expect(t.scale, closeTo(2, 1e-9));
      expect(t.angle, closeTo(math.pi / 2, 1e-9));
      final back = t.then(t.inverse).apply(const Offset(13, 7));
      expect(back.dx, closeTo(13, 1e-9));
      expect(back.dy, closeTo(7, 1e-9));
    });

    test('a turned line is drawn turned, and is hit where it is drawn',
        () async {
      final upright = hLine(20, 80, 50);
      final turned = upright.transformed(
          StrokeTransform.around(const Offset(50, 50), angle: math.pi / 2));
      final px = await render([turned]);
      expect(red(px, 50, 25), lessThan(100), reason: 'now vertical');
      expect(red(px, 25, 50), greaterThan(200), reason: 'not horizontal');
      expect(turned.hits(const Offset(50, 25)), isTrue);
      expect(turned.hits(const Offset(25, 50)), isFalse);
      expect(turned.bounds.height, greaterThan(turned.bounds.width));
    });

    test('resizing scales the line and its width', () async {
      final big = hLine(40, 60, 50).transformed(
          StrokeTransform.around(const Offset(50, 50), scale: 3));
      final px = await render([big]);
      expect(red(px, 25, 50), lessThan(100), reason: '3x as long');
      expect(red(px, 50, 58), lessThan(100), reason: '3x as thick');
      expect(big.bounds.width, closeTo(hLine(40, 60, 50).bounds.width * 3, 1));
    });

    test('moving a turned stroke adds to its transform', () {
      final turned = hLine(20, 80, 50).transformed(
          StrokeTransform.around(const Offset(50, 50), angle: 0.3));
      final moved = turned.moved(const Offset(10, -5));
      expect(moved.points.first, turned.points.first, reason: 'same geometry');
      expect(moved.bounds.left, closeTo(turned.bounds.left + 10, 1e-6));
      expect(moved.bounds.top, closeTo(turned.bounds.top - 5, 1e-6));
      expect(moved.transform!.angle, closeTo(0.3, 1e-9));
    });

    test('shapes, text and mirrored strokes keep their transform when saved',
        () {
      final t = StrokeTransform.around(const Offset(30, 30),
          scale: 1.5, angle: 0.5);
      final strokes = [
        Stroke.shape(
          shape: ShapeKind.star,
          from: const Offset(10, 10),
          to: const Offset(50, 50),
          brush: BrushType.pen,
          color: Colors.red,
          size: 4,
          fill: true,
          isComplete: true,
        ).transformed(t),
        Stroke.text(
          anchor: const Offset(5, 5),
          content: const TextContent(text: 'hi'),
          color: Colors.blue,
        ).transformed(t),
        Stroke(
          brush: BrushType.spray,
          color: Colors.green,
          size: 6,
          mirrorX: 100,
          usesRealPressure: false,
          isComplete: true,
          points: const [PointVector(20, 20, 0.5), PointVector(40, 30, 0.5)],
        ).transformed(t),
      ];
      for (final s in strokes) {
        final back = Stroke.fromJson(s.toJson());
        expect(back.transform!.angle, closeTo(0.5, 1e-3));
        expect(back.transform!.scale, closeTo(1.5, 1e-3));
        expect(back.bounds.center.dx, closeTo(s.bounds.center.dx, 0.5));
        expect(back.seed, s.seed);
      }
    });

    test('paintings saved before v2.0 load without a transform', () {
      final json = hLine(0, 10, 0).toJson()..remove('transform');
      expect(Stroke.fromJson(json).transform, isNull);
    });

    test('recoloring and fading keep everything else', () {
      final s = hLine(0, 50, 10).transformed(
          StrokeTransform.around(Offset.zero, scale: 2));
      final c = s.copyWith(color: Colors.pink, opacity: 0.4);
      expect(c.color, Colors.pink);
      expect(c.opacity, 0.4);
      expect(c.seed, s.seed);
      expect(c.transform, s.transform);
      expect(c.points.length, s.points.length);
    });
  });

  group('Selecting several strokes', () {
    test('a quick swipe with few points is hit between them', () {
      final s = Stroke(
        brush: BrushType.pen,
        color: Colors.black,
        size: 6,
        usesRealPressure: false,
        isComplete: true,
        points: const [PointVector(0, 50, 0.5), PointVector(100, 50, 0.5)],
      );
      expect(s.hits(const Offset(50, 55)), isTrue);
      expect(s.hits(const Offset(50, 90)), isFalse);
      expect(s.touches(const Rect.fromLTRB(40, 40, 60, 60)), isTrue);
    });

    test('a box catches the strokes it touches, but not erasers', () {
      final a = hLine(10, 50, 10);
      final b = hLine(10, 50, 60);
      final far = hLine(150, 190, 90);
      final eraser = Stroke(
        brush: BrushType.eraser,
        color: Colors.black,
        size: 10,
        usesRealPressure: false,
        isComplete: true,
        points: const [PointVector(30, 30, 0.5)],
      );
      final d = DrawingController();
      for (final s in [a, b, far, eraser]) {
        d.add(s);
      }
      expect(d.strokesIn(const Rect.fromLTRB(0, 0, 60, 70)), [a, b]);
      expect(d.strokesIn(const Rect.fromLTRB(40, 55, 45, 65)), [b],
          reason: 'touching part of a line is enough');
      expect(d.strokesIn(const Rect.fromLTRB(100, 0, 120, 30)), isEmpty);
    });

    test('a box over a mirrored stroke\'s other half catches it', () {
      final s = Stroke(
        brush: BrushType.pen,
        color: Colors.black,
        size: 4,
        mirrorX: 100,
        usesRealPressure: false,
        isComplete: true,
        points: const [PointVector(20, 20, 0.5), PointVector(30, 20, 0.5)],
      );
      expect(s.touches(const Rect.fromLTRB(165, 10, 185, 30)), isTrue);
    });

    test('changing, copying and deleting several strokes are single undos',
        () {
      final a = hLine(10, 50, 10);
      final b = hLine(10, 50, 60);
      final d = DrawingController()
        ..add(a)
        ..add(b);
      d.replaceAll([a, b], [a.moved(const Offset(5, 0)), b.moved(const Offset(5, 0))]);
      d.undo();
      expect(d.strokes, [a, b]);
      d.addAll([a.moved(const Offset(24, 24)), b.moved(const Offset(24, 24))]);
      expect(d.strokes, hasLength(4));
      d.undo();
      expect(d.strokes, [a, b]);
      d.removeAll([a, b]);
      expect(d.strokes, isEmpty);
      d.undo();
      expect(d.strokes, [a, b]);
    });
  });

  group('Move tool on the canvas', () {
    CanvasPageState page(WidgetTester tester) =>
        tester.state<CanvasPageState>(find.byType(CanvasPage));
    Offset paper(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(CanvasPageState.paperKey));

    /// Taps a selection bar button, scrolling the bar to it first (it
    /// scrolls sideways on phones).
    Future<void> tapBar(WidgetTester tester, String tooltip) async {
      await tester.ensureVisible(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
    }

    /// Three short lines: two on the left, one far down on the right.
    Future<TestApp> threeLines(WidgetTester tester) async {
      final app = await pumpApp(tester);
      for (final (from, to) in [
        (const Offset(60, 300), const Offset(140, 300)),
        (const Offset(60, 400), const Offset(140, 400)),
        (const Offset(250, 650), const Offset(330, 650)),
      ]) {
        await tester.dragFrom(from, to - from);
        await tester.pump();
      }
      app.settings.brush = BrushType.move;
      await tester.pump();
      return app;
    }

    /// Drags a box over the first two lines.
    Future<void> boxSelectTwo(WidgetTester tester) async {
      await tester.dragFrom(const Offset(40, 270), const Offset(130, 160));
      await tester.pumpAndSettle();
    }

    testWidgets('dragging a box over empty paper selects what it touches',
        (tester) async {
      final app = await threeLines(tester);
      await boxSelectTwo(tester);
      final strokes = app.session.drawing.strokes;
      expect(page(tester).selected.value, [strokes[0], strokes[1]]);
      expect(find.text('已选 2 个'), findsOneWidget);
      expect(strokes, hasLength(3), reason: 'the box drew nothing');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('dragging the selection moves all of it, undone in one step',
        (tester) async {
      final app = await threeLines(tester);
      await boxSelectTwo(tester);
      final before = List.of(app.session.drawing.strokes);
      await tester.dragFrom(const Offset(100, 400), const Offset(50, 30));
      await tester.pumpAndSettle();
      final after = app.session.drawing.strokes;
      expect(after[0].points.first.x, closeTo(before[0].points.first.x + 50, 1));
      expect(after[1].points.first.y, closeTo(before[1].points.first.y + 30, 1));
      expect(after[2], same(before[2]), reason: 'not selected');
      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.pump();
      expect(app.session.drawing.strokes, before);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('copy, bigger, turn and delete buttons act on the selection',
        (tester) async {
      final app = await threeLines(tester);
      await boxSelectTwo(tester);
      final drawing = app.session.drawing;

      await tapBar(tester, '复制');
      expect(drawing.strokes, hasLength(5));
      final copies = drawing.strokes.sublist(3);
      expect(page(tester).selected.value, copies, reason: 'copies selected');
      expect(copies[0].points.first.x,
          closeTo(drawing.strokes[0].points.first.x + 24, 0.01));

      await tapBar(tester, '放大');
      expect(drawing.strokes[3].transform!.scale, closeTo(1.25, 1e-6));
      await tapBar(tester, '向右转');
      expect(drawing.strokes[4].transform!.angle, closeTo(math.pi / 12, 1e-6));

      await tapBar(tester, '删除选中的');
      expect(drawing.strokes, hasLength(3));
      expect(page(tester).selected.value, isEmpty);
      expect(find.byKey(CanvasPageState.selectionBarKey), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('dragging the corner knob resizes, the top knob turns',
        (tester) async {
      final app = await threeLines(tester);
      await boxSelectTwo(tester);
      final state = page(tester);
      var frame = state.selectionFrame.value!;
      var center = frame.box.center;
      final corner = frame.scaleHandle;
      // Twice as far from the middle: twice as big.
      await tester.dragFrom(paper(tester) + corner, corner - center);
      await tester.pumpAndSettle();
      for (final s in app.session.drawing.strokes.take(2)) {
        expect(s.transform!.scale, closeTo(2, 0.05));
      }

      frame = state.selectionFrame.value!;
      center = frame.box.center;
      final knob = frame.rotateHandle; // straight above the middle
      final radius = (knob - center).distance;
      // From above the middle to its right: a quarter turn clockwise.
      await tester.dragFrom(paper(tester) + knob,
          center + Offset(radius, 0) - knob);
      await tester.pumpAndSettle();
      final turned = app.session.drawing.strokes.first.transform!;
      expect(turned.angle, closeTo(math.pi / 2, 0.05));
      expect(turned.scale, closeTo(2, 0.05), reason: 'size kept');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the color sheet recolors and fades the selection',
        (tester) async {
      final app = await threeLines(tester);
      await boxSelectTwo(tester);
      await tapBar(tester, '颜色和透明度');
      expect(find.text('颜色和透明度'), findsWidgets);

      await tester.tap(find.bySemanticsLabel('颜色 #3DA9FC'));
      await tester.pump();
      final drawing = app.session.drawing;
      expect(drawing.strokes[0].color, const Color(0xFF3DA9FC));
      expect(drawing.strokes[1].color, const Color(0xFF3DA9FC));
      expect(drawing.strokes[2].color, isNot(const Color(0xFF3DA9FC)));

      // One drag of the slider is one undo step.
      final slider = find.descendant(
          of: find.byType(BottomSheet), matching: find.byType(Slider));
      await tester.drag(slider, const Offset(-120, 0));
      await tester.pumpAndSettle();
      final faded = drawing.strokes[0].opacity;
      expect(faded, lessThan(1));
      expect(drawing.strokes[1].opacity, faded);
      drawing.undo();
      expect(drawing.strokes[0].opacity, 1);
      expect(drawing.strokes[0].color, const Color(0xFF3DA9FC),
          reason: 'the recolor is the step before');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the bar sits below the selection and hides while dragging',
        (tester) async {
      await threeLines(tester);
      await boxSelectTwo(tester);
      final bar = find.byKey(CanvasPageState.selectionBarKey);
      final frame = page(tester).selectionFrame.value!;
      final selectionBottom = (paper(tester) + frame.box.bottomRight).dy;
      expect(tester.getRect(bar).top, greaterThan(selectionBottom));

      final finger = await tester.startGesture(const Offset(100, 400));
      await finger.moveBy(const Offset(0, 40));
      await tester.pump();
      await finger.moveBy(const Offset(0, 40));
      await tester.pump();
      await tester.pump();
      expect(bar, findsNothing, reason: 'out of the way while moving');
      await finger.up();
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the selection bar speaks English too', (tester) async {
      final app = await createTestApp(prefs: {'flutter.language': 'en'});
      await pumpApp(tester, app: app);
      for (final y in [300.0, 400.0]) {
        await tester.dragFrom(Offset(60, y), const Offset(80, 0));
        await tester.pump();
      }
      app.settings.brush = BrushType.move;
      await tester.pump();
      await boxSelectTwo(tester);
      expect(find.text('2 selected'), findsOneWidget);
      for (final tip in ['Copy', 'Bigger', 'Turn left', 'Color and opacity']) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a tap on another stroke selects just that one',
        (tester) async {
      final app = await threeLines(tester);
      await boxSelectTwo(tester);
      await tester.tapAt(const Offset(290, 650));
      await tester.pump();
      expect(page(tester).selected.value, [app.session.drawing.strokes[2]]);
      expect(find.text('已选 1 个'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
