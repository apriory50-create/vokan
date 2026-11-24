import 'dart:math';
import 'package:flutter/material.dart';
import 'ai.dart';
import 'grammar.dart';
import 'store.dart';

void _snack(BuildContext c, String t) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

/// Статистика хранится как [правильно, ошибок] по теме.
void recordGrammar(Store s, String topic, {int correct = 0, int errors = 0}) {
  final v = s.grammar.putIfAbsent(topic, () => [0, 0]);
  v[0] += correct;
  v[1] += errors;
}

String rateText(Store s, String topic) {
  final v = s.grammar[topic];
  if (v == null || v[0] + v[1] < 3) return 'мало данных';
  return 'доля ошибок: ${(v[1] * 100 / (v[0] + v[1])).round()}%';
}

String? weakestTopic(Store s) {
  String? best;
  var bestRate = -1.0;
  for (final t in grammarTopics) {
    final v = s.grammar[t.id];
    if (v == null || v[0] + v[1] < 3) continue;
    final r = v[1] / (v[0] + v[1]);
    if (r > bestRate) {
      bestRate = r;
      best = t.id;
    }
  }
  return best;
}

// ---------- Список тем ----------

class GrammarScreen extends StatefulWidget {
  final Store store;
  const GrammarScreen({super.key, required this.store});
  @override
  State<GrammarScreen> createState() => _GrammarState();
}

class _GrammarState extends State<GrammarScreen> {
  Future<void> _open(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final weak = weakestTopic(s);
    final weakTitle = weak == null ? null : grammarTopics.firstWhere((t) => t.id == weak).title;
    return Scaffold(
      appBar: AppBar(title: const Text('Грамматика')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (weakTitle != null)
          Card(child: ListTile(title: const Text('Слабая тема'), subtitle: Text(weakTitle))),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => _open(PracticeScreen(store: s)), child: const Text('Практика: все темы')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => _open(CheckTextScreen(store: s)), child: const Text('Проверить мой текст (ИИ)')),
        const SizedBox(height: 16),
        for (final t in grammarTopics)
          ListTile(
            title: Text(t.title),
            subtitle: Text(rateText(s, t.id)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(TopicScreen(store: s, topic: t)),
          ),
      ]),
    );
  }
}

// ---------- Правило темы ----------

class TopicScreen extends StatelessWidget {
  final Store store;
  final GrammarTopic topic;
  const TopicScreen({super.key, required this.store, required this.topic});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(topic.title)),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(topic.rule, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PracticeScreen(store: store, topic: topic.id)),
              ),
              child: const Text('Практика по теме'),
            ),
          ]),
        ),
      );
}

// ---------- Практика ----------

class PracticeScreen extends StatefulWidget {
  final Store store;
  final String? topic; // null — все темы
  const PracticeScreen({super.key, required this.store, this.topic});
  @override
  State<PracticeScreen> createState() => _PracticeState();
}

