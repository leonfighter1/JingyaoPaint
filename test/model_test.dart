import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/drawing/stroke.dart';
import 'package:jingyao_paint/gallery/painting_store.dart';
import 'package:jingyao_paint/gallery/store_backend_io.dart';
import 'package:jingyao_paint/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  group('Stroke', () {
    test('survives a JSON round trip', () {
      final original = sampleStroke(
          brush: BrushType.highlighter, color: const Color(0x80123456));
      final copy = Stroke.fromJson(original.toJson());

      expect(copy.brush, BrushType.highlighter);
      expect(copy.color.toARGB32(), 0x80123456);
      expect(copy.size, original.size);
      expect(copy.isComplete, isTrue);
      expect(copy.points.map((p) => (p.x, p.y, p.pressure)),
          original.points.map((p) => (p.x, p.y, p.pressure)));
    });

    test('unknown brush names fall back to pen', () {
      final json = sampleStroke().toJson()..['brush'] = 'crayon';
      expect(Stroke.fromJson(json).brush, BrushType.pen);
    });
  });

  group('PaintingStore', () {
    test('lists newest edits first and deletes', () async {
      final store = PaintingStore(MemoryStoreBackend());
      await store.save(sampleDoc('old', DateTime(2025, 3, 1)), tinyPng);
      await store.save(sampleDoc('new', DateTime(2026, 5, 1)), tinyPng);

      expect((await store.list()).map((m) => m.id), ['new', 'old']);
      expect((await store.load('old'))!.strokes, hasLength(1));
      expect(await store.thumbnail('old'), tinyPng);

      await store.delete('old');
      expect((await store.list()).map((m) => m.id), ['new']);
      expect(await store.load('old'), isNull);
      expect(await store.thumbnail('old'), isNull);
    });

    test('re-saving a painting replaces it instead of duplicating', () async {
      final store = PaintingStore(MemoryStoreBackend());
      await store.save(sampleDoc('a', DateTime(2026)), tinyPng);
      await store.save(sampleDoc('a', DateTime(2026), strokes: 3), tinyPng);

      final list = await store.list();
      expect(list, hasLength(1));
      expect(list.single.strokeCount, 3);
    });

    test('a corrupt index starts empty instead of crashing', () async {
      final backend = MemoryStoreBackend()..files['index.json'] = '{oops';
      expect(await PaintingStore(backend).list(), isEmpty);
    });

    test('works on real files, including Chinese text', () async {
      final dir = await Directory.systemTemp.createTemp('paint_test');
      addTearDown(() => dir.delete(recursive: true));
      final backend = FileStoreBackend(Future.value(dir));

      await backend.writeText('note.json', '靖瑶的画板');
      expect(await backend.readText('note.json'), '靖瑶的画板');

      final store = PaintingStore(backend);
      await store.save(sampleDoc('f', DateTime(2026, 1, 2)), tinyPng);
      final reopened = PaintingStore(FileStoreBackend(Future.value(dir)));
      expect((await reopened.list()).single.id, 'f');
      expect(await reopened.thumbnail('f'), tinyPng);
      expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    });
  });

  group('AppSettings', () {
    test('defaults to Chinese, pen and black', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      expect(settings.locale.value.languageCode, 'zh');
      expect(settings.brush, BrushType.pen);
      expect(settings.color.toARGB32(), Colors.black.toARGB32());
    });

    test('remembers brush, color, per-brush size and language', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load()
        ..brush = BrushType.marker
        ..size = 33
        ..language = 'en'
        ..addCustomColor(const Color(0xFF00AA00));
      settings.color = const Color(0xFF123456);

      final reloaded = AppSettings(await SharedPreferences.getInstance());
      expect(reloaded.brush, BrushType.marker);
      expect(reloaded.size, 33);
      expect(reloaded.sizeFor(BrushType.pen), isNot(33));
      expect(reloaded.color.toARGB32(), 0xFF123456);
      expect(reloaded.locale.value.languageCode, 'en');
      expect(reloaded.customColors.single.toARGB32(), 0xFF00AA00);
    });

    test('picking a color switches the eraser back to the pen', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load()..brush = BrushType.eraser;
      settings.color = Colors.red;
      expect(settings.brush, BrushType.pen);
    });

    test('keeps at most 8 custom colors, newest first', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      for (var i = 0; i < 10; i++) {
        settings.addCustomColor(Color(0xFF000000 + i));
      }
      expect(settings.customColors, hasLength(AppSettings.maxCustomColors));
      expect(settings.customColors.first.toARGB32(), 0xFF000009);
    });
  });

  group('PaintingSession', () {
    test('a blank new painting is not saved', () async {
      final app = await createTestApp();
      expect(await app.session.save(), isTrue);
      expect(await app.store.list(), isEmpty);
    });

    test('saves, then reopens the last painting on the next launch',
        () async {
      final app = await createTestApp();
      app.session.canvasSize = const Size(400, 300);
      app.session.drawing.load([sampleStroke(), sampleStroke()]);
      expect(await app.session.save(), isTrue);
      expect(app.settings.lastPaintingId, app.session.id);

      final next = await createTestApp(
          prefs: {'flutter.lastPaintingId': app.session.id});
      await next.store.save(
          (await app.store.load(app.session.id))!, tinyPng);
      await next.session.restoreLast();
      expect(next.session.id, app.session.id);
      expect(next.session.drawing.strokes, hasLength(2));
    });

    test('new painting saves the old one first', () async {
      final app = await createTestApp();
      app.session.drawing.load([sampleStroke()]);
      final oldId = app.session.id;

      expect(await app.session.newPainting(), isTrue);
      expect(app.session.id, isNot(oldId));
      expect(app.session.drawing.strokes, isEmpty);
      expect((await app.store.list()).single.id, oldId);
    });

    test('a failed save keeps the user on their painting', () async {
      final app = await createTestApp(backend: FailingBackend());
      Object? reported;
      app.session.onSaveError = (e) => reported = e;
      app.session.drawing.load([sampleStroke()]);
      final id = app.session.id;

      expect(await app.session.newPainting(), isFalse);
      expect(app.session.id, id);
      expect(app.session.drawing.strokes, hasLength(1));
      expect(reported, isNotNull);
    });

    test('deleting while an autosave is running does not bring it back',
        () async {
      final app = await createTestApp();
      app.session.drawing.load([sampleStroke()]);
      final id = app.session.id;

      final saving = app.session.save(); // still running when delete starts
      await app.session.delete(id);
      await saving;
      expect(await app.store.list(), isEmpty);
    });

    test('opening a painting does not mark it as changed', () async {
      final app = await createTestApp();
      await app.store.save(sampleDoc('p', DateTime(2026)), tinyPng);
      await app.session.open('p');
      expect(app.session.hasUnsavedChanges, isFalse);
    });

    test('deleting the open painting starts a fresh one', () async {
      final app = await createTestApp();
      app.session.drawing.load([sampleStroke()]);
      await app.session.save();
      final id = app.session.id;

      await app.session.delete(id);
      expect(app.session.id, isNot(id));
      expect(app.session.drawing.strokes, isEmpty);
      expect(await app.store.list(), isEmpty);
      expect(app.settings.lastPaintingId, isNull);
    });
  });
}
