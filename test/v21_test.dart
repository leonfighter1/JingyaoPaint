import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/device.dart';
import 'package:jingyao_paint/drawing/canvas_page.dart';
import 'package:jingyao_paint/gallery/painting_store.dart';
import 'package:jingyao_paint/l10n.dart';
import 'package:jingyao_paint/music/background_music.dart';
import 'package:jingyao_paint/onboarding_page.dart';
import 'package:jingyao_paint/settings.dart';
import 'package:jingyao_paint/share/painting_export.dart';
import 'package:jingyao_paint/widgets/parent_gate.dart';

import 'test_helpers.dart';
import 'widget_test.dart'
    show drawStroke, inGallery, leaveSettings, openSettings, openTab, pumpApp;

/// Answers the grown-up question shown on screen.
Future<void> answerGrownUp(WidgetTester tester, {bool wrong = false}) async {
  final question =
      tester.widget<Text>(find.byKey(ParentGate.questionKey)).data!;
  final (a, b) = ParentGate.parse(question);
  await tester.enterText(
      find.descendant(
          of: find.byType(ParentGate), matching: find.byType(TextField)),
      '${wrong ? a * b + 1 : a * b}');
  await tester.tap(find.descendant(
      of: find.byType(ParentGate), matching: find.byType(FilledButton)));
  await tester.pumpAndSettle();
}

/// Types [name] into the open name dialog and saves it.
Future<void> enterName(WidgetTester tester, String name) async {
  await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      name);
  await tester.pump(); // Save turns on once there's a name
  await tester.tap(find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
  await tester.pumpAndSettle();
}

