import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/drawing/canvas_page.dart';
import 'package:jingyao_paint/music/music_library.dart';
import 'package:jingyao_paint/share/share_actions.dart';

import 'widget_test.dart'
    show closeTools, drawStroke, leaveSettings, openSettings, openTools, pumpApp;

final _song = Uint8List.fromList(List.filled(64, 1));

/// Runs [body] as if on an iPhone or iPad. Flutter changes scrolling, page
/// transitions and text editing per platform, so the app is checked as iOS
/// too (the real iOS build runs in the GitHub iOS workflow).
void testIOS(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  group('iOS', () {
    testIOS('draws, opens the tools and Settings like on Android',
        (tester) async {
      final app = await pumpApp(tester);
      await drawStroke(tester);
      expect(app.session.drawing.strokes, hasLength(1));
      await openTools(tester);
      expect(find.text('画笔与颜色'), findsOneWidget);
      await closeTools(tester);
      await openSettings(tester);
      expect(find.text('背景音乐'), findsOneWidget);
      await leaveSettings(tester);
      expect(find.byType(CanvasPage), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testIOS('a big iPad screen gets the side rail', (tester) async {
      await pumpApp(tester, screen: const Size(1366, 1024));
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testIOS('music offers only formats Apple devices can play',
        (tester) async {
      expect(MusicLibrary.isApple, isTrue);
      final library = MusicLibrary(MemoryMusicFiles());
      for (final ok in ['a.mp3', 'b.m4a', 'c.wav', 'd.aiff', 'e.flac', 'f.caf']) {
        expect(await library.add(ok, _song), isNotNull, reason: ok);
      }
      for (final no in ['a.ogg', 'b.opus', 'c.mid', 'd.wma', 'e.webm', 'f.amr']) {
        expect(await library.add(no, _song), isNull, reason: no);
      }

      final app = await pumpApp(tester);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('上传本地音乐'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('AIFF'), findsOneWidget);
      expect(find.textContaining('MIDI'), findsNothing);
      expect(app.settings.musicOn, isFalse);
    });

    test('Android keeps the wider list of formats', () {
      expect(MusicLibrary.isApple, isFalse);
      expect(MusicLibrary.extensions, containsAll(['ogg', 'mid', 'wma']));
    });

    testWidgets('the share sheet is anchored to the page (iPad needs it)',
        (tester) async {
      await pumpApp(tester);
      final origin =
          shareOrigin(tester.element(find.byKey(CanvasPageState.paperKey)));
      expect(origin, isNotNull);
      expect(origin!.isEmpty, isFalse);
    });
  });
}
