/// Inline rich-text tags used only for display formatting.
///
/// The post-processing model may insert these tags but must never change the
/// base text. [stripRichTextTags] is the single source used by the diff guard
/// and by the renderer's tests.
final RegExp richTextTagPattern = RegExp(
  r'\[(RUBY=[^\]]*|/RUBY|BOLD|/BOLD|UNDERLINE|/UNDERLINE)\]',
  caseSensitive: false,
);

/// A reading gloss emitted by the result-generation model. The rich-text
/// formatter may delete the whole block when it adds an equivalent RUBY span.
final RegExp yomiBlockPattern = RegExp(
  r'\[YOMI\]([\s\S]*?)\[/YOMI\]',
  caseSensitive: false,
);

final RegExp yomiTagPattern = RegExp(r'\[/?YOMI\]', caseSensitive: false);

final RegExp _yomiOpenClosePattern = RegExp(
  r'\[(/?YOMI)\]',
  caseSensitive: false,
);

final RegExp _rubyBlockPattern = RegExp(
  r'\[RUBY=([^\]]*)\]([\s\S]*?)\[/RUBY\]',
  caseSensitive: false,
);

/// RUBY pair plus an optional trailing reading annotation. Brackets are the
/// current display form; parentheses are kept only for old data.
final RegExp _rubyWithTrailingAnnotationPattern = RegExp(
  r'\[RUBY=([^\]]*)\]([\s\S]*?)\[/RUBY\]([【（(][^【】（）()\r\n]*[】）)])?',
  caseSensitive: false,
);

final RegExp _trailingBracketPattern = RegExp(r'【([^【】\r\n]*)】$');
final RegExp _trailingParenPattern = RegExp(r'[（(]([^（）()\r\n]*)[）)]$');
final RegExp _leadingBracketPattern = RegExp(r'^【([^【】\r\n]*)】');
final RegExp _leadingParenPattern = RegExp(r'^[（(]([^（）()\r\n]*)[）)]');

/// One display segment of a minimal ruby annotation. A null [reading] is plain
/// base text; a non-null reading is a ruby span over [base].
typedef MinimalRubySegment = ({String base, String? reading});

bool _isKanaCodePoint(int rune) {
  return (rune >= 0x3040 && rune <= 0x309F) ||
      (rune >= 0x30A0 && rune <= 0x30FF) ||
      rune == 0x30FC ||
      (rune >= 0x31F0 && rune <= 0x31FF) ||
      (rune >= 0xFF66 && rune <= 0xFF9F);
}

