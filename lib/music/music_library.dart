import 'package:flutter/foundation.dart';

/// Where a track's sound comes from.
sealed class MusicSource {
  const MusicSource();
}

/// A track bundled with the app, by its path under `assets/`.
class AssetMusic extends MusicSource {
  const AssetMusic(this.path);
  final String path;
}

/// A track the user added, saved as a file in the app's folder.
class FileMusic extends MusicSource {
  const FileMusic(this.path);
  final String path;
}

/// A track kept in memory (the web, where there is no app folder).
class BytesMusic extends MusicSource {
  const BytesMusic(this.bytes);
  final Uint8List bytes;
}

/// One background music track.
class MusicTrack {
  /// A bundled track; [name] is its key for translation (`S.trackName`).
  const MusicTrack.builtIn(this.name, AssetMusic this.source) : builtIn = true;

  /// A track the user added, named after its file.
  const MusicTrack.added(this.name, this.source) : builtIn = false;

  /// Stored in settings to remember the choice.
  String get id => builtIn ? 'builtin:$name' : 'file:$name';

  /// The translation key of a built-in track, or the file name of an added
  /// one.
  final String name;
  final MusicSource source;
  final bool builtIn;
}

/// Saves the music files the user adds.
abstract class MusicFiles {
  /// The names of the saved files, sorted.
  Future<List<String>> list();
  Future<void> save(String name, Uint8List bytes);
  Future<void> delete(String name);

  /// How to play the saved file [name].
  MusicSource source(String name);
}

/// Keeps added music in memory only: for the web (where it lasts until the
/// page is reloaded) and for tests.
class MemoryMusicFiles implements MusicFiles {
  final Map<String, Uint8List> files = {};

  @override
  Future<List<String>> list() async => files.keys.toList()..sort();

  @override
  Future<void> save(String name, Uint8List bytes) async => files[name] = bytes;

  @override
  Future<void> delete(String name) async => files.remove(name);

  @override
  MusicSource source(String name) => BytesMusic(files[name]!);
}

/// The bundled tracks plus the ones the user added.
class MusicLibrary extends ChangeNotifier {
  MusicLibrary(this._files);

  final MusicFiles _files;

  /// Made for this app by `tool/make_music.dart`, so they're free to ship.
  static const builtIn = [
    MusicTrack.builtIn('sunny', AssetMusic('music/sunny_walk.wav')),
    MusicTrack.builtIn('twinkle', AssetMusic('music/twinkle_lullaby.wav')),
  ];

  /// File types Android, Windows and browsers can generally play.
  static const extensions = [
    'mp3', 'm4a', 'aac', 'mp4', 'wav', 'ogg', 'oga', 'opus', 'flac', //
    'mid', 'midi', 'amr', '3gp', 'webm', 'wma',
  ];

  /// Bigger files are refused; background music doesn't need more.
  static const maxBytes = 60 * 1024 * 1024;

  List<MusicTrack> _added = const [];

  List<MusicTrack> get added => _added;
  List<MusicTrack> get tracks => [...builtIn, ..._added];

  /// Reads the list of added tracks.
  Future<void> load() async {
    _added = [
      for (final name in await _files.list())
        MusicTrack.added(name, _files.source(name)),
    ];
    notifyListeners();
  }

  /// The track with [id], or the first built-in one if it's gone.
  MusicTrack trackById(String id) =>
      tracks.firstWhere((t) => t.id == id, orElse: () => builtIn.first);

  static bool isMusicFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 &&
        extensions.contains(fileName.substring(dot + 1).toLowerCase());
  }

  /// Saves an added file and returns its track, or null if it isn't a music
  /// file this app can play (or is too big). A name already in use gets a
  /// number, so nothing is overwritten.
  Future<MusicTrack?> add(String fileName, Uint8List bytes) async {
    final clean = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (!isMusicFile(clean) || bytes.isEmpty || bytes.length > maxBytes) {
      return null;
    }
    final taken = {for (final t in _added) t.name};
    var name = clean;
    final dot = clean.lastIndexOf('.');
    for (var n = 2; taken.contains(name); n++) {
      name = '${clean.substring(0, dot)} ($n)${clean.substring(dot)}';
    }
    await _files.save(name, bytes);
    await load();
    return _added.firstWhere((t) => t.name == name);
  }

  Future<void> remove(MusicTrack track) async {
    if (track.builtIn) return;
    await _files.delete(track.name);
    await load();
  }
}
