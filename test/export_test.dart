import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/drawing/drawing_controller.dart';
import 'package:jingyao_paint/drawing/stroke.dart';
import 'package:jingyao_paint/gallery/painting_file.dart';
import 'package:jingyao_paint/gallery/painting_store.dart';
import 'package:jingyao_paint/share/painting_export.dart';

import 'test_helpers.dart';

bool startsWith(Uint8List bytes, List<int> magic) =>
    bytes.length >= magic.length &&
    [for (var i = 0; i < magic.length; i++) bytes[i]].join(',') ==
        magic.join(',');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Export formats', () {
    final doc = sampleDoc('p1', DateTime(2026, 10, 24, 15, 30), strokes: 2);

    test('PNG is a real PNG at print resolution', () async {
      final f = await exportPainting(doc, ExportFormat.png);
      expect(startsWith(f.bytes, [0x89, 0x50, 0x4E, 0x47]), isTrue);
      expect(f.mimeType, 'image/png');
      expect(f.name, 'JoyPainting_20261024_1630.png');
    });

    test('JPG is a real JPEG', () async {
      final f = await exportPainting(doc, ExportFormat.jpg);
      expect(startsWith(f.bytes, [0xFF, 0xD8, 0xFF]), isTrue);
      expect(f.mimeType, 'image/jpeg');
      expect(f.name, endsWith('.jpg'));
    });

    test('PDF is a real PDF', () async {
      final f = await exportPainting(doc, ExportFormat.pdf);
      expect(ascii.decode(f.bytes.sublist(0, 5)), '%PDF-');
      expect(f.mimeType, 'application/pdf');
    });

    test('painting file reopens with every stroke', () async {
      final f = await exportPainting(doc, ExportFormat.painting);
      expect(f.name, endsWith('.jypaint'));
      final back = PaintingFile.decode(f.bytes);
      expect(back.strokes, hasLength(2));
      expect(back.meta.createdAt, doc.meta.createdAt);
    });
  });

  group('PaintingFile', () {
    test('rejects files that are not paintings', () {
      for (final bad in [
        utf8.encode('hello'),
        utf8.encode('{"some": "json"}'),
        utf8.encode('{"format":"jingyao-paint","version":99,"painting":{}}'),
        utf8.encode('{"format":"jingyao-paint","version":1,"painting":{"id":5}}'),
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00]),
      ]) {
        expect(() => PaintingFile.decode(Uint8List.fromList(bad)),
            throwsFormatException, reason: utf8.decode(bad, allowMalformed: true));
      }
    });

    test('keeps text, shapes and paper', () {
      final doc = sampleDoc('t', DateTime(2026));
      final rich = PaintingFileDocFixture.withEverything(doc);
      final back = PaintingFile.decode(PaintingFile.encode(rich));
      expect(back.paper.toARGB32(), 0xFFFFF0F5);
      expect(back.strokes.map((s) => s.text?.text).whereType<String>(), ['你好']);
      expect(back.strokes.map((s) => s.shape).whereType<ShapeKind>(),
          [ShapeKind.heart]);
    });
  });

  group('Importing', () {
    test('a received painting becomes a new painting and opens', () async {
      final app = await createTestApp();
      final file = PaintingFile.encode(sampleDoc('sent', DateTime(2025, 5, 5), strokes: 3));

      expect(await app.session.importPainting(file), isTrue);
      expect(app.session.id, isNot('sent'), reason: 'gets its own id');
      expect(app.session.drawing.strokes, hasLength(3));
      final saved = await app.store.list();
      expect(saved.single.createdAt, DateTime(2025, 5, 5));
    });

    test('importing the same file twice keeps both copies', () async {
      final app = await createTestApp();
      final file = PaintingFile.encode(sampleDoc('x', DateTime(2026)));
      await app.session.importPainting(file);
      await app.session.importPainting(file);
      expect(await app.store.list(), hasLength(2));
    });

    test('a non-painting file is rejected and nothing changes', () async {
      final app = await createTestApp();
      app.session.drawing.load([sampleStroke()]);
      final id = app.session.id;
      expect(await app.session.importPainting(utf8.encode('nope')), isFalse);
      expect(app.session.id, id);
      expect(app.session.drawing.strokes, hasLength(1));
    });

    test('the open painting is saved before an import replaces it', () async {
      final app = await createTestApp();
      app.session.drawing.load([sampleStroke()]);
      final id = app.session.id;
      await app.session.importPainting(
          PaintingFile.encode(sampleDoc('in', DateTime(2026))));
      expect((await app.store.list()).map((m) => m.id), contains(id));
    });
  });

  group('Undo history', () {
    Stroke text(String t, [Offset at = const Offset(10, 10)]) => Stroke.text(
        anchor: at, content: TextContent(text: t), color: Colors.black);

    test('clearing can be undone', () {
      final d = DrawingController()..load([sampleStroke(), sampleStroke()]);
      d.clear();
      expect(d.strokes, isEmpty);
      d.undo();
      expect(d.strokes, hasLength(2));
    });

    test('changing paper can be undone', () {
      final d = DrawingController()..setPaper(const Color(0xFFEEF6FF));
      d.undo();
      expect(d.paper.toARGB32(), Colors.white.toARGB32());
      d.redo();
      expect(d.paper.toARGB32(), 0xFFEEF6FF);
    });

    test('a whole text drag undoes in one step', () {
      final original = text('hi');
      final d = DrawingController()..add(original);
      var current = original;
      for (var x = 20.0; x <= 60; x += 10) {
        final moved = current.moved(Offset(x, 10) - current.anchor);
        d.replace(current, moved, recordUndo: current == original);
        current = moved;
      }
      expect(d.strokes.single.anchor, const Offset(60, 10));
      d.undo();
      expect(d.strokes.single, same(original));
    });

    test('editing and removing text keep its layer and can be undone', () {
      final a = text('a'), b = text('b'), c = text('c');
      final d = DrawingController()
        ..add(a)
        ..add(b)
        ..add(c);
      final b2 = text('B');
      d.replace(b, b2);
      expect(d.strokes, [a, b2, c]);
      d.remove(b2);
      expect(d.strokes, [a, c]);
      d.undo();
      d.undo();
      expect(d.strokes, [a, b, c]);
    });

    test('history is capped', () {
      final d = DrawingController();
      for (var i = 0; i < DrawingController.maxUndo + 20; i++) {
        d.add(sampleStroke());
      }
      var steps = 0;
      while (d.canUndo) {
        d.undo();
        steps++;
      }
      expect(steps, DrawingController.maxUndo);
    });
  });
}

/// A document using every kind of item, for format round trips.
abstract final class PaintingFileDocFixture {
  static PaintingDoc withEverything(PaintingDoc doc) => PaintingDoc(
        meta: doc.meta,
        paper: const Color(0xFFFFF0F5),
        strokes: [
          sampleStroke(),
          Stroke.shape(
            shape: ShapeKind.heart,
            from: const Offset(10, 10),
            to: const Offset(60, 60),
            brush: BrushType.marker,
            color: Colors.pink,
            size: 6,
            fill: true,
            isComplete: true,
          ),
          Stroke.text(
            anchor: const Offset(30, 80),
            content: const TextContent(
                text: '你好', bold: true, align: TextAlign.center, bubble: true),
            color: Colors.purple,
            opacity: 0.8,
          ),
        ],
      );
}
