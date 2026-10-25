// Runs in a real browser only:
//   flutter test --platform chrome test/web_store_test.dart
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/gallery/store_backend_web.dart';
import 'package:web/web.dart' as web;

void main() {
  var n = 0;
  IndexedDbStoreBackend fresh() =>
      IndexedDbStoreBackend(databaseName: 'test_${DateTime.now().microsecondsSinceEpoch}_${n++}');

  group('Browser storage (IndexedDB)', () {
    test('keeps text and bytes, and survives reopening', () async {
      final name = 'test_reopen_${DateTime.now().microsecondsSinceEpoch}';
      final store = IndexedDbStoreBackend(databaseName: name);
      await store.writeText('index.json', '{"画":"ok"}');
      await store.writeBytes('p1.png', Uint8List.fromList([1, 2, 3, 255]));

      final reopened = IndexedDbStoreBackend(databaseName: name);
      expect(await reopened.readText('index.json'), '{"画":"ok"}');
      expect(await reopened.readBytes('p1.png'), [1, 2, 3, 255]);
      expect(await reopened.readText('missing'), isNull);
    });

    test('holds far more than localStorage could (about 5 MB)', () async {
      final store = fresh();
      final big = Uint8List(4 * 1024 * 1024)..fillRange(0, 10, 7);
      for (var i = 0; i < 3; i++) {
        await store.writeBytes('big$i.png', big);
      }
      expect((await store.readBytes('big2.png'))!.length, big.length);
    });

    test('remove deletes the item', () async {
      final store = fresh();
      await store.writeText('a', 'x');
      await store.remove('a');
      expect(await store.readText('a'), isNull);
    });

    test('moves paintings saved by older versions out of localStorage',
        () async {
      final storage = web.window.localStorage;
      storage.setItem('paintings/old.json', '{"old":true}');
      storage.setItem('paintings/old.png', base64Encode([9, 8, 7]));
      final store = fresh();

      expect(await store.readText('old.json'), '{"old":true}');
      expect(await store.readBytes('old.png'), [9, 8, 7]);
      expect(storage.getItem('paintings/old.json'), isNull, reason: 'moved');
      expect(await store.readText('old.json'), '{"old":true}',
          reason: 'now read from IndexedDB');
    });
  });
}
