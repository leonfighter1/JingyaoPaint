import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'painting_store.dart';

StoreBackend createStoreBackend() => LocalStorageBackend();

/// Stores items in the browser's localStorage. Browsers cap this at about
/// 5 MB, which is plenty for testing in Chrome but not for real use.
class LocalStorageBackend implements StoreBackend {
  static const _prefix = 'paintings/';

  web.Storage get _storage => web.window.localStorage;

  @override
  Future<String?> readText(String name) async =>
      _storage.getItem('$_prefix$name');

  @override
  Future<void> writeText(String name, String value) async =>
      _storage.setItem('$_prefix$name', value);

  @override
  Future<Uint8List?> readBytes(String name) async {
    final value = _storage.getItem('$_prefix$name');
    return value == null ? null : base64Decode(value);
  }

  @override
  Future<void> writeBytes(String name, Uint8List value) async =>
      _storage.setItem('$_prefix$name', base64Encode(value));

  @override
  Future<void> remove(String name) async =>
      _storage.removeItem('$_prefix$name');
}
