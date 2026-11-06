import '../../../core/models/agent/agent_profile.dart';
import '../../../core/models/dictionary_sample.dart';

/// Local analysis of one bounded dictionary sample.
///
/// Language pairs and coverage metrics are deterministic and never call a
/// model; the profile model only supplies descriptive fields and a language
/// hint that can disambiguate Han-only samples.
class DictionarySampleAnalysis {
  const DictionarySampleAnalysis({
    required this.languagePairs,
    required this.coverage,
  });

  final List<DictionaryLanguagePair> languagePairs;
  final DictionaryCoverage coverage;
}

DictionarySampleAnalysis analyzeDictionarySample(
  DictionarySample sample, {
  List<String> modelLanguages = const <String>[],
}) {
  final languages = _normalizeLanguages(modelLanguages);
  final headwords = _countScripts(
    sample.entries.map((entry) => entry.headword),
  );
  final definitions = _countScripts(
    sample.entries.map((entry) => entry.snippet),
  );
  return DictionarySampleAnalysis(
    languagePairs: _detectLanguagePairs(
      title: sample.metadata.title,
      headwords: headwords,
      definitions: definitions,
      modelLanguages: languages,
    ),
    coverage: DictionaryCoverage(
      sampleEntries: sample.entries.length,
      entryCount: sample.metadata.entryCount,
      headwordScripts: _scriptLabels(headwords),
      definitionScripts: _scriptLabels(definitions),
      featureCount: _featureCount(sample.entries),
    ),
  );
}

const _latinLanguages = <String>{
  'en',
  'fr',
  'de',
  'es',
  'it',
  'pt',
  'nl',
  'sv',
  'da',
  'no',
  'fi',
  'pl',
  'tr',
  'id',
  'vi',
  'ms',
};

const _scriptOrder = <String>[
  'han',
  'hiragana',
  'katakana',
  'latin',
  'hangul',
  'cyrillic',
  'greek',
  'thai',
  'arabic',
];

class _ScriptCounts {
  int han = 0;
  int hiragana = 0;
  int katakana = 0;
  int latin = 0;
  int hangul = 0;
  int cyrillic = 0;
  int greek = 0;
  int thai = 0;
  int arabic = 0;

  int get kana => hiragana + katakana;
}

_ScriptCounts _countScripts(Iterable<String> texts) {
  final counts = _ScriptCounts();
  for (final text in texts) {
    for (final rune in text.runes) {
      if (_isHiragana(rune)) {
        counts.hiragana++;
      } else if (_isKatakana(rune)) {
        counts.katakana++;
      } else if (_isHan(rune)) {
        counts.han++;
      } else if (_isHangul(rune)) {
        counts.hangul++;
      } else if (_isCyrillic(rune)) {
        counts.cyrillic++;
      } else if (_isGreek(rune)) {
        counts.greek++;
      } else if (_isThai(rune)) {
        counts.thai++;
      } else if (_isArabic(rune)) {
        counts.arabic++;
      } else if (_isLatin(rune)) {
        counts.latin++;
      }
    }
  }
  return counts;
}

List<String> _scriptLabels(_ScriptCounts counts) {
  final present = <String>{
    if (counts.han > 0) 'han',
    if (counts.hiragana > 0) 'hiragana',
    if (counts.katakana > 0) 'katakana',
    if (counts.latin > 0) 'latin',
    if (counts.hangul > 0) 'hangul',
    if (counts.cyrillic > 0) 'cyrillic',
    if (counts.greek > 0) 'greek',
    if (counts.thai > 0) 'thai',
    if (counts.arabic > 0) 'arabic',
  };
  return <String>[
    for (final script in _scriptOrder)
      if (present.contains(script)) script,
  ];
}

int _featureCount(List<DictionarySampleEntry> entries) {
  if (entries.isEmpty) return 0;
  var count = 0;
  if (entries.any((entry) => entry.features.hasRuby)) count++;
  if (entries.any((entry) => entry.features.hasKanjiInfo)) count++;
  if (entries.any((entry) => entry.features.hasExamples)) count++;
  if (entries.any((entry) => entry.features.hasAudio)) count++;
  if (entries.any((entry) => entry.features.hasImages)) count++;
  if (entries.any((entry) => entry.features.hasTables)) count++;
  return count;
}

List<String> _normalizeLanguages(Iterable<String> raw) {
  final result = <String>[];
  for (final value in raw) {
    final normalized = _normalizeLanguage(value);
    if (normalized == null || result.contains(normalized)) continue;
    result.add(normalized);
  }
  return result;
}