/// Splits a whole-word ruby into the minimal unknown part plus plain kana.
///
/// Japanese okurigana is already known from the base text, so annotating
/// `悩んでも` as `なやんでも` repeats information. The minimal rule annotates
/// only `悩（なや）` and leaves `んでも` plain. Prefix/suffix kana are trimmed
/// first; internal kana anchors (for example the `し` in `申し込み`) are found
/// with an LCS on equal kana code points, producing `申（もう）し込（こ）み`.
/// If the two strings cannot be aligned, the original whole-word pair is
/// returned and the caller keeps the existing ruby.
List<MinimalRubySegment> minimalRubySegments(String base, String reading) {
  final baseRunes = base.runes.toList(growable: false);
  final readingRunes = reading.runes.toList(growable: false);
  final full = <MinimalRubySegment>[(base: base, reading: reading)];
  if (base.isEmpty || reading.isEmpty || base == reading) {
    return full;
  }

  final baseLength = baseRunes.length;
  final readingLength = readingRunes.length;
  var prefix = 0;
  while (prefix < baseLength &&
      prefix < readingLength &&
      baseRunes[prefix] == readingRunes[prefix] &&
      _isKanaCodePoint(baseRunes[prefix])) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < baseLength - prefix &&
      suffix < readingLength - prefix &&
      baseRunes[baseLength - 1 - suffix] ==
          readingRunes[readingLength - 1 - suffix] &&
      _isKanaCodePoint(baseRunes[baseLength - 1 - suffix])) {
    suffix++;
  }

  final baseMiddle = baseRunes.sublist(prefix, baseLength - suffix);
  final readingMiddle = readingRunes.sublist(prefix, readingLength - suffix);
  if (baseMiddle.isEmpty || readingMiddle.isEmpty) return full;

  // LCS anchors: only equal kana may stay plain. Kanji/Latin base characters
  // are always part of a ruby segment even when the reading happens to contain
  // the same character.
  final n = baseMiddle.length;
  final m = readingMiddle.length;
  final anchors = <(int, int)>[];
  if (n > 0 && m > 0) {
    final dp = List<List<int>>.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
      growable: false,
    );
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        if (baseMiddle[i] == readingMiddle[j] &&
            _isKanaCodePoint(baseMiddle[i])) {
          dp[i][j] = dp[i + 1][j + 1] + 1;
        } else {
          dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
        }
      }
    }
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (baseMiddle[i] == readingMiddle[j] &&
          _isKanaCodePoint(baseMiddle[i])) {
        anchors.add((i, j));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }
  }

  String baseRange(List<int> runes, int start, int end) =>
      String.fromCharCodes(runes.sublist(start, end));

  final segments = <MinimalRubySegment>[];
  if (prefix > 0) {
    segments.add((base: baseRange(baseRunes, 0, prefix), reading: null));
  }
  var baseCursor = 0;
  var readingCursor = 0;
  for (final anchor in anchors) {
    final basePart = baseRange(baseMiddle, baseCursor, anchor.$1);
    final readingPart = baseRange(readingMiddle, readingCursor, anchor.$2);
    if (basePart.isEmpty || readingPart.isEmpty) {
      // Extra kana on one side cannot be represented as one ruby span; fall
      // back to the original pair instead of dropping part of the reading.
      return full;
    }
    segments.add((base: basePart, reading: readingPart));
    segments.add((
      base: String.fromCharCode(baseMiddle[anchor.$1]),
      reading: null,
    ));
    baseCursor = anchor.$1 + 1;
    readingCursor = anchor.$2 + 1;
  }
  final tailBase = baseRange(baseMiddle, baseCursor, n);
  final tailReading = baseRange(readingMiddle, readingCursor, m);
  if (tailBase.isNotEmpty || tailReading.isNotEmpty) {
    if (tailBase.isEmpty || tailReading.isEmpty) return full;
    segments.add((base: tailBase, reading: tailReading));
  }
  if (suffix > 0) {
    segments.add((
      base: baseRange(baseRunes, baseLength - suffix, baseLength),
      reading: null,
    ));
  }
  return segments.isEmpty ? full : segments;
}

/// Converts a full-word base/reading pair to the minimal tagged display form.
String minimalRubyText(String base, String reading) {
  return minimalRubySegments(base, reading)
      .map(
        (segment) => segment.reading == null
            ? segment.base
            : '[RUBY=${segment.reading}]${segment.base}[/RUBY]',
      )
      .join();
}

/// Full-width and half-width punctuation that may wrap or trail a reading
/// annotation. It is removed before comparing YOMI contents and before a
/// RUBY reading is shown/copied.
final RegExp _readingPunctuationPattern = RegExp(
  r'''[!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~、。，．・：；！？「」『』（）［］｛｝【】〈〉《》〔〕〜～…—–―／＼]''',
);

/// Reading annotations are intentionally language-agnostic and do not
/// enumerate scripts. Brackets, control characters and line breaks are not
/// permitted.
final RegExp _readingPattern = RegExp(r'^[^\[\]\r\n\x00-\x1F]+$');

/// Reading annotations use corner brackets. Both `reading【surface】` (the
/// display/export form, e.g. `すき【好き】`) and the conventional
/// `surface【reading】` (e.g. `好き【すき】`) are accepted. Parentheses are
/// ordinary explanations and are never treated as readings.
final RegExp _bracketReadingPattern = RegExp(
  r'(^|[\s、。，．！？：；「」『』（）\[\]【】])'
  r'([^\s、。，．！？：；「」『』（）【】\[\]]{1,16})'
  r'【([^【】\[\]\r\n]{1,32})】',
);

