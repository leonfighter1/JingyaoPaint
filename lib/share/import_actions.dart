import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../gallery/painting_file.dart';
import '../l10n.dart';
import '../painting_session.dart';

/// Lets the user pick a `.jypaint` file (for example one saved from a chat
/// app) and opens it as a new painting.
Future<void> pickAndImport(
    BuildContext context, PaintingSession session, VoidCallback onOpened) async {
  final s = S.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final file = await openFile(acceptedTypeGroups: [
    XTypeGroup(
      label: s.appTitle,
      extensions: const [PaintingFile.extension],
      // Chat apps often save it without a specific type, so accept the
      // generic ones too; the content is checked on import.
      mimeTypes: const [
        PaintingFile.mimeType,
        'application/json',
        'application/octet-stream',
      ],
      // The type declared in ios/Runner/Info.plist, plus any data for files
      // that arrive without it.
      uniformTypeIdentifiers: const [
        'com.personal.jingyaopaint.painting',
        'public.data',
      ],
      webWildCards: const ['.${PaintingFile.extension}'],
    ),
  ]);
  if (file == null) return;
  await importBytes(messenger, s, session, await file.readAsBytes(), onOpened);
}

/// Imports [bytes] and tells the user how it went.
Future<void> importBytes(
  ScaffoldMessengerState messenger,
  S s,
  PaintingSession session,
  Uint8List bytes,
  VoidCallback onOpened,
) async {
  final ok = await session.importPainting(bytes);
  messenger.showSnackBar(
      SnackBar(content: Text(ok ? s.imported : s.notAPainting)));
  if (ok) onOpened();
}
