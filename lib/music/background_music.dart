import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import '../settings.dart';
import 'music_library.dart';

/// Plays one track over and over. Behind an interface so tests can use a
/// fake: there's no sound hardware in a widget test.
abstract class MusicEngine {
  /// Starts [source] from the beginning, looping, at [volume] (0 to 1).
  Future<void> play(MusicSource source, double volume);
  Future<void> pause();
  Future<void> resume();
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

/// The real player (audioplayers: Android's media player, Windows Media
/// Foundation, or the browser's audio element).
class AudioPlayersEngine implements MusicEngine {
  final _player = AudioPlayer(playerId: 'backgroundMusic');

  @override
  Future<void> play(MusicSource source, double volume) async {
    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(
      switch (source) {
        AssetMusic(:final path) => AssetSource(path),
        FileMusic(:final path) => DeviceFileSource(path),
        BytesMusic(:final bytes) => BytesSource(bytes),
      },
      volume: volume,
    );
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}

/// Keeps the background music in step with the settings (on/off, track,
/// volume) and pauses it while the app is in the background.
class BackgroundMusic with WidgetsBindingObserver {
  BackgroundMusic({
    required this.settings,
    required this.library,
    required this.engine,
  });

  final AppSettings settings;
  final MusicLibrary library;
  final MusicEngine engine;

  /// Called when a track can't be played (say, an unsupported file); the
  /// music then switches back to the first built-in track.
  void Function(Object error)? onError;

  bool _foreground = true;
  bool _playing = false;
  String? _loaded;
  double? _volume;
  Future<void> _queue = Future.value();

  void start() {
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_sync);
    library.addListener(_sync);
    _sync();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    settings.removeListener(_sync);
    library.removeListener(_sync);
    engine.dispose();
  }

  /// Paused or hidden means the user left the app (or turned the screen
  /// off). "Inactive" alone is a dialog or the notification shade on top,
  /// so the music keeps going.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _sync();
  }

  /// Settings can change many times a second (the volume slider), so the
  /// player calls run one after another, never overlapping.
  void _sync() => _queue = _queue.then((_) => _apply());

  /// A future that completes when every change so far has reached the
  /// player. For tests.
  Future<void> get settled => _queue;

  Future<void> _apply() async {
    if (!settings.musicOn || !_foreground) {
      if (_playing) {
        _playing = false;
        await engine.pause();
      }
      return;
    }
    final track = library.trackById(settings.musicTrack);
    final volume = settings.musicVolume;
    try {
      if (_loaded != track.id) {
        _loaded = track.id;
        _volume = volume;
        _playing = true;
        await engine.play(track.source, volume);
        return;
      }
      if (!_playing) {
        _playing = true;
        await engine.resume();
      }
      if (_volume != volume) {
        _volume = volume;
        await engine.setVolume(volume);
      }
    } catch (e) {
      _loaded = null;
      _playing = false;
      onError?.call(e);
      if (!track.builtIn) {
        // Falls back to a track that always works (and plays it).
        settings.musicTrack = MusicLibrary.builtIn.first.id;
      }
    }
  }
}