/// A bracket reading whose word is inside a BOLD/UNDERLINE span that closes
/// before the bracket, e.g. `[BOLD]すき[/BOLD]【好き】`. The RUBY must be moved
/// inside the still-open emphasis span so the reading inherits bold.
final RegExp _baseThenClosingTagsThenBracketPattern = RegExp(
  r'([^\s【】\[\]]{1,16})'
  r'((?:\[/(?:BOLD|UNDERLINE)\])+)'
  r'【([^【】\[\]\r\n]{1,32})】',
  caseSensitive: false,
);

/// A RUBY pair followed by a full bracket annotation, optionally separated by
/// closing emphasis tags: `[RUBY=すき]好き[/RUBY]すき【好き】`.
final RegExp _rubyThenClosingTagsThenBracketPattern = RegExp(
  r'\[RUBY=([^\]]*)\]([\s\S]*?)\[/RUBY\]'
  r'((?:\[/(?:BOLD|UNDERLINE)\])*)'
  r'([^\s【】\[\]]{1,16})【([^【】\[\]\r\n]{1,32})】',
  caseSensitive: false,
);

/// A RUBY pair followed by a bare bracket, e.g.
/// `[RUBY=すき]好き[/RUBY]【すき】`.
final RegExp _rubyThenClosingTagsThenBareBracketPattern = RegExp(
  r'\[RUBY=([^\]]*)\]([\s\S]*?)\[/RUBY\]'
  r'((?:\[/(?:BOLD|UNDERLINE)\])*)'
  r'【([^【】\[\]\r\n]{1,32})】',
  caseSensitive: false,
);

/// A RUBY pair followed by an old-style parenthetical duplicate. Parentheses
/// are no longer converted, but an exact duplicate after RUBY is noise.
final RegExp _rubyThenClosingTagsThenParenPattern = RegExp(
  r'\[RUBY=([^\]]*)\]([\s\S]*?)\[/RUBY\]'
  r'((?:\[/(?:BOLD|UNDERLINE)\])*)'
  r'[（(]([^（）()\r\n]*)[）)]',
  caseSensitive: false,
);

final RegExp _kanaOnlyPattern = RegExp(r'^[぀-ヿー・]+$');
final RegExp _cjkPattern = RegExp(r'[㐀-䶿一-鿿豈-﫿々〆ヶ]');
final RegExp _latinOnlyPattern = RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿĀ-ž]+$');

/// Resolves a bracket annotation to the actual surface and reading. Kana/Latin
/// is treated as the reading side; the other side is the surface. This accepts
/// both `すき【好き】` and `好き【すき】`. Ambiguous all-kanji or all-Latin
/// brackets are left untouched to avoid false positives.
({String surface, String reading})? _resolveBracketReading(
  String outside,
  String inside,
) {
  final o = outside.trim();
  final i = inside.trim();
  if (o.isEmpty || i.isEmpty) return null;
  final or = cleanReading(o);
  final ir = cleanReading(i);
  if (or.isEmpty || ir.isEmpty) return null;
  if (or == ir) return (surface: o, reading: or);
  final oKana = _kanaOnlyPattern.hasMatch(or);
  final iKana = _kanaOnlyPattern.hasMatch(ir);
  final oLatin = _latinOnlyPattern.hasMatch(or);
  final iLatin = _latinOnlyPattern.hasMatch(ir);
  final oCjk = _cjkPattern.hasMatch(or);
  final iCjk = _cjkPattern.hasMatch(ir);
  final oReading = oKana || (oLatin && iCjk);
  final iReading = iKana || (iLatin && oCjk);
  if (oReading && !iReading) return (surface: i, reading: or);
  if (iReading && !oReading) return (surface: o, reading: ir);
  if (oReading && iReading) {
    // Both sides are kana: the outside is the user's reading-first form.
    if (oKana && iKana) return (surface: i, reading: or);
    return null;
  }
  return null;
}

/// The result model's `word[YOMI]reading[/YOMI]` annotation. The visible result
/// must carry RUBY from the first frame, so this is converted locally before
/// the optional display-formatting model runs.
final RegExp _yomiToRubyPattern = RegExp(
  r'([぀-ヿ㐀-䶿一-鿿豈-﫿々〆ヶーA-Za-zÀ-ÖØ-öø-ÿĀ-ž]+)'
  r'\[YOMI\]([\s\S]*?)\[\/YOMI\]',
  caseSensitive: false,
);

