import 'package:flutter/material.dart';

import '../l10n.dart';

/// Asks for a name (a painting's or a kid's). Returns the trimmed name, or
/// null if cancelled. With [allowEmpty] false, Save stays off until
/// something is typed.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String initial,
  String? label,
  String? hint,
  bool allowEmpty = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      title: title,
      initial: initial,
      label: label,
      hint: hint,
      allowEmpty: allowEmpty,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.label,
    required this.hint,
    required this.allowEmpty,
  });

  final String title;
  final String initial;
  final String? label;
  final String? hint;
  final bool allowEmpty;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection =
        TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave =>
      widget.allowEmpty || _controller.text.trim().isNotEmpty;

  void _save() {
    if (_canSave) Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.label ?? s.nameLabel,
          hintText: widget.hint,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: Text(s.save),
        ),
      ],
    );
  }
}
