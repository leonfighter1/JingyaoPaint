// Makes the built-in background music: two seamless music-box loops, written
// as 16-bit mono WAV files to assets/music/.
//
//   dart run tool/make_music.dart
//
// The tunes are synthesized here (an original melody, and "Twinkle Twinkle
// Little Star", which is in the public domain), so the app can ship them
// without any license questions.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const sampleRate = 16000;

void main() {
  _write('assets/music/sunny_walk.wav', _sunnyWalk());
  _write('assets/music/twinkle_lullaby.wav', _twinkle());
}

/// A note: name like 'C5', start and length in beats, loudness.
typedef Note = (String, double, double, double);

/// "阳光散步": a bouncy tune in C major, 8 bars at 112 bpm.
Float64List _sunnyWalk() {
  const bpm = 112.0;
  // Melody in eighth notes, bar by bar.
  const melody = [
    ['E5', 1], ['G5', 1], ['C6', 2], ['B5', 1], ['A5', 1], ['G5', 2], //
    ['D5', 1], ['G5', 1], ['B5', 2], ['A5', 1], ['G5', 1], ['D5', 2],
    ['C5', 1], ['E5', 1], ['A5', 2], ['G5', 1], ['E5', 1], ['C5', 2],
    ['F5', 2], ['A5', 2], ['G5', 1], ['F5', 1], ['E5', 1], ['D5', 1],
    ['E5', 1], ['G5', 1], ['C6', 2], ['D6', 1], ['C6', 1], ['G5', 2],
    ['B5', 1], ['D6', 1], ['G5', 2], ['A5', 1], ['B5', 1], ['D6', 2],
    ['C6', 2], ['A5', 2], ['B5', 2], ['G5', 2],
    ['C6', 4], ['G5', 2], ['E5', 2],
  ];
  // One chord per half bar: root, third, fifth.
  const chords = [
    'C', 'C', 'G', 'G', 'Am', 'Am', 'F', 'F', //
    'C', 'C', 'G', 'G', 'F', 'G', 'C', 'C',
  ];
  final notes = <Note>[];
  var beat = 0.0;
  for (final [name as String, eighths as int] in melody) {
    notes.add((name, beat, eighths / 2, 0.9));
    beat += eighths / 2;
  }
  for (final (i, chord) in chords.indexed) {
    final (root, third, fifth) = _chord(chord);
    final at = i * 2.0;
    // Bass on the half bar, a soft chord tone on its off-beat.
    notes
      ..add(('${root}3', at, 1, 0.55))
      ..add(('${third}4', at + 1, 0.5, 0.28))
      ..add(('${fifth}4', at + 1.5, 0.5, 0.28));
  }
  return _render(notes, beats: 32, bpm: bpm, decay: 0.7);
}

/// "小星星摇篮曲": Twinkle Twinkle as a slow lullaby over broken chords,
/// 12 bars at 84 bpm.
Float64List _twinkle() {
  const bpm = 84.0;
  const tune = 'C C G G A A G- F F E E D D C- G G F F E E D- '
      'G G F F E E D- C C G G A A G- F F E E D D C-';
  const chords = [
    'C', 'C', 'F', 'C', 'F', 'C', 'G', 'C', //
    'C', 'F', 'C', 'G', 'C', 'F', 'C', 'G',
    'C', 'C', 'F', 'C', 'F', 'C', 'G', 'C',
  ];
  final notes = <Note>[];
  var beat = 0.0;
  for (final word in tune.split(' ')) {
    final long = word.endsWith('-');
    final length = long ? 2.0 : 1.0;
    notes.add(('${word[0]}5', beat, length, 0.85));
    beat += length;
  }
  for (final (i, chord) in chords.indexed) {
    final (root, third, fifth) = _chord(chord);
    final at = i * 2.0;
    // Root, fifth, third, fifth in eighths: a gentle rocking.
    for (final (k, tone) in ['${root}3', '${fifth}3', '${third}4', '${fifth}3']
        .indexed) {
      notes.add((tone, at + k * 0.5, 0.5, k == 0 ? 0.42 : 0.26));
    }
  }
  return _render(notes, beats: 48, bpm: bpm, decay: 1.1);
}

(String, String, String) _chord(String name) => switch (name) {
      'C' => ('C', 'E', 'G'),
      'F' => ('F', 'A', 'C'),
      'G' => ('G', 'B', 'D'),
      'Am' => ('A', 'C', 'E'),
      _ => throw ArgumentError(name),
    };

double _frequency(String note) {
  const steps = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  final midi = 12 * (int.parse(note.substring(1)) + 1) + steps[note[0]]!;
  return 440 * math.pow(2, (midi - 69) / 12).toDouble();
}

/// Plays every note as a music-box tine: a quick attack, then partials that
/// die away (the higher ones faster). Tails that run past the end wrap to
/// the start, so the loop has no seam.
Float64List _render(List<Note> notes,
    {required double beats, required double bpm, required double decay}) {
  final secondsPerBeat = 60 / bpm;
  final total = (beats * secondsPerBeat * sampleRate).round();
  final out = Float64List(total);
  const partials = [(1.0, 1.0, 1.0), (2.0, 0.32, 0.5), (3.0, 0.1, 0.3), (4.2, 0.05, 0.18)];
  for (final (name, start, length, loudness) in notes) {
    final f = _frequency(name);
    final tau = decay * (0.6 + 0.4 * length.clamp(0, 2) / 2);
    final ring = (math.min(4 * tau, 6.0) * sampleRate).round();
    final first = (start * secondsPerBeat * sampleRate).round();
    for (var i = 0; i < ring; i++) {
      final t = i / sampleRate;
      final attack = math.min(1.0, t / 0.004);
      var v = 0.0;
      for (final (mult, amp, speed) in partials) {
        v += amp * math.exp(-t / (tau * speed)) * math.sin(2 * math.pi * f * mult * t);
      }
      out[(first + i) % total] += loudness * attack * v;
    }
  }
  var peak = 0.0;
  for (final v in out) {
    peak = math.max(peak, v.abs());
  }
  for (var i = 0; i < total; i++) {
    out[i] = out[i] / peak * 0.7;
  }
  return out;
}

void _write(String path, Float64List samples) {
  final data = ByteData(44 + samples.length * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little) // fmt chunk size
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little) // bytes per second
    ..setUint16(32, 2, Endian.little) // bytes per frame
    ..setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (final (i, v) in samples.indexed) {
    data.setInt16(44 + i * 2, (v * 32767).round().clamp(-32768, 32767),
        Endian.little);
  }
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data.buffer.asUint8List());
  stdout.writeln('$path: ${(samples.length / sampleRate).toStringAsFixed(1)} s, '
      '${(data.lengthInBytes / 1024).round()} KB');
}