/// Existing display spans that must not be rewritten by the parenthetical
/// converter. RUBY bases and YOMI contents may contain text that looks like a
/// word-plus-reading pair.
final RegExp _protectedDisplaySpanPattern = RegExp(
  r'\[RUBY=[^\]]*\][\s\S]*?\[/RUBY\]|\[YOMI\][\s\S]*?\[/YOMI\]',
  caseSensitive: false,
);

String cleanReading(String reading) =>
    reading.replaceAll(_readingPunctuationPattern, '').trim();

/// Converts the result model's `word[YOMI]reading[/YOMI]` annotations to
/// RUBY. A reading identical to its base is dropped. This is a display-only
/// helper; the base characters are never changed.
String yomiToRuby(String text) {
  return text.replaceAllMapped(_yomiToRubyPattern, (match) {
    final base = match.group(1) ?? '';
    final reading = cleanReading(match.group(2) ?? '');
    if (base.isEmpty || reading.isEmpty || reading == base) return base;
    return '[RUBY=$reading]$base[/RUBY]';
  });
}

/// The local display conversion used before the optional formatting model
/// runs: YOMI and bracket readings become RUBY. The result preview therefore
/// shows RUBY immediately instead of waiting for the network pass.
String localReadingsToRuby(String text) =>
    bracketReadingsToRuby(yomiToRuby(text));

/// Converts bracket reading annotations to RUBY without touching existing
/// RUBY/YOMI spans. A reading identical to its surface is dropped. This is a
/// display-only helper: the base characters are never changed.
///
/// The conversion is tag-aware. If the formatter closed BOLD/UNDERLINE before
/// the reading (`[BOLD]すき[/BOLD]【好き】`), the reading is moved inside the
/// emphasis span as RUBY; a duplicate annotation after RUBY is removed.
String bracketReadingsToRuby(String text) {
  final normalized = _dropDuplicateBracketAfterRuby(
    _dropDuplicateParenAfterRuby(text),
  );
  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in _protectedDisplaySpanPattern.allMatches(normalized)) {
    buffer.write(
      _convertBracketReadings(normalized.substring(cursor, match.start)),
    );
    buffer.write(match.group(0));
    cursor = match.end;
  }
  buffer.write(_convertBracketReadings(normalized.substring(cursor)));
  return buffer.toString();
}

String _convertBracketReadings(String text) {
  final moved = text.replaceAllMapped(_baseThenClosingTagsThenBracketPattern, (
    match,
  ) {
    final outside = match.group(1) ?? '';
    final closings = match.group(2) ?? '';
    final inside = match.group(3) ?? '';
    final resolved = _resolveBracketReading(outside, inside);
    if (resolved == null) return match.group(0) ?? '';
    if (cleanReading(resolved.surface) == resolved.reading) {
      return '${resolved.surface}$closings';
    }
    return '[RUBY=${resolved.reading}]${resolved.surface}[/RUBY]$closings';
  });
  return moved.replaceAllMapped(_bracketReadingPattern, (match) {
    final prefix = match.group(1) ?? '';
    final outside = match.group(2) ?? '';
    final inside = match.group(3) ?? '';
    final resolved = _resolveBracketReading(outside, inside);
    if (resolved == null) return match.group(0) ?? '';
    if (cleanReading(resolved.surface) == resolved.reading) {
      return '$prefix${resolved.surface}';
    }
    return '$prefix[RUBY=${resolved.reading}]${resolved.surface}[/RUBY]';
  });
}

