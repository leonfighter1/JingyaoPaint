import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_theme.dart';
import 'drawing/canvas_page.dart';
import 'gallery/gallery_page.dart';
import 'gallery/painting_store.dart';
import 'gallery/store_backend.dart';
import 'l10n.dart';
import 'painting_session.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'share/import_actions.dart';
import 'share/incoming_files.dart';
import 'theme/cute_theme.dart';
import 'theme/theme_spec.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  final settings = await AppSettings.load();
  final themes = await ThemeSpec.loadAll(kThemeIds);
  final session = PaintingSession(
    store: PaintingStore(createStoreBackend()),
    settings: settings,
  );
  await session.restoreLast();
  runApp(PaintApp(settings: settings, session: session, themes: themes));
}

/// Lists the bundled fonts' licenses on Flutter's licenses page, as the
/// SIL Open Font License asks.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final font in kFonts) {
      if (font.licenseAsset case final asset?) {
        yield LicenseEntryWithLineBreaks(
            [font.family!], await rootBundle.loadString(asset));
      }
    }
  });
}

class PaintApp extends StatelessWidget {
  PaintApp({
    super.key,
    required this.settings,
    required this.session,
    required this.themes,
  });

  final AppSettings settings;
  final PaintingSession session;
  final List<ThemeSpec> themes;

  /// Built themes, one per theme and font combination actually used.
  final Map<(String, String), ThemeData> _cache = {};

  ThemeData _theme(String themeId, String fontId) =>
      _cache.putIfAbsent((themeId, fontId), () {
        // An unknown saved theme id (say, a removed theme) falls back to the
        // first bundled one.
        final spec = themes.firstWhere((t) => t.id == themeId,
            orElse: () => themes.first);
        return CuteTheme.build(spec, fontFamily: fontById(fontId).family);
      });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [settings.locale, settings.themeId, settings.fontId]),
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => S.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: _theme(settings.themeId.value, settings.fontId.value),
        locale: settings.locale.value,
        supportedLocales: [
          for (final code in AppSettings.supportedLanguages) Locale(code),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: HomeShell(settings: settings, session: session, themes: themes),
      ),
    );
  }
}

/// The three main screens behind a colorful bottom navigation bar.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.settings,
    required this.session,
    required this.themes,
  });

  final AppSettings settings;
  final PaintingSession session;
  final List<ThemeSpec> themes;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.onSaveError = _showSaveError;
    // After the first frame, so the snackbar and translations are ready.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => IncomingFiles.listen(_openIncoming));
  }

  /// A painting file opened from another app (Android "open with").
  Future<void> _openIncoming(Uint8List bytes) async {
    if (!mounted) return;
    await importBytes(ScaffoldMessenger.of(context), S.of(context),
        widget.session, bytes, () => _selectTab(0));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.onSaveError = null;
    super.dispose();
  }

  /// Saves right away when the app goes to the background, since Android may
  /// kill it before the autosave timer fires.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) widget.session.save();
  }

  void _showSaveError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).autosaveFailed(error))));
  }

  /// Screens at least this wide get a side navigation rail.
  static const railMinWidth = 600.0;

  void _openSettings() {
    widget.session.save();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          SettingsPage(settings: widget.settings, themes: widget.themes),
    ));
  }

  void _selectTab(int i) {
    // Leaving the canvas is a natural moment to save, so the gallery is
    // up to date when it opens.
    if (_tab == 0 && i != 0) widget.session.save();
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    // Settings isn't a tab: it opens from the ⋮ menu, leaving the bar to
    // the two places you actually work in.
    final destinations = [
      (Icons.brush_outlined, Icons.brush_rounded, s.navCanvas),
      (Icons.photo_library_outlined, Icons.photo_library_rounded, s.navGallery),
    ];
    Color navColor(int i) => cute.nav[i % cute.nav.length];
    final pages = IndexedStack(
      index: _tab,
      children: [
        CanvasPage(
          session: widget.session,
          settings: widget.settings,
          onOpenSettings: _openSettings,
        ),
        GalleryPage(
          session: widget.session,
          onOpened: () => _selectTab(0),
          onOpenSettings: _openSettings,
        ),
      ],
    );
    final indicator =
        navColor(_tab).withValues(alpha: ThemeSpec.navIndicatorAlpha);

    // Tablets and turned phones: tabs move to a side rail, leaving the full
    // height for the paper (Material's guidance for medium+ widths).
    if (MediaQuery.sizeOf(context).width >= railMinWidth) {
      return Scaffold(
        body: Row(
          children: [
            ClipRRect(
              borderRadius:
                  BorderRadius.horizontal(right: Radius.circular(cute.radius)),
              child: NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: _selectTab,
                indicatorColor: indicator,
                labelType: NavigationRailLabelType.all,
                groupAlignment: 0,
                destinations: [
                  for (final (i, (icon, selectedIcon, label))
                      in destinations.indexed)
                    NavigationRailDestination(
                      icon: Icon(icon, color: navColor(i)),
                      selectedIcon:
                          Icon(selectedIcon, color: navColor(i), size: 28),
                      label: Text(label),
                    ),
                ],
              ),
            ),
            Expanded(child: pages),
          ],
        ),
      );
    }

    return Scaffold(
      body: pages,
      bottomNavigationBar: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cute.radius)),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _selectTab,
          indicatorColor: indicator,
          height: 68,
          destinations: [
            for (final (i, (icon, selectedIcon, label)) in destinations.indexed)
              NavigationDestination(
                // Full-strength tab colors: theme tests check them for 3:1
                // contrast on the bar and on the selected pill.
                icon: Icon(icon, color: navColor(i)),
                selectedIcon: Icon(selectedIcon, color: navColor(i), size: 28),
                label: label,
              ),
          ],
        ),
      ),
    );
  }
}
