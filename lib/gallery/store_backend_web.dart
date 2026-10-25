import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'painting_store.dart';

StoreBackend createStoreBackend() => IndexedDbStoreBackend();

/// Stores each item in the browser's IndexedDB, which allows hundreds of
/// megabytes (localStorage stops at about 5 MB, a handful of paintings).
///
/// Items saved by older versions in localStorage are read from there once,
/// moved into IndexedDB and removed.
class IndexedDbStoreBackend implements StoreBackend {
  IndexedDbStoreBackend({this.databaseName = 'jingyao_paint'}) {
    // Asks the browser not to clear the paintings when space runs low, and
    // Safari not to after weeks without a visit. A refusal is fine.
    try {
      web.window.navigator.storage.persist().toDart.ignore();
    } catch (_) {}
  }

  final String databaseName;
  static const _store = 'files';
  static const _legacyPrefix = 'paintings/';

  late final Future<web.IDBDatabase> _db = _open();

  Future<web.IDBDatabase> _open() {
    final done = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(databaseName, 1);
    request.onupgradeneeded = (web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_store);
    }.toJS;
    request.onsuccess = ((web.Event _) =>
        done.complete(request.result as web.IDBDatabase)).toJS;
    request.onerror = ((web.Event _) => done.completeError(
        Exception('IndexedDB: ${request.error?.message}'))).toJS;
    return done.future;
  }

  /// Runs one change and waits until the browser has committed it.
  Future<void> _change(void Function(web.IDBObjectStore files) change) async {
    final tx = (await _db).transaction(_store.toJS, 'readwrite');
    final done = Completer<void>();
    // A failed transaction fires both "error" and "abort".
    void fail(web.Event _) {
      if (!done.isCompleted) {
        done.completeError(Exception('IndexedDB: ${tx.error?.message}'));
      }
    }
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onerror = fail.toJS;
    tx.onabort = fail.toJS;
    change(tx.objectStore(_store));
    return done.future;
  }

  Future<Uint8List?> _get(String name) async {
    final request =
        (await _db).transaction(_store.toJS).objectStore(_store).get(name.toJS);
    final done = Completer<Uint8List?>();
    request.onsuccess = (web.Event _) {
      final value = request.result;
      done.complete(value == null ? null : (value as JSUint8Array).toDart);
    }.toJS;
    request.onerror = ((web.Event _) => done.completeError(
        Exception('IndexedDB: ${request.error?.message}'))).toJS;
    return done.future;
  }

  Future<void> _put(String name, Uint8List bytes) =>
      _change((files) => files.put(bytes.toJS, name.toJS));

  /// An item an older version left in localStorage, moved over (or null).
  Future<Uint8List?> _takeLegacy(String name, {required bool binary}) async {
    final storage = web.window.localStorage;
    final value = storage.getItem('$_legacyPrefix$name');
    if (value == null) return null;
    final bytes = binary ? base64Decode(value) : utf8.encode(value);
    await _put(name, bytes);
    storage.removeItem('$_legacyPrefix$name');
    return bytes;
  }

  @override
  Future<String?> readText(String name) async {
    final bytes =
        await _get(name) ?? await _takeLegacy(name, binary: false);
    return bytes == null ? null : utf8.decode(bytes);
  }

  @override
  Future<void> writeText(String name, String value) =>
      _put(name, utf8.encode(value));

  @override
  Future<Uint8List?> readBytes(String name) async =>
      await _get(name) ?? await _takeLegacy(name, binary: true);

  @override
  Future<void> writeBytes(String name, Uint8List value) => _put(name, value);

  @override
  Future<void> remove(String name) async {
    web.window.localStorage.removeItem('$_legacyPrefix$name');
    await _change((files) => files.delete(name.toJS));
  }
}
