import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';

/// Checks that a grown-up is there before adding or deleting a kid or
/// resetting the app: a multiplication of two numbers from 11 to 19, like
/// 12 × 15, easy for a parent and out of reach for a young child. A wrong
/// answer brings a new question. Returns true once answered right.
Future<bool> askGrownUp(BuildContext context, {math.Random? random}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => ParentGate(random: random ?? math.Random()),
    ) ??
    false;

class ParentGate extends StatefulWidget {
  const ParentGate({super.key, required this.random});

  final math.Random random;

  /// Finds the question ("12 × 15 = ?") in tests.
  static const questionKey = Key('parentGateQuestion');

  /// The two numbers in [question], for tests that answer it.
  static (int, int) parse(String question) {
    final m = RegExp(r'(\d+) × (\d+)').firstMatch(question)!;
    return (int.parse(m[1]!), int.parse(m[2]!));
  }

  @override
  State<ParentGate> createState() => _ParentGateState();
}

class _ParentGateState extends State<ParentGate> {
  late (int, int) _question = _newQuestion();
  final _answer = TextEditingController();
  bool _wrong = false;

  (int, int) _newQuestion() =>
      (11 + widget.random.nextInt(9), 11 + widget.random.nextInt(9));

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _check() {
    final (a, b) = _question;
    if (int.tryParse(_answer.text.trim()) == a * b) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _wrong = true;
      _question = _newQuestion();
      _answer.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final (a, b) = _question;
    return AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded),
      title: Text(s.parentCheck),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.parentCheckHint),
          const SizedBox(height: 12),
          Text(
            '$a × $b = ?',
            key: ParentGate.questionKey,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _answer,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: s.answer,
              errorText: _wrong ? s.wrongAnswer : null,
            ),
            onSubmitted: (_) => _check(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.cancel),
        ),
        FilledButton(onPressed: _check, child: Text(s.confirm)),
      ],
    );
  }
}
