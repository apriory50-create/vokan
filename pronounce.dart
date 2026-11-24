import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'model.dart';
import 'store.dart';

String normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z' ]"), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int _lev(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// 0..1: насколько распознанная фраза похожа на эталон.
double similarity(String target, String said) {
  final a = normalize(target);
  final b = normalize(said);
  if (a.isEmpty) return 0;
  return max(0, 1 - _lev(a, b) / max(a.length, b.length));
}

// ---------- Произношение: слово + микрофон ----------

class PronounceScreen extends StatefulWidget {
  final Store store;
  const PronounceScreen({super.key, required this.store});
  @override
  State<PronounceScreen> createState() => _PronounceState();
}

class _PronounceState extends State<PronounceScreen> {
  final tts = FlutterTts();
  final speech = stt.SpeechToText();
  final rnd = Random();
  WordCard? card;
  bool listening = false;
  String? heard;
  double? score;

  @override
  void initState() {
    super.initState();
    tts.setLanguage('en-US');
    _roll();
  }

  @override
  void dispose() {
    tts.stop();
    speech.cancel();
    super.dispose();
  }

  void _roll() {
    final pool = widget.store.cards;
    card = pool.isEmpty ? null : pool[rnd.nextInt(pool.length)];
    heard = null;
    score = null;
    listening = false;
    if (mounted) setState(() {});
  }

  Future<void> _listen() async {
    final ok = await speech.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) setState(() => listening = false);
      },
    );
    if (!ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Распознавание речи недоступно на этом устройстве')));
      return;
    }
    setState(() {
      listening = true;
      heard = null;
      score = null;
    });
    await speech.listen(
      localeId: 'en_US',
      listenFor: const Duration(seconds: 6),
      pauseFor: const Duration(seconds: 2),
      onResult: (r) {
        if (!mounted) return;
        setState(() {
          heard = r.recognizedWords;
          if (r.finalResult) {
            listening = false;
            score = similarity(card!.en, r.recognizedWords);
          }
        });
      },
    );
  }

  String _verdict(double s) {
    if (s >= 0.9) return 'Отлично!';
    if (s >= 0.7) return 'Почти. Повторите медленнее.';
    return 'Не совпало. Послушайте ещё раз и повторите.';
  }

  @override
  Widget build(BuildContext context) {
    final c = card;
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Произношение')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: c == null
            ? const Center(child: Text('В базе пока нет слов'))
            : Column(children: [
                const Spacer(),
                Text(c.en, style: theme.displaySmall, textAlign: TextAlign.center),
                if (c.ru.isNotEmpty) Text(c.ru, style: theme.titleMedium),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => tts.speak(c.en),
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Послушать'),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: listening ? null : _listen,
                  icon: Icon(listening ? Icons.hearing : Icons.mic),
                  label: Text(listening ? 'Слушаю...' : 'Сказать'),
                ),
                const SizedBox(height: 16),
                if (heard != null) Text('Вы сказали: "$heard"', textAlign: TextAlign.center),
                if (score != null) ...[
                  const SizedBox(height: 8),
                  Text('Совпадение: ${(score! * 100).round()}%', style: theme.titleMedium),
                  Text(_verdict(score!), textAlign: TextAlign.center),
                ],
                const Spacer(),
                TextButton(onPressed: _roll, child: const Text('Следующее слово')),
              ]),
      ),
    );
  }
}

// ---------- Минимальные пары ----------

const _pairs = <List<String>>[
  ['ship', 'sheep'], ['light', 'right'], ['bit', 'beat'], ['full', 'fool'], ['cat', 'cut'],
  ['think', 'sink'], ['very', 'berry'], ['bad', 'bed'], ['live', 'leave'], ['pen', 'pan'],
  ['hat', 'hut'], ['wall', 'well'], ['thing', 'sing'], ['cot', 'caught'], ['work', 'walk'],
  ['bat', 'bet'], ['fan', 'fun'], ['look', 'luck'], ['late', 'rate'], ['cheap', 'chip'],
];

class MinimalPairsScreen extends StatefulWidget {
  const MinimalPairsScreen({super.key});
  @override
  State<MinimalPairsScreen> createState() => _PairsState();
}

class _PairsState extends State<MinimalPairsScreen> {
  final tts = FlutterTts();
  final rnd = Random();
  late List<String> pair;
  late String target;
  String? answer;
  int right = 0;
  int total = 0;

  @override
  void initState() {
    super.initState();
    tts.setLanguage('en-US');
    _roll();
  }

  @override
  void dispose() {
    tts.stop();
    super.dispose();
  }

  void _roll() {
    pair = _pairs[rnd.nextInt(_pairs.length)];
    target = pair[rnd.nextInt(2)];
    answer = null;
  }

  Future<void> _play() async {
    await tts.setSpeechRate(0.35);
    await tts.speak(target);
  }

  void _next() {
    setState(_roll);
    _play();
  }

  void _pick(String w) {
    if (answer != null) return;
    setState(() {
      answer = w;
      total++;
      if (w == target) right++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final done = answer != null;
    return Scaffold(
      appBar: AppBar(title: Text('Минимальные пары: $right из $total')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Spacer(),
          FilledButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.volume_up),
            label: const Text('Прослушать'),
          ),
          const SizedBox(height: 24),
          Row(children: [
            for (final w in pair)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: done && w == target ? Colors.green.shade200 : null,
                    ),
                    onPressed: () => _pick(w),
                    child: Text(w, style: theme.titleLarge),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          if (done)
            Text(
              answer == target ? 'Верно!' : 'Нет, было: $target',
              style: theme.titleMedium,
            ),
          const Spacer(),
          if (done) FilledButton(onPressed: _next, child: const Text('Далее')),
        ]),
      ),
    );
  }
}
