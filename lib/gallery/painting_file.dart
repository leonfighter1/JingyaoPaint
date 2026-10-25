import 'dart:convert';
import 'dart:typed_data';

import 'painting_store.dart';

/// The `.jypaint` file format: a painting someone can open in this app and
/// keep drawing on.
///
/// It's JSON with a format marker, so files that aren't paintings (or are
/// from a newer, incompatible version) are rejected instead of half-loaded.
abstract final class PaintingFile {
  static const extension = 'jypaint';
  static const mimeType = 'application/vnd.jingyao.paint+json';
  static const version = 1;
  static const _format = 'jingyao-paint';

  static Uint8List encode(PaintingDoc doc) => utf8.encode(jsonEncode({
        'format': _format,
        'version': version,
        'painting': doc.toJson(),
      }));

  /// Throws [FormatException] if [bytes] isn't a painting file this app can
  /// read.
  static PaintingDoc decode(Uint8List bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map ||
          json['format'] != _format ||
          (json['version'] as num? ?? 0) > version ||
          json['painting'] is! Map) {
        throw const FormatException('Not a JoyPainting painting');
      }
      return PaintingDoc.fromJson(
          (json['painting'] as Map).cast<String, Object?>());
    } on FormatException {
      rethrow;
    } catch (e) {
      // Wrong types inside otherwise valid JSON.
      throw FormatException('Damaged painting file: $e');
    }
  }
}
