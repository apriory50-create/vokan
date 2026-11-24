import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'grammar_screen.dart';
import 'offline_mnemonic.dart';
import 'pronounce.dart';
import 'reader.dart';
import 'ai.dart';
import 'model.dart';
import 'store.dart';

void snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

// ---------- Главный экран ----------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> {
  Store? store;

  @override
  void initState() {
    super.initState();
    Store.open().then((s) async {
      final n = await s.syncBundled();
      if (n > 0 && mounted) snack(context, 'Добавлено новых слов: $n');
      if (mounted) setState(() => store = s);
    });
  }

  Future<void> _go(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = store;
    return Scaffold(
      appBar: AppBar(title: const Text('English Trainer')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Слов в базе: ${s.cards.length}', style: Theme.of(context).textTheme.titleMedium),
                Text('Новых: ${s.cards.where((c) => c.isNew).length}   '
                    'На повтор сейчас: ${s.cards.where((c) => !c.isNew && c.isDue).length}'),
                const SizedBox(height: 24),
                FilledButton(onPressed: () => _go(StudyScreen(store: s)), child: const Text('Учить')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _go(AddScreen(store: s)), child: const Text('Добавить слово')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _go(ReaderScreen(store: s)), child: const Text('Читать текст')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _go(PronounceScreen(store: s)), child: const Text('Произношение')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _go(const MinimalPairsScreen()), child: const Text('Минимальные пары')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _go(GrammarScreen(store: s)), child: const Text('Грамматика')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _go(SettingsScreen(store: s)), child: const Text('Настройки ИИ')),
              ]),
            ),
    );
  }
}

// ---------- Занятие ----------

class StudyScreen extends StatefulWidget {
  final Store store;
  const StudyScreen({super.key, required this.store});
  @override
  State<StudyScreen> createState() => _StudyState();
}

class _StudyState extends State<StudyScreen> {
  late final List<WordCard> queue;
  final tts = FlutterTts();
  int i = 0;
  bool showBack = false;
  bool busy = false;
  String? mnemonic;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().millisecondsSinceEpoch;
    final cards = widget.store.cards;
    final due = cards.where((c) => !c.isNew && c.due <= now).toList()..sort((a, b) => a.due.compareTo(b.due));
    final fresh = cards.where((c) => c.isNew).take(15);
    queue = [...due, ...fresh];
    tts.setLanguage('en-US');
  }

  @override
  void dispose() {
    tts.stop();
    super.dispose();
  }

  WordCard? get card => i < queue.length ? queue[i] : null;

  Future<void> _grade(Grade g) async {
    review(card!, g);
    await widget.store.save();
    setState(() {
      i++;
      showBack = false;
      mnemonic = null;
    });
  }

  Future<void> _mnemonic() async {
    final ai = widget.store.ai;
    if (!ai.ok) {
      snack(context, 'Укажите ключ API в настройках');
      return;
    }
    setState(() => busy = true);
    try {
      final c = card!;
      if (c.mnemonic.isEmpty) c.mnemonic = await Ai(ai).mnemonic(c);
      await widget.store.save();
      if (mounted) setState(() => mnemonic = c.mnemonic);
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = card;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Занятие')),
        body: const Center(child: Text('На сегодня всё. Отлично!')),
      );
    }
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('${i + 1} / ${queue.length}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Spacer(),
          Text(c.en, style: theme.displaySmall, textAlign: TextAlign.center),
          IconButton(icon: const Icon(Icons.volume_up), onPressed: () => tts.speak(c.en)),
          if (showBack) ...[
            const SizedBox(height: 12),
            Text(c.ru.isEmpty ? '(нет перевода)' : c.ru, style: theme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(c.example, style: theme.bodyLarge, textAlign: TextAlign.center),
            if (morphHint(c.en).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(morphHint(c.en), textAlign: TextAlign.center),
            ],
            if (mnemonic != null) ...[
              const SizedBox(height: 12),
              Text(mnemonic!, textAlign: TextAlign.center),
            ],
          ],
          const Spacer(),
          if (busy) const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
          if (!showBack)
            FilledButton(
              onPressed: () => setState(() => showBack = true),
              child: const Text('Показать ответ'),
            )
          else
            Column(children: [
              Row(children: [
                Expanded(child: _gradeBtn('Снова', Grade.again, Colors.red)),
                Expanded(child: _gradeBtn('Трудно', Grade.hard, Colors.orange)),
                Expanded(child: _gradeBtn('Хорошо', Grade.good, Colors.green)),
                Expanded(child: _gradeBtn('Легко', Grade.easy, Colors.blue)),
              ]),
              TextButton(onPressed: busy ? null : _mnemonic, child: const Text('Мнемоника (ИИ, по желанию)')),
            ]),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _gradeBtn(String label, Grade g, Color color) => Padding(
        padding: const EdgeInsets.all(3),
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: () => _grade(g),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );
}

// ---------- Добавить слово ----------

class AddScreen extends StatefulWidget {
  final Store store;
  const AddScreen({super.key, required this.store});
  @override
  State<AddScreen> createState() => _AddState();
}

class _AddState extends State<AddScreen> {
  final word = TextEditingController();
  final ru = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    word.dispose();
    ru.dispose();
    super.dispose();
  }

  Future<void> _save({required bool useAi}) async {
    final en = word.text.trim();
    if (en.isEmpty) return;
    if (widget.store.cards.any((c) => c.en.toLowerCase() == en.toLowerCase())) {
      snack(context, 'Уже есть в базе');
      return;
    }
    final card = WordCard(en: en, ru: ru.text.trim());
    setState(() => busy = true);
    try {
      if (useAi) {
        if (!widget.store.ai.ok) throw Exception('Укажите ключ API в настройках');
        await Ai(widget.store.ai).enrich(card);
      }
      widget.store.cards.add(card);
      await widget.store.save();
      word.clear();
      ru.clear();
      if (mounted) snack(context, 'Добавлено: $en');
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Добавить слово')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: word, decoration: const InputDecoration(labelText: 'Слово или фраза (EN)')),
            const SizedBox(height: 12),
            TextField(controller: ru, decoration: const InputDecoration(labelText: 'Перевод (необязательно)')),
            const SizedBox(height: 20),
            if (busy) const CircularProgressIndicator(),
            if (!busy) ...[
              FilledButton(onPressed: () => _save(useAi: false), child: const Text('Сохранить')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _save(useAi: true),
                child: const Text('Сохранить и заполнить через ИИ (по желанию)'),
              ),
            ],
          ]),
        ),
      );
}