/// Drops a bracket annotation that duplicates a preceding RUBY pair, even when
/// closing emphasis tags sit between them.
String _dropDuplicateBracketAfterRuby(String text) {
  var result = text.replaceAllMapped(_rubyThenClosingTagsThenBracketPattern, (
    match,
  ) {
    final rubyReading = cleanReading(match.group(1) ?? '');
    final rubyBase = match.group(2) ?? '';
    final closings = match.group(3) ?? '';
    final outside = match.group(4) ?? '';
    final inside = match.group(5) ?? '';
    final resolved = _resolveBracketReading(outside, inside);
    if (resolved == null) return match.group(0) ?? '';
    final matchesReading = cleanReading(resolved.reading) == rubyReading;
    final matchesBase =
        cleanReading(resolved.surface) == cleanReading(rubyBase);
    if (matchesReading || matchesBase) {
      return '[RUBY=$rubyReading]$rubyBase[/RUBY]$closings';
    }
    return match.group(0) ?? '';
  });
  result = result.replaceAllMapped(_rubyThenClosingTagsThenBareBracketPattern, (
    match,
  ) {
    final rubyReading = cleanReading(match.group(1) ?? '');
    final rubyBase = match.group(2) ?? '';
    final closings = match.group(3) ?? '';
    final bracket = cleanReading(match.group(4) ?? '');
    if (bracket.isNotEmpty &&
        (bracket == rubyReading || bracket == cleanReading(rubyBase))) {
      return '[RUBY=$rubyReading]$rubyBase[/RUBY]$closings';
    }
    return match.group(0) ?? '';
  });
  return result;
}

/// Drops an old-style parenthetical duplicate that immediately follows a RUBY
/// pair. Standalone parentheses are ordinary explanations and are not touched.
String _dropDuplicateParenAfterRuby(String text) {
  return text.replaceAllMapped(_rubyThenClosingTagsThenParenPattern, (match) {
    final reading = cleanReading(match.group(1) ?? '');
    final base = match.group(2) ?? '';
    final closings = match.group(3) ?? '';
    final trailing = cleanReading(match.group(4) ?? '');
    if (reading.isEmpty || trailing.isEmpty || reading != trailing) {
      return match.group(0) ?? '';
    }
    return '[RUBY=$reading]$base[/RUBY]$closings';
  });
}

/// Removes a bracket reading at the end of [base] when it is exactly the
/// reading already supplied by the RUBY tag. This prevents
/// `[RUBY=いま]今【いま】[/RUBY]` from rendering as `今【いま】【いま】`.
/// Old parenthetical duplicates are also removed.
String rubyDisplayBase(String base, String reading) {
  final cleanedReading = cleanReading(reading);
  if (cleanedReading.isEmpty) return base;
  final bracket = _trailingBracketPattern.firstMatch(base);
  if (bracket != null &&
      cleanReading(bracket.group(1) ?? '') == cleanedReading) {
    return base.substring(0, bracket.start);
  }
  final paren = _trailingParenPattern.firstMatch(base);
  if (paren != null && cleanReading(paren.group(1) ?? '') == cleanedReading) {
    return base.substring(0, paren.start);
  }
  return base;
}

/// Returns the offset after a bracket reading that immediately follows a RUBY
/// span and duplicates its reading, for example
/// `[RUBY=いま]今[/RUBY]【いま】`. Old parenthetical duplicates are also
/// skipped. The duplicate annotation must not be shown or copied twice.
int skipDuplicateRubyReading(String text, int offset, String reading) {
  final cleanedReading = cleanReading(reading);
  if (cleanedReading.isEmpty || offset >= text.length) return offset;
  final rest = text.substring(offset);
  final bracket = _leadingBracketPattern.firstMatch(rest);
  if (bracket != null &&
      cleanReading(bracket.group(1) ?? '') == cleanedReading) {
    return offset + bracket.end;
  }
  final paren = _leadingParenPattern.firstMatch(rest);
  if (paren != null && cleanReading(paren.group(1) ?? '') == cleanedReading) {
    return offset + paren.end;
  }
  return offset;
}

String stripRichTextTags(String text) =>
    text.replaceAll(richTextTagPattern, '');

final RegExp _rubyThenYomiPattern = RegExp(
  r'\[RUBY=([^\]]*)\]([\s\S]*?)\[/RUBY\]\[YOMI\]([\s\S]*?)\[/YOMI\]',
  caseSensitive: false,
);

