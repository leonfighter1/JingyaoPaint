import 'dart:typed_data';

import 'web_send_result.dart';

export 'web_send_result.dart';

/// Only the web uses this; apps share through the system share sheet.
Future<WebSendResult> sendFromBrowser(Uint8List bytes,
        {required String name,
        required String mimeType,
        required String subject,
        required String body}) =>
    throw UnsupportedError('Only for the web');