// ---------- Настройки ИИ ----------

class SettingsScreen extends StatefulWidget {
  final Store store;
  const SettingsScreen({super.key, required this.store});
  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  late final url = TextEditingController(text: widget.store.ai.baseUrl);
  late final key = TextEditingController(text: widget.store.ai.apiKey);
  late final model = TextEditingController(text: widget.store.ai.model);

  @override
  void dispose() {
    url.dispose();
    key.dispose();
    model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.store.saveAi(AiConfig(
      baseUrl: url.text.trim(),
      apiKey: key.text.trim(),
      model: model.text.trim(),
    ));
    if (mounted) snack(context, 'Сохранено');
  }

  Future<void> _export() async {
    await Clipboard.setData(ClipboardData(text: jsonEncode(widget.store.cards.map((c) => c.toJson()).toList())));
    if (mounted) snack(context, 'Скопировано в буфер');
  }

  Future<void> _import() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Импорт'),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'JSON-массив или строки: слово;перевод;пример'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Импорт')),
        ],
      ),
    );
    if (ok == true) {
      try {
        final n = widget.store.importText(ctrl.text);
        await widget.store.save();
        if (mounted) snack(context, 'Добавлено слов: $n');
      } catch (e) {
        if (mounted) snack(context, 'Ошибка импорта: $e');
      }
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Настройки ИИ')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: url, decoration: const InputDecoration(labelText: 'Base URL')),
          const SizedBox(height: 12),
          TextField(controller: key, obscureText: true, decoration: const InputDecoration(labelText: 'API-ключ')),
          const SizedBox(height: 12),
          TextField(controller: model, decoration: const InputDecoration(labelText: 'Модель')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Сохранить')),
          const SizedBox(height: 24),
          Text(
            'Работает с любым OpenAI-совместимым API. Примеры:\n'
            '• OpenAI: https://api.openai.com/v1 (модель gpt-4o-mini)\n'
            '• DeepSeek: https://api.deepseek.com/v1 (deepseek-chat)\n'
            '• Groq: https://api.groq.com/openai/v1\n'
            '• Mistral: https://api.mistral.ai/v1\n'
            '• Gemini: https://generativelanguage.googleapis.com/v1beta/openai\n'
            '• Ollama в локальной сети: http://IP_компьютера:11434/v1\n\n'
            'Ключ хранится только на этом устройстве.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Text('Данные', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _export, child: const Text('Экспорт в буфер (JSON)')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _import, child: const Text('Импорт из буфера (JSON или строки)')),
        ]),
      );
}
