/// MDict lookup normalization.
///
/// Generates a de-duplicated candidate list: the original token candidates
/// first, then NFKC, case, width and hiragana/katakana variants, and finally a
/// stripped form without whitespace/punctuation. Trying several candidates is
/// cheap (binary search) and avoids a dependency on one dictionary's exact
/// key policy.
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'kana.dart';

final RegExp _stripPattern = RegExp(
  r'''[\s!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~、。，．・：；！？「」『』（）［］｛｝【】〈〉《》〔〕〜～…—–―]''',
);

String normalizeLookupText(String input) => unorm.nfkc(input).trim();

/// Removes whitespace and punctuation for MDict stripkey-style lookup.
String stripLookupKey(String input) {
  return normalizeLookupText(input).replaceAll(_stripPattern, '').toLowerCase();
}

String _lowerAscii(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x41 && rune <= 0x5A) {
      buffer.writeCharCode(rune + 0x20);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Expands raw candidates into lookup variants, preserving priority order.
List<String> lookupCandidatesFor(Iterable<String> rawValues) {
  final seen = <String>{};
  final candidates = <String>[];

  void add(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) return;
    candidates.add(trimmed);
  }

  void addFamily(String value) {
    add(value);
    final normalized = normalizeLookupText(value);
    add(normalized);

    for (final variant in {value, normalized}) {
      add(katakanaToHiragana(variant));
      add(hiraganaToKatakana(variant));
      add(_lowerAscii(variant));
      final stripped = stripLookupKey(variant);
      add(stripped);
      add(katakanaToHiragana(stripped));
      add(hiraganaToKatakana(stripped));
    }
  }

  for (final raw in rawValues) {
    addFamily(raw);
  }
  return candidates;
}
