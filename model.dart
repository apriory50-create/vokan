import 'dart:math';

enum Grade { again, hard, good, easy }

String _newId() => '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

class WordCard {
  final String id;
  final String en;
  String ru;
  String example;
  String kind; // word | phrase
  String mnemonic;
  String cefr; // уровень, например B1
  double ease;
  int interval; // дни
  int reps;
  int lapses;
  int due; // epoch ms

  WordCard({required this.en, this.ru = '', this.example = '', this.kind = 'word', this.mnemonic = '', this.cefr = ''})
      : id = _newId(),
        ease = 2.5,
        interval = 0,
        reps = 0,
        lapses = 0,
        due = DateTime.now().millisecondsSinceEpoch;

  WordCard.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? _newId(),
        en = j['en'],
        ru = j['ru'] ?? '',
        example = j['example'] ?? '',
        kind = j['kind'] ?? 'word',
        mnemonic = j['mnemonic'] ?? '',
        cefr = j['cefr'] ?? '',
        ease = (j['ease'] ?? 2.5).toDouble(),
        interval = j['interval'] ?? 0,
        reps = j['reps'] ?? 0,
        lapses = j['lapses'] ?? 0,
        due = j['due'] ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'en': en,
        'ru': ru,
        'example': example,
        'kind': kind,
        'mnemonic': mnemonic,
        'cefr': cefr,
        'ease': ease,
        'interval': interval,
        'reps': reps,
        'lapses': lapses,
        'due': due,
      };

  bool get isNew => reps == 0 && lapses == 0 && interval == 0;
  bool get isDue => due <= DateTime.now().millisecondsSinceEpoch;
}

/// Упрощённый SM-2.
void review(WordCard c, Grade g) {
  final q = switch (g) {
    Grade.again => 1,
    Grade.hard => 3,
    Grade.good => 4,
    Grade.easy => 5,
  };
  final now = DateTime.now();

  if (q < 3) {
    c.lapses++;
    c.reps = 0;
    c.interval = 1;
    c.due = now.add(const Duration(minutes: 10)).millisecondsSinceEpoch;
  } else {
    c.reps++;
    if (c.reps == 1) {
      c.interval = 1;
    } else if (c.reps == 2) {
      c.interval = 3;
    } else {
      c.interval = (c.interval * c.ease).round();
    }
    if (g == Grade.hard) c.interval = max(1, (c.interval * 0.7).round());
    if (g == Grade.easy) c.interval = (c.interval * 1.3).round() + 1;
    c.due = now.add(Duration(days: c.interval)).millisecondsSinceEpoch;
  }

  final d = 5 - q;
  c.ease = max(1.3, c.ease + 0.1 - d * (0.08 + d * 0.02));
}