void main() {
  group('First start', () {
    testWidgets('starts in English; language, theme and name are chosen',
        (tester) async {
      final app = await createTestApp(fresh: true);
      await pumpApp(tester, app: app);
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.textContaining('Welcome!'), findsOneWidget,
          reason: 'English first');

      await tester.tap(find.text('简体中文'));
      await tester.pumpAndSettle();
      expect(find.textContaining('欢迎来画画！'), findsOneWidget,
          reason: 'the page switches language at once');

      await tester.tap(find.text('薰衣草'));
      await tester.pumpAndSettle();
      expect(app.settings.themeId.value, 'lavender');

      await tester.enterText(find.byKey(OnboardingPage.nameFieldKey), '小明');
      await tester.pump();
      expect(find.text('小明的画板'), findsOneWidget, reason: 'live preview');
      await tester.ensureVisible(find.byKey(OnboardingPage.startKey));
      await tester.tap(find.byKey(OnboardingPage.startKey));
      await tester.pumpAndSettle();

      expect(find.byType(CanvasPage), findsOneWidget);
      expect(find.text('小明的画板'), findsOneWidget, reason: 'the title');
      expect(app.settings.kidName, '小明');
      expect(app.settings.onboarded.value, isTrue);
    });

    testWidgets('the setup is skipped once done', (tester) async {
      await pumpApp(tester);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.text('靖瑶的画板'), findsOneWidget);
    });
  });

  group('Painting names', () {
    testWidgets('new paintings are numbered in the app language and renamed',
        (tester) async {
      final app = await pumpApp(tester);
      await app.session.restoreLast();
      await tester.pump();
      expect(app.session.name, '我的画作 1');
      await drawStroke(tester);
      await tester.pump(const Duration(seconds: 1)); // autosave

      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await tester.pumpAndSettle();
      expect(app.session.name, '我的画作 2');
      expect(find.text('我的画作 2'), findsOneWidget, reason: 'in the title');

      // Tapping the title renames the open painting.
      await tester.tap(find.text('我的画作 2'));
      await tester.pumpAndSettle();
      await enterName(tester, '大恐龙');
      expect(app.session.name, '大恐龙');
      expect(find.text('大恐龙'), findsOneWidget);
      await drawStroke(tester);
      await tester.pump(const Duration(seconds: 1));
      final names = [for (final m in await app.store.list()) m.name];
      expect(names, containsAll(['我的画作 1', '大恐龙']));
    });

    testWidgets('in English the default is "My painting 1"', (tester) async {
      final app = await createTestApp(prefs: {'flutter.language': 'en'});
      await pumpApp(tester, app: app);
      await app.session.restoreLast();
      expect(app.session.name, 'My painting 1');
    });

    testWidgets('a painting can be renamed from its gallery card',
        (tester) async {
      final app = await createTestApp();
      await app.store.save(
          sampleDoc('a', DateTime(2026, 2, 1)).withName('小猫'), tinyPng);
      await pumpApp(tester, app: app);
      await openTab(tester, 1);
      expect(inGallery(find.text('小猫')), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '重命名'));
      await tester.pumpAndSettle();
      await enterName(tester, '小狗');
      expect(inGallery(find.text('小狗')), findsOneWidget);
      expect((await app.store.load('a'))!.meta.name, '小狗',
          reason: 'saved in the painting too');
    });

    test('paintings from before v2.1 get numbers, oldest first', () async {
      final app = await createTestApp();
      await app.store.save(sampleDoc('new', DateTime(2026, 5, 1)), tinyPng);
      await app.store.save(sampleDoc('old', DateTime(2025, 1, 1)), tinyPng);
      await app.session.restoreLast();
      final byId = {for (final m in await app.store.list()) m.id: m.name};
      expect(byId, {'old': '我的画作 1', 'new': '我的画作 2'});
      expect((await app.store.load('old'))!.meta.name, '我的画作 1');
      expect(app.session.name, '我的画作 3', reason: 'the blank page');
    });

    test('exported files are named after the painting', () {
      final doc = sampleDoc('a', DateTime(2026, 1, 1)).withName('My cat: Tom?');
      expect(exportName(doc, ExportFormat.png), 'My cat_ Tom_.png');
    });
  });

  group('Kids', () {
    testWidgets('adding a kid needs a grown-up and gives them their own paintings',
        (tester) async {
      final app = await createTestApp();
      await app.store.save(sampleDoc('jy', DateTime(2026, 1, 1)), tinyPng);
      await pumpApp(tester, app: app);
      await openSettings(tester);

      await tester.tap(find.text('添加小画家'));
      await tester.pumpAndSettle();
      await answerGrownUp(tester, wrong: true);
      expect(find.text('不对哦，换一道题再试试'), findsOneWidget);
      await answerGrownUp(tester);
      await enterName(tester, '小明');

      expect(app.settings.kids.map((k) => k.name), ['靖瑶', '小明']);
      expect(app.settings.kidName, '小明');
      expect(await app.session.store.list(), isEmpty,
          reason: "小明 starts with no paintings");

      // Back to 靖瑶: her painting is still there.
      await tester.tap(find.widgetWithText(ListTile, '靖瑶'));
      await tester.pumpAndSettle();
      expect(app.settings.kidName, '靖瑶');
      expect([for (final m in await app.session.store.list()) m.id], ['jy']);
      await leaveSettings(tester);
      expect(find.text('靖瑶的画板'), findsOneWidget);
    });

    testWidgets('deleting a kid removes their paintings; the last one stays',
        (tester) async {
      final app = await createTestApp();
      await pumpApp(tester, app: app);
      final kid = await app.family.addKid('小明');
      await app.session.store.save(sampleDoc('xm', DateTime(2026, 1, 1)), tinyPng);
      expect(app.base is MemoryStoreBackend, isTrue);
      final memory = app.base as MemoryStoreBackend;
      expect(memory.files.keys, contains('${kid.storePrefix}xm.json'));

      await openSettings(tester);
      await tester.tap(find.descendant(
          of: find.widgetWithText(ListTile, '小明'),
          matching: find.byTooltip('删除')));
      await tester.pumpAndSettle();
      await answerGrownUp(tester);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(app.settings.kids.map((k) => k.name), ['靖瑶']);
      expect(memory.files.keys.where((k) => k.startsWith(kid.storePrefix)),
          isEmpty);
      expect(find.byTooltip('删除'), findsNothing,
          reason: 'the last kid has no delete button');
    });

    testWidgets('resetting the app asks a grown-up, then starts over',
        (tester) async {
      final app = await createTestApp();
      await app.store.save(sampleDoc('a', DateTime(2026, 1, 1)), tinyPng);
      await app.music.add('song.mp3', tinyPng);
      await pumpApp(tester, app: app);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('重置整个应用'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('重置整个应用'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重置整个应用'));
      await tester.pumpAndSettle();
      await answerGrownUp(tester);
      await tester.tap(find.widgetWithText(FilledButton, '重置'));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.textContaining('Welcome!'), findsOneWidget,
          reason: 'English again');
      expect(await app.session.store.list(), isEmpty);
      expect(app.music.added, isEmpty);
      expect(app.settings.kids.single.name, isEmpty);
    });

    testWidgets('the grown-up check can be cancelled', (tester) async {
      await pumpApp(tester);
      final context = tester.element(find.byType(CanvasPage));
      final answer = askGrownUp(context, random: math.Random(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
    });
  });

  group('Music play order', () {
    testWidgets('in order and shuffle move on when a track ends; repeat loops',
        (tester) async {
      final app = await createTestApp();
      final player = BackgroundMusic(
        settings: app.settings,
        library: app.music,
        engine: app.engine,
        random: math.Random(3),
      )..start();
      addTearDown(player.dispose);
      app.settings.musicOn = true;
      await player.settled;
      expect(app.engine.loop, isTrue, reason: 'repeat one by default');

      app.settings.musicMode = MusicMode.sequence;
      await player.settled;
      expect(app.engine.loop, isFalse);
      app.engine.finishTrack();
      await player.settled;
      expect(app.settings.musicTrack, 'builtin:twinkle');
      app.engine.finishTrack();
      await player.settled;
      expect(app.settings.musicTrack, 'builtin:sunny', reason: 'wraps around');

      await app.music.add('mine.mp3', tinyPng);
      app.settings.musicMode = MusicMode.shuffle;
      await player.settled;
      for (var i = 0; i < 5; i++) {
        final before = app.settings.musicTrack;
        app.engine.finishTrack();
        await player.settled;
        expect(app.settings.musicTrack, isNot(before),
            reason: 'shuffle picks another track');
      }
      expect(app.engine.calls.where((c) => c == 'play').length, greaterThan(5));
    });

    testWidgets('the play order is chosen in Settings', (tester) async {
      final app = await pumpApp(tester);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('随机播放'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('随机播放'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('随机播放'));
      await tester.pumpAndSettle();
      expect(app.settings.musicMode, MusicMode.shuffle);
    });
  });

  group('Texts for each device', () {
    tearDown(() => Device.debugOverride = null);

    test('printing explains how to come back on each device', () {
      const s = S('zh');
      Device.debugOverride = const Device(DeviceKind.android);
      expect(s.printHint, contains('返回键'));
      Device.debugOverride = const Device(DeviceKind.apple);
      expect(s.printHint, contains('左上角'));
      Device.debugOverride =
          const Device(DeviceKind.web, browser: 'Safari');
      expect(s.printHint, contains('浏览器'));
      Device.debugOverride = const Device(DeviceKind.desktop, desktopOs: true);
      expect(s.printHint, contains('电脑'));
    });

    test('About names the browser on the web', () {
      Device.debugOverride = const Device(DeviceKind.web, browser: 'Safari');
      expect(const S('en').runsOn, 'web version · Safari');
      expect(const S('zh').aboutBody, contains('浏览器'));
      Device.debugOverride = const Device(DeviceKind.apple);
      expect(const S('en').runsOn, 'for iPhone and iPad');
      expect(const S('zh').saveToGallery, '保存到“照片”');
    });

    test('a mouse gets the scroll-wheel hint', () {
      Device.debugOverride =
          const Device(DeviceKind.web, browser: 'Chrome', desktopOs: true);
      expect(const S('en').pinchHint, contains('scroll the wheel'));
      Device.debugOverride = const Device(DeviceKind.android);
      expect(const S('en').pinchHint, isNot(contains('wheel')));
    });
  });
}

extension on PaintingDoc {
  PaintingDoc withName(String name) =>
      PaintingDoc(meta: meta.copyWith(name: name), strokes: strokes, paper: paper);
}
