import 'dart:convert';
import 'package:http/http.dart' as http;
import 'model.dart';

/// Настройки любого OpenAI-совместимого провайдера.
class AiConfig {
  String baseUrl;
  String apiKey;
  String model;

  AiConfig({this.baseUrl = 'https://api.openai.com/v1', this.apiKey = '', this.model = 'gpt-4o-mini'});

  bool get ok => apiKey.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {'baseUrl': baseUrl, 'apiKey': apiKey, 'model': model};

  factory AiConfig.fromJson(Map<String, dynamic> j) => AiConfig(
        baseUrl: j['baseUrl'] ?? 'https://api.openai.com/v1',
        apiKey: j['apiKey'] ?? '',
        model: j['model'] ?? 'gpt-4o-mini',
      );
}

class Ai {
  final AiConfig cfg;
  Ai(this.cfg);

  Future<String> chat(String system, String user, {double temperature = 0.4}) async {
    final base = cfg.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final res = await http
        .post(
          Uri.parse('$base/chat/completions'),
          headers: {'Authorization': 'Bearer ${cfg.apiKey.trim()}', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': cfg.model.trim(),
            'temperature': temperature,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          }),
        )
        .timeout(const Duration(seconds: 90));

    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) throw Exception('Ошибка ИИ ${res.statusCode}: $body');
    final data = jsonDecode(body);
    return (data['choices'][0]['message']['content'] as String).trim();
  }

  Future<dynamic> chatJson(String system, String user) async {
    var text = await chat(system, user, temperature: 0.2);
    text = text
        .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '')
        .replaceAll(RegExp(r'```\s*$', multiLine: true), '')
        .trim();
    return jsonDecode(text);
  }

  Future<WordCard> enrich(WordCard c) async {
    final j = await chatJson(
      'You are an English teacher for Russian speakers. Reply with JSON only, no markdown: '
      '{"ru": "short Russian translation", "example": "one natural English sentence under 15 words", '
      '"kind": "word or phrase"}',
      'Word or phrase: ${c.en}',
    );
    c.ru = (j['ru'] ?? c.ru).toString();
    c.example = (j['example'] ?? c.example).toString();
    c.kind = (j['kind'] ?? c.kind).toString();
    return c;
  }

  Future<String> mnemonic(WordCard c) => chat(
        'Ты помогаешь русскоязычному ученику запоминать английские слова. Ответ на русском, не более 60 слов, без вступлений. '
        'Дай: созвучие с русским словом (keyword), яркий абсурдный образ, связывающий созвучие со значением, '
        'и если уместно — этимологию или части слова.',
        'Слово: ${c.en}\nПеревод: ${c.ru}\nПример: ${c.example}',
      );
}
