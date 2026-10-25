import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'family.dart';
import 'l10n.dart';
import 'music/music_library.dart';
import 'settings.dart';
import 'theme/cute_font.dart';
import 'theme/cute_theme.dart';
import 'theme/theme_spec.dart';
import 'widgets/name_dialog.dart';
import 'widgets/parent_gate.dart';

const appVersion = '2.1.0';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.themes,
    required this.music,
    required this.family,
  });

  static const maxContentWidth = 760.0;

  /// Roughly the side rail's width on wide screens, so centering is accurate.
  static const railWidth = 80.0;

  final AppSettings settings;
  final List<ThemeSpec> themes;
  final MusicLibrary music;
  final Family family;

  static const _languageNames = {'zh': '简体中文', 'en': 'English'};

  /// Starts over, after the grown-up check and a last confirmation. The
  /// app then shows the first-start setup.
  Future<void> _confirmReset(BuildContext context) async {
    final s = S.of(context);
    final navigator = Navigator.of(context);
    if (!await askGrownUp(context) || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.resetApp),
        content: Text(s.resetAppBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.reset),
          ),
        ],
      ),
    );
    if (ok != true) return;
    navigator.popUntil((route) => route.isFirst);
    await family.resetAll();
  }

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
              itemBuilder: (context, i) => ThemeCard(
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
          _SectionTitle(icon: Icons.face_rounded, text: s.kids),
          _KidsSettings(settings: settings, family: family),
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
          _SectionTitle(icon: Icons.music_note_rounded, text: s.backgroundMusic),
          _MusicSettings(settings: settings, library: music),
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
                  title: Text(s.boardTitle(settings.kidName)),
                  subtitle: Text(
                      '${s.version(appVersion)} · ${s.runsOn}\n${s.aboutBody}'),
                  isThreeLine: true,
                ),
                ListTile(
                  leading: Icon(Icons.description_outlined,
                      color: cute.spec.primary),
                  title: Text(s.licenses),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: s.appName,
                    applicationVersion: appVersion,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: Icon(Icons.restart_alt_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: Text(s.resetApp,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: Text(s.resetAppBody),
              onTap: () => _confirmReset(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// A preview of one theme: its header gradient, emoji, name and nav colors,
/// with text in that theme's own contrast-checked colors.
class ThemeCard extends StatelessWidget {
  const ThemeCard({
    super.key,
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
          // Long titles wrap on small phones with large text.
          Flexible(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// Background music: on/off, volume, which track, and adding new ones from
/// the device.
class _MusicSettings extends StatelessWidget {
  const _MusicSettings({required this.settings, required this.library});

  final AppSettings settings;
  final MusicLibrary library;

  /// Picks an audio file, saves it in the app and plays it.
  Future<void> _upload(BuildContext context) async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final file = await openFile(acceptedTypeGroups: [
      XTypeGroup(
        label: s.backgroundMusic,
        extensions: MusicLibrary.extensions,
        mimeTypes: const ['audio/*'],
        uniformTypeIdentifiers: const ['public.audio'],
        webWildCards: const ['audio/*'],
      ),
    ]);
    if (file == null) return;
    final track = await library.add(file.name, await file.readAsBytes());
    if (track == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.musicAddFailed)));
      return;
    }
    settings
      ..musicTrack = track.id
      ..musicOn = true;
    messenger.showSnackBar(SnackBar(content: Text(s.musicAdded(track.name))));
  }

  Future<void> _confirmRemove(BuildContext context, MusicTrack track) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.deleteMusicTitle(track.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (settings.musicTrack == track.id) {
      settings.musicTrack = MusicLibrary.builtIn.first.id;
    }
    await library.remove(track);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([settings, library]),
      builder: (context, _) {
        final current = library.trackById(settings.musicTrack).id;
        return Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary:
                    Icon(Icons.music_note_rounded, color: cute.spec.primary),
                title: Text(s.playMusic),
                subtitle: Text(s.playMusicHint),
                value: settings.musicOn,
                onChanged: (v) => settings.musicOn = v,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Tooltip(
                      message: s.musicVolume,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.volume_up_rounded,
                            color: cute.spec.primary),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: settings.musicVolume,
                        divisions: 20,
                        label: s.percent(settings.musicVolume),
                        semanticFormatterCallback: (v) =>
                            '${s.musicVolume} ${s.percent(v)}',
                        onChanged: (v) => settings.musicVolume = v,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(s.percent(settings.musicVolume)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(s.musicPlayOrder,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    for (final mode in MusicMode.values)
                      ChoiceChip(
                        avatar: Icon(
                          switch (mode) {
                            MusicMode.repeatOne => Icons.repeat_one_rounded,
                            MusicMode.sequence => Icons.repeat_rounded,
                            MusicMode.shuffle => Icons.shuffle_rounded,
                          },
                          size: 18,
                        ),
                        label: Text(s.musicModeName(mode)),
                        selected: settings.musicMode == mode,
                        showCheckmark: false,
                        onSelected: (_) => settings.musicMode = mode,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final track in library.tracks)
                ListTile(
                  leading: Icon(
                    track.id == current
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: cute.spec.primary,
                  ),
                  title: Text(
                    track.builtIn ? s.trackName(track.name) : track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(track.builtIn ? s.builtInMusic : s.myMusic),
                  selected: track.id == current,
                  // Picking a track means wanting to hear it.
                  onTap: () => settings
                    ..musicTrack = track.id
                    ..musicOn = true,
                  trailing: track.builtIn
                      ? null
                      : IconButton(
                          tooltip: s.delete,
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _confirmRemove(context, track),
                        ),
                ),
              ListTile(
                leading:
                    Icon(Icons.upload_file_rounded, color: cute.spec.primary),
                title: Text(s.uploadMusic),
                subtitle: Text(s.musicFormats(apple: MusicLibrary.isApple)),
                onTap: () => _upload(context),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The kids: who's drawing now (tap another to switch), their names, and
/// adding or deleting kids (grown-ups only).
class _KidsSettings extends StatelessWidget {
  const _KidsSettings({required this.settings, required this.family});

  final AppSettings settings;
  final Family family;

  Future<void> _rename(BuildContext context, Kid kid) async {
    final s = S.of(context);
    final name = await showNameDialog(
      context,
      title: s.changeKidName,
      initial: kid.name,
      label: s.kidNameLabel,
      hint: s.kidNameHint,
      allowEmpty: true,
    );
    if (name != null) settings.renameKid(kid.id, name);
  }

  Future<void> _add(BuildContext context) async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await askGrownUp(context) || !context.mounted) return;
    final name = await showNameDialog(
      context,
      title: s.addKid,
      initial: '',
      label: s.kidNameLabel,
      hint: s.kidNameHint,
    );
    if (name == null) return;
    final kid = await family.addKid(name);
    messenger.showSnackBar(SnackBar(content: Text(s.switchedTo(kid.name))));
  }

  Future<void> _delete(BuildContext context, Kid kid) async {
    final s = S.of(context);
    if (!await askGrownUp(context) || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.deleteKidTitle(kid.name.isEmpty ? s.noKidName : kid.name)),
        content: Text(s.deleteKidBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok == true) await family.removeKid(kid.id);
  }

  Future<void> _switch(BuildContext context, Kid kid) async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (await family.switchTo(kid.id)) {
      messenger.showSnackBar(SnackBar(
          content: Text(s.switchedTo(kid.name.isEmpty ? s.noKidName : kid.name))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cute = CuteTheme.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final current = settings.currentKid.id;
        final kids = settings.kids;
        return Card(
          child: Column(
            children: [
              for (final kid in kids)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: kid.id == current
                        ? cute.spec.primary
                        : cute.spec.primary.withValues(alpha: 0.15),
                    foregroundColor: kid.id == current
                        ? cute.onColor(cute.spec.primary)
                        : cute.ink,
                    child: Text(kid.name.isEmpty ? '?' : kid.name.characters.first),
                  ),
                  title: Text(kid.name.isEmpty ? s.noKidName : kid.name),
                  subtitle: kid.id == current ? Text(s.usingNow) : null,
                  selected: kid.id == current,
                  onTap: () => _switch(context, kid),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: s.changeKidName,
                        icon: const Icon(Icons.edit_rounded),
                        onPressed: () => _rename(context, kid),
                      ),
                      if (kids.length > 1)
                        IconButton(
                          tooltip: s.delete,
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _delete(context, kid),
                        ),
                    ],
                  ),
                ),
              ListTile(
                leading: Icon(Icons.person_add_alt_1_rounded,
                    color: cute.spec.primary),
                title: Text(s.addKid),
                onTap: () => _add(context),
              ),
            ],
          ),
        );
      },
    );
  }
}
