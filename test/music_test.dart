import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/music/music_library.dart';

import 'test_helpers.dart';
import 'widget_test.dart' show openSettings, pumpApp, tapMenu;

final _song = Uint8List.fromList(List.filled(64, 1));

void main() {
  group('Music library', () {
    test('has the built-in tracks, and finds the first for unknown ids', () {
      final library = MusicLibrary(MemoryMusicFiles());
      expect([for (final t in library.tracks) t.id],
          ['builtin:sunny', 'builtin:twinkle']);
      expect(library.trackById('file:gone.mp3').id, 'builtin:sunny');
    });

    test('adds common music formats and refuses other files', () async {
      final library = MusicLibrary(MemoryMusicFiles());
      for (final name in ['a.mp3', 'b.M4A', 'c.ogg', 'd.flac', 'e.wav']) {
        expect(await library.add(name, _song), isNotNull, reason: name);
      }
      expect(await library.add('notes.txt', _song), isNull);
      expect(await library.add('noext', _song), isNull);
      expect(await library.add('empty.mp3', Uint8List(0)), isNull);
      expect(library.added, hasLength(5));
    });

    test('a name in use gets a number instead of overwriting', () async {
      final library = MusicLibrary(MemoryMusicFiles());
      await library.add('song.mp3', _song);
      final second = await library.add('song.mp3', _song);
      expect(second!.name, 'song (2).mp3');
      await library.remove(library.trackById('file:song.mp3'));
      expect([for (final t in library.added) t.name], ['song (2).mp3']);
    });

    test('added music is still there after a restart', () async {
      final files = MemoryMusicFiles();
      await MusicLibrary(files).add('keep.mp3', _song);
      final reopened = MusicLibrary(files);
      await reopened.load();
      expect(reopened.trackById('file:keep.mp3').name, 'keep.mp3');
    });
  });

  group('Background music player', () {
    testWidgets('is quiet until switched on, then loops the chosen track',
        (tester) async {
      final app = await createTestApp();
      app.player.start();
      addTearDown(app.player.dispose);
      await app.player.settled;
      expect(app.engine.calls, isEmpty, reason: 'off by default');

      app.settings.musicOn = true;
      await app.player.settled;
      expect(app.engine.calls, ['play']);
      expect((app.engine.source! as AssetMusic).path, 'music/sunny_walk.wav');
      expect(app.engine.volume, 0.4);

      app.settings.musicVolume = 0.8;
      await app.player.settled;
      expect(app.engine.volume, 0.8);

      app.settings.musicTrack = 'builtin:twinkle';
      await app.player.settled;
      expect((app.engine.source! as AssetMusic).path,
          'music/twinkle_lullaby.wav');

      app.settings.musicOn = false;
      await app.player.settled;
      expect(app.engine.calls.last, 'pause');
    });

    testWidgets('pauses in the background and picks up again on return',
        (tester) async {
      final app = await createTestApp();
      app.settings.musicOn = true;
      app.player.start();
      addTearDown(app.player.dispose);
      await app.player.settled;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await app.player.settled;
      expect(app.engine.calls, ['play'], reason: 'a dialog on top is fine');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await app.player.settled;
      expect(app.engine.calls.last, 'pause');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await app.player.settled;
      expect(app.engine.calls.last, 'resume');
    });

    testWidgets('an unplayable file falls back to a built-in track',
        (tester) async {
      final app = await createTestApp();
      final track = await app.music.add('broken.mp3', _song);
      Object? reported;
      app.player.onError = (e) => reported = e;
      app.player.start();
      addTearDown(app.player.dispose);
      app.engine.failNext = true;
      app.settings
        ..musicTrack = track!.id
        ..musicOn = true;
      await app.player.settled;
      await app.player.settled;
      expect(reported, isNotNull);
      expect(app.settings.musicTrack, 'builtin:sunny');
      expect(app.engine.source, isA<AssetMusic>());
    });
  });

  group('Music settings', () {
    Future<void> scrollToMusic(WidgetTester tester) async {
      await tester.scrollUntilVisible(find.text('上传本地音乐'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }

    testWidgets('switch, volume and track choice are in Settings',
        (tester) async {
      final app = await createTestApp();
      await app.music.add('my song.mp3', _song);
      await pumpApp(tester, app: app);
      await openSettings(tester);
      await scrollToMusic(tester);
      expect(find.text('背景音乐'), findsOneWidget);
      expect(find.text('阳光散步'), findsOneWidget);
      expect(find.text('my song.mp3'), findsOneWidget);
      expect(find.textContaining('MP3'), findsOneWidget, reason: 'formats');

      await tester.tap(find.widgetWithText(SwitchListTile, '播放背景音乐'));
      await tester.pumpAndSettle();
      expect(app.settings.musicOn, isTrue);
      await tester.tap(find.widgetWithText(SwitchListTile, '播放背景音乐'));
      await tester.pumpAndSettle();
      expect(app.settings.musicOn, isFalse);

      // Picking a track plays it.
      await tester.tap(find.text('小星星摇篮曲'));
      await tester.pumpAndSettle();
      expect(app.settings.musicTrack, 'builtin:twinkle');
      expect(app.settings.musicOn, isTrue);

      final volume = find.descendant(
          of: find.ancestor(
              of: find.byIcon(Icons.volume_up_rounded), matching: find.byType(Row)),
          matching: find.byType(Slider));
      await tester.drag(volume, const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(app.settings.musicVolume, greaterThan(0.4));
    });

    testWidgets('deleting the playing added track goes back to a built-in one',
        (tester) async {
      final app = await createTestApp();
      final track = await app.music.add('mine.ogg', _song);
      app.settings.musicTrack = track!.id;
      await pumpApp(tester, app: app);
      await openSettings(tester);
      await scrollToMusic(tester);
      await tester.tap(find.descendant(
          of: find.widgetWithText(ListTile, 'mine.ogg'),
          matching: find.byIcon(Icons.delete_outline_rounded)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(find.text('mine.ogg'), findsNothing);
      expect(app.music.added, isEmpty);
      expect(app.settings.musicTrack, 'builtin:sunny');
    });

    testWidgets('the ⋮ menu has a quick music switch', (tester) async {
      final app = await pumpApp(tester);
      await tapMenu(tester, '背景音乐');
      expect(app.settings.musicOn, isTrue);
      await tapMenu(tester, '背景音乐');
      expect(app.settings.musicOn, isFalse);
    });
  });
}
