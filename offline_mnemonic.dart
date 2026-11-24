// Офлайн-подсказка: разбор приставки и суффикса. Без ИИ и без сети.

const _prefixes = <String, String>{
  'under': 'недо-, ниже', 'over': 'пере-, сверх', 'inter': 'между', 'trans': 'через, сквозь',
  'anti': 'против', 'mis': 'неправильно', 'out': 'вне, превосходя', 'pre': 'до, заранее',
  'sub': 'под', 'non': 'не-', 'dis': 'не-, отмена', 'com': 'вместе', 'con': 'вместе',
  'un': 'не-, наоборот', 're': 'снова, заново', 'in': 'в, не-', 'im': 'в, не-',
};

const _suffixes = <String, String>{
  'tion': 'существительное-действие (-ция)', 'sion': 'существительное (-сия)',
  'ment': 'существительное-результат', 'ness': 'существительное-качество',
  'ity': 'существительное-качество', 'able': 'можно (прилагательное)',
  'ible': 'можно (прилагательное)', 'ful': 'полный (прилагательное)',
  'less': 'без (прилагательное)', 'ous': 'полный чего-то (прилагательное)',
  'ive': 'склонный к (прилагательное)', 'ize': 'делать (глагол)', 'ise': 'делать (глагол)',
  'ly': 'наречие', 'ist': 'специалист', 'er': 'тот, кто (существительное)',
  'or': 'тот, кто (существительное)', 'ing': 'действие, -ing', 'ed': 'прошедшее/причастие',
};

/// Возвращает строку вида "Части слова: un- (не-), -able (можно)" или пустую строку.
String morphHint(String word) {
  final w = word.toLowerCase().trim();
  if (w.isEmpty || w.contains(' ')) return '';
  final parts = <String>[];

  final pre = _prefixes.keys
      .where((p) => w.startsWith(p) && w.length - p.length >= 4)
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (pre.isNotEmpty) parts.add('${pre.first}- (${_prefixes[pre.first]})');

  final suf = _suffixes.keys
      .where((s) => w.endsWith(s) && w.length - s.length >= 3)
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (suf.isNotEmpty) parts.add('-${suf.first} (${_suffixes[suf.first]})');

  return parts.isEmpty ? '' : 'Части слова: ${parts.join(', ')}';
}
