import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Downloads [bytes] as `<name>.png`.
Future<void> saveImage(Uint8List bytes, String name) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = '$name.png'
    ..click();
  // Give the browser time to start the download before freeing the blob.
  Timer(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
}
