import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../drawing/drawing_controller.dart';
import '../gallery/painting_store.dart';
import '../l10n.dart';
import '../theme/cute_theme.dart';
import 'painting_export.dart';

IconData _formatIcon(ExportFormat f) => switch (f) {
      ExportFormat.png => Icons.image_rounded,
      ExportFormat.jpg => Icons.photo_rounded,
      ExportFormat.pdf => Icons.picture_as_pdf_rounded,
      ExportFormat.painting => Icons.brush_rounded,
    };

/// Asks which format to send [doc] in, then opens the system share sheet,
/// where the user picks who or which app to send it to. On the web, where
/// sharing files may not be supported, the file is downloaded instead.
Future<void> showSendSheet(BuildContext context, PaintingDoc doc) async {
  final s = S.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final format = await showModalBottomSheet<ExportFormat>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final cute = CuteTheme.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(s.sendAs,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final f in ExportFormat.values)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: cute.spec.secondary,
                  foregroundColor: cute.spec.onSecondary,
                  child: Icon(_formatIcon(f)),
                ),
                title: Text(s.formatName(f.name)),
                subtitle: Text(s.formatHint(f.name)),
                onTap: () => Navigator.pop(context, f),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (format == null) return;
  try {
    final file = await exportPainting(doc, format);
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(file.bytes, mimeType: file.mimeType, name: file.name)],
      fileNameOverrides: [file.name],
      title: s.appTitle,
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(s.sendFailed(e))));
  }
}

/// Opens the system print dialog with [doc] as a one-page picture.
Future<void> printPainting(BuildContext context, PaintingDoc doc) async {
  final s = S.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final size = paintingSize(doc);
    final png = await DrawingController.renderPng(
        doc.strokes, size, exportPixelRatio, paper: doc.paper);
    await Printing.layoutPdf(
      name: exportName(doc, ExportFormat.pdf),
      onLayout: (format) => buildPdf(png, size, format),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(s.printFailed(e))));
  }
}
