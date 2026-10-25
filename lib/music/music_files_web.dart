import 'music_library.dart';

/// Browsers have no app folder; added music lasts until the page reloads.
MusicFiles createMusicFiles() => MemoryMusicFiles();
