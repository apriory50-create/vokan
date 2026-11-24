import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'model.dart';
import 'store.dart';

class ReaderScreen extends StatefulWidget {
  final Store store;
  const ReaderScreen({super.key, required this.store});
  @override
  State<ReaderScreen> createState() => _ReaderState();
}

class _ReaderState extends State<ReaderScreen> {
  final input = TextEditingController();
  List<(String, bool)>? tokens; // (фрагмент, это слово?)
  final recognizers = <TapGestureRecognizer>[];

  static final _wordRe = RegExp(r"[A-Za-z]+(?:['’][A-Za-z]+)*");

  @override
  void dispose() {
    input.dispose();
    for (final r in recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  void _split() {
    final text = input.text;
    final parts = <(String, bool)>[];
    var last = 0;
    for (final m in _wordRe.allMatches(text)) {
      if (m.start > last) parts.add((text.substring(last, m.start), false));
      parts.add((m.group(0)!, true));
      last = m.end;
    }
    if (last < text.length) parts.add((text.substring(last), false));
    for (final r in recognizers) {
      r.dispose();
    }
    recognizers.clear();
    setState(() => tokens = parts);
  }

  WordCard? _find(String w) {
    final k = w.toLowerCase();
    for (final c in widget.store.cards) {
      if (c.en.toLowerCase() == k) return c;
    }
    return null;
  }

  /// Доля уникальных слов текста, которые уже изучаются (не новые).
  String _coverage() {
    final words = tokens!.where((t) => t.$2).map((t) => t.$1.toLowerCase()).toSet();
    if (words.isEmpty) return '';
    final known = words.where((w) => (_find(w)?.isNew ?? false) == false && _find(w) != null).length;
    final pct = (known * 100 / words.length).round();
    return 'Уникальных слов: ${words.length}, уже в изучении: $known ($pct%)';
  }

  InlineSpan _span(String text, bool isWord, TextStyle? style) {
    if (!isWord) return TextSpan(text: text, style: style);
    final r = TapGestureRecognizer()..onTap = () => _tap(text);
    recognizers.add(r);
    final known = _find(text) != null;
    return TextSpan(
      text: text,
      recognizer: r,
      style: style?.copyWith(
        color: known ? Colors.green.shade700 : null,
        decoration: known ? null : TextDecoration.underline,
      ),
    );
  }

  void _tap(String w) {
    final card = _find(w);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(w, style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (card != null) ...[
              Text(card.ru.isEmpty ? '(нет перевода)' : card.ru),
              if (card.example.isNotEmpty) Text(card.example),
            ] else
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _add(w);
                },
                child: const Text('Добавить в колоду'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(String w) async {
    final ctrl = TextEditingController();
    final ru = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Добавить: $w'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Перевод (можно пусто)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Добавить')),
        ],
      ),
    );
    ctrl.dispose();
    if (ru == null) return;
    widget.store.cards.add(WordCard(en: w, ru: ru));
    await widget.store.save();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final style = Theme.of(context).textTheme.bodyLarge;
    return Scaffold(
      appBar: AppBar(title: const Text('Чтение')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: input,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Вставьте текст на английском',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _split, child: const Text('Показать текст')),
          if (t != null) ...[
            const SizedBox(height: 8),
            Text(_coverage()),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Text.rich(TextSpan(
                  style: style,
                  children: [for (final p in t) _span(p.$1, p.$2, style)],
                )),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