class _PracticeState extends State<PracticeScreen> {
  final rnd = Random();
  late final List<Exercise> queue;
  int i = 0;
  int correct = 0;
  int? picked;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    queue = builtinExercises
        .where((e) => widget.topic == null || e.topic == widget.topic)
        .toList()
      ..shuffle(rnd);
  }

  Exercise get ex => queue[i];
  bool get finished => i >= queue.length;

  Future<void> _pick(int idx) async {
    if (picked != null) return;
    final wrong = idx != ex.answer;
    setState(() {
      picked = idx;
      if (!wrong) correct++;
    });
    recordGrammar(widget.store, ex.topic, correct: wrong ? 0 : 1, errors: wrong ? 1 : 0);
    await widget.store.saveGrammar();
  }

  void _next() => setState(() {
        i++;
        picked = null;
      });

  Future<void> _more() async {
    final ai = widget.store.ai;
    if (!ai.ok) {
      _snack(context, 'Укажите ключ API в настройках');
      return;
    }
    GrammarTopic? topic;
    for (final t in grammarTopics) {
      if (t.id == widget.topic) topic = t;
    }
    final ids = grammarTopics.map((t) => t.id).join(', ');
    setState(() => loading = true);
    try {
      final data = await Ai(ai).chatJson(
        'You create English grammar exercises for a Russian-speaking learner at B1-C1. Reply with JSON only, no markdown. '
        'Format: [{"topic":"<topic id>","sentence":"sentence with exactly one ___ blank",'
        '"options":["a","b","c"],"answer":<0-based index of the correct option>,'
        '"why":"короткое объяснение по-русски"}]. Allowed topic ids: $ids. '
        'Make wrong options plausible. Exactly 5 items.',
        topic == null
            ? 'Mixed topics.'
            : 'Topic id: ${topic.id}. Rule: ${topic.rule}',
      );
      final list = (data as List)
          .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
          .whereType<Exercise>()
          .where((e) => topic == null || e.topic == topic.id)
          .toList();
      setState(() => queue.addAll(list));
      if (list.isEmpty && mounted) _snack(context, 'ИИ не вернул подходящих упражнений');
    } catch (e) {
      if (mounted) _snack(context, '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Практика')),
      body: finished
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Результат: $correct из ${queue.length}', style: t.headlineSmall),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: loading ? null : _more,
                  child: Text(loading ? 'Генерирую...' : 'Ещё 5 упражнений (ИИ)'),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Назад')),
              ]),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text('${i + 1} / ${queue.length}'),
                const Spacer(),
                Text(ex.sentence, style: t.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                for (var k = 0; k < ex.options.length; k++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: picked == null
                              ? null
                              : (k == ex.answer
                                  ? Colors.green.shade200
                                  : (k == picked ? Colors.red.shade200 : null)),
                        ),
                        onPressed: () => _pick(k),
                        child: Text(ex.options[k]),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (picked != null)
                  Text(
                    picked == ex.answer ? 'Верно! ${ex.why}' : 'Неверно. ${ex.why}',
                    textAlign: TextAlign.center,
                  ),
                const Spacer(),
                if (picked != null) FilledButton(onPressed: _next, child: const Text('Далее')),
              ]),
            ),
    );
  }
}

// ---------- Проверка своего текста ----------

class CheckTextScreen extends StatefulWidget {
  final Store store;
  const CheckTextScreen({super.key, required this.store});
  @override
  State<CheckTextScreen> createState() => _CheckState();
}

class _CheckState extends State<CheckTextScreen> {
  final input = TextEditingController();
  bool busy = false;
  List<Map<String, dynamic>> errors = [];
  String corrected = '';
  bool checked = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    if (!widget.store.ai.ok) {
      _snack(context, 'Укажите ключ API в настройках');
      return;
    }
    final ids = grammarTopics.map((t) => t.id).join(', ');
    setState(() {
      busy = true;
      errors = [];
      corrected = '';
      checked = false;
    });
    try {
      final j = await Ai(widget.store.ai).chatJson(
        'You check English grammar for a Russian-speaking learner (B1-C1). Reply with JSON only, no markdown: '
        '{"errors":[{"original":"wrong fragment","correct":"fixed fragment",'
        '"topic":"one of: $ids, other","explanation_ru":"краткое объяснение по-русски"}],'
        '"corrected_text":"full corrected text"}. If there are no errors, return an empty list.',
        text,
      );
      final list = ((j['errors'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (final e in list) {
        final t = (e['topic'] ?? '').toString();
        if (grammarTopics.any((g) => g.id == t)) recordGrammar(widget.store, t, errors: 1);
      }
      await widget.store.saveGrammar();
      if (!mounted) return;
      setState(() {
        errors = list;
        corrected = (j['corrected_text'] ?? '').toString();
        checked = true;
      });
    } catch (e) {
      if (mounted) _snack(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _topicTitle(String id) {
    for (final t in grammarTopics) {
      if (t.id == id) return t.title;
    }
    return 'Прочее';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Проверка текста')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: input,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Напишите несколько предложений на английском',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: busy ? null : _check,
          child: Text(busy ? 'Проверяю...' : 'Проверить'),
        ),
        const SizedBox(height: 16),
        if (checked && errors.isEmpty) const Text('Ошибок не найдено.'),
        for (final e in errors)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['original']}  →  ${e['correct']}', style: t.titleSmall),
                const SizedBox(height: 4),
                Text(_topicTitle((e['topic'] ?? '').toString()), style: t.labelMedium),
                Text((e['explanation_ru'] ?? '').toString()),
              ]),
            ),
          ),
        if (corrected.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Исправленный текст', style: t.titleSmall),
          Text(corrected),
        ],
      ]),
    );
  }
}