String? _normalizeLanguage(String raw) {
  final value = raw.trim().toLowerCase().replaceAll('_', '-');
  final base = value.split('-').first;
  return switch (base) {
    'ja' || 'jp' || 'jpn' => 'ja',
    'zh' || 'zho' || 'chi' || 'chs' || 'cht' || 'cmn' => 'zh',
    'en' || 'eng' => 'en',
    'ko' || 'kor' => 'ko',
    'ru' || 'rus' => 'ru',
    'fr' || 'fra' || 'fre' => 'fr',
    'de' || 'deu' || 'ger' => 'de',
    'es' || 'spa' => 'es',
    'it' || 'ita' => 'it',
    'pt' || 'por' => 'pt',
    'vi' || 'vie' => 'vi',
    'th' || 'tha' => 'th',
    'ar' || 'ara' => 'ar',
    'el' || 'ell' || 'gre' => 'el',
    _ => base.length == 2 ? base : null,
  };
}

List<DictionaryLanguagePair> _detectLanguagePairs({
  required String title,
  required _ScriptCounts headwords,
  required _ScriptCounts definitions,
  required List<String> modelLanguages,
}) {
  final source = _sourceLanguage(headwords, modelLanguages);
  final target = _targetLanguage(definitions, modelLanguages);
  final hints = _titleHintPairs(title);
  final fromHints = <DictionaryLanguagePair>[];
  // A multi-script title intentionally lists several targets (for example
  // 日中英); keep all of them even if one sample happens to lean toward one
  // target script. For a single hint, strong script evidence wins over a
  // misleading title token.
  final keepAllHints = hints.length > 1;
  for (final hint in hints) {
    if (!keepAllHints &&
        source != null &&
        target != null &&
        (source != hint.source || target != hint.target)) {
      continue;
    }
    var confidence = hint.confidence;
    if (source == hint.source) confidence += 0.25;
    if (target == hint.target) confidence += 0.2;
    if (modelLanguages.contains(hint.source) &&
        modelLanguages.contains(hint.target)) {
      confidence += 0.1;
    }
    fromHints.add(
      DictionaryLanguagePair(
        source: hint.source,
        target: hint.target,
        confidence: confidence.clamp(0, 0.95).toDouble(),
      ),
    );
  }
  if (fromHints.isNotEmpty) return _dedupePairs(fromHints);

  if (source != null && target != null) {
    var confidence = 0.55;
    if (modelLanguages.contains(source)) confidence += 0.1;
    if (modelLanguages.contains(target)) confidence += 0.1;
    if (source == target) confidence += 0.05;
    return <DictionaryLanguagePair>[
      DictionaryLanguagePair(
        source: source,
        target: target,
        confidence: confidence.clamp(0, 0.9).toDouble(),
      ),
    ];
  }

  // The profile model's LANGUAGES tag is the bounded fallback when the local
  // script evidence is insufficient.
  if (modelLanguages.length >= 2) {
    return <DictionaryLanguagePair>[
      DictionaryLanguagePair(
        source: modelLanguages.first,
        target: modelLanguages.last,
        confidence: 0.45,
      ),
    ];
  }
  if (modelLanguages.length == 1 && source != null) {
    return <DictionaryLanguagePair>[
      DictionaryLanguagePair(
        source: source,
        target: modelLanguages.first,
        confidence: 0.4,
      ),
    ];
  }
  return const <DictionaryLanguagePair>[];
}

String? _sourceLanguage(_ScriptCounts counts, List<String> modelLanguages) {
  if (counts.kana > 0) return 'ja';
  if (counts.hangul > 0) return 'ko';
  if (counts.cyrillic > 0) return 'ru';
  if (counts.thai > 0) return 'th';
  if (counts.arabic > 0) return 'ar';
  if (counts.greek > 0) return 'el';
  if (counts.han > 0 && counts.han >= counts.latin) {
    if (modelLanguages.contains('ja') && !modelLanguages.contains('zh')) {
      return 'ja';
    }
    if (modelLanguages.contains('zh')) return 'zh';
    return null;
  }
  if (counts.latin > 0) {
    for (final language in modelLanguages) {
      if (_latinLanguages.contains(language)) return language;
    }
    return 'en';
  }
  return null;
}

String? _targetLanguage(_ScriptCounts counts, List<String> modelLanguages) {
  if (counts.kana > 0) return 'ja';
  if (counts.hangul > 0) return 'ko';
  if (counts.cyrillic > 0) return 'ru';
  if (counts.thai > 0) return 'th';
  if (counts.arabic > 0) return 'ar';
  if (counts.greek > 0) return 'el';
  if (counts.han > 0 && counts.han >= counts.latin) return 'zh';
  if (counts.latin > 0) {
    for (final language in modelLanguages) {
      if (_latinLanguages.contains(language)) return language;
    }
    return 'en';
  }
  if (counts.han > 0) return 'zh';
  return null;
}

