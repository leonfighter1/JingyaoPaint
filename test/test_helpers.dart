import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:jingyao_paint/drawing/stroke.dart';
import 'package:jingyao_paint/family.dart';
import 'package:jingyao_paint/gallery/painting_store.dart';
import 'package:jingyao_paint/music/background_music.dart';
import 'package:jingyao_paint/music/music_library.dart';
import 'package:jingyao_paint/painting_session.dart';
import 'package:jingyao_paint/settings.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A real 1x1 PNG, so code that expects image bytes gets valid ones.
final tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

/// Thumbnails are faked because real PNG encoding never completes under the
/// fake clock widget tests run on.
Future<Uint8List> fakeThumbnailer(
        List<Stroke> strokes, Size size, Color paper) async =>
    tinyPng;

class TestApp {
  TestApp(this.settings, this.backend, this.session);

  final AppSettings settings;
  final MemoryStoreBackend backend;
  final PaintingSession session;
  final musicFiles = MemoryMusicFiles();
  late final music = MusicLibrary(musicFiles);
  final engine = FakeMusicEngine();
  late final player =
      BackgroundMusic(settings: settings, library: music, engine: engine);

  /// The storage all kids' paintings share.
  late StoreBackend base;
  late final family = Family(
      settings: settings, backend: base, session: session, music: music);

  PaintingStore get store => session.store;
}

/// Most tests run in Chinese with the first-start setup already done, as
/// the app was used before v2.1. [prefs] can change either.
const testDefaults = <String, Object>{
  'flutter.language': 'zh',
  'flutter.onboarded': true,
};

Future<TestApp> createTestApp({
  Map<String, Object> prefs = const {},
  StoreBackend? backend,
  bool fresh = false,
}) async {
  SharedPreferences.setMockInitialValues(
      fresh ? prefs : {...testDefaults, ...prefs});
  final settings = await AppSettings.load();
  final memory = MemoryStoreBackend();
  final base = backend ?? memory;
  final session = PaintingSession(
    store: Family.storeFor(base, settings.currentKid),
    settings: settings,
    thumbnailer: fakeThumbnailer,
  );
  return TestApp(settings, memory, session)..base = base;
}

Stroke sampleStroke({BrushType brush = BrushType.pen, Color? color}) => Stroke(
      brush: brush,
      color: color ?? const Color(0xFFFF5A5F),
      size: 8,
      usesRealPressure: false,
      isComplete: true,
      points: const [
        PointVector(10, 10, 0.5),
        PointVector(40, 25, 0.6),
        PointVector(80, 60, 0.7),
      ],
    );

PaintingDoc sampleDoc(String id, DateTime created, {int strokes = 1}) =>
    PaintingDoc(
      meta: PaintingMeta(
        id: id,
        createdAt: created,
        updatedAt: created.add(const Duration(hours: 1)),
        width: 400,
        height: 300,
        strokeCount: strokes,
      ),
      strokes: [for (var i = 0; i < strokes; i++) sampleStroke()],
    );

/// A backend whose writes always fail, for testing save errors.
class FailingBackend extends MemoryStoreBackend {
  @override
  Future<void> writeText(String name, String value) async =>
      throw Exception('disk full');
}

/// Records what the background music was told to do, instead of playing.
class FakeMusicEngine implements MusicEngine {
  final List<String> calls = [];
  MusicSource? source;
  double volume = 0;
  bool loop = true;
  VoidCallback? _onComplete;

  @override
  set onComplete(VoidCallback? callback) => _onComplete = callback;

  /// The track playing reached its end.
  void finishTrack() => _onComplete?.call();

  @override
  Future<void> setLoop(bool loop) async {
    this.loop = loop;
    calls.add('loop:$loop');
  }

  /// Makes the next [play] fail, like an unplayable file.
  bool failNext = false;

  @override
  Future<void> play(MusicSource source, double volume,
      {bool loop = true}) async {
    if (failNext) {
      failNext = false;
      throw Exception('cannot play');
    }
    this.source = source;
    this.volume = volume;
    this.loop = loop;
    calls.add('play');
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
    calls.add('volume');
  }

  @override
  Future<void> dispose() async {}
}
