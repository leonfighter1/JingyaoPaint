import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jingyao_paint/drawing/canvas_page.dart';
import 'package:jingyao_paint/share/print_preview_page.dart';

import 'test_helpers.dart';
import 'widget_test.dart' show pumpApp;

void main() {
  group('Print preview', () {
    /// Opens the preview over the canvas, like the ⋮ menu does.
    Future<List<String>> openPreview(WidgetTester tester,
        {Size size = const Size(400, 600), bool printed = false}) async {
      await pumpApp(tester);
      final calls = <String>[];
      Navigator.of(tester.element(find.byType(CanvasPage)))
          .push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PrintPreviewPage(
          png: tinyPng,
          size: size,
          name: 'test.pdf',
          printer: (layout, name) async {
            calls.add(name);
            return printed;
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('打印预览'), findsOneWidget);
      return calls;
    }

    testWidgets('the big ✕ button closes it', (tester) async {
      await openPreview(tester);
      await tester.tap(find.byKey(PrintPreviewPage.closeKey));
      await tester.pumpAndSettle();
      expect(find.byType(PrintPreviewPage), findsNothing);
      expect(find.byType(CanvasPage), findsOneWidget);
    });

    testWidgets('the ✕ in the title bar and Back close it too',
        (tester) async {
      await openPreview(tester);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(PrintPreviewPage), findsNothing);

      await openPreview(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PrintPreviewPage), findsNothing);
    });

    testWidgets('says how to come back from the system print screen',
        (tester) async {
      await openPreview(tester);
      expect(find.textContaining('按返回键'), findsOneWidget);
    });

    testWidgets('printing closes the preview once it has been printed',
        (tester) async {
      final calls = await openPreview(tester, printed: true);
      await tester.tap(find.byKey(PrintPreviewPage.printKey));
      await tester.pumpAndSettle();
      expect(calls, ['test.pdf']);
      expect(find.byType(PrintPreviewPage), findsNothing);
      expect(find.text('已交给打印机'), findsOneWidget);
    });

    testWidgets('backing out of the system print screen stays on the preview',
        (tester) async {
      final calls = await openPreview(tester);
      await tester.tap(find.byKey(PrintPreviewPage.printKey));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(find.byType(PrintPreviewPage), findsOneWidget);
    });

    testWidgets('a wide painting is shown on a sideways sheet', (tester) async {
      await openPreview(tester, size: const Size(800, 400));
      final sheet = tester.widget<AspectRatio>(find.descendant(
          of: find.byType(PrintPreviewPage), matching: find.byType(AspectRatio)));
      expect(sheet.aspectRatio, greaterThan(1));
    });
  });
}
