import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/utils/rich_text_tags.dart';

/// Reports human-readable analysis fields that clearly do not use the selected
/// answer language. Source quotes, word forms, readings and dictionary
/// snippets are intentionally excluded from this check.
class AgentLanguageCheck {
  const AgentLanguageCheck(this.mismatchedFields);

  final List<String> mismatchedFields;

  bool get isMismatch => mismatchedFields.isNotEmpty;
}

class AgentLanguageValidator {
  const AgentLanguageValidator({
    this.minLetters = 3,
    this.kanaRatio = 0.2,
    this.latinRatio = 0.7,
    this.japaneseRatio = 0.4,
  });

  /// Fields shorter than this are ambiguous and never reported.
  final int minLetters;

  /// Kana share of all letters that indicates Japanese prose.
  final double kanaRatio;

  /// Latin share that indicates English prose when no Han characters appear.
  final double latinRatio;

  /// Han+kana share that indicates Japanese prose for an English target.
  final double japaneseRatio;

  AgentLanguageCheck check(
    AgentAnalysis analysis,
    AgentResponseLanguage language, {
    Iterable<String> allowedJapaneseTerms = const <String>[],
  }) {
    final allowed = <String>{
      for (final term in allowedJapaneseTerms)
        if (term.trim().isNotEmpty) term.trim(),
    }.toList(growable: false)..sort((a, b) => b.length.compareTo(a.length));

    String prepare(String text) {
      // Reading annotations are not prose. Remove the whole YOMI/YOMI base and
      // the bracket form (`reading【surface】`) before counting scripts.
      var prepared = stripYomiBlocks(text);
      prepared = prepared.replaceAll(RegExp(r'[^\s【】\[\]]{1,16}【[^】]*】'), ' ');
      prepared = stripYomiTags(prepared);
      prepared = _stripParentheticals(prepared);
      prepared = _stripQuotes(prepared);
      for (final term in allowed) {
        prepared = prepared.replaceAll(term, ' ');
      }
      return prepared;
    }

    final mismatched = <String>[];
    void inspect(String field, String text) {
      if (_isMismatch(prepare(text), language)) mismatched.add(field);
    }

    for (final translation in analysis.translation) {
      inspect('translation:${translation.quoteId}', translation.text);
    }
    for (final segment in analysis.segments) {
      inspect('segment:${segment.id}', segment.interpretation);
      for (final note in segment.wordNotes) {
        inspect('word:${note.surface}', note.sense);
      }
      for (final note in segment.grammarNotes) {
        inspect('grammar:${note.patternId}', note.explanation);
      }
    }
    for (final interpretation in analysis.interpretations) {
      inspect('option:${interpretation.id}', interpretation.meaning);
    }
    for (final unresolved in analysis.unresolved) {
      inspect('unresolved:${unresolved.quoteId}', unresolved.reason);
    }
    for (final supplement in analysis.modelSupplements) {
      inspect('supplement', supplement.text);
    }
    final noAnalysisReason = analysis.noAnalysisReason.trim();
    if (noAnalysisReason.isNotEmpty) {
      inspect('no_analysis', noAnalysisReason);
    }
    return AgentLanguageCheck(List<String>.unmodifiable(mismatched));
  }

  bool _isMismatch(String text, AgentResponseLanguage language) {
    final counts = _countScripts(text);
    final letters = counts.han + counts.kana + counts.latin;
    if (letters < minLetters) return false;
    final kana = counts.kana / letters;
    final latin = counts.latin / letters;
    final japanese = (counts.han + counts.kana) / letters;

    return switch (language) {
      AgentResponseLanguage.chinese =>
        (counts.kana >= 2 && kana >= kanaRatio) ||
            (counts.han == 0 && counts.latin >= 2 && latin >= latinRatio),
      AgentResponseLanguage.english =>
        (counts.kana >= 2 && kana >= kanaRatio) ||
            (japanese >= japaneseRatio && counts.han + counts.kana >= 2),
      AgentResponseLanguage.japanese =>
        counts.kana == 0 &&
            counts.han == 0 &&
            counts.latin >= 2 &&
            latin >= latinRatio,
    };
  }
}

String _stripParentheticals(String text) {
  return text
      .replaceAll(RegExp(r'（[^）]*）'), ' ')
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      // Bracket readings (`reading【surface】`) are display annotations, not
      // prose; do not count their kana as untranslated Japanese.
      .replaceAll(RegExp(r'【[^】]*】'), ' ');
}

String _stripQuotes(String text) {
  return text
      .replaceAll(RegExp(r'「[^」]*」'), ' ')
      .replaceAll(RegExp(r'『[^』]*』'), ' ')
      .replaceAll(RegExp(r'“[^”]*”'), ' ')
      .replaceAll(RegExp(r'"[^"]*"'), ' ');
}

({int han, int kana, int latin}) _countScripts(String text) {
  var han = 0;
  var kana = 0;
  var latin = 0;
  for (final rune in text.runes) {
    if (_isHan(rune)) {
      han++;
    } else if (_isKana(rune)) {
      kana++;
    } else if (_isLatin(rune)) {
      latin++;
    }
  }
  return (han: han, kana: kana, latin: latin);
}

bool _isHan(int rune) =>
    (rune >= 0x3400 && rune <= 0x4DBF) ||
    (rune >= 0x4E00 && rune <= 0x9FFF) ||
    (rune >= 0xF900 && rune <= 0xFAFF);

bool _isKana(int rune) =>
    (rune >= 0x3040 && rune <= 0x30FF) ||
    (rune >= 0x31F0 && rune <= 0x31FF) ||
    (rune >= 0xFF66 && rune <= 0xFF9F);

bool _isLatin(int rune) =>
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0x61 && rune <= 0x7A) ||
    (rune >= 0x00C0 && rune <= 0x024F);
