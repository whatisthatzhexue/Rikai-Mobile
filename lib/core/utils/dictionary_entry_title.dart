import 'package:html/parser.dart' as html_parser;

/// Some MDict dictionaries use internal ids as entry keys (`00044`,
/// `01570 03798`, `@daijirin2-...`). Those keys are required for exact
/// lookups and redirects, but they are not human-readable entry titles.
///
/// This helper extracts a display title from the entry HTML. The key itself is
/// never rewritten: callers keep it for lookup/navigation and use the returned
/// title only for rendering.
const _cjkPattern = r'[㐀-䶿一-鿿豈-﫿]';
const _kanaPattern = r'[぀-ゟ゠-ヿ]';
final _cjk = RegExp(_cjkPattern);
final _kana = RegExp(_kanaPattern);
final _bracketTitle = RegExp(r'【([^】]{1,60})】');
final _titleClass = RegExp(
  r'(?:^|[\s_-])(headword|head[-_]?word|entry[-_]?title|entry[-_]?headword|'
  r'midashi|見出し|keyword|title|word)(?:$|[\s_-])',
  caseSensitive: false,
);

/// Labels that commonly appear in brackets but are not entry headwords.
const _bracketLabels = <String>{
  '使い方',
  '類語',
  '類義',
  '対義',
  '品格',
  '意味',
  '語源',
  '参考',
  '注意',
  '表記',
  '発音',
  'アクセント',
  '漢字',
  'かな',
  '見出し',
  '品詞',
  '活用',
  '例文',
  '慣用',
  'ことわざ',
  '成句',
  '関連',
  '同音',
  '同訓',
  '地名',
  '人名',
};

/// True when [value] looks like an internal MDict key rather than a title.
///
/// Keep this conservative: real English headwords such as `apple` or `B2B`
/// must not be treated as opaque.
bool isOpaqueDictionaryKey(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed.startsWith('@')) return true;
  if (RegExp(r'^[0-9\s._-]+$').hasMatch(trimmed)) return true;
  if (RegExp(r'^[A-Za-z0-9_.:\-]+$').hasMatch(trimmed) &&
      RegExp(r'\d').hasMatch(trimmed) &&
      trimmed.length >= 10) {
    return true;
  }
  return false;
}

/// Extracts a human-readable title from a raw MDict entry HTML fragment.
///
/// Preference order:
/// 1. a bracketed Japanese headword such as `【焼▽べる】`;
/// 2. an element whose class/id marks a headword/entry title;
/// 3. a heading/strong fallback.
///
/// Returns null when no reliable title is present.
String? extractDictionaryEntryTitle(String html) {
  if (html.trim().isEmpty) return null;
  final fragment = html_parser.parseFragment(html);
  for (final element in fragment.querySelectorAll('script, style, noscript')) {
    element.remove();
  }

  final candidates = <_TitleCandidate>[];
  var order = 0;
  void consider(String raw, int baseScore) {
    final value = _cleanTitle(raw);
    if (!_isUsableTitle(value)) return;
    var score = baseScore;
    if (_cjk.hasMatch(value)) score += 4;
    if (_kana.hasMatch(value)) score += 1;
    if (value.length <= 20) score += 2;
    if (_kana.hasMatch(value) && !_cjk.hasMatch(value)) score -= 1;
    candidates.add(_TitleCandidate(value, score, order++));
  }

  for (final element in fragment.querySelectorAll('h1, h2, h3')) {
    consider(element.text, 7);
  }
  for (final element in fragment.querySelectorAll('*')) {
    final classAndId =
        '${element.attributes['class'] ?? ''} '
                '${element.attributes['id'] ?? ''}'
            .toLowerCase();
    if (!_titleClass.hasMatch(classAndId)) continue;
    consider(element.text, 8);
  }
  for (final element in fragment.querySelectorAll('strong, b')) {
    consider(element.text, 2);
  }

  final text = fragment.text ?? '';
  var bracketCount = 0;
  for (final match in _bracketTitle.allMatches(text)) {
    final raw = match.group(1) ?? '';
    final cleaned = _cleanTitle(raw);
    if (_bracketLabels.contains(cleaned)) continue;
    consider(raw, 12);
    bracketCount++;
    // Entry HTML can contain long cross-reference lists. The main headword is
    // normally in the first few brackets; do not scan the whole definition.
    if (bracketCount >= 8) break;
  }

  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.order.compareTo(b.order);
  });
  return candidates.first.value;
}

/// Extracts a bracketed title from already-plain citation text/snippet.
///
/// Used for old history entries that were saved before display titles were
/// derived from the full entry HTML.
String? extractDictionaryEntryTitleFromText(String text) {
  if (text.trim().isEmpty) return null;
  _TitleCandidate? best;
  var order = 0;
  for (final match in _bracketTitle.allMatches(text)) {
    final value = _cleanTitle(match.group(1) ?? '');
    if (!_isUsableTitle(value) || _bracketLabels.contains(value)) continue;
    var score = 12;
    if (_cjk.hasMatch(value)) score += 4;
    if (value.length <= 20) score += 2;
    final candidate = _TitleCandidate(value, score, order++);
    if (best == null || candidate.score > best.score) best = candidate;
    if (order >= 8) break;
  }
  return best?.value;
}

/// Resolves the title to display for one dictionary entry.
///
/// [matchedKey] is preferred over [headword] only when the HTML has no title:
/// it is the key the user queried, while [headword] may be an internal redirect
/// target. Both are rejected when they look like opaque ids.
String dictionaryEntryDisplayTitle({
  required String html,
  String matchedKey = '',
  String headword = '',
}) {
  final extracted = extractDictionaryEntryTitle(html);
  final matched = matchedKey.trim();
  final head = headword.trim();
  if (extracted != null) {
    // A kana-only class/heading is usually a reading; prefer a human-readable
    // matched key when it contains kanji.
    if (_kana.hasMatch(extracted) &&
        !_cjk.hasMatch(extracted) &&
        _cjk.hasMatch(matched) &&
        !isOpaqueDictionaryKey(matched)) {
      return matched;
    }
    return extracted;
  }
  if (!isOpaqueDictionaryKey(matched)) return matched;
  if (!isOpaqueDictionaryKey(head)) return head;
  return '';
}

String _cleanTitle(String raw) {
  var value = raw
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
      .replaceAll(RegExp(r'[▽▼△▲]'), '')
      .replaceAll(' ', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  value = value.replaceAll(RegExp(r'^[\s・\-–—:：]+'), '');
  value = value.replaceAll(RegExp(r'[\s・\-–—:：]+$'), '');
  return value;
}

bool _isUsableTitle(String value) {
  if (value.isEmpty || value.length > 60) return false;
  if (isOpaqueDictionaryKey(value)) return false;
  if (value.contains(RegExp(r'[［］\[\]]'))) return false;
  return true;
}

class _TitleCandidate {
  const _TitleCandidate(this.value, this.score, this.order);

  final String value;
  final int score;
  final int order;
}
