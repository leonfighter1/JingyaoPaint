import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/app_theme.dart';
import 'package:jingyao_paint/drawing/canvas_page.dart';
import 'package:jingyao_paint/drawing/stroke.dart';
import 'package:jingyao_paint/gallery/gallery_page.dart';
import 'package:jingyao_paint/main.dart';
import 'package:jingyao_paint/settings.dart';
import 'package:jingyao_paint/theme/cute_theme.dart';
import 'package:jingyao_paint/theme/theme_spec.dart';
import 'package:jingyao_paint/widgets/corner_float.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

List<ThemeSpec>? _themes;

Future<TestApp> pumpApp(
  WidgetTester tester, {
  TestApp? app,
  Size screen = const Size(393, 829),
}) async {
  // Phone-sized by default, so the layout matches what users see.
  tester.view.physicalSize = screen * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  _themes ??= await tester.runAsync(() => ThemeSpec.loadAll(kThemeIds));
  app ??= await createTestApp();
  await tester.pumpWidget(PaintApp(
    settings: app.settings,
    session: app.session,
    themes: _themes!,
    music: app.music,
  ));
  await tester.pumpAndSettle();
  return app;
}

IconButton iconButton(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

Finder inGallery(Finder f) =>
    find.descendant(of: find.byType(GalleryPage), matching: f);

Future<void> drawStroke(WidgetTester tester) async {
  await tester.dragFrom(const Offset(80, 250), const Offset(150, 120));
  await tester.pump();
}

/// Taps tab [index] in whichever navigation is showing: the bottom bar on
/// phones, the side rail on wide screens. Each tab has exactly one label.
Future<void> openTab(WidgetTester tester, int index) async {
  final nav = find.byWidgetPredicate(
      (w) => w is NavigationBar || w is NavigationRail);
  await tester.tap(
      find.descendant(of: nav, matching: find.byType(Text)).at(index));
  await tester.pumpAndSettle();
}

/// Taps an item in the canvas page's "more" menu.
Future<void> tapMenu(WidgetTester tester, String label) =>
    _tapMenuItem(tester, find.widgetWithText(ListTile, label));

/// Opens the ⋮ menu and taps [item]. The menu unfolds downward and
/// scrolls on short screens, so the item is scrolled into view first.
Future<void> _tapMenuItem(WidgetTester tester, Finder item) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

/// The ⋮ menu on a gallery card (not the one in the gallery's header).
Finder cardMenu() => find
    .descendant(
        of: find.byType(Card), matching: find.byType(PopupMenuButton<VoidCallback>))
    .first;

/// Opens Settings from the canvas page's ⋮ menu (it isn't a tab anymore).
/// Found by its icon, so it works in either language.
Future<void> openSettings(WidgetTester tester) async {
  await openTab(tester, 0);
  await _tapMenuItem(
      tester, find.widgetWithIcon(ListTile, Icons.settings_rounded));
}

/// Goes back from Settings with its back arrow. (Not `tester.pageBack()`:
/// it looks for the English "Back" tooltip, and the app is in Chinese.)
Future<void> leaveSettings(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

/// Slides in the tools drawer with the "画笔 · 颜色" button.
Future<void> openTools(WidgetTester tester) async {
  await tester.tap(find.byKey(CanvasPageState.toolsButtonKey));
  await tester.pumpAndSettle();
}

/// Scrolls the open tools drawer until [target] is built and visible.
/// The drawer's list builds lazily, so lower items don't exist until then.
Future<void> scrollTools(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 120,
      scrollable: find
          .descendant(
              of: find.byKey(CanvasPageState.toolsListKey),
              matching: find.byType(Scrollable))
          .first);
  await tester.pumpAndSettle();
}

/// Closes the tools drawer with its close button.
Future<void> closeTools(WidgetTester tester) async {
  await tester.tap(find.byTooltip('收起画笔和颜色'));
  await tester.pumpAndSettle();
}

/// The current zoom level of the paper view.
double zoomOf(WidgetTester tester) => CanvasPageState.zoomLevel(
    tester.widget<Transform>(find.byKey(CanvasPageState.zoomKey)).transform);

void main() {
  testWidgets('opens in Chinese with the new title and all brushes',
      (tester) async {
    await pumpApp(tester);

    expect(find.text('靖瑶的画板'), findsOneWidget);
    expect(find.text('画板'), findsOneWidget);
    expect(find.text('我的画作'), findsOneWidget);
    expect(find.text('设置'), findsNothing,
        reason: 'settings lives in the ⋮ menu, not the bottom bar');
    expect(find.text('画笔 · 颜色'), findsOneWidget, reason: 'tools button');

    await openTools(tester);
    for (final name in ['钢笔', '铅笔', '马克笔', '荧光笔', '喷枪', '彩虹笔', '印章', '文字', '橡皮擦']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  group('Tools drawer', () {
    testWidgets('is hidden until the button is tapped, then slides in',
        (tester) async {
      await pumpApp(tester);
      expect(find.byType(Slider), findsNothing, reason: 'hidden at first');

      await tester.tap(find.byKey(CanvasPageState.toolsButtonKey));
      await tester.pump(const Duration(milliseconds: 120));
      // Mid-animation: the drawer is partly on screen, still moving in.
      final drawer = find.text('画笔与颜色');
      final midX = tester.getTopLeft(drawer).dx;
      await tester.pumpAndSettle();
      final endX = tester.getTopLeft(drawer).dx;
      expect(endX, lessThan(midX), reason: 'slides in from the right');
      expect(find.text('钢笔'), findsOneWidget);
      await scrollTools(tester, find.byTooltip('笔刷大小'));
      expect(find.byType(Slider), findsWidgets);
    });

    testWidgets('closes with the close button, the backdrop, Back or a swipe',
        (tester) async {
      await pumpApp(tester);
      final title = find.text('画笔与颜色');

      await openTools(tester);
      await closeTools(tester);
      expect(title, findsNothing, reason: 'close button');

      await openTools(tester);
      await tester.tapAt(const Offset(30, 400)); // the dimmed paper
      await tester.pumpAndSettle();
      expect(title, findsNothing, reason: 'tapping the backdrop');
      expect(tester.takeException(), isNull);

      await openTools(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(title, findsNothing, reason: 'Back closes it, not the app');

      await openTools(tester);
      await tester.drag(title, const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(title, findsNothing, reason: 'swiping the header right');
    });

    testWidgets('tapping the backdrop does not draw', (tester) async {
      final app = await pumpApp(tester);
      await openTools(tester);
      await drawStroke(tester); // lands on the backdrop
      await tester.pumpAndSettle();
      expect(app.session.drawing.strokes, isEmpty);
    });

    testWidgets('the button shows the current brush and color',
        (tester) async {
      final app = await pumpApp(tester);
      app.settings.brush = BrushType.marker;
      await tester.pumpAndSettle();
      final button = find.byKey(CanvasPageState.toolsButtonKey);
      expect(
          find.descendant(of: button, matching: find.byIcon(Icons.brush_rounded)),
          findsOneWidget);
      expect(find.bySemanticsLabel('打开画笔和颜色'), findsOneWidget);
    });

    testWidgets('screen readers can activate the tools button',
        (tester) async {
      // Found on the emulator: merging the label with excludeSemantics had
      // dropped the tap action, so TalkBack could read it but not press it.
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      final button = find.semantics.byLabel('打开画笔和颜色');
      expect(button.evaluate().single.getSemanticsData()
          .hasAction(SemanticsAction.tap), isTrue);
      tester.semantics.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('画笔与颜色'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Draggable corner controls', () {
    Finder tools() => find.byKey(CanvasPageState.toolsButtonKey);
    Finder undo() => find.byKey(CanvasPageState.undoFloatKey);

    testWidgets('the tools button can be dragged to another corner',
        (tester) async {
      final app = await pumpApp(tester);
      expect(app.settings.toolsCorner, Corner.bottomRight);
      final paper = tester.getRect(find.byKey(CanvasPageState.paperKey));

      // Drag towards the bottom-left corner and let go.
      await tester.drag(tools(), Offset(-(paper.width - 120), 0));
      await tester.pumpAndSettle();
      expect(app.settings.toolsCorner, Corner.bottomLeft);
      expect(tester.getCenter(tools()).dx, lessThan(paper.left + 150),
          reason: 'it glided into the corner');
    });

    testWidgets('the two controls never share a corner', (tester) async {
      final app = await pumpApp(tester);
      expect(app.settings.undoCorner, Corner.topRight);
      final paper = tester.getRect(find.byKey(CanvasPageState.paperKey));

      // Drop the tools button right onto the undo buttons' corner.
      await tester.drag(tools(), Offset(0, -(paper.height - 120)));
      await tester.pumpAndSettle();
      expect(app.settings.toolsCorner, isNot(Corner.topRight));
      expect(app.settings.undoCorner, Corner.topRight);
      expect(tester.getRect(tools()).overlaps(tester.getRect(undo())), isFalse);
    });

    testWidgets('undo/redo can be dragged too, and the corner is remembered',
        (tester) async {
      final app = await pumpApp(tester);
      final paper = tester.getRect(find.byKey(CanvasPageState.paperKey));
      await tester.drag(undo(), Offset(-(paper.width - 140), 0));
      await tester.pumpAndSettle();
      expect(app.settings.undoCorner, Corner.topLeft);
      final again = AppSettings(await SharedPreferences.getInstance());
      expect(again.undoCorner, Corner.topLeft);
    });

    testWidgets('a quick tap still opens the drawer (dragging needs movement)',
        (tester) async {
      await pumpApp(tester);
      await tester.tap(tools());
      await tester.pumpAndSettle();
      expect(find.text('画笔与颜色'), findsOneWidget);
    });

    testWidgets('with the button on the left, the drawer opens from the left',
        (tester) async {
      final app = await pumpApp(tester);
      app.settings.toolsCorner = Corner.bottomLeft;
      await tester.pumpAndSettle();
      expect(find.descendant(of: tools(),
              matching: find.byIcon(Icons.chevron_right_rounded)),
          findsOneWidget, reason: 'the arrow points where it opens');
      await openTools(tester);
      final title = tester.getTopLeft(find.text('画笔与颜色'));
      expect(title.dx, lessThan(200), reason: 'drawer is on the left');

      // Swiping its header back to the left closes it.
      await tester.drag(find.text('画笔与颜色'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('画笔与颜色'), findsNothing);
    });
  });

  group('Move tool and eraser options', () {
    testWidgets('switching to move selects the last stroke; dragging moves it',
        (tester) async {
      final app = await pumpApp(tester);
      await drawStroke(tester); // from (80,250) to (230,130) on screen
      final before = app.session.drawing.strokes.single;
      app.settings.brush = BrushType.move;
      await tester.pump();

      final overlay = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.foregroundPainter)
          .whereType<CanvasOverlayPainter>()
          .single;
      expect(overlay.selected.value.single, same(before), reason: 'last stroke');

      // Grab it in the middle and drag it 60px right.
      final paper = tester.getTopLeft(find.byKey(CanvasPageState.paperKey));
      final onStroke = paper + (before.points[before.points.length ~/ 2]);
      await tester.dragFrom(onStroke, const Offset(60, 0));
      await tester.pumpAndSettle();
      final after = app.session.drawing.strokes.single;
      expect(after.points.first.x, closeTo(before.points.first.x + 60, 1));
      expect(overlay.selected.value.single, same(after), reason: 'still selected');

      // One undo puts the whole drag back.
      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.pump();
      expect(app.session.drawing.strokes.single, same(before));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('tapping empty paper clears the selection, drawing nothing',
        (tester) async {
      final app = await pumpApp(tester);
      await drawStroke(tester);
      app.settings.brush = BrushType.move;
      await tester.pump();
      await tester.tapAt(const Offset(350, 600));
      await tester.pump();
      final overlay = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.foregroundPainter)
          .whereType<CanvasOverlayPainter>()
          .single;
      expect(overlay.selected.value, isEmpty);
      expect(app.session.drawing.strokes, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the eraser shows no colors or shapes and draws round only',
        (tester) async {
      final app = await pumpApp(tester);
      app.settings
        ..shape = ShapeKind.rectangle
        ..brush = BrushType.eraser;
      await openTools(tester);
      expect(find.text('颜料'), findsNothing);
      expect(find.text('形状'), findsNothing);
      expect(find.textContaining('橡皮擦是圆头的'), findsOneWidget);
      await closeTools(tester);

      await drawStroke(tester);
      expect(app.session.drawing.strokes.single.shape, isNull,
          reason: 'ignores the rectangle setting');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('rainbow hides colors but keeps shapes; move hides both',
        (tester) async {
      final app = await pumpApp(tester);
      app.settings.brush = BrushType.rainbow;
      await openTools(tester);
      expect(find.text('颜料'), findsNothing);
      expect(find.text('形状'), findsOneWidget);
      app.settings.brush = BrushType.move;
      await tester.pumpAndSettle();
      expect(find.text('形状'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      app.settings.brush = BrushType.pen;
      await tester.pumpAndSettle();
      expect(find.text('颜料'), findsOneWidget);
    });
  });

  group('Zoom', () {
    testWidgets('pinching zooms the paper and does not draw', (tester) async {
      final app = await pumpApp(tester);
      final a = await tester.startGesture(const Offset(150, 300), pointer: 1);
      await tester.pump(const Duration(milliseconds: 30));
      final b = await tester.startGesture(const Offset(250, 300), pointer: 2);
      for (var i = 1; i <= 5; i++) {
        await a.moveTo(Offset(150 - i * 15.0, 300));
        await b.moveTo(Offset(250 + i * 15.0, 300));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      expect(zoomOf(tester), closeTo(2.5, 0.05), reason: '100px → 250px');
      expect(app.session.drawing.strokes, isEmpty,
          reason: 'the first finger did not leave a stroke');
      expect(find.text('250% · 适应屏幕'), findsOneWidget);
    });

    testWidgets('fit to screen animates back to 100%', (tester) async {
      await pumpApp(tester);
      await tapMenu(tester, '放大画布');
      expect(zoomOf(tester), closeTo(1.25, 0.001));
      await tester.tap(find.text('125% · 适应屏幕'));
      await tester.pump(); // the animation starts on the next frame
      await tester.pump(const Duration(milliseconds: 100));
      final mid = zoomOf(tester);
      await tester.pumpAndSettle();
      expect(mid, inExclusiveRange(1.0, 1.25), reason: 'animated, not a jump');
      expect(zoomOf(tester), closeTo(1, 0.001));
      expect(find.textContaining('适应屏幕'), findsNothing,
          reason: 'chip hides at 100%');
    });

    testWidgets('zoom stays between 50% and 800%', (tester) async {
      await pumpApp(tester);
      for (var i = 0; i < 20; i++) {
        await tapMenu(tester, '放大画布');
      }
      expect(zoomOf(tester), closeTo(CanvasPageState.maxZoom, 0.001));
      for (var i = 0; i < 30; i++) {
        await tapMenu(tester, '缩小画布');
      }
      expect(zoomOf(tester), closeTo(CanvasPageState.minZoom, 0.001));
    });

    testWidgets('drawing while zoomed lands under the finger', (tester) async {
      final app = await pumpApp(tester);
      final paper = find.byKey(CanvasPageState.paperKey);
      final before = tester.getTopLeft(paper);
      await tapMenu(tester, '放大画布');
      await tapMenu(tester, '放大画布'); // 156%

      // Where does paper point (150, 300) appear on screen now?
      const target = Offset(150, 300);
      final box = tester.renderObject<RenderBox>(paper);
      final onScreen = box.localToGlobal(target);
      expect(onScreen, isNot(before + target));
      await tester.dragFrom(onScreen, const Offset(40, 0));
      await tester.pump();
      final first = app.session.drawing.strokes.single.points.first;
      expect(first.x, closeTo(target.dx, 1));
      expect(first.y, closeTo(target.dy, 1));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('opening another painting resets the zoom', (tester) async {
      final app = await createTestApp();
      await app.store.save(sampleDoc('p', DateTime(2026, 1, 1)), tinyPng);
      await pumpApp(tester, app: app);
      await tapMenu(tester, '放大画布');
      await app.session.open('p');
      await tester.pumpAndSettle();
      expect(zoomOf(tester), closeTo(1, 0.001));
    });
  });

  testWidgets('drawing enables undo, and undo disables it again',
      (tester) async {
    await pumpApp(tester);
    expect(iconButton(tester, Icons.undo_rounded).onPressed, isNull);

    await drawStroke(tester);
    expect(iconButton(tester, Icons.undo_rounded).onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pump();
    expect(iconButton(tester, Icons.undo_rounded).onPressed, isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a stroke uses the chosen opacity', (tester) async {
    final app = await pumpApp(tester);
    app.settings.opacity = 0.4;
    await drawStroke(tester);
    expect(app.session.drawing.strokes.single.opacity, closeTo(0.4, 1e-9));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the stamp brush shows shape choices and stamps that shape',
      (tester) async {
    final app = await pumpApp(tester);
    expect(find.text('星星'), findsNothing);

    app.settings.brush = BrushType.stamp;
    await openTools(tester);
    await scrollTools(tester, find.widgetWithText(ChoiceChip, '星星'));
    await tester.tap(find.widgetWithText(ChoiceChip, '星星'));
    await tester.pumpAndSettle();
    expect(app.settings.stamp, StampShape.star);
    await closeTools(tester);

    await drawStroke(tester);
    final stroke = app.session.drawing.strokes.single;
    expect(stroke.brush, BrushType.stamp);
    expect(stroke.stamp, StampShape.star);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('mirror drawing from the menu mirrors new strokes',
      (tester) async {
    final app = await pumpApp(tester);
    await tapMenu(tester, '对称绘画');
    expect(app.settings.mirror, isTrue);

    await drawStroke(tester);
    final stroke = app.session.drawing.strokes.single;
    expect(stroke.mirrorX, app.session.canvasSize.width / 2);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('paper color can be changed from the menu', (tester) async {
    final app = await pumpApp(tester);
    await tapMenu(tester, '画纸颜色');
    await tester.tap(find.bySemanticsLabel('奶油'));
    await tester.pumpAndSettle();
    expect(app.session.drawing.paper.toARGB32(), AppTheme.papers[1].toARGB32());
    expect(app.settings.paper.toARGB32(), AppTheme.papers[1].toARGB32());
    await tester.pump(const Duration(seconds: 1)); // let the autosave run
  });

  testWidgets('drawing a rectangle with the shape tool', (tester) async {
    final app = await pumpApp(tester);
    await openTools(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '矩形'));
    await tester.pumpAndSettle();
    expect(app.settings.shape, ShapeKind.rectangle);
    await closeTools(tester);

    await tester.dragFrom(const Offset(80, 150), const Offset(120, 100));
    await tester.pump();
    final stroke = app.session.drawing.strokes.single;
    expect(stroke.shape, ShapeKind.rectangle);
    expect(stroke.shapeTo! - stroke.shapeFrom!, const Offset(120, 100));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('fill only works for closed shapes', (tester) async {
    final app = await pumpApp(tester);
    final fill = find.widgetWithText(ChoiceChip, '填充');
    await openTools(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '直线'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(fill);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(fill).onSelected, isNull,
        reason: 'a line cannot be filled');

    app.settings.shape = ShapeKind.ellipse;
    await tester.pumpAndSettle();
    await tester.tap(fill);
    await tester.pumpAndSettle();
    expect(app.settings.fill, isTrue);
  });

  testWidgets('long-pressing with the eraser shows its range circle',
      (tester) async {
    final app = await pumpApp(tester);
    app.settings.brush = BrushType.eraser;
    await tester.pumpAndSettle();
    final overlay = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.foregroundPainter)
        .whereType<CanvasOverlayPainter>()
        .single;

    final gesture = await tester.startGesture(const Offset(150, 250));
    await tester.pump(const Duration(milliseconds: 100));
    expect(overlay.eraserCursor.value, isNull, reason: 'not yet a long press');

    await tester.pump(CanvasPageState.longPressDelay);
    expect(overlay.eraserCursor.value, isNotNull, reason: 'circle shows');

    await gesture.moveTo(const Offset(180, 260));
    await tester.pump();
    expect(overlay.eraserCursor.value, isNotNull);
    expect(CanvasOverlayPainter.eraserRadius(app.settings),
        app.settings.size * BrushType.eraser.sizeFactor / 2,
        reason: 'the circle matches the eraser width');

    await gesture.up();
    await tester.pump();
    expect(overlay.eraserCursor.value, isNull, reason: 'hidden on release');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a quick eraser stroke does not show the circle',
      (tester) async {
    final app = await pumpApp(tester);
    app.settings.brush = BrushType.eraser;
    await tester.pumpAndSettle();
    final overlay = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.foregroundPainter)
        .whereType<CanvasOverlayPainter>()
        .single;
    await drawStroke(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(overlay.eraserCursor.value, isNull);
  });

  testWidgets('the cute font is the default and can be changed',
      (tester) async {
    final app = await pumpApp(tester);
    TextStyle? body() => Theme.of(tester.element(find.byType(AppBar).first))
        .textTheme
        .bodyMedium;
    expect(body()?.fontFamily, 'ZCOOLKuaiLe');

    await openSettings(tester);
    final handwriting = find.bySemanticsLabel('手写体', skipOffstage: false);
    await tester.ensureVisible(handwriting);
    await tester.pumpAndSettle();
    await tester.tap(handwriting);
    await tester.pumpAndSettle();
    expect(app.settings.fontId.value, 'longcang');
    expect(body()?.fontFamily, 'LongCang');
  });

  testWidgets('adding bold, centered text with the text tool', (tester) async {
    final app = await pumpApp(tester);
    app.settings.brush = BrushType.text;
    await tester.pumpAndSettle();
    await openTools(tester);
    expect(find.textContaining('点画布添加文字'), findsOneWidget,
        reason: 'the drawer explains the text tool');
    await closeTools(tester);

    await tester.tapAt(const Offset(150, 250));
    await tester.pumpAndSettle();
    expect(find.text('添加文字'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '你好呀');
    await tester.tap(find.byTooltip('加粗'));
    await tester.tap(find.byTooltip('居中'));
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final item = app.session.drawing.strokes.single;
    expect(item.text!.text, '你好呀');
    expect(item.text!.bold, isTrue);
    expect(item.text!.align, TextAlign.center);
    expect(app.settings.textStyle!.bold, isTrue,
        reason: 'next text starts bold too');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tapping text edits it; dragging moves it; undo puts it back',
      (tester) async {
    final app = await pumpApp(tester);
    app.settings.brush = BrushType.text;
    final canvasOrigin =
        tester.getTopLeft(find.byKey(CanvasPageState.paperKey));
    app.session.drawing.add(Stroke.text(
      anchor: const Offset(40, 60),
      content: const TextContent(text: 'AB', fontSize: 30),
      color: Colors.black,
    ));
    await tester.pumpAndSettle();
    final onText = canvasOrigin + const Offset(55, 75);

    // Drag it 60px right.
    await tester.dragFrom(onText, const Offset(60, 0));
    await tester.pumpAndSettle();
    final moved = app.session.drawing.strokes.single;
    expect(moved.anchor.dx, closeTo(100, 1));
    expect(find.text('编辑文字'), findsNothing, reason: 'a drag does not edit');

    // Tap it: the editor opens with a delete button.
    await tester.tapAt(onText + const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(find.text('编辑文字'), findsOneWidget);
    await tester.tap(find.byTooltip('删除文字'));
    await tester.pumpAndSettle();
    expect(app.session.drawing.strokes, isEmpty);

    // Undo the delete, then the whole drag.
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pump();
    expect(app.session.drawing.strokes.single.anchor, const Offset(40, 60));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the text editor meets accessibility guidelines',
      (tester) async {
    final handle = tester.ensureSemantics();
    final app = await pumpApp(tester, screen: const Size(393, 1200));
    app.settings.brush = BrushType.text;
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(150, 300));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('send offers PNG, JPG, PDF and the editable painting file',
      (tester) async {
    await pumpApp(tester);
    await tapMenu(tester, '发送给别人');
    expect(find.text('选择发送格式'), findsOneWidget);
    for (final label in ['图片（PNG）', '图片（JPG）', 'PDF 文档', '画作文件（可继续画）']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Close without sending.
    await tester.tapAt(const Offset(200, 60));
    await tester.pumpAndSettle();
    expect(find.text('选择发送格式'), findsNothing);
  });

  testWidgets('print is in the canvas menu and gallery cards',
      (tester) async {
    final app = await createTestApp();
    await app.store.save(sampleDoc('p', DateTime(2026, 2, 2)), tinyPng);
    await pumpApp(tester, app: app);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('打印'), findsOneWidget);
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();

    await openTab(tester, 1);
    expect(find.byTooltip('导入画作文件'), findsOneWidget);
    await tester.tap(cardMenu());
    await tester.pumpAndSettle();
    expect(find.text('发送给别人'), findsOneWidget);
    expect(find.text('打印'), findsOneWidget);
  });

  group('Top-right painting actions', () {
    IconButton button(WidgetTester tester, String tooltip) =>
        tester.widget<IconButton>(find.ancestor(
            of: find.byTooltip(tooltip), matching: find.byType(IconButton)));

    testWidgets('new, save and clear are buttons; delete is in the ⋮ menu',
        (tester) async {
      await pumpApp(tester);
      for (final t in ['新建画作', '保存画作', '清空画布', '更多']) {
        expect(find.byTooltip(t), findsOneWidget, reason: t);
      }
      expect(find.byTooltip('删除这幅画'), findsNothing,
          reason: 'delete moved into the menu');
      // Nothing to save or clear on a blank page yet.
      for (final t in ['保存画作', '清空画布']) {
        expect(button(tester, t).onPressed, isNull, reason: t);
      }
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      final delete = find.widgetWithText(ListTile, '删除这幅画');
      await tester.ensureVisible(delete);
      expect(tester.widget<ListTile>(delete).enabled, isFalse);
      await tester.tapAt(const Offset(30, 600)); // close the menu
      await tester.pumpAndSettle();

      await drawStroke(tester);
      for (final t in ['保存画作', '清空画布']) {
        expect(button(tester, t).onPressed, isNotNull, reason: t);
      }
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the ⋮ menu unfolds from the top, in groups', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pump(); // first frame of the animation
      await tester.pump(const Duration(milliseconds: 100));
      final menu = find.ancestor(
          of: find.text('发送给别人'), matching: find.byType(SizeTransition));
      final midHeight = tester.getSize(menu).height;
      await tester.pumpAndSettle();
      final fullHeight = tester.getSize(menu).height;
      expect(midHeight, lessThan(fullHeight), reason: 'grows downward');
      expect(tester.getTopLeft(menu).dy, lessThan(100),
          reason: 'anchored under the app bar');
      for (final group in ['分享', '视图', '画纸', '画作']) {
        expect(find.text(group), findsOneWidget, reason: group);
      }
    });

    testWidgets('save saves at once and says so', (tester) async {
      final app = await pumpApp(tester);
      await drawStroke(tester);
      await tester.tap(find.byTooltip('保存画作'));
      await tester.pump();
      await tester.pump();
      expect((await app.store.list()), hasLength(1));
      expect(find.text('已保存到“我的画作”'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('clear asks first and can be undone', (tester) async {
      final app = await pumpApp(tester);
      await drawStroke(tester);
      await tester.tap(find.byTooltip('清空画布'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(app.session.drawing.strokes, isEmpty);
      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.pump();
      expect(app.session.drawing.strokes, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('delete asks first, removes the painting, gives a new page',
        (tester) async {
      final app = await pumpApp(tester);
      await drawStroke(tester);
      await tester.pump(const Duration(seconds: 1)); // autosaved
      final id = app.session.id;
      expect(await app.store.list(), hasLength(1));

      await tapMenu(tester, '删除这幅画');
      expect(find.text('删除这幅画？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(app.session.id, isNot(id));
      expect(app.session.drawing.strokes, isEmpty);
      expect(await app.store.list(), isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('undo and redo start at the top right, for the right thumb',
        (tester) async {
      await pumpApp(tester);
      final undo = tester.getCenter(find.byIcon(Icons.undo_rounded));
      final paper = tester.getRect(find.byKey(CanvasPageState.paperKey));
      expect(undo.dx, greaterThan(paper.right - 150));
      expect(undo.dy, lessThan(paper.top + 80));
    });

    testWidgets('settings opens from the ⋮ menu with a back arrow',
        (tester) async {
      await pumpApp(tester);
      expect(find.byType(NavigationDestination), findsNWidgets(2),
          reason: 'canvas and gallery only');
      await openSettings(tester);
      expect(find.text('主题'), findsOneWidget);
      await leaveSettings(tester);
      expect(find.text('主题'), findsNothing);
      expect(find.byKey(CanvasPageState.toolsButtonKey), findsOneWidget);
    });

    testWidgets('settings is also in the gallery ⋮ menu', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 1);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    });
  });

  testWidgets('with the tools tucked away, the paper fills the screen',
      (tester) async {
    await pumpApp(tester);
    final paper = tester.getSize(find.byKey(CanvasPageState.paperKey));
    // 829 tall screen minus app bar and bottom bar.
    expect(paper.height, greaterThan(600));
    expect(paper.width, greaterThan(370));
  });

  testWidgets('switching theme recolors the app and is remembered',
      (tester) async {
    final app = await pumpApp(tester);
    await openSettings(tester);
    // The theme cards scroll sideways; mint is off-screen at first.
    final mint = find.bySemanticsLabel('薄荷糖', skipOffstage: false);
    await tester.ensureVisible(mint);
    await tester.pumpAndSettle();
    await tester.tap(mint);
    await tester.pumpAndSettle();

    expect(app.settings.themeId.value, 'mint');
    final context = tester.element(find.byType(AppBar).first);
    expect(CuteTheme.of(context).spec.id, 'mint');
  });

  testWidgets('a stroke autosaves and shows up in My Paintings with its date',
      (tester) async {
    final app = await pumpApp(tester);

    await drawStroke(tester);
    await tester.pump(const Duration(seconds: 1));
    final saved = await app.store.list();
    expect(saved, hasLength(1));

    await openTab(tester, 1);
    final year = DateTime.now().year;
    expect(inGallery(find.text('$year年 (1)')), findsOneWidget);
    expect(inGallery(find.text('正在画')), findsOneWidget);
  });

  testWidgets('the year filter shows only that year', (tester) async {
    final app = await createTestApp();
    await app.store.save(sampleDoc('a', DateTime(2025, 6, 1)), tinyPng);
    await app.store.save(sampleDoc('b', DateTime(2026, 2, 1)), tinyPng);
    await app.store.save(sampleDoc('c', DateTime(2026, 9, 1)), tinyPng);
    await pumpApp(tester, app: app);

    await openTab(tester, 1);
    expect(inGallery(find.byType(Card)), findsNWidgets(3));

    await tester.tap(inGallery(find.text('2025年 (1)')));
    await tester.pumpAndSettle();
    expect(inGallery(find.byType(Card)), findsOneWidget);
    expect(inGallery(find.text('2025-06-01')), findsOneWidget);

    await tester.tap(inGallery(find.text('全部 (3)')));
    await tester.pumpAndSettle();
    expect(inGallery(find.byType(Card)), findsNWidgets(3));
  });

  testWidgets('tapping a painting reopens it on the canvas', (tester) async {
    final app = await createTestApp();
    await app.store
        .save(sampleDoc('old', DateTime(2025, 6, 1), strokes: 4), tinyPng);
    await pumpApp(tester, app: app);

    await openTab(tester, 1);
    await tester.tap(inGallery(find.text('2025-06-01')));
    await tester.pumpAndSettle();

    expect(app.session.id, 'old');
    expect(app.session.drawing.strokes, hasLength(4));
    expect(find.text('靖瑶的画板'), findsOneWidget);
  });

  testWidgets('deleting asks first, then removes the painting',
      (tester) async {
    final app = await createTestApp();
    await app.store.save(sampleDoc('x', DateTime(2026, 1, 1)), tinyPng);
    await pumpApp(tester, app: app);

    await openTab(tester, 1);
    await tester.tap(cardMenu());
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除这幅画？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(await app.store.list(), isEmpty);
    expect(inGallery(find.textContaining('还没有画作')), findsOneWidget);
  });

  testWidgets('switching to English relabels the app and is remembered',
      (tester) async {
    final app = await pumpApp(tester);

    await openSettings(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget,
        reason: 'the open settings page switches language at once');
    expect(app.settings.locale.value.languageCode, 'en');
    await leaveSettings(tester);

    expect(find.text('Canvas'), findsOneWidget);
    expect(find.text('My Paintings'), findsOneWidget);
    expect(find.text('JingyaoPaint'), findsOneWidget);
    expect(find.text('Brushes · Colors'), findsOneWidget);
    await tester.tap(find.byKey(CanvasPageState.toolsButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Highlighter'), findsOneWidget);
  });

  // Accessibility: every theme, every screen, checked with Flutter's own
  // guidelines (WCAG text contrast, 48x48 tap targets, labelled buttons).
  for (final id in kThemeIds) {
    testWidgets('theme $id meets accessibility guidelines on every screen',
        (tester) async {
      final handle = tester.ensureSemantics();
      final app = await createTestApp(prefs: {'flutter.theme': id});
      await app.store.save(sampleDoc('a', DateTime(2026, 3, 1)), tinyPng);
      // Tall enough that no text is half-hidden at a scroll edge: the
      // contrast check would measure the clipped background instead.
      await pumpApp(tester, app: app, screen: const Size(393, 1200));

      Future<void> checkAll(String where) async {
        await expectLater(tester, meetsGuideline(textContrastGuideline),
            reason: '$id $where text contrast');
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline),
            reason: '$id $where tap targets');
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline),
            reason: '$id $where labels');
      }

      for (final tab in [0, 1]) {
        await openTab(tester, tab);
        await checkAll('tab $tab');
      }
      await openSettings(tester);
      await checkAll('settings');
      await leaveSettings(tester);
      // And the tools drawer.
      await openTab(tester, 0);
      await openTools(tester);
      await expectLater(tester, meetsGuideline(textContrastGuideline),
          reason: '$id tools text contrast');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline),
          reason: '$id tools tap targets');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline),
          reason: '$id tools labels');
      handle.dispose();
    });
  }

  group('Tablets and landscape', () {
    const screens = {
      'tablet landscape 1280x800': Size(1280, 800),
      'tablet portrait 800x1280': Size(800, 1280),
      'phone landscape 851x393': Size(851, 393),
      'small tablet portrait 600x960': Size(600, 960),
    };

    for (final MapEntry(key: name, value: screen) in screens.entries) {
      testWidgets('$name: side rail, sensible layout, no overflow',
          (tester) async {
        final app = await createTestApp();
        await app.store.save(sampleDoc('a', DateTime(2026, 3, 1)), tinyPng);
        app.settings.brush = BrushType.stamp; // tallest tool panel
        await pumpApp(tester, app: app, screen: screen);

        expect(find.byType(NavigationRail), findsOneWidget,
            reason: 'wide screens use a side rail');
        expect(find.byType(NavigationBar), findsNothing);

        // With the tools tucked away, the paper gets nearly the whole page.
        final paper = tester.getRect(find.byKey(CanvasPageState.paperKey));
        expect(paper.height, greaterThan(screen.height * 0.7));
        expect(paper.width, greaterThan(screen.width * 0.8));

        // The drawer slides in from the right and fits on screen.
        await openTools(tester);
        final drawer = tester.getRect(find.text('画笔与颜色'));
        expect(drawer.left, greaterThan(screen.width * 0.4));
        expect(tester.takeException(), isNull, reason: '$name drawer');
        await closeTools(tester);

        for (final tab in [1, 0]) {
          await openTab(tester, tab);
          expect(tester.takeException(), isNull, reason: '$name tab $tab');
        }
        await openSettings(tester);
        expect(tester.takeException(), isNull, reason: '$name settings');
        await leaveSettings(tester);
      });
    }

    testWidgets('a phone in portrait keeps the bottom bar', (tester) async {
      await pumpApp(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('rotating never cuts the drawing off', (tester) async {
      final app = await pumpApp(tester, screen: const Size(1280, 800));
      final paperFinder = find.byKey(CanvasPageState.paperKey);
      // Draw a long line across the wide landscape paper.
      final p = tester.getRect(paperFinder);
      await tester.dragFrom(p.centerLeft + const Offset(40, 0),
          Offset(p.width - 80, 0));
      await tester.pump();
      final drawn = app.session.drawing.contentBounds;
      expect(drawn.right, greaterThan(800), reason: 'wider than portrait');

      // Turn the tablet to portrait.
      tester.view.physicalSize = const Size(800, 1280) * 2;
      await tester.pumpAndSettle();
      final paper = app.session.canvasSize;
      expect(paper.width, greaterThanOrEqualTo(drawn.right),
          reason: 'the paper still holds the whole drawing');
      final shown = tester.getRect(paperFinder);
      expect(shown.right, lessThanOrEqualTo(800),
          reason: 'and is scaled to fit on screen, not cropped');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('drawing still lands under the finger on a scaled paper',
        (tester) async {
      final app = await createTestApp();
      // A painting made on a wider device, opened on a phone.
      app.session.drawing.load([
        Stroke.text(
          anchor: const Offset(1500, 100),
          content: const TextContent(text: 'far right', fontSize: 40),
          color: Colors.black,
        ),
      ]);
      await pumpApp(tester, app: app);
      final paperFinder = find.byKey(CanvasPageState.paperKey);
      final shown = tester.getRect(paperFinder);
      final scale = shown.width / app.session.canvasSize.width;
      expect(scale, lessThan(1), reason: 'big painting is scaled down');

      // Drag on screen inside the (small) paper and check where the stroke
      // landed in paper coordinates.
      final at = Offset(shown.width * 0.1, shown.height * 0.6);
      await tester.dragFrom(shown.topLeft + at, const Offset(30, 0));
      await tester.pump();
      final stroke = app.session.drawing.strokes.last;
      expect(stroke.text, isNull, reason: 'a new stroke was drawn');
      expect(stroke.points.first.x, closeTo(at.dx / scale, 2 / scale));
      expect(stroke.points.first.y, closeTo(at.dy / scale, 2 / scale));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('tablet landscape meets accessibility guidelines',
        (tester) async {
      final handle = tester.ensureSemantics();
      final app = await createTestApp();
      await app.store.save(sampleDoc('a', DateTime(2026, 3, 1)), tinyPng);
      await pumpApp(tester, app: app, screen: const Size(1280, 1000));
      Future<void> checkAll() async {
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }

      for (final tab in [0, 1]) {
        await openTab(tester, tab);
        await checkAll();
      }
      await openSettings(tester);
      await checkAll();
      await leaveSettings(tester);
      handle.dispose();
    });
  });

  for (final language in ['zh', 'en']) {
    testWidgets('fits a small 360x640 phone with large text ($language)',
        (tester) async {
      final app = await createTestApp(prefs: {'flutter.language': language});
      await app.store.save(sampleDoc('s', DateTime(2026, 1, 1)), tinyPng);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, app: app, screen: const Size(360, 640));

      app.settings.brush = BrushType.stamp; // tallest panel layout
      await tester.pumpAndSettle();
      for (final tab in [1, 0]) {
        await openTab(tester, tab);
        expect(tester.takeException(), isNull, reason: 'tab $tab');
      }
      await openSettings(tester);
      expect(tester.takeException(), isNull, reason: 'settings');
      await leaveSettings(tester);
      final canvas = tester.getSize(find.byType(CustomPaint).first);
      expect(canvas.height, greaterThan(150),
          reason: 'there must still be room to draw');
    });
  }
}