/// Removes a YOMI block immediately after a RUBY pair when both carry the
/// same reading. The formatter is told to delete the YOMI itself, but a
/// retained duplicate must never render/export as RUBY plus a bracket reading.
String _dropDuplicateYomiAfterRuby(String text) {
  return text.replaceAllMapped(_rubyThenYomiPattern, (match) {
    final reading = cleanReading(match.group(1) ?? '');
    final yomi = cleanReading(match.group(3) ?? '');
    if (reading.isNotEmpty && reading == yomi) {
      return '[RUBY=${match.group(1)}]${match.group(2)}[/RUBY]';
    }
    return match.group(0) ?? '';
  });
}

final RegExp _wordYomiPattern = RegExp(
  r'([぀-ヿ㐀-䶿一-鿿豈-﫿々〆ヶーA-Za-zÀ-ÖØ-öø-ÿĀ-ž]+)'
  r'\[YOMI\]([\s\S]*?)\[/YOMI\]',
  caseSensitive: false,
);

/// Converts YOMI annotations to the bracket display form used by Markdown and
/// plain fallbacks: `reading【surface】` (for example `すき【好き】`). A YOMI
/// block that duplicates the reading of an immediately preceding RUBY pair is
/// dropped. A bare YOMI without a surface keeps its cleaned reading.
String stripYomiTags(String text) {
  var result = _dropDuplicateYomiAfterRuby(text);
  result = result.replaceAllMapped(_wordYomiPattern, (match) {
    final base = match.group(1) ?? '';
    final reading = cleanReading(match.group(2) ?? '');
    if (reading.isEmpty || reading == cleanReading(base)) return base;
    return '$reading【$base】';
  });
  result = result.replaceAllMapped(yomiBlockPattern, (match) {
    return cleanReading(match.group(1) ?? '');
  });
  return result.replaceAll(yomiTagPattern, '');
}

/// Removes whole YOMI blocks (tags + reading). Used only by the diff guard so
/// the formatter is allowed to replace a gloss with RUBY.
String stripYomiBlocks(String text) => text.replaceAll(yomiBlockPattern, '');

List<String> yomiContents(String text) => <String>[
  for (final match in yomiBlockPattern.allMatches(text)) match.group(1) ?? '',
];

bool isWellFormedYomi(String text) {
  var depth = 0;
  for (final match in _yomiOpenClosePattern.allMatches(text)) {
    final closing = (match.group(1) ?? '').startsWith('/');
    if (closing) {
      if (depth == 0) return false;
      depth--;
    } else {
      if (depth > 0) return false;
      depth++;
    }
  }
  return depth == 0;
}

/// Removes a RUBY pair when its reading is identical to its base. Such a pair
/// adds no information and is the most common model-generated noise, e.g.
/// `[RUBY=reading]reading[/RUBY]`.
String stripRedundantRubyTags(String text) {
  return text.replaceAllMapped(_rubyBlockPattern, (match) {
    final reading = cleanReading(match.group(1) ?? '');
    final base = match.group(2) ?? '';
    if (reading.isNotEmpty && reading == base) return base;
    return match.group(0) ?? '';
  });
}

/// Rewrites every RUBY opening tag with a punctuation-cleaned reading. If
/// cleaning leaves no reading, or the reading equals the base, the pair is
/// removed and only the base remains.
String cleanRubyReadings(String text) {
  return text.replaceAllMapped(_rubyBlockPattern, (match) {
    final reading = cleanReading(match.group(1) ?? '');
    final base = match.group(2) ?? '';
    if (reading.isEmpty || reading == base) return base;
    return '[RUBY=$reading]$base[/RUBY]';
  });
}

/// Converts rich-text markup to a copyable plain string:
/// RUBY becomes `reading【base】`, BOLD/UNDERLINE tags disappear, and YOMI
/// wrappers are converted to the same bracket form.
String richTextToPlain(String text) {
  var plain = _dropDuplicateYomiAfterRuby(text);
  plain = _dropDuplicateBracketAfterRuby(plain);
  plain = plain.replaceAllMapped(_rubyWithTrailingAnnotationPattern, (match) {
    final reading = cleanReading(match.group(1) ?? '');
    final base = match.group(2) ?? '';
    final trailing = match.group(3) ?? '';
    if (reading.isEmpty) return '$base$trailing';
    final displayBase = rubyDisplayBase(base, reading);
    if (displayBase.isEmpty) return '$base$trailing';
    final keepTrailing = _keepTrailingAnnotation(
      trailing,
      reading,
      displayBase,
    );
    if (reading == cleanReading(displayBase)) {
      return '$displayBase$keepTrailing';
    }
    return '$reading【$displayBase】$keepTrailing';
  });
  plain = plain.replaceAll(richTextTagPattern, '');
  return stripYomiTags(plain);
}

