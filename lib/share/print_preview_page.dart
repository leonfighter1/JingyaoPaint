import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../app_theme.dart';
import '../l10n.dart';
import '../theme/cute_theme.dart';
import 'painting_export.dart';

/// Sends a PDF to the system print screen; true if it was printed.
typedef PdfPrinter = Future<bool> Function(
    LayoutCallback onLayout, String name);

Future<bool> _systemPrint(LayoutCallback onLayout, String name) =>
    Printing.layoutPdf(onLayout: onLayout, name: name);

/// The app's own print page: the picture on a sheet of paper, a big ✕ to
/// leave and a big Print button.
///
/// Android's print screen has no close button (only Back or an edge
/// swipe), which children don't find. So it only opens when asked, and
/// this page says how to come back from it.
class PrintPreviewPage extends StatefulWidget {
  const PrintPreviewPage({
    super.key,
    required this.png,
    required this.size,
    required this.name,
    this.printer = _systemPrint,
  });

  /// The rendered painting.
  final Uint8List png;

  /// The painting's size, to lay the sheet out like the PDF will be.
  final Size size;
  final String name;
  final PdfPrinter printer;

  static const closeKey = Key('closePrint');
  static const printKey = Key('printNow');

  @override
  State<PrintPreviewPage> createState() => _PrintPreviewPageState();
}

class _PrintPreviewPageState extends State<PrintPreviewPage> {
  bool _busy = false;

  Future<void> _print() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final printed = await widget.printer(
        (format) => buildPdf(widget.png, widget.size, format),
        widget.name,
      );
      if (!mounted) return;
      if (printed) {
        // Done: straight back to the painting.
        navigator.pop();
        messenger.showSnackBar(SnackBar(content: Text(s.printSent)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.printFailed(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    // The same page shape and margin buildPdf uses: A4, sideways for wide
    // paintings, 24pt margins.
    final wide = widget.size.width > widget.size.height;
    final page = wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    final margin = 24 / page.width;
    return Scaffold(
      appBar: GradientAppBar(
        leading: IconButton(
          tooltip: s.closePrint,
          iconSize: 30,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: AppLogoTitle(text: s.printPreview),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: page.width / page.height,
                    child: LayoutBuilder(
                      builder: (context, box) => Material(
                        color: Colors.white,
                        elevation: 6,
                        shadowColor: cute.spec.primary.withValues(alpha: 0.3),
                        child: Padding(
                          padding: EdgeInsets.all(box.maxWidth * margin),
                          child: Image.memory(
                            widget.png,
                            fit: BoxFit.contain,
                            semanticLabel: s.printPreview,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: cute.spec.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.printHint, style: TextStyle(color: cute.ink)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: PrintPreviewPage.closeKey,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      icon: const Icon(Icons.close_rounded),
                      label: Text(s.closePrint),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      key: PrintPreviewPage.printKey,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.print_rounded),
                      label: Text(s.printNow),
                      onPressed: _busy ? null : _print,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
