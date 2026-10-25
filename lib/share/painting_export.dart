import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../drawing/drawing_controller.dart';
import '../gallery/painting_file.dart';
import '../gallery/painting_store.dart';

/// The formats a painting can be sent as.
enum ExportFormat {
  png('png', 'image/png'),
  jpg('jpg', 'image/jpeg'),
  pdf('pdf', 'application/pdf'),
  painting(PaintingFile.extension, PaintingFile.mimeType);

  const ExportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

class ExportedFile {
  const ExportedFile(this.bytes, this.name, this.mimeType);

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// Pixels per canvas point in exported images: sharp enough to print.
const exportPixelRatio = 2.0;

/// The painting's canvas size, with a sensible fallback for odd data.
Size paintingSize(PaintingDoc doc) => doc.meta.width > 0 && doc.meta.height > 0
    ? Size(doc.meta.width, doc.meta.height)
    : const Size(800, 1000);

/// A file name like `JingyaoPaint_20261024_1530.png`.
String exportName(PaintingDoc doc, ExportFormat format) {
  final d = doc.meta.updatedAt;
  String two(int n) => n.toString().padLeft(2, '0');
  return 'JingyaoPaint_${d.year}${two(d.month)}${two(d.day)}_'
      '${two(d.hour)}${two(d.minute)}.${format.extension}';
}

Future<ExportedFile> exportPainting(PaintingDoc doc, ExportFormat format) async {
  final size = paintingSize(doc);
  final Uint8List bytes = switch (format) {
    ExportFormat.png => await DrawingController.renderPng(
        doc.strokes, size, exportPixelRatio, paper: doc.paper),
    ExportFormat.jpg => await _jpg(doc, size),
    ExportFormat.pdf => await buildPdf(
        await DrawingController.renderPng(
            doc.strokes, size, exportPixelRatio, paper: doc.paper),
        size,
        PdfPageFormat.a4),
    ExportFormat.painting => PaintingFile.encode(doc),
  };
  return ExportedFile(bytes, exportName(doc, format), format.mimeType);
}

Future<Uint8List> _jpg(PaintingDoc doc, Size size) async {
  final raw = await DrawingController.renderRgba(
      doc.strokes, size, exportPixelRatio, paper: doc.paper);
  // JPEG encoding is pure Dart and can take a moment on big paintings, so
  // do it off the UI thread where the platform allows.
  return compute(_encodeJpg, raw);
}

Uint8List _encodeJpg(({Uint8List rgba, int width, int height}) raw) {
  final image = img.Image.fromBytes(
    width: raw.width,
    height: raw.height,
    bytes: raw.rgba.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: 92);
}

/// A one-page PDF with the picture centered and as large as fits, turned
/// sideways for wide paintings.
Future<Uint8List> buildPdf(
    Uint8List png, Size imageSize, PdfPageFormat format) async {
  final pageFormat =
      imageSize.width > imageSize.height ? format.landscape : format.portrait;
  final doc = pw.Document(title: 'JingyaoPaint', creator: 'JingyaoPaint');
  doc.addPage(pw.Page(
    pageFormat: pageFormat,
    margin: const pw.EdgeInsets.all(24),
    build: (_) => pw.Center(
      child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
    ),
  ));
  return doc.save();
}
