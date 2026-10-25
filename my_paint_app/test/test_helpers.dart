import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:jingyao_paint/drawing/stroke.dart';
import 'package:jingyao_paint/gallery/painting_store.dart';
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

  PaintingStore get store => session.store;
}

Future<TestApp> createTestApp({
  Map<String, Object> prefs = const {},
  StoreBackend? backend,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final settings = await AppSettings.load();
  final memory = MemoryStoreBackend();
  final session = PaintingSession(
    store: PaintingStore(backend ?? memory),
    settings: settings,
    thumbnailer: fakeThumbnailer,
  );
  return TestApp(settings, memory, session);
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
