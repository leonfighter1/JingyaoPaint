import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'music_library.dart';

MusicFiles createMusicFiles() => FolderMusicFiles();

/// Keeps added music in a `music` folder in the app's private support
/// folder, so it's still there after the original file is deleted.
class FolderMusicFiles implements MusicFiles {
  FolderMusicFiles() : _root = _defaultRoot();

  final Future<Directory> _root;
  String? _rootPath;

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}music')
        .create(recursive: true);
  }

  Future<String> _path(String name) async {
    _rootPath ??= (await _root).path;
    return '$_rootPath${Platform.pathSeparator}$name';
  }

  @override
  Future<List<String>> list() async {
    final dir = await _root;
    _rootPath ??= dir.path;
    return [
      await for (final e in dir.list())
        if (e is File && !e.path.endsWith('.tmp'))
          e.uri.pathSegments.last,
    ]..sort();
  }

  @override
  Future<void> save(String name, Uint8List bytes) async {
    // Temp file first, so a crash never leaves half a song behind.
    final target = await _path(name);
    final temp = File('$target.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target);
  }

  @override
  Future<void> delete(String name) async {
    final f = File(await _path(name));
    if (await f.exists()) await f.delete();
  }

  /// [list] runs first (the library loads before playing), so the folder's
  /// path is known by then.
  @override
  MusicSource source(String name) =>
      FileMusic('$_rootPath${Platform.pathSeparator}$name');
}