String _keepTrailingAnnotation(
  String trailing,
  String reading,
  String displayBase,
) {
  if (trailing.isEmpty) return '';
  final isBracket = trailing.startsWith('【') && trailing.endsWith('】');
  final isParen =
      (trailing.startsWith('（') && trailing.endsWith('）')) ||
      (trailing.startsWith('(') && trailing.endsWith(')'));
  if (!isBracket && !isParen) return trailing;
  final content = cleanReading(trailing.substring(1, trailing.length - 1));
  if (content == reading || content == cleanReading(displayBase)) return '';
  return trailing;
}

/// True when every YOMI block kept in [candidate] also exists, unchanged and
/// at the same base position, in [source]. Deletion is allowed; creation,
/// rewriting and moving are not.
bool allowsYomiDeletion(String source, String candidate) {
  final original = _yomiBlocks(source);
  final kept = _yomiBlocks(candidate);
  var index = 0;
  for (final block in kept) {
    var found = false;
    while (index < original.length) {
      final sourceBlock = original[index++];
      if (sourceBlock.content == block.content &&
          sourceBlock.before == block.before) {
        found = true;
        break;
      }
    }
    if (!found) return false;
  }
  return true;
}

List<({String content, String before})> _yomiBlocks(String text) {
  return <({String content, String before})>[
    for (final match in yomiBlockPattern.allMatches(text))
      (
        // Full-/half-width punctuation in the reading is ignored for the
        // YOMI comparison; it is not part of the annotated source text.
        content: cleanReading(match.group(1) ?? ''),
        // Compare the base text before the annotation, ignoring formatting
        // tags. This prevents a kept annotation from being moved onto a
        // different surface while still allowing whole-block deletion.
        before: stripRichTextTags(
          stripYomiBlocks(text.substring(0, match.start)),
        ),
      ),
  ];
}

/// True when every tag is paired and properly nested, and every RUBY reading
/// is a safe pronunciation annotation. RUBY may be wrapped by BOLD/UNDERLINE;
/// style tags may not appear inside a RUBY base, and a tag may not nest inside
/// an identical tag.
bool isWellFormedRichText(String text) {
  final stack = <String>[];
  for (final match in richTextTagPattern.allMatches(text)) {
    final raw = match.group(1) ?? '';
    final lower = raw.toLowerCase();
    if (lower.startsWith('ruby=')) {
      if (stack.contains('ruby')) return false;
      final reading = raw.substring('ruby='.length).trim();
      if (reading.isEmpty || !_readingPattern.hasMatch(reading)) {
        return false;
      }
      final close = text.indexOf('[/RUBY]', match.end);
      if (close < 0) return false;
      final base = text.substring(match.end, close);
      if (base.isEmpty || base.contains('\n') || base.contains('\r')) {
        return false;
      }
      // The base is plain copied text; style/YOMI tags belong outside the pair.
      if (richTextTagPattern.hasMatch(base) || yomiTagPattern.hasMatch(base)) {
        return false;
      }
      stack.add('ruby');
      continue;
    }
    if (lower == '/ruby') {
      if (stack.isEmpty || stack.last != 'ruby') return false;
      stack.removeLast();
      continue;
    }
    if (lower == 'bold' || lower == 'underline') {
      if (stack.contains('ruby')) return false;
      if (stack.contains(lower)) return false;
      stack.add(lower);
      continue;
    }
    if (lower == '/bold' || lower == '/underline') {
      final open = lower.substring(1);
      if (stack.isEmpty || stack.last != open) return false;
      stack.removeLast();
    }
  }
  return stack.isEmpty;
}
