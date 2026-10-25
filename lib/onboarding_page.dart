import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'l10n.dart';
import 'settings.dart';
import 'settings_page.dart' show ThemeCard;
import 'theme/cute_theme.dart';
import 'theme/theme_spec.dart';

/// The first screen on a new install: pick a language (English to start)
/// and a theme, and give the little artist's name. Every choice shows
/// right away, and all of them can be changed later in Settings.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.settings,
    required this.themes,
  });

  final AppSettings settings;
  final List<ThemeSpec> themes;

  static const nameFieldKey = Key('onboardingName');
  static const startKey = Key('onboardingStart');

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late final _name = TextEditingController(text: widget.settings.kidName);

  static const _languageNames = {'en': 'English', 'zh': '简体中文'};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _start() {
    final settings = widget.settings;
    settings.renameKid(settings.currentKid.id, _name.text);
    settings.onboardingDone = true;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final heading = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w800);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(
            vertical: 24,
            horizontal:
                math.max(20, (MediaQuery.sizeOf(context).width - 560) / 2),
          ),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset('assets/icon/logo.png',
                    width: 88, height: 88, excludeFromSemantics: true),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${s.welcomeTitle} ${cute.spec.emoji}',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: cute.ink),
            ),
            const SizedBox(height: 8),
            Text(s.welcomeBody,
                textAlign: TextAlign.center, style: TextStyle(color: cute.ink)),
            const SizedBox(height: 24),
            Text(s.language, style: heading),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final code in const ['en', 'zh'])
                    ListTile(
                      title: Text(_languageNames[code]!),
                      selected: code == language,
                      trailing: code == language
                          ? Icon(Icons.check_circle_rounded,
                              color: cute.spec.primary)
                          : null,
                      onTap: () => widget.settings.language = code,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(s.theme, style: heading),
            const SizedBox(height: 8),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.themes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => ThemeCard(
                  spec: widget.themes[i],
                  name: widget.themes[i].name(language),
                  selected: widget.themes[i].id == cute.spec.id,
                  onTap: () => widget.settings.theme = widget.themes[i].id,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(s.kidNameLabel, style: heading),
            const SizedBox(height: 8),
            TextField(
              key: OnboardingPage.nameFieldKey,
              controller: _name,
              maxLength: 40,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: s.kidNameHint,
                prefixIcon: const Icon(Icons.face_rounded),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _start(),
            ),
            const SizedBox(height: 4),
            Text(
              s.boardTitle(_name.text.trim()),
              textAlign: TextAlign.center,
              style: TextStyle(color: cute.ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: OnboardingPage.startKey,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56)),
              icon: const Icon(Icons.brush_rounded),
              label: Text(s.startDrawing),
              onPressed: _start,
            ),
          ],
        ),
      ),
    );
  }
}