List<DictionaryLanguagePair> _titleHintPairs(String title) {
  final text = title.toLowerCase();
  const scriptLanguage = <String, String>{'日': 'ja', '中': 'zh', '英': 'en'};

  // A three-script title such as 日中英 can otherwise produce contradictory
  // two-character hints (日中, 中英, ...). Treat the first script as source.
  final triple = RegExp(r'([日中英])([日中英])([日中英])').firstMatch(text);
  if (triple != null) {
    final source = scriptLanguage[triple.group(1)]!;
    final targets = <String>{
      scriptLanguage[triple.group(2)]!,
      scriptLanguage[triple.group(3)]!,
    }..remove(source);
    return <DictionaryLanguagePair>[
      for (final target in targets)
        DictionaryLanguagePair(
          source: source,
          target: target,
          confidence: 0.55,
        ),
    ];
  }

  final pairs = <DictionaryLanguagePair>[];
  void add(String source, String target) {
    if (pairs.any((pair) => pair.source == source && pair.target == target)) {
      return;
    }
    pairs.add(
      DictionaryLanguagePair(source: source, target: target, confidence: 0.55),
    );
  }

  if (text.contains('日中') || text.contains('日汉') || text.contains('日漢')) {
    add('ja', 'zh');
  }
  if (text.contains('中日') || text.contains('汉日') || text.contains('漢日')) {
    add('zh', 'ja');
  }
  if (text.contains('日英') || text.contains('和英')) add('ja', 'en');
  if (text.contains('英和') || text.contains('英日')) add('en', 'ja');
  if (text.contains('英汉') || text.contains('英漢') || text.contains('英中')) {
    add('en', 'zh');
  }
  if (text.contains('汉英') || text.contains('漢英') || text.contains('中英')) {
    add('zh', 'en');
  }
  if (text.contains('日日') ||
      text.contains('国語') ||
      text.contains('国语') ||
      text.contains('漢和') ||
      text.contains('汉和')) {
    add('ja', 'ja');
  }
  if (text.contains('英英')) add('en', 'en');

  if (text.contains('japanese-english') || text.contains('japanese english')) {
    add('ja', 'en');
  }
  if (text.contains('english-japanese') || text.contains('english japanese')) {
    add('en', 'ja');
  }
  if (text.contains('japanese-chinese') || text.contains('japanese chinese')) {
    add('ja', 'zh');
  }
  if (text.contains('chinese-japanese') || text.contains('chinese japanese')) {
    add('zh', 'ja');
  }
  if (text.contains('english-chinese') || text.contains('english chinese')) {
    add('en', 'zh');
  }
  if (text.contains('chinese-english') || text.contains('chinese english')) {
    add('zh', 'en');
  }
  return pairs;
}

List<DictionaryLanguagePair> _dedupePairs(
  Iterable<DictionaryLanguagePair> pairs,
) {
  final seen = <String>{};
  final result = <DictionaryLanguagePair>[];
  for (final pair in pairs) {
    if (pair.source.isEmpty || pair.target.isEmpty) continue;
    if (!seen.add('${pair.source}|${pair.target}')) continue;
    result.add(pair);
  }
  result.sort((a, b) => b.confidence.compareTo(a.confidence));
  return result.take(3).toList(growable: false);
}

bool _isHiragana(int rune) => rune >= 0x3040 && rune <= 0x309F;

bool _isKatakana(int rune) =>
    (rune >= 0x30A0 && rune <= 0x30FF) ||
    (rune >= 0x31F0 && rune <= 0x31FF) ||
    (rune >= 0xFF66 && rune <= 0xFF9F);

bool _isHan(int rune) =>
    (rune >= 0x3400 && rune <= 0x4DBF) ||
    (rune >= 0x4E00 && rune <= 0x9FFF) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0x20000 && rune <= 0x2FA1F);

bool _isLatin(int rune) =>
    (rune >= 0x0041 && rune <= 0x005A) ||
    (rune >= 0x0061 && rune <= 0x007A) ||
    (rune >= 0x00C0 && rune <= 0x024F) ||
    (rune >= 0x1E00 && rune <= 0x1EFF);

bool _isHangul(int rune) =>
    (rune >= 0x1100 && rune <= 0x11FF) ||
    (rune >= 0x3130 && rune <= 0x318F) ||
    (rune >= 0xAC00 && rune <= 0xD7AF);

bool _isCyrillic(int rune) =>
    (rune >= 0x0400 && rune <= 0x04FF) || (rune >= 0x0500 && rune <= 0x052F);

bool _isGreek(int rune) =>
    (rune >= 0x0370 && rune <= 0x03FF) || (rune >= 0x1F00 && rune <= 0x1FFF);

bool _isThai(int rune) => rune >= 0x0E00 && rune <= 0x0E7F;

bool _isArabic(int rune) =>
    (rune >= 0x0600 && rune <= 0x06FF) ||
    (rune >= 0x0750 && rune <= 0x077F) ||
    (rune >= 0x08A0 && rune <= 0x08FF);
