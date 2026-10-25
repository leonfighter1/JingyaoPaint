import 'dart:typed_data';

import 'package:gal/gal.dart';

/// The gallery album saved drawings go into.
const galleryAlbum = 'JingyaoPaint';

/// Saves [bytes] to the device gallery.
Future<void> saveImage(Uint8List bytes, String name) async {
  if (!await Gal.hasAccess(toAlbum: true) &&
      !await Gal.requestAccess(toAlbum: true)) {
    throw Exception('Gallery permission denied');
  }
  await Gal.putImageBytes(bytes, album: galleryAlbum, name: name);
}
