import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'painting_store.dart';

StoreBackend createStoreBackend() => FileStoreBackend();

/// Stores each item as a file in the app's private support folder.
class FileStoreBackend implements StoreBackend {
  FileStoreBackend([Future<Directory>? root]) : _root = root ?? _defaultRoot();

  final Future<Directory> _root;

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}paintings')
        .create(recursive: true);
  }

  Future<File> _file(String name) async =>
      File('${(await _root).path}${Platform.pathSeparator}$name');

  /// Writes to a temp file first so a crash mid-write never leaves a
  /// half-written painting behind.
  Future<void> _writeAtomic(String name, List<int> bytes) async {
    final target = await _file(name);
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
  }

  @override
  Future<String?> readText(String name) async {
    final f = await _file(name);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> writeText(String name, String value) =>
      _writeAtomic(name, utf8.encode(value));

  @override
  Future<Uint8List?> readBytes(String name) async {
    final f = await _file(name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> writeBytes(String name, Uint8List value) =>
      _writeAtomic(name, value);

  @override
  Future<void> remove(String name) async {
    final f = await _file(name);
    if (await f.exists()) await f.delete();
  }
}
