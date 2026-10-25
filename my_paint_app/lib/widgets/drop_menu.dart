import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/cute_theme.dart';

/// One row in a [showDropMenu] menu.
class DropMenuItem {
  const DropMenuItem({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.enabled = true,
    this.danger = false,
    this.checked,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final bool enabled;

  /// Shown in the error color, for destructive actions like delete.
  final bool danger;

  /// Non-null shows an on/off switch (for toggles like mirror drawing).
  final bool? checked;
}

/// A titled group of rows.
class DropMenuSection {
  const DropMenuSection({this.title, required this.items});

  final String? title;
  final List<DropMenuItem> items;
}

/// Opens a menu under the app bar's right edge that unfolds from the top
/// down and scrolls when it's taller than the screen allows. Choosing a row
/// closes the menu, then runs the row's action.
Future<void> showDropMenu(
    BuildContext context, List<DropMenuSection> sections) async {
  final animate = !MediaQuery.disableAnimationsOf(context);
  final action = await showGeneralDialog<VoidCallback>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: Duration(milliseconds: animate ? 280 : 0),
    pageBuilder: (context, animation, _) =>
        _DropMenuPanel(sections: sections, animation: animation),
  );
  action?.call();
}

class _DropMenuPanel extends StatelessWidget {
  const _DropMenuPanel({required this.sections, required this.animation});

  final List<DropMenuSection> sections;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final cute = CuteTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final top = media.padding.top + kToolbarHeight - 4;
    final maxHeight =
        math.max(160.0, media.size.height - top - media.padding.bottom - 24);
    final children = <Widget>[];
    for (final (i, section) in sections.indexed) {
      if (i > 0) children.add(const Divider(height: 12));
      if (section.title case final title?) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Text(title,
              style: TextStyle(
                  color: cute.ink, fontSize: 12, fontWeight: FontWeight.w800)),
        ));
      }
      for (final item in section.items) {
        final color = item.danger ? scheme.error : null;
        children.add(ListTile(
          enabled: item.enabled,
          leading: Icon(item.icon, color: item.enabled ? color : null),
          title: Text(item.label,
              style: item.enabled && color != null
                  ? TextStyle(color: color)
                  : null),
          trailing: item.checked == null
              ? null
              : Switch(
                  value: item.checked!,
                  onChanged: item.enabled
                      ? (_) => Navigator.pop(context, item.onSelected)
                      : null,
                ),
          onTap: () => Navigator.pop(context, item.onSelected),
        ));
      }
    }

    return Padding(
      padding: EdgeInsets.only(top: top, right: 8, left: 8),
      child: Align(
        alignment: Alignment.topRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 300, maxHeight: maxHeight),
          // Unfolds downward from its top edge.
          child: SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            alignment: Alignment.topCenter,
            child: Material(
              color: scheme.surface,
              elevation: 10,
              shadowColor: cute.spec.primary.withValues(alpha: 0.35),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(cute.radius * 0.75),
                side: BorderSide(
                    color: cute.spec.primary.withValues(alpha: 0.18)),
              ),
              // A short menu, so build every row at once (no lazy list):
              // it scrolls when the screen is too short to show them all.
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  // Stretch, so section titles line up left with the rows.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
