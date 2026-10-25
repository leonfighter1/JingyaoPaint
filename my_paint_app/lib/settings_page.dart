import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'l10n.dart';
import 'settings.dart';
import 'theme/cute_font.dart';
import 'theme/cute_theme.dart';
import 'theme/theme_spec.dart';

const appVersion = '1.6.0';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.settings, required this.themes});

  static const maxContentWidth = 760.0;

  /// Roughly the side rail's width on wide screens, so centering is accurate.
  static const railWidth = 80.0;

  final AppSettings settings;
  final List<ThemeSpec> themes;

  static const _languageNames = {'zh': '简体中文', 'en': 'English'};

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: GradientAppBar(title: AppLogoTitle(text: s.navSettings)),
      body: ListView(
        // On wide screens keep the content a readable width, centered.
        padding: EdgeInsets.symmetric(
          vertical: 16,
          horizontal: math.max(
              16, (MediaQuery.sizeOf(context).width - railWidth - maxContentWidth) / 2),
        ),
        children: [
          _SectionTitle(icon: Icons.color_lens_rounded, text: s.theme),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: themes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _ThemeCard(
                spec: themes[i],
                name: themes[i].name(language),
                selected: themes[i].id == cute.spec.id,
                onTap: () => settings.theme = themes[i].id,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(icon: Icons.font_download_rounded, text: s.font),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kFonts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _FontCard(
                font: kFonts[i],
                name: kFonts[i].name(language),
                sample: s.fontSample,
                selected: fontById(settings.fontId.value).id == kFonts[i].id,
                onTap: () => settings.font = kFonts[i].id,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(icon: Icons.translate_rounded, text: s.language),
          Card(
            child: Column(
              children: [
                for (final code in AppSettings.supportedLanguages)
                  ListTile(
                    title: Text(_languageNames[code]!),
                    trailing: code == language
                        ? Icon(Icons.check_circle_rounded,
                            color: cute.spec.primary)
                        : null,
                    selected: code == language,
                    onTap: () => settings.language = code,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(icon: Icons.info_outline_rounded, text: s.about),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/icon/logo.png',
                        width: 44, excludeFromSemantics: true),
                  ),
                  title: Text(s.appTitle),
                  subtitle: Text('${s.version(appVersion)}\n${s.aboutBody}'),
                  isThreeLine: true,
                ),
                ListTile(
                  leading: Icon(Icons.description_outlined,
                      color: cute.spec.primary),
                  title: Text(s.licenses),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: s.appTitle,
                    applicationVersion: appVersion,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A preview of one theme: its header gradient, emoji, name and nav colors,
/// with text in that theme's own contrast-checked colors.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.spec,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final ThemeSpec spec;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(spec.radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 112,
          decoration: BoxDecoration(
            color: spec.surface,
            borderRadius: BorderRadius.circular(spec.radius),
            border: Border.all(
              color: selected ? ring : spec.primary.withValues(alpha: 0.2),
              width: selected ? 3 : 1,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(spec.radius - 6),
                    gradient: LinearGradient(
                      colors: spec.header,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(spec.emoji, style: const TextStyle(fontSize: 30)),
                ),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: spec.ink,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in [spec.primary, ...spec.nav.skip(1)])
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration:
                            BoxDecoration(color: c, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A font choice, showing a sample written in that font.
class _FontCard extends StatelessWidget {
  const _FontCard({
    required this.font,
    required this.name,
    required this.sample,
    required this.selected,
    required this.onTap,
  });

  final CuteFont font;
  final String name;
  final String sample;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cute = CuteTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(cute.radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 150,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(cute.radius),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.2),
              width: selected ? 3 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                sample,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: font.family,
                  fontSize: 18,
                  color: cute.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: font.family,
                  fontSize: 12,
                  color: cute.ink,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cute = CuteTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: cute.spec.primary, size: 20),
          const SizedBox(width: 8),
          Text(text,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
