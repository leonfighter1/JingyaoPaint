import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../l10n.dart';
import 'stroke.dart';

/// What the user chose in the text editor.
class TextEditResult {
  const TextEditResult.save(this.content, this.color) : delete = false;
  const TextEditResult.delete()
      : content = null,
        color = null,
        delete = true;

  final TextContent? content;
  final Color? color;
  final bool delete;
}

/// Opens the text editor sheet. Returns null if cancelled.
///
/// [editing] adds a delete button and treats emptied text as a delete.
Future<TextEditResult?> showTextEditor(
  BuildContext context, {
  required TextContent initial,
  required Color color,
  required List<Color> palette,
  bool editing = false,
}) {
  return showModalBottomSheet<TextEditResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _TextEditorSheet(
      initial: initial,
      color: color,
      palette: palette,
      editing: editing,
    ),
  );
}

class _TextEditorSheet extends StatefulWidget {
  const _TextEditorSheet({
    required this.initial,
    required this.color,
    required this.palette,
    required this.editing,
  });

  final TextContent initial;
  final Color color;
  final List<Color> palette;
  final bool editing;

  @override
  State<_TextEditorSheet> createState() => _TextEditorSheetState();
}

class _TextEditorSheetState extends State<_TextEditorSheet> {
  late final _controller = TextEditingController(text: widget.initial.text);
  late TextContent _style = widget.initial;
  late Color _color = widget.color;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final text = _controller.text.trimRight();
    if (text.trim().isEmpty) {
      Navigator.pop(
          context, widget.editing ? const TextEditResult.delete() : null);
      return;
    }
    Navigator.pop(context, TextEditResult.save(_style.copyWith(text: text), _color));
  }

  Widget _toggle(IconData icon, String tooltip, bool on, TextContent Function(bool) set) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      isSelected: on,
      icon: Icon(icon),
      onPressed: () => setState(() => _style = set(!on)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final language = Localizations.localeOf(context).languageCode;
    // The preview caps the size so huge text still fits while typing.
    final preview = _style
        .copyWith(fontSize: _style.fontSize.clamp(14, 40).toDouble())
        .style(_color);
    final colors = [
      _color,
      for (final c in widget.palette)
        if (c.toARGB32() != _color.toARGB32()) c,
    ];
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.editing ? s.editText : s.addText,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (widget.editing)
                    IconButton(
                      tooltip: s.deleteText,
                      icon: Icon(Icons.delete_outline_rounded,
                          color: scheme.error),
                      onPressed: () =>
                          Navigator.pop(context, const TextEditResult.delete()),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _done,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(s.done),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                textAlign: _style.align,
                style: preview,
                decoration: InputDecoration(
                  hintText: s.textPlaceholder,
                  filled: true,
                  fillColor: _style.bubble
                      ? _color.withValues(alpha: 0.16)
                      : scheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _toggle(Icons.format_bold_rounded, s.bold, _style.bold,
                      (v) => _style.copyWith(bold: v)),
                  _toggle(Icons.format_italic_rounded, s.italic, _style.italic,
                      (v) => _style.copyWith(italic: v)),
                  _toggle(Icons.format_underlined_rounded, s.underline,
                      _style.underline, (v) => _style.copyWith(underline: v)),
                  _toggle(Icons.format_strikethrough_rounded, s.strikethrough,
                      _style.strikethrough,
                      (v) => _style.copyWith(strikethrough: v)),
                  _toggle(Icons.chat_bubble_outline_rounded, s.bubble,
                      _style.bubble, (v) => _style.copyWith(bubble: v)),
                  SegmentedButton<TextAlign>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: TextAlign.left,
                          tooltip: s.alignLeft,
                          icon: const Icon(Icons.format_align_left_rounded)),
                      ButtonSegment(
                          value: TextAlign.center,
                          tooltip: s.alignCenter,
                          icon: const Icon(Icons.format_align_center_rounded)),
                      ButtonSegment(
                          value: TextAlign.right,
                          tooltip: s.alignRight,
                          icon: const Icon(Icons.format_align_right_rounded)),
                    ],
                    selected: {_style.align},
                    onSelectionChanged: (v) =>
                        setState(() => _style = _style.copyWith(align: v.first)),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(s.fontSize),
                  Expanded(
                    child: Slider(
                      min: 12,
                      max: 120,
                      divisions: 108,
                      value: _style.fontSize.clamp(12, 120).toDouble(),
                      label: _style.fontSize.round().toString(),
                      semanticFormatterCallback: (v) =>
                          '${s.fontSize} ${v.round()}',
                      onChanged: (v) =>
                          setState(() => _style = _style.copyWith(fontSize: v)),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(_style.fontSize.round().toString(),
                        textAlign: TextAlign.end),
                  ),
                ],
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final font in kFonts)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(font.name(language),
                              style: TextStyle(fontFamily: font.family)),
                          selected: _style.fontFamily == font.family,
                          onSelected: (_) => setState(() => _style =
                              _style.copyWith(fontFamily: () => font.family)),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final c in colors)
                      Semantics(
                        button: true,
                        selected: c.toARGB32() == _color.toARGB32(),
                        label: s.colorLabel(c),
                        excludeSemantics: true,
                        child: InkResponse(
                          radius: 24,
                          onTap: () => setState(() => _color = c),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: c.withValues(alpha: 1),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: c.toARGB32() == _color.toARGB32()
                                        ? scheme.primary
                                        : Colors.black26,
                                    width: c.toARGB32() == _color.toARGB32()
                                        ? 3
                                        : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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
