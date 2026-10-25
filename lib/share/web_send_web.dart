import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_send_result.dart';

export 'web_send_result.dart';

/// Sends a painting from the browser so it ends up attached to an email.
///
/// Browsers that can share files (Safari, Chrome and Edge on phones,
/// tablets, Macs and Windows) open their share menu, where Mail attaches
/// it. A plain `mailto:` link can't carry an attachment, so other browsers
/// download the file and open a new email that says which file to attach.
Future<WebSendResult> sendFromBrowser(
  Uint8List bytes, {
  required String name,
  required String mimeType,
  required String subject,
  required String body,
}) async {
  final file = web.File(
      [bytes.toJS].toJS, name, web.FilePropertyBag(type: mimeType));
  final data = web.ShareData(files: [file].toJS, title: subject, text: body);
  var canShare = false;
  try {
    canShare = web.window.navigator.canShare(data);
  } catch (_) {
    // No Web Share in this browser.
  }
  if (canShare) {
    try {
      await web.window.navigator.share(data).toDart;
      return WebSendResult.shared;
    } catch (e) {
      if ('$e'.contains('AbortError')) return WebSendResult.cancelled;
      // Refused (say, too long after the tap): fall back to email below.
    }
  }
  _download(bytes, name, mimeType);
  web.window.location.href = 'mailto:?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}';
  return WebSendResult.downloadedForEmail;
}

void _download(Uint8List bytes, String name, String mimeType) {
  final url = web.URL.createObjectURL(
      web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType)));
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name;
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Give the download a moment to start before freeing the data.
  Future.delayed(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
}
