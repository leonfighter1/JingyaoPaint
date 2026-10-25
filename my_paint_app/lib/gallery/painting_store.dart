import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../drawing/stroke.dart';

/// What the gallery needs to show a painting without loading its strokes.
class PaintingMeta {
  const PaintingMeta({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.width,
    required this.height,
    required this.strokeCount,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Canvas size when last saved, used for the thumbnail's aspect ratio.
  final double width;
  final double height;
  final int strokeCount;

  Map<String, Object?> toJson() => {
        'id': id,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'width': width,
        'height': height,
        'strokeCount': strokeCount,
      };

  factory PaintingMeta.fromJson(Map<String, Object?> json) => PaintingMeta(
        id: json['id'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
        width: (json['width'] as num? ?? 0).toDouble(),
        height: (json['height'] as num? ?? 0).toDouble(),
        strokeCount: json['strokeCount'] as int? ?? 0,
      );
}

/// A full painting: its metadata plus every stroke.
class PaintingDoc {
  const PaintingDoc({
    required this.meta,
    required this.strokes,
    this.paper = const Color(0xFFFFFFFF),
  });

  final PaintingMeta meta;
  final List<Stroke> strokes;
  final Color paper;

  Map<String, Object?> toJson() => {
        ...meta.toJson(),
        'paper': paper.toARGB32(),
        'strokes': [for (final s in strokes) s.toJson()],
      };

  String encode() => jsonEncode(toJson());

  factory PaintingDoc.decode(String source) =>
      PaintingDoc.fromJson(jsonDecode(source) as Map<String, Object?>);

  factory PaintingDoc.fromJson(Map<String, Object?> json) {
    return PaintingDoc(
      meta: PaintingMeta.fromJson(json),
      paper: Color(json['paper'] as int? ?? 0xFFFFFFFF),
      strokes: [
        for (final s in json['strokes'] as List)
          Stroke.fromJson(s as Map<String, Object?>),
      ],
    );
  }
}

/// Raw named storage the [PaintingStore] is built on: files on Android and
/// Windows, browser storage on the web, a map in tests.
abstract class StoreBackend {
  Future<String?> readText(String name);
  Future<void> writeText(String name, String value);
  Future<Uint8List?> readBytes(String name);
  Future<void> writeBytes(String name, Uint8List value);
  Future<void> remove(String name);
}

class MemoryStoreBackend implements StoreBackend {
  final Map<String, Object> files = {};

  @override
  Future<String?> readText(String name) async => files[name] as String?;
  @override
  Future<void> writeText(String name, String value) async =>
      files[name] = value;
  @override
  Future<Uint8List?> readBytes(String name) async => files[name] as Uint8List?;
  @override
  Future<void> writeBytes(String name, Uint8List value) async =>
      files[name] = value;
  @override
  Future<void> remove(String name) async => files.remove(name);
}

/// Saves paintings as `<id>.json` plus a `<id>.png` thumbnail, and keeps an
/// `index.json` of [PaintingMeta] so the gallery can list them quickly.
class PaintingStore extends ChangeNotifier {
  PaintingStore(this._backend);

  static const _indexName = 'index.json';

  final StoreBackend _backend;
  List<PaintingMeta>? _index;
  final Map<String, Uint8List?> _thumbnails = {};

  /// Writes run one at a time so two saves can't interleave index updates.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<PaintingMeta>> _loadIndex() async {
    if (_index != null) return _index!;
    try {
      final raw = await _backend.readText(_indexName);
      _index = raw == null
          ? []
          : [
              for (final m in jsonDecode(raw) as List)
                PaintingMeta.fromJson(m as Map<String, Object?>),
            ];
    } catch (e) {
      debugPrint('Painting index unreadable, starting empty: $e');
      _index = [];
    }
    return _index!;
  }

  Future<void> _writeIndex(List<PaintingMeta> index) => _backend.writeText(
      _indexName, jsonEncode([for (final m in index) m.toJson()]));

  /// All paintings, most recently edited first.
  Future<List<PaintingMeta>> list() async {
    final index = await _loadIndex();
    return [...index]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<PaintingDoc?> load(String id) async {
    final raw = await _backend.readText('$id.json');
    return raw == null ? null : PaintingDoc.decode(raw);
  }

  Future<Uint8List?> thumbnail(String id) async {
    if (_thumbnails.containsKey(id)) return _thumbnails[id];
    return _thumbnails[id] = await _backend.readBytes('$id.png');
  }

  Future<void> save(PaintingDoc doc, Uint8List thumbnail) => _serial(() async {
        final id = doc.meta.id;
        await _backend.writeText('$id.json', doc.encode());
        await _backend.writeBytes('$id.png', thumbnail);
        _thumbnails[id] = thumbnail;
        final index = await _loadIndex();
        index
          ..removeWhere((m) => m.id == id)
          ..add(doc.meta);
        await _writeIndex(index);
        notifyListeners();
      });

  Future<void> delete(String id) => _serial(() async {
        final index = await _loadIndex();
        index.removeWhere((m) => m.id == id);
        await _writeIndex(index);
        await _backend.remove('$id.json');
        await _backend.remove('$id.png');
        _thumbnails.remove(id);
        notifyListeners();
      });
}
