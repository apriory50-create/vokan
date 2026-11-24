import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'ai.dart';
import 'model.dart';

class Store {
  static const _cardsKey = 'cards_v1';
  static const _aiKey = 'ai_v1';
  static const _grammarKey = 'grammar_v1';
  static const _bundleKey = 'bundle_fp';

  final SharedPreferences _prefs;
  final List<WordCard> cards;
  AiConfig ai;
  Map<String, List<int>> grammar = {};

  Store._(this._prefs, this.cards, this.ai);

  static Future<Store> open() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_cardsKey);
    final cards = raw == null
        ? <WordCard>[]
        : (jsonDecode(raw) as List).map((e) => WordCard.fromJson(e as Map<String, dynamic>)).toList();
    final aiRaw = p.getString(_aiKey);
    final ai = aiRaw == null ? AiConfig() : AiConfig.fromJson(jsonDecode(aiRaw) as Map<String, dynamic>);
    final store = Store._(p, cards, ai);
    final gRaw = p.getString(_grammarKey);
    if (gRaw != null) {
      store.grammar = (jsonDecode(gRaw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, List<int>.from(v as List)));
    }
    return store;
  }

  Future<void> save() => _prefs.setString(_cardsKey, jsonEncode(cards.map((c) => c.toJson()).toList()));

  Future<void> saveAi(AiConfig c) {
    ai = c;
    return _prefs.setString(_aiKey, jsonEncode(c.toJson()));
  }

  Future<void> saveGrammar() => _prefs.setString(_grammarKey, jsonEncode(grammar));

  /// Строка формата "слово|перевод|пример|уровень".
  WordCard? _fromLine(String line) {
    final p = line.split('|');
    if (p.length < 2 || p[0].trim().isEmpty) return null;
    final en = p[0].trim();
    return WordCard(
      en: en,
      ru: p[1].trim(),
      example: p.length > 2 ? p[2].trim() : '',
      cefr: p.length > 3 ? p[3].trim() : '',
      kind: en.contains(' ') ? 'phrase' : 'word',
    );
  }

  static String _fingerprint(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return '$h:${s.length}';
  }

  /// Части словаря: лежат в assets/words/. Новую часть добавьте сюда и в pubspec (папка assets/words/ уже подключена).
  static const _wordFiles = [
    'assets/words/01_everyday.txt',
    'assets/words/02_travel_people.txt',
    'assets/words/03_phrasal_collocations.txt',
    'assets/words/04_b1_b2_extra.txt',
    'assets/words/10_general_a.txt',
    'assets/words/11_general_b.txt',
    'assets/words/20_tech.txt',
    'assets/words/05_dev_ui_extra.txt',
  ];

  /// Подгрузка слов из assets: все файлы из [_wordFiles] и seed.json.
  /// Выполняется, когда содержимое файлов изменилось (проверяется отпечаток).
  /// Новые слова добавляются; существующие и их прогресс не меняются.
  Future<int> syncBundled() async {
    final texts = <String>[];
    for (final f in _wordFiles) {
      try {
        texts.add(await rootBundle.loadString(f));
      } catch (_) {}
    }
    var seed = '';
    try {
      seed = await rootBundle.loadString('assets/seed.json');
    } catch (_) {}

    final fp = '${texts.map(_fingerprint).join(',')}|${_fingerprint(seed)}';
    if (_prefs.getString(_bundleKey) == fp) return 0;

    final known = cards.map((c) => c.en.toLowerCase()).toSet();
    var added = 0;
    void addAll(Iterable<WordCard> items) {
      for (final c in items) {
        if (known.add(c.en.toLowerCase())) {
          cards.add(c);
          added++;
        }
      }
    }

    for (final t in texts) {
      addAll(t.split('\n').map(_fromLine).whereType<WordCard>());
    }
    if (seed.isNotEmpty) {
      try {
        addAll((jsonDecode(seed) as List).map((e) => WordCard.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }

    await _prefs.setString(_bundleKey, fp);
    await save();
    return added;
  }

  /// Импорт: JSON-массив карточек или строки "слово;перевод;пример". Возвращает число добавленных.
  int importText(String text) {
    final t = text.trim();
    final incoming = <WordCard>[];
    if (t.startsWith('[')) {
      for (final e in jsonDecode(t) as List) {
        incoming.add(WordCard.fromJson(e as Map<String, dynamic>));
      }
    } else {
      for (final line in t.split('\n')) {
        final p = line.split(';');
        if (p[0].trim().isEmpty) continue;
        incoming.add(WordCard(
          en: p[0].trim(),
          ru: p.length > 1 ? p[1].trim() : '',
          example: p.length > 2 ? p.sublist(2).join(';').trim() : '',
        ));
      }
    }
    var added = 0;
    for (final c in incoming) {
      if (!cards.any((x) => x.en.toLowerCase() == c.en.toLowerCase())) {
        cards.add(c);
        added++;
      }
    }
    return added;
  }
}
